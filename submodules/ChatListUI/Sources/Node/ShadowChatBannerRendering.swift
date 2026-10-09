import Foundation
import UIKit
import ImageIO
import TelegramCore
import TelegramPresentationData
import AccountContext

// Shadow: «Фоны чатов» — what a chat-list row needs to draw its photo
// (model and storage: TelegramCore ShadowChatBanners.swift / ShadowChatBannerStore.swift).
//
// The photo is decided when the list maps its entries to items
// (ChatListNode.mappedInsertEntries / mappedUpdateEntries): such a row gets its
// own ChatListPresentationData carrying `shadowChatBanner` and, when the photo
// is light (or dark) enough to need it, a theme with inverted chat-list text
// colors. ChatListItemNode draws the photo, a black dimming layer over it and
// keeps the separator barely visible.

public final class ShadowChatBannerAppearance {
    public let id: String
    public let image: UIImage
    public let imageAspect: Double
    public let dim: CGFloat
    public let offset: Double
    public let lightText: Bool

    init(id: String, image: UIImage, imageAspect: Double, dim: CGFloat, offset: Double, lightText: Bool) {
        self.id = id
        self.image = image
        self.imageAspect = imageAspect
        self.dim = dim
        self.offset = offset
        self.lightText = lightText
    }

    // CALayer.contentsRect for a row of this size.
    public func contentsRect(size: CGSize) -> CGRect {
        guard size.width > 0.0, size.height > 0.0 else {
            return CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
        }
        let rect = ShadowChatBanners.visibleRect(imageAspect: self.imageAspect, rowAspect: Double(size.width / size.height), offset: self.offset)
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

// A decoded photo: downscaled for drawing, plus its brightness per row for
// picking the text color.
public final class ShadowChatBannerImage {
    public let image: UIImage
    public let aspect: Double
    public let profile: [Double]

    init(image: UIImage, aspect: Double, profile: [Double]) {
        self.image = image
        self.aspect = aspect
        self.profile = profile
    }

    // Brightness under the text of a row of `rowAspect` with these settings.
    public func effectiveLuminance(rowAspect: Double, offset: Double, dim: Double) -> Double {
        let band = ShadowChatBanners.bandLuminance(profile: self.profile, imageAspect: self.aspect, rowAspect: rowAspect, offset: offset)
        return ShadowChatBanners.effectiveLuminance(bandLuminance: band, dim: dim)
    }

    public func prefersLightText(rowAspect: Double, offset: Double, dim: Double) -> Bool {
        return ShadowChatBanners.prefersLightText(effectiveLuminance: self.effectiveLuminance(rowAspect: rowAspect, offset: offset, dim: dim))
    }
}

public final class ShadowChatBannerImageCache {
    public static let shared = ShadowChatBannerImageCache()

    private let lock = NSLock()
    private var entries: [String: (signature: String, image: ShadowChatBannerImage)] = [:]

    private static let maxPixelSize: CGFloat = 1400.0
    private static let profileRows = 64

    public func image(path: String) -> ShadowChatBannerImage? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0.0
        let signature = "\(size)-\(modified)"
        self.lock.lock()
        if let entry = self.entries[path], entry.signature == signature {
            self.lock.unlock()
            return entry.image
        }
        self.lock.unlock()

        guard let decoded = ShadowChatBannerImageCache.decode(path: path) else {
            return nil
        }
        self.lock.lock()
        self.entries[path] = (signature, decoded)
        self.lock.unlock()
        return decoded
    }

    public func remove(path: String) {
        self.lock.lock()
        self.entries.removeValue(forKey: path)
        self.lock.unlock()
    }

    private static func decode(path: String) -> ShadowChatBannerImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }
        return ShadowChatBannerImage(image: UIImage(cgImage: cgImage), aspect: Double(width) / Double(height), profile: brightnessProfile(cgImage))
    }

    // Brightness of each of `profileRows` horizontal stripes, top to bottom.
    private static func brightnessProfile(_ image: CGImage) -> [Double] {
        let columns = 16
        let rows = profileRows
        guard let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return [0.5]
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let data = context.data else {
            return [0.5]
        }
        let bytes = data.bindMemory(to: UInt8.self, capacity: columns * rows)
        var result: [Double] = []
        result.reserveCapacity(rows)
        // Row 0 of a bitmap context's memory is the top of the drawn image.
        for row in 0 ..< rows {
            var sum = 0
            for column in 0 ..< columns {
                sum += Int(bytes[row * columns + column])
            }
            result.append(Double(sum) / Double(columns * 255))
        }
        return result
    }
}

// The chat-list theme with text colors for a photo background. Kept per base
// theme, so rows share two derived themes at most (and their resource caches).
public final class ShadowChatBannerThemes {
    public static let shared = ShadowChatBannerThemes()

    private let lock = NSLock()
    private weak var base: PresentationTheme?
    private var light: PresentationTheme?
    private var dark: PresentationTheme?

