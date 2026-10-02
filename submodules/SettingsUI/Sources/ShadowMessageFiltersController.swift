import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadow: message filters screen, modelled on AyuGram Desktop — a list of
// regex filters, each edited in its own sheet (ShadowMessageFilterEditController).

private enum ShadowMessageFiltersEntry: ItemListNodeEntry {
    case showPlaceholder(Bool)
    case placeholderInfo
    case add
    case filter(Int32, ShadowMessageFilter)
    case empty
    case help

    var section: ItemListSectionId {
        switch self {
        case .showPlaceholder, .placeholderInfo:
            return 0
        case .add, .filter, .empty:
            return 1
        case .help:
            return 2
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
            return ItemListTextItem(presentationData: presentationData, text: .plain("Выключено — совпавшие сообщения пропадают из чата полностью, без плашки."), sectionId: self.section)
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
        }
    }
}

private final class ShadowMessageFiltersArguments {
    let setShowPlaceholder: (Bool) -> Void
    let add: () -> Void
    let edit: (ShadowMessageFilter) -> Void

    init(setShowPlaceholder: @escaping (Bool) -> Void, add: @escaping () -> Void, edit: @escaping (ShadowMessageFilter) -> Void) {
        self.setShowPlaceholder = setShowPlaceholder
        self.add = add
        self.edit = edit
    }
}

public func shadowMessageFiltersController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

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
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowMessageFiltersEntry] = [.showPlaceholder(settings.messageFilterShowPlaceholder), .placeholderInfo, .add]
        for (index, filter) in settings.messageFilters.enumerated() {
            entries.append(.filter(Int32(index), filter))
        }
        if settings.messageFilters.isEmpty {
            entries.append(.empty)
        }
        entries.append(.help)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Фильтры"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
