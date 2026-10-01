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
        print("Shadow update check: \(count) checks passed")
    }
}
