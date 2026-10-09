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

        print("Shadow chat banners: \(count) checks passed")
    }
}
