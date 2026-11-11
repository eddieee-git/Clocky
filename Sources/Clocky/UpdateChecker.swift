import AppKit
import Combine
import CryptoKit

/// GitHub에 올린 릴리스 하나.
struct ReleaseInfo: Codable, Equatable {
    var version: String
    var pageURL: URL
    var notes: String
    var dmgURL: URL?
    /// GitHub가 올린 파일마다 적어 두는 SHA-256. 받은 파일과 비교한다.
    var dmgSHA256: String?

    /// GitHub API의 "최신 릴리스" 응답을 읽는다. 초안·시험판이거나 버전을 읽을 수 없으면 nil.
    static func parse(_ data: Data) -> ReleaseInfo? {
        struct Asset: Decodable {
            var name: String
            var browser_download_url: String
            var digest: String?
        }
        struct Release: Decodable {
            var tag_name: String
            var html_url: String
            var body: String?
            var draft: Bool?
            var prerelease: Bool?
            var assets: [Asset]?
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true,
              let version = AppVersion.normalized(release.tag_name),
              let page = URL(string: release.html_url), page.scheme == "https" else { return nil }
        let dmg = release.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
        var sha: String?
        if let digest = dmg?.digest, digest.hasPrefix("sha256:") { sha = String(digest.dropFirst("sha256:".count)).lowercased() }
        return ReleaseInfo(version: version, pageURL: page, notes: release.body ?? "",
                           dmgURL: dmg.flatMap { URL(string: $0.browser_download_url) }, dmgSHA256: sha)
    }

    /// 알림 창에 넣을 만큼 줄인 변경 내용. 마크다운 기호는 뺀다.
    var shortNotes: String {
        let lines = notes.replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var text = String(line)
                while text.hasPrefix("#") { text.removeFirst() }
                return text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        let text = lines.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 600 ? String(text.prefix(600)) + "…" : text
    }
}

enum AppVersion {
    /// 이 앱의 버전. 번들 없이 돌 때(시험)는 0.
    static var current: String {
        #if DEBUG
        if let version = UserDefaults.standard.string(forKey: "debugAppVersion") { return version }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// "v0.2.1" → "0.2.1". 숫자로 시작하지 않으면 nil.
    static func normalized(_ tag: String) -> String? {
        var text = tag.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        guard let first = text.first, first.isNumber else { return nil }
        return text
    }

    /// 점으로 나눈 숫자를 차례로 비교한다. 0.2 = 0.2.0. "-beta" 같은 꼬리는 무시한다.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ text: String) -> [Int] {
            let core = text.split(separator: "-").first.map(String.init) ?? text
            return core.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// 하루에 한 번 GitHub에 새 버전이 있는지 묻는다. 있으면 메뉴와 설정에 알리고,
/// 사용자가 고르면 dmg를 다운로드 폴더에 받아 열어 준다. 설치(응용 프로그램 폴더로 끌어 놓기)는 사용자가 한다.
/// 샌드박스 앱은 응용 프로그램 폴더의 자기 자신을 바꿀 수 없기 때문이다.
final class UpdateChecker: ObservableObject {
    static let interval: TimeInterval = 86400
    static let releaseAPI = URL(string: "https://api.github.com/repos/eddieee-git/mac-app-clocky/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/eddieee-git/mac-app-clocky/releases")!
    private static let maxBytes: Int64 = 200 * 1024 * 1024
    private enum Keys {
        static let lastCheck = "lastUpdateCheck", latest = "latestRelease"
    }

    /// 지금 버전보다 새 릴리스. 없으면 nil.
    @Published private(set) var available: ReleaseInfo?
    @Published private(set) var lastCheck: Date?
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    /// 마지막 확인이 실패한 까닭.
    @Published private(set) var error: String?

    private let settings: ClockySettings
    private let session: URLSession
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var subscriptions: Set<AnyCancellable> = []

    init(settings: ClockySettings) {
        self.settings = settings
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        lastCheck = defaults.object(forKey: Keys.lastCheck) as? Date
        // 지난번에 찾아 둔 새 버전. 그사이 업데이트했으면 버린다.
        available = defaults.data(forKey: Keys.latest)
            .flatMap { try? JSONDecoder().decode(ReleaseInfo.self, from: $0) }
            .flatMap { AppVersion.isNewer($0.version, than: AppVersion.current) ? $0 : nil }

        // 한 시간마다 하루가 지났는지 본다. 잠자기에서 깨어난 뒤에도 곧 확인하게 된다.
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        settings.$checkForUpdates.dropFirst().removeDuplicates()
            .sink { [weak self] on in if on { DispatchQueue.main.async { self?.checkIfDue() } } }
            .store(in: &subscriptions)
        // 켜자마자 인터넷이 아직 안 붙었을 수 있어 조금 기다린다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkIfDue() }
    }

    deinit { timer?.invalidate() }

    /// 묻는 주소. 시험에서는 이 Mac 안의 서버로 바꾼다.
    private var apiURL: URL {
        #if DEBUG
        if let text = defaults.string(forKey: "debugUpdateURL"), let url = URL(string: text) { return url }
        #endif
        return Self.releaseAPI
    }

    /// 자동 확인을 켰고 마지막 확인에서 하루가 지났으면 확인한다.
    func checkIfDue() {
        guard settings.checkForUpdates, !isChecking else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.interval, lastCheck <= Date() { return }
        check()
    }

    /// 지금 확인한다. 끝나면 `completion`에 새 버전(없으면 nil)을 넘긴다.
    func check(completion: ((ReleaseInfo?) -> Void)? = nil) {
        guard !isChecking else { return }
        isChecking = true
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, response, error in
            var release: ReleaseInfo?
            var failure: String?
            if let error {
                failure = error.localizedDescription
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // 아직 릴리스가 없으면 404다.
                if http.statusCode != 404 { failure = L("서버 응답 %d", http.statusCode) }
            } else if let data, let parsed = ReleaseInfo.parse(data) {
                release = parsed
            } else {
                failure = L("릴리스 정보를 읽지 못했습니다.")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                self.error = failure
                if failure == nil {
                    self.lastCheck = Date()
                    self.defaults.set(self.lastCheck, forKey: Keys.lastCheck)
                    let newer = release.flatMap { AppVersion.isNewer($0.version, than: AppVersion.current) ? $0 : nil }
                    self.available = newer
                    if let newer { self.defaults.set(try? JSONEncoder().encode(newer), forKey: Keys.latest) }
                    else { self.defaults.removeObject(forKey: Keys.latest) }
                }
                completion?(self.available)
            }
        }.resume()
    }

    // MARK: 받기

    enum DownloadError: Error, Equatable {
        case noFile, badAddress, tooLarge, checksum, server(Int), failed(String)

        var message: String {
            switch self {
            case .noFile: return L("이 릴리스에는 dmg 파일이 없습니다.")
            case .badAddress: return L("다운로드 주소가 GitHub가 아닙니다.")
            case .tooLarge: return L("파일이 너무 큽니다.")
            case .checksum: return L("받은 파일이 GitHub에 올린 파일과 다릅니다. 지웠습니다.")
            case .server(let code): return L("서버 응답 %d", code)
            case .failed(let text): return text
            }
        }
    }

    /// 받는 주소는 https인 GitHub만 받는다(이 Mac 안의 시험 서버는 예외).
    static func isAllowedDownload(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "http" || scheme == "https", host == "localhost" || host == "127.0.0.1" {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
        return scheme == "https" && (host == "github.com" || host.hasSuffix(".githubusercontent.com"))
    }

    /// dmg를 다운로드 폴더에 받아 SHA-256을 맞춰 본 뒤, 저장한 위치를 넘긴다.
    func download(_ release: ReleaseInfo, to folder: URL? = nil, completion: @escaping (Result<URL, DownloadError>) -> Void) {
        guard let url = release.dmgURL else { return completion(.failure(.noFile)) }
        guard Self.isAllowedDownload(url) else { return completion(.failure(.badAddress)) }
        guard !isDownloading else { return }
        isDownloading = true
        let folder = folder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        session.downloadTask(with: url) { [weak self] temp, response, error in
            var result: Result<URL, DownloadError>
            if let error {
                result = .failure(.failed(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(.server(http.statusCode))
            } else if let final = response?.url, !Self.isAllowedDownload(final) {
                result = .failure(.badAddress)
            } else if let temp {
                result = Self.store(temp, release: release, in: folder)
            } else {
                result = .failure(.failed(L("다운로드하지 못했습니다.")))
            }
            DispatchQueue.main.async {
                self?.isDownloading = false
                completion(result)
            }
        }.resume()
    }

    /// 받은 임시 파일을 확인하고 "Clocky 0.2.1.dmg"로 옮긴다. 같은 이름이 있으면 번호를 붙인다.
    private static func store(_ temp: URL, release: ReleaseInfo, in folder: URL) -> Result<URL, DownloadError> {
        let manager = FileManager.default
        let size = (try? manager.attributesOfItem(atPath: temp.path)[.size] as? Int64) ?? 0
        guard size > 0, size <= maxBytes else { return .failure(.tooLarge) }
        if let expected = release.dmgSHA256 {
            guard let data = try? Data(contentsOf: temp, options: .mappedIfSafe) else { return .failure(.failed(L("다운로드하지 못했습니다."))) }
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { return .failure(.checksum) }
        }
        var target = folder.appendingPathComponent("Clocky \(release.version).dmg")
        var number = 2
        while manager.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("Clocky \(release.version) (\(number)).dmg")
            number += 1
        }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try manager.moveItem(at: temp, to: target)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        return .success(target)
    }

    // MARK: 알림 창

    /// 새 버전을 알리고, 다운로드를 고르면 받아서 연다.
    func offer(_ release: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("새 버전 Clocky %@", release.version)
        let notes = release.shortNotes
        alert.informativeText = L("지금 쓰는 버전은 %@입니다.", AppVersion.current) + (notes.isEmpty ? "" : "\n\n" + notes)
        alert.addButton(withTitle: release.dmgURL == nil ? L("릴리스 페이지 열기") : L("다운로드"))
        alert.addButton(withTitle: L("나중에"))
        if release.dmgURL != nil { alert.addButton(withTitle: L("릴리스 페이지 열기")) }
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if release.dmgURL == nil { NSWorkspace.shared.open(release.pageURL) } else { downloadAndOpen(release) }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    /// 지금 확인하고, 결과를 창으로 알린다. 설정의 "지금 확인"과 메뉴에서 쓴다.
    func checkAndReport() {
        check { [weak self] release in
            guard let self else { return }
            if let release { return self.offer(release) }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            if let error = self.error {
                alert.messageText = L("업데이트를 확인하지 못했습니다")
                alert.informativeText = error
            } else {
                alert.messageText = L("최신 버전입니다")
                alert.informativeText = L("지금 쓰는 Clocky %@이 가장 새 버전입니다.", AppVersion.current)
            }
            alert.runModal()
        }
    }

    private func downloadAndOpen(_ release: ReleaseInfo) {
        download(release) { [weak self] result in
            switch result {
            case .success(let file):
                NSWorkspace.shared.open(file)
                self?.explainInstall(file)
            case .failure(let error):
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L("다운로드하지 못했습니다")
                alert.informativeText = error.message
                alert.addButton(withTitle: L("릴리스 페이지 열기"))
                alert.addButton(withTitle: L("닫기"))
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.pageURL) }
            }
        }
    }

    /// 열린 디스크 이미지에서 무엇을 하면 되는지 알려 준다. 실행 중인 앱은 덮어쓸 수 없으므로 먼저 끝낸다.
    private func explainInstall(_ file: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("다운로드한 Clocky를 열었습니다")
        alert.informativeText = L("Clocky를 종료한 뒤, 열린 창에서 Clocky를 Applications 폴더로 끌어 놓아 기존 것을 대체한 뒤 다시 여세요. 타이머와 알람은 그대로 남습니다.\n\n받은 파일: %@", file.path)
        alert.addButton(withTitle: L("Clocky 종료"))
        alert.addButton(withTitle: L("나중에"))
        if alert.runModal() == .alertFirstButtonReturn { NSApp.terminate(nil) }
    }
}
