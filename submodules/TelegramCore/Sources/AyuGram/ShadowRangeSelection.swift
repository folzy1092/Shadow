import Foundation
import Postbox
import SwiftSignalKit

// Shadow 2.0.0: «Диапазон» in the chat's selection panel. With two or more
// messages selected it selects every message between the first and the last;
// with one, everything from it to the newest message or to the start of the
// chat.
//
// Shadow 2.2.5: parts of the range the device has never loaded are downloaded
// first (the same history requests as scrolling, one at a time, up to
// `maxFillRequests`), then the range is read from the local database. Before
// that only what the chat had already loaded counted, so in a comments thread
// with 41 comments of which the screen had shown 16 the range selected 16.
public enum ShadowRangeSelection {
    public enum Direction {
        case between(EngineMessage.Id, EngineMessage.Id)
        case toNewest(EngineMessage.Id)
        case toOldest(EngineMessage.Id)
    }

    // A chat holds far fewer stored messages than this in practice.
    public static let scanLimit = 200_000
    // 100 messages per request: up to 5,000 missing messages are downloaded.
    static let maxFillRequests = 50
    static let fillPause: Double = 0.25

    static func bounds(_ direction: Direction) -> (lower: Int32, upper: Int32) {
        switch direction {
        case let .between(a, b):
            return (min(a.id, b.id), max(a.id, b.id))
        case let .toNewest(id):
            return (id.id, Int32.max)
        case let .toOldest(id):
            return (Int32.min, id.id)
        }
    }

    public static func messageIds(account: Account, peerId: PeerId, threadId: Int64?, direction: Direction) -> Signal<[EngineMessage.Id], NoError> {
        let (lower, upper) = bounds(direction)
        return fillHoles(account: account, peerId: peerId, threadId: threadId, lower: lower, upper: upper)
        |> then(storedIds(account: account, peerId: peerId, threadId: threadId, lower: lower, upper: upper))
    }

    static func storedIds(account: Account, peerId: PeerId, threadId: Int64?, lower: Int32, upper: Int32) -> Signal<[EngineMessage.Id], NoError> {
        return account.postbox.transaction { transaction -> [EngineMessage.Id] in
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

    // The topmost part of [lower, upper] the device has not loaded. A thread
    // uses its own holes, narrowed by the chat's when the account is a member
    // (then the chat's history covers the thread's messages too), as the
    // comments screen does.
    static func topHole(transaction: Transaction, peerId: PeerId, threadId: Int64?, lower: Int32, upper: Int32) -> ClosedRange<Int32>? {
        var holes: IndexSet
        if let threadId {
            holes = transaction.getThreadIndexHoles(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud)
            if transaction.getPeerChatListIndex(peerId) != nil {
                holes.formIntersection(transaction.getHoles(peerId: peerId, namespace: Namespaces.Message.Cloud))
            }
        } else {
            holes = transaction.getHoles(peerId: peerId, namespace: Namespaces.Message.Cloud)
        }
        let low = Int(max(lower, 1))
        let high = Int(upper)
        guard low <= high else {
            return nil
        }
        holes.formIntersection(IndexSet(integersIn: low ... high))
        guard let range = holes.rangeView.last, range.upperBound > range.lowerBound else {
            return nil
        }
        return Int32(range.lowerBound) ... Int32(range.upperBound - 1)
    }

    // Completes when the range has no holes left, when a request brings
    // nothing twice, or after `maxFillRequests` requests.
    static func fillHoles(account: Account, peerId: PeerId, threadId: Int64?, lower: Int32, upper: Int32) -> Signal<[EngineMessage.Id], NoError> {
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return .complete()
        }
        return Signal { subscriber in
            let disposable = MetaDisposable()
            let queue = Queue()
            var requests = 0
            var stalls = 0
            var lastHole: ClosedRange<Int32>?

            func step() {
                if requests >= ShadowRangeSelection.maxFillRequests {
                    subscriber.putCompletion()
                    return
                }
                let hole = account.postbox.transaction { transaction -> ClosedRange<Int32>? in
                    return topHole(transaction: transaction, peerId: peerId, threadId: threadId, lower: lower, upper: upper)
                }
                disposable.set((hole
                |> mapToSignal { hole -> Signal<(ClosedRange<Int32>?, Int), NoError> in
                    guard let hole else {
                        return .single((nil, 0))
                    }
                    let direction: MessageHistoryViewRelativeHoleDirection = .range(start: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: hole.upperBound), end: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: hole.lowerBound))
                    return fetchMessageHistoryHole(accountPeerId: account.peerId, source: .network(account.network), postbox: account.postbox, peerInput: .direct(peerId: peerId, threadId: threadId), namespace: Namespaces.Message.Cloud, direction: direction, space: .everywhere, count: 100)
                    |> map { result -> (ClosedRange<Int32>?, Int) in
                        return (hole, result?.ids.count ?? 0)
                    }
                }
                |> deliverOn(queue)).start(next: { hole, count in
                    guard let hole else {
                        subscriber.putCompletion()
                        return
                    }
                    requests += 1
                    if count == 0 {
                        // Nothing came back: the hole is gone or cannot be filled.
                        stalls += (lastHole == hole) ? 2 : 1
                        if stalls >= 2 {
                            subscriber.putCompletion()
                            return
                        }
                    } else {
                        stalls = 0
                    }
                    lastHole = hole
                    queue.after(ShadowRangeSelection.fillPause, {
                        step()
                    })
                }))
            }

            queue.async {
                step()
            }
            return disposable
        }
    }
}
