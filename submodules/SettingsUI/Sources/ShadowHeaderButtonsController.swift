import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import AlertUI
import PresentationDataUtils
import PromptUI

// Shadow: Кастомизация → Кнопки шапки (AyuGramSettings.headerButtons,
// ShadowHeaderButtons.swift). Up to 2 buttons on the left and 3 on the right
// of the root chat list header; each one has a tap action and an optional
// long-press action. Rendering and the actions themselves live in
// ChatListController.swift (applyShadowHeaderButtons / shadowPerformHeaderAction).

private enum ShadowHeaderSide: Int32 {
    case left
    case right

    var title: String {
        switch self {
        case .left: return "Слева"
        case .right: return "Справа"
        }
    }

    var limit: Int {
        switch self {
        case .left: return ShadowHeaderButtons.maxLeft
        case .right: return ShadowHeaderButtons.maxRight
        }
    }

    var other: ShadowHeaderSide {
        switch self {
        case .left: return .right
        case .right: return .left
        }
    }

    func buttons(_ value: ShadowHeaderButtons) -> [ShadowHeaderButton] {
        switch self {
        case .left: return value.left
        case .right: return value.right
        }
    }

    func setButtons(_ buttons: [ShadowHeaderButton], in value: inout ShadowHeaderButtons) {
        switch self {
        case .left: value.left = buttons
        case .right: value.right = buttons
        }
    }
}

private enum ShadowHeaderButtonsSection: Int32 {
    case left
    case right
    case reset
}

private enum ShadowHeaderButtonsEntry: ItemListNodeEntry {
    case header(side: Int32, text: String)
    case button(side: Int32, index: Int, title: String, label: String)
    case add(side: Int32, enabled: Bool)
    case footer(side: Int32, text: String)
    case reset(enabled: Bool)
    case resetFooter

    var section: ItemListSectionId {
        switch self {
        case let .header(side, _), let .button(side, _, _, _), let .add(side, _), let .footer(side, _):
            return side == ShadowHeaderSide.left.rawValue ? ShadowHeaderButtonsSection.left.rawValue : ShadowHeaderButtonsSection.right.rawValue
        case .reset, .resetFooter:
            return ShadowHeaderButtonsSection.reset.rawValue
        }
    }

    // 0 is the search entry id (ShadowSettingsSearchIndex, destination .headerButtons).
    var stableId: Int32 {
        switch self {
        case let .header(side, _):
            return side == ShadowHeaderSide.left.rawValue ? 0 : 1000
        case let .button(side, index, _, _):
            return (side == ShadowHeaderSide.left.rawValue ? 0 : 1000) + 10 + Int32(index)
        case let .add(side, _):
            return (side == ShadowHeaderSide.left.rawValue ? 0 : 1000) + 100
        case let .footer(side, _):
            return (side == ShadowHeaderSide.left.rawValue ? 0 : 1000) + 101
        case .reset:
            return 2000
        case .resetFooter:
            return 2001
        }
    }

    static func <(lhs: ShadowHeaderButtonsEntry, rhs: ShadowHeaderButtonsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowHeaderButtonsArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .button(side, index, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.open(ShadowHeaderSide(rawValue: side) ?? .left, index)
            })
        case let .add(side, enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Добавить кнопку", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add(ShadowHeaderSide(rawValue: side) ?? .left)
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .reset(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Вернуть стандартные кнопки", kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.reset()
            })
        case .resetFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Стандартные: «Изм.» слева; история, Призрак (удержание — его настройки) и «Написать» справа. В режиме маскировки всегда показываются стандартные кнопки."), sectionId: self.section)
        }
    }
}

private final class ShadowHeaderButtonsArguments {
    let open: (ShadowHeaderSide, Int) -> Void
    let add: (ShadowHeaderSide) -> Void
    let reset: () -> Void

    init(open: @escaping (ShadowHeaderSide, Int) -> Void, add: @escaping (ShadowHeaderSide) -> Void, reset: @escaping () -> Void) {
        self.open = open
        self.add = add
        self.reset = reset
    }
}

private func shadowHeaderActionTitle(_ action: ShadowHeaderAction, link: String) -> String {
    if action == .customLink {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Своя ссылка (не задана)" : "Ссылка: \(trimmed)"
    }
    return action.title
}

