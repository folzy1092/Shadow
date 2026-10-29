import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI

// Shadow 2.0.0: «Кастомизация → Чаты и звонки → Кнопки панели» (the formatting
// panel's buttons, ShadowInputToolbar, in the order they were checked) and
// «Шаблоны перевода» (up to ShadowInputTranslation.maxTemplates language pairs
// for «Перевод при отправке»).

// MARK: Кнопки панели

private final class ShadowInputToolbarButtonsArguments {
    let toggle: (ShadowInputToolbar.Button) -> Void
    let reset: () -> Void

    init(toggle: @escaping (ShadowInputToolbar.Button) -> Void, reset: @escaping () -> Void) {
        self.toggle = toggle
        self.reset = reset
    }
}

private enum ShadowInputToolbarButtonsSection: Int32 {
    case formatting
    case tools
    case reset
}

private enum ShadowInputToolbarButtonsEntry: ItemListNodeEntry {
    case formattingHeader
    case button(Int32, ShadowInputToolbar.Button, Int?)
    case formattingFooter
    case toolsHeader
    case tool(Int32, ShadowInputToolbar.Button, Int?)
    case toolsFooter
    case reset

    var section: ItemListSectionId {
        switch self {
        case .formattingHeader, .button, .formattingFooter:
            return ShadowInputToolbarButtonsSection.formatting.rawValue
        case .toolsHeader, .tool, .toolsFooter:
            return ShadowInputToolbarButtonsSection.tools.rawValue
        case .reset:
            return ShadowInputToolbarButtonsSection.reset.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .formattingHeader: return 0
        case let .button(index, _, _): return 100 + index
        case .formattingFooter: return 499
        case .toolsHeader: return 500
        case let .tool(index, _, _): return 600 + index
        case .toolsFooter: return 999
        case .reset: return 1000
        }
    }

    static func < (lhs: ShadowInputToolbarButtonsEntry, rhs: ShadowInputToolbarButtonsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    private static func title(_ text: String, position: Int?) -> String {
        if let position {
            return "\(position). \(text)"
        }
        return text
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowInputToolbarButtonsArguments
        switch self {
        case .formattingHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ФОРМАТИРОВАНИЕ", sectionId: self.section)
        case let .button(_, button, position), let .tool(_, button, position):
            return ItemListCheckboxItem(presentationData: presentationData, title: ShadowInputToolbarButtonsEntry.title(button.title, position: position), style: .left, checked: position != nil, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggle(button)
            })
        case .formattingFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Панель видна под полем ввода, пока открыта клавиатура. Если ничего не выделено, кнопка форматирует слово перед курсором. Цифра — место на панели, по порядку отметки."), sectionId: self.section)
        case .toolsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИНСТРУМЕНТЫ", sectionId: self.section)
        case .toolsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Перевод при отправке» включает перевод по шаблону и выключает его. «Упомянуть всех» вставляет участников группы в поле ввода. «К началу переписки» листает чат к первому сообщению."), sectionId: self.section)
        case .reset:
            return ItemListActionItem(presentationData: presentationData, title: "Как в Swiftgram", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.reset()
            })
        }
    }
}

