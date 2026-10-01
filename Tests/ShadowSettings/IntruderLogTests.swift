import Foundation

@main
struct IntruderLogTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        let suite = "shadow-intruder-tests-\(UInt64.random(in: 0 ... UInt64.max))"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ShadowIntruderLog(defaults: defaults, directory: directory)

        check(!log.isEnabled, "Off by default")
        check(!log.beginCapture(), "No capture while off")
        log.isEnabled = true
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        check(log.beginCapture(now: start), "First capture")
        check(!log.beginCapture(now: start.addingTimeInterval(5)), "Rate limited")
        check(log.beginCapture(now: start.addingTimeInterval(ShadowIntruderLog.minimumInterval + 1)), "Allowed after the interval")
        check(log.isCapturing, "Captures in flight")
        log.endCapture()
        log.endCapture()
        check(!log.isCapturing, "Ended captures")
        log.endCapture()
        check(!log.isCapturing, "Extra end is harmless")

        check(log.pending().isEmpty, "Nothing pending")
        check(log.save(jpeg: Data(), reason: .passcode) == nil, "Empty data is not saved")
        log.save(jpeg: Data([0xFF, 0xD8, 0x01]), reason: .chatLock, date: start.addingTimeInterval(10))
        log.save(jpeg: Data([0xFF, 0xD8, 0x02]), reason: .passcode, date: start)
        let pending = log.pending()
        check(pending.count == 2, "Two pending")
        check(pending.first?.reason == .passcode && pending.last?.reason == .chatLock, "Oldest first with reasons")
        check(abs((pending.first?.date.timeIntervalSince1970 ?? 0) - start.timeIntervalSince1970) < 0.01, "Date round-trips")
        if let first = pending.first {
            log.remove(first)
        }
        check(log.pending().count == 1, "Removed")

        print("Shadow intruder log: \(count) checks passed")
    }
}
