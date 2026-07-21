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
func ayuGramMarkMessagesDeleted(transaction: Transaction, ids: [MessageId]) {
    let filteredIds = ids.filter { id in
        guard let message = transaction.getMessage(id) else {
            // No local copy to inspect — keep default behaviour (retain).
            return true
        }
        // Skip our own outgoing messages.
        if !message.flags.contains(.Incoming) {
            return false
        }
        // Skip messages authored by a bot.
        if let author = message.author as? TelegramUser, author.botInfo != nil {
            return false
        }
        return true
    }
    if filteredIds.isEmpty {
        return
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
}
