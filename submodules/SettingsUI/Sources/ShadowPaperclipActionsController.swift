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

// Shadow: «Кастомизация → Чаты и звонки → Действия скрепки». Up to
// ShadowPaperclip.maxActions checkboxes: what the paperclip menu offers in a
// chat, in the order they were checked. Pranks come from the admin catalog
// (ShadowDeviceAccess paperclip_pranks), refreshed when the screen opens.

private final class ShadowPaperclipActionsArguments {
    let toggle: (ShadowPaperclip.Action) -> Void

    init(toggle: @escaping (ShadowPaperclip.Action) -> Void) {
        self.toggle = toggle
    }
}

private enum ShadowPaperclipActionsSection: Int32 {
    case imitation
    case pranks
}

private enum ShadowPaperclipActionsEntry: ItemListNodeEntry {
    case imitationHeader(Int)
    case imitation(Int32, ShadowActivityImitationMode, Int?)
    case imitationFooter
    case pranksHeader
    case prank(Int32, ShadowPaperclip.Prank, Int?)
    case pranksEmpty
    case pranksFooter

    var section: ItemListSectionId {
        switch self {
        case .imitationHeader, .imitation, .imitationFooter:
            return ShadowPaperclipActionsSection.imitation.rawValue
        case .pranksHeader, .prank, .pranksEmpty, .pranksFooter:
            return ShadowPaperclipActionsSection.pranks.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .imitationHeader: return 0
        case let .imitation(index, _, _): return 100 + index
        case .imitationFooter: return 999
        case .pranksHeader: return 1000
        case let .prank(index, _, _): return 1100 + index
        case .pranksEmpty: return 1998
        case .pranksFooter: return 1999
        }
    }

    static func < (lhs: ShadowPaperclipActionsEntry, rhs: ShadowPaperclipActionsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    // "3." in front of a checked action: its place in the menu.
    private static func title(_ text: String, position: Int?) -> String {
        if let position {
            return "\(position). \(text)"
        }
        return text
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowPaperclipActionsArguments
        switch self {
        case let .imitationHeader(count):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИМИТАЦИЯ · ВЫБРАНО \(count) ИЗ \(ShadowPaperclip.maxActions)", sectionId: self.section)
        case let .imitation(_, mode, position):
            return ItemListCheckboxItem(presentationData: presentationData, title: ShadowPaperclipActionsEntry.title(mode.title, position: position), style: .left, checked: position != nil, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggle(.imitation(mode))
            })
        case .imitationFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Собеседник видит выбранное в шапке чата, пока не остановишь в том же меню скрепки. «Записывает кружок» и «Отправляет кружок» — разные действия, как и голосовое и видео. «Случайно» меняет действие каждые несколько секунд. В секретном чате работает только «Печатает». Цифра — место в меню."), sectionId: self.section)
        case .pranksHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ПРИКОЛЫ", sectionId: self.section)
        case let .prank(_, prank, position):
            return ItemListCheckboxItem(presentationData: presentationData, title: ShadowPaperclipActionsEntry.title(prank.title, position: position), style: .left, checked: position != nil, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggle(.prank(id: prank.id))
            })
        case .pranksEmpty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Приколов пока нет."), sectionId: self.section)
        case .pranksFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Прикол уходит в чат без автора, как будто его отправил ты. С «Приколы: имитировать запись» перед голосовым или кружком собеседник сначала видит «записывает…» столько секунд, сколько задано."), sectionId: self.section)
        }
    }
}

public func shadowPaperclipActionsController(context: AccountContext) -> ViewController {
    let pranksPromise = ValuePromise<[ShadowPaperclip.Prank]>(ShadowDeviceAccess.cachedWhitelist?.paperclipPranks ?? [], ignoreRepeated: true)
    ShadowDeviceAccess.refresh { whitelist in
        if let whitelist {
            pranksPromise.set(whitelist.paperclipPranks)
        }
    }

    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = ShadowPaperclipActionsArguments(toggle: { action in
        let current = ShadowPaperclip.parseActions(currentAyuGramSettings(accountId: context.account.id).paperclipActions)
        guard let updated = ShadowPaperclip.toggled(current, action) else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Не больше \(ShadowPaperclip.maxActions) действий. Сними галочку с ненужного.", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
            return
        }
        let _ = updateAyuGramSettings(postbox: context.account.postbox, { settings in
            var settings = settings
            settings.paperclipActions = ShadowPaperclip.encodeActions(updated)
            return settings
        }).startStandalone()
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox), pranksPromise.get())
    |> map { presentationData, settings, pranks -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let actions = ShadowPaperclip.parseActions(settings.paperclipActions)
        func position(_ action: ShadowPaperclip.Action) -> Int? {
            return actions.firstIndex(of: action).map { $0 + 1 }
        }
        var entries: [ShadowPaperclipActionsEntry] = [.imitationHeader(actions.count)]
        for (index, mode) in ShadowActivityImitationMode.menuOrder.enumerated() {
            entries.append(.imitation(Int32(index), mode, position(.imitation(mode))))
        }
        entries.append(.imitationFooter)
        entries.append(.pranksHeader)
        if pranks.isEmpty {
            entries.append(.pranksEmpty)
        }
        for (index, prank) in pranks.enumerated() {
            entries.append(.prank(Int32(index), prank, position(.prank(id: prank.id))))
        }
        entries.append(.pranksFooter)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Действия скрепки"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false), arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] value in
        controller?.present(value, in: .current)
    }
    return controller
}
