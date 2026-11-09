import AppKit
UserDefaults.standard.removePersistentDomain(forName: "Clocky")
setvbuf(stdout, nil, _IONBF, 0)
UserDefaults.standard.set("ko", forKey: "language"); UserDefaults.standard.set(true, forKey: "hasLaunched")
let shots = CommandLine.arguments[1]
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
var failures = 0
func check(_ ok: Bool, _ msg: String) { print(ok ? "PASS" : "FAIL", msg); if !ok { failures += 1 } }
var t: ClockStore { delegate.window.store }
var panel: TimerPanel { delegate.window.panel }
func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) {
  let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
  NSApp.postEvent(e, atStart: false)
}
func click(_ p: NSPoint) {
  func ev(_ k: NSEvent.EventType) -> NSEvent { NSEvent.mouseEvent(with: k, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)! }
  NSApp.postEvent(ev(.leftMouseDown), atStart: false); NSApp.postEvent(ev(.leftMouseUp), atStart: false)
}
func shot(_ name: String) {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = ["-x", "-o", "-l", "\(panel.windowNumber)", "\(shots)/\(name).png"]; try? p.run(); p.waitUntilExit()
}
var steps: [(Double, () -> Void)] = []
func at(_ s: Double, _ f: @escaping () -> Void) { steps.append((s, f)) }
var first = UUID()

at(0.2) { t.mode = .timer; delegate.window.show() }
at(0.6) { first = t.timers[0].id; panel.makeFirstResponder(nil); print("fr:", String(describing: panel.firstResponder), "key:", panel.isKeyWindow); key(49, " "); DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { print("0.1 later", t.timers[0].phase) } }
at(0.9) { check(t.timers[0].phase == .running, "스페이스로 시작"); key(49, " ") }
at(1.2) { check(t.timers[0].phase == .paused, "스페이스로 일시정지"); key(45, "n", .command) }
at(1.5) {
  check(t.timers.count == 2 && t.selectedTimerID == t.timers[1].id, "⌘N으로 타이머 추가")
  check(t.displayName(of: t.timers[1]) == "타이머 2" && t.timers[1].name.isEmpty, "새 타이머 이름은 비우고 번호로 부름")
  key(126, "") }
at(1.8) { check(t.selectedTimerID == first, "↑로 위 항목 고르기"); key(125, "") }
at(2.1) { check(t.selectedTimerID == t.timers[1].id, "↓로 아래 항목 고르기"); key(51, "\u{7f}", .command) }
at(2.4) { check(t.timers.count == 1, "⌘⌫로 고른 타이머 지우기"); key(19, "2", .command) }
at(2.7) { check(t.mode == .alarm, "⌘2로 알람 칸"); key(45, "n", .command) }
at(3.0) { check(t.alarms.count == 1, "알람 칸에서 ⌘N은 알람 추가"); key(49, " ") }
at(3.3) { check(!t.alarms[0].enabled, "알람 칸에서 스페이스로 끄기"); key(49, " ") }
at(3.6) { check(t.alarms[0].enabled, "다시 스페이스로 켜기") }
at(3.8) { t.forceNext(t.alarms[0].id, Date().addingTimeInterval(-0.5)); t.tick() }
at(4.1) { check(t.isRinging && t.isSounding, "알람 울림"); key(53, "\u{1b}") }
at(4.4) { check(!t.isRinging && !t.isSounding, "Esc로 울림 끄기") }
at(4.6) { t.setAlarmEnabled(t.alarms[0].id, true); t.forceNext(t.alarms[0].id, Date().addingTimeInterval(-0.5)); t.tick() }
at(4.9) { key(1, "s") }
at(5.2) { check(!t.isRinging && t.alarms[0].snoozeUntil != nil, "S로 5분 뒤 다시 울림"); t.setAlarmEnabled(t.alarms[0].id, false) }
at(5.4) { t.setAlarmEnabled(t.alarms[0].id, true); t.forceNext(t.alarms[0].id, Date().addingTimeInterval(-0.5)); t.tick() }
at(6.0) {
  shot("ringing-snooze")
  let f = panel.snoozeFrame
  check(f != .zero, "다시 울림 버튼 자리 알림: \(f)")
  click(NSPoint(x: f.midX, y: panel.frame.height - f.midY))
}
at(6.4) {
  check(!t.isRinging && t.alarms[0].snoozeUntil != nil, "다시 울림 버튼을 누르면 끄지 않고 다시 울림으로")
  check(panel.snoozeFrame == .zero, "울림이 끝나면 버튼 자리 지움")
  shot("snoozed")
}
at(6.6) { t.forceSnooze(t.alarms[0].id, Date().addingTimeInterval(125)); t.tick() }
at(7.2) {
  let title = delegate.statusItem?.button?.title ?? ""
  check(title.count >= 5 && title.count <= 6, "도는 타이머가 없으면 1시간 안 알람까지 남은 시간: '\(title)'")
  check(delegate.statusItem?.button?.image?.size.width != 18, "알람 시계 아이콘으로 바뀜")
  t.start(t.timers[0].id)
}
at(7.6) {
  let title = delegate.statusItem?.button?.title ?? ""
  check(title.hasPrefix(" 4:") || title.hasPrefix(" 5:"), "타이머가 돌면 타이머가 먼저: '\(title)'")
  check(delegate.statusItem?.button?.image?.size.width == 18, "넘김시계 아이콘으로 돌아옴")
  t.reset(t.timers[0].id)
  t.forceSnooze(t.alarms[0].id, Date().addingTimeInterval(-7200)); t.setAlarmEnabled(t.alarms[0].id, false); t.tick()
  t.pause(t.timers[0].id); t.reset(t.timers[0].id)
  t.mode = .timer
}
at(8.2) { click(NSPoint(x: 170, y: panel.frame.height - 16)) }
at(8.5) { check(panel.firstResponder is NSTextView, "이름 칸 편집 시작"); key(49, " ") }
at(8.8) { check(t.timers[0].phase == .idle, "편집 중 스페이스는 타이머를 건드리지 않음"); key(53, "\u{1b}") }
at(9.1) { check(!(panel.firstResponder is NSTextView), "Esc로 편집 끝내기: \(String(describing: panel.firstResponder))") }
at(9.3) { t.mode = .alarm; check(t.isDisplayed, "보이는 동안 표시 중"); panel.close() }
at(9.6) {
  check(!t.isDisplayed, "닫으면 표시 아님")
  t.setAlarmEnabled(t.alarms[0].id, false)
  check(t.nextWake(after: Date()) == nil, "할 일이 없으면 깨어나지 않음")
}
at(9.8) {
  print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
  UserDefaults.standard.removePersistentDomain(forName: "Clocky")
  exit(failures == 0 ? 0 : 1)
}
for (s, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
app.run()
