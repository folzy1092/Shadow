import Foundation

// Shadow: «Лента» (beta) — posts of the channels one after another, newest
// first, like Twitter. Foundation only (tested in Tests/ShadowSettings/FeedTests.swift):
// the post model the page receives as JSON, text formatting to HTML, where
// the tab goes, and the per-account store of chips (feed-only collections of
// channels, chip order). ShadowFeedCollect.swift reads the posts from the
// database, ShadowFeedPage.swift is the page, TelegramUI/ShadowFeedController
// the tab.
public enum ShadowFeed {
    // Where the tab goes in the bottom bar.
    public enum Position: Int32, CaseIterable {
        case beforeContacts = 0
        case beforeSettings = 1
        case afterSettings = 2
        // A round button left of the tabs, like search on the right.
        case leading = 3

        public var title: String {
            switch self {
            case .beforeContacts: return "Левее контактов"
            case .beforeSettings: return "Между чатами и профилем"
            case .afterSettings: return "Правее профиля"
            case .leading: return "Отдельной кнопкой слева"
            }
        }

        public static func normalized(_ value: Int32) -> Position {
            return Position(rawValue: value) ?? .beforeSettings
        }

        // Index of the feed tab among `count` other tabs, settings being last.
        public func index(otherTabs count: Int) -> Int {
            switch self {
            case .beforeContacts, .leading: return 0
            case .beforeSettings: return max(0, count - 1)
            case .afterSettings: return count
            }
        }
    }

    public struct Media: Codable, Equatable {
        public var key: String
        // photo, video, gif, round, voice, audio, file, sticker, poll, location, other
        public var kind: String
        public var width: Int
        public var height: Int
        public var duration: Int?
        public var title: String?

        public init(key: String, kind: String, width: Int = 0, height: Int = 0, duration: Int? = nil, title: String? = nil) {
            self.key = key
            self.kind = kind
            self.width = width
            self.height = height
            self.duration = duration
            self.title = title
        }
    }

    public struct Reaction: Codable, Equatable {
        public var key: String
        public var count: Int
        public var mine: Bool
        public var image: String?

        public init(key: String, count: Int, mine: Bool, image: String? = nil) {
            self.key = key
            self.count = count
            self.mine = mine
            self.image = image
        }
    }

    public struct Post: Codable, Equatable {
        public var id: String
        public var peerId: Int64
        public var namespace: Int32
        public var messageId: Int32
        public var channel: String
        public var color: Int
        public var initials: String
        public var timestamp: Int32
        public var html: String
        public var textLength: Int
        public var forwardFrom: String?
        public var media: [Media]
        public var views: Int?
        public var reactions: [Reaction]
        public var comments: Int?
        public var unread: Bool
        public var edited: Bool

        public init(id: String, peerId: Int64, namespace: Int32, messageId: Int32, channel: String, color: Int, initials: String, timestamp: Int32, html: String, textLength: Int, forwardFrom: String?, media: [Media], views: Int?, reactions: [Reaction], comments: Int?, unread: Bool, edited: Bool) {
            self.id = id
            self.peerId = peerId
            self.namespace = namespace
            self.messageId = messageId
            self.channel = channel
            self.color = color
            self.initials = initials
            self.timestamp = timestamp
            self.html = html
            self.textLength = textLength
            self.forwardFrom = forwardFrom
            self.media = media
            self.views = views
            self.reactions = reactions
            self.comments = comments
            self.unread = unread
            self.edited = edited
        }
    }

    // A chip above the feed.
    public struct Chip: Codable, Equatable {
        public var id: String
        public var title: String
        // nil: all channels ("all", "unread").
        public var peerIds: [Int64]?

        public init(id: String, title: String, peerIds: [Int64]?) {
            self.id = id
            self.title = title
            self.peerIds = peerIds
        }
    }

