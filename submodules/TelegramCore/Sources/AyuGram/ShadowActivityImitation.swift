import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

// Shadow: «Имитация активности» (ShadowActivityImitationMode). Repeats
// messages.setTyping with the chosen action every few seconds until stopped,
// then sends the cancel action. Requests go straight to the network, not through
// ManagedLocalInputActivities, so Ghost Mode's «не показывать "печатает"» does not
// hide an imitation the user started on purpose. Runs on the main queue; one
// imitation per account, chat and topic, any number of chats at once. Nothing is
// stored: the imitations end with the app process.
public final class ShadowActivityImitation {
    public static let shared = ShadowActivityImitation()
    public static let didChangeNotification = Notification.Name("ShadowActivityImitation.didChange")

    public struct Key: Hashable {
        public let accountPeerId: Int64
        public let peerId: Int64
        public let threadId: Int64?

        public init(accountPeerId: Int64, peerId: Int64, threadId: Int64?) {
            self.accountPeerId = accountPeerId
            self.peerId = peerId
            self.threadId = threadId
        }
    }

    private enum Target {
        case peer(Api.InputPeer, topMessageId: Int32?)
        case secretChat(Api.InputEncryptedChat)
    }

    private final class Imitation {
        let mode: ShadowActivityImitationMode
        let network: Network
        var target: Target?
        var timer: SwiftSignalKit.Timer?
        var tick: Int = 0
        let resolveDisposable = MetaDisposable()

        init(mode: ShadowActivityImitationMode, network: Network) {
            self.mode = mode
            self.network = network
        }
    }

    private var imitations: [Key: Imitation] = [:]

    private init() {
    }

    // The running mode in this chat, nil when there is none. Main queue.
    public func mode(_ key: Key) -> ShadowActivityImitationMode? {
        assert(Queue.mainQueue().isCurrent())
        return self.imitations[key]?.mode
    }

    // How many imitations this account runs. Main queue.
    public func count(accountPeerId: Int64) -> Int {
        assert(Queue.mainQueue().isCurrent())
        return self.imitations.keys.filter { $0.accountPeerId == accountPeerId }.count
    }

    // Starts (or replaces) the imitation in a chat. Main queue.
    public func start(account: Account, peerId: PeerId, threadId: Int64?, mode: ShadowActivityImitationMode) {
        assert(Queue.mainQueue().isCurrent())
        let key = Key(accountPeerId: account.peerId.toInt64(), peerId: peerId.toInt64(), threadId: threadId)
        if let current = self.imitations.removeValue(forKey: key) {
            self.invalidate(current, sendCancel: false)
        }
        let imitation = Imitation(mode: mode, network: account.network)
        self.imitations[key] = imitation

        imitation.resolveDisposable.set((account.postbox.transaction { transaction -> Target? in
            guard let peer = transaction.getPeer(peerId) else {
                return nil
            }
            if let secretChat = peer as? TelegramSecretChat {
                return .secretChat(.inputEncryptedChat(.init(chatId: Int32(secretChat.id.id._internalGetInt64Value()), accessHash: secretChat.accessHash)))
            }
            guard let inputPeer = apiInputPeer(peer) else {
                return nil
            }
            return .peer(inputPeer, topMessageId: threadId.flatMap { Int32(clamping: $0) })
        }
        |> deliverOnMainQueue).start(next: { [weak self, weak imitation] target in
            guard let self, let imitation, self.imitations[key] === imitation else {
                return
            }
            guard let target else {
                self.stop(key)
                return
            }
            imitation.target = target
            self.fire(imitation)
            let timer = SwiftSignalKit.Timer(timeout: ShadowActivityImitationMode.repeatInterval, repeat: true, completion: { [weak self, weak imitation] in
                guard let self, let imitation else {
                    return
                }
                self.fire(imitation)
            }, queue: Queue.mainQueue())
            imitation.timer = timer
            timer.start()
        }))
        NotificationCenter.default.post(name: ShadowActivityImitation.didChangeNotification, object: nil)
    }

