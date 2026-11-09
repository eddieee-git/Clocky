import AppKit
import SwiftUI
// 이 Mac 안에 작은 웹 서버를 띄워 iCal 주소처럼 쓰고, 받아 오기부터 울리기까지 본다.
UserDefaults.standard.removePersistentDomain(forName: "Clocky")
setvbuf(stdout, nil, _IONBF, 0)
let shots = CommandLine.arguments[1]
let lang = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "ko"
UserDefaults.standard.set(lang, forKey: "language"); UserDefaults.standard.set(true, forKey: "hasLaunched")
UserDefaults.standard.set(1, forKey: "calendarLeadMinutes")
let ko = lang == "ko"

// 1분 뒤 시작(알림은 시작 1분 전이라 곧), 3시간 뒤 시작, 거절한 일정, 종일 일정
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clocky-cal-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func utc(_ date: Date) -> String {
  let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
  f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; return f.string(from: date)
}
let soon = Date().addingTimeInterval(72)
let later = Date().addingTimeInterval(3 * 3600)
let ics = """
BEGIN:VCALENDAR\r
VERSION:2.0\r
X-WR-CALNAME:\(ko ? "업무" : "Work")\r
BEGIN:VEVENT\r
UID:soon\r
DTSTART:\(utc(soon))\r
DTEND:\(utc(soon.addingTimeInterval(1800)))\r
SUMMARY:\(ko ? "디자인 검토" : "Design review")\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:later\r
DTSTART:\(utc(later))\r
SUMMARY:\(ko ? "주간 회의" : "Weekly sync")\r
RRULE:FREQ=WEEKLY\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:declined\r
DTSTART:\(utc(later.addingTimeInterval(1800)))\r
SUMMARY:거절\r
ATTENDEE;PARTSTAT=DECLINED:mailto:me@example.com\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:allday\r
DTSTART;VALUE=DATE:20991231\r
SUMMARY:종일\r
END:VEVENT\r
END:VCALENDAR\r
"""
let port = Int.random(in: 20000...40000)
// 구글 주소처럼 /calendar/ical/<이메일>/private-.../basic.ics 경로에 둔다.
let path = folder.appendingPathComponent("calendar/ical/me@example.com/private-test")
try! FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
try! ics.write(to: path.appendingPathComponent("basic.ics"), atomically: true, encoding: .utf8)
let server = Process()
server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
server.arguments = ["-m", "http.server", "\(port)", "--bind", "127.0.0.1", "--directory", folder.path]
server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
try! server.run()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
var failures = 0
func check(_ ok: Bool, _ msg: String) { print(ok ? "PASS" : "FAIL", msg); if !ok { failures += 1 } }
var t: ClockStore { delegate.window.store }
func shot(_ number: Int, _ name: String) {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = ["-x", "-o", "-l", "\(number)", "\(shots)/\(name).png"]; try? p.run(); p.waitUntilExit()
}
var steps: [(Double, () -> Void)] = []
func at(_ x: Double, _ f: @escaping () -> Void) { steps.append((x, f)) }
var settingsWindow: NSWindow?

at(1.0) {
  let sync = delegate.calendarSync
  check(sync.add("http://example.com/x.ics") == .notSecure, "http 주소는 받지 않음")
  check(sync.add("http://127.0.0.1:\(port)/calendar/ical/me%40example.com/private-test/basic.ics") == nil, "주소 추가")
  check(sync.add("http://127.0.0.1:\(port)/calendar/ical/me%40example.com/private-test/basic.ics") == .duplicate, "같은 주소는 한 번만")
  check(sync.add("http://127.0.0.1:\(port)/missing.ics") == nil, "없는 주소도 일단 추가")
  t.mode = .alarm
  delegate.window.show()
}
at(4.0) {
  let sync = delegate.calendarSync
  let feeds = delegate.settings.calendarFeeds
  let good = sync.statuses[feeds[0].id]
  check(good?.lastSuccess != nil && good?.error == nil, "일정 받아 옴: \(String(describing: good))")
  check(sync.title(of: feeds[0]) == (ko ? "업무" : "Work"), "캘린더 이름: \(sync.title(of: feeds[0]))")
  check(t.calendarEvents.map(\.title) == [ko ? "디자인 검토" : "Design review", ko ? "주간 회의" : "Weekly sync"],
        "거절한 일정과 종일 일정은 빠짐: \(t.calendarEvents.map(\.title))")
  let bad = sync.statuses[feeds[1].id]
  check(bad?.error != nil && bad?.lastSuccess == nil, "없는 주소는 오류 표시: \(bad?.error ?? "nil")")
  sync.remove(feeds[1].id)
  check(delegate.settings.calendarFeeds.count == 1, "주소 빼기")
  // 설정 창의 캘린더 탭을 따로 띄워 찍는다.
  let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 520, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
  w.contentView = NSHostingView(rootView: SettingsView(settings: delegate.settings, calendar: sync, tab: .calendar))
  w.orderFrontRegardless(); settingsWindow = w
}
at(5.0) {
  shot(settingsWindow!.windowNumber, "settings-calendar-\(lang)"); settingsWindow?.close()
  shot(delegate.window.panel.windowNumber, "clock-calendar-\(lang)")
  check(t.nextAlert?.title == (ko ? "디자인 검토" : "Design review"), "다음 알림은 곧 시작하는 일정")
}
// 알림은 시작 1분 전 = 처음부터 약 12초 뒤
at(14.0) {
  check(t.ringingEventIDs.count == 1 && t.mode == .alarm, "일정 알림이 울림")
  check(t.ringingTitles == [ko ? "디자인 검토" : "Design review"], "울리는 이름: \(t.ringingTitles)")
  shot(delegate.window.panel.windowNumber, "ringing-calendar-\(lang)")
  t.stopRinging()
}
at(14.5) {
  delegate.listWindow.show()
  delegate.listWindow.model.filter = .calendar
  delegate.listWindow.model.selection = [t.calendarEvents[1].listID]
}
at(15.5) {
  shot(delegate.listWindow.windowNumber, "list-calendar-\(lang)")
  t.setEventSkipped(t.calendarEvents[1].id, true)
  check(t.pendingEventAlerts.isEmpty, "남은 일정 알림 끄기")
}
at(16.0) {
  print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
  server.terminate()
  try? FileManager.default.removeItem(at: folder)
  UserDefaults.standard.removePersistentDomain(forName: "Clocky")
  exit(failures == 0 ? 0 : 1)
}
for (x, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + x, execute: f) }
app.run()
