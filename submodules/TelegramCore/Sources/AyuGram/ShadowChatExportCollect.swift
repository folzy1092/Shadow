import Foundation
import Postbox
import SwiftSignalKit

// Shadow: gathers a chat for ShadowChatExport from the local database. Only
// what is stored on this device is exported: messages the app has loaded
// (scrolled to, received) plus those kept after deletion. Older history that
// was never downloaded is not fetched from the server.
public enum ShadowChatExportCollect {
    public static let messageLimit = 50_000

    public static func chat(postbox: Postbox, peerId: PeerId, title: String) -> Signal<ShadowChatExport.Chat, NoError> {
        return postbox.transaction { transaction -> ShadowChatExport.Chat in
            var messages: [Message] = []
            for namespace in [Namespaces.Message.Cloud, Namespaces.Message.Local, Namespaces.Message.SecretIncoming] {
                transaction.scanTopMessages(peerId: peerId, namespace: namespace, limit: ShadowChatExportCollect.messageLimit, { message in
                    messages.append(message)
                    return true
                })
            }
            messages.sort(by: { $0.index < $1.index })
            if messages.count > ShadowChatExportCollect.messageLimit {
                messages.removeFirst(messages.count - ShadowChatExportCollect.messageLimit)
            }
            let records = messages.map(ShadowChatExportCollect.record(message:))
            return ShadowChatExport.Chat(title: title, exportDate: Int32(Date().timeIntervalSince1970), records: records)
        }
    }

    static func record(message: Message) -> ShadowChatExport.Record {
        var deletedDate: Int32?
        var editDate: Int32?
        var edits: [ShadowChatExport.Edit] = []
        var replyToId: Int32?
        for attribute in message.attributes {
            if let attribute = attribute as? DeletedMessageAttribute {
                deletedDate = attribute.date
            } else if let attribute = attribute as? EditedMessageAttribute, !attribute.isHidden {
                editDate = attribute.date
            } else if let attribute = attribute as? SavedMessageEditsAttribute {
                edits = attribute.versions.map { ShadowChatExport.Edit(date: $0.date, text: $0.text) }
            } else if let attribute = attribute as? ReplyMessageAttribute, attribute.messageId.peerId == message.id.peerId {
                replyToId = attribute.messageId.id
            }
        }

        var author = message.author?.debugDisplayTitle ?? ""
        if author.isEmpty {
            author = message.peers[message.id.peerId]?.debugDisplayTitle ?? ""
        }
        // Channel posts carry the admin's signature separately from the author.
        if message.forwardInfo == nil, let signature = message.attributes.compactMap({ ($0 as? AuthorSignatureMessageAttribute)?.signature }).first, !signature.isEmpty {
            author += " (\(signature))"
        }

        var forwardedFrom: String?
        if let forwardInfo = message.forwardInfo {
            forwardedFrom = forwardInfo.author?.debugDisplayTitle ?? forwardInfo.source?.debugDisplayTitle ?? forwardInfo.authorSignature ?? "скрытый пользователь"
        }

        return ShadowChatExport.Record(
            id: message.id.id,
            date: message.timestamp,
            author: author,
            text: message.text,
            isOutgoing: !message.flags.contains(.Incoming),
            deletedDate: deletedDate,
            editDate: editDate,
            edits: edits,
            media: message.media.compactMap(ShadowChatExportCollect.describe(media:)).first,
            replyToId: replyToId,
            forwardedFrom: forwardedFrom
        )
    }

    static func describe(media: Media) -> String? {
        switch media {
        case is TelegramMediaImage:
            return "Фото"
        case let file as TelegramMediaFile:
            if file.isInstantVideo {
                return "Видеосообщение"
            } else if file.isVoice {
                return "Голосовое сообщение"
            } else if file.isSticker {
                return "Стикер"
            } else if file.isAnimated {
                return "GIF"
            } else if file.isVideo {
                return "Видео"
            } else if file.isMusic {
                return "Аудио" + (file.fileName.map { ": " + $0 } ?? "")
            } else {
                return "Файл" + (file.fileName.map { ": " + $0 } ?? "")
            }
        case is TelegramMediaMap:
            return "Геопозиция"
        case let contact as TelegramMediaContact:
            return "Контакт: " + [contact.firstName, contact.lastName, contact.phoneNumber].filter { !$0.isEmpty }.joined(separator: " ")
        case let poll as TelegramMediaPoll:
            return "Опрос: " + poll.text
        case is TelegramMediaDice:
            return "Кубик"
        case is TelegramMediaAction:
            return "Служебное сообщение"
        default:
            return nil
        }
    }
}
