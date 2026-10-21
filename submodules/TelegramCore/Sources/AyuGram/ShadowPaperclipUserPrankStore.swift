import Foundation

// Shadow: the user's own paperclip pranks (ShadowPaperclip, «Мои приколы»),
// kept on this device for every account, in UserDefaults as the same
// [{"title", "url"}] list the admin catalog uses. Not part of AyuGramSettings,
// so settings export and account sync do not carry it.
public enum ShadowPaperclipUserPrankStore {
    public static let didChangeNotification = Notification.Name("ShadowPaperclipUserPrankStore.didChange")
    private static let key = "shadow.paperclip.userPranks.v1"

    public static var pranks: [ShadowPaperclip.Prank] {
        guard let data = UserDefaults.standard.data(forKey: Self.key), let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return ShadowPaperclip.parsePranks(object)
    }

    public static func set(_ pranks: [ShadowPaperclip.Prank]) {
        if let data = try? JSONSerialization.data(withJSONObject: ShadowPaperclip.encodePranks(pranks)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    public static func add(title: String, link: String) -> Result<[ShadowPaperclip.Prank], ShadowPaperclip.UserPrankError> {
        let result = ShadowPaperclip.addingUserPrank(Self.pranks, title: title, link: link)
        if case let .success(updated) = result {
            Self.set(updated)
        }
        return result
    }

    public static func remove(id: String) {
        Self.set(ShadowPaperclip.removingUserPrank(Self.pranks, id: id))
    }
}
