import XCTest
@testable import Perch

final class HistoryBookTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1000)
    func testDefaultAndIndependentLimits() {
        var book = HistoryBook(textLimit: 2, imageLimit: 1)
        XCTAssertEqual(HistoryBook().textLimit, 1000)
        XCTAssertEqual(HistoryBook().imageLimit, 100)
        _ = book.rememberText("alpha", at: start)
        _ = book.rememberText("beta", at: start.addingTimeInterval(1))
        _ = book.rememberImage(key: "a", filename: "a.png", width: 10, height: 20, bytes: 30, at: start)
        _ = book.rememberImage(key: "b", filename: "b.png", width: 10, height: 20, bytes: 30, at: start.addingTimeInterval(1))
        XCTAssertEqual(book.items.filter { !$0.isImage }.count, 2)
        XCTAssertEqual(book.items.filter(\.isImage).map(\.imageKey), ["b"])
    }
    func testViewingProtectsOldImageWithoutChangingCopyDate() {
        var book = HistoryBook(imageLimit: 2)
        let a = book.rememberImage(key: "a", filename: "a.png", width: 1, height: 1, bytes: 1, at: start)
        _ = book.rememberImage(key: "b", filename: "b.png", width: 1, height: 1, bytes: 1, at: start.addingTimeInterval(1))
        book.touch(a.id, at: start.addingTimeInterval(2))
        _ = book.rememberImage(key: "c", filename: "c.png", width: 1, height: 1, bytes: 1, at: start.addingTimeInterval(3))
        XCTAssertEqual(Set(book.items.compactMap(\.imageKey)), ["a", "c"])
        XCTAssertEqual(book.items.first { $0.id == a.id }?.date, start)
    }
    func testDuplicateAndShrinkPreserveMostRecentUsage() throws {
        var book = HistoryBook(imageLimit: 2)
        let a = book.rememberImage(key: "a", filename: "a.png", width: 1, height: 1, bytes: 1, at: start)
        _ = book.rememberImage(key: "b", filename: "b.png", width: 1, height: 1, bytes: 1, at: start.addingTimeInterval(1))
        let again = book.rememberImage(key: "a", filename: "unused.png", width: 1, height: 1, bytes: 1, at: start.addingTimeInterval(2))
        XCTAssertEqual(a.id, again.id)
        XCTAssertEqual(again.imageFilename, "a.png")
        book.setLimits(text: 1000, images: 1)
        let decoded = try JSONDecoder().decode([HistoryClip].self, from: JSONEncoder().encode(book.items))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.id, a.id)
        XCTAssertEqual(decoded.first?.lastUsed, start.addingTimeInterval(2))
    }
    func testLegacyTextDecodesAndMultiwordSearchExcludesImages() throws {
        let id = UUID()
        let json = "[{\"id\":\"\(id)\",\"text\":\"Hello Config\",\"date\":1000}]"
        let clips = try JSONDecoder().decode([HistoryClip].self, from: Data(json.utf8))
        var book = HistoryBook(items: clips)
        _ = book.rememberImage(key: "i", filename: "i.png", width: 1, height: 1, bytes: 1, at: start)
        XCTAssertEqual(book.matches("config hello").map(\.id), [id])
        XCTAssertEqual(book.matches("missing").count, 0)
        XCTAssertEqual(book.matches(" ").count, 2)
    }
    func testTextEvictionAndDeleteRestore() {
        var book = HistoryBook(textLimit: 2)
        let a = book.rememberText("a", at: start)!
        _ = book.rememberText("b", at: start.addingTimeInterval(1))
        book.touch(a.id, at: start.addingTimeInterval(10))
        _ = book.rememberText("c", at: start.addingTimeInterval(2))
        XCTAssertFalse(book.items.contains { $0.id == a.id })
        let removed = book.remove(book.items[0].id)!
        book.restore(removed)
        XCTAssertTrue(book.items.contains { $0.id == removed.id })
    }
    func testUndoAfterRecopyDoesNotDuplicateImage() {
        var book = HistoryBook()
        let first = book.rememberImage(key: "same", filename: "same.png", width: 1, height: 1, bytes: 1, at: start)
        let removed = book.remove(first.id)!
        let newer = book.rememberImage(key: "same", filename: "same.png", width: 1, height: 1, bytes: 1, at: start.addingTimeInterval(1))
        book.restore(removed)
        XCTAssertEqual(book.items.count, 1)
        XCTAssertEqual(book.items.first?.id, newer.id)
    }

    func testDateGroupsAreExclusiveAcrossYear() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = cal.date(from: DateComponents(year: 2026, month: 1, day: 2))!
        XCTAssertEqual(HistoryBook.group(for: today, now: today, calendar: cal), .today)
        XCTAssertEqual(HistoryBook.group(for: today.addingTimeInterval(-86400), now: today, calendar: cal), .yesterday)
        XCTAssertEqual(HistoryBook.group(for: today.addingTimeInterval(-86400 * 3), now: today, calendar: cal), .week)
        XCTAssertEqual(HistoryBook.group(for: today.addingTimeInterval(-86400 * 20), now: today, calendar: cal), .month)
        XCTAssertEqual(HistoryBook.group(for: today.addingTimeInterval(-86400 * 40), now: today, calendar: cal), .older(year: 2025, month: 11))
    }
}
