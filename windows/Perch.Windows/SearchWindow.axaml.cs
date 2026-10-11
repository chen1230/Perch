using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Platform;
using Avalonia.Styling;
using Avalonia.Threading;

namespace Perch;

public partial class SearchWindow : Window
{
    ClipBook _book = new();
    ThemeId _theme = ThemeId.Day;
    int _selection;
    bool _acceptOutside;
    bool _ateDelete;
    int _openGeneration;
    bool _allowClose;
    IntPtr _previous;

    public event Action<string, IntPtr>? PasteRequested;

    public SearchWindow()
    {
        InitializeComponent();
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Transparent;
        Query.Watermark = L.SearchWatermark;
        Footer.Text = L.Footer;
        Clear.Click += (_, _) => Query.Text = "";
        Query.TextChanged += (_, _) => Rebuild();
        AddHandler(KeyDownEvent, OnTunnelKey, RoutingStrategies.Tunnel);
        AddHandler(KeyUpEvent, OnTunnelUp, RoutingStrategies.Tunnel);
        Deactivated += (_, _) =>
        {
            if (_acceptOutside)
                Hide();
        };
        ApplyTheme();
    }

    public void AllowClose() => _allowClose = true;

    public void Attach(ClipBook book) => _book = book;

    public void SetTheme(ThemeId theme)
    {
        _theme = theme;
        ApplyTheme();
    }

    public void Reload()
    {
        if (IsVisible)
            Rebuild();
    }

    public void Toggle(Screen? screen)
    {
        if (IsVisible)
        {
            Hide();
            return;
        }

        _previous = Win.Foreground();
        _acceptOutside = false;
        if (screen != null)
        {
            var scale = screen.Scaling <= 0 ? 1 : screen.Scaling;
            Position = new PixelPoint(screen.Bounds.X, screen.Bounds.Y);
            Width = screen.Bounds.Width / scale;
            Height = screen.Bounds.Height / scale;
        }
        else
        {
            Width = 800;
            Height = 640;
        }

        Show();
        Activate();
        Rebuild();
        Query.Focus();
        var opened = ++_openGeneration;
        var arm = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        arm.Tick += (_, _) =>
        {
            arm.Stop();
            if (opened == _openGeneration)
                _acceptOutside = true;
        };
        arm.Start();
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        if (!_acceptOutside)
            return;
        var point = e.GetPosition(Shell);
        var inside = point.X >= 0 && point.Y >= 0 && point.X <= Shell.Bounds.Width && point.Y <= Shell.Bounds.Height;
        if (!inside)
            Hide();
    }

    protected override void OnClosing(WindowClosingEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true;
            Hide();
        }

