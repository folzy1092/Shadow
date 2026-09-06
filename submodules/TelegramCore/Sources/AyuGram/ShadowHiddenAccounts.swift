import Foundation
import Postbox
import SwiftSignalKit

/// Device-local visibility for authorized accounts.
///
/// Hidden accounts stay authorized and continue receiving updates. The flag only
/// removes them from Shadow's account switcher and can always be changed from
/// Shadow settings. Telegram user ids are used instead of AccountRecordId values
/// so the choice remains stable when the account records are rebuilt.
public enum ShadowHiddenAccounts {
    private static let defaultsKey = "shadow.hiddenAccountPeerIds.v1"
    private static let value = ValuePromise<Set<Int64>>(ShadowHiddenAccounts.loadIds(), ignoreRepeated: true)

    private static func loadIds() -> Set<Int64> {
        let values = UserDefaults.standard.stringArray(forKey: self.defaultsKey) ?? []
        return Set(values.compactMap(Int64.init))
    }

    public static func ids() -> Set<Int64> {
        return self.loadIds()
    }

    public static func signal() -> Signal<Set<Int64>, NoError> {
        return self.value.get()
    }

    public static func contains(_ peerId: PeerId) -> Bool {
        return self.ids().contains(peerId.toInt64())
    }

    public static func setHidden(_ hidden: Bool, peerId: PeerId) {
        var values = self.ids()
        if hidden {
            values.insert(peerId.toInt64())
        } else {
            values.remove(peerId.toInt64())
        }
        UserDefaults.standard.set(values.sorted().map(String.init), forKey: self.defaultsKey)
        self.value.set(values)
    }
}
