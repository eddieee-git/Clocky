import AppKit
UserDefaults.standard.removePersistentDomain(forName: "Clocky")
setvbuf(stdout, nil, _IONBF, 0)
let shots = CommandLine.arguments[1]
let lang = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "ko"
UserDefaults.standard.set(lang, forKey: "language"); UserDefaults.standard.set(true, forKey: "hasLaunched")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
var failures = 0
func check(_ ok: Bool, _ msg: String) { print(ok ? "PASS" : "FAIL", msg); if !ok { failures += 1 } }
var t: ClockStore { delegate.window.store }
var s: ClockySettings { delegate.settings }
func shot(_ n: Int, _ name: String) {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = ["-x", "-o", "-l", "\(n)", "\(shots)/\(name).png"]; try? p.run(); p.waitUntilExit()
}
func key(_ window: Int, _ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags) {
  let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
  NSApp.postEvent(e, atStart: false)
}
// 단계 사이를 넉넉히 두어, 기계가 바빠 잠깐 밀려도 결과가 흔들리지 않게 한다.
var steps: [(Double, () -> Void)] = []
func at(_ x: Double, _ f: @escaping () -> Void) { steps.append((x, f)) }
let ko = lang == "ko"
var ids: [UUID] = []

at(0.3) {
  let a = t.timers[0].id; t.renameTimer(a, to: ko ? "라면" : "Noodles"); t.setDuration(a, 180); t.start(a)
  let b = t.addTimer(); t.renameTimer(b, to: ko ? "빨래" : "Laundry"); t.setDuration(b, 40*60)
  let x = t.addAlarm(minutes: 7*60+30); t.renameAlarm(x, to: ko ? "기상" : "Wake up")
  let y = t.addAlarm(minutes: 14*60); t.renameAlarm(y, to: ko ? "회의" : "Meeting"); t.setAlarmDays(y, AlarmItem.weekdays)
  let z = t.addAlarm(minutes: 21*60); t.renameAlarm(z, to: ko ? "약 먹기" : "Medicine"); t.setAlarmEnabled(z, false)
  ids = [a, b, x, y, z]
  delegate.window.show()
}
// ⌘, 와 ⌘L 은 시계 창에서도
at(1.2) { key(delegate.window.panel.windowNumber, 43, ",", .command) }
at(2.1) { check(delegate.settingsWindow.isVisible, "시계 창에서 ⌘,로 설정 창") ; shot(delegate.settingsWindow.windowNumber, "settings-general-\(lang)") }
at(2.4) {
  s.warningSeconds = 30; s.snoozeMinutes = 10; s.soundLimitSeconds = 180; s.menuBarShowsAlarm = false
  check(t.warningSeconds == 30 && t.snoozeMinutes == 10 && t.soundLimit == 180 && !t.tracksMenuBarAlarm, "설정 값이 바로 시계에 반영")
  s.menuBarShowsTimer = false
}
at(3.0) {
  check(delegate.statusItem?.button?.title == "", "메뉴바 타이머 표시 끄면 제목 없음: '\(delegate.statusItem?.button?.title ?? "")'")
  s.menuBarShowsTimer = true; s.menuBarShowsAlarm = true; s.warningSeconds = 10; s.snoozeMinutes = 5; s.soundLimitSeconds = 60
}
at(3.6) { check(delegate.statusItem?.button?.title.hasPrefix(" 2:") == true, "다시 켜면 타이머 표시"); key(delegate.window.panel.windowNumber, 37, "l", .command) }
at(4.8) {
  check(delegate.listWindow.isVisible && t.isListDisplayed, "⌘L로 전체 목록 창")
  delegate.listWindow.model.selection = [ids[3]]
}
at(6.0) { shot(delegate.listWindow.windowNumber, "list-alarm-\(lang)"); delegate.listWindow.model.selection = [ids[0]] }
at(7.2) { shot(delegate.listWindow.windowNumber, "list-timer-\(lang)"); delegate.listWindow.model.selection = [ids[2], ids[3], ids[1]] }
at(8.1) {
  shot(delegate.listWindow.windowNumber, "list-multi-\(lang)")
  let m = delegate.listWindow.model
  m.setEnabled(false, m.selection)
  check(t.alarms.filter { [ids[2], ids[3]].contains($0.id) }.allSatisfy { !$0.enabled }, "여러 알람 한꺼번에 끄기")
  m.remove(m.selection)
  check(t.timers.count == 1 && t.alarms.count == 1, "여러 개 한꺼번에 지우기")
}
at(8.7) {
  key(delegate.listWindow.windowNumber, 6, "z", .command)
}
at(9.3) {
  // 목록 창은 일반 창이라 편집 메뉴의 ⌘Z가 창으로 간다. 합성 이벤트로는 메뉴를 거치지 않을 수 있어 바로도 확인한다.
  if t.alarms.count == 1 { _ = NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
  check(t.timers.count == 2 && t.alarms.count == 3, "⌘Z 한 번에 모두 되살아남 (\(t.timers.count), \(t.alarms.count))")
  delegate.listWindow.model.onReveal(ids[3])
}
at(9.9) {
  check(t.mode == .alarm && t.selectedAlarmID == ids[3] && delegate.window.isVisible, "시계 창에서 보기")
  check(s.failedHotKeys.isEmpty, "전역 단축키 등록: 실패 \(s.failedHotKeys)")
  s.timerPresets = [2, 15, 45]
  check(t.presets == [2, 15, 45], "타이머 버튼 설정이 바로 반영")
  s.timerPresets = ClockySettings.defaultPresets
  delegate.window.panel.makeKey()
  delegate.perform(.toggleClock)
}
at(10.35) {
  check(!delegate.window.isVisible, "전역 단축키 동작: 시계 창 숨기기")
  delegate.perform(.toggleClock)
  delegate.listWindow.show()
}
// 다른 창(목록 창)에 키보드가 있는 동안 울린다.
at(10.9) { t.forceNext(ids[2], Date().addingTimeInterval(-0.5)); t.tick() }
at(11.4) {
  check(delegate.window.isVisible && t.isRinging, "다시 보이기, 알람 울림")
  check(delegate.listWindow.window?.isKeyWindow == true && !delegate.window.panel.isKeyWindow,
        "울려도 키보드는 쓰던 창에 남음 (key: \(NSApp.keyWindow?.title ?? "nil"))")
  shot(delegate.listWindow.windowNumber, "list-ringing-\(lang)")
  delegate.perform(.stopRinging)
  check(!t.isRinging, "전역 단축키 동작: 울림 끄기")
}
at(11.85) {
  print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
  UserDefaults.standard.removePersistentDomain(forName: "Clocky")
  exit(failures == 0 ? 0 : 1)
}
for (x, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + x, execute: f) }
app.run()
