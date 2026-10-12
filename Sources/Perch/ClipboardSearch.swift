import AppKit
import Carbon
import ImageIO
import SwiftUI

/// A borderless panel that can take the keyboard. The line's panel cannot.
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Glass size, plus the clear margin the shadow is drawn in.
private enum SearchChrome {
    static let glassWidth: CGFloat = 704
    static let glassHeight: CGFloat = 520
    static let margin: CGFloat = 40
    static var windowSize: NSSize {
        NSSize(width: glassWidth + margin * 2, height: glassHeight + margin * 2)
    }
}

/// A search for copied text. It is not a panel that stays on screen: a shortcut
/// or the menu brings it up. Moving the pointer away leaves it up. A click
/// outside the glass, or the window losing the keyboard, closes it.
@MainActor
final class ClipboardSearch: NSObject, NSWindowDelegate {
    static let shared = ClipboardSearch()

    private let model = ClipboardSearchModel()
    private var panel: SearchPanel?
    private var keyMonitor: Any?
    private var outsideMonitor: Any?
    private var localOutsideMonitor: Any?
    private var session = 0
    private var lastToggle = Date.distantPast
    private var closing = false
    private var closeGeneration = 0
    /// Clicks that open the window must not count as a click outside it.
    private var acceptsOutsideClose = false
    /// The app that was in front when the search opened, so a paste returns there.
    private var target: NSRunningApplication?

    func toggle() {
        let now = Date()
        guard now.timeIntervalSince(lastToggle) > 0.25 else { return }
        lastToggle = now
        if panel?.isVisible == true { close() } else { show() }
    }

