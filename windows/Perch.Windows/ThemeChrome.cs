using Avalonia.Media;

namespace Perch;

static class ThemeChrome
{
    public static bool Dark(ThemeId id) => id is ThemeId.Night or ThemeId.Lacquer or ThemeId.Spectrum;

    public static Color Page(ThemeId id) => id switch
    {
        ThemeId.Night => Color.Parse("#171311"),
        ThemeId.Lacquer => Color.Parse("#2a1612"),
        ThemeId.Spectrum => Color.Parse("#141820"),
        ThemeId.Reflection => Color.Parse("#f3f5fb"),
        _ => Color.Parse("#f6f1ea"),
    };

    public static Color Ink(ThemeId id) => id switch
    {
        ThemeId.Night => Color.Parse("#f4efe8"),
        ThemeId.Lacquer => Color.Parse("#f6ead8"),
        ThemeId.Spectrum => Color.Parse("#eef1f8"),
        _ => Color.Parse("#1c140e"),
    };

    public static Color Muted(ThemeId id) => Mix(Ink(id), Page(id), 0.45);

    public static Color Field(ThemeId id) => Mix(Page(id), Ink(id), Dark(id) ? 0.08 : 0.04);

    public static Color Accent(ThemeId theme, Guid id) => Color.Parse(Themes.AccentHex(theme, id));

    public static Color SelectedFill(ThemeId id, Color accent) => id switch
    {
        ThemeId.Night => Mix(Page(id), accent, 0.28),
        ThemeId.Lacquer => Mix(accent, Color.Parse("#24140e"), 0.14),
        ThemeId.Spectrum => Mix(Page(id), accent, 0.24),
        ThemeId.Reflection => Mix(Colors.White, accent, 0.16),
        _ => Mix(Colors.White, accent, 0.22),
    };

    public static Color SelectedInk(ThemeId id, Color accent)
    {
        if (id == ThemeId.Day)
            return Mix(accent, Ink(id), 0.42);
        return Ink(id);
    }

    public static Color Wash(ThemeId id, Color accent, bool selected)
    {
        if (id == ThemeId.Lacquer && selected)
            return Color.FromArgb(87, 255, 255, 255);
        var alpha = id == ThemeId.Night ? 0.42 : selected ? 0.34 : 0.22;
        return Color.FromArgb((byte)Math.Round(alpha * 255), accent.R, accent.G, accent.B);
    }

    public static Color Mix(Color from, Color to, double amount)
    {
        byte Channel(byte start, byte end) => (byte)Math.Round(start + (end - start) * amount);
        return Color.FromRgb(Channel(from.R, to.R), Channel(from.G, to.G), Channel(from.B, to.B));
    }
}
