using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Platform;
using Avalonia.Threading;

namespace Perch;

sealed class AppHost
{
    readonly Shelf _shelf = new();
    readonly LineWindow _line = new();
    readonly SearchWindow _search = new();
    readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(50) };
    readonly DateTime _started = DateTime.UtcNow;
    readonly List<(NativeMenuItem Item, ThemeId Theme)> _themes = new();

    IClassicDesktopStyleApplicationLifetime _desktop = null!;
    NativeMenuItem _showItem = null!;
    NativeMenuItem _hangItem = null!;
    FileSystemWatcher? _watcher;
    bool _pinned;
    bool _tDown;
    bool _vDown;
    DateTime _lastLineKey;
    DateTime _lastSearchKey;
    DateTime _holdUntil;
    DateTime? _outsideSince;
    uint _sequence;
    int _tick;
    string? _macText;

    public void Start(IClassicDesktopStyleApplicationLifetime desktop)
    {
        _desktop = desktop;
        _shelf.Load();
        _line.Rope.Bind(_shelf.Line);
        _line.SyncHint();
        _line.Rope.CopyRequested += CopyImage;
        _line.Rope.DiscardRequested += Discard;
        _line.Rope.Changed += () => _shelf.SaveLine();
        _search.Attach(_shelf);
        _search.SetTheme(_shelf.Theme);
        _search.PasteRequested += Paste;
        _search.ClipsChanged += () => { if (!_shelf.SaveClips()) _search.Report(_shelf.Error); };
        var icon = LoadIcon();
        if (icon != null)
        {
            _line.Icon = icon;
            _search.Icon = icon;
        }

        BuildTray(icon);
        desktop.ShutdownRequested += (_, _) =>
        {
            _timer.Stop();
            _watcher?.Dispose();
            _line.AllowClose();
            _search.AllowClose();
        };
        if (OperatingSystem.IsWindows())
            _sequence = Win.Sequence();
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
        AttachWatcher();
    }

    void BuildTray(WindowIcon? icon)
    {
        var menu = new NativeMenu();
        _showItem = new NativeMenuItem(L.ShowLine + "    " + L.LineShortcut);
        _showItem.Click += (_, _) => ToggleLine();
        menu.Add(_showItem);

        var copied = new NativeMenuItem(L.CopiedText + "    " + L.SearchShortcut);
        copied.Click += (_, _) => ToggleSearch();
        menu.Add(copied);
        var capacity = new NativeMenuItem(L.S("历史容量", "History capacity")) { Menu = new NativeMenu() };
        AddCapacityMenu(capacity.Menu, true, new[] { 50, 100, 200, 500 });
        AddCapacityMenu(capacity.Menu, false, new[] { 100, 500, 1000, 5000 });
        menu.Add(capacity);

        _hangItem = new NativeMenuItem(L.HangImages)
        {
            ToggleType = NativeMenuItemToggleType.CheckBox,
            IsChecked = _shelf.ImageHang,
        };
        _hangItem.Click += (_, _) =>
        {
            _shelf.ImageHang = _hangItem.IsChecked;
            _shelf.SaveSettings();
        };
        menu.Add(_hangItem);

        var theme = new NativeMenuItem(L.Theme) { Menu = new NativeMenu() };
        foreach (var id in new[] { ThemeId.Night, ThemeId.Day, ThemeId.Lacquer, ThemeId.Spectrum, ThemeId.Reflection })
        {
            var item = new NativeMenuItem(L.ThemeName(id))
            {
                ToggleType = NativeMenuItemToggleType.Radio,
                IsChecked = id == _shelf.Theme,
            };
            var chosen = id;
            item.Click += (_, _) => SelectTheme(chosen);
            _themes.Add((item, chosen));
            theme.Menu.Add(item);
        }

        menu.Add(theme);
        menu.Add(new NativeMenuItemSeparator());
        var quit = new NativeMenuItem(L.Quit);
        quit.Click += (_, _) => _desktop.Shutdown();
        menu.Add(quit);

        var tray = new TrayIcon
        {
            Icon = icon,
            ToolTipText = "Perch",
            Menu = menu,
        };
        tray.Clicked += (_, _) => ToggleLine();
        TrayIcon.SetIcons(Application.Current!, new TrayIcons { tray });
    }

    void AddCapacityMenu(NativeMenu menu, bool images, int[] values)
    {
        var category = new NativeMenuItem(images ? L.S("图片", "Images") : L.S("文字记录", "Text records")) { Menu = new NativeMenu() };
        var choices = new List<(NativeMenuItem Item, int Value)>();
        foreach (var value in values)
        {
            var option = new NativeMenuItem(value.ToString()) { ToggleType = NativeMenuItemToggleType.Radio,
                IsChecked = value == (images ? _shelf.Clips.ImageLimit : _shelf.Clips.TextLimit) };
            choices.Add((option, value));
            option.Click += (_, _) =>
            {
                _shelf.Clips.SetLimits(images ? _shelf.Clips.TextLimit : value, images ? value : _shelf.Clips.ImageLimit);
                _shelf.SaveSettings(); _shelf.SaveClips(); _search.Reload();
                foreach (var choice in choices) choice.Item.IsChecked = choice.Value == value;
            };
            category.Menu.Add(option);
        }
        menu.Add(category);
    }

    void SelectTheme(ThemeId theme)
    {
        _shelf.Theme = theme;
        _shelf.SaveSettings();
        foreach (var (item, id) in _themes)
            item.IsChecked = id == theme;
        _search.SetTheme(theme);
    }

    void Tick()
    {
        _showItem.Header = (_line.IsVisible ? L.HideLine : L.ShowLine) + "    " + L.LineShortcut;
        if (OperatingSystem.IsWindows())
        {
            PollHotkeys();
            PollCursor();
        }

        if (++_tick >= 8)
        {
            _tick = 0;
            if (OperatingSystem.IsWindows())
                PollClipboard();
            else
                _ = PollMacClipboard();
            if (_watcher == null)
                AttachWatcher();
        }
    }

    void PollHotkeys()
    {
        var line = Win.Down(Win.VkControl) && Win.Down(Win.VkMenu) && !Win.Down(Win.VkShift) && Win.Down(Win.VkT);
        var search = Win.Down(Win.VkControl) && Win.Down(Win.VkMenu) && !Win.Down(Win.VkShift) && Win.Down(Win.VkV);
        Edge(line, ref _tDown, ref _lastLineKey, ToggleLine);
        Edge(search, ref _vDown, ref _lastSearchKey, ToggleSearch);
    }

    static void Edge(bool down, ref bool latched, ref DateTime last, Action fire)
    {
        if (down && !latched)
        {
            latched = true;
            if (DateTime.UtcNow - last > TimeSpan.FromMilliseconds(250))
            {
                last = DateTime.UtcNow;
                fire();
            }
        }
        else if (!down)
        {
            latched = false;
        }
    }

    void PollCursor()
    {
        if (!Win.TryCursor(out var point))
            return;
        var screen = ScreenAt(point) ?? _line.Screens.Primary;
        if (screen == null)
            return;
        var area = screen.WorkingArea;
        var nearTop = point.X >= area.X && point.X < area.Right && point.Y >= area.Y && point.Y < area.Y + 8;
        if (!_line.IsVisible)
        {
            if (nearTop)
                Reveal(false);
            return;
        }

        if (_pinned || nearTop || OverLine(point) || DateTime.UtcNow < _holdUntil)
        {
            _outsideSince = null;
            return;
        }

        _outsideSince ??= DateTime.UtcNow;
        if (DateTime.UtcNow - _outsideSince > TimeSpan.FromMilliseconds(280))
        {
            _pinned = false;
            _line.Hide();
        }
    }

    void PollClipboard()
    {
        var sequence = Win.Sequence();
        if (sequence == 0 || sequence == _sequence)
            return;
        if (!Win.TryRead(out var read)) return;
        _sequence = sequence;
        if (read.HasFiles || read.Excluded) return;
        if (!string.IsNullOrWhiteSpace(read.Text))
        {
            _shelf.Clips.Remember(read.Text, DateTimeOffset.Now, Win.SourceName());
            _shelf.SaveClips();
            _search.Reload();
            return;
        }

        if (read.Png is { Length: > 32 })
        {
            _shelf.RememberImage(read.Png, Win.SourceName());
            _search.Reload();
            if (_shelf.Error != null) _search.Report(_shelf.Error);
            if (_shelf.ImageHang) HangBytes(read.Png);
        }
    }

    async Task PollMacClipboard()
    {
        try
        {
            var clipboard = _line.Clipboard;
            if (clipboard == null)
                return;
            var text = await clipboard.GetTextAsync();
            if (string.IsNullOrWhiteSpace(text) || text == _macText)
                return;
            _macText = text;
            _shelf.Clips.Remember(text, DateTimeOffset.Now);
            _shelf.SaveClips();
            _search.Reload();
        }
        catch
        {
            // 这台 Mac 只用来看界面，剪贴板读失败不影响 Windows 程序。
        }
    }

    void ToggleLine()
    {
        if (_line.IsVisible)
        {
            _pinned = false;
            _line.Hide();
            return;
        }

        Reveal(true);
    }

    void ToggleSearch()
    {
        var screen = _line.Screens.Primary;
        if (OperatingSystem.IsWindows() && Win.TryCursor(out var point))
            screen = ScreenAt(point) ?? screen;
        _search.Toggle(screen);
    }

    void Reveal(bool pin)
    {
        if (pin)
            _pinned = true;
        var screen = _line.Screens.Primary;
        if (OperatingSystem.IsWindows() && Win.TryCursor(out var point))
            screen = ScreenAt(point) ?? screen;
        if (screen == null)
        {
            _line.Width = 1280;
            _line.Height = 230;
            _line.Position = new PixelPoint(0, 0);
            if (!_line.IsVisible)
                _line.Show();
            _line.SyncHint();
            _line.Rope.Redraw();
            return;
        }
        var scale = screen.Scaling <= 0 ? 1 : screen.Scaling;
        var area = screen.WorkingArea;
        _line.Position = new PixelPoint(area.X, area.Y);
        _line.Width = Math.Max(320, area.Width / scale);
        _line.Height = 230;
        if (!_line.IsVisible)
            _line.Show();
        _line.SyncHint();
        _line.Rope.Redraw();
    }

    bool OverLine(PixelPoint point)
    {
        var scale = _line.Screens.ScreenFromPoint(point)?.Scaling ?? 1;
        var left = _line.Position.X;
        var top = _line.Position.Y;
        var right = left + (int)(_line.Width * scale);
        var bottom = top + (int)(_line.Height * scale);
        return point.X >= left && point.X <= right && point.Y >= top && point.Y <= bottom + 16;
    }

    Screen? ScreenAt(PixelPoint point)
    {
        foreach (var screen in _line.Screens.All)
        {
            if (screen.Bounds.Contains(point))
                return screen;
        }

        return null;
    }

    void CopyImage(string path)
    {
        if (Win.SetImageFile(path, _line.TryGetPlatformHandle()?.Handle ?? IntPtr.Zero))
            _sequence = Win.Sequence();
    }

    void Discard(string path)
    {
        _shelf.Line.Remove(path);
        _line.Rope.Forget(path);
        if (AppPaths.IsOwnFile(path))
        {
            try
            {
                File.Delete(path);
            }
            catch
            {
                // 文件正被占用时，先从绳子上拿下，下次启动不会再挂回来。
            }
        }

        _shelf.SaveLine();
        _line.SyncHint();
        _line.Rope.Redraw();
    }

    void Paste(Clip clip, IntPtr previous)
    {
        if (OperatingSystem.IsWindows())
        {
            bool copied;
            try { copied = clip.IsImage ? Win.SetImageFile(clip.ImagePath!, _search.TryGetPlatformHandle()?.Handle ?? IntPtr.Zero) : Win.SetText(clip.Text, _search.TryGetPlatformHandle()?.Handle ?? IntPtr.Zero); }
            catch { copied = false; }
            if (!copied) { _search.Report(clip.IsImage ? L.UnreadableImage : L.S("复制失败，请重试", "Could not copy; try again")); return; }
            _sequence = Win.Sequence();
            _shelf.Clips.Touch(clip.Id, DateTimeOffset.Now); _shelf.SaveClips();
            if (!Win.CanPasteInto(previous))
            {
                _search.Report(L.S("已复制，关闭后按 Ctrl+V 粘贴", "Copied. Close, then press Ctrl+V"));
                return;
            }
            _search.PasteSucceeded();
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(160) };
            timer.Tick += (_, _) => { timer.Stop(); Win.PasteInto(previous); };
            timer.Start();
            return;
        }
        if (clip.IsImage) { _search.Report(L.S("图片粘贴请在 Windows 验证", "Test image pasting on Windows")); return; }
        _macText = clip.Text;
        _ = _line.Clipboard?.SetTextAsync(clip.Text);
        _search.Report(L.S("已复制", "Copied"));
    }

    void HangBytes(byte[] png)
    {
        Directory.CreateDirectory(AppPaths.Screenshots);
        var path = Path.Combine(AppPaths.Screenshots, DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + ".png");
        File.WriteAllBytes(path, png);
        HangPath(path);
    }

    void HangPath(string path)
    {
        if (_shelf.Line.Items.Any(item => string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase)))
            return;
        var evicted = _shelf.Line.Add(path);
        if (evicted != null && AppPaths.IsOwnFile(evicted))
        {
            _line.Rope.Forget(evicted);
            try
            {
                File.Delete(evicted);
            }
            catch
            {
                // 挤掉的旧副本删不掉就留在磁盘上，绳子上不再显示。
            }
        }

        _shelf.SaveLine();
        _holdUntil = DateTime.UtcNow.AddSeconds(4);
        Reveal(false);
    }

    void AttachWatcher()
    {
        var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");
        if (!Directory.Exists(folder))
            return;
        _watcher = new FileSystemWatcher(folder)
        {
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite,
            EnableRaisingEvents = true,
        };
        _watcher.Created += (_, e) => QueueShot(e.FullPath, 0);
        _watcher.Renamed += (_, e) => QueueShot(e.FullPath, 0);
    }

    void QueueShot(string path, int attempt)
    {
        Dispatcher.UIThread.Post(async () =>
        {
            await Task.Delay(280);
            if (!File.Exists(path))
                return;
            var ext = Path.GetExtension(path);
            if (!ext.Equals(".png", StringComparison.OrdinalIgnoreCase)
                && !ext.Equals(".jpg", StringComparison.OrdinalIgnoreCase)
                && !ext.Equals(".jpeg", StringComparison.OrdinalIgnoreCase))
                return;
            try
            {
                var info = new FileInfo(path);
                if (info.Length < 64)
                {
                    if (attempt < 6)
                        QueueShot(path, attempt + 1);
                    return;
                }

                if (info.LastWriteTimeUtc < _started.AddSeconds(-3) && info.CreationTimeUtc < _started.AddSeconds(-3))
                    return;
            }
            catch
            {
                return;
            }

            HangPath(path);
        });
    }

    static WindowIcon? LoadIcon()
    {
        try
        {
            using var stream = AssetLoader.Open(new Uri("avares://Perch/Assets/icon.png"));
            return new WindowIcon(stream);
        }
        catch
        {
            return null;
        }
    }
}
