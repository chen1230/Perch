using Perch;
using Xunit;

namespace Perch.Windows.Tests;

public class ClipBookTests
{
    [Fact]
    public void Remember_moves_duplicate_to_front()
    {
        var book = new ClipBook();
        var first = book.Remember("alpha", DateTimeOffset.UnixEpoch);
        book.Remember("beta", DateTimeOffset.UnixEpoch.AddMinutes(1));
        var again = book.Remember("alpha", DateTimeOffset.UnixEpoch.AddMinutes(2));

        Assert.Equal(2, book.Items.Count);
        Assert.Equal(first!.Id, again!.Id);
        Assert.Equal("alpha", book.Items[0].Text);
        Assert.Equal("beta", book.Items[1].Text);
    }

    [Fact]
    public void Remember_caps_at_default_text_capacity()
    {
        var book = new ClipBook();
        for (var i = 0; i < ClipBook.Limit + 5; i++)
            book.Remember($"item-{i}", DateTimeOffset.UnixEpoch.AddSeconds(i));

        Assert.Equal(ClipBook.Limit, book.Items.Count);
        Assert.Equal($"item-{ClipBook.Limit + 4}", book.Items[0].Text);
        Assert.DoesNotContain(book.Items, clip => clip.Text == "item-0");
    }

    [Fact]
    public void Empty_query_returns_every_clip_and_no_highlight()
    {
        var book = new ClipBook();
        book.Remember("Config", DateTimeOffset.UnixEpoch);
        book.Remember("other", DateTimeOffset.UnixEpoch);
        var all = ClipBook.Filter(book.Items, "  ");

        Assert.Equal(2, all.Count);
        Assert.Empty(ClipBook.Ranges("Config", ""));
        Assert.Empty(ClipBook.Ranges("Config", "   "));
    }

    [Fact]
    public void Search_matches_each_word_and_marks_every_hit()
    {
        Assert.True(ClipBook.Matches("Hello Config", "config hello"));
        Assert.False(ClipBook.Matches("only one", "one two"));
        var ranges = ClipBook.Ranges("aa aa", "aa");
        Assert.Equal(2, ranges.Count);
        Assert.Equal((0, 2), ranges[0]);
        Assert.Equal((3, 2), ranges[1]);
    }

    [Fact]
    public void Snippet_includes_a_hit_near_the_end()
    {
        var text = new string('x', 400) + "Config";
        var snippet = ClipBook.Snippet(text, "Config");
        Assert.Contains("Config", snippet, StringComparison.Ordinal);
        Assert.True(snippet.Length < text.Length);
    }

    [Fact]
    public void Delete_selection_falls_forward_then_back()
    {
        Assert.Equal(1, ClipBook.SelectionAfterDelete(1, 2));
        Assert.Equal(1, ClipBook.SelectionAfterDelete(2, 2));
        Assert.Equal(0, ClipBook.SelectionAfterDelete(0, 0));
    }

    [Fact]
    public void Remove_drops_one_record()
    {
        var book = new ClipBook();
        var keep = book.Remember("keep", DateTimeOffset.UnixEpoch);
        var drop = book.Remember("drop", DateTimeOffset.UnixEpoch);
        Assert.True(book.Remove(drop!.Id));
        Assert.False(book.Remove(drop.Id));
        Assert.Equal(new[] { keep!.Id }, book.Items.Select(clip => clip.Id));
    }
}
