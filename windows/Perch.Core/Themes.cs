namespace Perch;

public enum ThemeId
{
    Night,
    Day,
    Lacquer,
    Spectrum,
    Reflection,
}

public static class Themes
{
    static readonly string[] Dots = ["#e2a860", "#e07d86", "#49b5a6", "#8e86d8", "#c6b15a"];
    static readonly string[] Lacquer = ["#c4523a", "#c4842a", "#1f7a6a", "#2f4c9a", "#7a3e78"];
    static readonly string[] Spectrum = ["#e23b4a", "#e08a1e", "#1c9a6a", "#2a6fe0", "#7a45d6"];
    static readonly string[] Reflection = ["#5c7fe0", "#7a6ad4", "#c45c78", "#d4896a", "#3d7a9a"];

    public static ThemeId Parse(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "night" => ThemeId.Night,
        "lacquer" => ThemeId.Lacquer,
        "spectrum" => ThemeId.Spectrum,
        "reflection" => ThemeId.Reflection,
        _ => ThemeId.Day,
    };

    public static string Key(ThemeId id) => id switch
    {
        ThemeId.Night => "night",
        ThemeId.Lacquer => "lacquer",
        ThemeId.Spectrum => "spectrum",
        ThemeId.Reflection => "reflection",
        _ => "day",
    };

    public static IReadOnlyList<string> Palette(ThemeId id) => id switch
    {
        ThemeId.Lacquer => Lacquer,
        ThemeId.Spectrum => Spectrum,
        ThemeId.Reflection => Reflection,
        _ => Dots,
    };

    public static string AccentHex(ThemeId theme, Guid id)
    {
        var palette = Palette(theme);
        var sum = 0;
        foreach (var b in id.ToByteArray())
            sum += b;
        return palette[sum % palette.Count];
    }
}
