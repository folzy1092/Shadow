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
        // The user's own pranks («Мои приколы») first, then the Shadow catalog.
        let pranks = ShadowPaperclip.mergedPranks(user: ShadowPaperclipUserPrankStore.pranks, catalog: ShadowDeviceAccess.cachedWhitelist?.paperclipPranks ?? [])
        let running = ShadowActivityImitation.shared.mode(key)
        let runningCount = ShadowActivityImitation.shared.count(accountPeerId: accountPeerId)

        var actions = ShadowPaperclip.menuActions(ShadowPaperclip.parseActions(settings.paperclipActions), pranks: pranks)
        if isSecretChat {
            // Only «печатает» exists there, and pranks cannot be forwarded in.
            actions = actions.filter { $0 == .imitation(.typing) || $0 == .tool(.scrollToStart) || $0 == .tool(.translate) }
        }
        // «Упомянуть всех» only where there are members to mention.
        if !self.shadowCanMentionAll {
            actions = actions.filter { $0 != .tool(.mentionAll) }
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
            case let .tool(tool):
                let title: String
                if tool == .translate, let template = ShadowInputTranslation.activeTemplate {
                    title = "Перевод: \(template.title) — выключить"
                } else {
                    title = tool.title
                }
                items.append(.action(ContextMenuActionItem(text: title, icon: { theme in
                    return generateTintedImage(image: UIImage(systemName: tool.icon), color: theme.contextMenu.primaryColor)
                }, action: { [weak self, weak sourceView] _, f in
                    f(.default)
                    self?.shadowRunChatTool(tool, sourceView: sourceView)
                })))
            case let .prank(id):
                guard let prank = pranks.first(where: { $0.id == id }) else {
                    continue
                }
                items.append(.action(ContextMenuActionItem(text: prank.title, icon: { theme in
                    return generateTintedImage(image: UIImage(systemName: "theatermasks"), color: theme.contextMenu.primaryColor)
                }, action: { [weak self] _, f in
                    f(.default)
                    guard let self else {
                        return
                    }
                    // A reply chosen in the chat (swipe on a message) is taken now
                    // and cleared, as a sent message clears it.
                    let replySubject = self.presentationInterfaceState.interfaceState.replyMessageSubject?.subjectModel
                    if replySubject != nil {
                        self.updateChatPresentationInterfaceState(animated: true, interactive: false, {
                            $0.updatedInterfaceState { $0.withUpdatedReplyMessageSubject(nil) }
                        })
                    }
                    self.shadowSendPaperclipPrank(prank, peerId: peerId, threadId: threadId, replySubject: replySubject)
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
    // «отправляет…» for paperclipPrankSeconds, and a voice message or round
    // video then «отправляет…» for paperclipPrankSendSeconds (0: skipped).
    //
    // As a reply it is sent as a copy instead: a forward cannot be a reply
    // (TelegramCore drops the reply of a forward), while the same file sent by
    // reference is an ordinary message of the user's, reply included, and is not
    // uploaded again.
    private func shadowSendPaperclipPrank(_ prank: ShadowPaperclip.Prank, peerId: EnginePeer.Id, threadId: Int64?, replySubject: EngineMessageReplySubject?) {
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
                let enqueued: EnqueueMessage
                if let replySubject {
                    enqueued = shadowPrankCopy(message, threadId: threadId, replySubject: replySubject)
                } else {
                    enqueued = .forward(source: message.id, threadId: threadId, grouping: .none, attributes: [ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false)], correlationId: nil)
                }
                let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [enqueued]).startStandalone()
            }
            guard settings.paperclipPrankImitation else {
                send()
                return
            }
            let key = ShadowActivityImitation.Key(accountPeerId: context.account.peerId.toInt64(), peerId: peerId.toInt64(), threadId: threadId)
            let media = shadowPrankMedia(message)
            let mode = ShadowPaperclip.imitationMode(for: media)
            let sendSeconds = ShadowPaperclip.normalizedPrankSendSeconds(settings.paperclipPrankSendSeconds)
            let sendingMode = sendSeconds > 0 ? ShadowPaperclip.sendingMode(for: media) : nil
            ShadowActivityImitation.shared.start(account: context.account, peerId: peerId, threadId: threadId, mode: mode)
            Queue.mainQueue().after(Double(ShadowPaperclip.normalizedPrankSeconds(settings.paperclipPrankSeconds)), {
                // A different imitation the user started meanwhile keeps running.
                guard ShadowActivityImitation.shared.mode(key) == mode else {
                    send()
                    return
                }
                guard let sendingMode else {
                    ShadowActivityImitation.shared.stop(key)
                    send()
                    return
                }
                // Second phase: «записывает…» becomes «отправляет…».
                ShadowActivityImitation.shared.start(account: context.account, peerId: peerId, threadId: threadId, mode: sendingMode)
                Queue.mainQueue().after(Double(sendSeconds), {
                    if ShadowActivityImitation.shared.mode(key) == sendingMode {
                        ShadowActivityImitation.shared.stop(key)
                    }
                    send()
                })
            })
        })
    }
}

// The prank post as the user's own message: its text (with formatting) and its
// file or photo by reference to the post, answering `replySubject`.
private func shadowPrankCopy(_ message: EngineRawMessage, threadId: Int64?, replySubject: EngineMessageReplySubject) -> EnqueueMessage {
    var attributes: [EngineMessage.Attribute] = []
    for attribute in message.attributes {
        if let attribute = attribute as? TextEntitiesMessageAttribute {
            attributes.append(attribute)
        }
    }
    let media = message.media.first(where: { $0 is TelegramMediaFile || $0 is TelegramMediaImage })
    let mediaReference: AnyMediaReference? = media.map { .message(message: MessageReference(message), media: $0) }
    return .message(text: message.text, attributes: attributes, inlineStickers: [:], mediaReference: mediaReference, threadId: threadId, replyToMessageId: replySubject, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
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
