import Foundation
import Postbox
import SwiftSignalKit

// AyuGram fork (Этап 4b): estimate a user's last-online time from their activity
// in shared chats, for when the real "last seen" is hidden by privacy. We take
// the timestamp of the most recent message the user authored in the 1:1 chat or
// in any group/supergroup that is in our chat list. This is a lazy, bounded scan
// (top chats × a short tail) computed on demand and memoised, so it never builds
// a heavy per-message author index.

private let ayuLastSeenLock = NSLock()
private var ayuLastSeenCache: [PeerId: (timestamp: Int32?, computedAt: Double)] = [:]
private let ayuLastSeenTTL: Double = 600.0
// Bound the scan so opening a profile can never turn into a full-database walk.
private let ayuLastSeenMaxGroups = 40
private let ayuLastSeenTailCount = 30

private func ayuLastSeenCacheRead(_ peerId: PeerId, now: Double) -> (value: Int32?, fresh: Bool)? {
    ayuLastSeenLock.lock()
    defer { ayuLastSeenLock.unlock() }
    if let entry = ayuLastSeenCache[peerId] {
        return (entry.timestamp, now - entry.computedAt < ayuLastSeenTTL)
    }
    return nil
}

private func ayuLastSeenCacheWrite(_ peerId: PeerId, _ value: Int32?, now: Double) {
    ayuLastSeenLock.lock()
    ayuLastSeenCache[peerId] = (value, now)
    ayuLastSeenLock.unlock()
}

private func ayuScanApproximateLastActivity(transaction: Transaction, peerId: PeerId) -> Int32? {
    var best: Int32?

    func consider(_ chatPeerId: PeerId) {
        let view = transaction.getMessagesHistoryViewState(
            input: .single(peerId: chatPeerId, threadId: nil),
            ignoreMessagesInTimestampRange: nil,
            ignoreMessageIds: Set(),
            count: ayuLastSeenTailCount,
            clipHoles: false,
            anchor: .upperBound,
            namespaces: .just(Set([Namespaces.Message.Cloud]))
        )
        // entries are ascending by index; walk newest-first and take the first
        // one this peer authored.
        for entry in view.entries.reversed() {
            if entry.message.author?.id == peerId {
                if best == nil || entry.message.timestamp > best! {
                    best = entry.message.timestamp
                }
                break
            }
        }
    }

    // The 1:1 chat (its incoming messages are authored by the peer).
    consider(peerId)

    // Shared groups / supergroups in the chat list.
    var scannedGroups = 0
    for chatPeerId in transaction.chatListGetAllPeerIds() {
        if scannedGroups >= ayuLastSeenMaxGroups {
            break
        }
        if chatPeerId.namespace == Namespaces.Peer.CloudGroup || chatPeerId.namespace == Namespaces.Peer.CloudChannel {
            scannedGroups += 1
            consider(chatPeerId)
        }
    }

    return best
}

// Emits the cached estimate immediately (or nil), then — if the cache is stale —
// a freshly scanned value. Safe to subscribe from the profile screen; the scan
// is throttled by the TTL across opens.
public func ayuApproximateLastActivity(postbox: Postbox, peerId: PeerId) -> Signal<Int32?, NoError> {
    let now = Date().timeIntervalSince1970
    if let cached = ayuLastSeenCacheRead(peerId, now: now), cached.fresh {
        return .single(cached.value)
    }
    let initial: Int32? = ayuLastSeenCacheRead(peerId, now: now)?.value
    let scan = postbox.transaction { transaction -> Int32? in
        let result = ayuScanApproximateLastActivity(transaction: transaction, peerId: peerId)
        ayuLastSeenCacheWrite(peerId, result, now: Date().timeIntervalSince1970)
        return result
    }
    return .single(initial)
    |> then(scan)
}
