import Foundation

// Shadow: account registration date on the profile screen.
//
// Telegram has no "signup date" field for arbitrary users, so the value comes
// from the best source available, in this order:
//   1. Telegram itself — `peerSettings.registration_month` ("MM.YYYY"), which
//      the server sends for non-contacts (the "new chat" info card). Exact to
//      the month.
//   2. The @ayugrambot inline query `regdate <id>` — the same source AyuGram
//      Desktop uses. Answers EXACT / INTERPOLATED / LT (earlier than) /
//      ET (later than) with a day-precision date.
//   3. A local estimate: piecewise-linear interpolation between known
//      (user id → registration date) anchors. Past the newest anchor the
//      growth rate of the last stretch is extrapolated instead of clamping
//      (the old table clamped every id above 7.5e9 to June 2024).
//
// Every month seen in (1) is stored and becomes an extra anchor for (3), so
// the local estimate keeps improving for new accounts.
//
// Foundation only, so it is unit-tested by the Foundation suite
// (Tests/ShadowSettings/RegistrationDateTests.swift).
public enum ShadowRegistrationDate {
    public enum BotFlag: String, Codable {
        case exact = "EXACT"
        case interpolated = "INTERPOLATED"
        case earlier = "LT"
        case later = "ET"
    }

    public struct BotAnswer: Equatable, Codable {
        public var flag: BotFlag
        // UTC midnight of the date the bot returned.
        public var timestamp: Int64

        public init(flag: BotFlag, timestamp: Int64) {
            self.flag = flag
            self.timestamp = timestamp
        }
    }

    public enum Precision: Equatable {
        case day
        case month
    }

    public enum Value: Equatable {
        // From Telegram: exact month.
        case official(month: Int, year: Int)
        case approximately(timestamp: Int64, precision: Precision)
        case before(timestamp: Int64)
        case after(timestamp: Int64)
    }

    // Known (user id, unix time) points from real accounts, sorted by id and
    // made monotone (pool-adjacent-violators: the raw data has a few
    // "back in time" points). Source: the public dataset of the getids bot.
    public static let staticAnchors: [(Int64, Int64)] = [
        (2768409, 1383264000),       // 2013-11-01
        (7679610, 1388448000),       // 2013-12-31
        (11538514, 1391212000),      // 2014-01-31
        (15835244, 1392940000),      // 2014-02-20
        (23646077, 1393459000),      // 2014-02-26
        (38015510, 1393632000),      // 2014-03-01
        (44634663, 1399334000),      // 2014-05-05
        (46145305, 1400198000),      // 2014-05-15
        (54845238, 1411257000),      // 2014-09-20
        (63263518, 1414454000),      // 2014-10-27
        (101260938, 1425600000),     // 2015-03-06
        (101323197, 1426204000),     // 2015-03-12
        (103258382, 1433073500),     // 2015-05-31
        (111220210, 1434326000),     // 2015-06-14
        (116812045, 1438387000),     // 2015-07-31
        (124872445, 1439856000),     // 2015-08-18
        (130029930, 1442663500),     // 2015-09-19
        (133909606, 1444176000),     // 2015-10-07
        (143445125, 1448928000),     // 2015-12-01
        (152079341, 1450799666),     // 2015-12-22
        (171295414, 1457481000),     // 2016-03-08
        (181783990, 1460246000),     // 2016-04-09
        (222021233, 1465344000),     // 2016-06-08
        (225034354, 1466208000),     // 2016-06-18
        (278941742, 1473465000),     // 2016-09-09
        (285253072, 1476835000),     // 2016-10-18
        (294851037, 1479600000),     // 2016-11-20
        (297621225, 1481846000),     // 2016-12-15
        (328594461, 1482969000),     // 2016-12-28
        (337808429, 1487707000),     // 2017-02-21
        (341546272, 1487782000),     // 2017-02-22
        (352940995, 1487894000),     // 2017-02-23
        (369669043, 1490918000),     // 2017-03-30
        (400169472, 1501459000),     // 2017-07-30
        (805158066, 1563208000),     // 2019-07-15
        (1974255900, 1634000000),    // 2021-10-12
        (5795034000, 1662076800),    // 2022-09-02
        (6227468000, 1679270400),    // 2023-03-20
        (7583599300, 1739664000),    // 2025-02-16
        (7947063900, 1754092800),    // 2025-08-02
        (8235679900, 1758758400)     // 2025-09-25
    ]

