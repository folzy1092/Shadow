import Foundation

// Shadow: in-app update check.
//
// Source of truth is the manifest `shadow-update.json` in the public data
// repository folzy1092/tgfork (branch main, next to the badge config.json) —
// edited by hand to decide which build is announced. It lives there, not in
// the Shadow repo, so the check keeps working if that repo goes private. CI still publishes every successful master build as a GitHub
// Release tagged "build-<CFBundleVersion>"; that release list is only a
// fallback when the manifest cannot be fetched.
//
// Manifest format:
// {
//   "enabled": true,              // false: never announce anything
//   "build": 34700,               // announced CFBundleVersion
//   "version": "12.9.2",          // shown next to the build
//   "title": "Замки чатов",        // optional headline
//   "notes": "Что нового…",       // optional release notes
//   "url": "https://…",           // optional release page (default: releases)
//   "ipa_url": "https://…",       // optional direct IPA link
//                                 // (default: releases/download/build-<build>/Shadow.ipa)
//   "minimum_build": 0            // installed builds below it see "обязательное"
// }
public enum ShadowUpdateCheck {
    public static let manifestURL = URL(string: "https://raw.githubusercontent.com/folzy1092/tgfork/main/shadow-update.json")!
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/folzy1092/Shadow/releases/latest")!
    public static let releasesPageURL = URL(string: "https://github.com/folzy1092/Shadow/releases")!
    // Per-build release notes in Russian, newest first (see shadow-changelog.json).
    public static let changelogURL = URL(string: "https://raw.githubusercontent.com/folzy1092/tgfork/main/shadow-changelog.json")!

    public struct ChangelogEntry: Equatable {
        public let build: Int
        public let date: String
        public let items: [String]

        public init(build: Int, date: String, items: [String]) {
            self.build = build
            self.date = date
            self.items = items
        }
    }

    // CI attaches the IPA to every release under this fixed name.
    public static func ipaURL(build: Int) -> URL {
        return URL(string: "https://github.com/folzy1092/Shadow/releases/download/build-\(build)/Shadow.ipa")!
    }

    public struct Release: Equatable {
        public let build: Int
        public let title: String
        public let pageURL: URL
        public let publishedAt: Date?
        public let notes: String
        // Direct IPA download, when known.
        public let downloadURL: URL?
        // The installed build is below the manifest's minimum_build.
        public let isRequired: Bool
        // Changes of every build newer than the installed one, newest first.
        public var changelog: [ChangelogEntry] = []

        public init(build: Int, title: String, pageURL: URL, publishedAt: Date?, notes: String, downloadURL: URL? = nil, isRequired: Bool = false) {
            self.build = build
            self.title = title
            self.pageURL = pageURL
            self.publishedAt = publishedAt
            self.notes = notes
            self.downloadURL = downloadURL
            self.isRequired = isRequired
        }
    }

    public struct Manifest: Equatable {
        public let enabled: Bool
        public let build: Int
        public let version: String?
        public let title: String?
        public let notes: String
        public let pageURL: URL
        public let downloadURL: URL?
        public let minimumBuild: Int
    }

    public enum Status: Equatable {
        // nil: nothing is announced (manifest disabled).
        case upToDate(Release?)
        case available(Release)
        case failed(String)
    }

    // "build-34700" -> 34700. Anything else is not a Shadow build tag.
    public static func buildNumber(fromTag tag: String) -> Int? {
        let prefix = "build-"
        guard tag.hasPrefix(prefix) else {
            return nil
        }
        return Int(tag.dropFirst(prefix.count))
    }

