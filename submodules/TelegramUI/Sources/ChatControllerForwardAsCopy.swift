import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import AccountContext
import PresentationDataUtils
import UndoUI

// Shadow: forward-as-copy for copy-protected (noforwards) chats. The server
// rejects a native .forward from such a source, so each message is re-sent as
// a new message: its text plus a fresh local copy of its media, the same idea
// the core uses for secret-chat forwards (convertForwardedMediaForSecretChat).
//
// The copy owns its bytes: the downloaded original is linked into a new
// LocalFileMediaResource inside MediaBox, so the upload never touches the
// source resource, and the source never loses its file when the copy's send
// is cleaned up. The copy also carries no cloud thumbnail of the original —
// uploading that thumbnail through a standalone reference cannot refresh an
// expired file reference and left the copy stuck in "sending" forever.

private enum AyuCopyLimits {
    // A download that shows no progress for this long is treated as dead
    // (expired reference, no connection). Any progress restarts the countdown,
    // so a large video on a slow link keeps going.
    static let stallTimeout: Double = 90.0
    // The progress toast stays up for the whole copy and is dismissed
    // explicitly once the batch is ready.
    static let progressToastLifetime: Double = 60.0 * 60.0
}

private let ayuCopyQueue = Queue(name: "org.shadow.forward-copy")

private enum AyuCopyStep<T> {
    case progress(Float)
    case finished(T)

    func mapFinished<U>(_ transform: (T) -> U) -> AyuCopyStep<U> {
        switch self {
        case let .progress(value):
            return .progress(value)
        case let .finished(value):
            return .finished(transform(value))
        }
    }
}

private enum AyuCopyItemResult {
    case message(EnqueueMessage)
    case failed
    case unsupported
}

private enum AyuCopySource {
    case text
    case standalone(Media)
    case file(TelegramMediaFile)
    case image(TelegramMediaImage, TelegramMediaImageRepresentation)
    case unsupported
}

extension ChatControllerImpl {
    struct AyuCopyMessageBatch {
        let messages: [EnqueueMessage]
        let failedCount: Int
        let unsupportedCount: Int

        static let empty = AyuCopyMessageBatch(messages: [], failedCount: 0, unsupportedCount: 0)

        // A failed download blocks the whole batch, so an album is never sent
        // with holes in it; a poll or story among the selection is only
        // skipped, since it has no copyable content at all.
        var canSend: Bool {
            return self.failedCount == 0 && !self.messages.isEmpty
        }

        var skippedNote: String? {
            if self.unsupportedCount == 0 {
                return nil
            }
            return "Пропущено: \(self.unsupportedCount) — опросы, игры и истории не копируются"
        }
    }

    // Builds the copies behind a progress toast and hands the batch over once
    // every media item is local.
    func ayuPrepareCopyBatch(_ messages: [EngineRawMessage], threadId: Int64?, completion: @escaping (AyuCopyMessageBatch) -> Void) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let progressController = UndoOverlayController(presentationData: presentationData, content: ayuCopyProgressContent(percent: nil), elevatedLayout: false, action: { _ in return false })
        self.present(progressController, in: .current)

