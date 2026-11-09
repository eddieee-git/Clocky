import Foundation
import Testing
@testable import Clocky

private let feed = UUID()
private let seoul = TimeZone(identifier: "Asia/Seoul")!

private func date(_ text: String, _ zone: TimeZone = seoul) -> Date {
    ICalendar.dateValue(text, params: [:], defaultZone: zone)!.date
}

private func ics(_ events: String, name: String = "업무") -> String {
    """
    BEGIN:VCALENDAR\r
    VERSION:2.0\r
    X-WR-CALNAME:\(name)\r
    \(events)\r
    END:VCALENDAR\r
    """
}

private func read(_ text: String, from: String, to: String, options: ICalendar.Options = .init()) -> [CalendarEvent] {
    ICalendar.events(from: text, feedID: feed, fallbackName: "?", in: date(from)...date(to), options: options, defaultZone: seoul).events
}

@Suite struct ICalendarTests {
    @Test func 시간대와_UTC와_떠다니는_시각() {
        let text = ics("""
        BEGIN:VEVENT
        UID:a
        DTSTART;TZID=Asia/Seoul:20261110T100000
        DTEND;TZID=Asia/Seoul:20261110T110000
        SUMMARY:회의
        END:VEVENT
        BEGIN:VEVENT
        UID:b
        DTSTART:20261110T030000Z
        SUMMARY:UTC
        END:VEVENT
        BEGIN:VEVENT
        UID:c
        DTSTART;TZID=America/New_York:20261109T210000
        SUMMARY:뉴욕
        END:VEVENT
        """)
        let events = read(text, from: "20261110T000000", to: "20261111T000000")
        #expect(events.map(\.title) == ["회의", "뉴욕", "UTC"])
        #expect(events[0].start == date("20261110T100000"))
        #expect(events[0].end == date("20261110T110000"))
        #expect(events[0].calendarName == "업무")
        // 뉴욕 11월 9일 밤 9시(UTC-5) = 서울 11월 10일 오전 11시
        #expect(events[1].start == date("20261110T110000"))
        #expect(events[2].start == date("20261110T120000"))
    }

    @Test func 종일_일정은_빼거나_넣는다() {
        let text = ics("""
        BEGIN:VEVENT
        UID:allday
        DTSTART;VALUE=DATE:20261110
        DTEND;VALUE=DATE:20261111
        SUMMARY:휴가
        END:VEVENT
        """)
        #expect(read(text, from: "20261109T000000", to: "20261112T000000").isEmpty)
        var options = ICalendar.Options()
        options.includeAllDay = true
        let all = read(text, from: "20261109T000000", to: "20261112T000000", options: options)
        #expect(all.count == 1 && all[0].start == date("20261110T000000"))
    }

    @Test func 매주_여러_요일_횟수와_빠진_날() {
        // 2026-11-02(월)부터 월·수·금 10회, 11월 6일(금)은 빠짐
        let text = ics("""
        BEGIN:VEVENT
        UID:w
        DTSTART;TZID=Asia/Seoul:20261102T090000
        DURATION:PT30M
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=10
        EXDATE;TZID=Asia/Seoul:20261106T090000
        SUMMARY:스탠드업
        END:VEVENT
        """)
        let events = read(text, from: "20261101T000000", to: "20261231T000000")
        let days = events.map { Calendar(identifier: .gregorian).dateComponents(in: seoul, from: $0.start).day! }
        #expect(days == [2, 4, 9, 11, 13, 16, 18, 20, 23])
        #expect(events[0].end.timeIntervalSince(events[0].start) == 1800)
    }

    @Test func 매월_둘째_화요일과_마지막_금요일() {
        let text = ics("""
        BEGIN:VEVENT
        UID:m1
        DTSTART;TZID=Asia/Seoul:20260113T140000
        RRULE:FREQ=MONTHLY;BYDAY=2TU
        SUMMARY:둘째 화요일
        END:VEVENT
        BEGIN:VEVENT
        UID:m2
        DTSTART;TZID=Asia/Seoul:20260130T170000
        RRULE:FREQ=MONTHLY;BYDAY=-1FR
        SUMMARY:마지막 금요일
        END:VEVENT
        BEGIN:VEVENT
        UID:m3
        DTSTART;TZID=Asia/Seoul:20260131T080000
        RRULE:FREQ=MONTHLY
        SUMMARY:31일
        END:VEVENT
        """)
        let events = read(text, from: "20261101T000000", to: "20261231T235959")
        let pairs = events.map { ($0.title, Calendar(identifier: .gregorian).dateComponents(in: seoul, from: $0.start).day!) }
        #expect(pairs.filter { $0.0 == "둘째 화요일" }.map(\.1) == [10, 8])
        #expect(pairs.filter { $0.0 == "마지막 금요일" }.map(\.1) == [27, 25])
        // 11월에는 31일이 없어 건너뛴다.
        #expect(pairs.filter { $0.0 == "31일" }.map(\.1) == [31])
    }

