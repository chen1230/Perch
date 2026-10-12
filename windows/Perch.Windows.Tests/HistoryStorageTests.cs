using Perch;
using Xunit;
using System.Text.Json;

namespace Perch.Windows.Tests;

public class HistoryStorageTests
{
    static byte[] ImageBytes(byte color)
    {
        using var bitmap = new SkiaSharp.SKBitmap(10, 20);
        bitmap.Erase(new SkiaSharp.SKColor(color, 20, 30));
        using var image = SkiaSharp.SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SkiaSharp.SKEncodedImageFormat.Png, 100);
        return data.ToArray();
    }
    [Fact]
    public void Migration_settings_cleanup_and_undo_keep_independent_files()
    {
        var root = Path.Combine(Path.GetTempPath(), "PerchTest-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        try
        {
            var original = "[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"text\":\"keep me\",\"at\":\"2026-01-01T00:00:00Z\"}]";
            File.WriteAllText(Path.Combine(root, "text-clips.json"), original);
            var shelf = new Shelf(root);
            shelf.Load();
            Assert.Equal("keep me", Assert.Single(shelf.Clips.Items).Text);
            shelf.Clips.SetLimits(500, 1);
            shelf.SaveSettings();
            var a = shelf.RememberImage(ImageBytes(10), "test")!;
            Assert.True(File.Exists(a.ImagePath));
            var rope = Path.Combine(root, "Screenshots", "rope.png");
            File.WriteAllBytes(rope, ImageBytes(10));
            var b = shelf.RememberImage(ImageBytes(30), "test")!;
            Assert.False(File.Exists(a.ImagePath));
            Assert.True(File.Exists(rope));
            Assert.Equal(original, File.ReadAllText(Path.Combine(root, "text-clips.json")));
            var reload = new Shelf(root);
            reload.Load();
            Assert.Equal(500, reload.Clips.TextLimit);
            Assert.Equal(1, reload.Clips.ImageLimit);
            Assert.Equal(2, reload.Clips.Items.Count);
            reload.PendingDelete = b;
            reload.Clips.Remove(b.Id);
            Assert.True(reload.SaveClips());
            Assert.True(File.Exists(b.ImagePath));
            reload.Clips.Restore(b);
            reload.PendingDelete = null;
            Assert.True(reload.SaveClips());
            Assert.Contains(reload.Clips.Items, clip => clip.Id == b.Id);
        }
        finally { Directory.Delete(root, true); }
    }
    [Fact]
    public void Corrupted_metadata_is_backed_up_before_new_history_is_written()
    {
        var root = Path.Combine(Path.GetTempPath(), "PerchTest-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "clipboard-history.json"), "broken original");
            var shelf = new Shelf(root);
            shelf.Load();
            shelf.Clips.Remember("new", DateTimeOffset.Now);
            Assert.True(shelf.SaveClips());
            var backup = Assert.Single(Directory.GetFiles(root, "*.backup.json"));
            Assert.Equal("broken original", File.ReadAllText(backup));
        }
        finally { Directory.Delete(root, true); }
    }
    [Fact]
    public void Lru_usage_survives_disk_restart_and_shrink()
    {
        var root = Path.Combine(Path.GetTempPath(), "PerchTest-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        try
        {
            var shelf = new Shelf(root);
            shelf.Load();
            var a = shelf.RememberImage(ImageBytes(10), "test")!;
            shelf.RememberImage(ImageBytes(20), "test");
            shelf.Clips.Touch(a.Id, DateTimeOffset.Now.AddMinutes(1));
            Assert.True(shelf.SaveClips());
            var loaded = new Shelf(root);
            loaded.Load();
            loaded.Clips.SetLimits(1000, 1);
            loaded.SaveClips();
            Assert.Equal(a.Id, Assert.Single(loaded.Clips.Items).Id);
            Assert.True(File.Exists(a.ImagePath));
        }
        finally { Directory.Delete(root, true); }
    }
}