    public static func initials(_ title: String) -> String {
        let words = title.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        let letters = words.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }
        return letters.isEmpty ? "#" : letters.joined()
    }

    // MARK: - Text

    public enum EntityKind: Equatable {
        case bold
        case italic
        case underline
        case strikethrough
        case code
        case pre
        case spoiler
        case blockquote
        case link(String)
        // Premium emoji: its fallback emoji, swapped for the picture on the page.
        case customEmoji(Int64)
    }

    public struct Entity: Equatable {
        public var location: Int
        public var length: Int
        public var kind: EntityKind

        public init(location: Int, length: Int, kind: EntityKind) {
            self.location = location
            self.length = length
            self.kind = kind
        }
    }

    public static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            case "\n": result += "<br>"
            default: result.append(character)
            }
        }
        return result
    }

    static func openTag(_ kind: EntityKind) -> String {
        switch kind {
        case .bold: return "<b>"
        case .italic: return "<i>"
        case .underline: return "<u>"
        case .strikethrough: return "<s>"
        case .code: return "<code>"
        case .pre: return "<pre>"
        case .spoiler: return "<span class=\"spoiler\">"
        case .blockquote: return "<blockquote>"
        case let .link(url):
            return "<a data-url=\"\(escape(url))\">"
        case let .customEmoji(fileId):
            return "<span class=\"ce\" data-ce=\"\(fileId)\">"
        }
    }

    static func closeTag(_ kind: EntityKind) -> String {
        switch kind {
        case .bold: return "</b>"
        case .italic: return "</i>"
        case .underline: return "</u>"
        case .strikethrough: return "</s>"
        case .code: return "</code>"
        case .pre: return "</pre>"
        case .spoiler, .customEmoji: return "</span>"
        case .link: return "</a>"
        case .blockquote: return "</blockquote>"
        }
    }

    static func isBlock(_ kind: EntityKind) -> Bool {
        return kind == .blockquote || kind == .pre
    }

    // Text with entities (UTF-16 ranges, as Telegram stores them) to safe HTML.
    // Quotes and code blocks are whole blocks (1.9.1: a quote with bold words
    // inside used to break into a dozen quotes); inline entities are closed
    // and reopened at every boundary inside them, so the tags always nest.
    public static func html(text: String, entities: [Entity]) -> String {
        let utf16 = Array(text.utf16)
        let count = utf16.count
        let valid = entities.filter { $0.length > 0 && $0.location >= 0 && $0.location < count }
        if valid.isEmpty {
            return escape(text)
        }
        let inline = valid.filter { !isBlock($0.kind) }
        var result = ""
        var cursor = 0
        for block in valid.filter({ isBlock($0.kind) }).sorted(by: { $0.location < $1.location }) where block.location >= cursor {
            if block.location > cursor {
                result += inlineHTML(utf16, start: cursor, end: block.location, entities: inline)
            }
            let end = min(count, block.location + block.length)
            result += openTag(block.kind) + inlineHTML(utf16, start: block.location, end: end, entities: inline) + closeTag(block.kind)
            cursor = end
        }
        if cursor < count {
            result += inlineHTML(utf16, start: cursor, end: count, entities: inline)
        }
        return result
    }

    static func inlineHTML(_ utf16: [UInt16], start rangeStart: Int, end rangeEnd: Int, entities: [Entity]) -> String {
        let valid = entities.filter { $0.location < rangeEnd && $0.location + $0.length > rangeStart }
        var boundaries = Set<Int>([rangeStart, rangeEnd])
        for entity in valid {
            boundaries.insert(max(rangeStart, entity.location))
            boundaries.insert(min(rangeEnd, entity.location + entity.length))
        }
        let points = boundaries.sorted()
        var result = ""
        for index in 0 ..< points.count - 1 {
            let start = points[index]
            let end = points[index + 1]
            if start >= end {
                continue
            }
            let active = valid.filter { $0.location <= start && $0.location + $0.length >= end }
            let piece = String(decoding: utf16[start ..< end], as: UTF16.self)
            var open = ""
            var close = ""
            for entity in active {
                open += openTag(entity.kind)
                close = closeTag(entity.kind) + close
            }
            result += open + escape(piece) + close
        }
        return result
    }
}

// Per account: feed-only collections of channels, the chip order and the
// newest post seen («вы остановились здесь»).
public final class ShadowFeedStore {
    public static let shared = ShadowFeedStore(defaults: .standard)

