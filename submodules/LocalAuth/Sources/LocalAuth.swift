import Foundation
import LocalAuthentication
import SwiftSignalKit
import Security

public enum LocalAuthBiometricAuthentication {
    case touchId
    case faceId
}

public struct LocalAuth {
    private static let customKeyIdPrefix = "$#_".data(using: .utf8)!
    
    public enum DecryptionResult {
        public enum Error {
            case cancelled
            case generic
        }
        
        case result(Data)
        case error(Error)
    }
    
    #if targetEnvironment(simulator)
    public final class PrivateKey {
        public let publicKeyRepresentation: Data
        
        fileprivate init() {
            self.publicKeyRepresentation = Data(count: 32)
        }
        
        public func encrypt(data: Data) -> Data? {
            return data
        }
        
        public func decrypt(data: Data) -> DecryptionResult {
            return .result(data)
        }
    }
    #else
    public final class PrivateKey {
        private let privateKey: SecKey
        private let publicKey: SecKey
        public let publicKeyRepresentation: Data
        
        fileprivate init(privateKey: SecKey, publicKey: SecKey, publicKeyRepresentation: Data) {
            self.privateKey = privateKey
            self.publicKey = publicKey
            self.publicKeyRepresentation = publicKeyRepresentation
        }
        
        public func encrypt(data: Data) -> Data? {
            var error: Unmanaged<CFError>?
            let cipherText = SecKeyCreateEncryptedData(self.publicKey, .eciesEncryptionCofactorVariableIVX963SHA512AESGCM, data as CFData, &error)
            if let error {
                error.release()
            }
            guard let cipherText else {
                return nil
            }
            
            let result = cipherText as Data
            return result
        }
        
        public func decrypt(data: Data) -> DecryptionResult {
            var maybeError: Unmanaged<CFError>?
            let plainText = SecKeyCreateDecryptedData(self.privateKey, .eciesEncryptionCofactorVariableIVX963SHA512AESGCM, data as CFData, &maybeError)
            let error = maybeError?.takeRetainedValue()
            
            guard let plainText else {
                if let error {
                    if CFErrorGetCode(error) == -2 {
                        return .error(.cancelled)
                    }
                }
                return .error(.generic)
            }
            
            let result = plainText as Data
            return .result(result)
        }
    }
    #endif
    
    public static var biometricAuthentication: LocalAuthBiometricAuthentication? {
        let context = LAContext()
        if context.canEvaluatePolicy(LAPolicy(rawValue: Int(kLAPolicyDeviceOwnerAuthenticationWithBiometrics))!, error: nil) {
            switch context.biometryType {
            case .faceID, .opticID:
                return .faceId
            case .touchID:
                return .touchId
            case .none:
                return nil
            @unknown default:
                return nil
            }
        } else {
            return nil
        }
    }
    
