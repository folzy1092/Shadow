import Foundation
@main struct ScreenshotAnonymizerTests {
    static func main() {
        let value = ShadowScreenshotAnonymizer()
        let alice = value.register(id: 1, names: ["Алиса"], usernames: ["alice_test"], phone: "79991234567")
        value.register(id: 2, names: ["Борис"], usernames: ["boris_test"], phone: "78881234567", redact: false)
        let result = value.redact("😀 Алиса @alice_test https://t.me/alice_test +7 (999) 123-45-67 Борис @boris_test", redactUnknownIdentifiers: false)
        precondition(!result.contains("Алиса") && !result.contains("alice_test") && !result.contains("999"))
        precondition(result.contains(alice) && result.contains("Борис @boris_test"))
        precondition(!result.contains("https://"))
        let source = "😀 Алиса и Борис" as NSString
        let entity = ShadowScreenshotAnonymizer.Replacement(range: source.range(of: "Борис"), text: "выбранный участник")
        precondition(value.redact(source as String, replacements: [entity], redactUnknownIdentifiers: false).contains("выбранный участник"))
        let invalid = ShadowScreenshotAnonymizer.Replacement(range: NSRange(location: Int.max, length: 1), text: "x")
        precondition(value.redact("текст", replacements: [invalid], redactUnknownIdentifiers: false) == "текст")
        value.register(id: 3, names: ["Алиса"], usernames: [], phone: nil, redact: false)
        precondition(value.redact("Алиса", redactUnknownIdentifiers: false) == "Алиса")
        precondition(ShadowScreenshotAnonymizer().label(for: 42) == "Участник 1")
        let unknown = value.redact("@unknown_user https://t.me/unknown_user +7 123 456 78 90")
        precondition(!unknown.contains("unknown_user") && !unknown.contains("123"))
        print("Screenshot anonymization: selected identities, UTF-16, overlaps and visible peers passed")
    }
}
