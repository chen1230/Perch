namespace Perch;

public sealed record Clip(Guid Id, string Text, DateTimeOffset At);

public sealed class ClipBook
{
    public const int Limit = 100;
    public const int MaxCharacters = 50_000;

    readonly List<Clip> _items = new();

    public IReadOnlyList<Clip> Items => _items;

    public void ReplaceAll(IEnumerable<Clip> clips)
    {
        _items.Clear();
        foreach (var clip in clips)
        {
            if (string.IsNullOrWhiteSpace(clip.Text) || _items.Count >= Limit)
                continue;
            var text = clip.Text.Length > MaxCharacters ? clip.Text[..MaxCharacters] : clip.Text;
            _items.Add(clip with { Text = text });
        }
    }

    public Clip? Remember(string? text, DateTimeOffset at)
    {
        if (string.IsNullOrWhiteSpace(text))
            return null;
        text = text.Replace("\0", "");
        if (text.Length > MaxCharacters)
            text = text[..MaxCharacters];
        var existing = _items.FindIndex(c => c.Text == text);
        if (existing >= 0)
        {
            var moved = _items[existing] with { At = at };
            _items.RemoveAt(existing);
            _items.Insert(0, moved);
            return moved;
        }

        var clip = new Clip(Guid.NewGuid(), text, at);
        _items.Insert(0, clip);
        if (_items.Count > Limit)
            _items.RemoveAt(_items.Count - 1);
        return clip;
    }

    public bool Remove(Guid id)
    {
        var index = _items.FindIndex(c => c.Id == id);
        if (index < 0)
            return false;
        _items.RemoveAt(index);
        return true;
    }

    public static IReadOnlyList<Clip> Filter(IReadOnlyList<Clip> items, string? query)
    {
        if (string.IsNullOrWhiteSpace(query))
            return items.ToList();
        return items.Where(c => Matches(c.Text, query)).ToList();
    }

    public static bool Matches(string text, string query)
    {
        var parts = Split(query);
        return parts.Length > 0 && parts.All(part => text.Contains(part, StringComparison.CurrentCultureIgnoreCase));
    }

    public static string Snippet(string text, string? query, int limit = 240, int lead = 32)
    {
        var flat = string.Join(' ', text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (flat.Length <= limit)
            return flat;
        if (string.IsNullOrWhiteSpace(query))
            return flat[..limit] + "…";

        var hit = -1;
        foreach (var part in Split(query))
        {
            hit = flat.IndexOf(part, StringComparison.CurrentCultureIgnoreCase);
            if (hit >= 0)
                break;
        }

        if (hit < 0)
            return flat[..limit] + "…";

        var start = Math.Max(0, hit - lead);
        var end = Math.Min(flat.Length, start + limit);
        if (end - start < limit)
            start = Math.Max(0, end - limit);
        var slice = flat[start..end];
        if (start > 0)
            slice = "…" + slice;
        if (end < flat.Length)
            slice += "…";
        return slice;
    }

    public static List<(int Start, int Length)> Ranges(string snippet, string? query)
    {
        var found = new List<(int Start, int Length)>();
        if (string.IsNullOrWhiteSpace(query) || snippet.Length == 0)
            return found;

        foreach (var part in Split(query))
        {
            var cursor = 0;
            while (cursor < snippet.Length)
            {
                var index = snippet.IndexOf(part, cursor, StringComparison.CurrentCultureIgnoreCase);
                if (index < 0)
                    break;
                found.Add((index, part.Length));
                var next = index + Math.Max(part.Length, 1);
                if (next <= cursor)
                    break;
                cursor = next;
            }
        }

        return Merge(found);
    }

    public static int SelectionAfterDelete(int selection, int countAfter)
    {
        if (countAfter <= 0)
            return 0;
        if (selection < 0)
            return 0;
        if (selection >= countAfter)
            return countAfter - 1;
        return selection;
    }

    static string[] Split(string query) =>
        query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    static List<(int Start, int Length)> Merge(List<(int Start, int Length)> ranges)
    {
        if (ranges.Count == 0)
            return ranges;
        var ordered = ranges.OrderBy(r => r.Start).ThenByDescending(r => r.Length).ToList();
        var merged = new List<(int Start, int Length)>();
        var (start, length) = ordered[0];
        for (var i = 1; i < ordered.Count; i++)
        {
            var range = ordered[i];
            var end = start + length;
            if (range.Start <= end)
            {
                var newEnd = Math.Max(end, range.Start + range.Length);
                length = newEnd - start;
            }
            else
            {
                merged.Add((start, length));
                (start, length) = range;
            }
        }

        merged.Add((start, length));
        return merged;
    }
}
