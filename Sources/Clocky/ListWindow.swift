import AppKit
import Combine
import SwiftUI

/// 전체 목록 창. 왼쪽에 모든 타이머와 알람을, 오른쪽에 고른 항목의 편집기를 보여 준다.
/// 시계 창은 크기가 고정이라 여기서 여러 개를 한꺼번에 살피고 고친다.
final class ListWindowController: NSObject, NSWindowDelegate {
    let model: ClockListModel
    private let undoManager: UndoManager
    private var window: ListWindow?

    init(model: ClockListModel, undoManager: UndoManager) {
        self.model = model
        self.undoManager = undoManager
        super.init()
        NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.window?.title = L("전체 목록")
        }
    }

    var isVisible: Bool { window?.isVisible == true }
    var windowNumber: Int { window?.windowNumber ?? 0 }

    func show() {
        if window == nil {
            let w = ListWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = L("전체 목록")
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 640, height: 400)
            // 항상 위 시계 창에 가려지지 않게 한다.
            w.level = .floating
            w.delegate = self
            w.contentView = NSHostingView(rootView: ClockListView(model: model, store: model.store, settings: model.settings))
            w.setFrameAutosaveName("ClockyList")
            if !w.setFrameUsingName("ClockyList") { w.center() }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.store.isListDisplayed = true
    }

    func windowWillClose(_ notification: Notification) {
        model.store.isListDisplayed = false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        model.store.isListDisplayed = false
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        model.store.isListDisplayed = true
    }

    /// 시계 창과 같은 되돌리기 기록을 쓴다.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManager
    }
}

/// ⌘Z가 편집 메뉴를 거쳐 이 창까지 오면 같은 기록으로 되돌린다.
final class ListWindow: NSWindow {
    @objc func undo(_ sender: Any?) { undoManager?.undo() }
    @objc func redo(_ sender: Any?) { undoManager?.redo() }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(undo(_:)) { return undoManager?.canUndo ?? false }
        if item.action == #selector(redo(_:)) { return undoManager?.canRedo ?? false }
        return super.validateMenuItem(item)
    }
}

enum ListFilter: String, CaseIterable {
    case all = "전체"
    case timers = "타이머"
    case alarms = "알람"
}

enum AlarmSort: String, CaseIterable {
    case next = "다음 울림 순"
    case time = "시각 순"
    case name = "이름 순"
    case added = "추가한 순"
}

final class ClockListModel: ObservableObject {
    let store: ClockStore
    let settings: ClockySettings
    @Published var filter: ListFilter = .all
    @Published var sort: AlarmSort = .next
    @Published var query = ""
    @Published var selection = Set<UUID>()
    /// 시계 창에 그 항목을 띄운다.
    var onReveal: (UUID) -> Void = { _ in }

    init(store: ClockStore, settings: ClockySettings) {
        self.store = store
        self.settings = settings
    }

    private func matches(_ name: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }

    var timers: [TimerItem] {
        guard filter != .alarms else { return [] }
        return store.timers.filter { matches(store.displayName(of: $0)) }
    }

    var alarms: [AlarmItem] {
        guard filter != .timers else { return [] }
        let found = store.alarms.filter { matches(store.displayName(of: $0)) }
        switch sort {
        case .added: return found
        case .time: return found.sorted { $0.minutes < $1.minutes }
        case .name: return found.sorted { store.displayName(of: $0).localizedStandardCompare(store.displayName(of: $1)) == .orderedAscending }
        case .next:
            // 꺼진 알람은 뒤로 보내고 시각 순으로 둔다.
            return found.sorted {
                switch ($0.upcoming, $1.upcoming) {
                case let (a?, b?): return a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return $0.minutes < $1.minutes
                }
            }
        }
    }

    func timer(_ id: UUID) -> TimerItem? { store.timers.first { $0.id == id } }
    func alarm(_ id: UUID) -> AlarmItem? { store.alarms.first { $0.id == id } }

    func addTimer() {
        if filter == .alarms { filter = .all }
        let id = store.addTimer()
        query = ""
        selection = [id]
    }

    func addAlarm() {
        if filter == .timers { filter = .all }
        let id = store.addAlarm()
        query = ""
        selection = [id]
    }

