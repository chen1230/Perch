namespace Perch;

public sealed class LineItem
{
    public LineItem(string path, double anchor)
    {
        Path = path;
        Anchor = Math.Clamp(anchor, Edge, 1 - Edge);
    }

    public const double Edge = 0.04;

    public string Path { get; }
    public double Anchor { get; set; }
}

public sealed class LineBook
{
    public const int Cap = 16;
    public const double MinGap = 0.07;

    readonly List<LineItem> _items = new();

    public IReadOnlyList<LineItem> Items => _items;

    public void ReplaceAll(IEnumerable<(string Path, double Anchor)> items)
    {
        _items.Clear();
        foreach (var (path, anchor) in items)
        {
            if (string.IsNullOrWhiteSpace(path))
                continue;
            if (_items.Any(item => string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase)))
                continue;
            _items.Add(new LineItem(path, anchor));
            if (_items.Count >= Cap)
                break;
        }
    }

    public string? Add(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            return null;
        if (_items.Any(item => string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase)))
            return null;

        string? evicted = null;
        if (_items.Count >= Cap)
        {
            evicted = _items[0].Path;
            _items.RemoveAt(0);
        }

        _items.Add(new LineItem(path, NextAnchor()));
        PushApart(null);
        return evicted;
    }

    public bool Remove(string path) =>
        _items.RemoveAll(item => string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase)) > 0;

    public bool TryMove(string path, double anchor)
    {
        var item = Find(path);
        if (item == null)
            return false;
        item.Anchor = Math.Clamp(anchor, LineItem.Edge, 1 - LineItem.Edge);
        PushApart(item);
        return true;
    }

    public static bool ShouldPlace(double pointerY, double ropeY, double reach) =>
        Math.Abs(pointerY - ropeY) <= reach;

    LineItem? Find(string path) =>
        _items.FirstOrDefault(item => string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase));

    double NextAnchor()
    {
        if (_items.Count == 0)
            return 0.5;
        var used = _items.Select(item => item.Anchor).OrderBy(anchor => anchor).ToList();
        var bestAt = LineItem.Edge;
        var bestGap = used[0] - LineItem.Edge;
        var previous = LineItem.Edge;
        foreach (var anchor in used)
        {
            var gap = anchor - previous;
            if (gap > bestGap)
            {
                bestGap = gap;
                bestAt = previous + gap / 2;
            }

            previous = anchor;
        }

        var tail = (1 - LineItem.Edge) - used[^1];
        if (tail > bestGap)
            bestAt = used[^1] + tail / 2;
        return Math.Clamp(bestAt, LineItem.Edge, 1 - LineItem.Edge);
    }

    void PushApart(LineItem? keep)
    {
        for (var pass = 0; pass < 8; pass++)
        {
            var ordered = _items.OrderBy(item => item.Anchor).ToList();
            var moved = false;
            for (var i = 1; i < ordered.Count; i++)
            {
                var left = ordered[i - 1];
                var right = ordered[i];
                var gap = right.Anchor - left.Anchor;
                if (gap >= MinGap)
                    continue;
                var need = MinGap - gap;
                if (keep != null && ReferenceEquals(right, keep))
                    left.Anchor = Math.Clamp(left.Anchor - need, LineItem.Edge, 1 - LineItem.Edge);
                else
                    right.Anchor = Math.Clamp(right.Anchor + need, LineItem.Edge, 1 - LineItem.Edge);
                moved = true;
            }

            if (!moved)
                break;
        }
    }
}
