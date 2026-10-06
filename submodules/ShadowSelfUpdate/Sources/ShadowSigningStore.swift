import Foundation
import Security
import Zsign

// Shadow: the signing pair chosen in "Автообновление". Device-level, not per
// account: the files live in Application Support/ShadowSigning (excluded from
// iCloud/iTunes backup), the p12 password in the Keychain (this device only).
// Never exported with the settings backup and never synced between accounts.
public final class ShadowSigningStore {
    public static let shared = ShadowSigningStore()
    public static let didChangeNotification = Notification.Name("ShadowSigningStoreDidChange")

    // A real p12 is a few KB, a profile tens of KB.
    private static let maximumFileSize = 2 * 1024 * 1024
    private static let keychainService = "ShadowSigning"
    private static let keychainAccount = "p12-password"

    public enum ImportError: LocalizedError {
        case unreadable
        case tooLarge
        case notProfile

        public var errorDescription: String? {
            switch self {
            case .unreadable: return "Не удалось прочитать файл."
            case .tooLarge: return "Файл слишком большой для сертификата или профиля."
            case .notProfile: return "Это не .mobileprovision: в файле нет Team ID или App ID."
            }
        }
    }

    public let directory: URL

    public var certificateURL: URL {
        return self.directory.appendingPathComponent("signing.p12")
    }

    public var profileURL: URL {
        return self.directory.appendingPathComponent("signing.mobileprovision")
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base.appendingPathComponent("ShadowSigning", isDirectory: true)
    }

    public var hasCertificate: Bool {
        return FileManager.default.fileExists(atPath: self.certificateURL.path)
    }

    public var hasProfile: Bool {
        return FileManager.default.fileExists(atPath: self.profileURL.path)
    }

    // Both files are chosen; the password may legitimately be empty.
    public var isConfigured: Bool {
        return self.hasCertificate && self.hasProfile
    }

    public var profile: ShadowProvisioningProfile? {
        guard let data = try? Data(contentsOf: self.profileURL) else {
            return nil
        }
        return ShadowProvisioningProfile.parse(data)
    }

    public var hasPassword: Bool {
        return self.password != nil
    }

    public var password: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: ShadowSigningStore.keychainService,
                kSecAttrAccount as String: ShadowSigningStore.keychainAccount,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: ShadowSigningStore.keychainService,
                kSecAttrAccount as String: ShadowSigningStore.keychainAccount
            ]
            SecItemDelete(query as CFDictionary)
            if let newValue {
                var item = query
                item[kSecValueData as String] = Data(newValue.utf8)
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(item as CFDictionary, nil)
            }
            self.notify()
        }
    }

    public func importCertificate(from url: URL) throws {
        let data = try self.readPicked(url)
        try self.store(data, at: self.certificateURL)
    }

    @discardableResult
    public func importProfile(from url: URL) throws -> ShadowProvisioningProfile {
        let data = try self.readPicked(url)
        guard let profile = ShadowProvisioningProfile.parse(data) else {
            throw ImportError.notProfile
        }
        try self.store(data, at: self.profileURL)
        return profile
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: self.directory)
        self.password = nil
    }

    // Opens the p12 with the saved password and checks that its certificate is
    // in the profile. Slow (PKCS#12 key derivation); call off the main thread.
    // nil = the pair can sign.
    public func check() -> String? {
        guard self.hasCertificate else {
            return "Не выбран сертификат .p12"
        }
        guard self.hasProfile else {
            return "Не выбран профиль .mobileprovision"
        }
        return ShadowZsign.check(provisionPath: self.profileURL.path, p12Path: self.certificateURL.path, password: self.password ?? "")
    }

    private func readPicked(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > ShadowSigningStore.maximumFileSize {
            throw ImportError.tooLarge
        }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw ImportError.unreadable
        }
        if data.count > ShadowSigningStore.maximumFileSize {
            throw ImportError.tooLarge
        }
        return data
    }

    private func store(_ data: Data, at destination: URL) throws {
        var directory = self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        self.notify()
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: ShadowSigningStore.didChangeNotification, object: nil)
        }
    }
}
