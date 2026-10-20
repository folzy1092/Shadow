import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import ContextUI
import UndoUI
import SettingsUI

// Shadow: «Меню скрепки» (ShadowPaperclip). Holding the attachment button in a
// chat (ChatTextInputPanelNode → ChatPanelInterfaceInteraction
// .shadowPaperclipLongPress) opens the actions chosen in «Действия скрепки»:
// activity imitation (ShadowActivityImitation) and pranks from the admin
// catalog, forwarded without the author.
extension ChatControllerImpl {
    func shadowPresentPaperclipMenu(sourceView: UIView) {
        guard let peerId = self.chatLocation.peerId else {
            return
        }
        let context = self.context
        let threadId = self.chatLocation.threadId
        let isSecretChat = peerId.namespace == Namespaces.Peer.SecretChat
        let accountPeerId = context.account.peerId.toInt64()
        let key = ShadowActivityImitation.Key(accountPeerId: accountPeerId, peerId: peerId.toInt64(), threadId: threadId)
        let settings = currentAyuGramSettings(accountId: context.account.id)
        let pranks = ShadowDeviceAccess.cachedWhitelist?.paperclipPranks ?? []
        let running = ShadowActivityImitation.shared.mode(key)
        let runningCount = ShadowActivityImitation.shared.count(accountPeerId: accountPeerId)

        var actions = ShadowPaperclip.menuActions(ShadowPaperclip.parseActions(settings.paperclipActions), pranks: pranks)
        if isSecretChat {
            // Only «печатает» exists there, and pranks cannot be forwarded in.
            actions = actions.filter { $0 == .imitation(.typing) }
        }

        var items: [ContextMenuItem] = []
        if let running {
            items.append(.action(ContextMenuActionItem(text: "Остановить: \(running.title)", textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(systemName: "stop.circle"), color: theme.contextMenu.destructiveColor)
            }, action: { [weak self] _, f in
                f(.default)
                ShadowActivityImitation.shared.stop(key)
                self?.shadowPaperclipToast("Имитация остановлена")
            })))
        }
        if runningCount > (running == nil ? 0 : 1) {
            items.append(.action(ContextMenuActionItem(text: "Остановить везде (\(runningCount))", textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(systemName: "stop.fill"), color: theme.contextMenu.destructiveColor)
            }, action: { [weak self] _, f in
                f(.default)
                let count = ShadowActivityImitation.shared.stopAll(accountPeerId: accountPeerId)
                self?.shadowPaperclipToast("Остановлено имитаций: \(count)")
            })))
        }
        if !items.isEmpty {
            items.append(.separator)
        }

        for action in actions {
            switch action {
            case let .imitation(mode):
                let isRunning = running == mode
                items.append(.action(ContextMenuActionItem(text: mode.title, icon: { theme in
                    return generateTintedImage(image: UIImage(systemName: isRunning ? "checkmark" : mode.icon), color: theme.contextMenu.primaryColor)
                }, action: { [weak self] _, f in
                    f(.default)
                    ShadowActivityImitation.shared.start(account: context.account, peerId: peerId, threadId: threadId, mode: mode)
                    self?.shadowPaperclipToast("Имитация: \(mode.title.lowercased()). Остановить — снова зажать скрепку.")
                })))
            case let .prank(id):
                guard let prank = pranks.first(where: { $0.id == id }) else {
                    continue
                }
                items.append(.action(ContextMenuActionItem(text: prank.title, icon: { theme in
                    return generateTintedImage(image: UIImage(systemName: "theatermasks"), color: theme.contextMenu.primaryColor)
                }, action: { [weak self] _, f in
                    f(.default)
                    self?.shadowSendPaperclipPrank(prank, peerId: peerId, threadId: threadId)
                })))
            }
        }

        if actions.isEmpty {
            items.append(.action(ContextMenuActionItem(text: "Действия не выбраны", textColor: .disabled, icon: { _ in nil }, action: { _, _ in })))
        }
        items.append(.separator)
        items.append(.action(ContextMenuActionItem(text: "Настроить действия", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "gearshape"), color: theme.contextMenu.primaryColor)
        }, action: { [weak self] _, f in
            f(.default)
            self?.push(shadowPaperclipActionsController(context: context))
        })))

        let contextController = makeContextController(presentationData: self.presentationData, source: .reference(ChatControllerContextReferenceContentSource(controller: self, sourceView: sourceView, insets: .zero, actionsOnTop: true)), items: .single(ContextController.Items(content: .list(items))), gesture: nil)
        self.presentInGlobalOverlay(contextController)
    }

    private func shadowPaperclipToast(_ text: String) {
        self.present(UndoOverlayController(presentationData: self.presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }

    // Loads the prank post and forwards it without the author. With
    // paperclipPrankImitation the chat first shows the matching «записывает…» /
    // «отправляет…» for paperclipPrankSeconds.
    private func shadowSendPaperclipPrank(_ prank: ShadowPaperclip.Prank, peerId: EnginePeer.Id, threadId: Int64?) {
        let context = self.context
        let loaded: Signal<EngineRawMessage?, NoError> = context.engine.peers.resolvePeerByName(name: prank.channel, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            if case let .result(peer) = result {
                return .single(peer)
            }
            return .complete()
        }
        |> take(1)
        |> mapToSignal { peer -> Signal<EngineRawMessage?, NoError> in
            guard let peer, case .channel = peer else {
                return .single(nil)
            }
            return context.engine.messages.getMessagesLoadIfNecessary([EngineMessage.Id(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: prank.messageId)])
            |> `catch` { _ -> Signal<GetMessagesResult, NoError> in
                return .single(.result([]))
            }
            |> mapToSignal { result -> Signal<EngineRawMessage?, NoError> in
                if case let .result(messages) = result {
                    return .single(messages.first)
                }
                return .complete()
            }
            |> take(1)
        }
        |> timeout(20.0, queue: Queue.mainQueue(), alternate: .single(nil))

        let _ = (loaded |> deliverOnMainQueue).startStandalone(next: { [weak self] message in
            guard let message else {
                self?.shadowPaperclipToast("Не удалось загрузить прикол «\(prank.title)». Пост удалён или канал закрыт.")
                return
            }
            let settings = currentAyuGramSettings(accountId: context.account.id)
            let send: () -> Void = {
                let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [
                    .forward(source: message.id, threadId: threadId, grouping: .none, attributes: [ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false)], correlationId: nil)
                ]).startStandalone()
            }
            guard settings.paperclipPrankImitation else {
                send()
                return
            }
            let key = ShadowActivityImitation.Key(accountPeerId: context.account.peerId.toInt64(), peerId: peerId.toInt64(), threadId: threadId)
            let mode = ShadowPaperclip.imitationMode(for: shadowPrankMedia(message))
            ShadowActivityImitation.shared.start(account: context.account, peerId: peerId, threadId: threadId, mode: mode)
            Queue.mainQueue().after(Double(ShadowPaperclip.normalizedPrankSeconds(settings.paperclipPrankSeconds)), {
                // A different imitation the user started meanwhile keeps running.
                if ShadowActivityImitation.shared.mode(key) == mode {
                    ShadowActivityImitation.shared.stop(key)
                }
                send()
            })
        })
    }
}

private func shadowPrankMedia(_ message: EngineRawMessage) -> ShadowPaperclip.PrankMedia {
    for media in message.media {
        if let file = media as? TelegramMediaFile {
            if file.isInstantVideo {
                return .roundVideo
            } else if file.isVoice {
                return .voice
            } else if file.isSticker || file.isAnimatedSticker {
                return .sticker
            } else if file.isVideo || file.isAnimated {
                return .video
            } else if file.isMusic {
                return .audio
            } else {
                return .file
            }
        } else if media is TelegramMediaImage {
            return .photo
        }
    }
    return .text
}
