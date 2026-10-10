import Foundation

// Shadow: «Фоны чатов» — a picture behind a chat's row in the chat list (all
// folders and the archive), dimmed so the text stays readable. Many photos can
// be stored; every photo has its own chats, dimming and vertical position
// (like a cover: the visible band slides up and down the photo). A chat has at
// most one photo: binding it to another photo moves it.
//
// One photo can be set on «Все чаты» (1.11.1): every chat without its own photo
// gets it, also chats that appear later, except its `excludedPeerIds`. Chats
// bound to other photos keep theirs. The chats such a photo had before keep
// their binding in `peerIds` (unused while «Все чаты» is on) and get it back
// when it is switched off.
//
// «Узор» (`pattern`, 1.11.1) is for seamless pictures: the photo is scaled to
// the row width and repeated top to bottom, fixed to the list, so rows of any
// height continue it without seams.
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
    // «Все чаты» (1.11.1): at most one photo of the index has it.
    public var allChats: Bool
    // Chats without any photo while `allChats` is on.
    public var excludedPeerIds: [Int64]
    // «Узор (без стыков)» (1.11.1).
    public var pattern: Bool

    public init(id: String, dim: Double = ShadowChatBanners.defaultDim, offset: Double = 0.5, peerIds: [Int64] = [], created: Double = 0.0, mirrored: Bool = false, allChats: Bool = false, excludedPeerIds: [Int64] = [], pattern: Bool = false) {
        self.id = id
        self.dim = ShadowChatBanners.clampDim(dim)
        self.offset = ShadowChatBanners.clampOffset(offset)
        self.peerIds = peerIds
        self.created = created
        self.mirrored = mirrored
        self.allChats = allChats
        self.excludedPeerIds = excludedPeerIds
        self.pattern = pattern
    }

    private enum CodingKeys: String, CodingKey {
        case id, dim, offset, peerIds, created, mirrored, allChats, excludedPeerIds, pattern
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.dim = ShadowChatBanners.clampDim((try? container.decodeIfPresent(Double.self, forKey: .dim)) ?? ShadowChatBanners.defaultDim)
        self.offset = ShadowChatBanners.clampOffset((try? container.decodeIfPresent(Double.self, forKey: .offset)) ?? 0.5)
        self.peerIds = (try? container.decodeIfPresent([Int64].self, forKey: .peerIds)) ?? []
        self.created = (try? container.decodeIfPresent(Double.self, forKey: .created)) ?? 0.0
        self.mirrored = (try? container.decodeIfPresent(Bool.self, forKey: .mirrored)) ?? false
        self.allChats = (try? container.decodeIfPresent(Bool.self, forKey: .allChats)) ?? false
        self.excludedPeerIds = (try? container.decodeIfPresent([Int64].self, forKey: .excludedPeerIds)) ?? []
        self.pattern = (try? container.decodeIfPresent(Bool.self, forKey: .pattern)) ?? false
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

    // The photo set on «Все чаты», if any.
    public var allChatsBanner: ShadowChatBanner? {
        return self.banners.first(where: { $0.allChats })
    }

    // The photo of a chat, if any: its own photo first, then the «Все чаты»
    // photo unless the chat is excluded from it. (The chat list resolves a
    // whole batch with `ShadowChatBannerResolver`, same rules.)
    public func banner(peerId: Int64) -> ShadowChatBanner? {
        if let banner = self.banners.first(where: { !$0.allChats && $0.peerIds.contains(peerId) }) {
            return banner
        }
        if let banner = self.allChatsBanner, !banner.excludedPeerIds.contains(peerId) {
            return banner
        }
        return nil
    }

    // Binds exactly `peerIds` to the photo: chats not in the list lose it,
    // chats in the list are taken away from any other photo. «Все чаты» and
    // its exclusions are left as they are (a chat's own photo wins anyway).
    public mutating func setPeers(_ peerIds: [Int64], bannerId: String) {
        guard let index = self.banners.firstIndex(where: { $0.id == bannerId }) else {
            return
        }
        let unique = ShadowChatBanners.unique(peerIds)
        let seen = Set(unique)
        for i in self.banners.indices where i != index {
            self.banners[i].peerIds.removeAll(where: { seen.contains($0) })
        }
        self.banners[index].peerIds = unique
    }

    // Switches «Все чаты» on the photo; switching it on takes it off any other
    // photo (their exclusions are kept for when it comes back).
    public mutating func setAllChats(_ value: Bool, bannerId: String) {
        guard let index = self.banners.firstIndex(where: { $0.id == bannerId }) else {
            return
        }
        if value {
            for i in self.banners.indices where i != index {
                self.banners[i].allChats = false
            }
        }
        self.banners[index].allChats = value
    }

    public mutating func setExcluded(_ peerIds: [Int64], bannerId: String) {
        guard let index = self.banners.firstIndex(where: { $0.id == bannerId }) else {
            return
        }
        self.banners[index].excludedPeerIds = ShadowChatBanners.unique(peerIds)
    }

    public mutating func update(_ banner: ShadowChatBanner) {
        if let index = self.banners.firstIndex(where: { $0.id == banner.id }) {
            var banner = banner
            banner.dim = ShadowChatBanners.clampDim(banner.dim)
            banner.offset = ShadowChatBanners.clampOffset(banner.offset)
            self.banners[index] = banner
            if banner.allChats {
                self.setAllChats(true, bannerId: banner.id)
            }
        }
    }

    public mutating func remove(id: String) {
        self.banners.removeAll(where: { $0.id == id })
    }
}

