import Foundation

@main
struct SilentSendTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        typealias Silent = ShadowSilentSend

        check(!Silent.isActive(enabled: false, mode: 0, from: 0, to: 420, minute: 100), "Off")
        check(Silent.isActive(enabled: true, mode: 0, from: 0, to: 420, minute: 900), "Always")
        check(Silent.isActive(enabled: true, mode: 9, from: 600, to: 660, minute: 900), "Unknown mode is always")

        // 0:00–7:00.
        check(Silent.isActive(enabled: true, mode: 1, from: 0, to: 420, minute: 0), "Night starts at 0:00")
        check(Silent.isActive(enabled: true, mode: 1, from: 0, to: 420, minute: 419), "6:59 is night")
        check(!Silent.isActive(enabled: true, mode: 1, from: 0, to: 420, minute: 420), "7:00 is day")
        check(!Silent.isActive(enabled: true, mode: 1, from: 0, to: 420, minute: 1439), "23:59 is day")

        // 23:00–8:00 crosses midnight.
        check(Silent.contains(minute: 1380, from: 1380, to: 480), "23:00 in")
        check(Silent.contains(minute: 30, from: 1380, to: 480), "0:30 in")
        check(!Silent.contains(minute: 480, from: 1380, to: 480), "8:00 out")
        check(!Silent.contains(minute: 720, from: 1380, to: 480), "Noon out")
        check(Silent.contains(minute: 720, from: 300, to: 300), "Equal ends: all day")

        check(Silent.clock(0) == "0:00" && Silent.clock(425) == "7:05" && Silent.clock(1439) == "23:59", "Clock")
        check(Silent.clock(1440) == "0:00" && Silent.clock(-60) == "23:00", "Clock wraps")
        check(Silent.rangeTitle(from: 1380, to: 480) == "23:00–8:00", "Range title")
        check(Silent.modeTitle(1) == "По расписанию" && Silent.modeTitle(0) == "Всегда", "Mode titles")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        // 2026-10-13 21:30 UTC = 0:30 at UTC+3.
        let date = Date(timeIntervalSince1970: 1_791_927_000)
        check(Silent.minuteOfDay(date, calendar: calendar) == 30, "Minute of day in the calendar's zone")

        print("Silent send: \(count) checks passed")
    }
}
