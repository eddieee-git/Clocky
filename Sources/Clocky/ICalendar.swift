import Foundation

/// 캘린더 일정 하나(반복 일정이면 그중 한 번). 같은 일정의 같은 시각이면 언제 읽어도 `id`가 같다.
struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarName: String
    let feedID: UUID
}

/// iCalendar(.ics) 글을 읽어 일정으로 바꾼다. 구글 캘린더의 비공개 iCal 주소가 주는 형식을 기준으로 한다.
///
/// 다루는 것: 줄 이어 쓰기, 시간대(TZID·UTC·떠다니는 시각), 종일 일정, 반복(RRULE의 FREQ·INTERVAL·COUNT·UNTIL·
/// BYDAY·BYMONTHDAY·BYMONTH), 빠진 날짜(EXDATE), 한 번만 바뀐 일정(RECURRENCE-ID), 취소, 참석 여부.
/// 다루지 않는 것: BYSETPOS, BYWEEKNO, BYYEARDAY, BYHOUR 같은 드문 반복 규칙. 그런 일정은 첫 시각만 쓴다.
enum ICalendar {
    struct Property {
        let name: String
        let params: [String: String]
        let value: String
    }

    struct Component {
        let name: String
        var properties: [Property] = []
        var children: [Component] = []

        func first(_ name: String) -> Property? { properties.first { $0.name == name } }
        func all(_ name: String) -> [Property] { properties.filter { $0.name == name } }
    }

    struct Options {
        var includeAllDay = false
        var includeDeclined = false
        /// 이 주소의 주인. 참석을 거절한 일정을 가려내는 데 쓴다.
        var ownerEmail: String?
    }

    /// 읽은 결과. 캘린더 이름은 X-WR-CALNAME에서 온다.
    struct Result {
        var calendarName: String?
        var events: [CalendarEvent]
    }

    // MARK: 글 → 구성 요소

