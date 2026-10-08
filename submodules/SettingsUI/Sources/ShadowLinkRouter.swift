import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import UndoUI

// Shadow: where each quick link (ShadowLinks) leads. shadow://<command> and
// tg://shadow/<command> are the same link. The list is in docs/shadow-links.md;
// keep both in sync.
public func shadowOpenLink(context: AccountContext, link: ShadowLinks.Link, navigationController: NavigationController?) {
    // With the settings hidden (disguise, duress session) there is nothing to open.
    if ShadowDisguise.shared.hidesSettings {
        return
    }
    guard let navigationController = navigationController ?? (context.sharedContext.mainWindow?.viewController as? NavigationController) else {
        return
    }
    let push: (ViewController) -> Void = { controller in
        navigationController.pushViewController(controller)
    }

    // shadow://<screen>/<toggle>[?on|?off|?switch|?value=N] (ShadowSettingLinks).
    if let slug = link.arguments.first, let setting = ShadowSettingLinks.find(screen: link.command, slug: slug) {
        shadowOpenSettingLink(context: context, setting: setting, mode: ShadowSettingLinks.mode(ShadowSettingLinks.mode(query: link.query), for: setting), navigationController: navigationController)
        return
    }
    // A setting this version does not know: say so instead of opening the screen.
    if !link.arguments.isEmpty, ShadowSettingLinks.isScreen(link.command) {
        shadowShowUnsupportedLink(context: context, link: link, isSetting: true, push: push)
        return
    }

    switch link.command {
    case "settings":
        push(ayuGramSettingsController(context: context))
    case "updates", "update":
        push(ayuGramSettingsController(context: context, autoCheckUpdates: true))
    case "customization":
        push(ayuCustomizationController(context: context))
    case "spy":
        push(ayuSpyController(context: context))
    case "ghost":
        push(ayuGhostController(context: context))
    case "filters", "shadowban":
        push(shadowMessageFiltersController(context: context))
    case "profile":
        push(ayuMiscController(context: context))
    case "accounts":
        push(shadowHiddenAccountsController(context: context))
    case "backup":
        push(shadowSettingsBackupController(context: context))
    case "misc":
        push(shadowMiscController(context: context))
    case "screenshot":
        push(shadowMessageScreenshotSettingsController(context: context))
    case "templates":
        push(shadowQuickRepliesController(context: context))
    case "locks":
        push(shadowChatLocksController(context: context))
    case "space":
        push(shadowSecondSpaceController(context: context))
    case "feed":
        push(shadowFeedSettingsController(context: context))
    case "emergency":
        push(shadowEmergencyController(context: context))
    case "storage":
        push(ayuForkStorageController(context: context))
    case "versions", "archive":
        push(shadowVersionArchiveController(context: context))
    case "autoupdate", "signing":
        push(shadowAutoUpdateController(context: context))
    case "header", "buttons":
        push(shadowHeaderButtonsController(context: context))
    case "sync":
        push(shadowSettingsSyncController(context: context))
    case "deleted":
        push(ayuArchiveChatController(context: context))
    case "edited":
        push(ayuEditedArchiveChatController(context: context))
    case "access":
        // The device list is the admins'; for everyone else the link is a no-op.
        if ShadowDeviceAccess.hasAdminAccess(peerId: context.account.peerId.id._internalGetInt64Value()) {
            push(shadowDeviceAccessController(context: context, prefillDeviceId: link.query["id"]))
        }
    case "me", "user":
        // shadow://me, shadow://user?id=N|username=name (ShadowProfileTarget).
        guard let target = ShadowProfileTarget(link: link) else {
            push(ayuGramSettingsController(context: context))
            return
        }
        shadowOpenProfile(context: context, target: target, push: push)
    case "gift", "gifts":
        // Telegram's "Отправить подарок": contacts, birthdays, yourself.
        let _ = (context.account.stateManager.contactBirthdays
        |> take(1)
        |> deliverOnMainQueue).start(next: { birthdays in
            push(context.sharedContext.makePremiumGiftController(context: context, source: .settings(birthdays), completion: nil))
        })
    case "folzy":
        shadowOpenDeveloperProfile(context: context, peerId: 7878830498, username: nil, push: push)
    case "matey":
        shadowOpenDeveloperProfile(context: context, peerId: 1068369028, username: "helbooyy", push: push)
    default:
        // Shadow: an unknown command is an easter egg name (ShadowEasterEggs);
        // when there is no such egg, the link is from a newer Shadow or wrong.
        context.sharedContext.shadowOpenEasterEgg(context: context, name: link.command, notFound: {
            shadowShowUnsupportedLink(context: context, link: link, isSetting: false, push: push)
        })
    }
}

// "Эта настройка работает с Shadow 1.4.4. У вас 1.4.3 — обновите Shadow."
// The ?v= of the link says which version it needs (ShadowSettingLink.since);
// "Обновить" opens the update screen.
private func shadowShowUnsupportedLink(context: AccountContext, link: ShadowLinks.Link, isSetting: Bool, push: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let linkVersion = link.query["v"].flatMap { $0.isEmpty ? nil : $0 }
    let text = ShadowSettingLinks.unsupportedText(isSetting: isSetting, linkVersion: linkVersion, current: ShadowVersion.fork)
    context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: 6.0, customUndoText: "Обновить"), elevatedLayout: false, action: { action in
        if case .undo = action {
            push(ayuGramSettingsController(context: context, autoCheckUpdates: true))
        }
        return false
    }), on: .root)
}

// Opens a developer's profile by user id; falls back to the username when the
// account has never seen that user (a bare id cannot be resolved remotely).
private func shadowOpenDeveloperProfile(context: AccountContext, peerId: Int64, username: String?, push: @escaping (ViewController) -> Void) {
    let id = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(peerId))
    let open: (EnginePeer) -> Void = { peer in
        if let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            push(controller)
        }
    }
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: id))
    |> deliverOnMainQueue).start(next: { peer in
        if let peer {
            open(peer)
            return
        }
        guard let username else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Профиль пока недоступен: напиши этому человеку или найди его в поиске.", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), on: .root)
            return
        }
        let _ = (context.engine.peers.resolvePeerByName(name: username, referrer: nil)
        |> deliverOnMainQueue).start(next: { result in
            if case let .result(peer) = result, let peer {
                open(peer)
            }
        })
    })
}

// A person's profile by link: your own opens as "Мой профиль".
private func shadowOpenProfile(context: AccountContext, target: ShadowProfileTarget, push: @escaping (ViewController) -> Void) {
    switch target {
    case .me:
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> deliverOnMainQueue).start(next: { peer in
            if let peer, let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .myProfile, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
                push(controller)
            }
        })
    case let .id(value):
        shadowOpenDeveloperProfile(context: context, peerId: value, username: nil, push: push)
    case let .username(name):
        let _ = (context.engine.peers.resolvePeerByName(name: name, referrer: nil)
        |> deliverOnMainQueue).start(next: { result in
            guard case let .result(peer) = result else {
                return
            }
            if let peer, let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
                push(controller)
            } else if peer == nil {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Нет пользователя @\(name).", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), on: .root)
            }
        })
    }
}
