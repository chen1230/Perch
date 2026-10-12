using System.Text.Json;

namespace Perch;

static class AppPaths
{
    public static string Root => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Perch");

    public static string Screenshots => Path.Combine(Root, "Screenshots");
    public static string HistoryFile => Path.Combine(Root, "clipboard-history.json");
    public static string HistoryImages => Path.Combine(Root, "ClipboardImages");
    public static string TextClips => Path.Combine(Root, "text-clips.json");
    public static string LineFile => Path.Combine(Root, "line.json");
    public static string SettingsFile => Path.Combine(Root, "settings.json");

    public static bool IsOwnFile(string path)
    {
        var full = Path.GetFullPath(path);
        var root = Path.GetFullPath(Screenshots) + Path.DirectorySeparatorChar;
        return full.StartsWith(root, StringComparison.OrdinalIgnoreCase);
    }
}

sealed class Shelf
{
    readonly string _root;
    bool _unreadableHistory;
    HashSet<string> _knownImageFiles = new(StringComparer.OrdinalIgnoreCase);
    public Shelf(string? root = null) { _root = root ?? AppPaths.Root; }
    string FileAt(string name) => Path.Combine(_root, name);
    string HistoryImages => FileAt("ClipboardImages");

    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    public ClipBook Clips { get; } = new();
    public LineBook Line { get; } = new();
    public ThemeId Theme { get; set; } = ThemeId.Day;
    public bool ImageHang { get; set; } = true;
    public Clip? PendingDelete { get; set; }
    public string? Error { get; private set; }

    public void Load()
    {
        Directory.CreateDirectory(FileAt("Screenshots"));
        var settings = Read<SettingsFile>(FileAt("settings.json"));
        if (settings != null)
        {
            Theme = Themes.Parse(settings.Theme);
            ImageHang = settings.ImageHang;
            Clips.SetLimits(settings.TextLimit, settings.ImageLimit);
        }

        var historyExists = File.Exists(FileAt("clipboard-history.json"));
        var clips = Read<List<Clip>>(historyExists ? FileAt("clipboard-history.json") : FileAt("text-clips.json"));
        if (clips != null)
        {
            _knownImageFiles = clips.Where(c => c.ImagePath != null).Select(c => c.ImagePath!).ToHashSet(StringComparer.OrdinalIgnoreCase);
            Clips.ReplaceAll(clips.Where(clip => clip.Id != Guid.Empty));
        }
        _unreadableHistory = historyExists && clips == null;
        if (_unreadableHistory) Error = L.SaveFailed;

        var line = Read<LineFile>(FileAt("line.json"));
        if (line != null)
        {
            Line.ReplaceAll(line.Items
                .Where(item => File.Exists(item.Path))
                .Select(item => (item.Path, item.Anchor)));
        }
    }

    public bool SaveClips()
    {
        try
        {
            if (_unreadableHistory)
            {
                File.Copy(FileAt("clipboard-history.json"), FileAt("clipboard-history-" + Guid.NewGuid().ToString("N") + ".backup.json"));
                _unreadableHistory = false;
            }
            Write(FileAt("clipboard-history.json"), Clips.Items);
            Error = null;
            var keep = Clips.Items.Where(c => c.IsImage).Select(c => c.ImagePath!).ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (PendingDelete?.ImagePath is string pending) keep.Add(pending);
            foreach (var path in _knownImageFiles.Except(keep, StringComparer.OrdinalIgnoreCase))
            {
                try
                {
                    if (string.Equals(Path.GetDirectoryName(Path.GetFullPath(path)), Path.GetFullPath(HistoryImages), StringComparison.OrdinalIgnoreCase))
                        File.Delete(path);
                }
                catch { }
            }
            _knownImageFiles = keep;
            return true;
        }
        catch { Error = L.SaveFailed; return false; }
    }

    public Clip? RememberImage(byte[] png, string? source)
    {
        try
        {
            Error = null;
            if (png.Length > 64 * 1024 * 1024) { Error = L.ImageTooLarge; return null; }
            using var codec = SkiaSharp.SKCodec.Create(new SkiaSharp.SKMemoryStream(png));
            if (codec == null || codec.Info.Width <= 0 || codec.Info.Height <= 0
                || (long)codec.Info.Width * codec.Info.Height > 80_000_000) { Error = L.UnreadableImage; return null; }
            var key = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(png));
            Directory.CreateDirectory(HistoryImages);
            var path = Path.Combine(HistoryImages, key + ".png");
            if (!File.Exists(path))
            {
                File.WriteAllBytes(path + ".tmp", png);
                File.Move(path + ".tmp", path, true);
            }
            var clip = Clips.RememberImage(path, key, codec.Info.Width, codec.Info.Height, png.Length, DateTimeOffset.Now, source);
            SaveClips();
            return clip;
        }
        catch { Error = L.SaveFailed; return null; }
    }

    public void SaveLine()
    {
        Write(FileAt("line.json"), new LineFile
        {
            Items = Line.Items.Select(item => new LineItemFile
            {
                Path = item.Path,
                Anchor = item.Anchor,
            }).ToList(),
        });
    }

    public void SaveSettings()
    {
        Write(FileAt("settings.json"), new SettingsFile
        {
            Theme = Themes.Key(Theme),
            ImageHang = ImageHang,
            TextLimit = Clips.TextLimit,
            ImageLimit = Clips.ImageLimit,
        });
    }

    static T? Read<T>(string path)
    {
        try
        {
            if (!File.Exists(path))
                return default;
            return JsonSerializer.Deserialize<T>(File.ReadAllText(path), Json);
        }
        catch
        {
            return default;
        }
    }

    void Write(string path, object value)
    {
        Directory.CreateDirectory(_root);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(value, Json));
        File.Move(tmp, path, true);
    }

    sealed class SettingsFile
    {
        public string Theme { get; set; } = "day";
        public bool ImageHang { get; set; } = true;
        public int TextLimit { get; set; } = 1000;
        public int ImageLimit { get; set; } = 100;
    }

    sealed class LineFile
    {
        public List<LineItemFile> Items { get; set; } = new();
    }

    sealed class LineItemFile
    {
        public string Path { get; set; } = "";
        public double Anchor { get; set; }
    }
}
