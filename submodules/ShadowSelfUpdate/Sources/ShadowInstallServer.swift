import Foundation
import Network
import Security
import ImageIO
import CoreGraphics

// Shadow: a tiny HTTPS server on 127.0.0.1 for itms-services. It serves the
// install manifest, the signed IPA (with Range support) and two icons, and
// reports how much of the IPA the system installer has read. Like Feather's
// ServerInstaller, but on Network.framework instead of Vapor.
final class ShadowInstallServer {
    struct Item {
        let ipaURL: URL
        let bundleId: String
        let bundleVersion: String
        let title: String
    }

    private let item: Item
    private let queue = DispatchQueue(label: "ShadowInstallServer")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let ipaSize: Int64
    // Highest byte offset of the IPA handed to the installer.
    private var payloadSent: Int64 = 0
    private var didReportManifest = false
    private var didReportFinished = false

    var onManifestRequested: (() -> Void)?
    var onPayloadProgress: ((Int64, Int64) -> Void)?
    var onPayloadFinished: (() -> Void)?

    private(set) var manifestURL: URL?

    init(item: Item) {
        self.item = item
        self.ipaSize = ((try? FileManager.default.attributesOfItem(atPath: item.ipaURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    deinit {
        self.listener?.cancel()
    }

    // completion runs on the server queue with the manifest URL.
    func start(material: ShadowLocalTLSIdentity.Material, completion: @escaping (Result<URL, Error>) -> Void) {
        let tls = NWProtocolTLS.Options()
        guard let identity = sec_identity_create_with_certificates(material.identity, material.chain as CFArray) else {
            completion(.failure(ServerError.identity))
            return
        }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

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
        self.listener = listener
        var completed = false
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, !completed else {
                return
            }
            switch state {
            case .ready:
                completed = true
                guard let port = listener.port?.rawValue else {
                    completion(.failure(ServerError.port))
                    return
                }
                var components = URLComponents()
                components.scheme = "https"
                components.host = ShadowLocalTLSIdentity.host
                components.port = Int(port)
                components.path = "/manifest.plist"
                guard let url = components.url else {
                    completion(.failure(ServerError.port))
                    return
                }
                self.manifestURL = url
                completion(.success(url))
            case let .failed(error):
                completed = true
                completion(.failure(error))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: self.queue)
    }

    func stop() {
        self.queue.async {
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
        }
    }

    static func installURL(manifest: URL) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = manifest.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "itms-services://?action=download-manifest&url=" + encoded)
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

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        self.connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: self.queue)
        self.readRequest(connection, buffer: Data())
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
        case "/manifest.plist":
            if !self.didReportManifest {
                self.didReportManifest = true
                self.onManifestRequested?()
            }
            self.send(connection, status: "200 OK", headers: ["Content-Type": "text/xml"], body: self.manifestData(), isHead: isHead)
        case "/icon57.png":
            self.send(connection, status: "200 OK", headers: ["Content-Type": "image/png"], body: ShadowInstallServer.iconData(size: 57), isHead: isHead)
        case "/icon512.png":
            self.send(connection, status: "200 OK", headers: ["Content-Type": "image/png"], body: ShadowInstallServer.iconData(size: 512), isHead: isHead)
        case "/shadow.ipa":
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
            if next > self.payloadSent {
                self.payloadSent = next
                self.onPayloadProgress?(min(next, self.ipaSize), self.ipaSize)
            }
            if isLast {
                file.closeFile()
                connection.cancel()
                if next >= self.ipaSize, !self.didReportFinished {
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
        guard let manifestURL = self.manifestURL else {
            return Data()
        }
        let base = manifestURL.deletingLastPathComponent()
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
