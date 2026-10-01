import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import PromptUI

// Shadow: local quick reply templates (AyuGramSettings.quickReplyTemplates).
// The chat input shows a templates button while the field is empty; picking a
// template inserts its text into the composer.

private enum ShadowQuickRepliesSection: Int32 {
    case add
    case templates
}

private enum ShadowQuickRepliesEntry: ItemListNodeEntry {
    case add(enabled: Bool)
    case addFooter
    case template(index: Int, text: String)
    case templatesFooter

    var section: ItemListSectionId {
        switch self {
        case .add, .addFooter:
            return ShadowQuickRepliesSection.add.rawValue
        case .template, .templatesFooter:
            return ShadowQuickRepliesSection.templates.rawValue
        }
    }

    // 0 is the search entry id (ShadowSettingsSearchIndex, destination .quickReplies).
    var stableId: Int32 {
        switch self {
        case .add: return 0
        case .addFooter: return 1
        case let .template(index, _): return 100 + Int32(index)
        case .templatesFooter: return 10_000
        }
    }

    static func <(lhs: ShadowQuickRepliesEntry, rhs: ShadowQuickRepliesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowQuickRepliesArguments
        switch self {
        case let .add(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Добавить шаблон", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.add)
        case .addFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Кнопка шаблонов появляется в поле ввода, когда оно пустое. Выбранный шаблон вставляется в поле — отправляете вы сами. До \(AyuGramSettings.quickReplyTemplatesLimit) шаблонов."), sectionId: self.section)
        case let .template(index, text):
            return ItemListDisclosureItem(presentationData: presentationData, title: shadowQuickReplyListTitle(text), label: "", sectionId: self.section, style: .blocks, action: {
                arguments.open(index)
            })
        case .templatesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Нажмите на шаблон, чтобы изменить или удалить его. Шаблоны хранятся только на этом устройстве и не входят в экспорт настроек."), sectionId: self.section)
        }
    }
}

private func shadowQuickReplyListTitle(_ text: String) -> String {
    let singleLine = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    if singleLine.count <= 60 {
        return singleLine
    }
    return String(singleLine.prefix(59)) + "…"
}

private final class ShadowQuickRepliesArguments {
    let add: () -> Void
    let open: (Int) -> Void

    init(add: @escaping () -> Void, open: @escaping (Int) -> Void) {
        self.add = add
        self.open = open
    }
}

// Normalizes the stored list: trims, drops empty entries and enforces limits.
func shadowNormalizedQuickReplyTemplates(_ templates: [String]) -> [String] {
    var result: [String] = []
    for template in templates {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            continue
        }
        result.append(String(trimmed.prefix(AyuGramSettings.quickReplyTemplateMaxLength)))
        if result.count == AyuGramSettings.quickReplyTemplatesLimit {
            break
        }
    }
    return result
}

func shadowQuickRepliesController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var focusedIndex: Int?

    let updateTemplates: (@escaping ([String]) -> [String]) -> Void = { f in
        let _ = updateAyuGramSettings(postbox: context.account.postbox, { current in
            var current = current
            current.quickReplyTemplates = shadowNormalizedQuickReplyTemplates(f(current.quickReplyTemplates))
            return current
        }).startStandalone()
    }

    let edit: (Int?) -> Void = { index in
        let templates = currentAyuGramSettings(accountId: context.account.id).quickReplyTemplates
        var initialValue: String?
        if let index, index < templates.count {
            initialValue = templates[index]
        }
        let controller = promptController(context: context, text: index == nil ? "Новый шаблон" : "Изменить шаблон", value: initialValue, placeholder: "Текст шаблона", characterLimit: AyuGramSettings.quickReplyTemplateMaxLength, apply: { value in
            guard let value else {
                return
            }
            updateTemplates { current in
                var current = current
                if let index, index < current.count {
                    current[index] = value
                } else {
                    current.append(value)
                }
                return current
            }
        })
        presentControllerImpl?(controller)
    }

    let arguments = ShadowQuickRepliesArguments(add: {
        edit(nil)
    }, open: { index in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: "Изменить", color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    edit(index)
                }),
                ActionSheetButtonItem(title: "Удалить", color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    updateTemplates { current in
                        var current = current
                        if index < current.count {
                            current.remove(at: index)
                        }
                        return current
                    }
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        presentControllerImpl?(actionSheet)
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowQuickRepliesEntry] = [
            .add(enabled: settings.quickReplyTemplates.count < AyuGramSettings.quickReplyTemplatesLimit),
            .addFooter
        ]
        for (index, text) in settings.quickReplyTemplates.enumerated() {
            entries.append(.template(index: index, text: text))
        }
        if !settings.quickReplyTemplates.isEmpty {
            entries.append(.templatesFooter)
        }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Шаблоны ответов"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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
