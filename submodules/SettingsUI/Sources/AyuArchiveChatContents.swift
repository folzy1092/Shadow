import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext

// Shadow: «архив» — отдельный экран-чат, где собраны все сообщения, которые
// форк сохранил: удалённые собеседником (анти-удаление) и отредактированные
// (история правок). Идея как в AyuGram: открывается обычный чат, только с
// подборкой сообщений из разных чатов.
//
// Рисуется НАСТОЯЩИМ чат-контроллером через ChatCustomContentsProtocol —
// механизм, которым Telegram уже показывает произвольные сообщения (быстрые
// ответы, поиск по хэштегу). За счёт этого бесплатно получаем полный рендер:
// фото, видео, кружки, голосовые, подписи, альбомы, галерею по тапу.
//
// Про kind: используется .hashTagSearch, а не свой новый case. Причины:
//   1) он ровно про «список произвольных сообщений только на чтение» — панель
//      ввода и реакции при нём отключены (см. canSendMessagesToChat),
//      а у сообщений показывается имя и аватар исходного чата — то что надо,
//      когда сообщения собраны из разных чатов;
//   2) добавление своего case в ChatCustomContentsKind — это enum апстрима,
//      по нему больше двух десятков switch'ей; лишняя поверхность для
//      конфликтов при каждом обновлении Telegram, ради нулевой выгоды.
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

    init(context: AccountContext) {
        let postbox = context.account.postbox

        // Подписка на сам индекс форка, а не разовая загрузка: если прямо во
        // время просмотра архива придёт новое удаление или правка, список
        // обновится сам.
        self.disposable = (postbox.preferencesView(keys: [PreferencesKeys.ayuForkStore])
        |> mapToSignal { _ -> Signal<[Message], NoError> in
            return postbox.transaction { transaction -> [Message] in
                let store = ayuForkStore(transaction: transaction)

                var seen = Set<MessageId>()
                var messages: [Message] = []
                for ref in store.keptDeleted + store.editHistory {
                    // AyuForkMsgRef.messageId живёт внутри TelegramCore, снаружи
                    // не виден — собираем id из его публичных полей.
                    let id = MessageId(peerId: PeerId(ref.peer), namespace: ref.namespace, id: ref.id)
                    if seen.contains(id) {
                        continue
                    }
                    seen.insert(id)
                    // Сообщения могли быть вычищены (кнопками очистки в
                    // «Хранилище» или по сроку хранения) — их просто пропускаем.
                    if let message = transaction.getMessage(id) {
                        messages.append(message)
                    }
                }
                messages.sort(by: { $0.index < $1.index })
                return messages
            }
        }
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

// Экран архива: обычный чат-контроллер поверх AyuArchiveChatContents.
public func ayuArchiveChatController(context: AccountContext) -> ViewController {
    let contents = AyuArchiveChatContents(context: context)
    return context.sharedContext.makeChatController(
        context: context,
        chatLocation: .customChatContents,
        subject: .customChatContents(contents: contents),
        botStart: nil,
        mode: .standard(.default),
        params: nil
    )
}