    private func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { target = front }
        session += 1
        closeGeneration += 1
        acceptsOutsideClose = false
        closing = false
        model.query = ""
        model.selectFirst()
        let panel = ensurePanel()
        place(panel)
        panel.alphaValue = 0
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        installOutsideMonitors()
        DispatchQueue.main.async { [weak self] in self?.acceptsOutsideClose = true }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.panel?.isKeyWindow == true else { return event }
                return self.handle(event) ? nil : event
            }
        }
    }

    private func close(returnFocus: Bool = true) {
        guard let panel, panel.isVisible, !closing else { return }
        closing = true
        acceptsOutsideClose = false
        closeGeneration += 1
        let generation = closeGeneration
        let previous = returnFocus ? target : nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard generation == self.closeGeneration else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.closing = false
                previous?.activate(options: [.activateAllWindows])
            }
        })
    }

    /// A click in the clear margin, or in another app, dismisses the search.
    /// Moving the pointer away does not.
    private func installOutsideMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                self?.closeIfClickIsOutside()
            }
        }
        if localOutsideMonitor == nil {
            localOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.closeIfClickIsOutside()
                return event
            }
        }
    }

    private func closeIfClickIsOutside() {
        guard acceptsOutsideClose, let panel, panel.isVisible, !closing else { return }
        let glass = panel.frame.insetBy(dx: SearchChrome.margin, dy: SearchChrome.margin)
        guard !glass.contains(NSEvent.mouseLocation) else { return }
        close(returnFocus: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        guard acceptsOutsideClose, !closing else { return }
        close(returnFocus: false)
    }

    private func ensurePanel() -> SearchPanel {
        if let panel { return panel }
        let panel = SearchPanel(contentRect: NSRect(origin: .zero, size: SearchChrome.windowSize),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        self.panel = panel
        return panel
    }

    /// The hosting view is created once. A new session still has to reach it,
    /// so the root view is replaced each time the window opens.
    private func place(_ panel: NSPanel) {
        if let screen = LinePanel.screenUnderPointer() {
            panel.setContentSize(NSSize(width: min(SearchChrome.windowSize.width, screen.visibleFrame.width),
                                        height: min(SearchChrome.windowSize.height, screen.visibleFrame.height)))
        }
        let host = NSHostingView(rootView: ClipboardSearchView(model: model, session: session,
            onPaste: { [weak self] clip in self?.paste(clip) }, onClose: { [weak self] in self?.close() }))
        host.sizingOptions = []
        host.clipsToBounds = false
        panel.contentView = host
        guard let screen = LinePanel.screenUnderPointer() else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.midY - size.height / 2 + 36))
    }

    /// Escape and the arrows are handled here. Everything else goes to the field.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            if model.expanded { model.expanded = false; return true }
            close()
            return true
        case 36, 76:
            if let text = model.confirm() { paste(text) }
            return true
        case 125:
            model.move(1)
            return true
        case 126:
            model.move(-1)
            return true
        case UInt16(kVK_ANSI_Z):
            guard event.modifierFlags.contains(.command) else { return false }
            model.undo()
            return true
        case UInt16(kVK_Delete):
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let commandOnly = flags.contains(.command) && flags.isDisjoint(with: [.shift, .option, .control])
            // Plain Delete only edits the search. Command-Delete removes one row,
            // and holding it must not walk the whole list.
            guard commandOnly else { return false }
            if !event.isARepeat { model.deleteSelection() }
            return true
        default:
            return false
        }
    }

    private func paste(_ clip: HistoryClip) {
        guard ClipboardHistory.shared.copyToPasteboard(clip) else { return }
        if !AXIsProcessTrusted() || target == nil || target?.isTerminated == true {
            ClipboardHistory.shared.status = L("Copied. Close, then press Command-V")
            return
        }
        let app = target
        // Leave before sending Command-V, so the keystroke is not typed into this field.
        closing = true
        acceptsOutsideClose = false
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        app?.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let app, !app.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            Self.postPaste()
        }
    }

    /// Command-V into whichever app is now in front.
    private static func postPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class ClipboardSearchModel: ObservableObject {
    @Published var query = ""
    @Published var selectedID: UUID?
    @Published var scrollToken = 0
    @Published var expanded = false
    var matches: [HistoryClip] { ClipboardHistory.shared.matches(query) }
    var selection: Int {
        get { matches.firstIndex { $0.id == selectedID } ?? 0 }
        set { let found = matches; select(found.indices.contains(newValue) ? found[newValue].id : nil) }
    }
    func select(_ id: UUID?) {
        guard selectedID != id else { return }
        selectedID = id
        expanded = false
        if let id { ClipboardHistory.shared.touch(id) }
    }
    func selectFirst() { selectedID = nil; select(matches.first?.id); scrollToken += 1 }
    func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        selection = min(max(0, selection + delta), matches.count - 1)
        scrollToken += 1
    }
    func confirm() -> HistoryClip? { matches.first { $0.id == selectedID } }
    func delete(_ id: UUID) {
        let index = matches.firstIndex { $0.id == id } ?? selection
        ClipboardHistory.shared.remove(id: id)
        let found = matches
        select(found.isEmpty ? nil : found[min(index, found.count - 1)].id)
    }
    func deleteSelection() { if let selectedID { delete(selectedID) } }
    func undo() {
        if let id = ClipboardHistory.shared.undoDelete() { select(id); scrollToken += 1 }
    }
}

