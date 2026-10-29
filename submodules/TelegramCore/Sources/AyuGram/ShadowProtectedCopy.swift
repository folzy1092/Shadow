import Foundation
import Postbox
import SwiftSignalKit

// Shadow: forward-as-copy for copy-protected (noforwards) chats and secret
// (view-once / self-destruct) media. The server rejects a native forward from
// such a source, so each message is re-sent as a new message: its text plus a
// fresh local copy of its media, the same idea the core uses for secret-chat
// forwards (convertForwardedMediaForSecretChat).
//
// The copy owns its bytes: the downloaded original is linked into a new
// LocalFileMediaResource inside MediaBox, so the upload never touches the
// source resource, and the source never loses its file when the copy's send
// is cleaned up. The copy also carries no cloud thumbnail of the original —
// uploading that thumbnail through a standalone reference cannot refresh an
// expired file reference and left the copy stuck in "sending" forever.
//
// Two users:
//   - the chat's forward flow (ChatControllerForwardAsCopy), which builds the
//     batch behind a progress toast before it enqueues;
//   - enqueueMessages itself (replacingProtectedForwards): every native
//     .forward whose source is protected is turned into a copy there, so a
//     forward started anywhere (gallery, profile media, search, the share
//     sheet, a forward draft, the paperclip pranks) cannot reach the server
//     as a forward that it then rejects.
public enum ShadowProtectedCopy {
    // A download that shows no progress for this long is treated as dead
    // (expired reference, no connection). Any progress restarts the countdown,
    // so a large video on a slow link keeps going.
    public static let stallTimeout: Double = 90.0

    public enum Step<T> {
        case progress(Float)
        case finished(T)

        public func mapFinished<U>(_ transform: (T) -> U) -> Step<U> {
            switch self {
            case let .progress(value):
                return .progress(value)
            case let .finished(value):
                return .finished(transform(value))
            }
        }
    }

    public enum ItemResult {
        case message(EnqueueMessage)
        case failed
        case unsupported
    }

    public struct Batch {
        // One entry per source message, in order.
        public let results: [ItemResult]

        public init(results: [ItemResult]) {
            self.results = results
        }

        public static let empty = Batch(results: [])

        public var messages: [EnqueueMessage] {
            return self.results.compactMap { result -> EnqueueMessage? in
                if case let .message(message) = result {
                    return message
                }
                return nil
            }
        }

        public var failedCount: Int {
            return self.results.filter { if case .failed = $0 { return true } else { return false } }.count
        }

        public var unsupportedCount: Int {
            return self.results.filter { if case .unsupported = $0 { return true } else { return false } }.count
        }

        // A failed download blocks the whole batch, so an album is never sent
        // with holes in it; a poll or story among the selection is only
        // skipped, since it has no copyable content at all.
        public var canSend: Bool {
            return self.failedCount == 0 && !self.messages.isEmpty
        }

        public var skippedNote: String? {
            if self.unsupportedCount == 0 {
                return nil
            }
            return "Пропущено: \(self.unsupportedCount) — опросы, игры и истории не копируются"
        }
    }

    // The server refuses a native forward of this message: its chat has
    // content protection (or the message itself is protected), or its media
    // is secret. Keys off the real server flags, not off isCopyProtected(),
    // which the «allow save» toggle forces to false.
    public static func needsCopy(_ message: Message) -> Bool {
        return message.isServerCopyProtected() || message.containsSecretMedia
    }

    public static func needsCopy(_ messages: [Message]) -> Bool {
        return messages.contains(where: { ShadowProtectedCopy.needsCopy($0) })
    }

    // Builds the copies of `messages`. Messages of one album share a fresh
    // grouping key, so the copy lands as one grouped post with its caption.
    // `extraAttributes` (silent, schedule, paid stars …) go onto every copy.
    public static func build(account: Account, messages: [Message], threadId: Int64?, extraAttributes: [Int: [MessageAttribute]] = [:], correlationIds: [Int: Int64] = [:]) -> Signal<Step<Batch>, NoError> {
        let originalGroupingKeys = Set(messages.compactMap { $0.groupingKey })
        let groupingKeys = Dictionary(uniqueKeysWithValues: originalGroupingKeys.map { ($0, Int64.random(in: Int64.min ... Int64.max)) })

        let items = messages.enumerated().map { index, message in
            return copyItem(account: account, message: message, threadId: threadId, groupingKey: message.groupingKey.flatMap { groupingKeys[$0] }, extraAttributes: extraAttributes[index] ?? [], correlationId: correlationIds[index])
        }
        return combineSteps(items)
        |> map { step -> Step<Batch> in
            return step.mapFinished { results in
                return Batch(results: results)
            }
        }
    }

