"""Source contracts: on-device update (Shadow 1.4.0, local install 1.4.1) and the compact camera tile."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"
ZSIGN = ROOT / "third-party/zsign"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ZsignContracts(unittest.TestCase):
    def test_vendored_without_openssl(self):
        build = (ZSIGN / "BUILD").read_text(encoding="utf-8")
        self.assertIn('module_name = "Zsign"', build)
        # Telegram's minimal OpenSSL lacks CMS/RC2/DES; a second one would clash.
        self.assertNotIn("//submodules/openssl", build)
        self.assertNotIn("boringssl", build)
        self.assertFalse((ZSIGN / "Sources/openssl.cpp").exists())
        self.assertTrue((ZSIGN / "Sources/openssl_apple.mm").exists())
        self.assertTrue((ZSIGN / "Sources/shim/openssl/sha.h").exists())
        self.assertTrue((ZSIGN / "LICENSE").exists())

    def test_crypto_uses_security_framework(self):
        crypto = (ZSIGN / "Sources/openssl_apple.mm").read_text(encoding="utf-8")
        self.assertIn("SecPKCS12Import", crypto)
        self.assertIn("SecKeyCreateSignature", crypto)
        self.assertIn("kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256", crypto)
        # CDHashes plist and CDHashes2 signed attributes, as upstream zsign.
        self.assertIn('"1.2.840.113635.100.9.1"', crypto)
        self.assertIn('"1.2.840.113635.100.9.2"', crypto)
        # The p12 certificate must be one the profile allows.
        self.assertIn('jvProv["DeveloperCertificates"]', crypto)
        for token in ("#include <openssl/", "CMS_sign(", "PKCS12_parse("):
            self.assertNotIn(token, crypto)

    def test_openssl3_p12_fallback(self):
        # iOS rejects OpenSSL 3 exports (PBES2/AES-256, SHA-256 MAC) with
        # errSecDecode -26275; zsign then reads the p12 itself.
        reader = (ZSIGN / "Sources/pkcs12_apple.mm").read_text(encoding="utf-8")
        for oid in ('"1.2.840.113549.1.5.13"', '"1.2.840.113549.1.5.12"', '"2.16.840.1.101.3.4.1.42"', '"1.2.840.113549.2.9"', '"1.2.840.113549.1.12.1.3"', '"1.2.840.113549.1.12.1.6"'):
            self.assertIn(oid, reader)
        self.assertIn(r"passwordBMP.append(2, '\0');", reader)
        crypto = (ZSIGN / "Sources/openssl_apple.mm").read_text(encoding="utf-8")
        self.assertIn("ShadowParsePKCS12(strP12Data, strPassword", crypto)
        self.assertIn("SecCertificateCopyKey(certificate)", crypto)
        self.assertLess(crypto.index("SecPKCS12Import"), crypto.index("ShadowParsePKCS12(strP12Data"))

    def test_wrapper_has_swift_names(self):
        header = (ZSIGN / "PublicHeaders/Zsign/ShadowZsign.h").read_text(encoding="utf-8")
        self.assertIn("NS_SWIFT_NAME(sign(appPath:provisionPath:p12Path:password:))", header)
        self.assertIn("NS_SWIFT_NAME(check(provisionPath:p12Path:password:))", header)


class SelfUpdateContracts(unittest.TestCase):
    def test_module_wiring(self):
        build = read("ShadowSelfUpdate/BUILD")
        self.assertIn('"//third-party/zsign:Zsign"', build)
        self.assertIn('"//third-party/ZipArchive:ZipArchive"', build)
        self.assertIn('"//submodules/ShadowSelfUpdate:ShadowSelfUpdate"', read("SettingsUI/BUILD"))

    def test_signs_with_the_installed_bundle_id(self):
        preparer = read("ShadowSelfUpdate/Sources/ShadowBundlePreparer.swift")
        self.assertIn('info["CFBundleIdentifier"] = target', preparer)
        self.assertIn("bundle.bundleIdentifier", preparer)
        updater = read("ShadowSelfUpdate/Sources/ShadowSelfUpdater.swift")
        self.assertIn("ShadowBundlePreparer.Installed.current()", updater)
        self.assertIn("bundleId: installed.bundleId", updater)

    def test_signing_files_stay_on_the_device(self):
        store = read("ShadowSelfUpdate/Sources/ShadowSigningStore.swift")
        self.assertIn("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly", store)
        self.assertIn("isExcludedFromBackup = true", store)
        for path in ("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift", "TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift", "TelegramCore/Sources/AyuGram/AyuGramSettings.swift"):
            self.assertNotIn("ShadowSigning", read(path), path)

    def test_install_server_is_loopback_only(self):
        server = read("ShadowSelfUpdate/Sources/ShadowInstallServer.swift")
        self.assertIn("requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)", server)
        self.assertIn("requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: endpointPort)", server)
        self.assertNotIn(".any, port", server)
        self.assertIn("case localHTTP", server)
        self.assertIn("sec_protocol_options_set_local_identity", server)
        self.assertIn('"Content-Range: bytes', server)
        self.assertIn('method == "HEAD"', server)
        identity = read("ShadowSelfUpdate/Sources/ShadowLocalTLSIdentity.swift")
        self.assertIn('"https://backloop.dev/pack.json"', identity)
        self.assertIn("key1 + key2", identity)
        # The revoked backloop.dev certificate is used only while iOS trusts it.
        self.assertIn("SecTrustEvaluateWithError", identity)
        self.assertIn("errSecCertificateRevoked", identity)

    def test_install_follows_ipa_hub(self):
        # 1.4.1: the IPA on http://127.0.0.1, the manifest from api.palera.in,
        # a Safari page that hands the itms-services link to iOS.
        links = read("ShadowSelfUpdate/Sources/ShadowInstallLinks.swift")
        self.assertIn('"itms-services://?action=download-manifest&url="', links)
        self.assertIn('externalManifestBase = "https://api.palera.in/genPlist"', links)
        self.assertIn('public static let loopback = "127.0.0.1"', links)
        self.assertIn("window.location=", links)
        updater = read("ShadowSelfUpdate/Sources/ShadowSelfUpdater.swift")
        self.assertIn("static let hintDelay: TimeInterval = 10.0", updater)
        self.assertIn("ShadowInstallLinks.externalManifestProblem(", updater)
        self.assertIn("ShadowLocalTLSIdentity.trustProblem(chain:", updater)
        self.assertIn("ShadowInstallLinks.resolve(host: ShadowLocalTLSIdentity.host)", updater)
        self.assertIn("UIApplication.willResignActiveNotification", updater)
        # Only a resign right after the link is the install window.
        self.assertIn("guard case .waitingForConfirmation(hint: false) = self.stateValue.stage, self.didOpen else", updater)
        # A stopped listener is restarted by "Показать окно установки".
        retry = updater.split("public func retryInstallPrompt()", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("guard activity.isReady else", retry)
        self.assertIn("self.startServer(", retry)
        diagnostics = read("ShadowSelfUpdate/Sources/ShadowInstallDiagnostics.swift")
        self.assertIn("public var line: String", diagnostics)
        self.assertIn("public func cause(now: Date) -> String", diagnostics)
        self.assertIn("«Поделиться подписанным IPA»", diagnostics)

    def test_hub_and_screen(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        self.assertIn("ShadowSelfUpdater.shared.state", hub)
        self.assertIn("case .autoUpdate: return shadowAutoUpdateController(context: context, focus: item)", hub)
        update = read("SettingsUI/Sources/ShadowUpdateController.swift")
        self.assertIn("case mainButton(String, Bool)", update)
        self.assertIn("ShadowSelfUpdater.shared.start(", update)
        self.assertIn("bindings.pushIdleTimerExtension()", update)
        # 1.4.1: the Safari install page and the open result.
        self.assertIn("SFSafariViewController(url: url)", update)
        self.assertIn("UIApplication.shared.open(installURL, options: [:], completionHandler: completion)", update)
        self.assertIn("beginBackgroundTask(withName:", update)
        # An expired task is begun again when Shadow comes back.
        self.assertIn("UIApplication.willEnterForegroundNotification", update)
        self.assertIn("if signingReady, release.downloadURL != nil", update)
        self.assertIn('entries.append(.mainButton("Обновить до \(target)", true))', update)
        self.assertIn("pushControllerImpl?(shadowAutoUpdateController(context: context))", update)
        screen = read("SettingsUI/Sources/ShadowAutoUpdateController.swift")
        self.assertIn("field.isSecureTextEntry = true", screen)
        self.assertIn("ShadowSigningStore.shared.check()", screen)
        self.assertIn('UTType(filenameExtension: "p12")', screen)
        self.assertIn('UTType(filenameExtension: "mobileprovision", conformingTo: .data)', screen)
        self.assertIn('let expectedExtension = kind == .certificate ? "p12" : "mobileprovision"', screen)
        router = read("SettingsUI/Sources/ShadowLinkRouter.swift")
        self.assertIn('case "autoupdate", "signing":', router)
        doc = (ROOT / "docs/shadow-links.md").read_text(encoding="utf-8")
        self.assertIn("`shadow://autoupdate`", doc)

    def test_foundation_suite_covers_the_module(self):
        script = (ROOT / "build-system/ci/test_shadow_foundation.py").read_text(encoding="utf-8")
        self.assertIn("Tests/ShadowSettings/SelfUpdateTests.swift", script)
        self.assertIn("submodules/ShadowSelfUpdate/Sources/ShadowInstallLinks.swift", script)
        self.assertIn("submodules/ShadowSelfUpdate/Sources/ShadowInstallDiagnostics.swift", script)


class CompactCameraTileContracts(unittest.TestCase):
    def test_setting_is_stored_and_used(self):
        settings = read("TelegramCore/Sources/AyuGram/AyuGramSettings.swift")
        self.assertEqual(settings.count('"cameraTileCompact"'), 2)
        self.assertIn("cameraTileCompact: false,", settings)
        self.assertIn('"cameraTileCompact"', read("TelegramCore/Sources/AyuGram/ShadowSettingsDocument.swift"))
        self.assertIn('"cameraTileCompact": \\.cameraTileCompact', read("TelegramCore/Sources/AyuGram/ShadowSettingsTransfer.swift"))
        self.assertIn('slug: "camera-compact", entryId: 115, key: "cameraTileCompact"', read("TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift"))
        picker = read("MediaPickerUI/Sources/MediaPickerScreen.swift")
        self.assertIn("ayuGramSettingsCurrent.cameraTileCompact ? itemWidth : itemWidth * 2.0 + itemSpacing", picker)



class CustomizationOrderContracts(unittest.TestCase):
    def test_badges_section_is_last(self):
        hub = read("SettingsUI/Sources/AyuGramSettingsController.swift")
        body = hub.split("entries.append(.mediaFooter)", 1)[1].split("return entries", 1)[0]
        order = [body.index(name) for name in (".customRoundVideosHeader", ".bannerHeader", ".profileBackgroundHeader", ".callsHeader")]
        self.assertEqual(order, sorted(order))
        self.assertIn('text: "ЗНАЧКИ"', hub)
        # The badge sync button is hidden; badges refresh on launch.
        self.assertNotIn("entries.append(.syncGithub)", hub)


if __name__ == "__main__":
    unittest.main()
