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
    case "emergency":
        push(shadowEmergencyController(context: context))
    case "storage":
        push(ayuForkStorageController(context: context))
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
    case "folzy":
        shadowOpenDeveloperProfile(context: context, peerId: 7878830498, username: nil, push: push)
    case "matey":
        shadowOpenDeveloperProfile(context: context, peerId: 1068369028, username: "helbooyy", push: push)
    default:
        // Shadow: an unknown command is an easter egg name (ShadowEasterEggs);
        // when there is no such egg, Shadow settings open as before.
        context.sharedContext.shadowOpenEasterEgg(context: context, name: link.command, notFound: {
            push(ayuGramSettingsController(context: context))
        })
    }
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
