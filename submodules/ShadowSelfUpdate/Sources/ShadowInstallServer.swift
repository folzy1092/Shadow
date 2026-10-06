import Foundation
import Network
import Security
import ImageIO
import CoreGraphics

// Shadow: a tiny server on 127.0.0.1 for itms-services, like Feather's
// ServerInstaller but on Network.framework instead of Vapor. It serves the
// signed IPA (with Range support), the /install page that hands the
// itms-services link to Safari, the manifest with two icons for the HTTPS
// route, and reports what the system installer asked for.
final class ShadowInstallServer {
    struct Item {
        let ipaURL: URL
        let bundleId: String
        let bundleVersion: String
        let title: String
    }

    enum Route {
        // Plain HTTP on the 127.0.0.1 literal: no DNS, no local TLS. The
        // manifest comes from api.palera.in (Feather's "Semi Local").
        case localHTTP
        // HTTPS for shadow.backloop.dev on 127.0.0.1 and ::1 with the
        // backloop pack (Feather's "Fully Local").
        case backloopHTTPS(ShadowLocalTLSIdentity.Material)

        var isLocalHTTP: Bool {
            if case .localHTTP = self {
                return true
            }
            return false
        }
    }

    private let item: Item
    let route: Route
    private let queue = DispatchQueue(label: "ShadowInstallServer")
    private var listeners: [NWListener] = []
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let ipaSize: Int64
    private var port: UInt16?
    // The itms-services link /install leads to.
    private var pageTarget: URL?
    private var activity = ShadowInstallActivity()
    // Bytes of the IPA handed to the installer, over all requests: a Range
    // request for the tail (the zip directory) does not end the transfer.
    private var payloadSent = IndexSet()
    private var didReportManifest = false
    private var didReportPayload = false
    private var didReportFinished = false

    // All callbacks run on the server queue.
    var onActivity: ((ShadowInstallActivity) -> Void)?
    var onManifestRequested: (() -> Void)?
    var onPayloadRequested: (() -> Void)?
    var onPayloadProgress: ((Int64, Int64) -> Void)?
    var onPayloadFinished: (() -> Void)?

    init(item: Item, route: Route) {
        self.item = item
        self.route = route
        self.ipaSize = ((try? FileManager.default.attributesOfItem(atPath: item.ipaURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    deinit {
        for listener in self.listeners {
            listener.cancel()
        }
    }

    // completion runs once, on the server queue, with the port.
    func start(completion: @escaping (Result<UInt16, Error>) -> Void) {
        var tls: NWProtocolTLS.Options?
        if case let .backloopHTTPS(material) = self.route {
            let options = NWProtocolTLS.Options()
            guard let identity = sec_identity_create_with_certificates(material.identity, material.chain as CFArray) else {
                completion(.failure(ServerError.identity))
                return
            }
            sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)
            sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
            tls = options
        }

        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        // Loopback only: the IPA is not offered to the local network.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            completion(.failure(error))
            return
        }
        self.listeners = [listener]
        var completed = false
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }
            switch state {
            case .ready:
                self.activity.listener = "работает"
                self.activity.isReady = true
                if !completed {
                    completed = true
                    if let port = listener.port?.rawValue {
                        self.port = port
                        self.startIPv6Listener(parameters: parameters, port: port)
                        completion(.success(port))
                    } else {
                        completion(.failure(ServerError.port))
                    }
                }
            case let .waiting(error):
                self.activity.listener = "ждёт: \(ShadowInstallServer.describe(error))"
                self.activity.isReady = false
            case let .failed(error):
                self.activity.listener = "ошибка: \(ShadowInstallServer.describe(error))"
                self.activity.isReady = false
                listener.cancel()
                if !completed {
                    completed = true
                    completion(.failure(error))
                }
            case .cancelled:
                if self.activity.isReady {
                    self.activity.listener = "остановлен"
                }
                self.activity.isReady = false
            default:
                break
            }
            self.reportActivity()
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: self.queue)
    }

