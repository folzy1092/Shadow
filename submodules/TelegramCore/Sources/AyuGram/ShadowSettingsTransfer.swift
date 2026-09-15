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
        "keepDeletedSecretChatMessages": \.keepDeletedSecretChatMessages,
        "saveEditHistory": \.saveEditHistory,
        "showEditComparisonAction": \.showEditComparisonAction,
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
        "preferUsernameForBots": \.preferUsernameForBots,
        "showExactViewCounts": \.showExactViewCounts,
        "showForwardCount": \.showForwardCount,
        "hideAllChatsFolder": \.hideAllChatsFolder,
        "disableStoryCameraSwipe": \.disableStoryCameraSwipe,
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
        "screenshotTime": \.messageScreenshot.showTime,
        "screenshotOwnName": \.messageScreenshot.showOwnName,
        "screenshotPeerNames": \.messageScreenshot.showPeerNames,
        "screenshotOwnAvatar": \.messageScreenshot.showOwnAvatar,
        "screenshotPeerAvatars": \.messageScreenshot.showPeerAvatars
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
        values["screenshotCustomColorARGB"] = .integer(Int64(settings.messageScreenshot.customColorARGB))
        return try ShadowSettingsDocument(settings: values)
    }

    public static func applying(_ document: ShadowSettingsDocument, to current: AyuGramSettings) -> AyuGramSettings {
        var updated = current

        // Handle screenshot appearance after the generic loop. Dictionary
        // iteration order must not decide whether raw background 2 means old
        // white or the new customColor representation.
        var screenshotBackgroundRaw: Int32?
        var screenshotCustomColorARGB: Int32?

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
                case "screenshotBackground": screenshotBackgroundRaw = Int32(number)
                case "screenshotCustomColorARGB": screenshotCustomColorARGB = Int32(number)
                default: break
                }
            }
        }

        if let rawBackground = screenshotBackgroundRaw {
            switch rawBackground {
            case 2:
                updated.messageScreenshot.background = .customColor
                if let screenshotCustomColorARGB {
                    // New export: raw 2 + explicit color.
                    updated.messageScreenshot.customColorARGB = screenshotCustomColorARGB
                } else {
                    // Legacy export: raw 2 = white.
                    updated.messageScreenshot.customColorARGB = ShadowMessageScreenshotSettings.legacyWhiteARGB
                }
            case 3:
                // Legacy export: raw 3 = black.
                updated.messageScreenshot.background = .customColor
                updated.messageScreenshot.customColorARGB = ShadowMessageScreenshotSettings.legacyBlackARGB
            default:
                updated.messageScreenshot.background = ShadowMessageScreenshotSettings.Background(rawValue: rawBackground) ?? .chat
                if let screenshotCustomColorARGB {
                    updated.messageScreenshot.customColorARGB = screenshotCustomColorARGB
                }
            }
        } else if let screenshotCustomColorARGB {
            // A partial/newer document may carry only the color value.
            updated.messageScreenshot.customColorARGB = screenshotCustomColorARGB
        }

        return updated
    }

    public static func changedKeys(_ document: ShadowSettingsDocument, from current: AyuGramSettings) throws -> [String] {
        let existing = try self.document(from: current)
        var changed = document.settings.keys.filter { existing.settings[$0] != document.settings[$0] }

        // Raw value 2 is ambiguous across versions. Compare the semantic result
        // too, otherwise an old white export may look identical to a new
        // customColor=2 setting even when applying it changes the color.
        let applied = self.applying(document, to: current)
        let screenshotAppearanceChanged = applied.messageScreenshot.background != current.messageScreenshot.background
            || applied.messageScreenshot.customColorARGB != current.messageScreenshot.customColorARGB
        if screenshotAppearanceChanged
            && !changed.contains("screenshotBackground")
            && !changed.contains("screenshotCustomColorARGB") {
            changed.append("screenshotBackground")
        }

        return changed.sorted()
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
        updateAyuGramSettings(transaction: transaction) { current in
            // Presence telemetry belongs to the account service state and must
            // never move backwards when a user restores an older UI snapshot.
            var restored = backup.settings
            restored.ghostLastSeenTimestamp = max(current.ghostLastSeenTimestamp, restored.ghostLastSeenTimestamp)
            return restored
        }
        transaction.setPreferencesEntry(key: shadowSettingsBackupKey, value: nil)
        return .applied
    }
}
