import Foundation

// Shadow: Telegram 13 records round videos with CameraNeo by default. When a
// CameraNeo recording fails on this device, or the app died while a CameraNeo
// screen was open (a freeze the user had to kill), later rounds use the old
// camera (CameraLegacy) until the app is updated, so a broken pipeline costs
// one round instead of every one. A new build retries CameraNeo, since it may
// carry the fix.
enum ShadowRoundVideoCameraFallback {
    private static let failedBuildKey = "shadow.roundVideo.neoFailedBuild"
    // "<build>|<launch>" while a CameraNeo screen is open.
    private static let openSessionKey = "shadow.roundVideo.neoOpenSession"
    private static let launchId = UUID().uuidString

    private static var currentBuild: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    static var prefersLegacyCamera: Bool {
        let defaults = UserDefaults.standard
        // A mark from an earlier launch of this build: that launch ended with a
        // CameraNeo screen still open.
        if let open = defaults.string(forKey: Self.openSessionKey) {
            let parts = open.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[1] != Self.launchId {
                defaults.removeObject(forKey: Self.openSessionKey)
                if parts[0] == Self.currentBuild {
                    Self.noteModernCameraFailure()
                }
            }
        }
        guard let failedBuild = defaults.string(forKey: Self.failedBuildKey) else {
            return false
        }
        return failedBuild == Self.currentBuild
    }

    static func noteModernCameraFailure() {
        UserDefaults.standard.set(Self.currentBuild, forKey: Self.failedBuildKey)
    }

    static func beginModernSession() {
        UserDefaults.standard.set("\(Self.currentBuild)|\(Self.launchId)", forKey: Self.openSessionKey)
    }

    // Called a moment after the screen is gone, from the main queue: a frozen
    // main thread never gets here, so the mark survives a freeze.
    static func endModernSession() {
        UserDefaults.standard.removeObject(forKey: Self.openSessionKey)
    }
}
