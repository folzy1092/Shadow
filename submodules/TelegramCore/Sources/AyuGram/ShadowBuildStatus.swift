import Foundation

// Shadow: the build that CI is running right now, for "Проверить обновления".
//
// Read straight from the public GitHub API (no token):
//   1. the newest run of .github/workflows/build.yml on master — is a build going on;
//   2. its job steps — the current step ("Restore Bazel output", "Build the App", …);
//   3. while "Build the App" runs, the check run "Shadow build progress", which CI
//      updates every 30 s with Bazel's "[done / total]" counter and the build number.
// At most three requests per check (the unauthenticated limit is 60 an hour).
//
// Foundation only, so it is unit-tested by the Foundation suite.
public enum ShadowBuildStatus {
    public static let repository = "folzy1092/Shadow"
    public static let progressCheckName = "Shadow build progress"

    public struct Info: Equatable {
        public var isQueued: Bool
        public var step: String?
        public var done: Int?
        public var total: Int?
        public var build: Int?
        public var startedAt: Date?

        public init(isQueued: Bool, step: String? = nil, done: Int? = nil, total: Int? = nil, build: Int? = nil, startedAt: Date? = nil) {
            self.isQueued = isQueued
            self.step = step
            self.done = done
            self.total = total
            self.build = build
            self.startedAt = startedAt
        }
    }

    public struct Run: Equatable {
        public let id: Int64
        public let isActive: Bool
        public let isQueued: Bool
        public let headSha: String
        public let startedAt: Date?
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else {
            return nil
        }
        return ISO8601DateFormatter().date(from: string)
    }

    // GET /repos/{repo}/actions/workflows/build.yml/runs?branch=master&per_page=5
    // GitHub sometimes starts several runs for one push in the same second;
    // concurrency cancels all but one, and the list order between them is
    // arbitrary. So the running run wins, then a queued one, then the newest.
    public static func parseLatestRun(_ data: Data) -> Run? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = object["workflow_runs"] as? [[String: Any]] else {
            return nil
        }
        let run = runs.first(where: { ($0["status"] as? String) == "in_progress" })
            ?? runs.first(where: { ($0["status"] as? String).map { $0 != "completed" } ?? false })
            ?? runs.first
        guard let run,
              let id = (run["id"] as? NSNumber)?.int64Value,
              let status = run["status"] as? String,
              let sha = run["head_sha"] as? String else {
            return nil
        }
        let active = status != "completed"
        let queued = ["queued", "waiting", "requested", "pending"].contains(status)
        return Run(id: id, isActive: active, isQueued: queued, headSha: sha, startedAt: date(run["run_started_at"]))
    }

    // GET /repos/{repo}/actions/runs/{id}/jobs: the step that is running, or
    // the last finished one between two steps; nil while the job is queued.
    public static func parseCurrentStep(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let job = (object["jobs"] as? [[String: Any]])?.first,
              let steps = job["steps"] as? [[String: Any]] else {
            return nil
        }
        if let running = steps.first(where: { ($0["status"] as? String) == "in_progress" }) {
            return running["name"] as? String
        }
        return steps.last(where: { ($0["status"] as? String) == "completed" })?["name"] as? String
    }

    // "Build the App [4872/5876]" and "build=34757" from the progress check run.
    public static func parseProgress(_ data: Data) -> (done: Int?, total: Int?, build: Int?)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let run = (object["check_runs"] as? [[String: Any]])?.first(where: { ($0["name"] as? String) == progressCheckName }),
              let output = run["output"] as? [String: Any] else {
            return nil
        }
        let title = (output["title"] as? String) ?? ""
        let summary = (output["summary"] as? String) ?? ""
        var done: Int?
        var total: Int?
        if let expression = try? NSRegularExpression(pattern: "\\[\\s*([0-9,]+)\\s*/\\s*([0-9,]+)\\s*\\]"),
           let match = expression.firstMatch(in: title, range: NSRange(location: 0, length: (title as NSString).length)) {
            let string = title as NSString
            done = Int(string.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ""))
            total = Int(string.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: ""))
        }
        var build: Int?
        if let range = summary.range(of: "build=") {
            build = Int(summary[range.upperBound...].prefix(while: { $0.isNumber }))
        }
        return (done, total, build)
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.groupingSize = 3
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // "Собирается сборка 34757 · Build the App [4 872/5 876] · 83% · идёт 12 мин"
    public static func text(_ info: Info, now: Date = Date()) -> String {
        if info.isQueued {
            return "Новая сборка в очереди"
        }
        var parts: [String] = []
        if let build = info.build {
            parts.append("Собирается сборка \(build)")
        } else {
            parts.append("Собирается новая сборка")
        }
        if let step = info.step {
            var stepText = step
            if let done = info.done, let total = info.total, total > 0 {
                stepText += " [\(grouped(done))/\(grouped(total))]"
                parts.append(stepText)
                parts.append("\(min(100, done * 100 / total))%")
            } else {
                parts.append(stepText)
            }
        }
        if let startedAt = info.startedAt {
            let minutes = max(0, Int(now.timeIntervalSince(startedAt) / 60.0))
            parts.append("идёт \(minutes) мин")
        }
        return parts.joined(separator: " · ")
    }

    private static func get(_ path: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/" + path) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10.0
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error == nil, let status = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(status) {
                completion(data)
            } else {
                completion(nil)
            }
        }.resume()
    }

    // nil: no build is running (or GitHub did not answer). Main queue.
    public static func fetch(completion: @escaping (Info?) -> Void) {
        let finish: (Info?) -> Void = { info in
            DispatchQueue.main.async {
                completion(info)
            }
        }
        get("actions/workflows/build.yml/runs?branch=master&per_page=5") { data in
            guard let data, let run = parseLatestRun(data), run.isActive else {
                finish(nil)
                return
            }
            if run.isQueued {
                finish(Info(isQueued: true))
                return
            }
            get("actions/runs/\(run.id)/jobs") { data in
                let step = data.flatMap { parseCurrentStep($0) }
                var info = Info(isQueued: step == nil, step: step, startedAt: run.startedAt)
                guard step == "Build the App" else {
                    finish(info)
                    return
                }
                get("commits/\(run.headSha)/check-runs?check_name=\(progressCheckName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") { data in
                    if let data, let progress = parseProgress(data) {
                        info.done = progress.done
                        info.total = progress.total
                        info.build = progress.build
                    }
                    finish(info)
                }
            }
        }
    }
}
