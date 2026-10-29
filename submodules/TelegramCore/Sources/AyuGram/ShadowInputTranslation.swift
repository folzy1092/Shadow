import Foundation

// Shadow: «Перевод при отправке» (2.0.0). The user keeps up to maxTemplates
// language pairs in settings (AyuGramSettings.inputTranslateTemplates,
// "ru>en,ru>kk"). Turning the translation on (formatting panel, paperclip)
// asks which pair to use; from then on, in every chat, the text of each sent
// message is translated before it leaves (ChatControllerImpl.sendMessages):
// the phone translates (Apple Translation, iOS 18+), else Telegram's server.
// Turning it off and on again asks for the pair again. The active pair is
// device state, kept in UserDefaults, not a setting.
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowInputTranslation {
    public static let maxTemplates = 10
    public static let defaultTemplates = "ru>en"

    public struct Template: Equatable, Hashable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }

        public var storageId: String {
            return "\(self.from)>\(self.to)"
        }

        // «Русский → Английский».
        public var title: String {
            return "\(ShadowInputTranslation.languageName(self.from)) → \(ShadowInputTranslation.languageName(self.to))"
        }

        // «RU → EN», for the input placeholder.
        public var shortTitle: String {
            return "\(self.from.uppercased()) → \(self.to.uppercased())"
        }

        public init?(storageId: String) {
            let parts = storageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: ">", omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                return nil
            }
            let from = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let to = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard ShadowInputTranslation.isLanguageCode(from), ShadowInputTranslation.isLanguageCode(to), from != to else {
                return nil
            }
            self.from = from
            self.to = to
        }
    }

    // The languages offered when a pair is made, in this order. Apple
    // Translation covers only some of them; the rest go to the server.
    public static let languages: [String] = [
        "ru", "en", "kk", "tr", "uk", "uz", "ky", "tg", "az", "hy", "ka", "be",
        "de", "fr", "es", "it", "pt", "pl", "cs", "nl", "ro", "sr", "bg",
        "zh", "ja", "ko", "ar", "fa", "he", "hi", "id", "th", "vi"
    ]

    static func isLanguageCode(_ value: String) -> Bool {
        guard value.count >= 2, value.count <= 3 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { $0.value >= 97 && $0.value <= 122 }
    }

    public static func languageName(_ code: String) -> String {
        let name = Locale(identifier: "ru").localizedString(forLanguageCode: code) ?? code.uppercased()
        guard let first = name.first else {
            return code.uppercased()
        }
        return String(first).uppercased() + name.dropFirst()
    }

    // Known pairs, in order, without duplicates, at most maxTemplates.
    public static func parseTemplates(_ value: String) -> [Template] {
        var result: [Template] = []
        for part in value.split(separator: ",") {
            guard let template = Template(storageId: String(part)), !result.contains(template) else {
                continue
            }
            result.append(template)
            if result.count == maxTemplates {
                break
            }
        }
        return result
    }

    public static func encodeTemplates(_ templates: [Template]) -> String {
        return templates.prefix(maxTemplates).map { $0.storageId }.joined(separator: ",")
    }

    public static func normalizedTemplates(_ value: String) -> String {
        return encodeTemplates(parseTemplates(value))
    }

    public enum AddError: Error, Equatable {
        case sameLanguage
        case duplicate
        case full
    }

    public static func adding(_ templates: [Template], from: String, to: String) -> Result<[Template], AddError> {
        guard from != to else {
            return .failure(.sameLanguage)
        }
        guard let template = Template(storageId: "\(from)>\(to)") else {
            return .failure(.sameLanguage)
        }
        if templates.contains(template) {
            return .failure(.duplicate)
        }
        if templates.count >= maxTemplates {
            return .failure(.full)
        }
        return .success(templates + [template])
    }

    public static func removing(_ templates: [Template], _ template: Template) -> [Template] {
        return templates.filter { $0 != template }
    }

    // A message text worth translating: not empty, not a bot command.
    public static func isTranslatable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("/")
    }

    // MARK: Active pair (device state)

    public static let didChangeNotification = Notification.Name("ShadowInputTranslationDidChange")
    private static let activeKey = "shadow.inputTranslation.active.v1"

    public static var activeTemplate: Template? {
        get {
            return UserDefaults.standard.string(forKey: activeKey).flatMap(Template.init(storageId:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.storageId, forKey: activeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeKey)
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
