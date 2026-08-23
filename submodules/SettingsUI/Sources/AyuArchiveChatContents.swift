import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext

// Shadow: «архив» — сохранённые форком сообщения, показанные обычным чатом.
// Три входа в один и тот же экран:
//   • весь архив                        — ayuArchiveChatController(context:)
//   • удалённые в конкретном чате        — ayuArchiveChatController(context:peerId:)
//   • история правок одного сообщения    — ayuEditHistoryChatController(context:message:)
//
// Рисуется НАСТОЯЩИМ чат-контроллером через ChatCustomContentsProtocol —
// механизм, которым Telegram уже показывает произвольные сообщения (быстрые
// ответы, поиск по хэштегу). За счёт этого бесплатно получаем полный рендер:
// фото, видео, кружки, голосовые, подписи, галерею по тапу.
//
// Про kind: используется .hashTagSearch, а не свой новый case. Он ровно про
// «список произвольных сообщений только на чтение»: панель ввода и реакции при
// нём отключены (canSendMessagesToChat), а у сообщений показывается имя и
// аватар исходного чата. Свой case означал бы правку enum апстрима, по которому
// больше двух десятков switch'ей — лишняя поверхность конфликтов при каждом
// обновлении Telegram без выигрыша по функциональности.
final class AyuArchiveChatContents: ChatCustomContentsProtocol {
    var kind: ChatCustomContentsKind {
        return .hashTagSearch(publicPosts: false)
    }

    var messageLimit: Int? {
        return nil
    }

    private let historyViewValue = Promise<(EngineRawMessageHistoryView, EngineViewUpdateType)>()
    var historyView: Signal<(EngineRawMessageHistoryView, EngineViewUpdateType), NoError> {
        return self.historyViewValue.get()
    }

    private var disposable: Disposable?

