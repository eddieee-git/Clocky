import AppKit
import EventKit

/// Mac 캘린더 앱에 들어온 일정을 읽는다. 시스템 설정 → 인터넷 계정에 구글(회사 계정 포함)·Exchange 등을
/// 추가해 두면 그 일정도 여기로 들어온다. 비공개 iCal 주소를 쓸 수 없는 회사 계정을 위한 길이다.
///
/// 캘린더 접근은 켤 때 한 번 묻는다. 묻기 전에는 EKEventStore를 만들지 않는다.
final class MacCalendarSource: ObservableObject {
    /// 목록과 기록에서 Mac 캘린더 일정을 iCal 주소 일정과 구별하는 값.
    static let feedID = UUID(uuidString: "00000000-0000-4000-8000-0000000CA1E0")!

    struct Choice: Identifiable, Equatable {
        let id: String
        let title: String
        let account: String
        let color: NSColor
    }

    enum Access: Equatable {
        case notDetermined, granted, denied, writeOnly, restricted
    }

    @Published private(set) var access: Access
    @Published private(set) var calendars: [Choice] = []
    /// 일정이 바뀌면(캘린더 앱이 새로 받아 오는 등) 불린다.
    var onChange: () -> Void = {}

    private var store: EKEventStore?
    private var observer: NSObjectProtocol?

    init() {
        access = Self.currentAccess()
        if access == .granted { start() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    static func currentAccess() -> Access {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, *) {
            switch status {
            case .fullAccess: return .granted
            case .writeOnly: return .writeOnly
            case .denied: return .denied
            case .restricted: return .restricted
            default: return .notDetermined
            }
        } else {
            switch status {
            case .authorized: return .granted
            case .denied: return .denied
            case .restricted: return .restricted
            default: return .notDetermined
            }
        }
    }

    /// 아직 묻지 않았으면 macOS의 허용 창을 띄운다. 이미 정해졌으면 그 결과를 그대로 알려 준다.
    func requestAccess(_ completion: @escaping () -> Void = {}) {
        access = Self.currentAccess()
        guard access == .notDetermined else {
            if access == .granted { start() }
            completion()
            return
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        let done: (Bool, Error?) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.access = Self.currentAccess()
                if self.access == .granted { self.start() }
                completion()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
    }

    private func start() {
        if store == nil { store = EKEventStore() }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                self?.reloadCalendars()
                self?.onChange()
            }
        }
        reloadCalendars()
    }

    func reloadCalendars() {
        guard access == .granted, let store else { calendars = []; return }
        let list = store.calendars(for: .event).map {
            Choice(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "", color: $0.color ?? .systemBlue)
        }
        calendars = list.sorted { ($0.account, $0.title).0 == ($1.account, $1.title).0 ? $0.title < $1.title : $0.account < $1.account }
    }

    /// `range` 안에 시작하는 일정. `selected`가 nil이면 모든 캘린더.
    func events(in range: ClosedRange<Date>, selected: Set<String>?, includeAllDay: Bool, includeDeclined: Bool) -> [CalendarEvent] {
        guard access == .granted, let store else { return [] }
        let all = store.calendars(for: .event)
        let chosen = selected.map { ids in all.filter { ids.contains($0.calendarIdentifier) } } ?? all
        guard !chosen.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: range.lowerBound, end: range.upperBound, calendars: chosen)
        return store.events(matching: predicate).compactMap { event -> CalendarEvent? in
            guard range.contains(event.startDate) else { return nil }
            let myStatus = event.attendees?.first(where: \.isCurrentUser)?.participantStatus
            guard Self.include(isAllDay: event.isAllDay, isCanceled: event.status == .canceled,
                               declined: myStatus == .declined, includeAllDay: includeAllDay,
                               includeDeclined: includeDeclined) else { return nil }
            // 반복 일정은 같은 식별자를 나눠 쓰므로 시작 시각을 붙여 한 번씩 구별한다.
            let key = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
            let title = (event.title ?? "").isEmpty ? L("(제목 없음)") : event.title!
            return CalendarEvent(id: "mac|\(key)|\(Int(event.startDate.timeIntervalSince1970))", title: title,
                                 start: event.startDate, end: event.endDate ?? event.startDate,
                                 calendarName: event.calendar?.title ?? "", feedID: Self.feedID)
        }
        .sorted { $0.start < $1.start }
    }

    /// 취소된 일정은 늘 빼고, 종일 일정과 거절한 일정은 설정에 따라 뺀다.
    static func include(isAllDay: Bool, isCanceled: Bool, declined: Bool, includeAllDay: Bool, includeDeclined: Bool) -> Bool {
        if isCanceled { return false }
        if isAllDay && !includeAllDay { return false }
        if declined && !includeDeclined { return false }
        return true
    }

    /// 시스템 설정의 개인정보 보호 → 캘린더를 연다.
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 시스템 설정의 인터넷 계정을 연다. 구글 계정을 여기서 추가한다.
    static func openInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
