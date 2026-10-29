import Foundation
import Postbox
import SwiftSignalKit

// Shadow 2.0.0: «Диапазон» in the chat's selection panel. With two or more
// messages selected it selects every message between the first and the last;
// with one, everything from it to the newest message or to the start of the
// chat. Only messages stored on this device count (what the chat has loaded,
// plus kept deleted ones); a part of the history never loaded is skipped.
public enum ShadowRangeSelection {
    public enum Direction {
        case between(EngineMessage.Id, EngineMessage.Id)
        case toNewest(EngineMessage.Id)
        case toOldest(EngineMessage.Id)
    }

    // A chat holds far fewer stored messages than this in practice.
    public static let scanLimit = 200_000

    public static func messageIds(account: Account, peerId: PeerId, threadId: Int64?, direction: Direction) -> Signal<[EngineMessage.Id], NoError> {
        return account.postbox.transaction { transaction -> [EngineMessage.Id] in
            let lower: Int32
            let upper: Int32
            switch direction {
            case let .between(a, b):
                lower = min(a.id, b.id)
                upper = max(a.id, b.id)
            case let .toNewest(id):
                lower = id.id
                upper = Int32.max
            case let .toOldest(id):
                lower = Int32.min
                upper = id.id
            }
            var result: [EngineMessage.Id] = []
            transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: ShadowRangeSelection.scanLimit, { message in
                if message.id.id < lower {
                    return false
                }
                if message.id.id <= upper, threadId == nil || message.threadId == threadId {
                    result.append(message.id)
                }
                return true
            })
            return result
        }
    }
}