    init(messages: Signal<[Message], NoError>) {
        self.disposable = (messages
        |> deliverOnMainQueue).start(next: { [weak self] messages in
            guard let self else {
                return
            }
            let entries = messages.map { message in
                return EngineRawMessageHistoryEntry(
                    message: message,
                    isRead: true,
                    location: nil,
                    monthLocation: nil,
                    attributes: EngineRawMutableMessageHistoryEntryAttributes(authorIsContact: false)
                )
            }
            let view = EngineRawMessageHistoryView(
                tag: nil,
                namespaces: .all,
                entries: entries,
                holeEarlier: false,
                holeLater: false,
                isLoading: false
            )
            self.historyViewValue.set(.single((view, .Initial)))
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    // Архив только на чтение — отправлять, удалять и редактировать в нём нечего.
    func enqueueMessages(messages: [EnqueueMessage]) {
    }

    func deleteMessages(ids: [EngineMessage.Id]) {
    }

    func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {
    }

    func quickReplyUpdateShortcut(value: String) {
    }

    func businessLinkUpdate(message: String, entities: [MessageTextEntity], title: String?) {
    }

    // Весь список отдаётся сразу — дозагружать нечего.
    func loadMore() {
    }

    func hashtagSearchUpdate(query: String) {
    }

    var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void = { _ in }
}

// MARK: - Источники сообщений

// Сохранённые сообщения из индекса форка. peerId != nil — только из этого чата.
//
// Подписка на сам индекс, а не разовое чтение: если во время просмотра придёт
// новое удаление или правка, список обновится сам.
private func ayuArchiveMessages(context: AccountContext, peerId: PeerId?) -> Signal<[Message], NoError> {
    let postbox = context.account.postbox
    return postbox.preferencesView(keys: [PreferencesKeys.ayuForkStore])
    |> mapToSignal { _ -> Signal<[Message], NoError> in
        return postbox.transaction { transaction -> [Message] in
            let store = ayuForkStore(transaction: transaction)

            var seen = Set<MessageId>()
            var messages: [Message] = []
            for ref in store.keptDeleted + store.editHistory {
                // AyuForkMsgRef.messageId живёт внутри TelegramCore, снаружи не
                // виден — собираем id из его публичных полей.
                let id = MessageId(peerId: PeerId(ref.peer), namespace: ref.namespace, id: ref.id)
                if let peerId, id.peerId != peerId {
                    continue
                }
                if seen.contains(id) {
                    continue
                }
                seen.insert(id)
                // Сообщения могли быть вычищены (кнопками очистки в «Хранилище»
                // или по сроку хранения) — их просто пропускаем.
                if let message = transaction.getMessage(id) {
                    messages.append(message)
                }
            }
            messages.sort(by: { $0.index < $1.index })
            return messages
        }
    }
}

// MARK: - История правок как чат

// Восстанавливает медиа сохранённой версии из приватной папки форка.
//
// Файл там лежит настоящий (положен туда при захвате правки), поэтому строим
// медиа поверх LocalFileReferenceMediaResource с путём к нему — дальше чат
// рисует его как обычное фото/видео/голосовое. Раньше вместо этого в меню
// показывался просто эмодзи-маркер вида "🖼 [media]".
private func ayuRestoredMedia(basePath: String, version: SavedMessageEditVersion) -> Media? {
    guard let fileName = version.mediaFileName else {
        return nil
    }
    let path = AyuSavedMedia.directory(basePath: basePath) + "/" + fileName
    guard FileManager.default.fileExists(atPath: path) else {
        return nil
    }
    let resource = LocalFileReferenceMediaResource(localFilePath: path, randomId: Int64.random(in: Int64.min ... Int64.max))
    var fileSize: Int64?
    if let attributes = try? FileManager.default.attributesOfItem(atPath: path), let size = attributes[.size] as? NSNumber {
        fileSize = size.int64Value
    }

    switch version.mediaKind {
    case "image":
        // Реальные размеры читаем из самого файла — иначе картинка поедет по
        // пропорциям. Если прочитать не удалось, берём квадрат: лучше слегка
        // неверные пропорции, чем не показать фото вовсе.
        let dimensions: PixelDimensions
        if let image = UIImage(contentsOfFile: path) {
            dimensions = PixelDimensions(width: Int32(image.size.width * image.scale), height: Int32(image.size.height * image.scale))
        } else {
            dimensions = PixelDimensions(width: 1280, height: 1280)
        }
        let representation = TelegramMediaImageRepresentation(dimensions: dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: nil)
        return TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
    default:
        let attributes: [TelegramMediaFileAttribute]
        let mimeType: String
        switch version.mediaKind {
        case "video":
            attributes = [.Video(duration: 0.0, size: PixelDimensions(width: 720, height: 720), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)]
            mimeType = "video/mp4"
        case "roundVideo":
            attributes = [.Video(duration: 0.0, size: PixelDimensions(width: 400, height: 400), flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)]
            mimeType = "video/mp4"
        case "voice":
            attributes = [.Audio(isVoice: true, duration: 0, title: nil, performer: nil, waveform: nil)]
            mimeType = "audio/ogg"
        default:
            attributes = [.FileName(fileName: fileName)]
            mimeType = "application/octet-stream"
        }
        return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: fileSize, attributes: attributes, alternativeRepresentations: [])
    }
}

// Собирает версии сообщения в цепочку "сообщений": каждая прошлая версия плюс
// текущая последним. Синтетические копии делаются от самого сообщения, поэтому
// автор, чат и оформление у них те же, что у оригинала.
private func ayuEditHistoryMessages(context: AccountContext, message: Message) -> Signal<[Message], NoError> {
    let basePath = context.account.postbox.mediaBox.basePath
    return Signal { subscriber in
        var result: [Message] = []
        var syntheticId: Int32 = 1
        var stableId: UInt32 = 1

        if let attribute = message.attributes.first(where: { $0 is SavedMessageEditsAttribute }) as? SavedMessageEditsAttribute {
            for version in attribute.versions {
                // Служебные атрибуты форка снимаем: иначе на каждой версии
                // повиснет значок корзины и пункт "История изменений", ведущий
                // сам в себя.
                let attributes = message.attributes.filter { !($0 is SavedMessageEditsAttribute) && !($0 is DeletedMessageAttribute) }
                var versionMessage = message
                    .withUpdatedId(id: MessageId(peerId: message.id.peerId, namespace: Namespaces.Message.Local, id: syntheticId))
                    .withUpdatedStableId(stableId: stableId)
                    .withUpdatedText(version.text)
                    .withUpdatedTimestamp(version.date)
                    .withUpdatedAttributes(attributes)
                versionMessage = versionMessage.withUpdatedMedia(ayuRestoredMedia(basePath: basePath, version: version).flatMap { [$0] } ?? [])
                result.append(versionMessage)
                syntheticId += 1
                stableId += 1
            }
        }

        // Текущая версия — как есть, но без атрибутов форка (см. выше).
        let currentAttributes = message.attributes.filter { !($0 is SavedMessageEditsAttribute) && !($0 is DeletedMessageAttribute) }
        result.append(message
            .withUpdatedId(id: MessageId(peerId: message.id.peerId, namespace: Namespaces.Message.Local, id: syntheticId))
            .withUpdatedStableId(stableId: stableId)
            .withUpdatedAttributes(currentAttributes))

        subscriber.putNext(result)
        subscriber.putCompletion()
        return EmptyDisposable
    }
    |> runOn(Queue.concurrentDefaultQueue())
}

// MARK: - Экраны

private func ayuArchiveController(context: AccountContext, messages: Signal<[Message], NoError>) -> ViewController {
    let contents = AyuArchiveChatContents(messages: messages)
    return context.sharedContext.makeChatController(
        context: context,
        chatLocation: .customChatContents,
        subject: .customChatContents(contents: contents),
        botStart: nil,
        mode: .standard(.default),
        params: nil
    )
}

// Весь архив, либо только сохранённое из одного чата.
public func ayuArchiveChatController(context: AccountContext, peerId: PeerId? = nil) -> ViewController {
    return ayuArchiveController(context: context, messages: ayuArchiveMessages(context: context, peerId: peerId))
}

// История правок одного сообщения, показанная чатом.
public func ayuEditHistoryChatController(context: AccountContext, message: Message) -> ViewController {
    return ayuArchiveController(context: context, messages: ayuEditHistoryMessages(context: context, message: message))
}
