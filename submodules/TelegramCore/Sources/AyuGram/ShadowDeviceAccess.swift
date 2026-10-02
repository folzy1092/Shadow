import Foundation
import Security

// Shadow: device whitelist. The app makes up its own device id (UDID is not
// readable by apps), keeps it in the Keychain so it survives reinstalls signed
// by the same team, and compares it with shadow-whitelist.json on master.
public enum ShadowDeviceAccess {
    public static let adminPeerId: Int64 = 7878830498
    // Admins: the owner (Folzy) and matey. They pass the whitelist, see
    // "Доступ устройств" and open shadow://access links.
    public static let adminPeerIds: Set<Int64> = [adminPeerId, 1068369028]

    public static func isAdmin(peerId: Int64) -> Bool {
        return adminPeerIds.contains(peerId)
    }
    public static let whitelistURL = URL(string: "https://raw.githubusercontent.com/folzy1092/tgfork/main/shadow-whitelist.json")!
    public static let editURL = URL(string: "https://github.com/folzy1092/tgfork/edit/main/shadow-whitelist.json")!

    public struct Device: Equatable {
        public let id: String
        public let note: String
        public init(id: String, note: String) {
            self.id = ShadowDeviceAccess.normalize(id)
            self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public struct Whitelist: Equatable {
        public let enabled: Bool
        public let devices: [Device]
        // Access-request endpoint (the Cloudflare Worker in tools/shadow-bot):
        // "Запросить доступ" on the gate posts the device id there and the
        // owner gets a bot message with a button. nil hides the button.
        public let requestURL: URL?
        public init(enabled: Bool, devices: [Device], requestURL: URL? = nil) {
            self.enabled = enabled
            self.devices = devices
            self.requestURL = requestURL
        }
    }

    public enum Decision: Equatable {
        case allowed
        case denied
        case unknown
    }

    public static func normalize(_ id: String) -> String {
        return id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func parse(_ data: Data) -> Whitelist? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let enabled = (object["enabled"] as? Bool) ?? true
        var devices: [Device] = []
        for entry in (object["devices"] as? [[String: Any]]) ?? [] {
            guard let id = entry["id"] as? String, !normalize(id).isEmpty else {
                continue
            }
            devices.append(Device(id: id, note: (entry["note"] as? String) ?? ""))
        }
        var requestURL: URL?
        if let string = object["request_url"] as? String, let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https" {
            requestURL = url
        }
        return Whitelist(enabled: enabled, devices: devices, requestURL: requestURL)
    }

    // Body of an access request: the device id plus what helps the owner tell
    // who is asking. `name` is whatever the person typed, possibly empty.
    public static func accessRequestBody(deviceId: String, name: String, model: String, system: String, build: String) -> Data {
        let object: [String: String] = [
            "id": normalize(deviceId),
            "name": String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)),
            "model": model,
            "system": system,
            "build": build
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    public static func decide(deviceId: String, whitelist: Whitelist?) -> Decision {
        guard let whitelist else {
            return .unknown
        }
        if !whitelist.enabled {
            return .allowed
        }
        let id = normalize(deviceId)
        return whitelist.devices.contains(where: { $0.id == id }) ? .allowed : .denied
    }

    public static func encode(_ whitelist: Whitelist) -> String {
        var object: [String: Any] = [
            "enabled": whitelist.enabled,
            "devices": whitelist.devices.map { ["id": $0.id, "note": $0.note] }
        ]
        // Kept, so copying the list from the admin menu does not drop the bot.
        if let requestURL = whitelist.requestURL {
            object["request_url"] = requestURL.absoluteString
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Device id (Keychain)

    private static let keychainService = "shadow.device-access"
    private static let keychainAccount = "device-id"
    private static let lock = NSLock()
    private static var cachedDeviceId: String?

    // Empty while the Keychain is unavailable (the app was woken in the
    // background before the first unlock after a reboot). A new id is minted
    // only when the item really does not exist; otherwise a locked Keychain
    // would hand out a random id for the whole process lifetime.
    public static var deviceId: String {
        lock.lock()
        defer { lock.unlock() }
        if let cachedDeviceId {
            return cachedDeviceId
        }
        switch readKeychain() {
        case let .value(value):
            cachedDeviceId = value
            return value
        case .unavailable:
            return ""
        case .missing:
            let generated = makeDeviceId()
            switch addKeychain(generated) {
            case .added:
                cachedDeviceId = generated
                return generated
            case .duplicate:
                // Another launch path stored one first; use it.
                if case let .value(value) = readKeychain() {
                    cachedDeviceId = value
                    return value
                }
                return ""
            case .failed:
                return ""
            }
        }
    }

    private static func makeDeviceId() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
        var groups: [String] = []
        var index = raw.startIndex
        while index < raw.endIndex {
            let end = raw.index(index, offsetBy: 4)
            groups.append(String(raw[index ..< end]))
            index = end
        }
        return groups.joined(separator: "-")
    }

    private enum KeychainRead {
        case value(String)
        case missing
        case unavailable
    }

    private enum KeychainAdd {
        case added
        case duplicate
        case failed
    }

    private static func baseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func readKeychain() -> KeychainRead {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return .missing
        }
        guard status == errSecSuccess, let data = result as? Data else {
            return .unavailable
        }
        let value = normalize(String(decoding: data, as: UTF8.self))
        return value.isEmpty ? .missing : .value(value)
    }

    private static func addKeychain(_ value: String) -> KeychainAdd {
        var query = baseQuery()
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        switch SecItemAdd(query as CFDictionary, nil) {
        case errSecSuccess:
            return .added
        case errSecDuplicateItem:
            return .duplicate
        default:
            return .failed
        }
    }

    // MARK: - Whitelist cache and fetch

    private static var cacheURL: URL? {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("shadow-whitelist-cache.json")
    }

    public static var cachedWhitelist: Whitelist? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return parse(data)
    }

    public static func refresh(completion: @escaping (Whitelist?) -> Void) {
        var request = URLRequest(url: whitelistURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15.0
        URLSession.shared.dataTask(with: request) { data, response, error in
            var result: Whitelist?
            if error == nil, let status = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(status), let data, let list = parse(data) {
                result = list
                if let url = cacheURL {
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: url, options: .atomic)
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }
}
