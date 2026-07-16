import Foundation

// AyuGram fork: the client "fingerprint" reported to Telegram in `initConnection`
// (shown in Settings → Devices, and used by anti-spam heuristics).
//
// IMPORTANT — read before relying on this:
//   * These strings only DISPLAY the client; they do not cryptographically prove
//     a platform. On their own they barely change the odds of an account being
//     frozen. The dominant factors are the phone number, behavior, IP, and the
//     `api_id` — NOT device_model.
//   * The point of this file is CONSISTENCY: if you spoof, spoof the whole
//     fingerprint together (done below), never just one field — a mismatched
//     desktop/mobile fingerprint looks MORE suspicious, not less.
//   * The real "trusted client" lever is the `api_id`. Official Telegram Desktop
//     uses api_id 2040. Using someone else's api_id violates Telegram's ToS and
//     can itself get flagged, so it is intentionally NOT set here — that choice
//     is left to you, in your build configuration (`--configurationPath`).
//
// The fingerprint is fixed at session creation (login), so this is a build-time
// constant rather than a runtime toggle. It applies to every account added in
// this build.
//
// `systemLangCode` is deliberately NOT part of this profile. Unlike the fields
// below (which are cosmetic display strings with no functional effect on the
// client), `system_lang_code` is what the server uses to decide
// `suggestedLangCode` in Config (and drives the "Continue in <language>"
// onboarding prompt / auto-detection of the device's language). Hardcoding it
// breaks Telegram's own language auto-detection for this device regardless of
// the user's actual iOS language — so it must keep reflecting the real system
// locale (MTApiEnvironment already derives it from the device by default).
public enum AyuGramClientProfile {
    // Disabled: report the genuine iOS client. Even with `systemLangCode` no
    // longer overridden, this fingerprint spoof was the only variable still
    // separating this build's session/network setup from stock — turning it
    // off removes it entirely as a suspect while the interface-language bug
    // is investigated further.
    public static let spoofDesktopWindows: Bool = false

    // A plausible, internally-consistent Telegram Desktop / Windows fingerprint.
    public static let deviceModel: String = "Desktop"
    public static let systemVersion: String = "Windows 10"
    public static let appVersion: String = "5.10.3 x64"
    public static let langPack: String = "tdesktop"
}
