import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer

// Read the self user's raw API status before Postbox substitutes its permanent
// "own account is online" presence. This read never sends account.updateStatus.
public func shadowOwnServerPresence(account: Account) -> Signal<ShadowOwnServerPresence, NoError> {
    let result: Signal<ShadowOwnServerPresence, MTRpcError> = account.network.request(Api.functions.users.getUsers(id: [.inputUserSelf]))
    |> map { (users: [Api.User]) -> ShadowOwnServerPresence in
        guard let user = users.first, case let .user(data) = user, let status = data.status else {
            return .unavailable
        }
        switch status {
        case let .userStatusOffline(data): return .offline(wasOnline: data.wasOnline)
        case let .userStatusOnline(data): return .online(expires: data.expires)
        case .userStatusRecently: return .recently
        case .userStatusLastWeek: return .lastWeek
        case .userStatusLastMonth: return .lastMonth
        case .userStatusEmpty: return .unavailable
        }
    }
    return result
    |> `catch` { _ -> Signal<ShadowOwnServerPresence, NoError> in
        return .single(.unavailable)
    }
    |> timeout(10.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(.unavailable))
}

private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)

    private var shouldKeepOnlinePresenceDisposable: Disposable?
    // Shadow fork: subscription to the "re-assert offline now" trigger fired
    // right after a send while "send without appearing online" is on.
    private var offlineReassertDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    // AyuGram: start as "unknown" (nil) so the very first value — including a
    // `false` when online is hidden from launch — actually triggers updatePresence
    // and arms the re-assert timer. Previously an initial `false == false` was
    // skipped, so the aggressive "stay offline" never started for a boot-hidden
    // account and reading a chat could leave you online.
    private var wasOnline: Bool? = nil

    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        self.queue = queue
        self.network = network
        
        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            let previousValue = self.wasOnline
            if previousValue != value {
                self.wasOnline = value
                self.updatePresence(value)
            }
        })

        // Shadow fork: when a send fires the offline re-assert trigger, and we
        // are currently meant to be hidden/offline, re-send "offline" right away
        // (bypassing the 30s timer and the same-value `wasOnline` guard) so the
        // brief server-side online blip from the send RPC is cleared immediately.
        self.offlineReassertDisposable = (ayuOfflineReassertPipe.signal()
        |> deliverOn(self.queue)).start(next: { [weak self] network in
            guard let self, self.network === network else {
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
        self.onlineTimer?.invalidate()
    }
    
    private func updatePresence(_ isOnline: Bool) {
        let request: Signal<Api.Bool, MTRpcError>
        self.onlineTimer?.invalidate()
        // Keep-alive is only needed while advertising online presence. Repeating
        // updateStatus(offline) in Ghost Mode sends a request every five seconds
        // and can itself refresh the authorization's activity timestamp shown in
        // Devices. The transition to offline and the post-send reassert above
        // still send an explicit offline request when needed.
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                self?.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
        } else {
            self.onlineTimer = nil
        }
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
        |> deliverOn(self.queue)).start(completed: { [weak self] in
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
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network)
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
