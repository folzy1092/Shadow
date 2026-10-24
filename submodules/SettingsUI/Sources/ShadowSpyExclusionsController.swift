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

// Shadow: chats the spy leaves alone (AyuGramSettings.spyExcludedPeerIds) — no
// kept deletions, edit history or auto-saved media there. A chat is added by its
// Bot API id (-100… for channels, as the profile shows it with «ID профиля»)
// or picked from the chat list; tapping a row removes it.

private struct ShadowSpyExcludedChat: Equatable {
    let peerId: EnginePeer.Id
    let title: String
    let botApiId: Int64
}

private enum ShadowSpyExclusionsEntry: ItemListNodeEntry {
    case addById
    case addFromChats
    case chatsHeader
    case chat(Int32, ShadowSpyExcludedChat)
    case empty
    case info

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

    static func < (lhs: ShadowSpyExclusionsEntry, rhs: ShadowSpyExclusionsEntry) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section < rhs.section
        }
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowSpyExclusionsArguments
        switch self {
        case .addById:
            return ItemListActionItem(presentationData: presentationData, title: "Добавить по ID", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addById()
            })
        case .addFromChats:
            return ItemListActionItem(presentationData: presentationData, title: "Выбрать из чатов", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addFromChats()
            })
        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИСКЛЮЧЁННЫЕ ЧАТЫ", sectionId: self.section)
        case let .chat(_, chat):
            return ItemListDisclosureItem(presentationData: presentationData, title: chat.title, label: "\(chat.botApiId)", sectionId: self.section, style: .blocks, action: {
                arguments.remove(chat)
            })
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Пока пусто. Добавь канал по ID — например, -100123456789 — или выбери чаты из списка."), sectionId: self.section)
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain("В этих чатах не сохраняются удалённые сообщения, история правок и входящие медиа. Уже сохранённое остаётся. ID видно в профиле чата, если включено «ID профиля (Bot API)»: у каналов и супергрупп он начинается с -100. Нажми на чат, чтобы убрать его из исключений."), sectionId: self.section)
        }
    }
}

private final class ShadowSpyExclusionsArguments {
    let addById: () -> Void
    let addFromChats: () -> Void
    let remove: (ShadowSpyExcludedChat) -> Void

    init(addById: @escaping () -> Void, addFromChats: @escaping () -> Void, remove: @escaping (ShadowSpyExcludedChat) -> Void) {
        self.addById = addById
        self.addFromChats = addFromChats
        self.remove = remove
    }
}

private func shadowUpdateSpyExclusions(context: AccountContext, _ transform: @escaping ([Int64]) -> [Int64]) {
    let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
        var current = current
        current.spyExcludedPeerIds = transform(current.spyExcludedPeerIds)
        return current
    }.startStandalone()
}

// The picker opens with the current list selected and returns the whole
// selection: keep the order of what stayed, append what is new. Ids of chats
// the picker cannot show (added by id, never opened) stay selected, so they are
// not dropped.
private func shadowMergedSpyExclusions(current: [Int64], selected: [Int64]) -> [Int64] {
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
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = ShadowSpyExclusionsArguments(addById: {
        let prompt = promptController(context: context, text: "ID чата или канала", subtitle: "Bot API ID: -100… у каналов и супергрупп, -… у групп, число без минуса у пользователей и ботов.", value: nil, placeholder: "-100123456789", characterLimit: 24, apply: { value in
            guard let value else {
                return
            }
            guard let peerId = ShadowBotApiPeerId.peerId(parsing: value) else {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentControllerImpl?(textAlertController(context: context, title: nil, text: "Это не ID чата. Пример ID канала или супергруппы: -100123456789.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
                return
            }
            let id = peerId.toInt64()
            shadowUpdateSpyExclusions(context: context) { ids in
                return ids.contains(id) ? ids : ids + [id]
            }
        })
        presentControllerImpl?(prompt)
    }, addFromChats: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let current = currentAyuGramSettings(accountId: context.account.id).spyExcludedPeerIds
        let picker = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
            title: "Исключённые чаты",
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
                if case let .peer(id) = peerId {
                    selected.append(id.toInt64())
                }
            }
            shadowUpdateSpyExclusions(context: context) { ids in
                return shadowMergedSpyExclusions(current: ids, selected: selected)
            }
            picker?.dismiss()
        })
        pushControllerImpl?(picker)
    }, remove: { chat in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: "Убрать «\(chat.title)» из исключений? Шпион снова начнёт сохранять этот чат.", actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: "Убрать", action: {
                let id = chat.peerId.toInt64()
                shadowUpdateSpyExclusions(context: context) { ids in
                    return ids.filter { $0 != id }
                }
            })
        ]))
    })

    let excludedChats: Signal<[ShadowSpyExcludedChat], NoError> = ayuGramSettings(postbox: context.account.postbox)
    |> map { $0.spyExcludedPeerIds }
    |> distinctUntilChanged
    |> mapToSignal { ids -> Signal<[ShadowSpyExcludedChat], NoError> in
        let peerIds = ids.map { EnginePeer.Id($0) }
        return context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> [ShadowSpyExcludedChat] in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            return peerIds.map { peerId in
                let title = peers[peerId].flatMap { $0 }?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "Неизвестный чат"
                return ShadowSpyExcludedChat(peerId: peerId, title: title, botApiId: ShadowBotApiPeerId.botApiId(peerId))
            }
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, excludedChats)
    |> deliverOnMainQueue
    |> map { presentationData, chats -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowSpyExclusionsEntry] = [.addById, .addFromChats, .chatsHeader]
        for (index, chat) in chats.enumerated() {
            entries.append(.chat(Int32(index), chat))
        }
        if chats.isEmpty {
            entries.append(.empty)
        }
        entries.append(.info)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Исключения"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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
