import Foundation
import FlyingFox

/// HTTP server that lets browsers on the same Wi-Fi upload/download files to `directory`.
///
/// Every request must carry `?t=<token>`; the URL from `shareURL()` already includes it.
public final class LANShareServer: Sendable {
    public let directory: URL
    public let port: UInt16
    public let token: String
    private let server: HTTPServer

    /// - Parameter onReceive: called (off the main thread) with the saved file URL after each upload.
    public init(directory: URL, port: UInt16 = 8080, onReceive: @escaping @Sendable (URL) -> Void = { _ in }) {
        let token = String(UUID().uuidString.prefix(8))
        self.directory = directory
        self.port = port
        self.token = token
        // ponytail: one closure + switch instead of FlyingFox routes, 4 endpoints don't need a router
        self.server = HTTPServer(port: port, timeout: 60) { request in
            try await Self.handle(request, directory: directory, token: token, onReceive: onReceive)
        }
    }

    /// Runs until `stop()` is called or the task is cancelled.
    public func run() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await server.run()
    }

    public func stop() async {
        await server.stop()
    }

    /// `http://<wifi-ip>:<port>/?t=<token>`, nil when not on Wi-Fi/hotspot.
    public func shareURL() -> URL? {
        NetworkInfo.localIPv4().flatMap { URL(string: "http://\($0):\(port)/?t=\(token)") }
    }

    // MARK: - Routing

    static func handle(_ request: HTTPRequest, directory: URL, token: String,
                       onReceive: @Sendable (URL) -> Void) async throws -> HTTPResponse {
        guard request.query["t"] == token else {
            return HTTPResponse(statusCode: .unauthorized, body: Data("Invalid or missing token".utf8))
        }
        switch (request.method, request.path) {
        case (.GET, "/"):
            return try indexPage()
        case (.GET, "/api/files"):
            return try listFiles(in: directory)
        case (.PUT, "/api/files"):
            guard let name = safeFileName(request.query["name"]) else { return HTTPResponse(statusCode: .badRequest) }
            let saved = try await receive(request.bodySequence, named: name, in: directory)
            onReceive(saved)
            return HTTPResponse(statusCode: .created)
        case (.GET, "/api/file"):
            guard let name = safeFileName(request.query["name"]) else { return HTTPResponse(statusCode: .badRequest) }
            return try download(directory.appendingPathComponent(name))
        default:
            return HTTPResponse(statusCode: .notFound)
        }
    }

    private static func indexPage() throws -> HTTPResponse {
        let url = Bundle(for: LANShareServer.self).url(forResource: "index", withExtension: "html")!
        return HTTPResponse(statusCode: .ok,
                            headers: [.contentType: "text/html; charset=utf-8"],
                            body: try Data(contentsOf: url))
    }

    private struct FileEntry: Encodable { let name: String; let size: Int }

    private static func listFiles(in directory: URL) throws -> HTTPResponse {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey],
                                                               options: .skipsHiddenFiles)
        let entries = urls.map {
            FileEntry(name: $0.lastPathComponent, size: (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }.sorted { $0.name < $1.name }
        return HTTPResponse(statusCode: .ok,
                            headers: [.contentType: "application/json"],
                            body: try JSONEncoder().encode(entries))
    }

    /// Streams the raw request body straight to disk (no multipart; the page sends `xhr.send(file)`).
    private static func receive(_ body: HTTPBodySequence, named name: String, in directory: URL) async throws -> URL {
        let dest = uniqueURL(for: name, in: directory)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        do {
            for try await chunk in body { try handle.write(contentsOf: chunk) }
            try handle.close()
            return dest
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: dest) // don't leave half-written files behind
            throw error
        }
    }

    private static func download(_ url: URL) throws -> HTTPResponse {
        guard FileManager.default.fileExists(atPath: url.path) else { return HTTPResponse(statusCode: .notFound) }
        let encoded = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "file"
        return HTTPResponse(statusCode: .ok,
                            headers: [.contentType: "application/octet-stream",
                                      .contentDisposition: "attachment; filename*=UTF-8''\(encoded)"],
                            body: try HTTPBodySequence(file: url))
    }

    // MARK: - File names

    /// Strips any path so `../../etc/x` can't escape `directory`.
    static func safeFileName(_ raw: String?) -> String? {
        guard let name = raw.map({ ($0 as NSString).lastPathComponent }),
              !name.isEmpty, name != ".", name != "..", !name.hasPrefix(".") else { return nil }
        return name
    }

    /// `a.pdf` → `a (1).pdf` when taken, so uploads never overwrite.
    static func uniqueURL(for name: String, in directory: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(base) (\(n))"
            candidate = directory.appendingPathComponent(ext.isEmpty ? numbered : "\(numbered).\(ext)")
            n += 1
        }
        return candidate
    }
}
