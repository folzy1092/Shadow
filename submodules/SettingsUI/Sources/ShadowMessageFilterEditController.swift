import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// Shadow: "Добавить фильтр" sheet, the same fields as AyuGram Desktop's
// dialog: expression, enabled, case-insensitive, reversed. Opened from the
// filters screen and from the chat ("В фильтры" on a text selection or an
// @username). Saves into the account settings by itself.

private struct ShadowMessageFilterEditState: Equatable {
    var expression: String
    var enabled: Bool
    var caseInsensitive: Bool
    var reversed: Bool

    var isValid: Bool {
        return ShadowMessageFilter.isValid(expression: self.expression)
    }
}

private final class ShadowMessageFilterEditArguments {
    let updateExpression: (String) -> Void
    let toggleEnabled: () -> Void
    let toggleCaseInsensitive: () -> Void
    let toggleReversed: () -> Void
    let delete: () -> Void

    init(updateExpression: @escaping (String) -> Void, toggleEnabled: @escaping () -> Void, toggleCaseInsensitive: @escaping () -> Void, toggleReversed: @escaping () -> Void, delete: @escaping () -> Void) {
        self.updateExpression = updateExpression
        self.toggleEnabled = toggleEnabled
        self.toggleCaseInsensitive = toggleCaseInsensitive
        self.toggleReversed = toggleReversed
        self.delete = delete
    }
}

private enum ShadowMessageFilterEditEntry: ItemListNodeEntry {
    case header
    case expression(String)
    case error
    case enabled(Bool)
    case caseInsensitive(Bool)
    case reversed(Bool)
    case help
    case delete

    var section: ItemListSectionId {
        switch self {
        case .header, .expression, .error:
            return 0
        case .enabled, .caseInsensitive, .reversed, .help:
            return 1
        case .delete:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .expression: return 1
        case .error: return 2
        case .enabled: return 3
        case .caseInsensitive: return 4
        case .reversed: return 5
        case .help: return 6
        case .delete: return 7
        }
    }

    static func < (lhs: ShadowMessageFilterEditEntry, rhs: ShadowMessageFilterEditEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowMessageFilterEditArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "Выражение".uppercased(), sectionId: self.section)
        case let .expression(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: ""), text: value, placeholder: "Выражение", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateExpression(value)
            }, action: {})
        case .error:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Неверное регулярное выражение"), sectionId: self.section)
        case let .enabled(value):
            return ItemListCheckboxItem(presentationData: presentationData, title: "Включить фильтр", style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleEnabled()
            })
        case let .caseInsensitive(value):
            return ItemListCheckboxItem(presentationData: presentationData, title: "Без учёта регистра", style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleCaseInsensitive()
            })
        case let .reversed(value):
            return ItemListCheckboxItem(presentationData: presentationData, title: "Обратный фильтр", style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleReversed()
            })
        case .help:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Регулярное выражение; обычный текст тоже работает. Спецсимволы . * ? + ( ) [ ] { } | ^ $ \\ экранируй обратной чертой — из чата они экранируются сами. Обратный фильтр скрывает всё, что НЕ совпадает."), sectionId: self.section)
        case .delete:
            return ItemListActionItem(presentationData: presentationData, title: "Удалить фильтр", kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.delete()
            })
        }
    }
}

public func shadowMessageFilterEditController(context: AccountContext, filter: ShadowMessageFilter?, initialExpression: String? = nil) -> ViewController {
    let initialState = ShadowMessageFilterEditState(
        expression: filter?.expression ?? initialExpression ?? "",
        enabled: filter?.enabled ?? true,
        caseInsensitive: filter?.caseInsensitive ?? true,
        reversed: filter?.reversed ?? false
    )
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((ShadowMessageFilterEditState) -> ShadowMessageFilterEditState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    var dismissImpl: (() -> Void)?

    let arguments = ShadowMessageFilterEditArguments(updateExpression: { value in
        updateState { state in
            var state = state
            state.expression = value
            return state
        }
    }, toggleEnabled: {
        updateState { state in
            var state = state
            state.enabled = !state.enabled
            return state
        }
    }, toggleCaseInsensitive: {
        updateState { state in
            var state = state
            state.caseInsensitive = !state.caseInsensitive
            return state
        }
    }, toggleReversed: {
        updateState { state in
            var state = state
            state.reversed = !state.reversed
            return state
        }
    }, delete: {
        guard let filter else {
            return
        }
        let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
            var current = current
            current.messageFilters.removeAll(where: { $0.id == filter.id })
            return current
        }.startStandalone()
        dismissImpl?()
    })

    let save: () -> Void = {
        let state = stateValue.with { $0 }
        guard state.isValid else {
            return
        }
        let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
            var current = current
            let id = filter?.id ?? ((current.messageFilters.map { $0.id }.max() ?? 0) + 1)
            let updated = ShadowMessageFilter(id: id, expression: state.expression, enabled: state.enabled, caseInsensitive: state.caseInsensitive, reversed: state.reversed)
            if let index = current.messageFilters.firstIndex(where: { $0.id == id }) {
                current.messageFilters[index] = updated
            } else {
                current.messageFilters.append(updated)
            }
            return current
        }.startStandalone()
        dismissImpl?()
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowMessageFilterEditEntry] = [.header, .expression(state.expression)]
        if !state.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !state.isValid {
            entries.append(.error)
        }
        entries += [.enabled(state.enabled), .caseInsensitive(state.caseInsensitive), .reversed(state.reversed), .help]
        if filter != nil {
            entries.append(.delete)
        }
        let leftButton = ItemListNavigationButton(content: .text("Отмена"), style: .regular, enabled: true, action: {
            dismissImpl?()
        })
        let rightButton = ItemListNavigationButton(content: .text("Сохранить"), style: .bold, enabled: state.isValid, action: {
            save()
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(filter == nil ? "Добавить фильтр" : "Изменить фильтр"), leftNavigationButton: leftButton, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    dismissImpl = { [weak controller] in
        controller?.view.endEditing(true)
        controller?.dismiss()
    }
    return controller
}
