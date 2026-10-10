import Foundation
import UIKit
import ImageIO
import Display
import ItemListUI
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
// keeps the separator barely visible. A «Узор» photo is drawn by
// ShadowChatBannerPatternLayer: copies of the photo at the row width, fixed to
// the list (the row passes its position from updateAbsoluteRect).

public final class ShadowChatBannerAppearance {
    public let id: String
    public let image: UIImage
    public let imageAspect: Double
    public let dim: CGFloat
    public let offset: Double
    public let lightText: Bool
    public let pattern: Bool

    init(id: String, image: UIImage, imageAspect: Double, dim: CGFloat, offset: Double, lightText: Bool, pattern: Bool) {
        self.id = id
        self.image = image
        self.imageAspect = imageAspect
        self.dim = dim
        self.offset = offset
        self.lightText = lightText
        self.pattern = pattern
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
    private let lock = NSLock()
    private var mirroredValue: UIImage?

    init(image: UIImage, aspect: Double, profile: [Double]) {
        self.image = image
        self.aspect = aspect
        self.profile = profile
    }

    // The photo mirrored left-to-right (drawn once, on first use). The
    // brightness profile is per row, so mirroring does not change it.
    public func image(mirrored: Bool) -> UIImage {
        guard mirrored else {
            return self.image
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        if let mirroredValue = self.mirroredValue {
            return mirroredValue
        }
        var result = self.image
        if let cgImage = self.image.cgImage {
            let width = cgImage.width
            let height = cgImage.height
            if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.translateBy(x: CGFloat(width), y: 0.0)
                context.scaleBy(x: -1.0, y: 1.0)
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                if let flipped = context.makeImage() {
                    result = UIImage(cgImage: flipped)
                }
            }
        }
        self.mirroredValue = result
        return result
    }

    // Brightness under the text of a row of `rowAspect` with these settings.
    public func effectiveLuminance(rowAspect: Double, offset: Double, dim: Double) -> Double {
        let band = ShadowChatBanners.bandLuminance(profile: self.profile, imageAspect: self.aspect, rowAspect: rowAspect, offset: offset)
        return ShadowChatBanners.effectiveLuminance(bandLuminance: band, dim: dim)
    }

    public func prefersLightText(rowAspect: Double, offset: Double, dim: Double) -> Bool {
        return ShadowChatBanners.prefersLightText(effectiveLuminance: self.effectiveLuminance(rowAspect: rowAspect, offset: offset, dim: dim))
    }

    // «Узор»: a row can show any part of the photo, so the whole photo counts.
    public func prefersLightTextAsPattern(dim: Double) -> Bool {
        let luminance = ShadowChatBanners.effectiveLuminance(bandLuminance: ShadowChatBanners.averageLuminance(profile: self.profile), dim: dim)
        return ShadowChatBanners.prefersLightText(effectiveLuminance: luminance)
    }

    public func prefersLightText(banner: ShadowChatBanner, rowAspect: Double) -> Bool {
        if banner.pattern {
            return self.prefersLightTextAsPattern(dim: banner.dim)
        }
        return self.prefersLightText(rowAspect: rowAspect, offset: banner.offset, dim: banner.dim)
    }
}

// «Узор»: copies of the photo scaled to the row width, one under another,
// shifted so that they start at the top of the list. Used by the chat-list
// rows and the editor preview (same drawing, so the preview is what the list
// shows).
public final class ShadowChatBannerPatternLayer: CALayer {
    private let copiesLayer = CAReplicatorLayer()
    private let tileLayer = CALayer()
    private weak var image: UIImage?

    override public init() {
        super.init()
        self.masksToBounds = true
        self.tileLayer.contentsGravity = .resize
        self.copiesLayer.addSublayer(self.tileLayer)
        self.addSublayer(self.copiesLayer)
    }

