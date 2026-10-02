import Foundation

// Shadow: local message filters, modelled on AyuGram Desktop — a regular
// expression with enabled / case-insensitive / reversed flags. Matching hides
// messages on this device only.
public struct ShadowMessageFilter: Codable, Equatable {
    public var id: Int64
    public var expression: String
    public var enabled: Bool
    public var caseInsensitive: Bool
    public var reversed: Bool

    public init(id: Int64, expression: String, enabled: Bool = true, caseInsensitive: Bool = true, reversed: Bool = false) {
        self.id = id
        self.expression = expression
        self.enabled = enabled
        self.caseInsensitive = caseInsensitive
        self.reversed = reversed
    }

    // Postbox's Codable adapter stores Bool as Int32 elsewhere in AyuGramSettings; keep that here.
    private enum CodingKeys: String, CodingKey {
        case id, expression, enabled, caseInsensitive, reversed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.expression = try container.decode(String.self, forKey: .expression)
        self.enabled = ((try container.decodeIfPresent(Int32.self, forKey: .enabled)) ?? 1) != 0
        self.caseInsensitive = ((try container.decodeIfPresent(Int32.self, forKey: .caseInsensitive)) ?? 1) != 0
        self.reversed = ((try container.decodeIfPresent(Int32.self, forKey: .reversed)) ?? 0) != 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.expression, forKey: .expression)
        try container.encode((self.enabled ? 1 : 0) as Int32, forKey: .enabled)
        try container.encode((self.caseInsensitive ? 1 : 0) as Int32, forKey: .caseInsensitive)
        try container.encode((self.reversed ? 1 : 0) as Int32, forKey: .reversed)
    }

    public static func isValid(expression: String) -> Bool {
        guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return (try? NSRegularExpression(pattern: expression)) != nil
    }

    public static func escaped(_ text: String) -> String {
        return NSRegularExpression.escapedPattern(for: text)
    }

    public static func migrated(phrases: [String]) -> [ShadowMessageFilter] {
        var result: [ShadowMessageFilter] = []
        for phrase in phrases {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            result.append(ShadowMessageFilter(id: Int64(result.count + 1), expression: escaped(trimmed)))
        }
        return result
    }
}

public final class ShadowMessageFilterMatcher {
    private let rules: [(NSRegularExpression, Bool)]

    public init(filters: [ShadowMessageFilter]) {
        self.rules = filters.compactMap { filter in
            guard filter.enabled else {
                return nil
            }
            let options: NSRegularExpression.Options = filter.caseInsensitive ? [.caseInsensitive] : []
            guard let regex = try? NSRegularExpression(pattern: filter.expression, options: options) else {
                return nil
            }
            return (regex, filter.reversed)
        }
    }

    public var isEmpty: Bool {
        return self.rules.isEmpty
    }

    // Messages without text (media without a caption, stickers, service
    // messages) are never hidden, so a reversed filter cannot wipe them out.
    public func hides(text: String) -> Bool {
        if text.isEmpty {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        for (regex, reversed) in self.rules {
            let found = regex.firstMatch(in: text, options: [], range: range) != nil
            if found != reversed {
                return true
            }
        }
        return false
    }
}
