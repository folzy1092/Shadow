import Foundation
import Postbox
import SwiftSignalKit

// Shadow fork: an "immediately re-assert offline" trigger. Sending a message
// makes the server flip the account online as a side effect of the send RPC; the
// aggressive-offline timer in ManagedAccountPresence only re-sends "offline"
// every 30s (5s under Ghost Mode), so without this the user can look online for
// that whole period after a send. The presence manager subscribes to this pipe
// and re-sends "offline" at once when it fires.
public let ayuOfflineReassertPipe = ValuePipe<Void>()

public func ayuTriggerOfflineReassert() {
    ayuOfflineReassertPipe.putNext(Void())
}

// Shadow fork: fire the reassert only after we KNOW the send RPC's round
// trip has actually finished (PendingMessageManager hooks this on completion/
// failure/cancellation of the real network request, not at enqueue time).
// Previously this fired from `enqueueMessages` at t=0/+2s/+5s as a blind guess,
// racing the real RPC dispatch (which can be delayed arbitrarily by media
// upload, transaction commit, or queueing behind other pending sends) — a send
// that went out later than +5s left the account online with no further
// correction until the next periodic timer tick. Hooking the actual RPC
// completion removes the guesswork: our "offline" call is now guaranteed to be
// queued strictly after the send RPC's own online side effect, so it always
// corrects it (at the cost of one network round trip's worth of residual blip,
// which is not eliminable client-side — see the comment on `transform` below).
public func ayuReassertOfflineAfterSendIfNeeded() {
    if ayuGramSettingsCurrent.effectiveSendViaScheduled || ayuGramSettingsCurrent.effectiveSendWithoutOnline {
        ayuTriggerOfflineReassert()
    }
}

// Shadow fork: "delayed send" (отложенная отправка).
//
// Goal: while the full Ghost Mode is on, the user should not flash "online" at
// the exact moment of sending a message. Telegram's SEND RPC itself
// (messages.sendMessage / sendMedia / …) makes the SERVER mark the account
// online as a side effect — no client-side presence gate can prevent that within
// the same request. The only reliable way to send without appearing online is to
// route the message through Telegram's NATIVE Scheduled Messages mechanism
// (schedule_date): a scheduled message is stored server-side and delivered later
// by the server, and does NOT update the sender's last-seen at enqueue time.
//
// So this is NOT a local fake queue with send()+sleep()+timer(). We attach a real
// `OutgoingScheduleInfoMessageAttribute` with a schedule time a few seconds in the
// future; the existing pending-message pipeline then sends it as a proper
// scheduled message (Namespaces.Message.ScheduledCloud), exactly like the user
// picking "Schedule Message" by hand — just automatic and with a short delay.
//
// Delays (per spec):
//   • text-only messages: 12 seconds;
//   • media messages (photo / video / document / voice / round video): a longer,
//     "dynamic" delay so the upload has time to finish before the scheduled
//     moment (the client uploads the file first, then the server publishes it at
//     schedule_date). We scale by whether media is present.

public enum AyuDelayedSend {
    // Base delay for text messages, in seconds.
    public static let textDelay: Int32 = 12
    // Delay for media messages, in seconds. Media must be uploaded before the
    // scheduled time, so we give it more headroom than plain text.
    public static let mediaDelay: Int32 = 30

    // Only regular cloud conversations support server-side scheduling. Secret
    // chats have no schedule_date, and messages already in a scheduled/quick-reply
    // namespace must not be re-scheduled.
    private static func peerSupportsScheduling(_ peerId: PeerId) -> Bool {
        switch peerId.namespace {
        case Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel:
            return true
        default:
            return false
        }
    }

    // True if the message already carries an attribute that fixes its send
    // semantics and therefore must not be overridden by delayed send: an explicit
    // schedule (the user already scheduled it, incl. "send when online"), a quick
    // reply, a paid-stars send, or a suggested post.
    private static func hasOverridingAttribute(_ attributes: [MessageAttribute]) -> Bool {
        for attribute in attributes {
            if attribute is OutgoingScheduleInfoMessageAttribute {
                return true
            }
            if attribute is OutgoingQuickReplyMessageAttribute {
                return true
            }
            if attribute is PaidStarsMessageAttribute {
                return true
            }
            if attribute is SuggestedPostMessageAttribute {
                return true
            }
        }
        return false
    }

    // The normal chat UI clears its composer when the newly-enqueued message
    // appears in the current history view. Automatically scheduled messages go
    // into ScheduledCloud instead, so that view update never arrives. Expose the
    // exact transform eligibility to the UI so it can clear optimistically.
    public static func willAutomaticallySchedule(messages: [EnqueueMessage], peerId: PeerId) -> Bool {
        guard ayuGramSettingsCurrent.effectiveSendViaScheduled else {
            return false
        }
        guard peerSupportsScheduling(peerId) else {
            return false
        }
        return messages.contains(where: { message in
            return !hasOverridingAttribute(message.attributes)
        })
    }

    private static func messageHasMedia(_ message: EnqueueMessage) -> Bool {
        switch message {
        case let .message(_, _, _, mediaReference, _, _, _, _, _, _):
            return mediaReference != nil
        case .forward:
            // Forwarded messages usually carry media; use the longer delay to be
            // safe (a forwarded media still needs server-side processing).
            return true
        }
    }

    // Transform a batch of outgoing messages for one peer, attaching a schedule
    // attribute to each eligible message. `now` is the current unix time. Returns
    // the possibly-modified messages. Cheap and side-effect-free.
    public static func transform(messages: [EnqueueMessage], peerId: PeerId, now: Int32) -> [EnqueueMessage] {
        guard willAutomaticallySchedule(messages: messages, peerId: peerId) else {
            return messages
        }
        return messages.map { message -> EnqueueMessage in
            if hasOverridingAttribute(message.attributes) {
                return message
            }
            let delay = messageHasMedia(message) ? mediaDelay : textDelay
            let scheduleTime = now + delay
            let scheduleAttribute = OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: nil)
            return message.withUpdatedAttributes { attributes in
                var attributes = attributes
                attributes.removeAll(where: { $0 is OutgoingScheduleInfoMessageAttribute })
                attributes.append(scheduleAttribute)
                return attributes
            }
        }
    }
}
