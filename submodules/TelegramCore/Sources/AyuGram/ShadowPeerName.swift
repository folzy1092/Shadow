import Foundation

public enum ShadowPeerName {
    // Unknown contact state deliberately preserves the normal title. This is
    // presentation-only: never rewrite Peer names or Telegram contacts.
    public static func username(_ username: String?, enabled: Bool, isContact: Bool?, isSelf: Bool, isBot: Bool = false, botsEnabled: Bool = false) -> String? {
        guard !isBot || botsEnabled else { return nil }
        guard enabled, isContact == false, !isSelf, let username, !username.isEmpty else {
            return nil
        }
        // Keep the @ prefix and adjacent badges stable in RTL interfaces.
        return "\u{2066}@\(username)\u{2069}"
    }
}
