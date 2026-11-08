import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = ClockySettings()
    private(set) lazy var window = FlipTimerWindowController(settings: settings)
    private(set) var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    /// 메뉴를 열 때마다 새로 만드는 타이머·알람 상태 줄.
    private var statusLineItems: [NSMenuItem] = []
    private var subscriptions: Set<AnyCancellable> = []

    private static let launchedKey = "hasLaunched"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.make()
        item.button?.imagePosition = .imageLeading
        statusItem = item
        rebuildStatusMenu()

        // 타이머가 도는 동안 메뉴바에 남은 시간을 띄운다.
        window.timer.$now.combineLatest(window.timer.$timers)
            .sink { [weak self] _, _ in self?.updateStatusTitle() }
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

    /// 메뉴바 아이콘을 누르지 않고 앱을 다시 열면(Finder에서 더블클릭 등) 창을 보여 준다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.show()
        return false
    }

    /// 여러 타이머가 돌면 가장 먼저 끝나는 것을 보여 준다. 도는 것이 없으면 일시정지한 것 중에서 고른다.
    private func updateStatusTitle() {
        let timer = window.timer
        let now = timer.now
        let shown = timer.timers.filter { $0.phase == .ringing }.first
            ?? timer.timers.filter { $0.phase == .running }.min { $0.remaining(at: now) < $1.remaining(at: now) }
            ?? timer.timers.filter { $0.phase == .paused }.min { $0.remaining(at: now) < $1.remaining(at: now) }
        let title = shown.map { " " + clockText($0.remaining(at: now)) } ?? ""
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

        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = languageMenu.addItem(withTitle: language.title, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = settings.language == language ? .on : .off
        }
        menu.addItem(withTitle: L("언어"), action: nil, keyEquivalent: "").submenu = languageMenu

        let soundMenu = NSMenu()
        soundMenu.delegate = self
        menu.addItem(withTitle: L("알람 소리"), action: nil, keyEquivalent: "").submenu = soundMenu

        let login = menu.addItem(withTitle: L("로그인 시 자동 실행"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.isEnabled = settings.canLaunchAtLogin
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Clocky 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem?.menu = menu
        statusMenu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu {
            updateStatusLines(in: menu)
            menu.items.first { $0.action == #selector(toggleLaunchAtLogin) }?.state = settings.launchAtLogin ? .on : .off
            return
        }
        // 알람 소리 하위 메뉴
        menu.removeAllItems()
        for name in AlarmSound.choices {
            let item = menu.addItem(withTitle: name, action: #selector(chooseSound(_:)), keyEquivalent: "")
            item.target = self
            item.state = settings.alarmSound == name ? .on : .off
        }
    }

    /// "Clocky 열기" 바로 아래에 도는·멈춘 타이머와 켜 둔 알람을 한 줄씩 넣는다. 누르면 그 항목을 창에 띄운다.
    private func updateStatusLines(in menu: NSMenu) {
        statusLineItems.forEach(menu.removeItem)
        statusLineItems = []
        let timer = window.timer
        let now = Date()
        var lines: [(String, String)] = []
        for item in timer.timers {
            let name = timer.displayName(of: item)
            switch item.phase {
            case .running: lines.append((L("%@ · %@ 남음", name, clockText(item.remaining(at: now))), "timer:\(item.id)"))
            case .paused: lines.append((L("%@ · 일시정지 %@", name, clockText(item.remaining(at: now))), "timer:\(item.id)"))
            case .idle, .ringing: break
            }
        }
        for item in timer.upcomingAlarms {
            guard let next = item.next else { continue }
            lines.append((L("%@ · %@ (%@ 남음)", timer.displayName(of: item), settings.timeText(next),
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

    @objc private func showWindow() {
        window.show()
    }

    @objc private func showItem(_ sender: NSMenuItem) {
        let timer = window.timer
        if let key = sender.representedObject as? String {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let id = UUID(uuidString: parts[1]) {
                if parts[0] == "timer", timer.timers.contains(where: { $0.id == id }) {
                    timer.selectedTimerID = id
                    timer.mode = .timer
                } else if parts[0] == "alarm", timer.alarms.contains(where: { $0.id == id }) {
                    timer.selectedAlarmID = id
                    timer.mode = .alarm
                }
            }
        }
        window.show()
    }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        settings.language = language
    }

    /// 고르면 바로 들려준다.
    @objc private func chooseSound(_ sender: NSMenuItem) {
        settings.alarmSound = sender.title
        AlarmSound.play()
    }

    @objc private func toggleLaunchAtLogin() {
        settings.setLaunchAtLogin(!settings.launchAtLogin)
    }

    /// 메뉴바 전용 앱이라 보이지 않지만, 이름 칸에서 ⌘C·⌘V·⌘Z가 동작하려면 주 메뉴가 있어야 한다.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = main.addItem(withTitle: "Clocky", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
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
