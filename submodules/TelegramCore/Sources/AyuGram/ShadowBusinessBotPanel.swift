import Foundation

// Shadow: the chat header when a business bot manages the chat. Telegram shows
// only the bot panel then, and the pinned message disappears until the bot is
// removed. AyuGramSettings.businessBotPinned (on by default) keeps both;
// businessBotPinnedLayout picks how:
//
//   0 Пополам          one row: the bot on one half (avatar, name, Стоп/Старт,
//                      settings), the pinned message on the other
//   1 Друг под другом  the full bot panel and the full pinned panel, one under
//                      the other
//   2 Значок бота      the pinned message over the whole row, the bot is its
//                      avatar; a tap opens Стоп/Старт and the settings menu
//   3 Только закреп    the pinned message only; the bot panel comes back when
//                      nothing is pinned
//
// businessBotPinnedFirst puts the pinned message first (left / on top),
// businessBotPinnedCompact drops the bot name in «Пополам» so the pinned
// message gets the rest of the row. Off: stock Telegram (the bot panel).
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowBusinessBotPanel {
    public enum Layout: Int32, CaseIterable {
        case split = 0
        case stacked = 1
        case icon = 2
        case pinnedOnly = 3

        public var title: String {
            switch self {
            case .split: return "Пополам"
            case .stacked: return "Друг под другом"
            case .icon: return "Значок бота"
            case .pinnedOnly: return "Только закреп"
            }
        }

        public var details: String {
            switch self {
            case .split: return "Бот и закреп в одной строке"
            case .stacked: return "Две полные панели"
            case .icon: return "Закреп во всю строку, бот — аватаркой"
            case .pinnedOnly: return "Бот виден, когда закрепа нет"
            }
        }

        public static func normalized(_ raw: Int32) -> Layout {
            return Layout(rawValue: raw) ?? .split
        }
    }

    public static let layouts: [Int32] = Layout.allCases.map { $0.rawValue }

    // What the chat header shows.
    public enum Arrangement: Equatable {
        case bot
        case pinned
        case combined(Layout)
    }

    // nil: neither a managing bot nor a pinned message to show.
    public static func arrangement(enabled: Bool, layout: Int32, hasBot: Bool, hasPinned: Bool) -> Arrangement? {
        switch (hasBot, hasPinned) {
        case (false, false):
            return nil
        case (true, false):
            return .bot
        case (false, true):
            return .pinned
        case (true, true):
            guard enabled else {
                return .bot
            }
            let layout = Layout.normalized(layout)
            if layout == .pinnedOnly {
                return .pinned
            }
            return .combined(layout)
        }
    }

    // The layout a chat uses: its own (ShadowBusinessBotChatLayoutStore), which
    // works even with the global toggle off, else the global settings.
    public static func effective(enabled: Bool, layout: Int32, chatLayout: Int32?) -> (enabled: Bool, layout: Int32) {
        if let chatLayout, Layout(rawValue: chatLayout) != nil {
            return (true, chatLayout)
        }
        return (enabled, layout)
    }

    // The bot's share of a «Пополам» row. Without the name the bot takes what
    // its avatar and buttons need (contentWidth); either way the pinned
    // message keeps at least minimumPinnedWidth.
    public static func splitBotWidth(totalWidth: Double, compact: Bool, contentWidth: Double, minimumPinnedWidth: Double = 120.0) -> Double {
        let maximum = max(0.0, totalWidth - minimumPinnedWidth)
        let wanted = compact ? contentWidth : (totalWidth * 0.5).rounded(.down)
        return min(max(0.0, wanted), maximum)
    }
}

// Shadow: «Бот и закреп» for one chat (the chat's «Shadow ›» menu in the list):
// its own layout instead of the one in Кастомизация. Per account and chat, in
// UserDefaults of this device; nil — like everywhere.
public final class ShadowBusinessBotChatLayoutStore {
    public static let shared = ShadowBusinessBotChatLayoutStore(defaults: .standard)
    public static let didChangeNotification = Notification.Name("ShadowBusinessBotChatLayoutStore.didChange")

    private let defaults: UserDefaults
    private let key = "shadow.businessBotChatLayouts.v1"
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func chatKey(accountPeerId: Int64, peerId: Int64) -> String {
        return "\(accountPeerId)/\(peerId)"
    }

    public func layout(accountPeerId: Int64, peerId: Int64) -> Int32? {
        self.lock.lock()
        defer { self.lock.unlock() }
        let all = (self.defaults.dictionary(forKey: self.key) as? [String: Int]) ?? [:]
        guard let value = all[self.chatKey(accountPeerId: accountPeerId, peerId: peerId)], ShadowBusinessBotPanel.Layout(rawValue: Int32(value)) != nil else {
            return nil
        }
        return Int32(value)
    }

    public func setLayout(_ layout: Int32?, accountPeerId: Int64, peerId: Int64) {
        self.lock.lock()
        var all = (self.defaults.dictionary(forKey: self.key) as? [String: Int]) ?? [:]
        let chatKey = self.chatKey(accountPeerId: accountPeerId, peerId: peerId)
        if let layout, ShadowBusinessBotPanel.Layout(rawValue: layout) != nil {
            all[chatKey] = Int(layout)
        } else {
            all.removeValue(forKey: chatKey)
        }
        self.defaults.set(all, forKey: self.key)
        self.lock.unlock()
        NotificationCenter.default.post(name: ShadowBusinessBotChatLayoutStore.didChangeNotification, object: nil)
    }
}
