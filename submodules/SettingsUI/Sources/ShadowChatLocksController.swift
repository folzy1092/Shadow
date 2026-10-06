import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import AVFoundation
import PasscodeUI

// Shadow: "Замки чатов" — password, locked chats of this account and reset
// (spec docs/specs/2026-10-01-shadow-batch.md, section 5). Chats are locked from
// the chat list context menu; state lives in ShadowChatLockStore.

private enum ShadowChatLocksSection: Int32 {
    case password
    case intruder
    case chats
    case reset
    case preview
}

private enum ShadowChatLocksEntry: ItemListNodeEntry {
    case passwordAction(hasPassword: Bool)
    case passwordFooter
    case intruderPhoto(Bool)
    case intruderFooter
    case chatsHeader
    case chat(index: Int, peerId: EnginePeer.Id, title: String)
    case chatsEmpty
    case chatsFooter
    case hidePreview(Bool)
    case hidePreviewFooter
    case resetAction
    case resetPending(String)
    case resetNow(enabled: Bool)
    case resetCancel
    case resetFooter

    var section: ItemListSectionId {
        switch self {
        case .passwordAction, .passwordFooter:
            return ShadowChatLocksSection.password.rawValue
        case .intruderPhoto, .intruderFooter:
            return ShadowChatLocksSection.intruder.rawValue
        case .chatsHeader, .chat, .chatsEmpty, .chatsFooter:
            return ShadowChatLocksSection.chats.rawValue
        case .resetAction, .resetPending, .resetNow, .resetCancel, .resetFooter:
            return ShadowChatLocksSection.reset.rawValue
        case .hidePreview, .hidePreviewFooter:
            return ShadowChatLocksSection.preview.rawValue
        }
    }

    // 0 is the search entry id (ShadowSettingsSearchIndex, destination .chatLocks).
    var stableId: Int32 {
        switch self {
        case .passwordAction: return 0
        case .passwordFooter: return 1
        case .chatsHeader: return 2
        case let .chat(index, _, _): return 100 + Int32(index)
        case .chatsEmpty: return 10_000
        case .chatsFooter: return 10_001
        case .hidePreview: return 10_002
        case .hidePreviewFooter: return 10_003
        case .resetAction: return 10_004
        case .resetPending: return 10_005
        case .resetNow: return 10_006
        case .resetCancel: return 10_007
        case .resetFooter: return 10_008
        case .intruderPhoto: return 10_009
        case .intruderFooter: return 10_010
        }
    }

    static func <(lhs: ShadowChatLocksEntry, rhs: ShadowChatLocksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowChatLocksArguments
        switch self {
        case let .passwordAction(hasPassword):
            return ItemListActionItem(presentationData: presentationData, title: hasPassword ? "Сменить пароль" : "Задать пароль", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.changePassword)
        case .passwordFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Чат открывается по Face ID / Touch ID. Пароль нужен, если биометрия не сработала, и для сброса замков. Пароль хранится на устройстве только в виде хэша."), sectionId: self.section)
        case let .intruderPhoto(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Фото при неверном пароле", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setIntruderPhoto(value)
            })
        case .intruderFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Если кто-то ошибётся с паролем замка или код-паролем Telegram, фронтальная камера сделает снимок. Снимок сразу сохраняется в галерею, а после следующей разблокировки приходит вам в «Избранное» с временем и причиной. Face ID сам по себе снимок не делает — только неверный пароль."), sectionId: self.section)
        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЗАБЛОКИРОВАННЫЕ ЧАТЫ", sectionId: self.section)
        case let .chat(_, peerId, title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "Снять", sectionId: self.section, style: .blocks, action: {
                arguments.unlock(peerId)
            })
        case .chatsEmpty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Нет заблокированных чатов. Зажмите чат в списке и выберите «Заблокировать чат»."), sectionId: self.section)
        case .chatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Имя закрытого чата в списке видно. После разблокировки чат остаётся открытым, пока приложение не уйдёт в фон."), sectionId: self.section)
        case let .hidePreview(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Прятать последнее сообщение", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setHidesPreview(value)
            })
        case .hidePreviewFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Включено — текст последнего сообщения, черновик и превью медиа закрытого чата в списке скрыты спойлером. Выключено — чат в списке выглядит как обычный и не привлекает внимания, но последнее сообщение видно."), sectionId: self.section)
        case .resetAction:
            return ItemListActionItem(presentationData: presentationData, title: "Сбросить все замки", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.reset)
        case let .resetPending(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .resetNow(enabled):
            return ItemListActionItem(presentationData: presentationData, title: "Сбросить сейчас", kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.resetNow)
        case .resetCancel:
            return ItemListActionItem(presentationData: presentationData, title: "Отменить сброс", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.cancelReset)
        case .resetFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Сброс снимает замки со всех чатов на всех аккаунтах и удаляет пароль. С паролем — сразу, без пароля — через час. Любая успешная разблокировка чата за этот час отменяет сброс."), sectionId: self.section)
        }
    }
}

