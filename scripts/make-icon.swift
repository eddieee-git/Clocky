// Clocky 앱 아이콘(자명종)을 그려 Resources/AppIcon.icns와 docs/images/icon.png를 만든다.
// 실행: swift scripts/make-icon.swift
import AppKit

/// 종 두 개와 다리가 달린 자명종. 바늘은 시계 광고처럼 10시 10분을 가리킨다.
func draw(in size: CGFloat) {
    let scale = size / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)

    // 배경: macOS 아이콘 격자에 맞춘 둥근 사각형
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.55, blue: 0.30, alpha: 1),
               ending: NSColor(srgbRed: 0.93, green: 0.30, blue: 0.36, alpha: 1))!.draw(in: tile, angle: -60)

    let center = NSPoint(x: 512, y: 470)
    let dark = NSColor(white: 0.13, alpha: 1)
    func circle(_ c: NSPoint, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    func point(_ angle: CGFloat, _ radius: CGFloat) -> NSPoint {
        // 0도가 12시, 시계 방향
        let radians = (90 - angle) * .pi / 180
        return NSPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -20 * scale), blur: 46 * scale,
                      color: NSColor.black.withAlphaComponent(0.32).cgColor)
    context.beginTransparencyLayer(auxiliaryInfo: nil)

    // 다리
    dark.setStroke()
    for side in [-1.0, 1.0] as [CGFloat] {
        let leg = NSBezierPath()
        leg.lineWidth = 46
        leg.lineCapStyle = .round
        leg.move(to: NSPoint(x: center.x + side * 150, y: center.y - 230))
        leg.line(to: NSPoint(x: center.x + side * 215, y: 205))
        leg.stroke()
    }
    // 종을 치는 손잡이
    let stem = NSBezierPath()
    stem.lineWidth = 30
    stem.lineCapStyle = .round
    stem.move(to: NSPoint(x: center.x, y: center.y + 280))
    stem.line(to: NSPoint(x: center.x, y: center.y + 345))
    stem.stroke()
    dark.setFill()
    circle(NSPoint(x: center.x, y: center.y + 352), 30).fill()
    // 종 두 개: 몸통 뒤에서 위쪽 바깥으로 비져 나온 반구
    for angle in [-42.0, 42.0] as [CGFloat] {
        let c = point(angle, 270)
        circle(c, 118).fill()
    }
    // 몸통 테두리와 판
    circle(center, 300).fill()
    NSColor(srgbRed: 0.99, green: 0.97, blue: 0.93, alpha: 1).setFill()
    circle(center, 252).fill()

    context.endTransparencyLayer()
    context.restoreGState()

    // 눈금: 3·6·9·12는 길게
    for i in 0..<12 {
        let major = i % 3 == 0
        let tick = NSBezierPath()
        tick.lineWidth = major ? 22 : 12
        tick.lineCapStyle = .round
        tick.move(to: point(CGFloat(i) * 30, major ? 196 : 210))
        tick.line(to: point(CGFloat(i) * 30, 228))
        NSColor(white: 0.13, alpha: major ? 1 : 0.55).setStroke()
        tick.stroke()
    }
    // 바늘: 10시 10분
    func hand(_ angle: CGFloat, length: CGFloat, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.move(to: point(angle + 180, length * 0.14))
        path.line(to: point(angle, length))
        color.setStroke()
        path.stroke()
    }
    hand(305, length: 132, width: 30, color: dark)
    hand(60, length: 186, width: 22, color: dark)
    hand(160, length: 196, width: 9, color: NSColor(srgbRed: 0.93, green: 0.32, blue: 0.30, alpha: 1))
    dark.setFill()
    circle(center, 26).fill()
    NSColor(srgbRed: 0.93, green: 0.32, blue: 0.30, alpha: 1).setFill()
    circle(center, 11).fill()
}

func png(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(in: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(256).write(to: root.appendingPathComponent("docs/images/icon.png"))

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
task.launch()
task.waitUntilExit()
print("Resources/AppIcon.icns")