    // shadow.backloop.dev also has AAAA ::1, which iOS tries first; the
    // second listener on the same port answers there. Best effort.
    private func startIPv6Listener(parameters: NWParameters, port: UInt16) {
        guard case .backloopHTTPS = self.route, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return
        }
        let ipv6 = parameters.copy()
        ipv6.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: endpointPort)
        guard let listener = try? NWListener(using: ipv6) else {
            return
        }
        listener.stateUpdateHandler = { state in
            if case .failed = state {
                listener.cancel()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listeners.append(listener)
        listener.start(queue: self.queue)
    }

    func stop() {
        self.queue.async {
            for listener in self.listeners {
                listener.cancel()
            }
            self.listeners.removeAll()
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
        }
    }

    // Must not be called on the server queue.
    func snapshot() -> ShadowInstallActivity {
        return self.queue.sync {
            self.activity
        }
    }

    func setPageTarget(_ itms: URL) {
        self.queue.async {
            self.pageTarget = itms
        }
    }

    // Where the manifest points the installer, by route.
    private var baseURL: URL? {
        guard let port = self.port else {
            return nil
        }
        switch self.route {
        case .localHTTP:
            return URL(string: "http://\(ShadowInstallLinks.loopback):\(port)/")
        case .backloopHTTPS:
            return URL(string: "https://\(ShadowLocalTLSIdentity.host):\(port)/")
        }
    }

    enum ServerError: LocalizedError {
        case identity
        case port

        var errorDescription: String? {
            switch self {
            case .identity: return "Не удалось подготовить TLS для локальной установки."
            case .port: return "Не удалось открыть локальный порт для установки."
            }
        }
    }

    static func describe(_ error: NWError) -> String {
        switch error {
        case let .posix(code):
            return "POSIX \(code.rawValue)"
        case let .tls(status):
            return "TLS \(status)"
        case let .dns(code):
            return "DNS \(code)"
        default:
            return "\(error)"
        }
    }

    private func reportActivity() {
        self.onActivity?(self.activity)
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        self.connections[id] = connection
        self.activity.connections += 1
        self.reportActivity()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }
            switch state {
            case let .waiting(error), let .failed(error):
                self.noteConnectionError(error)
                self.connections.removeValue(forKey: id)
                connection.cancel()
            case .cancelled:
                self.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: self.queue)
        self.readRequest(connection, buffer: Data())
    }

    private func noteConnectionError(_ error: NWError) {
        self.activity.connectionErrors += 1
        if case .tls = error {
            self.activity.tlsErrors += 1
        }
        self.activity.lastConnectionError = ShadowInstallServer.describe(error)
        self.reportActivity()
    }

    private func readRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[buffer.startIndex ..< end.lowerBound], as: UTF8.self)
                self.respond(connection, head: head)
            } else if error != nil || isComplete || buffer.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.readRequest(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.components(separatedBy: " ") ?? []
        guard requestLine.count >= 2 else {
            self.send(connection, status: "400 Bad Request", headers: [:], body: Data(), isHead: false)
            return
        }
        let method = requestLine[0].uppercased()
        let isHead = method == "HEAD"
        guard method == "GET" || isHead else {
            self.send(connection, status: "405 Method Not Allowed", headers: [:], body: Data(), isHead: false)
            return
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                headers[line[line.startIndex ..< colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let path = requestLine[1].components(separatedBy: "?").first ?? ""
        switch path {
        case ShadowInstallLinks.pagePath:
            guard let target = self.pageTarget else {
                self.send(connection, status: "404 Not Found", headers: [:], body: Data(), isHead: isHead)
                return
            }
            self.activity.pageRequested = true
            self.reportActivity()
            self.send(connection, status: "200 OK", headers: ["Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store"], body: Data(ShadowInstallLinks.installPage(itms: target).utf8), isHead: isHead)
        case ShadowInstallLinks.manifestPath:
            self.activity.manifestRequested = true
            self.reportActivity()
            if !self.didReportManifest {
                self.didReportManifest = true
                self.onManifestRequested?()
            }
            self.send(connection, status: "200 OK", headers: ["Content-Type": "text/xml"], body: self.manifestData(), isHead: isHead)
        case "/icon57.png", "/icon512.png":
            self.activity.iconsRequested = true
            self.reportActivity()
            self.send(connection, status: "200 OK", headers: ["Content-Type": "image/png"], body: ShadowInstallServer.iconData(size: path == "/icon57.png" ? 57 : 512), isHead: isHead)
        case ShadowInstallLinks.payloadPath:
            self.activity.payloadRequested = true
            self.reportActivity()
            if !self.didReportPayload {
                self.didReportPayload = true
                self.onPayloadRequested?()
            }
            self.sendPayload(connection, range: headers["range"], isHead: isHead)
        default:
            self.send(connection, status: "404 Not Found", headers: [:], body: Data(), isHead: isHead)
        }
    }

    private func send(_ connection: NWConnection, status: String, headers: [String: String], body: Data, isHead: Bool) {
        var response = "HTTP/1.1 \(status)\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(body.count)"
        allHeaders["Connection"] = "close"
        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"
        var data = Data(response.utf8)
        if !isHead {
            data.append(body)
        }
        connection.send(content: data, isComplete: true, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    // "bytes=a-b", "bytes=a-" or "bytes=-n"; nil = the whole file.
    static func parseRange(_ header: String?, size: Int64) -> ClosedRange<Int64>? {
        guard let header, header.hasPrefix("bytes="), size > 0 else {
            return nil
        }
        let spec = header.dropFirst("bytes=".count).components(separatedBy: ",")[0].trimmingCharacters(in: .whitespaces)
        let parts = spec.components(separatedBy: "-")
        guard parts.count == 2 else {
            return nil
        }
        if parts[0].isEmpty {
            guard let suffix = Int64(parts[1]), suffix > 0 else {
                return nil
            }
            return max(0, size - suffix) ... size - 1
        }
        guard let start = Int64(parts[0]), start < size else {
            return nil
        }
        let end = parts[1].isEmpty ? size - 1 : min(Int64(parts[1]) ?? (size - 1), size - 1)
        guard end >= start else {
            return nil
        }
        return start ... end
    }

    private func sendPayload(_ connection: NWConnection, range rangeHeader: String?, isHead: Bool) {
        let size = self.ipaSize
        guard size > 0, let file = try? FileHandle(forReadingFrom: self.item.ipaURL) else {
            self.send(connection, status: "404 Not Found", headers: [:], body: Data(), isHead: isHead)
            return
        }
        let range = ShadowInstallServer.parseRange(rangeHeader, size: size)
        let span = range ?? (0 ... size - 1)
        var response = range == nil ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 206 Partial Content\r\n"
        response += "Content-Type: application/octet-stream\r\n"
        response += "Accept-Ranges: bytes\r\n"
        response += "Content-Length: \(span.upperBound - span.lowerBound + 1)\r\n"
        if range != nil {
            response += "Content-Range: bytes \(span.lowerBound)-\(span.upperBound)/\(size)\r\n"
        }
        response += "Connection: close\r\n\r\n"
        if isHead {
            file.closeFile()
            connection.send(content: Data(response.utf8), isComplete: true, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
            return
        }
        connection.send(content: Data(response.utf8), completion: .contentProcessed({ _ in }))
        file.seek(toFileOffset: UInt64(span.lowerBound))
        self.sendChunk(connection, file: file, offset: span.lowerBound, end: span.upperBound)
    }

    private func sendChunk(_ connection: NWConnection, file: FileHandle, offset: Int64, end: Int64) {
        let chunkSize: Int64 = 512 * 1024
        let length = min(chunkSize, end - offset + 1)
        let data = file.readData(ofLength: Int(length))
        if data.isEmpty {
            file.closeFile()
            connection.cancel()
            return
        }
        let next = offset + Int64(data.count)
        let isLast = next > end
        connection.send(content: data, isComplete: isLast, completion: .contentProcessed({ [weak self] error in
            guard let self else {
                file.closeFile()
                return
            }
            if error != nil {
                file.closeFile()
                connection.cancel()
                return
            }
            self.payloadSent.insert(integersIn: Int(offset) ..< Int(next))
            let sent = Int64(self.payloadSent.count)
            self.onPayloadProgress?(min(sent, self.ipaSize), self.ipaSize)
            if isLast {
                file.closeFile()
                connection.cancel()
                if sent >= self.ipaSize, !self.didReportFinished {
                    self.didReportFinished = true
                    self.onPayloadFinished?()
                }
            } else {
                self.sendChunk(connection, file: file, offset: next, end: end)
            }
        }))
    }

    // MARK: - Manifest and icons

    private func manifestData() -> Data {
        guard let base = self.baseURL else {
            return Data()
        }
        let manifest: [String: Any] = [
            "items": [[
                "assets": [
                    ["kind": "software-package", "url": base.appendingPathComponent("shadow.ipa").absoluteString],
                    ["kind": "display-image", "url": base.appendingPathComponent("icon57.png").absoluteString],
                    ["kind": "full-size-image", "url": base.appendingPathComponent("icon512.png").absoluteString]
                ],
                "metadata": [
                    "bundle-identifier": self.item.bundleId,
                    "bundle-version": self.item.bundleVersion,
                    "kind": "software",
                    "title": self.item.title
                ]
            ]]
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)) ?? Data()
    }

    // A flat Shadow-blue square; iOS shows it only while the update installs.
    static func iconData(size: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Data()
        }
        context.setFillColor(CGColor(colorSpace: colorSpace, components: [0.17, 0.55, 1.0, 1.0]) ?? CGColor(gray: 0.5, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else {
            return Data()
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}
