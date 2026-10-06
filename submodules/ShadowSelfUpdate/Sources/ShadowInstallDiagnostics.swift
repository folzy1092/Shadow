import Foundation

// Shadow: what the local install saw — the line under the status on
// «Обновление» and the cause shown when no iOS window appears in time.
// Foundation only: the foundation suite checks the texts on macOS.

// Requests and connections seen by ShadowInstallServer.
public struct ShadowInstallActivity: Equatable {
    public var listener: String = "запуск"
    public var isReady = false
    public var connections = 0
    public var connectionErrors = 0
    public var tlsErrors = 0
    public var lastConnectionError: String?
    public var pageRequested = false
    public var manifestRequested = false
    public var iconsRequested = false
    public var payloadRequested = false

    public init() {
    }
}

public struct ShadowInstallDiagnostics: Equatable {
    public enum Route: Equatable {
        // IPA on http://127.0.0.1, manifest from api.palera.in.
        case localHTTP
        // Everything on https://shadow.backloop.dev.
        case backloopHTTPS
    }

    public enum Opener: Equatable {
        // SFSafariViewController on http://127.0.0.1:PORT/install.
        case safariPage
        // UIApplication.open(itms-services://…).
        case openURL
    }

    public enum Check: Equatable {
        case pending
        case ok
        case failed(String)
    }

    public var route: Route = .localHTTP
    public var opener: Opener = .safariPage
    // UIApplication.open completion; nil until it reports.
    public var openResult: Bool?
    // The app's own GET of the api.palera.in manifest.
    public var externalManifest: Check = .pending
    // getaddrinfo of shadow.backloop.dev.
    public var resolved: [String]?
    public var resolveError: String?
    // The backloop.dev pack: trust evaluation of its certificate.
    public var certificate: Check = .pending
    public var certificateNotAfter: Date?
    public var server = ShadowInstallActivity()
    // The app resigned active after the open: a system window covered it.
    public var promptSeen = false

    public init() {
    }

    public var line: String {
        var parts: [String] = []
        switch self.route {
        case .localHTTP:
            parts.append("HTTP 127.0.0.1")
            parts.append("манифест palera \(Self.mark(self.externalManifest))")
        case .backloopHTTPS:
            parts.append("HTTPS backloop")
        }
        switch self.opener {
        case .safariPage:
            parts.append("Safari \(self.server.pageRequested ? "✓" : "—")")
        case .openURL:
            parts.append("open \(self.openResult.map { $0 ? "✓" : "✗" } ?? "…")")
        }
        parts.append("DNS \(self.resolvedText)")
        parts.append("сервер \(self.server.listener)")
        var connections = "подкл. \(self.server.connections)"
        if self.server.connectionErrors > 0 {
            connections += ", ошибок \(self.server.connectionErrors)"
        }
        if self.server.tlsErrors > 0 {
            connections += ", TLS \(self.server.tlsErrors)"
        }
        if let error = self.server.lastConnectionError {
            connections += " (\(error))"
        }
        parts.append(connections)
        switch self.route {
        case .localHTTP:
            parts.append("ipa \(self.server.payloadRequested ? "✓" : "—")")
        case .backloopHTTPS:
            parts.append("manifest \(self.server.manifestRequested ? "✓" : "—")")
            parts.append("иконки \(self.server.iconsRequested ? "✓" : "—")")
            parts.append("ipa \(self.server.payloadRequested ? "✓" : "—")")
        }
        var certificate = "серт. backloop"
        if let notAfter = self.certificateNotAfter {
            certificate += " до \(Self.dateText(notAfter))"
        }
        certificate += " \(Self.mark(self.certificate))"
        parts.append(certificate)
        return parts.joined(separator: " · ")
    }

    // Why the iOS window has not appeared, most specific first; ends with
    // the way around it.
    public func cause(now: Date) -> String {
        return self.reason(now: now) + " Или «Поделиться подписанным IPA» и установить его через ESign."
    }

