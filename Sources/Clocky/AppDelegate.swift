import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = ClockySettings()
    private(set) lazy var window = TimerWindowController(settings: settings)
    private(set) lazy var settingsWindow = SettingsWindowController(settings: settings)
    private(set) lazy var listWindow: ListWindowController = {
        let model = ClockListModel(store: window.store, settings: settings)
        model.onReveal = { [weak self] id in self?.reveal(id) }
        return ListWindowController(model: model, undoManager: window.sharedUndoManager)
    }()
    private(set) var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    /// 메뉴를 열 때마다 새로 만드는 타이머·알람 상태 줄.
    private var statusLineItems: [NSMenuItem] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var showingAlarmIcon = false
    private var hotKeys: [HotKey] = []

    private static let launchedKey = "hasLaunched"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.make()
        item.button?.imagePosition = .imageLeading
        statusItem = item
        rebuildStatusMenu()
        window.panel.onOpenSettings = { [weak self] in self?.showSettings() }
        window.panel.onOpenList = { [weak self] in self?.showList() }

        // 타이머가 도는 동안 메뉴바에 남은 시간을 띄운다.
        window.store.$now.combineLatest(window.store.$timers, window.store.$alarms)
            .sink { [weak self] _, _, _ in self?.updateStatusTitle() }
            .store(in: &subscriptions)
        // 단축키를 새로 누르는 동안에는 모두 풀어 둔다.
        settings.$hotKeys.combineLatest(settings.$isRecordingHotKey)
            .sink { [weak self] combos, isRecording in self?.registerHotKeys(isRecording ? [:] : combos) }
            .store(in: &subscriptions)
        // 설정에서 메뉴바 표시를 바꾸면 바로 고친다.
        settings.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.updateStatusTitle() } }
            .store(in: &subscriptions)
        NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildStatusMenu()
            self?.buildMainMenu()
        }

        // 처음 실행하면 무엇이 생겼는지 보이도록 창을 띄운다.
        if !UserDefaults.standard.bool(forKey: Self.launchedKey) {
            UserDefaults.standard.set(true, forKey: Self.launchedKey)
            window.show()
        }
    }

    /// 미뤄 둔 저장을 마저 한다.
    func applicationWillTerminate(_ notification: Notification) {
        window.store.save()
    }

    /// 메뉴바 아이콘을 누르지 않고 앱을 다시 열면(Finder에서 더블클릭 등) 창을 보여 준다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.show()
        return false
    }

    /// 여러 타이머가 돌면 가장 먼저 끝나는 것을 보여 준다. 도는 것이 없으면 일시정지한 것 중에서 고른다.
    private func updateStatusTitle() {
        let store = window.store
        let now = store.now
        let active = store.timers.filter { $0.phase == .ringing }.first
            ?? store.timers.filter { $0.phase == .running }.min { $0.remaining(at: now) < $1.remaining(at: now) }
        let paused = store.timers.filter { $0.phase == .paused }.min { $0.remaining(at: now) < $1.remaining(at: now) }
        var title = ""
        // 도는 타이머가 없으면 1시간 안에 울릴 알람까지 남은 시간을 알람 시계 모양과 함께 보여 준다.
        // 그것도 없으면 일시정지한 타이머를 보여 준다.
        var showsAlarm = false
        if let active, settings.menuBarShowsTimer {
            title = " " + clockText(active.remaining(at: now))
        } else if active == nil || !settings.menuBarShowsTimer, settings.menuBarShowsAlarm,
                  let soonest = store.upcomingAlarms.first?.upcoming,
                  case let left = soonest.timeIntervalSince(now), left > 0 && left <= ClockStore.menuBarAlarmWindow {
            title = " " + clockText(Int(ceil(left - 0.001)))
            showsAlarm = true
        } else if let paused, settings.menuBarShowsTimer {
            title = " " + clockText(paused.remaining(at: now))
        }
        if showsAlarm != showingAlarmIcon, let button = statusItem?.button {
            showingAlarmIcon = showsAlarm
            button.image = showsAlarm ? MenuBarIcon.alarm() : MenuBarIcon.make()
        }
        guard let button = statusItem?.button, button.title != title else { return }
        button.title = title
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    // MARK: 메뉴

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Clocky 열기"), action: #selector(showWindow), keyEquivalent: "").target = self
        statusLineItems = []
        menu.addItem(.separator())
        menu.addItem(withTitle: L("전체 목록…"), action: #selector(showList), keyEquivalent: "l").target = self
        menu.addItem(withTitle: L("설정…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Clocky 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem?.menu = menu
        statusMenu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatusLines(in: menu)
    }

    /// "Clocky 열기" 바로 아래에 도는·멈춘 타이머와 켜 둔 알람을 한 줄씩 넣는다. 누르면 그 항목을 창에 띄운다.
    private func updateStatusLines(in menu: NSMenu) {
        statusLineItems.forEach(menu.removeItem)
        statusLineItems = []
        let store = window.store
        let now = Date()
        var lines: [(String, String)] = []
        for item in store.timers {
            let name = store.displayName(of: item)
            switch item.phase {
            case .running: lines.append((L("%@ · %@ 남음", name, clockText(item.remaining(at: now))), "timer:\(item.id)"))
            case .paused: lines.append((L("%@ · 일시정지 %@", name, clockText(item.remaining(at: now))), "timer:\(item.id)"))
            case .idle, .ringing: break
            }
        }
        for item in store.upcomingAlarms {
            guard let next = item.upcoming else { continue }
            lines.append((L("%@ · %@ (%@ 남음)", store.displayName(of: item), settings.timeText(next),
                            remainingText(until: next, from: now)), "alarm:\(item.id)"))
        }
        for (index, line) in lines.enumerated() {
            let item = NSMenuItem(title: line.0, action: #selector(showItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = line.1
            menu.insertItem(item, at: 1 + index)
            statusLineItems.append(item)
        }
    }

    private func registerHotKeys(_ combos: [String: KeyCombo]) {
        hotKeys = []
        var failed = Set<HotKeyAction>()
        for (index, action) in HotKeyAction.allCases.enumerated() {
            guard let combo = combos[action.rawValue] else { continue }
            if let hotKey = HotKey(id: UInt32(index + 1), combo: combo, action: { [weak self] in self?.perform(action) }) {
                hotKeys.append(hotKey)
            } else {
                failed.insert(action)
            }
        }
        if settings.failedHotKeys != failed { settings.failedHotKeys = failed }
    }

    func perform(_ action: HotKeyAction) {
        let store = window.store
        switch action {
        case .toggleClock:
            if window.isVisible && window.panel.isKeyWindow { window.panel.close() } else { window.show() }
        case .toggleTimer:
            store.toggle(store.selectedTimerID)
        case .stopRinging:
            store.stopRinging()
        case .showList:
            showList()
        }
    }

    @objc private func showWindow() {
        window.show()
    }

    @objc func showSettings() {
        settingsWindow.show()
    }

    @objc func showList() {
        listWindow.show()
    }

    /// 목록에서 고른 항목을 시계 창에 띄운다.
    func reveal(_ id: UUID) {
        let store = window.store
        if store.timers.contains(where: { $0.id == id }) {
            store.selectedTimerID = id
            store.mode = .timer
        } else if store.alarms.contains(where: { $0.id == id }) {
            store.selectedAlarmID = id
            store.mode = .alarm
        }
        window.show()
    }

    @objc private func showItem(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let id = key.split(separator: ":").last.flatMap({ UUID(uuidString: String($0)) }) else { return window.show() }
        reveal(id)
    }

    /// 메뉴바 전용 앱이라 보이지 않지만, 이름 칸에서 ⌘C·⌘V·⌘Z가 동작하려면 주 메뉴가 있어야 한다.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = main.addItem(withTitle: "Clocky", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("설정…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: L("전체 목록…"), action: #selector(showList), keyEquivalent: "l").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Clocky 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = main.addItem(withTitle: L("편집"), action: nil, keyEquivalent: "")
        let edit = NSMenu(title: L("편집"))
        edit.addItem(withTitle: L("실행 취소"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("실행 복귀"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("잘라내기"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("복사하기"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("붙여넣기"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("전체 선택"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}
