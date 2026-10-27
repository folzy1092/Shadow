import Foundation

@main
struct TextDiffTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        func joined(_ segments: [ShadowTextDiff.Segment], _ kinds: Set<String>) -> String {
            return segments.filter { segment in
                switch segment.kind {
                case .same: return kinds.contains("same")
                case .deleted: return kinds.contains("deleted")
                case .inserted: return kinds.contains("inserted")
                }
            }.map(\.text).joined()
        }
        func roundTrips(_ old: String, _ new: String) -> Bool {
            let segments = ShadowTextDiff.segments(old: old, new: new)
            return joined(segments, ["same", "deleted"]) == old && joined(segments, ["same", "inserted"]) == new
        }

        check(ShadowTextDiff.tokens("Привет, мир!  Да") == ["Привет", ",", " ", "мир", "!", "  ", "Да"], "Tokens")
        check(ShadowTextDiff.tokens("") == [], "No tokens")

        let same = ShadowTextDiff.segments(old: "один два", new: "один два")
        check(same == [ShadowTextDiff.Segment(kind: .same, text: "один два")], "Unchanged text is one segment")

        let word = ShadowTextDiff.segments(old: "Теперь это считаются методом", new: "Теперь это считается методом")
        check(word == [
            .init(kind: .same, text: "Теперь это "),
            .init(kind: .deleted, text: "считаются"),
            .init(kind: .inserted, text: "считается"),
            .init(kind: .same, text: " методом")
        ], "One changed word")

        let added = ShadowTextDiff.segments(old: "a c", new: "a b c")
        check(added == [.init(kind: .same, text: "a "), .init(kind: .inserted, text: "b "), .init(kind: .same, text: "c")], "Inserted word")

        let removed = ShadowTextDiff.segments(old: "a b c", new: "a c")
        check(removed == [.init(kind: .same, text: "a "), .init(kind: .deleted, text: "b "), .init(kind: .same, text: "c")], "Deleted word")

        let phrase = ShadowTextDiff.segments(old: "x red fox y", new: "x blue cat y")
        check(phrase == [
            .init(kind: .same, text: "x "),
            .init(kind: .deleted, text: "red fox"),
            .init(kind: .inserted, text: "blue cat"),
            .init(kind: .same, text: " y")
        ], "A changed phrase stays one deletion and one insertion")

        check(ShadowTextDiff.segments(old: "", new: "новое") == [.init(kind: .inserted, text: "новое")], "From empty")
        check(ShadowTextDiff.segments(old: "старое", new: "") == [.init(kind: .deleted, text: "старое")], "To empty")
        check(ShadowTextDiff.segments(old: "", new: "").isEmpty, "Both empty")

        check(roundTrips("Строка один\nСтрока два\n\nтри 😀 четыре", "Строка один\nСтрока 2\n\nтри 😃 четыре пять"), "Round trip with lines and emoji")
        check(roundTrips("a b c d e f g", "g f e d c b a"), "Round trip reversed")

        let long = (0 ..< 1200).map { "w\($0)" }.joined(separator: " ")
        let longEdited = (0 ..< 1200).map { "v\($0)" }.joined(separator: " ")
        check(roundTrips(long, longEdited), "Round trip above the comparison limit")

        let counts = ShadowTextDiff.changedWordCounts(word)
        check(counts.deleted == 1 && counts.inserted == 1, "Changed word counts")

        print("Text diff: \(count) checks passed")
    }
}
