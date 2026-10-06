import Foundation
import Security

// Shadow: the TLS identity of the local install server. itms-services only
// accepts an https manifest with a publicly trusted certificate, so, like
// Feather, the server uses the public *.backloop.dev pack (any subdomain
// resolves to 127.0.0.1). The certificate lives ~90 days, so the pack is
// fetched at update time and cached until it nears expiry.
//
// iOS has no public API to build a SecIdentity from a key and a certificate;
// both are stored in the app's Keychain and the identity is read back.
enum ShadowLocalTLSIdentity {
    static let packURL = URL(string: "https://backloop.dev/pack.json")!
    static let host = "shadow.backloop.dev"
    private static let label = "ShadowLocalInstall"
    private static let keyTag = Data("ph.shadow.local-install.key".utf8)

    struct Material {
        let identity: SecIdentity
        // Leaf first, then intermediates.
        let chain: [SecCertificate]
    }

    enum IdentityError: LocalizedError {
        case download(String)
        case badPack
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .download(reason): return "Не удалось скачать сертификат для локальной установки: \(reason)"
            case .badPack: return "Сертификат для локальной установки повреждён."
            case let .keychain(status): return "Keychain не принял сертификат локальной установки (код \(status))."
            }
        }
    }

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("shadow-backloop-pack.json")
    }

    static func load(completion: @escaping (Result<Material, Error>) -> Void) {
        if let data = try? Data(contentsOf: self.cacheURL), let material = try? self.material(from: data, requireFreshFor: 24 * 60 * 60) {
            completion(.success(material))
            return
        }
        var request = URLRequest(url: self.packURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.0)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        URLSession.shared.dataTask(with: request, completionHandler: { data, _, error in
            guard let data else {
                completion(.failure(IdentityError.download(error?.localizedDescription ?? "нет ответа")))
                return
            }
            do {
                let material = try self.material(from: data, requireFreshFor: 0)
                try? data.write(to: self.cacheURL, options: .atomic)
                completion(.success(material))
            } catch {
                completion(.failure(error))
            }
        }).resume()
    }

    private static func material(from data: Data, requireFreshFor interval: TimeInterval) throws -> Material {
        guard let pack = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let certPem = pack["cert"] as? String,
              let key1 = pack["key1"] as? String,
              let key2 = pack["key2"] as? String else {
            throw IdentityError.badPack
        }
        let leafs = derBlocks(pem: certPem)
        let intermediates = derBlocks(pem: pack["ca"] as? String ?? "")
        // key1 stops in the middle of a base64 line; key2 continues it.
        guard let leafData = leafs.first,
              let leaf = SecCertificateCreateWithData(nil, leafData as CFData),
              let pkcs8 = derBlocks(pem: key1 + key2).first,
              let pkcs1 = rsaPrivateKey(fromPKCS8: pkcs8) else {
            throw IdentityError.badPack
        }
        if interval > 0 {
            guard let notAfter = (pack["info"] as? [String: Any])?["notAfter"] as? String,
                  let date = ISO8601DateFormatter.withFractions.date(from: notAfter) ?? ISO8601DateFormatter().date(from: notAfter),
                  date.timeIntervalSinceNow > interval else {
                throw IdentityError.badPack
            }
        }
        var keyError: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &keyError) else {
            keyError?.release()
            throw IdentityError.badPack
        }
        let identity = try self.storeAndReadIdentity(key: key, certificate: leaf)
        let chain = [leaf] + intermediates.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        return Material(identity: identity, chain: chain)
    }

    private static func storeAndReadIdentity(key: SecKey, certificate: SecCertificate) throws -> SecIdentity {
        // Replace whatever an older pack left.
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: self.keyTag] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: self.label] as CFDictionary)

        let keyStatus = SecItemAdd([
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: key,
            kSecAttrApplicationTag as String: self.keyTag,
            kSecAttrLabel as String: self.label,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ] as CFDictionary, nil)
        guard keyStatus == errSecSuccess || keyStatus == errSecDuplicateItem else {
            throw IdentityError.keychain(keyStatus)
        }
        let certificateStatus = SecItemAdd([
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: self.label,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ] as CFDictionary, nil)
        guard certificateStatus == errSecSuccess || certificateStatus == errSecDuplicateItem else {
            throw IdentityError.keychain(certificateStatus)
        }

        // The identity takes the certificate's label.
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: self.label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let result, CFGetTypeID(result) == SecIdentityGetTypeID() else {
            throw IdentityError.keychain(status == errSecSuccess ? errSecItemNotFound : status)
        }
        return result as! SecIdentity
    }

    static func derBlocks(pem: String) -> [Data] {
        var result: [Data] = []
        var body: String?
        for rawLine in pem.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-----BEGIN") {
                body = ""
            } else if line.hasPrefix("-----END") {
                if let text = body, let data = Data(base64Encoded: text) {
                    result.append(data)
                }
                body = nil
            } else if body != nil {
                body! += line
            }
        }
        return result
    }

    // PrivateKeyInfo { version, AlgorithmIdentifier, OCTET STRING { RSAPrivateKey } }
    static func rsaPrivateKey(fromPKCS8 data: Data) -> Data? {
        let bytes = [UInt8](data)
        var index = 0
        func readHeader(expecting tag: UInt8) -> Int? {
            guard index < bytes.count, bytes[index] == tag else {
                return nil
            }
            index += 1
            guard index < bytes.count else {
                return nil
            }
            var length = Int(bytes[index])
            index += 1
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard count > 0, count <= 4, index + count <= bytes.count else {
                    return nil
                }
                length = 0
                for _ in 0 ..< count {
                    length = (length << 8) | Int(bytes[index])
                    index += 1
                }
            }
            return index + length <= bytes.count ? length : nil
        }
        guard readHeader(expecting: 0x30) != nil else { return nil }
        guard let versionLength = readHeader(expecting: 0x02) else { return nil }
        index += versionLength
        guard let algorithmLength = readHeader(expecting: 0x30) else { return nil }
        index += algorithmLength
        guard let keyLength = readHeader(expecting: 0x04) else { return nil }
        return Data(bytes[index ..< index + keyLength])
    }
}

private extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
