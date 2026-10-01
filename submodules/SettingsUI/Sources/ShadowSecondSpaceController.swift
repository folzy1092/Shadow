import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadow: "Второе пространство" (spec docs/specs/2026-10-01-shadow-batch.md, section 6).
// The second code is entered on the Telegram passcode screen; this screen sets
// it up and lists chats with a non-default visibility. In the main space the
// list shows only "only main" chats, so it never reveals second-space chats.

private enum ShadowSecondSpaceSection: Int32 {
    case status
    case code
    case chats
}

private enum ShadowSecondSpaceEntry: ItemListNodeEntry {
    case status(String)
    case statusFooter(String)
    case setCode(hasCode: Bool, enabled: Bool)
    case leave
    case removeCode
    case codeFooter(String)
    case chatsHeader
    case addChat
    case chat(index: Int, peerId: EnginePeer.Id, title: String, visibility: ShadowSpaceStore.Visibility)
    case chatsFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .status, .statusFooter:
            return ShadowSecondSpaceSection.status.rawValue
        case .setCode, .leave, .removeCode, .codeFooter:
            return ShadowSecondSpaceSection.code.rawValue
        case .chatsHeader, .addChat, .chat, .chatsFooter:
            return ShadowSecondSpaceSection.chats.rawValue
        }
    }

    // 0 is the search entry id (ShadowSettingsSearchIndex, destination .secondSpace).
    var stableId: Int32 {
        switch self {
        case .setCode: return 0
        case .status: return 1
        case .statusFooter: return 2
        case .leave: return 3
        case .removeCode: return 4
        case .codeFooter: return 5
        case .chatsHeader: return 6
        case .addChat: return 7
        case let .chat(index, _, _, _): return 100 + Int32(index)
        case .chatsFooter: return 100_000
        }
    }

    // Sorting differs from stableId so the code button can keep id 0 for search.
    private var sortKey: Int32 {
        switch self {
        case .status: return 0
        case .statusFooter: return 1
        case .setCode: return 2
        case .leave: return 3
        case .removeCode: return 4
        case .codeFooter: return 5
        case .chatsHeader: return 6
        case .addChat: return 7
        case let .chat(index, _, _, _): return 100 + Int32(index)
        case .chatsFooter: return 100_000
        }
    }

    static func ==(lhs: ShadowSecondSpaceEntry, rhs: ShadowSecondSpaceEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.status(a), .status(b)), let (.statusFooter(a), .statusFooter(b)), let (.codeFooter(a), .codeFooter(b)), let (.chatsFooter(a), .chatsFooter(b)):
            return a == b
        case let (.setCode(a1, a2), .setCode(b1, b2)):
            return a1 == b1 && a2 == b2
        case (.leave, .leave), (.removeCode, .removeCode), (.chatsHeader, .chatsHeader), (.addChat, .addChat):
            return true
        case let (.chat(a1, a2, a3, a4), .chat(b1, b2, b3, b4)):
            return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        default:
            return false
        }
    }

    static func <(lhs: ShadowSecondSpaceEntry, rhs: ShadowSecondSpaceEntry) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowSecondSpaceArguments
        switch self {
        case let .status(text):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Сейчас открыто", label: text, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .statusFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .setCode(hasCode, enabled):
            return ItemListActionItem(presentationData: presentationData, title: hasCode ? "Сменить второй код" : "Задать второй код", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.setCode)
        case .leave:
            return ItemListActionItem(presentationData: presentationData, title: "Перейти в основное пространство", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.leave)
        case .removeCode:
            return ItemListActionItem(presentationData: presentationData, title: "Удалить второй код", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.removeCode)
        case let .codeFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЧАТЫ", sectionId: self.section)
        case .addChat:
            return ItemListActionItem(presentationData: presentationData, title: "Добавить чат", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.addChat)
        case let .chat(_, peerId, title, visibility):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: visibility.title, sectionId: self.section, style: .blocks, action: {
                arguments.changeChat(peerId, title)
            })
        case let .chatsFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class ShadowSecondSpaceArguments {
    let setCode: () -> Void
    let leave: () -> Void
    let removeCode: () -> Void
    let addChat: () -> Void
    let changeChat: (EnginePeer.Id, String) -> Void

    init(setCode: @escaping () -> Void, leave: @escaping () -> Void, removeCode: @escaping () -> Void, addChat: @escaping () -> Void, changeChat: @escaping (EnginePeer.Id, String) -> Void) {
        self.setCode = setCode
        self.leave = leave
        self.removeCode = removeCode
        self.addChat = addChat
        self.changeChat = changeChat
    }
}

