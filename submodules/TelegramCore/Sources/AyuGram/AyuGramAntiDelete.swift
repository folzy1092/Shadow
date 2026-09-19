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
func ayuGramMarkMessagesDeleted(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) -> [MessageId] {
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
        // Shadow: копируем медиа удаляемого сообщения в приватную папку форка
        // ПРЯМО СЕЙЧАС, пока байты ещё есть на диске.
        //
        // Одного лишь сохранения самого сообщения мало: его медиа физически
        // лежит в общем кэше Telegram, который периодически подчищается. Как
        // только это произойдёт, перекачать уже нечего — на сервере сообщение
        // удалено. Внешне это выглядит так: сообщение с корзиной осталось, а
        // видео/фото в нём "как не бывало".
        //
        // saveMessageMedia делает hard link на файл в кэше (лишнего места не
        // занимает), и именно эта ссылка удерживает байты живыми после того,
        // как кэш удалит свою копию.
        if let message = transaction.getMessage(id) {
            AyuSavedMedia.saveMessageMedia(mediaBox: mediaBox, message: message)
        }
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


// A later `UpdateMinAvailableMessage` can arrive right after an ordinary
// delete update. Telegram uses it to trim a history range and its stock path
// would otherwise remove the same locally-kept ghost a second time. Only
// restore messages already marked by anti-delete; this is not a history
// backfill and never resurrects ordinary old messages.
func ayuGramKeptDeletedMessagesInRange(
    transaction: Transaction,
    peerId: PeerId,
    namespace: MessageId.Namespace,
    minId: MessageId.Id,
    maxId: MessageId.Id
) -> [StoreMessage] {
    let refs = ayuForkStore(transaction: transaction).keptDeleted
    var messages: [StoreMessage] = []
    for ref in refs where ref.peer == peerId.toInt64() && ref.namespace == namespace && ref.id >= minId && ref.id <= maxId {
        guard let message = transaction.getMessage(ref.messageId) else {
            continue
        }
        guard message.attributes.contains(where: { $0 is DeletedMessageAttribute }) else {
            continue
        }
        let storeForwardInfo = message.forwardInfo.flatMap { info in
            StoreMessageForwardInfo(authorId: info.author?.id, sourceId: info.source?.id, sourceMessageId: info.sourceMessageId, date: info.date, authorSignature: info.authorSignature, psaType: info.psaType, flags: info.flags)
        }
        messages.append(StoreMessage(
            id: message.id,
            customStableId: nil,
            globallyUniqueId: message.globallyUniqueId,
            groupingKey: message.groupingKey,
            threadId: message.threadId,
            timestamp: message.timestamp,
            flags: StoreMessageFlags(message.flags),
            tags: message.tags,
            globalTags: message.globalTags,
            localTags: message.localTags,
            forwardInfo: storeForwardInfo,
            authorId: message.author?.id,
            text: message.text,
            attributes: message.attributes,
            media: message.media
        ))
    }
    return messages
}

// A remote "clear history" in a secret chat bypasses the cloud update path.
// Telegram stores both directions in the shared SecretIncoming message
// namespace and distinguishes them with the Incoming flag. Preserve incoming
// content through the archive path and still remove our own outgoing messages.
func ayuGramHandleSecretChatClearHistory(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId) {
    var messageIds: [MessageId] = []
    transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.SecretIncoming, limit: 1_000_000, { message in
        messageIds.append(message.id)
        return true
    })
    guard !messageIds.isEmpty else {
        return
    }
    let excludedIds = ayuGramMarkMessagesDeleted(transaction: transaction, mediaBox: mediaBox, ids: messageIds)
    if !excludedIds.isEmpty {
        _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: excludedIds)
    }
}
