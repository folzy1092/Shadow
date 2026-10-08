import Foundation

// Shadow: hiding ads by the marking Russian law requires on every ad post —
// an `erid` token, "Реклама. ООО …" with the advertiser, the advertiser's ИНН,
// "#реклама" and similar. The markers are case-insensitive regular expressions
// from shadow-ad-markers.json in folzy1092/tgfork, so they can be fixed without
// a new build; `builtIn` is the fallback until the first download (and when
// the file is missing or broken). Matching is local: posts are only hidden on
// this device. Foundation only (tested in Tests/ShadowSettings/AdFilterTests.swift);
// the message-level check lives in ShadowLocalHide.swift.

public struct ShadowAdMarkers: Equatable {
    public let version: Int
    public let patterns: [String]

    public init(version: Int, patterns: [String]) {
        self.version = version
        self.patterns = patterns
    }

    // Referral links (`?start=`, `?ref=`) are deliberately not markers: people
    // share useful bots with their own referral link (Folzy, 2026-10-08).
    // "По вопросам рекламы: @…" footers are not markers either: almost every
    // channel puts one under ordinary posts.
    public static let builtIn = ShadowAdMarkers(version: 1, patterns: [
        // erid: 2VtzqwJFKdP / ?erid=LjN8K… — the ad registry token.
        "(?<![a-z0-9])erid\\s*[:=]?\\s*[a-z0-9]{6,}",
        // "Реклама. ООО «Ромашка»", "Рекламодатель: ИП Иванов".
        "(реклама|рекламодатель)\\s*[.:,|\\-–—]?\\s*[«\"]?\\s*(ооо|оао|пао|зао|нао|ао|ип)(?![а-яё])",
        // The advertiser's ИНН (10 or 12 digits).
        "(?<![а-яё])инн\\s*[:№]?\\s*\\d{10}(\\d{2})?(?!\\d)",
        "#(реклама|промо|ad|ads|sponsored|партн[её]рск[а-яё]*|спонсорск[а-яё]*)(?![a-zа-яё0-9_])",
        "на\\s+правах\\s+рекламы",
        "партн[её]рск(ий|ая|ое)\\s+(пост|материал|публикаци[яи])",
        "рекламн(ый|ая|ое)\\s+(пост|материал|интеграци[яи]|запись|публикаци[яи])",
        // A line that is only "Реклама" (the label under a post).
        "(?m)^\\s*#?реклама\\s*[.!]?\\s*$"
    ])

    private struct File: Decodable {
        struct Pattern: Decodable {
            let regex: String

            init(from decoder: Decoder) throws {
                if let single = try? decoder.singleValueContainer(), let value = try? single.decode(String.self) {
                    self.regex = value
                    return
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.regex = try container.decode(String.self, forKey: .regex)
            }

            private enum CodingKeys: String, CodingKey {
                case regex
            }
        }
        let version: Int?
        let patterns: [Pattern]?
    }

    // Accepts `"patterns": ["regex", …]` or `[{"regex": "…", "note": "…"}, …]`.
    // nil when the file is malformed or has no valid pattern, so a broken
    // upload never switches ad hiding off.
    public static func parse(_ data: Data) -> ShadowAdMarkers? {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            return nil
        }
        let patterns = (file.patterns ?? []).map { $0.regex }.filter { pattern in
            return !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) != nil
        }
        if patterns.isEmpty {
            return nil
        }
        return ShadowAdMarkers(version: file.version ?? 0, patterns: patterns)
    }
}

public final class ShadowAdMatcher {
    private let expressions: [NSRegularExpression]

    public init(markers: ShadowAdMarkers) {
        self.expressions = markers.patterns.compactMap { pattern in
            return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }

    // `texts`: the message text plus hidden link URLs, button URLs and the link
    // preview URL — the erid often sits only in the "Подробнее" link.
    public func isAd(texts: [String]) -> Bool {
        for text in texts where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for expression in self.expressions {
                if expression.firstMatch(in: text, options: [], range: range) != nil {
                    return true
                }
            }
        }
        return false
    }
}

// Where a message is, for the per-place toggles of the ad filter.
public enum ShadowAdPlace {
    case channel
    case group
    case privateChat
}

public struct ShadowAdScope: Equatable {
    public var channels: Bool
    public var groups: Bool
    public var forwarded: Bool

    public init(channels: Bool, groups: Bool, forwarded: Bool) {
        self.channels = channels
        self.groups = groups
        self.forwarded = forwarded
    }

    public var isEnabled: Bool {
        return self.channels || self.groups || self.forwarded
    }

    // Channel posts follow "в каналах" (a channel's repost of another channel's
    // ad too). In groups and private chats a forwarded message follows "в
    // пересланных"; in groups everything else follows "в группах".
    public func applies(place: ShadowAdPlace, isForwarded: Bool) -> Bool {
        switch place {
        case .channel:
            return self.channels
        case .group:
            return self.groups || (isForwarded && self.forwarded)
        case .privateChat:
            return isForwarded && self.forwarded
        }
    }
}

// Process-wide marker list: disk cache first, then a refresh from tgfork.
public final class ShadowAdMarkersStore {
    public static let shared = ShadowAdMarkersStore()

    public static let remoteURL = URL(string: "https://raw.githubusercontent.com/folzy1092/tgfork/main/shadow-ad-markers.json")!

    private let lock = NSLock()
    private var markers: ShadowAdMarkers = .builtIn
    private var cachedMatcher: ShadowAdMatcher?
    private var started = false

    public var current: ShadowAdMarkers {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.markers
    }

    public var matcher: ShadowAdMatcher {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let cachedMatcher = self.cachedMatcher {
            return cachedMatcher
        }
        let matcher = ShadowAdMatcher(markers: self.markers)
        self.cachedMatcher = matcher
        return matcher
    }

    public func set(_ markers: ShadowAdMarkers) {
        self.lock.lock()
        if self.markers != markers {
            self.markers = markers
            self.cachedMatcher = nil
        }
        self.lock.unlock()
    }

    private static var cacheURL: URL? {
        guard let directory = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        return directory.appendingPathComponent("ShadowAdMarkers.json")
    }

    // Once per process (Account setup), like the badge config.
    public func startIfNeeded() {
        self.lock.lock()
        if self.started {
            self.lock.unlock()
            return
        }
        self.started = true
        self.lock.unlock()

        if let cacheURL = ShadowAdMarkersStore.cacheURL, let data = try? Data(contentsOf: cacheURL), let markers = ShadowAdMarkers.parse(data) {
            self.set(markers)
        }
        self.refresh()
    }

    public func refresh() {
        var request = URLRequest(url: ShadowAdMarkersStore.remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20.0
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil, let data = data, (response as? HTTPURLResponse)?.statusCode == 200, let markers = ShadowAdMarkers.parse(data) else {
                return
            }
            self?.set(markers)
            if let cacheURL = ShadowAdMarkersStore.cacheURL {
                try? data.write(to: cacheURL, options: .atomic)
            }
        }.resume()
    }
}
