import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

// Shadow 2.2.4: an account restored from a session backup starts with an empty postbox,
// and nothing on launch writes the account's own user into it. Lists that need that user
// either dropped the account (it ran invisibly) or showed a placeholder. Fetch it once when
// it is missing, the same request `refreshAccountPeer` makes after a photo change.
public func shadowFetchSelfUserIfMissing(account: Account) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Bool in
        return transaction.getPeer(account.peerId) == nil
    }
    |> mapToSignal { isMissing -> Signal<Void, NoError> in
        if !isMissing {
            return .complete()
        }
        Logger.shared.log("ShadowSessionBackup", "own user of peer \(account.peerId.id._internalGetInt64Value()) is missing, fetching it")
        return account.network.request(Api.functions.users.getUsers(id: [.inputUserSelf]))
        |> `catch` { _ -> Signal<[Api.User], NoError> in
            return .single([])
        }
        |> mapToSignal { users -> Signal<Void, NoError> in
            if users.isEmpty {
                return .complete()
            }
            return account.postbox.transaction { transaction -> Void in
                updatePeers(transaction: transaction, accountPeerId: account.peerId, peers: AccumulatedPeers(users: users))
            }
        }
    }
}
