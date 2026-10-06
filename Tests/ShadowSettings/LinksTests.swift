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

        check(ShadowProfileTarget(string: "shadow://me") == .me, "My profile")
        check(ShadowProfileTarget(string: "shadow://user?id=7878830498") == .id(7878830498), "Profile by id")
        check(ShadowProfileTarget(string: "shadow://user?username=durov") == .username("durov"), "Profile by username")
        check(ShadowProfileTarget(string: "shadow://user/@durov") == .username("durov"), "Short username form")
        check(ShadowProfileTarget(string: "tg://shadow/user/123456") == .id(123456), "Short id form")
        check(ShadowProfileTarget(string: "shadow://user?id=5&name=%D0%9A%D0%B0%D1%82%D1%8F") == .id(5), "A name label is ignored")
        check(ShadowProfileTarget(string: "shadow://user") == nil, "Nobody")
        check(ShadowProfileTarget(string: "shadow://user?username=ab") == nil, "Too short a username")
        check(ShadowProfileTarget(input: "@durov") == .username("durov"), "Typed @username")
        check(ShadowProfileTarget(input: "https://t.me/durov") == .username("durov"), "Typed t.me link")
        check(ShadowProfileTarget(input: " 42 ") == .id(42), "Typed id")
        check(ShadowProfileTarget(input: "1abc") == nil, "A username cannot start with a digit")
        check(ShadowProfileTarget.id(42).link == "shadow://user?id=42", "Id link")
        check(ShadowProfileTarget.username("durov").link == "shadow://user?username=durov", "Username link")
        check(ShadowLinks.parse("shadow://user?id=5&name=%D0%9A%D0%B0%D1%82%D1%8F")?.query["name"] == "Катя", "Name label decodes")

        print("Shadow links: \(count) checks passed")
    }
}
