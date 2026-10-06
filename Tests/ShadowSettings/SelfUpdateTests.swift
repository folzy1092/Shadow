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

        // MARK: Local install links

        let payload = ShadowInstallLinks.payloadURL(port: 49758)
        check(payload.absoluteString == "http://127.0.0.1:49758/shadow.ipa", "IPA on 127.0.0.1, no DNS")
        check(ShadowInstallLinks.pageURL(port: 49758).absoluteString == "http://127.0.0.1:49758/install", "Install page")
        let manifest = ShadowInstallLinks.externalManifestURL(bundleId: "ph.telegra.Telegra", bundleVersion: "34778", title: "Shadow 1.4.1", payload: payload)
        check(manifest?.absoluteString == "https://api.palera.in/genPlist?bundleid=ph.telegra.Telegra&name=Shadow%201.4.1&version=34778&fetchurl=http%3A%2F%2F127.0.0.1%3A49758%2Fshadow.ipa", "palera.in manifest query")
        check(ShadowInstallLinks.externalManifestURL(bundleId: "ph.telegra.<x>", bundleVersion: "1", title: "Shadow", payload: payload) == nil, "No XML-unsafe bundle id")
        check(ShadowInstallLinks.externalManifestURL(bundleId: "ph.telegra.Telegra", bundleVersion: "", title: "Shadow", payload: payload) == nil, "Version is required")
        check(ShadowInstallLinks.plainTitle("Shadow & <Тень> 1.4.1") == "Shadow 1.4.1", "Title without XML-unsafe characters")
        check(ShadowInstallLinks.plainTitle("Тень") == "Shadow", "Empty title falls back")
        let itms = manifest.flatMap { ShadowInstallLinks.itmsURL(manifest: $0) }
        check(itms?.absoluteString == "itms-services://?action=download-manifest&url=https%3A%2F%2Fapi.palera.in%2FgenPlist%3Fbundleid%3Dph.telegra.Telegra%26name%3DShadow%25201.4.1%26version%3D34778%26fetchurl%3Dhttp%253A%252F%252F127.0.0.1%253A49758%252Fshadow.ipa", "itms-services link")
        if let itms {
            let page = ShadowInstallLinks.installPage(itms: itms)
            check(page.contains("window.location=\"\(itms.absoluteString)\""), "Page sends Safari on to itms-services")
            check(page.contains("href=\"itms-services://?action=download-manifest&amp;url="), "Link attribute is escaped")
        }

        // palera.in answers with a plist naming the payload.
        let plist = "<plist><dict><key>kind</key><string>software-package</string><key>url</key><string>http://127.0.0.1:49758/shadow.ipa</string></dict></plist>"
        let manifestURL = manifest ?? payload
        let ok = HTTPURLResponse(url: manifestURL, statusCode: 200, httpVersion: nil, headerFields: nil)
        check(ShadowInstallLinks.externalManifestProblem(data: Data(plist.utf8), response: ok, error: nil, payload: payload) == nil, "Manifest for this payload is accepted")
        check(ShadowInstallLinks.externalManifestProblem(data: Data(plist.utf8), response: ok, error: nil, payload: ShadowInstallLinks.payloadURL(port: 1)) == "неверный ответ", "Manifest for another port is rejected")
        let missing = HTTPURLResponse(url: manifestURL, statusCode: 503, httpVersion: nil, headerFields: nil)
        check(ShadowInstallLinks.externalManifestProblem(data: Data(plist.utf8), response: missing, error: nil, payload: payload) == "HTTP 503", "HTTP status")
        check(ShadowInstallLinks.externalManifestProblem(data: nil, response: nil, error: URLError(.timedOut), payload: payload) == "нет ответа", "Timeout")
        check(ShadowInstallLinks.externalManifestProblem(data: nil, response: nil, error: URLError(.cannotFindHost), payload: payload) == "DNS", "DNS")
        check(ShadowInstallLinks.externalManifestProblem(data: nil, response: nil, error: URLError(.serverCertificateUntrusted), payload: payload) == "TLS", "TLS")

        // MARK: Resolved addresses

        check(ShadowInstallLinks.classify("127.0.0.1") == .loopback, "IPv4 loopback")
        check(ShadowInstallLinks.classify("::1") == .loopback, "IPv6 loopback")
        check(ShadowInstallLinks.classify("::ffff:127.0.0.1") == .loopback, "Mapped loopback")
        check(ShadowInstallLinks.classify("0.0.0.0") == .blocked, "Filter answer")
        check(ShadowInstallLinks.classify("::") == .blocked, "IPv6 filter answer")
        check(ShadowInstallLinks.classify("198.18.0.5") == .fakeIP, "VPN fake IP")
        check(ShadowInstallLinks.classify("64:ff9b::7f00:1") == .nat64, "NAT64")
        check(ShadowInstallLinks.classify("192.168.1.10") == .privateNetwork, "Router address")
        check(ShadowInstallLinks.classify("fe80::1%en0") == .privateNetwork, "Link-local with zone")
        check(ShadowInstallLinks.classify("8.8.8.8") == .publicNetwork, "Public address")
        check(ShadowInstallLinks.classify("shadow") == .invalid, "Not an address")

        // MARK: Diagnostics

        let now = Date(timeIntervalSince1970: 1_791_000_000)
        var diagnostics = ShadowInstallDiagnostics()
        diagnostics.server.listener = "работает"
        diagnostics.server.isReady = true
        diagnostics.externalManifest = .ok
        diagnostics.resolved = ["127.0.0.1", "::1"]
        diagnostics.certificate = .failed("отозван")
        diagnostics.certificateNotAfter = Date(timeIntervalSince1970: 1_790_000_000)
        check(diagnostics.line.hasPrefix("HTTP 127.0.0.1 · манифест palera ✓ · Safari — · DNS 127.0.0.1, ::1 · сервер работает · подкл. 0 · ipa — · серт. backloop до "), "Diagnostics line")
        check(diagnostics.line.hasSuffix(" ✗ отозван"), "Certificate mark")
        check(diagnostics.cause(now: now).hasPrefix("Safari не открыл страницу установки"), "No page request")
        check(diagnostics.cause(now: now).hasSuffix("Или «Поделиться подписанным IPA» и установить его через ESign."), "Cause ends with the way around")
        diagnostics.server.pageRequested = true
        check(diagnostics.cause(now: now).hasPrefix("Ссылка установки открыта, но iOS не показала окно."), "Page seen, no window")
        diagnostics.promptSeen = true
        check(diagnostics.cause(now: now).hasPrefix("Окно установки показано, но iOS не начала загрузку."), "Window shown, no download")
        diagnostics.server.payloadRequested = true
        check(diagnostics.cause(now: now).hasPrefix("iOS начала загрузку, но не закончила."), "Download started")
        diagnostics.server.isReady = false
        diagnostics.server.listener = "ошибка"
        check(diagnostics.cause(now: now).hasPrefix("Локальный сервер не работает (ошибка)."), "Server down goes first")

        var palera = ShadowInstallDiagnostics()
        palera.server.isReady = true
        palera.externalManifest = .failed("DNS")
        check(palera.cause(now: now).hasPrefix("Не удалось получить манифест с api.palera.in (DNS)"), "palera.in unreachable")
        // Leaving the app (to change the VPN) does not hide it.
        palera.promptSeen = true
        check(palera.cause(now: now).hasPrefix("Не удалось получить манифест с api.palera.in (DNS)"), "palera.in failure goes before promptSeen")
        palera.opener = .openURL
        palera.openResult = false
        check(palera.line.contains("open ✗"), "openURL result")
        check(palera.cause(now: now).hasPrefix("iOS отказалась открыть ссылку itms-services."), "openURL refused")

        var backloop = ShadowInstallDiagnostics()
        backloop.route = .backloopHTTPS
        backloop.opener = .openURL
        backloop.openResult = true
        backloop.server.isReady = true
        backloop.certificate = .ok
        backloop.certificateNotAfter = Date(timeIntervalSince1970: 1_790_000_000)
        check(backloop.cause(now: now).hasPrefix("Сертификат backloop.dev истёк"), "Expired certificate")
        backloop.certificateNotAfter = Date(timeIntervalSince1970: 1_800_000_000)
        backloop.resolved = ["198.18.0.7"]
        check(backloop.cause(now: now).hasPrefix("VPN подменяет DNS (shadow.backloop.dev → 198.18.0.7)"), "Fake-IP DNS")
        backloop.resolved = ["127.0.0.1"]
        check(backloop.cause(now: now).hasPrefix("iOS ни разу не подключилась"), "No connection")
        backloop.server.connections = 1
        backloop.server.tlsErrors = 1
        backloop.server.lastConnectionError = "bad certificate"
        check(backloop.cause(now: now).hasPrefix("iOS отвергла TLS-подключение к локальному серверу (bad certificate)"), "TLS rejected")
        check(backloop.line.contains("manifest — · иконки — · ipa —"), "backloop requests")

        // MARK: Certificate of the backloop pack

        let pack = Data(#"{"info":{"notAfter":"2026-10-29T12:00:00.000Z"}}"#.utf8)
        check(ShadowLocalTLSIdentity.notAfter(fromPack: pack) == Date(timeIntervalSince1970: 1_793_275_200), "Pack expiry")
        check(ShadowLocalTLSIdentity.notAfter(fromPack: Data("{}".utf8)) == nil, "Pack without expiry")
        check(ShadowLocalTLSIdentity.trustProblemText(errSecCertificateRevoked) == "отозван", "Revoked")
        check(ShadowLocalTLSIdentity.trustProblemText(errSecCertificateExpired) == "истёк", "Expired")
        check(ShadowLocalTLSIdentity.trustProblem(chain: []) == "не проверен", "Empty chain")
        check(ShadowLocalTLSIdentity.shortText(ShadowLocalTLSIdentity.IdentityError.keychain(-25300)) == "Keychain -25300", "Keychain short text")

        print("SelfUpdateTests: \(count) checks passed")
    }
}