        base.OnClosing(e);
    }

    void OnTunnelUp(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Back)
            _ateDelete = false;
    }

    void OnTunnelKey(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            Hide();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Down)
        {
            Move(1);
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Up)
        {
            Move(-1);
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Enter)
        {
            PasteSelection();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Back && e.KeyModifiers == KeyModifiers.Control)
        {
            if (!_ateDelete)
            {
                _ateDelete = true;
                DeleteSelection();
            }

            e.Handled = true;
        }
    }

    void Move(int delta)
    {
        var found = Current();
        if (found.Count == 0)
            return;
        _selection = Math.Clamp(_selection + delta, 0, found.Count - 1);
        Rebuild();
    }

    void PasteSelection()
    {
        var found = Current();
        if (!found.Any() || _selection < 0 || _selection >= found.Count)
            return;
        var text = found[_selection].Text;
        var previous = _previous;
        Hide();
        PasteRequested?.Invoke(text, previous);
    }

    void DeleteSelection()
    {
        var found = Current();
        if (!found.Any() || _selection < 0 || _selection >= found.Count)
            return;
        _book.Remove(found[_selection].Id);
        _selection = ClipBook.SelectionAfterDelete(_selection, found.Count - 1);
        ClipsChanged?.Invoke();
        Rebuild();
    }

    public event Action? ClipsChanged;

    IReadOnlyList<Clip> Current() => ClipBook.Filter(_book.Items, Query.Text);

    void ApplyTheme()
    {
        var page = ThemeChrome.Page(_theme);
        var ink = ThemeChrome.Ink(_theme);
        var muted = ThemeChrome.Muted(_theme);
        RequestedThemeVariant = ThemeChrome.Dark(_theme) ? ThemeVariant.Dark : ThemeVariant.Light;
        Shell.Background = new SolidColorBrush(page);
        Query.Foreground = new SolidColorBrush(ink);
        Query.Background = new SolidColorBrush(ThemeChrome.Field(_theme));
        Footer.Foreground = new SolidColorBrush(muted);
        Empty.Foreground = new SolidColorBrush(muted);
        Clear.IsVisible = !string.IsNullOrEmpty(Query.Text);
        Rebuild();
    }

    void Rebuild()
    {
        var query = Query.Text ?? "";
        Clear.IsVisible = query.Length > 0;
        var found = ClipBook.Filter(_book.Items, query);
        if (found.Count == 0)
            _selection = 0;
        else if (_selection >= found.Count)
            _selection = found.Count - 1;
        else if (_selection < 0)
            _selection = 0;

        Rows.Children.Clear();
        Empty.IsVisible = found.Count == 0;
        Empty.Text = string.IsNullOrWhiteSpace(query) ? L.EmptyClips : L.NoMatches;
        Border? selectedRow = null;
        for (var index = 0; index < found.Count; index++)
        {
            var row = MakeRow(found[index], query, index == _selection);
            if (index == _selection)
                selectedRow = row;
            Rows.Children.Add(row);
        }

        if (selectedRow != null)
            Dispatcher.UIThread.Post(() => selectedRow.BringIntoView(), DispatcherPriority.Background);
    }

    Border MakeRow(Clip clip, string query, bool selected)
    {
        var accent = ThemeChrome.Accent(_theme, clip.Id);
        var ink = selected ? ThemeChrome.SelectedInk(_theme, accent) : ThemeChrome.Ink(_theme);
        var row = new Border
        {
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(10, 8),
            Background = selected ? new SolidColorBrush(ThemeChrome.SelectedFill(_theme, accent)) : Brushes.Transparent,
            Cursor = new Cursor(StandardCursorType.Hand),
            Tag = clip.Id,
        };
        if (_theme == ThemeId.Spectrum && selected)
        {
            row.BorderThickness = new Thickness(2, 0, 0, 0);
            row.BorderBrush = new SolidColorBrush(accent);
        }

        var grid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("16,*,Auto,28"),
        };
        var showDot = _theme != ThemeId.Reflection;
        if (showDot)
        {
            var dot = new Avalonia.Controls.Shapes.Ellipse
            {
                Width = 8,
                Height = 8,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                Fill = _theme == ThemeId.Lacquer && selected
                    ? new SolidColorBrush(Colors.White) { Opacity = 0.9 }
                    : new SolidColorBrush(accent),
            };
            grid.Children.Add(dot);
        }

        var text = new TextBlock
        {
            FontSize = 14,
            TextWrapping = TextWrapping.Wrap,
            Foreground = new SolidColorBrush(ink),
            Margin = new Thickness(8, 0, 8, 0),
            MaxHeight = 72,
        };
        FillHighlight(text, ClipBook.Snippet(clip.Text, query), query, _theme, accent, selected);
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);

        var time = new TextBlock
        {
            Text = clip.At.ToLocalTime().ToString("HH:mm"),
            FontSize = 12,
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            Foreground = new SolidColorBrush(_theme == ThemeId.Reflection ? accent : ThemeChrome.Muted(_theme)),
            FontWeight = _theme == ThemeId.Reflection && selected ? FontWeight.Bold : FontWeight.Normal,
            Margin = new Thickness(0, 0, 8, 0),
        };
        Grid.SetColumn(time, 2);
        grid.Children.Add(time);

        var delete = new Button
        {
            Content = "×",
            Width = 24,
            Height = 24,
            Padding = new Thickness(0),
            Background = Brushes.Transparent,
            Foreground = new SolidColorBrush(ink),
            BorderThickness = new Thickness(0),
            Opacity = 0,
            IsHitTestVisible = false,
            Tag = clip.Id,
        };
        ToolTip.SetTip(delete, L.Delete);
        delete.PointerPressed += (_, e) =>
        {
            e.Handled = true;
            DeleteId(clip.Id);
        };
        Grid.SetColumn(delete, 3);
        grid.Children.Add(delete);
        row.Child = grid;
        row.PointerEntered += (_, _) => ShowDelete(delete, true);
        row.PointerExited += (_, _) => ShowDelete(delete, false);
        row.PointerPressed += (_, e) =>
        {
            if (e.Handled)
                return;
            if (e.GetCurrentPoint(row).Properties.IsLeftButtonPressed)
            {
                var found = Current();
                var index = -1;
                for (var i = 0; i < found.Count; i++)
                {
                    if (found[i].Id == clip.Id)
                        index = i;
                }

                if (index >= 0)
                    _selection = index;
                PasteSelection();
                e.Handled = true;
            }
        };
        return row;
    }

    void ShowDelete(Button delete, bool show)
    {
        delete.Opacity = show ? 1 : 0;
        delete.IsHitTestVisible = show;
    }

    void DeleteId(Guid id)
    {
        var found = Current();
        var index = -1;
        for (var i = 0; i < found.Count; i++)
        {
            if (found[i].Id == id)
                index = i;
        }

        if (index < 0 || !_book.Remove(id))
            return;
        _selection = ClipBook.SelectionAfterDelete(index, found.Count - 1);
        ClipsChanged?.Invoke();
        Rebuild();
    }

    static void FillHighlight(TextBlock block, string snippet, string query, ThemeId theme, Color accent, bool selected)
    {
        var ranges = ClipBook.Ranges(snippet, query);
        if (ranges.Count == 0)
        {
            block.Text = snippet;
            return;
        }

        var inlines = block.Inlines;
        if (inlines == null)
        {
            block.Text = snippet;
            return;
        }

        var wash = new SolidColorBrush(ThemeChrome.Wash(theme, accent, selected));
        var cursor = 0;
        foreach (var (start, length) in ranges)
        {
            if (start < cursor)
                continue;
            if (start > cursor)
                inlines.Add(new Run(snippet[cursor..start]));
            var end = Math.Min(snippet.Length, start + length);
            if (end <= start)
                break;
            inlines.Add(new Run(snippet[start..end]) { Background = wash });
            cursor = end;
        }

        if (cursor < snippet.Length)
            inlines.Add(new Run(snippet[cursor..]));
    }
}
