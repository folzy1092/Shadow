import Foundation

// Shadow: «Итоги чата» — statistics of one chat over a chosen period, computed
// on this device. Foundation only (tested in Tests/ShadowSettings/ChatStatsTests.swift):
// ShadowChatStatsCollect.swift turns stored messages into `Item`s, the builder
// here counts them, `Report` is what the list keeps (one per chat) and what
// ShadowChatStatsPage renders as HTML (in the app and as a shared file).
public enum ShadowChatStats {
    public enum Period: Int32, Codable, CaseIterable {
        case week = 0
        case month = 1
        case year = 2
        case fiveYears = 3

        public var title: String {
            switch self {
            case .week: return "Неделя"
            case .month: return "Месяц"
            case .year: return "Год"
            case .fiveYears: return "5 лет"
            }
        }

        // "за неделю", "за год"…
        public var forTitle: String {
            switch self {
            case .week: return "за неделю"
            case .month: return "за месяц"
            case .year: return "за год"
            case .fiveYears: return "за 5 лет"
            }
        }

        public var days: Int32 {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .fiveYears: return 365 * 5 + 1
            }
        }

        public func start(now: Int32) -> Int32 {
            return now - self.days * 86400
        }

        // The previous period of the same length, for «По сравнению с прошлым»
        // (1.11.0). None for 5 years: that would be ten years of history.
        public func previousStart(now: Int32) -> Int32? {
            switch self {
            case .week, .month, .year:
                return now - self.days * 2 * 86400
            case .fiveYears:
                return nil
            }
        }

