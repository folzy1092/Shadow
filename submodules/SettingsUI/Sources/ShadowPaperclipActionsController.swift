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
import PromptUI

// Shadow: «Кастомизация → Чаты и звонки → Действия скрепки». Up to
// ShadowPaperclip.maxActions checkboxes: what the paperclip menu offers in a
// chat, in the order they were checked. Pranks come from the admin catalog
// (ShadowDeviceAccess paperclip_pranks), refreshed when the screen opens, and
// from «Мои приколы» (1.14.0): posts of public channels the user adds by link,
// kept on this device (ShadowPaperclipUserPrankStore).

private final class ShadowPaperclipActionsArguments {
    let toggle: (ShadowPaperclip.Action) -> Void
    let addUserPrank: () -> Void
    let removeUserPrank: () -> Void

    init(toggle: @escaping (ShadowPaperclip.Action) -> Void, addUserPrank: @escaping () -> Void, removeUserPrank: @escaping () -> Void) {
        self.toggle = toggle
        self.addUserPrank = addUserPrank
        self.removeUserPrank = removeUserPrank
    }
}

private enum ShadowPaperclipActionsSection: Int32 {
    case imitation
    case userPranks
    case pranks
}

private enum ShadowPaperclipActionsEntry: ItemListNodeEntry {
    case imitationHeader(Int)
    case imitation(Int32, ShadowActivityImitationMode, Int?)
    case imitationFooter
    case userPranksHeader
    case userPrank(Int32, ShadowPaperclip.Prank, Int?)
    case userPrankAdd
    case userPrankRemove
    case userPranksFooter
    case pranksHeader
    case prank(Int32, ShadowPaperclip.Prank, Int?)
    case pranksEmpty
    case pranksFooter

