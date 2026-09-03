import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    private let postbox: Postbox
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)

    private var shouldKeepOnlinePresenceDisposable: Disposable?
    // Shadow fork: subscription to the "re-assert offline now" trigger fired
    // right after a send while "send without appearing online" is on.
    private var offlineReassertDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private let lastSeenUpdateDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    // Set only for a real online -> offline transition. Timer-driven offline
    // reasserts and post-send reasserts must not keep moving the displayed
    // last-seen time forward while the account remains hidden.
    private var pendingOfflineTransitionTimestamp: Int32?
    
    // AyuGram: start as "unknown" (nil) so the very first value — including a
    // `false` when online is hidden from launch — actually triggers updatePresence
    // and arms the re-assert timer. Previously an initial `false == false` was
    // skipped, so the aggressive "stay offline" never started for a boot-hidden
    // account and reading a chat could leave you online.
    private var wasOnline: Bool? = nil

    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, postbox: Postbox) {
        self.queue = queue
        self.network = network
        self.postbox = postbox
        
        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            let previousValue = self.wasOnline
            if previousValue != value {
                self.wasOnline = value
                if value {
                    // An in-flight offline request no longer represents the
                    // account's current transition.
                    self.pendingOfflineTransitionTimestamp = nil
                } else if previousValue == true {
                    self.pendingOfflineTransitionTimestamp = Int32(Date().timeIntervalSince1970)
                }
                self.updatePresence(value)
            }
        })

        // Shadow fork: when a send fires the offline re-assert trigger, and we
        // are currently meant to be hidden/offline, re-send "offline" right away
        // (bypassing the 30s timer and the same-value `wasOnline` guard) so the
        // brief server-side online blip from the send RPC is cleared immediately.
        self.offlineReassertDisposable = (ayuOfflineReassertPipe.signal()
        |> deliverOn(self.queue)).start(next: { [weak self] in
            guard let self else {
                return
            }
            if self.wasOnline != true {
                self.updatePresence(false)
            }
        })
    }

    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.offlineReassertDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.lastSeenUpdateDisposable.dispose()
        self.onlineTimer?.invalidate()
    }
    
    private func updatePresence(_ isOnline: Bool) {
        let request: Signal<Api.Bool, MTRpcError>
        self.onlineTimer?.invalidate()
        // AyuGram: re-assert presence on a timer in BOTH directions. Upstream only
        // re-armed the online keep-alive; we also keep re-sending "offline" so a
        // hidden online status can never resurface between updates. Under Ghost
        // Mode, shorten the period so this timer acts as a backstop in case the
        // event-driven reassert (ayuReassertOfflineAfterSendIfNeeded, fired from
        // PendingMessageManager right after a send RPC completes) is ever missed.
        let timerPeriod: Double = ayuGramSettingsCurrent.ghostMode ? 5.0 : 30.0
        let timer = SignalKitTimer(timeout: timerPeriod, repeat: false, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updatePresence(isOnline)
        }, queue: self.queue)
        self.onlineTimer = timer
        timer.start()
        if isOnline {
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(next: { [weak self] result in
            guard let self, !isOnline, case .boolTrue = result, let timestamp = self.pendingOfflineTransitionTimestamp else {
                return
            }
            self.pendingOfflineTransitionTimestamp = nil
            self.lastSeenUpdateDisposable.set(updateAyuGramSettings(postbox: self.postbox) { settings in
                guard timestamp > settings.ghostLastSeenTimestamp else {
                    return settings
                }
                var settings = settings
                settings.ghostLastSeenTimestamp = timestamp
                return settings
            }.start())
        }, completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, postbox: Postbox) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network, postbox: postbox)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
