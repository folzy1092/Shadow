import Foundation
import Postbox
import SwiftSignalKit

// AyuGram: "Burn" a kept view-once / self-destruct photo or video. Reports the
// view to the server (so the sender sees it as opened, exactly like a normal
// view) but locally converts the message into a regular one — the self-destruct
// attributes are removed, so afterwards the photo/video can be forwarded, copied
// and saved and shows the full normal context menu.
func _internal_ayuBurnViewOnceMedia(postbox: Postbox, messageId: MessageId) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        guard let message = transaction.getMessage(messageId), message.flags.contains(.Incoming) else {
            return
        }

        // 1. Tell the server the content was viewed. This makes the sender see it
        // as opened (messages.readMessageContents), just like a normal view.
        if messageId.peerId.namespace != Namespaces.Peer.SecretChat {
            addSynchronizeConsumeMessageContentsOperation(transaction: transaction, messageIds: [messageId])
        }

        // 2. Locally strip the self-destruct so the media becomes a normal photo /
        // video: drop the auto-remove / auto-clear timeout attributes (which is what
        // `containsSecretMedia` keys off) and mark any consumable content as consumed.
        transaction.updateMessage(messageId, update: { currentMessage in
            var attributes: [MessageAttribute] = []
            for attribute in currentMessage.attributes {
                if attribute is AutoremoveTimeoutMessageAttribute || attribute is AutoclearTimeoutMessageAttribute {
                    continue
                }
                if attribute is ConsumableContentMessageAttribute {
                    attributes.append(ConsumableContentMessageAttribute(consumed: true))
                } else {
                    attributes.append(attribute)
                }
            }
            let storeForwardInfo = currentMessage.forwardInfo.flatMap { info in
                StoreMessageForwardInfo(authorId: info.author?.id, sourceId: info.source?.id, sourceMessageId: info.sourceMessageId, date: info.date, authorSignature: info.authorSignature, psaType: info.psaType, flags: info.flags)
            }
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
}
