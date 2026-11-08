import AppKit
import SwiftUI

/// 위에서부터 이름, 타이머·알람 고르기, 큰 숫자판, 조작 버튼, 목록 순서다.
/// 창 크기는 고정이고 목록이 길어지면 목록 안에서만 스크롤된다.
struct FlipTimerView: View {
    @ObservedObject var store: ClockStore
    @ObservedObject var settings: ClockySettings
    /// 다시 울림 버튼의 자리를 창에 알린다. 창 왼쪽 위가 원점이다.
    var onSnoozeFrame: ((CGRect) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            // 닫기 버튼과 같은 줄. 양쪽 폭을 맞춰 이름이 가운데 오게 한다.
            HStack(spacing: 0) {
                Color.clear.frame(width: 44, height: 1)
                TextField(namePlaceholder, text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .disabled(store.mode == .alarm && store.selectedAlarm == nil)
                    // 고른 항목이 바뀌면 칸을 새로 만들어, 고치던 글자가 다른 항목에 들어가지 않게 한다.
                    .id(selectionKey)
                Button {
                    store.isPinned.toggle()
                } label: {
                    Image(systemName: store.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .help(store.isPinned ? L("항상 위 해제") : L("항상 위"))
                .accessibilityLabel(L("항상 위"))
                .accessibilityValue(store.isPinned ? L("켜짐") : L("꺼짐"))
                .frame(width: 44, alignment: .trailing)
            }
            .frame(height: 22)

            Picker("", selection: $store.mode) {
                Text(L("타이머")).tag(ClockStore.Mode.timer)
                Text(L("알람")).tag(ClockStore.Mode.alarm)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)

            HStack(spacing: 6) {
                let units = store.displayedUnits
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
        .background(Color.red.opacity(store.isFlashing ? 0.35 : 0))
        .animation(.easeInOut(duration: 0.15), value: store.isFlashing)
        .onPreferenceChange(SnoozeFrameKey.self) { onSnoozeFrame?($0) }
    }

    private var selectionKey: String {
        store.mode == .timer ? "timer-\(store.selectedTimerID)" : "alarm-\(store.selectedAlarmID?.uuidString ?? "")"
    }

    /// 이름을 비워 두면 목록에서 부르는 이름이 흐리게 보인다.
    private var namePlaceholder: String {
        switch store.mode {
        case .timer: return store.displayName(of: store.selectedTimer)
        case .alarm: return store.selectedAlarm.map { store.displayName(of: $0) } ?? L("이름")
        }
    }

    private var nameBinding: Binding<String> {
        switch store.mode {
        case .timer:
            let id = store.selectedTimerID
            return Binding(get: { store.selectedTimer.name }, set: { store.renameTimer(id, to: $0) })
        case .alarm:
            guard let id = store.selectedAlarmID else { return .constant("") }
            return Binding(get: { store.selectedAlarm?.name ?? "" }, set: { store.renameAlarm(id, to: $0) })
        }
    }

    // MARK: 조작

    @ViewBuilder
    private var controls: some View {
        if store.isRinging {
            VStack(spacing: 6) {
                Text(L("창을 누르거나 Esc로 끄기"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                // 울리는 동안 창의 다른 곳을 누르면 꺼지지만, 이 버튼은 눌린다.
                Button(L("%d분 뒤 다시 울림", store.snoozeMinutes)) { store.snooze() }
                    .controlSize(.small)
                    .help(L("S 키로도 됩니다"))
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: SnoozeFrameKey.self, value: geometry.frame(in: .global))
                    })
            }
        } else if store.mode == .timer {
            timerControls(store.selectedTimer)
        } else if let alarm = store.selectedAlarm {
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
                    ForEach(ClockStore.presets, id: \.self) { minutes in
                        Button(L("%d분", minutes)) { store.setDuration(item.id, minutes * 60) }
                    }
                    Button(L("직접…")) { askDuration(for: item.id) }
                }
                .controlSize(.small)
                Button(L("시작")) { store.start(item.id) }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            HStack(spacing: 8) {
                if item.phase == .running {
                    Button(L("일시정지")) { store.pause(item.id) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("계속")) { store.start(item.id) }
                        .keyboardShortcut(.defaultAction)
                }
                Button(L("초기화")) { store.reset(item.id) }
            }
        }
    }

    private func alarmControls(_ alarm: AlarmItem) -> some View {
        let id = alarm.id
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                DatePicker("", selection: Binding(get: { store.alarms.first { $0.id == id }?.timeToday ?? Date() },
                                                  set: { store.setAlarmTime(id, $0) }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .fixedSize()
                daysMenu(alarm)
                Toggle(L("켜기"), isOn: Binding(get: { store.alarms.first { $0.id == id }?.enabled ?? false },
                                               set: { store.setAlarmEnabled(id, $0) }))
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
        guard let next = alarm.upcoming else { return L("알람 꺼짐") }
        return L("%@ %@에 울림 · %@ 남음", settings.dayText(next), settings.timeText(next), remainingText(until: next, from: store.now))
    }

    /// 매일·평일·주말·한 번을 고르거나 요일을 하나씩 켜고 끈다.
    private func daysMenu(_ alarm: AlarmItem) -> some View {
        let id = alarm.id
        let days = Binding(get: { store.alarms.first { $0.id == id }?.days ?? [] }, set: { store.setAlarmDays(id, $0) })
        return Menu(daysText(alarm.days)) {
            ForEach([AlarmItem.everyDay, AlarmItem.weekdays, AlarmItem.weekend, []], id: \.self) { preset in
                Toggle(daysText(preset), isOn: Binding(get: { days.wrappedValue == preset }, set: { if $0 { days.wrappedValue = preset } }))
            }
            Divider()
            ForEach(weekdayOrder, id: \.self) { day in
                Toggle(L(weekdayNames[day - 1]), isOn: Binding(
                    get: { days.wrappedValue.contains(day) },
                    set: { isOn in
                        var value = days.wrappedValue
                        if isOn { value.insert(day) } else { value.remove(day) }
                        days.wrappedValue = value
                    }))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("반복"))
        .accessibilityLabel(L("반복"))
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
        if let seconds = ClockStore.parse(field.stringValue) { store.setDuration(id, seconds) } else { NSSound.beep() }
    }

    // MARK: 목록

    private var list: some View {
        VStack(spacing: 4) {
            HStack {
                Text(store.mode == .timer ? L("타이머 %d개", store.timers.count) : L("알람 %d개", store.alarms.count))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if store.mode == .timer { store.addTimer() } else { store.addAlarm() }
                } label: {
                    Label(store.mode == .timer ? L("타이머 추가") : L("알람 추가"), systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if store.mode == .timer {
                            ForEach(store.timers) { timerRow($0).id($0.id) }
                        } else if store.alarms.isEmpty {
                            Text(L("등록된 알람이 없습니다"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.top, 20)
                        } else {
                            ForEach(store.alarms) { alarmRow($0).id($0.id) }
                        }
                    }
                }
                .onChange(of: selectionKey) { _ in
                    let id = store.mode == .timer ? store.selectedTimerID : store.selectedAlarmID
                    if let id { withAnimation { proxy.scrollTo(id) } }
                }
            }
        }
    }

    private func timerRow(_ item: TimerItem) -> some View {
        let warning = item.isWarning(at: store.now, within: store.warningSeconds) || item.phase == .ringing
        return row(selected: item.id == store.selectedTimerID, select: { store.selectedTimerID = item.id }) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.displayName(of: item))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(phaseText(item.phase))
                    .font(.system(size: 11))
                    .foregroundStyle(warning ? Color.red : Color.secondary)
            }
            Spacer(minLength: 4)
            Text(clockText(item.remaining(at: store.now)))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(warning ? Color.red : Color.primary)
            Group {
                switch item.phase {
                case .running:
                    Button { store.pause(item.id) } label: { Image(systemName: "pause.fill") }
                        .help(L("일시정지"))
                        .accessibilityLabel(L("%@ 일시정지", store.displayName(of: item)))
                case .idle, .paused:
                    Button { store.start(item.id) } label: { Image(systemName: "play.fill") }
                        .help(L("시작"))
                        .accessibilityLabel(L("%@ 시작", store.displayName(of: item)))
                case .ringing:
                    Color.clear
                }
            }
            .frame(width: 18)
            Button { if settings.confirmRemoval(count: 1) { store.removeTimer(item.id) } } label: { Image(systemName: "xmark") }
                .help(L("삭제 (⌘Z로 되돌리기)"))
                .accessibilityLabel(L("%@ 삭제", store.displayName(of: item)))
                .disabled(store.timers.count <= 1)
                .frame(width: 18)
        }
    }

    private func alarmRow(_ item: AlarmItem) -> some View {
        let warning = item.isWarning(at: store.now, within: store.warningSeconds) || store.ringingAlarmIDs.contains(item.id)
        return row(selected: item.id == store.selectedAlarmID, select: { store.selectedAlarmID = item.id }) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.displayName(of: item))
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
            Toggle("", isOn: Binding(get: { store.alarms.first { $0.id == item.id }?.enabled ?? false },
                                     set: { store.setAlarmEnabled(item.id, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(L("%@ 켜기", store.displayName(of: item)))
            Button { if settings.confirmRemoval(count: 1) { store.removeAlarm(item.id) } } label: { Image(systemName: "xmark") }
                .help(L("삭제 (⌘Z로 되돌리기)"))
                .accessibilityLabel(L("%@ 삭제", store.displayName(of: item)))
                .frame(width: 18)
        }
    }

    /// "매일 · 3시간 2분 남음", "한 번 · 45분 남음", "울림".
    private func alarmRowStatus(_ item: AlarmItem) -> String {
        store.ringingAlarmIDs.contains(item.id) ? L("울림") : alarmSummary(item, now: store.now)
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
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: L("고르기"), select)
    }
}

/// 다시 울림 버튼의 자리. 울리는 동안 창이 클릭을 가로챌 때 이 자리는 그대로 넘긴다.
struct SnoozeFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
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
