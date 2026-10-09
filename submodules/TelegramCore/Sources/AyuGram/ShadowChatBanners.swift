import Foundation

// Shadow: «Фоны чатов» — a picture behind a chat's row in the chat list (all
// folders and the archive), dimmed so the text stays readable. Many photos can
// be stored; every photo has its own chats, dimming and vertical position
// (like a cover: the visible band slides up and down the photo). A chat has at
// most one photo: binding it to another photo moves it.
//
// Storage is per account, on the device only, next to the other fork images
// (AyuSavedMedia directory) in `shadow-chat-banners/`: `index.json` plus one
// `<id>.jpg` per photo. Nothing is sent anywhere.
//
// Foundation only (tested in Tests/ShadowSettings/ChatBannersTests.swift); the
// rendering is ChatListUI/ShadowChatBannerRendering.swift, the screens are
// SettingsUI/ShadowChatBannersController.swift.

public struct ShadowChatBanner: Codable, Equatable {
    public var id: String
    // 0 — the photo as is, 0.9 — almost black.
    public var dim: Double
    // Vertical position of the visible band: 0 — top of the photo, 1 — bottom.
    public var offset: Double
    public var peerIds: [Int64]
    public var created: Double
    // Mirrored left-to-right (1.10.1): moves what is on the left of the photo
    // out from under the avatar.
    public var mirrored: Bool

    public init(id: String, dim: Double = ShadowChatBanners.defaultDim, offset: Double = 0.5, peerIds: [Int64] = [], created: Double = 0.0, mirrored: Bool = false) {
        self.id = id
        self.dim = ShadowChatBanners.clampDim(dim)
        self.offset = ShadowChatBanners.clampOffset(offset)
        self.peerIds = peerIds
        self.created = created
        self.mirrored = mirrored
    }

    private enum CodingKeys: String, CodingKey {
        case id, dim, offset, peerIds, created, mirrored
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.dim = ShadowChatBanners.clampDim((try? container.decodeIfPresent(Double.self, forKey: .dim)) ?? ShadowChatBanners.defaultDim)
        self.offset = ShadowChatBanners.clampOffset((try? container.decodeIfPresent(Double.self, forKey: .offset)) ?? 0.5)
        self.peerIds = (try? container.decodeIfPresent([Int64].self, forKey: .peerIds)) ?? []
        self.created = (try? container.decodeIfPresent(Double.self, forKey: .created)) ?? 0.0
        self.mirrored = (try? container.decodeIfPresent(Bool.self, forKey: .mirrored)) ?? false
    }
}

public struct ShadowChatBannersIndex: Codable, Equatable {
    public var banners: [ShadowChatBanner]

    public init(banners: [ShadowChatBanner] = []) {
        self.banners = banners
    }

    public func banner(id: String) -> ShadowChatBanner? {
        return self.banners.first(where: { $0.id == id })
    }

    // The photo of a chat, if any.
    public func banner(peerId: Int64) -> ShadowChatBanner? {
        return self.banners.first(where: { $0.peerIds.contains(peerId) })
    }

    // Binds exactly `peerIds` to the photo: chats not in the list lose it,
    // chats in the list are taken away from any other photo.
    public mutating func setPeers(_ peerIds: [Int64], bannerId: String) {
        guard let index = self.banners.firstIndex(where: { $0.id == bannerId }) else {
            return
        }
        var unique: [Int64] = []
        var seen = Set<Int64>()
        for peerId in peerIds where !seen.contains(peerId) {
            seen.insert(peerId)
            unique.append(peerId)
        }
        for i in self.banners.indices where i != index {
            self.banners[i].peerIds.removeAll(where: { seen.contains($0) })
        }
        self.banners[index].peerIds = unique
    }

    public mutating func update(_ banner: ShadowChatBanner) {
        if let index = self.banners.firstIndex(where: { $0.id == banner.id }) {
            var banner = banner
            banner.dim = ShadowChatBanners.clampDim(banner.dim)
            banner.offset = ShadowChatBanners.clampOffset(banner.offset)
            self.banners[index] = banner
        }
    }

    public mutating func remove(id: String) {
        self.banners.removeAll(where: { $0.id == id })
    }
}

public enum ShadowChatBanners {
    public static let defaultDim: Double = 0.45
    public static let maxDim: Double = 0.9
    public static let directoryName = "shadow-chat-banners"

    public static func clampDim(_ value: Double) -> Double {
        if !value.isFinite {
            return defaultDim
        }
        return max(0.0, min(maxDim, value))
    }

    public static func clampOffset(_ value: Double) -> Double {
        if !value.isFinite {
            return 0.5
        }
        return max(0.0, min(1.0, value))
    }

    public static func decode(_ data: Data) -> ShadowChatBannersIndex {
        return (try? JSONDecoder().decode(ShadowChatBannersIndex.self, from: data)) ?? ShadowChatBannersIndex()
    }

    public static func encode(_ index: ShadowChatBannersIndex) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(index)
    }

    // The part of the photo (unit coordinates, as CALayer.contentsRect) shown
    // in a row of `rowAspect` = width / height, filling the row like
    // aspect-fill. A photo taller than the row shows a horizontal band at
    // `offset`; a wider one is centered horizontally.
    public static func visibleRect(imageAspect: Double, rowAspect: Double, offset: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        guard imageAspect > 0.0, rowAspect > 0.0, imageAspect.isFinite, rowAspect.isFinite else {
            return (0.0, 0.0, 1.0, 1.0)
        }
        if imageAspect < rowAspect {
            let height = imageAspect / rowAspect
            let y = (1.0 - height) * clampOffset(offset)
            return (0.0, y, 1.0, height)
        } else {
            let width = rowAspect / imageAspect
            return ((1.0 - width) / 2.0, 0.0, width, 1.0)
        }
    }

    // Average brightness (0…1) of the visible band, from the photo's brightness
    // per row (`profile`, top to bottom, any length).
    public static func bandLuminance(profile: [Double], imageAspect: Double, rowAspect: Double, offset: Double) -> Double {
        guard !profile.isEmpty else {
            return 0.0
        }
        let rect = visibleRect(imageAspect: imageAspect, rowAspect: rowAspect, offset: offset)
        let count = Double(profile.count)
        let start = max(0, min(profile.count - 1, Int((rect.y * count).rounded(.down))))
        let end = max(start + 1, min(profile.count, Int(((rect.y + rect.height) * count).rounded(.up))))
        var sum = 0.0
        for i in start ..< end {
            sum += profile[i]
        }
        return sum / Double(end - start)
    }

    // The brightness under the text once the black dimming layer is applied.
    public static func effectiveLuminance(bandLuminance: Double, dim: Double) -> Double {
        return max(0.0, min(1.0, bandLuminance)) * (1.0 - clampDim(dim))
    }

    // Light text (white) on a dark result, dark text on a light one. The
    // threshold sits a little above the middle: white text stays readable on
    // mid-gray longer than black does.
    public static let lightTextThreshold: Double = 0.58

    public static func prefersLightText(effectiveLuminance: Double) -> Bool {
        return effectiveLuminance < lightTextThreshold
    }
}
