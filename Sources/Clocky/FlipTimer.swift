import AppKit
import Combine

/// 타이머 하나. 이름과 정해 둔 시간은 저장하고, 돌고 있는 상태는 앱을 끄면 사라진다.
struct TimerItem: Identifiable, Equatable {
    enum Phase { case idle, running, paused, ringing }

    let id: UUID
    var name: String
    /// 정해 둔 시간(초). 초기화하면 여기로 돌아간다.
    var duration: Int
    var phase = Phase.idle
    var endDate: Date?
    var pausedRemaining = 0

    init(id: UUID = UUID(), name: String, duration: Int) {
        self.id = id
        self.name = name
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

    func isWarning(at now: Date) -> Bool {
        guard phase == .running else { return false }
        let left = remaining(at: now)
        return left > 0 && left <= FlipTimer.warningSeconds
    }
}

/// 알람 하나. 시와 분만 쓰고, 매일 반복하지 않으면 한 번 울린 뒤 스스로 꺼진다.
struct AlarmItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    /// 자정부터 센 분.
    var minutes: Int
    var enabled: Bool
    var repeats: Bool
    /// 다음에 울릴 때. 꺼져 있으면 없다.
    var next: Date?

    init(id: UUID = UUID(), name: String, minutes: Int, enabled: Bool = true, repeats: Bool = true) {
        self.id = id
        self.name = name
        self.minutes = minutes
        self.enabled = enabled
        self.repeats = repeats
    }

    /// 오늘 날짜에 이 시각을 얹은 값. 시각 고르기 칸에 쓴다.
    var timeToday: Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    func isWarning(at now: Date) -> Bool {
        guard let next else { return false }
        let left = next.timeIntervalSince(now)
        return left > 0 && left <= TimeInterval(FlipTimer.warningSeconds)
    }

    mutating func schedule(after date: Date) {
        guard enabled else { next = nil; return }
        next = Calendar.current.nextDate(after: date, matching: DateComponents(hour: minutes / 60, minute: minutes % 60, second: 0),
                                         matchingPolicy: .nextTime)
    }
}

/// 타이머 여러 개와 알람 여러 개를 함께 돌린다.
/// 창에서 타이머·알람 중 무엇을 보여 줄지(`mode`)는 화면만 바꾸고, 도는 타이머에는 손대지 않는다.
final class FlipTimer: ObservableObject {
    enum Mode: String { case timer, alarm }

    static let presets = [1, 3, 5, 10, 25]
    /// 끝나기 몇 초 전부터 깜빡일지.
    static let warningSeconds = 10
    static let defaultDuration = 5 * 60
    static let maxDuration = 100 * 3600 - 1
    /// 잠자기 등으로 늦게 확인했을 때 이 안이면 늦게라도 울린다.
    private static let lateLimit: TimeInterval = 3600
    /// 0.6초 간격으로 세 번 울리고 두 박자 쉰다. 끌 때까지 되풀이하되 1분이 지나면 소리만 멈춘다.
    private static let ringInterval: TimeInterval = 0.6
    private static let ringPattern = [true, true, true, false, false]
    private static let soundLimit: TimeInterval = 60

    private enum Keys {
        static let mode = "timerMode", pinned = "timerPinned", timers = "timers", alarms = "alarms"
        // 타이머·알람이 하나씩이던 때의 값. 처음 실행할 때 첫 항목으로 옮기고 지운다.
        static let name = "timerName", duration = "timerDuration"
        static let alarmName = "alarmName", alarmMinutes = "alarmMinutes"
        static let alarmEnabled = "alarmEnabled", alarmRepeats = "alarmRepeats"
    }
    /// 도는·멈춘 상태도 저장해 앱을 다시 켜도 이어 간다. 예전에 저장한 값에는 뒤의 셋이 없다.
    private struct SavedTimer: Codable {
        var id: UUID
        var name: String
        var duration: Int
        var phase: String?
        var endDate: Date?
        var pausedRemaining: Int?
    }
    private struct SavedAlarm: Codable { var id: UUID; var name: String; var minutes: Int; var enabled: Bool; var repeats: Bool }
    private let defaults = UserDefaults.standard

