import AppKit
import Carbon
import SwiftUI

/// A borderless panel that can take the keyboard. The line's panel cannot.
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Glass size, plus the clear margin the shadow is drawn in.
private enum SearchChrome {
    static let glassWidth: CGFloat = 460
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
        model.selection = 0
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
        let host = NSHostingView(rootView: ClipboardSearchView(model: model, session: session) { [weak self] text in
            self?.paste(text)
        })
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

    private func paste(_ text: String) {
        ClipboardHistory.shared.copyToPasteboard(text)
        let app = target
        // Leave before sending Command-V, so the keystroke is not typed into this field.
        closing = true
        acceptsOutsideClose = false
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        app?.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
    @Published var selection = 0
    /// Bumps only when the keyboard moves the highlight, so hovering a row does not scroll the list.
    @Published var scrollToken = 0

    var matches: [TextClip] { ClipboardHistory.shared.matches(query) }

    func move(_ delta: Int) {
        let count = matches.count
        guard count > 0 else { return }
        selection = min(max(0, selection + delta), count - 1)
        scrollToken += 1
    }

    func confirm() -> String? {
        let found = matches
        guard found.indices.contains(selection) else { return nil }
        return found[selection].text
    }

    /// Removes one row and leaves the highlight on the row that slides into its place.
    func delete(_ id: UUID) {
        let index = matches.firstIndex(where: { $0.id == id }) ?? selection
        withAnimation(.easeOut(duration: 0.12)) {
            ClipboardHistory.shared.remove(id: id)
        }
        let count = matches.count
        selection = count == 0 ? 0 : min(index, count - 1)
    }

    func deleteSelection() {
        let found = matches
        guard found.indices.contains(selection) else { return }
        delete(found[selection].id)
    }
}

private struct ClipboardSearchView: View {
    @ObservedObject var model: ClipboardSearchModel
    @ObservedObject private var history = ClipboardHistory.shared
    @ObservedObject private var themes = ClipboardThemes.shared
    var session: Int
    var onPaste: (String) -> Void

    @FocusState private var focused: Bool

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var theme: ClipboardTheme { themes.current }
    private var night: Bool { theme == .night }

