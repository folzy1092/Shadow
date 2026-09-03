import Foundation

@main struct MessageScreenshotTests {
    static func main() throws {
        let defaults = try JSONDecoder().decode(ShadowMessageScreenshotSettings.self, from: Data("{}".utf8))
        precondition(defaults.enabled && defaults.showAvatars && defaults.showNames && defaults.showBadges && defaults.showTime)
        precondition(defaults.background == .chat)
        precondition(ShadowMessageScreenshotSettings.Background.allCases.count == 4)
        let future = try JSONDecoder().decode(ShadowMessageScreenshotSettings.self, from: Data("{\"background\":999}".utf8))
        precondition(future.background == .chat)
        for background in ShadowMessageScreenshotSettings.Background.allCases {
            var original = defaults
            original.background = background
            original.showNames = false
            original.enabled = false
            let data = try JSONEncoder().encode(original)
            let restored = try JSONDecoder().decode(ShadowMessageScreenshotSettings.self, from: data)
            precondition(original == restored)
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
        print("Message screenshot settings and allocation limits passed")
    }
}
