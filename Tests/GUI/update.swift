import AppKit
import CryptoKit
import SwiftUI
// 이 Mac 안의 작은 웹 서버를 GitHub 릴리스처럼 쓰고, 새 버전 찾기부터 dmg 받기와 SHA-256 확인까지 본다.
UserDefaults.standard.removePersistentDomain(forName: "Clocky")
setvbuf(stdout, nil, _IONBF, 0)
let shots = CommandLine.arguments[1]
let lang = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "ko"
let ko = lang == "ko"
let port = Int.random(in: 20000...40000)
let base = "http://127.0.0.1:\(port)"
UserDefaults.standard.set(lang, forKey: "language"); UserDefaults.standard.set(true, forKey: "hasLaunched")
UserDefaults.standard.set("0.2.0", forKey: "debugAppVersion")
UserDefaults.standard.set("\(base)/latest.json", forKey: "debugUpdateURL")

let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clocky-update-\(UUID().uuidString)")
let downloads = folder.appendingPathComponent("Downloads")
try! FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
let dmg = Data((0..<50_000).map { UInt8($0 % 251) })
try! dmg.write(to: folder.appendingPathComponent("Clocky.dmg"))
let sha = SHA256.hash(data: dmg).map { String(format: "%02x", $0) }.joined()
func release(_ tag: String, digest: String) -> String {
  ##"{"tag_name":"\##(tag)","html_url":"https://github.com/eddieee-git/mac-app-clocky/releases/tag/\##(tag)","body":"새 기능 · New\r\n- **업데이트 확인**","draft":false,"prerelease":false,"assets":[{"name":"Clocky.dmg","browser_download_url":"\##(base)/Clocky.dmg","digest":"sha256:\##(digest)"}]}"##
}
try! release("v0.3.0", digest: sha).write(to: folder.appendingPathComponent("latest.json"), atomically: true, encoding: .utf8)
try! release("v0.2.0", digest: sha).write(to: folder.appendingPathComponent("same.json"), atomically: true, encoding: .utf8)
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
func shot(_ number: Int, _ name: String) {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  p.arguments = ["-x", "-o", "-l", "\(number)", "\(shots)/\(name).png"]; try? p.run(); p.waitUntilExit()
}
var steps: [(Double, () -> Void)] = []
func at(_ x: Double, _ f: @escaping () -> Void) { steps.append((x, f)) }
var u: UpdateChecker { delegate.updater }
func menuTitles() -> [String] { delegate.statusItem?.menu?.items.map(\.title) ?? [] }

at(1.0) {
  check(u.available == nil && u.lastCheck == nil, "처음에는 아직 확인 전")
  check(menuTitles().contains(ko ? "업데이트 확인…" : "Check for Updates…"), "메뉴에 업데이트 확인")
}
// 켠 지 5초 뒤 저절로 확인한다.
at(7.0) {
  check(u.available?.version == "0.3.0", "새 버전 찾음: \(String(describing: u.available?.version))")
  check(u.lastCheck != nil && u.error == nil, "마지막 확인 시각 기록")
  check(menuTitles().contains(ko ? "새 버전 Clocky 0.3.0 받기…" : "Get New Version, Clocky 0.3.0…"), "메뉴에 새 버전 알림: \(menuTitles())")
  delegate.settingsWindow.show(tab: .general)
}
at(8.5) {
  if let w = NSApp.windows.first(where: { $0.title == L("Clocky 설정") }) { shot(w.windowNumber, "settings-update-\(lang)") }
  u.download(u.available!, to: downloads) { result in
    if case .success(let file) = result {
      check(file.lastPathComponent == "Clocky 0.3.0.dmg", "다운로드 폴더에 저장: \(file.lastPathComponent)")
      check((try? Data(contentsOf: file)) == dmg, "받은 내용이 같음")
    } else { check(false, "다운로드 실패: \(result)") }
    // 같은 이름이 있으면 번호를 붙인다.
    u.download(u.available!, to: downloads) { again in
      if case .success(let file) = again { check(file.lastPathComponent == "Clocky 0.3.0 (2).dmg", "두 번째는 번호: \(file.lastPathComponent)") }
      else { check(false, "두 번째 다운로드 실패") }
    }
  }
}
at(10.0) {
  // SHA-256이 다르면 받은 파일을 남기지 않는다.
  var bad = u.available!
  bad.dmgSHA256 = String(repeating: "0", count: 64)
  u.download(bad, to: downloads) { result in
    check(result == .failure(.checksum), "SHA-256이 다르면 실패: \(result)")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? []
    check(files.count == 2, "잘못 받은 파일은 남지 않음: \(files)")
  }
  var elsewhere = u.available!
  elsewhere.dmgURL = URL(string: "https://example.com/Clocky.dmg")
  u.download(elsewhere, to: downloads) { result in check(result == .failure(.badAddress), "GitHub 밖에서는 받지 않음") }
}
at(11.5) {
  // 같은 버전이 최신이면 알림이 사라진다.
  UserDefaults.standard.set("\(base)/same.json", forKey: "debugUpdateURL")
  u.check { found in
    check(found == nil && u.available == nil, "최신 버전이면 알림 없음")
    DispatchQueue.main.async {
      check(menuTitles().contains(ko ? "업데이트 확인…" : "Check for Updates…"), "메뉴가 다시 업데이트 확인으로")
    }
  }
}
at(13.0) {
  // 끄면 저절로 확인하지 않는다.
  delegate.settings.checkForUpdates = false
  u.checkIfDue()
  check(!u.isChecking, "자동 확인을 끄면 묻지 않음")
}
at(14.0) {
  print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
  server.terminate()
  try? FileManager.default.removeItem(at: folder)
  UserDefaults.standard.removePersistentDomain(forName: "Clocky")
  exit(failures == 0 ? 0 : 1)
}
for (x, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + x, execute: f) }
app.run()
