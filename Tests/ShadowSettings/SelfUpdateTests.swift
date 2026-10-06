import Foundation

@main
struct SelfUpdateTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }

        // MARK: Provisioning profile

        let profilePlist: [String: Any] = [
            "Name": "Shadow Folzy",
            "TeamName": "Zieringer Sven Erik",
            "TeamIdentifier": ["336W4P3WL5"],
            "ExpirationDate": Date(timeIntervalSince1970: 1_814_000_000),
            "ProvisionedDevices": ["00008130-000C64A821DA001C"],
            "DeveloperCertificates": [Data([1, 2, 3])],
            "Entitlements": [
                "application-identifier": "336W4P3WL5.app.eclipse296.lake3160",
                "aps-environment": "production"
            ]
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: profilePlist, format: .xml, options: 0)
        // CMS around the plist: arbitrary bytes before and after.
        var profileData = Data([0x30, 0x82, 0x4c, 0xe6, 0x06, 0x09])
        profileData.append(plistData)
        profileData.append(Data([0xa0, 0x82, 0x01, 0x00]))
        let profile = ShadowProvisioningProfile.parse(profileData)
        check(profile != nil, "Profile plist is found inside CMS bytes")
        check(profile?.teamId == "336W4P3WL5", "Team id")
        check(profile?.bundleIdPattern == "app.eclipse296.lake3160", "App id without the team prefix")
        check(profile?.isWildcard == false, "Explicit app id")
        check(profile?.deviceCount == 1, "Device count")
        check(profile?.apsEnvironment == "production", "Push environment")
        check(profile?.developerCertificates == [Data([1, 2, 3])], "Certificates")
        check(profile?.isExpired(at: Date(timeIntervalSince1970: 1_900_000_000)) == true, "Expired later")
        check(profile?.isExpired(at: Date(timeIntervalSince1970: 1_700_000_000)) == false, "Valid before")
        check(ShadowProvisioningProfile.parse(Data("not a profile".utf8)) == nil, "Garbage is rejected")

        // MARK: Bundle id rebase

        check(ShadowBundlePreparer.rebase("ph.telegra.Telegraph", from: "ph.telegra.Telegraph", to: "ph.telegra.Telegra") == "ph.telegra.Telegra", "Main id")
        check(ShadowBundlePreparer.rebase("ph.telegra.Telegraph.Share", from: "ph.telegra.Telegraph", to: "ph.telegra.Telegra") == "ph.telegra.Telegra.Share", "Extension id")
        check(ShadowBundlePreparer.rebase("ph.telegra.TelegraphX", from: "ph.telegra.Telegraph", to: "ph.telegra.Telegra") == "ph.telegra.TelegraphX", "Only a whole prefix")
        check(ShadowBundlePreparer.rebase("com.apple.other", from: "ph.telegra.Telegraph", to: "x") == "com.apple.other", "Foreign id stays")

        // MARK: Prepare an unpacked build

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("shadow-self-update-tests-" + UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let app = root.appendingPathComponent("Payload/Telegram.app", isDirectory: true)
        try fileManager.createDirectory(at: app.appendingPathComponent("PlugIns/Share.appex"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: app.appendingPathComponent("PlugIns/Widget.appex"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: app.appendingPathComponent("Watch/WatchApp.app"), withIntermediateDirectories: true)
        func writePlist(_ dict: [String: Any], _ url: URL) throws {
            try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0).write(to: url)
        }
        func readPlist(_ url: URL) -> [String: Any] {
            return (try? PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil)) as? [String: Any] ?? [:]
        }
        try writePlist([
            "CFBundleIdentifier": "ph.telegra.Telegraph",
            "CFBundleVersion": "34770",
            "BGTaskSchedulerPermittedIdentifiers": ["ph.telegra.Telegraph.refresh", "other.task"]
        ], app.appendingPathComponent("Info.plist"))
        try writePlist([
            "CFBundleIdentifier": "ph.telegra.Telegraph.Share",
            "NSExtension": ["NSExtensionAttributes": ["WKAppBundleIdentifier": "ph.telegra.Telegraph.watchkitapp"]]
        ], app.appendingPathComponent("PlugIns/Share.appex/Info.plist"))
        try writePlist(["CFBundleIdentifier": "ph.telegra.Telegraph.Widget"], app.appendingPathComponent("PlugIns/Widget.appex/Info.plist"))
        try Data("old profile".utf8).write(to: app.appendingPathComponent("PlugIns/Share.appex/embedded.mobileprovision"))
        let newProfile = root.appendingPathComponent("signing.mobileprovision")
        try profileData.write(to: newProfile)

        check(ShadowBundlePreparer.findApp(inPayloadParent: root)?.lastPathComponent == "Telegram.app", "App is found under Payload")

        let installed = ShadowBundlePreparer.Installed(bundleId: "ph.telegra.Telegra", plugIns: ["Share.appex"], hasWatch: false)
        let summary = try ShadowBundlePreparer.prepare(app: app, installed: installed, profileURL: newProfile)
        check(summary.previousBundleId == "ph.telegra.Telegraph", "Previous id reported")
        check(summary.removedPlugIns == ["Widget.appex"], "Extension the installed copy lacks is removed")
        check(summary.keptPlugIns == ["Share.appex"], "Installed extension is kept")
        check(summary.removedWatch, "Watch app is removed when the installed copy has none")
        check(!fileManager.fileExists(atPath: app.appendingPathComponent("Watch").path), "Watch folder is gone")

        let info = readPlist(app.appendingPathComponent("Info.plist"))
        check(info["CFBundleIdentifier"] as? String == "ph.telegra.Telegra", "Main id = installed id")
        check(info["CFBundleVersion"] as? String == "34770", "Other keys stay")
        check(info["BGTaskSchedulerPermittedIdentifiers"] as? [String] == ["ph.telegra.Telegra.refresh", "other.task"], "Background task ids follow")
        let share = readPlist(app.appendingPathComponent("PlugIns/Share.appex/Info.plist"))
        check(share["CFBundleIdentifier"] as? String == "ph.telegra.Telegra.Share", "Extension id follows")
        let attributes = (share["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any]
        check(attributes?["WKAppBundleIdentifier"] as? String == "ph.telegra.Telegra.watchkitapp", "Watch companion id follows")
        check((try? Data(contentsOf: app.appendingPathComponent("PlugIns/Share.appex/embedded.mobileprovision"))) == profileData, "Extension embeds the signing profile")

        // No extensions installed: the folder goes away entirely.
        let bare = ShadowBundlePreparer.Installed(bundleId: "ph.telegra.Telegra", plugIns: [], hasWatch: false)
        _ = try ShadowBundlePreparer.prepare(app: app, installed: bare, profileURL: nil)
        check(!fileManager.fileExists(atPath: app.appendingPathComponent("PlugIns").path), "Empty PlugIns is removed")

        // MARK: Local TLS pack

        // key1 ends mid-line and key2 continues it, as in backloop.dev's pack.json.
        let pem = "-----BEGIN PRIVATE KEY-----\nAAEC\nAw" + "QF\n-----END PRIVATE KEY-----\n"
        check(ShadowLocalTLSIdentity.derBlocks(pem: pem) == [Data([0, 1, 2, 3, 4, 5])], "PEM split between key1 and key2")
        let chain = "-----BEGIN CERTIFICATE-----\nAQ==\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nAg==\n-----END CERTIFICATE-----\n"
        check(ShadowLocalTLSIdentity.derBlocks(pem: chain) == [Data([1]), Data([2])], "Several certificates")
        let rsaKey = Data([0x30, 0x03, 0x02, 0x01, 0x00])
        var pkcs8 = Data([0x02, 0x01, 0x00, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x04, UInt8(rsaKey.count)])
        pkcs8.append(rsaKey)
        pkcs8.insert(contentsOf: [0x30, UInt8(pkcs8.count)], at: 0)
        check(ShadowLocalTLSIdentity.rsaPrivateKey(fromPKCS8: pkcs8) == rsaKey, "PKCS#8 → PKCS#1")
        check(ShadowLocalTLSIdentity.rsaPrivateKey(fromPKCS8: Data([0x04, 0x00])) == nil, "Not PKCS#8")

        print("SelfUpdateTests: \(count) checks passed")
    }
}