private final class ShadowChatLocksArguments {
    let changePassword: () -> Void
    let unlock: (EnginePeer.Id) -> Void
    let reset: () -> Void
    let resetNow: () -> Void
    let cancelReset: () -> Void
    var setIntruderPhoto: (Bool) -> Void = { _ in }
    var setHidesPreview: (Bool) -> Void = { _ in }

    init(changePassword: @escaping () -> Void, unlock: @escaping (EnginePeer.Id) -> Void, reset: @escaping () -> Void, resetNow: @escaping () -> Void, cancelReset: @escaping () -> Void) {
        self.changePassword = changePassword
        self.unlock = unlock
        self.reset = reset
        self.resetNow = resetNow
        self.cancelReset = cancelReset
    }
}

private func shadowChatLockResetText(remaining: TimeInterval) -> String {
    if remaining <= 0.0 {
        return "Сброс без пароля доступен."
    }
    let minutes = Int(ceil(remaining / 60.0))
    return "Сброс без пароля станет доступен через \(minutes) мин."
}

func shadowChatLocksController(context: AccountContext, focus: ShadowSettingsSearchItem? = nil) -> ViewController {
    let linkRows = ShadowSettingsLinkRows()
    let store = ShadowChatLockStore.shared
    let accountPeerId = context.account.peerId.toInt64()
    var presentControllerImpl: ((ViewController) -> Void)?
    var focusedIndex: Int?

    // Re-render on store changes and every 30 seconds (reset countdown).
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    var revisionValue = 0
    let bump: () -> Void = {
        revisionValue += 1
        revision.set(revisionValue)
    }
    let observer = NotificationCenter.default.addObserver(forName: ShadowChatLockStore.didChangeNotification, object: nil, queue: .main, using: { _ in
        bump()
    })
    let ticker = (Signal<Void, NoError>.single(Void())
    |> then(Signal<Void, NoError>.complete() |> delay(30.0, queue: Queue.mainQueue()))
    |> restart)

    let arguments = ShadowChatLocksArguments(changePassword: {
        if store.hasPassword {
            context.sharedContext.shadowChatLockAuthenticate(reason: "Сменить пароль замков", completion: { success in
                if success {
                    context.sharedContext.shadowChatLockCreatePassword(completion: { _ in })
                }
            })
        } else {
            context.sharedContext.shadowChatLockCreatePassword(completion: { _ in })
        }
    }, unlock: { peerId in
        context.sharedContext.shadowChatLockUnlockChat(context: context, peerId: peerId, completion: { _ in })
    }, reset: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Снять все замки и удалить пароль?", parseMarkdown: false)]
        if store.hasPassword {
            items.append(ActionSheetButtonItem(title: "Ввести пароль", color: .destructive, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                // Password only: the reset exists for when Face ID is not an option.
                ShadowChatLockPasswordPrompt.present(context: context, completion: { password in
                    guard let password else {
                        return
                    }
                    if store.verifyPassword(password) {
                        store.performReset()
                    } else {
                        ShadowChatLockPasswordPrompt.showWrongPassword(context: context)
                    }
                })
            }))
        }
        items.append(ActionSheetButtonItem(title: "Не помню пароль (через 1 час)", color: .destructive, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            store.requestReset()
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
    }, resetNow: {
        if store.canResetWithoutPassword() {
            store.performReset()
        }
    }, cancelReset: {
        store.cancelReset()
    })

    arguments.setHidesPreview = { value in
        store.setHidesPreview(value)
    }

    arguments.setIntruderPhoto = { value in
        if !value {
            ShadowIntruderLog.shared.isEnabled = false
            bump()
            return
        }
        // Ask for the camera and the photo library here, never on the lock screen.
        AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
            DispatchQueue.main.async {
                ShadowIntruderLog.shared.isEnabled = granted
                bump()
                if !granted {
                    ShadowChatLockPasswordPrompt.showMessage(context: context, title: "Нет доступа к камере", message: "Разрешите Telegram доступ к камере в Настройках iOS.")
                    return
                }
                ShadowIntruderCamera.requestPhotoLibraryAccess(completion: { photosGranted in
                    if !photosGranted {
                        ShadowChatLockPasswordPrompt.showMessage(context: context, title: "Нет доступа к фото", message: "Снимки будут приходить только в «Избранное». Чтобы они сразу сохранялись в галерею, разрешите Telegram добавлять фото в Настройках iOS.")
                    }
                })
            }
        })
    }

    let lockedPeers: Signal<[(EnginePeer.Id, String)], NoError> = revision.get()
    |> map { _ -> [EnginePeer.Id] in
        return store.lockedPeerIds(accountPeerId: accountPeerId).map { EnginePeer.Id($0) }
    }
    |> distinctUntilChanged
    |> mapToSignal { peerIds -> Signal<[(EnginePeer.Id, String)], NoError> in
        return context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> [(EnginePeer.Id, String)] in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            return peerIds.map { peerId in
                if peerId == context.account.peerId {
                    return (peerId, presentationData.strings.Conversation_SavedMessages)
                }
                let title = peers[peerId].flatMap { $0 }?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "Чат \(peerId.id._internalGetInt64Value())"
                return (peerId, title)
            }
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, revision.get(), ticker, lockedPeers)
    |> deliverOnMainQueue
    |> map { presentationData, _, _, lockedPeers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ShadowChatLocksEntry] = [
            .passwordAction(hasPassword: store.hasPassword),
            .passwordFooter,
            .chatsHeader
        ]
        if lockedPeers.isEmpty {
            entries.append(.chatsEmpty)
        } else {
            for (index, item) in lockedPeers.enumerated() {
                entries.append(.chat(index: index, peerId: item.0, title: item.1))
            }
            entries.append(.chatsFooter)
        }
        entries.append(.hidePreview(store.hidesPreview))
        entries.append(.hidePreviewFooter)
        if let remaining = store.resetRemaining() {
            entries.append(.resetPending(shadowChatLockResetText(remaining: remaining)))
            entries.append(.resetNow(enabled: remaining <= 0.0))
            entries.append(.resetCancel)
        } else {
            entries.append(.resetAction)
        }
        entries.append(.resetFooter)
        entries.append(.intruderPhoto(ShadowIntruderLog.shared.isEnabled))
        entries.append(.intruderFooter)
        linkRows.stableIds = entries.map { $0.stableId }
        focusedIndex = shadowSettingsFocusIndex(stableIds: entries.map { $0.stableId }, target: focus)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Замки чатов"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: shadowSettingsInitialScroll(index: focusedIndex), animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    let controller = ItemListController(context: context, state: signal)
    shadowSettingsInstallLinkMenu(controller: controller, context: context, screen: "locks", rows: linkRows)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    if focus != nil {
        shadowSettingsInstallFocus(controller: controller, index: { focusedIndex }, color: shadowSettingsPulseColor(context.sharedContext.currentPresentationData.with { $0 }.theme))
    }
    return controller
}

// Secure password entry for the reset (system alert with a secure text field).
private enum ShadowChatLockPasswordPrompt {
    static func present(context: AccountContext, completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "Введите пароль", message: "Пароль замков чатов", preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = "Пароль"
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: { _ in
            completion(nil)
        }))
        alert.addAction(UIAlertAction(title: "Сбросить", style: .destructive, handler: { [weak alert] _ in
            completion(alert?.textFields?.first?.text ?? "")
        }))
        DispatchQueue.main.async {
            context.sharedContext.mainWindow?.presentNative(alert)
        }
    }

    static func showMessage(context: AccountContext, title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        DispatchQueue.main.async {
            context.sharedContext.mainWindow?.presentNative(alert)
        }
    }

    static func showWrongPassword(context: AccountContext) {
        let alert = UIAlertController(title: "Неверный пароль", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        DispatchQueue.main.async {
            context.sharedContext.mainWindow?.presentNative(alert)
        }
    }
}
