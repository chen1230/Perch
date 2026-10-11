using Perch;
using Xunit;

namespace Perch.Windows.Tests;

public class LineBookTests
{
    [Fact]
    public void Add_does_not_duplicate_a_path()
    {
        var book = new LineBook();
        book.Add("/shots/a.png");
        book.Add("/shots/a.png");
        Assert.Single(book.Items);
    }

    [Fact]
    public void Move_keeps_a_gap_and_clamps_the_edge()
    {
        var book = new LineBook();
        book.Add("/shots/a.png");
        book.Add("/shots/b.png");
        Assert.True(book.TryMove("/shots/b.png", 0.5));
        Assert.True(book.TryMove("/shots/a.png", 0.5));
        var ordered = book.Items.OrderBy(item => item.Anchor).ToList();
        Assert.True(ordered[1].Anchor - ordered[0].Anchor >= LineBook.MinGap - 0.0001);

        Assert.True(book.TryMove("/shots/a.png", 5));
        Assert.InRange(book.Items.Single(item => item.Path.EndsWith("a.png")).Anchor, 0, 1 - LineItem.Edge + 0.0001);
    }

    [Fact]
    public void Add_evicts_the_oldest_past_the_cap()
    {
        var book = new LineBook();
        for (var i = 0; i < LineBook.Cap; i++)
            book.Add($"/shots/{i}.png");
        var evicted = book.Add("/shots/new.png");
        Assert.Equal("/shots/0.png", evicted);
        Assert.Equal(LineBook.Cap, book.Items.Count);
        Assert.Contains(book.Items, item => item.Path == "/shots/new.png");
    }

    [Fact]
    public void Drop_far_from_the_rope_is_rejected()
    {
        Assert.True(LineBook.ShouldPlace(100, 140, 72));
        Assert.False(LineBook.ShouldPlace(300, 140, 72));
    }

    [Fact]
    public void Accent_is_stable_for_a_record()
    {
        var id = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
        Assert.Equal(Themes.AccentHex(ThemeId.Day, id), Themes.AccentHex(ThemeId.Night, id));
        Assert.NotEqual(Themes.AccentHex(ThemeId.Day, id), Themes.AccentHex(ThemeId.Lacquer, id));
        Assert.Equal(Themes.Palette(ThemeId.Day)[0], Themes.AccentHex(ThemeId.Day, Guid.Empty));
    }
}