    var section: ItemListSectionId {
        switch self {
        case .imitationHeader, .imitation, .imitationFooter:
            return ShadowPaperclipActionsSection.imitation.rawValue
        case .userPranksHeader, .userPrank, .userPrankAdd, .userPrankRemove, .userPranksFooter:
            return ShadowPaperclipActionsSection.userPranks.rawValue
        case .pranksHeader, .prank, .pranksEmpty, .pranksFooter:
            return ShadowPaperclipActionsSection.pranks.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .imitationHeader: return 0
        case let .imitation(index, _, _): return 100 + index
        case .imitationFooter: return 499
        case .userPranksHeader: return 500
        case let .userPrank(index, _, _): return 600 + index
        case .userPrankAdd: return 700
        case .userPrankRemove: return 701
        case .userPranksFooter: return 702
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
        case .userPranksHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "МОИ ПРИКОЛЫ", sectionId: self.section)
        case let .userPrank(_, prank, position):
            return ItemListCheckboxItem(presentationData: presentationData, title: ShadowPaperclipActionsEntry.title(prank.title, position: position), style: .left, checked: position != nil, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggle(.prank(id: prank.id))
            })
        case .userPrankAdd:
            return ItemListActionItem(presentationData: presentationData, title: "Добавить прикол по ссылке", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addUserPrank()
            })
        case .userPrankRemove:
            return ItemListActionItem(presentationData: presentationData, title: "Удалить свой прикол", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.removeUserPrank()
            })
        case .userPranksFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Свой прикол — пост публичного канала: выложи туда голосовое, кружок или что угодно и вставь ссылку на пост (t.me/канал/123). Приколы хранятся на этом телефоне и видны только тебе. Канал должен оставаться публичным, а пост — без запрета пересылки."), sectionId: self.section)
        case .pranksHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ПРИКОЛЫ SHADOW", sectionId: self.section)
        case let .prank(_, prank, position):
            return ItemListCheckboxItem(presentationData: presentationData, title: ShadowPaperclipActionsEntry.title(prank.title, position: position), style: .left, checked: position != nil, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggle(.prank(id: prank.id))
            })
        case .pranksEmpty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Приколов пока нет."), sectionId: self.section)
        case .pranksFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Прикол уходит в чат без автора, как будто его отправил ты; если в чате выбран ответ на сообщение, прикол уходит ответом на него. С «Приколы: имитировать запись» перед голосовым или кружком собеседник сначала видит «записывает…», затем «отправляет…» — столько секунд, сколько задано."), sectionId: self.section)
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

    let userPranksPromise = ValuePromise<[ShadowPaperclip.Prank]>(ShadowPaperclipUserPrankStore.pranks, ignoreRepeated: true)

    var presentControllerImpl: ((ViewController) -> Void)?

    func toast(_ text: String) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
    }

    // A new prank goes into the menu right away when there is room.
    func checkAdded(_ prank: ShadowPaperclip.Prank) {
        let current = ShadowPaperclip.parseActions(currentAyuGramSettings(accountId: context.account.id).paperclipActions)
        guard !current.contains(.prank(id: prank.id)), let updated = ShadowPaperclip.toggled(current, .prank(id: prank.id)) else {
            return
        }
        let _ = updateAyuGramSettings(postbox: context.account.postbox, { settings in
            var settings = settings
            settings.paperclipActions = ShadowPaperclip.encodeActions(updated)
            return settings
        }).startStandalone()
    }

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
    }, addUserPrank: {
        presentControllerImpl?(promptController(context: context, text: "Ссылка на пост", subtitle: "Пост публичного канала с голосовым, кружком или чем угодно: t.me/канал/123", value: nil, placeholder: "https://t.me/канал/123", characterLimit: 200, apply: { link in
            guard let link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            guard ShadowPaperclip.parsePrankLink(link) != nil else {
                toast("Это не ссылка на пост публичного канала. Нужна вида t.me/канал/123.")
                return
            }
            // After the first prompt has gone.
            Queue.mainQueue().after(0.4) {
                presentControllerImpl?(promptController(context: context, text: "Название прикола", subtitle: "Так он будет называться в меню скрепки", value: nil, placeholder: "Прикол", characterLimit: ShadowPaperclip.maxTitleLength, apply: { title in
                    guard let title else {
                        return
                    }
                    switch ShadowPaperclipUserPrankStore.add(title: title, link: link) {
                    case let .success(pranks):
                        userPranksPromise.set(pranks)
                        if let added = pranks.last {
                            checkAdded(added)
                            toast("Прикол «\(added.title)» добавлен в меню скрепки")
                        }
                    case .failure(.duplicate):
                        toast("Этот пост уже есть в твоих приколах")
                    case .failure(.full):
                        toast("Не больше \(ShadowPaperclip.maxPranks) своих приколов")
                    case .failure(.badLink):
                        toast("Это не ссылка на пост публичного канала")
                    }
                }))
            }
        }))
    }, removeUserPrank: {
        let pranks = ShadowPaperclipUserPrankStore.pranks
        guard !pranks.isEmpty else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Какой прикол удалить?", parseMarkdown: false)]
        for prank in pranks {
            items.append(ActionSheetButtonItem(title: prank.title, color: .destructive, action: { [weak sheet] in
                sheet?.dismissAnimated()
                ShadowPaperclipUserPrankStore.remove(id: prank.id)
                userPranksPromise.set(ShadowPaperclipUserPrankStore.pranks)
                // It leaves the menu too, unless the Shadow catalog has the same post.
                let catalog = ShadowDeviceAccess.cachedWhitelist?.paperclipPranks ?? []
                if !catalog.contains(where: { $0.id == prank.id }) {
                    let current = ShadowPaperclip.parseActions(currentAyuGramSettings(accountId: context.account.id).paperclipActions)
                    if current.contains(.prank(id: prank.id)), let updated = ShadowPaperclip.toggled(current, .prank(id: prank.id)) {
                        let _ = updateAyuGramSettings(postbox: context.account.postbox, { settings in
                            var settings = settings
                            settings.paperclipActions = ShadowPaperclip.encodeActions(updated)
                            return settings
                        }).startStandalone()
                    }
                }
            }))
        }
        sheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak sheet] in
            sheet?.dismissAnimated()
        })])])
        presentControllerImpl?(sheet)
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, ayuGramSettings(postbox: context.account.postbox), pranksPromise.get(), userPranksPromise.get())
    |> map { presentationData, settings, catalogPranks, userPranks -> (ItemListControllerState, (ItemListNodeState, Any)) in
        // A post that is both the user's and the catalog's is listed as the user's.
        let pranks = catalogPranks.filter { prank in !userPranks.contains(where: { $0.id == prank.id }) }
        let actions = ShadowPaperclip.parseActions(settings.paperclipActions)
        func position(_ action: ShadowPaperclip.Action) -> Int? {
            return actions.firstIndex(of: action).map { $0 + 1 }
        }
        var entries: [ShadowPaperclipActionsEntry] = [.imitationHeader(actions.count)]
        for (index, mode) in ShadowActivityImitationMode.menuOrder.enumerated() {
            entries.append(.imitation(Int32(index), mode, position(.imitation(mode))))
        }
        entries.append(.imitationFooter)
        entries.append(.userPranksHeader)
        for (index, prank) in userPranks.enumerated() {
            entries.append(.userPrank(Int32(index), prank, position(.prank(id: prank.id))))
        }
        entries.append(.userPrankAdd)
        if !userPranks.isEmpty {
            entries.append(.userPrankRemove)
        }
        entries.append(.userPranksFooter)
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