    public static func parseManifest(_ data: Data) -> Manifest? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let enabled = (object["enabled"] as? Bool) ?? true
        let build = (object["build"] as? Int) ?? 0
        if enabled && build <= 0 {
            return nil
        }
        var pageURL = releasesPageURL
        if let urlString = object["url"] as? String, let url = URL(string: urlString), url.scheme == "https" {
            pageURL = url
        }
        var downloadURL: URL? = build > 0 ? ipaURL(build: build) : nil
        if let urlString = object["ipa_url"] as? String, let url = URL(string: urlString), url.scheme == "https" {
            downloadURL = url
        }
        func nonEmpty(_ key: String) -> String? {
            guard let value = object[key] as? String else {
                return nil
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return Manifest(
            enabled: enabled,
            build: build,
            version: nonEmpty("version"),
            title: nonEmpty("title"),
            notes: nonEmpty("notes") ?? "",
            pageURL: pageURL,
            downloadURL: downloadURL,
            minimumBuild: max(0, (object["minimum_build"] as? Int) ?? 0)
        )
    }

    public static func status(installedBuild: Int?, manifest: Manifest) -> Status {
        guard manifest.enabled else {
            return .upToDate(nil)
        }
        var title = "Shadow"
        if let version = manifest.version {
            title += " \(version)"
        }
        title += " (\(manifest.build))"
        if let headline = manifest.title {
            title += " — " + headline
        }
        let isRequired = installedBuild.map { $0 < manifest.minimumBuild } ?? false
        let release = Release(build: manifest.build, title: title, pageURL: manifest.pageURL, publishedAt: nil, notes: manifest.notes, downloadURL: manifest.downloadURL, isRequired: isRequired)
        return self.status(installedBuild: installedBuild, latest: release)
    }

    // {"entries": [{"build": 34703, "date": "2026-10-01", "items": ["…"]}, …]}
    public static func parseChangelog(_ data: Data) -> [ChangelogEntry] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["entries"] as? [[String: Any]] else {
            return []
        }
        var result: [ChangelogEntry] = []
        for entry in entries {
            guard let build = entry["build"] as? Int, build > 0 else {
                continue
            }
            let items = ((entry["items"] as? [String]) ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if items.isEmpty {
                continue
            }
            result.append(ChangelogEntry(build: build, date: (entry["date"] as? String) ?? "", items: items))
        }
        return result.sorted(by: { $0.build > $1.build })
    }

    // Entries newer than the installed build and not newer than the announced one.
    // Unknown installed build (re-signed IPA without a numeric CFBundleVersion):
    // only the announced entry, never the whole history.
    public static func changes(installedBuild: Int?, announcedBuild: Int, entries: [ChangelogEntry]) -> [ChangelogEntry] {
        guard let installedBuild else {
            return entries.filter { $0.build == announcedBuild }
        }
        return entries.filter { entry in
            entry.build <= announcedBuild && entry.build > installedBuild
        }
    }

    public static func parseLatestRelease(_ data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let build = buildNumber(fromTag: tag),
              let pageString = object["html_url"] as? String,
              let pageURL = URL(string: pageString) else {
            return nil
        }
        let title = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag
        var publishedAt: Date?
        if let published = object["published_at"] as? String {
            publishedAt = ISO8601DateFormatter().date(from: published)
        }
        let notes = (object["body"] as? String) ?? ""
        var downloadURL: URL?
        if let assets = object["assets"] as? [[String: Any]] {
            for asset in assets {
                if let name = asset["name"] as? String, name.hasSuffix(".ipa"), let urlString = asset["browser_download_url"] as? String, let url = URL(string: urlString) {
                    downloadURL = url
                    break
                }
            }
        }
        return Release(build: build, title: title, pageURL: pageURL, publishedAt: publishedAt, notes: notes, downloadURL: downloadURL)
    }

    public static func status(installedBuild: Int?, latest: Release) -> Status {
        guard let installedBuild else {
            return .available(latest)
        }
        return latest.build > installedBuild ? .available(latest) : .upToDate(latest)
    }

    public static var installedBuild: Int? {
        return (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) }
    }

    public static var installedVersion: String {
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    private static func fetch(_ url: URL, completion: @escaping (Data?, Int?, Error?) -> Void) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20.0
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            completion(data, (response as? HTTPURLResponse)?.statusCode, error)
        }.resume()
    }

    private static func checkReleases(completion: @escaping (Status) -> Void) {
        fetch(latestReleaseURL) { data, statusCode, error in
            let result: Status
            if let error {
                result = .failed(error.localizedDescription)
            } else if statusCode == 404 {
                result = .failed("Релизов пока нет")
            } else if let statusCode, !(200 ..< 300).contains(statusCode) {
                result = .failed("GitHub ответил \(statusCode)")
            } else if let data, let release = parseLatestRelease(data) {
                result = status(installedBuild: installedBuild, latest: release)
            } else {
                result = .failed("Не удалось прочитать ответ GitHub")
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    // Manifest first, GitHub Releases as a fallback. Calls `completion` on the main queue.
    public static func check(completion: @escaping (Status) -> Void) {
        fetch(manifestURL) { data, statusCode, error in
            if error == nil, let statusCode, (200 ..< 300).contains(statusCode), let data, let manifest = parseManifest(data) {
                let result = status(installedBuild: installedBuild, manifest: manifest)
                guard case var .available(release) = result else {
                    DispatchQueue.main.async {
                        completion(result)
                    }
                    return
                }
                // Attach what changed since the installed build; the update is
                // still reported if the changelog cannot be fetched.
                fetch(changelogURL) { data, statusCode, error in
                    if error == nil, let statusCode, (200 ..< 300).contains(statusCode), let data {
                        release.changelog = changes(installedBuild: installedBuild, announcedBuild: release.build, entries: parseChangelog(data))
                    }
                    DispatchQueue.main.async {
                        completion(.available(release))
                    }
                }
            } else {
                checkReleases(completion: completion)
            }
        }
    }
}
