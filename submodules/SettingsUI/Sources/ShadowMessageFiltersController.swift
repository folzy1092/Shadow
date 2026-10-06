import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI
import AlertUI

// Shadow: message filters screen, modelled on AyuGram Desktop — a list of
// regex filters, each edited in its own sheet (ShadowMessageFilterEditController),
// plus the shadow-ban list (users whose messages are hidden without blocking).

private enum ShadowMessageFiltersEntry: ItemListNodeEntry {
    case showPlaceholder(Bool)
    case placeholderInfo
    case add
    case filter(Int32, ShadowMessageFilter)
    case empty
    case help
    case banHeader
    case banned(Int32, EnginePeer.Id, String)
    case banInfo

    var section: ItemListSectionId {
        switch self {
        case .showPlaceholder, .placeholderInfo:
            return 0
        case .add, .filter, .empty:
            return 1
        case .help:
            return 2
        case .banHeader, .banned, .banInfo:
            return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .showPlaceholder: return 0
        case .placeholderInfo: return 1
        case .add: return 2
        case let .filter(index, _): return 100 + index
        case .empty: return 10000
        case .help: return 10001
        case .banHeader: return 20000
        case let .banned(index, _, _): return 20001 + index
        case .banInfo: return 30000
        }
    }

    static func < (lhs: ShadowMessageFiltersEntry, rhs: ShadowMessageFiltersEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowMessageFiltersArguments
        switch self {
        case let .showPlaceholder(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Плашка «Скрыто локальным фильтром»", value: value, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setShowPlaceholder(value)
            })
        case .placeholderInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Выключено — совпавшие сообщения и сообщения из теневого бана пропадают из чата полностью, без плашки."), sectionId: self.section)
        case .add:
            return ItemListActionItem(presentationData: presentationData, title: "Добавить фильтр", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .filter(_, filter):
            var flags: [String] = []
            if !filter.enabled {
                flags.append("выкл")
            }
            if !filter.caseInsensitive {
                flags.append("Аа")
            }
            if filter.reversed {
                flags.append("обратный")
            }
            return ItemListDisclosureItem(presentationData: presentationData, title: filter.expression, enabled: true, label: flags.joined(separator: " · "), sectionId: self.section, style: .blocks, action: {
                arguments.edit(filter)
            })
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Фильтров пока нет. Добавь здесь или прямо из чата: выдели текст или зажми @username и нажми «В фильтры»."), sectionId: self.section)
        case .help:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Совпадения ищутся в тексте и подписях сообщений. Скрываются только на этом устройстве: сообщения не удаляются, прочтения не отправляются. «Аа» — с учётом регистра."), sectionId: self.section)
        case .banHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ТЕНЕВОЙ БАН", sectionId: self.section)
        case let .banned(_, peerId, title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "Снять", sectionId: self.section, style: .blocks, action: {
                arguments.unban(peerId, title)
            })
        case .banInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Сообщения этих людей скрываются во всех чатах, без чёрного списка — они ничего не узнают. Добавить: профиль пользователя → «…» → «Теневой бан»."), sectionId: self.section)
        }
    }
}

private final class ShadowMessageFiltersArguments {
    let setShowPlaceholder: (Bool) -> Void
    let add: () -> Void
    let edit: (ShadowMessageFilter) -> Void
    let unban: (EnginePeer.Id, String) -> Void

    init(setShowPlaceholder: @escaping (Bool) -> Void, add: @escaping () -> Void, edit: @escaping (ShadowMessageFilter) -> Void, unban: @escaping (EnginePeer.Id, String) -> Void) {
        self.setShowPlaceholder = setShowPlaceholder
        self.add = add
        self.edit = edit
        self.unban = unban
    }
}

// MARK: - Shadow ban

public func shadowIsShadowBanned(context: AccountContext, peerId: EnginePeer.Id) -> Bool {
    return currentAyuGramSettings(accountId: context.account.id).isShadowBanned(peerId: peerId.toInt64())
}

private func shadowSetShadowBanned(context: AccountContext, peerId: EnginePeer.Id, banned: Bool) {
    let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
        var current = current
        current.shadowBannedPeerIds.removeAll(where: { $0 == peerId.toInt64() })
        if banned {
            current.shadowBannedPeerIds.append(peerId.toInt64())
        }
        return current
    }.startStandalone()
}

// Toggles the ban and confirms it with a toast on `controller`.
public func shadowToggleShadowBan(context: AccountContext, peerId: EnginePeer.Id, title: String, from controller: ViewController) {
    let banned = !shadowIsShadowBanned(context: context, peerId: peerId)
    shadowSetShadowBanned(context: context, peerId: peerId, banned: banned)
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let text = banned ? "\(title) в теневом бане: его сообщения скрыты." : "Теневой бан снят: сообщения \(title) снова видны."
    controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
}

// MARK: - Screen

public func shadowMessageFiltersController(context: AccountContext) -> ViewController {
    return shadowMessageFiltersController(context: context, focus: nil)
}

func shadowMessageFiltersController(context: AccountContext, focus: ShadowSettingsSearchItem?) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let linkRows = ShadowSettingsLinkRows()
    var focusedIndex: Int?
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = ShadowMessageFiltersArguments(setShowPlaceholder: { value in
        let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
            var current = current
            current.messageFilterShowPlaceholder = value
            return current
        }.startStandalone()
    }, add: {
        pushControllerImpl?(shadowMessageFilterEditController(context: context, filter: nil))
    }, edit: { filter in
        pushControllerImpl?(shadowMessageFilterEditController(context: context, filter: filter))
    }, unban: { peerId, title in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: "Снять теневой бан с \(title)?", actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: "Снять", action: {
                shadowSetShadowBanned(context: context, peerId: peerId, banned: false)
            })
        ]))
    })

    let settings = ayuGramSettings(postbox: context.account.postbox)
    let bannedPeers: Signal<[(EnginePeer.Id, String)], NoError> = settings
    |> map { $0.shadowBannedPeerIds }
    |> distinctUntilChanged
    |> mapToSignal { ids -> Signal<[(EnginePeer.Id, String)], NoError> in
        let peerIds = ids.map { EnginePeer.Id($0) }
        return context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> [(EnginePeer.Id, String)] in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            return peerIds.map { peerId in
                let title = peers[peerId].flatMap { $0 }?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "Пользователь \(peerId.id._internalGetInt64Value())"
                return (peerId, title)
            }
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, settings, bannedPeers)
    |> deliverOnMainQueue
    |> map { presentationData, settings, bannedPeers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowMessageFiltersEntry] = [.showPlaceholder(settings.messageFilterShowPlaceholder), .placeholderInfo, .add]
        for (index, filter) in settings.messageFilters.enumerated() {
            entries.append(.filter(Int32(index), filter))
        }
        if settings.messageFilters.isEmpty {
            entries.append(.empty)
        }
        entries.append(.help)
        entries.append(.banHeader)
        for (index, item) in bannedPeers.enumerated() {
            entries.append(.banned(Int32(index), item.0, item.1))
        }
        entries.append(.banInfo)
        linkRows.stableIds = entries.map { $0.stableId }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Фильтры"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    shadowSettingsInstallLinkMenu(controller: controller, context: context, screen: "filters", rows: linkRows)
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
