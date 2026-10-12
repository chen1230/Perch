import AppKit

/// A transparent strip along the top of the screen that floats over every
/// app and every Space except full screen ones, never takes focus, and lets clicks pass through
/// everywhere except over the photos.
final class LinePanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        // Every Space, full screen ones included. Whether the line comes down
        // over a full screen app is up to the user, see FullScreen.showLineOver.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        contentView = content
        content.clipsToBounds = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The line hangs on the screen you are using, which is the one with the
    /// pointer: that is where you just took the screenshot.
    static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// While a clip is off the rope the strip grows down to the bottom of the
    /// screen, so the photo can follow the pointer. The top edge stays put.
    private var expandedDown = false

    func setExpandedDown(_ on: Bool) {
        guard expandedDown != on else { return }
        expandedDown = on
        placeOnScreen(screen)
    }

    func placeOnScreen(_ screen: NSScreen? = nil) {
        // An implicit placement follows the pointer. Preferring the window's
        // old screen leaves it behind when a hover reveals it on another display.
        // Callers resizing an existing panel pass its screen explicitly.
        guard let screen = screen ?? LinePanel.screenUnderPointer() ?? self.screen else { return }
        let visible = screen.visibleFrame
        let top = visible.maxY
        let bottom = expandedDown ? screen.frame.minY : top - Layout.panelHeight
        let target = NSRect(x: visible.minX, y: bottom,
                            width: visible.width, height: max(Layout.panelHeight, top - bottom))
        if frame != target { setFrame(target, display: true) }
    }
}
