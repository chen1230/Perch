using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Styling;
using Avalonia.Threading;
using Avalonia.VisualTree;
using System.Globalization;

namespace Perch;

public partial class SearchWindow : Window
{
    ClipBook _book = new();
    Shelf? _shelf;
    ThemeId _theme = ThemeId.Day;
    Guid? _selected;
    bool _acceptOutside, _ateDelete, _allowClose, _expanded;
    int _openGeneration, _undoGeneration;
    IntPtr _previous;
    readonly Dictionary<Guid, Border> _rows = new();
    readonly Dictionary<(string, int), Bitmap> _images = new();
    public event Action<Clip, IntPtr>? PasteRequested;
    public event Action? ClipsChanged;

    public SearchWindow()
    {
        InitializeComponent();
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Transparent;
        Query.Watermark = L.SearchWatermark;
        PasteButton.Content = "↩ " + L.S("粘贴", "Paste");
        DeleteButton.Content = "Ctrl+⌫ " + L.Delete;
        CloseButton.Content = "esc " + L.S("关闭", "Close");
        UndoButton.Content = L.S("撤销删除", "Undo delete");
        PasteButton.Click += (_, _) => PasteSelection();
        DeleteButton.Click += (_, _) => DeleteSelection();
        CloseButton.Click += (_, _) => Dismiss(true);
        UndoButton.Click += (_, _) => Undo();
        Clear.Click += (_, _) => { Query.Text = ""; Query.Focus(); };
        Query.TextChanged += (_, _) => { _selected = null; _expanded = false; Rebuild(); SelectFirst(); };
        AddHandler(KeyDownEvent, OnTunnelKey, RoutingStrategies.Tunnel);
        AddHandler(KeyUpEvent, (_, e) => { if (e.Key == Key.Back) _ateDelete = false; }, RoutingStrategies.Tunnel);
        Deactivated += (_, _) => { if (_acceptOutside) Dismiss(false); };
        ApplyTheme();
    }

    public void AllowClose() => _allowClose = true;
    internal void Attach(Shelf shelf) { _shelf = shelf; _book = shelf.Clips; }
    public void SetTheme(ThemeId theme) { _theme = theme; ApplyTheme(); }
    public void Reload() { if (IsVisible) Rebuild(); }
    public void Report(string? message) { Feedback.Text = message; }

    public void Toggle(Screen? screen)
    {
        if (IsVisible) { Dismiss(true); return; }
        _previous = Win.Foreground();
        _acceptOutside = false;
        _ateDelete = false;
        _expanded = false;
        Query.Text = "";
        _selected = null;
        if (screen != null)
        {
            var scale = screen.Scaling <= 0 ? 1 : screen.Scaling;
            Position = new PixelPoint(screen.WorkingArea.X, screen.WorkingArea.Y);
            Width = screen.WorkingArea.Width / scale;
            Height = screen.WorkingArea.Height / scale;
        }
        else { Width = 800; Height = 640; }
        Shell.Width = Math.Min(704, Math.Max(380, Width - 48));
        Shell.Height = Math.Min(520, Math.Max(280, Height - 48));
        Body.ColumnDefinitions[0].Width = new GridLength(Math.Min(222, Shell.Width * 0.32));
        Show(); Activate(); Rebuild(); SelectFirst(); Query.Focus();
        var opened = ++_openGeneration;
        var arm = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        arm.Tick += (_, _) => { arm.Stop(); if (opened == _openGeneration) _acceptOutside = true; };
        arm.Start();
    }

    void Dismiss(bool restore)
    {
        _acceptOutside = false;
        _openGeneration++;
        Hide();
        if (restore) Win.RestoreFocus(_previous);
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        var point = e.GetPosition(Shell);
        if (_acceptOutside && (point.X < 0 || point.Y < 0 || point.X > Shell.Bounds.Width || point.Y > Shell.Bounds.Height))
            Dismiss(false);
    }

    protected override void OnClosing(WindowClosingEventArgs e)
    {
        if (!_allowClose) { e.Cancel = true; Dismiss(false); }
        else { foreach (var bitmap in _images.Values) bitmap.Dispose(); _images.Clear(); }
        base.OnClosing(e);
    }