// The photo of every chat of a batch of chat-list rows, built once from the
// index (a dictionary instead of a search per row). Same rules as
// `ShadowChatBannersIndex.banner(peerId:)`.
public struct ShadowChatBannerResolver {
    private let byPeer: [Int64: ShadowChatBanner]
    private let allChats: ShadowChatBanner?
    private let excluded: Set<Int64>

    public init(index: ShadowChatBannersIndex) {
        var byPeer: [Int64: ShadowChatBanner] = [:]
        for banner in index.banners where !banner.allChats {
            for peerId in banner.peerIds where byPeer[peerId] == nil {
                byPeer[peerId] = banner
            }
        }
        let allChats = index.allChatsBanner
        self.byPeer = byPeer
        self.allChats = allChats
        self.excluded = Set(allChats?.excludedPeerIds ?? [])
    }

    public func banner(peerId: Int64) -> ShadowChatBanner? {
        if let banner = self.byPeer[peerId] {
            return banner
        }
        if let allChats = self.allChats, !self.excluded.contains(peerId) {
            return allChats
        }
        return nil
    }
}

public enum ShadowChatBanners {
    public static let defaultDim: Double = 0.45
    public static let maxDim: Double = 0.9
    public static let directoryName = "shadow-chat-banners"

    // Duplicates dropped, order kept.
    public static func unique(_ peerIds: [Int64]) -> [Int64] {
        var result: [Int64] = []
        var seen = Set<Int64>()
        for peerId in peerIds where !seen.contains(peerId) {
            seen.insert(peerId)
            result.append(peerId)
        }
        return result
    }

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

    // Average brightness of the whole photo: a «Узор» row can show any part of
    // it.
    public static func averageLuminance(profile: [Double]) -> Double {
        guard !profile.isEmpty else {
            return 0.0
        }
        return profile.reduce(0.0, +) / Double(profile.count)
    }

    // «Узор»: height of one copy of the photo scaled to the row width (at
    // least 2 points, so a strip-like photo does not need hundreds of copies).
    public static func patternTileHeight(imageAspect: Double, rowWidth: Double) -> Double {
        guard imageAspect > 0.0, imageAspect.isFinite, rowWidth > 0.0, rowWidth.isFinite else {
            return 0.0
        }
        return max(2.0, rowWidth / imageAspect)
    }

    // «Узор»: the copies start at the top of the list, so a row whose top is
    // `rowY` points down the list draws its first copy at -shift and
    // neighbouring rows continue each other. 0 <= shift < tileHeight.
    public static func patternShift(rowY: Double, tileHeight: Double) -> Double {
        guard tileHeight > 0.0, rowY.isFinite else {
            return 0.0
        }
        var shift = rowY.truncatingRemainder(dividingBy: tileHeight)
        if shift < 0.0 {
            shift += tileHeight
        }
        return shift
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
