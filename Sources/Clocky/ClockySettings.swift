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
        static let language = "language", alarmSound = "alarmSound"
    }
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
    /// 시스템의 로그인 항목에 저장되므로 UserDefaults에 두지 않는다.
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// `swift run`으로 실행하면 번들이 없어 로그인 항목에 등록할 수 없다.
    var canLaunchAtLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    init() {
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init) ?? .systemDefault
        alarmSound = defaults.string(forKey: Keys.alarmSound).flatMap { AlarmSound.choices.contains($0) ? $0 : nil }
            ?? AlarmSound.defaultName
        Localization.language = language
        AlarmSound.name = alarmSound
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
    /// 앞 소리가 끝나기 전에 다시 내려면 같은 객체를 멈췄다 다시 틀어야 한다.
    private static var current: NSSound?

    static func play() {
        current?.stop()
        current = NSSound(named: name)
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