    @Test func 매일_끝나는_날까지와_매년() {
        let text = ics("""
        BEGIN:VEVENT
        UID:d
        DTSTART;TZID=Asia/Seoul:20261108T070000
        RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20261113T000000Z
        SUMMARY:격일
        END:VEVENT
        BEGIN:VEVENT
        UID:y
        DTSTART;TZID=Asia/Seoul:20201111T120000
        RRULE:FREQ=YEARLY
        SUMMARY:기념일
        END:VEVENT
        """)
        let events = read(text, from: "20261101T000000", to: "20261130T000000")
        let days = events.filter { $0.title == "격일" }.map { Calendar(identifier: .gregorian).dateComponents(in: seoul, from: $0.start).day! }
        #expect(days == [8, 10, 12])
        #expect(events.filter { $0.title == "기념일" }.map(\.start) == [date("20261111T120000")])
    }

    @Test func 한_번만_바뀐_일정과_취소한_일정() {
        let text = ics("""
        BEGIN:VEVENT
        UID:r
        DTSTART;TZID=Asia/Seoul:20261109T100000
        RRULE:FREQ=DAILY;COUNT=4
        SUMMARY:정기
        END:VEVENT
        BEGIN:VEVENT
        UID:r
        RECURRENCE-ID;TZID=Asia/Seoul:20261110T100000
        DTSTART;TZID=Asia/Seoul:20261110T150000
        SUMMARY:정기(옮김)
        END:VEVENT
        BEGIN:VEVENT
        UID:r
        RECURRENCE-ID;TZID=Asia/Seoul:20261111T100000
        DTSTART;TZID=Asia/Seoul:20261111T100000
        STATUS:CANCELLED
        SUMMARY:정기
        END:VEVENT
        BEGIN:VEVENT
        UID:x
        DTSTART;TZID=Asia/Seoul:20261109T130000
        STATUS:CANCELLED
        SUMMARY:취소된 점심
        END:VEVENT
        """)
        let events = read(text, from: "20261109T000000", to: "20261113T000000")
        #expect(events.map(\.title) == ["정기", "정기(옮김)", "정기"])
        #expect(events.map(\.start) == [date("20261109T100000"), date("20261110T150000"), date("20261112T100000")])
    }

    @Test func 거절한_일정은_뺀다() {
        let text = ics("""
        BEGIN:VEVENT
        UID:i
        DTSTART;TZID=Asia/Seoul:20261110T100000
        SUMMARY:초대
        ATTENDEE;CN=나;PARTSTAT=DECLINED:mailto:Me@Example.com
        ATTENDEE;CN=다른 사람;PARTSTAT=ACCEPTED:mailto:other@example.com
        END:VEVENT
        BEGIN:VEVENT
        UID:j
        DTSTART;TZID=Asia/Seoul:20261110T110000
        SUMMARY:수락
        ATTENDEE;PARTSTAT=ACCEPTED:mailto:me@example.com
        END:VEVENT
        """)
        var options = ICalendar.Options()
        options.ownerEmail = "me@example.com"
        #expect(read(text, from: "20261110T000000", to: "20261111T000000", options: options).map(\.title) == ["수락"])
        options.includeDeclined = true
        #expect(read(text, from: "20261110T000000", to: "20261111T000000", options: options).count == 2)
    }

    @Test func 줄_이어_쓰기와_글자_되돌리기() {
        let text = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:f\r\nDTSTART:20261110T010000Z\r\nSUMMARY:아주 긴 제목\\, 쉼표\r\n  이어짐\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        let result = ICalendar.events(from: text, feedID: feed, fallbackName: "기본", in: date("20261110T000000")...date("20261111T000000"),
                                      options: .init(), defaultZone: seoul)
        #expect(result.events.map(\.title) == ["아주 긴 제목, 쉼표 이어짐"])
        #expect(result.events[0].calendarName == "기본" && result.calendarName == nil)
    }

    @Test func 서머타임이_바뀌어도_벽시계_시각을_지킨다() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let text = ics("""
        BEGIN:VEVENT
        UID:dst
        DTSTART;TZID=America/New_York:20261026T090000
        RRULE:FREQ=WEEKLY
        SUMMARY:주간 회의
        END:VEVENT
        """)
        let events = ICalendar.events(from: text, feedID: feed, fallbackName: "", in: date("20261025T000000")...date("20261111T000000"),
                                      options: .init(), defaultZone: seoul).events
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        #expect(events.count == 3)
        #expect(events.allSatisfy { calendar.component(.hour, from: $0.start) == 9 })
    }

    @Test func 구글_주소에서_주인_이메일() {
        let url = URL(string: "https://calendar.google.com/calendar/ical/me%40example.com/private-abc123/basic.ics")!
        #expect(ICalendar.ownerEmail(from: url) == "me@example.com")
        #expect(ICalendar.ownerEmail(from: URL(string: "https://example.com/feed.ics")!) == nil)
        #expect(ICalendar.duration("PT1H30M") == 5400)
        #expect(ICalendar.duration("P1DT2H") == 93600)
    }
}
