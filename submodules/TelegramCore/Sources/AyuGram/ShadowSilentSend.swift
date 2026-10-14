import Foundation

// Shadow: «Тихая отправка» (Призрак). Outgoing messages go without a sound at
// the recipient, like the stock «Отправить без звука», but by default.
// AyuGramSettings.silentSend turns it on, silentSendMode:
//
//   0 Всегда          every message
//   1 По расписанию   only between silentSendFrom and silentSendTo (minutes
//                     after local midnight); the window may cross midnight,
//                     e.g. 0:00–7:00 or 23:00–8:00
//
// Applied in EnqueueMessage (NotificationInfoMessageAttribute .muted). Works
// without the Ghost Mode master switch: it hides nothing, it only mutes.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowSilentSend {
    public static let modeAlways: Int32 = 0
    public static let modeSchedule: Int32 = 1
    public static let modes: [Int32] = [modeAlways, modeSchedule]

    public static let minutesPerDay: Int32 = 24 * 60
    public static let defaultFrom: Int32 = 0
    public static let defaultTo: Int32 = 7 * 60

    public static func modeTitle(_ mode: Int32) -> String {
        return normalizedMode(mode) == modeSchedule ? "По расписанию" : "Всегда"
    }

    public static func normalizedMode(_ mode: Int32) -> Int32 {
        return modes.contains(mode) ? mode : modeAlways
    }

    public static func normalizedMinute(_ minute: Int32) -> Int32 {
        let value = minute % minutesPerDay
        return value < 0 ? value + minutesPerDay : value
    }

    // "0:00", "7:30", "23:05".
    public static func clock(_ minute: Int32) -> String {
        let value = normalizedMinute(minute)
        let minutes = value % 60
        return "\(value / 60):\(minutes < 10 ? "0" : "")\(minutes)"
    }

    // "0:00–7:00".
    public static func rangeTitle(from: Int32, to: Int32) -> String {
        return "\(clock(from))–\(clock(to))"
    }

    // Whether `minute` (after local midnight) is inside [from, to). Equal ends
    // mean the whole day.
    public static func contains(minute: Int32, from: Int32, to: Int32) -> Bool {
        let minute = normalizedMinute(minute)
        let from = normalizedMinute(from)
        let to = normalizedMinute(to)
        if from == to {
            return true
        }
        if from < to {
            return minute >= from && minute < to
        }
        return minute >= from || minute < to
    }

    public static func isActive(enabled: Bool, mode: Int32, from: Int32, to: Int32, minute: Int32) -> Bool {
        guard enabled else {
            return false
        }
        if normalizedMode(mode) == modeAlways {
            return true
        }
        return contains(minute: minute, from: from, to: to)
    }

    // Minutes after local midnight of `date` in `calendar` (its time zone).
    public static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int32 {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Int32((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }
}
