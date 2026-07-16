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
