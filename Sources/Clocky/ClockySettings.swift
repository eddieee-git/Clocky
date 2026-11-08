import AppKit
import ServiceManagement

/// 앱 화면 언어. 메뉴에서 고르면 바로 바뀐다.
enum AppLanguage: String, CaseIterable {
    case korean = "ko"
    case english = "en"

    /// 언어 이름은 그 언어로 쓴다.
    var title: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    /// 처음에는 Mac의 언어를 따르고, 한국어가 아니면 영어로 시작한다.
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english
    }
}

/// 메뉴에서 바꾸는 설정. 창 화면은 이것을 지켜보다 다시 그린다.
final class ClockySettings: ObservableObject {
    private enum Keys {
        static let language = "language", alarmSound = "alarmSound", volume = "soundVolume"
        static let warning = "warningSeconds", snooze = "snoozeMinutes", soundLimit = "soundLimitSeconds"
        static let menuBarTimer = "menuBarShowsTimer", menuBarAlarm = "menuBarShowsAlarm", confirmDelete = "confirmDelete"
    }
    static let warningChoices = [0, 5, 10, 30, 60]
    static let snoozeChoices = [1, 3, 5, 10, 15, 30]
    static let soundLimitChoices = [10, 30, 60, 180, 300]
    private let defaults = UserDefaults.standard

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            Localization.language = language
        }
    }
    /// 시스템 사운드 이름.
    @Published var alarmSound: String {
        didSet {
            defaults.set(alarmSound, forKey: Keys.alarmSound)
            AlarmSound.name = alarmSound
        }
    }
    /// 알람 소리 크기. 0~1.
    @Published var soundVolume: Double {
        didSet {
            defaults.set(soundVolume, forKey: Keys.volume)
            AlarmSound.volume = Float(soundVolume)
        }
    }
    /// 끝나기 몇 초 전부터 창을 깜빡일지. 0이면 깜빡이지 않는다.
    @Published var warningSeconds: Int { didSet { defaults.set(warningSeconds, forKey: Keys.warning) } }
    @Published var snoozeMinutes: Int { didSet { defaults.set(snoozeMinutes, forKey: Keys.snooze) } }
    /// 끄지 않으면 소리를 몇 초까지 되풀이할지. 깜빡임은 끌 때까지 계속된다.
    @Published var soundLimitSeconds: Int { didSet { defaults.set(soundLimitSeconds, forKey: Keys.soundLimit) } }
    @Published var menuBarShowsTimer: Bool { didSet { defaults.set(menuBarShowsTimer, forKey: Keys.menuBarTimer) } }
    @Published var menuBarShowsAlarm: Bool { didSet { defaults.set(menuBarShowsAlarm, forKey: Keys.menuBarAlarm) } }
    /// 지우기 전에 묻는다. 꺼 두어도 ⌘Z로 되살릴 수 있다.
    @Published var confirmDelete: Bool { didSet { defaults.set(confirmDelete, forKey: Keys.confirmDelete) } }
    /// 시스템의 로그인 항목에 저장되므로 UserDefaults에 두지 않는다.
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// `swift run`으로 실행하면 번들이 없어 로그인 항목에 등록할 수 없다.
    var canLaunchAtLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    init() {
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init) ?? .systemDefault
        alarmSound = defaults.string(forKey: Keys.alarmSound).flatMap { AlarmSound.choices.contains($0) ? $0 : nil }
            ?? AlarmSound.defaultName
        soundVolume = min(max(defaults.object(forKey: Keys.volume) as? Double ?? 1, 0), 1)
        warningSeconds = (defaults.object(forKey: Keys.warning) as? Int).flatMap { Self.warningChoices.contains($0) ? $0 : nil } ?? 10
        snoozeMinutes = (defaults.object(forKey: Keys.snooze) as? Int).flatMap { Self.snoozeChoices.contains($0) ? $0 : nil } ?? 5
        soundLimitSeconds = (defaults.object(forKey: Keys.soundLimit) as? Int)
            .flatMap { Self.soundLimitChoices.contains($0) ? $0 : nil } ?? 60
        menuBarShowsTimer = defaults.object(forKey: Keys.menuBarTimer) as? Bool ?? true
        menuBarShowsAlarm = defaults.object(forKey: Keys.menuBarAlarm) as? Bool ?? true
        confirmDelete = defaults.bool(forKey: Keys.confirmDelete)
        Localization.language = language
        AlarmSound.name = alarmSound
        AlarmSound.volume = Float(soundVolume)
    }

    /// 지우기 전에 확인을 켜 두었으면 묻는다. 지워도 되면 true.
    func confirmRemoval(count: Int) -> Bool {
        guard confirmDelete else { return true }
        let alert = NSAlert()
        alert.messageText = count == 1 ? L("지울까요?") : L("%d개를 지울까요?", count)
        alert.informativeText = L("지운 뒤에도 ⌘Z로 되살릴 수 있습니다.")
        alert.addButton(withTitle: L("삭제"))
        alert.addButton(withTitle: L("취소"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func setLaunchAtLogin(_ isOn: Bool) {
        do {
            if isOn { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSAlert(error: error).runModal()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// "오전 9:00" 또는 "9:00 AM".
    func timeText(_ date: Date) -> String {
        formatter(language == .korean ? "a h:mm" : "h:mm a").string(from: date)
    }

    /// "오늘", "내일", 그 뒤는 "수요일"·"Wednesday".
    func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("오늘") }
        if calendar.isDateInTomorrow(date) { return L("내일") }
        return formatter("EEEE").string(from: date)
    }

    /// 목록을 그릴 때마다 만들지 않도록 언어·형식마다 하나씩 둔다. 시간대가 바뀌면 다시 만든다.
    private var formatters: [String: DateFormatter] = [:]

    private func formatter(_ format: String) -> DateFormatter {
        let key = "\(language.rawValue)|\(format)|\(TimeZone.current.identifier)"
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .korean ? "ko_KR" : "en_US")
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }
}

/// 타이머와 알람이 끝났을 때 내는 소리.
enum AlarmSound {
    static let defaultName = "Glass"
    static let choices = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                          "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    static var name = defaultName
    static var volume: Float = 1
    /// 앞 소리가 끝나기 전에 다시 내려면 같은 객체를 멈췄다 다시 틀어야 한다.
    private static var current: NSSound?

    static func play() {
        current?.stop()
        current = NSSound(named: name)
        current?.volume = volume
        current?.play()
    }

    static func stop() {
        current?.stop()
        current = nil
    }
}

enum Localization {
    /// 바뀌면 메뉴를 다시 만든다.
    static var language = AppLanguage.systemDefault {
        didSet {
            guard language != oldValue else { return }
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
    static let didChange = Notification.Name("ClockyLanguageDidChange")

    /// 화면 문구는 한국어를 열쇠로 쓰고, 영어일 때 이 표에서 바꾼다. 표에 없으면 한국어가 그대로 나온다.
    static let english: [String: String] = [
        // 메뉴
        "Clocky 열기": "Open Clocky",
        "%@ · 일시정지 %@": "%@ · paused %@",
        "%@ · %@ (%@ 남음)": "%@ · %@ (in %@)",
        "언어": "Language",
        "알람 소리": "Alarm Sound",
        "로그인 시 자동 실행": "Open at Login",
        "Clocky 종료": "Quit Clocky",
        // 창
        "이름": "Name",
        "타이머": "Timer",
        "알람": "Alarm",
        "항상 위": "Always on Top",
        "항상 위 해제": "Turn Off Always on Top",
        "직접…": "Custom…",
        "시작": "Start",
        "일시정지": "Pause",
        "계속": "Resume",
        "초기화": "Reset",
        "알람 추가를 눌러 시각을 등록합니다": "Click Add Alarm to set a time",
        // 목록
        "타이머 %d": "Timer %d",
        "창을 누르거나 Esc로 끄기": "Click the window or press Esc to stop",
        "%d분 뒤 다시 울림": "Snooze %d min",
        "S 키로도 됩니다": "You can also press S",
        "다시 울림": "Snoozed",
        "반복": "Repeat",
        "평일": "Weekdays",
        "주말": "Weekends",
        "일": "Sun", "월": "Mon", "화": "Tue", "수": "Wed", "목": "Thu", "금": "Fri", "토": "Sat",
        "켜짐": "On",
        "꺼짐": "Off",
        "%@ 시작": "Start %@",
        "%@ 일시정지": "Pause %@",
        "%@ 삭제": "Delete %@",
        "%@ 켜기": "%@ on",
        "고르기": "Select",
        "알람 %d": "Alarm %d",
        "타이머 %d개": "Timers: %d",
        "알람 %d개": "Alarms: %d",
        "타이머 추가": "Add Timer",
        "알람 추가": "Add Alarm",
        "등록된 알람이 없습니다": "No alarms yet",
        "삭제": "Delete",
        "삭제 (⌘Z로 되돌리기)": "Delete (⌘Z to undo)",
        "타이머 삭제": "Delete Timer",
        "알람 삭제": "Delete Alarm",
        "대기": "Ready",
        "진행 중": "Running",
        "일시정지됨": "Paused",
        "울림": "Ringing",
        "한 번": "Once",
        "%@ · %@ 남음": "%@ · %@ left",
        "%@ · 꺼짐": "%@ · off",
        "매일": "Daily",
        "켜기": "On",
        "알람 꺼짐": "Alarm off",
        "오늘": "today",
        "내일": "tomorrow",
        "%@ %@에 울림 · %@ 남음": "Rings %@ at %@ · in %@",
        "시간 입력": "Set Time",
        "분, 분:초, 또는 시:분:초로 입력합니다. 예: 90, 5:30, 1:30:00": "Enter minutes, m:ss, or h:mm:ss. For example: 90, 5:30, 1:30:00",
        "설정": "Set",
        "취소": "Cancel",
        // 남은 시간
        "%d일 %d시간": "%dd %dh",
        "%d일": "%dd",
        "%d시간 %d분": "%dh %dm",
        "%d시간": "%dh",
        "%d분": "%dm",
        "%d초": "%ds",
        // 설정 창
        "Clocky 설정": "Clocky Settings",
        "설정…": "Settings…",
        "일반": "General",
        "타이머·알람": "Timers & Alarms",
        "소리": "Sound",
        "단축키": "Shortcuts",
        "삭제하기 전에 확인": "Confirm before deleting",
        "메뉴바": "Menu Bar",
        "타이머 남은 시간 표시": "Show timer countdown",
        "1시간 안에 울릴 알람까지 남은 시간 표시": "Show countdown to alarms within an hour",
        "미리 깜빡이기": "Flash before ringing",
        "깜빡이지 않음": "Don't flash",
        "%d초 전부터": "%d seconds before",
        "다시 울림 간격": "Snooze length",
        "소리를 되풀이하는 시간": "Keep ringing for",
        "소리가 멈춘 뒤에도 끌 때까지 창은 깜빡입니다.": "The window keeps flashing until you stop it, even after the sound ends.",
        "소리 크기": "Volume",
        "들어 보기": "Preview",
        "Mac의 소리를 꺼 두면 알람도 들리지 않습니다.": "If your Mac is muted, alarms are silent too.",
        "시계 창": "Clock Window",
        "어디서나": "Anywhere",
        "스페이스": "Space",
        "고른 타이머 시작·일시정지, 고른 알람 켜기·끄기": "Start or pause the timer, turn the alarm on or off",
        "목록에서 고르기": "Select in the list",
        "타이머 또는 알람 추가": "Add a timer or alarm",
        "고른 항목 지우기": "Delete the selected item",
        "지운 항목 되살리기, 다시 지우기": "Undo or redo a delete",
        "타이머, 알람": "Timers, alarms",
        "울림 끄기, 이름 편집 끝내기": "Stop ringing, finish editing a name",
        "울리는 동안 다시 울림": "Snooze while ringing",
        "지울까요?": "Delete this item?",
        "%d개를 지울까요?": "Delete %d items?",
        "지운 뒤에도 ⌘Z로 되살릴 수 있습니다.": "You can bring it back with ⌘Z.",
        // 전체 목록
        "전체 목록": "All Timers & Alarms",
        "전체 목록…": "All Timers & Alarms…",
        "전체": "All",
        "보기": "Show",
        "이름 검색": "Search names",
        "알람 정렬": "Sort alarms",
        "다음 울림 순": "Next to ring",
        "시각 순": "Time",
        "이름 순": "Name",
        "추가한 순": "Date added",
        "추가": "Add",
        "새 타이머": "New Timer",
        "새 알람": "New Alarm",
        "찾는 항목이 없습니다": "No matches",
        "왼쪽에서 타이머나 알람을 고르세요": "Select a timer or alarm on the left",
        "시계 창에서 보기": "Show in Clock Window",
        "복제": "Duplicate",
        "끄기": "Off",
        "남은 시간": "Time left",
        "상태": "Status",
        "시간": "Duration",
        "시각": "Time",
        "다음 울림": "Next",
        "요일 지정": "Custom",
        "%@ %@ · %@ 남음": "%@ %@ · in %@",
        "분, 분:초, 또는 시:분:초로 입력하고 Return을 누릅니다. 시간을 바꾸면 처음부터 다시 셉니다.": "Enter minutes, m:ss, or h:mm:ss and press Return. Changing the duration starts the count over.",
        "%d개 선택됨": "%d selected",
        "알람 모두 켜기": "Turn All Alarms On",
        "알람 모두 끄기": "Turn All Alarms Off",
        // 편집 메뉴
        "편집": "Edit",
        "실행 취소": "Undo",
        "실행 복귀": "Redo",
        "잘라내기": "Cut",
        "복사하기": "Copy",
        "붙여넣기": "Paste",
        "전체 선택": "Select All",
    ]
}

/// 화면 문구. 한국어 문구를 그대로 넘기면 고른 언어로 돌려준다.
func L(_ korean: String) -> String {
    Localization.language == .korean ? korean : Localization.english[korean] ?? korean
}

/// `%d`, `%@`가 든 문구.
func L(_ korean: String, _ arguments: CVarArg...) -> String {
    String(format: L(korean), arguments: arguments)
}
