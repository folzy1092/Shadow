import Foundation
import UIKit
import Display
import TelegramPresentationData

// Shadow: icons of the Shadow hub rows — an SF Symbol on a colored rounded
// square, the same 30×30 shape as Telegram's settings icons. Follows "Одноцветные
// иконки" (shadowMonochromeSettingsIconColors). A symbol missing on the running
// iOS gives nil, and the row is drawn without an icon.
// Items may be built off the main thread: the cache is locked.
private let shadowSymbolIconLock = NSLock()
private var shadowSymbolIconCache: [String: UIImage] = [:]

func shadowSymbolIcon(_ symbol: String, color: UIColor) -> UIImage? {
    var background = color
    var glyph = UIColor.white
    if let monochrome = shadowMonochromeSettingsIconColors {
        background = monochrome.background
        glyph = monochrome.glyph
    }
    let key = "\(symbol)|\(background.argb)|\(glyph.argb)"
    shadowSymbolIconLock.lock()
    let cached = shadowSymbolIconCache[key]
    shadowSymbolIconLock.unlock()
    if let cached {
        return cached
    }
    let configuration = UIImage.SymbolConfiguration(pointSize: 16.0, weight: .semibold)
    guard let symbolImage = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(glyph, renderingMode: .alwaysOriginal) else {
        return nil
    }
    let image = generateImage(CGSize(width: 30.0, height: 30.0), rotatedContext: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        context.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: 7.0).cgPath)
        context.setFillColor(background.cgColor)
        context.fillPath()

        UIGraphicsPushContext(context)
        let maxSide: CGFloat = 19.0
        let scale = min(maxSide / max(symbolImage.size.width, 1.0), maxSide / max(symbolImage.size.height, 1.0), 1.0)
        let drawSize = CGSize(width: symbolImage.size.width * scale, height: symbolImage.size.height * scale)
        symbolImage.draw(in: CGRect(x: floor((size.width - drawSize.width) / 2.0), y: floor((size.height - drawSize.height) / 2.0), width: drawSize.width, height: drawSize.height))
        UIGraphicsPopContext()
    })
    if let image {
        shadowSymbolIconLock.lock()
        shadowSymbolIconCache[key] = image
        shadowSymbolIconLock.unlock()
    }
    return image
}

// Palette of the hub rows (iOS system colors).
enum ShadowIconColor {
    static let blue = UIColor(rgb: 0x007AFF)
    static let indigo = UIColor(rgb: 0x5856D6)
    static let orange = UIColor(rgb: 0xFF9500)
    static let gray = UIColor(rgb: 0x8E8E93)
    static let teal = UIColor(rgb: 0x30B0C7)
    static let red = UIColor(rgb: 0xFF3B30)
    static let green = UIColor(rgb: 0x34C759)
    static let pink = UIColor(rgb: 0xFF2D55)
    static let purple = UIColor(rgb: 0xAF52DE)
    static let yellow = UIColor(rgb: 0xFFB800)
    static let mint = UIColor(rgb: 0x00C7BE)
}
