import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Clocky 설정 창. 값은 바뀌는 즉시 저장되고 반영된다.
final class SettingsWindowController {
    private let settings: ClockySettings
    private var window: NSWindow?
    private var levelObservers: [NSObjectProtocol] = []

    init(settings: ClockySettings) {
        self.settings = settings
        NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.window?.title = L("Clocky 설정")
        }
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = L("Clocky 설정")
            w.isReleasedWhenClosed = false
            levelObservers = floatWhileActive(w)
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    var windowNumber: Int { window?.windowNumber ?? 0 }
}

/// 앱을 쓰는 동안에는 항상 위 시계 창에 가려지지 않게 띄우고, 다른 앱으로 가면 보통 창처럼 그 앱 뒤로 보낸다.
func floatWhileActive(_ window: NSWindow) -> [NSObjectProtocol] {
    window.level = NSApp.isActive ? .floating : .normal
    let center = NotificationCenter.default
    return [
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak window] _ in
            window?.level = .floating
        },
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak window] _ in
            window?.level = .normal
        },
    ]
}

struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general = "일반"
        case clock = "타이머·알람"
        case sound = "소리"
        case shortcuts = "단축키"
    }

    @ObservedObject var settings: ClockySettings
    @State var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("설정"), selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            // 분할 버튼은 글자가 바뀌어도 다시 그리지 않아서, 언어를 바꾸면 새로 만든다.
            .id(settings.language)
            .padding(.top, 12)

            switch tab {
            case .general: general
            case .clock: clock
            case .sound: sound
            case .shortcuts: shortcuts
            }
        }
        .frame(width: 480, height: 400, alignment: .top)
    }

    private var general: some View {
        Form {
            Section {
                Picker(L("언어"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(L("로그인 시 자동 실행"), isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                    .disabled(!settings.canLaunchAtLogin)
                Toggle(L("삭제하기 전에 확인"), isOn: $settings.confirmDelete)
            }
            Section(L("메뉴바")) {
                Toggle(L("타이머 남은 시간 표시"), isOn: $settings.menuBarShowsTimer)
                Toggle(L("1시간 안에 울릴 알람까지 남은 시간 표시"), isOn: $settings.menuBarShowsAlarm)
            }
        }
        .formStyle(.grouped)
    }

    private var clock: some View {
        Form {
            Section {
                Picker(L("미리 깜빡이기"), selection: $settings.warningSeconds) {
                    ForEach(ClockySettings.warningChoices, id: \.self) {
                        Text($0 == 0 ? L("깜빡이지 않음") : L("%d초 전부터", $0)).tag($0)
                    }
                }
                Picker(L("다시 울림 간격"), selection: $settings.snoozeMinutes) {
                    ForEach(ClockySettings.snoozeChoices, id: \.self) { Text(L("%d분", $0)).tag($0) }
                }
                Picker(L("소리를 되풀이하는 시간"), selection: $settings.soundLimitSeconds) {
                    ForEach(ClockySettings.soundLimitChoices, id: \.self) {
                        Text($0 < 60 ? L("%d초", $0) : L("%d분", $0 / 60)).tag($0)
                    }
                }
            } footer: {
                Text(L("소리가 멈춘 뒤에도 끌 때까지 창은 깜빡입니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                PresetEditor(settings: settings)
            } footer: {
                Text(L("시계 창과 목록 창의 시간 버튼입니다. 분 단위로 쉼표를 넣어 적고 Return을 누릅니다. 6개까지 씁니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var sound: some View {
        Form {
            Section {
                HStack {
                    SoundPicker(title: L("알람 소리"), selection: $settings.alarmSound, choices: soundChoices)
                    Button { AlarmSound.play() } label: { Image(systemName: "play.fill") }
                        .help(L("들어 보기"))
                        .accessibilityLabel(L("들어 보기"))
                }
                HStack {
                    Spacer()
                    if settings.alarmSound.hasPrefix(AlarmSound.filePrefix) {
                        Button(L("이 파일 지우기")) { removeCustomSound() }
                    }
                    Button(L("내 소리 파일 추가…")) { importSound() }
                }
                LabeledContent(L("소리 크기")) {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $settings.soundVolume, in: 0...1) { editing in
                            if !editing { AlarmSound.play() }
                        }
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(L("Mac의 소리를 꺼 두면 알람도 들리지 않습니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.alarmSound) { _ in AlarmSound.play() }
    }

    /// 파일을 더하거나 지우면 목록을 다시 읽는다.
    @State private var soundChoices = AlarmSound.choices

    private func importSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = L("알람으로 쓸 소리 파일을 고르세요. Clocky 폴더로 복사해 둡니다.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let id = AlarmSound.importFile(url) {
            soundChoices = AlarmSound.choices
            settings.alarmSound = id
        } else {
            let alert = NSAlert()
            alert.messageText = L("이 파일은 소리로 열 수 없습니다.")
            alert.runModal()
        }
    }

    private func removeCustomSound() {
        let id = settings.alarmSound
        settings.alarmSound = AlarmSound.defaultName
        AlarmSound.removeFile(id)
        soundChoices = AlarmSound.choices
    }

    /// 위는 바꿀 수 있는 전역 단축키, 아래는 창 안에서 쓰는 키 안내.
    private var shortcuts: some View {
        Form {
            Section {
                HotKeyEditor(settings: settings)
            } header: {
                Text(L("어디서나 (다른 앱을 쓰는 중에도)"))
            }
            Section(L("시계 창")) {
                shortcut("스페이스", "고른 타이머 시작·일시정지, 고른 알람 켜기·끄기")
                shortcut("↑ ↓", "목록에서 고르기")
                shortcut("⌘N", "타이머 또는 알람 추가")
                shortcut("⌘⌫", "고른 항목 지우기")
                shortcut("⌘Z  ⇧⌘Z", "지운 항목 되살리기, 다시 지우기")
                shortcut("⌘1  ⌘2", "타이머, 알람")
                shortcut("Esc", "울림 끄기, 이름 편집 끝내기")
                shortcut("S", "울리는 동안 다시 울림")
            }
            Section(L("Clocky 창")) {
                shortcut("⌘L", "전체 목록")
                shortcut("⌘,", "설정")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        LabeledContent(L(action)) {
            Text(L(keys)).monospaced().foregroundStyle(.secondary)
        }
    }
}

/// 시스템 소리와 내 소리 파일을 한 메뉴에서 고른다.
struct SoundPicker<Tag: Hashable>: View {
    let title: String
    @Binding var selection: Tag
    let choices: [String]
    /// 목록 창의 알람처럼 "기본 소리"를 맨 위에 둘 때.
    var defaultOption: (label: String, tag: Tag)?
    var tag: (String) -> Tag = { $0 as! Tag }

    var body: some View {
        Picker(title, selection: $selection) {
            if let defaultOption {
                Text(defaultOption.label).tag(defaultOption.tag)
                Divider()
            }
            ForEach(choices.filter { !$0.hasPrefix(AlarmSound.filePrefix) }, id: \.self) { Text(AlarmSound.title($0)).tag(tag($0)) }
            let files = choices.filter { $0.hasPrefix(AlarmSound.filePrefix) }
            if !files.isEmpty {
                Divider()
                ForEach(files, id: \.self) { Text(AlarmSound.title($0)).tag(tag($0)) }
            }
        }
    }
}

/// 타이머 시간 버튼을 "1, 3, 5, 10, 25"처럼 적어 바꾼다.
private struct PresetEditor: View {
    @ObservedObject var settings: ClockySettings
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        LabeledContent(L("타이머 버튼(분)")) {
            HStack {
                TextField("", text: $text)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 140)
                    .onSubmit(apply)
                    .foregroundStyle(invalid ? Color.red : Color.primary)
                Button(L("기본값")) {
                    settings.timerPresets = ClockySettings.defaultPresets
                    load()
                }
                .disabled(settings.timerPresets == ClockySettings.defaultPresets)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        text = settings.timerPresets.map(String.init).joined(separator: ", ")
        invalid = false
    }

    private func apply() {
        guard let presets = ClockySettings.parsePresets(text) else {
            invalid = true
            NSSound.beep()
            return
        }
        settings.timerPresets = presets
        load()
    }
}

/// 전역 단축키를 바꾼다. 버튼을 누른 뒤 새 조합을 누르면 바로 등록된다.
private struct HotKeyEditor: View {
    @ObservedObject var settings: ClockySettings
    @State private var recording: HotKeyAction?
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        ForEach(HotKeyAction.allCases, id: \.self) { action in
            LabeledContent(action.title) {
                HStack(spacing: 8) {
                    if settings.failedHotKeys.contains(action) {
                        Text(L("등록하지 못함")).font(.caption).foregroundStyle(.red)
                    }
                    Button(recording == action ? L("키를 누르세요") : settings.hotKeys[action.rawValue]?.displayText ?? L("없음")) {
                        recording == action ? stop() : start(action)
                    }
                    .frame(minWidth: 110)
                    Button {
                        settings.hotKeys[action.rawValue] = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.hotKeys[action.rawValue] == nil)
                    .help(L("단축키 지우기"))
                    .accessibilityLabel(L("단축키 지우기"))
                }
            }
        }
        HStack {
            Text(message ?? L("Esc를 누르면 입력을 취소합니다."))
                .font(.caption)
                .foregroundStyle(message == nil ? Color.secondary : Color.red)
            Spacer()
            Button(L("기본값")) {
                stop()
                settings.hotKeys = KeyCombo.defaults
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start(_ action: HotKeyAction) {
        stop()
        recording = action
        settings.isRecordingHotKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: action)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        message = nil
        if settings.isRecordingHotKey { settings.isRecordingHotKey = false }
    }

    private func handle(_ event: NSEvent, for action: HotKeyAction) {
        if event.keyCode == 53 { // Esc
            stop()
            return
        }
        guard let combo = KeyCombo(event: event) else {
            message = L("⌘, ⌃, ⌥ 중 하나와 함께 누르세요.")
            return
        }
        if let other = HotKeyAction.allCases.first(where: { $0 != action && settings.hotKeys[$0.rawValue] == combo }) {
            message = L("%@에서 쓰는 단축키입니다.", other.title)
            return
        }
        settings.hotKeys[action.rawValue] = combo
        stop()
    }
}
