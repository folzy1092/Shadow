import Foundation

// Shadow: the fork's own version, independent of the Telegram base version.
// The full version shown to users is "<telegram>-<fork>", e.g. 12.9.2-1.0.0.
//
// `fork` here is the source of truth for the app. CI reads the same number from
// versions.json ("fork") for the release title; a contract test keeps the two
// in sync.
public enum ShadowVersion {
    public static let fork = "1.11.0"

    // Telegram base version from the bundle (CFBundleShortVersionString).
    public static var telegram: String {
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    // "12.9.2-1.0.0" — what the hub and the update card show.
    public static var full: String {
        return "\(telegram)-\(fork)"
    }
}
