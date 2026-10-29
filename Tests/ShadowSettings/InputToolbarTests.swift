import Foundation

@main
struct InputToolbarTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        typealias Toolbar = ShadowInputToolbar

        let defaults = Toolbar.parseButtons(Toolbar.defaultButtons)
        check(defaults == [.newLine, .clearFormatting, .quote, .spoiler, .bold, .italic, .date, .monospace, .link, .underline, .strikethrough, .code], "Swiftgram's buttons by default")
        check(Toolbar.parseButtons("b, b,zz,,tr,top") == [.bold, .translate, .scrollToStart], "Unknown and duplicate buttons dropped")
        check(Toolbar.encodeButtons([.mentionAll, .bold]) == "ma,b", "Encode keeps order")
        check(Toolbar.normalizedButtons(Toolbar.defaultButtons) == Toolbar.defaultButtons, "Defaults are normal")
        check(Toolbar.toggled([.bold, .italic], .bold) == [.italic], "Uncheck")
        check(Toolbar.toggled([.italic], .bold) == [.italic, .bold], "Check appends")
        check(Toolbar.Button.allCases.allSatisfy { !$0.title.isEmpty }, "Every button has a title")
        check(Toolbar.Button.translate.tool == .translate && Toolbar.Button.bold.tool == nil, "Tools map to the chat tools")
        check(Toolbar.Button.bold.formatsSelection && !Toolbar.Button.newLine.formatsSelection && !Toolbar.Button.mentionAll.formatsSelection, "Only formatting acts on the selection")

        check(Toolbar.lastWordRange(in: "привет мир", caret: 10) == NSRange(location: 7, length: 3), "Last word at the end")
        check(Toolbar.lastWordRange(in: "привет мир ", caret: 11) == NSRange(location: 7, length: 3), "Trailing space skipped")
        check(Toolbar.lastWordRange(in: "привет мир", caret: 6) == NSRange(location: 0, length: 6), "Word before the caret in the middle")
        check(Toolbar.lastWordRange(in: "   ", caret: 3) == nil, "No word")
        check(Toolbar.lastWordRange(in: "", caret: 0) == nil, "Empty")
        check(Toolbar.lastWordRange(in: "a\nb", caret: 99) == NSRange(location: 2, length: 1), "Caret clamped, newline separates")

        print("Input toolbar: \(count) checks passed")
    }
}
