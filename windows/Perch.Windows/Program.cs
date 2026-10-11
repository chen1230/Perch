using Avalonia;

namespace Perch;

static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        catch (Exception ex)
        {
            try
            {
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Perch");
                Directory.CreateDirectory(dir);
                File.WriteAllText(Path.Combine(dir, "startup.log"), ex.ToString());
            }
            catch
            {
                // 启动日志写失败时，仍然把异常抛给系统。
            }

            throw;
        }
    }

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
