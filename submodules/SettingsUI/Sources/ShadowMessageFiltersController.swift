import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private enum ShadowMessageFiltersEntry: ItemListNodeEntry {
    case input(String)
    case help
    case clear

    var section: ItemListSectionId {
        switch self {
        case .input, .help: return 0
        case .clear: return 1
        }
    }
    var stableId: Int32 {
        switch self { case .input: return 0; case .help: return 1; case .clear: return 2 }
    }
    static func < (lhs: ShadowMessageFiltersEntry, rhs: ShadowMessageFiltersEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowMessageFiltersArguments
        switch self {
        case let .input(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: ""), text: value, placeholder: "слово, фраза, ещё одно", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: arguments.update, action: {})
        case .help:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Укажите слова или фразы через запятую. Совпадения в тексте и подписях сворачиваются только на этом устройстве. Регистр не учитывается; сообщения не удаляются и прочтения не отправляются."), sectionId: self.section)
        case .clear:
            return ItemListActionItem(presentationData: presentationData, title: "Очистить фильтры", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.clear)
        }
    }
}

private final class ShadowMessageFiltersArguments {
    let update: (String) -> Void
    let clear: () -> Void
    init(update: @escaping (String) -> Void, clear: @escaping () -> Void) { self.update = update; self.clear = clear }
}

public func shadowMessageFiltersController(context: AccountContext) -> ViewController {
    let setText: (String) -> Void = { text in
        let phrases = text.split(separator: ",", omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let _ = updateAyuGramSettings(postbox: context.account.postbox) { current in
            var current = current
            current.messageFilterPhrases = phrases
            return current
        }.startStandalone()
    }
    let arguments = ShadowMessageFiltersArguments(update: setText, clear: { setText("") })
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [ShadowMessageFiltersEntry] = [.input(settings.messageFilterPhrases.joined(separator: ", ")), .help, .clear]
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Фильтры сообщений"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    return ItemListController(context: context, state: signal)
}
