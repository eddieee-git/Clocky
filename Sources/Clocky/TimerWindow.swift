import AppKit
import Combine
import SwiftUI

final class TimerWindowController: NSObject, NSWindowDelegate {
    static let contentSize = NSSize(width: 340, height: 420)

    let store = ClockStore()
    private let settings: ClockySettings
    private(set) lazy var panel: TimerPanel = makePanel()
    private var isLoaded = false
    private var pinSubscription: AnyCancellable?
    private var settingSubscriptions: Set<AnyCancellable> = []
    /// 창 왼쪽 아래 모서리. 닫았다 열어도, 앱을 다시 켜도 옮겨 둔 자리에 뜬다.
    private static let originKey = "windowOrigin"
    /// 지운 타이머·알람을 ⌘Z로 되살린다.
    private let undoManager = UndoManager()

    init(settings: ClockySettings) {
        self.settings = settings
        super.init()
        store.onRing = { [weak self] in self?.show() }
        store.undoManager = undoManager
        // 설정 창에서 바꾼 값을 바로 반영한다.
        settings.$warningSeconds.sink { [weak self] in self?.store.warningSeconds = $0 }.store(in: &settingSubscriptions)
        settings.$snoozeMinutes.sink { [weak self] in self?.store.snoozeMinutes = $0 }.store(in: &settingSubscriptions)
        settings.$soundLimitSeconds.sink { [weak self] in self?.store.soundLimit = TimeInterval($0) }.store(in: &settingSubscriptions)
        settings.$menuBarShowsAlarm.sink { [weak self] in self?.store.tracksMenuBarAlarm = $0 }.store(in: &settingSubscriptions)
        settings.$timerPresets.sink { [weak self] in self?.store.presets = $0 }.store(in: &settingSubscriptions)
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
        updateDisplayed()
        // 이름 칸이 처음부터 선택돼 있으면 어수선하다. 눌러야 편집된다.
        DispatchQueue.main.async { self.panel.makeFirstResponder(nil) }
    }

    /// 닫아도 타이머와 알람은 계속 돈다.
    func windowWillClose(_ notification: Notification) {
        store.isDisplayed = false
    }

    /// 다른 창에 완전히 가려졌거나 다른 데스크톱에 있으면 숫자판을 위해 깨어나지 않는다.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateDisplayed()
    }

    private func updateDisplayed() {
        store.isDisplayed = panel.isVisible && panel.occlusionState.contains(.visible)
    }

    func windowDidMove(_ notification: Notification) {
        let origin = panel.frame.origin
        UserDefaults.standard.set([Double(origin.x), Double(origin.y)], forKey: Self.originKey)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManager
    }

    /// 목록 창도 같은 되돌리기 기록을 쓴다.
    var sharedUndoManager: UndoManager { undoManager }

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
        var view = FlipTimerView(store: store, settings: settings)
        view.onSnoozeFrame = { [weak panel] frame in panel?.snoozeFrame = frame }
        view.onOpenList = { [weak panel] in panel?.onOpenList?() }
        view.onOpenSettings = { [weak panel] in panel?.onOpenSettings?() }
        let hosting = NSHostingView(rootView: view)
        // 내용에 따라 창 크기가 바뀌지 않게 한다. 제목 표시줄까지 내용이 덮으므로 창 전체 크기를 정한다.
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(NSRect(origin: .zero, size: Self.contentSize), display: false)
        panel.store = store
        panel.settings = settings
        panel.delegate = self
        pinSubscription = store.$isPinned.sink { [weak panel] pinned in
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
    weak var store: ClockStore?
    weak var settings: ClockySettings?
    /// 설정 창과 목록 창을 연다. 메뉴바 메뉴와 같은 단축키(⌘,·⌘L)를 이 창에서도 쓴다.
    var onOpenSettings: (() -> Void)?
    var onOpenList: (() -> Void)?
    /// 다시 울림 버튼의 자리. 창 왼쪽 위가 원점이다.
    var snoozeFrame: CGRect = .zero
    override var canBecomeKey: Bool { true }

    private enum Key {
        static let returnKey: UInt16 = 36, space: UInt16 = 49, escape: UInt16 = 53, delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117, up: UInt16 = 126, down: UInt16 = 125, s: UInt16 = 1
    }

    /// 울리는 동안에는 창 어디를 눌러도 멈춘다. 그 클릭이 시작 버튼까지 눌러 다시 돌지 않게 삼킨다.
    /// 다시 울림 버튼만은 눌리게 둔다. 키보드로는 Esc·Return·스페이스가 끄고 S가 다시 울림이다.
    override func sendEvent(_ event: NSEvent) {
        if let store, store.isRinging {
            switch event.type {
            case .leftMouseDown, .rightMouseDown:
                let point = event.locationInWindow
                let flipped = CGPoint(x: point.x, y: frame.height - point.y)
                if event.type == .leftMouseDown, snoozeFrame.contains(flipped) { break }
                store.stopRinging()
                return
            case .keyDown:
                switch event.keyCode {
                case Key.escape, Key.returnKey, Key.space: store.stopRinging(); return
                case Key.s where event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty: store.snooze(); return
                default: break
                }
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    /// 이름 칸을 고치는 중이 아닐 때 창으로 오는 키.
    /// 스페이스는 시작·일시정지(알람은 켜기·끄기), 위·아래는 목록에서 고르기, ⌘⌫는 지우기.
    override func keyDown(with event: NSEvent) {
        guard let store else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (event.keyCode, flags) {
        case (Key.space, []): store.toggleSelected()
        case (Key.up, _) where !flags.contains(.command): store.selectAdjacent(-1)
        case (Key.down, _) where !flags.contains(.command): store.selectAdjacent(1)
        case (Key.delete, .command), (Key.forwardDelete, _):
            if settings?.confirmRemoval(count: 1) ?? true { store.removeSelected() }
        case (Key.escape, []): makeFirstResponder(nil)
        default: super.keyDown(with: event)
        }
    }

    /// ⌘N은 지금 보는 쪽(타이머·알람)에 하나 더한다. ⌘1·⌘2는 타이머·알람으로 바꾼다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let store, flags == .command, event.type == .keyDown {
            switch event.charactersIgnoringModifiers {
            case "n": store.addItem(); return true
            case "1": store.mode = .timer; return true
            case "2": store.mode = .alarm; return true
            case ",": onOpenSettings?(); return true
            case "l": onOpenList?(); return true
            default: break
            }
        }
        // 메뉴바 앱은 다른 앱이 앞에 있는 채로 이 창만 키보드를 받기도 해서, 편집 메뉴를 거치지 않고 직접 되돌린다.
        // 이름 칸의 글자 되돌리기도 같은 UndoManager를 쓴다.
        if event.type == .keyDown, event.charactersIgnoringModifiers?.lowercased() == "z", let undoManager {
            if flags == .command, undoManager.canUndo { undoManager.undo(); return true }
            if flags == [.command, .shift], undoManager.canRedo { undoManager.redo(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func undo(_ sender: Any?) { undoManager?.undo() }
    @objc func redo(_ sender: Any?) { undoManager?.redo() }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(undo(_:)) { return undoManager?.canUndo ?? false }
        if item.action == #selector(redo(_:)) { return undoManager?.canRedo ?? false }
        return super.validateMenuItem(item)
    }

    /// 이름을 고치다 Esc를 누르면 편집을 끝낸다.
    override func cancelOperation(_ sender: Any?) {
        makeFirstResponder(nil)
    }
}

