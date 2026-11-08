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

public struct AyuForkMsgRef: Codable, Equatable, Hashable {
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

private func appendUnique(_ list: inout [AyuForkMsgRef], _ refs: [AyuForkMsgRef]) {
    var seen = Set(list)
    for ref in refs where seen.insert(ref).inserted {
        list.append(ref)
    }
}

// Called from the anti-delete marking path.
func ayuForkStoreRecordKeptDeleted(transaction: Transaction, ids: [MessageId]) {
    let refs = ids.map(AyuForkMsgRef.init)
    updateAyuForkStore(transaction: transaction) { store in
        var store = store
        appendUnique(&store.keptDeleted, refs)
        return store
    }
}

// Called from the edit-history capture path.
func ayuForkStoreRecordEditHistory(transaction: Transaction, id: MessageId) {
    let ref = AyuForkMsgRef(id)
    updateAyuForkStore(transaction: transaction) { store in
        var store = store
        appendUnique(&store.editHistory, [ref])
        return store
    }
}

// Repairs indexes created by older builds that discarded references after
// 5,000 entries. Visible history is scanned lazily, so those messages become
// manageable again without an expensive full database migration at launch.
public func ayuForkStoreRepair(transaction: Transaction, messages: [Message]) {
    let kept = messages.filter { message in message.attributes.contains(where: { $0 is DeletedMessageAttribute }) }.map { AyuForkMsgRef($0.id) }
    let edited = messages.filter { message in message.attributes.contains(where: { $0 is SavedMessageEditsAttribute }) }.map { AyuForkMsgRef($0.id) }
    guard !kept.isEmpty || !edited.isEmpty else { return }
    updateAyuForkStore(transaction: transaction) { store in
        var store = store
        appendUnique(&store.keptDeleted, kept)
        appendUnique(&store.editHistory, edited)
        return store
    }
}

// MARK: - Full rescan

// Upper bound of messages scanned per chat and namespace.
private let ayuForkRescanLimitPerChat = 1_000_000

// The index above is filled only at capture time and by the lazy repair of
// visible history, and builds before 2.2.0 dropped refs past 5,000. Messages it
// never saw were invisible to the storage screen: its counts read 0, its clear
// buttons stayed disabled or deleted nothing, and kept deleted messages stayed in
// groups. This walks the stored attributes of every chat (Postbox keeps no index
// for them), repairs the index, and returns everything that is really stored.
public func ayuForkStoreRescan(transaction: Transaction) -> (kept: [MessageId], edited: [MessageId]) {
    let store = ayuForkStore(transaction: transaction)
    var peerIds = Set(transaction.chatListGetAllPeerIds())
    for ref in store.keptDeleted + store.editHistory {
        peerIds.insert(PeerId(ref.peer))
    }
    var kept: [AyuForkMsgRef] = []
    var edited: [AyuForkMsgRef] = []
    for peerId in peerIds {
        for namespace in [Namespaces.Message.Cloud, Namespaces.Message.SecretIncoming] {
            transaction.scanMessageAttributes(peerId: peerId, namespace: namespace, limit: ayuForkRescanLimitPerChat) { id, attributes in
                if attributes.contains(where: { $0 is DeletedMessageAttribute }) {
                    kept.append(AyuForkMsgRef(id))
                }
                if attributes.contains(where: { $0 is SavedMessageEditsAttribute }) {
                    edited.append(AyuForkMsgRef(id))
                }
                // Postbox reads in batches and `false` only ends the current one.
                return true
            }
        }
    }
    updateAyuForkStore(transaction: transaction) { current in
        var current = current
        appendUnique(&current.keptDeleted, kept)
        appendUnique(&current.editHistory, edited)
        return current
    }
    let repaired = ayuForkStore(transaction: transaction)
    return (repaired.keptDeleted.map { $0.messageId }, repaired.editHistory.map { $0.messageId })
}

// MARK: - Public read / clear for the storage screen

public func ayuForkStoreCounts(postbox: Postbox) -> Signal<(keptDeleted: Int, editHistory: Int), NoError> {
    return postbox.transaction { transaction -> (keptDeleted: Int, editHistory: Int) in
        let found = ayuForkStoreRescan(transaction: transaction)
        return (found.kept.count, found.edited.count)
    }
}

// Delete every kept (anti-deleted) message for real, indexed or not, and clear the index.
public func ayuForkStoreClearKeptDeleted(postbox: Postbox) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Void in
        let ids = ayuForkStoreRescan(transaction: transaction).kept
        if !ids.isEmpty {
            _internal_deleteMessages(transaction: transaction, mediaBox: postbox.mediaBox, ids: ids)
            AyuSavedMedia.removeMessageMedia(basePath: postbox.mediaBox.basePath, messageIds: ids)
        }
        let cleared = Set(ids.map(AyuForkMsgRef.init))
        updateAyuForkStore(transaction: transaction) { current in
            var current = current
            current.keptDeleted = []
            current.editHistory.removeAll(where: { cleared.contains($0) })
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
func ayuForkStorePruneKeptDeleted(transaction: Transaction, mediaBox: MediaBox, maxAge: Int32, keepPeerIds: Set<Int64>, now: Int32) -> Int {
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
        if keepPeerIds.contains(ref.peer) {
            remaining.append(ref)
            continue
        }
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
        AyuSavedMedia.removeMessageMedia(basePath: mediaBox.basePath, messageIds: expiredIds)
    }
    if remaining.count != store.keptDeleted.count {
        updateAyuForkStore(transaction: transaction) { current in
            var current = current
            current.keptDeleted = remaining
            let removed = Set(store.keptDeleted).subtracting(remaining)
            current.editHistory.removeAll(where: { removed.contains($0) })
            return current
        }
    }
    return expiredIds.count
}

// Age out stored edit versions: every version older than `maxAge` seconds (by the
// moment it was replaced) is dropped, with its backed-up media. A message left
// with no versions loses the attribute and leaves the index. `maxAge <= 0` keeps
// everything. Chats in `keepPeerIds` are left alone, like for the saved media.
// Returns how many versions were removed.
@discardableResult
func ayuForkStorePruneEditHistory(transaction: Transaction, mediaBox: MediaBox, maxAge: Int32, keepPeerIds: Set<Int64>, now: Int32) -> Int {
    guard maxAge > 0 else {
        return 0
    }
    let store = ayuForkStore(transaction: transaction)
    if store.editHistory.isEmpty {
        return 0
    }
    var remaining: [AyuForkMsgRef] = []
    var removedVersions = 0
    for ref in store.editHistory {
        if keepPeerIds.contains(ref.peer) {
            remaining.append(ref)
            continue
        }
        let messageId = ref.messageId
        guard let message = transaction.getMessage(messageId) else {
            // Already gone — the ref is stale, drop it.
            continue
        }
        guard let attribute = message.attributes.first(where: { $0 is SavedMessageEditsAttribute }) as? SavedMessageEditsAttribute else {
            continue
        }
        let kept = attribute.versions.filter { !ShadowEditHistoryRetention.isExpired(versionDate: $0.date, now: now, maxAge: maxAge) }
        if kept.count == attribute.versions.count {
            remaining.append(ref)
            continue
        }
        removedVersions += attribute.versions.count - kept.count
        let candidates = Set(attribute.versions.compactMap { $0.mediaFileName })
        var keeping = Set(kept.compactMap { $0.mediaFileName })
        if let name = AyuSavedMedia.principalFileName(peerId: messageId.peerId, messageId: messageId, mediaList: message.media) {
            keeping.insert(name)
        }
        AyuSavedMedia.removeEditHistoryMedia(basePath: mediaBox.basePath, candidates: candidates, keeping: keeping)
        if !kept.isEmpty {
            remaining.append(ref)
        }
        transaction.updateMessage(messageId, update: { currentMessage in
            var attributes = currentMessage.attributes
            attributes.removeAll(where: { $0 is SavedMessageEditsAttribute })
            if !kept.isEmpty {
                attributes.append(SavedMessageEditsAttribute(versions: kept))
            }
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
            }
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
    if remaining.count != store.editHistory.count {
        updateAyuForkStore(transaction: transaction) { current in
            var current = current
            current.editHistory = remaining
            return current
        }
    }
    return removedVersions
}

// Remove a message's stored edit versions and their backed-up media.
private func ayuForkStripEditHistory(transaction: Transaction, basePath: String, messageId: MessageId) {
    guard let message = transaction.getMessage(messageId), message.attributes.contains(where: { $0 is SavedMessageEditsAttribute }) else {
        return
    }
    let candidates = Set(message.attributes.compactMap { $0 as? SavedMessageEditsAttribute }.flatMap { $0.versions }.compactMap { $0.mediaFileName })
    let keeping = Set([AyuSavedMedia.principalFileName(peerId: messageId.peerId, messageId: messageId, mediaList: message.media)].compactMap { $0 })
    AyuSavedMedia.removeEditHistoryMedia(basePath: basePath, candidates: candidates, keeping: keeping)
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

// Strip the stored edit versions from every affected message, indexed or not, and clear the index.
public func ayuForkStoreClearEditHistory(postbox: Postbox) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Void in
        for messageId in ayuForkStoreRescan(transaction: transaction).edited {
            ayuForkStripEditHistory(transaction: transaction, basePath: postbox.mediaBox.basePath, messageId: messageId)
        }
        updateAyuForkStore(transaction: transaction) { current in
            var current = current
            current.editHistory = []
            return current
        }
    }
    |> ignoreValues
}
