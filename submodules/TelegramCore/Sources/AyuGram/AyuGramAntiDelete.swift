import Foundation
import Postbox

// AyuGram anti-delete: instead of removing messages the server told us to
// delete, we keep them and tag them with DeletedMessageAttribute so the UI can
// mark them (trash badge). Media survives because the retained message keeps
// referencing it, so it is not garbage-collected.
//
// Shadow: anti-delete is meant for other people's messages in regular user
// conversations only. Two sender types are never kept:
//   • BOT authors — a bot deleting its own messages (menus, throwaway prompts,
//     cleanup) should not leave "deleted" ghosts.
//   • OUR OWN outgoing messages — deleting something we sent is intentional and
//     must not be resurrected.
// The sender is resolved per-id from the stored message (author peer / incoming
// flag).
//
// Returns the ids that are NOT kept. The caller MUST delete those through the
// normal delete path: the caller's anti-delete branch deletes nothing by
// itself, so an id that is merely skipped here would stay in the chat forever
// with no trash badge — exactly the "ghost" this exclusion exists to prevent.
@discardableResult
func ayuGramMarkMessagesDeleted(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
    var filteredIds: [MessageId] = []
    var excludedIds: [MessageId] = []
    for id in ids {
        guard let message = transaction.getMessage(id) else {
            // No local copy to inspect — keep default behaviour (retain).
            filteredIds.append(id)
            continue
        }
        // Skip our own outgoing messages.
        if !message.flags.contains(.Incoming) {
            excludedIds.append(id)
            continue
        }
        // Skip messages authored by a bot.
        if let author = message.author as? TelegramUser, author.botInfo != nil {
            excludedIds.append(id)
            continue
        }
        filteredIds.append(id)
    }
    if filteredIds.isEmpty {
        return excludedIds
    }
    let markDate = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    for id in filteredIds {
        transaction.updateMessage(id) { currentMessage -> PostboxUpdateMessage in
            if currentMessage.attributes.contains(where: { $0 is DeletedMessageAttribute }) {
                return .skip
            }
            var attributes = currentMessage.attributes
            attributes.append(DeletedMessageAttribute(date: markDate))
            let storeForwardInfo = currentMessage.forwardInfo.flatMap { info in
                StoreMessageForwardInfo(authorId: info.author?.id, sourceId: info.source?.id, sourceMessageId: info.sourceMessageId, date: info.date, authorSignature: info.authorSignature, psaType: info.psaType, flags: info.flags)
            }
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        }
    }
    // AyuGram: index the kept messages so the fork-storage screen can count and
    // clear them without scanning the whole database.
    ayuForkStoreRecordKeptDeleted(transaction: transaction, ids: filteredIds)
    return excludedIds
}
