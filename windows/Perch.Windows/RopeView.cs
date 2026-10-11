using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Threading;

namespace Perch;

public sealed class RopeView : Control
{
    const double CardWidth = 148;
    const double CardHeight = 108;
    const double Side = 36;

    readonly Dictionary<string, Bitmap> _images = new(StringComparer.OrdinalIgnoreCase);
    readonly DispatcherTimer _springClock;
    readonly Pen _ropePen = new(new SolidColorBrush(Color.Parse("#7A4E32")), 3);
    readonly IBrush _peg = new SolidColorBrush(Color.Parse("#C6A15A"));
    readonly IBrush _closeFill = new SolidColorBrush(Color.Parse("#F4EFE8"));
    readonly IBrush _closeInk = new SolidColorBrush(Color.Parse("#1C140E"));

    LineBook _book = new();
    List<CardGeom> _geoms = new();
    string? _dragPath;
    Point _press;
    Point _grab;
    Point _pointer;
    bool _dragging;
    bool _lifted;
    string? _springPath;
    Point _springFrom;
    Point _springTo;
    DateTime _springStart;
    string? _hover;

    public RopeView()
    {
        _springClock = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        _springClock.Tick += (_, _) =>
        {
            InvalidateVisual();
            if (_springPath == null)
                _springClock.Stop();
        };
    }

    public event Action<string>? CopyRequested;
    public event Action<string>? DiscardRequested;
    public event Action? Changed;

    public int Count => _book.Items.Count;

    public void Bind(LineBook book)
    {
        _book = book;
        InvalidateVisual();
    }

    public void Redraw() => InvalidateVisual();

    public void Forget(string path)
    {
        if (_images.Remove(path, out var bitmap))
            bitmap.Dispose();
    }

    public override void Render(DrawingContext context)
    {
        var size = Bounds.Size;
        _geoms = Layout(size);
        DrawRope(context, size.Width);
        foreach (var card in _geoms)
            DrawCard(context, card);
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        var point = e.GetPosition(this);
        if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
            return;
        _geoms = Layout(Bounds.Size);
        var hit = Hit(point);
        if (hit == null)
            return;
        if (hit.Close.Contains(point))
        {
            DiscardRequested?.Invoke(hit.Path);
            e.Handled = true;
            return;
        }

        _dragPath = hit.Path;
        _press = point;
        _pointer = point;
        _grab = point - hit.Body.TopLeft;
        _dragging = false;
        _lifted = false;
        e.Pointer.Capture(this);
        e.Handled = true;
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        var point = e.GetPosition(this);
        _geoms = Layout(Bounds.Size);
        var hit = Hit(point);
        var hover = hit?.Path;
        if (hover != _hover)
        {
            _hover = hover;
            InvalidateVisual();
        }

        if (_dragPath == null)
            return;
        _pointer = point;
        if (!_dragging && Distance(point, _press) > 4)
            _dragging = true;
        if (_dragging)
        {
            var ropeY = RopeY(_pointer.X, Bounds.Width);
            _lifted = !LineBook.ShouldPlace(_pointer.Y, ropeY, 64);
            InvalidateVisual();
        }
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        FinishDrag(e.GetPosition(this));
        e.Pointer.Capture(null);
    }

    protected override void OnPointerCaptureLost(PointerCaptureLostEventArgs e)
    {
        base.OnPointerCaptureLost(e);
        if (_dragPath != null)
            FinishDrag(_pointer);
    }

    void FinishDrag(Point point)
    {
        var path = _dragPath;
        var dragging = _dragging;
        var lifted = _lifted;
        _dragPath = null;
        _dragging = false;
        _lifted = false;
        if (path == null)
            return;
        if (!dragging)
        {
            CopyRequested?.Invoke(path);
            InvalidateVisual();
            return;
        }

        var ropeY = RopeY(point.X, Bounds.Width);
        if (lifted && !LineBook.ShouldPlace(point.Y, ropeY, 72))
        {
            var home = Home(path, Bounds.Size);
            _springPath = path;
            _springFrom = point - _grab;
            _springTo = home;
            _springStart = DateTime.UtcNow;
            _springClock.Start();
            InvalidateVisual();
            return;
        }

        _book.TryMove(path, AnchorAt(point.X, Bounds.Width));
        Changed?.Invoke();
        InvalidateVisual();
    }

