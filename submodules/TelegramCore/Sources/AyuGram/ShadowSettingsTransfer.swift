import Foundation
import Postbox
import SwiftSignalKit

private let shadowSettingsBackupKey: ValueBoxKey = {
    // Eight bytes ("SHADOWBK"), separate from the four-byte preference registry.
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: 0x534841444f57424b)
    return key
}()

private struct ShadowSettingsBackup: Codable {
    let settings: AyuGramSettings
}

// Apply a reviewed allowlist to the existing account snapshot. Missing keys and
// local-only fields stay unchanged; an older export never resets newer options.
public enum ShadowSettingsTransfer {
    private static let booleanFields: [String: WritableKeyPath<AyuGramSettings, Bool>] = [
        "keepDeletedMessages": \.keepDeletedMessages,
        "saveEditHistory": \.saveEditHistory,
        "keepSelfDestructMedia": \.keepSelfDestructMedia,
        "ghostMode": \.ghostMode,
        "hideOnlineStatus": \.hideOnlineStatus,
        "hideTyping": \.hideTyping,
        "hideReadReceipts": \.hideReadReceipts,
        "hideStoryViews": \.hideStoryViews,
        "askBeforeStoryView": \.askBeforeStoryView,
        "sendViaScheduled": \.sendViaScheduled,
        "sendWithoutOnline": \.sendWithoutOnline,
        "showMessageSeconds": \.showMessageSeconds,
        "editedIndicatorAsPencil": \.editedIndicatorAsPencil,
        "regularEmojiFirst": \.regularEmojiFirst,
        "doubleTapToEdit": \.doubleTapToEdit,
        "showExactLastSeen": \.showExactLastSeen,
        "showExactLastSeenSeconds": \.showExactLastSeenSeconds,
        "wideChannelPosts": \.wideChannelPosts,
        "preferUsernameForNonContacts": \.preferUsernameForNonContacts,
        "showExactViewCounts": \.showExactViewCounts,
        "showForwardCount": \.showForwardCount,
        "hideAllChatsFolder": \.hideAllChatsFolder,
        "foldersAtBottom": \.foldersAtBottom,
        "hideBottomSearch": \.hideBottomSearch,
        "compactBottomBar": \.compactBottomBar,
        "allowSaveRestrictedContent": \.allowSaveRestrictedContent,
        "roundVideoUseBackCamera": \.roundVideoUseBackCamera,
        "showCameraTile": \.showCameraTile,
        "cameraTileLivePreview": \.cameraTileLivePreview,
        "confirmCalls": \.confirmCalls,
        "saveDestructingMedia": \.saveDestructingMedia,
        "saveAllIncomingMedia": \.saveAllIncomingMedia,
        "mediaAutoCleanKeepPinned": \.mediaAutoCleanKeepPinned,
        "mediaAutoCleanKeepChannels": \.mediaAutoCleanKeepChannels,
        "mediaAutoCleanKeepBots": \.mediaAutoCleanKeepBots,
        "showProfileId": \.showProfileId,
        "showProfileDC": \.showProfileDC,
        "showRegistrationDate": \.showRegistrationDate,
        "hideOwnPhoneNumber": \.hideOwnPhoneNumber,
        "screenshotEnabled": \.messageScreenshot.enabled,
        "screenshotAvatars": \.messageScreenshot.showAvatars,
        "screenshotNames": \.messageScreenshot.showNames,
        "screenshotBadges": \.messageScreenshot.showBadges,
        "screenshotTime": \.messageScreenshot.showTime
    ]

    public static func document(from settings: AyuGramSettings) throws -> ShadowSettingsDocument {
        var values: [String: ShadowSettingValue] = [:]
        for (key, path) in self.booleanFields {
            values[key] = .bool(settings[keyPath: path])
        }
        values["editedIndicatorText"] = .text(settings.editedIndicatorText)
        values["deletedIndicatorText"] = .text(settings.deletedIndicatorText)
        values["mediaAutoCleanInterval"] = .integer(Int64(settings.mediaAutoCleanInterval))
        values["attachmentSizeLimit"] = .integer(settings.attachmentSizeLimit)
        values["bottomBarScrollMode"] = .integer(Int64(settings.bottomBarScrollMode))
        values["screenshotBackground"] = .integer(Int64(settings.messageScreenshot.background.rawValue))
        return try ShadowSettingsDocument(settings: values)
    }

    public static func applying(_ document: ShadowSettingsDocument, to current: AyuGramSettings) -> AyuGramSettings {
        var updated = current
        for (key, value) in document.settings {
            switch value {
            case let .bool(flag):
                if let path = self.booleanFields[key] {
                    updated[keyPath: path] = flag
                }
            case let .text(text):
                switch key {
                case "editedIndicatorText": updated.editedIndicatorText = text
                case "deletedIndicatorText": updated.deletedIndicatorText = text
                default: break
                }
            case let .integer(number):
                switch key {
                case "mediaAutoCleanInterval": updated.mediaAutoCleanInterval = Int32(number)
                case "attachmentSizeLimit": updated.attachmentSizeLimit = number
                case "bottomBarScrollMode": updated.bottomBarScrollMode = Int32(number)
                case "screenshotBackground": updated.messageScreenshot.background = ShadowMessageScreenshotSettings.Background(rawValue: Int32(number)) ?? .chat
                default: break
                }
            }
        }
        return updated
    }

    public static func changedKeys(_ document: ShadowSettingsDocument, from current: AyuGramSettings) throws -> [String] {
        let existing = try self.document(from: current)
        return document.settings.keys.filter { existing.settings[$0] != document.settings[$0] }.sorted()
    }
}

public enum ShadowSettingsImportResult {
    case applied
    case unchanged
    case settingsChanged
    case noBackup
}

public func shadowSettingsBackupAvailable(postbox: Postbox) -> Signal<Bool, NoError> {
    return postbox.preferencesView(keys: [shadowSettingsBackupKey])
    |> map { view in
        return view.values[shadowSettingsBackupKey]?.get(ShadowSettingsBackup.self) != nil
    }
    |> distinctUntilChanged
}

public func importShadowSettings(postbox: Postbox, document: ShadowSettingsDocument, expected: AyuGramSettings) -> Signal<ShadowSettingsImportResult, NoError> {
    return postbox.transaction { transaction -> ShadowSettingsImportResult in
        let current = currentAyuGramSettings(transaction: transaction)
        // A setting changed after preview. Do not silently apply a stale plan.
        guard current == expected else { return .settingsChanged }
        let updated = ShadowSettingsTransfer.applying(document, to: current)
        guard updated != current else { return .unchanged }
        // Snapshot and replacement commit atomically in the same account DB.
        transaction.setPreferencesEntry(key: shadowSettingsBackupKey, value: PreferencesEntry(ShadowSettingsBackup(settings: current)))
        updateAyuGramSettings(transaction: transaction) { _ in updated }
        return .applied
    }
}

public func restoreShadowSettingsBackup(postbox: Postbox) -> Signal<ShadowSettingsImportResult, NoError> {
    return postbox.transaction { transaction -> ShadowSettingsImportResult in
        guard let backup = transaction.getPreferencesEntry(key: shadowSettingsBackupKey)?.get(ShadowSettingsBackup.self) else {
            return .noBackup
        }
        updateAyuGramSettings(transaction: transaction) { _ in backup.settings }
        transaction.setPreferencesEntry(key: shadowSettingsBackupKey, value: nil)
        return .applied
    }
}
