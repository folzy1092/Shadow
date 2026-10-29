import Foundation

// Shadow: «Панель форматирования» (2.0.0), ported from Swiftgram's
// SGInputToolbar: a row of round buttons under the chat input field while it
// has focus. AyuGramSettings.inputToolbar turns it on; the buttons, in order,
// are AyuGramSettings.inputToolbarButtons ("nl,cl,q,sp,b,i"), chosen in
// «Кнопки панели» like the paperclip actions. Besides formatting it can hold
// the chat tools (ShadowPaperclip.Tool): translation, «Упомянуть всех»,
// «К началу переписки».
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowInputToolbar {
    public enum Button: String, CaseIterable {
        case newLine = "nl"
        case clearFormatting = "cl"
        case quote = "q"
        case spoiler = "sp"
        case bold = "b"
        case italic = "i"
        case underline = "u"
        case strikethrough = "s"
        case monospace = "m"
        case code = "c"
        case link = "l"
        case date = "d"
        case translate = "tr"
        case mentionAll = "ma"
        case scrollToStart = "top"

        public var title: String {
            switch self {
            case .newLine: return "Новая строка"
            case .clearFormatting: return "Убрать форматирование"
            case .quote: return "Цитата"
            case .spoiler: return "Спойлер"
            case .bold: return "Жирный"
            case .italic: return "Курсив"
            case .underline: return "Подчёркнутый"
            case .strikethrough: return "Зачёркнутый"
            case .monospace: return "Моноширинный"
            case .code: return "Блок кода"
            case .link: return "Ссылка"
            case .date: return "Дата"
            case .translate: return "Перевод при отправке"
            case .mentionAll: return "Упомянуть всех"
            case .scrollToStart: return "К началу переписки"
            }
        }

        // SF Symbol; nil for the monospace button, which is a monospaced «M».
        public var icon: String? {
            switch self {
            case .newLine: return "return"
            case .clearFormatting: return "pencil.slash"
            case .quote: return "text.quote"
            case .spoiler: return "eye.slash"
            case .bold: return "bold"
            case .italic: return "italic"
            case .underline: return "underline"
            case .strikethrough: return "strikethrough"
            case .monospace: return nil
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .link: return "link"
            case .date: return "calendar"
            case .translate: return "character.bubble"
            case .mentionAll: return "at"
            case .scrollToStart: return "arrow.up.to.line"
            }
        }

        // Formatting buttons act on the selection, or on the last word when
        // nothing is selected (as in Swiftgram).
        public var formatsSelection: Bool {
            switch self {
            case .quote, .spoiler, .bold, .italic, .underline, .strikethrough, .monospace, .code, .link, .date:
                return true
            default:
                return false
            }
        }

        public var tool: ShadowPaperclip.Tool? {
            switch self {
            case .translate: return .translate
            case .mentionAll: return .mentionAll
            case .scrollToStart: return .scrollToStart
            default: return nil
            }
        }
    }

    // Swiftgram's order.
    public static let defaultButtons = "nl,cl,q,sp,b,i,d,m,l,u,s,c"

    public static func parseButtons(_ value: String) -> [Button] {
        var result: [Button] = []
        for part in value.split(separator: ",") {
            guard let button = Button(rawValue: part.trimmingCharacters(in: .whitespaces)), !result.contains(button) else {
                continue
            }
            result.append(button)
        }
        return result
    }

    public static func encodeButtons(_ buttons: [Button]) -> String {
        return buttons.map { $0.rawValue }.joined(separator: ",")
    }

    public static func normalizedButtons(_ value: String) -> String {
        return encodeButtons(parseButtons(value))
    }

    // Checks or unchecks a button; a checked one goes to the end.
    public static func toggled(_ buttons: [Button], _ button: Button) -> [Button] {
        if let index = buttons.firstIndex(of: button) {
            var result = buttons
            result.remove(at: index)
            return result
        }
        return buttons + [button]
    }

    // The range of the word right before the caret (UTF-16), for a formatting
    // button pressed with nothing selected; nil when there is no such word.
    public static func lastWordRange(in text: String, caret: Int) -> NSRange? {
        let string = text as NSString
        var end = min(max(caret, 0), string.length)
        let separators = CharacterSet.whitespacesAndNewlines
        // Spaces right before the caret are skipped: «привет |» formats «привет».
        while end > 0, let scalar = UnicodeScalar(string.character(at: end - 1)), separators.contains(scalar) {
            end -= 1
        }
        var start = end
        while start > 0 {
            let unit = string.character(at: start - 1)
            if let scalar = UnicodeScalar(unit), separators.contains(scalar) {
                break
            }
            start -= 1
        }
        if start == end {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }
}
