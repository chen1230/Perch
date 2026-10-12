import XCTest
@testable import Perch

@MainActor
final class HistoryStorageTests: XCTestCase {
    func testMigrationCapacitySettingsAndOwnedFileCleanup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "PerchTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("text-clips.json")
        let old = [HistoryClip(id: UUID(), text: "keep my original text", date: Date())]
        let original = try JSONEncoder().encode(old)
        try original.write(to: legacy)
        let history = ClipboardHistory(root: root, defaults: defaults)
        XCTAssertEqual(history.items.first?.id, old.first?.id)
        history.setLimits(text: 500, images: 1)
        history.rememberImage(Data([1, 2, 3]), width: 10, height: 20, source: "test")
        let keptImage = history.items.first { $0.isImage }!
        let imageURL = history.imageURL(for: keptImage)!
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        let screenshots = root.appendingPathComponent("Screenshots")
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        let ropeFile = screenshots.appendingPathComponent("independent.png")
        try Data([4]).write(to: ropeFile)
        history.rememberImage(Data([5, 6, 7]), width: 20, height: 30, source: "test")
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ropeFile.path))
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        let reloaded = ClipboardHistory(root: root, defaults: defaults)
        XCTAssertEqual(reloaded.textLimit, 500)
        XCTAssertEqual(reloaded.imageLimit, 1)
        XCTAssertEqual(reloaded.items.count, 2)
        let image = reloaded.items.first { $0.isImage }!
        reloaded.remove(id: image.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reloaded.imageURL(for: image)!.path))
        XCTAssertEqual(reloaded.undoDelete(), image.id)
        XCTAssertTrue(reloaded.items.contains { $0.id == image.id })
    }
    func testUntrustedFilenameCannotLeaveOwnedImageFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history = ClipboardHistory(root: root)
        let clip = HistoryClip(id: UUID(), text: "", date: Date(), imageFilename: "../private.png")
        XCTAssertNil(history.imageURL(for: clip))
    }
}
