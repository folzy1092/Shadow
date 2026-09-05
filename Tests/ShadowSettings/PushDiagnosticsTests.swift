import Foundation

@main
struct PushDiagnosticsTests {
    static func main() {
        precondition(!NotificationTokenRegistrationResult.acknowledged(false).requiresTokenInvalidation)
        precondition(!NotificationTokenRegistrationResult.acknowledged(true).requiresTokenInvalidation)
        precondition(!NotificationTokenRegistrationResult.notRequired.requiresTokenInvalidation)
        for error in ["TOKEN_INVALID", "TOKEN_TYPE_INVALID", "TOKEN_EMPTY", "TIMEOUT"] {
            let result = NotificationTokenRegistrationResult.rpcError(code: 400, description: error)
            precondition(!result.requiresTokenInvalidation)
            precondition(result.diagnosticDescription.contains(error))
        }
        precondition(NotificationTokenRegistrationResult.rpcError(code: 400, description: "TOKEN_WAS_INVALIDATED").requiresTokenInvalidation)
        let store = ShadowPushDiagnostics.shared
        precondition(store.snapshot(accountId: 1).token == nil)
        store.apnsRegistrationCalled()
        store.apnsRegistrationSucceeded(token: Data([0, 1, 2]))
        store.registrationStarted(accountId: 1, tokenType: 1, sandbox: false, encrypted: true, otherAccountCount: 2, noMuted: true)
        store.registrationFinished(accountId: 1, tokenType: 1, result: .acknowledged(false))
        precondition(store.snapshot(accountId: 1).registration.contains("Bool=false"))
        precondition(store.snapshot(accountId: 2).registration.contains("Не наблюдалась"))
        precondition(store.snapshot(accountId: 1, tokenType: 9).registration.contains("Не наблюдалась"))
        precondition(store.snapshot(accountId: 1).token == Data([0, 1, 2]))
        print("Push diagnostics: result fidelity, scoped state and invalidation policy passed")
    }
}
