import Foundation

@main
struct FakeGiftTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        typealias Gift = ShadowFakeGift

        check(Gift.slug(from: "https://t.me/nft/PlushPepe-123") == "PlushPepe-123", "Full link")
        check(Gift.slug(from: " t.me/nft/PlushPepe-1/ ") == "PlushPepe-1", "Short link, trailing slash")
        check(Gift.slug(from: "https://t.me/nft/PlushPepe-77?start=1") == "PlushPepe-77", "Query dropped")
        check(Gift.slug(from: "tg://nft?slug=DurovsCap-5") == "DurovsCap-5", "tg link")
        check(Gift.slug(from: "PlushPepe-2001") == "PlushPepe-2001", "Bare slug")
        check(Gift.slug(from: "") == nil, "Empty")
        check(Gift.slug(from: "https://t.me/durov") == nil, "Not a gift")
        check(Gift.slug(from: "PlushPepe") == nil, "No number")
        check(Gift.slug(from: "PlushPepe-12a") == nil, "Bad number")
        check(Gift.slug(from: "Plush Pepe-12") == nil, "Space in name")

        print("Fake gift: \(count) checks passed")
    }
}
