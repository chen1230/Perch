using System.Globalization;

namespace Perch;

static class L
{
    static bool Zh => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "zh";

    public static string ShowLine => Zh ? "放下绳子" : "Show line";
    public static string HideLine => Zh ? "收起绳子" : "Hide line";
    public static string CopiedText => Zh ? "复制的文字" : "Copied text";
    public static string HangImages => Zh ? "挂上复制的图片" : "Hang copied images";
    public static string Theme => Zh ? "主题" : "Theme";
    public static string Quit => Zh ? "退出 Perch" : "Quit Perch";
    public static string SearchWatermark => Zh ? "搜索复制过的文字" : "Search copied text";
    public static string EmptyClips => Zh ? "还没有复制过文字" : "No copied text yet";
    public static string NoMatches => Zh ? "没有匹配的文字" : "No matches";
    public static string Footer => Zh
        ? "Ctrl+Backspace 删除这一条     Enter 粘贴     Esc 关闭"
        : "Ctrl+Backspace deletes one     Enter pastes     Esc closes";
    public static string EmptyLine => Zh ? "新的截图会挂在这里" : "New screenshots hang here";
    public static string Delete => Zh ? "删除" : "Delete";
    public static string LineShortcut => "Ctrl+Alt+T";
    public static string SearchShortcut => "Ctrl+Alt+V";

    public static string ThemeName(ThemeId id) => id switch
    {
        ThemeId.Night => Zh ? "夜市" : "Night",
        ThemeId.Lacquer => Zh ? "釉" : "Lacquer",
        ThemeId.Spectrum => Zh ? "谱" : "Spectrum",
        ThemeId.Reflection => Zh ? "映" : "Reflection",
        _ => Zh ? "昼" : "Day",
    };
}
