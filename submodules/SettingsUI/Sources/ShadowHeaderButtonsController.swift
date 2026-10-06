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

private struct ShadowSheetEntry {
    let title: String
    let color: ActionSheetButtonColor
    let action: () -> Void
}

private func shadowHeaderModeTitle(_ mode: ShadowSettingLinks.Mode) -> String {
    switch mode {
    case .toggle: return "переключать"
    case .on: return "включать"
    case .off: return "выключать"
    case .open: return "открыть"
    case let .value(value): return "ставить \(value)"
    }
}

// The profile link of a header button, with the person's name for the list.
private func shadowHeaderProfileLink(_ target: ShadowProfileTarget, name: String) -> String {
    guard target != .me, let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics), !encoded.isEmpty else {
        return target.link
    }
    return target.link + "&name=" + encoded
}

func shadowHeaderStepTitle(_ step: ShadowHeaderStep) -> String {
    switch step.action {
    case .openProfile:
        guard let link = ShadowLinks.parse(step.link), let target = ShadowProfileTarget(link: link) else {
            return "Профиль (не выбран)"
        }
        switch target {
        case .me:
            return "Мой профиль"
        case let .username(name):
            return "Профиль @\(name)"
        case let .id(value):
            if let name = link.query["name"], !name.isEmpty {
                return "Профиль: \(name)"
            }
            return "Профиль (ID \(value))"
        }
    case .customLink, .setting:
        if let (setting, mode) = ShadowSettingLinks.resolve(step.link) {
            if case let .value(value) = mode, let choice = setting.choiceTitle(value) {
                return "\(setting.title): \(choice)"
            }
            return "\(setting.title) (\(shadowHeaderModeTitle(mode)))"
        }
        let trimmed = step.link.trimmingCharacters(in: .whitespacesAndNewlines)
        if step.action == .setting {
            return "Тумблер (не задан)"
        }
        return trimmed.isEmpty ? "Своя ссылка (не задана)" : "Ссылка: \(trimmed)"
    default:
        return step.action.title
    }
}

private func shadowHeaderStepsTitle(_ steps: [ShadowHeaderStep]) -> String {
    if steps.isEmpty {
        return "Ничего"
    }
    return steps.map { shadowHeaderStepTitle($0) }.joined(separator: " + ")
}

private func shadowHeaderButtonsEntries(_ value: ShadowHeaderButtons) -> [ShadowHeaderButtonsEntry] {
    var entries: [ShadowHeaderButtonsEntry] = []
    for side in [ShadowHeaderSide.left, ShadowHeaderSide.right] {
        let buttons = side.buttons(value)
        entries.append(.header(side: side.rawValue, text: "\(side.title.uppercased()) (ДО \(side.limit))"))
        for (index, button) in buttons.enumerated() {
            let label = button.longPressSteps.isEmpty ? "" : "удерж.: \(shadowHeaderStepsTitle(button.longPressSteps))"
            entries.append(.button(side: side.rawValue, index: index, title: shadowHeaderStepsTitle(button.tapSteps), label: label))
        }
        entries.append(.add(side: side.rawValue, enabled: buttons.count < side.limit))
        if side == .right {
            entries.append(.footer(side: side.rawValue, text: "Кнопки идут в том же порядке, что и в шапке: сверху — левая. На одно нажатие или удержание можно поставить до \(ShadowHeaderButton.maxSteps) действий; тумблеры в одной кнопке переключаются вместе: если все включены — выключаются, иначе включаются все."))
        }
    }
    entries.append(.reset(enabled: !value.isStock))
    entries.append(.resetFooter)
    return entries
}