    List<CardGeom> Layout(Size size)
    {
        var cards = new List<CardGeom>();
        foreach (var item in _book.Items)
        {
            var home = Home(item.Path, size);
            var origin = home;
            if (_springPath == item.Path)
            {
                var t = (DateTime.UtcNow - _springStart).TotalMilliseconds / 180;
                if (t >= 1)
                    _springPath = null;
                else
                {
                    var ease = 1 - Math.Pow(1 - t, 3);
                    origin = new Point(
                        _springFrom.X + (_springTo.X - _springFrom.X) * ease,
                        _springFrom.Y + (_springTo.Y - _springFrom.Y) * ease);
                }
            }
            else if (_dragging && _dragPath == item.Path)
            {
                origin = _lifted
                    ? _pointer - _grab
                    : new Point(_pointer.X - CardWidth / 2, RopeY(_pointer.X, size.Width) - 18);
            }

            var body = new Rect(origin, new Size(CardWidth, CardHeight));
            var close = new Rect(body.Right - 22, body.Top + 6, 16, 16);
            cards.Add(new CardGeom(item.Path, item.Anchor, body, close, RopeY(body.Center.X, size.Width)));
        }

        return cards;
    }

    Point Home(string path, Size size)
    {
        var item = _book.Items.FirstOrDefault(entry =>
            string.Equals(entry.Path, path, StringComparison.OrdinalIgnoreCase));
        var anchor = item?.Anchor ?? 0.5;
        var x = Side + anchor * Math.Max(1, size.Width - Side * 2) - CardWidth / 2;
        var y = RopeY(x + CardWidth / 2, size.Width) - 18;
        return new Point(x, y);
    }

    static double RopeY(double x, double width)
    {
        var t = width <= 1 ? 0.5 : Math.Clamp(x / width, 0, 1);
        return 52 + 112 * t * (1 - t);
    }

    double AnchorAt(double x, double width)
    {
        var span = Math.Max(1, width - Side * 2);
        return Math.Clamp((x - Side) / span, LineItem.Edge, 1 - LineItem.Edge);
    }

    CardGeom? Hit(Point point)
    {
        for (var i = _geoms.Count - 1; i >= 0; i--)
        {
            var card = _geoms[i];
            if (card.Close.Contains(point) || card.Body.Contains(point))
                return card;
        }

        return null;
    }

    void DrawRope(DrawingContext context, double width)
    {
        if (width < 2)
            return;
        Point? previous = null;
        for (var x = 16d; x <= width - 16; x += 10)
        {
            var point = new Point(x, RopeY(x, width));
            if (previous != null)
                context.DrawLine(_ropePen, previous.Value, point);
            previous = point;
        }
    }

    void DrawCard(DrawingContext context, CardGeom card)
    {
        var shadow = card.Body.Translate(new Vector(0, 4));
        context.DrawRectangle(new SolidColorBrush(Color.Parse("#33000000")), null, new RoundedRect(shadow, 12));
        var bitmap = ImageFor(card.Path);
        if (bitmap != null)
        {
            using (context.PushClip(new RoundedRect(card.Body, 12)))
                context.DrawImage(bitmap, card.Body);
        }
        else
        {
            context.DrawRectangle(new SolidColorBrush(Color.Parse("#E7D7C4")), null, new RoundedRect(card.Body, 12));
        }

        context.DrawRectangle(null, new Pen(new SolidColorBrush(Color.Parse("#F7F1E8")), 2), new RoundedRect(card.Body, 12));
        context.DrawEllipse(_peg, null, new Point(card.Body.Center.X, card.RopeY), 5, 5);
        var hot = _hover == card.Path || _dragPath == card.Path;
        context.DrawEllipse(hot ? _closeFill : new SolidColorBrush(Color.Parse("#E7D7C4")), null, card.Close.Center, 8, 8);
        var pen = new Pen(_closeInk, 1.4);
        var c = card.Close.Center;
        context.DrawLine(pen, c + new Vector(-3, -3), c + new Vector(3, 3));
        context.DrawLine(pen, c + new Vector(3, -3), c + new Vector(-3, 3));
    }

    Bitmap? ImageFor(string path)
    {
        if (_images.TryGetValue(path, out var cached))
            return cached;
        try
        {
            var bytes = File.ReadAllBytes(path);
            using var stream = new MemoryStream(bytes);
            var bitmap = new Bitmap(stream);
            _images[path] = bitmap;
            return bitmap;
        }
        catch
        {
            return null;
        }
    }

    static double Distance(Point a, Point b)
    {
        var dx = a.X - b.X;
        var dy = a.Y - b.Y;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    sealed record CardGeom(string Path, double Anchor, Rect Body, Rect Close, double RopeY);
}
