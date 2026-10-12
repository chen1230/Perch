using System.Runtime.InteropServices;
using System.Diagnostics;
using Avalonia;
using SkiaSharp;

namespace Perch;

static class Win
{
    public const int VkShift = 0x10;
    public const int VkControl = 0x11;
    public const int VkMenu = 0x12;
    public const int VkT = 0x54;
    public const int VkV = 0x56;

    public readonly record struct ClipRead(bool HasFiles, bool Excluded, string? Text, byte[]? Png);

    public static uint Sequence() => OperatingSystem.IsWindows() ? GetClipboardSequenceNumber() : 0;

    public static bool Down(int vk) =>
        OperatingSystem.IsWindows() && (GetAsyncKeyState(vk) & 0x8000) != 0;

    public static bool TryCursor(out PixelPoint point)
    {
        point = default;
        if (!OperatingSystem.IsWindows() || !GetCursorPos(out var p))
            return false;
        point = new PixelPoint(p.X, p.Y);
        return true;
    }

    public static IntPtr Foreground() =>
        OperatingSystem.IsWindows() ? GetForegroundWindow() : IntPtr.Zero;

    public static bool TryRead(out ClipRead read)
    {
        read = default;
        if (!OperatingSystem.IsWindows() || !OpenClipboard(IntPtr.Zero))
            return false;
        try
        {
            var exclude = RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing");
            var pngFormat = RegisterClipboardFormat("PNG");
            var excluded = IsClipboardFormatAvailable(exclude);
            var files = IsClipboardFormatAvailable(15);
            string? text = files || excluded ? null : ReadText();
            byte[]? png = null;
            if (!files && !excluded && string.IsNullOrWhiteSpace(text))
            {
                var rawPng = ReadBytes(pngFormat);
                if (rawPng is { Length: > 8 })
                    png = rawPng;
                else
                {
                    var dib = ReadBytes(8);
                    if (dib != null)
                        png = DibToPng(dib);
                }
            }

            read = new ClipRead(files, excluded, text, png);
            return true;
        }
        finally
        {
            CloseClipboard();
        }
    }

    public static bool SetText(string text, IntPtr owner)
    {
        if (!OperatingSystem.IsWindows())
            return false;
        var bytes = System.Text.Encoding.Unicode.GetBytes(text + "\0");
        return Set(13, bytes, owner);
    }

    public static bool SetImageFile(string path, IntPtr owner)
    {
        if (!OperatingSystem.IsWindows() || !File.Exists(path))
            return false;
        using var bitmap = SKBitmap.Decode(path);
        if (bitmap == null)
            return false;
        return Set(8, BitmapToDib(bitmap), owner);
    }

    public static string? SourceName()
    {
        if (!OperatingSystem.IsWindows()) return null;
        try
        {
            GetWindowThreadProcessId(GetForegroundWindow(), out var pid);
            using var process = Process.GetProcessById((int)pid);
            return process.MainModule?.FileVersionInfo.ProductName ?? process.ProcessName;
        }
        catch { return null; }
    }
    public static bool CanPasteInto(IntPtr hwnd) => OperatingSystem.IsWindows() && hwnd != IntPtr.Zero && IsWindow(hwnd);
    public static void RestoreFocus(IntPtr hwnd) { if (CanPasteInto(hwnd)) Focus(hwnd); }

