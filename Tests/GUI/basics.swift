import AppKit
UserDefaults.standard.removePersistentDomain(forName: "Clocky")
setvbuf(stdout, nil, _IONBF, 0)
let shots = CommandLine.arguments[1]
let lang = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "ko"
// 옛 구조의 값을 넣어 두고 옮겨지는지 본다.
let d = UserDefaults.standard
d.set(lang, forKey: "language")
d.set("라면", forKey: "timerName"); d.set(180, forKey: "timerDuration")
d.set("기상", forKey: "alarmName"); d.set(7*60+30, forKey: "alarmMinutes"); d.set(true, forKey: "alarmEnabled"); d.set(false, forKey: "alarmRepeats")
d.set(true, forKey: "hasLaunched")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
var failures = 0
func check(_ ok: Bool, _ msg: String) { print(ok ? "PASS" : "FAIL", msg); if !ok { failures += 1 } }
var t: ClockStore { delegate.window.store }
func post(_ p: NSPoint) {
  let w = delegate.window.panel
  func ev(_ k: NSEvent.EventType) -> NSEvent { NSEvent.mouseEvent(with: k, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)! }
  NSApp.postEvent(ev(.leftMouseDown), atStart: false); NSApp.postEvent(ev(.leftMouseUp), atStart: false)
}
func shot(_ name: String) {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = ["-x", "-o", "-l", "\(delegate.window.panel.windowNumber)", "\(shots)/\(name).png"]
  try? p.run(); p.waitUntilExit()
}
var steps: [(Double, () -> Void)] = []
func at(_ s: Double, _ f: @escaping () -> Void) { steps.append((s, f)) }
let h: CGFloat = 420
var firstID = UUID(), secondID = UUID(), rem1 = 0

