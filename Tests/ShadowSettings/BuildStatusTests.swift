import Foundation

@main
struct BuildStatusTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        func data(_ string: String) -> Data {
            return string.data(using: .utf8)!
        }

        let running = ShadowBuildStatus.parseLatestRun(data("""
        {"workflow_runs":[{"id":37443853188,"status":"in_progress","head_sha":"abc","run_started_at":"2026-10-06T10:00:00Z"}]}
        """))
        check(running?.id == 37443853188 && running?.isActive == true && running?.isQueued == false, "Running run")
        check(running?.headSha == "abc" && running?.startedAt != nil, "Run sha and start")
        let queued = ShadowBuildStatus.parseLatestRun(data("""
        {"workflow_runs":[{"id":1,"status":"queued","head_sha":"abc"}]}
        """))
        check(queued?.isActive == true && queued?.isQueued == true, "Queued run")
        let completed = ShadowBuildStatus.parseLatestRun(data("""
        {"workflow_runs":[{"id":1,"status":"completed","conclusion":"success","head_sha":"abc"}]}
        """))
        check(completed?.isActive == false, "Completed run is not active")
        check(ShadowBuildStatus.parseLatestRun(data(#"{"workflow_runs":[]}"#)) == nil, "No runs")
        check(ShadowBuildStatus.parseLatestRun(data("garbage")) == nil, "Bad JSON")

        let step = ShadowBuildStatus.parseCurrentStep(data("""
        {"jobs":[{"steps":[{"name":"Restore Bazel output","status":"completed"},{"name":"Build the App","status":"in_progress"},{"name":"Save Bazel output","status":"queued"}]}]}
        """))
        check(step == "Build the App", "In-progress step")
        let between = ShadowBuildStatus.parseCurrentStep(data("""
        {"jobs":[{"steps":[{"name":"Restore Bazel output","status":"completed"},{"name":"Set active Xcode path","status":"queued"}]}]}
        """))
        check(between == "Restore Bazel output", "Last finished step between steps")
        check(ShadowBuildStatus.parseCurrentStep(data(#"{"jobs":[{"steps":[]}]}"#)) == nil, "No steps yet")

        let progress = ShadowBuildStatus.parseProgress(data("""
        {"check_runs":[{"name":"Other","output":{"title":"[1 / 2]","summary":"build=1"}},{"name":"Shadow build progress","output":{"title":"Build the App [4,872 / 5,876]","summary":"build=34757"}}]}
        """))
        check(progress?.done == 4872 && progress?.total == 5876, "Progress counter")
        check(progress?.build == 34757, "Build number")
        let noCounter = ShadowBuildStatus.parseProgress(data("""
        {"check_runs":[{"name":"Shadow build progress","output":{"title":"Build the App","summary":"build=34757"}}]}
        """))
        check(noCounter?.done == nil && noCounter?.build == 34757, "Build without counter yet")
        check(ShadowBuildStatus.parseProgress(data(#"{"check_runs":[]}"#)) == nil, "No progress check")

        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(12 * 60 + 30)
        let full = ShadowBuildStatus.text(.init(isQueued: false, step: "Build the App", done: 4872, total: 5876, build: 34757, startedAt: start), now: now)
        check(full == "Собирается сборка 34757 · Build the App [4 872/5 876] · 82% · идёт 12 мин", "Full text: \(full)")
        let restore = ShadowBuildStatus.text(.init(isQueued: false, step: "Restore Bazel output", startedAt: start), now: now)
        check(restore == "Собирается новая сборка · Restore Bazel output · идёт 12 мин", "Step text: \(restore)")
        check(ShadowBuildStatus.text(.init(isQueued: true)) == "Новая сборка в очереди", "Queued text")

        print("BuildStatusTests: \(count) checks passed")
    }
}
