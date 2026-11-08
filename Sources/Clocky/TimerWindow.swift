import AppKit
import Combine
import SwiftUI

final class FlipTimerWindowController: NSObject, NSWindowDelegate {
    static let contentSize = NSSize(width: 340, height: 420)

    let timer = FlipTimer()
    private let settings: ClockySettings
    private(set) lazy var panel: TimerPanel = makePanel()
    private var isLoaded = false
    private var pinSubscription: AnyCancellable?
    /// 창 왼쪽 아래 모서리. 닫았다 열어도, 앱을 다시 켜도 옮겨 둔 자리에 뜬다.
    private static let originKey = "windowOrigin"
    /// 지운 타이머·알람을 ⌘Z로 되살린다.
    private let undoManager = UndoManager()

    init(settings: ClockySettings) {
        self.settings = settings
        super.init()
        timer.onRing = { [weak self] in self?.show() }
        timer.undoManager = undoManager
        // 타이머를 띄워 둔 모니터를 빼면 남은 화면으로 옮긴다.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.ensureOnScreen()
        }
    }

    var isVisible: Bool { isLoaded && panel.isVisible }
    var frame: NSRect { panel.frame }
    func setFrame(_ frame: NSRect) { panel.setFrame(frame, display: false) }

    func show() {
        if !panel.isVisible { panel.setFrameOrigin(savedOrigin() ?? defaultOrigin()) }
        panel.orderFrontRegardless()
        panel.makeKey()
        timer.isDisplayed = true
        // 이름 칸이 처음부터 선택돼 있으면 어수선하다. 눌러야 편집된다.
        DispatchQueue.main.async { self.panel.makeFirstResponder(nil) }
    }

    /// 닫아도 타이머와 알람은 계속 돈다.
    func windowWillClose(_ notification: Notification) {
        timer.isDisplayed = false
    }

    func windowDidMove(_ notification: Notification) {
        let origin = panel.frame.origin
        UserDefaults.standard.set([Double(origin.x), Double(origin.y)], forKey: Self.originKey)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManager
    }

    /// 창의 윗부분이 어느 화면에도 충분히 걸쳐 있지 않으면 기본 자리로 옮긴다.
    func ensureOnScreen() {
        guard isVisible else { return }
        if !Self.isReachable(panel.frame) { panel.setFrameOrigin(defaultOrigin()) }
    }

    /// 제목 표시줄 자리를 잡고 끌 수 있을 만큼 화면에 걸쳐 있는지.
    private static func isReachable(_ frame: NSRect) -> Bool {
        let top = NSRect(x: frame.minX, y: frame.maxY - 30, width: frame.width, height: 30)
        return NSScreen.screens.contains { screen in
            let visible = screen.visibleFrame.intersection(top)
            return visible.width >= 60 && visible.height >= 15
        }
    }

    /// 저장해 둔 자리. 그 모니터를 뺐으면 쓰지 않는다.
    private func savedOrigin() -> NSPoint? {
        guard let values = UserDefaults.standard.array(forKey: Self.originKey) as? [Double], values.count == 2 else { return nil }
        let origin = NSPoint(x: values[0], y: values[1])
        return Self.isReachable(NSRect(origin: origin, size: panel.frame.size)) ? origin : nil
    }

    private func makePanel() -> TimerPanel {
        isLoaded = true
        let panel = TimerPanel(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                               styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        let hosting = NSHostingView(rootView: FlipTimerView(timer: timer, settings: settings))
        // 내용에 따라 창 크기가 바뀌지 않게 한다. 제목 표시줄까지 내용이 덮으므로 창 전체 크기를 정한다.
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(NSRect(origin: .zero, size: Self.contentSize), display: false)
        panel.timer = timer
        panel.delegate = self
        pinSubscription = timer.$isPinned.sink { [weak panel] pinned in
            panel?.level = pinned ? .floating : .normal
        }
        return panel
    }

    /// 마우스가 있는 화면의 오른쪽 위.
    private func defaultOrigin() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(x: screen.maxX - panel.frame.width - 24, y: screen.maxY - panel.frame.height - 24)
    }
}

final class TimerPanel: NSPanel {
    weak var timer: FlipTimer?
    override var canBecomeKey: Bool { true }

    /// 울리는 동안에는 창 어디를 눌러도 멈춘다. 그 클릭이 시작 버튼까지 눌러 다시 돌지 않게 삼킨다.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown, let timer, timer.isRinging {
            timer.stopRinging()
            return
        }
        super.sendEvent(event)
    }
}

