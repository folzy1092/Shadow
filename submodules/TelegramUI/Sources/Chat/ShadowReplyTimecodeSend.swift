import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import ComponentFlow
import AlertComponent
import AlertCheckComponent
import ChatPresentationInterfaceState
import ChatInterfaceState

// Shadow: the timecode for a text reply to a voice message or round video
// (ShadowReplyTimecode). ChatControllerNode.sendCurrentMessage asks for it
// before sending and prepends it to the text.
struct ShadowReplyTimecodeCandidate {
    let timecode: String
    let duration: Double
    let isRoundVideo: Bool
    let chatKey: String
    let action: ShadowReplyTimecode.Action
}

func shadowReplyTimecodeCandidate(context: AccountContext, state: ChatPresentationInterfaceState, chatLocation: ChatLocation) -> ShadowReplyTimecodeCandidate? {
    let settings = currentAyuGramSettings(accountId: context.account.id)
    guard settings.replyTimecode, let peerId = chatLocation.peerId else {
        return nil
    }
    guard let replySubject = state.interfaceState.replyMessageSubject, let replyMessage = state.replyMessage, replyMessage.id == replySubject.messageId else {
        return nil
    }
    var file: TelegramMediaFile?
    for media in replyMessage.media {
        if let media = media as? TelegramMediaFile, media.isVoice || media.isInstantVideo {
            file = media
        }
    }
    guard let file else {
        return nil
    }
    let accountPeerId = context.account.peerId.toInt64()
    let key = ShadowReplyTimecode.messageKey(accountPeerId: accountPeerId, peerId: replyMessage.id.peerId.toInt64(), namespace: replyMessage.id.namespace, id: replyMessage.id.id)
    guard let sample = ShadowReplyTimecode.positions.sample(key: key) else {
        return nil
    }
    let duration = sample.duration > 0.0 ? sample.duration : (file.duration ?? 0.0)
    guard let timecode = ShadowReplyTimecode.timecode(position: sample.position(now: CACurrentMediaTime()), duration: duration) else {
        return nil
    }
    let chatKey = ShadowReplyTimecode.chatKey(accountPeerId: accountPeerId, peerId: peerId.toInt64(), threadId: chatLocation.threadId)
    let remembered = ShadowReplyTimecode.memory.answer(chat: chatKey, now: Date().timeIntervalSince1970)
    let action = ShadowReplyTimecode.action(enabled: true, mode: settings.replyTimecodeMode, remembered: remembered)
    return ShadowReplyTimecodeCandidate(timecode: timecode, duration: duration, isRoundVideo: file.isInstantVideo, chatKey: chatKey, action: action)
}

// "Добавить тайм-код 0:53?" with a checkbox that remembers the answer in this
// chat for 30 minutes. Cancel keeps the message in the input field.
func shadowReplyTimecodeAlertController(context: AccountContext, candidate: ShadowReplyTimecodeCandidate, completion: @escaping (ShadowReplyTimecode.Resolved) -> Void) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let checkState = AlertCheckComponent.ExternalState()
    let kind = candidate.isRoundVideo ? "Кружок" : "Голосовое"
    let length = ShadowVoiceTime.clock(Int32(candidate.duration))

    let content: [AnyComponentWithIdentity<AlertComponentEnvironment>] = [
        AnyComponentWithIdentity(id: "title", component: AnyComponent(AlertTitleComponent(title: "Добавить тайм-код \(candidate.timecode)?"))),
        AnyComponentWithIdentity(id: "text", component: AnyComponent(AlertTextComponent(content: .plain("\(kind) \(length) · вы на \(candidate.timecode)")))),
        AnyComponentWithIdentity(id: "check", component: AnyComponent(AlertCheckComponent(title: "Запомнить для этого чата на 30 мин", initialValue: false, externalState: checkState)))
    ]

    func resolve(_ add: Bool) {
        if checkState.value {
            ShadowReplyTimecode.memory.remember(chat: candidate.chatKey, add: add, now: Date().timeIntervalSince1970)
        }
        completion(add ? .add(candidate.timecode) : .skip)
    }

    return AlertScreen(
        configuration: AlertScreen.Configuration(actionAlignment: .vertical),
        content: content,
        actions: [
            .init(title: "Добавить", type: .default, action: {
                resolve(true)
            }),
            .init(title: "Без тайм-кода", action: {
                resolve(false)
            }),
            .init(title: presentationData.strings.Common_Cancel)
        ],
        updatedPresentationData: (presentationData, context.sharedContext.presentationData)
    )
}
