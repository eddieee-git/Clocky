import AppKit
import Combine
import SwiftUI

/// 작은 시계 창. 숫자판이 넘어가는 탁상시계처럼 초 단위로 움직인다.
/// 타이머는 정한 시간만큼 줄어들고, 알람은 지금 시각을 보여 주다가 정한 시각(매일 반복 가능)에 울린다.
final class FlipTimer: ObservableObject {
    enum Mode: String { case timer, alarm }
    enum Phase { case idle, running, paused, ringing }

    static let presets = [1, 3, 5, 10, 25]
    /// 끝나기 몇 초 전부터 깜빡일지.
    static let warningSeconds = 10
    /// 잠자기 등으로 늦게 확인했을 때 이 안이면 늦게라도 울린다.
    private static let lateLimit: TimeInterval = 3600
    private static let rings = 3
    private static let ringInterval: TimeInterval = 0.6

    private enum Keys {
        static let mode = "timerMode", name = "timerName", duration = "timerDuration", pinned = "timerPinned"
        static let alarmName = "alarmName", alarmMinutes = "alarmMinutes"
        static let alarmEnabled = "alarmEnabled", alarmRepeats = "alarmRepeats"
    }
    private let defaults = UserDefaults.standard

    @Published var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: Keys.mode); updateTicker() } }
    /// 항상 위. 기본은 켬.
    @Published var isPinned: Bool { didSet { defaults.set(isPinned, forKey: Keys.pinned) } }
    @Published private(set) var now = Date()
    /// 창이 화면에 있는지. 시계를 보여 줄 때만 자주 깨어난다.
    var isDisplayed = false { didSet { updateTicker() } }
    /// 울리기 시작하면 불린다. 창을 앞으로 가져오는 데 쓴다.
    var onRing: (() -> Void)?
    private var ticker: Timer?

    // MARK: 타이머

    @Published var name: String { didSet { defaults.set(name, forKey: Keys.name) } }
    /// 정해 둔 시간(초). 초기화하면 여기로 돌아간다.
    @Published private(set) var duration: Int { didSet { defaults.set(duration, forKey: Keys.duration) } }
    @Published private(set) var phase = Phase.idle
    private var endDate: Date?
    private var pausedRemaining = 0

    // MARK: 알람

    @Published var alarmName: String { didSet { defaults.set(alarmName, forKey: Keys.alarmName) } }
    /// 시와 분만 쓴다.
    @Published var alarmTime: Date {
        didSet {
            let c = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
            defaults.set((c.hour ?? 0) * 60 + (c.minute ?? 0), forKey: Keys.alarmMinutes)
            scheduleAlarm()
        }
    }
    @Published var alarmEnabled: Bool { didSet { defaults.set(alarmEnabled, forKey: Keys.alarmEnabled); scheduleAlarm() } }
    /// 끄면 한 번 울린 뒤 스스로 꺼진다.
    @Published var alarmRepeats: Bool { didSet { defaults.set(alarmRepeats, forKey: Keys.alarmRepeats) } }
    @Published private(set) var nextAlarm: Date?
    @Published private(set) var isAlarmRinging = false

    init() {
        mode = defaults.string(forKey: Keys.mode).flatMap(Mode.init) ?? .timer
        isPinned = defaults.object(forKey: Keys.pinned) as? Bool ?? true
        name = defaults.string(forKey: Keys.name) ?? ""
        let saved = defaults.integer(forKey: Keys.duration)
        duration = saved > 0 ? saved : 5 * 60
        alarmName = defaults.string(forKey: Keys.alarmName) ?? ""
        let minutes = defaults.object(forKey: Keys.alarmMinutes) as? Int ?? 9 * 60
        alarmTime = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        alarmEnabled = defaults.bool(forKey: Keys.alarmEnabled)
        alarmRepeats = defaults.object(forKey: Keys.alarmRepeats) as? Bool ?? true
        scheduleAlarm()
    }

    var isRinging: Bool { phase == .ringing || isAlarmRinging }

    /// 남은 초. 0.3초가 남았으면 1초로 보여 줘야 0이 되는 순간 끝난다.
    var remaining: Int {
        switch phase {
        case .idle: return duration
        case .paused: return pausedRemaining
        case .ringing: return 0
        case .running:
            guard let endDate else { return 0 }
            return max(0, Int(ceil(endDate.timeIntervalSince(now) - 0.001)))
        }
    }

    /// 판에 보일 시·분·초. 타이머는 남은 시간, 알람은 지금 시각.
    var displayedUnits: [Int] {
        switch mode {
        case .timer:
            let s = remaining
            return [s / 3600, s / 60 % 60, s % 60]
        case .alarm:
            let c = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
            return [c.hour ?? 0, c.minute ?? 0, c.second ?? 0]
        }
    }

    /// 타이머나 알람이 10초 안으로 다가왔을 때.
    var isWarning: Bool {
        if phase == .running && remaining > 0 && remaining <= Self.warningSeconds { return true }
        if let nextAlarm {
            let left = nextAlarm.timeIntervalSince(now)
            return left > 0 && left <= TimeInterval(Self.warningSeconds)
        }
        return false
    }

    /// 끝나기 직전과 울리는 동안 0.5초마다 켜졌다 꺼진다.
    var isFlashing: Bool {
        (isWarning || isRinging) && Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0
    }

    func setDuration(_ seconds: Int) {
        guard seconds > 0 else { return }
        duration = min(seconds, 100 * 3600 - 1)
        phase = .idle
        updateTicker()
    }

    func start() {
        switch phase {
        case .idle: endDate = Date().addingTimeInterval(TimeInterval(duration))
        case .paused: endDate = Date().addingTimeInterval(TimeInterval(pausedRemaining))
        case .running, .ringing: return
        }
        phase = .running
        now = Date()
        updateTicker()
    }

    func pause() {
        guard phase == .running else { return }
        pausedRemaining = remaining
        phase = .paused
        updateTicker()
    }

    func reset() {
        phase = .idle
        now = Date()
        updateTicker()
    }

    /// 울리는 것을 모두 끈다. 타이머는 처음 시간으로 돌아간다.
    func stopRinging() {
        if phase == .ringing { phase = .idle }
        isAlarmRinging = false
        now = Date()
        updateTicker()
    }

    private func scheduleAlarm(after date: Date = Date()) {
        guard alarmEnabled else { nextAlarm = nil; updateTicker(); return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        nextAlarm = Calendar.current.nextDate(after: date, matching: DateComponents(hour: c.hour, minute: c.minute, second: 0),
                                              matchingPolicy: .nextTime)
        updateTicker()
    }

    // MARK: 시계

    /// 화면에 보이거나 곧 울릴 때는 자주, 알람만 기다릴 때는 1초마다, 할 일이 없으면 멈춘다.
    private var wantedInterval: TimeInterval? {
        if phase == .running || isRinging || isDisplayed { return 0.1 }
        if let nextAlarm { return nextAlarm.timeIntervalSince(Date()) < 15 ? 0.1 : 1 }
        return nil
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
        if phase == .running && remaining == 0 {
            phase = .ringing
            ring(.timer)
        }
        if let next = nextAlarm, now >= next {
            if now.timeIntervalSince(next) < Self.lateLimit {
                isAlarmRinging = true
                ring(.alarm)
            }
            if alarmRepeats { scheduleAlarm(after: max(now, next)) } else { alarmEnabled = false }
        }
        updateTicker()
    }

    private func ring(_ source: Mode) {
        mode = source
        onRing?()
        for ring in 0..<Self.rings {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(ring) * Self.ringInterval) { [weak self] in
                if self?.isRinging == true { AlarmSound.play() }
            }
        }
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

/// "3시간 2분", "45분"처럼 남은 시간을 분 단위로 올려 적는다.
func remainingText(until date: Date, from now: Date) -> String {
    let minutes = max(Int((date.timeIntervalSince(now) / 60).rounded(.up)), 1)
    let (days, hours, rest) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
    if days > 0 { return hours > 0 ? L("%d일 %d시간", days, hours) : L("%d일", days) }
    if hours > 0 { return rest > 0 ? L("%d시간 %d분", hours, rest) : L("%d시간", hours) }
    return L("%d분", rest)
}

final class FlipTimerWindowController: NSObject, NSWindowDelegate {
    static let contentSize = NSSize(width: 340, height: 234)

    let timer = FlipTimer()
    private let settings: ClockySettings
    private(set) lazy var panel: TimerPanel = makePanel()
    private var isLoaded = false
    private var pinSubscription: AnyCancellable?

    init(settings: ClockySettings) {
        self.settings = settings
        super.init()
        timer.onRing = { [weak self] in self?.show() }
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
        if !panel.isVisible { panel.setFrameOrigin(defaultOrigin()) }
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

    /// 창의 윗부분이 어느 화면에도 충분히 걸쳐 있지 않으면 기본 자리로 옮긴다.
    func ensureOnScreen() {
        guard isVisible else { return }
        let top = NSRect(x: panel.frame.minX, y: panel.frame.maxY - 30, width: panel.frame.width, height: 30)
        let reachable = NSScreen.screens.contains { screen in
            let visible = screen.visibleFrame.intersection(top)
            return visible.width >= 60 && visible.height >= 15
        }
        if !reachable { panel.setFrameOrigin(defaultOrigin()) }
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

// MARK: - 화면

struct FlipTimerView: View {
    @ObservedObject var timer: FlipTimer
    @ObservedObject var settings: ClockySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            // 닫기 버튼과 같은 줄. 양쪽 폭을 맞춰 이름이 가운데 오게 한다.
            HStack(spacing: 0) {
                Color.clear.frame(width: 44, height: 1)
                TextField(L("이름"), text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                Button {
                    timer.isPinned.toggle()
                } label: {
                    Image(systemName: timer.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .help(timer.isPinned ? L("항상 위 해제") : L("항상 위"))
                .frame(width: 44, alignment: .trailing)
            }
            .frame(height: 22)

            Picker("", selection: $timer.mode) {
                Text(L("타이머")).tag(FlipTimer.Mode.timer)
                Text(L("알람")).tag(FlipTimer.Mode.alarm)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)

            HStack(spacing: 6) {
                let units = timer.displayedUnits
                ForEach(units.indices, id: \.self) { i in
                    if i > 0 {
                        Text(":")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    FlipCard(value: String(format: "%02d", units[i]), dark: colorScheme == .dark)
                }
            }

            controls
                .frame(height: 52)
        }
        .padding(.horizontal, 14)
        .padding(.top, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 제목 표시줄 자리까지 써서 이름과 압정이 닫기 버튼과 같은 줄에 오게 한다.
        .ignoresSafeArea()
        .background(Color.red.opacity(timer.isFlashing ? 0.35 : 0))
        .animation(.easeInOut(duration: 0.15), value: timer.isFlashing)
        .id(settings.language)
    }

    private var nameBinding: Binding<String> {
        timer.mode == .timer ? $timer.name : $timer.alarmName
    }

    @ViewBuilder
    private var controls: some View {
        if timer.isRinging {
            Text(L("눌러서 알람 끄기"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else if timer.mode == .timer {
            timerControls
        } else {
            alarmControls
        }
    }

    @ViewBuilder
    private var timerControls: some View {
        if timer.phase == .idle {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(FlipTimer.presets, id: \.self) { minutes in
                        Button(L("%d분", minutes)) { timer.setDuration(minutes * 60) }
                    }
                    Button(L("직접…")) { askDuration() }
                }
                .controlSize(.small)
                Button(L("시작")) { timer.start() }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            HStack(spacing: 8) {
                if timer.phase == .running {
                    Button(L("일시정지")) { timer.pause() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("계속")) { timer.start() }
                        .keyboardShortcut(.defaultAction)
                }
                Button(L("초기화")) { timer.reset() }
            }
        }
    }

    private var alarmControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                DatePicker("", selection: $timer.alarmTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .fixedSize()
                Toggle(L("매일"), isOn: $timer.alarmRepeats)
                Toggle(L("켜기"), isOn: $timer.alarmEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Text(alarmStatus)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var alarmStatus: String {
        guard let next = timer.nextAlarm else { return L("알람 꺼짐") }
        let day = Calendar.current.isDateInToday(next) ? L("오늘") : L("내일")
        return L("%@ %@에 울림 · %@ 남음", day, settings.timeText(next), remainingText(until: next, from: timer.now))
    }

    private func askDuration() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "5:00"
        let alert = NSAlert()
        alert.messageText = L("시간 입력")
        alert.informativeText = L("분, 분:초, 또는 시:분:초로 입력합니다. 예: 90, 5:30, 1:30:00")
        alert.accessoryView = field
        alert.addButton(withTitle: L("설정"))
        alert.addButton(withTitle: L("취소"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let seconds = FlipTimer.parse(field.stringValue) { timer.setDuration(seconds) } else { NSSound.beep() }
    }
}

/// 숫자 두 자리가 적힌 판 하나. 값이 바뀌면 위쪽 반이 아래로 접히며 새 숫자가 드러난다.
struct FlipCard: View {
    let value: String
    let dark: Bool

    static let size = CGSize(width: 86, height: 80)
    private static let flipDuration = 0.14

    @State private var shown: String
    @State private var previous: String
    @State private var topAngle: Double = -90
    @State private var bottomAngle: Double = 0

    init(value: String, dark: Bool) {
        self.value = value
        self.dark = dark
        _shown = State(initialValue: value)
        _previous = State(initialValue: value)
    }

    var body: some View {
        ZStack {
            // 뒤에 고정된 판: 위는 새 숫자, 아래는 아직 덮이지 않은 옛 숫자.
            VStack(spacing: 1.5) {
                half(shown, top: true)
                half(previous, top: false)
            }
            // 넘어가는 판: 옛 숫자의 위쪽 반이 접혀 내려오고, 새 숫자의 아래쪽 반이 펼쳐진다.
            VStack(spacing: 1.5) {
                half(previous, top: true)
                    .rotation3DEffect(.degrees(topAngle), axis: (1, 0, 0), anchor: .bottom, perspective: 0.4)
                    .opacity(topAngle <= -89 ? 0 : 1)
                half(shown, top: false)
                    .rotation3DEffect(.degrees(bottomAngle), axis: (1, 0, 0), anchor: .top, perspective: 0.4)
                    .opacity(bottomAngle >= 89 ? 0 : 1)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height + 1.5)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .onChange(of: value) { newValue in flip(to: newValue) }
    }

    private func flip(to newValue: String) {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            previous = shown
            shown = newValue
            topAngle = 0
            bottomAngle = 90
        }
        DispatchQueue.main.async {
            withAnimation(.easeIn(duration: Self.flipDuration)) { topAngle = -90 }
            withAnimation(.easeOut(duration: Self.flipDuration).delay(Self.flipDuration)) { bottomAngle = 0 }
        }
    }

    private func half(_ text: String, top: Bool) -> some View {
        Text(text)
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundColor(dark ? Color(white: 0.95) : Color(white: 0.12))
            .frame(width: Self.size.width, height: Self.size.height)
            .frame(width: Self.size.width, height: Self.size.height / 2, alignment: top ? .top : .bottom)
            .background(dark ? Color(white: 0.13) : Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
