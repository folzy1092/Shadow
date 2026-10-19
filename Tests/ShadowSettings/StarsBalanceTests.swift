import Foundation

@main
struct StarsBalanceTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        typealias Balance = ShadowStarsBalance
        let star = Balance.nanosPerStar

        check(Balance.parse("1337") == 1337 * star, "Whole number")
        check(Balance.parse("228.55") == 228 * star + 550_000_000, "Dot fraction")
        check(Balance.parse("228,55") == 228 * star + 550_000_000, "Comma fraction")
        check(Balance.parse(" 1 337 ") == 1337 * star, "Spaces")
        check(Balance.parse("0.5") == star / 2, "Half")
        check(Balance.parse(".75") == 750_000_000, "Leading dot")
        check(Balance.parse("1.999") == star + 990_000_000, "Extra digits dropped")
        check(Balance.parse("") == nil && Balance.parse(".") == nil, "Empty")
        check(Balance.parse("-5") == nil && Balance.parse("abc") == nil && Balance.parse("1.2.3") == nil, "Garbage")

        check(Balance.nanos(value: 1144, nanos: 750_000_000) == 1144 * star + 750_000_000, "To nanos")
        let parts = Balance.parts(1144 * star + 750_000_000)
        check(parts.value == 1144 && parts.nanos == 750_000_000, "To parts")
        let negative = Balance.parts(-(star + 250_000_000))
        check(negative.value == -1 && negative.nanos == -250_000_000, "Negative parts")

        let real = Balance.nanos(value: 1144, nanos: 750_000_000)
        check(Balance.displayed(real: real, offset: nil) == real, "No override")

        let defaults = UserDefaults(suiteName: "shadow-stars-balance-tests")!
        defaults.removePersistentDomain(forName: "shadow-stars-balance-tests")
        check(Balance.offset(accountPeerId: 7, defaults: defaults) == nil, "Nothing stored")
        Balance.set(displayed: 1337 * star, real: real, accountPeerId: 7, defaults: defaults)
        let offset = Balance.offset(accountPeerId: 7, defaults: defaults)
        check(Balance.displayed(real: real, offset: offset) == 1337 * star, "Shows the chosen number")
        check(Balance.displayed(real: real - star, offset: offset) == 1336 * star, "Moves with real balance")
        check(Balance.offset(accountPeerId: 8, defaults: defaults) == nil, "Per account")
        Balance.set(displayed: 0, real: real, accountPeerId: 7, defaults: defaults)
        check(Balance.displayed(real: real - star, offset: Balance.offset(accountPeerId: 7, defaults: defaults)) == 0, "Never below zero")
        check(Balance.isActive(accountPeerId: 7, defaults: defaults), "Active while set")
        Balance.set(displayed: 1000 * star, real: real, accountPeerId: 7, defaults: defaults)
        Balance.adjust(by: 535 * star, accountPeerId: 7, defaults: defaults)
        check(Balance.displayed(real: real, offset: Balance.offset(accountPeerId: 7, defaults: defaults)) == 1535 * star, "Fake credit")
        Balance.adjust(by: -100 * star, accountPeerId: 7, defaults: defaults)
        check(Balance.displayed(real: real, offset: Balance.offset(accountPeerId: 7, defaults: defaults)) == 1435 * star, "Fake gift sent")
        Balance.adjust(by: 5 * star, accountPeerId: 9, defaults: defaults)
        check(Balance.displayed(real: real, offset: Balance.offset(accountPeerId: 9, defaults: defaults)) == real + 5 * star, "Adjust without override")
        Balance.set(displayed: nil, real: real, accountPeerId: 7, defaults: defaults)
        check(Balance.offset(accountPeerId: 7, defaults: defaults) == nil, "Reset")
        defaults.removePersistentDomain(forName: "shadow-stars-balance-tests")

        print("StarsBalanceTests: \(count) checks passed")
    }
}