// Telegram passcode -> the format the second code must follow and the main code.
private func shadowSecondSpacePasscodeInfo(_ data: PostboxAccessChallengeData) -> (ShadowSpaceStore.CodeFormat, String)? {
    switch data {
    case .none:
        return nil
    case let .numericalPassword(code):
        return (.digits(code.count == 6 ? 6 : 4), code)
    case let .plaintextPassword(code):
        return (.text, code)
    }
}

private enum ShadowSecondSpaceCodePrompt {
    static func present(context: AccountContext, title: String, message: String?, format: ShadowSpaceStore.CodeFormat, completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = "Код"
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            if case .digits = format {
                field.keyboardType = .numberPad
            }
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: { _ in
            completion(nil)
        }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] _ in
            completion(alert?.textFields?.first?.text ?? "")
        }))
        DispatchQueue.main.async {
            context.sharedContext.mainWindow?.presentNative(alert)
        }
    }

    static func showMessage(context: AccountContext, title: String, message: String? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        DispatchQueue.main.async {
            context.sharedContext.mainWindow?.presentNative(alert)
        }
    }
}

func shadowSecondSpaceController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    let store = ShadowSpaceStore.shared
    let accountPeerId = context.account.peerId.toInt64()
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var focusedIndex: Int?

    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revisionValue = 0
    let observer = NotificationCenter.default.addObserver(forName: ShadowSpaceStore.didChangeNotification, object: nil, queue: .main, using: { _ in
        revisionValue += 1
        revision.set(revisionValue)
    })

    let passcodeData: Signal<PostboxAccessChallengeData, NoError> = context.sharedContext.accountManager.accessChallengeData()
    |> map { $0.data }

    let chooseVisibility: ([EnginePeer.Id], String) -> Void = { peerIds, title in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: title, parseMarkdown: false)]
        for visibility in ShadowSpaceStore.Visibility.allCases {
            items.append(ActionSheetButtonItem(title: visibility.title, color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                let _ = shadowApplySpaceVisibility(account: context.account, peerIds: peerIds, visibility: visibility).startStandalone()
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(actionSheet)
    }

    let arguments = ShadowSecondSpaceArguments(setCode: {
        let _ = (passcodeData |> take(1) |> deliverOnMainQueue).startStandalone(next: { data in
            guard let passcodeInfo = shadowSecondSpacePasscodeInfo(data) else {
                ShadowSecondSpaceCodePrompt.showMessage(context: context, title: "Сначала включите код-пароль", message: "Настройки → Конфиденциальность → Код-пароль. Второй код вводится на его экране.")
                return
            }
            let (format, mainCode) = passcodeInfo
            let ask: () -> Void = {
                var hint = "Отличается от код-пароля Telegram."
                if case let .digits(length) = format {
                    hint = "\(length) цифр, как у код-пароля Telegram, но другие."
                }
                ShadowSecondSpaceCodePrompt.present(context: context, title: "Второй код", message: hint, format: format, completion: { first in
                    guard let first else {
                        return
                    }
                    if let error = ShadowSpaceStore.validationError(code: first, format: format, mainCode: mainCode) {
                        ShadowSecondSpaceCodePrompt.showMessage(context: context, title: error)
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: {
                        ShadowSecondSpaceCodePrompt.present(context: context, title: "Повторите код", message: nil, format: format, completion: { second in
                            guard let second else {
                                return
                            }
                            guard ShadowSpaceStore.normalize(second) == ShadowSpaceStore.normalize(first) else {
                                ShadowSecondSpaceCodePrompt.showMessage(context: context, title: "Коды не совпадают")
                                return
                            }
                            store.setCode(first)
                            ShadowSecondSpaceCodePrompt.showMessage(context: context, title: "Второй код задан", message: "Введите его вместо код-пароля на экране блокировки, чтобы открыть второе пространство.")
                        })
                    })
                })
            }
            if store.hasCode && store.activeSpace != .second {
                // Changing the code from the main space requires the current one.
                ShadowSecondSpaceCodePrompt.present(context: context, title: "Текущий второй код", message: nil, format: format, completion: { current in
                    guard let current else {
                        return
                    }
                    if store.verifyCode(current) {
                        ask()
                    } else {
                        ShadowSecondSpaceCodePrompt.showMessage(context: context, title: "Неверный код")
                    }
                })
            } else {
                ask()
            }
        })
    }, leave: {
        store.setActiveSpace(.main)
    }, removeCode: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: "Все чаты этого аккаунта снова станут видны везде, уведомления вернутся к прежним.", parseMarkdown: false),
                ActionSheetButtonItem(title: "Удалить второй код", color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    let _ = shadowRemoveSecondSpace(account: context.account).startStandalone()
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(actionSheet)
    }, addChat: {
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSavedMessages, .removeSearchHeader, .excludeRecent, .doNotSearchMessages], hasContactSelector: false, title: "Выберите чат"))
        controller.peerSelected = { [weak controller] peer, _ in
            controller?.dismiss()
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            chooseVisibility([peer.id], peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder))
        }
        pushControllerImpl?(controller)
    }, changeChat: { peerId, title in
        chooseVisibility([peerId], title)
    })

    let customPeers: Signal<[(EnginePeer.Id, String, ShadowSpaceStore.Visibility)], NoError> = revision.get()
    |> map { _ -> [(Int64, ShadowSpaceStore.Visibility)] in
        let space = store.activeSpace
        return store.customVisibilities(accountPeerId: accountPeerId)
        .filter { $0.value.isVisible(in: space) || space == .second }
        .sorted(by: { $0.key < $1.key })
        .map { ($0.key, $0.value) }
    }
    |> mapToSignal { items -> Signal<[(EnginePeer.Id, String, ShadowSpaceStore.Visibility)], NoError> in
        let peerIds = items.map { EnginePeer.Id($0.0) }
        return context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> [(EnginePeer.Id, String, ShadowSpaceStore.Visibility)] in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            return items.map { item in
                let peerId = EnginePeer.Id(item.0)
                let title = peers[peerId].flatMap { $0 }?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "Чат \(peerId.id._internalGetInt64Value())"
                return (peerId, title, item.1)
            }
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, revision.get(), passcodeData, customPeers)
    |> deliverOnMainQueue
    |> map { presentationData, _, passcode, customPeers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let hasPasscode = shadowSecondSpacePasscodeInfo(passcode) != nil
        let inSecond = store.activeSpace == .second
        var entries: [ShadowSecondSpaceEntry] = [
            .status(inSecond ? "Второе пространство" : "Основное пространство"),
            .statusFooter("Основной код-пароль или Face ID открывают основное пространство, второй код — второе. Второе пространство действует, пока приложение снова не заблокируется."),
            .setCode(hasCode: store.hasCode, enabled: hasPasscode)
        ]
        if inSecond {
            entries.append(.leave)
            entries.append(.removeCode)
        }
        if hasPasscode {
            entries.append(.codeFooter("Код хранится на устройстве только в виде хэша. Удалить его можно только из второго пространства — все чаты снова станут видны везде."))
        } else {
            entries.append(.codeFooter("Нужен включённый код-пароль Telegram: Настройки → Конфиденциальность → Код-пароль."))
        }
        if store.hasCode {
            entries.append(.chatsHeader)
            entries.append(.addChat)
            for (index, item) in customPeers.enumerated() {
                entries.append(.chat(index: index, peerId: item.0, title: item.1, visibility: item.2))
            }
            entries.append(.chatsFooter(inSecond ? "Чаты «только второе» не видны в основном пространстве и не присылают уведомлений. Изменить видимость можно и долгим нажатием на чат или кнопкой 🫥 в режиме «Изменить»." : "Здесь показаны только чаты основного пространства. Чаты второго пространства видны, когда оно открыто."))
        }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Второе пространство"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: context.sharedContext.currentPresentationData.with { $0 }.theme.list.itemAccentColor)
    }
    return controller
}
