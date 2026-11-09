import AppKit
import Combine

/// 타이머 하나. 이름, 정해 둔 시간, 도는·멈춘 상태를 저장한다.
struct TimerItem: Identifiable, Equatable {
    enum Phase: String { case idle, running, paused, ringing }

    let id: UUID
    /// 비어 있으면 "타이머 3"처럼 번호로 부른다. 번호는 지금 고른 언어로 보여 준다.
    var name: String
    /// 만들 때 붙인 번호. 다른 타이머를 지워도 바뀌지 않는다.
    var number: Int
    /// 정해 둔 시간(초). 초기화하면 여기로 돌아간다.
    var duration: Int
    var phase = Phase.idle
    var endDate: Date?
    var pausedRemaining = 0

    init(id: UUID = UUID(), name: String = "", number: Int, duration: Int) {
        self.id = id
        self.name = name
        self.number = number
        self.duration = duration
    }

    /// 남은 초. 0.3초가 남았으면 1초로 보여 줘야 0이 되는 순간 끝난다.
    func remaining(at now: Date) -> Int {
        switch phase {
        case .idle: return duration
        case .paused: return pausedRemaining
        case .ringing: return 0
        case .running:
            guard let endDate else { return 0 }
            return max(0, Int(ceil(endDate.timeIntervalSince(now) - 0.001)))
        }
    }

    func isWarning(at now: Date, within seconds: Int) -> Bool {
        guard phase == .running else { return false }
        let left = remaining(at: now)
        return left > 0 && left <= seconds
    }
}

/// 알람 하나. 시와 분, 울릴 요일을 정한다. 요일이 없으면 한 번 울린 뒤 스스로 꺼진다.
struct AlarmItem: Identifiable, Equatable {
    /// `Calendar`의 요일 번호. 1이 일요일, 7이 토요일이다.
    static let everyDay: Set<Int> = Set(1...7)
    static let weekdays: Set<Int> = [2, 3, 4, 5, 6]
    static let weekend: Set<Int> = [1, 7]

    let id: UUID
    var name: String
    var number: Int
    /// 자정부터 센 분.
    var minutes: Int
    var enabled: Bool
    var days: Set<Int>
    /// 이 알람만의 소리. 없으면 설정의 기본 소리.
    var sound: String?
    /// 정해 둔 다음 시각. 꺼져 있으면 없다.
    var next: Date?
    /// "5분 뒤 다시"를 누른 뒤 한 번 더 울릴 때. 정해 둔 시각과 따로 센다.
    var snoozeUntil: Date?

    init(id: UUID = UUID(), name: String = "", number: Int, minutes: Int, enabled: Bool = true, days: Set<Int> = everyDay) {
        self.id = id
        self.name = name
        self.number = number
        self.minutes = minutes
        self.enabled = enabled
        self.days = days
    }

    var repeats: Bool { !days.isEmpty }

    /// 다시 알림과 정해 둔 시각 중 먼저 오는 것.
    var upcoming: Date? {
        switch (next, snoozeUntil) {
        case let (a?, b?): return min(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    /// 오늘 날짜에 이 시각을 얹은 값. 시각 고르기 칸에 쓴다.
    var timeToday: Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    func isWarning(at now: Date, within seconds: Int) -> Bool {
        guard let upcoming else { return false }
        let left = upcoming.timeIntervalSince(now)
        return left > 0 && left <= TimeInterval(seconds)
    }

    mutating func schedule(after date: Date) {
        guard enabled else { next = nil; return }
        let calendar = Calendar.current
        let (hour, minute) = (minutes / 60, minutes % 60)
        if days.isEmpty || days == Self.everyDay {
            next = calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                     matchingPolicy: .nextTime)
        } else {
            next = days.compactMap {
                calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: $0),
                                  matchingPolicy: .nextTime)
            }.min()
        }
    }
}

/// 타이머 여러 개와 알람 여러 개를 함께 돌린다.
/// 창에서 타이머·알람 중 무엇을 보여 줄지(`mode`)는 화면만 바꾸고, 도는 타이머에는 손대지 않는다.
final class ClockStore: ObservableObject {
    enum Mode: String { case timer, alarm }

    static let defaultDuration = 5 * 60
    static let maxDuration = 100 * 3600 - 1
    /// 메뉴바에 알람까지 남은 시간을 보여 주기 시작하는 때.
    static let menuBarAlarmWindow: TimeInterval = 3600
    /// 잠자기 등으로 늦게 확인했을 때 이 안이면 늦게라도 울린다.
    static let lateLimit: TimeInterval = 3600
    /// 0.6초 간격으로 세 번 울리고 두 박자 쉰다. 끌 때까지 되풀이하되 1분이 지나면 소리만 멈춘다.
    private static let ringInterval: TimeInterval = 0.6
    private static let ringPattern = [true, true, true, false, false]
    /// 이름을 칠 때마다 쓰지 않도록 잠깐 모았다가 저장한다.
    private static let saveDelay: TimeInterval = 0.5

