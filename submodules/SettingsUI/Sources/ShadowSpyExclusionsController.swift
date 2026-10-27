import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI
import PromptUI

// Shadow: a list of chats kept in one AyuGramSettings field. Two screens use it:
// the chats the spy leaves alone (spyExcludedPeerIds — no kept deletions, edit
// history or auto-saved media there) and the people whose online history is
// recorded (onlineHistoryPeerIds). A chat is added by its Bot API id (-100… for
// channels, as the profile shows it with «ID профиля») or picked from the chat
// list; tapping a row removes it.

private struct ShadowChatListScreen {
    let ids: WritableKeyPath<AyuGramSettings, [Int64]>
    let title: String
    let header: String
    let prompt: String
    let promptHint: String
    let placeholder: String
    let invalidIdText: String
    let emptyText: String
    let infoText: String
    let removeText: (String) -> String
    // Peers this list can hold; the rest are refused by id and dropped from a picker selection.
    let accepts: (EnginePeer.Id) -> Bool

    static let spyExclusions = ShadowChatListScreen(
        ids: \.spyExcludedPeerIds,
        title: "Исключения",
        header: "ИСКЛЮЧЁННЫЕ ЧАТЫ",
        prompt: "ID чата или канала",
        promptHint: "Bot API ID: -100… у каналов и супергрупп, -… у групп, число без минуса у пользователей и ботов.",
        placeholder: "-100123456789",
        invalidIdText: "Это не ID чата. Пример ID канала или супергруппы: -100123456789.",
        emptyText: "Пока пусто. Добавь канал по ID — например, -100123456789 — или выбери чаты из списка.",
        infoText: "В этих чатах не сохраняются удалённые сообщения, история правок и входящие медиа. Уже сохранённое остаётся. ID видно в профиле чата, если включено «ID профиля (Bot API)»: у каналов и супергрупп он начинается с -100. Нажми на чат, чтобы убрать его из исключений.",
        removeText: { title in "Убрать «\(title)» из исключений? Шпион снова начнёт сохранять этот чат." },
        accepts: { _ in true }
    )

    static let onlineHistory = ShadowChatListScreen(
        ids: \.onlineHistoryPeerIds,
        title: "История в сети",
        header: "ВЫБРАННЫЕ ЧАТЫ",
        prompt: "ID пользователя",
        promptHint: "Bot API ID пользователя — число без минуса, его видно в профиле с «ID профиля (Bot API)».",
        placeholder: "123456789",
        invalidIdText: "Это не ID пользователя. История в сети бывает только у людей: ID — число без минуса, например 123456789.",
        emptyText: "Пока пусто. Выбери личные чаты из списка или добавь человека по ID.",
        infoText: "Shadow записывает, когда эти люди в сети, — даже если их нет в контактах. Группы и каналы не подходят: у них нет статуса «в сети». Нажми на чат, чтобы убрать его из списка; уже записанная история остаётся.",
        removeText: { title in "Убрать «\(title)» из списка? Shadow перестанет записывать, когда этот человек в сети." },
        accepts: { $0.namespace == Namespaces.Peer.CloudUser }
    )
}

private struct ShadowListedChat: Equatable {
    let peerId: EnginePeer.Id
    let title: String
    let botApiId: Int64
}

private enum ShadowChatListEntry: ItemListNodeEntry {
    case addById
    case addFromChats
    case chatsHeader(String)
    case chat(Int32, ShadowListedChat)
    case empty(String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .addById, .addFromChats:
            return 0
        case .chatsHeader, .chat, .empty, .info:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .addById: return 0
        case .addFromChats: return 1
        case .chatsHeader: return 2
        case let .chat(index, _): return 100 + index
        case .empty: return 10000
        case .info: return 10001
        }
    }

    static func < (lhs: ShadowChatListEntry, rhs: ShadowChatListEntry) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section < rhs.section
        }
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowChatListArguments
        switch self {
        case .addById:
            return ItemListActionItem(presentationData: presentationData, title: "Добавить по ID", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addById()
            })
        case .addFromChats:
            return ItemListActionItem(presentationData: presentationData, title: "Выбрать из чатов", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addFromChats()
            })
        case let .chatsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .chat(_, chat):
            return ItemListDisclosureItem(presentationData: presentationData, title: chat.title, label: "\(chat.botApiId)", sectionId: self.section, style: .blocks, action: {
                arguments.remove(chat)
            })
        case let .empty(text), let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class ShadowChatListArguments {
    let addById: () -> Void
    let addFromChats: () -> Void
    let remove: (ShadowListedChat) -> Void

    init(addById: @escaping () -> Void, addFromChats: @escaping () -> Void, remove: @escaping (ShadowListedChat) -> Void) {
        self.addById = addById
        self.addFromChats = addFromChats
        self.remove = remove
    }
}