        let _ = (ayuBuildCopyBatch(context: self.context, messages: messages, threadId: threadId)
        |> map { step -> AyuCopyStep<AyuCopyMessageBatch> in
            switch step {
            case let .progress(value):
                return .progress(Float(Int(value * 100.0)))
            case .finished:
                return step
            }
        }
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            if case let .progress(lhsValue) = lhs, case let .progress(rhsValue) = rhs {
                return lhsValue == rhsValue
            }
            return false
        })
        |> deliverOnMainQueue).startStandalone(next: { [weak progressController] step in
            switch step {
            case let .progress(percent):
                if let progressController, progressController.isNodeLoaded {
                    progressController.content = ayuCopyProgressContent(percent: Int(percent))
                }
            case let .finished(batch):
                progressController?.dismiss()
                completion(batch)
            }
        })
    }

    func ayuReportUnsendableCopy(_ batch: AyuCopyMessageBatch) {
        let text: String
        if batch.failedCount > 0 {
            text = "Не скачалось медиа: \(batch.failedCount). Копия не отправлена — проверь соединение и повтори попытку."
        } else {
            text = "В выбранных сообщениях нечего скопировать: опросы, игры и истории не копируются."
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.present(textAlertController(context: self.context, title: "Не удалось переслать", text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }

    func ayuPresentCopyInfo(_ text: String) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
}

private func ayuCopyProgressContent(percent: Int?) -> UndoOverlayContent {
    let text: String
    if let percent {
        text = "Пересылка защищена — скачиваю медиа для копии: \(percent)%"
    } else {
        text = "Пересылка защищена — готовлю копию…"
    }
    return .info(title: nil, text: text, timeout: AyuCopyLimits.progressToastLifetime, customUndoText: nil)
}

private func ayuBuildCopyBatch(context: AccountContext, messages: [EngineRawMessage], threadId: Int64?) -> Signal<AyuCopyStep<ChatControllerImpl.AyuCopyMessageBatch>, NoError> {
    // Messages of one album share a fresh grouping key, so the copy lands as
    // one grouped post with its caption, not as separate messages.
    let originalGroupingKeys = Set(messages.compactMap { $0.groupingKey })
    let groupingKeys = Dictionary(uniqueKeysWithValues: originalGroupingKeys.map { ($0, Int64.random(in: Int64.min ... Int64.max)) })

    let items = messages.map { message in
        return ayuCopyItem(context: context, message: message, threadId: threadId, groupingKey: message.groupingKey.flatMap { groupingKeys[$0] })
    }
    return ayuCombineCopySteps(items)
    |> map { step -> AyuCopyStep<ChatControllerImpl.AyuCopyMessageBatch> in
        return step.mapFinished { results -> ChatControllerImpl.AyuCopyMessageBatch in
            let messages = results.compactMap { result -> EnqueueMessage? in
                if case let .message(message) = result {
                    return message
                }
                return nil
            }
            let failedCount = results.filter { if case .failed = $0 { return true } else { return false } }.count
            let unsupportedCount = results.filter { if case .unsupported = $0 { return true } else { return false } }.count
            return ChatControllerImpl.AyuCopyMessageBatch(messages: messages, failedCount: failedCount, unsupportedCount: unsupportedCount)
        }
    }
}

private func ayuCopySource(of message: EngineRawMessage) -> AyuCopySource {
    for media in message.media {
        switch media {
        case let file as TelegramMediaFile:
            return .file(file)
        case let image as TelegramMediaImage:
            guard let largest = largestImageRepresentation(image.representations) else {
                return .unsupported
            }
            return .image(image, largest)
        case let map as TelegramMediaMap:
            // A live location would start broadcasting from this account;
            // send its last point instead.
            return .standalone(TelegramMediaMap(latitude: map.latitude, longitude: map.longitude, heading: nil, accuracyRadius: map.accuracyRadius, venue: map.venue, address: map.address))
        case let contact as TelegramMediaContact:
            return .standalone(contact)
        case is TelegramMediaWebpage:
            // A link preview is rebuilt by the server from the text.
            continue
        default:
            return .unsupported
        }
    }
    return message.text.isEmpty ? .unsupported : .text
}

private func ayuCopyItem(context: AccountContext, message: EngineRawMessage, threadId: Int64?, groupingKey: Int64?) -> Signal<AyuCopyStep<AyuCopyItemResult>, NoError> {
    let attributes: [MessageAttribute] = message.attributes.filter { $0 is TextEntitiesMessageAttribute }
    let text = message.text
    let enqueue: (Media?) -> AyuCopyItemResult = { media in
        return .message(.message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: media.map { AnyMediaReference.standalone(media: $0) }, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey, correlationId: nil, bubbleUpEmojiOrStickersets: []))
    }
    let userLocation: MediaResourceUserLocation = .peer(message.id.peerId)

    switch ayuCopySource(of: message) {
    case .text:
        return .single(.finished(enqueue(nil)))
    case let .standalone(media):
        return .single(.finished(enqueue(media)))
    case .unsupported:
        return .single(.finished(.unsupported))
    case let .image(image, largest):
        let reference: AnyMediaReference = .message(message: MessageReference(message), media: image)
        return ayuDownloadAndCopy(context: context, resource: largest.resource, mediaReference: reference, userLocation: userLocation, userContentType: .image)
        |> map { step -> AyuCopyStep<AyuCopyItemResult> in
            return step.mapFinished { copy -> AyuCopyItemResult in
                guard let copy else {
                    return .failed
                }
                let representation = TelegramMediaImageRepresentation(dimensions: largest.dimensions, resource: copy, progressiveSizes: [], immediateThumbnailData: image.immediateThumbnailData)
                return enqueue(TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: [representation], immediateThumbnailData: image.immediateThumbnailData, reference: nil, partialReference: nil, flags: []))
            }
        }
    case let .file(file):
        let reference: AnyMediaReference = .message(message: MessageReference(message), media: file)
        let fileSignal = ayuDownloadAndCopy(context: context, resource: file.resource, mediaReference: reference, userLocation: userLocation, userContentType: MediaResourceUserContentType(file: file))
        let thumbnail = smallestImageRepresentation(file.previewRepresentations)
        let thumbnailSignal: Signal<AyuCopyStep<LocalFileMediaResource?>, NoError> = thumbnail.map { thumbnail in
            return ayuDownloadAndCopy(context: context, resource: thumbnail.resource, mediaReference: reference, userLocation: userLocation, userContentType: .image)
        } ?? .single(.finished(nil))

        let startedFileSignal = Signal<AyuCopyStep<LocalFileMediaResource?>, NoError>.single(.progress(0.0)) |> then(fileSignal)
        let startedThumbnailSignal = Signal<AyuCopyStep<LocalFileMediaResource?>, NoError>.single(.progress(0.0)) |> then(thumbnailSignal)
        return combineLatest(startedFileSignal, startedThumbnailSignal)
        |> map { fileStep, thumbnailStep -> AyuCopyStep<AyuCopyItemResult> in
            switch (fileStep, thumbnailStep) {
            case let (.progress(value), _):
                return .progress(value)
            case (.finished, .progress):
                return .progress(1.0)
            case let (.finished(fileCopy), .finished(thumbnailCopy)):
                guard let fileCopy else {
                    return .failed
                }
                // A thumbnail that failed to download is dropped, not fatal:
                // the server builds its own preview for the uploaded file.
                let previewRepresentations: [TelegramMediaImageRepresentation]
                if let thumbnail, let thumbnailCopy {
                    previewRepresentations = [TelegramMediaImageRepresentation(dimensions: thumbnail.dimensions, resource: thumbnailCopy, progressiveSizes: [], immediateThumbnailData: nil)]
                } else {
                    previewRepresentations = []
                }
                return enqueue(TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: fileCopy, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: file.immediateThumbnailData, mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: []))
            }
        }
    }
}

