import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext

// Shadow: keeps AyuGramSettings identical across the accounts ticked in
// ShadowSettingsSync (Shadow → Синхронизация аккаунтов). Installed once by
// SharedAccountContextImpl in the main app.
//
// It watches the STORED settings of every synced account (never the disguise
// mask). When one account's value changes, that value is written to the others;
// their echo matches what was written and is ignored. The first value of each
// account after (re)subscribing is only recorded: the settings screen already
// copied the current account's settings when sync was turned on.
final class ShadowSettingsSyncManager {
    private static var shared: ShadowSettingsSyncManager?

    private let disposable = MetaDisposable()
    // Main queue only.
    private var known: [Int64: AyuGramSettings] = [:]
    private var members: Set<Int64> = Set()

    static func install(sharedContext: SharedAccountContext) {
        if self.shared != nil {
            return
        }
        let manager = ShadowSettingsSyncManager()
        self.shared = manager
        manager.start(sharedContext: sharedContext)
    }

    private func start(sharedContext: SharedAccountContext) {
        let accounts: Signal<[AccountContext], NoError> = sharedContext.activeAccountContexts
        |> map { _, accounts, _ -> [AccountContext] in
            return accounts.map { $0.1 }
        }
        let values: Signal<[(Int64, AccountContext, AyuGramSettings)], NoError> = combineLatest(accounts, ShadowSettingsSync.signal())
        |> mapToSignal { accounts, ids -> Signal<[(Int64, AccountContext, AyuGramSettings)], NoError> in
            let synced = accounts.filter { ids.contains($0.account.peerId.toInt64()) }
            if synced.count < 2 {
                return .single([])
            }
            let streams: [Signal<(Int64, AccountContext, AyuGramSettings), NoError>] = synced.map { context in
                let peerId = context.account.peerId.toInt64()
                return shadowStoredAyuGramSettings(postbox: context.account.postbox)
                |> map { settings -> (Int64, AccountContext, AyuGramSettings) in
                    return (peerId, context, settings)
                }
            }
            return combineLatest(streams)
        }
        |> deliverOnMainQueue

        self.disposable.set(values.start(next: { [weak self] values in
            self?.process(values)
        }))
    }

    private func process(_ values: [(Int64, AccountContext, AyuGramSettings)]) {
        let members = Set(values.map { $0.0 })
        if members != self.members {
            // A different group: record everyone, propagate nothing.
            self.members = members
            self.known.removeAll()
            for (peerId, _, settings) in values {
                self.known[peerId] = ShadowSettingsSync.syncedValue(settings)
            }
            return
        }

        var source: (Int64, AyuGramSettings)?
        for (peerId, _, settings) in values {
            let synced = ShadowSettingsSync.syncedValue(settings)
            if let previous = self.known[peerId], previous != synced {
                source = (peerId, settings)
            }
            self.known[peerId] = synced
        }
        guard let (sourcePeerId, sourceSettings) = source else {
            return
        }
        let target = ShadowSettingsSync.syncedValue(sourceSettings)
        for (peerId, context, settings) in values where peerId != sourcePeerId {
            if ShadowSettingsSync.syncedValue(settings) != target {
                self.known[peerId] = target
                let _ = shadowApplySyncedAyuGramSettings(sourceSettings, to: context.account.postbox).start()
            }
        }
    }
}
