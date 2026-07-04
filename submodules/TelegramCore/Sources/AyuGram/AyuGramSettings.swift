import Foundation
import Postbox
import SwiftSignalKit

// AyuGram fork settings. Kept in a single, self-contained file so it can be
// re-applied on top of upstream with minimal merge friction. The preferences
// key uses a deliberately high raw value (well above upstream's range) to avoid
// colliding with keys that upstream may add over time.
public extension PreferencesKeys {
    static let ayuGramSettings: ValueBoxKey = {
        let key = ValueBoxKey(length: 4)
        key.setInt32(0, value: 1000)
        return key
    }()
}

public struct AyuGramSettings: Codable, Equatable {
    // Anti-deletion
    public var keepDeletedMessages: Bool
    public var saveEditHistory: Bool
    // Presence hiding
    public var hideOnlineStatus: Bool
    public var hideTyping: Bool

    public static var defaultSettings: AyuGramSettings {
        return AyuGramSettings(
            keepDeletedMessages: true,
            saveEditHistory: true,
            hideOnlineStatus: false,
            hideTyping: false
        )
    }

    public init(keepDeletedMessages: Bool, saveEditHistory: Bool, hideOnlineStatus: Bool, hideTyping: Bool) {
        self.keepDeletedMessages = keepDeletedMessages
        self.saveEditHistory = saveEditHistory
        self.hideOnlineStatus = hideOnlineStatus
        self.hideTyping = hideTyping
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.keepDeletedMessages = ((try container.decodeIfPresent(Int32.self, forKey: "keepDeletedMessages")) ?? 1) != 0
        self.saveEditHistory = ((try container.decodeIfPresent(Int32.self, forKey: "saveEditHistory")) ?? 1) != 0
        self.hideOnlineStatus = ((try container.decodeIfPresent(Int32.self, forKey: "hideOnlineStatus")) ?? 0) != 0
        self.hideTyping = ((try container.decodeIfPresent(Int32.self, forKey: "hideTyping")) ?? 0) != 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode((self.keepDeletedMessages ? 1 : 0) as Int32, forKey: "keepDeletedMessages")
        try container.encode((self.saveEditHistory ? 1 : 0) as Int32, forKey: "saveEditHistory")
        try container.encode((self.hideOnlineStatus ? 1 : 0) as Int32, forKey: "hideOnlineStatus")
        try container.encode((self.hideTyping ? 1 : 0) as Int32, forKey: "hideTyping")
    }
}

// Synchronous read inside a Postbox transaction — used by the low-level
// interception points (presence, typing, delete handling).
public func currentAyuGramSettings(transaction: Transaction) -> AyuGramSettings {
    if let entry = transaction.getPreferencesEntry(key: PreferencesKeys.ayuGramSettings)?.get(AyuGramSettings.self) {
        return entry
    } else {
        return AyuGramSettings.defaultSettings
    }
}

public func updateAyuGramSettings(transaction: Transaction, _ f: (AyuGramSettings) -> AyuGramSettings) {
    let current = currentAyuGramSettings(transaction: transaction)
    let updated = f(current)
    if updated != current {
        transaction.setPreferencesEntry(key: PreferencesKeys.ayuGramSettings, value: PreferencesEntry(updated))
    }
}

public func updateAyuGramSettings(postbox: Postbox, _ f: @escaping (AyuGramSettings) -> AyuGramSettings) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Void in
        updateAyuGramSettings(transaction: transaction, f)
    }
    |> ignoreValues
}

// Reactive stream — used by the UI (settings screen) and the presence wiring.
public func ayuGramSettings(postbox: Postbox) -> Signal<AyuGramSettings, NoError> {
    return postbox.preferencesView(keys: [PreferencesKeys.ayuGramSettings])
    |> map { view -> AyuGramSettings in
        return view.values[PreferencesKeys.ayuGramSettings]?.get(AyuGramSettings.self) ?? AyuGramSettings.defaultSettings
    }
}
