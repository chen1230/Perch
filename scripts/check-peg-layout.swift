import Foundation

// Layout checks for PegLayout. Compile with the source file:
//   swiftc -o /tmp/pegcheck Sources/Perch/PegLayout.swift scripts/check-peg-layout.swift

@main
enum PegLayoutCheck {
    static func main() {
        run()
    }
}

private var failures: [String] = []

private func run() {

func check(_ name: String, _ ok: Bool) {
    if ok { print("ok  \(name)") } else {
        failures.append(name)
        print("FAIL \(name)")
    }
}

let width: CGFloat = 1000
let margin: CGFloat = 100
let gap: CGFloat = 80

let round = PegLayout.anchor(x: 460, width: width, margin: margin)
let back = PegLayout.x(anchor: round, width: width, margin: margin)
check("anchor roundtrip", abs(back - 460) < 0.01)

check("largest gap is the middle",
      abs(PegLayout.largestGapAnchor(existing: [0.2, 0.8]) - 0.5) < 0.0001)
check("largest gap is the right end",
      abs(PegLayout.largestGapAnchor(existing: [0.4, 0.5]) - 0.75) < 0.0001)
check("empty rope hangs in the center",
      abs(PegLayout.largestGapAnchor(existing: []) - 0.5) < 0.0001)

func slot(_ n: Int, _ anchor: CGFloat, dragged: Bool = false) -> PegSlot {
    PegSlot(id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!,
            anchor: anchor, dragged: dragged)
}

func xs(_ slots: [PegSlot]) -> [CGFloat] {
    let resolved = PegLayout.resolve(slots: slots, width: width, margin: margin, gap: gap)
    return slots.map { PegLayout.x(anchor: resolved[$0.id]!, width: width, margin: margin) }
}

let pushed = xs([slot(1, 0.2, dragged: true), slot(2, 0.25)])
check("neighbor is pushed to the minimum gap", abs(pushed[1] - pushed[0] - gap) < 0.01)

let apart = xs([slot(1, 0.2, dragged: true), slot(2, 0.7)])
check("a wide gap stays put", abs(apart[0] - 260) < 0.01 && abs(apart[1] - 660) < 0.01)

let edge = xs([slot(1, PegLayout.anchor(x: 0, width: width, margin: margin), dragged: true), slot(2, 0.05)])
check("drag stops at the left margin", abs(edge[0] - 100) < 0.01)
check("the next photo clears the left margin", edge[1] >= edge[0] + gap - 0.01)

let packed = (0..<12).map { slot($0, CGFloat($0) / 11) }
let packedXs = xs(packed)
check("a crowded rope spans the margins",
      abs(packedXs.first! - 100) < 0.01 && abs(packedXs.last! - 900) < 0.01)
check("a crowded rope never overlaps",
      zip(packedXs, packedXs.dropFirst()).allSatisfy { $1 - $0 >= gap - 0.5 || packedXs.last! - packedXs.first! >= 799 })

if !failures.isEmpty {
    fputs("\(failures.count) failed\n", stderr)
    exit(1)
}
print("peg layout ok")
}
