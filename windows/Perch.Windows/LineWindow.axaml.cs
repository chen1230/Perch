using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace Perch;

public partial class LineWindow : Window
{
    bool _allowClose;

    public LineWindow()
    {
        InitializeComponent();
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
        HintText.Text = L.EmptyLine;
    }

    public void AllowClose() => _allowClose = true;

    public void SyncHint() => Hint.IsVisible = Rope.Count == 0;

    protected override void OnClosing(WindowClosingEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true;
            Hide();
        }

        base.OnClosing(e);
    }
}
