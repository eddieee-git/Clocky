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
