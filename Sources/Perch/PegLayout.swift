import Foundation

/// Where one photo sits along the rope, as a fraction of the usable span.
struct PegSlot: Equatable {
    var id: UUID
    var anchor: CGFloat
    var dragged: Bool
}

/// Pure placement math for photos on the rope. x grows to the right.
/// `anchor` 0 is the left margin, 1 is the right margin.
enum PegLayout {
    static func usableRange(width: CGFloat, margin: CGFloat) -> (lo: CGFloat, hi: CGFloat) {
        let lo = min(max(0, margin), max(0, width / 2))
        let hi = max(lo, width - margin)
        return (lo, hi)
    }

    static func x(anchor: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        let (lo, hi) = usableRange(width: width, margin: margin)
        let span = hi - lo
        guard span > 0 else { return lo }
        return lo + min(1, max(0, anchor)) * span
    }

    static func anchor(x: CGFloat, width: CGFloat, margin: CGFloat) -> CGFloat {
        let (lo, hi) = usableRange(width: width, margin: margin)
        let span = hi - lo
        guard span > 0.5 else { return 0.5 }
        return min(1, max(0, (x - lo) / span))
    }

    /// Middle of the widest open stretch, including the ends of the rope.
    /// `existing` anchors must already lie in 0...1.
    static func largestGapAnchor(existing: [CGFloat]) -> CGFloat {
        let sorted = existing.sorted()
        guard let first = sorted.first else { return 0.5 }
        var bestSpan = first
        var bestMid = first / 2
        for i in 0..<(sorted.count - 1) {
            let span = sorted[i + 1] - sorted[i]
            if span > bestSpan {
                bestSpan = span
                bestMid = (sorted[i] + sorted[i + 1]) / 2
            }
        }
        if let last = sorted.last {
            let tail = 1 - last
            if tail > bestSpan { bestMid = (last + 1) / 2 }
        }
        return min(1, max(0, bestMid))
    }

    /// New anchors keyed by id. Centers stay at least `gap` apart, inside the
    /// margins. The dragged photo follows the pointer until the row hits an edge.
    static func resolve(slots: [PegSlot], width: CGFloat, margin: CGFloat, gap: CGFloat) -> [UUID: CGFloat] {
        let (lo, hi) = usableRange(width: width, margin: margin)
        var ordered = slots.map { ($0, x(anchor: $0.anchor, width: width, margin: margin)) }
        ordered.sort { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.id.uuidString < rhs.0.id.uuidString }
            return lhs.1 < rhs.1
        }
        let n = ordered.count
        guard n > 0 else { return [:] }
        var xs = ordered.map(\.1)
        if n == 1 {
            xs[0] = min(hi, max(lo, xs[0]))
        } else {
            let room = hi - lo
            let needed = gap * CGFloat(n - 1)
            if gap > 0, needed >= room - 0.01 {
                for i in 0..<n {
                    xs[i] = lo + room * CGFloat(i) / CGFloat(n - 1)
                }
            } else if let d = ordered.firstIndex(where: { $0.0.dragged }) {
                xs[d] = min(hi, max(lo, xs[d]))
                separate(from: d, xs: &xs, gap: gap, lo: lo, hi: hi)
            } else {
                separate(from: 0, xs: &xs, gap: gap, lo: lo, hi: hi)
            }
        }
        var result: [UUID: CGFloat] = [:]
        for (i, entry) in ordered.enumerated() {
            result[entry.0.id] = anchor(x: xs[i], width: width, margin: margin)
        }
        return result
    }

    /// Push neighbors out from `pinned` until every pair is `gap` apart and
    /// every center lies in `lo...hi`. When the row hits an edge, the pinned
    /// center moves too, so a drag stops instead of piling up.
    private static func separate(from pinned: Int, xs: inout [CGFloat], gap: CGFloat, lo: CGFloat, hi: CGFloat) {
        let n = xs.count
        guard n > 1, gap > 0 else { return }
        xs[pinned] = min(hi, max(lo, xs[pinned]))
        if pinned + 1 < n {
            for i in (pinned + 1)..<n {
                xs[i] = max(xs[i], xs[i - 1] + gap)
            }
        }
        if pinned > 0 {
            for i in stride(from: pinned - 1, through: 0, by: -1) {
                xs[i] = min(xs[i], xs[i + 1] - gap)
            }
        }
        if xs[n - 1] > hi {
            xs[n - 1] = hi
            for i in stride(from: n - 2, through: 0, by: -1) {
                xs[i] = min(xs[i], xs[i + 1] - gap)
            }
        }
        if xs[0] < lo {
            xs[0] = lo
            for i in 1..<n {
                xs[i] = max(xs[i], xs[i - 1] + gap)
            }
        }
        if xs[n - 1] > hi {
            xs[n - 1] = hi
            for i in stride(from: n - 2, through: 0, by: -1) {
                xs[i] = min(xs[i], xs[i + 1] - gap)
            }
        }
    }
}
