using System.Diagnostics;
using System.IO.Compression;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Perch.Setup;

static class Program
{
    const string Version = "1.1.0";

    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            if (args.Any(arg => arg.Equals("--extract-test", StringComparison.OrdinalIgnoreCase)))
                return ExtractTest();
            if (!OperatingSystem.IsWindows())
            {
                Say("这个安装包要在 Windows 上运行。");
                return 1;
            }

            if (args.Any(arg => arg.Equals("/uninstall", StringComparison.OrdinalIgnoreCase)))
                return Uninstall();
            return Install();
        }
        catch (Exception ex)
        {
            Say("没有完成。\n\n" + ex.Message);
            return 1;
        }
    }

    static int Install()
    {
        var dest = InstallDir();
        if (Ask($"将把 Perch {Version} 安装到\n{dest}\n\n不需要管理员权限。", yesNo: false) != 1)
            return 0;
        while (Process.GetProcessesByName("Perch").Length > 0)
        {
            if (Ask("Perch 正在运行。先退出它，再继续安装。", retry: true) != 4)
                return 0;
        }

        if (Directory.Exists(dest))
            Directory.Delete(dest, true);
        Directory.CreateDirectory(dest);
        ExtractPayload(dest);

        var exe = Path.Combine(dest, "Perch.exe");
        if (!File.Exists(exe))
            throw new InvalidOperationException("安装包里没有 Perch.exe。");

        var uninstall = Path.Combine(dest, "Uninstall.exe");
        File.Copy(Environment.ProcessPath!, uninstall, true);
        CreateShortcut(ShortcutPath(), exe, dest);
        WriteUninstallKey(dest, uninstall);

        if (Ask("安装完成。现在打开 Perch？", yesNo: true) == 6)
        {
            Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = dest, UseShellExecute = true });
        }

        return 0;
    }

    static int Uninstall()
    {
        if (Ask("卸载 Perch？复制过的文字和截图会留在本机。", yesNo: true) != 6)
            return 0;
        while (Process.GetProcessesByName("Perch").Length > 0)
        {
            if (Ask("Perch 正在运行。先退出它，再继续卸载。", retry: true) != 4)
                return 0;
        }

        var dest = InstallDir();
        TryDelete(ShortcutPath());
        try
        {
            Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\Perch", false);
            Registry.CurrentUser.DeleteSubKeyTree(@"Software\Perch", false);
        }
        catch
        {
            // 注册表项不在时，继续删安装目录。
        }

        Say("Perch 已卸载。");
        var script = Path.Combine(Path.GetTempPath(), "perch-uninstall.cmd");
        File.WriteAllText(script, $"""
            @echo off
            ping 127.0.0.1 -n 3 > nul
            rmdir /s /q "{dest}"
            del "%~f0"
            """);
        Process.Start(new ProcessStartInfo("cmd.exe", $"/c \"{script}\"")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
        });
        return 0;
    }

    static int ExtractTest()
    {
        var dest = Path.Combine(Path.GetTempPath(), "perch-setup-test-" + Guid.NewGuid().ToString("N"));
        ExtractPayload(dest);
        var exe = Path.Combine(dest, "Perch.exe");
        var runtime = Path.Combine(dest, "coreclr.dll");
        var ok = File.Exists(exe) && File.Exists(runtime);
        Directory.Delete(dest, true);
        Console.WriteLine(ok ? "extract-ok" : "extract-missing");
        return ok ? 0 : 1;
    }

    static void ExtractPayload(string dest)
    {
        var stream = typeof(Program).Assembly.GetManifestResourceStream("payload.zip")
            ?? throw new InvalidOperationException("安装包内容缺失。");
        using (stream)
        {
            using var zip = new ZipArchive(stream, ZipArchiveMode.Read);
            foreach (var entry in zip.Entries)
            {
                if (string.IsNullOrEmpty(entry.Name))
                    continue;
                var relative = entry.FullName.Replace('\\', '/');
                if (relative.StartsWith("Perch/", StringComparison.OrdinalIgnoreCase))
                    relative = relative["Perch/".Length..];
                if (relative.Contains("..", StringComparison.Ordinal))
                    continue;
                var path = Path.Combine(dest, relative.Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                entry.ExtractToFile(path, true);
            }
        }
    }

    static string InstallDir() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Programs",
        "Perch");

    static string ShortcutPath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Microsoft", "Windows", "Start Menu", "Programs", "Perch.lnk");

    static void CreateShortcut(string shortcut, string target, string workingDirectory)
    {
        var script = Path.Combine(Path.GetTempPath(), "perch-shortcut.ps1");
        File.WriteAllText(script, """
            $shell = New-Object -ComObject WScript.Shell
            $link = $shell.CreateShortcut($args[0])
            $link.TargetPath = $args[1]
            $link.WorkingDirectory = $args[2]
            $link.Description = 'Perch'
            $link.Save()
            """, new System.Text.UTF8Encoding(true));
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "powershell.exe",
            ArgumentList = { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, shortcut, target, workingDirectory },
            CreateNoWindow = true,
            UseShellExecute = false,
        });
        process?.WaitForExit();
        TryDelete(script);
        if (process is not { ExitCode: 0 } || !File.Exists(shortcut))
            throw new InvalidOperationException("没有创建开始菜单快捷方式。");
    }

    static void WriteUninstallKey(string dest, string uninstallExe)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\Perch");
        key.SetValue("DisplayName", "Perch");
        key.SetValue("DisplayVersion", Version);
        key.SetValue("Publisher", "Perch");
        key.SetValue("InstallLocation", dest);
        key.SetValue("DisplayIcon", Path.Combine(dest, "Perch.exe"));
        key.SetValue("UninstallString", $"\"{uninstallExe}\" /uninstall");
        key.SetValue("NoModify", 1, RegistryValueKind.DWord);
        key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        long bytes = 0;
        foreach (var file in Directory.EnumerateFiles(dest, "*", SearchOption.AllDirectories))
            bytes += new FileInfo(file).Length;
        key.SetValue("EstimatedSize", (int)(bytes / 1024), RegistryValueKind.DWord);
    }

    static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
                File.Delete(path);
        }
        catch
        {
            // 删不掉的快捷方式或脚本不影响安装结果。
        }
    }

    static int Ask(string text, bool yesNo = false, bool retry = false)
    {
        uint kind = 0;
        if (yesNo)
            kind = 4;
        else if (retry)
            kind = 5;
        else
            kind = 1;
        return MessageBox(IntPtr.Zero, text, "Perch", kind | 0x40);
    }

    static void Say(string text) => MessageBox(IntPtr.Zero, text, "Perch", 0x40);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int MessageBox(IntPtr owner, string text, string caption, uint type);
}