    public static void PasteInto(IntPtr hwnd)
    {
        if (!CanPasteInto(hwnd)) return;
        Focus(hwnd);
        if (GetForegroundWindow() != hwnd) return;
        var inputs = new[]
        {
            Key(VkControl, false),
            Key(VkV, false),
            Key(VkV, true),
            Key(VkControl, true),
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    static void Focus(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero)
            return;
        var foreground = GetForegroundWindow();
        var foregroundThread = GetWindowThreadProcessId(foreground, out _);
        var thisThread = GetCurrentThreadId();
        AttachThreadInput(thisThread, foregroundThread, true);
        SetForegroundWindow(hwnd);
        AttachThreadInput(thisThread, foregroundThread, false);
    }

    static bool Set(uint format, byte[] bytes, IntPtr owner)
    {
        if (owner == IntPtr.Zero || !OpenClipboard(owner))
            return false;
        try
        {
            if (!EmptyClipboard())
                return false;
            var handle = GlobalAlloc(0x0002, (nuint)bytes.Length);
            if (handle == IntPtr.Zero)
                return false;
            var pointer = GlobalLock(handle);
            try
            {
                Marshal.Copy(bytes, 0, pointer, bytes.Length);
            }
            finally
            {
                GlobalUnlock(handle);
            }

            if (SetClipboardData(format, handle) == IntPtr.Zero)
            {
                GlobalFree(handle);
                return false;
            }

            return true;
        }
        finally
        {
            CloseClipboard();
        }
    }

    static string? ReadText()
    {
        var handle = GetClipboardData(13);
        if (handle == IntPtr.Zero)
            return null;
        var pointer = GlobalLock(handle);
        if (pointer == IntPtr.Zero)
            return null;
        try
        {
            return Marshal.PtrToStringUni(pointer);
        }
        finally
        {
            GlobalUnlock(handle);
        }
    }

    static byte[]? ReadBytes(uint format)
    {
        var handle = GetClipboardData(format);
        if (handle == IntPtr.Zero)
            return null;
        var pointer = GlobalLock(handle);
        if (pointer == IntPtr.Zero)
            return null;
        try
        {
            var size = (int)GlobalSize(handle);
            if (size <= 0 || size > 80_000_000)
                return null;
            var bytes = new byte[size];
            Marshal.Copy(pointer, bytes, 0, size);
            return bytes;
        }
        finally
        {
            GlobalUnlock(handle);
        }
    }

    static byte[] BitmapToDib(SKBitmap source)
    {
        var info = new SKImageInfo(source.Width, source.Height, SKColorType.Bgra8888, SKAlphaType.Unpremul);
        using var bitmap = new SKBitmap(info);
        using (var canvas = new SKCanvas(bitmap))
            canvas.DrawBitmap(source, 0, 0);

        var width = bitmap.Width;
        var height = bitmap.Height;
        var stride = width * 4;
        var data = new byte[40 + stride * height];
        WriteI32(data, 0, 40);
        WriteI32(data, 4, width);
        WriteI32(data, 8, height);
        WriteI16(data, 12, 1);
        WriteI16(data, 14, 32);
        for (var y = 0; y < height; y++)
        {
            var sourceY = height - 1 - y;
            for (var x = 0; x < width; x++)
            {
                var color = bitmap.GetPixel(x, sourceY);
                var index = 40 + y * stride + x * 4;
                data[index] = color.Blue;
                data[index + 1] = color.Green;
                data[index + 2] = color.Red;
                data[index + 3] = color.Alpha;
            }
        }

        return data;
    }

    static byte[]? DibToPng(byte[] dib)
    {
        if (dib.Length < 40)
            return null;
        var header = ReadI32(dib, 0);
        if (header < 40 || header > dib.Length)
            return null;
        var width = ReadI32(dib, 4);
        var height = ReadI32(dib, 8);
        var planes = ReadI16(dib, 12);
        var bit = ReadI16(dib, 14);
        var compression = ReadI32(dib, 16);
        if (planes != 1 || width is <= 0 or > 16000 || bit is not (24 or 32) || compression != 0)
            return null;
        var topDown = height < 0;
        height = Math.Abs(height);
        if (height is <= 0 or > 16000)
            return null;
        var stride = ((width * bit + 31) / 32) * 4;
        if (header + (long)stride * height > dib.Length)
            return null;

        var info = new SKImageInfo(width, height, SKColorType.Bgra8888, SKAlphaType.Unpremul);
        using var bitmap = new SKBitmap(info);
        var pixel = bit / 8;
        for (var y = 0; y < height; y++)
        {
            var sourceY = topDown ? y : height - 1 - y;
            var row = header + sourceY * stride;
            for (var x = 0; x < width; x++)
            {
                var index = row + x * pixel;
                var blue = dib[index];
                var green = dib[index + 1];
                var red = dib[index + 2];
                var alpha = bit == 32 ? dib[index + 3] : (byte)255;
                bitmap.SetPixel(x, y, new SKColor(red, green, blue, alpha));
            }
        }

        using var image = SKImage.FromBitmap(bitmap);
        using var encoded = image.Encode(SKEncodedImageFormat.Png, 90);
        return encoded?.ToArray();
    }

    static INPUT Key(ushort vk, bool up) => new()
    {
        type = 1,
        U = new INPUTUNION
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                dwFlags = up ? 0x0002u : 0,
            },
        },
    };

    static int ReadI32(byte[] data, int offset) => BitConverter.ToInt32(data, offset);
    static short ReadI16(byte[] data, int offset) => BitConverter.ToInt16(data, offset);
    static void WriteI32(byte[] data, int offset, int value) => BitConverter.GetBytes(value).CopyTo(data, offset);
    static void WriteI16(byte[] data, int offset, short value) => BitConverter.GetBytes(value).CopyTo(data, offset);

    [StructLayout(LayoutKind.Sequential)]
    struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT
    {
        public int type;
        public INPUTUNION U;
    }

    [StructLayout(LayoutKind.Explicit)]
    struct INPUTUNION
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public nuint dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public nuint dwExtraInfo;
    }

    [DllImport("user32.dll")] static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("user32.dll", SetLastError = true)] static extern bool OpenClipboard(IntPtr hWndNewOwner);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll")] static extern bool EmptyClipboard();
    [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint format);
    [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint format, IntPtr memory);
    [DllImport("user32.dll")] static extern bool IsClipboardFormatAvailable(uint format);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint flags, nuint bytes);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr memory);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr memory);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr memory);
    [DllImport("kernel32.dll")] static extern nuint GlobalSize(IntPtr memory);
}
