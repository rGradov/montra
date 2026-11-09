import Foundation
import Network

/// One bounded HTTP/1.1 JSON request per connection. All socket work stays off the UI actor.
final class LocalHTTPServer {
    static let port: UInt16 = 8766
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.montra.local-api")
    private var sessions: [UUID: HTTPSession] = [:]

    init(port: UInt16 = LocalHTTPServer.port) throws {
        let parameters = NWParameters.tcp
        guard let port = NWEndpoint.Port(rawValue: port) else { throw LedgerError("Invalid API port.") }
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        listener = try NWListener(using: parameters)
    }

    func start(
        token: String,
        state: @escaping (NWListener.State) -> Void,
        handle: @escaping (Data, @escaping (HTTPReply) -> Void) -> Void
    ) {
        listener.stateUpdateHandler = state
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.sessions.count < 16, let port = self.listener.port else {
                connection.cancel()
                return
            }
            let id = UUID()
            let session = HTTPSession(connection: connection, queue: self.queue, port: port.rawValue, token: token)
            self.sessions[id] = session
            session.start(handle: handle) { [weak self] in self?.sessions.removeValue(forKey: id) }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
        queue.async {
            for session in Array(self.sessions.values) { session.close() }
        }
    }
}

struct HTTPReply {
    let status: Int
    let body: Data

    init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    init(status: Int, error: String) {
        self.init(status: status, body: (try? JSONSerialization.data(withJSONObject: ["error": error])) ?? Data())
    }

    var bytes: Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        case 413: reason = "Content Too Large"
        case 415: reason = "Unsupported Media Type"
        case 422: reason = "Unprocessable Content"
        case 503: reason = "Service Unavailable"
        default: reason = "Internal Server Error"
        }
        let challenge = status == 401 ? "WWW-Authenticate: Bearer\r\n" : ""
        let headers = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\(challenge)\r\n"
        return Data(headers.utf8) + body
    }
}

private final class HTTPSession {
    private static let maxHeaders = 8 * 1024
    private static let maxBody = 256 * 1024
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let expectedHost: String
    private let authorization: [UInt8]
    private var buffer = Data()
    private var bodySize: Int?
    private var onClose: (() -> Void)?

    init(connection: NWConnection, queue: DispatchQueue, port: UInt16, token: String) {
        self.connection = connection
        self.queue = queue
        expectedHost = "127.0.0.1:\(port)"
        authorization = Array("Bearer \(token)".utf8)
    }

    func start(handle: @escaping (Data, @escaping (HTTPReply) -> Void) -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in self?.close() }
        receive(handle: handle)
    }

    func close() {
        guard let onClose else { return }
        self.onClose = nil
        connection.cancel()
        onClose()
    }

    private func receive(handle: @escaping (Data, @escaping (HTTPReply) -> Void) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, self.onClose != nil else { return }
            if error != nil { self.close(); return }
            if let data { self.buffer.append(data) }
            if self.bodySize == nil {
                if let separator = self.buffer.range(of: Data("\r\n\r\n".utf8)) {
                    if let failure = self.parseHeaders(self.buffer.prefix(upTo: separator.lowerBound)) {
                        self.send(failure)
                        return
                    }
                    self.buffer.removeSubrange(..<separator.upperBound)
                } else if self.buffer.count > Self.maxHeaders {
                    self.send(HTTPReply(status: 413, error: "Headers exceed 8 KiB."))
                    return
                }
            }
            if let size = self.bodySize, self.buffer.count >= size {
                guard self.buffer.count == size else {
                    self.send(HTTPReply(status: 400, error: "Send one request per connection."))
                    return
                }
                handle(self.buffer) { [weak self] reply in
                    guard let self else { return }
                    self.queue.async { self.send(reply) }
                }
            } else if complete {
                self.send(HTTPReply(status: 400, error: "Incomplete HTTP request."))
            } else {
                self.receive(handle: handle)
            }
        }
    }

    private func parseHeaders(_ data: Data) -> HTTPReply? {
        let invalid = HTTPReply(status: 400, error: "Invalid HTTP/1.1 request.")
        guard data.count <= Self.maxHeaders else { return HTTPReply(status: 413, error: "Headers exceed 8 KiB.") }
        guard let text = String(data: data, encoding: .ascii) else { return invalid }
        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count == 3, requestLine[2] == "HTTP/1.1" else { return invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let fields = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, !fields[0].isEmpty,
                  fields[0].utf8.allSatisfy({ (33...126).contains($0) }),
                  fields[1].utf8.allSatisfy({ $0 == 9 || (32...126).contains($0) }) else { return invalid }
            let name = fields[0].lowercased()
            guard headers[name] == nil else { return invalid }
            headers[name] = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        }

        guard headers["host"] == expectedHost, headers["origin"] == nil else {
            return HTTPReply(status: 403, error: "Use the local 127.0.0.1 endpoint from a native client.")
        }
        let supplied = Array((headers["authorization"] ?? "").utf8)
        guard supplied.count == authorization.count,
              zip(supplied, authorization).reduce(0, { $0 | ($1.0 ^ $1.1) }) == 0 else {
            return HTTPReply(status: 401, error: "A valid Montra Bearer token is required.")
        }
        guard requestLine[0] == "POST", requestLine[1] == "/v1/commands" else {
            return HTTPReply(status: 404, error: "Use POST /v1/commands.")
        }
        guard headers["transfer-encoding"] == nil, headers["expect"] == nil,
              let length = headers["content-length"], !length.isEmpty,
              length.utf8.allSatisfy({ (48...57).contains($0) }), let size = Int(length), size > 0 else { return invalid }
        guard size <= Self.maxBody else { return HTTPReply(status: 413, error: "JSON body exceeds 256 KiB.") }
        let mediaType = headers["content-type"]?.split(separator: ";", maxSplits: 1).first
        guard mediaType?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
            return HTTPReply(status: 415, error: "Send application/json.")
        }
        bodySize = size
        return nil
    }

    private func send(_ reply: HTTPReply) {
        guard onClose != nil else { return }
        connection.send(content: reply.bytes, completion: .contentProcessed { [weak self] _ in self?.close() })
    }
}