    func duplicate(_ ids: Set<UUID>) {
        var made = Set<UUID>()
        for id in ids {
            if let copy = store.duplicateTimer(id) ?? store.duplicateAlarm(id) { made.insert(copy) }
        }
        if !made.isEmpty { selection = made }
    }

    func setEnabled(_ enabled: Bool, _ ids: Set<UUID>) {
        for id in ids where alarm(id) != nil { store.setAlarmEnabled(id, enabled) }
    }

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty, settings.confirmRemoval(count: ids.count) else { return }
        store.remove(ids)
        selection = selection.filter { id in timer(id) != nil || alarm(id) != nil }
    }
}

struct ClockListView: View {
    @ObservedObject var model: ClockListModel
    @ObservedObject var store: ClockStore
    @ObservedObject var settings: ClockySettings

    var body: some View {
        HStack(spacing: 0) {
            ClockListSidebar(model: model, store: store, settings: settings)
                .frame(width: 300)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        let selected = model.selection.filter { model.timer($0) != nil || model.alarm($0) != nil }
        if selected.count == 1, let id = selected.first {
            if let item = model.timer(id) {
                TimerDetail(model: model, store: store, item: item).id(id)
            } else if let item = model.alarm(id) {
                AlarmDetail(model: model, store: store, settings: settings, item: item).id(id)
            }
        } else if selected.count > 1 {
            MultipleDetail(model: model, ids: selected)
        } else {
            Text(L("왼쪽에서 타이머나 알람을 고르세요"))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ClockListSidebar: View {
    @ObservedObject var model: ClockListModel
    @ObservedObject var store: ClockStore
    @ObservedObject var settings: ClockySettings

    var body: some View {
        VStack(spacing: 8) {
            Picker(L("보기"), selection: $model.filter) {
                ForEach(ListFilter.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .id(settings.language)

            HStack(spacing: 6) {
                TextField(L("이름 검색"), text: $model.query)
                    .textFieldStyle(.roundedBorder)
                Menu {
                    Picker(L("알람 정렬"), selection: $model.sort) {
                        ForEach(AlarmSort.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("알람 정렬"))
                .accessibilityLabel(L("알람 정렬"))
                Menu {
                    Button(L("새 타이머")) { model.addTimer() }
                    Button(L("새 알람")) { model.addAlarm() }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("추가"))
                .accessibilityLabel(L("추가"))
            }

            let timers = model.timers
            let alarms = model.alarms
            List(selection: $model.selection) {
                if !timers.isEmpty {
                    Section(L("타이머")) {
                        ForEach(timers) { TimerListRow(store: store, item: $0).tag($0.id) }
                    }
                }
                if !alarms.isEmpty {
                    Section(L("알람")) {
                        ForEach(alarms) { AlarmListRow(store: store, settings: settings, item: $0).tag($0.id) }
                    }
                }
            }
            // 보기나 검색어가 바뀌면 줄을 하나씩 고치지 않고 목록을 새로 만든다.
            .id("\(model.filter.rawValue)|\(model.query)|\(model.sort.rawValue)")
            .contextMenu(forSelectionType: UUID.self) { ids in
                menuItems(for: ids)
            } primaryAction: { ids in
                ids.first.map(model.onReveal)
            }
            .onDeleteCommand { model.remove(model.selection) }
            .overlay {
                if timers.isEmpty && alarms.isEmpty {
                    Text(model.query.isEmpty ? L("등록된 알람이 없습니다") : L("찾는 항목이 없습니다"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func menuItems(for ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            if ids.count == 1, let id = ids.first {
                Button(L("시계 창에서 보기")) { model.onReveal(id) }
                if let timer = model.timer(id) {
                    Button(timer.phase == .running ? L("일시정지") : L("시작")) { store.toggle(id) }
                    if timer.phase != .idle { Button(L("초기화")) { store.reset(id) } }
                }
                Divider()
            }
            if ids.contains(where: { model.alarm($0) != nil }) {
                Button(L("켜기")) { model.setEnabled(true, ids) }
                Button(L("끄기")) { model.setEnabled(false, ids) }
                Divider()
            }
            Button(L("복제")) { model.duplicate(ids) }
            Button(L("삭제")) { model.remove(ids) }
        }
    }
}

private struct TimerListRow: View {
    @ObservedObject var store: ClockStore
    let item: TimerItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(item.phase == .running ? Color.accentColor : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName(of: item)).lineLimit(1)
                Text(phaseText(item.phase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(clockText(item.remaining(at: store.now)))
                .monospacedDigit()
                .foregroundStyle(item.phase == .idle ? .secondary : .primary)
        }
        .padding(.vertical, 2)
    }
}

private struct AlarmListRow: View {
    @ObservedObject var store: ClockStore
    @ObservedObject var settings: ClockySettings
    let item: AlarmItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.snoozeUntil != nil ? "zzz" : "alarm")
                .foregroundStyle(item.upcoming != nil ? Color.accentColor : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName(of: item)).lineLimit(1)
                Text(alarmSummary(item, now: store.now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(settings.timeText(item.timeToday))
                .monospacedDigit()
                .foregroundStyle(item.enabled ? .primary : .secondary)
            Toggle("", isOn: Binding(get: { store.alarms.first { $0.id == item.id }?.enabled ?? false },
                                     set: { store.setAlarmEnabled(item.id, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(L("%@ 켜기", store.displayName(of: item)))
        }
        .padding(.vertical, 2)
    }
}

/// "평일 · 3시간 남음", "다시 울림 · 4분 남음", "매일 · 꺼짐".
func alarmSummary(_ item: AlarmItem, now: Date) -> String {
    if let snooze = item.snoozeUntil, item.upcoming == snooze {
        return L("%@ · %@ 남음", L("다시 울림"), remainingText(until: snooze, from: now))
    }
    let repeats = daysText(item.days)
    guard let next = item.next else { return L("%@ · 꺼짐", repeats) }
    return L("%@ · %@ 남음", repeats, remainingText(until: next, from: now))
}

func phaseText(_ phase: TimerItem.Phase) -> String {
    switch phase {
    case .idle: return L("대기")
    case .running: return L("진행 중")
    case .paused: return L("일시정지됨")
    case .ringing: return L("울림")
    }
}

// MARK: - 오른쪽 편집기

private struct DetailFooter: View {
    let reveal: () -> Void
    let duplicate: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            Button(L("시계 창에서 보기"), action: reveal)
            Spacer()
            Button(L("복제"), action: duplicate)
            Button(L("삭제"), role: .destructive, action: remove)
        }
        .padding(12)
    }
}

private struct TimerDetail: View {
    let model: ClockListModel
    @ObservedObject var store: ClockStore
    let item: TimerItem
    @State private var durationText = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField(store.displayName(of: item), text: Binding(get: { store.timers.first { $0.id == item.id }?.name ?? "" },
                                                                  set: { store.renameTimer(item.id, to: $0) }))
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .padding([.horizontal, .top], 16)
            Form {
                Section {
                    LabeledContent(L("남은 시간")) {
                        Text(clockText(item.remaining(at: store.now)))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(item.phase == .ringing ? Color.red : Color.primary)
                    }
                    LabeledContent(L("상태"), value: phaseText(item.phase))
                    HStack {
                        Spacer()
                        switch item.phase {
                        case .running: Button(L("일시정지")) { store.pause(item.id) }
                        case .paused: Button(L("계속")) { store.start(item.id) }
                        case .idle: Button(L("시작")) { store.start(item.id) }
                        case .ringing: Button(L("끄기")) { store.stopRinging() }
                        }
                        Button(L("초기화")) { store.reset(item.id) }
                            .disabled(item.phase == .idle)
                    }
                }
                Section {
                    LabeledContent(L("시간")) {
                        TextField("", text: $durationText)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 100)
                            .onSubmit(applyDuration)
                    }
                    HStack(spacing: 4) {
                        Spacer()
                        ForEach(ClockStore.presets, id: \.self) { minutes in
                            Button(L("%d분", minutes)) { store.setDuration(item.id, minutes * 60); durationText = clockText(minutes * 60) }
                        }
                    }
                    .controlSize(.small)
                } footer: {
                    Text(L("분, 분:초, 또는 시:분:초로 입력하고 Return을 누릅니다. 시간을 바꾸면 처음부터 다시 셉니다."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            DetailFooter(reveal: { model.onReveal(item.id) }, duplicate: { model.duplicate([item.id]) },
                         remove: { model.remove([item.id]) })
        }
        .onAppear { durationText = clockText(item.duration) }
    }

    private func applyDuration() {
        if let seconds = ClockStore.parse(durationText) {
            store.setDuration(item.id, seconds)
        } else {
            NSSound.beep()
        }
        durationText = clockText(store.timers.first { $0.id == item.id }?.duration ?? item.duration)
    }
}

private struct AlarmDetail: View {
    let model: ClockListModel
    @ObservedObject var store: ClockStore
    @ObservedObject var settings: ClockySettings
    let item: AlarmItem

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(store.displayName(of: item), text: Binding(get: { store.alarms.first { $0.id == item.id }?.name ?? "" },
                                                                      set: { store.renameAlarm(item.id, to: $0) }))
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                Toggle(L("켜기"), isOn: Binding(get: { store.alarms.first { $0.id == item.id }?.enabled ?? false },
                                               set: { store.setAlarmEnabled(item.id, $0) }))
                    .toggleStyle(.switch)
            }
            .padding([.horizontal, .top], 16)
            Form {
                Section {
                    LabeledContent(L("시각")) {
                        DatePicker("", selection: Binding(get: { store.alarms.first { $0.id == item.id }?.timeToday ?? Date() },
                                                          set: { store.setAlarmTime(item.id, $0) }),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.stepperField)
                    }
                    LabeledContent(L("반복")) {
                        Picker("", selection: Binding(get: { presetValue }, set: { if let days = $0 { store.setAlarmDays(item.id, days) } })) {
                            Text(L("매일")).tag(Set<Int>?.some(AlarmItem.everyDay))
                            Text(L("평일")).tag(Set<Int>?.some(AlarmItem.weekdays))
                            Text(L("주말")).tag(Set<Int>?.some(AlarmItem.weekend))
                            Text(L("한 번")).tag(Set<Int>?.some([]))
                            if presetValue == nil { Text(L("요일 지정")).tag(Set<Int>?.none) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    HStack(spacing: 4) {
                        Spacer()
                        ForEach(weekdayOrder, id: \.self) { day in
                            Toggle(L(weekdayNames[day - 1]), isOn: Binding(
                                get: { item.days.contains(day) },
                                set: { isOn in
                                    var days = item.days
                                    if isOn { days.insert(day) } else { days.remove(day) }
                                    store.setAlarmDays(item.id, days)
                                }))
                                .toggleStyle(.button)
                        }
                    }
                    .controlSize(.small)
                }
                Section {
                    LabeledContent(L("다음 울림"), value: nextText)
                    if let snooze = item.snoozeUntil {
                        LabeledContent(L("다시 울림")) {
                            HStack {
                                Text(L("%@ · %@ 남음", settings.timeText(snooze), remainingText(until: snooze, from: store.now)))
                                Button(L("취소")) { store.cancelSnooze(item.id) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            DetailFooter(reveal: { model.onReveal(item.id) }, duplicate: { model.duplicate([item.id]) },
                         remove: { model.remove([item.id]) })
        }
    }

    private var presetValue: Set<Int>? {
        [AlarmItem.everyDay, AlarmItem.weekdays, AlarmItem.weekend, []].first { $0 == item.days }
    }

    private var nextText: String {
        guard let next = item.next else { return L("꺼짐") }
        return L("%@ %@ · %@ 남음", settings.dayText(next), settings.timeText(next), remainingText(until: next, from: store.now))
    }
}

private struct MultipleDetail: View {
    let model: ClockListModel
    let ids: Set<UUID>

    var body: some View {
        VStack(spacing: 12) {
            Text(L("%d개 선택됨", ids.count))
                .font(.title3)
            if ids.contains(where: { model.alarm($0) != nil }) {
                HStack {
                    Button(L("알람 모두 켜기")) { model.setEnabled(true, ids) }
                    Button(L("알람 모두 끄기")) { model.setEnabled(false, ids) }
                }
            }
            HStack {
                Button(L("복제")) { model.duplicate(ids) }
                Button(L("삭제"), role: .destructive) { model.remove(ids) }
            }
        }
    }
}
