import AppKit
import AVFoundation
import Combine
import os

let log = Logger(subsystem: "app.perch.Perch", category: "line")

/// One screenshot hanging on the line.
struct Pegged: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var thumb: NSImage
    /// Every photo hangs a little crooked, like on a real line.
    let tilt = Double.random(in: -2.5...2.5)
    var falling = false
    /// Still flying in from where it was captured; the card waits hidden.
    var flying = false
    /// Where this photo hangs, as a fraction of the usable rope. Nil means it
    /// still takes part in the even spacing and has not been slid by hand.
    var anchor: CGFloat?
    /// A screen recording rather than a screenshot.
    var isRecording: Bool { Perch.isRecording(url) }

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.flying == b.flying
            && a.anchor == b.anchor && a.thumb === b.thumb
    }
}

/// The line itself: what hangs on it and what you can do with each item.
/// The files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    @Published private(set) var items: [Pegged] = []
    @Published private(set) var gust = 0
    @Published var copiedID: UUID?
    @Published var draggingID: UUID?
    /// The clip currently off the rope, following the pointer. Distinct from
    /// `draggingID`, which is a file drag and fades the photo.
    @Published var slidingID: UUID?
    /// Layout x the carried photo hangs from until it is dropped or put back.
    private(set) var carryBaseX: CGFloat = 0
    /// Shift from `carryBaseX` while the clip is in hand, in line coordinates.
    @Published private(set) var carryOffset: CGSize = .zero
    /// Letting go: ease onto the rope, or back to where it was taken from.
    @Published private(set) var carrySettling = false
    /// Where each arranged photo is drawn. This can be tighter than the saved
    /// anchors when the screen is too narrow to honor them; it is not saved.
    @Published private(set) var placed: [UUID: CGFloat] = [:]
    @Published var pressedID: UUID?
    /// Whether the line has slid down into view.
    @Published var revealed = false

    /// Card and clip frames in window coordinates, reported by the views. The
    /// panel uses them to only catch clicks over a photo or its clip.
    var hitRects: [UUID: [CGRect]] = [:]

    var maxItems = 8


    var soundOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }

    private let storeKey = "pegged"
    private let placementsKey = "peggedPlacements"
    /// Last width the line was laid out in. New photos need it to settle
    /// into a gap without waiting for the next resize.
    private var layoutWidth: CGFloat = 0
    /// Bumps whenever a new carry starts, so a late settle cannot clear it.
    private var carryGeneration = 0

    init() {
        restore()
        scheduleGust()
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false) -> UUID? {
        guard !items.contains(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return nil }
        var item = Pegged(url: url, thumb: thumb)
        item.flying = flying
        if isArranged {
            let taken = items.compactMap { !$0.falling ? $0.anchor : nil }
            item.anchor = PegLayout.largestGapAnchor(existing: taken)
        }
        items.append(item)
        if item.anchor != nil { refreshPlacement() }
        // A full line lets the oldest photo fall off the far end. Only one: a
        // line hung on a wider screen keeps its length here instead of losing
        // several photos to a single capture.
        if liveCount > maxItems, let oldest = items.first(where: { !$0.falling }) {
            letGo(oldest.id)
        }
        save()
        if !quietly { play("Tink", volume: 0.35) }
        return item.id
    }

    /// The capture has reached the line: the real card takes over.
    func land(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].flying = false
    }

    /// Called just before a photo starts falling, so the fall can be drawn
    /// over the whole screen.
    var onFall: ((Pegged) -> Void)?

    func drop(_ id: UUID, quietly: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        onFall?(items[i])
        items[i].falling = true
        hitRects[id] = nil
        save()
        if !quietly { play("Pop", volume: 0.25) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    /// "Take everything down": every photo goes the way of its corner cross.
    func clear() {
        let live = items.filter { !$0.falling }
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.discard(item.id, quietly: n > 0)
            }
        }
    }

    /// Photos whose file was deleted or moved away fall off by themselves.
    func prune() {
        for item in items where !item.falling && !FileManager.default.fileExists(atPath: item.url.path) {
            drop(item.id, quietly: true)
        }
    }

    // MARK: Actions on one photo

    func copy(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let entry = NSPasteboardItem()
        // A recording is copied as the file, which apps paste as the video.
        if !item.isRecording, let png = pngData(item.url) { entry.setData(png, forType: .png) }
        entry.setString(item.url.absoluteString, forType: .fileURL)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([entry])

        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }

    func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.open(item.url)
    }

    /// Moves the file to the Trash and takes the photo off the line. When a
    /// drag ends on the Dock's Trash, macOS only reports it: deleting the file
    /// is the source app's job, as Finder does.
    @discardableResult
    func trash(_ id: UUID, quietly: Bool = false) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            log.notice("Trashed \(item.url.lastPathComponent, privacy: .public)")
            if soundOn && !quietly { Line.trashSound?.play() }
            drop(id, quietly: true)
            return true
        } catch {
            log.error("Could not trash \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if !quietly { NSSound.beep() }
            return false
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    /// Whether the file lives in Perch's own folder. Those are discarded
    /// to the Trash, or the folder would fill up with forgotten screenshots.
    /// Files anywhere else, like the Desktop, stay where they are.
    func isInInbox(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return item.url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    /// The corner cross and "Take down" both end up here.
    func discard(_ id: UUID, quietly: Bool = false) {
        if isInInbox(id) { trash(id, quietly: quietly) } else { drop(id, quietly: quietly) }
    }

    /// The oldest photo falling off a full line. Like the cross, a file from
    /// Perch's folder goes to the Trash, or nothing would ever take it out
    /// of that folder. If the Trash refuses it, it still leaves the line.
    private func letGo(_ id: UUID) {
        if isInInbox(id), trash(id, quietly: true) { return }
        drop(id, quietly: true)
    }

    /// Inbox mode: keep a screenshot by moving it to the Desktop.
    func saveToDesktop(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let target = uniqueURL(in: desktop, for: item.url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            drop(id, quietly: true)
        } catch {
            log.error("Could not save to Desktop: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Long press: open the photo in the system Markup editor. Markup does
    /// not edit video, so a recording opens in the trimming editor instead.
    func markup(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.isRecording {
            Trim.shared.edit(item.url, size: item.thumb.size)
        } else {
            Markup.shared.edit(item.url)
        }
    }

    /// After editing, the photo on the line shows the new version.
    func reloadThumbnail(for url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return }
        items[i].thumb = thumb
    }

    /// After a change of size, every photo is redrawn sharp at the new one.
    func reloadThumbnails() {
        for i in items.indices where !items[i].falling {
            if let thumb = makeThumbnail(items[i].url) { items[i].thumb = thumb }
        }
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Breeze

    /// Every so often a little wind moves the line. It is the detail that
    /// makes it feel like an object and not a widget.
    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil && self.slidingID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Taking a clip off the rope

    private var isArranged: Bool {
        items.contains { !$0.falling && $0.anchor != nil }
    }

    /// The pointer has lifted this clip off the rope. Nothing is saved yet:
    /// letting go away from the rope puts it back.
    func beginCarry(_ id: UUID, width: CGFloat) {
        guard width > 1, !carrySettling,
              let index = items.firstIndex(where: { $0.id == id && !$0.falling }) else { return }
        guard slidingID != id else { return }
        carryGeneration += 1
        layoutWidth = width
        let anchor = displayAnchor(for: id)
        carryBaseX = Layout.placedX(anchor: anchor, index: index, count: items.count, width: width)
        carryOffset = .zero
        carrySettling = false
        slidingID = id
    }

    func moveCarry(_ id: UUID, translation: CGSize) {
        guard slidingID == id, !carrySettling else { return }
        carryOffset = translation
    }

    /// Near the rope, the clip hangs at the drop and neighbors ease aside.
    /// Anywhere else, it goes back to the place it was lifted from.
    func endCarry(_ id: UUID, translation: CGSize, width: CGFloat) {
        guard slidingID == id, !carrySettling, width > 1 else { return }
        layoutWidth = width
        let dropX = carryBaseX + translation.width
        let slotY = Layout.ropeY(x: carryBaseX, width: width) - Layout.pinAbove + Layout.pinSlot + translation.height
        if Layout.caughtRope(slotY: slotY, x: dropX, width: width),
           let index = items.firstIndex(where: { $0.id == id && !$0.falling }) {
            let fromY = Layout.centerY(ropeY: Layout.ropeY(x: carryBaseX, width: width))
            freezeAnchors(width: width)
            items[index].anchor = PegLayout.anchor(x: dropX, width: width, margin: Layout.edgeMargin)
            applyResolution(width: width)
            var drawn: [UUID: CGFloat] = [:]
            for item in items where !item.falling {
                if let anchor = item.anchor { drawn[item.id] = anchor }
            }
            placed = drawn
            let resolvedX = PegLayout.x(anchor: items[index].anchor ?? 0.5, width: width, margin: Layout.edgeMargin)
            let toY = Layout.centerY(ropeY: Layout.ropeY(x: resolvedX, width: width))
            carryBaseX = resolvedX
            carryOffset = CGSize(width: dropX - resolvedX, height: fromY + translation.height - toY)
            save()
        }
        settleBack()
    }

    /// Ease `carryOffset` to zero, then let the line be a strip again.
    private func settleBack() {
        carryGeneration += 1
        let generation = carryGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.carryGeneration == generation else { return }
            self.carrySettling = true
            self.carryOffset = .zero
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { [weak self] in
            guard let self, self.carryGeneration == generation else { return }
            self.slidingID = nil
            self.carrySettling = false
            self.carryOffset = .zero
            self.refreshPlacement()
        }
    }

    /// Anchor used to draw and to fly a capture onto the line. A narrow screen
    /// may draw photos closer than the saved anchors; that adjustment lives
    /// in `placed` and is not itself saved.
    func displayAnchor(for id: UUID) -> CGFloat? {
        placed[id] ?? items.first { $0.id == id }?.anchor
    }

    /// Forget hand-placed positions. The line goes back to even spacing.
    func spaceEvenly() {
        guard slidingID == nil else { return }
        var changed = false
        for index in items.indices where items[index].anchor != nil {
            items[index].anchor = nil
            changed = true
        }
        if changed {
            placed = [:]
            save()
        }
    }

    /// Remember the width and recompute the drawn positions. Saved anchors
    /// stay as the user left them.
    func noteWidth(_ width: CGFloat) {
        guard width > 1 else { return }
        layoutWidth = width
        refreshPlacement()
    }

    /// Pack the drawn row after a size change. Does not write anchors.
    func reflow() {
        refreshPlacement()
    }

    private func refreshPlacement() {
        guard layoutWidth > 1, slidingID == nil, isArranged else {
            if slidingID == nil, !placed.isEmpty { placed = [:] }
            return
        }
        let slots = items.compactMap { item -> PegSlot? in
            guard !item.falling, let anchor = item.anchor else { return nil }
            return PegSlot(id: item.id, anchor: anchor, dragged: false)
        }
        let resolved = PegLayout.resolve(slots: slots, width: layoutWidth,
                                         margin: Layout.edgeMargin, gap: Layout.minGap)
        if !sameAnchors(placed, resolved) { placed = resolved }
    }

    private func sameAnchors(_ a: [UUID: CGFloat], _ b: [UUID: CGFloat]) -> Bool {
        guard a.count == b.count else { return false }
        for (id, value) in a {
            guard let other = b[id], abs(value - other) < 0.0001 else { return false }
        }
        return true
    }

    private func freezeAnchors(width: CGFloat) {
        let count = items.count
        for index in items.indices where !items[index].falling && items[index].anchor == nil {
            let x = Layout.x(index: index, count: count, width: width)
            items[index].anchor = PegLayout.anchor(x: x, width: width, margin: Layout.edgeMargin)
        }
    }

    @discardableResult
    private func applyResolution(width: CGFloat) -> Bool {
        let slots = items.compactMap { item -> PegSlot? in
            guard !item.falling, let anchor = item.anchor else { return nil }
            return PegSlot(id: item.id, anchor: anchor, dragged: item.id == slidingID)
        }
        let resolved = PegLayout.resolve(slots: slots, width: width,
                                         margin: Layout.edgeMargin, gap: Layout.minGap)
        var changed = false
        for index in items.indices {
            guard let next = resolved[items[index].id], let current = items[index].anchor else { continue }
            if abs(current - next) > 0.0001 {
                items[index].anchor = next
                changed = true
            }
        }
        return changed
    }

    // MARK: Persistence

    private struct Placement: Codable {
        var path: String
        var anchor: Double?
    }

    private func save() {
        let live = items.filter { !$0.falling }
        UserDefaults.standard.set(live.map(\.url.path), forKey: storeKey)
        let placements = live.map { Placement(path: $0.url.path, anchor: $0.anchor.map(Double.init)) }
        if let data = try? JSONEncoder().encode(placements) {
            UserDefaults.standard.set(data, forKey: placementsKey)
        }
    }

    /// Everything comes back as it was. This runs before the line knows its
    /// screen, so the capacity is still the default one: hanging through
    /// `hang` would let photos fall off a wide screen's line at every launch.
    private func restore() {
        if let data = UserDefaults.standard.data(forKey: placementsKey),
           let placements = try? JSONDecoder().decode([Placement].self, from: data) {
            restore(placements)
            return
        }
        let paths = UserDefaults.standard.stringArray(forKey: storeKey) ?? []
        restore(paths.map { Placement(path: $0, anchor: nil) })
    }

    private func restore(_ placements: [Placement]) {
        for placement in placements where FileManager.default.fileExists(atPath: placement.path) {
            let url = URL(fileURLWithPath: placement.path)
            guard !items.contains(where: { $0.url == url }), let thumb = makeThumbnail(url) else { continue }
            var item = Pegged(url: url, thumb: thumb)
            if let anchor = placement.anchor {
                item.anchor = CGFloat(min(1, max(0, anchor)))
            }
            items.append(item)
        }
    }

    // MARK: Helpers

    private func play(_ name: String, volume: Float) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Screen recordings, as macOS saves them.
func isRecording(_ url: URL) -> Bool {
    ["mov", "mp4"].contains(url.pathExtension.lowercased())
}

/// The default size covers a card at twice its size in points, as on a
/// Retina screen, and no more: every photo on the line keeps one in memory.
func makeThumbnail(_ url: URL, maxPixels: Int = Int(320 * Layout.size.scale)) -> NSImage? {
    if isRecording(url) { return firstFrame(url, maxPixels: maxPixels) }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

/// A recording shows its first frame.
private func firstFrame(_ url: URL, maxPixels: Int) -> NSImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
    guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
