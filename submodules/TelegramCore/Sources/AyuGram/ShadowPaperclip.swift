import Foundation

// Shadow: «Меню скрепки». With AyuGramSettings.paperclipMenu on, holding the
// attachment (paperclip) button in a chat opens a menu of quick actions chosen
// in «Кастомизация → Чаты и звонки → Действия скрепки» (up to maxActions):
//
//   - an activity imitation mode (ShadowActivityImitationMode): «печатает»,
//     «записывает кружок», … until stopped from the same menu;
//   - a prank from the admin catalog (shadow-whitelist.json → paperclip_pranks,
//     edited in «Доступ устройств»): a post of a public channel, e.g. the
//     «longest» voice message, forwarded into the chat without the author. With
//     paperclipPrankImitation a voice or round video is preceded by
//     «записывает…» for paperclipPrankSeconds, then «отправляет…» for
//     paperclipPrankSendSeconds (1.14.0; 0 skips that phase);
//   - a prank of the user's own (1.14.0): a post of a public channel added by
//     link in «Действия скрепки → Мои приколы», kept on this device
//     (ShadowPaperclipUserPrankStore) and listed with the catalog's.
//
// The chosen actions are stored as one string, "a1,a2,pkartinki5222/93":
// "a<mode>" for an imitation, "p<channel>/<post>" for a prank. Foundation only,
// so it is unit-tested by the Foundation suite.
public enum ShadowPaperclip {
    public static let maxActions = 20
    public static let defaultPrankSeconds: Int32 = 5
    public static let prankSecondsRange: ClosedRange<Int32> = 1 ... 60
    public static let defaultPrankSendSeconds: Int32 = 2
    public static let prankSendSecondsRange: ClosedRange<Int32> = 0 ... 60
    // «Печатает», «Записывает голосовое», «Записывает кружок».
    public static let defaultActions = "a0,a1,a2"

    public enum Action: Hashable {
        case imitation(ShadowActivityImitationMode)
        case prank(id: String)

        public var storageId: String {
            switch self {
            case let .imitation(mode):
                return "a\(mode.rawValue)"
            case let .prank(id):
                return "p\(id)"
            }
        }

        public init?(storageId: String) {
            let value = storageId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = value.first else {
                return nil
            }
            let rest = String(value.dropFirst())
            switch first {
            case "a":
                guard let raw = Int32(rest), let mode = ShadowActivityImitationMode(rawValue: raw) else {
                    return nil
                }
                self = .imitation(mode)
            case "p":
                guard let link = ShadowPaperclip.parsePrankId(rest) else {
                    return nil
                }
                self = .prank(id: ShadowPaperclip.prankId(channel: link.channel, messageId: link.messageId))
            default:
                return nil
            }
        }
    }

    // A post of a public channel sent by a prank action.
    public struct Prank: Equatable {
        public let title: String
        public let channel: String
        public let messageId: Int32

        public init(title: String, channel: String, messageId: Int32) {
            self.title = title
            self.channel = channel
            self.messageId = messageId
        }

        public var id: String {
            return ShadowPaperclip.prankId(channel: self.channel, messageId: self.messageId)
        }

        public var url: String {
            return "https://t.me/\(self.channel)/\(self.messageId)"
        }
    }

    public static func normalizedPrankSeconds(_ value: Int32) -> Int32 {
        return min(prankSecondsRange.upperBound, max(prankSecondsRange.lowerBound, value))
    }

    public static func normalizedPrankSendSeconds(_ value: Int32) -> Int32 {
        return min(prankSendSecondsRange.upperBound, max(prankSendSecondsRange.lowerBound, value))
    }

    // Known actions, in order, without duplicates, at most maxActions.
    public static func parseActions(_ value: String) -> [Action] {
        var result: [Action] = []
        for part in value.split(separator: ",") {
            guard let action = Action(storageId: String(part)), !result.contains(action) else {
                continue
            }
            result.append(action)
            if result.count == maxActions {
                break
            }
        }
        return result
    }

    public static func encodeActions(_ actions: [Action]) -> String {
        return actions.prefix(maxActions).map { $0.storageId }.joined(separator: ",")
    }

    public static func normalizedActions(_ value: String) -> String {
        return encodeActions(parseActions(value))
    }

    // Checks or unchecks an action. nil when it would be one too many.
    public static func toggled(_ actions: [Action], _ action: Action) -> [Action]? {
        if let index = actions.firstIndex(of: action) {
            var result = actions
            result.remove(at: index)
            return result
        }
        guard actions.count < maxActions else {
            return nil
        }
        return actions + [action]
    }

    static func prankId(channel: String, messageId: Int32) -> String {
        return "\(channel.lowercased())/\(messageId)"
    }

