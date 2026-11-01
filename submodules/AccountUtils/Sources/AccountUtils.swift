import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext

public let maximumNumberOfAccounts = 3
public let maximumPremiumNumberOfAccounts = 4

public func activeAccountsAndPeers(context: AccountContext, includePrimary: Bool = false) -> Signal<((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]), NoError> {
    let sharedContext = context.sharedContext
    return context.sharedContext.activeAccountContexts
    |> mapToSignal { primary, activeAccounts, _ -> Signal<((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]), NoError> in
        var accounts: [Signal<(AccountContext, EnginePeer, Int32)?, NoError>] = []
        func accountWithPeer(_ context: AccountContext) -> Signal<(AccountContext, EnginePeer, Int32)?, NoError> {
            return combineLatest(context.account.postbox.peerView(id: context.account.peerId), renderedTotalUnreadCount(accountManager: sharedContext.accountManager, engine: context.engine))
            |> map { view, totalUnreadCount -> (EnginePeer?, Int32) in
                return (view.peers[view.peerId].flatMap(EnginePeer.init), totalUnreadCount.0)
            }
            |> distinctUntilChanged { lhs, rhs in
                if lhs.0 != rhs.0 {
                    return false
                }
                if lhs.1 != rhs.1 {
                    return false
                }
                return true
            }
            |> map { peer, totalUnreadCount -> (AccountContext, EnginePeer, Int32)? in
                if let peer = peer {
                    return (context, peer, totalUnreadCount)
                } else {
                    // Shadow 2.2.4: an account restored from a session backup starts with an empty
                    // postbox. Dropping it here kept a running account out of every list (and a logout
                    // could switch to it unseen); show it under a placeholder until its own user arrives.
                    return (context, shadowPlaceholderAccountPeer(id: context.account.peerId), totalUnreadCount)
                }
            }
        }
        for (_, context, _) in activeAccounts {
            accounts.append(accountWithPeer(context))
        }
        
        return combineLatest(accounts)
        |> map { accounts -> ((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]) in
            var primaryRecord: (AccountContext, EnginePeer)?
            if let first = accounts.filter({ $0?.0.account.id == primary?.account.id }).first, let (account, peer, _) = first {
                primaryRecord = (account, peer)
            }
            let accountRecords: [(AccountContext, EnginePeer, Int32)] = (includePrimary ? accounts : accounts.filter({ $0?.0.account.id != primary?.account.id })).compactMap({ $0 })
            return (primaryRecord, accountRecords)
        }
    }
}

private func shadowPlaceholderAccountPeer(id: EnginePeer.Id) -> EnginePeer {
    return .user(TelegramUser(id: id, accessHash: nil, firstName: "Аккаунт \(id.id._internalGetInt64Value())", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
}