    private enum Keys {
        static let mode = "timerMode", pinned = "timerPinned", timers = "timers", alarms = "alarms"
        static let eventsFired = "calendarFired", eventsSkipped = "calendarSkipped", eventSnoozes = "calendarSnoozes"
        // 타이머·알람이 하나씩이던 때의 값. 처음 실행할 때 첫 항목으로 옮기고 지운다.
        static let name = "timerName", duration = "timerDuration"
        static let alarmName = "alarmName", alarmMinutes = "alarmMinutes"
        static let alarmEnabled = "alarmEnabled", alarmRepeats = "alarmRepeats"
    }
    /// 예전에 저장한 값에는 뒤쪽 칸들이 없으므로 모두 선택 사항이다.
    struct SavedTimer: Codable {
        var id: UUID
        var name: String
        var duration: Int
        var number: Int?
        var phase: String?
        var endDate: Date?
        var pausedRemaining: Int?
    }
    struct SavedAlarm: Codable {
        var id: UUID
        var name: String
        var minutes: Int
        var enabled: Bool
        var repeats: Bool?
        var number: Int?
        var days: [Int]?
        var snoozeUntil: Date?
        var sound: String?
        /// 앱이 꺼진 동안 지난 알람을 켤 때 울리려고 저장한다.
        var next: Date?
    }
    private let defaults: UserDefaults
    /// 벽시계와 잠자기 중에도 흐르는 시계의 차이. 시스템 시계를 손으로 바꾸면 달라진다.
    private var clockOffset = ClockStore.currentClockOffset()

    // 설정 창에서 바꾸는 값. 창이 설정을 지켜보다 넣어 준다.
    /// 끝나기 몇 초 전부터 깜빡일지. 0이면 깜빡이지 않는다.
    var warningSeconds = 10 { didSet { scheduleTick() } }
    var snoozeMinutes = 5
    /// 타이머 시간 버튼(분).
    var presets = [1, 3, 5, 10, 25]
    /// 소리를 되풀이하는 최대 시간.
    var soundLimit: TimeInterval = 60
    /// 메뉴바에 1시간 안의 알람까지 남은 시간을 보여 주는지. 끄면 그것 때문에 초마다 깨어나지 않는다.
    var tracksMenuBarAlarm = true { didSet { scheduleTick() } }

