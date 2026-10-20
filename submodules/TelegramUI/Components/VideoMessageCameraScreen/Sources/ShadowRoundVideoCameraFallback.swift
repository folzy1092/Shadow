import Foundation

// Shadow: Telegram 13 records round videos with CameraNeo by default. When a
// CameraNeo recording fails on this device, later rounds use the old camera
// (CameraLegacy) until the app is updated, so a broken pipeline costs one
// round instead of every one. A new build retries CameraNeo, since it may
// carry the fix.
enum ShadowRoundVideoCameraFallback {
    private static let failedBuildKey = "shadow.roundVideo.neoFailedBuild"

    private static var currentBuild: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    static var prefersLegacyCamera: Bool {
        guard let failedBuild = UserDefaults.standard.string(forKey: Self.failedBuildKey) else {
            return false
        }
        return failedBuild == Self.currentBuild
    }

    static func noteModernCameraFailure() {
        UserDefaults.standard.set(Self.currentBuild, forKey: Self.failedBuildKey)
    }
}
