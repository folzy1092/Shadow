import Foundation
import Postbox

// Shadow: the Bot API form of a peer id — users positive, basic groups negated,
// channels and supergroups as -100…. This is the id people copy from bots and
// from the profile's «ID профиля» row, so settings that take a chat id by hand
// (spy exclusions) read and show it in this form.
public enum ShadowBotApiPeerId {
    private static let channelOffset: Int64 = 1_000_000_000_000
    // PeerId.Id asserts on anything wider than 56 bits.
    private static let maxRawId: Int64 = 0x00ffffffffffffff

    public static func botApiId(_ peerId: PeerId) -> Int64 {
        let raw = peerId.id._internalGetInt64Value()
        if peerId.namespace == Namespaces.Peer.CloudChannel {
            return -(channelOffset + raw)
        } else if peerId.namespace == Namespaces.Peer.CloudGroup {
            return -raw
        } else {
            return raw
        }
    }

    // nil for anything that is not a valid Bot API id: text, zero, ids out of range.
    public static func peerId(parsing text: String) -> PeerId? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int64(trimmed), value != 0, value != Int64.min else {
            return nil
        }
        if value > 0 {
            return peerId(namespace: Namespaces.Peer.CloudUser, raw: value)
        }
        if value <= -channelOffset {
            return peerId(namespace: Namespaces.Peer.CloudChannel, raw: -value - channelOffset)
        }
        return peerId(namespace: Namespaces.Peer.CloudGroup, raw: -value)
    }

    private static func peerId(namespace: PeerId.Namespace, raw: Int64) -> PeerId? {
        guard raw > 0, raw <= maxRawId else {
            return nil
        }
        return PeerId(namespace: namespace, id: PeerId.Id._internalFromInt64Value(raw))
    }
}