public func shadowInputToolbarButtonsController(context: AccountContext) -> ViewController {
    let update: (@escaping (String) -> String) -> Void = { f in
        let _ = updateAyuGramSettings(postbox: context.account.postbox, { settings in
            var settings = settings
            settings.inputToolbarButtons = ShadowInputToolbar.normalizedButtons(f(settings.inputToolbarButtons))
            return settings
        }).startStandalone()
    }
    let arguments = ShadowInputToolbarButtonsArguments(toggle: { button in
        update { current in
            return ShadowInputToolbar.encodeButtons(ShadowInputToolbar.toggled(ShadowInputToolbar.parseButtons(current), button))
        }
    }, reset: {
        update { _ in ShadowInputToolbar.defaultButtons }
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let buttons = ShadowInputToolbar.parseButtons(settings.inputToolbarButtons)
        func position(_ button: ShadowInputToolbar.Button) -> Int? {
            return buttons.firstIndex(of: button).map { $0 + 1 }
        }
        var entries: [ShadowInputToolbarButtonsEntry] = [.formattingHeader]
        let formatting = ShadowInputToolbar.Button.allCases.filter { $0.tool == nil }
        for (index, button) in formatting.enumerated() {
            entries.append(.button(Int32(index), button, position(button)))
        }
        entries.append(.formattingFooter)
        entries.append(.toolsHeader)
        let tools = ShadowInputToolbar.Button.allCases.filter { $0.tool != nil }
        for (index, button) in tools.enumerated() {
            entries.append(.tool(Int32(index), button, position(button)))
        }
        entries.append(.toolsFooter)
        entries.append(.reset)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Кнопки панели"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false), arguments))
    }

    return ItemListController(context: context, state: signal)
}

// MARK: Шаблоны перевода

private final class ShadowTranslateTemplatesArguments {
    let add: () -> Void
    let remove: (ShadowInputTranslation.Template) -> Void

    init(add: @escaping () -> Void, remove: @escaping (ShadowInputTranslation.Template) -> Void) {
        self.add = add
        self.remove = remove
    }
}

private enum ShadowTranslateTemplatesEntry: ItemListNodeEntry {
    case header(Int)
    case template(Int32, ShadowInputTranslation.Template)
    case add
    case footer

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .template(index, _): return 100 + index
        case .add: return 500
        case .footer: return 501
        }
    }

    static func < (lhs: ShadowTranslateTemplatesEntry, rhs: ShadowTranslateTemplatesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowTranslateTemplatesArguments
        switch self {
        case let .header(count):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ШАБЛОНЫ · \(count) ИЗ \(ShadowInputTranslation.maxTemplates)", sectionId: self.section)
        case let .template(_, template):
            return ItemListDisclosureItem(presentationData: presentationData, title: template.title, label: template.shortTitle, labelStyle: .detailText, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.remove(template)
            })
        case .add:
            return ItemListActionItem(presentationData: presentationData, title: "Добавить шаблон", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Нажми на шаблон, чтобы удалить его. В чате кнопка «Перевод при отправке» (панель форматирования или скрепка) спрашивает шаблон и включает перевод во всех чатах: пишешь как обычно, а уходит перевод. Переводит телефон (iOS 18+), если не может — сервер Telegram. Снова нажать кнопку — выключить."), sectionId: self.section)
        }
    }
}

public func shadowInputTranslateTemplatesController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?

    func toast(_ text: String) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
    }

    func store(_ templates: [ShadowInputTranslation.Template]) {
        let _ = updateAyuGramSettings(postbox: context.account.postbox, { settings in
            var settings = settings
            settings.inputTranslateTemplates = ShadowInputTranslation.encodeTemplates(templates)
            return settings
        }).startStandalone()
    }

    // A compact sheet with every offered language.
    func pickLanguage(title: String, excluding: String?, completion: @escaping (String) -> Void) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: title, parseMarkdown: false)]
        for code in ShadowInputTranslation.languages where code != excluding {
            items.append(ActionSheetButtonItem(title: ShadowInputTranslation.languageName(code), action: { [weak sheet] in
                sheet?.dismissAnimated()
                completion(code)
            }))
        }
        sheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak sheet] in
            sheet?.dismissAnimated()
        })])])
        presentControllerImpl?(sheet)
    }

    let arguments = ShadowTranslateTemplatesArguments(add: {
        let current = ShadowInputTranslation.parseTemplates(currentAyuGramSettings(accountId: context.account.id).inputTranslateTemplates)
        guard current.count < ShadowInputTranslation.maxTemplates else {
            toast("Не больше \(ShadowInputTranslation.maxTemplates) шаблонов. Удали ненужный.")
            return
        }
        pickLanguage(title: "С какого языка", excluding: nil, completion: { from in
            Queue.mainQueue().after(0.35) {
                pickLanguage(title: "На какой язык", excluding: from, completion: { to in
                    let current = ShadowInputTranslation.parseTemplates(currentAyuGramSettings(accountId: context.account.id).inputTranslateTemplates)
                    switch ShadowInputTranslation.adding(current, from: from, to: to) {
                    case let .success(templates):
                        store(templates)
                    case .failure(.duplicate):
                        toast("Такой шаблон уже есть")
                    case .failure(.full):
                        toast("Не больше \(ShadowInputTranslation.maxTemplates) шаблонов")
                    case .failure(.sameLanguage):
                        toast("Языки должны быть разными")
                    }
                })
            }
        })
    }, remove: { template in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: "Удалить шаблон «\(template.title)»?", actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                let current = ShadowInputTranslation.parseTemplates(currentAyuGramSettings(accountId: context.account.id).inputTranslateTemplates)
                store(ShadowInputTranslation.removing(current, template))
                if ShadowInputTranslation.activeTemplate == template {
                    ShadowInputTranslation.activeTemplate = nil
                }
            })
        ]))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let templates = ShadowInputTranslation.parseTemplates(settings.inputTranslateTemplates)
        var entries: [ShadowTranslateTemplatesEntry] = [.header(templates.count)]
        for (index, template) in templates.enumerated() {
            entries.append(.template(Int32(index), template))
        }
        if templates.count < ShadowInputTranslation.maxTemplates {
            entries.append(.add)
        }
        entries.append(.footer)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Шаблоны перевода"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false), arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] value in
        controller?.present(value, in: .current)
    }
    return controller
}
