// Perch icon: the 映 study. A cool ground, a rope, a water picture
// behind a larger window. Chosen from docs/images/icon-options/stack-5.png.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func shadow(_ c: NSColor, blur: CGFloat, y: CGFloat) {
    let s = NSShadow()
    s.shadowColor = c
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.set()
}

func squircle(_ fill: [NSColor], rim: NSColor) {
    let body = NSRect(x: 88, y: 88, width: 848, height: 848)
    let shape = NSBezierPath(roundedRect: body, xRadius: 196, yRadius: 196)
    ctx.saveGState()
    shadow(color(40, 24, 16, 0.28), blur: 28, y: -14)
    color(255, 255, 255).setFill()
    shape.fill()
    ctx.restoreGState()
    shape.addClip()
    NSGradient(colors: fill, atLocations: fill.count == 2 ? [0, 1] : [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -72)
    NSGradient(colors: [color(255, 255, 255, 0.28), color(255, 255, 255, 0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY + 40, width: body.width, height: body.height / 2), angle: -90)
    shape.lineWidth = 10
    rim.setStroke()
    shape.stroke()
}

func rope(from a: NSPoint, to b: NSPoint, sag: CGFloat, width: CGFloat, stroke: NSColor, shine: NSColor) {
    let c = NSPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - sag)
    let p = NSBezierPath()
    p.move(to: a)
    p.curve(to: b,
            controlPoint1: NSPoint(x: a.x + (c.x - a.x) * 2 / 3, y: a.y + (c.y - a.y) * 2 / 3),
            controlPoint2: NSPoint(x: b.x + (c.x - b.x) * 2 / 3, y: b.y + (c.y - b.y) * 2 / 3))
    ctx.saveGState()
    shadow(color(40, 24, 16, 0.22), blur: 10, y: -6)
    p.lineWidth = width
    p.lineCapStyle = .round
    stroke.setStroke()
    p.stroke()
    ctx.restoreGState()
    let hi = p.copy() as! NSBezierPath
    hi.transform(using: AffineTransform(translationByX: 0, byY: 3))
    hi.lineWidth = width * 0.28
    shine.setStroke()
    hi.stroke()
}

func lineY(x: CGFloat, a: NSPoint, b: NSPoint, sag: CGFloat) -> CGFloat {
    let t = max(0, min(1, (x - a.x) / (b.x - a.x)))
    let mid = (a.y + b.y) / 2 - sag
    return (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * mid + t * t * b.y
}

func brassClip() {
    let clip = NSRect(x: -18, y: -8, width: 36, height: 78)
    let path = NSBezierPath(roundedRect: clip, xRadius: 12, yRadius: 12)
    ctx.saveGState()
    shadow(color(40, 24, 16, 0.28), blur: 8, y: -4)
    color(176, 118, 52).setFill()
    path.fill()
    ctx.restoreGState()
    NSGradient(colors: [color(122, 78, 36), color(236, 196, 120), color(168, 112, 52), color(98, 62, 30)],
               atLocations: [0, 0.42, 0.72, 1], colorSpace: .sRGB)!.draw(in: path, angle: 0)
    color(70, 40, 18, 0.5).setFill()
    NSBezierPath(roundedRect: NSRect(x: -11, y: 28, width: 22, height: 6), xRadius: 3, yRadius: 3).fill()
}

func windowCard(_ r: NSRect) {
    color(255, 250, 246).setFill(); r.fill()
    color(236, 226, 214).setFill()
    let bar = NSRect(x: r.minX, y: r.maxY - r.height * 0.16, width: r.width, height: r.height * 0.16)
    bar.fill()
    for (i, c) in [color(214, 96, 72), color(214, 164, 72), color(72, 158, 120)].enumerated() {
        c.setFill()
        let d = r.height * 0.045
        NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.08 + CGFloat(i) * d * 1.7, y: bar.midY - d / 2, width: d, height: d)).fill()
    }
    color(184, 92, 58).setFill()
    NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * 0.1, y: bar.minY - r.height * 0.12, width: r.width * 0.46, height: r.height * 0.045), xRadius: 8, yRadius: 8).fill()
    color(196, 176, 158).setFill()
    for i in 0..<4 {
        let w = r.width * [0.72, 0.5, 0.64, 0.42][i]
        NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * 0.1, y: bar.minY - r.height * 0.22 - CGFloat(i) * r.height * 0.09, width: w, height: r.height * 0.032), xRadius: 6, yRadius: 6).fill()
    }
}

func water(_ r: NSRect) {
    NSGradient(colors: [color(186, 214, 232), color(92, 150, 186), color(36, 92, 128)])!.draw(in: r, angle: 90)
    color(255, 248, 230).setFill()
    let s = r.width * 0.16
    NSBezierPath(ovalIn: NSRect(x: r.midX - s / 2, y: r.maxY - r.height * 0.38, width: s, height: s)).fill()
    color(255, 255, 255, 0.55).setFill()
    NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.22, y: r.minY + r.height * 0.22, width: r.width * 0.56, height: r.height * 0.08)).fill()
}

func hang(at x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat, glass: NSColor, block: (NSRect) -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.rotate(by: angle * .pi / 180)
    brassClip()
    let radius = min(w, h) * 0.16
    let frame = NSRect(x: -w / 2, y: -h - 18, width: w, height: h)
    let framePath = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    ctx.saveGState()
    shadow(color(40, 24, 16, 0.3), blur: 28, y: -16)
    glass.setFill()
    framePath.fill()
    ctx.restoreGState()
    let photo = frame.insetBy(dx: w * 0.055, dy: w * 0.055)
    ctx.saveGState()
    NSBezierPath(roundedRect: photo, xRadius: radius * 0.72, yRadius: radius * 0.72).addClip()
    block(photo)
    ctx.restoreGState()
    ctx.saveGState()
    let ring = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    ring.append(NSBezierPath(roundedRect: frame.insetBy(dx: 5, dy: 5), xRadius: radius - 5, yRadius: radius - 5))
    ring.windingRule = .evenOdd
    ring.addClip()
    NSGradient(colors: [color(255, 255, 255, 0.92), color(255, 255, 255, 0.18)])!.draw(in: frame, angle: -90)
    ctx.restoreGState()
    ctx.restoreGState()
}

squircle([color(232, 238, 248), color(244, 226, 216)], rim: color(255, 255, 255, 0.5))
let a = NSPoint(x: 150, y: 760), b = NSPoint(x: 874, y: 748)
let sag: CGFloat = 70
rope(from: a, to: b, sag: sag, width: 16, stroke: color(90, 78, 92), shine: color(255, 255, 255, 0.7))
hang(at: 348, y: lineY(x: 348, a: a, b: b, sag: sag) + 4, w: 320, h: 280, angle: -8, glass: color(255, 252, 248, 0.62)) { water($0) }
hang(at: 578, y: lineY(x: 578, a: a, b: b, sag: sag) + 8, w: 430, h: 470, angle: -1, glass: color(255, 252, 248, 0.8)) { windowCard($0) }

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
