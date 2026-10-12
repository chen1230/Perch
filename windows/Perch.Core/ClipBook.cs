namespace Perch;

public sealed record Clip(Guid Id, string Text, DateTimeOffset At,
    string? Source = null, string? ImagePath = null, string? ImageKey = null,
    int Width = 0, int Height = 0, long Bytes = 0, DateTimeOffset? LastUsed = null)
{
    public bool IsImage => ImagePath != null;
}

public sealed class ClipBook
{
    public const int Limit = 1000;
    public const int MaxCharacters = 50_000;
    readonly List<Clip> _items = new();
    public IReadOnlyList<Clip> Items => _items;
    public int TextLimit { get; private set; } = Limit;
    public int ImageLimit { get; private set; } = 100;

    public void SetLimits(int text, int images)
    {
        TextLimit = Math.Clamp(text, 1, 10_000);
        ImageLimit = Math.Clamp(images, 1, 1000);
        Trim();
    }

    public void ReplaceAll(IEnumerable<Clip> clips)
    {
        _items.Clear();
        _items.AddRange(clips.Where(c => c.IsImage || !string.IsNullOrWhiteSpace(c.Text))
            .Select(c => c with { Text = c.Text.Length > MaxCharacters ? c.Text[..MaxCharacters] : c.Text })
            .DistinctBy(c => c.Id));
        Trim();
    }

    public Clip? Remember(string? text, DateTimeOffset at, string? source = null)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        text = text.Replace("\0", "");
        if (text.Length > MaxCharacters) text = text[..MaxCharacters];
        if (string.IsNullOrWhiteSpace(text)) return null;
        var clip = _items.FirstOrDefault(c => !c.IsImage && c.Text == text)
            ?? new Clip(Guid.NewGuid(), text, at);
        clip = clip with { At = at, Source = source };
        _items.RemoveAll(c => c.Id == clip.Id);
        _items.Insert(0, clip);
        Trim();
        return clip;
    }

    public Clip RememberImage(string path, string key, int width, int height, long bytes,
        DateTimeOffset at, string? source = null)
    {
        var clip = _items.FirstOrDefault(c => c.IsImage && c.ImageKey == key)
            ?? new Clip(Guid.NewGuid(), "", at, ImagePath: path, ImageKey: key,
                Width: width, Height: height, Bytes: bytes);
        clip = clip with { At = at, LastUsed = at, Source = source };
        _items.RemoveAll(c => c.Id == clip.Id);
        _items.Insert(0, clip);
        Trim();
        return clip;
    }

    public void Touch(Guid id, DateTimeOffset at)
    {
        var index = _items.FindIndex(c => c.Id == id && c.IsImage);
        if (index >= 0) _items[index] = _items[index] with { LastUsed = at };
    }

    public bool Remove(Guid id) => _items.RemoveAll(c => c.Id == id) > 0;

    public Guid? Restore(Clip clip)
    {
        var existing = _items.FirstOrDefault(c => c.Id == clip.Id ||
            (clip.IsImage ? c.IsImage && c.ImageKey == clip.ImageKey : !c.IsImage && c.Text == clip.Text));
        if (existing != null) return existing.Id;
        _items.Add(clip);
        Trim();
        return _items.Any(c => c.Id == clip.Id) ? clip.Id : null;
    }

    void Trim()
    {
        var images = _items.Where(c => c.IsImage).OrderByDescending(c => c.LastUsed ?? c.At)
            .ThenByDescending(c => c.At).Take(ImageLimit).Select(c => c.Id).ToHashSet();
        var text = _items.Where(c => !c.IsImage).OrderByDescending(c => c.At)
            .Take(TextLimit).Select(c => c.Id).ToHashSet();
        _items.RemoveAll(c => c.IsImage ? !images.Contains(c.Id) : !text.Contains(c.Id));
        _items.Sort((a, b) => b.At.CompareTo(a.At));
    }

    public static IReadOnlyList<Clip> Filter(IReadOnlyList<Clip> items, string? query)
    {
        if (string.IsNullOrWhiteSpace(query)) return items.ToList();
        return items.Where(c => !c.IsImage && Matches(c.Text, query)).ToList();
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
