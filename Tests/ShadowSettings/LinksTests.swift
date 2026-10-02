import Foundation

@main
struct LinksTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        check(ShadowLinks.parse("shadow://updates")?.command == "updates", "shadow:// command")
        check(ShadowLinks.parse("tg://shadow/updates")?.command == "updates", "tg://shadow/ command")
        check(ShadowLinks.parse("shadow://updates") == ShadowLinks.parse("tg://shadow/updates"), "Both forms are the same link")
        check(ShadowLinks.parse("SHADOW://Filters")?.command == "filters", "Case-insensitive")
        check(ShadowLinks.parse("shadow://")?.command == "settings", "Empty link opens settings")
        check(ShadowLinks.parse("tg://shadow")?.command == "settings", "Bare tg://shadow opens settings")
        let access = ShadowLinks.parse("tg://shadow/access?id=AB12-CD34-EF56-7890")
        check(access?.command == "access" && access?.query["id"] == "AB12-CD34-EF56-7890", "Query parsed")
        check(ShadowLinks.parse("shadow://access?id=AB12") == ShadowLinks.parse("tg://shadow/access?id=AB12"), "Query in both forms")
        check(ShadowLinks.parse("shadow://a/b/c")?.arguments == ["b", "c"], "Arguments")
        check(ShadowLinks.parse("tg://resolve?domain=durov") == nil, "Other tg links are not Shadow links")
        check(ShadowLinks.parse("tg://shadowban") == nil, "tg://shadow prefix needs a separator")
        check(ShadowLinks.parse("https://shadow.example") == nil, "Web links are not Shadow links")

        let text = "Открой shadow://updates, а потом tg://shadow/filters. И google.com"
        let string = text as NSString
        let found = ShadowLinks.ranges(in: text).map { string.substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }
        check(found == ["shadow://updates", "tg://shadow/filters"], "Links found, trailing punctuation dropped")
        check(ShadowLinks.ranges(in: "без ссылок").isEmpty, "No links")
        check(ShadowLinks.ranges(in: "tg://resolve?domain=x").isEmpty, "Other tg links are ignored")

        print("Shadow links: \(count) checks passed")
    }
}
