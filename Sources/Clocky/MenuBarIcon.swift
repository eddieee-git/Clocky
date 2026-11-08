import AppKit

/// 메뉴바 아이콘. 앱 아이콘과 같은 자명종 모양이다.
/// 템플릿 이미지라 메뉴바의 밝기에 맞춰 색이 바뀐다.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let center = NSPoint(x: 9, y: 8.4)
            NSColor.black.set()
            // 종 두 개
            for x in [4.1, 13.9] {
                NSBezierPath(ovalIn: NSRect(x: x - 2.4, y: 12.0, width: 4.8, height: 4.8)).fill()
            }
            // 다리
            for side in [-1.0, 1.0] {
                let leg = NSBezierPath()
                leg.lineWidth = 1.5
                leg.lineCapStyle = .round
                leg.move(to: NSPoint(x: center.x + side * 3.4, y: center.y - 4.6))
                leg.line(to: NSPoint(x: center.x + side * 5.4, y: 1.0))
                leg.stroke()
            }
            // 몸통: 테두리만 남기고 속을 비운다
            NSBezierPath(ovalIn: NSRect(x: center.x - 6.4, y: center.y - 6.4, width: 12.8, height: 12.8)).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: center.x - 4.9, y: center.y - 4.9, width: 9.8, height: 9.8)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            // 바늘: 짧은 시침은 10시, 긴 분침은 12시 쪽으로
            let hands = NSBezierPath()
            hands.lineWidth = 1.4
            hands.lineCapStyle = .round
            hands.lineJoinStyle = .round
            hands.move(to: NSPoint(x: center.x - 2.3, y: center.y + 1.0))
            hands.line(to: center)
            hands.line(to: NSPoint(x: center.x + 0.6, y: center.y + 3.8))
            hands.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clocky"
        return image
    }

    /// 1시간 안에 울릴 알람이 있을 때 쓰는 종 모양.
    static func alarm() -> NSImage {
        let image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Clocky")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? make()
        image.isTemplate = true
        return image
    }
}