    @Published var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: Keys.mode); scheduleTick() } }
    /// 항상 위. 기본은 켬.
    @Published var isPinned: Bool { didSet { defaults.set(isPinned, forKey: Keys.pinned) } }
    @Published private(set) var now = Date()
    /// 창이 보이는지. 창이 가려졌거나 닫혔으면 숫자판을 위해 깨어나지 않는다.
    var isDisplayed = false { didSet { if isDisplayed != oldValue { tick() } } }
    /// 전체 목록 창이 보이는지. 목록의 남은 시간을 초마다 고친다.
    var isListDisplayed = false { didSet { if isListDisplayed != oldValue { tick() } } }
    /// 울리기 시작하면 불린다. 창을 앞으로 가져오는 데 쓴다.
    var onRing: (() -> Void)?
    /// 지운 항목을 되살리는 데 쓴다. 창이 넘겨준다.
    weak var undoManager: UndoManager?
    private var ticker: Timer?
    private var soundTimer: Timer?
    private var pendingSave: DispatchWorkItem?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// 적어도 하나는 있다.
    @Published private(set) var timers: [TimerItem] { didSet { setNeedsSave(); scheduleTick() } }
    @Published private(set) var alarms: [AlarmItem] { didSet { setNeedsSave(); scheduleTick() } }
    /// 큰 숫자판에 보이는 타이머.
    @Published var selectedTimerID: UUID
    /// 알람 칸에서 고쳐지는 알람.
    @Published var selectedAlarmID: UUID?
    @Published private(set) var ringingAlarmIDs: Set<UUID> = []

    // MARK: 캘린더 일정
    /// 앞으로 이틀 안의 일정. 캘린더 동기화가 넣어 준다.
    @Published private(set) var calendarEvents: [CalendarEvent] = []
    @Published private(set) var ringingEventIDs: Set<String> = []
    /// 이번 한 번은 울리지 않게 한 일정.
    @Published private(set) var skippedEventIDs: Set<String> = [] { didSet { setNeedsSave() } }
    @Published private(set) var eventSnoozes: [String: Date] = [:] { didSet { setNeedsSave() } }
    /// 이미 울린 일정. 앱을 다시 켜도 또 울리지 않게 저장한다.
    private var firedEventIDs: Set<String> = [] { didSet { setNeedsSave() } }
    /// 일정 시작 몇 초 전에 울릴지.
    var calendarLead: TimeInterval = 300 { didSet { scheduleTick() } }
    /// 잠자기 등으로 늦게 확인했을 때 일정 알람은 이 안이면 늦게라도 울린다.
    static let eventLateLimit: TimeInterval = 15 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Keys.mode).flatMap(Mode.init) ?? .timer
        isPinned = defaults.object(forKey: Keys.pinned) as? Bool ?? true
        let start = Date()

        var timers: [TimerItem]
        let timerData = defaults.data(forKey: Keys.timers)
        if let data = timerData, let saved = try? JSONDecoder().decode([SavedTimer].self, from: data) {
            timers = saved.enumerated().map { Self.restore($1, index: $0, at: start) }
        } else if let data = timerData {
            // 읽지 못한 값은 덮어쓰기 전에 따로 남겨 둔다.
            Self.keepUnreadable(data, key: Keys.timers, in: defaults)
            timers = []
        } else {
            let duration = defaults.integer(forKey: Keys.duration)
            timers = [TimerItem(name: defaults.string(forKey: Keys.name) ?? "", number: 1,
                                duration: duration > 0 ? min(duration, Self.maxDuration) : Self.defaultDuration)]
        }
        if timers.isEmpty { timers = [TimerItem(number: 1, duration: Self.defaultDuration)] }

        var alarms: [AlarmItem]
        let alarmData = defaults.data(forKey: Keys.alarms)
        if let data = alarmData, let saved = try? JSONDecoder().decode([SavedAlarm].self, from: data) {
            alarms = saved.enumerated().map { Self.restore($1, index: $0) }
        } else if let data = alarmData {
            Self.keepUnreadable(data, key: Keys.alarms, in: defaults)
            alarms = []
        } else if [Keys.alarmName, Keys.alarmMinutes, Keys.alarmEnabled, Keys.alarmRepeats].contains(where: { defaults.object(forKey: $0) != nil }) {
            let repeats = defaults.object(forKey: Keys.alarmRepeats) as? Bool ?? true
            alarms = [AlarmItem(name: defaults.string(forKey: Keys.alarmName) ?? "", number: 1,
                                minutes: defaults.object(forKey: Keys.alarmMinutes) as? Int ?? 9 * 60,
                                enabled: defaults.bool(forKey: Keys.alarmEnabled),
                                days: repeats ? AlarmItem.everyDay : [])]
        } else {
            alarms = []
        }
        for i in alarms.indices {
            // 앱이 꺼진 동안 지난 알람은 1시간 안이면 첫 확인 때 울린다.
            if alarms[i].enabled, let missed = alarms[i].next, missed <= start, start.timeIntervalSince(missed) < Self.lateLimit {
                continue
            }
            alarms[i].schedule(after: start)
        }

        self.timers = timers
        self.alarms = alarms
        selectedTimerID = timers[0].id
        selectedAlarmID = alarms.first?.id
        // 옛 값을 새 구조로 옮겼으면 다시 옮기지 않게 지운다.
        if defaults.data(forKey: Keys.timers) == nil || defaults.data(forKey: Keys.alarms) == nil {
            save()
            for key in [Keys.name, Keys.duration, Keys.alarmName, Keys.alarmMinutes, Keys.alarmEnabled, Keys.alarmRepeats] {
                defaults.removeObject(forKey: key)
            }
        }
        firedEventIDs = Set(defaults.stringArray(forKey: Keys.eventsFired) ?? [])
        skippedEventIDs = Set(defaults.stringArray(forKey: Keys.eventsSkipped) ?? [])
        eventSnoozes = (defaults.dictionary(forKey: Keys.eventSnoozes) as? [String: Date]) ?? [:]
        observeClock()
        scheduleTick()
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
        ticker?.invalidate()
        soundTimer?.invalidate()
    }

    // MARK: 저장

    /// 앱이 꺼진 동안 끝난 타이머는 1시간 안이면 켜자마자 울리고, 그보다 오래됐으면 처음 시간으로 둔다.
    private static func restore(_ saved: SavedTimer, index: Int, at now: Date) -> TimerItem {
        let (name, number) = splitDefaultName(saved.name, prefixes: ["타이머", "Timer"], fallback: saved.number ?? index + 1)
        var item = TimerItem(id: saved.id, name: name, number: number, duration: min(max(saved.duration, 1), maxDuration))
        switch saved.phase.flatMap(TimerItem.Phase.init) {
        case .running:
            if let end = saved.endDate, now.timeIntervalSince(end) < lateLimit {
                item.phase = .running
                item.endDate = end
            }
        case .paused:
            if let left = saved.pausedRemaining, left > 0 {
                item.phase = .paused
                item.pausedRemaining = min(left, maxDuration)
            }
        case .idle, .ringing, nil:
            break
        }
        return item
    }

    private static func restore(_ saved: SavedAlarm, index: Int) -> AlarmItem {
        let (name, number) = splitDefaultName(saved.name, prefixes: ["알람", "Alarm"], fallback: saved.number ?? index + 1)
        let days = saved.days.map { Set($0.filter { (1...7).contains($0) }) }
            ?? ((saved.repeats ?? true) ? AlarmItem.everyDay : [])
        var item = AlarmItem(id: saved.id, name: name, number: number, minutes: min(max(saved.minutes, 0), 24 * 60 - 1),
                             enabled: saved.enabled, days: days)
        item.snoozeUntil = saved.snoozeUntil
        item.next = saved.next
        item.sound = saved.sound
        return item
    }

    private static func keepUnreadable(_ data: Data, key: String, in defaults: UserDefaults) {
        defaults.set(data, forKey: key + "Unreadable")
        NSLog("Clocky: 저장된 %@ 값을 읽지 못해 %@Unreadable에 남겨 두었습니다.", key, key)
    }

    /// 예전 판은 새 항목에 "타이머 2"처럼 그때의 언어로 이름을 박아 두었다. 그런 이름은 비우고 번호만 남긴다.
    private static func splitDefaultName(_ name: String, prefixes: [String], fallback: Int) -> (String, Int) {
        for prefix in prefixes where name.hasPrefix(prefix + " ") {
            if let number = Int(name.dropFirst(prefix.count + 1)), number > 0 { return ("", number) }
        }
        return (name, fallback)
    }

    private func setNeedsSave() {
        guard pendingSave == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// 미뤄 둔 저장을 바로 한다. 앱을 끝낼 때 부른다.
    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        let savedTimers = timers.map { item -> SavedTimer in
            var saved = SavedTimer(id: item.id, name: item.name, duration: item.duration, number: item.number)
            switch item.phase {
            case .running: saved.phase = item.phase.rawValue; saved.endDate = item.endDate
            case .paused: saved.phase = item.phase.rawValue; saved.pausedRemaining = item.pausedRemaining
            case .idle, .ringing: break
            }
            return saved
        }
        let savedAlarms = alarms.map {
            SavedAlarm(id: $0.id, name: $0.name, minutes: $0.minutes, enabled: $0.enabled, repeats: $0.repeats,
                       number: $0.number, days: $0.days.sorted(), snoozeUntil: $0.snoozeUntil, sound: $0.sound, next: $0.next)
        }
        if let data = try? JSONEncoder().encode(savedTimers) { defaults.set(data, forKey: Keys.timers) }
        if let data = try? JSONEncoder().encode(savedAlarms) { defaults.set(data, forKey: Keys.alarms) }
        defaults.set(firedEventIDs.sorted(), forKey: Keys.eventsFired)
        defaults.set(skippedEventIDs.sorted(), forKey: Keys.eventsSkipped)
        defaults.set(eventSnoozes, forKey: Keys.eventSnoozes)
    }

    /// 시간대·시계·날짜가 바뀌면 알람의 다음 시각을 다시 셈한다. 잠자기에서 깨면 바로 확인한다.
    private func observeClock() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange, .NSCalendarDayChanged] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.clockDidChange()
            }
            observers.append((center, observer))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let observer = workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tick()
        }
        observers.append((workspace, observer))
    }

    /// 벽시계 시각 - 잠자기 중에도 흐르는 시계. 시계를 손으로 바꿀 때만 크게 달라진다.
    static func currentClockOffset() -> TimeInterval {
        Date().timeIntervalSince1970 - Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    func clockDidChange() {
        NSTimeZone.resetSystemTimeZone()
        // 시계를 손으로 바꿨으면 도는 타이머와 다시 알림은 실제로 흐른 시간대로 남도록 끝나는 시각을 같이 옮긴다.
        let offset = Self.currentClockOffset()
        shiftRelativeTimes(by: offset - clockOffset)
        clockOffset = offset
        // 바뀌기 전에 이미 지난 알람은 먼저 울린다.
        tick()
        let date = Date()
        let rescheduled = alarms.map { alarm -> AlarmItem in
            var alarm = alarm
            alarm.schedule(after: date)
            return alarm
        }
        if rescheduled != alarms { alarms = rescheduled }
    }

    /// 남은 시간으로 정해진 것(도는 타이머, 다시 알림)을 시계가 바뀐 만큼 옮긴다. 2초 안의 차이는 무시한다.
    func shiftRelativeTimes(by jump: TimeInterval) {
        guard abs(jump) >= 2 else { return }
        let shiftedTimers = timers.map { item -> TimerItem in
            var item = item
            if item.phase == .running, let end = item.endDate { item.endDate = end.addingTimeInterval(jump) }
            return item
        }
        if shiftedTimers != timers { timers = shiftedTimers }
        let shiftedAlarms = alarms.map { item -> AlarmItem in
            var item = item
            if let snooze = item.snoozeUntil { item.snoozeUntil = snooze.addingTimeInterval(jump) }
            return item
        }
        if shiftedAlarms != alarms { alarms = shiftedAlarms }
    }

    // MARK: 상태

    var selectedTimer: TimerItem { timers.first { $0.id == selectedTimerID } ?? timers[0] }
    var selectedAlarm: AlarmItem? { alarms.first { $0.id == selectedAlarmID } }

    var isRinging: Bool { timers.contains { $0.phase == .ringing } || !ringingAlarmIDs.isEmpty || !ringingEventIDs.isEmpty }

    /// 어느 타이머나 알람이 10초 안으로 다가왔을 때.
    var isWarning: Bool {
        timers.contains { $0.isWarning(at: now, within: warningSeconds) }
            || alarms.contains { $0.isWarning(at: now, within: warningSeconds) }
            || pendingEventAlerts.contains {
                let left = $0.date.timeIntervalSince(now)
                return left > 0 && left <= TimeInterval(warningSeconds)
            }
    }

    /// 끝나기 직전과 울리는 동안 0.5초마다 켜졌다 꺼진다.
    var isFlashing: Bool {
        (isWarning || isRinging) && Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0
    }

    /// 판에 보일 시·분·초. 타이머는 고른 타이머의 남은 시간, 알람은 지금 시각.
    var displayedUnits: [Int] {
        switch mode {
        case .timer:
            let s = selectedTimer.remaining(at: now)
            return [s / 3600, s / 60 % 60, s % 60]
        case .alarm:
            let c = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
            return [c.hour ?? 0, c.minute ?? 0, c.second ?? 0]
        }
    }

    /// 앞으로 울릴 알람(다시 알림 포함), 이른 것부터.
    var upcomingAlarms: [AlarmItem] {
        alarms.filter { $0.upcoming != nil }.sorted { $0.upcoming! < $1.upcoming! }
    }

    /// 일정이 울릴 때. 다시 울림을 걸어 두었으면 그때.
    func alertDate(of event: CalendarEvent) -> Date {
        eventSnoozes[event.id] ?? event.start.addingTimeInterval(-calendarLead)
    }

    /// 아직 울리지 않았고 건너뛰지도 않은 일정과 그 알림 시각, 이른 것부터.
    var pendingEventAlerts: [(event: CalendarEvent, date: Date)] {
        calendarEvents.compactMap { event -> (CalendarEvent, Date)? in
            if skippedEventIDs.contains(event.id) { return nil }
            if let snooze = eventSnoozes[event.id] { return (event, snooze) }
            if firedEventIDs.contains(event.id) { return nil }
            return (event, event.start.addingTimeInterval(-calendarLead))
        }
        .sorted { $0.1 < $1.1 }
        .map { (event: $0.0, date: $0.1) }
    }

    /// 다음에 울릴 것(알람이나 일정)의 이름과 시각. 메뉴바에 쓴다.
    var nextAlert: (title: String, date: Date)? {
        let alarm = upcomingAlarms.first.flatMap { item in item.upcoming.map { (displayName(of: item), $0) } }
        let event = pendingEventAlerts.first { $0.date > now.addingTimeInterval(-1) }.map { ($0.event.title, $0.date) }
        switch (alarm, event) {
        case let (a?, e?): return a.1 <= e.1 ? (a.0, a.1) : (e.0, e.1)
        case let (a?, nil): return (a.0, a.1)
        case let (nil, e?): return (e.0, e.1)
        case (nil, nil): return nil
        }
    }

    /// 지금 울리는 것들의 이름. 시계 창과 목록 창에 보여 준다.
    var ringingTitles: [String] {
        timers.filter { $0.phase == .ringing }.map { displayName(of: $0) }
            + alarms.filter { ringingAlarmIDs.contains($0.id) }.map { displayName(of: $0) }
            + calendarEvents.filter { ringingEventIDs.contains($0.id) }.map(\.title)
    }

    func setCalendarEvents(_ events: [CalendarEvent]) {
        if events != calendarEvents { calendarEvents = events }
        // 오래된 기록은 지운다. 일정 id 끝에 시작 시각(초)이 있다.
        let cutoff = Date().addingTimeInterval(-3 * 86400).timeIntervalSince1970
        func recent(_ id: String) -> Bool { (id.split(separator: "|").last.flatMap { Double($0) } ?? 0) > cutoff }
        let fired = firedEventIDs.filter(recent)
        if fired != firedEventIDs { firedEventIDs = fired }
        let skipped = skippedEventIDs.filter(recent)
        if skipped != skippedEventIDs { skippedEventIDs = skipped }
        let snoozes = eventSnoozes.filter { recent($0.key) }
        if snoozes != eventSnoozes { eventSnoozes = snoozes }
        scheduleTick()
    }

    /// 이번 한 번만 이 일정을 울리지 않거나 다시 울리게 한다.
    func setEventSkipped(_ id: String, _ skipped: Bool) {
        if skipped { skippedEventIDs.insert(id) } else { skippedEventIDs.remove(id) }
        if skipped { eventSnoozes[id] = nil }
    }

    func displayName(of item: TimerItem) -> String {
        item.name.trimmingCharacters(in: .whitespaces).isEmpty ? L("타이머 %d", item.number) : item.name
    }

    func displayName(of item: AlarmItem) -> String {
        item.name.trimmingCharacters(in: .whitespaces).isEmpty ? L("알람 %d", item.number) : item.name
    }

    // MARK: 타이머

    @discardableResult
    func addTimer() -> UUID {
        let item = TimerItem(number: (timers.map(\.number).max() ?? 0) + 1, duration: selectedTimer.duration)
        timers.append(item)
        selectedTimerID = item.id
        return item.id
    }

    /// 마지막 하나는 지우지 않는다.
    func removeTimer(_ id: UUID) {
        guard timers.count > 1, let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let item = timers.remove(at: index)
        if selectedTimerID == id { selectedTimerID = timers[min(index, timers.count - 1)].id }
        undoManager?.registerUndo(withTarget: self) { $0.restoreTimer(item, at: index) }
        undoManager?.setActionName(L("타이머 삭제"))
    }

    /// 지울 때의 상태 그대로 되살린다. 도는 타이머는 끝나는 시각이 그대로라 그동안 흐른 시간도 반영된다.
    private func restoreTimer(_ item: TimerItem, at index: Int) {
        guard !timers.contains(where: { $0.id == item.id }) else { return }
        timers.insert(item, at: min(index, timers.count))
        selectedTimerID = item.id
        mode = .timer
        undoManager?.registerUndo(withTarget: self) { $0.removeTimer(item.id) }
        undoManager?.setActionName(L("타이머 삭제"))
    }

    func renameTimer(_ id: UUID, to name: String) {
        updateTimer(id) { $0.name = name }
    }

    func setDuration(_ id: UUID, _ seconds: Int) {
        guard seconds > 0 else { return }
        updateTimer(id) {
            $0.duration = min(seconds, Self.maxDuration)
            $0.phase = .idle
        }
    }

    func start(_ id: UUID) {
        let date = Date()
        updateTimer(id) {
            switch $0.phase {
            case .idle: $0.endDate = date.addingTimeInterval(TimeInterval($0.duration))
            case .paused: $0.endDate = date.addingTimeInterval(TimeInterval($0.pausedRemaining))
            case .running, .ringing: return
            }
            $0.phase = .running
        }
        now = date
    }

    func pause(_ id: UUID) {
        let date = Date()
        updateTimer(id) {
            guard $0.phase == .running else { return }
            $0.pausedRemaining = $0.remaining(at: date)
            $0.phase = .paused
        }
    }

    func reset(_ id: UUID) {
        updateTimer(id) { $0.phase = .idle }
        now = Date()
    }

    /// 도는 타이머는 멈추고, 멈춘 타이머는 시작한다.
    func toggle(_ id: UUID) {
        guard let item = timers.first(where: { $0.id == id }) else { return }
        if item.phase == .running { pause(id) } else { start(id) }
    }

    private func updateTimer(_ id: UUID, _ change: (inout TimerItem) -> Void) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        var item = timers[index]
        change(&item)
        if item != timers[index] { timers[index] = item }
    }

    // MARK: 알람

    /// 다음 정각에 매일 울리는 알람을 켜서 더한다. 시각은 그다음에 고친다.
    @discardableResult
    func addAlarm(minutes: Int? = nil) -> UUID {
        let hour = Calendar.current.component(.hour, from: Date())
        var item = AlarmItem(number: (alarms.map(\.number).max() ?? 0) + 1, minutes: minutes ?? (hour + 1) % 24 * 60)
        item.schedule(after: Date())
        alarms.append(item)
        selectedAlarmID = item.id
        return item.id
    }

    func removeAlarm(_ id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        let item = alarms.remove(at: index)
        ringingAlarmIDs.remove(id)
        if selectedAlarmID == id { selectedAlarmID = alarms.isEmpty ? nil : alarms[min(index, alarms.count - 1)].id }
        undoManager?.registerUndo(withTarget: self) { $0.restoreAlarm(item, at: index) }
        undoManager?.setActionName(L("알람 삭제"))
    }

    private func restoreAlarm(_ item: AlarmItem, at index: Int) {
        guard !alarms.contains(where: { $0.id == item.id }) else { return }
        var item = item
        item.schedule(after: Date())
        alarms.insert(item, at: min(index, alarms.count))
        selectedAlarmID = item.id
        mode = .alarm
        undoManager?.registerUndo(withTarget: self) { $0.removeAlarm(item.id) }
        undoManager?.setActionName(L("알람 삭제"))
    }

    func renameAlarm(_ id: UUID, to name: String) {
        updateAlarm(id) { $0.name = name }
    }

    func setAlarmTime(_ id: UUID, _ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        updateAlarm(id) { $0.minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    }

    /// 끄면 다시 알림도 지운다.
    func setAlarmEnabled(_ id: UUID, _ enabled: Bool) {
        updateAlarm(id) {
            $0.enabled = enabled
            if !enabled { $0.snoozeUntil = nil }
        }
    }

    /// nil이면 기본 소리를 쓴다.
    func setAlarmSound(_ id: UUID, _ sound: String?) {
        updateAlarm(id) { $0.sound = sound }
    }

    func setAlarmDays(_ id: UUID, _ days: Set<Int>) {
        updateAlarm(id) { $0.days = days }
    }

    /// 시각·켜기·요일이 바뀌면 다음에 울릴 때를 다시 셈한다.
    private func updateAlarm(_ id: UUID, _ change: (inout AlarmItem) -> Void) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        let old = alarms[index]
        var item = old
        change(&item)
        if item.minutes != old.minutes || item.enabled != old.enabled || item.days != old.days { item.schedule(after: Date()) }
        if item != old { alarms[index] = item }
    }

    /// 같은 설정으로 바로 뒤에 하나 더 만든다.
    @discardableResult
    func duplicateTimer(_ id: UUID) -> UUID? {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return nil }
        let source = timers[index]
        let copy = TimerItem(name: source.name, number: (timers.map(\.number).max() ?? 0) + 1, duration: source.duration)
        timers.insert(copy, at: index + 1)
        return copy.id
    }

    @discardableResult
    func duplicateAlarm(_ id: UUID) -> UUID? {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return nil }
        let source = alarms[index]
        var copy = AlarmItem(name: source.name, number: (alarms.map(\.number).max() ?? 0) + 1, minutes: source.minutes,
                             enabled: source.enabled, days: source.days)
        copy.sound = source.sound
        copy.schedule(after: Date())
        alarms.insert(copy, at: index + 1)
        return copy.id
    }

    /// 다시 알림만 지우고 정해 둔 시각은 그대로 둔다.
    func cancelSnooze(_ id: UUID) {
        updateAlarm(id) { $0.snoozeUntil = nil }
    }

    /// 여러 개를 한 번에 지운다. ⌘Z 한 번으로 모두 되살아난다.
    func remove(_ ids: Set<UUID>) {
        undoManager?.beginUndoGrouping()
        for id in ids where alarms.contains(where: { $0.id == id }) { removeAlarm(id) }
        for id in ids where timers.contains(where: { $0.id == id }) { removeTimer(id) }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(L("삭제"))
    }

    // MARK: 고른 항목

    /// 스페이스: 타이머는 시작·일시정지, 알람은 켜기·끄기.
    func toggleSelected() {
        switch mode {
        case .timer:
            toggle(selectedTimerID)
        case .alarm:
            if let alarm = selectedAlarm { setAlarmEnabled(alarm.id, !alarm.enabled) }
        }
    }

    /// 위·아래 화살표로 목록에서 고른다.
    func selectAdjacent(_ offset: Int) {
        switch mode {
        case .timer:
            guard let index = timers.firstIndex(where: { $0.id == selectedTimerID }) else { return }
            selectedTimerID = timers[max(0, min(timers.count - 1, index + offset))].id
        case .alarm:
            guard !alarms.isEmpty else { return }
            let index = alarms.firstIndex { $0.id == selectedAlarmID } ?? (offset > 0 ? -1 : alarms.count)
            selectedAlarmID = alarms[max(0, min(alarms.count - 1, index + offset))].id
        }
    }

    func addItem() {
        if mode == .timer { addTimer() } else { addAlarm() }
    }

    func removeSelected() {
        switch mode {
        case .timer: removeTimer(selectedTimerID)
        case .alarm: if let id = selectedAlarmID { removeAlarm(id) }
        }
    }

    // MARK: 울림

    /// 울리는 것을 모두 끈다. 울리던 타이머는 처음 시간으로 돌아간다.
    func stopRinging() {
        if timers.contains(where: { $0.phase == .ringing }) {
            timers = timers.map { var t = $0; if t.phase == .ringing { t.phase = .idle }; return t }
        }
        ringingAlarmIDs = []
        ringingEventIDs = []
        stopSound()
        now = Date()
        scheduleTick()
    }

    /// 울리는 것을 모두 끄고 5분 뒤에 한 번 더 울린다. 타이머는 5분짜리로 다시 돈다.
    func snooze() {
        let date = Date()
        let until = date.addingTimeInterval(TimeInterval(snoozeMinutes * 60))
        if timers.contains(where: { $0.phase == .ringing }) {
            timers = timers.map {
                var t = $0
                if t.phase == .ringing { t.phase = .running; t.endDate = until }
                return t
            }
        }
        if !ringingAlarmIDs.isEmpty {
            alarms = alarms.map {
                var a = $0
                if ringingAlarmIDs.contains(a.id) { a.snoozeUntil = until }
                return a
            }
        }
        for id in ringingEventIDs { eventSnoozes[id] = until }
        ringingAlarmIDs = []
        ringingEventIDs = []
        stopSound()
        now = date
        scheduleTick()
    }

    // MARK: 시계

    /// 다음에 화면이나 상태가 바뀌는 순간에만 깨어난다.
    /// 숫자는 초가 바뀔 때, 깜빡임은 0.5초마다, 알람은 10초 전과 울릴 때. 할 일이 없으면 멈춘다.
    func nextWake(after now: Date) -> Date? {
        let reference = now.timeIntervalSinceReferenceDate
        let nextSecond = Date(timeIntervalSinceReferenceDate: floor(reference) + 1)
        let nextHalf = Date(timeIntervalSinceReferenceDate: floor(reference * 2) / 2 + 0.5)
        var dates: [Date] = []

        for item in timers where item.phase == .running {
            guard let end = item.endDate else { continue }
            let left = end.timeIntervalSince(now)
            // 남은 초가 하나 줄어드는 순간.
            dates.append(left <= 0 ? now : end.addingTimeInterval(-(ceil(left) - 1)))
        }
        if let alert = pendingEventAlerts.first(where: { $0.date > now })?.date ?? pendingEventAlerts.first?.date {
            dates.append(max(alert, now))
            let warning = TimeInterval(warningSeconds)
            if warning > 0 && alert.timeIntervalSince(now) > warning { dates.append(alert.addingTimeInterval(-warning)) }
            if tracksMenuBarAlarm {
                let left = alert.timeIntervalSince(now)
                if left <= Self.menuBarAlarmWindow {
                    dates.append(nextSecond)
                } else {
                    dates.append(alert.addingTimeInterval(-Self.menuBarAlarmWindow))
                }
            }
        }
        if let soonest = upcomingAlarms.first?.upcoming {
            let left = soonest.timeIntervalSince(now)
            dates.append(soonest)
            let warning = TimeInterval(warningSeconds)
            if warning > 0 && left > warning { dates.append(soonest.addingTimeInterval(-warning)) }
            // 메뉴바에 초 단위로 남은 시간을 보여 준다.
            if tracksMenuBarAlarm {
                if left <= Self.menuBarAlarmWindow {
                    dates.append(nextSecond)
                } else {
                    dates.append(soonest.addingTimeInterval(-Self.menuBarAlarmWindow))
                }
            }
        }
        if isListDisplayed { dates.append(nextSecond) }
        if isDisplayed {
            // 알람 칸은 지금 시각과 남은 시간을 보여 준다.
            if mode == .alarm { dates.append(nextSecond) }
            if isWarning || isRinging { dates.append(nextHalf) }
        }
        guard let soonest = dates.min() else { return nil }
        // 멀리 있는 알람만 기다릴 때도 가끔 깨어나 시계가 어긋나지 않았는지 본다.
        return min(soonest, now.addingTimeInterval(300))
    }

    private func scheduleTick() {
        guard let wake = nextWake(after: Date()) else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        // 경계를 살짝 넘긴 뒤에 깨어나야 바뀐 값을 읽는다.
        let fireDate = max(wake, Date()).addingTimeInterval(0.005)
        if let ticker, ticker.isValid, abs(ticker.fireDate.timeIntervalSince(fireDate)) < 0.002 { return }
        ticker?.invalidate()
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.01
        // 메뉴를 열어 둔 동안에도 멈추지 않게 한다.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func tick() {
        now = Date()
        var rangTimer: UUID?
        var rangAlarm: UUID?

        var newTimers = timers
        for i in newTimers.indices where newTimers[i].phase == .running && newTimers[i].remaining(at: now) == 0 {
            newTimers[i].phase = .ringing
            rangTimer = rangTimer ?? newTimers[i].id
        }
        if newTimers != timers { timers = newTimers }

        var newAlarms = alarms
        var newRinging = ringingAlarmIDs
        for i in newAlarms.indices {
            if let snooze = newAlarms[i].snoozeUntil, now >= snooze {
                newAlarms[i].snoozeUntil = nil
                if now.timeIntervalSince(snooze) < Self.lateLimit {
                    newRinging.insert(newAlarms[i].id)
                    rangAlarm = rangAlarm ?? newAlarms[i].id
                }
            }
            guard let next = newAlarms[i].next, now >= next else { continue }
            if now.timeIntervalSince(next) < Self.lateLimit {
                newRinging.insert(newAlarms[i].id)
                rangAlarm = rangAlarm ?? newAlarms[i].id
            }
            if newAlarms[i].repeats {
                newAlarms[i].schedule(after: max(now, next))
            } else {
                newAlarms[i].enabled = false
                newAlarms[i].next = nil
            }
        }
        if newRinging != ringingAlarmIDs { ringingAlarmIDs = newRinging }
        if newAlarms != alarms { alarms = newAlarms }

        var rangEvent: String?
        for (event, date) in pendingEventAlerts where now >= date {
            eventSnoozes[event.id] = nil
            firedEventIDs.insert(event.id)
            // 잠자기 등으로 많이 늦었으면 울리지 않는다.
            if now.timeIntervalSince(date) < Self.eventLateLimit {
                ringingEventIDs.insert(event.id)
                rangEvent = rangEvent ?? event.id
            }
        }
        if rangEvent != nil && rangAlarm == nil { mode = .alarm }

        // 울린 것을 큰 판에 보여 준다. 타이머와 알람이 함께 울리면 타이머를 먼저 보여 준다.
        if let rangAlarm {
            selectedAlarmID = rangAlarm
            mode = .alarm
        }
        if let rangTimer {
            selectedTimerID = rangTimer
            mode = .timer
        }
        if rangTimer != nil || rangAlarm != nil || rangEvent != nil { ring() }
        scheduleTick()
    }

    /// 새로 울릴 때마다 1분 제한을 다시 센다.
    private func ring() {
        onRing?()
        stopSound()
        let started = Date()
        var beat = 0
        let timer = Timer(timeInterval: Self.ringInterval, repeats: true) { [weak self] _ in
            guard let self, self.isRinging, Date().timeIntervalSince(started) < self.soundLimit else {
                self?.stopSound()
                return
            }
            if Self.ringPattern[beat % Self.ringPattern.count] { AlarmSound.play(self.ringingSound) }
            beat += 1
        }
        RunLoop.main.add(timer, forMode: .common)
        soundTimer = timer
        timer.fire()
    }

    /// 울리는 알람에 저마다 소리가 있으면 처음 것을 낸다. 타이머만 울리면 기본 소리.
    var ringingSound: String? {
        alarms.first { ringingAlarmIDs.contains($0.id) && $0.sound != nil }?.sound
    }

    /// 소리가 울리는 중인지.
    var isSounding: Bool { soundTimer != nil }

    private func stopSound() {
        soundTimer?.invalidate()
        soundTimer = nil
        AlarmSound.stop()
    }

    #if DEBUG
    // MARK: 시험용 (디버그 빌드에만 들어간다)

    /// 시험에서 분 단위 알람을 기다리지 않도록 다음 시각을 옮긴다.
    func forceNext(_ id: UUID, _ date: Date) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].next = date
    }

    func forceSnooze(_ id: UUID, _ date: Date) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].snoozeUntil = date
    }

    func forceEventSnooze(_ id: String, _ date: Date) {
        eventSnoozes[id] = date
    }

    func forceTimerEnd(_ id: UUID, _ date: Date) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[index].endDate = date
    }

    #endif

    /// "90"은 90분, "5:00"은 5분, "1:30:00"은 1시간 30분. 0이거나 최대(99:59:59)를 넘으면 nil.
    static func parse(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        let numbers = parts.map { Int($0.trimmingCharacters(in: .whitespaces)) }
        // 아주 큰 수를 곱하다 넘치지 않도록 칸마다 먼저 거른다.
        guard !numbers.isEmpty, numbers.count <= 3,
              numbers.allSatisfy({ $0 != nil && $0! >= 0 && $0! <= maxDuration }) else { return nil }
        let values = numbers.map { $0! }
        let seconds: Int
        switch values.count {
        case 1: seconds = values[0] * 60
        case 2: seconds = values[0] * 60 + values[1]
        default: seconds = values[0] * 3600 + values[1] * 60 + values[2]
        }
        return (1...maxDuration).contains(seconds) ? seconds : nil
    }
}

