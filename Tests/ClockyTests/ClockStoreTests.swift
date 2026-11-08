import Foundation
import Testing
@testable import Clocky

/// 시험마다 따로 쓰고 지우는 설정 저장소.
private func makeDefaults() -> (UserDefaults, String) {
    let name = "ClockyTests-\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

private func encode<T: Encodable>(_ value: T) -> Data { try! JSONEncoder().encode(value) }

@Suite(.serialized) struct ClockStoreTests {
    @Test func 옛_설정을_첫_항목으로_옮긴다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("라면", forKey: "timerName")
        defaults.set(180, forKey: "timerDuration")
        defaults.set("기상", forKey: "alarmName")
        defaults.set(450, forKey: "alarmMinutes")
        defaults.set(true, forKey: "alarmEnabled")
        defaults.set(false, forKey: "alarmRepeats")

        let store = ClockStore(defaults: defaults)
        #expect(store.timers.map(\.name) == ["라면"])
        #expect(store.timers[0].duration == 180)
        #expect(store.alarms.count == 1)
        #expect(store.alarms[0].minutes == 450 && store.alarms[0].enabled && store.alarms[0].days.isEmpty)
        #expect(defaults.object(forKey: "timerName") == nil)
        #expect(defaults.data(forKey: "timers") != nil)
    }

    @Test func 언어가_박힌_기본_이름은_번호로_바꾼다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(encode([ClockStore.SavedTimer(id: UUID(), name: "타이머 3", duration: 60),
                             ClockStore.SavedTimer(id: UUID(), name: "라면", duration: 60)]), forKey: "timers")
        defaults.set(encode([ClockStore.SavedAlarm(id: UUID(), name: "Alarm 2", minutes: 60, enabled: false, repeats: true)]),
                     forKey: "alarms")
        let store = ClockStore(defaults: defaults)
        #expect(store.timers[0].name == "" && store.timers[0].number == 3)
        #expect(store.timers[1].name == "라면" && store.timers[1].number == 2)
        #expect(store.alarms[0].name == "" && store.alarms[0].number == 2 && store.alarms[0].days == AlarmItem.everyDay)

        let id = store.addTimer()
        #expect(store.timers.first { $0.id == id }?.number == 4)
        Localization.language = .english
        #expect(store.displayName(of: store.timers[0]) == "Timer 3")
        Localization.language = .korean
        #expect(store.displayName(of: store.timers[0]) == "타이머 3")
    }

    @Test func 도는_타이머와_멈춘_타이머를_저장하고_다시_읽는다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let a = store.timers[0].id
        let b = store.addTimer()
        store.setDuration(a, 120)
        store.start(a)
        store.start(b)
        store.pause(b)
        store.save()

        let again = ClockStore(defaults: defaults)
        #expect(again.timers[0].phase == .running)
        #expect(abs(again.timers[0].remaining(at: Date()) - 120) <= 1)
        #expect(again.timers[1].phase == .paused)
    }

    @Test func 요일을_고르면_그_요일에만_울린다() throws {
        var alarm = AlarmItem(number: 1, minutes: 8 * 60, days: AlarmItem.weekdays)
        // 2026-11-07은 토요일이다.
        let saturday = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12)))
        alarm.schedule(after: saturday)
        let next = try #require(alarm.next)
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute, .day], from: next)
        #expect(c.weekday == 2 && c.day == 9 && c.hour == 8 && c.minute == 0)

        alarm.days = AlarmItem.weekend
        alarm.schedule(after: saturday)
        #expect(Calendar.current.component(.day, from: alarm.next!) == 8)

        alarm.enabled = false
        alarm.schedule(after: saturday)
        #expect(alarm.next == nil)
    }

    @Test func 알람이_울리고_한_번_알람은_꺼지고_매일_알람은_다시_잡힌다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let once = store.addAlarm(minutes: 7 * 60)
        store.setAlarmDays(once, [])
        let daily = store.addAlarm(minutes: 8 * 60)
        store.forceNext(once, Date().addingTimeInterval(-1))
        store.tick()
        #expect(store.ringingAlarmIDs == [once])
        #expect(store.alarms.first { $0.id == once }?.enabled == false)
        #expect(store.alarms.first { $0.id == daily }?.next != nil)
        store.stopRinging()
        #expect(!store.isRinging && !store.isSounding)

        store.forceNext(daily, Date().addingTimeInterval(-1))
        store.tick()
        #expect(store.ringingAlarmIDs == [daily])
        #expect((store.alarms.first { $0.id == daily }?.next ?? .distantPast) > Date())
        store.stopRinging()
    }

    @Test func 다시_울림은_5분_뒤에_한_번_더_울린다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let alarm = store.addAlarm(minutes: 7 * 60)
        store.setAlarmDays(alarm, [])
        let timer = store.timers[0].id
        store.setDuration(timer, 1)
        store.start(timer)
        store.forceTimerEnd(timer, Date().addingTimeInterval(-0.1))
        store.forceNext(alarm, Date().addingTimeInterval(-1))
        store.tick()
        #expect(store.timers[0].phase == .ringing && store.ringingAlarmIDs == [alarm])

        store.snooze()
        #expect(!store.isRinging)
        #expect(store.timers[0].phase == .running)
        #expect(abs(store.timers[0].remaining(at: Date()) - 300) <= 1)
        let snoozed = store.alarms.first { $0.id == alarm }!
        #expect(!snoozed.enabled && snoozed.snoozeUntil != nil && snoozed.upcoming == snoozed.snoozeUntil)

        store.forceSnooze(alarm, Date().addingTimeInterval(-1))
        store.tick()
        #expect(store.ringingAlarmIDs == [alarm])
        #expect(store.alarms.first { $0.id == alarm }?.snoozeUntil == nil)
        store.stopRinging()
    }

    @Test func 할_일이_없으면_깨어나지_않고_있으면_다음_경계에_깨어난다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let now = Date()
        #expect(store.nextWake(after: now) == nil)

        let id = store.timers[0].id
        store.setDuration(id, 100)
        store.start(id)
        store.forceTimerEnd(id, now.addingTimeInterval(10.3))
        let wake = store.nextWake(after: now)!
        #expect(abs(wake.timeIntervalSince(now) - 0.3) < 0.01)

        store.reset(id)
        let alarm = store.addAlarm(minutes: 7 * 60)
        store.forceNext(alarm, now.addingTimeInterval(7200))
        let far = store.nextWake(after: now)!
        #expect(abs(far.timeIntervalSince(now) - 300) < 0.01)
        // 2시간 뒤 알람은 1시간 전부터 메뉴바에 초 단위로 남은 시간을 보여 주므로 그때 깨어나면 된다.
        // 1시간 안이면 초마다 깨어난다.
        store.forceNext(alarm, now.addingTimeInterval(200))
        #expect(store.nextWake(after: now)!.timeIntervalSince(now) <= 1)
    }

    @Test func 지운_항목을_되돌린다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        let second = store.addTimer()
        store.start(second)
        undo.beginUndoGrouping(); store.removeTimer(second); undo.endUndoGrouping()
        #expect(store.timers.count == 1)
        undo.undo()
        #expect(store.timers.count == 2 && store.timers[1].id == second && store.timers[1].phase == .running)
        store.undoManager = nil
        store.removeTimer(store.timers[0].id)
        store.removeTimer(store.timers[0].id)
        #expect(store.timers.count == 1)
    }

    @Test func 복제하고_여러_개를_한_번에_지우고_되돌린다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        let a = store.addAlarm(minutes: 7 * 60)
        store.renameAlarm(a, to: "기상")
        store.setAlarmDays(a, AlarmItem.weekdays)
        let copy = store.duplicateAlarm(a)!
        let c = store.alarms.first { $0.id == copy }!
        #expect(c.name == "기상" && c.days == AlarmItem.weekdays && c.number == 2 && store.alarms[1].id == copy)
        let t = store.duplicateTimer(store.timers[0].id)!
        #expect(store.timers.count == 2)

        undo.beginUndoGrouping()
        store.remove([a, copy, t])
        undo.endUndoGrouping()
        #expect(store.alarms.isEmpty && store.timers.count == 1)
        undo.undo()
        #expect(store.alarms.map(\.id) == [a, copy] && store.timers.count == 2)
    }

    @Test func 다시_울림을_취소한다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let a = store.addAlarm(minutes: 7 * 60)
        store.forceSnooze(a, Date().addingTimeInterval(60))
        #expect(store.alarms[0].upcoming == store.alarms[0].snoozeUntil)
        store.cancelSnooze(a)
        #expect(store.alarms[0].snoozeUntil == nil && store.alarms[0].upcoming == store.alarms[0].next)
    }

    @Test func 목록은_보기_검색_정렬을_따른다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let settings = ClockySettings()
        let model = ClockListModel(store: store, settings: settings)
        let late = store.addAlarm(minutes: 22 * 60); store.renameAlarm(late, to: "약 먹기")
        let early = store.addAlarm(minutes: 6 * 60); store.renameAlarm(early, to: "기상")
        let off = store.addAlarm(minutes: 5 * 60); store.renameAlarm(off, to: "운동"); store.setAlarmEnabled(off, false)
        store.forceNext(late, Date().addingTimeInterval(60))
        store.forceNext(early, Date().addingTimeInterval(3600))

        model.sort = .next
        #expect(model.alarms.map(\.id) == [late, early, off])
        model.sort = .time
        #expect(model.alarms.map(\.id) == [off, early, late])
        model.sort = .name
        #expect(model.alarms.map(\.id) == [early, late, off])
        model.sort = .added
        #expect(model.alarms.map(\.id) == [late, early, off])

        model.filter = .alarms
        #expect(model.timers.isEmpty && model.alarms.count == 3)
        model.filter = .timers
        #expect(model.alarms.isEmpty && model.timers.count == 1)
        model.filter = .all
        model.query = "기상"
        #expect(model.alarms.map(\.id) == [early] && model.timers.isEmpty)

        model.setEnabled(false, [late, early, store.timers[0].id])
        #expect(store.alarms.allSatisfy { !$0.enabled })
        model.addAlarm()
        #expect(model.query.isEmpty && model.selection.count == 1 && store.alarms.count == 4)
    }

    @Test func 설정한_미리_깜빡임_시간을_쓴다() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ClockStore(defaults: defaults)
        let id = store.timers[0].id
        store.setDuration(id, 100)
        store.start(id)
        store.forceTimerEnd(id, Date().addingTimeInterval(20))
        store.tick()
        #expect(!store.isWarning)
        store.warningSeconds = 30
        #expect(store.isWarning)
        store.warningSeconds = 0
        #expect(!store.isWarning)
    }

    @Test func 글자() {
        let now = Date()
        Localization.language = .korean
        #expect(remainingText(until: now.addingTimeInterval(9.2), from: now) == "10초")
        #expect(remainingText(until: now.addingTimeInterval(3 * 3600 + 61), from: now) == "3시간 2분")
        #expect(remainingText(until: now.addingTimeInterval(26 * 3600), from: now) == "1일 2시간")
        #expect(daysText(AlarmItem.everyDay) == "매일")
        #expect(daysText([]) == "한 번")
        #expect(daysText([2, 4, 6]) == "월 수 금")
        #expect(daysText([1, 7]) == "주말")
        #expect(clockText(3725) == "1:02:05")
        #expect(ClockStore.parse("90") == 5400)
        #expect(ClockStore.parse("5:30") == 330)
        #expect(ClockStore.parse("1:30:00") == 5400)
        #expect(ClockStore.parse("0") == nil && ClockStore.parse("a") == nil)
    }
}