    public static let evaluatedPolicyDomainState: Data? = {
        let context = LAContext()
        if context.canEvaluatePolicy(LAPolicy(rawValue: Int(kLAPolicyDeviceOwnerAuthenticationWithBiometrics))!, error: nil) {
            if #available(iOSApplicationExtension 9.0, iOS 9.0, *) {
                return context.evaluatedPolicyDomainState
            } else {
                return Data()
            }
        }
        return nil
    }()
    
    public static func auth(reason: String) -> Signal<(Bool, Data?), NoError> {
        return Signal { subscriber in
            let context = LAContext()
            
            if LAContext().canEvaluatePolicy(LAPolicy(rawValue: Int(kLAPolicyDeviceOwnerAuthenticationWithBiometrics))!, error: nil) {
                context.evaluatePolicy(LAPolicy(rawValue: Int(kLAPolicyDeviceOwnerAuthenticationWithBiometrics))!, localizedReason: reason, reply: { result, _ in
                    let evaluatedPolicyDomainState: Data?
                    if #available(iOSApplicationExtension 9.0, iOS 9.0, *) {
                        evaluatedPolicyDomainState = context.evaluatedPolicyDomainState
                    } else {
                        evaluatedPolicyDomainState = Data()
                    }
                    subscriber.putNext((result, evaluatedPolicyDomainState))
                    subscriber.putCompletion()
                })
            } else {
                subscriber.putNext((false, nil))
                subscriber.putCompletion()
            }
            
            return ActionDisposable {
                if #available(iOSApplicationExtension 9.0, iOS 9.0, *) {
                    context.invalidate()
                }
            }
        }
    }
    
    // Shadow: like auth(reason:), but also tells whether the biometrics did not
    // recognize the user (LAError.authenticationFailed) — as opposed to a
    // cancel, the password fallback or biometrics being unavailable.
    public static func authDetailed(reason: String) -> Signal<(success: Bool, domainState: Data?, biometryRejected: Bool), NoError> {
        return Signal { subscriber in
            let context = LAContext()
            let policy = LAPolicy(rawValue: Int(kLAPolicyDeviceOwnerAuthenticationWithBiometrics))!
            if LAContext().canEvaluatePolicy(policy, error: nil) {
                context.evaluatePolicy(policy, localizedReason: reason, reply: { result, error in
                    let rejected = !result && (error as? LAError)?.code == .authenticationFailed
                    subscriber.putNext((result, context.evaluatedPolicyDomainState, rejected))
                    subscriber.putCompletion()
                })
            } else {
                subscriber.putNext((false, nil, false))
                subscriber.putCompletion()
            }
            return ActionDisposable {
                context.invalidate()
            }
        }
    }

    private static func bundleSeedId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrAccount as String: "bundleSeedID",
            kSecAttrService as String: "",
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            status = SecItemAdd(query as CFDictionary, &result)
        }
        if status != errSecSuccess {
            return nil
        }
        guard let result = result else {
            return nil
        }
        if CFGetTypeID(result) != CFDictionaryGetTypeID() {
            return nil
        }
        guard let resultDict = (result as! CFDictionary) as? [String: Any] else {
            return nil
        }
        guard let accessGroup = resultDict[kSecAttrAccessGroup as String] as? String else {
            return nil
        }
        let components = accessGroup.components(separatedBy: ".")
        guard let seedId = components.first else {
            return nil
        }
        return seedId;
    }
    
    public static func getOrCreatePrivateKey(baseAppBundleId: String, keyId: Data) -> PrivateKey? {
        if let key = self.getPrivateKey(baseAppBundleId: baseAppBundleId, keyId: keyId) {
            return key
        } else {
            return self.addPrivateKey(baseAppBundleId: baseAppBundleId, keyId: keyId)
        }
    }
    
    private static func getPrivateKey(baseAppBundleId: String, keyId: Data) -> PrivateKey? {
        #if targetEnvironment(simulator)
        return PrivateKey()
        #else
        guard let bundleSeedId = self.bundleSeedId() else {
            return nil
        }
        
        let applicationTag = customKeyIdPrefix + keyId
        let accessGroup = "\(bundleSeedId).\(baseAppBundleId)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey as String,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom as String,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnRef as String: true
        ]
        
        var maybePrivateKey: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &maybePrivateKey)
        if status != errSecSuccess {
            return nil
        }
        guard let maybePrivateKey else {
            return nil
        }
        if CFGetTypeID(maybePrivateKey) != SecKeyGetTypeID() {
            return nil
        }
        let privateKey = maybePrivateKey as! SecKey
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }
        guard let publicKeyRepresentation = SecKeyCopyExternalRepresentation(publicKey, nil) else {
            return nil
        }
        
        let result = PrivateKey(privateKey: privateKey, publicKey: publicKey, publicKeyRepresentation: publicKeyRepresentation as Data)
        
        return result
        #endif
    }
    
    public static func removePrivateKey(baseAppBundleId: String, keyId: Data) -> Bool {
        guard let bundleSeedId = self.bundleSeedId() else {
            return false
        }
        
        let applicationTag = customKeyIdPrefix + keyId
        let accessGroup = "\(bundleSeedId).\(baseAppBundleId)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey as String,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom as String,
            kSecAttrIsPermanent as String: true,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess {
            return false
        }
        return true
    }
    
    private static func addPrivateKey(baseAppBundleId: String, keyId: Data) -> PrivateKey? {
        #if targetEnvironment(simulator)
        return PrivateKey()
        #else
        guard let bundleSeedId = self.bundleSeedId() else {
            return nil
        }
        
        let applicationTag = customKeyIdPrefix + keyId
        let accessGroup = "\(bundleSeedId).\(baseAppBundleId)"
        
        guard let access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.userPresence, .privateKeyUsage], nil) else {
            return nil
        }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom as String,
            kSecAttrKeySizeInBits as String: 256 as NSNumber,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave as String,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: applicationTag,
                kSecAttrAccessControl as String: access,
                kSecAttrAccessGroup as String: accessGroup,
            ] as [String: Any]
        ]
        var error: Unmanaged<CFError>?
        let maybePrivateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
        if let error {
            error.release()
        }
        guard let privateKey = maybePrivateKey else {
            return nil
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }
        guard let publicKeyRepresentation = SecKeyCopyExternalRepresentation(publicKey, nil) else {
            return nil
        }
        
        let result = PrivateKey(privateKey: privateKey, publicKey: publicKey, publicKeyRepresentation: publicKeyRepresentation as Data)
        return result
        #endif
    }
}