    override public init(layer: Any) {
        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // `rowY` — the top of this layer in the list's coordinates.
    public func update(image: UIImage, imageAspect: Double, size: CGSize, rowY: CGFloat) {
        let tileHeight = CGFloat(ShadowChatBanners.patternTileHeight(imageAspect: imageAspect, rowWidth: Double(size.width)))
        guard tileHeight > 0.0, size.height > 0.0 else {
            return
        }
        let shift = CGFloat(ShadowChatBanners.patternShift(rowY: Double(rowY), tileHeight: Double(tileHeight)))
        let count = min(256, Int(ceil((size.height + shift) / tileHeight)) + 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self.image !== image {
            self.image = image
            self.tileLayer.contents = image.cgImage
        }
        self.tileLayer.frame = CGRect(x: 0.0, y: 0.0, width: size.width, height: tileHeight)
        self.copiesLayer.instanceCount = count
        self.copiesLayer.instanceTransform = CATransform3DMakeTranslation(0.0, tileHeight, 0.0)
        self.copiesLayer.frame = CGRect(x: 0.0, y: -shift, width: size.width, height: tileHeight * CGFloat(count))
        CATransaction.commit()
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
    private static let lock = NSLock()
    private static var heights: [String: CGFloat] = [:]

    // Height of a chat row in the list for this font size: the same formula
    // as ChatListItem's layout (title line + three preview lines, two when
    // compact), measured with the same font. The editor preview uses it, so
    // the photo is cut the same way as in the list.
    public static func rowHeight(fontSize: PresentationFontSize, compact: Bool) -> CGFloat {
        let key = "\(fontSize.itemListBaseFontSize)|\(compact)"
        lock.lock()
        if let height = heights[key] {
            lock.unlock()
            return height
        }
        lock.unlock()
        let titleFont = Font.semibold(floor(fontSize.itemListBaseFontSize * 16.0 / 17.0))
        let (measure, _) = TextNode.asyncLayout(nil)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: " ", font: titleFont, textColor: .black), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: 200.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
        let line = measure.size.height
        // ChatListItem: 8 * 2 + 1 - 21 + title + lines - 1 (title spacing) - 3 (author spacing).
        let height = max(40.0, 8.0 * 2.0 + 1.0 - 21.0 + line + line * (compact ? 2.0 : 3.0) - 1.0 - 3.0)
        lock.lock()
        heights[key] = height
        lock.unlock()
        return height
    }

    // Width / height of a chat row, for picking the text color before the row
    // is laid out (the drawn band uses the real size).
    // Called off the main thread too, so no UIScreen: a typical phone width.
    public static func estimatedRowAspect(fontSize: PresentationFontSize, compact: Bool) -> Double {
        let width: Double = 393.0
        return width / Double(rowHeight(fontSize: fontSize, compact: compact))
    }
}

// Decides the photos for one batch of chat-list rows: settings and the index
// are read once per batch, the photo of each chat comes from a dictionary
// (ShadowChatBannerResolver: own photo, else «Все чаты» unless excluded).
final class ShadowChatBannerBatch {
    private let enabled: Bool
    private let basePath: String
    private let resolver: ShadowChatBannerResolver
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
        self.resolver = ShadowChatBannerResolver(index: index)
        self.enabled = enabled
    }

    func presentationData(_ base: ChatListPresentationData, peerId: EnginePeer.Id) -> ChatListPresentationData {
        guard self.enabled, let banner = self.resolver.banner(peerId: peerId.toInt64()) else {
            return base
        }
        let key = "\(banner.id)|\(ObjectIdentifier(base).hashValue)"
        if let cached = self.presentationData[key] {
            return cached
        }
        guard let appearance = self.appearance(banner, fontSize: base.fontSize, compact: base.compactChatList) else {
            return base
        }
        let theme = ShadowChatBannerThemes.shared.theme(base: base.theme, lightText: appearance.lightText)
        let result = base.withShadowChatBanner(appearance, theme: theme)
        self.presentationData[key] = result
        return result
    }

    private func appearance(_ banner: ShadowChatBanner, fontSize: PresentationFontSize, compact: Bool) -> ShadowChatBannerAppearance? {
        let key = "\(banner.id)|\(fontSize.itemListBaseFontSize)|\(compact)"
        if let appearance = self.appearances[key] {
            return appearance
        }
        let path = ShadowChatBannerStore.shared.imagePath(basePath: self.basePath, id: banner.id)
        guard let image = ShadowChatBannerImageCache.shared.image(path: path) else {
            return nil
        }
        let lightText = image.prefersLightText(banner: banner, rowAspect: ShadowChatBannerRows.estimatedRowAspect(fontSize: fontSize, compact: compact))
        let appearance = ShadowChatBannerAppearance(id: banner.id, image: image.image(mirrored: banner.mirrored), imageAspect: image.aspect, dim: CGFloat(banner.dim), offset: banner.offset, lightText: lightText, pattern: banner.pattern)
        self.appearances[key] = appearance
        return appearance
    }
}