// Averages progress over all items and finishes once every item has.
private func ayuCombineCopySteps<T>(_ signals: [Signal<AyuCopyStep<T>, NoError>]) -> Signal<AyuCopyStep<[T]>, NoError> {
    if signals.isEmpty {
        return .single(.finished([]))
    }
    let startedSignals = signals.map { signal -> Signal<AyuCopyStep<T>, NoError> in
        return Signal<AyuCopyStep<T>, NoError>.single(.progress(0.0)) |> then(signal)
    }
    return combineLatest(startedSignals)
    |> map { steps -> AyuCopyStep<[T]> in
        let values = steps.compactMap { step -> T? in
            if case let .finished(value) = step {
                return value
            }
            return nil
        }
        if values.count == steps.count {
            return .finished(values)
        }
        let total = steps.reduce(Float(0.0)) { sum, step in
            switch step {
            case let .progress(value):
                return sum + value
            case .finished:
                return sum + 1.0
            }
        }
        return .progress(total / Float(steps.count))
    }
}

private func ayuDownloadAndCopy(context: AccountContext, resource: MediaResource, mediaReference: AnyMediaReference, userLocation: MediaResourceUserLocation, userContentType: MediaResourceUserContentType) -> Signal<AyuCopyStep<LocalFileMediaResource?>, NoError> {
    return ayuDownloadResource(context: context, resource: resource, mediaReference: mediaReference, userLocation: userLocation, userContentType: userContentType)
    |> deliverOn(ayuCopyQueue)
    |> map { step -> AyuCopyStep<LocalFileMediaResource?> in
        return step.mapFinished { path -> LocalFileMediaResource? in
            return path.flatMap { ayuLocalResourceCopy(context: context, sourcePath: $0) }
        }
    }
}

