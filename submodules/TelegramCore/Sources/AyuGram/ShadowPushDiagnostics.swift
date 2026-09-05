import Foundation

/// A server acknowledgement is not proof that an APNs notification was delivered.
public enum NotificationTokenRegistrationResult: Equatable {
    case acknowledged(Bool)
    case rpcError(code: Int32, description: String)
    case notRequired

    public var requiresTokenInvalidation: Bool {
        if case let .rpcError(_, description) = self {
            return description == "TOKEN_WAS_INVALIDATED"
        }
        return false
    }

    public var diagnosticDescription: String {
        switch self {
        case let .acknowledged(value): return "registerDevice Bool=\(value)"
        case let .rpcError(code, description): return "registerDevice RPC \(code): \(description)"
        case .notRequired: return "Регистрация не запрошена для этого аккаунта"
        }
    }
}

/// Session-only diagnostics. No token, encryption secret or account id is written to disk.
public final class ShadowPushDiagnostics {
    public static let shared = ShadowPushDiagnostics()
    public static var telegramSandbox: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    public struct Snapshot {
        public var apnsCalled = "Не наблюдалось в этой сессии"
        public var apnsStatus = "Ожидание callback iOS"
        public var token: Data?
        public var registration = "Не наблюдалась в этой сессии"
        public var parameters = "—"
    }

    private let lock = NSLock()
    private var state = Snapshot()
    private var registrations: [String: (String, String)] = [:]

    private static func timestamp() -> String {
        return ISO8601DateFormatter().string(from: Date())
    }

    public func snapshot(accountId: Int64, tokenType: Int32 = 1) -> Snapshot {
        self.lock.lock()
        defer { self.lock.unlock() }
        var result = self.state
        if let registration = self.registrations["\(accountId):\(tokenType)"] {
            result.registration = registration.0
            result.parameters = registration.1
        }
        return result
    }

    public func apnsRegistrationCalled() {
        self.lock.lock()
        self.state.apnsCalled = Self.timestamp()
        self.lock.unlock()
    }

    public func apnsRegistrationSucceeded(token: Data) {
        self.lock.lock()
        self.state.apnsStatus = "Успех · \(Self.timestamp()) · \(token.count) байт"
        self.state.token = token
        self.lock.unlock()
    }

    public func apnsRegistrationFailed(error: Error) {
        let error = error as NSError
        self.lock.lock()
        self.state.apnsStatus = "Ошибка · \(Self.timestamp())\n\(error.domain) (\(error.code))\n\(error.localizedDescription)\n\(error.userInfo)"
        self.lock.unlock()
    }

    public func registrationStarted(accountId: Int64, tokenType: Int32, sandbox: Bool, encrypted: Bool, otherAccountCount: Int, noMuted: Bool) {
        self.lock.lock()
        self.registrations["\(accountId):\(tokenType)"] = (
            "Запрос отправлен · \(Self.timestamp())",
            "token_type=\(tokenType), app_sandbox=\(sandbox), secret=\(encrypted ? "present" : "empty"), other_uids.count=\(otherAccountCount), no_muted=\(noMuted)"
        )
        self.lock.unlock()
    }

    public func registrationFinished(accountId: Int64, tokenType: Int32, result: NotificationTokenRegistrationResult) {
        self.lock.lock()
        let key = "\(accountId):\(tokenType)"
        self.registrations[key] = ("\(result.diagnosticDescription) · \(Self.timestamp())", self.registrations[key]?.1 ?? "—")
        self.lock.unlock()
    }
}
