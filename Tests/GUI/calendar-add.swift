import AppKit
// 설정 → 캘린더의 "캘린더 추가…" 팝업: 클립보드 주소 미리 채우기, 추가, 잘못된 주소일 때 이유와 함께 다시 뜨기.
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
func shot(_ w: NSWindow, _ name: String) {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = ["-x", "-o", "-l", "\(w.windowNumber)", "\(shots)/\(name).png"]; try? p.run(); p.waitUntilExit()
}
func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
/// 떠 있는 팝업의 입력 칸과 단추.
var alertWindow: NSWindow? { NSApp.modalWindow }
var alertField: NSTextField? { alertWindow.flatMap { views($0.contentView!).compactMap { $0 as? NSTextField }.first { $0.isEditable } } }
func alertButton(_ title: String) -> NSButton? { alertWindow.flatMap { views($0.contentView!).compactMap { $0 as? NSButton }.first { $0.title == title } } }
var alertText: String { alertWindow.map { views($0.contentView!).compactMap { $0 as? NSTextField }.filter { !$0.isEditable }.map(\.stringValue).joined(separator: " | ") } ?? "" }

let address = "https://calendar.google.com/calendar/ical/me%40example.com/private-abc/basic.ics"
var steps: [(Double, () -> Void)] = []
func at(_ x: Double, _ f: @escaping () -> Void) { steps.append((x, f)) }
at(0.5) { delegate.showCalendarSettings() }
at(1.5) {
  NSPasteboard.general.clearContents(); NSPasteboard.general.setString(address, forType: .string)
  // 이 다음 단계들은 팝업이 떠 있는 동안 돈다.
  CalendarAddPrompt.run(sync: delegate.calendarSync)
}
at(2.5) {
  check(alertField?.stringValue == address, "클립보드의 iCal 주소를 미리 채움: \(alertField?.stringValue ?? "nil")")
  if let w = alertWindow { shot(w, "calendar-add-popup-\(lang)") }
  alertButton(L("추가"))?.performClick(nil)
}
at(3.0) {
  NSPasteboard.general.clearContents(); NSPasteboard.general.setString("그냥 글", forType: .string)
  CalendarAddPrompt.run(sync: delegate.calendarSync)
}
at(3.8) {
  check(alertField?.stringValue == "", "주소가 아닌 클립보드는 채우지 않음")
  alertField?.stringValue = "http://example.com/a.ics"
  alertButton(L("추가"))?.performClick(nil)
}
at(4.6) {
  check(alertWindow != nil && alertText.contains(L("https:// 또는 webcal:// 로 시작하는 주소만 넣을 수 있습니다.")), "잘못된 주소면 이유와 함께 다시 뜸: \(alertText.prefix(80))")
  check(alertField?.stringValue == "http://example.com/a.ics", "넣었던 글이 그대로 남음")
  if let w = alertWindow { shot(w, "calendar-add-error-\(lang)") }
  alertButton(L("취소"))?.performClick(nil)
}
at(5.2) {
  check(alertWindow == nil, "취소하면 닫힘")
  // 팝업이 닫힌 뒤에야 주소가 들어가므로 마지막에 한 번에 본다. 잘못된 주소는 들어가지 않는다.
  check(delegate.settings.calendarFeeds.map(\.url) == [address], "추가 단추로 들어감: \(delegate.settings.calendarFeeds.map(\.url))")
  if let w = NSApp.windows.first(where: { $0.title == L("Clocky 설정") }) { shot(w, "settings-calendar-added-\(lang)") }
  print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
  UserDefaults.standard.removePersistentDomain(forName: "Clocky")
  exit(failures == 0 ? 0 : 1)
}
// 팝업(runModal)이 떠 있는 동안에도 돌도록 모든 모드에 타이머를 건다.
for (x, f) in steps {
  RunLoop.main.add(Timer(fire: Date().addingTimeInterval(x), interval: 0, repeats: false) { _ in f() }, forMode: .common)
}
app.run()
