import Foundation

@main
struct InputTranslationTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        typealias Translation = ShadowInputTranslation
        typealias Template = ShadowInputTranslation.Template

        check(Translation.parseTemplates(Translation.defaultTemplates) == [Template(from: "ru", to: "en")], "Default pair")
        check(Translation.parseTemplates(" RU>EN ,ru>kk,ru>en,ru>ru,x>en,ru>,>en,russian>en,ru>tr") == [Template(from: "ru", to: "en"), Template(from: "ru", to: "kk"), Template(from: "ru", to: "tr")], "Bad, same-language and duplicate pairs dropped, case folded")
        let many = Translation.languages.dropFirst().map { "ru>\($0)" }.joined(separator: ",")
        check(Translation.parseTemplates(many).count == Translation.maxTemplates, "At most 10 pairs")
        check(Translation.normalizedTemplates("ru>kk, ru>en") == "ru>kk,ru>en", "Order kept")
        check(Template(storageId: "ru>en")?.shortTitle == "RU → EN", "Short title")
        check(Template(storageId: "ru>en")?.title == "Русский → Английский", "Russian language names, capitalised")

        let base = [Template(from: "ru", to: "en")]
        check(Translation.adding(base, from: "ru", to: "kk") == .success(base + [Template(from: "ru", to: "kk")]), "Pair added at the end")
        check(Translation.adding(base, from: "ru", to: "en") == .failure(.duplicate), "Duplicate refused")
        check(Translation.adding(base, from: "ru", to: "ru") == .failure(.sameLanguage), "Same language refused")
        let full = Translation.parseTemplates(many)
        check(Translation.adding(full, from: "en", to: "ru") == .failure(.full), "No 11th pair")
        check(Translation.removing(base + [Template(from: "ru", to: "kk")], Template(from: "ru", to: "en")) == [Template(from: "ru", to: "kk")], "Pair removed")

        check(Translation.isTranslatable("Привет"), "Text is translated")
        check(!Translation.isTranslatable("   \n"), "Blank is not")
        check(!Translation.isTranslatable(" /start"), "Bot command is not")

        print("Input translation: \(count) checks passed")
    }
}
