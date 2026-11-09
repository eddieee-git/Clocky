import AppKit
UserDefaults.standard.removePersistentDomain(forName: "Clocky")
setvbuf(stdout, nil, _IONBF, 0)
let d = UserDefaults.standard
d.set("ko", forKey: "language"); d.set(true, forKey: "hasLaunched")
// 앱이 꺼진 동안 10초 전에 끝난 타이머, 2시간 전에 끝난 타이머, 일시정지한 타이머
let saved = [
  ClockStore.SavedTimer(id: UUID(), name: "끝남", duration: 60, phase: "running", endDate: Date().addingTimeInterval(-10), pausedRemaining: nil),
  ClockStore.SavedTimer(id: UUID(), name: "오래됨", duration: 60, phase: "running", endDate: Date().addingTimeInterval(-7200), pausedRemaining: nil),
  ClockStore.SavedTimer(id: UUID(), name: "멈춤", duration: 60, phase: "paused", endDate: nil, pausedRemaining: 42),
]
d.set(try! JSONEncoder().encode(saved), forKey: "timers")
d.set([200.0, 300.0], forKey: "windowOrigin")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
var failures = 0
func check(_ ok: Bool, _ msg: String) { print(ok ? "PASS" : "FAIL", msg); if !ok { failures += 1 } }
var t: ClockStore { delegate.window.store }
var steps: [(Double, () -> Void)] = []
func at(_ s: Double, _ f: @escaping () -> Void) { steps.append((s, f)) }
var runID = UUID()

at(0.1) {
  check(t.timers[0].phase == .running || t.timers[0].phase == .ringing, "꺼진 동안 끝난 타이머(1시간 안)는 진행 상태로 복원(곧바로 울림)")
  check(t.timers[1].phase == .idle, "1시간 넘게 지난 타이머는 대기로")
  check(t.timers[2].phase == .paused && t.timers[2].pausedRemaining == 42, "일시정지 타이머와 남은 시간 복원")
}
at(0.6) {
  check(t.timers[0].phase == .ringing && t.isSounding, "켜자마자 울리고 소리가 남")
  check(delegate.window.panel.frame.origin == NSPoint(x: 200, y: 300), "저장한 자리에 창이 뜸: \(delegate.window.panel.frame.origin)")
}
at(2.5) { check(t.isSounding, "2초가 지나도 소리가 계속 반복"); t.stopRinging(); check(!t.isSounding, "끄면 소리도 멈춤") }
// 실행 중 타이머 저장 → 다시 읽기
at(2.7) {
  runID = t.timers[1].id; t.setDuration(runID, 120); t.start(runID); t.save()
  let again = ClockStore()
  let r = again.timers[1]
  check(r.phase == .running && abs(r.remaining(at: Date()) - 120) <= 1, "도는 타이머를 다시 읽으면 이어서 돔 (\(r.remaining(at: Date())))")
  check(again.timers[2].phase == .paused, "일시정지도 다시 읽힘")
}
// 창 자리 기억
at(3.0) {
  delegate.window.panel.setFrameOrigin(NSPoint(x: 500, y: 200)); delegate.window.panel.close()
}
at(3.3) {
  delegate.window.show()
  check(delegate.window.panel.frame.origin == NSPoint(x: 500, y: 200), "닫았다 열어도 옮긴 자리: \(delegate.window.panel.frame.origin)")
  let saved = d.array(forKey: "windowOrigin") as? [Double]
  check(saved == [500, 200], "자리 저장: \(String(describing: saved))")
}
// 되돌리기
at(3.6) {
  let count = t.timers.count
  t.removeTimer(runID)
  check(t.timers.count == count - 1, "도는 타이머 삭제")
  delegate.window.panel.makeKey(); delegate.window.panel.makeFirstResponder(nil)
  let ok = NSApp.sendAction(Selector(("undo:")), to: delegate.window.panel, from: nil)
  check(ok && t.timers.count == count && t.timers[1].id == runID && t.timers[1].phase == .running, "⌘Z(undo:)로 같은 자리에 진행 중 그대로 되살아남")
  check(t.selectedTimerID == runID, "되살린 타이머가 선택됨")
  NSApp.sendAction(Selector(("redo:")), to: delegate.window.panel, from: nil)
  check(t.timers.count == count - 1, "다시 실행하면 다시 지워짐")
  NSApp.sendAction(Selector(("undo:")), to: delegate.window.panel, from: nil)
  let a = t.addAlarm(minutes: 8*60); t.renameAlarm(a, to: "출근")
  t.removeAlarm(a); check(t.alarms.isEmpty, "알람 삭제")
  NSApp.sendAction(Selector(("undo:")), to: delegate.window.panel, from: nil)
  check(t.alarms.count == 1 && t.alarms[0].name == "출근" && t.alarms[0].next != nil && t.mode == .alarm, "알람 되돌리기, 다음 시각도 다시 잡힘")
  // ⌘Z 키 입력
  t.removeAlarm(a)
  let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: delegate.window.panel.windowNumber, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
  NSApp.postEvent(key, atStart: false)
}
at(4.0) { check(t.alarms.count == 1, "⌘Z 키로도 되살아남") }
// 시간대·시계 변경
at(4.2) {
  let a = t.alarms[0].id
  t.alarms[0].next = Date().addingTimeInterval(5 * 86400)  // 틀어진 값
  NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
  let n = t.alarms.first { $0.id == a }!.next!
  check(n.timeIntervalSinceNow > 0 && n.timeIntervalSinceNow <= 86400, "시계가 바뀌면 다음 시각을 다시 셈: \(n)")
  // 시간대 바꾸기: 다음 08:00이 새 시간대 기준으로 잡히는지
  NSTimeZone.default = TimeZone(identifier: "America/New_York")!
  NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
  let m = t.alarms[0].next!
  var cal = Calendar.current; cal.timeZone = TimeZone(identifier: "America/New_York")!
  let c = cal.dateComponents([.hour, .minute], from: m)
  check(c.hour == 8 && c.minute == 0, "시간대가 바뀌면 그 시간대의 8:00로 잡힘: \(m)")
  NSTimeZone.default = TimeZone(identifier: "Asia/Seoul")!
  // 깨어날 때 바로 확인
  t.alarms[0].next = Date().addingTimeInterval(-1)
  NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
  check(!t.ringingAlarmIDs.isEmpty, "깨어나면 바로 확인해 지난 알람을 울림")
  t.stopRinging()
}
at(4.5) {
  print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
  UserDefaults.standard.removePersistentDomain(forName: "Clocky")
  exit(failures == 0 ? 0 : 1)
}
for (s, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
app.run()
