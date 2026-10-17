import Foundation

// Shadow: скрытая подмена баланса звёзд (только на экране, на сервер ничего не
// уходит). Двойной тап по балансу на экране «Звёзды Telegram» открывает меню:
// «Настоящий баланс» или «Своё число». Нигде в настройках не показывается.
//
// Хранится не само число, а сдвиг от настоящего баланса (в нано-звёздах), на
// аккаунт, в UserDefaults: показанный баланс = настоящий + сдвиг, поэтому он
// двигается вместе с настоящим (поставил реакцию за 1★ — стало на 1 меньше).
// Применяется в StarsContext (state / currentState), то есть везде, где
// показывается баланс звёзд (не TON).
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowStarsBalance {
    public static let nanosPerStar: Int64 = 1_000_000_000

    public static let didChangeNotification = Notification.Name("ShadowStarsBalanceDidChange")

    static func key(accountPeerId: Int64) -> String {
        return "shadow.starsBalanceOffset.\(accountPeerId)"
    }

    public static func nanos(value: Int64, nanos: Int32) -> Int64 {
        return value * nanosPerStar + Int64(nanos)
    }

    // Back to (value, nanos) the way the server sends it: nanos has the sign
    // of value and |nanos| < 1e9.
    public static func parts(_ total: Int64) -> (value: Int64, nanos: Int32) {
        return (total / nanosPerStar, Int32(total % nanosPerStar))
    }

    // What to show for `real`; never below zero.
    public static func displayed(real: Int64, offset: Int64?) -> Int64 {
        guard let offset else {
            return real
        }
        return max(0, real + offset)
    }

    // "1337", "228.55", "228,55", "1 337" → нано-звёзды; nil — не число или
    // меньше нуля. Больше двух знаков после запятой отбрасываются.
    public static func parse(_ text: String) -> Int64? {
        var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        string = string.replacingOccurrences(of: " ", with: "")
        string = string.replacingOccurrences(of: "\u{00A0}", with: "")
        string = string.replacingOccurrences(of: ",", with: ".")
        if string.isEmpty {
            return nil
        }
        let pieces = string.split(separator: ".", omittingEmptySubsequences: false)
        if pieces.count > 2 {
            return nil
        }
        let whole = String(pieces[0])
        let fraction = pieces.count == 2 ? String(pieces[1].prefix(2)) : ""
        if whole.isEmpty && fraction.isEmpty {
            return nil
        }
        let digits = CharacterSet(charactersIn: "0123456789")
        if !(whole + fraction).unicodeScalars.allSatisfy({ digits.contains($0) }) {
            return nil
        }
        if whole.count > 12 {
            return nil
        }
        let value = Int64(whole.isEmpty ? "0" : whole) ?? 0
        var fractionNanos: Int64 = 0
        if !fraction.isEmpty {
            let padded = fraction.padding(toLength: 9, withPad: "0", startingAt: 0)
            fractionNanos = Int64(padded) ?? 0
        }
        return value * nanosPerStar + fractionNanos
    }

    public static func offset(accountPeerId: Int64, defaults: UserDefaults = .standard) -> Int64? {
        guard defaults.object(forKey: key(accountPeerId: accountPeerId)) != nil else {
            return nil
        }
        return (defaults.object(forKey: key(accountPeerId: accountPeerId)) as? NSNumber)?.int64Value
    }

    // `displayed` nil — снова настоящий баланс.
    public static func set(displayed: Int64?, real: Int64, accountPeerId: Int64, defaults: UserDefaults = .standard) {
        if let displayed {
            defaults.set(NSNumber(value: displayed - real), forKey: key(accountPeerId: accountPeerId))
        } else {
            defaults.removeObject(forKey: key(accountPeerId: accountPeerId))
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil, userInfo: ["accountPeerId": accountPeerId])
    }
}
