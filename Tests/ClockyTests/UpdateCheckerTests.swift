import CryptoKit
import Foundation
import Testing
@testable import Clocky

private func json(tag: String = "v0.3.0", draft: Bool = false, prerelease: Bool = false,
                  assets: String = #"[{"name":"Clocky.dmg","browser_download_url":"https://github.com/eddieee-git/mac-app-clocky/releases/download/v0.3.0/Clocky.dmg","digest":"sha256:ABCDEF"}]"#) -> Data {
    Data("""
    {"tag_name":"\(tag)","html_url":"https://github.com/eddieee-git/mac-app-clocky/releases/tag/\(tag)",
     "body":"## 새 기능\\r\\n- **업데이트** 확인","draft":\(draft),"prerelease":\(prerelease),"assets":\(assets)}
    """.utf8)
}

@Suite struct UpdateCheckerTests {
    @Test func 버전_비교() {
        #expect(AppVersion.isNewer("0.2.1", than: "0.2.0"))
        #expect(AppVersion.isNewer("0.10.0", than: "0.9.9"))
        #expect(AppVersion.isNewer("1.0", than: "0.99.99"))
        #expect(!AppVersion.isNewer("0.2", than: "0.2.0"))
        #expect(!AppVersion.isNewer("0.2.0", than: "0.2.0"))
        #expect(!AppVersion.isNewer("0.1.9", than: "0.2.0"))
        #expect(AppVersion.isNewer("0.3.0-beta", than: "0.2.0"))
        #expect(AppVersion.normalized("v0.2.1") == "0.2.1")
        #expect(AppVersion.normalized("release") == nil)
    }

    @Test func 릴리스_읽기() throws {
        let release = try #require(ReleaseInfo.parse(json()))
        #expect(release.version == "0.3.0")
        #expect(release.dmgURL?.lastPathComponent == "Clocky.dmg")
        #expect(release.dmgSHA256 == "abcdef")
        #expect(release.shortNotes == "새 기능\n- 업데이트 확인")
    }

    @Test func 초안과_시험판과_dmg_없는_릴리스() throws {
        #expect(ReleaseInfo.parse(json(draft: true)) == nil)
        #expect(ReleaseInfo.parse(json(prerelease: true)) == nil)
        #expect(ReleaseInfo.parse(json(tag: "latest")) == nil)
        #expect(ReleaseInfo.parse(Data("{}".utf8)) == nil)
        let bare = try #require(ReleaseInfo.parse(json(assets: "[]")))
        #expect(bare.dmgURL == nil && bare.dmgSHA256 == nil)
    }

    @Test func 받는_주소는_GitHub만() {
        #expect(UpdateChecker.isAllowedDownload(URL(string: "https://github.com/a/b/releases/download/v1/Clocky.dmg")!))
        #expect(UpdateChecker.isAllowedDownload(URL(string: "https://release-assets.githubusercontent.com/x")!))
        #expect(!UpdateChecker.isAllowedDownload(URL(string: "http://github.com/a.dmg")!))
        #expect(!UpdateChecker.isAllowedDownload(URL(string: "https://github.com.evil.example/a.dmg")!))
        #expect(!UpdateChecker.isAllowedDownload(URL(string: "https://evilgithubusercontent.com/a.dmg")!))
    }
}

@Suite struct ReleaseSignatureTests {
    @Test func 서명은_버전과_파일에_묶인다() {
        let key = Curve25519.Signing.PrivateKey()
        let sha = String(repeating: "ab", count: 32)
        let signature = try! key.signature(for: UpdateChecker.signedMessage(version: "0.3.0", sha256: sha)).base64EncodedString()
        #expect(UpdateChecker.verify(signature: signature, version: "0.3.0", sha256: sha, key: key.publicKey))
        #expect(!UpdateChecker.verify(signature: signature, version: "0.3.1", sha256: sha, key: key.publicKey))
        #expect(!UpdateChecker.verify(signature: signature, version: "0.3.0", sha256: String(repeating: "cd", count: 32), key: key.publicKey))
        #expect(!UpdateChecker.verify(signature: signature, version: "0.3.0", sha256: sha, key: Curve25519.Signing.PrivateKey().publicKey))
        #expect(!UpdateChecker.verify(signature: "not base64", version: "0.3.0", sha256: sha, key: key.publicKey))
    }

    @Test func 서명_파일_찾기() throws {
        let data = Data("""
        {"tag_name":"v0.3.0","html_url":"https://github.com/a/b/releases/tag/v0.3.0","assets":[
         {"name":"Clocky-0.3.0.dmg","browser_download_url":"https://github.com/a/b/releases/download/v0.3.0/Clocky-0.3.0.dmg"},
         {"name":"Clocky-0.3.0.dmg.sig","browser_download_url":"https://github.com/a/b/releases/download/v0.3.0/Clocky-0.3.0.dmg.sig"}]}
        """.utf8)
        let release = try #require(ReleaseInfo.parse(data))
        #expect(release.signatureURL?.lastPathComponent == "Clocky-0.3.0.dmg.sig")
        #expect(release.dmgURL?.lastPathComponent == "Clocky-0.3.0.dmg")
    }

    /// 이 Mac에 릴리스 서명 키가 있으면, 서명 스크립트로 서명한 파일을 앱에 넣은 공개키로 검증해 본다.
    /// 스크립트와 앱의 서명 형식, 그리고 앱의 공개키가 비밀키와 짝인지 확인한다.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.clocky-release/signing-key")))
    func 서명_스크립트와_앱의_공개키가_맞다() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clocky-sign-\(UUID().uuidString).dmg")
        let data = Data((0..<1000).map { UInt8($0 % 7) })
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(atPath: file.path + ".sig") }
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/release-key.swift")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [script.path, "sign", file.path, "9.9.9"]
        process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        let signature = try String(contentsOfFile: file.path + ".sig", encoding: .utf8)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: UpdateChecker.releasePublicKey)!)
        #expect(UpdateChecker.verify(signature: signature, version: "9.9.9", sha256: sha, key: key))
    }

    @Test func 앱에_넣은_공개키는_올바르다() {
        #expect(Data(base64Encoded: UpdateChecker.releasePublicKey).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) } != nil)
    }
}

@Suite struct InstallLocationTests {
    @Test func dmg와_임시_위치에서_실행하면_알린다() {
        #expect(InstallLocation.needsMove("/Volumes/Clocky/Clocky.app"))
        #expect(InstallLocation.needsMove("/private/var/folders/ab/xyz/T/AppTranslocation/1234/d/Clocky.app"))
        #expect(!InstallLocation.needsMove("/Applications/Clocky.app"))
        #expect(!InstallLocation.needsMove("/Users/me/Applications/Clocky.app"))
    }
}