private struct ClipboardSearchView: View {
    @ObservedObject var model: ClipboardSearchModel
    @ObservedObject private var history = ClipboardHistory.shared
    @ObservedObject private var themes = ClipboardThemes.shared
    var session: Int
    var onPaste: (HistoryClip) -> Void
    var onClose: () -> Void
    @FocusState private var focused: Bool
    private var night: Bool { themes.current == .night }
    private var ink: Color { night ? Color(white: 0.94) : Color(red: 0.23, green: 0.20, blue: 0.18) }
    private var muted: Color { night ? Color(white: 0.68) : Color(red: 0.51, green: 0.48, blue: 0.45) }
    private var rule: Color { night ? .white.opacity(0.10) : .black.opacity(0.06) }
    private var searching: Bool { !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                search
                HStack(spacing: 0) {
                    if !model.expanded {
                        results.frame(width: min(232, max(190, geometry.size.width * 0.31)))
                        Rectangle().fill(rule).frame(width: 1).padding(.vertical, 8)
                    }
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 12)
                footer
            }
            .foregroundStyle(ink)
            .frame(width: max(0, geometry.size.width - SearchChrome.margin * 2),
                   height: max(0, geometry.size.height - SearchChrome.margin * 2))
            .modifier(ClipboardGlass(dark: night))
            .shadow(color: .black.opacity(night ? 0.28 : 0.12), radius: 22, y: 10)
            .padding(SearchChrome.margin)
        }
        .onAppear { focused = true; if model.selectedID == nil { model.selectFirst() } }
        .task(id: session) { focused = true }
        .onChange(of: model.query) { _, _ in model.selectFirst() }
        .onChange(of: history.items) { _, _ in
            if !model.matches.contains(where: { $0.id == model.selectedID }) { model.selectFirst() }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(muted)
            TextField(L("Search copied content"), text: $model.query)
                .textFieldStyle(.plain).font(.system(size: 14)).focused($focused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(muted).accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, 14).frame(height: 36)
        .background(night ? Color.white.opacity(0.08) : Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(rule, lineWidth: 0.5))
        .padding(14)
    }

    private var results: some View {
        let found = model.matches
        return ScrollViewReader { proxy in
            ScrollView {
                if found.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: searching ? "magnifyingglass" : "doc.on.clipboard").font(.system(size: 22))
                        Text(searching ? L("No matching text") : L("No clipboard history yet"))
                            .font(.system(size: 13)).multilineTextAlignment(.center)
                    }.foregroundStyle(muted).padding(.top, 48).padding(.horizontal, 8)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(found.enumerated()), id: \.element.id) { index, clip in
                            if !searching && (index == 0 || HistoryBook.group(for: clip.date) != HistoryBook.group(for: found[index - 1].date)) {
                                Text(groupName(clip.date)).font(.system(size: 14)).foregroundStyle(muted)
                                    .padding(.top, index == 0 ? 2 : 12).padding(.bottom, 4).padding(.leading, 8)
                            }
                            row(clip).id(clip.id)
                        }
                    }.padding(.trailing, 6)
                }
            }
            .onChange(of: model.scrollToken) { _, _ in
                if let id = model.selectedID { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func row(_ clip: HistoryClip) -> some View {
        let selected = clip.id == model.selectedID
        let accent = themes.current.accent(for: clip.id)
        return HStack(spacing: 8) {
            if clip.isImage {
                HistoryImage(clip: clip, maxPixels: 72).frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Circle().fill(accent).frame(width: 6, height: 6).frame(width: 24)
            }
            Text(clip.isImage ? AttributedString("\(L("Image")) (\(clip.width ?? 0) × \(clip.height ?? 0))") : highlighted(clip.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines), accent: accent))
                .font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if selected {
                Button { model.delete(clip.id) } label: { Image(systemName: "xmark").font(.system(size: 9)).frame(width: 16, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(muted).help(L("Delete"))
                    .accessibilityLabel(L("Delete"))
            }
        }
        .padding(.horizontal, 8).frame(height: 36)
        .background(selected ? (night ? accent.opacity(0.22) : Color.white.mixed(with: accent, fraction: 0.18)) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.select(clip.id); onPaste(clip) }
        .onTapGesture { model.select(clip.id) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var detail: some View {
        if let clip = model.confirm() {
            VStack(alignment: .leading, spacing: 0) {
                if model.expanded {
                    Button { model.expanded = false } label: { Label(L("Back"), systemImage: "chevron.left") }
                        .buttonStyle(.plain).foregroundStyle(muted).padding(.bottom, 12)
                    HistoryImage(clip: clip, maxPixels: 2048).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if clip.isImage {
                        HistoryImage(clip: clip, maxPixels: 1024).frame(maxWidth: .infinity).frame(height: 214)
                            .background(night ? Color.white.opacity(0.03) : Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle()).onTapGesture { model.expanded = true }
                            .help(L("Click to enlarge"))
                    } else {
                        ScrollView {
                            Text(highlighted(clip.text, accent: themes.current.accent(for: clip.id)))
                                .font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }.frame(maxHeight: 214)
                    }
                    VStack(spacing: 0) {
                        metadata(L("Source"), clip.source ?? L("Unknown source"))
                        metadata(L("Type"), clip.isImage ? L("Image") : L("Text"))
                        if clip.isImage {
                            metadata(L("Dimensions"), "\(clip.width ?? 0) × \(clip.height ?? 0) px")
                            metadata(L("File size"), ByteCountFormatter.string(fromByteCount: Int64(clip.bytes ?? 0), countStyle: .file))
                        } else {
                            metadata(L("Characters"), "\(clip.text.count)")
                        }
                        metadata(L("Time"), timeName(clip.date))
                    }.padding(.top, 14)
                    Spacer(minLength: 0)
                }
            }.padding(.horizontal, 16).padding(.top, 2)
        } else {
            Text(searching ? L("No matching text") : L("Copy text or an image to get started"))
                .font(.system(size: 14)).foregroundStyle(muted).padding(24)
        }
    }

    private func metadata(_ key: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(rule).frame(height: 0.5)
            HStack {
                Text(key).foregroundStyle(muted)
                Spacer(minLength: 12)
                Text(value).lineLimit(1).help(value)
            }.font(.system(size: 13)).padding(.vertical, 7)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button { if let clip = model.confirm() { onPaste(clip) } } label: { Text("↩ " + L("Paste")) }
                .disabled(model.confirm() == nil)
            Button { model.deleteSelection() } label: { Text("⌘⌫ " + L("Delete")) }
                .disabled(model.confirm() == nil)
            Button(action: onClose) { Text("esc " + L("Close")) }
            Spacer(minLength: 0)
            if history.deleted != nil {
                Button { model.undo() } label: { Text(L("Undo delete")) }
            } else if let status = history.status {
                Text(status).lineLimit(1).help(status).onTapGesture { history.status = nil }
            } else if searching {
                Text(L("Searches text only"))
            }
        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(muted)
            .padding(.horizontal, 18).frame(height: 42)
    }

    private func highlighted(_ text: String, accent: Color) -> AttributedString {
        var result = AttributedString(text)
        for word in model.query.split(whereSeparator: \.isWhitespace) {
            var rest = text.startIndex..<text.endIndex
            while let range = text.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive], range: rest) {
                if let converted = Range(range, in: result) { result[converted].backgroundColor = accent.opacity(0.22) }
                guard range.upperBound < text.endIndex else { break }
                rest = range.upperBound..<text.endIndex
            }
        }
        return result
    }

    private func groupName(_ date: Date) -> String {
        switch HistoryBook.group(for: date) {
        case .today: return L("Today")
        case .yesterday: return L("Yesterday")
        case .week: return L("Last 7 days")
        case .month: return L("Last 30 days")
        case .older(let year, _):
            if year == Calendar.current.component(.year, from: Date()) { return date.formatted(.dateTime.month(.wide)) }
            return date.formatted(.dateTime.year().month(.wide))
        }
    }
    private func timeName(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return L("Today") + " " + date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return L("Yesterday") + " " + date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Decodes a bounded thumbnail off the main thread; the original stays untouched for pasting.
private struct HistoryImage: View {
    let clip: HistoryClip
    let maxPixels: Int
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary).help(L("This image cannot be read")) }
            else { ProgressView().controlSize(.small) }
        }
        .task(id: clip.imageFilename) {
            let url = ClipboardHistory.shared.imageURL(for: clip)
            image = nil
            failed = false
            let result = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let url, let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { return nil }
                return NSImage(cgImage: thumbnail, size: .zero)
            }.value
            guard !Task.isCancelled else { return }
            image = result
            failed = result == nil
        }
    }
}

/// System liquid glass on macOS 26. Older systems keep the app's thin material.
/// Night is the dark appearance of that glass, not a dimming veil.
private struct ClipboardGlass: ViewModifier {
    var dark: Bool

    func body(content: Content) -> some View {
        glass(content).environment(\.colorScheme, dark ? .dark : .light)
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else if dark {
            content
                .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.92), in: shape)
                .glassFrame(cornerRadius: 22)
        } else {
            content.glassFrame(cornerRadius: 22)
        }
    }
}
