import AppKit
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
func shot(_ name: String) {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = ["-x", "-o", "-l", "\(delegate.window.panel.windowNumber)", "\(shots)/\(name).png"]
  try? p.run(); p.waitUntilExit()
}
let ko = lang == "ko"
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
  let a = t.timers[0].id
  t.renameTimer(a, to: ko ? "라면" : "Noodles"); t.setDuration(a, 180)
  let b = t.addTimer(); t.renameTimer(b, to: ko ? "빨래" : "Laundry"); t.setDuration(b, 40*60)
  let c = t.addTimer(); t.renameTimer(c, to: ko ? "스트레칭" : "Stretch"); t.setDuration(c, 10*60)
  t.start(b); t.alarms.indices.forEach { _ in }
  t.timers[1].endDate = Date().addingTimeInterval(23*60+12)
  t.pause(b)
  t.start(a); t.timers[0].endDate = Date().addingTimeInterval(2*60+47)
  t.selectedTimerID = a
  let x = t.addAlarm(minutes: 7*60+30); t.renameAlarm(x, to: ko ? "기상" : "Wake up")
  let y = t.addAlarm(minutes: 14*60); t.renameAlarm(y, to: ko ? "회의" : "Meeting"); t.setAlarmDays(y, AlarmItem.weekdays)
  let z = t.addAlarm(minutes: 21*60); t.renameAlarm(z, to: ko ? "약 먹기" : "Medicine"); t.setAlarmEnabled(z, false)
  t.selectedAlarmID = x
  t.mode = .timer
  delegate.window.show()
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { shot("timer-\(lang)"); t.mode = .alarm }
DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { shot("alarm-\(lang)"); UserDefaults.standard.removePersistentDomain(forName: "Clocky"); exit(0) }
app.run()