    // enqueueMessages' net: every .forward whose source is in `protectedSources`
    // becomes a copy (keeping its thread, correlation id and send options);
    // other messages pass unchanged. One result per input message, in order:
    // nil where a copy could not be made (the message is then not sent).
    static func replacingProtectedForwards(account: Account, messages: [EnqueueMessage], protectedSources: [MessageId: Message]) -> Signal<[EnqueueMessage?], NoError> {
        var copySources: [Message] = []
        var copyIndices: [Int] = []
        var extraAttributes: [Int: [MessageAttribute]] = [:]
        var correlationIds: [Int: Int64] = [:]
        var threadId: Int64?
        for (index, message) in messages.enumerated() {
            guard case let .forward(source, forwardThreadId, _, attributes, correlationId) = message, let sourceMessage = protectedSources[source] else {
                continue
            }
            let copyIndex = copySources.count
            copySources.append(sourceMessage)
            copyIndices.append(index)
            extraAttributes[copyIndex] = attributes.filter { attribute in
                return !(attribute is ForwardOptionsMessageAttribute) && !(attribute is ForwardVideoTimestampAttribute)
            }
            if let correlationId {
                correlationIds[copyIndex] = correlationId
            }
            if threadId == nil {
                threadId = forwardThreadId
            }
        }
        if copySources.isEmpty {
            return .single(messages.map { Optional($0) })
        }
        Logger.shared.log("Shadow", "forward-as-copy: \(copySources.count) protected forward(s) become copies")
        return build(account: account, messages: copySources, threadId: threadId, extraAttributes: extraAttributes, correlationIds: correlationIds)
        |> mapToSignal { step -> Signal<Batch, NoError> in
            if case let .finished(batch) = step {
                return .single(batch)
            }
            return .complete()
        }
        |> take(1)
        |> map { batch -> [EnqueueMessage?] in
            var result: [EnqueueMessage?] = messages.map { Optional($0) }
            for (copyIndex, index) in copyIndices.enumerated() {
                if copyIndex < batch.results.count, case let .message(copy) = batch.results[copyIndex] {
                    result[index] = copy
                } else {
                    result[index] = nil
                }
            }
            return result
        }
    }

    private enum Source {
        case text
        case standalone(Media)
        case file(TelegramMediaFile)
        case image(TelegramMediaImage, TelegramMediaImageRepresentation)
        case unsupported
    }

