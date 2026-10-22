import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import ChatPresentationInterfaceState
import UndoUI

// Shadow: local pins (ShadowLocalPinStore) in the chat. The header panel gets
// them merged with the real pinned messages (shadowMergeLocalPins); the message
// menu pins and unpins them (shadowLocalPinMenuAction), the panel's close
// button and list button go through shadowHandleLocalPinUnpin /
// shadowOpenLocalPinList.

func shadowLocalPinnedMessages(context: AccountContext, peerId: EnginePeer.Id) -> Signal<[Message], NoError> {
    let accountPeerId = context.account.peerId.toInt64()
    let pins: Signal<[ShadowLocalPin], NoError> = Signal { subscriber in
        let emit = {
            subscriber.putNext(ShadowLocalPinStore.shared.pins(accountPeerId: accountPeerId, peerId: peerId.toInt64()))
        }
        emit()
        let observer = NotificationCenter.default.addObserver(forName: ShadowLocalPinStore.didChangeNotification, object: nil, queue: nil, using: { _ in
            emit()
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return pins
    |> distinctUntilChanged
    |> mapToSignal { pins -> Signal<[Message], NoError> in
        if pins.isEmpty {
            return .single([])
        }
        let ids = pins.map { EngineMessage.Id(peerId: peerId, namespace: $0.namespace, id: $0.id) }
        return context.engine.data.subscribe(EngineDataList(ids.map { TelegramEngine.EngineData.Item.Messages.Message(id: $0) }))
        |> map { messages -> [Message] in
            return messages.compactMap { $0?._asMessage() }.sorted(by: { $0.id < $1.id })
        }
    }
}

// The pinned message the header shows with local pins mixed in. Only plain
// chats (not threads); a local pin of a message that is really pinned is
// skipped. Counts and the "#N" index treat both kinds as one list.
func shadowMergeLocalPins(server: Signal<ChatControllerImpl.TopPinnedMessageState, NoError>, context: AccountContext, chatLocation: ChatLocation, referenceMessage: Signal<ChatControllerImpl.PinnedReferenceMessage?, NoError>) -> Signal<ChatControllerImpl.TopPinnedMessageState, NoError> {
    guard case let .peer(peerId) = chatLocation else {
        return server
    }
    return combineLatest(queue: .mainQueue(),
        server,
        shadowLocalPinnedMessages(context: context, peerId: peerId),
        referenceMessage
    )
    |> map { serverState, local, reference -> ChatControllerImpl.TopPinnedMessageState in
        // Still loading: the header waits for the real pins.
        guard case let .resolved(server) = serverState else {
            return serverState
        }
        return .resolved(shadowMergedPin(server: server, local: local, reference: reference, peerId: peerId))
    }
    |> distinctUntilChanged
}

private func shadowMergedPin(server: ChatPinnedMessage?, local: [Message], reference: ChatControllerImpl.PinnedReferenceMessage?, peerId: EnginePeer.Id) -> ChatPinnedMessage? {
    let local = local.filter { message in
        return message.id != server?.message.id && !message.tags.contains(.pinned)
    }
    if local.isEmpty {
        return server
    }
    var referenceId: Int32?
    var isScrolled = false
    if let reference, case let .ready(loaded) = reference, loaded.id.peerId == peerId {
        referenceId = loaded.id.id
        isScrolled = loaded.isScrolled
    }
    guard let localIndex = ShadowLocalPins.pickIndex(ids: local.map { $0.id.id }, referenceId: referenceId, isScrolled: isScrolled) else {
        return server
    }
    let localPick = local[localIndex]
    let localTopId = local[local.count - 1].id
    guard let server else {
        return ChatPinnedMessage(message: localPick, index: localIndex, totalCount: local.count, topMessageId: localTopId)
    }
    let totalCount = server.totalCount + local.count
    let topMessageId = max(server.topMessageId, localTopId)
    if ShadowLocalPins.prefersFirst(localPick.id.id, over: server.message.id.id, referenceId: referenceId, isScrolled: isScrolled) {
        let olderServer = server.message.id < localPick.id ? server.index + 1 : server.index
        return ChatPinnedMessage(message: localPick, index: min(totalCount - 1, olderServer + localIndex), totalCount: totalCount, topMessageId: topMessageId)
    } else {
        let olderLocal = local.filter { $0.id < server.message.id }.count
        return ChatPinnedMessage(message: server.message, index: min(totalCount - 1, server.index + olderLocal), totalCount: totalCount, topMessageId: topMessageId)
    }
}

func shadowIsLocallyPinned(context: AccountContext, messageId: EngineMessage.Id) -> Bool {
    return ShadowLocalPinStore.shared.isPinned(accountPeerId: context.account.peerId.toInt64(), peerId: messageId.peerId.toInt64(), pin: ShadowLocalPin(namespace: messageId.namespace, id: messageId.id))
}

func shadowSetLocallyPinned(context: AccountContext, messageId: EngineMessage.Id, pinned: Bool) {
    ShadowLocalPinStore.shared.setPinned(pinned, accountPeerId: context.account.peerId.toInt64(), peerId: messageId.peerId.toInt64(), pin: ShadowLocalPin(namespace: messageId.namespace, id: messageId.id))
}

extension ChatControllerImpl {
    // The close button of the pinned panel and «Открепить» on a local pin:
    // unpins it here, nothing goes to the server. False: not a local pin.
    func shadowHandleLocalPinUnpin(messageId: EngineMessage.Id) -> Bool {
        guard shadowIsLocallyPinned(context: self.context, messageId: messageId) else {
            return false
        }
        shadowSetLocallyPinned(context: self.context, messageId: messageId, pinned: false)
        self.shadowLocalPinToast("Откреплено у вас")
        return true
    }

    func shadowLocalPinToast(_ text: String) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: true, action: { _ in return false }), in: .current)
    }

    // The list button while the panel shows a local pin: the local pins of
    // this chat — tap to go to one, or unpin the shown one. True: handled.
    func shadowOpenLocalPinList(messageId: EngineMessage.Id) -> Bool {
        guard shadowIsLocallyPinned(context: self.context, messageId: messageId) else {
            return false
        }
        let context = self.context
        let peerId = messageId.peerId
        let _ = (shadowLocalPinnedMessages(context: context, peerId: peerId)
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] messages in
            guard let self else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Закреплено у вас", parseMarkdown: false)]
            for message in messages.reversed() {
                var text = message.text.replacingOccurrences(of: "\n", with: " ")
                if text.isEmpty {
                    text = message.media.isEmpty ? "Сообщение" : "Медиа"
                }
                if text.count > 60 {
                    text = String(text.prefix(60)) + "…"
                }
                items.append(ActionSheetButtonItem(title: text, action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    self?.interfaceInteraction?.navigateToMessage(message.id, false, true, .pinnedMessage)
                }))
            }
            items.append(ActionSheetButtonItem(title: "Открепить показанное", color: .destructive, action: { [weak self, weak actionSheet] in
                actionSheet?.dismissAnimated()
                let _ = self?.shadowHandleLocalPinUnpin(messageId: messageId)
            }))
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak actionSheet] in actionSheet?.dismissAnimated() })])
            ])
            self.present(actionSheet, in: .window(.root))
        })
        return true
    }
}
