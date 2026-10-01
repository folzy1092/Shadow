import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext

// Shadow: sends wrong-password photos (ShadowIntruderLog, spec 7.2) to Saved
// Messages of the account that is unlocked; if they cannot be queued, they go
// to the photo library instead. Called whenever the app becomes unlocked.
enum ShadowIntruderDelivery {
    static func deliverPending(context: AccountContext) {
        let log = ShadowIntruderLog.shared
        let entries = log.pending()
        guard !entries.isEmpty else {
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"

        var messages: [EnqueueMessage] = []
        var images: [UIImage] = []
        var delivered: [ShadowIntruderLog.Entry] = []
        for entry in entries {
            guard let data = try? Data(contentsOf: entry.url), let image = UIImage(data: data) else {
                log.remove(entry)
                continue
            }
            let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
            let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(image.size), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
            let media = TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
            let caption = "Shadow: \(entry.reason.title) · \(formatter.string(from: entry.date))"
            messages.append(.message(text: caption, attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []))
            images.append(image)
            delivered.append(entry)
        }
        guard !messages.isEmpty else {
            return
        }
        // Remove first so a second unlock while sending does not send them twice.
        for entry in delivered {
            log.remove(entry)
        }
        let _ = (enqueueMessages(account: context.account, peerId: context.account.peerId, messages: messages)
        |> deliverOnMainQueue).startStandalone(next: { ids in
            if !ids.contains(where: { $0 != nil }) {
                for image in images {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
        })
    }
}
