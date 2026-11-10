import AppKit
// README 이미지를 찍는다(한국어·영어): 시계 창의 타이머·알람, 전체 목록, 설정의 캘린더 탭.
UserDefaults.standard.removePersistentDomain(forName: "Clocky")
let shots = CommandLine.arguments[1]
let lang = CommandLine.arguments[2]
UserDefaults.standard.set(lang, forKey: "language")
UserDefaults.standard.set(true, forKey: "hasLaunched")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
var t: ClockStore { delegate.window.store }
func shot(_ number: Int, _ name: String) {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = ["-x", "-o", "-l", "\(number)", "\(shots)/\(name).png"]
  try? p.run(); p.waitUntilExit()
}
let ko = lang == "ko"
var meeting = UUID()
var feedID = UUID()
var steps: [(Double, () -> Void)] = []
func at(_ x: Double, _ f: @escaping () -> Void) { steps.append((x, f)) }

at(0.3) {
  let a = t.timers[0].id
  t.renameTimer(a, to: ko ? "라면" : "Noodles"); t.setDuration(a, 180)
  let b = t.addTimer(); t.renameTimer(b, to: ko ? "빨래" : "Laundry"); t.setDuration(b, 40*60)
  let c = t.addTimer(); t.renameTimer(c, to: ko ? "스트레칭" : "Stretch"); t.setDuration(c, 10*60)
  t.start(b)
  t.timers[1].endDate = Date().addingTimeInterval(23*60+12)
  t.pause(b)
  t.start(a); t.timers[0].endDate = Date().addingTimeInterval(2*60+47)
  t.selectedTimerID = a
  let x = t.addAlarm(minutes: 7*60+30); t.renameAlarm(x, to: ko ? "기상" : "Wake up")
  meeting = t.addAlarm(minutes: 14*60); t.renameAlarm(meeting, to: ko ? "회의" : "Meeting"); t.setAlarmDays(meeting, AlarmItem.weekdays)
  // 알람 칸 아래의 캘린더 일정까지 보이도록 알람은 둘만 둔다.
  t.selectedAlarmID = x
  // 캘린더에서 받아 온 것처럼 일정 둘을 넣는다.
  let feed = MacCalendarSource.feedID
  func event(_ title: String, _ minutes: Double) -> CalendarEvent {
    let start = Date().addingTimeInterval(minutes * 60)
    return CalendarEvent(id: "\(feed)|\(title)|\(Int(start.timeIntervalSince1970))", title: title, start: start,
                         end: start.addingTimeInterval(1800), calendarName: ko ? "업무" : "Work", feedID: feed)
  }
  t.setCalendarEvents([event(ko ? "디자인 검토" : "Design review", 95), event(ko ? "1:1 미팅" : "1:1", 245)])
  t.mode = .timer
  delegate.window.show()
}
at(1.6) { shot(delegate.window.panel.windowNumber, "timer-\(lang)"); t.mode = .alarm }
at(3.0) {
  shot(delegate.window.panel.windowNumber, "alarm-\(lang)")
  delegate.listWindow.show()
  delegate.listWindow.model.selection = [meeting]
  // 설정의 캘린더 탭: 구글 주소 하나를 넣고, 받아 온 것처럼 상태를 채운다.
  _ = delegate.calendarSync.add("https://calendar.google.com/calendar/ical/me%40example.com/private-0123456789abcdef/basic.ics")
}
at(4.2) { shot(delegate.listWindow.windowNumber, "list-\(lang)") }
// 가짜 주소라 받기는 실패하므로, 실패가 끝난 뒤 상태를 덮어쓴다.
at(6.0) {
  let sync = delegate.calendarSync
  feedID = delegate.settings.calendarFeeds[0].id
  sync.statuses[feedID] = CalendarSync.Status(lastSuccess: Date(), error: nil, calendarName: ko ? "개인" : "Personal", eventCount: 4)
  delegate.showCalendarSettings()
}
at(7.2) {
  if let w = NSApp.windows.first(where: { $0.title == L("Clocky 설정") }) { shot(w.windowNumber, "calendar-\(lang)") }
  UserDefaults.standard.removePersistentDomain(forName: "Clocky")
  exit(0)
}
for (x, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + x, execute: f) }
app.run()
