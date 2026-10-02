import Foundation

@main
struct MessageFiltersTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        check(ShadowMessageFilter.isValid(expression: "реклама|@alfa\\w+"), "Valid regex")
        check(!ShadowMessageFilter.isValid(expression: "(unclosed"), "Invalid regex")
        check(!ShadowMessageFilter.isValid(expression: "  "), "Blank expression")

        let plain = ShadowMessageFilter(id: 1, expression: "реклама")
        check(ShadowMessageFilterMatcher(filters: [plain]).hides(text: "Тут РЕКЛАМА канала"), "Case-insensitive by default")
        let strict = ShadowMessageFilter(id: 2, expression: "Реклама", caseInsensitive: false)
        check(!ShadowMessageFilterMatcher(filters: [strict]).hides(text: "реклама"), "Case-sensitive")
        let disabled = ShadowMessageFilter(id: 3, expression: "реклама", enabled: false)
        check(!ShadowMessageFilterMatcher(filters: [disabled]).hides(text: "реклама"), "Disabled filter ignored")
        check(ShadowMessageFilterMatcher(filters: [disabled]).isEmpty, "Only disabled filters — empty")
        let reversed = ShadowMessageFilter(id: 4, expression: "важно", reversed: true)
        check(ShadowMessageFilterMatcher(filters: [reversed]).hides(text: "просто текст"), "Reversed hides non-matching")
        check(!ShadowMessageFilterMatcher(filters: [reversed]).hides(text: "это важно"), "Reversed keeps matching")
        check(!ShadowMessageFilterMatcher(filters: [reversed]).hides(text: ""), "Reversed keeps messages without text")
        let broken = ShadowMessageFilter(id: 5, expression: "(unclosed")
        check(!ShadowMessageFilterMatcher(filters: [broken]).hides(text: "(unclosed"), "Broken regex never matches")

        check(ShadowMessageFilter.escaped("a.b") == "a\\.b", "Escaping")
        let migrated = ShadowMessageFilter.migrated(phrases: ["a.b", " ", "@domrf_bank"])
        check(migrated.map { $0.expression } == ["a\\.b", "@domrf_bank"], "Migration escapes and drops blanks")
        check(migrated.allSatisfy { $0.enabled && $0.caseInsensitive && !$0.reversed }, "Migration defaults")
        check(Set(migrated.map { $0.id }).count == 2, "Migration ids unique")
        check(ShadowMessageFilterMatcher(filters: migrated).hides(text: "пишет @DOMRF_BANK"), "Migrated phrase still matches")

        print("Shadow message filters: \(count) checks passed")
    }
}
