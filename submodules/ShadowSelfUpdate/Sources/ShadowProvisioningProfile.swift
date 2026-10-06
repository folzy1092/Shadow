import Foundation

// Shadow: the fields of a .mobileprovision that matter for re-signing Shadow.
// The file is CMS SignedData with the plist as its content; only the plist is
// read here (the CMS signature is not verified).
//
// Foundation only, so it is unit-tested by the Foundation suite.
public struct ShadowProvisioningProfile: Equatable {
    public let name: String
    public let teamId: String
    public let teamName: String
    // "TEAMID.bundle.id" or "TEAMID.*".
    public let applicationIdentifier: String
    public let expirationDate: Date?
    public let deviceCount: Int
    public let provisionsAllDevices: Bool
    public let apsEnvironment: String?
    // DER of every certificate the profile allows.
    public let developerCertificates: [Data]

    public var bundleIdPattern: String {
        let prefix = self.teamId + "."
        if self.applicationIdentifier.hasPrefix(prefix) {
            return String(self.applicationIdentifier.dropFirst(prefix.count))
        }
        return self.applicationIdentifier
    }

    public var isWildcard: Bool {
        return self.bundleIdPattern == "*" || self.bundleIdPattern.hasSuffix(".*")
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        guard let expirationDate = self.expirationDate else {
            return false
        }
        return expirationDate <= date
    }

    public static func plistData(in data: Data) -> Data? {
        guard let start = data.range(of: Data("<?xml".utf8)) ?? data.range(of: Data("<plist".utf8)) else {
            return nil
        }
        let closing = Data("</plist>".utf8)
        guard let end = data.range(of: closing, in: start.lowerBound ..< data.endIndex) else {
            return nil
        }
        return data.subdata(in: start.lowerBound ..< end.upperBound)
    }

    public static func parse(_ data: Data) -> ShadowProvisioningProfile? {
        guard let plistData = ShadowProvisioningProfile.plistData(in: data),
              let plist = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any] else {
            return nil
        }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        guard let teamId = (plist["TeamIdentifier"] as? [String])?.first, !teamId.isEmpty,
              let applicationIdentifier = entitlements["application-identifier"] as? String, !applicationIdentifier.isEmpty else {
            return nil
        }
        return ShadowProvisioningProfile(
            name: plist["Name"] as? String ?? "",
            teamId: teamId,
            teamName: plist["TeamName"] as? String ?? "",
            applicationIdentifier: applicationIdentifier,
            expirationDate: plist["ExpirationDate"] as? Date,
            deviceCount: (plist["ProvisionedDevices"] as? [String])?.count ?? 0,
            provisionsAllDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
            apsEnvironment: entitlements["aps-environment"] as? String,
            developerCertificates: plist["DeveloperCertificates"] as? [Data] ?? []
        )
    }
}