    public static func themeHasLightText(_ theme: PresentationTheme) -> Bool {
        var white: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        if theme.chatList.titleColor.getWhite(&white, alpha: &alpha) {
            return white > 0.5
        }
        return theme.overallDarkAppearance
    }

    public func theme(base: PresentationTheme, lightText: Bool) -> PresentationTheme {
        if ShadowChatBannerThemes.themeHasLightText(base) == lightText {
            return base
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.base !== base {
            self.base = base
            self.light = nil
            self.dark = nil
        }
        if lightText {
            if let light = self.light {
                return light
            }
            let theme = ShadowChatBannerThemes.make(base: base, lightText: true)
            self.light = theme
            return theme
        } else {
            if let dark = self.dark {
                return dark
            }
            let theme = ShadowChatBannerThemes.make(base: base, lightText: false)
            self.dark = theme
            return theme
        }
    }

    private static func make(base: PresentationTheme, lightText: Bool) -> PresentationTheme {
        let primary: UIColor = lightText ? .white : .black
        let secondary: UIColor = lightText ? UIColor(white: 1.0, alpha: 0.72) : UIColor(white: 0.0, alpha: 0.62)
        let tertiary: UIColor = lightText ? UIColor(white: 1.0, alpha: 0.55) : UIColor(white: 0.0, alpha: 0.45)
        let chatList = base.chatList.withUpdated(
            titleColor: primary,
            secretTitleColor: primary,
            dateTextColor: secondary,
            authorNameColor: primary,
            messageTextColor: secondary,
            muteIconColor: tertiary,
            pinnedBadgeColor: tertiary
        )
        return PresentationTheme(
            name: base.name,
            index: base.index,
            referenceTheme: base.referenceTheme,
            overallDarkAppearance: base.overallDarkAppearance,
            intro: base.intro,
            passcode: base.passcode,
            rootController: base.rootController,
            list: base.list,
            chatList: chatList,
            chat: base.chat,
            actionSheet: base.actionSheet,
            contextMenu: base.contextMenu,
            inAppNotification: base.inAppNotification,
            chart: base.chart,
            preview: base.preview
        )
    }
}

public enum ShadowChatBannerRows {
    // Width / height of a chat row, for picking the text color before the row
    // is laid out (the drawn band uses the real size).
    // Called off the main thread too, so no UIScreen: a typical phone width.
    public static func estimatedRowAspect(compact: Bool) -> Double {
        let width: Double = 393.0
        let height: Double = compact ? 62.0 : 76.0
        return width / height
    }
}

// Decides the photos for one batch of chat-list rows: settings and the index
// are read once per batch.
final class ShadowChatBannerBatch {
    private let enabled: Bool
    private let basePath: String
    private let index: ShadowChatBannersIndex
    private var appearances: [String: ShadowChatBannerAppearance] = [:]
    private var presentationData: [String: ChatListPresentationData] = [:]

    init(context: AccountContext, location: ChatListControllerLocation) {
        var enabled = false
        if case .chatList = location {
            enabled = currentAyuGramSettings(accountId: context.account.id).chatBannersEnabled
        }
        let basePath = context.account.postbox.mediaBox.basePath
        var index = ShadowChatBannersIndex()
        if enabled {
            index = ShadowChatBannerStore.shared.index(basePath: basePath)
            enabled = !index.banners.isEmpty
        }
        self.basePath = basePath
        self.index = index
        self.enabled = enabled
    }

    func presentationData(_ base: ChatListPresentationData, peerId: EnginePeer.Id) -> ChatListPresentationData {
        guard self.enabled, let banner = self.index.banner(peerId: peerId.toInt64()) else {
            return base
        }
        let key = "\(banner.id)|\(ObjectIdentifier(base).hashValue)"
        if let cached = self.presentationData[key] {
            return cached
        }
        guard let appearance = self.appearance(banner, compact: base.compactChatList) else {
            return base
        }
        let theme = ShadowChatBannerThemes.shared.theme(base: base.theme, lightText: appearance.lightText)
        let result = base.withShadowChatBanner(appearance, theme: theme)
        self.presentationData[key] = result
        return result
    }

    private func appearance(_ banner: ShadowChatBanner, compact: Bool) -> ShadowChatBannerAppearance? {
        let key = "\(banner.id)|\(compact)"
        if let appearance = self.appearances[key] {
            return appearance
        }
        let path = ShadowChatBannerStore.shared.imagePath(basePath: self.basePath, id: banner.id)
        guard let image = ShadowChatBannerImageCache.shared.image(path: path) else {
            return nil
        }
        let lightText = image.prefersLightText(rowAspect: ShadowChatBannerRows.estimatedRowAspect(compact: compact), offset: banner.offset, dim: banner.dim)
        let appearance = ShadowChatBannerAppearance(id: banner.id, image: image.image, imageAspect: image.aspect, dim: CGFloat(banner.dim), offset: banner.offset, lightText: lightText)
        self.appearances[key] = appearance
        return appearance
    }
}
