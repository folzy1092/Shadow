import Foundation

// Shadow: quick links to fork screens, like exteraGram's.
//
//   shadow://<command>/<arguments>?<query>
//   tg://shadow/<command>/<arguments>?<query>
//
// Both forms mean the same thing: `shadow://` is registered as the app's own
// URL scheme, `tg://shadow/` is for places that only accept tg:// links (bot
// buttons). In messages both are highlighted locally, so they look and tap
// like web links even though Telegram's server does not mark them.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowLinks {
    public struct Link: Equatable {
        // Lowercased command; "settings" when the link has none.
        public let command: String
        public let arguments: [String]
        public let query: [String: String]

        public init(command: String, arguments: [String], query: [String: String]) {
            self.command = command
            self.arguments = arguments
            self.query = query
        }
    }

    public static func parse(_ string: String) -> Link? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        var remainder: Substring?
        if lowered.hasPrefix("shadow://") {
            remainder = trimmed.dropFirst("shadow://".count)
        } else if lowered == "tg://shadow" {
            remainder = ""
        } else if lowered.hasPrefix("tg://shadow/") {
            remainder = trimmed.dropFirst("tg://shadow/".count)
        } else if lowered.hasPrefix("tg://shadow?") {
            remainder = trimmed.dropFirst("tg://shadow".count)
        }
        guard let remainder else {
            return nil
        }
        let parts = remainder.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = parts.first.map { String($0) } ?? ""
        let components = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }.filter { !$0.isEmpty }
        var query: [String: String] = [:]
        if parts.count > 1, let items = URLComponents(string: "shadow://q?" + parts[1])?.queryItems {
            for item in items {
                query[item.name.lowercased()] = item.value ?? ""
            }
        }
        let command = components.first?.lowercased() ?? "settings"
        return Link(command: command, arguments: Array(components.dropFirst()), query: query)
    }

    public static func isShadowLink(_ string: String) -> Bool {
        return parse(string) != nil
    }

    private static let expression = try? NSRegularExpression(pattern: "(?:shadow://|tg://shadow(?=[/?\\s]|$))[^\\s<>\"'«»]*", options: [.caseInsensitive])
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,!?;:)]}")

    // UTF-16 ranges of every quick link in `text`, trailing punctuation excluded.
    public static func ranges(in text: String) -> [Range<Int>] {
        guard let expression, text.range(of: "shadow", options: .caseInsensitive) != nil else {
            return []
        }
        let string = text as NSString
        var result: [Range<Int>] = []
        for match in expression.matches(in: text, options: [], range: NSRange(location: 0, length: string.length)) {
            var length = match.range.length
            while length > 0, let scalar = UnicodeScalar(string.character(at: match.range.location + length - 1)), trailingPunctuation.contains(scalar) {
                length -= 1
            }
            let candidate = string.substring(with: NSRange(location: match.range.location, length: length))
            if length > 0, parse(candidate) != nil {
                result.append(match.range.location ..< match.range.location + length)
            }
        }
        return result
    }
}