    // How far back (in ids) the extrapolation looks for its slope, so a
    // single close pair of anchors does not dictate the growth rate.
    static let extrapolationSpan: Int64 = 300_000_000

    // Pool-adjacent-violators: returns anchors sorted by id whose dates never
    // go down. Conflicting neighbours are averaged into one point.
    public static func monotone(_ points: [(Int64, Int64)]) -> [(Int64, Int64)] {
        var byId: [Int64: Int64] = [:]
        for (id, timestamp) in points where id > 0 && timestamp > 0 {
            byId[id] = timestamp
        }
        let sorted = byId.sorted { $0.key < $1.key }
        // (sum of timestamps, count, ids)
        var blocks: [(sum: Double, count: Int, ids: [Int64])] = []
        for (id, timestamp) in sorted {
            blocks.append((Double(timestamp), 1, [id]))
            while blocks.count > 1 {
                let last = blocks[blocks.count - 1]
                let previous = blocks[blocks.count - 2]
                if previous.sum / Double(previous.count) <= last.sum / Double(last.count) {
                    break
                }
                blocks.removeLast()
                blocks[blocks.count - 1] = (previous.sum + last.sum, previous.count + last.count, previous.ids + last.ids)
            }
        }
        return blocks.map { block in
            return (block.ids[block.ids.count / 2], Int64(block.sum / Double(block.count)))
        }
    }

