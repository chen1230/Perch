import SwiftUI

enum Layout {
    /// How big the photos hang, from Size in the menu bar. The clip, the rope
    /// and the glass frame keep their size; the photos and the room they take
    /// grow or shrink. Medium is the original size.
    enum Size: String, CaseIterable {
        case small, medium, large

        var scale: CGFloat {
            switch self {
            case .small: 0.8
            case .medium: 1
            case .large: 1.35
            }
        }
    }

    static var size: Size {
        get { Size(rawValue: UserDefaults.standard.string(forKey: "lineSize") ?? "") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lineSize") }
    }

    static var photoMaxHeight: CGFloat { (104 * size.scale).rounded() }
    static var cardWidth: CGFloat { (150 * size.scale).rounded() }
    static var spacing: CGFloat { cardWidth + 24 }
    static var panelHeight: CGFloat { photoMaxHeight + 106 }
    static let ropeTop: CGFloat = 10
    static let pinAbove: CGFloat = 9.5
    /// The slot in the clip, measured from the top of the pin. Matches the
    /// drawing in `Clothespin`.
    static let pinSlot: CGFloat = 8.5
    /// How close that slot must be to the rope before a drop will catch.
    static let catchDistance: CGFloat = 44

    static func centerY(ropeY: CGFloat) -> CGFloat {
        ropeY - pinAbove + (panelHeight - ropeY) / 2
    }

    /// The clip is back on the rope when its slot is near the curve, and the
    /// drop is still over this screen.
    static func caughtRope(slotY: CGFloat, x: CGFloat, width: CGFloat) -> Bool {
        guard width > 1, x >= -catchDistance, x <= width + catchDistance else { return false }
        let clamped = min(max(x, 0), width)
        return abs(slotY - ropeY(x: clamped, width: width)) <= catchDistance
    }
    /// Centers stay this far from each screen edge, so a card is not cut in half.
    static var edgeMargin: CGFloat { max(28, cardWidth * 0.42) }
    /// Closest two clips may hang. Near enough to overlap a little, far enough
    /// that each photo can still be told apart.
    static var minGap: CGFloat { max(48, cardWidth * 0.72) }

    /// Hand-placed photos use their anchor. The rest stay evenly spaced.
    static func placedX(anchor: CGFloat?, index: Int, count: Int, width: CGFloat) -> CGFloat {
        if let anchor {
            return PegLayout.x(anchor: anchor, width: width, margin: edgeMargin)
        }
        return x(index: index, count: count, width: width)
    }

    /// The rope hangs as a parabola from edge to edge of the screen.
    static func sag(width: CGFloat) -> CGFloat { min(30, width * 0.018) }

    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = x / width
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }

    /// Photos hang `spacing` apart. A line hung on a wider screen can hold
    /// more than this one has room for, and then they move closer together
    /// so that none ends up past the edge.
    static func x(index: Int, count: Int, width: CGFloat) -> CGFloat {
        let gaps = CGFloat(max(count - 1, 0))
        let step = gaps > 0 ? min(spacing, max(0, width - 200) / gaps) : spacing
        return width / 2 - gaps * step / 2 + CGFloat(index) * step
    }
}

struct LineView: View {
    @ObservedObject var line: Line

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Rope(width: width)

                if line.items.isEmpty {
                    Hint()
                        .position(x: width / 2, y: Layout.ropeY(x: width / 2, width: width) + 34)
                        .transition(.opacity)
                }

                ForEach(Array(line.items.enumerated()), id: \.element.id) { index, item in
                    let carried = line.slidingID == item.id
                    let x = carried ? line.carryBaseX
                        : Layout.placedX(anchor: line.displayAnchor(for: item.id), index: index,
                                         count: line.items.count, width: width)
                    let ropeY = Layout.ropeY(x: x, width: width)
                    PeggedView(item: item, line: line, lineWidth: width)
                        .frame(width: Layout.cardWidth, height: Layout.panelHeight - ropeY, alignment: .top)
                        .position(x: x, y: Layout.centerY(ropeY: ropeY))
                        .offset(carried ? line.carryOffset : .zero)
                        .zIndex(carried ? 1 : 0)
                        // Off the rope, the clip follows the pointer with no lag.
                        // Letting go eases it onto the rope, or back where it was.
                        .animation(carried && !line.carrySettling ? nil
                                   : .spring(response: 0.42, dampingFraction: 0.82),
                                   value: carried ? line.carryOffset.width : x)
                        .animation(carried && line.carrySettling
                                   ? .spring(response: 0.42, dampingFraction: 0.82) : nil,
                                   value: line.carryOffset)
                }
            }
            .coordinateSpace(name: "line")
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: line.items.map(\.id))
            .animation(.easeInOut(duration: 0.3), value: line.items.isEmpty)
            // Tucked away, the whole line waits above the top edge and slides
            // out from under the menu bar, the way an auto-hiding Dock does.
            .offset(y: line.revealed ? 0 : -(Layout.panelHeight + 12))
            .animation(line.revealed ? .spring(response: 0.42, dampingFraction: 0.82)
                                     : .easeIn(duration: 0.22), value: line.revealed)
            .onAppear { line.noteWidth(width) }
            .onChange(of: width) { _, newWidth in line.noteWidth(newWidth) }
        }
        .onPreferenceChange(HitRectsKey.self) { rects in
            line.hitRects = rects
        }
    }
}

private struct Hint: View {
    var body: some View {
        Text(L("Take a screenshot and it will hang here"))
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

/// A thin, neutral line: a mid gray core with a faint highlight and a soft
/// shadow, so it reads on light and dark backgrounds alike. It fades out at
/// both ends so it seems to come from beyond the screen.
struct Rope: View {
    let width: CGFloat

    private var path: Path {
        Path { p in
            let top = Layout.ropeTop
            p.move(to: CGPoint(x: -20, y: top))
            p.addQuadCurve(
                to: CGPoint(x: width + 20, y: top),
                control: CGPoint(x: width / 2, y: top + 2 * Layout.sag(width: width)))
        }
    }

    var body: some View {
        ZStack {
            path.stroke(Color.black.opacity(0.22), lineWidth: 1.4).offset(y: 1.2).blur(radius: 1.2)
            path.stroke(Color(white: 0.55), lineWidth: 1.2)
            path.stroke(Color.white.opacity(0.45), lineWidth: 0.4).offset(y: -0.35)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .allowsHitTesting(false)
    }
}

struct HitRectsKey: PreferenceKey {
    static var defaultValue: [UUID: [CGRect]] = [:]
    static func reduce(value: inout [UUID: [CGRect]], nextValue: () -> [UUID: [CGRect]]) {
        for (id, rects) in nextValue() {
            value[id, default: []].append(contentsOf: rects)
        }
    }
}
