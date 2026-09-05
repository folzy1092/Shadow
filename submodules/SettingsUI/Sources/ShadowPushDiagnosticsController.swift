import Foundation
import UIKit
import UserNotifications
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private enum ShadowPushEntry: ItemListNodeEntry {
    case report(String)
    case token(String)
    case retry
    case help

    var section: ItemListSectionId { return self.stableId }
    var stableId: Int32 {
        switch self { case .report: return 0; case .token: return 1; case .retry: return 2; case .help: return 3 }
    }
    static func < (lhs: ShadowPushEntry, rhs: ShadowPushEntry) -> Bool { return lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ShadowPushArguments
        switch self {
        case let .report(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .token(text):
            return ItemListDisclosureItem(presentationData: presentationData, title: "APNs device token", label: text, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, action: arguments.toggleToken)
        case .retry:
            return ItemListActionItem(presentationData: presentationData, title: "Повторить регистрацию push", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.retry)
        case .help:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Токен скрыт: нажмите на строку, чтобы показать/скрыть его локально. Не публикуйте скриншоты с токеном.\n\nСтатусы относятся к этой сессии приложения и выбранному аккаунту. APNs callback и Telegram Bool=true не доказывают доставку push. Ошибки APNs Provider API доступны только серверу-отправителю. Повторная регистрация не запрашивает разрешение на показ уведомлений — его можно изменить в настройках iOS.\n\nEntitlements прочитаны из XML-блока подписи исполняемого файла, не из профиля. Это не проверка подписи и не запрос к ядру; для DER-only подписи значение будет неизвестно. NSE detected означает наличие расширения, а не его успешный запуск."), sectionId: self.section)
        }
    }
}

private final class ShadowPushArguments {
    let toggleToken: () -> Void
    let retry: () -> Void
    init(toggleToken: @escaping () -> Void, retry: @escaping () -> Void) {
        self.toggleToken = toggleToken
        self.retry = retry
    }
}

public func shadowPushDiagnosticsController(context: AccountContext) -> ViewController {
    let revealed = ValuePromise<Bool>(false, ignoreRepeated: true)
    var isRevealed = false
    let permission = ValuePromise<String>("Запрос состояния iOS…", ignoreRepeated: true)
    let refreshPermission: () -> Void = {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            permission.set("\(settings.authorizationStatus) (raw=\(settings.authorizationStatus.rawValue)), alert=\(settings.alertSetting.rawValue), sound=\(settings.soundSetting.rawValue), badge=\(settings.badgeSetting.rawValue)")
        }
    }
    let arguments = ShadowPushArguments(toggleToken: {
        isRevealed.toggle()
        revealed.set(isRevealed)
    }, retry: {
        refreshPermission()
        ShadowPushDiagnostics.shared.apnsRegistrationCalled()
        UIApplication.shared.registerForRemoteNotifications()
        context.sharedContext.updateNotificationTokensRegistration()
    })
    let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
    let entitlements = ShadowCodeSignature.entitlements(executableURL: Bundle.main.executableURL)
    func value(_ key: String) -> String {
        guard let entitlements = entitlements else { return "Не удалось прочитать подпись" }
        guard let value = entitlements[key] else { return "Отсутствует" }
        if let values = value as? [String] { return values.joined(separator: ", ") }
        return String(describing: value)
    }
    let appGroup = "group.\(bundleId)"
    let groupAccessible = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    let pluginURLs = Bundle.main.builtInPlugInsURL.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
    let services = pluginURLs.compactMap { url -> String? in
        guard let bundle = Bundle(url: url), let ext = bundle.infoDictionary?["NSExtension"] as? [String: Any], ext["NSExtensionPointIdentifier"] as? String == "com.apple.usernotifications.service" else { return nil }
        return bundle.bundleIdentifier ?? url.lastPathComponent
    }
    let staticReport = """
    CFBundleIdentifier: \(bundleId)
    application-identifier: \(value("application-identifier"))
    Team Identifier: \(value("com.apple.developer.team-identifier"))
    aps-environment: \(value("aps-environment"))
    keychain-access-groups: \(value("keychain-access-groups"))
    application-groups: \(value("com.apple.security.application-groups"))
    Build: \(ShadowPushDiagnostics.telegramSandbox ? "DEBUG" : "release")
    Telegram appSandbox: \(ShadowPushDiagnostics.telegramSandbox)
    Expected App Group: \(appGroup)
    Shared container accessible: \(groupAccessible)
    NotificationService detected: \(services.isEmpty ? "Нет" : services.joined(separator: ", "))
    """
    let ticks = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let timer = SwiftSignalKit.Timer(timeout: 2.0, repeat: true, completion: {
            refreshPermission()
            subscriber.putNext(0)
        }, queue: .mainQueue())
        timer.start()
        return ActionDisposable { timer.invalidate() }
    }
    refreshPermission()
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, permission.get(), revealed.get(), ticks)
    |> map { presentationData, permission, revealed, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let snapshot = ShadowPushDiagnostics.shared.snapshot(accountId: context.account.id.int64)
        let voip = ShadowPushDiagnostics.shared.snapshot(accountId: context.account.id.int64, tokenType: 9)
        let lastNSE = groupAccessible ? UserDefaults(suiteName: appGroup)?.string(forKey: "ShadowPushNSELastEvent") : nil
        let report = """
        Notification permission: \(permission)
        iOS registeredForRemoteNotifications: \(UIApplication.shared.isRegisteredForRemoteNotifications)
        registerForRemoteNotifications called: \(snapshot.apnsCalled)
        APNs registration: \(snapshot.apnsStatus)

        \(staticReport)

        Telegram APNs: \(snapshot.registration)
        \(snapshot.parameters)
        Telegram VoIP: \(voip.registration)
        \(voip.parameters)
        NSE last event (shared storage): \(lastNSE ?? "Не наблюдалось / нет общей группы")
        """
        let token: String
        if let data = snapshot.token {
            token = revealed ? data.map { String(format: "%02x", $0) }.joined() : "Получен (\(data.count) байт). Нажмите, чтобы показать."
        } else {
            token = "Не получен в этой сессии"
        }
        let entries: [ShadowPushEntry] = [.report(report), .token(token), .retry, .help]
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Диагностика push"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false), arguments))
    }
    return ItemListController(context: context, state: signal)
}
