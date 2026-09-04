import Foundation

@main
struct MessageScreenshotTests {
    static func main() throws {
        let defaults = try JSONDecoder().decode(
            ShadowMessageScreenshotSettings.self,
            from: Data("{}".utf8)
        )

        precondition(defaults.enabled && defaults.showAvatars && defaults.showNames && defaults.showBadges && defaults.showTime)
        precondition(defaults.background == .chat)
        precondition(defaults.customColorARGB == ShadowMessageScreenshotSettings.legacyBlackARGB)
        precondition(ShadowMessageScreenshotSettings.Background.allCases.count == 3)

        // Legacy raw 2 without a color field meant white.
        let legacyWhite = try JSONDecoder().decode(
            ShadowMessageScreenshotSettings.self,
            from: Data("{\"background\":2}".utf8)
        )
        precondition(legacyWhite.background == .customColor)
        precondition(legacyWhite.customColorARGB == ShadowMessageScreenshotSettings.legacyWhiteARGB)

        // Legacy raw 3 meant black.
        let legacyBlack = try JSONDecoder().decode(
            ShadowMessageScreenshotSettings.self,
            from: Data("{\"background\":3}".utf8)
        )
        precondition(legacyBlack.background == .customColor)
        precondition(legacyBlack.customColorARGB == ShadowMessageScreenshotSettings.legacyBlackARGB)

        // New raw 2 is distinguished by explicit customColorARGB.
        let customARGB = Int32(bitPattern: 0xFF12AB34)
        let newFormatJSON = "{\"background\":2,\"customColorARGB\":\(customARGB)}"
        let customColor = try JSONDecoder().decode(
            ShadowMessageScreenshotSettings.self,
            from: Data(newFormatJSON.utf8)
        )
        precondition(customColor.background == .customColor)
        precondition(customColor.customColorARGB == customARGB)

        let future = try JSONDecoder().decode(
            ShadowMessageScreenshotSettings.self,
            from: Data("{\"background\":999}".utf8)
        )
        precondition(future.background == .chat)

        var original = defaults
        original.background = .customColor
        original.customColorARGB = customARGB
        original.showNames = false
        original.enabled = false
        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ShadowMessageScreenshotSettings.self, from: encoded)
        precondition(restored == original)
        precondition(restored.customColorARGB == customARGB)

        for background in ShadowMessageScreenshotSettings.Background.allCases {
            var value = defaults
            value.background = background
            let data = try JSONEncoder().encode(value)
            let restored = try JSONDecoder().decode(ShadowMessageScreenshotSettings.self, from: data)
            precondition(value == restored)
        }

        precondition(ShadowMessageScreenshotSettings.renderScale(width: 390, height: 800) == 2)
        precondition(ShadowMessageScreenshotSettings.renderScale(width: 390, height: 100_000) == nil)
        precondition(ShadowMessageScreenshotSettings.renderScale(width: 0, height: 100) == nil)
        precondition(ShadowMessageScreenshotSettings.renderScale(width: 390, height: .infinity) == nil)
        for height in stride(from: 100.0, through: 32_000.0, by: 100.0) {
            if let scale = ShadowMessageScreenshotSettings.renderScale(width: 390, height: height) {
                precondition(390 * height * scale * scale <= 16_000_001)
                precondition(height * scale <= 16_384.1)
            }
        }
        precondition(ShadowMessageScreenshotSettings.backgroundURL(mediaBoxPath: "/account-a/media") != ShadowMessageScreenshotSettings.backgroundURL(mediaBoxPath: "/account-b/media"))
        print("Message screenshot settings, migration and allocation limits passed")
    }
}
