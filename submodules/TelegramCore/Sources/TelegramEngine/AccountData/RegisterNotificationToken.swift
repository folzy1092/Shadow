import Foundation
import SwiftSignalKit
import Postbox
import TelegramApi


public enum NotificationTokenType {
    case aps(encrypt: Bool)
    case voip
}

func _internal_unregisterNotificationToken(account: Account, token: Data, type: NotificationTokenType, otherAccountUserIds: [PeerId.Id]) -> Signal<Never, NoError> {
    let mappedType: Int32
    switch type {
        case .aps:
            mappedType = 1
        case .voip:
            mappedType = 9
    }
    return account.network.request(Api.functions.account.unregisterDevice(tokenType: mappedType, token: hexString(token), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
    |> retryRequest
    |> ignoreValues
}

func _internal_registerNotificationToken(account: Account, token: Data, type: NotificationTokenType, sandbox: Bool, otherAccountUserIds: [PeerId.Id], excludeMutedChats: Bool) -> Signal<NotificationTokenRegistrationResult, NoError> {
    return masterNotificationsKey(account: account, ignoreDisabled: false)
    |> mapToSignal { masterKey -> Signal<NotificationTokenRegistrationResult, NoError> in
        let mappedType: Int32
        var keyData = Data()
        switch type {
            case let .aps(encrypt):
                mappedType = 1
                if encrypt {
                    keyData = masterKey.data
                }
            case .voip:
                mappedType = 9
                keyData = masterKey.data
        }
        var flags: Int32 = 0
        if excludeMutedChats {
            flags |= 1 << 0
        }
        ShadowPushDiagnostics.shared.registrationStarted(accountId: account.id.int64, tokenType: mappedType, sandbox: sandbox, encrypted: !keyData.isEmpty, otherAccountCount: otherAccountUserIds.count, noMuted: excludeMutedChats)
        return account.network.request(Api.functions.account.registerDevice(flags: flags, tokenType: mappedType, token: hexString(token), appSandbox: sandbox ? .boolTrue : .boolFalse, secret: Buffer(data: keyData), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
        |> map { value -> NotificationTokenRegistrationResult in
            let accepted: Bool
            switch value {
            case .boolTrue: accepted = true
            case .boolFalse: accepted = false
            }
            let result = NotificationTokenRegistrationResult.acknowledged(accepted)
            ShadowPushDiagnostics.shared.registrationFinished(accountId: account.id.int64, tokenType: mappedType, result: result)
            Logger.shared.log("ShadowPush", "token_type=\(mappedType) \(result.diagnosticDescription)")
            return result
        }
        |> `catch` { error -> Signal<NotificationTokenRegistrationResult, NoError> in
            let result = NotificationTokenRegistrationResult.rpcError(code: error.errorCode, description: error.errorDescription)
            ShadowPushDiagnostics.shared.registrationFinished(accountId: account.id.int64, tokenType: mappedType, result: result)
            Logger.shared.log("ShadowPush", "token_type=\(mappedType) \(result.diagnosticDescription)")
            return .single(result)
        }
    }
}