    @Published var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: Keys.mode) } }
    /// 항상 위. 기본은 켬.
    @Published var isPinned: Bool { didSet { defaults.set(isPinned, forKey: Keys.pinned) } }
    @Published private(set) var now = Date()
    /// 창이 화면에 있는지. 시계를 보여 줄 때만 자주 깨어난다.
    var isDisplayed = false { didSet { updateTicker() } }
    /// 울리기 시작하면 불린다. 창을 앞으로 가져오는 데 쓴다.
    var onRing: (() -> Void)?
    /// 지운 항목을 되살리는 데 쓴다. 창이 넘겨준다.
    weak var undoManager: UndoManager?
    private var ticker: Timer?
    private var soundTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// 적어도 하나는 있다.
    @Published private(set) var timers: [TimerItem] { didSet { saveTimers(); updateTicker() } }
    @Published private(set) var alarms: [AlarmItem] { didSet { saveAlarms(); updateTicker() } }
    /// 큰 숫자판에 보이는 타이머.
    @Published var selectedTimerID: UUID
    /// 알람 칸에서 고쳐지는 알람.
    @Published var selectedAlarmID: UUID?
    @Published private(set) var ringingAlarmIDs: Set<UUID> = []

    init() {
        let defaults = self.defaults
        mode = defaults.string(forKey: Keys.mode).flatMap(Mode.init) ?? .timer
        isPinned = defaults.object(forKey: Keys.pinned) as? Bool ?? true

        var timers: [TimerItem]
        if let data = defaults.data(forKey: Keys.timers),
           let saved = try? JSONDecoder().decode([SavedTimer].self, from: data) {
            timers = saved.map { Self.restore($0, at: Date()) }
        } else {
            let duration = defaults.integer(forKey: Keys.duration)
            timers = [TimerItem(name: defaults.string(forKey: Keys.name) ?? "",
                                duration: duration > 0 ? duration : Self.defaultDuration)]
        }
        if timers.isEmpty { timers = [TimerItem(name: "", duration: Self.defaultDuration)] }

        var alarms: [AlarmItem]
        if let data = defaults.data(forKey: Keys.alarms),
           let saved = try? JSONDecoder().decode([SavedAlarm].self, from: data) {
            alarms = saved.map { AlarmItem(id: $0.id, name: $0.name, minutes: $0.minutes, enabled: $0.enabled, repeats: $0.repeats) }
        } else if [Keys.alarmName, Keys.alarmMinutes, Keys.alarmEnabled, Keys.alarmRepeats].contains(where: { defaults.object(forKey: $0) != nil }) {
            alarms = [AlarmItem(name: defaults.string(forKey: Keys.alarmName) ?? "",
                                minutes: defaults.object(forKey: Keys.alarmMinutes) as? Int ?? 9 * 60,
                                enabled: defaults.bool(forKey: Keys.alarmEnabled),
                                repeats: defaults.object(forKey: Keys.alarmRepeats) as? Bool ?? true)]
        } else {
            alarms = []
        }
        let start = Date()
        for i in alarms.indices { alarms[i].schedule(after: start) }

        self.timers = timers
        self.alarms = alarms
        selectedTimerID = timers[0].id
        selectedAlarmID = alarms.first?.id
        // 옛 값을 새 구조로 옮겼으면 다시 옮기지 않게 지운다.
        if defaults.data(forKey: Keys.timers) == nil || defaults.data(forKey: Keys.alarms) == nil {
            saveTimers()
            saveAlarms()
            for key in [Keys.name, Keys.duration, Keys.alarmName, Keys.alarmMinutes, Keys.alarmEnabled, Keys.alarmRepeats] {
                defaults.removeObject(forKey: key)
            }
        }
        observeClock()
        updateTicker()
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    /// 앱이 꺼진 동안 끝난 타이머는 1시간 안이면 켜자마자 울리고, 그보다 오래됐으면 처음 시간으로 둔다.
    private static func restore(_ saved: SavedTimer, at now: Date) -> TimerItem {
        var item = TimerItem(id: saved.id, name: saved.name, duration: min(max(saved.duration, 1), maxDuration))
        switch saved.phase {
        case "running":
            if let end = saved.endDate, now.timeIntervalSince(end) < lateLimit {
                item.phase = .running
                item.endDate = end
            }
        case "paused":
            if let left = saved.pausedRemaining, left > 0 {
                item.phase = .paused
                item.pausedRemaining = min(left, maxDuration)
            }
        default:
            break
        }
        return item
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

    func clockDidChange() {
        NSTimeZone.resetSystemTimeZone()
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

    private func saveTimers() {
        let saved = timers.map { item -> SavedTimer in
            var saved = SavedTimer(id: item.id, name: item.name, duration: item.duration)
            switch item.phase {
            case .running: saved.phase = "running"; saved.endDate = item.endDate
            case .paused: saved.phase = "paused"; saved.pausedRemaining = item.pausedRemaining
            case .idle, .ringing: break
            }
            return saved
        }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Keys.timers) }
    }

    private func saveAlarms() {
        let saved = alarms.map { SavedAlarm(id: $0.id, name: $0.name, minutes: $0.minutes, enabled: $0.enabled, repeats: $0.repeats) }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Keys.alarms) }
    }

    // MARK: 상태

    var selectedTimer: TimerItem { timers.first { $0.id == selectedTimerID } ?? timers[0] }
    var selectedAlarm: AlarmItem? { alarms.first { $0.id == selectedAlarmID } }

    var isRinging: Bool { timers.contains { $0.phase == .ringing } || !ringingAlarmIDs.isEmpty }

    /// 어느 타이머나 알람이 10초 안으로 다가왔을 때.
    var isWarning: Bool {
        timers.contains { $0.isWarning(at: now) } || alarms.contains { $0.isWarning(at: now) }
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

    /// 다음에 울릴 켜진 알람, 이른 것부터.
    var upcomingAlarms: [AlarmItem] {
        alarms.filter { $0.next != nil }.sorted { $0.next! < $1.next! }
    }

    /// 이름을 비워 둔 항목은 목록 순서로 부른다.
    func displayName(of item: TimerItem) -> String {
        if !item.name.trimmingCharacters(in: .whitespaces).isEmpty { return item.name }
        return L("타이머 %d", (timers.firstIndex { $0.id == item.id } ?? 0) + 1)
    }

    func displayName(of item: AlarmItem) -> String {
        if !item.name.trimmingCharacters(in: .whitespaces).isEmpty { return item.name }
        return L("알람 %d", (alarms.firstIndex { $0.id == item.id } ?? 0) + 1)
    }

    // MARK: 타이머

    @discardableResult
    func addTimer() -> UUID {
        let item = TimerItem(name: L("타이머 %d", timers.count + 1), duration: selectedTimer.duration)
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
        let c = Calendar.current.dateComponents([.hour], from: Date())
        var item = AlarmItem(name: L("알람 %d", alarms.count + 1), minutes: minutes ?? ((c.hour ?? 0) + 1) % 24 * 60)
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

    func setAlarmEnabled(_ id: UUID, _ enabled: Bool) {
        updateAlarm(id) { $0.enabled = enabled }
    }

    func setAlarmRepeats(_ id: UUID, _ repeats: Bool) {
        updateAlarm(id) { $0.repeats = repeats }
    }

    /// 시각이나 켜기가 바뀌면 다음에 울릴 때를 다시 셈한다.
    private func updateAlarm(_ id: UUID, _ change: (inout AlarmItem) -> Void) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        var item = alarms[index]
        change(&item)
        if item.minutes != alarms[index].minutes || item.enabled != alarms[index].enabled { item.schedule(after: Date()) }
        if item != alarms[index] { alarms[index] = item }
    }

    // MARK: 울림

    /// 울리는 것을 모두 끈다. 울리던 타이머는 처음 시간으로 돌아간다.
    func stopRinging() {
        if timers.contains(where: { $0.phase == .ringing }) {
            timers = timers.map { var t = $0; if t.phase == .ringing { t.phase = .idle }; return t }
        }
        ringingAlarmIDs = []
        stopSound()
        now = Date()
        updateTicker()
    }

    // MARK: 시계

    /// 화면에 보이거나 곧 울릴 때는 자주, 알람만 기다릴 때는 1초마다, 할 일이 없으면 멈춘다.
    private var wantedInterval: TimeInterval? {
        if isDisplayed || isRinging || timers.contains(where: { $0.phase == .running }) { return 0.1 }
        guard let soonest = upcomingAlarms.first?.next else { return nil }
        return soonest.timeIntervalSince(Date()) < 15 ? 0.1 : 1
    }

    private func updateTicker() {
        let wanted = wantedInterval
        guard wanted != ticker?.timeInterval else { return }
        ticker?.invalidate()
        ticker = nil
        guard let wanted else { return }
        let timer = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = wanted / 5
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
        for i in newAlarms.indices {
            guard let next = newAlarms[i].next, now >= next else { continue }
            if now.timeIntervalSince(next) < Self.lateLimit {
                ringingAlarmIDs.insert(newAlarms[i].id)
                rangAlarm = rangAlarm ?? newAlarms[i].id
            }
            if newAlarms[i].repeats {
                newAlarms[i].schedule(after: max(now, next))
            } else {
                newAlarms[i].enabled = false
                newAlarms[i].next = nil
            }
        }
        if newAlarms != alarms { alarms = newAlarms }

        // 울린 것을 큰 판에 보여 준다. 타이머와 알람이 함께 울리면 타이머를 먼저 보여 준다.
        if let rangAlarm {
            selectedAlarmID = rangAlarm
            mode = .alarm
        }
        if let rangTimer {
            selectedTimerID = rangTimer
            mode = .timer
        }
        if rangTimer != nil || rangAlarm != nil { ring() }
        updateTicker()
    }

    /// 새로 울릴 때마다 1분 제한을 다시 센다.
    private func ring() {
        onRing?()
        stopSound()
        let started = Date()
        var beat = 0
        let timer = Timer(timeInterval: Self.ringInterval, repeats: true) { [weak self] _ in
            guard let self, self.isRinging, Date().timeIntervalSince(started) < Self.soundLimit else {
                self?.stopSound()
                return
            }
            if Self.ringPattern[beat % Self.ringPattern.count] { AlarmSound.play() }
            beat += 1
        }
        RunLoop.main.add(timer, forMode: .common)
        soundTimer = timer
        timer.fire()
    }

    /// 소리가 울리는 중인지. 시험에서 확인한다.
    var isSounding: Bool { soundTimer != nil }

    private func stopSound() {
        soundTimer?.invalidate()
        soundTimer = nil
        AlarmSound.stop()
    }

    /// "90"은 90분, "5:00"은 5분, "1:30:00"은 1시간 30분.
    static func parse(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        let numbers = parts.map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !numbers.isEmpty, numbers.count <= 3, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let values = numbers.map { $0! }
        let seconds: Int
        switch values.count {
        case 1: seconds = values[0] * 60
        case 2: seconds = values[0] * 60 + values[1]
        default: seconds = values[0] * 3600 + values[1] * 60 + values[2]
        }
        return seconds > 0 ? seconds : nil
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
