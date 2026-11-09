import Foundation
import Testing
@testable import Clocky

private func makeStore() -> (ClockStore, UserDefaults, String) {
    let name = "ClockyCalendarTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (ClockStore(defaults: defaults), defaults, name)
}

private func event(_ title: String, startsIn seconds: TimeInterval, feed: UUID = UUID()) -> CalendarEvent {
    let start = Date().addingTimeInterval(seconds)
    return CalendarEvent(id: "\(feed)|\(title)|\(Int(start.timeIntervalSince1970))", title: title, start: start,
                         end: start.addingTimeInterval(1800), calendarName: "업무", feedID: feed)
}

@Suite(.serialized) struct CalendarAlertTests {
    @Test func 알림_시각에_울리고_다시_켜도_또_울리지_않는다() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.calendarLead = 300
        let meeting = event("회의", startsIn: 299)
        store.setCalendarEvents([meeting])
        #expect(store.pendingEventAlerts.count == 1)
        store.tick()
        #expect(store.ringingEventIDs == [meeting.id] && store.mode == .alarm)
        #expect(store.ringingTitles == ["회의"])
        store.stopRinging()
        store.tick()
        #expect(!store.isRinging && store.pendingEventAlerts.isEmpty)
        store.save()

        let again = ClockStore(defaults: defaults)
        again.calendarLead = 300
        again.setCalendarEvents([meeting])
        again.tick()
        #expect(!again.isRinging)
    }

    @Test func 건너뛴_일정과_너무_늦은_일정은_울리지_않는다() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.calendarLead = 0
        let skipped = event("건너뜀", startsIn: -1)
        let late = event("늦음", startsIn: -20 * 60)
        store.setCalendarEvents([late, skipped])
        store.setEventSkipped(skipped.id, true)
        store.tick()
        #expect(!store.isRinging)
        #expect(store.pendingEventAlerts.isEmpty)
    }

    @Test func 다시_울림은_정한_시간_뒤에_한_번_더() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.calendarLead = 0
        store.snoozeMinutes = 10
        let call = event("통화", startsIn: -1)
        store.setCalendarEvents([call])
        store.tick()
        store.snooze()
        #expect(!store.isRinging)
        let snooze = store.eventSnoozes[call.id]!
        #expect(abs(snooze.timeIntervalSinceNow - 600) < 2)
        #expect(store.alertDate(of: call) == snooze)
        store.forceEventSnooze(call.id, Date().addingTimeInterval(-1))
        store.tick()
        #expect(store.ringingEventIDs == [call.id] && store.eventSnoozes[call.id] == nil)
        store.stopRinging()
    }

    @Test func 다음_알림은_알람과_일정_중_이른_것() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.calendarLead = 300
        let alarm = store.addAlarm(minutes: 7 * 60)
        store.forceNext(alarm, Date().addingTimeInterval(3600))
        store.setCalendarEvents([event("점심", startsIn: 1800)])
        #expect(store.nextAlert?.title == "점심")
        #expect(abs(store.nextAlert!.date.timeIntervalSinceNow - 1500) < 2)
        store.forceNext(alarm, Date().addingTimeInterval(600))
        #expect(store.nextAlert?.title == store.displayName(of: store.alarms[0]))
        // 10초 안으로 다가오면 깜빡인다.
        store.setCalendarEvents([event("곧", startsIn: 305)])
        store.tick()
        #expect(store.isWarning)
    }

    @Test func Mac_캘린더_일정_거르기() {
        func include(_ allDay: Bool = false, canceled: Bool = false, declined: Bool = false,
                     allDayOn: Bool = false, declinedOn: Bool = false) -> Bool {
            MacCalendarSource.include(isAllDay: allDay, isCanceled: canceled, declined: declined,
                                      includeAllDay: allDayOn, includeDeclined: declinedOn)
        }
        #expect(include())
        #expect(!include(canceled: true) && !include(canceled: true, allDayOn: true, declinedOn: true))
        #expect(!include(true) && include(true, allDayOn: true))
        #expect(!include(declined: true) && include(declined: true, declinedOn: true))
    }

    @Test func 주소는_https만_받는다() {
        func check(_ text: String) -> CalendarSync.AddError? {
            if case .failure(let error) = CalendarSync.normalizedURL(text) { return error }
            return nil
        }
        #expect(check("https://calendar.google.com/calendar/ical/me%40example.com/private-x/basic.ics") == nil)
        if case .success(let url) = CalendarSync.normalizedURL(" webcal://example.com/a.ics ") {
            #expect(url.absoluteString == "https://example.com/a.ics")
        } else {
            Issue.record("webcal 주소를 받지 못함")
        }
        #expect(check("http://example.com/a.ics") == .notSecure)
        #expect(check("http://127.0.0.1:8000/a.ics") == nil)
        #expect(check("아무 글") == .invalid)
        let feed = CalendarFeed(url: "https://calendar.google.com/calendar/ical/me%40example.com/private-secret/basic.ics")
        #expect(feed.maskedURL == "calendar.google.com/…/basic.ics")
        #expect(!feed.maskedURL.contains("secret"))
    }
}