    // "channel/93" → (channel, 93).
    static func parsePrankId(_ value: String) -> (channel: String, messageId: Int32)? {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let channel = normalizedChannel(String(parts[0])), let messageId = Int32(parts[1]), messageId > 0 else {
            return nil
        }
        return (channel, messageId)
    }

    // "https://t.me/kartinki5222/93", "t.me/kartinki5222/93?single",
    // "@kartinki5222/93" → (kartinki5222, 93). Private links (t.me/c/…) are not
    // supported: the post must be readable by everyone who gets the catalog.
    public static func parsePrankLink(_ value: String) -> (channel: String, messageId: Int32)? {
        var link = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where link.lowercased().hasPrefix(prefix) {
            link = String(link.dropFirst(prefix.count))
        }
        for prefix in ["www.t.me/", "t.me/", "telegram.me/", "telegram.dog/"] where link.lowercased().hasPrefix(prefix) {
            link = String(link.dropFirst(prefix.count))
        }
        if link.hasPrefix("@") {
            link.removeFirst()
        }
        if let query = link.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            link = String(link[..<query])
        }
        while link.hasSuffix("/") {
            link.removeLast()
        }
        guard !link.lowercased().hasPrefix("c/") else {
            return nil
        }
        return parsePrankId(link)
    }

    static func normalizedChannel(_ value: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard value.count >= 4, value.count <= 32, value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return value
    }

    // shadow-whitelist.json → paperclip_pranks: [{"title": "…", "url": "…"}].
    // Bad entries and duplicates are skipped; at most maxPranks.
    public static let maxPranks = 50
    public static let maxTitleLength = 48

    public static func parsePranks(_ object: Any?) -> [Prank] {
        var result: [Prank] = []
        for entry in (object as? [[String: Any]]) ?? [] {
            guard let url = entry["url"] as? String, let link = parsePrankLink(url) else {
                continue
            }
            let title = String(((entry["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTitleLength))
            let prank = Prank(title: title.isEmpty ? "Прикол" : title, channel: link.channel, messageId: link.messageId)
            if result.contains(where: { $0.id == prank.id }) {
                continue
            }
            result.append(prank)
            if result.count == maxPranks {
                break
            }
        }
        return result
    }

    public static func encodePranks(_ pranks: [Prank]) -> [[String: Any]] {
        return pranks.map { ["title": $0.title, "url": $0.url] }
    }

    // The menu: the chosen actions that still exist (a prank removed from the
    // catalog disappears from the menu).
    public static func menuActions(_ actions: [Action], pranks: [Prank]) -> [Action] {
        return actions.filter { action in
            switch action {
            case .imitation:
                return true
            case let .prank(id):
                return pranks.contains(where: { $0.id == id })
            }
        }
    }

    // What a prank imitates before it is sent, by what the post holds.
    public enum PrankMedia {
        case voice
        case roundVideo
        case video
        case photo
        case audio
        case file
        case sticker
        case text
    }

    // The second phase, after «записывает…»: only a voice message and a round
    // video are recorded first and then uploaded; every other kind already
    // imitates its upload in the first phase.
    public static func sendingMode(for media: PrankMedia) -> ShadowActivityImitationMode? {
        switch media {
        case .voice: return .sendingAudio
        case .roundVideo: return .sendingRound
        default: return nil
        }
    }

    // The menu's pranks: the user's own first, then the catalog's that are not
    // also the user's.
    public static func mergedPranks(user: [Prank], catalog: [Prank]) -> [Prank] {
        var result = user
        for prank in catalog where !result.contains(where: { $0.id == prank.id }) {
            result.append(prank)
        }
        return result
    }

    public enum UserPrankError: Error, Equatable {
        // Not a post of a public channel (t.me/<channel>/<post>).
        case badLink
        case duplicate
        case full
    }

    // Adds a prank of the user's own, at the end.
    public static func addingUserPrank(_ pranks: [Prank], title: String, link: String) -> Result<[Prank], UserPrankError> {
        guard let parsed = parsePrankLink(link) else {
            return .failure(.badLink)
        }
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTitleLength))
        let prank = Prank(title: trimmed.isEmpty ? "Прикол" : trimmed, channel: parsed.channel, messageId: parsed.messageId)
        if pranks.contains(where: { $0.id == prank.id }) {
            return .failure(.duplicate)
        }
        if pranks.count >= maxPranks {
            return .failure(.full)
        }
        return .success(pranks + [prank])
    }

    public static func removingUserPrank(_ pranks: [Prank], id: String) -> [Prank] {
        return pranks.filter { $0.id != id }
    }

    public static func imitationMode(for media: PrankMedia) -> ShadowActivityImitationMode {
        switch media {
        case .voice: return .recordingVoice
        case .roundVideo: return .recordingRound
        case .video: return .sendingVideo
        case .photo: return .sendingPhoto
        case .audio: return .sendingAudio
        case .file: return .sendingFile
        case .sticker: return .choosingSticker
        case .text: return .typing
        }
    }
}