        // How far back history is loaded and scanned: the previous period,
        // and always at least two weeks («Две недели на одном графике»).
        public func scanStart(now: Int32) -> Int32 {
            return min(self.previousStart(now: now) ?? self.start(now: now), now - 14 * 86400)
        }
    }

    public enum Kind: Int {
        case text
        case voice
        case round
        case sticker
        case gif
        case photo
        case video
        case file
        case call
    }

    public struct Reaction {
        public var authorId: Int64
        public var key: String

        public init(authorId: Int64, key: String) {
            self.authorId = authorId
            self.key = key
        }
    }

    // One message, already stripped to what the statistics need. Service
    // messages are not items, except calls (kind .call, duration in seconds).
    public struct Item {
        public var timestamp: Int32
        public var authorId: Int64
        public var text: String
        public var kind: Kind
        public var duration: Int32
        public var stickerKey: String?
        public var stickerLabel: String?
        public var isForward: Bool
        public var isReply: Bool
        public var hasLink: Bool
        public var isDeleted: Bool
        public var isEdited: Bool
        public var reactions: [Reaction]
        // Author of the message this one replies to (groups: «Кто кому отвечает»).
        public var replyToAuthorId: Int64?

        public init(timestamp: Int32, authorId: Int64, text: String = "", kind: Kind = .text, duration: Int32 = 0, stickerKey: String? = nil, stickerLabel: String? = nil, isForward: Bool = false, isReply: Bool = false, hasLink: Bool = false, isDeleted: Bool = false, isEdited: Bool = false, reactions: [Reaction] = [], replyToAuthorId: Int64? = nil) {
            self.timestamp = timestamp
            self.authorId = authorId
            self.text = text
            self.kind = kind
            self.duration = duration
            self.stickerKey = stickerKey
            self.stickerLabel = stickerLabel
            self.isForward = isForward
            self.isReply = isReply
            self.hasLink = hasLink
            self.isDeleted = isDeleted
            self.isEdited = isEdited
            self.reactions = reactions
            self.replyToAuthorId = replyToAuthorId
        }
    }

    public struct Count: Codable, Equatable {
        public var key: String
        public var count: Int
        // Sticker: its emoji, shown when there is no picture.
        public var label: String?

        public init(key: String, count: Int, label: String? = nil) {
            self.key = key
            self.count = count
            self.label = label
        }
    }

    public struct DayCount: Codable, Equatable {
        public var day: Int32
        public var count: Int

        public init(day: Int32, count: Int) {
            self.day = day
            self.count = count
        }
    }

    // A record of the period: the longest message (characters), voice
    // message, round video, call (seconds) and the busiest clock hour
    // (messages; authorId 0 — the whole chat).
    public struct Record: Codable, Equatable {
        public var kind: String
        public var authorId: Int64
        public var value: Int
        public var timestamp: Int32

        public init(kind: String, authorId: Int64, value: Int, timestamp: Int32) {
            self.kind = kind
            self.authorId = authorId
            self.value = value
            self.timestamp = timestamp
        }
    }

    // «Ваш обычный день»: medians over the days with messages. A day runs
    // from 4:00, so a talk past midnight belongs to the evening it started.
    // Minutes are local clock minutes (0…1439).
    public struct TypicalDay: Codable, Equatable {
        public var days: Int
        public var messages: Int
        public var startMinute: Int
        public var endMinute: Int
        public var spanMinutes: Int
        public var busyWeekday: Int
        public var quietWeekday: Int

        public init(days: Int, messages: Int, startMinute: Int, endMinute: Int, spanMinutes: Int, busyWeekday: Int, quietWeekday: Int) {
            self.days = days
            self.messages = messages
            self.startMinute = startMinute
            self.endMinute = endMinute
            self.spanMinutes = spanMinutes
            self.busyWeekday = busyWeekday
            self.quietWeekday = quietWeekday
        }
    }

    // Groups: how many times `from` replied to a message of `to`.
    public struct ReplyPair: Codable, Equatable {
        public var from: Int64
        public var to: Int64
        public var count: Int

        public init(from: Int64, to: Int64, count: Int) {
            self.from = from
            self.to = to
            self.count = count
        }
    }

    public struct PersonCount: Codable, Equatable {
        public var id: Int64
        public var messages: Int

        public init(id: Int64, messages: Int) {
            self.id = id
            self.messages = messages
        }
    }

    // The previous period of the same length, counted the same way.
    public struct PeriodSummary: Codable, Equatable {
        public var from: Int32
        public var to: Int32
        public var total: Int
        public var daysWithMessages: Int
        public var words: Int
        public var voiceSeconds: Int
        public var roundCount: Int
        public var stickers: Int
        public var calls: Int
        public var callSeconds: Int
        public var people: [PersonCount]

        public init(from: Int32, to: Int32, total: Int, daysWithMessages: Int, words: Int, voiceSeconds: Int, roundCount: Int, stickers: Int, calls: Int, callSeconds: Int, people: [PersonCount]) {
            self.from = from
            self.to = to
            self.total = total
            self.daysWithMessages = daysWithMessages
            self.words = words
            self.voiceSeconds = voiceSeconds
            self.roundCount = roundCount
            self.stickers = stickers
            self.calls = calls
            self.callSeconds = callSeconds
            self.people = people
        }
    }

    // «Две недели на одном графике»: messages per day of the last 7 days
    // (ending today) and of the 7 days before, oldest first. `firstDay` is
    // the local day of `current[0]`.
    public struct TwoWeeks: Codable, Equatable {
        public var firstDay: Int32
        public var current: [Int]
        public var previous: [Int]

        public init(firstDay: Int32, current: [Int], previous: [Int]) {
            self.firstDay = firstDay
            self.current = current
            self.previous = previous
        }
    }

    public struct Person: Codable, Equatable {
        public var id: Int64
        public var name: String
        public var messages = 0
        public var words = 0
        public var voiceCount = 0
        public var voiceSeconds = 0
        public var roundCount = 0
        public var roundSeconds = 0
        public var stickers = 0
        public var gifs = 0
        public var photos = 0
        public var videos = 0
        public var files = 0
        public var links = 0
        public var forwards = 0
        public var replies = 0
        public var deleted = 0
        public var edited = 0
        public var calls = 0
        public var callSeconds = 0
        public var night = 0
        public var firstOfDay = 0
        public var replySeconds: Int?
        public var replySamples = 0
        public var hours = [Int](repeating: 0, count: 24)
        public var weekdays = [Int](repeating: 0, count: 7)
        public var timeline: [Int] = []
        public var emoji: [Count] = []
        public var topStickers: [Count] = []
        public var reactions: [Count] = []
        public var topWords: [Count] = []
        public var bestDay: DayCount?
        // 1.11.0 (nil in older reports).
        // Mood by emoji in own messages and reactions given (keys: Mood).
        public var moods: [Count]?
        // Private chats: words this person uses and the other never does.
        public var uniqueWords: [Count]?
        // «Кто кого ждёт» (private chats): waits for an answer of 1…24 h,
        // their sum, the longest wait (up to a week) and when it began, and
        // turns left without an answer for more than a day.
        public var waitLongCount: Int?
        public var waitTotalSeconds: Int?
        public var waitLongest: Int?
        public var waitLongestAt: Int32?
        public var unanswered: Int?

        public init(id: Int64, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Report: Codable, Equatable {
        public static let currentVersion = 2

        public var version: Int
        public var accountPeerId: Int64
        public var peerId: Int64
        public var title: String
        public var isGroup: Bool
        public var period: Period
        public var from: Int32
        public var to: Int32
        public var generated: Int32
        public var meId: Int64
        public var people: [Person]
        public var total: Int
        public var daysWithMessages: Int
        public var daysInPeriod: Int
        public var firstOfDayDays: Int
        public var streakCurrent: Int
        public var streakBest: Int
        public var longestBreak: Int32
        public var longestBreakFrom: Int32
        public var longestBreakTo: Int32
        public var bestDay: DayCount?
        public var timelineLabels: [String]
        public var heatmap: [[Int]]
        public var firstMessage: Int32?
        public var timeZoneOffset: Int32
        // key -> data: URI of a sticker or custom emoji picture (filled by the app).
        public var images: [String: String]
        // false: messages kept after deletion were left out (nil in older reports).
        public var countsDeleted: Bool?
        // 1.11.0 (nil in older reports).
        public var records: [Record]?
        public var typicalDay: TypicalDay?
        public var replyPairs: [ReplyPair]?
        // The dominant mood of each timeline bucket ("" — too few emoji).
        public var moodTimeline: [String]?
        public var previous: PeriodSummary?
        public var twoWeeks: TwoWeeks?

        public var me: Person? {
            return self.people.first(where: { $0.id == self.meId })
        }

        // In a private chat: the other person.
        public var other: Person? {
            return self.people.first(where: { $0.id != self.meId })
        }
    }

    // MARK: - Text

    static let stopWords: Set<String> = Set("""
    и в во не что он на я с со как а то все всё она так его но да ты к у же вы за бы по только ее её мне было вот от меня еще ещё нет о об из ему теперь когда даже ну ли если уже или ни быть был него до вас нибудь опять уж вам ведь там потом себя ничего ей может они тут где есть надо ней для мы тебя их чем была сам чтоб без будто чего раз тоже себе под будет ж тогда кто этот того потому этого какой совсем ним здесь этом один почти мой тем чтобы нее неё были куда зачем всех никогда можно при два другой хоть после над больше тот через эти нас про всего них какая много разве три эту моя впрочем свою этой перед иногда лучше чуть том нельзя такой им более всегда конечно всю между это тебе мои твой твоя мной тобой сейчас вообще просто очень тоже либо пока типа там тут тебе ему ими нам вами
    the a an to and of is it in i you he she we they that this for on with as at be are was were but not or so if my me your do does did have has had just what
    http https www com ru org net
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    static func isEmoji(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first else {
            return false
        }
        if first.properties.isEmojiPresentation {
            return true
        }
        return first.properties.isEmoji && (character.unicodeScalars.count > 1 || first.value > 0x238C)
    }

    static func emoji(in text: String) -> [String] {
        var result: [String] = []
        for character in text where isEmoji(character) {
            result.append(String(character))
        }
        return result
    }

    // MARK: - Mood

    // «Настроение по эмодзи»: an emoji (or a reaction) counts for one mood.
    // Skin tones and the emoji variation selector are ignored.
    public enum Mood: String, CaseIterable {
        case laugh
        case love
        case joy
        case sad
        case angry
        case wow
        case meh
    }

    static let moodEmoji: [String: Mood] = {
        var result: [String: Mood] = [:]
        let table: [(Mood, String)] = [
            (.laugh, "😂 🤣 😹 😆 😅 😝 😜 🤪"),
            (.love, "❤ 😍 🥰 😘 💕 💖 💗 💘 💞 💓 😻 💋 🫶 ♥ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💝 ❣ 😚 😙 🩷 🩵"),
            (.joy, "😊 🙂 😄 😃 😀 😁 ☺ 🥳 🎉 👍 👌 🔥 ✨ 💯 🤩 😎 🤗 👏 🙌 💪 😇 🥹"),
            (.sad, "😢 😭 😔 😞 😟 🥺 💔 😿 😥 😓 ☹ 🙁 😩 😫 😪 😣 😖"),
            (.angry, "😡 🤬 😠 👿 💢 😤 🖕 👎"),
            (.wow, "😮 😱 😳 🤯 😲 😯 🙀 😨 👀 🫢 😧 😦 😰"),
            (.meh, "🤔 🧐 🤨 😐 😑 🙄 😒 🫤 😶 🤷")
        ]
        for (mood, list) in table {
            for emoji in list.split(separator: " ") {
                result[ShadowChatStats.normalizedEmoji(String(emoji))] = mood
            }
        }
        return result
    }()

    static func normalizedEmoji(_ emoji: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in emoji.unicodeScalars {
            // Variation selector-16 and skin tones.
            if scalar.value == 0xFE0F || (0x1F3FB ... 0x1F3FF).contains(scalar.value) {
                continue
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    public static func mood(of emoji: String) -> Mood? {
        return moodEmoji[normalizedEmoji(emoji)]
    }

    // Words without links, @mentions, numbers and emoji.
    static func words(in text: String) -> [String] {
        var result: [String] = []
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let lower = token.lowercased()
            if lower.hasPrefix("http") || lower.hasPrefix("@") || lower.hasPrefix("www.") || lower.hasPrefix("t.me/") || lower.contains("://") {
                continue
            }
            for part in lower.split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
                if part.contains(where: { $0.isLetter }) {
                    result.append(String(part))
                }
            }
        }
        return result
    }

    // MARK: - Time

    public struct Clock {
        public let offset: Int32

        public init(offset: Int32) {
            self.offset = offset
        }

        public static var current: Clock {
            return Clock(offset: Int32(TimeZone.current.secondsFromGMT()))
        }

        // Local calendar day (days since 1970-01-01, local midnight).
        public func day(_ timestamp: Int32) -> Int32 {
            return Int32((Int64(timestamp) + Int64(self.offset)).floorDiv(86400))
        }

        // "First message of the day" counts days from 4:00, so a chat that
        // goes on past midnight does not start a new day.
        public func morningDay(_ timestamp: Int32) -> Int32 {
            return Int32((Int64(timestamp) + Int64(self.offset) - 4 * 3600).floorDiv(86400))
        }

        public func hour(_ timestamp: Int32) -> Int {
            let local = (Int64(timestamp) + Int64(self.offset)).floorMod(86400)
            return Int(local / 3600)
        }

        // Monday = 0 … Sunday = 6 (1970-01-01 was a Thursday).
        public func weekday(_ timestamp: Int32) -> Int {
            return Int((Int64(self.day(timestamp)) + 3).floorMod(7))
        }

        // (year, month 1…12) of a local day.
        public func yearMonth(day: Int32) -> (Int, Int) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let date = Date(timeIntervalSince1970: TimeInterval(Int64(day) * 86400))
            let components = calendar.dateComponents([.year, .month], from: date)
            return (components.year ?? 1970, components.month ?? 1)
        }
    }

    static let monthNames = ["янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    // Longest run of consecutive days in a set, and the run that ends today
    // (or yesterday: today is not over yet, it does not break the run).
    public static func streaks(days: Set<Int32>, today: Int32) -> (current: Int, best: Int) {
        var best = 0
        var run = 0
        var previous: Int32?
        for day in days.sorted() {
            if let previous, day == previous + 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        var current = 0
        var day = days.contains(today) ? today : today - 1
        while days.contains(day) {
            current += 1
            day -= 1
        }
        return (current, best)
    }

    static func median(_ values: [Int32]) -> Int? {
        if values.isEmpty {
            return nil
        }
        let sorted = values.sorted()
        if sorted.count % 2 == 1 {
            return Int(sorted[sorted.count / 2])
        }
        return Int((Int64(sorted[sorted.count / 2 - 1]) + Int64(sorted[sorted.count / 2])) / 2)
    }

    static func top(_ counts: [String: Int], limit: Int, labels: [String: String] = [:]) -> [Count] {
        return counts.sorted(by: { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return lhs.key < rhs.key
        }).prefix(limit).map { Count(key: $0.key, count: $0.value, label: labels[$0.key]) }
    }

    // MARK: - Builder

    // A reply is the first message of another person after someone wrote;
    // pauses longer than this are not a reply time (asleep, busy).
    public static let maxReplyPause: Int32 = 6 * 3600

    // «Кто кого ждёт»: a long wait is 1…24 h; more than a day is «без ответа».
    public static let longWait = 3600
    public static let unansweredAfter = 24 * 3600
    public static let longestWaitLimit = 7 * 86400
    // «Только у одного из вас»: a word used at least this many times.
    public static let uniqueWordMinimum = 2

    public final class Builder {
        private struct Accumulator {
            var person: Person
            var emoji: [String: Int] = [:]
            var stickers: [String: Int] = [:]
            var stickerLabels: [String: String] = [:]
            var reactions: [String: Int] = [:]
            var words: [String: Int] = [:]
            var days: [Int32: Int] = [:]
            var replySamples: [Int32] = []
            var moods: [String: Int] = [:]
        }

        public let accountPeerId: Int64
        public let peerId: Int64
        public let title: String
        public let isGroup: Bool
        public let period: Period
        public let from: Int32
        public let to: Int32
        public let clock: Clock
        private let names: [Int64: String]
        private var people: [Int64: Accumulator] = [:]
        private var order: [(timestamp: Int32, authorId: Int64)] = []
        private var chatDays: [Int32: Int] = [:]
        private var heatmap = [[Int]](repeating: [Int](repeating: 0, count: 24), count: 7)
        private var firstMessage: Int32?
        // 1.11.0
        private var records: [String: Record] = [:]
        private var hourSlots: [Int64: Int] = [:]
        private var morningDays: [Int32: (first: Int32, last: Int32, count: Int)] = [:]
        private var dayMoods: [Int32: [String: Int]] = [:]
        private var replyPairs: [String: Int] = [:]

        public init(accountPeerId: Int64, peerId: Int64, title: String, isGroup: Bool, period: Period, from: Int32, to: Int32, names: [Int64: String], clock: Clock = .current) {
            self.accountPeerId = accountPeerId
            self.peerId = peerId
            self.title = title
            self.isGroup = isGroup
            self.period = period
            self.from = from
            self.to = to
            self.names = names
            self.clock = clock
            // Both sides of a private chat always show, even if one is silent.
            for (id, name) in names where !isGroup {
                self.people[id] = Accumulator(person: Person(id: id, name: name))
            }
        }

        private func name(_ id: Int64) -> String {
            return self.names[id] ?? (id == self.accountPeerId ? "Я" : "Участник")
        }

        // Keeps the larger value; on a tie, the earlier one.
        private func record(_ kind: String, authorId: Int64, value: Int, timestamp: Int32) {
            guard value > 0 else {
                return
            }
            if let current = self.records[kind], current.value > value || (current.value == value && current.timestamp <= timestamp) {
                return
            }
            self.records[kind] = Record(kind: kind, authorId: authorId, value: value, timestamp: timestamp)
        }

        private func addMood(_ emoji: String, to acc: inout Accumulator, day: Int32) {
            guard let mood = ShadowChatStats.mood(of: emoji) else {
                return
            }
            acc.moods[mood.rawValue, default: 0] += 1
            self.dayMoods[day, default: [:]][mood.rawValue, default: 0] += 1
        }

        public func add(_ item: Item) {
            guard item.timestamp >= self.from, item.timestamp <= self.to else {
                return
            }
            var acc = self.people[item.authorId] ?? Accumulator(person: Person(id: item.authorId, name: self.name(item.authorId)))
            defer {
                self.people[item.authorId] = acc
            }
            if item.kind == .call {
                acc.person.calls += 1
                acc.person.callSeconds += Int(item.duration)
                self.record("call", authorId: item.authorId, value: Int(item.duration), timestamp: item.timestamp)
                return
            }
            acc.person.messages += 1
            let day = self.clock.day(item.timestamp)
            let hour = self.clock.hour(item.timestamp)
            let weekday = self.clock.weekday(item.timestamp)
            acc.person.hours[hour] += 1
            acc.person.weekdays[weekday] += 1
            acc.days[day, default: 0] += 1
            self.chatDays[day, default: 0] += 1
            self.heatmap[weekday][hour] += 1
            if hour < 6 {
                acc.person.night += 1
            }
            self.order.append((item.timestamp, item.authorId))
            if self.firstMessage == nil || item.timestamp < self.firstMessage! {
                self.firstMessage = item.timestamp
            }
            let slot = (Int64(item.timestamp) + Int64(self.clock.offset)) / 3600
            self.hourSlots[slot, default: 0] += 1
            let morning = self.clock.morningDay(item.timestamp)
            if let current = self.morningDays[morning] {
                self.morningDays[morning] = (first: min(current.first, item.timestamp), last: max(current.last, item.timestamp), count: current.count + 1)
            } else {
                self.morningDays[morning] = (first: item.timestamp, last: item.timestamp, count: 1)
            }
            if self.isGroup, let to = item.replyToAuthorId, to != item.authorId {
                self.replyPairs["\(item.authorId):\(to)", default: 0] += 1
            }

            switch item.kind {
            case .voice:
                acc.person.voiceCount += 1
                acc.person.voiceSeconds += Int(item.duration)
                self.record("voice", authorId: item.authorId, value: Int(item.duration), timestamp: item.timestamp)
            case .round:
                acc.person.roundCount += 1
                acc.person.roundSeconds += Int(item.duration)
                self.record("round", authorId: item.authorId, value: Int(item.duration), timestamp: item.timestamp)
            case .sticker:
                acc.person.stickers += 1
                if let key = item.stickerKey {
                    acc.stickers[key, default: 0] += 1
                    if let label = item.stickerLabel, acc.stickerLabels[key] == nil {
                        acc.stickerLabels[key] = label
                    }
                }
            case .gif:
                acc.person.gifs += 1
            case .photo:
                acc.person.photos += 1
            case .video:
                acc.person.videos += 1
            case .file:
                acc.person.files += 1
            case .text, .call:
                break
            }
            if item.isForward {
                acc.person.forwards += 1
            } else if !item.text.isEmpty {
                let words = ShadowChatStats.words(in: item.text)
                acc.person.words += words.count
                for word in words where word.count >= 2 && !ShadowChatStats.stopWords.contains(word) && !word.allSatisfy({ $0.isNumber }) {
                    acc.words[word, default: 0] += 1
                }
                for emoji in ShadowChatStats.emoji(in: item.text) {
                    acc.emoji[emoji, default: 0] += 1
                    self.addMood(emoji, to: &acc, day: day)
                }
                self.record("text", authorId: item.authorId, value: item.text.count, timestamp: item.timestamp)
            }
            if item.isReply {
                acc.person.replies += 1
            }
            if item.hasLink {
                acc.person.links += 1
            }
            if item.isDeleted {
                acc.person.deleted += 1
            }
            if item.isEdited {
                acc.person.edited += 1
            }
            for reaction in item.reactions {
                var reactor = reaction.authorId == item.authorId ? acc : (self.people[reaction.authorId] ?? Accumulator(person: Person(id: reaction.authorId, name: self.name(reaction.authorId))))
                reactor.reactions[reaction.key, default: 0] += 1
                self.addMood(reaction.key, to: &reactor, day: day)
                if reaction.authorId == item.authorId {
                    acc = reactor
                } else {
                    self.people[reaction.authorId] = reactor
                }
            }
        }

        private func timelineBuckets() -> (labels: [String], index: (Int32) -> Int?) {
            let fromDay = self.clock.day(self.from)
            let toDay = self.clock.day(self.to)
            switch self.period {
            case .week, .month:
                let count = Int(toDay - fromDay) + 1
                let labels = (0 ..< count).map { offset -> String in
                    let (_, month) = self.clock.yearMonth(day: fromDay + Int32(offset))
                    let dayOfMonth = self.dayOfMonth(fromDay + Int32(offset))
                    return "\(dayOfMonth) \(ShadowChatStats.monthNames[month - 1])"
                }
                return (labels, { day in
                    let index = Int(day - fromDay)
                    return index >= 0 && index < count ? index : nil
                })
            case .year, .fiveYears:
                let (fromYear, fromMonth) = self.clock.yearMonth(day: fromDay)
                let (toYear, toMonth) = self.clock.yearMonth(day: toDay)
                let monthsPerBucket = self.period == .year ? 1 : 3
                let first = fromYear * 12 + fromMonth - 1
                let last = toYear * 12 + toMonth - 1
                let count = (last - first) / monthsPerBucket + 1
                let labels = (0 ..< count).map { index -> String in
                    let month = first + index * monthsPerBucket
                    let name = ShadowChatStats.monthNames[month % 12]
                    if self.period == .fiveYears || month % 12 == 0 || index == 0 {
                        return "\(name) \(String(month / 12).suffix(2))"
                    }
                    return name
                }
                var cache: [Int32: Int] = [:]
                return (labels, { day in
                    if let cached = cache[day] {
                        return cached
                    }
                    let (year, month) = self.clock.yearMonth(day: day)
                    let index = (year * 12 + month - 1 - first) / monthsPerBucket
                    let result = index >= 0 && index < count ? index : 0
                    cache[day] = result
                    return result
                })
            }
        }

        private func dayOfMonth(_ day: Int32) -> Int {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar.component(.day, from: Date(timeIntervalSince1970: TimeInterval(Int64(day) * 86400)))
        }

        public func build(generated: Int32) -> Report {
            self.order.sort(by: { $0.timestamp < $1.timestamp })

            // Replies, first message of the day, longest break.
            var longestBreak: Int32 = 0
            var longestBreakFrom: Int32 = 0
            var longestBreakTo: Int32 = 0
            var firstOfDayDays = Set<Int32>()
            var previous: (timestamp: Int32, authorId: Int64)?
            for entry in self.order {
                if let previous {
                    let gap = entry.timestamp - previous.timestamp
                    if gap > longestBreak {
                        longestBreak = gap
                        longestBreakFrom = previous.timestamp
                        longestBreakTo = entry.timestamp
                    }
                    if previous.authorId != entry.authorId {
                        // Time since the previous message, written by someone else.
                        let pause = entry.timestamp - previous.timestamp
                        if pause >= 0 && pause <= ShadowChatStats.maxReplyPause {
                            self.people[entry.authorId]?.replySamples.append(pause)
                        }
                    }
                }
                let morning = self.clock.morningDay(entry.timestamp)
                if !firstOfDayDays.contains(morning) {
                    firstOfDayDays.insert(morning)
                    self.people[entry.authorId]?.person.firstOfDay += 1
                }
                previous = entry
            }

            // «Кто кого ждёт» (private chats): a turn is a run of messages of one
            // person; the wait is the time from its last message to the
            // other's next one.
            typealias Wait = (long: Int, total: Int, longest: Int, longestAt: Int32, unanswered: Int)
            typealias Turn = (author: Int64, first: Int32, last: Int32)
            let noWait: Wait = (long: 0, total: 0, longest: 0, longestAt: 0, unanswered: 0)
            var waits: [Int64: Wait] = [:]
            if !self.isGroup {
                var turns: [Turn] = []
                for entry in self.order {
                    if let lastTurn = turns.last, lastTurn.author == entry.authorId {
                        turns[turns.count - 1].last = entry.timestamp
                    } else {
                        let turn: Turn = (author: entry.authorId, first: entry.timestamp, last: entry.timestamp)
                        turns.append(turn)
                    }
                }
                for (index, turn) in turns.enumerated() {
                    var value = waits[turn.author] ?? noWait
                    if index + 1 < turns.count {
                        let wait = Int(turns[index + 1].first - turn.last)
                        if wait > ShadowChatStats.unansweredAfter {
                            value.unanswered += 1
                        } else if wait >= ShadowChatStats.longWait {
                            value.long += 1
                            value.total += wait
                        }
                        if wait <= ShadowChatStats.longestWaitLimit && wait > value.longest {
                            value.longest = wait
                            value.longestAt = turn.last
                        }
                    } else if Int(self.to - turn.last) > ShadowChatStats.unansweredAfter {
                        value.unanswered += 1
                    }
                    waits[turn.author] = value
                }
            }

            // Words only one side of a private chat uses.
            var uniqueWords: [Int64: [Count]] = [:]
            if !self.isGroup, self.people.count == 2 {
                let ids = Array(self.people.keys)
                for id in ids {
                    guard let mine = self.people[id], let theirs = self.people.first(where: { $0.key != id })?.value else {
                        continue
                    }
                    let only = mine.words.filter { $0.value >= ShadowChatStats.uniqueWordMinimum && theirs.words[$0.key] == nil }
                    uniqueWords[id] = ShadowChatStats.top(only, limit: 8)
                }
            }

            let (labels, bucket) = self.timelineBuckets()
            var moodBuckets = [[String: Int]](repeating: [:], count: labels.count)
            for (day, moods) in self.dayMoods {
                if let index = bucket(day) {
                    for (mood, count) in moods {
                        moodBuckets[index][mood, default: 0] += count
                    }
                }
            }
            let moodTimeline = moodBuckets.map { counts -> String in
                guard counts.values.reduce(0, +) >= 3, let best = ShadowChatStats.top(counts, limit: 1).first else {
                    return ""
                }
                return best.key
            }

            var result: [Person] = []
            for (_, acc) in self.people {
                var person = acc.person
                person.moods = ShadowChatStats.top(acc.moods, limit: Mood.allCases.count)
                if !self.isGroup {
                    person.uniqueWords = uniqueWords[person.id] ?? []
                    let wait = waits[person.id] ?? noWait
                    person.waitLongCount = wait.long
                    person.waitTotalSeconds = wait.total
                    person.waitLongest = wait.longest
                    person.waitLongestAt = wait.longest > 0 ? wait.longestAt : nil
                    person.unanswered = wait.unanswered
                }
                person.emoji = ShadowChatStats.top(acc.emoji, limit: 8)
                person.topStickers = ShadowChatStats.top(acc.stickers, limit: 5, labels: acc.stickerLabels)
                person.reactions = ShadowChatStats.top(acc.reactions, limit: 6)
                person.topWords = ShadowChatStats.top(acc.words, limit: 10)
                person.replySeconds = ShadowChatStats.median(acc.replySamples)
                person.replySamples = acc.replySamples.count
                if let best = acc.days.max(by: { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key }) {
                    person.bestDay = DayCount(day: best.key, count: best.value)
                }
                var timeline = [Int](repeating: 0, count: labels.count)
                for (day, count) in acc.days {
                    if let index = bucket(day) {
                        timeline[index] += count
                    }
                }
                person.timeline = timeline
                if person.messages > 0 || person.calls > 0 || person.reactions.count > 0 || !self.isGroup {
                    result.append(person)
                }
            }
            result.sort(by: { lhs, rhs in
                if lhs.id == self.accountPeerId && !self.isGroup {
                    return true
                }
                if rhs.id == self.accountPeerId && !self.isGroup {
                    return false
                }
                if lhs.messages != rhs.messages {
                    return lhs.messages > rhs.messages
                }
                return lhs.id < rhs.id
            })

            // "Общаемся N дней подряд": days on which both sides wrote.
            var streakCurrent = 0
            var streakBest = 0
            if !self.isGroup, let me = self.people[self.accountPeerId], let other = self.people.first(where: { $0.key != self.accountPeerId })?.value {
                let both = Set(me.days.keys).intersection(other.days.keys)
                let streaks = ShadowChatStats.streaks(days: both, today: self.clock.day(generated))
                streakCurrent = streaks.current
                streakBest = streaks.best
            }

            var bestDay: DayCount?
            if let best = self.chatDays.max(by: { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key }) {
                bestDay = DayCount(day: best.key, count: best.value)
            }

            // Records: the busiest clock hour joins the per-message ones.
            if let busiest = self.hourSlots.max(by: { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key }), busiest.value > 1 {
                self.record("hour", authorId: 0, value: busiest.value, timestamp: Int32(clamping: busiest.key * 3600 - Int64(self.clock.offset)))
            }
            let recordOrder = ["text", "voice", "round", "call", "hour"]
            let records = recordOrder.compactMap { self.records[$0] }

            var pairs: [ReplyPair] = []
            for (key, count) in self.replyPairs {
                let parts = key.split(separator: ":")
                if parts.count == 2, let from = Int64(parts[0]), let to = Int64(parts[1]) {
                    pairs.append(ReplyPair(from: from, to: to, count: count))
                }
            }
            pairs.sort(by: { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return (lhs.from, lhs.to) < (rhs.from, rhs.to)
            })

            var report = Report(
                version: Report.currentVersion,
                accountPeerId: self.accountPeerId,
                peerId: self.peerId,
                title: self.title,
                isGroup: self.isGroup,
                period: self.period,
                from: self.from,
                to: self.to,
                generated: generated,
                meId: self.accountPeerId,
                people: result,
                total: self.order.count,
                daysWithMessages: self.chatDays.count,
                daysInPeriod: Int(self.clock.day(self.to) - self.clock.day(self.from)) + 1,
                firstOfDayDays: firstOfDayDays.count,
                streakCurrent: streakCurrent,
                streakBest: streakBest,
                longestBreak: longestBreak,
                longestBreakFrom: longestBreakFrom,
                longestBreakTo: longestBreakTo,
                bestDay: bestDay,
                timelineLabels: labels,
                heatmap: self.heatmap,
                firstMessage: self.firstMessage,
                timeZoneOffset: self.clock.offset,
                images: [:]
            )
            report.records = records
            report.typicalDay = self.typicalDay()
            report.replyPairs = self.isGroup ? Array(pairs.prefix(20)) : nil
            report.moodTimeline = moodTimeline
            return report
        }

        // Medians over the days (from 4:00) with at least one message.
        private func typicalDay() -> TypicalDay? {
            guard self.morningDays.count >= 2 else {
                return nil
            }
            let shift = Int64(self.clock.offset) - 4 * 3600
            func minuteOfMorningDay(_ timestamp: Int32) -> Int32 {
                return Int32((Int64(timestamp) + shift).floorMod(86400) / 60)
            }
            let values = Array(self.morningDays.values)
            let starts = values.map { minuteOfMorningDay($0.first) }
            let ends = values.map { minuteOfMorningDay($0.last) }
            let spans = values.map { Int32(($0.last - $0.first) / 60) }
            let counts = values.map { Int32($0.count) }
            let toClock: (Int) -> Int = { ($0 + 240) % 1440 }
            let weekdayTotals = self.heatmap.map { $0.reduce(0, +) }
            let busy = weekdayTotals.indices.max(by: { weekdayTotals[$0] != weekdayTotals[$1] ? weekdayTotals[$0] < weekdayTotals[$1] : $0 > $1 }) ?? 0
            let quiet = weekdayTotals.indices.min(by: { weekdayTotals[$0] != weekdayTotals[$1] ? weekdayTotals[$0] < weekdayTotals[$1] : $0 < $1 }) ?? 0
            return TypicalDay(
                days: values.count,
                messages: ShadowChatStats.median(counts) ?? 0,
                startMinute: toClock(ShadowChatStats.median(starts) ?? 0),
                endMinute: toClock(ShadowChatStats.median(ends) ?? 0),
                spanMinutes: ShadowChatStats.median(spans) ?? 0,
                busyWeekday: busy,
                quietWeekday: quiet
            )
        }
    }

    // MARK: - Previous period, two weeks

    public static func summary(_ report: Report) -> PeriodSummary {
        let people = report.people.filter { $0.messages > 0 }.map { PersonCount(id: $0.id, messages: $0.messages) }
        return PeriodSummary(
            from: report.from,
            to: report.to,
            total: report.total,
            daysWithMessages: report.daysWithMessages,
            words: report.people.reduce(0) { $0 + $1.words },
            voiceSeconds: report.people.reduce(0) { $0 + $1.voiceSeconds },
            roundCount: report.people.reduce(0) { $0 + $1.roundCount },
            stickers: report.people.reduce(0) { $0 + $1.stickers },
            calls: report.people.reduce(0) { $0 + $1.calls },
            callSeconds: report.people.reduce(0) { $0 + $1.callSeconds },
            people: people
        )
    }

    // Messages (not calls) per local day: the 7 days ending today and the 7
    // before them.
    public static func twoWeeks(items: [Item], now: Int32, clock: Clock) -> TwoWeeks {
        let today = clock.day(now)
        let firstDay = today - 6
        var current = [Int](repeating: 0, count: 7)
        var previous = [Int](repeating: 0, count: 7)
        for item in items where item.kind != .call && item.timestamp <= now {
            let day = clock.day(item.timestamp)
            if day >= firstDay && day <= today {
                current[Int(day - firstDay)] += 1
            } else if day >= firstDay - 7 && day < firstDay {
                previous[Int(day - firstDay + 7)] += 1
            }
        }
        return TwoWeeks(firstDay: firstDay, current: current, previous: previous)
    }

    // MARK: - Anonymous copy

    // For a shared file without names: the other people become "Собеседник"
    // (private chat) or "Участник N" (group), the chat title goes too.
    public static func anonymized(_ report: Report) -> Report {
        var copy = report
        var index = 0
        copy.people = report.people.map { person in
            var person = person
            if person.id != report.meId {
                index += 1
                person.name = report.isGroup ? "Участник \(index)" : "Собеседник"
            }
            return person
        }
        copy.title = report.isGroup ? "Группа" : "Собеседник"
        copy.peerId = 0
        return copy
    }
}

// MARK: - Storage

// One report per chat: computing it again replaces the old one.
public final class ShadowChatStatsStore {
    public static let shared = ShadowChatStatsStore(directory: ShadowChatStatsStore.defaultDirectory)

    private let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    private static var defaultDirectory: URL? {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("shadow-chat-stats", isDirectory: true)
    }

    private func folder(accountPeerId: Int64) -> URL? {
        return self.directory?.appendingPathComponent(String(accountPeerId), isDirectory: true)
    }

    private func file(accountPeerId: Int64, peerId: Int64) -> URL? {
        return self.folder(accountPeerId: accountPeerId)?.appendingPathComponent("\(peerId).json")
    }

    public func save(_ report: ShadowChatStats.Report) {
        guard let folder = self.folder(accountPeerId: report.accountPeerId), let file = self.file(accountPeerId: report.accountPeerId, peerId: report.peerId) else {
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    public func report(accountPeerId: Int64, peerId: Int64) -> ShadowChatStats.Report? {
        guard let file = self.file(accountPeerId: accountPeerId, peerId: peerId), let data = try? Data(contentsOf: file) else {
            return nil
        }
        return try? JSONDecoder().decode(ShadowChatStats.Report.self, from: data)
    }

    // Newest first.
    public func reports(accountPeerId: Int64) -> [ShadowChatStats.Report] {
        guard let folder = self.folder(accountPeerId: accountPeerId), let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file) else {
                return nil
            }
            return try? JSONDecoder().decode(ShadowChatStats.Report.self, from: data)
        }.sorted(by: { $0.generated > $1.generated })
    }

    public func remove(accountPeerId: Int64, peerId: Int64) {
        if let file = self.file(accountPeerId: accountPeerId, peerId: peerId) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

private extension Int64 {
    func floorDiv(_ divisor: Int64) -> Int64 {
        let quotient = self / divisor
        return (self % divisor != 0 && (self < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    func floorMod(_ divisor: Int64) -> Int64 {
        let remainder = self % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }
}