/// "3시간 2분", "45분"처럼 남은 시간을 분 단위로 올려 적는다. 1분이 안 남았으면 초로 적는다.
func remainingText(until date: Date, from now: Date) -> String {
    let seconds = Int(ceil(date.timeIntervalSince(now) - 0.001))
    if seconds < 60 { return L("%d초", max(seconds, 1)) }
    let minutes = Int((Double(seconds) / 60).rounded(.up))
    let (days, hours, rest) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
    if days > 0 { return hours > 0 ? L("%d일 %d시간", days, hours) : L("%d일", days) }
    if hours > 0 { return rest > 0 ? L("%d시간 %d분", hours, rest) : L("%d시간", hours) }
    return L("%d분", rest)
}

/// "4:05" 또는 "1:02:03".
func clockText(_ seconds: Int) -> String {
    seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                    : String(format: "%d:%02d", seconds / 60, seconds % 60)
}

/// "매일", "평일", "주말", "한 번", 또는 "월 수 금".
func daysText(_ days: Set<Int>) -> String {
    switch days {
    case []: return L("한 번")
    case AlarmItem.everyDay: return L("매일")
    case AlarmItem.weekdays: return L("평일")
    case AlarmItem.weekend: return L("주말")
    default: return weekdayOrder.filter(days.contains).map { L(weekdayNames[$0 - 1]) }.joined(separator: " ")
    }
}

/// 월요일부터 적는다.
let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]
