import Foundation

// Shadow: reading and changing settings toggles by key for settings links
// (ShadowSettingLinks): the long-press menu, shadow://…?on|off|switch and
// header buttons. Keys are the export allowlist's (ShadowSettingsTransfer)
// plus a few local-only toggles that are never exported.
extension ShadowSettingsTransfer {
    // Shadow: toggles reachable by settings links (ShadowSettingLinks) that are
    // not part of the export allowlist above. Never exported or imported.
    private static let linkOnlyBooleanFields: [String: WritableKeyPath<AyuGramSettings, Bool>] = [
        "customBannerEnabled": \.customBannerEnabled,
        "customProfileBackgroundEnabled": \.customProfileBackgroundEnabled,
        "customProfileBackgroundForOthers": \.customProfileBackgroundForOthers,
        "customProfileBackgroundForSettings": \.customProfileBackgroundForSettings,
        "spoofProfileIdEnabled": \.spoofProfileIdEnabled,
        "spoofProfileDcEnabled": \.spoofProfileDcEnabled,
        "spoofProfilePhoneEnabled": \.spoofProfilePhoneEnabled,
        "screenshotReactions": \.messageScreenshot.showReactions,
        "screenshotOwnName": \.messageScreenshot.showOwnName,
        "screenshotPeerNames": \.messageScreenshot.showPeerNames,
        "screenshotOwnAvatar": \.messageScreenshot.showOwnAvatar,
        "screenshotPeerAvatars": \.messageScreenshot.showPeerAvatars
    ]

    // Settings with a choice of values (ShadowSettingLink.choices), set by
    // shadow://…?value=N. Exported through the integer keys of the document.
    private static let choiceFields: [String: WritableKeyPath<AyuGramSettings, Int32>] = [
        "voiceTimeFormat": \.voiceTimeFormat,
        "replyTimecodeMode": \.replyTimecodeMode,
        "bottomBarScrollMode": \.bottomBarScrollMode,
        "feedPosition": \.feedPosition
    ]

    public static func intValue(_ key: String, in settings: AyuGramSettings) -> Int32? {
        guard let path = self.choiceFields[key] else {
            return nil
        }
        return settings[keyPath: path]
    }

    @discardableResult
    public static func setInt(_ key: String, _ value: Int32, in settings: inout AyuGramSettings) -> Bool {
        guard let path = self.choiceFields[key] else {
            return false
        }
        settings[keyPath: path] = value
        return true
    }

    private static func booleanPath(_ key: String) -> WritableKeyPath<AyuGramSettings, Bool>? {
        return self.exportBooleanPath(key) ?? self.linkOnlyBooleanFields[key]
    }

    public static func boolValue(_ key: String, in settings: AyuGramSettings) -> Bool? {
        guard let path = self.booleanPath(key) else {
            return nil
        }
        return settings[keyPath: path]
    }

    // Settings links: sets one toggle. The Ghost master switch made by hand
    // also pins the per-account mode to manual, like the Ghost screen does.
    @discardableResult
    public static func setBool(_ key: String, _ value: Bool, in settings: inout AyuGramSettings) -> Bool {
        guard let path = self.booleanPath(key) else {
            return false
        }
        settings[keyPath: path] = value
        if key == "ghostMode" {
            settings.ghostAccountMode = .manual
        }
        return true
    }

    // Applies several settings links at once. `.toggle` items share one target
    // (ShadowSettingLinks.groupTarget): all on → all off, otherwise all on.
    // `.value` items set their choice. Returns the toggles' new values in the
    // same order.
    public static func applying(links: [(ShadowSettingLink, ShadowSettingLinks.Mode)], to current: AyuGramSettings) -> (AyuGramSettings, [Bool]) {
        var updated = current
        for (link, mode) in links {
            if case let .value(value) = mode, link.isChoice, let key = link.key, link.choiceTitle(value) != nil {
                self.setInt(key, value, in: &updated)
            }
        }
        let switchable = links.filter { item in
            guard item.0.isSwitchable else {
                return false
            }
            switch item.1 {
            case .on, .off, .toggle: return true
            case .open, .value: return false
            }
        }
        let toggled = switchable.filter { $0.1 == .toggle }.compactMap { item -> Bool? in
            guard let key = item.0.key else {
                return nil
            }
            return self.boolValue(key, in: current)
        }
        let groupValue = ShadowSettingLinks.groupTarget(currentValues: toggled)
        var values: [Bool] = []
        for (link, mode) in switchable {
            guard let key = link.key else {
                continue
            }
            let value: Bool
            switch mode {
            case .on: value = true
            case .off: value = false
            case .toggle: value = groupValue
            case .open, .value: continue
            }
            if self.setBool(key, value, in: &updated) {
                values.append(value)
            }
        }
        return (updated, values)
    }

}
