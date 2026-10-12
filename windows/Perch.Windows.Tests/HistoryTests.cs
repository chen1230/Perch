using Perch;
using Xunit;

namespace Perch.Windows.Tests;

public class HistoryTests
{
    readonly DateTimeOffset Start = DateTimeOffset.UnixEpoch;
    [Fact]
    public void Defaults_and_capacities_are_independent()
    {
        var book = new ClipBook();
        Assert.Equal(1000, book.TextLimit);
        Assert.Equal(100, book.ImageLimit);
        book.SetLimits(2, 1);
        book.Remember("a", Start);
        book.Remember("b", Start.AddSeconds(1));
        book.RememberImage("a.png", "a", 10, 20, 30, Start);
        book.RememberImage("b.png", "b", 10, 20, 30, Start.AddSeconds(1));
        Assert.Equal(2, book.Items.Count(c => !c.IsImage));
        Assert.Single(book.Items, c => c.IsImage);
    }
    [Fact]
    public void Viewing_protects_an_old_image_without_changing_copy_time()
    {
        var book = new ClipBook();
        book.SetLimits(1000, 2);
        var a = book.RememberImage("a.png", "a", 1, 1, 1, Start);
        book.RememberImage("b.png", "b", 1, 1, 1, Start.AddSeconds(1));
        book.Touch(a.Id, Start.AddSeconds(2));
        book.RememberImage("c.png", "c", 1, 1, 1, Start.AddSeconds(3));
        Assert.Equal(new[] { "a", "c" }, book.Items.Where(c => c.IsImage).Select(c => c.ImageKey).Order());
        Assert.Equal(Start, book.Items.Single(c => c.Id == a.Id).At);
    }
    [Fact]
    public void Duplicate_and_shrink_keep_recently_used_image()
    {
        var book = new ClipBook();
        var a = book.RememberImage("a.png", "a", 1, 1, 1, Start);
        book.RememberImage("b.png", "b", 1, 1, 1, Start.AddSeconds(1));
        var again = book.RememberImage("unused.png", "a", 1, 1, 1, Start.AddSeconds(2));
        Assert.Equal(a.Id, again.Id);
        Assert.Equal("a.png", again.ImagePath);
        book.SetLimits(1000, 1);
        Assert.Equal(a.Id, Assert.Single(book.Items).Id);
    }
    [Fact]
    public void Text_search_excludes_images_and_legacy_json_survives()
    {
        var json = "{\"Id\":\"00000000-0000-0000-0000-000000000001\",\"Text\":\"hello config\",\"At\":\"2026-01-01T00:00:00Z\"}";
        var old = System.Text.Json.JsonSerializer.Deserialize<Clip>(json)!;
        Assert.False(old.IsImage);
        var book = new ClipBook();
        book.ReplaceAll(new[] { old });
        book.RememberImage("i.png", "i", 1, 1, 1, Start);
        Assert.Equal(old.Id, Assert.Single(ClipBook.Filter(book.Items, "CONFIG hello")).Id);
    }
    [Fact]
    public void Text_capacity_does_not_use_image_lru()
    {
        var book = new ClipBook();
        book.SetLimits(2, 100);
        var a = book.Remember("a", Start)!;
        book.Remember("b", Start.AddSeconds(1));
        book.Touch(a.Id, Start.AddSeconds(10));
        book.Remember("c", Start.AddSeconds(2));
        Assert.DoesNotContain(book.Items, c => c.Id == a.Id);
    }
    [Fact]
    public void Image_lru_survives_serialization()
    {
        var book = new ClipBook();
        var a = book.RememberImage("a.png", "a", 1, 1, 1, Start);
        book.Touch(a.Id, Start.AddSeconds(10));
        book.RememberImage("b.png", "b", 1, 1, 1, Start.AddSeconds(1));
        var decoded = System.Text.Json.JsonSerializer.Deserialize<List<Clip>>(System.Text.Json.JsonSerializer.Serialize(book.Items))!;
        var loaded = new ClipBook();
        loaded.ReplaceAll(decoded);
        loaded.SetLimits(1000, 1);
        Assert.Equal(a.Id, Assert.Single(loaded.Items).Id);
    }
    [Fact]
    public void Undo_after_recopy_does_not_duplicate_image()
    {
        var book = new ClipBook();
        var first = book.RememberImage("same.png", "same", 1, 1, 1, Start);
        book.Remove(first.Id);
        var newer = book.RememberImage("same.png", "same", 1, 1, 1, Start.AddSeconds(1));
        book.Restore(first);
        Assert.Equal(newer.Id, Assert.Single(book.Items).Id);
    }

}
