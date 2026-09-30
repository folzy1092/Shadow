import Foundation

// One instance per preview. Telegram entity offsets and these ranges are UTF-16.
public final class ShadowScreenshotAnonymizer {
    public struct Replacement {
        public let range: NSRange
        public let text: String
        public init(range: NSRange, text: String) {
            self.range = range
            self.text = text
        }
    }
    private var labels: [Int64: String] = [:]
    private var tokens: [String: String] = [:]
    private var visibleTokens = Set<String>()
    private var phones = Set<String>()
    public init() {}

    public func label(for id: Int64) -> String {
        if let value = self.labels[id] { return value }
        let value = "Участник \(self.labels.count + 1)"
        self.labels[id] = value
        return value
    }

    @discardableResult
    public func register(id: Int64, names: [String], usernames: [String], phone: String?, redact: Bool = true) -> String {
        let label = self.label(for: id)
        let normalizedPhone = phone?.filter { "0123456789".contains($0) }
        if !redact {
            self.visibleTokens.formUnion((names + usernames.map { "@" + $0 } + [normalizedPhone].compactMap { $0 }).map { $0.lowercased() })
            return label
        }
        for name in names where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.tokens[name] = label }
        for username in usernames where !username.isEmpty {
            self.tokens["@" + username] = label
            for domain in ["t.me/", "telegram.me/"] {
                for prefix in ["", "https://", "http://"] { self.tokens[prefix + domain + username] = "[ссылка скрыта]" }
            }
        }
        if let normalizedPhone, !normalizedPhone.isEmpty { self.phones.insert(normalizedPhone) }
        return label
    }

    public func redact(_ text: String, replacements: [Replacement] = [], redactUnknownIdentifiers: Bool = true) -> String {
        let source = text as NSString
        var candidates = replacements.filter {
            $0.range.location >= 0 && $0.range.length > 0 && $0.range.location <= source.length && $0.range.length <= source.length - $0.range.location
        }
        func collect(_ pattern: String, value: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
            candidates.append(contentsOf: regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { Replacement(range: $0.range, text: value) })
        }
        // Match original text once: replacement labels must not be matched again.
        // Ambiguous plain names shared with a visible person are left alone.
        for token in self.tokens.keys.sorted() where !self.visibleTokens.contains(token.lowercased()) {
            collect("(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: token) + "(?![\\p{L}\\p{N}_])", value: self.tokens[token] ?? "[скрыто]")
        }
        for phone in self.phones.sorted() where phone.count >= 7 && !self.visibleTokens.contains(phone) {
            let digits = phone.map { String($0) }.joined(separator: "[ ()\\.-]{0,4}")
            collect("(?<![\\p{L}\\p{N}])\\+?" + digits + "(?![\\p{L}\\p{N}])", value: "[номер скрыт]")
        }
        if redactUnknownIdentifiers {
            collect("(?:https?://)?(?:t\\.me|telegram\\.me)/[^\\s<>]+", value: "[ссылка скрыта]")
            collect("(?<![\\p{L}\\p{N}_])@[A-Za-z][A-Za-z0-9_]{3,31}(?![A-Za-z0-9_])", value: "[username скрыт]")
            collect("(?<![\\p{L}\\p{N}])\\+\\d[\\d ()-]{6,}\\d(?![\\p{L}\\p{N}])", value: "[номер скрыт]")
        }
        let ordered = candidates.enumerated().sorted {
            if $0.element.range.location != $1.element.range.location { return $0.element.range.location < $1.element.range.location }
            if $0.element.range.length != $1.element.range.length { return $0.element.range.length > $1.element.range.length }
            return $0.offset < $1.offset
        }
        var accepted: [Replacement] = []
        var end = 0
        for (_, item) in ordered where item.range.location >= end {
            accepted.append(item)
            end = NSMaxRange(item.range)
        }
        let result = NSMutableString(string: text)
        for item in accepted.reversed() { result.replaceCharacters(in: item.range, with: item.text) }
        return result as String
    }
}