    private func reason(now: Date) -> String {
        if !self.server.isReady {
            return "Локальный сервер не работает (\(self.server.listener)). «Показать окно установки» перезапустит его."
        }
        if self.server.payloadRequested {
            return "iOS начала загрузку, но не закончила. Держите Shadow открытым и нажмите «Показать окно установки»."
        }
        if self.opener == .openURL, self.openResult == false {
            return "iOS отказалась открыть ссылку itms-services."
        }
        // Without the manifest iOS has no window to show: whatever covered
        // the app was something else.
        if self.route == .localHTTP, case let .failed(error) = self.externalManifest {
            return "Не удалось получить манифест с api.palera.in (\(error)): без него iOS не покажет окно. Проверьте интернет и VPN."
        }
        if self.promptSeen {
            return "Окно установки показано, но iOS не начала загрузку. Если нажали «Отмена» — нажмите «Показать окно установки»."
        }
        switch self.route {
        case .localHTTP:
            if self.opener == .safariPage, !self.server.pageRequested {
                return "Safari не открыл страницу установки на 127.0.0.1. «Показать окно установки» откроет окно напрямую."
            }
            return "Ссылка установки открыта, но iOS не показала окно. Обычно iOS не смогла скачать манифест с api.palera.in: проверьте VPN и DNS-фильтры."
        case .backloopHTTPS:
            if case let .failed(error) = self.certificate {
                return "Сертификат backloop.dev \(error): iOS не доверяет локальному серверу."
            }
            if let notAfter = self.certificateNotAfter, notAfter <= now {
                return "Сертификат backloop.dev истёк \(Self.dateText(notAfter)): iOS не доверяет локальному серверу."
            }
            if let dns = self.dnsProblem {
                return dns
            }
            if self.server.tlsErrors > 0 {
                return "iOS отвергла TLS-подключение к локальному серверу (\(self.server.lastConnectionError ?? "ошибка TLS"))."
            }
            if self.server.connections == 0 {
                return "iOS ни разу не подключилась к локальному серверу: ссылка не дошла до установщика."
            }
            if !self.server.manifestRequested {
                return "iOS подключилась, но не запросила манифест (\(self.server.lastConnectionError ?? "соединение закрыто"))."
            }
            return "iOS получила манифест, но не показала окно."
        }
    }

    // A loopback hostname has to resolve to 127.0.0.1 or ::1.
    private var dnsProblem: String? {
        if let error = self.resolveError {
            return "shadow.backloop.dev не находится в DNS (\(error)): проверьте VPN и DNS-фильтры."
        }
        guard let addresses = self.resolved, !addresses.isEmpty else {
            return nil
        }
        let kinds = addresses.map { ShadowInstallLinks.classify($0) }
        if kinds.contains(.loopback) {
            return nil
        }
        let list = addresses.prefix(2).joined(separator: ", ")
        if kinds.contains(.fakeIP) {
            return "VPN подменяет DNS (shadow.backloop.dev → \(list)): выключите VPN или добавьте backloop.dev в исключения."
        }
        if kinds.contains(.blocked) {
            return "DNS-фильтр блокирует backloop.dev (\(list))."
        }
        if kinds.contains(.nat64) {
            return "Сеть только IPv6 (NAT64): shadow.backloop.dev → \(list)."
        }
        return "DNS вернул для shadow.backloop.dev не локальный адрес (\(list)): похоже на защиту от DNS rebinding в роутере."
    }

    private var resolvedText: String {
        if let error = self.resolveError {
            return "✗ \(error)"
        }
        guard let addresses = self.resolved else {
            return "…"
        }
        if addresses.isEmpty {
            return "пусто"
        }
        return addresses.prefix(3).joined(separator: ", ")
    }

    private static func mark(_ check: Check) -> String {
        switch check {
        case .pending:
            return "…"
        case .ok:
            return "✓"
        case let .failed(error):
            return "✗ \(error)"
        }
    }

    static func dateText(_ date: Date) -> String {
        return self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()
}
