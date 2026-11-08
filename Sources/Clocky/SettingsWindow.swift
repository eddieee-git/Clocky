import AppKit
import SwiftUI

/// Clocky 설정 창. 값은 바뀌는 즉시 저장되고 반영된다.
final class SettingsWindowController {
    private let settings: ClockySettings
    private var window: NSWindow?

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
            // 항상 위 시계 창에 가려지지 않게 한다.
            w.level = .floating
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    var windowNumber: Int { window?.windowNumber ?? 0 }
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
        }
        .formStyle(.grouped)
    }

    private var sound: some View {
        Form {
            Section {
                HStack {
                    Picker(L("알람 소리"), selection: $settings.alarmSound) {
                        ForEach(AlarmSound.choices, id: \.self) { Text($0).tag($0) }
                    }
                    Button { AlarmSound.play() } label: { Image(systemName: "play.fill") }
                        .help(L("들어 보기"))
                        .accessibilityLabel(L("들어 보기"))
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

    /// 시계 창에서 쓰는 키. 바꿀 수는 없고 안내만 한다.
    private var shortcuts: some View {
        Form {
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
            Section(L("어디서나")) {
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
