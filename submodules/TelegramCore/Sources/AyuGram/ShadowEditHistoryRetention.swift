import Foundation

// Shadow: how long the stored edit versions of a message are kept. The age limit
// of the saved media ("Срок хранения") already removed the kept deleted messages
// and their files, but the edit versions live in an attribute of a message that
// is still in the chat, so nothing ever removed them. AyuGramSettings.
// editHistoryRetention picks the period, as a choice number:
//
//   0      Как у удалённых   the saved media's period (mediaAutoCleanInterval)
//   1      Никогда           the versions are kept until cleared by hand
//   2...9  a fixed period, 1 day to 1 year
//
// Every version ages from the moment it was replaced (SavedMessageEditVersion.
// date), so a message keeps its recent versions and loses the old ones.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowEditHistoryRetention {
    public static let followDeleted: Int32 = 0
    public static let never: Int32 = 1
    public static let periods: [Int32] = [86400, 259200, 604800, 1209600, 2592000, 7776000, 15552000, 31536000]
    public static let choices: [Int32] = [Int32](0 ..< Int32(2 + periods.count))

    public static func normalized(_ choice: Int32) -> Int32 {
        return choices.contains(choice) ? choice : followDeleted
    }

    public static func title(_ choice: Int32) -> String {
        switch normalized(choice) {
        case followDeleted:
            return "Как у удалённых"
        case never:
            return "Никогда"
        default:
            return periodTitle(periods[Int(normalized(choice)) - 2])
        }
    }

    public static func periodTitle(_ seconds: Int32) -> String {
        switch seconds {
        case 86400:
            return "1 день"
        case 259200:
            return "3 дня"
        case 604800:
            return "7 дней"
        case 1209600:
            return "14 дней"
        case 2592000:
            return "30 дней"
        case 7776000:
            return "90 дней"
        case 15552000:
            return "180 дней"
        case 31536000:
            return "1 год"
        default:
            return "Никогда"
        }
    }

    // The age in seconds after which a version goes; 0 keeps them all.
    public static func maxAge(choice: Int32, deletedMaxAge: Int32) -> Int32 {
        switch normalized(choice) {
        case followDeleted:
            return max(0, deletedMaxAge)
        case never:
            return 0
        default:
            return periods[Int(normalized(choice)) - 2]
        }
    }

    public static func isExpired(versionDate: Int32, now: Int32, maxAge: Int32) -> Bool {
        return maxAge > 0 && now - versionDate >= maxAge
    }
}
