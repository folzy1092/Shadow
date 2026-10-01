import Foundation

@main
struct CrashReportsTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-crash-tests-\(UInt64.random(in: 0 ... UInt64.max))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShadowCrashReports(directory: directory)

        check(store.reports().isEmpty, "Empty at first")
        check(store.save(Data()) == nil, "Empty data is not saved")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(Data("{\"a\":1}".utf8), date: base)
        store.save(Data("{\"a\":2}".utf8), date: base)
        store.save(Data("{\"a\":3}".utf8), date: base.addingTimeInterval(60))
        let reports = store.reports()
        check(reports.count == 3, "Same timestamp does not overwrite")
        check(reports.first?.date == base.addingTimeInterval(60), "Newest first")
        for i in 0 ..< ShadowCrashReports.limit + 5 {
            store.save(Data("{}".utf8), date: base.addingTimeInterval(TimeInterval(1000 + i)))
        }
        check(store.reports().count == ShadowCrashReports.limit, "Old reports dropped")
        store.removeAll()
        check(store.reports().isEmpty, "Removed")

        print("Shadow crash reports: \(count) checks passed")
    }
}
