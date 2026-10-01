import Foundation

// Shadow: in-app update check.
//
// Source of truth is the manifest `shadow-update.json` at the root of the
// repository's master branch — edited by hand to decide which build is
// announced. CI still publishes every successful master build as a GitHub
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
//   "url": "https://…",           // optional download page (default: releases)
//   "minimum_build": 0            // installed builds below it see "обязательное"
// }
public enum ShadowUpdateCheck {
    public static let manifestURL = URL(string: "https://raw.githubusercontent.com/folzy1092/Shadow/master/shadow-update.json")!
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/folzy1092/Shadow/releases/latest")!
    public static let releasesPageURL = URL(string: "https://github.com/folzy1092/Shadow/releases")!

    public struct Release: Equatable {
        public let build: Int
        public let title: String
        public let pageURL: URL
        public let publishedAt: Date?
        public let notes: String
        // The installed build is below the manifest's minimum_build.
        public let isRequired: Bool

        public init(build: Int, title: String, pageURL: URL, publishedAt: Date?, notes: String, isRequired: Bool = false) {
            self.build = build
            self.title = title
            self.pageURL = pageURL
            self.publishedAt = publishedAt
            self.notes = notes
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
        let release = Release(build: manifest.build, title: title, pageURL: manifest.pageURL, publishedAt: nil, notes: manifest.notes, isRequired: isRequired)
        return self.status(installedBuild: installedBuild, latest: release)
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
        return Release(build: build, title: title, pageURL: pageURL, publishedAt: publishedAt, notes: notes)
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
                DispatchQueue.main.async {
                    completion(result)
                }
            } else {
                checkReleases(completion: completion)
            }
        }
    }
}
