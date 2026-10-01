import Foundation

// Shadow: in-app update check. CI publishes every successful master build as a
// GitHub Release tagged "build-<CFBundleVersion>"; the "Обновления" screen
// fetches the latest release and compares its build number with the installed one.
public enum ShadowUpdateCheck {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/folzy1092/Shadow/releases/latest")!
    public static let releasesPageURL = URL(string: "https://github.com/folzy1092/Shadow/releases")!

    public struct Release: Equatable {
        public let build: Int
        public let title: String
        public let pageURL: URL
        public let publishedAt: Date?
        public let notes: String
    }

    public enum Status: Equatable {
        case upToDate(Release)
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

    // Calls `completion` on the main queue.
    public static func check(completion: @escaping (Status) -> Void) {
        var request = URLRequest(url: latestReleaseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20.0
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Status
            if let error {
                result = .failed(error.localizedDescription)
            } else if let response = response as? HTTPURLResponse, response.statusCode == 404 {
                result = .failed("Релизов пока нет")
            } else if let response = response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
                result = .failed("GitHub ответил \(response.statusCode)")
            } else if let data, let release = parseLatestRelease(data) {
                result = status(installedBuild: installedBuild, latest: release)
            } else {
                result = .failed("Не удалось прочитать ответ GitHub")
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
        task.resume()
    }
}
