import AppKit
import Combine
import CryptoKit

/// 설정에 넣은 iCal 주소 하나. 구글 캘린더의 "비공개 주소(iCal 형식)"를 쓴다.
struct CalendarFeed: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: String
    /// 비어 있으면 받아 온 캘린더 이름(X-WR-CALNAME)을 쓴다.
    var name = ""
    var enabled = true

    /// 화면에는 비밀 토큰을 가리고 보여 준다. 예: calendar.google.com/…/basic.ics
    var maskedURL: String {
        guard let url = URL(string: url), let host = url.host else { return "…" }
        return "\(host)/…/\(url.lastPathComponent)"
    }
}

extension CalendarEvent {
    /// 목록 창은 UUID로 고르므로, 같은 일정이면 늘 같은 UUID를 만든다.
    var listID: UUID {
        let digest = Array(SHA256.hash(data: Data(id.utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }
}

/// iCal 주소에서 일정을 받아 와 시계에 넘긴다. 15분마다, Mac이 깨어날 때, 설정을 바꿀 때 새로 받는다.
/// 받지 못하면(인터넷이 끊기는 등) 마지막으로 받은 내용으로 계속 알린다.
final class CalendarSync: ObservableObject {
    struct Status: Equatable {
        var lastSuccess: Date?
        var error: String?
        var calendarName: String?
        var eventCount = 0
    }

    static let refreshInterval: TimeInterval = 15 * 60
    /// 앞으로 이만큼 안의 일정을 알린다. 지난 일정은 조금 늦게 깨어났을 때를 위해 1시간 전까지 본다.
    static let lookAhead: TimeInterval = 2 * 86400
    static let lookBehind: TimeInterval = 3600
    private static let maxBytes = 20 * 1024 * 1024

    @Published private(set) var statuses: [UUID: Status] = [:]
    /// Mac 캘린더 앱의 일정. 설정에서 켰을 때만 접근을 묻는다.
    let mac = MacCalendarSource()
    /// Mac 캘린더 앱에서 읽은 이틀 안 일정 수.
    @Published private(set) var macEventCount = 0
    @Published private(set) var isRefreshing = false

    private let settings: ClockySettings
    private let store: ClockStore
    private let session: URLSession
    private var texts: [UUID: String] = [:]
    /// 서버가 준 ETag. 앱을 다시 켜면 처음 한 번은 전부 받는다.
    private var etags: [UUID: String] = [:]
    private var timer: Timer?
    private var subscriptions: Set<AnyCancellable> = []
    private var wakeObserver: NSObjectProtocol?
    private var generation = 0

    init(settings: ClockySettings, store: ClockStore) {
        self.settings = settings
        self.store = store
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)

        for feed in settings.calendarFeeds {
            if let text = try? String(contentsOf: Self.cacheURL(feed.id), encoding: .utf8) { texts[feed.id] = text }
        }
        recompute()

        // 주소를 더하거나 끄고 켜면 새로 받고, 알림 시점이나 거를 일정을 바꾸면 이미 받은 것으로 다시 셈한다.
        settings.$calendarFeeds.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.feedsChanged() } }
            .store(in: &subscriptions)
        settings.$calendarIncludeAllDay.combineLatest(settings.$calendarIncludeDeclined).dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.recompute() } }
            .store(in: &subscriptions)
        // Mac 캘린더를 켜면 처음 한 번 접근을 묻고, 고른 캘린더가 바뀌면 다시 셈한다.
        settings.$macCalendarEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] enabled in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if enabled { self.mac.requestAccess { self.recompute() } } else { self.recompute() }
                }
            }
            .store(in: &subscriptions)
        settings.$macCalendarIDs.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.recompute() } }
            .store(in: &subscriptions)
        mac.onChange = { [weak self] in self?.recompute() }
        settings.$calendarLeadMinutes
            .sink { [weak store] in store?.calendarLead = TimeInterval($0 * 60) }
            .store(in: &subscriptions)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // 깨어난 직후에는 인터넷이 아직 안 붙었을 수 있어 조금 기다린다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self?.refresh() }
        }
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    // MARK: 주소

    enum AddError: Error, Equatable {
        case invalid, notSecure, duplicate
    }

    /// webcal://은 https://로 바꾼다. 비밀 주소가 그대로 오가지 않게 https만 받는다(이 Mac 안의 시험 서버는 예외).
    static func normalizedURL(_ text: String) -> Result<URL, AddError> {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.lowercased().hasPrefix("webcal://") { raw = "https://" + raw.dropFirst("webcal://".count) }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            return .failure(.invalid)
        }
        let local = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && local) else { return .failure(.notSecure) }
        return .success(url)
    }

    @discardableResult
    func add(_ text: String) -> AddError? {
        switch Self.normalizedURL(text) {
        case .failure(let error):
            return error
        case .success(let url):
            if settings.calendarFeeds.contains(where: { $0.url == url.absoluteString }) { return .duplicate }
            settings.calendarFeeds.append(CalendarFeed(url: url.absoluteString))
            return nil
        }
    }

    func remove(_ id: UUID) {
        settings.calendarFeeds.removeAll { $0.id == id }
    }

    // MARK: 받기

    private func feedsChanged() {
        let ids = Set(settings.calendarFeeds.map(\.id))
        for id in texts.keys where !ids.contains(id) {
            texts[id] = nil
            statuses[id] = nil
            etags[id] = nil
            try? FileManager.default.removeItem(at: Self.cacheURL(id))
        }
        recompute()
        refresh()
    }

    /// 켜 둔 주소를 모두 새로 받는다. 받는 대로 다시 셈한다.
    func refresh() {
        let feeds = settings.calendarFeeds.filter(\.enabled)
        // Mac 캘린더 앱은 스스로 새로 받으므로 여기서는 다시 셈하기만 한다.
        guard !feeds.isEmpty else { isRefreshing = false; recompute(); return }
        generation += 1
        let current = generation
        isRefreshing = true
        var pending = feeds.count
        for feed in feeds {
            guard case .success(let url) = Self.normalizedURL(feed.url) else {
                statuses[feed.id, default: Status()].error = L("주소가 올바르지 않습니다.")
                pending -= 1
                continue
            }
            let etag = etags[feed.id]
            Self.fetch(url, etag: etag, session: session) { [weak self] result in
                guard let self else { return }
                self.apply(result, to: feed.id)
                pending -= 1
                self.recompute()
                if pending <= 0 && current == self.generation { self.isRefreshing = false }
            }
        }
        if pending <= 0 { isRefreshing = false }
    }

    /// 받아 둔 글로 앞으로 이틀 안의 일정을 다시 셈해 시계에 넘긴다.
    func recompute() {
        let now = Date()
        let range = now.addingTimeInterval(-Self.lookBehind)...now.addingTimeInterval(Self.lookAhead)
        var events: [CalendarEvent] = []
        for feed in settings.calendarFeeds where feed.enabled {
            guard let text = texts[feed.id] else { continue }
            var options = ICalendar.Options()
            options.includeAllDay = settings.calendarIncludeAllDay
            options.includeDeclined = settings.calendarIncludeDeclined
            options.ownerEmail = URL(string: feed.url).flatMap(ICalendar.ownerEmail)
            let fallback = feed.name.isEmpty ? feed.maskedURL : feed.name
            var result = ICalendar.events(from: text, feedID: feed.id, fallbackName: fallback, in: range, options: options)
            if !feed.name.isEmpty {
                result.events = result.events.map {
                    CalendarEvent(id: $0.id, title: $0.title, start: $0.start, end: $0.end, calendarName: feed.name, feedID: $0.feedID)
                }
            }
            statuses[feed.id, default: Status()].calendarName = result.calendarName
            statuses[feed.id, default: Status()].eventCount = result.events.count
            events += result.events
        }
        if settings.macCalendarEnabled {
            let macEvents = mac.events(in: range, selected: settings.macCalendarIDs.map(Set.init),
                                       includeAllDay: settings.calendarIncludeAllDay,
                                       includeDeclined: settings.calendarIncludeDeclined)
            if macEvents.count != macEventCount { macEventCount = macEvents.count }
            events += macEvents
        } else if macEventCount != 0 {
            macEventCount = 0
        }
        store.setCalendarEvents(events.sorted { $0.start < $1.start })
    }

    private func apply(_ result: FetchResult, to id: UUID) {
        switch result {
        case .notModified:
            statuses[id, default: Status()].lastSuccess = Date()
            statuses[id, default: Status()].error = nil
        case .text(let text, let newTag):
            etags[id] = newTag
            // 바뀌지 않았으면 디스크에 다시 쓰지 않는다.
            if texts[id] != text {
                texts[id] = text
                try? FileManager.default.createDirectory(at: Self.cacheFolder, withIntermediateDirectories: true)
                try? text.write(to: Self.cacheURL(id), atomically: true, encoding: .utf8)
            }
            statuses[id, default: Status()].lastSuccess = Date()
            statuses[id, default: Status()].error = nil
        case .failure(let message):
            statuses[id, default: Status()].error = message
        }
    }

    /// 받은 결과를 메인 스레드에서 넘긴다.
    static func fetch(_ url: URL, etag: String?, session: URLSession, completion: @escaping (FetchResult) -> Void) {
        Task {
            let result = await fetch(url, etag: etag, session: session)
            DispatchQueue.main.async { completion(result) }
        }
    }

    enum FetchResult: Equatable {
        case text(String, etag: String?)
        case notModified
        case failure(String)
    }

    /// 주소 하나를 받는다. 서버가 ETag를 주면 다음에는 바뀌었을 때만 받는다(구글은 주지 않는다).
    /// 받는 동안 크기를 세어 너무 크면 끝까지 받지 않고 멈춘다.
    static func fetch(_ url: URL, etag: String?, session: URLSession) async -> FetchResult {
        var request = URLRequest(url: url)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 304 { return .notModified }
                guard (200..<300).contains(http.statusCode) else {
                    return .failure(http.statusCode == 404 ? L("주소를 찾을 수 없습니다. 비공개 주소를 다시 복사해 주세요.")
                                                          : L("서버 응답 %d", http.statusCode))
                }
            }
            if response.expectedContentLength > Int64(maxBytes) { return .failure(L("파일이 너무 큽니다.")) }
            var data = Data()
            data.reserveCapacity(max(0, min(Int(response.expectedContentLength), maxBytes)))
            var chunk = [UInt8]()
            chunk.reserveCapacity(64 * 1024)
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count == 64 * 1024 {
                    data.append(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true)
                    if data.count > maxBytes { return .failure(L("파일이 너무 큽니다.")) }
                }
            }
            data.append(contentsOf: chunk)
            guard data.count <= maxBytes else { return .failure(L("파일이 너무 큽니다.")) }
            guard let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  body.contains("BEGIN:VCALENDAR") else { return .failure(L("iCal 형식이 아닙니다.")) }
            let tag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
            return .text(body, etag: tag)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// 화면에 보일 캘린더 이름: 직접 붙인 이름 → 받아 온 이름 → 가린 주소.
    func title(of feed: CalendarFeed) -> String {
        if !feed.name.isEmpty { return feed.name }
        return statuses[feed.id]?.calendarName ?? feed.maskedURL
    }

    static var cacheFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clocky/Calendars", isDirectory: true)
    }

    static func cacheURL(_ id: UUID) -> URL {
        cacheFolder.appendingPathComponent("\(id.uuidString).ics")
    }
}
