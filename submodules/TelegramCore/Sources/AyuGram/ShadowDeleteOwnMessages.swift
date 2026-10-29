import Foundation
import Postbox
import SwiftSignalKit

// Shadow: «Удалить мои сообщения» (chat list menu → «Shadow ›»). Finds every
// message the account sent in a chat through the server search (from_id =
// self, so history that was never loaded is found too) and deletes it for
// everyone, page by page. Anti-delete keeps nothing of it: own outgoing
// messages are skipped there (AyuGramAntiDelete).
public enum ShadowDeleteOwnMessages {
    public enum Period: Int32, CaseIterable {
        case day = 0
        case week = 1
        case month = 2
        case all = 3

        public var title: String {
            switch self {
            case .day:
                return "За последние 24 часа"
            case .week:
                return "За последнюю неделю"
            case .month:
                return "За последний месяц"
            case .all:
                return "За всё время"
            }
        }

        // The earliest message date to delete, nil for all time.
        public func minDate(now: Int32) -> Int32? {
            switch self {
            case .day:
                return now - 24 * 60 * 60
            case .week:
                return now - 7 * 24 * 60 * 60
            case .month:
                return now - 30 * 24 * 60 * 60
            case .all:
                return nil
            }
        }
    }

    public struct Progress: Equatable {
        public let deleted: Int
        public let total: Int?
        public let isFinished: Bool

        public init(deleted: Int, total: Int?, isFinished: Bool) {
            self.deleted = deleted
            self.total = total
            self.isFinished = isFinished
        }
    }

    public static let pageSize: Int32 = 100
    // A pause between pages keeps the search and delete calls under the flood limits.
    public static let pageDelay: Double = 0.4

    // Private chats and groups: there own messages can be deleted for everyone at
    // any age. Not Saved Messages (nobody else sees them), not broadcast
    // channels (posts are not «mine» there), not secret chats (not on the server).
    public static func isAvailable(peer: EnginePeer, accountPeerId: EnginePeer.Id) -> Bool {
        switch peer {
        case let .user(user):
            return user.id != accountPeerId
        case .legacyGroup:
            return true
        case let .channel(channel):
            if case .group = channel.info {
                return true
            }
            return false
        default:
            // Secret chats (not on the server) and any other kind.
            return false
        }
    }

    // The ids among a search page that this run deletes: cloud messages sent by
    // the account, not seen on an earlier page.
    static func idsToDelete(messages: [Message], accountPeerId: PeerId, seen: Set<MessageId>) -> [MessageId] {
        var result: [MessageId] = []
        for message in messages {
            guard message.id.namespace == Namespaces.Message.Cloud, !seen.contains(message.id) else {
                continue
            }
            guard message.author?.id == accountPeerId || !message.flags.contains(.Incoming) else {
                continue
            }
            result.append(message.id)
        }
        return result
    }

    public static func run(account: Account, peerId: PeerId, period: Period) -> Signal<Progress, NoError> {
        let engine = TelegramEngine(account: account)
        let accountPeerId = account.peerId
        let minDate = period.minDate(now: Int32(Date().timeIntervalSince1970))
        let location: SearchMessagesLocation = .peer(peerId: peerId, fromId: accountPeerId, tags: nil, reactions: nil, threadId: nil, minDate: minDate, maxDate: nil)

        return Signal { subscriber in
            let disposable = MetaDisposable()
            var seen = Set<MessageId>()
            var deleted = 0
            var total: Int?

            func page(state: SearchMessagesState?) {
                disposable.set((engine.messages.searchMessages(location: location, query: "", state: state, limit: ShadowDeleteOwnMessages.pageSize)
                |> take(1)
                |> mapToSignal { result, nextState -> Signal<(SearchMessagesResult, SearchMessagesState, Int), NoError> in
                    let ids = ShadowDeleteOwnMessages.idsToDelete(messages: result.messages, accountPeerId: accountPeerId, seen: seen)
                    seen.formUnion(ids)
                    if ids.isEmpty {
                        return .single((result, nextState, 0))
                    }
                    return engine.messages.deleteMessagesInteractively(messageIds: ids, type: .forEveryone)
                    |> take(1)
                    |> map { _ -> (SearchMessagesResult, SearchMessagesState, Int) in
                        return (result, nextState, ids.count)
                    }
                    |> then(.single((result, nextState, ids.count)))
                    |> take(1)
                }
                |> deliverOnMainQueue).start(next: { result, nextState, count in
                    if total == nil {
                        total = Int(result.totalCount)
                    }
                    deleted += count
                    let finished = result.completed || count == 0
                    subscriber.putNext(Progress(deleted: deleted, total: total.map { max($0, deleted) }, isFinished: finished))
                    if finished {
                        subscriber.putCompletion()
                    } else {
                        disposable.set((Signal<Void, NoError>.single(Void())
                        |> delay(ShadowDeleteOwnMessages.pageDelay, queue: Queue.mainQueue())).start(completed: {
                            page(state: nextState)
                        }))
                    }
                }))
            }

            Queue.mainQueue().async {
                page(state: nil)
            }

            return disposable
        }
    }
}
