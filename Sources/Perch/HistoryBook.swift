import Foundation

struct HistoryClip: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var date: Date
    var source: String?
    var imageFilename: String?
    var imageKey: String?
    var width: Int?
    var height: Int?
    var bytes: Int?
    var lastUsed: Date?
    var isImage: Bool { imageFilename != nil }
}

enum HistoryGroup: Equatable {
    case today, yesterday, week, month
    case older(year: Int, month: Int)
}

/// Copy order drives the list; image access order independently drives eviction.
struct HistoryBook {
    private(set) var items: [HistoryClip]
    private(set) var textLimit: Int
    private(set) var imageLimit: Int
    static let maxCharacters = 50_000

    init(items: [HistoryClip] = [], textLimit: Int = 1000, imageLimit: Int = 100) {
        self.items = items
        self.textLimit = max(1, min(10_000, textLimit))
        self.imageLimit = max(1, min(1000, imageLimit))
        trim()
    }

    mutating func setLimits(text: Int, images: Int) {
        textLimit = max(1, min(10_000, text))
        imageLimit = max(1, min(1000, images))
        trim()
    }

    mutating func rememberText(_ text: String, at: Date = Date(), source: String? = nil) -> HistoryClip? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let text = String(text.prefix(Self.maxCharacters))
        var clip = items.first { !$0.isImage && $0.text == text }
            ?? HistoryClip(id: UUID(), text: text, date: at)
        clip.date = at
        clip.source = source
        items.removeAll { $0.id == clip.id }
        items.insert(clip, at: 0)
        trim()
        return clip
    }

    mutating func rememberImage(key: String, filename: String, width: Int, height: Int, bytes: Int,
                                at: Date = Date(), source: String? = nil) -> HistoryClip {
        var clip = items.first { $0.isImage && $0.imageKey == key }
            ?? HistoryClip(id: UUID(), text: "", date: at, imageFilename: filename,
                           imageKey: key, width: width, height: height, bytes: bytes)
        clip.date = at
        clip.lastUsed = at
        clip.source = source
        items.removeAll { $0.id == clip.id }
        items.insert(clip, at: 0)
        trim()
        return clip
    }

    mutating func touch(_ id: UUID, at: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].isImage else { return }
        items[i].lastUsed = at
    }

    mutating func remove(_ id: UUID) -> HistoryClip? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    @discardableResult
    mutating func restore(_ clip: HistoryClip) -> UUID? {
        if let existing = items.first(where: {
            $0.id == clip.id || (clip.isImage ? $0.isImage && $0.imageKey == clip.imageKey : !$0.isImage && $0.text == clip.text)
        }) { return existing.id }
        items.append(clip)
        trim()
        return items.contains(where: { $0.id == clip.id }) ? clip.id : nil
    }

    func matches(_ query: String) -> [HistoryClip] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { !$0.isImage && words.allSatisfy($0.text.localizedStandardContains) }
    }

    private mutating func trim() {
        items.sort { $0.date > $1.date }
        let images = items.filter(\.isImage).sorted {
            let a = $0.lastUsed ?? $0.date, b = $1.lastUsed ?? $1.date
            return a == b ? $0.date > $1.date : a > b
        }
        let keepImages = Set(images.prefix(imageLimit).map(\.id))
        var texts = 0
        items = items.filter { clip in
            if clip.isImage { return keepImages.contains(clip.id) }
            guard !clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            texts += 1
            return texts <= textLimit
        }
    }

    static func group(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> HistoryGroup {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .yesterday
        case 2..<7: return .week
        case 7..<30: return .month
        default: return .older(year: calendar.component(.year, from: date), month: calendar.component(.month, from: date))
        }
    }
}
