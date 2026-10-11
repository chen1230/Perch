// Five Perch icon studies. Does not replace the app icon.
// Usage: swift scripts/make-icon-options.swift [folder]
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "docs/images/icon-options"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let S: CGFloat = 1024

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

func bitmap(_ px: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func drawIcon(_ body: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = bitmap(Int(S))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

func squircle(_ fill: [NSColor], rim: NSColor) {
    let body = NSRect(x: 88, y: 88, width: 848, height: 848)
    let shape = NSBezierPath(roundedRect: body, xRadius: 196, yRadius: 196)
    NSGraphicsContext.current!.cgContext.saveGState()
    shadow(color(40, 24, 16, 0.28), blur: 28, y: -14)
    color(255, 255, 255).setFill()
    shape.fill()
    NSGraphicsContext.current!.cgContext.restoreGState()
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
    NSGraphicsContext.current!.cgContext.saveGState()
    shadow(color(40, 24, 16, 0.22), blur: 10, y: -6)
    p.lineWidth = width
    p.lineCapStyle = .round
    stroke.setStroke()
    p.stroke()
    NSGraphicsContext.current!.cgContext.restoreGState()
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
    NSGraphicsContext.current!.cgContext.saveGState()
    shadow(color(40, 24, 16, 0.28), blur: 8, y: -4)
    color(176, 118, 52).setFill()
    path.fill()
    NSGraphicsContext.current!.cgContext.restoreGState()
    NSGradient(colors: [color(122, 78, 36), color(236, 196, 120), color(168, 112, 52), color(98, 62, 30)],
               atLocations: [0, 0.42, 0.72, 1], colorSpace: .sRGB)!.draw(in: path, angle: 0)
    color(70, 40, 18, 0.5).setFill()
    NSBezierPath(roundedRect: NSRect(x: -11, y: 28, width: 22, height: 6), xRadius: 3, yRadius: 3).fill()
}

func windowCard(_ r: NSRect, dark: Bool) {
    if dark {
        color(28, 30, 40).setFill(); r.fill()
        color(48, 52, 68).setFill()
    } else {
        color(255, 250, 246).setFill(); r.fill()
        color(236, 226, 214).setFill()
    }
    let bar = NSRect(x: r.minX, y: r.maxY - r.height * 0.16, width: r.width, height: r.height * 0.16)
    bar.fill()
    let dots: [NSColor] = dark
        ? [color(196, 92, 78), color(196, 154, 72), color(72, 150, 118)]
        : [color(214, 96, 72), color(214, 164, 72), color(72, 158, 120)]
    for (i, c) in dots.enumerated() {
        c.setFill()
        let d = r.height * 0.045
        NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.08 + CGFloat(i) * d * 1.7, y: bar.midY - d / 2, width: d, height: d)).fill()
    }
    (dark ? color(232, 176, 120) : color(184, 92, 58)).setFill()
    NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * 0.1, y: bar.minY - r.height * 0.12, width: r.width * 0.46, height: r.height * 0.045), xRadius: 8, yRadius: 8).fill()
    (dark ? color(180, 186, 204, 0.55) : color(196, 176, 158)).setFill()
    for i in 0..<4 {
        let w = r.width * [0.72, 0.5, 0.64, 0.42][i]
        NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * 0.1, y: bar.minY - r.height * 0.22 - CGFloat(i) * r.height * 0.09, width: w, height: r.height * 0.032), xRadius: 6, yRadius: 6).fill()
    }
}

func landscape(_ r: NSRect) {
    NSGradient(colors: [color(255, 214, 156), color(112, 186, 170), color(36, 112, 102)])!.draw(in: r, angle: 90)
    color(255, 244, 214).setFill()
    let s = r.width * 0.22
    NSBezierPath(ovalIn: NSRect(x: r.midX - s / 2, y: r.maxY - r.height * 0.42, width: s, height: s)).fill()
    let hills = NSBezierPath()
    hills.move(to: NSPoint(x: r.minX, y: r.minY + r.height * 0.34))
    hills.curve(to: NSPoint(x: r.maxX, y: r.minY + r.height * 0.26),
                controlPoint1: NSPoint(x: r.minX + r.width * 0.34, y: r.minY + r.height * 0.62),
                controlPoint2: NSPoint(x: r.minX + r.width * 0.68, y: r.minY + r.height * 0.08))
    hills.line(to: NSPoint(x: r.maxX, y: r.minY))
    hills.line(to: NSPoint(x: r.minX, y: r.minY))
    hills.close()
    color(24, 86, 74).setFill()
    hills.fill()
}