    var body: some View {
        let found = history.matches(model.query)
        VStack(spacing: 0) {
            search
            divider
            results(found)
            divider
            footer
        }
        .frame(width: SearchChrome.glassWidth, height: SearchChrome.glassHeight)
        .modifier(ClipboardGlass(dark: night))
        .shadow(color: .black.opacity(night ? 0.28 : 0.16), radius: 22, y: 10)
        .padding(SearchChrome.margin)
        .frame(width: SearchChrome.windowSize.width, height: SearchChrome.windowSize.height)
        .onAppear { focused = true }
        .task(id: session) { focused = true }
        .onChange(of: model.query) { _, _ in
            model.selection = 0
            model.scrollToken += 1
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(night ? Color(red: 0.72, green: 0.68, blue: 0.64) : Color(white: 0.42))
            TextField(L("Search copied text"), text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(night ? Color(red: 0.95, green: 0.93, blue: 0.90) : Color(white: 0.16))
                .focused($focused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(night ? Color.white.opacity(0.08) : Color.white.opacity(0.30),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(night ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func results(_ found: [TextClip]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if found.isEmpty {
                    empty
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(found) { clip in
                            row(clip, index: found.firstIndex(where: { $0.id == clip.id }) ?? 0)
                        }
                    }
                    .padding(8)
                }
            }
            .onChange(of: model.scrollToken) { _, _ in
                guard found.indices.contains(model.selection) else { return }
                let id = found[model.selection].id
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? L("Nothing copied yet") : L("No matches"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(night ? Color.white.opacity(0.55) : Color.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    private func row(_ clip: TextClip, index: Int) -> some View {
        let selected = index == model.selection
        let accent = theme.accent(for: clip.id)
        let ink = Color(red: 0.16, green: 0.13, blue: 0.11)
        let cream = Color(red: 1, green: 0.973, blue: 0.953)
        return HStack(alignment: .center, spacing: 4) {
            Button {
                onPaste(clip.text)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    mark(accent, selected: selected)
                    Text(highlighted(clip.text, query: model.query, accent: accent, selected: selected))
                        // The row used to be identified by its position. Clearing the search
                        // reused that cell, so the old string and its highlight stayed on screen.
                        .id(clip.id.uuidString + "\u{1e}" + model.query)
                        .font(.system(size: 14, weight: selected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(rowInk(accent, selected: selected, ink: ink, cream: cream))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Self.relative.localizedString(for: clip.date, relativeTo: Date()))
                        .font(.system(size: 11, weight: theme == .reflection && selected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(timeInk(accent, selected: selected))
                        .layoutPriority(1)
                        .padding(.top, 2)
                }
                .padding(.leading, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                model.delete(clip.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(timeInk(accent, selected: true))
                    .frame(width: 16, height: 16)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
            .accessibilityLabel(L("Delete"))
            .help(L("Delete"))
            .padding(.trailing, 8)
        }
        .background(rowFill(accent, selected: selected), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { inside in
            if inside { model.selection = index }
        }
    }

    @ViewBuilder
    private func mark(_ accent: Color, selected: Bool) -> some View {
        switch theme {
        case .night, .day:
            Circle().fill(accent).frame(width: 6, height: 6).padding(.top, 6)
        case .lacquer:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(selected ? Color.white.opacity(0.9) : accent)
                .frame(width: 9, height: 9)
                .padding(.top, 4)
        case .spectrum:
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(accent)
                .frame(width: 2)
                .padding(.vertical, 3)
        case .reflection:
            EmptyView()
        }
    }

    private func rowFill(_ accent: Color, selected: Bool) -> Color {
        guard selected else { return .clear }
        switch theme {
        case .night:
            return Color(red: 226 / 255, green: 176 / 255, blue: 106 / 255).opacity(0.22)
        case .day:
            return Color.white.mixed(with: accent, fraction: 0.22)
        case .lacquer:
            return accent.mixed(with: Color(red: 0.14, green: 0.08, blue: 0.05), fraction: 0.14)
        case .spectrum:
            return Color.white.mixed(with: accent, fraction: 0.18)
        case .reflection:
            return Color.white.mixed(with: accent, fraction: 0.20)
        }
    }

    private func rowInk(_ accent: Color, selected: Bool, ink: Color, cream: Color) -> Color {
        switch theme {
        case .night:
            return selected ? Color(red: 1, green: 0.965, blue: 0.918) : Color(red: 0.953, green: 0.925, blue: 0.894)
        case .day:
            return selected ? accent.mixed(with: ink, fraction: 0.42) : Color(red: 0.23, green: 0.20, blue: 0.17)
        case .lacquer:
            return selected ? cream : Color(red: 0.16, green: 0.14, blue: 0.12)
        case .spectrum:
            return selected ? accent.mixed(with: Color(red: 0.09, green: 0.08, blue: 0.07), fraction: 0.28) : Color(red: 0.14, green: 0.13, blue: 0.125)
        case .reflection:
            return Color(red: 0.15, green: 0.14, blue: 0.125)
        }
    }

    private func timeInk(_ accent: Color, selected: Bool) -> Color {
        switch theme {
        case .night:
            return selected ? Color(red: 0.94, green: 0.83, blue: 0.64) : Color(red: 0.60, green: 0.57, blue: 0.53)
        case .day:
            return selected ? accent.mixed(with: Color(red: 0.42, green: 0.36, blue: 0.31), fraction: 0.58) : Color(red: 0.55, green: 0.51, blue: 0.46)
        case .lacquer:
            return selected ? Color.white.opacity(0.76) : Color(red: 0.43, green: 0.40, blue: 0.37)
        case .spectrum:
            return selected ? accent.mixed(with: Color(red: 0.36, green: 0.35, blue: 0.33), fraction: 0.52) : Color(red: 0.48, green: 0.45, blue: 0.43)
        case .reflection:
            return accent
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            keyHint("↩", L("Paste"))
            keyHint("⌘⌫", L("Delete"))
            keyHint("esc", L("Close"))
        }
        .padding(.vertical, 10)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: Capsule())
            Text(label)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(night ? Color.white.opacity(0.45) : Color.black.opacity(0.4))
    }

    /// The same comparison the list filter uses, so a visible row always has something to mark.
    private func highlighted(_ text: String, query: String, accent: Color, selected: Bool) -> AttributedString {
        let flat = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let shown = snippet(flat, words: words)
        var styled = AttributedString(shown)
        guard !words.isEmpty else { return styled }
        let wash = matchWash(accent, selected: selected)
        for range in matchRanges(in: shown, words: words) {
            guard let lower = AttributedString.Index(range.lowerBound, within: styled),
                  let upper = AttributedString.Index(range.upperBound, within: styled) else { continue }
            styled[lower..<upper].backgroundColor = wash
        }
        return styled
    }

    /// Keeps the first hit on screen when the copied text is longer than the row.
    private func snippet(_ flat: String, words: [String]) -> String {
        let limit = 240
        guard flat.count > limit else { return flat }
        guard let hit = words.compactMap({ flat.localizedStandardRange(of: $0)?.lowerBound }).min() else {
            return String(flat.prefix(limit)) + "…"
        }
        let lead = 32
        let hitOffset = flat.distance(from: flat.startIndex, to: hit)
        let startOffset = max(0, hitOffset - lead)
        let endOffset = min(flat.count, startOffset + limit)
        let start = flat.index(flat.startIndex, offsetBy: startOffset)
        let end = flat.index(flat.startIndex, offsetBy: endOffset)
        var slice = String(flat[start..<end])
        if startOffset > 0 { slice = "…" + slice }
        if endOffset < flat.count { slice += "…" }
        return slice
    }

    private func matchRanges(in text: String, words: [String]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for word in words where !word.isEmpty {
            var cursor = text.startIndex
            while cursor < text.endIndex, let found = text[cursor...].localizedStandardRange(of: word) {
                ranges.append(found)
                if found.upperBound <= cursor { break }
                cursor = found.upperBound
            }
        }
        return ranges
    }

    /// A wash in this clip's own color. Lacquer's selected row is already that color, so the hit turns light.
    private func matchWash(_ accent: Color, selected: Bool) -> Color {
        switch theme {
        case .night:
            return accent.opacity(0.42)
        case .lacquer where selected:
            return Color.white.opacity(0.34)
        case .day, .spectrum, .reflection, .lacquer:
            return accent.opacity(selected ? 0.34 : 0.22)
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
