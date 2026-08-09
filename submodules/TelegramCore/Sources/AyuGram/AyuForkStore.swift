import Foundation
import Postbox
import SwiftSignalKit

// AyuGram fork: a small forward index of the message-scoped data the fork keeps
// beyond vanilla Telegram, so the "Fork storage usage" screen can report counts
// and offer a per-category clear without scanning the entire message database
// (which has no index for these). Ids are appended at the capture sites
// (anti-delete marking, edit-history capture) and removed when cleared.
//
// This complements the on-disk saved-media gallery (see AyuSavedMedia), which is
// measured directly from its directory.

public extension PreferencesKeys {
    static let ayuForkStore: ValueBoxKey = {
        let key = ValueBoxKey(length: 4)
        key.setInt32(0, value: 1001)
        return key
    }()
}

public struct AyuForkMsgRef: Codable, Equatable {
    public let peer: Int64
    public let namespace: Int32
    public let id: Int32

    public init(peer: Int64, namespace: Int32, id: Int32) {
        self.peer = peer
        self.namespace = namespace
        self.id = id
    }

    init(_ messageId: MessageId) {
        self.peer = messageId.peerId.toInt64()
        self.namespace = messageId.namespace
        self.id = messageId.id
    }

    var messageId: MessageId {
        return MessageId(peerId: PeerId(self.peer), namespace: self.namespace, id: self.id)
    }
}

public struct AyuForkStore: Codable, Equatable {
    // Cap each list so the index can never grow without bound; the oldest refs
    // are dropped first (the actual data is unaffected — only its bookkeeping).
    static let maxEntries = 5000

    public var keptDeleted: [AyuForkMsgRef]
    public var editHistory: [AyuForkMsgRef]

    public static var empty: AyuForkStore {
        return AyuForkStore(keptDeleted: [], editHistory: [])
    }

    public init(keptDeleted: [AyuForkMsgRef], editHistory: [AyuForkMsgRef]) {
        self.keptDeleted = keptDeleted
        self.editHistory = editHistory
    }
}

public func ayuForkStore(transaction: Transaction) -> AyuForkStore {
    if let entry = transaction.getPreferencesEntry(key: PreferencesKeys.ayuForkStore)?.get(AyuForkStore.self) {
        return entry
    }
    return AyuForkStore.empty
}

private func updateAyuForkStore(transaction: Transaction, _ f: (AyuForkStore) -> AyuForkStore) {
    let current = ayuForkStore(transaction: transaction)
    let updated = f(current)
    if updated != current {
        transaction.setPreferencesEntry(key: PreferencesKeys.ayuForkStore, value: PreferencesEntry(updated))
    }
}

private func appendCapped(_ list: inout [AyuForkMsgRef], _ refs: [AyuForkMsgRef]) {
    for ref in refs where !list.contains(ref) {
        list.append(ref)
    }
    if list.count > AyuForkStore.maxEntries {
        list.removeFirst(list.count - AyuForkStore.maxEntries)
    }
}

// Called from the anti-delete marking path.
func ayuForkStoreRecordKeptDeleted(transaction: Transaction, ids: [MessageId]) {
    let refs = ids.map(AyuForkMsgRef.init)
    updateAyuForkStore(transaction: transaction) { store in
        var store = store
        appendCapped(&store.keptDeleted, refs)
        return store
    }
}

// Called from the edit-history capture path.
func ayuForkStoreRecordEditHistory(transaction: Transaction, id: MessageId) {
    let ref = AyuForkMsgRef(id)
    updateAyuForkStore(transaction: transaction) { store in
        var store = store
        appendCapped(&store.editHistory, [ref])
        return store
    }
}

// MARK: - Public read / clear for the storage screen

public func ayuForkStoreCounts(postbox: Postbox) -> Signal<(keptDeleted: Int, editHistory: Int), NoError> {
    return postbox.transaction { transaction -> (keptDeleted: Int, editHistory: Int) in
        let store = ayuForkStore(transaction: transaction)
        return (store.keptDeleted.count, store.editHistory.count)
    }
}

// Delete the kept (anti-deleted) messages for real and clear the index.
public func ayuForkStoreClearKeptDeleted(postbox: Postbox) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Void in
        let store = ayuForkStore(transaction: transaction)
        let ids = store.keptDeleted.map { $0.messageId }
        if !ids.isEmpty {
            _internal_deleteMessages(transaction: transaction, mediaBox: postbox.mediaBox, ids: ids)
        }
        updateAyuForkStore(transaction: transaction) { current in
            var current = current
            current.keptDeleted = []
            return current
        }
    }
    |> ignoreValues
}

// Age out kept (anti-deleted) messages: delete for real every indexed message
// whose trash mark (DeletedMessageAttribute.date) is older than `maxAge`
// seconds, and drop it from the index. `maxAge <= 0` disables the expiry.
// Refs whose message no longer exists are dropped too. Returns how many
// messages were deleted.
//
// This is the message-side counterpart of the saved-media "Срок хранения": the
// media gallery was already pruned by age, but kept messages themselves lived
// forever until the user hit "Очистить" by hand.
@discardableResult
func ayuForkStorePruneKeptDeleted(transaction: Transaction, mediaBox: MediaBox, maxAge: Int32, now: Int32) -> Int {
    guard maxAge > 0 else {
        return 0
    }
    let store = ayuForkStore(transaction: transaction)
    if store.keptDeleted.isEmpty {
        return 0
    }
    var expiredIds: [MessageId] = []
    var remaining: [AyuForkMsgRef] = []
    for ref in store.keptDeleted {
        let messageId = ref.messageId
        guard let message = transaction.getMessage(messageId) else {
            // Already gone — the ref is stale, drop it.
            continue
        }
        var markDate: Int32?
        for attribute in message.attributes {
            if let attribute = attribute as? DeletedMessageAttribute {
                markDate = attribute.date
                break
            }
        }
        if let markDate = markDate, now - markDate >= maxAge {
            expiredIds.append(messageId)
        } else {
            remaining.append(ref)
        }
    }
    if !expiredIds.isEmpty {
        _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: expiredIds)
    }
    if remaining.count != store.keptDeleted.count {
        updateAyuForkStore(transaction: transaction) { current in
            var current = current
            current.keptDeleted = remaining
            return current
        }
    }
    return expiredIds.count
}

// Strip the stored edit versions from the affected messages and clear the index.
public func ayuForkStoreClearEditHistory(postbox: Postbox) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Void in
        let store = ayuForkStore(transaction: transaction)
        for ref in store.editHistory {
            let messageId = ref.messageId
            if let message = transaction.getMessage(messageId), message.attributes.contains(where: { $0 is SavedMessageEditsAttribute }) {
                transaction.updateMessage(messageId, update: { currentMessage in
                    var attributes = currentMessage.attributes
                    attributes.removeAll(where: { $0 is SavedMessageEditsAttribute })
                    var storeForwardInfo: StoreMessageForwardInfo?
                    if let forwardInfo = currentMessage.forwardInfo {
                        storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                    }
                    return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                })
            }
        }
        updateAyuForkStore(transaction: transaction) { current in
            var current = current
            current.editHistory = []
            return current
        }
    }
    |> ignoreValues
}