at(0.3) {
  check(t.timers.count == 1 && t.timers[0].name == "라면" && t.timers[0].duration == 180, "옛 타이머 값이 첫 타이머로 옮겨짐")
  check(t.alarms.count == 1 && t.alarms[0].name == "기상" && t.alarms[0].minutes == 450 && t.alarms[0].enabled && t.alarms[0].days.isEmpty, "옛 알람 값이 첫 알람으로 옮겨짐")
  check(d.object(forKey: "timerName") == nil && d.data(forKey: "timers") != nil, "옛 키 지우고 새 키에 저장")
  t.mode = .timer
  delegate.window.show()
  check(delegate.window.panel.frame.size == NSSize(width: 340, height: 420), "창 크기 340x420")
}
// 1. 모드 전환 중 타이머 유지 (실제 클릭)
at(1.0) { firstID = t.timers[0].id; t.start(firstID) }
at(2.2) { rem1 = t.timers[0].remaining(at: Date()); post(NSPoint(x: 215, y: h-44)) }  // 알람 탭
at(3.0) { check(t.mode == .alarm, "알람 탭 클릭으로 모드 전환"); check(t.timers[0].phase == .running, "알람 탭에서도 타이머 진행 중"); shot("alarm-mode") }
at(3.2) { post(NSPoint(x: 125, y: h-44)) } // 타이머 탭
at(4.0) {
  check(t.mode == .timer, "타이머 탭 클릭으로 돌아옴")
  let r = t.timers[0].remaining(at: Date())
  check(t.timers[0].phase == .running && r < rem1 && r > 170, "돌아와도 리셋 없이 계속 줄어듦 (\(rem1) -> \(r))")
  // 언어를 바꿔도 유지
  delegate.settings.language = .english
}
at(4.5) { check(t.timers[0].phase == .running, "언어를 바꿔도 타이머 유지"); delegate.settings.language = AppLanguage(rawValue: lang)! }
// 2. 두 타이머 동시 진행
at(5.0) {
  t.reset(firstID); t.setDuration(firstID, 3)
  secondID = t.addTimer(); t.renameTimer(secondID, to: "차"); t.setDuration(secondID, 6)
  check(t.timers.count == 2 && t.selectedTimerID == secondID, "타이머 추가하면 둘이 되고 새 타이머가 선택됨")
  t.start(firstID); t.start(secondID)
}
at(6.0) { check(t.timers.allSatisfy { $0.phase == .running }, "두 타이머가 함께 진행"); check(t.isWarning, "10초 안이라 깜빡임 경고"); shot("two-timers") }
at(8.4) {
  check(t.timers[0].phase == .ringing && t.timers[1].phase == .running, "3초 타이머만 울리고 6초 타이머는 진행")
  check(t.selectedTimerID == firstID && t.mode == .timer, "울린 타이머가 큰 판에 보임")
  check(delegate.statusItem?.button?.title == " 0:00", "메뉴바 제목은 울리는 타이머: '\(delegate.statusItem?.button?.title ?? "")'")
  shot("ringing")
  post(NSPoint(x: 170, y: 100)) // 창 아무 곳이나 눌러 끄기
}
at(9.0) { check(t.timers[0].phase == .idle && t.timers[1].phase == .running, "누르면 울리는 타이머만 꺼지고 다른 타이머는 계속") }
at(11.6) { check(t.timers[1].phase == .ringing && t.selectedTimerID == secondID, "두 번째 타이머도 제때 울림"); t.stopRinging() }
// 3. 알람 둘 등록, 각각 울림
at(12.0) {
  t.mode = .alarm
  let a = t.addAlarm(minutes: 23*60+59); t.renameAlarm(a, to: "회의")
  check(t.alarms.count == 2 && t.selectedAlarmID == a, "알람 추가")
  // 분 단위라 시험에서는 다음 울릴 때를 앞당긴다. 확인은 울릴 때보다 0.5초 넘게 늦게 해서, 기계가 바빠 잠깐 밀려도 흔들리지 않게 한다.
  t.alarms[0].enabled = true; t.alarms[0].days = []; t.alarms[0].next = Date().addingTimeInterval(2)
  t.alarms[1].days = AlarmItem.everyDay; t.alarms[1].next = Date().addingTimeInterval(4)
  t.isDisplayed = true
}
at(12.6) { shot("alarms-warning") }
at(14.9) {
  check(t.ringingAlarmIDs == [t.alarms[0].id], "첫 알람이 울림")
  check(!t.alarms[0].enabled && t.alarms[0].next == nil, "한 번 알람은 울린 뒤 꺼짐")
  check(t.alarms[1].next != nil && t.ringingAlarmIDs.count == 1, "둘째 알람은 아직 대기")
  t.stopRinging()
}
at(16.9) {
  check(t.ringingAlarmIDs == [t.alarms[1].id] && t.selectedAlarmID == t.alarms[1].id, "둘째 알람도 울리고 선택됨")
  let n = t.alarms[1].next!
  // 23:59 알람이니 다음 23:59(지금보다 뒤)로 다시 잡혀야 한다. 시험하는 시각에 따라 오늘일 수도 내일일 수도 있다.
  let c = Calendar.current.dateComponents([.hour, .minute], from: n)
  check(n > Date() && c.hour == 23 && c.minute == 59, "매일 알람은 다음 23:59로 다시 잡힘 (\(n))")
  t.stopRinging()
}
// 4. 남은 시간 표시
at(17.3) {
  let now = Date()
  check(remainingText(until: now.addingTimeInterval(9.2), from: now) == L("%d초", 10), "10초 미만: \(remainingText(until: now.addingTimeInterval(9.2), from: now))")
  check(remainingText(until: now.addingTimeInterval(3*3600+61), from: now) == L("%d시간 %d분", 3, 2), "3시간 1분 1초 -> \(remainingText(until: now.addingTimeInterval(3*3600+61), from: now))")
  // 남은 시간이 다른 알람 셋을 보여 주는 화면
  t.setAlarmEnabled(t.alarms[0].id, true)
  t.alarms[0].next = now.addingTimeInterval(45*60)
  let c = t.addAlarm(minutes: 12*60); t.renameAlarm(c, to: "점심"); t.setAlarmDays(c, [])
  t.alarms[2].next = now.addingTimeInterval(26*3600)
  t.selectedAlarmID = t.alarms[1].id
  t.removeTimer(secondID); check(t.timers.count == 1, "타이머 삭제")
  t.removeTimer(firstID); check(t.timers.count == 1, "마지막 타이머는 지우지 않음")
}
at(18.1) { shot("alarm-list") }
at(18.3) {
  // 메뉴 상태 줄
  let menu = delegate.statusItem!.menu!
  t.start(firstID)
  delegate.menuNeedsUpdate(menu)
  let titles = menu.items.map(\.title)
  print("menu:", titles.prefix(6))
  check(titles.contains { $0.contains("기상") } && titles.contains { $0.contains("회의") } && titles.contains { $0.contains("라면") }, "메뉴에 타이머와 알람마다 상태 줄")
  t.reset(firstID)
  t.removeAlarm(t.alarms[0].id); check(t.alarms.count == 2, "알람 삭제")
}
at(18.8) {
  // 다시 읽어도 그대로인지
  t.save()
  let again = ClockStore()
  check(again.timers.map(\.name) == t.timers.map(\.name) && again.alarms.map(\.name) == t.alarms.map(\.name), "저장한 목록 다시 읽기: \(again.alarms.map(\.name))")
  print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
  exit(failures == 0 ? 0 : 1)
}
for (s, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
app.run()
