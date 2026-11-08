import AppKit

/// 메뉴바 아이콘. 가운데가 갈라진 숫자판 두 장, 넘김시계 모양이다.
/// 템플릿 이미지라 메뉴바의 밝기에 맞춰 색이 바뀐다.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            for x in [1.5, 9.75] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 3, width: 6.75, height: 12), xRadius: 1.6, yRadius: 1.6).fill()
            }
            // 판이 접히는 가운데 틈을 비운다.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(rect: NSRect(x: 0, y: 8.4, width: 18, height: 1.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clocky"
        return image
    }

    /// 1시간 안에 울릴 알람이 있을 때 쓰는 알람 시계 모양.
    static func alarm() -> NSImage {
        let image = NSImage(systemSymbolName: "alarm", accessibilityDescription: "Clocky")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? make()
        image.isTemplate = true
        return image
    }
}