    private static func source(of message: Message) -> Source {
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

    private static func copyItem(account: Account, message: Message, threadId: Int64?, groupingKey: Int64?, extraAttributes: [MessageAttribute], correlationId: Int64?) -> Signal<Step<ItemResult>, NoError> {
        let attributes: [MessageAttribute] = message.attributes.filter { $0 is TextEntitiesMessageAttribute } + extraAttributes
        let text = message.text
        let enqueue: (Media?) -> ItemResult = { media in
            return .message(.message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: media.map { AnyMediaReference.standalone(media: $0) }, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: []))
        }
        let userLocation: MediaResourceUserLocation = .peer(message.id.peerId)

        switch source(of: message) {
        case .text:
            return .single(.finished(enqueue(nil)))
        case let .standalone(media):
            return .single(.finished(enqueue(media)))
        case .unsupported:
            return .single(.finished(.unsupported))
        case let .image(image, largest):
            let reference: AnyMediaReference = .message(message: MessageReference(message), media: image)
            return downloadAndCopy(account: account, resource: largest.resource, mediaReference: reference, userLocation: userLocation, userContentType: .image)
            |> map { step -> Step<ItemResult> in
                return step.mapFinished { copy -> ItemResult in
                    guard let copy else {
                        return .failed
                    }
                    let representation = TelegramMediaImageRepresentation(dimensions: largest.dimensions, resource: copy, progressiveSizes: [], immediateThumbnailData: image.immediateThumbnailData)
                    return enqueue(TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: [representation], immediateThumbnailData: image.immediateThumbnailData, reference: nil, partialReference: nil, flags: []))
                }
            }
        case let .file(file):
            let reference: AnyMediaReference = .message(message: MessageReference(message), media: file)
            let fileSignal = downloadAndCopy(account: account, resource: file.resource, mediaReference: reference, userLocation: userLocation, userContentType: MediaResourceUserContentType(file: file))
            let thumbnail = smallestImageRepresentation(file.previewRepresentations)
            let thumbnailSignal: Signal<Step<LocalFileMediaResource?>, NoError> = thumbnail.map { thumbnail in
                return downloadAndCopy(account: account, resource: thumbnail.resource, mediaReference: reference, userLocation: userLocation, userContentType: .image)
            } ?? .single(.finished(nil))

            let startedFileSignal = Signal<Step<LocalFileMediaResource?>, NoError>.single(.progress(0.0)) |> then(fileSignal)
            let startedThumbnailSignal = Signal<Step<LocalFileMediaResource?>, NoError>.single(.progress(0.0)) |> then(thumbnailSignal)
            return combineLatest(startedFileSignal, startedThumbnailSignal)
            |> map { fileStep, thumbnailStep -> Step<ItemResult> in
                switch (fileStep, thumbnailStep) {
                case let (.progress(value), _):
                    return .progress(value)
                case (.finished, .progress):
                    return .progress(1.0)
                case let (.finished(fileCopy), .finished(thumbnailCopy)):
                    guard let fileCopy else {
                        return .finished(.failed)
                    }
                    // A thumbnail that failed to download is dropped, not fatal:
                    // the server builds its own preview for the uploaded file.
                    let previewRepresentations: [TelegramMediaImageRepresentation]
                    if let thumbnail, let thumbnailCopy {
                        previewRepresentations = [TelegramMediaImageRepresentation(dimensions: thumbnail.dimensions, resource: thumbnailCopy, progressiveSizes: [], immediateThumbnailData: nil)]
                    } else {
                        previewRepresentations = []
                    }
                    return .finished(enqueue(TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: fileCopy, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: file.immediateThumbnailData, mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: [])))
                }
            }
        }
    }

    // Averages progress over all items and finishes once every item has.
    private static func combineSteps<T>(_ signals: [Signal<Step<T>, NoError>]) -> Signal<Step<[T]>, NoError> {
        if signals.isEmpty {
            return .single(.finished([]))
        }
        let startedSignals = signals.map { signal -> Signal<Step<T>, NoError> in
            return Signal<Step<T>, NoError>.single(.progress(0.0)) |> then(signal)
        }
        return combineLatest(startedSignals)
        |> map { steps -> Step<[T]> in
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

    private static let copyQueue = Queue(name: "org.shadow.forward-copy")

    private static func downloadAndCopy(account: Account, resource: MediaResource, mediaReference: AnyMediaReference, userLocation: MediaResourceUserLocation, userContentType: MediaResourceUserContentType) -> Signal<Step<LocalFileMediaResource?>, NoError> {
        return downloadResource(account: account, resource: resource, mediaReference: mediaReference, userLocation: userLocation, userContentType: userContentType)
        |> deliverOn(ShadowProtectedCopy.copyQueue)
        |> map { step -> Step<LocalFileMediaResource?> in
            return step.mapFinished { path -> LocalFileMediaResource? in
                return path.flatMap { ShadowProtectedCopy.localResourceCopy(account: account, sourcePath: $0) }
            }
        }
    }

    // Fetches the original through its message reference (so an expired file
    // reference is refreshed) and finishes with the complete local path, or nil
    // when the fetch fails or stops making progress.
    private static func downloadResource(account: Account, resource: MediaResource, mediaReference: AnyMediaReference, userLocation: MediaResourceUserLocation, userContentType: MediaResourceUserContentType) -> Signal<Step<String?>, NoError> {
        let resources = TelegramEngine(account: account).resources
        let engineResource = EngineMediaResource(resource)
        let resourceName = resource.id.stringRepresentation
        return Signal { subscriber in
            let finish: (String?) -> Void = { path in
                subscriber.putNext(.finished(path))
                subscriber.putCompletion()
            }
            let progress = resources.status(resource: engineResource)
            |> map(ShadowProtectedCopy.fetchProgress)
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
                return .single(Void()) |> delay(ShadowProtectedCopy.stallTimeout, queue: Queue.concurrentDefaultQueue())
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

    private static func fetchProgress(_ status: EngineMediaResource.FetchStatus) -> Float {
        switch status {
        case .Local:
            return 1.0
        case let .Remote(progress), let .Paused(progress):
            return progress
        case let .Fetching(_, progress):
            return progress
        }
    }

    private static func localResourceCopy(account: Account, sourcePath: String) -> LocalFileMediaResource? {
        let copy = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: fileSize(sourcePath))
        let targetPath = account.postbox.mediaBox.resourcePath(copy)
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
}
