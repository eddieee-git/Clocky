import AppKit
import SwiftUI

/// 위에서부터 이름, 타이머·알람 고르기, 큰 숫자판, 조작 버튼, 목록 순서다.
/// 창 크기는 고정이고 목록이 길어지면 목록 안에서만 스크롤된다.
struct FlipTimerView: View {
    @ObservedObject var timer: FlipTimer
    @ObservedObject var settings: ClockySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            // 닫기 버튼과 같은 줄. 양쪽 폭을 맞춰 이름이 가운데 오게 한다.
            HStack(spacing: 0) {
                Color.clear.frame(width: 44, height: 1)
                TextField(L("이름"), text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .disabled(timer.mode == .alarm && timer.selectedAlarm == nil)
                    // 고른 항목이 바뀌면 칸을 새로 만들어, 고치던 글자가 다른 항목에 들어가지 않게 한다.
                    .id(selectionKey)
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
            // 다른 항목으로 바꿀 때는 넘기지 않고 바로 보여 준다.
            .id(selectionKey)

            controls
                .frame(height: 52)

            Divider()
            list
        }
        .padding(.horizontal, 14)
        .padding(.top, 5)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 제목 표시줄 자리까지 써서 이름과 압정이 닫기 버튼과 같은 줄에 오게 한다.
        .ignoresSafeArea()
        .background(Color.red.opacity(timer.isFlashing ? 0.35 : 0))
        .animation(.easeInOut(duration: 0.15), value: timer.isFlashing)
    }

    private var selectionKey: String {
        timer.mode == .timer ? "timer-\(timer.selectedTimerID)" : "alarm-\(timer.selectedAlarmID?.uuidString ?? "")"
    }

    private var nameBinding: Binding<String> {
        switch timer.mode {
        case .timer:
            let id = timer.selectedTimerID
            return Binding(get: { timer.selectedTimer.name }, set: { timer.renameTimer(id, to: $0) })
        case .alarm:
            guard let id = timer.selectedAlarmID else { return .constant("") }
            return Binding(get: { timer.selectedAlarm?.name ?? "" }, set: { timer.renameAlarm(id, to: $0) })
        }
    }

    // MARK: 조작