    // Stops the imitation in a chat and clears the action. Main queue.
    public func stop(_ key: Key) {
        assert(Queue.mainQueue().isCurrent())
        guard let imitation = self.imitations.removeValue(forKey: key) else {
            return
        }
        self.invalidate(imitation, sendCancel: true)
        NotificationCenter.default.post(name: ShadowActivityImitation.didChangeNotification, object: nil)
    }

    // Stops every imitation of the account; returns how many there were. Main queue.
    @discardableResult
    public func stopAll(accountPeerId: Int64) -> Int {
        assert(Queue.mainQueue().isCurrent())
        let keys = self.imitations.keys.filter { $0.accountPeerId == accountPeerId }
        for key in keys {
            if let imitation = self.imitations.removeValue(forKey: key) {
                self.invalidate(imitation, sendCancel: true)
            }
        }
        if !keys.isEmpty {
            NotificationCenter.default.post(name: ShadowActivityImitation.didChangeNotification, object: nil)
        }
        return keys.count
    }

    private func invalidate(_ imitation: Imitation, sendCancel: Bool) {
        imitation.timer?.invalidate()
        imitation.timer = nil
        imitation.resolveDisposable.dispose()
        if sendCancel, let target = imitation.target {
            let _ = ShadowActivityImitation.request(network: imitation.network, target: target, action: nil).start()
        }
    }

    private func fire(_ imitation: Imitation) {
        guard let target = imitation.target else {
            return
        }
        let tick = imitation.tick
        imitation.tick += 1
        let mode = imitation.mode.resolved(randomIndex: Int.random(in: 0 ..< 1000))
        let action = ShadowActivityImitation.apiAction(mode, progress: ShadowActivityImitationMode.progress(tick: tick))
        let _ = ShadowActivityImitation.request(network: imitation.network, target: target, action: action).start()
    }

    // nil action: cancel.
    private static func request(network: Network, target: Target, action: Api.SendMessageAction?) -> Signal<Never, NoError> {
        let signal: Signal<Api.Bool, MTRpcError>
        switch target {
        case let .peer(inputPeer, topMessageId):
            var flags: Int32 = 0
            if topMessageId != nil {
                flags |= 1 << 0
            }
            signal = network.request(Api.functions.messages.setTyping(flags: flags, peer: inputPeer, topMsgId: topMessageId, action: action ?? .sendMessageCancelAction))
        case let .secretChat(inputChat):
            signal = network.request(Api.functions.messages.setEncryptedTyping(peer: inputChat, typing: action == nil ? .boolFalse : .boolTrue))
        }
        return signal
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> ignoreValues
    }

    private static func apiAction(_ mode: ShadowActivityImitationMode, progress: Int32) -> Api.SendMessageAction {
        switch mode {
        case .typing, .random:
            return .sendMessageTypingAction
        case .recordingVoice:
            return .sendMessageRecordAudioAction
        case .recordingRound:
            return .sendMessageRecordRoundAction
        case .recordingVideo:
            return .sendMessageRecordVideoAction
        case .sendingPhoto:
            return .sendMessageUploadPhotoAction(.init(progress: progress))
        case .sendingVideo:
            return .sendMessageUploadVideoAction(.init(progress: progress))
        case .sendingRound:
            return .sendMessageUploadRoundAction(.init(progress: progress))
        case .sendingAudio:
            return .sendMessageUploadAudioAction(.init(progress: progress))
        case .sendingFile:
            return .sendMessageUploadDocumentAction(.init(progress: progress))
        case .choosingSticker:
            return .sendMessageChooseStickerAction
        case .choosingLocation:
            return .sendMessageGeoLocationAction
        case .choosingContact:
            return .sendMessageChooseContactAction
        case .playingGame:
            return .sendMessageGamePlayAction
        case .importingHistory:
            return .sendMessageHistoryImportAction(.init(progress: progress))
        }
    }
}
