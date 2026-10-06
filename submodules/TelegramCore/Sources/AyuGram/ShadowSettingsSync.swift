import Foundation
import SwiftSignalKit

// Shadow: Shadow settings shared between accounts.
//
// The user ticks accounts in Shadow → Синхронизация аккаунтов. All ticked
// accounts keep identical AyuGramSettings: turning sync on copies the current
// account's settings to every ticked account, after that a change on any of
// them is copied to the others (ShadowSettingsSyncManager in TelegramUI).
//
// The list is device-local and keyed by Telegram user ids (like
// ShadowHiddenAccounts), so it survives rebuilt account records. Hidden
// accounts take part like any other.
//
// Everything in AyuGramSettings is synced except per-account runtime state that
// is not a setting: `ghostLastSeenTimestamp` (when THIS account was last seen
// going offline).
public enum ShadowSettingsSync {
    private static let defaultsKey = "shadow.settingsSyncPeerIds.v1"
    private static let value = ValuePromise<Set<Int64>>(ShadowSettingsSync.storedIds(), ignoreRepeated: true)

    private static func storedIds() -> Set<Int64> {
        let values = UserDefaults.standard.stringArray(forKey: self.defaultsKey) ?? []
        return Set(values.compactMap(Int64.init))
    }

    public static func ids() -> Set<Int64> {
        return self.storedIds()
    }

    public static func signal() -> Signal<Set<Int64>, NoError> {
        return self.value.get()
    }

    public static func setIds(_ ids: Set<Int64>) {
        UserDefaults.standard.set(ids.sorted().map(String.init), forKey: self.defaultsKey)
        self.value.set(ids)
    }

    // Also copy the chat-list banner and the profile background images
    // (AyuSavedMedia). On unless the user turns it off.
    private static let bannersKey = "shadow.settingsSyncBanners.v1"
    private static let bannersValue = ValuePromise<Bool>(ShadowSettingsSync.storedSyncBanners(), ignoreRepeated: true)

    private static func storedSyncBanners() -> Bool {
        return (UserDefaults.standard.object(forKey: self.bannersKey) as? Bool) ?? true
    }

    public static var syncBanners: Bool {
        return self.storedSyncBanners()
    }

    public static func syncBannersSignal() -> Signal<Bool, NoError> {
        return self.bannersValue.get()
    }

    public static func setSyncBanners(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: self.bannersKey)
        self.bannersValue.set(value)
    }

    // The part of the settings that is compared between accounts.
    public static func syncedValue(_ settings: AyuGramSettings) -> AyuGramSettings {
        var result = settings
        result.ghostLastSeenTimestamp = 0
        return result
    }

    // `source` with `target`'s own runtime state.
    public static func applying(_ source: AyuGramSettings, to target: AyuGramSettings) -> AyuGramSettings {
        var result = source
        result.ghostLastSeenTimestamp = target.ghostLastSeenTimestamp
        return result
    }
}