    // Local estimate. `extrapolated` is true when the id is newer than every
    // anchor and the date is a projection.
    public static func estimate(userId: Int64, anchors: [(Int64, Int64)], now: Int64) -> (timestamp: Int64, extrapolated: Bool)? {
        if userId <= 0 || anchors.isEmpty {
            return nil
        }
        let first = anchors[0]
        if userId <= first.0 {
            return (min(first.1, now), false)
        }
        let last = anchors[anchors.count - 1]
        if userId >= last.0 {
            if userId == last.0 || anchors.count < 2 {
                return (min(last.1, now), false)
            }
            var base = anchors[anchors.count - 2]
            for anchor in anchors.reversed() where last.0 - anchor.0 >= ShadowRegistrationDate.extrapolationSpan {
                base = anchor
                break
            }
            let slope = Double(last.1 - base.1) / Double(last.0 - base.0)
            let projected = Double(last.1) + slope * Double(userId - last.0)
            let clamped = max(Double(last.1), min(projected, Double(now)))
            return (Int64(clamped), true)
        }
        var low = 0
        var high = anchors.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if anchors[middle].0 <= userId {
                low = middle
            } else {
                high = middle
            }
        }
        let (lowId, lowTimestamp) = anchors[low]
        let (highId, highTimestamp) = anchors[high]
        let fraction = Double(userId - lowId) / Double(highId - lowId)
        let value = Double(lowTimestamp) + Double(highTimestamp - lowTimestamp) * fraction
        return (min(Int64(value), now), false)
    }

    // Telegram's `registration_month`: "MM.YYYY".
    public static func parseOfficialMonth(_ text: String) -> (month: Int, year: Int)? {
        let parts = text.split(separator: ".")
        guard parts.count == 2, let month = Int(parts[0]), let year = Int(parts[1]), (1 ... 12).contains(month), year >= 2013, year <= 2100 else {
            return nil
        }
        return (month, year)
    }

    // Middle of the official month, used as a learned anchor.
    public static func officialAnchorTimestamp(month: Int, year: Int) -> Int64? {
        return utcTimestamp(day: 15, month: month, year: year)
    }

    // The bot's inline answer: {"flag": "EXACT", "date": "12.10.2021"}.
    public static func parseBotAnswer(_ text: String) -> BotAnswer? {
        guard let data = text.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        guard let flagText = object["flag"] as? String, let flag = BotFlag(rawValue: flagText), let dateText = object["date"] as? String else {
            return nil
        }
        let parts = dateText.split(separator: ".")
        guard parts.count == 3, let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]), let timestamp = utcTimestamp(day: day, month: month, year: year) else {
            return nil
        }
        return BotAnswer(flag: flag, timestamp: timestamp)
    }

    public static func resolve(userId: Int64, official: String?, bot: BotAnswer?, anchors: [(Int64, Int64)], now: Int64) -> Value? {
        if let official, let parsed = parseOfficialMonth(official) {
            return .official(month: parsed.month, year: parsed.year)
        }
        let local = estimate(userId: userId, anchors: anchors, now: now)
        if let bot {
            switch bot.flag {
            case .exact, .interpolated:
                return .approximately(timestamp: bot.timestamp, precision: .day)
            case .earlier:
                // "Registered before X": the local estimate is more precise
                // when it agrees with the bound.
                if let local, local.timestamp < bot.timestamp {
                    return .approximately(timestamp: local.timestamp, precision: .month)
                }
                return .before(timestamp: bot.timestamp)
            case .later:
                // "Registered after X" — typical for accounts newer than the
                // bot's data.
                if let local, local.timestamp > bot.timestamp {
                    return .approximately(timestamp: local.timestamp, precision: .month)
                }
                return .after(timestamp: bot.timestamp)
            }
        }
        if let local {
            return .approximately(timestamp: local.timestamp, precision: .month)
        }
        return nil
    }

    private static let monthsNominative = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
    private static let monthsGenitive = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    public static func text(_ value: Value) -> String {
        switch value {
        case let .official(month, year):
            return capitalized("\(monthsNominative[month - 1]) \(year) г.")
        case let .approximately(timestamp, precision):
            let components = utcComponents(timestamp)
            switch precision {
            case .day:
                return "≈ \(components.day) \(monthsGenitive[components.month - 1]) \(components.year) г."
            case .month:
                return "≈ \(monthsNominative[components.month - 1]) \(components.year) г."
            }
        case let .before(timestamp):
            let components = utcComponents(timestamp)
            return "Раньше \(components.day) \(monthsGenitive[components.month - 1]) \(components.year) г."
        case let .after(timestamp):
            let components = utcComponents(timestamp)
            return "Позже \(components.day) \(monthsGenitive[components.month - 1]) \(components.year) г."
        }
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return first.uppercased() + text.dropFirst()
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func utcTimestamp(day: Int, month: Int, year: Int) -> Int64? {
        guard (1 ... 12).contains(month), (1 ... 31).contains(day), year >= 2013, year <= 2100 else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = utcCalendar.date(from: components) else {
            return nil
        }
        return Int64(date.timeIntervalSince1970)
    }

    static func utcComponents(_ timestamp: Int64) -> (day: Int, month: Int, year: Int) {
        let components = utcCalendar.dateComponents([.day, .month, .year], from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        return (components.day ?? 1, components.month ?? 1, components.year ?? 1970)
    }
}

// Persistent part: official months seen from Telegram and bot answers, kept
// on the device. Thread-safe; posts `didChangeNotification` (on the main
// queue) when something new arrives, so an open profile refreshes.
public final class ShadowRegistrationDateStore {
    public static let shared = ShadowRegistrationDateStore(
        fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("shadow-registration-dates.json")
    )

    public static let didChangeNotification = Notification.Name("ShadowRegistrationDateDidChange")

    // A failed or empty bot answer is retried after this long.
    public static let failedRetryInterval: Double = 24 * 60 * 60
    // A successful answer is refreshed after this long (the bot's data grows).
    public static let answerRefreshInterval: Double = 90 * 24 * 60 * 60
    static let maximumEntries = 3000

    private struct BotEntry: Codable {
        var answer: ShadowRegistrationDate.BotAnswer?
        var fetchedAt: Double
    }

    private struct Contents: Codable {
        // user id -> "MM.YYYY"
        var official: [String: String] = [:]
        var bot: [String: BotEntry] = [:]
    }

    private let fileURL: URL?
    private let lock = NSLock()
    private var contents = Contents()
    private var loaded = false
    private var inFlight = Set<Int64>()
    private var cachedAnchors: [(Int64, Int64)]?

    // `fileURL == nil` keeps everything in memory (tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    private func ensureLoaded() {
        if self.loaded {
            return
        }
        self.loaded = true
        if let fileURL = self.fileURL, let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(Contents.self, from: data) {
            self.contents = decoded
        }
    }

    private func save() {
        guard let fileURL = self.fileURL, let data = try? JSONEncoder().encode(self.contents) else {
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: ShadowRegistrationDateStore.didChangeNotification, object: nil)
        }
    }

    // Returns true if this is new information.
    @discardableResult
    public func recordOfficial(userId: Int64, month: String) -> Bool {
        guard userId > 0, ShadowRegistrationDate.parseOfficialMonth(month) != nil else {
            return false
        }
        self.lock.lock()
        self.ensureLoaded()
        let key = String(userId)
        if self.contents.official[key] == month {
            self.lock.unlock()
            return false
        }
        if self.contents.official.count >= ShadowRegistrationDateStore.maximumEntries {
            // Keep the newest ids: they are the ones the static table lacks.
            let keep = self.contents.official.sorted { (Int64($0.key) ?? 0) > (Int64($1.key) ?? 0) }.prefix(ShadowRegistrationDateStore.maximumEntries / 2)
            self.contents.official = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        self.contents.official[key] = month
        self.cachedAnchors = nil
        self.save()
        self.lock.unlock()
        self.notifyChanged()
        return true
    }

    public func officialMonth(userId: Int64) -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.ensureLoaded()
        return self.contents.official[String(userId)]
    }

    public func botAnswer(userId: Int64) -> ShadowRegistrationDate.BotAnswer? {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.ensureLoaded()
        return self.contents.bot[String(userId)]?.answer
    }

    // Marks a fetch as started. Returns false if one is running or a cached
    // answer is still fresh.
    public func beginBotFetch(userId: Int64, now: Double) -> Bool {
        guard userId > 0 else {
            return false
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        self.ensureLoaded()
        if self.inFlight.contains(userId) {
            return false
        }
        if let entry = self.contents.bot[String(userId)] {
            let age = now - entry.fetchedAt
            let interval = entry.answer == nil ? ShadowRegistrationDateStore.failedRetryInterval : ShadowRegistrationDateStore.answerRefreshInterval
            if age >= 0 && age < interval {
                return false
            }
        }
        self.inFlight.insert(userId)
        return true
    }

    // `answer == nil` records a failure (retried later). A failure never
    // replaces an earlier successful answer.
    public func finishBotFetch(userId: Int64, answer: ShadowRegistrationDate.BotAnswer?, now: Double) {
        self.lock.lock()
        self.ensureLoaded()
        self.inFlight.remove(userId)
        let key = String(userId)
        let previous = self.contents.bot[key]
        var changed = false
        if let answer {
            changed = previous?.answer != answer
            self.contents.bot[key] = BotEntry(answer: answer, fetchedAt: now)
        } else if let previousAnswer = previous?.answer {
            // Keep the old answer, try again after the short interval.
            self.contents.bot[key] = BotEntry(answer: previousAnswer, fetchedAt: now - ShadowRegistrationDateStore.answerRefreshInterval + ShadowRegistrationDateStore.failedRetryInterval)
        } else {
            self.contents.bot[key] = BotEntry(answer: nil, fetchedAt: now)
        }
        if self.contents.bot.count > ShadowRegistrationDateStore.maximumEntries {
            let keep = self.contents.bot.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(ShadowRegistrationDateStore.maximumEntries / 2)
            self.contents.bot = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        self.save()
        self.lock.unlock()
        if changed {
            self.notifyChanged()
        }
    }

    // Static anchors plus every official month seen, made monotone.
    public func anchors() -> [(Int64, Int64)] {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.ensureLoaded()
        if let cachedAnchors = self.cachedAnchors {
            return cachedAnchors
        }
        var points = ShadowRegistrationDate.staticAnchors
        for (key, month) in self.contents.official {
            if let userId = Int64(key), let parsed = ShadowRegistrationDate.parseOfficialMonth(month), let timestamp = ShadowRegistrationDate.officialAnchorTimestamp(month: parsed.month, year: parsed.year) {
                points.append((userId, timestamp))
            }
        }
        let result = ShadowRegistrationDate.monotone(points)
        self.cachedAnchors = result
        return result
    }

    public func value(userId: Int64, official: String?, now: Int64) -> ShadowRegistrationDate.Value? {
        let official = official ?? self.officialMonth(userId: userId)
        return ShadowRegistrationDate.resolve(userId: userId, official: official, bot: self.botAnswer(userId: userId), anchors: self.anchors(), now: now)
    }
}
