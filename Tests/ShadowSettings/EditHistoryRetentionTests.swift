import Foundation

@main
struct EditHistoryRetentionTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        let day: Int32 = 86400
        // Choices: like deleted, never, then eight periods.
        check(ShadowEditHistoryRetention.choices == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "Ten choices")
        check(ShadowEditHistoryRetention.title(0) == "Как у удалённых", "Default title")
        check(ShadowEditHistoryRetention.title(1) == "Никогда", "Never title")
        check(ShadowEditHistoryRetention.title(2) == "1 день", "First period title")
        check(ShadowEditHistoryRetention.title(9) == "1 год", "Last period title")
        check(ShadowEditHistoryRetention.title(77) == "Как у удалённых", "Unknown choice reads as the default")
        check(ShadowEditHistoryRetention.normalized(-3) == 0 && ShadowEditHistoryRetention.normalized(10) == 0, "Out-of-range choices fall back")
        check(ShadowEditHistoryRetention.normalized(9) == 9, "Valid choice stays")

        // Periods.
        check(ShadowEditHistoryRetention.maxAge(choice: 0, deletedMaxAge: day) == day, "Follows the deleted period (1 day)")
        check(ShadowEditHistoryRetention.maxAge(choice: 0, deletedMaxAge: 0) == 0, "Follows 'never' of the deleted period")
        check(ShadowEditHistoryRetention.maxAge(choice: 0, deletedMaxAge: -5) == 0, "A negative deleted period keeps everything")
        check(ShadowEditHistoryRetention.maxAge(choice: 1, deletedMaxAge: day) == 0, "Never keeps everything whatever the deleted period")
        check(ShadowEditHistoryRetention.maxAge(choice: 2, deletedMaxAge: 0) == day, "Own period beats a missing deleted period")
        check(ShadowEditHistoryRetention.maxAge(choice: 4, deletedMaxAge: day) == 604800, "Choice 4 is 7 days")
        check(ShadowEditHistoryRetention.maxAge(choice: 9, deletedMaxAge: day) == 31536000, "Choice 9 is a year")
        check(ShadowEditHistoryRetention.maxAge(choice: 55, deletedMaxAge: day) == day, "Unknown choice follows the deleted period")

        // Expiry.
        let now: Int32 = 1_000_000
        check(ShadowEditHistoryRetention.isExpired(versionDate: now - day, now: now, maxAge: day), "Exactly a day old is expired")
        check(!ShadowEditHistoryRetention.isExpired(versionDate: now - day + 1, now: now, maxAge: day), "A second younger is kept")
        check(!ShadowEditHistoryRetention.isExpired(versionDate: 0, now: now, maxAge: 0), "No period: nothing expires")
        check(ShadowEditHistoryRetention.isExpired(versionDate: 0, now: now, maxAge: day), "A version without a date is old")

        print("EditHistoryRetentionTests: \(count) checks passed")
    }
}
