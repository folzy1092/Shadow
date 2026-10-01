import Foundation
import MetricKit
import TelegramCore

// Shadow: subscribes to MetricKit; iOS hands over crash diagnostics on a
// later launch and they are stored in ShadowCrashReports (spec 7.9). No
// third-party service and no keys in the app: the user sends a report to a
// chat from the Shadow settings.
final class ShadowCrashReporter: NSObject, MXMetricManagerSubscriber {
    private static var instance: ShadowCrashReporter?

    static func start() {
        if #available(iOS 14.0, *) {
            if self.instance == nil {
                let reporter = ShadowCrashReporter()
                self.instance = reporter
                MXMetricManager.shared.add(reporter)
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
    }

    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            guard let crashes = payload.crashDiagnostics, !crashes.isEmpty else {
                continue
            }
            for crash in crashes {
                ShadowCrashReports.shared.save(crash.jsonRepresentation(), date: payload.timeStampEnd)
            }
        }
    }
}
