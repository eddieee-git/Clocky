// Clocky 앱 아이콘을 그려 Resources/AppIcon.icns와 docs/images/icon.png를 만든다.
// 실행: swift scripts/make-icon.swift
import AppKit

func draw(in size: CGFloat) {
    let scale = size / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)

    // 배경: macOS 아이콘 격자에 맞춘 둥근 사각형
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.55, blue: 0.30, alpha: 1),
               ending: NSColor(srgbRed: 0.93, green: 0.30, blue: 0.36, alpha: 1))!.draw(in: tile, angle: -60)

    // 숫자판 두 장
    let cardSize = NSSize(width: 300, height: 400)
    let gap: CGFloat = 36
    let originY: CGFloat = 512 - cardSize.height / 2
    let digits = ["1", "2"]
    for (i, digit) in digits.enumerated() {
        let x = 512 - gap / 2 - cardSize.width + CGFloat(i) * (cardSize.width + gap)
        let card = NSBezierPath(roundedRect: NSRect(origin: NSPoint(x: x, y: originY), size: cardSize), xRadius: 44, yRadius: 44)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -24 * scale), blur: 50 * scale,
                          color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor(white: 0.12, alpha: 1).setFill()
        card.fill()
        context.restoreGState()

        // 위쪽 반은 조금 밝게 해서 판이 두 장 겹친 느낌을 낸다.
        context.saveGState()
        card.addClip()
        NSColor(white: 0.17, alpha: 1).setFill()
        NSRect(x: x, y: 512, width: cardSize.width, height: cardSize.height / 2).fill()
        context.restoreGState()

        let font = NSFont.systemFont(ofSize: 330, weight: .bold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 330) } ?? font
        let text = NSAttributedString(string: digit, attributes: [.font: rounded, .foregroundColor: NSColor(white: 0.96, alpha: 1)])
        let bounds = text.size()
        text.draw(at: NSPoint(x: x + (cardSize.width - bounds.width) / 2, y: 512 - bounds.height / 2 + 6))

        // 판이 접히는 가운데 틈과 양옆의 경첩
        NSColor(white: 0.05, alpha: 1).setFill()
        NSRect(x: x, y: 506, width: cardSize.width, height: 12).fill()
        NSColor(white: 0.35, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 10, y: 494, width: 22, height: 36), xRadius: 6, yRadius: 6).fill()
        NSBezierPath(roundedRect: NSRect(x: x + cardSize.width - 12, y: 494, width: 22, height: 36), xRadius: 6, yRadius: 6).fill()
    }
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
