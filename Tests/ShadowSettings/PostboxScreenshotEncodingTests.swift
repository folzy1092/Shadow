import Foundation

// Run against the repository's real Coding.swift and AdaptedPostbox codecs.
// This envelope exercises unconditional nested settings encoding, but is not a
// replacement for an on-device AyuGramSettings transaction/account-switch test.
private struct SettingsEnvelope: Codable, Equatable {
    var messageScreenshot = ShadowMessageScreenshotSettings()
    var ghostMode: Int32 = 0
    var preferUsernameForNonContacts: Int32 = 0
    var preferUsernameForBots: Int32 = 0
    var bottomBarScrollMode: Int32 = 0
    var ghostLastSeenTimestamp: Int32 = 0

    enum CodingKeys: String, CodingKey {
        case messageScreenshot, ghostMode, preferUsernameForNonContacts
        case preferUsernameForBots
        case bottomBarScrollMode, ghostLastSeenTimestamp
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.messageScreenshot = try c.decodeIfPresent(ShadowMessageScreenshotSettings.self, forKey: .messageScreenshot) ?? ShadowMessageScreenshotSettings()
        self.ghostMode = try c.decodeIfPresent(Int32.self, forKey: .ghostMode) ?? 0
        self.preferUsernameForNonContacts = try c.decodeIfPresent(Int32.self, forKey: .preferUsernameForNonContacts) ?? 0
        self.preferUsernameForBots = try c.decodeIfPresent(Int32.self, forKey: .preferUsernameForBots) ?? 0
        self.bottomBarScrollMode = try c.decodeIfPresent(Int32.self, forKey: .bottomBarScrollMode) ?? 0
        self.ghostLastSeenTimestamp = try c.decodeIfPresent(Int32.self, forKey: .ghostLastSeenTimestamp) ?? 0
    }
}

private struct LegacyScreenshot: Encodable {
    let background: ShadowMessageScreenshotSettings.Background
}

private struct OldSettings: Encodable {
    let ghostMode: Int32
}

private struct UnknownBackground: Encodable {
    let background: Int32
}

@main struct PostboxScreenshotEncodingTests {
    static func encodedEntry<T: Encodable>(_ value: T) -> Data {
        // The same wrapper/key and codec used by PreferencesEntry.init.
        let encoder = PostboxEncoder()
        encoder.encode(value, forKey: "_")
        return encoder.makeData()
    }

    static func decodedEntry<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        return PostboxDecoder(buffer: MemoryBuffer(data: data)).decode(type, forKey: "_")
    }

    static func main() throws {
        if CommandLine.arguments.contains("--legacy-enum-probe") {
            // Expected to trap in a separate process. If it does not, reassess
            // the regression test against the current codec implementation.
            _ = encodedEntry(LegacyScreenshot(background: .chat))
            return
        }
        for background in ShadowMessageScreenshotSettings.Background.allCases {
            for flags in 0 ..< 64 {
                var options = ShadowMessageScreenshotSettings()
                options.background = background
                options.enabled = flags & 1 != 0
                options.showAvatars = flags & 2 != 0
                options.showNames = flags & 4 != 0
                options.showBadges = flags & 8 != 0
                options.showTime = flags & 16 != 0

                let direct = try AdaptedPostboxEncoder().encode(options)
                let restored = try AdaptedPostboxDecoder().decode(ShadowMessageScreenshotSettings.self, from: direct)
                precondition(restored == options)
                precondition(decodedEntry(ShadowMessageScreenshotSettings.self, encodedEntry(options)) == options)

                var envelope = SettingsEnvelope()
                envelope.messageScreenshot = options
                envelope.ghostMode = Int32((flags >> 5) & 1)
                envelope.preferUsernameForNonContacts = Int32((flags >> 1) & 1)
                envelope.preferUsernameForBots = Int32((flags >> 2) & 1)
                envelope.bottomBarScrollMode = Int32(flags % 3)
                envelope.ghostLastSeenTimestamp = Int32(1_700_000_000 + flags)
                precondition(decodedEntry(SettingsEnvelope.self, encodedEntry(envelope)) == envelope)
            }
        }
        let old = decodedEntry(SettingsEnvelope.self, encodedEntry(OldSettings(ghostMode: 1)))
        precondition(old?.ghostMode == 1)
        precondition(old?.preferUsernameForBots == 0)
        precondition(old?.messageScreenshot == ShadowMessageScreenshotSettings())
        for raw in [Int32(-1), 4, Int32.max] {
            let decoded = decodedEntry(ShadowMessageScreenshotSettings.self, encodedEntry(UnknownBackground(background: raw)))
            precondition(decoded?.background == .chat && decoded?.showAvatars == true)
        }
        print("Real Postbox screenshot encoding, nested settings and migration passed")
    }
}
