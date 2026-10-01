import Foundation

// Shadow: crash reports delivered by MetricKit (spec 7.9) are kept here until
// the user sends them to a chat or deletes them. Foundation only.
public final class ShadowCrashReports {
    public static let shared = ShadowCrashReports(
        directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("shadow-crashes", isDirectory: true)
    )

    public struct Report: Equatable {
        public let url: URL
        public let date: Date
    }

    // Older reports are dropped so the folder cannot grow without bound.
    public static let limit = 20

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    @discardableResult
    public func save(_ data: Data, date: Date = Date()) -> URL? {
        guard !data.isEmpty else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            var url = self.directory.appendingPathComponent("crash-\(Int64(date.timeIntervalSince1970 * 1000)).json")
            var suffix = 1
            while FileManager.default.fileExists(atPath: url.path) {
                url = self.directory.appendingPathComponent("crash-\(Int64(date.timeIntervalSince1970 * 1000))-\(suffix).json")
                suffix += 1
            }
            try data.write(to: url, options: [.atomic])
            let all = self.reports()
            if all.count > ShadowCrashReports.limit {
                for report in all.suffix(from: ShadowCrashReports.limit) {
                    self.remove(report)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // Newest first.
    public func reports() -> [Report] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [Report] = []
        for url in urls where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("crash-") {
            let name = url.deletingPathExtension().lastPathComponent.dropFirst("crash-".count)
            guard let millis = Int64(name.split(separator: "-").first ?? "") else {
                continue
            }
            result.append(Report(url: url, date: Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)))
        }
        return result.sorted(by: { $0.date > $1.date })
    }

    public func remove(_ report: Report) {
        try? FileManager.default.removeItem(at: report.url)
    }

    public func removeAll() {
        for report in self.reports() {
            self.remove(report)
        }
    }
}