func shadowHeaderButtonsController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
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

    // Every sheet button closes its sheet before running its action.
    let presentSheet: (String?, [ShadowSheetEntry]) -> Void = { title, buttons in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        if let title {
            items.append(ActionSheetTextItem(title: title, parseMarkdown: false))
        }
        for entry in buttons {
            items.append(ActionSheetButtonItem(title: entry.title, color: entry.color, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                entry.action()
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
    let sheetButton: (String, ActionSheetButtonColor, @escaping () -> Void) -> ShadowSheetEntry = { title, color, action in
        return ShadowSheetEntry(title: title, color: color, action: action)
    }

    // Asks for a custom link. Invalid input shows an alert.
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

    // Toggle picker: screen → toggle → mode.
    let pickSetting: (@escaping (ShadowHeaderStep) -> Void) -> Void = { completion in
        var screens: [ShadowSheetEntry] = []
        for screen in ShadowSettingLinks.screenOrder {
            let toggles = ShadowSettingLinks.all.filter { $0.screen == screen && ($0.isSwitchable || $0.isChoice) }
            if toggles.isEmpty {
                continue
            }
            screens.append(ShadowSheetEntry(title: ShadowSettingLinks.screenTitles[screen] ?? screen, color: .accent, action: {
                var items: [ShadowSheetEntry] = []
                for setting in toggles {
                    items.append(ShadowSheetEntry(title: setting.title, color: .accent, action: {
                        if setting.isChoice {
                            presentSheet("«\(setting.title)»: что ставить при нажатии", setting.choices.enumerated().map { index, choice in
                                ShadowSheetEntry(title: choice, color: .accent, action: { completion(ShadowHeaderStep(.setting, link: setting.link(.value(Int32(index))))) })
                            })
                            return
                        }
                        presentSheet("«\(setting.title)»: что делать при нажатии", [
                            ShadowSheetEntry(title: "Переключать (вкл ↔ выкл)", color: .accent, action: { completion(ShadowHeaderStep(.setting, link: setting.link(.toggle))) }),
                            ShadowSheetEntry(title: "Только включать", color: .accent, action: { completion(ShadowHeaderStep(.setting, link: setting.link(.on))) }),
                            ShadowSheetEntry(title: "Только выключать", color: .accent, action: { completion(ShadowHeaderStep(.setting, link: setting.link(.off))) })
                        ])
                    }))
                }
                presentSheet(ShadowSettingLinks.screenTitles[screen], items)
            }))
        }
        presentSheet("Какая настройка", screens)
    }

    // Whose profile: yourself, someone from the chats, or @username / id.
    let pickProfile: (@escaping (ShadowHeaderStep) -> Void) -> Void = { completion in
        presentSheet("Чей профиль открывать", [
            ShadowSheetEntry(title: "Мой профиль", color: .accent, action: {
                completion(ShadowHeaderStep(.openProfile, link: ShadowProfileTarget.me.link))
            }),
            ShadowSheetEntry(title: "Выбрать из чатов…", color: .accent, action: {
                let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyPrivateChats, .excludeSecretChats], hasContactSelector: false, title: "Чей профиль"))
                picker.peerSelected = { [weak picker] peer, _ in
                    picker?.dismiss()
                    let target: ShadowProfileTarget
                    if peer.id == context.account.peerId {
                        target = .me
                    } else {
                        target = .id(peer.id.id._internalGetInt64Value())
                    }
                    completion(ShadowHeaderStep(.openProfile, link: shadowHeaderProfileLink(target, name: peer.compactDisplayTitle)))
                }
                pushControllerImpl?(picker)
            }),
            ShadowSheetEntry(title: "Ввести @username или ID…", color: .accent, action: {
                let controller = promptController(context: context, text: "Чей профиль", subtitle: "@username, t.me/username или числовой ID. По ID открывается только тот, кого этот аккаунт уже видел.", value: "", placeholder: "@username", characterLimit: 64, apply: { value in
                    guard let value else {
                        return
                    }
                    if let target = ShadowProfileTarget(input: value) {
                        completion(ShadowHeaderStep(.openProfile, link: target.link))
                    } else {
                        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                        presentControllerImpl?(textAlertController(context: context, title: nil, text: "Нужен @username (от 4 символов) или числовой ID.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
                    }
                })
                presentControllerImpl?(controller)
            })
        ])
    }

    // One action: the action list, then a link or a toggle when needed.
    let pickStep: (String, @escaping (ShadowHeaderStep) -> Void) -> Void = { title, completion in
        var items: [ShadowSheetEntry] = []
        for action in ShadowHeaderAction.selectable {
            items.append(ShadowSheetEntry(title: action.title, color: .accent, action: {
                switch action {
                case .customLink:
                    askLink("", { link in
                        completion(ShadowHeaderStep(.customLink, link: link))
                    })
                case .setting:
                    pickSetting(completion)
                case .openProfile:
                    pickProfile(completion)
                default:
                    completion(ShadowHeaderStep(action))
                }
            }))
        }
        presentSheet(title, items)
    }

    let pickIcon: (String, @escaping (String) -> Void) -> Void = { current, completion in
        var items: [ShadowSheetEntry] = []
        for icon in [""] + ShadowHeaderButtons.iconPresets {
            items.append(ShadowSheetEntry(title: (icon == current ? "✓ " : "") + ShadowHeaderButtons.iconTitle(icon), color: .accent, action: {
                completion(icon)
            }))
        }
        presentSheet("Иконка кнопки", items)
    }

    // Editor of one gesture's steps.
    let editSteps: (ShadowHeaderSide, Int, Bool) -> Void = { side, index, isLongPress in
        let buttons = side.buttons(currentButtons())
        guard index < buttons.count else {
            return
        }
        let steps = isLongPress ? buttons[index].longPressSteps : buttons[index].tapSteps
        let setSteps: ([ShadowHeaderStep]) -> Void = { newSteps in
            updateButton(side, index, { button in
                if isLongPress {
                    button.longPressSteps = newSteps
                } else if !newSteps.isEmpty {
                    button.tapSteps = newSteps
                }
            })
        }
        var items: [ShadowSheetEntry] = []
        items.append(sheetButton(steps.isEmpty ? "Выбрать действие…" : "Заменить всё одним действием…", .accent, {
            pickStep(isLongPress ? "Что делает удержание" : "Что делает нажатие", { step in
                setSteps([step])
            })
        }))
        if !steps.isEmpty && steps.count < ShadowHeaderButton.maxSteps {
            items.append(sheetButton("Добавить действие…", .accent, {
                pickStep("Ещё одно действие", { step in
                    setSteps(steps + [step])
                })
            }))
        }
        if steps.count > 1 || (isLongPress && !steps.isEmpty) {
            for (stepIndex, step) in steps.enumerated() {
                items.append(sheetButton("Убрать: \(shadowHeaderStepTitle(step))", .destructive, {
                    var newSteps = steps
                    newSteps.remove(at: stepIndex)
                    setSteps(newSteps)
                }))
            }
        }
        presentSheet((isLongPress ? "Удержание: " : "Нажатие: ") + shadowHeaderStepsTitle(steps), items)
    }

    let arguments = ShadowHeaderButtonsArguments(open: { side, index in
        let value = currentButtons()
        let buttons = side.buttons(value)
        guard index < buttons.count else {
            return
        }
        let button = buttons[index]
        var items: [ShadowSheetEntry] = []
        items.append(sheetButton("Нажатие: \(shadowHeaderStepsTitle(button.tapSteps))", .accent, {
            editSteps(side, index, false)
        }))
        items.append(sheetButton("Удержание: \(shadowHeaderStepsTitle(button.longPressSteps))", .accent, {
            editSteps(side, index, true)
        }))
        items.append(sheetButton("Иконка: \(ShadowHeaderButtons.iconTitle(button.icon))", .accent, {
            pickIcon(button.icon, { icon in
                updateButton(side, index, { button in
                    button.icon = icon
                })
            })
        }))
        if index > 0 {
            items.append(sheetButton("Сдвинуть левее", .accent, {
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
            items.append(sheetButton("Сдвинуть правее", .accent, {
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
            items.append(sheetButton(side == .left ? "Перенести направо" : "Перенести налево", .accent, {
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
        items.append(sheetButton("Удалить кнопку", .destructive, {
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
        presentSheet(nil, items)
    }, add: { side in
        guard side.buttons(currentButtons()).count < side.limit else {
            return
        }
        pickStep("Новая кнопка: что делает нажатие", { step in
            let longPress: [ShadowHeaderStep] = step.action == .ghostMode ? [ShadowHeaderStep(.ghostSettings)] : []
            updateButtons { value in
                var value = value
                var buttons = side.buttons(value)
                if buttons.count < side.limit {
                    buttons.append(ShadowHeaderButton(tapSteps: [step], longPressSteps: longPress))
                }
                side.setButtons(buttons, in: &value)
                return value
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
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    return controller
}