// Fetches the original through its message reference (so an expired file
// reference is refreshed) and finishes with the complete local path, or nil
// when the fetch fails or stops making progress.
private func ayuDownloadResource(context: AccountContext, resource: MediaResource, mediaReference: AnyMediaReference, userLocation: MediaResourceUserLocation, userContentType: MediaResourceUserContentType) -> Signal<AyuCopyStep<String?>, NoError> {
    let resources = context.engine.resources
    let engineResource = EngineMediaResource(resource)
    let resourceName = resource.id.stringRepresentation
    return Signal { subscriber in
        let finish: (String?) -> Void = { path in
            subscriber.putNext(.finished(path))
            subscriber.putCompletion()
        }
        let progress = resources.status(resource: engineResource)
        |> map(ayuFetchProgress)
        |> distinctUntilChanged

        let fetchDisposable = resources.fetch(reference: mediaReference.resourceReference(resource), userLocation: userLocation, userContentType: userContentType).start(error: { error in
            Logger.shared.log("Shadow", "forward-as-copy: fetch failed for \(resourceName): \(error)")
            finish(nil)
        })
        let progressDisposable = progress.start(next: { value in
            subscriber.putNext(.progress(value))
        })
        let stallDisposable = (progress
        |> mapToSignal { _ -> Signal<Void, NoError> in
            return .single(Void()) |> delay(AyuCopyLimits.stallTimeout, queue: Queue.concurrentDefaultQueue())
        }
        |> take(1)).start(next: { _ in
            Logger.shared.log("Shadow", "forward-as-copy: download stalled for \(resourceName)")
            finish(nil)
        })
        let dataDisposable = (resources.data(resource: engineResource, waitUntilFetchStatus: true)
        |> filter { $0.isComplete }
        |> take(1)).start(next: { data in
            finish(data.path)
        })
        return ActionDisposable {
            fetchDisposable.dispose()
            progressDisposable.dispose()
            stallDisposable.dispose()
            dataDisposable.dispose()
        }
    }
}

private func ayuFetchProgress(_ status: EngineMediaResource.FetchStatus) -> Float {
    switch status {
    case .Local:
        return 1.0
    case let .Remote(progress), let .Paused(progress):
        return progress
    case let .Fetching(_, progress):
        return progress
    }
}

private func ayuLocalResourceCopy(context: AccountContext, sourcePath: String) -> LocalFileMediaResource? {
    let copy = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: fileSize(sourcePath))
    let targetPath = context.engine.resources.resourcePath(resource: EngineMediaResource(copy))
    do {
        // A hard link is free even for a multi-gigabyte video, and MediaBox
        // never rewrites a completed file in place, so the original is safe.
        do {
            try FileManager.default.linkItem(atPath: sourcePath, toPath: targetPath)
        } catch {
            try FileManager.default.copyItem(atPath: sourcePath, toPath: targetPath)
        }
        return copy
    } catch {
        Logger.shared.log("Shadow", "forward-as-copy: cannot copy \(sourcePath): \(error)")
        return nil
    }
}
