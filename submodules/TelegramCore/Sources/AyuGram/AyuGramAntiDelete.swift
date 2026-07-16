import Foundation
import Postbox

// AyuGram anti-delete: instead of removing messages the server told us to
// delete, we keep them and tag them with DeletedMessageAttribute so the UI can
// mark them (trash badge). Media survives because the retained message keeps
// referencing it, so it is not garbage-collected.
func ayuGramMarkMessagesDeleted(transaction: Transaction, ids: [MessageId]) {
    let markDate = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    for id in ids {
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
    ayuForkStoreRecordKeptDeleted(transaction: transaction, ids: ids)
}
