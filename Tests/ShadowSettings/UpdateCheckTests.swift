import Foundation

@main
struct UpdateCheckTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        check(ShadowUpdateCheck.buildNumber(fromTag: "build-34700") == 34700, "Build tag")
        check(ShadowUpdateCheck.buildNumber(fromTag: "v12.9.2") == nil, "Foreign tag")
        check(ShadowUpdateCheck.buildNumber(fromTag: "build-") == nil, "Empty number")
        check(ShadowUpdateCheck.buildNumber(fromTag: "build-12a") == nil, "Garbage number")

        let json = """
        {"tag_name":"build-34700","name":"Shadow 12.9.2 (34700)","html_url":"https://github.com/folzy1092/Shadow/releases/tag/build-34700","published_at":"2026-10-01T08:00:00Z","body":"notes"}
        """
        let release = ShadowUpdateCheck.parseLatestRelease(Data(json.utf8))
        check(release?.build == 34700, "Parsed build")
        check(release?.title == "Shadow 12.9.2 (34700)", "Parsed title")
        check(release?.publishedAt != nil, "Parsed date")
        check(ShadowUpdateCheck.parseLatestRelease(Data("{\"tag_name\":\"v1\"}".utf8)) == nil, "Non-Shadow release ignored")
        check(ShadowUpdateCheck.parseLatestRelease(Data("not json".utf8)) == nil, "Malformed JSON")

        if let release {
            check(ShadowUpdateCheck.status(installedBuild: 34681, latest: release) == .available(release), "Newer build")
            check(ShadowUpdateCheck.status(installedBuild: 34700, latest: release) == .upToDate(release), "Same build")
            check(ShadowUpdateCheck.status(installedBuild: 34800, latest: release) == .upToDate(release), "Local build is newer")
            check(ShadowUpdateCheck.status(installedBuild: nil, latest: release) == .available(release), "Unknown installed build")
        }
        let manifestJSON = """
        {"enabled":true,"build":34700,"version":"12.9.2","title":"Замки чатов","notes":"Что нового","url":"https://example.com/shadow","minimum_build":34690}
        """
        let manifest = ShadowUpdateCheck.parseManifest(Data(manifestJSON.utf8))
        check(manifest?.build == 34700 && manifest?.minimumBuild == 34690, "Manifest parsed")
        check(manifest?.pageURL.absoluteString == "https://example.com/shadow", "Manifest URL")
        check(manifest?.downloadURL == ShadowUpdateCheck.ipaURL(build: 34700), "Default IPA link")
        let customIpa = ShadowUpdateCheck.parseManifest(Data("{\"build\":7,\"ipa_url\":\"https://example.com/a.ipa\"}".utf8))
        check(customIpa?.downloadURL?.absoluteString == "https://example.com/a.ipa", "Custom IPA link")
        let releaseWithAsset = ShadowUpdateCheck.parseLatestRelease(Data("{\"tag_name\":\"build-9\",\"html_url\":\"https://github.com/x\",\"assets\":[{\"name\":\"Shadow.ipa\",\"browser_download_url\":\"https://github.com/x/Shadow.ipa\"}]}".utf8))
        check(releaseWithAsset?.downloadURL?.absoluteString == "https://github.com/x/Shadow.ipa", "Release IPA asset")
        if let manifest {
            if case let .available(release) = ShadowUpdateCheck.status(installedBuild: 34681, manifest: manifest) {
                check(release.isRequired, "Below minimum build is required")
                check(release.title == "Shadow 12.9.2 (34700) — Замки чатов", "Manifest title")
            } else {
                check(false, "Older build sees the announced one")
            }
            if case let .available(release) = ShadowUpdateCheck.status(installedBuild: 34695, manifest: manifest) {
                check(!release.isRequired, "Above minimum build is optional")
            } else {
                check(false, "Optional update")
            }
            if case .upToDate = ShadowUpdateCheck.status(installedBuild: 34700, manifest: manifest) {
                count += 1
            } else {
                check(false, "Announced build installed")
            }
        }
        let disabled = ShadowUpdateCheck.parseManifest(Data("{\"enabled\":false}".utf8))
        check(disabled != nil, "Disabled manifest parses without a build")
        if let disabled {
            check(ShadowUpdateCheck.status(installedBuild: 1, manifest: disabled) == .upToDate(nil), "Disabled manifest announces nothing")
        }
        check(ShadowUpdateCheck.parseManifest(Data("{\"build\":0}".utf8)) == nil, "Enabled manifest needs a build")
        let insecure = ShadowUpdateCheck.parseManifest(Data("{\"build\":5,\"url\":\"http://example.com\"}".utf8))
        check(insecure?.pageURL == ShadowUpdateCheck.releasesPageURL, "Only https download pages")

        let changelogJSON = """
        {"entries":[{"build":34700,"date":"2026-10-01","items":["Второе пространство"," "]},{"build":34703,"date":"2026-10-01","items":["Замок на несколько чатов"]},{"build":34690,"items":["Старое"]},{"build":0,"items":["Мусор"]},{"build":34705,"items":[]}]}
        """
        let entries = ShadowUpdateCheck.parseChangelog(Data(changelogJSON.utf8))
        check(entries.map { $0.build } == [34703, 34700, 34690], "Changelog parsed newest first, empty entries dropped")
        check(entries[1].items == ["Второе пространство"], "Blank items dropped")
        let missed = ShadowUpdateCheck.changes(installedBuild: 34695, announcedBuild: 34703, entries: entries)
        check(missed.map { $0.build } == [34703, 34700], "Every skipped build is listed")
        check(ShadowUpdateCheck.changes(installedBuild: 34703, announcedBuild: 34703, entries: entries).isEmpty, "Nothing for the installed build")
        check(ShadowUpdateCheck.parseChangelog(Data("[]".utf8)).isEmpty, "Malformed changelog")

        print("Shadow update check: \(count) checks passed")
    }
}
