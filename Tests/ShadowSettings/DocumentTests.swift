import Foundation

@main
struct DocumentTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        func expectFailure(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) }
            catch { count += 1 }
        }
        func fixture(_ settings: String, version: Int = 1, format: String = "shadow-settings") -> Data {
            return Data("{\"format\":\"\(format)\",\"version\":\(version),\"exportedAt\":\"2026-09-03T12:00:00Z\",\"settings\":\(settings)}".utf8)
        }
        let document = try ShadowSettingsDocument(settings: [
            "ghostMode": .bool(true), "compactBottomBar": .bool(false),
            "editedIndicatorText": .text("✎"), "attachmentSizeLimit": .integer(12884901888)
        ], date: Date(timeIntervalSince1970: 0))
        let encoded = try document.encoded()
        let roundTrip = try ShadowSettingsDocument.decode(encoded)
        check(roundTrip == document, "Round trip must preserve all values")
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let settings = object["settings"] as! [String: Any]
        check(settings["ghostMode"] as? Bool == true, "JSON uses booleans, not Postbox's 0/1 encoding")
        check(object["format"] as? String == "shadow-settings", "Format marker")

        let ignored = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":true,\"futureOption\":{\"nested\":[1,2]},\"spoofProfilePhoneValue\":\"private\"}"))
        check(ignored.settings.count == 1, "Unknown and private fields must be ignored")
        let partial = try ShadowSettingsDocument.decode(fixture("{\"compactBottomBar\":true}"))
        check(partial.settings["ghostMode"] == nil, "Missing values must remain absent")
        expectFailure("Invalid format") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":true}", format: "other")) }
        expectFailure("Future version") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":true}", version: 2)) }
        expectFailure("Unsupported old version") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":true}", version: 0)) }
        expectFailure("Malformed JSON") { _ = try ShadowSettingsDocument.decode(Data("{".utf8)) }
        expectFailure("Invalid bool string") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":\"yes\"}")) }
        expectFailure("Numeric bool") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":1}")) }
        expectFailure("Null bool") { _ = try ShadowSettingsDocument.decode(fixture("{\"ghostMode\":null}")) }
        expectFailure("Negative cleanup interval") { _ = try ShadowSettingsDocument.decode(fixture("{\"mediaAutoCleanInterval\":-1}")) }
        expectFailure("Invalid cleanup interval") { _ = try ShadowSettingsDocument.decode(fixture("{\"mediaAutoCleanInterval\":42}")) }
        expectFailure("Integer overflow") { _ = try ShadowSettingsDocument.decode(fixture("{\"attachmentSizeLimit\":9223372036854775808}")) }
        expectFailure("Empty settings") { _ = try ShadowSettingsDocument.decode(fixture("{}")) }
        expectFailure("Only unknown fields") { _ = try ShadowSettingsDocument.decode(fixture("{\"token\":\"secret\"}")) }
        expectFailure("Large document") { _ = try ShadowSettingsDocument.decode(Data(repeating: 32, count: ShadowSettingsDocument.maximumBytes + 1)) }
        expectFailure("Private fields cannot be exported") { _ = try ShadowSettingsDocument(settings: ["spoofProfilePhoneValue": .text("secret")]) }
        expectFailure("Wrong value type on export") { _ = try ShadowSettingsDocument(settings: ["ghostMode": .integer(1)]) }
        expectFailure("Overlong marker") { _ = try ShadowSettingsDocument(settings: ["editedIndicatorText": .text(String(repeating: "a", count: 65))]) }
        let marker = try ShadowSettingsDocument(settings: ["editedIndicatorText": .text(String(repeating: "a", count: 64))])
        check(marker.settings.count == 1, "64-character marker is accepted")
        let scroll = try ShadowSettingsDocument(settings: ["bottomBarScrollMode": .integer(2)])
        check(scroll.settings["bottomBarScrollMode"] == .integer(2), "Scroll mode is portable")
        expectFailure("Unsupported scroll mode") { _ = try ShadowSettingsDocument(settings: ["bottomBarScrollMode": .integer(3)]) }
        print("Shadow settings document: \(count) checks passed")
    }
}