func hang(at x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat, glass: NSColor, block: (NSRect) -> Void) {
    let ctx = NSGraphicsContext.current!.cgContext
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

// 1. One large screenshot.
func iconOne() -> NSBitmapImageRep {
    drawIcon { _ in
        squircle([color(255, 248, 240), color(244, 214, 186)], rim: color(255, 255, 255, 0.45))
        let a = NSPoint(x: 150, y: 760), b = NSPoint(x: 874, y: 748)
        rope(from: a, to: b, sag: 70, width: 16, stroke: color(122, 78, 48), shine: color(255, 228, 196, 0.75))
        hang(at: 512, y: lineY(x: 512, a: a, b: b, sag: 70) + 8, w: 460, h: 500, angle: -2, glass: color(255, 252, 248, 0.72)) {
            windowCard($0, dark: false)
        }
    }
}

// 2. Night ground, one pale window.
func iconTwo() -> NSBitmapImageRep {
    drawIcon { _ in
        squircle([color(54, 48, 78), color(22, 20, 32)], rim: color(255, 255, 255, 0.14))
        let a = NSPoint(x: 160, y: 770), b = NSPoint(x: 864, y: 752)
        rope(from: a, to: b, sag: 64, width: 14, stroke: color(232, 214, 186), shine: color(255, 255, 255, 0.35))
        hang(at: 512, y: lineY(x: 512, a: a, b: b, sag: 64) + 8, w: 440, h: 480, angle: 2, glass: color(255, 255, 255, 0.16)) {
            windowCard($0, dark: true)
        }
    }
}

// 3. A drying rack: two posts and a bar, one picture.
func iconThree() -> NSBitmapImageRep {
    drawIcon { _ in
        squircle([color(214, 232, 246), color(246, 228, 206)], rim: color(255, 255, 255, 0.5))
        func post(_ x: CGFloat) {
            let r = NSRect(x: x, y: 210, width: 54, height: 560)
            let p = NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16)
            NSGraphicsContext.current!.cgContext.saveGState()
            shadow(color(40, 50, 70, 0.2), blur: 12, y: -6)
            color(176, 122, 72).setFill()
            p.fill()
            NSGraphicsContext.current!.cgContext.restoreGState()
            NSGradient(colors: [color(128, 84, 48), color(214, 168, 112), color(150, 102, 58)],
                       atLocations: [0, 0.45, 1], colorSpace: .sRGB)!.draw(in: p, angle: 0)
        }
        post(250)
        post(720)
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: 230, y: 748))
        bar.curve(to: NSPoint(x: 794, y: 748),
                  controlPoint1: NSPoint(x: 420, y: 700),
                  controlPoint2: NSPoint(x: 604, y: 700))
        NSGraphicsContext.current!.cgContext.saveGState()
        shadow(color(40, 24, 16, 0.2), blur: 8, y: -4)
        bar.lineWidth = 36
        bar.lineCapStyle = .round
        color(150, 98, 54).setStroke()
        bar.stroke()
        NSGraphicsContext.current!.cgContext.restoreGState()
        let hi = bar.copy() as! NSBezierPath
        hi.transform(using: AffineTransform(translationByX: 0, byY: 6))
        hi.lineWidth = 8
        color(236, 206, 160, 0.7).setStroke()
        hi.stroke()
        hang(at: 512, y: 690, w: 360, h: 300, angle: 0, glass: color(255, 252, 248, 0.8)) {
            landscape($0)
        }
    }
}