    /// 75자에서 끊어 다음 줄을 공백으로 시작하는 "줄 이어 쓰기"를 되돌린다.
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }
        return lines
    }

    /// `NAME;PARAM=값;PARAM="값":본문` 한 줄을 나눈다. 따옴표 안의 `:`와 `;`는 구분자가 아니다.
    static func property(_ line: String) -> Property? {
        var inQuotes = false
        var colon: String.Index?
        for index in line.indices {
            let c = line[index]
            if c == "\"" { inQuotes.toggle() }
            if c == ":" && !inQuotes { colon = index; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        var parts: [String] = []
        var current = ""
        inQuotes = false
        for c in head {
            if c == "\"" { inQuotes.toggle(); continue }
            if c == ";" && !inQuotes { parts.append(current); current = ""; continue }
            current.append(c)
        }
        parts.append(current)
        guard let name = parts.first, !name.isEmpty else { return nil }
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { params[pair[0].uppercased()] = pair[1] }
        }
        return Property(name: name.uppercased(), params: params, value: value)
    }

    static func parse(_ text: String) -> [Component] {
        var stack: [Component] = []
        var roots: [Component] = []
        for line in unfold(text) {
            guard let property = property(line) else { continue }
            if property.name == "BEGIN" {
                stack.append(Component(name: property.value.uppercased()))
            } else if property.name == "END" {
                guard let done = stack.popLast() else { continue }
                if stack.isEmpty { roots.append(done) } else { stack[stack.count - 1].children.append(done) }
            } else if !stack.isEmpty {
                stack[stack.count - 1].properties.append(property)
            }
        }
        return roots
    }

    /// TEXT 값의 `\n`, `\,`, `\;`, `\\`를 되돌린다.
    static func unescape(_ value: String) -> String {
        var result = ""
        var escaping = false
        for c in value {
            if escaping {
                switch c {
                case "n", "N": result.append("\n")
                default: result.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                result.append(c)
            }
        }
        return result
    }

    // MARK: 날짜

    /// 날짜 값과 그 값이 속한 시간대. 종일 일정이면 `isDate`.
    struct DateValue {
        let date: Date
        let timeZone: TimeZone
        let isDate: Bool
    }

    static func dateValue(_ property: Property, defaultZone: TimeZone = .current) -> DateValue? {
        dateValue(property.value, params: property.params, defaultZone: defaultZone)
    }

    static func dateValue(_ raw: String, params: [String: String], defaultZone: TimeZone = .current) -> DateValue? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let isUTC = value.hasSuffix("Z")
        let digits = isUTC ? String(value.dropLast()) : value
        let zone: TimeZone
        if isUTC {
            zone = TimeZone(identifier: "UTC")!
        } else if let id = params["TZID"], let named = TimeZone(identifier: id) {
            zone = named
        } else {
            // 시간대가 없는 "떠다니는" 시각과 알 수 없는 TZID는 이 Mac의 시간대로 읽는다.
            zone = defaultZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func number(_ range: Range<Int>) -> Int? {
            guard digits.count >= range.upperBound else { return nil }
            let start = digits.index(digits.startIndex, offsetBy: range.lowerBound)
            let end = digits.index(digits.startIndex, offsetBy: range.upperBound)
            return Int(digits[start..<end])
        }
        guard let year = number(0..<4), let month = number(4..<6), let day = number(6..<8) else { return nil }
        if params["VALUE"] == "DATE" || digits.count == 8 {
            // 종일 일정은 이 Mac 기준 그날 0시.
            var local = Calendar(identifier: .gregorian)
            local.timeZone = defaultZone
            guard let date = local.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            return DateValue(date: date, timeZone: defaultZone, isDate: true)
        }
        guard digits.count >= 15, digits[digits.index(digits.startIndex, offsetBy: 8)] == "T",
              let hour = number(9..<11), let minute = number(11..<13), let second = number(13..<15),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                            hour: hour, minute: minute, second: second)) else { return nil }
        return DateValue(date: date, timeZone: zone, isDate: false)
    }

    /// "PT1H30M", "P1D" 같은 기간.
    static func duration(_ value: String) -> TimeInterval? {
        var text = value.uppercased()
        var sign: Double = 1
        if text.hasPrefix("-") { sign = -1; text.removeFirst() } else if text.hasPrefix("+") { text.removeFirst() }
        guard text.hasPrefix("P") else { return nil }
        text.removeFirst()
        var total: Double = 0
        var number = ""
        var inTime = false
        for c in text {
            if c == "T" { inTime = true; continue }
            if c.isNumber { number.append(c); continue }
            guard let n = Double(number) else { return nil }
            number = ""
            switch (c, inTime) {
            case ("W", _): total += n * 7 * 86400
            case ("D", _): total += n * 86400
            case ("H", true): total += n * 3600
            case ("M", true): total += n * 60
            case ("S", true): total += n
            default: return nil
            }
        }
        return sign * total
    }

    // MARK: 반복

    struct Rule {
        enum Frequency: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }
        var frequency: Frequency
        var interval = 1
        var count: Int?
        var until: Date?
        /// (몇째, 요일). 요일은 Calendar 번호(일=1). 몇째가 없으면 모든 그 요일.
        var byDay: [(ordinal: Int?, weekday: Int)] = []
        var byMonthDay: [Int] = []
        var byMonth: [Int] = []
        /// 지원하지 않는 규칙이 섞였는지.
        var unsupported = false
    }

    static let weekdayCodes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    static func rule(_ value: String, defaultZone: TimeZone) -> Rule? {
        var fields: [String: String] = [:]
        for part in value.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { fields[pair[0].uppercased()] = pair[1].uppercased() }
        }
        guard let frequency = fields["FREQ"].flatMap(Rule.Frequency.init) else { return nil }
        var rule = Rule(frequency: frequency)
        rule.interval = max(1, fields["INTERVAL"].flatMap { Int($0) } ?? 1)
        rule.count = fields["COUNT"].flatMap { Int($0) }
        if let until = fields["UNTIL"] { rule.until = dateValue(until, params: [:], defaultZone: defaultZone)?.date }
        if let days = fields["BYDAY"] {
            for code in days.split(separator: ",") {
                let text = String(code)
                guard let weekday = weekdayCodes[String(text.suffix(2))] else { continue }
                let prefix = text.dropLast(2)
                rule.byDay.append((prefix.isEmpty ? nil : Int(prefix), weekday))
            }
        }
        rule.byMonthDay = fields["BYMONTHDAY"].map { $0.split(separator: ",").compactMap { Int($0) } } ?? []
        rule.byMonth = fields["BYMONTH"].map { $0.split(separator: ",").compactMap { Int($0) } } ?? []
        rule.unsupported = ["BYSETPOS", "BYWEEKNO", "BYYEARDAY", "BYHOUR", "BYMINUTE", "BYSECOND"].contains { fields[$0] != nil }
            || (frequency != .daily && frequency != .weekly && frequency != .monthly && frequency != .yearly)
        return rule
    }

    /// 반복 일정의 시작 시각들 가운데 `range` 안에 드는 것. 시간대는 일정의 것으로 셈해서 서머타임이 바뀌어도 벽시계 시각이 같다.
    static func occurrences(start: DateValue, rule: Rule, in range: ClosedRange<Date>, excluded: Set<Date>) -> [Date] {
        if rule.unsupported {
            return range.contains(start.date) && !excluded.contains(start.date) ? [start.date] : []
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = start.timeZone
        calendar.firstWeekday = 2 // iCalendar의 기본 주 시작은 월요일
        let base = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: start.date)

        func make(year: Int, month: Int, day: Int) -> Date? {
            var c = DateComponents(year: year, month: month, day: day, hour: base.hour, minute: base.minute, second: base.second)
            c.calendar = calendar
            // 2월 30일처럼 없는 날은 건너뛴다.
            guard c.isValidDate(in: calendar) else { return nil }
            return calendar.date(from: c)
        }
        func daysInMonth(year: Int, month: Int) -> Int {
            guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
            return calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        }
        /// 그 달에서 규칙에 맞는 날들.
        func days(year: Int, month: Int) -> [Int] {
            let count = daysInMonth(year: year, month: month)
            guard count > 0 else { return [] }
            var result = Set<Int>()
            if !rule.byMonthDay.isEmpty {
                for d in rule.byMonthDay {
                    let day = d > 0 ? d : count + d + 1
                    if (1...count).contains(day) { result.insert(day) }
                }
            }
            if !rule.byDay.isEmpty {
                let firstWeekday = calendar.component(.weekday, from: calendar.date(from: DateComponents(year: year, month: month, day: 1))!)
                for (ordinal, weekday) in rule.byDay {
                    let firstMatch = (weekday - firstWeekday + 7) % 7 + 1
                    let matches = Array(stride(from: firstMatch, through: count, by: 7))
                    if let ordinal {
                        let index = ordinal > 0 ? ordinal - 1 : matches.count + ordinal
                        if matches.indices.contains(index) { result.insert(matches[index]) }
                    } else {
                        matches.forEach { result.insert($0) }
                    }
                }
                // 날짜와 요일이 함께 있으면 둘 다 맞는 날만.
                if !rule.byMonthDay.isEmpty {
                    let byDate = Set(rule.byMonthDay.map { $0 > 0 ? $0 : count + $0 + 1 })
                    result = result.intersection(byDate)
                }
            }
            if rule.byMonthDay.isEmpty && rule.byDay.isEmpty, let day = base.day, day <= count { result.insert(day) }
            return result.sorted()
        }

        var found: [Date] = []
        var produced = 0
        var period = 0
        // 아주 오래된 매일 일정도 몇십 년 안에서 끝나도록 한도를 둔다.
        while period < 40_000 {
            var candidates: [Date] = []
            /// 이번 주기가 시작하는 때. 범위를 지나면 더 볼 것이 없다.
            var nominal: Date?
            switch rule.frequency {
            case .daily:
                if let date = calendar.date(byAdding: .day, value: period * rule.interval, to: start.date) {
                    nominal = date
                    let c = calendar.dateComponents([.month, .weekday], from: date)
                    let monthOK = rule.byMonth.isEmpty || rule.byMonth.contains(c.month ?? 0)
                    let dayOK = rule.byDay.isEmpty || rule.byDay.contains { $0.weekday == c.weekday }
                    if monthOK && dayOK { candidates = [date] }
                }
            case .weekly:
                guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: start.date)?.start,
                      let thisWeek = calendar.date(byAdding: .weekOfYear, value: period * rule.interval, to: weekStart) else { break }
                nominal = thisWeek
                let weekdays = rule.byDay.isEmpty ? [base.weekday ?? 2] : rule.byDay.map(\.weekday)
                for weekday in Set(weekdays) {
                    let offset = (weekday - 2 + 7) % 7
                    guard let day = calendar.date(byAdding: .day, value: offset, to: thisWeek) else { continue }
                    let c = calendar.dateComponents([.year, .month, .day], from: day)
                    if let date = make(year: c.year!, month: c.month!, day: c.day!),
                       rule.byMonth.isEmpty || rule.byMonth.contains(c.month!) {
                        candidates.append(date)
                    }
                }
            case .monthly:
                let total = (base.year! * 12 + base.month! - 1) + period * rule.interval
                let (year, month) = (total / 12, total % 12 + 1)
                nominal = calendar.date(from: DateComponents(year: year, month: month, day: 1))
                if rule.byMonth.isEmpty || rule.byMonth.contains(month) {
                    candidates = days(year: year, month: month).compactMap { make(year: year, month: month, day: $0) }
                }
            case .yearly:
                let year = base.year! + period * rule.interval
                nominal = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
                let months = rule.byMonth.isEmpty ? [base.month!] : rule.byMonth.sorted()
                for month in months {
                    // 매년 같은 날이면 그 날만, 요일·날짜 규칙이 있으면 그 달에서 찾는다.
                    if rule.byDay.isEmpty && rule.byMonthDay.isEmpty {
                        if let date = make(year: year, month: month, day: base.day!) { candidates.append(date) }
                    } else {
                        candidates += days(year: year, month: month).compactMap { make(year: year, month: month, day: $0) }
                    }
                }
            }
            for date in candidates.sorted() where date >= start.date {
                if let until = rule.until, date > until { return found }
                produced += 1
                if let count = rule.count, produced > count { return found }
                if range.contains(date) && !excluded.contains(date) { found.append(date) }
                if date > range.upperBound { return found }
            }
            // 이번 주기가 이미 범위를 지났으면 그만.
            if let nominal, nominal > range.upperBound { return found }
            if let until = rule.until, let nominal, nominal > until { return found }
            period += 1
        }
        return found
    }

    // MARK: 일정 고르기

    /// `range` 안에 시작하는 일정을 모두 꺼낸다.
    static func events(from text: String, feedID: UUID, fallbackName: String, in range: ClosedRange<Date>,
                       options: Options, defaultZone: TimeZone = .current) -> Result {
        let roots = parse(text)
        guard let calendar = roots.first(where: { $0.name == "VCALENDAR" }) else { return Result(calendarName: nil, events: []) }
        let calendarName = calendar.first("X-WR-CALNAME").map { unescape($0.value) }
        let name = calendarName ?? fallbackName
        let vevents = calendar.children.filter { $0.name == "VEVENT" }

        // 한 번만 바뀐 일정: UID와 원래 시작 시각으로 찾는다.
        var overrides: [String: [Date: Component]] = [:]
        for event in vevents {
            guard let uid = event.first("UID")?.value, let rid = event.first("RECURRENCE-ID"),
                  let original = dateValue(rid, defaultZone: defaultZone)?.date else { continue }
            overrides[uid, default: [:]][original] = event
        }

        var result: [CalendarEvent] = []
        func add(_ event: Component, uid: String, start: Date, duration: TimeInterval) {
            guard include(event, options: options) else { return }
            let title = event.first("SUMMARY").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 } ?? L("(제목 없음)")
            let id = "\(feedID.uuidString)|\(uid)|\(Int(start.timeIntervalSince1970))"
            result.append(CalendarEvent(id: id, title: title, start: start, end: start.addingTimeInterval(duration),
                                        calendarName: name, feedID: feedID))
        }

        for event in vevents {
            guard let uid = event.first("UID")?.value,
                  let startProperty = event.first("DTSTART"),
                  let start = dateValue(startProperty, defaultZone: defaultZone) else { continue }
            if start.isDate && !options.includeAllDay { continue }
            let end = event.first("DTEND").flatMap { dateValue($0, defaultZone: defaultZone) }?.date
            let duration = end.map { $0.timeIntervalSince(start.date) }
                ?? event.first("DURATION").flatMap { self.duration($0.value) }
                ?? (start.isDate ? 86400 : 0)

            if event.first("RECURRENCE-ID") != nil {
                // 바뀐 한 번은 그 자체로 하나의 일정이다.
                if range.contains(start.date) { add(event, uid: uid, start: start.date, duration: duration) }
                continue
            }
            guard let ruleValue = event.first("RRULE")?.value, let rule = rule(ruleValue, defaultZone: defaultZone) else {
                if range.contains(start.date) { add(event, uid: uid, start: start.date, duration: duration) }
                continue
            }
            var excluded = Set<Date>()
            for exdate in event.all("EXDATE") {
                for part in exdate.value.split(separator: ",") {
                    if let date = dateValue(String(part), params: exdate.params, defaultZone: defaultZone)?.date { excluded.insert(date) }
                }
            }
            if let changed = overrides[uid]?.keys { excluded.formUnion(changed) }
            for date in occurrences(start: start, rule: rule, in: range, excluded: excluded) {
                add(event, uid: uid, start: date, duration: duration)
            }
        }
        return Result(calendarName: calendarName, events: result.sorted { $0.start < $1.start })
    }

    /// 취소된 일정, 거절한 일정, (설정에 따라) 시간이 없는 일정을 뺀다.
    private static func include(_ event: Component, options: Options) -> Bool {
        if event.first("STATUS")?.value.uppercased() == "CANCELLED" { return false }
        if !options.includeDeclined, let owner = options.ownerEmail?.lowercased() {
            let declined = event.all("ATTENDEE").contains { attendee in
                let email = attendee.value.lowercased().replacingOccurrences(of: "mailto:", with: "")
                return email == owner && attendee.params["PARTSTAT"]?.uppercased() == "DECLINED"
            }
            if declined { return false }
        }
        return true
    }

    /// 구글 비공개 주소 `.../calendar/ical/<이메일>/private-.../basic.ics`에서 이메일을 꺼낸다.
    static func ownerEmail(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "ical"), parts.indices.contains(index + 1) else { return nil }
        let id = parts[index + 1].removingPercentEncoding ?? parts[index + 1]
        return id.contains("@") ? id : nil
    }
}