    @ViewBuilder
    private var controls: some View {
        if timer.isRinging {
            Text(L("눌러서 알람 끄기"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else if timer.mode == .timer {
            timerControls(timer.selectedTimer)
        } else if let alarm = timer.selectedAlarm {
            alarmControls(alarm)
        } else {
            Text(L("알람 추가를 눌러 시각을 등록합니다"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func timerControls(_ item: TimerItem) -> some View {
        if item.phase == .idle {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(FlipTimer.presets, id: \.self) { minutes in
                        Button(L("%d분", minutes)) { timer.setDuration(item.id, minutes * 60) }
                    }
                    Button(L("직접…")) { askDuration(for: item.id) }
                }
                .controlSize(.small)
                Button(L("시작")) { timer.start(item.id) }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            HStack(spacing: 8) {
                if item.phase == .running {
                    Button(L("일시정지")) { timer.pause(item.id) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("계속")) { timer.start(item.id) }
                        .keyboardShortcut(.defaultAction)
                }
                Button(L("초기화")) { timer.reset(item.id) }
            }
        }
    }

    private func alarmControls(_ alarm: AlarmItem) -> some View {
        let id = alarm.id
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                DatePicker("", selection: Binding(get: { timer.alarms.first { $0.id == id }?.timeToday ?? Date() },
                                                  set: { timer.setAlarmTime(id, $0) }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .fixedSize()
                Toggle(L("매일"), isOn: Binding(get: { timer.alarms.first { $0.id == id }?.repeats ?? false },
                                               set: { timer.setAlarmRepeats(id, $0) }))
                Toggle(L("켜기"), isOn: Binding(get: { timer.alarms.first { $0.id == id }?.enabled ?? false },
                                               set: { timer.setAlarmEnabled(id, $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Text(alarmStatus(alarm))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .id(id)
    }

    private func alarmStatus(_ alarm: AlarmItem) -> String {
        guard let next = alarm.next else { return L("알람 꺼짐") }
        let day = Calendar.current.isDateInToday(next) ? L("오늘") : L("내일")
        return L("%@ %@에 울림 · %@ 남음", day, settings.timeText(next), remainingText(until: next, from: timer.now))
    }

    private func askDuration(for id: UUID) {
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
        if let seconds = FlipTimer.parse(field.stringValue) { timer.setDuration(id, seconds) } else { NSSound.beep() }
    }

    // MARK: 목록

    private var list: some View {
        VStack(spacing: 4) {
            HStack {
                Text(timer.mode == .timer ? L("타이머 %d개", timer.timers.count) : L("알람 %d개", timer.alarms.count))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if timer.mode == .timer { timer.addTimer() } else { timer.addAlarm() }
                } label: {
                    Label(timer.mode == .timer ? L("타이머 추가") : L("알람 추가"), systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if timer.mode == .timer {
                            ForEach(timer.timers) { timerRow($0).id($0.id) }
                        } else if timer.alarms.isEmpty {
                            Text(L("등록된 알람이 없습니다"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.top, 20)
                        } else {
                            ForEach(timer.alarms) { alarmRow($0).id($0.id) }
                        }
                    }
                }
                .onChange(of: selectionKey) { _ in
                    let id = timer.mode == .timer ? timer.selectedTimerID : timer.selectedAlarmID
                    if let id { withAnimation { proxy.scrollTo(id) } }
                }
            }
        }
    }

    private func timerRow(_ item: TimerItem) -> some View {
        let warning = item.isWarning(at: timer.now) || item.phase == .ringing
        return row(selected: item.id == timer.selectedTimerID, select: { timer.selectedTimerID = item.id }) {
            VStack(alignment: .leading, spacing: 1) {
                Text(timer.displayName(of: item))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(phaseText(item.phase))
                    .font(.system(size: 11))
                    .foregroundStyle(warning ? Color.red : Color.secondary)
            }
            Spacer(minLength: 4)
            Text(clockText(item.remaining(at: timer.now)))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(warning ? Color.red : Color.primary)
            Group {
                switch item.phase {
                case .running:
                    Button { timer.pause(item.id) } label: { Image(systemName: "pause.fill") }.help(L("일시정지"))
                case .idle, .paused:
                    Button { timer.start(item.id) } label: { Image(systemName: "play.fill") }.help(L("시작"))
                case .ringing:
                    Color.clear
                }
            }
            .frame(width: 18)
            Button { timer.removeTimer(item.id) } label: { Image(systemName: "xmark") }
                .help(L("삭제 (⌘Z로 되돌리기)"))
                .disabled(timer.timers.count <= 1)
                .frame(width: 18)
        }
    }

    private func alarmRow(_ item: AlarmItem) -> some View {
        let warning = item.isWarning(at: timer.now) || timer.ringingAlarmIDs.contains(item.id)
        return row(selected: item.id == timer.selectedAlarmID, select: { timer.selectedAlarmID = item.id }) {
            VStack(alignment: .leading, spacing: 1) {
                Text(timer.displayName(of: item))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(alarmRowStatus(item))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(warning ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(settings.timeText(item.timeToday))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(item.enabled ? (warning ? Color.red : Color.primary) : Color.secondary)
            Toggle("", isOn: Binding(get: { timer.alarms.first { $0.id == item.id }?.enabled ?? false },
                                     set: { timer.setAlarmEnabled(item.id, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            Button { timer.removeAlarm(item.id) } label: { Image(systemName: "xmark") }
                .help(L("삭제 (⌘Z로 되돌리기)"))
                .frame(width: 18)
        }
    }

    /// "매일 · 3시간 2분 남음", "한 번 · 45분 남음", "꺼짐".
    private func alarmRowStatus(_ item: AlarmItem) -> String {
        if timer.ringingAlarmIDs.contains(item.id) { return L("울림") }
        let repeats = item.repeats ? L("매일") : L("한 번")
        guard let next = item.next else { return L("%@ · 꺼짐", repeats) }
        return L("%@ · %@ 남음", repeats, remainingText(until: next, from: timer.now))
    }

    private func phaseText(_ phase: TimerItem.Phase) -> String {
        switch phase {
        case .idle: return L("대기")
        case .running: return L("진행 중")
        case .paused: return L("일시정지됨")
        case .ringing: return L("울림")
        }
    }

    private func row<Content: View>(selected: Bool, select: @escaping () -> Void,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
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
