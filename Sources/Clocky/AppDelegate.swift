import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = ClockySettings()
    private(set) lazy var window = FlipTimerWindowController(settings: settings)
    private(set) var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    /// 메뉴를 열 때마다 바꾸는 타이머·알람 상태 줄.
    private var timerStatusItem: NSMenuItem?
    private var alarmStatusItem: NSMenuItem?
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
        window.timer.$now.combineLatest(window.timer.$phase)
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

    private func updateStatusTitle() {
        let timer = window.timer
        let title: String
        switch timer.phase {
        case .running, .paused, .ringing:
            let s = timer.remaining
            title = s >= 3600 ? String(format: " %d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                              : String(format: " %d:%02d", s / 60, s % 60)
        case .idle:
            title = ""
        }
        guard let button = statusItem?.button, button.title != title else { return }
        button.title = title
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    // MARK: 메뉴

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Clocky 열기"), action: #selector(showWindow), keyEquivalent: "").target = self
        timerStatusItem = menu.addItem(withTitle: "", action: #selector(showWindow), keyEquivalent: "")
        timerStatusItem?.target = self
        alarmStatusItem = menu.addItem(withTitle: "", action: #selector(showWindow), keyEquivalent: "")
        alarmStatusItem?.target = self
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
            let timer = window.timer
            switch timer.phase {
            case .running:
                timerStatusItem?.title = L("타이머 %@ 남음", clockText(timer.remaining))
            case .paused:
                timerStatusItem?.title = L("타이머 일시정지 · %@", clockText(timer.remaining))
            case .idle, .ringing:
                timerStatusItem?.title = ""
            }
            timerStatusItem?.isHidden = timerStatusItem?.title.isEmpty ?? true
            if let next = timer.nextAlarm {
                alarmStatusItem?.title = L("알람 %@ · %@ 남음", settings.timeText(next), remainingText(until: next, from: Date()))
                alarmStatusItem?.isHidden = false
            } else {
                alarmStatusItem?.isHidden = true
            }
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

    private func clockText(_ seconds: Int) -> String {
        seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                        : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @objc private func showWindow() {
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