private func shadowHeaderButtonsEntries(_ value: ShadowHeaderButtons) -> [ShadowHeaderButtonsEntry] {
    var entries: [ShadowHeaderButtonsEntry] = []
    for side in [ShadowHeaderSide.left, ShadowHeaderSide.right] {
        let buttons = side.buttons(value)
        entries.append(.header(side: side.rawValue, text: "\(side.title.uppercased()) (ДО \(side.limit))"))
        for (index, button) in buttons.enumerated() {
            let label = button.longPress == .none ? "" : "удерж.: \(shadowHeaderActionTitle(button.longPress, link: button.longPressLink))"
            entries.append(.button(side: side.rawValue, index: index, title: shadowHeaderActionTitle(button.tap, link: button.tapLink), label: label))
        }
        entries.append(.add(side: side.rawValue, enabled: buttons.count < side.limit))
        if side == .right {
            entries.append(.footer(side: side.rawValue, text: "Кнопки идут в том же порядке, что и в шапке: сверху — левая. Нажмите на кнопку, чтобы задать нажатие, удержание, иконку, порядок или удалить её. Пустая сторона — без кнопок."))
        }
    }
    entries.append(.reset(enabled: !value.isStock))
    entries.append(.resetFooter)
    return entries
}

func shadowHeaderButtonsController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var focusedIndex: Int?

    let currentButtons: () -> ShadowHeaderButtons = {
        return currentAyuGramSettings(accountId: context.account.id).headerButtons.normalized()
    }
    let updateButtons: (@escaping (ShadowHeaderButtons) -> ShadowHeaderButtons) -> Void = { f in
        let _ = updateAyuGramSettings(postbox: context.account.postbox, { current in
            var current = current
            current.headerButtons = f(current.headerButtons.normalized()).normalized()
            return current
        }).startStandalone()
    }
    let updateButton: (ShadowHeaderSide, Int, @escaping (inout ShadowHeaderButton) -> Void) -> Void = { side, index, f in
        updateButtons { value in
            var value = value
            var buttons = side.buttons(value)
            if index < buttons.count {
                f(&buttons[index])
            }
            side.setButtons(buttons, in: &value)
            return value
        }
    }

    // Asks for a custom link; nil when cancelled. Invalid input shows an alert.
    let askLink: (String, @escaping (String) -> Void) -> Void = { initial, completion in
        let controller = promptController(context: context, text: "Ссылка для кнопки", subtitle: "https://…, t.me/…, @username, tg://… или shadow://…", value: initial, placeholder: "t.me/username", characterLimit: 512, apply: { value in
            guard let value else {
                return
            }
            if ShadowHeaderButtons.normalizedLink(value) != nil {
                completion(value.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentControllerImpl?(textAlertController(context: context, title: nil, text: "Это не похоже на ссылку. Подходят https://, t.me/…, @username, tg:// и shadow://.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
            }
        })
        presentControllerImpl?(controller)
    }

    // Action picker. `allowNone`: offer "Ничего" (long press only).
    let pickAction: (String, ShadowHeaderAction, Bool, @escaping (ShadowHeaderAction) -> Void) -> Void = { title, current, allowNone, completion in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: title, parseMarkdown: false)]
        var actions: [ShadowHeaderAction] = []
        if allowNone {
            actions.append(.none)
        }
        actions.append(contentsOf: ShadowHeaderAction.selectable)
        for action in actions {
            let itemTitle = (action == current ? "✓ " : "") + action.title
            items.append(ActionSheetButtonItem(title: itemTitle, color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                completion(action)
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        presentControllerImpl?(actionSheet)
    }

    let pickIcon: (String, @escaping (String) -> Void) -> Void = { current, completion in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Иконка кнопки (SF Symbols)", parseMarkdown: false)]
        let effectiveCurrent = current.isEmpty ? "link" : current
        for icon in ShadowHeaderButtons.customLinkIcons {
            items.append(ActionSheetButtonItem(title: (icon == effectiveCurrent ? "✓ " : "") + icon, color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                completion(icon)
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        presentControllerImpl?(actionSheet)
    }

    let setTap: (ShadowHeaderSide, Int, ShadowHeaderAction) -> Void = { side, index, action in
        if action == .customLink {
            let buttons = side.buttons(currentButtons())
            let initial = index < buttons.count ? buttons[index].tapLink : ""
            askLink(initial, { link in
                updateButton(side, index, { button in
                    button.tap = .customLink
                    button.tapLink = link
                })
            })
        } else {
            updateButton(side, index, { button in
                button.tap = action
                button.tapLink = ""
            })
        }
    }

    let setLongPress: (ShadowHeaderSide, Int, ShadowHeaderAction) -> Void = { side, index, action in
        if action == .customLink {
            let buttons = side.buttons(currentButtons())
            let initial = index < buttons.count ? buttons[index].longPressLink : ""
            askLink(initial, { link in
                updateButton(side, index, { button in
                    button.longPress = .customLink
                    button.longPressLink = link
                })
            })
        } else {
            updateButton(side, index, { button in
                button.longPress = action
                button.longPressLink = ""
            })
        }
    }

    let arguments = ShadowHeaderButtonsArguments(open: { side, index in
        let value = currentButtons()
        let buttons = side.buttons(value)
        guard index < buttons.count else {
            return
        }
        let button = buttons[index]
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        items.append(ActionSheetButtonItem(title: "Нажатие: \(shadowHeaderActionTitle(button.tap, link: button.tapLink))", color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            pickAction("Что делает нажатие", button.tap, false, { action in
                setTap(side, index, action)
            })
        }))
        items.append(ActionSheetButtonItem(title: "Удержание: \(shadowHeaderActionTitle(button.longPress, link: button.longPressLink))", color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            pickAction("Что делает удержание", button.longPress, true, { action in
                setLongPress(side, index, action)
            })
        }))
        if button.tap == .customLink {
            items.append(ActionSheetButtonItem(title: "Иконка: \(button.icon.isEmpty ? "link" : button.icon)", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                pickIcon(button.icon, { icon in
                    updateButton(side, index, { button in
                        button.icon = icon
                    })
                })
            }))
        }
        if index > 0 {
            items.append(ActionSheetButtonItem(title: "Сдвинуть левее", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                updateButtons { value in
                    var value = value
                    var buttons = side.buttons(value)
                    if index < buttons.count {
                        buttons.swapAt(index, index - 1)
                    }
                    side.setButtons(buttons, in: &value)
                    return value
                }
            }))
        }
        if index + 1 < buttons.count {
            items.append(ActionSheetButtonItem(title: "Сдвинуть правее", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                updateButtons { value in
                    var value = value
                    var buttons = side.buttons(value)
                    if index + 1 < buttons.count {
                        buttons.swapAt(index, index + 1)
                    }
                    side.setButtons(buttons, in: &value)
                    return value
                }
            }))
        }
        if side.other.buttons(value).count < side.other.limit {
            items.append(ActionSheetButtonItem(title: side == .left ? "Перенести направо" : "Перенести налево", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                updateButtons { value in
                    var value = value
                    var buttons = side.buttons(value)
                    var otherButtons = side.other.buttons(value)
                    if index < buttons.count, otherButtons.count < side.other.limit {
                        let moved = buttons.remove(at: index)
                        // Moving left→right lands next to the left edge of the
                        // right group, right→left next to the right edge.
                        if side == .left {
                            otherButtons.insert(moved, at: 0)
                        } else {
                            otherButtons.append(moved)
                        }
                    }
                    side.setButtons(buttons, in: &value)
                    side.other.setButtons(otherButtons, in: &value)
                    return value
                }
            }))
        }
        items.append(ActionSheetButtonItem(title: "Удалить кнопку", color: .destructive, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            updateButtons { value in
                var value = value
                var buttons = side.buttons(value)
                if index < buttons.count {
                    buttons.remove(at: index)
                }
                side.setButtons(buttons, in: &value)
                return value
            }
        }))
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        presentControllerImpl?(actionSheet)
    }, add: { side in
        guard side.buttons(currentButtons()).count < side.limit else {
            return
        }
        pickAction("Новая кнопка: что делает нажатие", .none, false, { action in
            let append: (ShadowHeaderButton) -> Void = { button in
                updateButtons { value in
                    var value = value
                    var buttons = side.buttons(value)
                    if buttons.count < side.limit {
                        buttons.append(button)
                    }
                    side.setButtons(buttons, in: &value)
                    return value
                }
            }
            if action == .customLink {
                askLink("", { link in
                    append(ShadowHeaderButton(tap: .customLink, tapLink: link))
                })
            } else {
                append(ShadowHeaderButton(tap: action, longPress: action == .ghostMode ? .ghostSettings : .none))
            }
        })
    }, reset: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: "Вернуть стандартные кнопки шапки?", actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: "Вернуть", action: {
                updateButtons { _ in
                    return .stock
                }
            })
        ]))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = shadowHeaderButtonsEntries(settings.headerButtons.normalized())
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Кнопки шапки"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: context.sharedContext.currentPresentationData.with { $0 }.theme.list.itemAccentColor)
    }
    return controller
}