    public struct Collection: Codable, Equatable {
        public var id: String
        public var title: String
        public var peerIds: [Int64]

        public init(id: String, title: String, peerIds: [Int64]) {
            self.id = id
            self.title = title
            self.peerIds = peerIds
        }
    }

    private struct State: Codable {
        var collections: [Collection] = []
        var order: [String] = []
        var lastSeen: Int32 = 0
        var hidden: [Int64]? = []
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func key(_ accountPeerId: Int64) -> String {
        return "shadow.feed.v1.\(accountPeerId)"
    }

    private func state(_ accountPeerId: Int64) -> State {
        guard let data = self.defaults.data(forKey: self.key(accountPeerId)), let state = try? JSONDecoder().decode(State.self, from: data) else {
            return State()
        }
        return state
    }

    private func save(_ state: State, _ accountPeerId: Int64) {
        if let data = try? JSONEncoder().encode(state) {
            self.defaults.set(data, forKey: self.key(accountPeerId))
        }
    }

    public func collections(accountPeerId: Int64) -> [Collection] {
        return self.state(accountPeerId).collections
    }

    // Adds or replaces (same id). An empty title or no channels removes it.
    public func setCollection(_ collection: Collection, accountPeerId: Int64) {
        var state = self.state(accountPeerId)
        state.collections.removeAll(where: { $0.id == collection.id })
        let title = collection.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && !collection.peerIds.isEmpty {
            var collection = collection
            collection.title = String(title.prefix(32))
            state.collections.append(collection)
        }
        if !state.collections.contains(where: { $0.id == collection.id }) {
            state.order.removeAll(where: { $0 == "col:" + collection.id })
        }
        self.save(state, accountPeerId)
    }

    public func removeCollection(id: String, accountPeerId: Int64) {
        var state = self.state(accountPeerId)
        state.collections.removeAll(where: { $0.id == id })
        state.order.removeAll(where: { $0 == "col:" + id })
        self.save(state, accountPeerId)
    }

    public func order(accountPeerId: Int64) -> [String] {
        return self.state(accountPeerId).order
    }

    public func setOrder(_ order: [String], accountPeerId: Int64) {
        var state = self.state(accountPeerId)
        state.order = order
        self.save(state, accountPeerId)
    }

    // Channels removed from the feed («Убрать канал из ленты»).
    public func hiddenChannels(accountPeerId: Int64) -> Set<Int64> {
        return Set(self.state(accountPeerId).hidden ?? [])
    }

    public func setChannelHidden(_ peerId: Int64, hidden: Bool, accountPeerId: Int64) {
        var state = self.state(accountPeerId)
        var list = state.hidden ?? []
        list.removeAll(where: { $0 == peerId })
        if hidden {
            list.append(peerId)
        }
        state.hidden = list
        self.save(state, accountPeerId)
    }

    public func clearHiddenChannels(accountPeerId: Int64) {
        var state = self.state(accountPeerId)
        state.hidden = []
        self.save(state, accountPeerId)
    }

    public func lastSeen(accountPeerId: Int64) -> Int32 {
        return self.state(accountPeerId).lastSeen
    }

    public func setLastSeen(_ timestamp: Int32, accountPeerId: Int64) {
        var state = self.state(accountPeerId)
        state.lastSeen = max(state.lastSeen, timestamp)
        self.save(state, accountPeerId)
    }

    // Chips in the saved order: "all" and "unread" always, then the folders
    // (when shown) and the collections; unknown ids are dropped, new chips go
    // to the end.
    public static func orderedChips(_ chips: [ShadowFeed.Chip], order: [String]) -> [ShadowFeed.Chip] {
        var result: [ShadowFeed.Chip] = []
        for id in order {
            if let chip = chips.first(where: { $0.id == id }), !result.contains(where: { $0.id == id }) {
                result.append(chip)
            }
        }
        for chip in chips where !result.contains(where: { $0.id == chip.id }) {
            result.append(chip)
        }
        return result
    }
}