    void OnTunnelKey(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            if (_expanded) { _expanded = false; ShowDetail(); }
            else Dismiss(true);
        }
        else if (e.Key == Key.Down) Move(1);
        else if (e.Key == Key.Up) Move(-1);
        else if (e.Key == Key.Enter) PasteSelection();
        else if (e.Key == Key.Z && e.KeyModifiers == KeyModifiers.Control) Undo();
        else if (e.Key == Key.Back && e.KeyModifiers == KeyModifiers.Control)
        {
            if (!_ateDelete) { _ateDelete = true; DeleteSelection(); }
        }
        else return;
        e.Handled = true;
    }

    IReadOnlyList<Clip> Current() => ClipBook.Filter(_book.Items, Query.Text);
    Clip? Selected() => Current().FirstOrDefault(c => c.Id == _selected);
    void SelectFirst() { _selected = null; Select(Current().FirstOrDefault()?.Id); }
    void Select(Guid? id)
    {
        if (_selected != id)
        {
            _selected = id;
            _expanded = false;
            if (id is Guid selected) { _book.Touch(selected, DateTimeOffset.Now); ClipsChanged?.Invoke(); }
        }
        RefreshSelection();
    }
    void Move(int delta)
    {
        var found = Current();
        if (found.Count == 0) return;
        var index = found.ToList().FindIndex(c => c.Id == _selected);
        Select(found[Math.Clamp(index + delta, 0, found.Count - 1)].Id);
        if (_selected is Guid id && _rows.TryGetValue(id, out var row)) row.BringIntoView();
    }
    void PasteSelection()
    {
        if (Selected() is not Clip clip) return;
        var previous = _previous;
        _acceptOutside = false;
        PasteRequested?.Invoke(clip, previous);
    }
    internal void PasteSucceeded() { Dismiss(false); }

    void DeleteSelection() { if (_selected is Guid id) DeleteId(id); }
    void DeleteId(Guid id)
    {
        var found = Current().ToList();
        var index = found.FindIndex(c => c.Id == id);
        if (index < 0 || _shelf == null) return;
        _shelf.PendingDelete = found[index];
        _book.Remove(id);
        var after = Current();
        _selected = after.Count == 0 ? null : after[Math.Min(index, after.Count - 1)].Id;
        _expanded = false;
        ClipsChanged?.Invoke();
        Rebuild();
        Feedback.Text = L.S("已删除", "Deleted");
        var generation = ++_undoGeneration;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (generation != _undoGeneration) return;
            _shelf.PendingDelete = null;
            ClipsChanged?.Invoke();
            Feedback.Text = "";
            UndoButton.IsVisible = false;
        };
        timer.Start();
    }
    void Undo()
    {
        if (_shelf?.PendingDelete is not Clip clip) return;
        _undoGeneration++;
        _shelf.PendingDelete = null;
        _selected = _book.Restore(clip);
        ClipsChanged?.Invoke();
        Rebuild();
        Feedback.Text = "";
    }

    void ApplyTheme()
    {
        RequestedThemeVariant = ThemeChrome.Dark(_theme) ? ThemeVariant.Dark : ThemeVariant.Light;
        Shell.Background = new SolidColorBrush(_theme == ThemeId.Day ? Color.Parse("#fcfbfd") : ThemeChrome.Page(_theme));
        Query.Foreground = new SolidColorBrush(ThemeChrome.Ink(_theme));
        Query.Background = new SolidColorBrush(ThemeChrome.Field(_theme));
        Divider.Background = new SolidColorBrush(ThemeChrome.Muted(_theme)) { Opacity = 0.16 };
        foreach (var button in new[] { PasteButton, DeleteButton, CloseButton, UndoButton })
            button.Foreground = new SolidColorBrush(ThemeChrome.Muted(_theme));
        Feedback.Foreground = Empty.Foreground = new SolidColorBrush(ThemeChrome.Muted(_theme));
        Rebuild();
    }

    void Rebuild()
    {
        var found = Current();
        Clear.IsVisible = !string.IsNullOrEmpty(Query.Text);
        if (!found.Any(c => c.Id == _selected)) { _selected = found.FirstOrDefault()?.Id; _expanded = false; }
        Rows.Children.Clear(); _rows.Clear();
        Empty.IsVisible = found.Count == 0;
        Empty.Text = string.IsNullOrWhiteSpace(Query.Text) ? L.EmptyClips : L.NoMatches;
        string? group = null;
        foreach (var clip in found)
        {
            var label = Group(clip.At);
            if (string.IsNullOrWhiteSpace(Query.Text) && label != group)
            {
                group = label;
                Rows.Children.Add(new TextBlock { Text = group, FontSize = 14, Margin = new Thickness(8, 10, 0, 4),
                    Foreground = new SolidColorBrush(ThemeChrome.Muted(_theme)) });
            }
            var row = MakeRow(clip);
            _rows[clip.Id] = row;
            Rows.Children.Add(row);
        }
        RefreshSelection();
        // Cached thumbnails must not hold files open or grow beyond current history.
        var paths = _book.Items.Where(c => c.IsImage).Select(c => c.ImagePath!).ToHashSet();
        if (_shelf?.PendingDelete?.ImagePath is string pending) paths.Add(pending);
        foreach (var key in _images.Keys.Where(k => !paths.Contains(k.Item1)).ToList())
        { _images[key].Dispose(); _images.Remove(key); }
    }

    Border MakeRow(Clip clip)
    {
        var row = new Border { CornerRadius = new CornerRadius(9), Padding = new Thickness(8, 4), Height = 36,
            Cursor = new Cursor(StandardCursorType.Hand), Tag = clip.Id };
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("24,*,16") };
        if (clip.IsImage)
        {
            var thumbnail = Picture(clip, 72);
            thumbnail.Width = 24; thumbnail.Height = 24;
            grid.Children.Add(thumbnail);
        }
        else grid.Children.Add(new Avalonia.Controls.Shapes.Ellipse { Width = 6, Height = 6,
            Fill = new SolidColorBrush(ThemeChrome.Accent(_theme, clip.Id)), VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Left });
        var text = new TextBlock { FontSize = 13, Margin = new Thickness(8, 0, 4, 0), TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center, Foreground = new SolidColorBrush(ThemeChrome.Ink(_theme)) };
        var label = clip.IsImage ? $"{L.S("图片", "Image")} ({clip.Width} × {clip.Height})" : ClipBook.Snippet(clip.Text, Query.Text);
        FillHighlight(text, label, Query.Text ?? "", ThemeChrome.Accent(_theme, clip.Id));
        Grid.SetColumn(text, 1); grid.Children.Add(text);
        var delete = new Button { Content = "×", Width = 16, Height = 24, Padding = new Thickness(0),
            Background = Brushes.Transparent, BorderThickness = new Thickness(0), FontSize = 11,
            Foreground = new SolidColorBrush(ThemeChrome.Muted(_theme)), IsVisible = clip.Id == _selected };
        ToolTip.SetTip(delete, L.Delete);
        delete.Click += (_, e) => { e.Handled = true; DeleteId(clip.Id); };
        Grid.SetColumn(delete, 2); grid.Children.Add(delete);
        row.Child = grid;
        row.PointerPressed += (_, e) =>
        {
            if (!e.GetCurrentPoint(row).Properties.IsLeftButtonPressed) return;
            if (e.Source is Control control && (control == delete || delete.IsVisualAncestorOf(control))) return;
            Select(clip.Id);
            if (e.ClickCount == 2) PasteSelection();
            e.Handled = true;
        };
        return row;
    }

    void RefreshSelection()
    {
        foreach (var (id, row) in _rows)
        {
            var selected = id == _selected;
            row.Background = selected ? new SolidColorBrush(ThemeChrome.SelectedFill(_theme, ThemeChrome.Accent(_theme, id))) : Brushes.Transparent;
            if (row.Child is Grid grid && grid.Children.LastOrDefault() is Button delete) delete.IsVisible = selected;
        }
        PasteButton.IsEnabled = Selected() is Clip clip && (!clip.IsImage || File.Exists(clip.ImagePath));
        DeleteButton.IsEnabled = Selected() != null;
        UndoButton.IsVisible = _shelf?.PendingDelete != null;
        Feedback.Text = _shelf?.Error ?? (string.IsNullOrWhiteSpace(Query.Text) ? "" : L.S("仅搜索文字", "Searches text only"));
        ShowDetail();
    }

    void ShowDetail()
    {
        Detail.Children.Clear();
        ListScroll.IsVisible = Divider.IsVisible = !_expanded;
        DetailScroll.SetValue(Grid.ColumnSpanProperty, _expanded ? 3 : 1);
        DetailScroll.SetValue(Grid.ColumnProperty, _expanded ? 0 : 2);
        if (Selected() is not Clip clip)
        {
            Detail.Children.Add(new TextBlock { Text = string.IsNullOrWhiteSpace(Query.Text)
                ? L.S("复制文字或图片后，会出现在这里", "Copy text or an image to get started") : L.NoMatches,
                TextWrapping = TextWrapping.Wrap, FontSize = 14, Margin = new Thickness(8, 32, 8, 0),
                Foreground = new SolidColorBrush(ThemeChrome.Muted(_theme)) });
            return;
        }
        foreach (var key in _images.Keys.Where(k => k.Item2 > 72 && k.Item1 != clip.ImagePath).ToList())
        { _images[key].Dispose(); _images.Remove(key); }
        if (_expanded)
        {
            var back = new Button { Content = "‹ " + L.S("返回", "Back"), Margin = new Thickness(0, 0, 0, 10) };
            back.Click += (_, _) => { _expanded = false; ShowDetail(); };
            Detail.Children.Add(back);
            var image = Picture(clip, 2048); image.Height = Math.Max(160, Shell.Height - 160);
            Detail.Children.Add(image);
            return;
        }
        if (clip.IsImage)
        {
            var image = Picture(clip, 1024);
            image.Height = 214;
            image.PointerPressed += (_, _) => { _expanded = true; ShowDetail(); };
            ToolTip.SetTip(image, L.S("点击放大", "Click to enlarge"));
            Detail.Children.Add(image);
        }
        else
        {
            var text = new SelectableTextBlock { Text = clip.Text, FontSize = 15, TextWrapping = TextWrapping.Wrap,
                Foreground = new SolidColorBrush(ThemeChrome.Ink(_theme)) };
            Detail.Children.Add(new ScrollViewer { Content = text, MaxHeight = 214, HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled });
        }
        var meta = new StackPanel { Margin = new Thickness(0, 14, 0, 0) };
        Meta(meta, L.S("来源", "Source"), clip.Source ?? L.S("未知来源", "Unknown source"));
        Meta(meta, L.S("类型", "Type"), clip.IsImage ? L.S("图片", "Image") : L.S("文字", "Text"));
        if (clip.IsImage)
        {
            Meta(meta, L.S("尺寸", "Dimensions"), $"{clip.Width} × {clip.Height} px");
            Meta(meta, L.S("大小", "File size"), clip.Bytes >= 1024 * 1024 ? $"{clip.Bytes / 1048576.0:0.#} MB" : $"{clip.Bytes / 1024.0:0.#} KB");
        }
        else Meta(meta, L.S("字数", "Characters"), new StringInfo(clip.Text).LengthInTextElements.ToString());
        Meta(meta, L.S("时间", "Time"), clip.At.ToLocalTime().ToString("g"));
        Detail.Children.Add(meta);
    }

    Control Picture(Clip clip, int pixels)
    {
        try
        {
            var path = clip.ImagePath!;
            if (!File.Exists(path)) throw new IOException();
            var key = (path, pixels);
            if (!_images.TryGetValue(key, out var bitmap))
            {
                using var stream = File.OpenRead(path);
                var width = Math.Max(1, Math.Min(clip.Width, (int)(pixels * Math.Min(1.0, (double)clip.Width / Math.Max(1, clip.Height)))));
                bitmap = Bitmap.DecodeToWidth(stream, width);
                _images[key] = bitmap;
            }
            return new Image { Source = bitmap, Stretch = Stretch.Uniform };
        }
        catch { return new TextBlock { Text = L.UnreadableImage, FontSize = 12, TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center,
            Foreground = new SolidColorBrush(ThemeChrome.Muted(_theme)) }; }
    }

    void Meta(StackPanel stack, string name, string value)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*"), Margin = new Thickness(0, 7) };
        grid.Children.Add(new TextBlock { Text = name, FontSize = 13, Foreground = new SolidColorBrush(ThemeChrome.Muted(_theme)) });
        var text = new TextBlock { Text = value, FontSize = 13, TextTrimming = TextTrimming.CharacterEllipsis,
            HorizontalAlignment = HorizontalAlignment.Right, Foreground = new SolidColorBrush(ThemeChrome.Ink(_theme)) };
        ToolTip.SetTip(text, value); Grid.SetColumn(text, 1); grid.Children.Add(text);
        stack.Children.Add(new Border { BorderThickness = new Thickness(0, 1, 0, 0),
            BorderBrush = new SolidColorBrush(ThemeChrome.Muted(_theme)) { Opacity = 0.16 }, Child = grid });
    }

    static string Group(DateTimeOffset at)
    {
        var local = at.LocalDateTime;
        var days = (DateTime.Today - local.Date).Days;
        if (days <= 0) return L.S("今天", "Today");
        if (days == 1) return L.S("昨天", "Yesterday");
        if (days < 7) return L.S("近一周", "Last 7 days");
        if (days < 30) return L.S("近一月", "Last 30 days");
        return local.ToString(local.Year == DateTime.Today.Year ? "MMMM" : "yyyy MMMM");
    }

    static void FillHighlight(TextBlock block, string text, string query, Color accent)
    {
        var ranges = ClipBook.Ranges(text, query);
        if (ranges.Count == 0 || block.Inlines == null) { block.Text = text; return; }
        var cursor = 0;
        foreach (var (start, length) in ranges)
        {
            if (start > cursor) block.Inlines.Add(new Run(text[cursor..start]));
            block.Inlines.Add(new Run(text.Substring(start, length)) { Background = new SolidColorBrush(accent) { Opacity = 0.25 } });
            cursor = start + length;
        }
        if (cursor < text.Length) block.Inlines.Add(new Run(text[cursor..]));
    }
}
