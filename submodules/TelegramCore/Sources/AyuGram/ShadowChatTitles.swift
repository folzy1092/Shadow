import Foundation

// Shadow: «Своё название» — a chat, channel, group, bot or person renamed only
// on this device. Telegram lets you rename contacts only; this works for any
// chat. The name replaces the real one in the chat list, the chat header, the
// profile and message author names (EnginePeer.shadowDisplayTitle in
// LocalizedPeerData, ChatTitleView/ChatTitleComponent). Set from the chat's
// «Shadow ›» menu in the list; an empty name gives the real one back.
//
// Stored per account in UserDefaults of this device; not synced and not
// exported (titles belong to the account's chats).
//
// Foundation only, so it is unit-tested by the Foundation suite.
public final class ShadowChatTitleStore {
    public static let shared = ShadowChatTitleStore(defaults: .standard)
    public static let didChangeNotification = Notification.Name("ShadowChatTitleStore.didChange")
    public static let maxLength = 64

    private let defaults: UserDefaults
    private let key = "shadow.chatTitles.v1"
    private let lock = NSLock()
    private var cache: [String: String]?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func chatKey(accountPeerId: Int64, peerId: Int64) -> String {
        return "\(accountPeerId)/\(peerId)"
    }

    private func loadLocked() -> [String: String] {
        if let cache = self.cache {
            return cache
        }
        let value = (self.defaults.dictionary(forKey: self.key) as? [String: String]) ?? [:]
        self.cache = value
        return value
    }

    // Read on every title draw, so it is served from memory.
    public func title(accountPeerId: Int64, peerId: Int64) -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.loadLocked()[self.chatKey(accountPeerId: accountPeerId, peerId: peerId)]
    }

    // Trimmed, one line, at most maxLength characters; empty — nil.
    public static func normalized(_ title: String?) -> String? {
        guard let title else {
            return nil
        }
        let line = title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            return nil
        }
        return String(line.prefix(maxLength))
    }

    public func setTitle(_ title: String?, accountPeerId: Int64, peerId: Int64) {
        self.lock.lock()
        var all = self.loadLocked()
        let chatKey = self.chatKey(accountPeerId: accountPeerId, peerId: peerId)
        if let title = ShadowChatTitleStore.normalized(title) {
            all[chatKey] = title
        } else {
            all.removeValue(forKey: chatKey)
        }
        self.cache = all
        self.defaults.set(all, forKey: self.key)
        self.lock.unlock()
        NotificationCenter.default.post(name: ShadowChatTitleStore.didChangeNotification, object: nil)
    }
}
