import Foundation

@main
struct ChatBannersTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        func near(_ a: Double, _ b: Double) -> Bool {
            return abs(a - b) < 0.0001
        }

        // Binding chats: a chat has one photo, binding moves it.
        var index = ShadowChatBannersIndex(banners: [ShadowChatBanner(id: "a", peerIds: [1, 2]), ShadowChatBanner(id: "b", peerIds: [3])])
        check(index.banner(peerId: 2)?.id == "a", "Chat 2 has photo a")
        index.setPeers([2, 3, 3, 4], bannerId: "b")
        check(index.banner(id: "b")?.peerIds == [2, 3, 4], "Duplicates dropped, order kept")
        check(index.banner(id: "a")?.peerIds == [1], "Chat 2 moved away from photo a")
        check(index.banner(peerId: 2)?.id == "b", "Chat 2 now has photo b")
        index.setPeers([], bannerId: "b")
        check(index.banner(peerId: 3) == nil, "Unbinding all chats of a photo")
        index.setPeers([9], bannerId: "missing")
        check(index.banner(peerId: 9) == nil, "Unknown photo changes nothing")
        index.remove(id: "a")
        check(index.banner(peerId: 1) == nil && index.banners.count == 1, "Removing a photo frees its chats")

        // Values are clamped, also when decoding a hand-edited file.
        var banner = ShadowChatBanner(id: "c", dim: 5.0, offset: -1.0)
        check(banner.dim == ShadowChatBanners.maxDim && banner.offset == 0.0, "Init clamps")
        index.banners.append(banner)
        banner.dim = -3.0
        banner.offset = 7.0
        index.update(banner)
        check(index.banner(id: "c")?.dim == 0.0 && index.banner(id: "c")?.offset == 1.0, "Update clamps")
        let json = "{\"banners\":[{\"id\":\"x\",\"dim\":2,\"peerIds\":[5]},{\"id\":\"y\"}]}".data(using: .utf8)!
        let decoded = ShadowChatBanners.decode(json)
        check(decoded.banners.count == 2 && decoded.banner(id: "x")?.dim == ShadowChatBanners.maxDim, "Decode clamps dim")
        check(decoded.banner(id: "y")?.offset == 0.5 && decoded.banner(id: "y")?.dim == ShadowChatBanners.defaultDim, "Missing fields get defaults")
        check(decoded.banner(id: "y")?.mirrored == false, "Not mirrored by default (files from 1.10.0)")
        var flipped = ShadowChatBannersIndex(banners: [ShadowChatBanner(id: "m", mirrored: true)])
        flipped = ShadowChatBanners.decode(ShadowChatBanners.encode(flipped)!)
        check(flipped.banner(id: "m")?.mirrored == true, "Mirroring is stored")
        check(ShadowChatBanners.decode(Data("garbage".utf8)).banners.isEmpty, "Broken file is empty")
        let roundTrip = ShadowChatBanners.decode(ShadowChatBanners.encode(decoded)!)
        check(roundTrip == decoded, "Round trip")

        // Visible band: aspect fill + vertical position.
        let tall = ShadowChatBanners.visibleRect(imageAspect: 1.0, rowAspect: 5.0, offset: 0.0)
        check(near(tall.height, 0.2) && near(tall.y, 0.0) && near(tall.width, 1.0), "Square photo, top band")
        let bottom = ShadowChatBanners.visibleRect(imageAspect: 1.0, rowAspect: 5.0, offset: 1.0)
        check(near(bottom.y, 0.8), "Square photo, bottom band")
        let middle = ShadowChatBanners.visibleRect(imageAspect: 0.5, rowAspect: 5.0, offset: 0.5)
        check(near(middle.height, 0.1) && near(middle.y, 0.45), "Portrait photo, middle band")
        let wide = ShadowChatBanners.visibleRect(imageAspect: 10.0, rowAspect: 5.0, offset: 0.0)
        check(near(wide.width, 0.5) && near(wide.x, 0.25) && near(wide.height, 1.0), "Panorama: centered, full height")
        let broken = ShadowChatBanners.visibleRect(imageAspect: 0.0, rowAspect: 5.0, offset: 0.3)
        check(broken.width == 1.0 && broken.height == 1.0, "Bad size: whole photo")

        // Text color: white top half, black bottom half.
        let profile = Array(repeating: 1.0, count: 32) + Array(repeating: 0.0, count: 32)
        let top = ShadowChatBanners.bandLuminance(profile: profile, imageAspect: 1.0, rowAspect: 5.0, offset: 0.0)
        let low = ShadowChatBanners.bandLuminance(profile: profile, imageAspect: 1.0, rowAspect: 5.0, offset: 1.0)
        check(near(top, 1.0) && near(low, 0.0), "Band brightness follows the position")
        check(!ShadowChatBanners.prefersLightText(effectiveLuminance: ShadowChatBanners.effectiveLuminance(bandLuminance: top, dim: 0.0)), "White photo, no dimming: dark text")
        check(ShadowChatBanners.prefersLightText(effectiveLuminance: ShadowChatBanners.effectiveLuminance(bandLuminance: top, dim: 0.6)), "White photo dimmed 60%: light text")
        check(ShadowChatBanners.prefersLightText(effectiveLuminance: ShadowChatBanners.effectiveLuminance(bandLuminance: low, dim: 0.0)), "Black photo: light text")
        check(ShadowChatBanners.bandLuminance(profile: [], imageAspect: 1.0, rowAspect: 5.0, offset: 0.5) == 0.0, "No profile")

        // «Все чаты» (1.11.1): A on all chats, B — Матвей (1), C — Глеб (2) and Даня (3).
        let old = ShadowChatBanners.decode("{\"banners\":[{\"id\":\"o\",\"peerIds\":[7],\"mirrored\":true}]}".data(using: .utf8)!)
        check(old.banner(id: "o")?.allChats == false && old.banner(id: "o")?.excludedPeerIds == [] && old.banner(id: "o")?.pattern == false, "Files from 1.10/1.11.0: no «Все чаты», no exclusions, no pattern")
        check(old.banner(peerId: 7)?.id == "o" && old.banner(peerId: 8) == nil, "Without «Все чаты» nothing changes")
        var all = ShadowChatBannersIndex(banners: [ShadowChatBanner(id: "A"), ShadowChatBanner(id: "B", peerIds: [1]), ShadowChatBanner(id: "C", peerIds: [2, 3])])
        all.setAllChats(true, bannerId: "A")
        all.setExcluded([5, 5, 6], bannerId: "A")
        check(all.banner(id: "A")?.excludedPeerIds == [5, 6], "Exclusions: duplicates dropped")
        check(all.banner(peerId: 1)?.id == "B", "Матвей keeps his own photo")
        check(all.banner(peerId: 2)?.id == "C" && all.banner(peerId: 3)?.id == "C", "Глеб and Даня keep theirs")
        check(all.banner(peerId: 4)?.id == "A" && all.banner(peerId: 999)?.id == "A", "Any other and any new chat gets «Все чаты»")
        check(all.banner(peerId: 5) == nil, "Excluded chat has no photo")
        all.setPeers([5], bannerId: "B")
        check(all.banner(peerId: 5)?.id == "B", "Own photo wins over the exclusion")
        check(all.banner(id: "A")?.allChats == true && all.banner(id: "A")?.excludedPeerIds == [5, 6], "setPeers leaves «Все чаты» alone")
        all.setAllChats(true, bannerId: "C")
        check(all.banner(id: "A")?.allChats == false && all.allChatsBanner?.id == "C", "Only one photo on «Все чаты»")
        check(all.banner(peerId: 4)?.id == "C" && all.banner(peerId: 2)?.id == "C", "Moved «Все чаты»")
        check(all.banner(id: "A")?.excludedPeerIds == [5, 6], "Old exclusions kept for later")
        var stale = all.banner(id: "A")!
        stale.allChats = true
        all.update(stale)
        check(all.banners.filter({ $0.allChats }).count == 1 && all.allChatsBanner?.id == "A", "Update with «Все чаты» also takes it off the others")

        // Chats of a photo before «Все чаты» come back when it is switched off.
        var restore = ShadowChatBannersIndex(banners: [ShadowChatBanner(id: "A", peerIds: [1, 2]), ShadowChatBanner(id: "B")])
        restore.setAllChats(true, bannerId: "A")
        check(restore.banner(peerId: 3)?.id == "A", "Switched on: everyone")
        restore.setPeers([2], bannerId: "B")
        restore.setAllChats(false, bannerId: "A")
        check(restore.banner(peerId: 1)?.id == "A" && restore.banner(peerId: 3) == nil, "Switched off: its own chats again")
        check(restore.banner(peerId: 2)?.id == "B", "A chat moved meanwhile stays moved")

        // Deleting the «Все чаты» photo: chats without their own photo lose it.
        var removal = ShadowChatBannersIndex(banners: [ShadowChatBanner(id: "A", allChats: true), ShadowChatBanner(id: "B", peerIds: [1])])
        removal.remove(id: "A")
        check(removal.banner(peerId: 1)?.id == "B" && removal.banner(peerId: 4) == nil && removal.allChatsBanner == nil, "Deleting «Все чаты» keeps own photos")

        // The batch resolver gives the same answers.
        let resolverIndex = ShadowChatBannersIndex(banners: [ShadowChatBanner(id: "A", peerIds: [9], allChats: true, excludedPeerIds: [5]), ShadowChatBanner(id: "B", peerIds: [1]), ShadowChatBanner(id: "C", peerIds: [2, 3])])
        let resolver = ShadowChatBannerResolver(index: resolverIndex)
        for peerId: Int64 in [1, 2, 3, 4, 5, 9, 100] {
            check(resolver.banner(peerId: peerId)?.id == resolverIndex.banner(peerId: peerId)?.id, "Resolver matches the index for \(peerId)")
        }
        check(resolver.banner(peerId: 9)?.id == "A" && resolver.banner(peerId: 5) == nil, "Own chats of the «Все чаты» photo are not used while it is on")
        check(ShadowChatBannerResolver(index: ShadowChatBannersIndex()).banner(peerId: 1) == nil, "Empty index")

        // Stored and round-tripped.
        let stored = ShadowChatBanners.decode(ShadowChatBanners.encode(resolverIndex)!)
        check(stored == resolverIndex && stored.banner(id: "A")?.excludedPeerIds == [5], "«Все чаты» and exclusions are stored")
        let patterned = ShadowChatBanners.decode(ShadowChatBanners.encode(ShadowChatBannersIndex(banners: [ShadowChatBanner(id: "p", pattern: true)]))!)
        check(patterned.banner(id: "p")?.pattern == true, "Pattern is stored")

        // «Узор»: copies at the row width, continuous down the list.
        check(near(ShadowChatBanners.patternTileHeight(imageAspect: 4.0, rowWidth: 400.0), 100.0), "Tile height from the row width")
        check(ShadowChatBanners.patternTileHeight(imageAspect: 1000.0, rowWidth: 400.0) == 2.0, "Tile at least 2 points")
        check(ShadowChatBanners.patternTileHeight(imageAspect: 0.0, rowWidth: 400.0) == 0.0, "Bad size: no tile")
        check(near(ShadowChatBanners.patternShift(rowY: 0.0, tileHeight: 100.0), 0.0), "First row starts at the top of a copy")
        check(near(ShadowChatBanners.patternShift(rowY: 76.0, tileHeight: 100.0), 76.0), "Next row continues where the first ended")
        check(near(ShadowChatBanners.patternShift(rowY: 230.0, tileHeight: 100.0), 30.0), "Shift wraps around")
        check(near(ShadowChatBanners.patternShift(rowY: -30.0, tileHeight: 100.0), 70.0), "Row above the top")
        check(near(ShadowChatBanners.averageLuminance(profile: profile), 0.5) && ShadowChatBanners.averageLuminance(profile: []) == 0.0, "Pattern text color: brightness of the whole photo")

        print("Shadow chat banners: \(count) checks passed")
    }
}