// 4. Three cards on a lacquer ground.
func iconFour() -> NSBitmapImageRep {
    drawIcon { _ in
        squircle([color(176, 72, 58), color(92, 28, 40)], rim: color(255, 220, 200, 0.28))
        let a = NSPoint(x: 130, y: 690), b = NSPoint(x: 894, y: 678)
        rope(from: a, to: b, sag: 48, width: 16, stroke: color(92, 48, 32), shine: color(255, 210, 180, 0.4))
        let mid = lineY(x: 512, a: a, b: b, sag: 48)
        hang(at: 300, y: lineY(x: 300, a: a, b: b, sag: 48) + 6, w: 250, h: 300, angle: -7, glass: color(255, 248, 242, 0.78)) { landscape($0) }
        hang(at: 512, y: mid + 6, w: 290, h: 390, angle: 1, glass: color(255, 248, 242, 0.82)) { windowCard($0, dark: false) }
        hang(at: 730, y: lineY(x: 730, a: a, b: b, sag: 48) + 6, w: 240, h: 290, angle: 6, glass: color(255, 248, 242, 0.78)) { r in
            color(255, 248, 242).setFill(); r.fill()
            let bars: [CGFloat] = [0.35, 0.55, 0.42, 0.72, 0.5]
            let bw = (r.width - 36) / CGFloat(bars.count)
            for (i, v) in bars.enumerated() {
                (i == 3 ? color(176, 72, 58) : color(176, 72, 58, 0.4)).setFill()
                NSBezierPath(roundedRect: NSRect(x: r.minX + 18 + CGFloat(i) * bw, y: r.minY + 28, width: bw - 10, height: (r.height - 70) * v), xRadius: 6, yRadius: 6).fill()
            }
        }
    }
}

// 5. Two cards stacked, the front one large.
func iconFive() -> NSBitmapImageRep {
    drawIcon { _ in
        squircle([color(255, 236, 214), color(232, 176, 140)], rim: color(255, 255, 255, 0.4))
        let a = NSPoint(x: 140, y: 820), b = NSPoint(x: 900, y: 800)
        rope(from: a, to: b, sag: 36, width: 16, stroke: color(122, 78, 48), shine: color(255, 228, 196, 0.7))
        hang(at: 400, y: lineY(x: 400, a: a, b: b, sag: 36) - 10, w: 340, h: 300, angle: -8, glass: color(255, 250, 244, 0.7)) { landscape($0) }
        hang(at: 600, y: lineY(x: 600, a: a, b: b, sag: 36) + 4, w: 420, h: 460, angle: 4, glass: color(255, 252, 248, 0.88)) { windowCard($0, dark: false) }
    }
}

