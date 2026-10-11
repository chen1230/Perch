using System.Text.Json;

namespace Perch;

static class AppPaths
{
    public static string Root => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Perch");

    public static string Screenshots => Path.Combine(Root, "Screenshots");
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
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    public ClipBook Clips { get; } = new();
    public LineBook Line { get; } = new();
    public ThemeId Theme { get; set; } = ThemeId.Day;
    public bool ImageHang { get; set; } = true;

    public void Load()
    {
        Directory.CreateDirectory(AppPaths.Screenshots);
        var settings = Read<SettingsFile>(AppPaths.SettingsFile);
        if (settings != null)
        {
            Theme = Themes.Parse(settings.Theme);
            ImageHang = settings.ImageHang;
        }

        var clips = Read<List<ClipFile>>(AppPaths.TextClips);
        if (clips != null)
        {
            Clips.ReplaceAll(clips
                .Where(clip => clip.Id != Guid.Empty)
                .Select(clip => new Clip(clip.Id, clip.Text, clip.At)));
        }

        var line = Read<LineFile>(AppPaths.LineFile);
        if (line != null)
        {
            Line.ReplaceAll(line.Items
                .Where(item => File.Exists(item.Path))
                .Select(item => (item.Path, item.Anchor)));
        }
    }

    public void SaveClips()
    {
        Write(AppPaths.TextClips, Clips.Items.Select(clip => new ClipFile
        {
            Id = clip.Id,
            Text = clip.Text,
            At = clip.At,
        }).ToList());
    }

    public void SaveLine()
    {
        Write(AppPaths.LineFile, new LineFile
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
        Write(AppPaths.SettingsFile, new SettingsFile
        {
            Theme = Themes.Key(Theme),
            ImageHang = ImageHang,
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

    static void Write(string path, object value)
    {
        Directory.CreateDirectory(AppPaths.Root);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(value, Json));
        File.Move(tmp, path, true);
    }

    sealed class SettingsFile
    {
        public string Theme { get; set; } = "day";
        public bool ImageHang { get; set; } = true;
    }

    sealed class ClipFile
    {
        public Guid Id { get; set; }
        public string Text { get; set; } = "";
        public DateTimeOffset At { get; set; }
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
