import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadow: «Экстренная защита» (ShadowDuress): the duress code, the accounts it
// logs out of, and the panic gesture. Changing or removing the code requires
// the owner (Face ID / Telegram passcode).

private enum ShadowEmergencySection: Int32 {
    case code
    case accounts
    case gesture
}

private enum ShadowEmergencyEntry: ItemListNodeEntry {
    case setCode(hasCode: Bool, enabled: Bool)
    case removeCode
    case codeFooter(String)
    case accountsHeader
    case account(index: Int, peerId: Int64, title: String, value: Bool)
    case accountsFooter
    case gestureHeader
    case gesture(String)
    case action(String)
    case gestureFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .setCode, .removeCode, .codeFooter:
            return ShadowEmergencySection.code.rawValue
        case .accountsHeader, .account, .accountsFooter:
            return ShadowEmergencySection.accounts.rawValue
        case .gestureHeader, .gesture, .action, .gestureFooter:
            return ShadowEmergencySection.gesture.rawValue
        }
    }

    // 0 and 1 are search entry ids (ShadowSettingsSearchIndex, destination .emergency).
    var stableId: Int32 {
        switch self {
        case .setCode: return 0
        case .gesture: return 1
        case .removeCode: return 2
        case .codeFooter: return 3
        case .accountsHeader: return 4
        case .accountsFooter: return 5
        case .gestureHeader: return 6
        case .action: return 7
        case .gestureFooter: return 8
        case let .account(index, _, _, _): return 100 + Int32(index)
        }
    }

    private var sortKey: Int32 {
        switch self {
        case .setCode: return 0
        case .removeCode: return 1
        case .codeFooter: return 2
        case .accountsHeader: return 3
        case let .account(index, _, _, _): return 100 + Int32(index)
        case .accountsFooter: return 10_000
        case .gestureHeader: return 10_001
        case .gesture: return 10_002
        case .action: return 10_003
        case .gestureFooter: return 10_004
        }
    }

    static func ==(lhs: ShadowEmergencyEntry, rhs: ShadowEmergencyEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.setCode(a1, a2), .setCode(b1, b2)):
            return a1 == b1 && a2 == b2
        case let (.codeFooter(a), .codeFooter(b)), let (.gesture(a), .gesture(b)), let (.action(a), .action(b)), let (.gestureFooter(a), .gestureFooter(b)):
            return a == b
        case let (.account(a1, a2, a3, a4), .account(b1, b2, b3, b4)):
            return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        case (.removeCode, .removeCode), (.accountsHeader, .accountsHeader), (.accountsFooter, .accountsFooter), (.gestureHeader, .gestureHeader):
            return true
        default:
            return false
        }
    }

    static func <(lhs: ShadowEmergencyEntry, rhs: ShadowEmergencyEntry) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowEmergencyArguments
        switch self {
        case let .setCode(hasCode, enabled):
            return ItemListActionItem(presentationData: presentationData, title: hasCode ? "Сменить код под принуждением" : "Задать код под принуждением", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.setCode)
        case .removeCode:
            return ItemListActionItem(presentationData: presentationData, title: "Удалить код под принуждением", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.removeCode)
        case let .codeFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .accountsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ПО КОДУ ВЫЙТИ ИЗ АККАУНТОВ", sectionId: self.section)
        case let .account(_, peerId, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setLogout(peerId, value)
            })
        case .accountsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Отмеченные аккаунты выходят из Telegram сразу после ввода кода — сессия на сервере завершается, локальные данные удаляются. Вернуться можно только повторным входом по номеру."), sectionId: self.section)
        case .gestureHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ТРЕВОЖНЫЙ ЖЕСТ", sectionId: self.section)
        case let .gesture(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Жест", label: label, sectionId: self.section, style: .blocks, action: arguments.chooseGesture)
        case let .action(label):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Действие", label: label, sectionId: self.section, style: .blocks, action: arguments.chooseAction)
        case let .gestureFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class ShadowEmergencyArguments {
    let setCode: () -> Void
    let removeCode: () -> Void
    let setLogout: (Int64, Bool) -> Void
    let chooseGesture: () -> Void
    let chooseAction: () -> Void

    init(setCode: @escaping () -> Void, removeCode: @escaping () -> Void, setLogout: @escaping (Int64, Bool) -> Void, chooseGesture: @escaping () -> Void, chooseAction: @escaping () -> Void) {
        self.setCode = setCode
        self.removeCode = removeCode
        self.setLogout = setLogout
        self.chooseGesture = chooseGesture
        self.chooseAction = chooseAction
    }
}

private func shadowEmergencyActionFooter(_ action: ShadowDuress.PanicAction) -> String {
    switch action {
    case .hideSecondSpace:
        return "Если открыто второе пространство, приложение сразу возвращается в основное. В основном жест ничего не делает."
    case .clean:
        return "Как код под принуждением, но без выхода из аккаунтов: скрываются чаты с замком и «Только второе», настройки Shadow пропадают. Вернуть всё — заблокировать приложение и ввести основной код или Face ID."
    case .fullDisguise:
        return "Включает Full-маскировку: приложение выглядит как обычный Telegram. Внимание: Full выключает замки и второе пространство, поэтому чаты с замком и из второго пространства становятся видны. Чтобы их спрятать, выберите «Чистый режим»."
    }
}

func shadowEmergencyController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    let duress = ShadowDuress.shared
    var presentControllerImpl: ((ViewController) -> Void)?
    var focusedIndex: Int?

    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revisionValue = 0
    let observer = NotificationCenter.default.addObserver(forName: ShadowDuress.didChangeNotification, object: nil, queue: .main, using: { _ in
        revisionValue += 1
        revision.set(revisionValue)
    })

    let passcodeData: Signal<PostboxAccessChallengeData, NoError> = context.sharedContext.accountManager.accessChallengeData()
    |> map { $0.data }

    let presentSheet: (String?, [(String, ActionSheetButtonColor, () -> Void)]) -> Void = { title, buttons in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        if let title {
            items.append(ActionSheetTextItem(title: title, parseMarkdown: false))
        }
        for (buttonTitle, color, action) in buttons {
            items.append(ActionSheetButtonItem(title: buttonTitle, color: color, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                action()
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

    let arguments = ShadowEmergencyArguments(setCode: {
        let _ = (passcodeData |> take(1) |> deliverOnMainQueue).startStandalone(next: { data in
            guard let passcodeInfo = shadowSecondSpacePasscodeInfo(data) else {
                ShadowSecondSpaceCodePrompt.showMessage(context: context, title: "Сначала включите код-пароль", message: "Настройки → Конфиденциальность → Код-пароль. Код под принуждением вводится на его экране.")
                return
            }
            let (format, mainCode) = passcodeInfo
            let ask: () -> Void = {
                var hint = "Отличается от код-пароля Telegram и от второго кода."
                if case let .digits(length) = format {
                    hint = "\(length) цифр, как у код-пароля Telegram, но другие (и не второй код)."
                }
                ShadowSecondSpaceCodePrompt.present(context: context, title: "Код под принуждением", message: hint, format: format, completion: { first in
                    guard let first else {
                        return
                    }
                    if let error = ShadowDuress.validationError(code: first, format: format, mainCode: mainCode, matchesSecondCode: { ShadowSpaceStore.shared.verifyCode($0) }) {
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
                            duress.setCode(first)
                            ShadowSecondSpaceCodePrompt.showMessage(context: context, title: "Код задан", message: "Если вас заставят разблокировать телефон, введите его вместо код-пароля: откроется чистое основное пространство без чатов с замком и второго пространства, настройки Shadow будут скрыты.")
                        })
                    })
                })
            }
            if duress.hasCode {
                context.sharedContext.shadowDisguiseAuthenticate(reason: "Сменить код под принуждением", completion: { success in
                    if success {
                        ask()
                    }
                })
            } else {
                ask()
            }
        })
    }, removeCode: {
        presentSheet("Код перестанет работать, список аккаунтов для выхода очистится.", [("Удалить код", .destructive, {
            context.sharedContext.shadowDisguiseAuthenticate(reason: "Удалить код под принуждением", completion: { success in
                if success {
                    duress.removeCode()
                }
            })
        })])
    }, setLogout: { peerId, value in
        duress.setLogout(value, accountPeerId: peerId)
    }, chooseGesture: {
        presentSheet(nil, ShadowDuress.PanicGesture.allCases.map { gesture -> (String, ActionSheetButtonColor, () -> Void) in
            return (gesture.title, .accent, {
                duress.setPanicGesture(gesture)
            })
        })
    }, chooseAction: {
        presentSheet(nil, ShadowDuress.PanicAction.allCases.map { action -> (String, ActionSheetButtonColor, () -> Void) in
            return (action.title, .accent, {
                duress.setPanicAction(action)
            })
        })
    })

    let accounts: Signal<[(Int64, String)], NoError> = context.sharedContext.activeAccountsWithInfo
    |> map { _, accounts -> [(Int64, String)] in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        return accounts.map { info -> (Int64, String) in
            return (info.peer.id.toInt64(), info.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder))
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, revision.get(), passcodeData, accounts)
    |> deliverOnMainQueue
    |> map { presentationData, _, passcode, accounts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let hasPasscode = shadowSecondSpacePasscodeInfo(passcode) != nil
        var entries: [ShadowEmergencyEntry] = [.setCode(hasCode: duress.hasCode, enabled: hasPasscode)]
        if duress.hasCode {
            entries.append(.removeCode)
        }
        if hasPasscode {
            entries.append(.codeFooter("Третий код для экрана блокировки. Он открывает основное пространство без чатов с замком и без чатов второго пространства и прячет настройки Shadow. Основной код или Face ID при следующей разблокировке возвращают всё. Код хранится только в виде хэша."))
        } else {
            entries.append(.codeFooter("Нужен включённый код-пароль Telegram: Настройки → Конфиденциальность → Код-пароль."))
        }
        if duress.hasCode {
            entries.append(.accountsHeader)
            let selected = Set(duress.logoutAccountPeerIds)
            for (index, account) in accounts.enumerated() {
                entries.append(.account(index: index, peerId: account.0, title: account.1, value: selected.contains(account.0)))
            }
            entries.append(.accountsFooter)
        }
        entries.append(.gestureHeader)
        entries.append(.gesture(duress.panicGesture.title))
        if duress.panicGesture != .off {
            entries.append(.action(duress.panicAction.title))
            entries.append(.gestureFooter(shadowEmergencyActionFooter(duress.panicAction) + " Жест работает, пока приложение открыто, и не требует кода."))
        } else {
            entries.append(.gestureFooter("Мгновенно прячет второе пространство, включает чистый режим или Full-маскировку — перевернуть телефон экраном вниз, встряхнуть или тройной тап двумя пальцами."))
        }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Экстренная защита"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: context.sharedContext.currentPresentationData.with { $0 }.theme.list.itemAccentColor)
    }
    return controller
}
