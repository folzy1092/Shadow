import Foundation

// Shadow: links of the local install. Foundation only, so the foundation suite
// checks them on macOS.
//
// Two routes, as in IPA Hub (Feather):
// - local HTTP ("Semi Local" + "Only use localhost address"): the IPA is on
//   http://127.0.0.1:PORT, no DNS and no local TLS. itms-services wants an
//   https manifest, so it comes from api.palera.in/genPlist, which only
//   builds the plist from the query. Safari opens /install, a page that sends
//   it on to itms-services.
// - backloop HTTPS ("Fully Local"): everything on https://shadow.backloop.dev
//   (127.0.0.1 and ::1 in public DNS) with the *.backloop.dev certificate.
public enum ShadowInstallLinks {
    public static let loopback = "127.0.0.1"
    static let externalManifestBase = "https://api.palera.in/genPlist"
    static let payloadPath = "/shadow.ipa"
    static let pagePath = "/install"
    static let manifestPath = "/manifest.plist"

    // RFC 3986 unreserved, ASCII only: CharacterSet.alphanumerics also lets
    // non-ASCII letters through unencoded.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: self.unreserved) ?? ""
    }

    public static func payloadURL(port: UInt16) -> URL {
        return URL(string: "http://\(self.loopback):\(port)\(self.payloadPath)")!
    }

    public static func pageURL(port: UInt16) -> URL {
        return URL(string: "http://\(self.loopback):\(port)\(self.pagePath)")!
    }

    public static func backloopManifestURL(host: String, port: UInt16) -> URL? {
        return URL(string: "https://\(host):\(port)\(self.manifestPath)")
    }

    // palera.in puts the values into the plist without XML escaping: the
    // title keeps only characters that need none.
    static func plainTitle(_ title: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .-_()")
        let cleaned = String(title.filter { allowed.contains($0) }).split(separator: " ").joined(separator: " ")
        return cleaned.isEmpty ? "Shadow" : cleaned
    }

    static func isPlainToken(_ value: String) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_")
        return !value.isEmpty && value.allSatisfy { allowed.contains($0) }
    }

    // https://api.palera.in/genPlist?bundleid=…&name=…&version=…&fetchurl=…
    public static func externalManifestURL(bundleId: String, bundleVersion: String, title: String, payload: URL) -> URL? {
        guard self.isPlainToken(bundleId), self.isPlainToken(bundleVersion) else {
            return nil
        }
        let query = [
            ("bundleid", bundleId),
            ("name", self.plainTitle(title)),
            ("version", bundleVersion),
            ("fetchurl", payload.absoluteString)
        ].map { "\($0.0)=\(self.encode($0.1))" }.joined(separator: "&")
        return URL(string: self.externalManifestBase + "?" + query)
    }

    public static func itmsURL(manifest: URL) -> URL? {
        let encoded = self.encode(manifest.absoluteString)
        guard !encoded.isEmpty else {
            return nil
        }
        return URL(string: "itms-services://?action=download-manifest&url=" + encoded)
    }

    // Why the api.palera.in manifest is unusable (short, for the diagnostics
    // line); nil when it is a plist for this payload.
    public static func externalManifestProblem(data: Data?, response: URLResponse?, error: Error?, payload: URL) -> String? {
        if let error {
            switch (error as? URLError)?.code {
            case .timedOut?:
                return "нет ответа"
            case .notConnectedToInternet?, .networkConnectionLost?:
                return "нет интернета"
            case .cannotFindHost?, .dnsLookupFailed?:
                return "DNS"
            case .secureConnectionFailed?, .serverCertificateUntrusted?, .serverCertificateHasBadDate?, .serverCertificateNotYetValid?, .serverCertificateHasUnknownRoot?, .clientCertificateRejected?:
                return "TLS"
            case let code?:
                return "ошибка \(code.rawValue)"
            case nil:
                return "ошибка"
            }
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            return "нет ответа"
        }
        guard status == 200 else {
            return "HTTP \(status)"
        }
        let body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        guard body.contains("software-package"), body.contains(payload.absoluteString) else {
            return "неверный ответ"
        }
        return nil
    }

    // The /install page: Safari follows the script; the link is for a second
    // try by hand.
    public static func installPage(itms: URL) -> String {
        // The link is percent-encoded ASCII: no quotes, angle brackets or
        // backslashes; only & needs escaping in the attribute.
        let link = itms.absoluteString
        let attribute = link.replacingOccurrences(of: "&", with: "&amp;")
        return """
        <!doctype html>
        <html lang="ru"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Shadow</title>
        <style>body{margin:0;padding:30vh 24px 0;background:#000;color:#fff;font:17px -apple-system,sans-serif;text-align:center}a{display:inline-block;margin-top:16px;padding:14px 28px;border-radius:12px;background:#2c8cff;color:#fff;text-decoration:none;font-weight:600}</style>
        </head><body>
        <div>Если окно установки не появилось:</div>
        <a href="\(attribute)">Установить Shadow</a>
        <script>window.location="\(link)"</script>
        </body></html>
        """
    }

    // MARK: - Addresses

    public enum AddressKind: Equatable {
        case loopback
        // 0.0.0.0 or :: — a DNS filter answers so for blocked names.
        case blocked
        // 198.18.0.0/15 and 240.0.0.0/4: fake-IP DNS of VPN apps.
        case fakeIP
        // 64:ff9b::/96: an IPv6-only network synthesized an address.
        case nat64
        case privateNetwork
        case publicNetwork
        case invalid
    }

    public static func classify(_ text: String) -> AddressKind {
        let address = text.split(separator: "%", maxSplits: 1).first.map(String.init) ?? text
        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            let value = UInt32(bigEndian: v4.s_addr)
            return self.classify(v4: (UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)))
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, address, &v6) == 1 else {
            return .invalid
        }
        let bytes = withUnsafeBytes(of: &v6) { Array($0) }
        if bytes.allSatisfy({ $0 == 0 }) {
            return .blocked
        }
        if bytes[0 ..< 15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 {
            return .loopback
        }
        // ::ffff:a.b.c.d
        if bytes[0 ..< 10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
            return self.classify(v4: (bytes[12], bytes[13], bytes[14], bytes[15]))
        }
        if bytes[0 ..< 12] == [0x00, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0] {
            return .nat64
        }
        if bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) {
            return .privateNetwork
        }
        return .publicNetwork
    }

    private static func classify(v4 a: (UInt8, UInt8, UInt8, UInt8)) -> AddressKind {
        switch a.0 {
        case 127:
            return .loopback
        case 0:
            return .blocked
        case 10:
            return .privateNetwork
        case 172 where a.1 & 0xf0 == 16:
            return .privateNetwork
        case 192 where a.1 == 168:
            return .privateNetwork
        case 169 where a.1 == 254:
            return .privateNetwork
        case 100 where a.1 & 0xc0 == 64:
            return .privateNetwork
        case 198 where a.1 & 0xfe == 18:
            return .fakeIP
        case 240 ... 255:
            return .fakeIP
        default:
            return .publicNetwork
        }
    }

    // getaddrinfo with AI_ADDRCONFIG, as the system installer's lookup; blocks
    // until DNS answers, so call it off the main thread.
    public static func resolve(host: String) -> (addresses: [String], error: String?) {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_ADDRCONFIG
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, "443", &hints, &result)
        guard status == 0, let first = result else {
            return ([], String(cString: gai_strerror(status)))
        }
        defer {
            freeaddrinfo(first)
        }
        var addresses: [String] = []
        var next: UnsafeMutablePointer<addrinfo>? = first
        while let info = next {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let text = String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if !addresses.contains(text) {
                    addresses.append(text)
                }
            }
            next = info.pointee.ai_next
        }
        return (addresses, nil)
    }
}