private func shadowUpdateChatList(context: AccountContext, ids keyPath: WritableKeyPath<AyuGramSettings, [Int64]>, _ transform: @escaping ([Int64]) -> [Int64]) {
    let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
        var current = current
        current[keyPath: keyPath] = transform(current[keyPath: keyPath])
        return current
    }.startStandalone()
}

// The picker opens with the current list selected and returns the whole
// selection: keep the order of what stayed, append what is new. Ids of chats
// the picker cannot show (added by id, never opened) stay selected, so they are
// not dropped.
private func shadowMergedChatList(current: [Int64], selected: [Int64]) -> [Int64] {
    let selectedSet = Set(selected)
    let kept = current.filter { selectedSet.contains($0) }
    let keptSet = Set(kept)
    var added: [Int64] = []
    for id in selected where !keptSet.contains(id) && !added.contains(id) {
        added.append(id)
    }
    return kept + added
}

public func shadowSpyExclusionsController(context: AccountContext) -> ViewController {
    return shadowChatListController(context: context, screen: .spyExclusions)
}

public func shadowOnlineHistoryChatsController(context: AccountContext) -> ViewController {
    return shadowChatListController(context: context, screen: .onlineHistory)
}

private func shadowChatListController(context: AccountContext, screen: ShadowChatListScreen) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = ShadowChatListArguments(addById: {
        let prompt = promptController(context: context, text: screen.prompt, subtitle: screen.promptHint, value: nil, placeholder: screen.placeholder, characterLimit: 24, apply: { value in
            guard let value else {
                return
            }
            guard let peerId = ShadowBotApiPeerId.peerId(parsing: value), screen.accepts(peerId) else {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentControllerImpl?(textAlertController(context: context, title: nil, text: screen.invalidIdText, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
                return
            }
            let id = peerId.toInt64()
            shadowUpdateChatList(context: context, ids: screen.ids) { ids in
                return ids.contains(id) ? ids : ids + [id]
            }
        })
        presentControllerImpl?(prompt)
    }, addFromChats: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let current = currentAyuGramSettings(accountId: context.account.id)[keyPath: screen.ids]
        let picker = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
            title: screen.title,
            searchPlaceholder: presentationData.strings.ChatListFilter_AddChatsSearchPlaceholder,
            selectedChats: Set(current.map { EnginePeer.Id($0) }),
            additionalCategories: nil,
            chatListFilters: nil
        )), filters: [], alwaysEnabled: true))
        picker.navigationPresentation = .modal
        let _ = (picker.result
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak picker] result in
            guard case let .result(peerIds, _) = result else {
                picker?.dismiss()
                return
            }
            var selected: [Int64] = []
            for peerId in peerIds {
                if case let .peer(id) = peerId, screen.accepts(id) {
                    selected.append(id.toInt64())
                }
            }
            shadowUpdateChatList(context: context, ids: screen.ids) { ids in
                return shadowMergedChatList(current: ids, selected: selected)
            }
            picker?.dismiss()
        })
        pushControllerImpl?(picker)
    }, remove: { chat in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: screen.removeText(chat.title), actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: "Убрать", action: {
                let id = chat.peerId.toInt64()
                shadowUpdateChatList(context: context, ids: screen.ids) { ids in
                    return ids.filter { $0 != id }
                }
            })
        ]))
    })

    let listedChats: Signal<[ShadowListedChat], NoError> = ayuGramSettings(postbox: context.account.postbox)
    |> map { $0[keyPath: screen.ids] }
    |> distinctUntilChanged
    |> mapToSignal { ids -> Signal<[ShadowListedChat], NoError> in
        let peerIds = ids.map { EnginePeer.Id($0) }
        return context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> [ShadowListedChat] in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            return peerIds.map { peerId in
                let title = peers[peerId].flatMap { $0 }?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "Неизвестный чат"
                return ShadowListedChat(peerId: peerId, title: title, botApiId: ShadowBotApiPeerId.botApiId(peerId))
            }
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, listedChats)
    |> deliverOnMainQueue
    |> map { presentationData, chats -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowChatListEntry] = [.addById, .addFromChats, .chatsHeader(screen.header)]
        for (index, chat) in chats.enumerated() {
            entries.append(.chat(Int32(index), chat))
        }
        if chats.isEmpty {
            entries.append(.empty(screen.emptyText))
        }
        entries.append(.info(screen.infoText))
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(screen.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