// Icon 1's rope and large window, with a second card behind it.
func stackIcon(fill: [NSColor], rim: NSColor, ropeColor: NSColor, shine: NSColor,
               dark: Bool, glass: NSColor, back: @escaping (NSRect) -> Void) -> NSBitmapImageRep {
    drawIcon { _ in
        squircle(fill, rim: rim)
        let a = NSPoint(x: 150, y: 760), b = NSPoint(x: 874, y: 748)
        let sag: CGFloat = 70
        rope(from: a, to: b, sag: sag, width: 16, stroke: ropeColor, shine: shine)
        hang(at: 348, y: lineY(x: 348, a: a, b: b, sag: sag) + 4, w: 320, h: 280, angle: -8, glass: glass.withAlphaComponent(0.62), block: back)
        hang(at: 578, y: lineY(x: 578, a: a, b: b, sag: sag) + 8, w: 430, h: 470, angle: -1, glass: glass) {
            windowCard($0, dark: dark)
        }
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

func bars(_ r: NSRect, tones: [NSColor]) {
    color(255, 250, 246).setFill()
    r.fill()
    let bw = (r.width - 40) / CGFloat(tones.count)
    for (i, tone) in tones.enumerated() {
        tone.setFill()
        let h = r.height * [0.34, 0.52, 0.4, 0.66, 0.46][i]
        NSBezierPath(roundedRect: NSRect(x: r.minX + 20 + CGFloat(i) * bw, y: r.minY + 24, width: bw - 12, height: h), xRadius: 7, yRadius: 7).fill()
    }
}

func stackSet() -> [NSBitmapImageRep] {[
    stackIcon(fill: [color(255, 248, 240), color(244, 214, 186)], rim: color(255, 255, 255, 0.45),
              ropeColor: color(122, 78, 48), shine: color(255, 228, 196, 0.75),
              dark: false, glass: color(255, 252, 248, 0.78), back: landscape),
    stackIcon(fill: [color(54, 48, 78), color(22, 20, 32)], rim: color(255, 255, 255, 0.14),
              ropeColor: color(232, 214, 186), shine: color(255, 255, 255, 0.35),
              dark: true, glass: color(255, 255, 255, 0.16), back: landscape),
    stackIcon(fill: [color(176, 72, 58), color(92, 28, 40)], rim: color(255, 220, 200, 0.28),
              ropeColor: color(92, 48, 32), shine: color(255, 210, 180, 0.45),
              dark: false, glass: color(255, 248, 242, 0.82), back: landscape),
    stackIcon(fill: [color(255, 246, 236), color(236, 214, 232)], rim: color(255, 255, 255, 0.45),
              ropeColor: color(122, 78, 48), shine: color(255, 228, 196, 0.75),
              dark: false, glass: color(255, 252, 248, 0.8), back: { r in
                  bars(r, tones: [color(226, 59, 74), color(224, 138, 30), color(28, 154, 106), color(42, 111, 224), color(122, 69, 214)])
              }),
    stackIcon(fill: [color(232, 238, 248), color(244, 226, 216)], rim: color(255, 255, 255, 0.5),
              ropeColor: color(90, 78, 92), shine: color(255, 255, 255, 0.7),
              dark: false, glass: color(255, 252, 248, 0.8), back: water),
]}

let icons = [iconOne(), iconTwo(), iconThree(), iconFour(), iconFive()]
for (i, rep) in icons.enumerated() { save(rep, "\(i + 1).png") }

let names = ["1  一帧", "2  夜", "3  衣架", "4  三张", "5  叠放"]
let sheetW = 1480, sheetH = 560
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sheetW, pixelsHigh: sheetH,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
color(244, 242, 238).setFill()
NSRect(x: 0, y: 0, width: CGFloat(sheetW), height: CGFloat(sheetH)).fill()
let font = NSFont(name: "PingFangSC-Medium", size: 28) ?? NSFont.systemFont(ofSize: 28, weight: .medium)
for (i, rep) in icons.enumerated() {
    let x = 40 + CGFloat(i) * 292
    rep.cgImage.map { img in
        NSGraphicsContext.current!.cgContext.draw(img, in: NSRect(x: x, y: 250, width: 260, height: 260))
        NSGraphicsContext.current!.cgContext.interpolationQuality = .high
        NSGraphicsContext.current!.cgContext.draw(img, in: NSRect(x: x + 98, y: 78, width: 64, height: 64))
    }
    let title = names[i] as NSString
    title.draw(at: NSPoint(x: x + 70, y: 168), withAttributes: [
        .font: font, .foregroundColor: color(40, 36, 32)
    ])
}
NSGraphicsContext.restoreGraphicsState()
save(sheet, "sheet.png")

let stacks = stackSet()
let stackNames = ["昼", "夜", "釉", "谱", "映"]
for (i, rep) in stacks.enumerated() { save(rep, "stack-\(i + 1).png") }
let stackSheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sheetW, pixelsHigh: sheetH,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: stackSheet)
color(244, 242, 238).setFill()
NSRect(x: 0, y: 0, width: CGFloat(sheetW), height: CGFloat(sheetH)).fill()
for (i, rep) in stacks.enumerated() {
    let x = 40 + CGFloat(i) * 292
    rep.cgImage.map { img in
        NSGraphicsContext.current!.cgContext.interpolationQuality = .high
        NSGraphicsContext.current!.cgContext.draw(img, in: NSRect(x: x, y: 250, width: 260, height: 260))
        NSGraphicsContext.current!.cgContext.draw(img, in: NSRect(x: x + 98, y: 78, width: 64, height: 64))
    }
    let title = stackNames[i] as NSString
    let w = title.size(withAttributes: [.font: font]).width
    title.draw(at: NSPoint(x: x + 130 - w / 2, y: 168), withAttributes: [
        .font: font, .foregroundColor: color(40, 36, 32)
    ])
}
NSGraphicsContext.restoreGraphicsState()
save(stackSheet, "stack-sheet.png")
