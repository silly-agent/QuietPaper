import Foundation

struct HTTPResponseSnapshot: Sendable {
    let url: URL?
    let statusCode: Int
    let headers: [HTTPResponseHeader]
    let body: String
    let duration: TimeInterval
    let size: Int

    static func displayText(for data: Data) -> String {
        guard !data.isEmpty else { return "" }
        let source = String(decoding: data, as: UTF8.self)
        return JSONPrettyPrinter.format(source) ?? source
    }

    func saved(at date: Date = Date()) -> HTTPSavedResponse {
        HTTPSavedResponse(
            url: url,
            statusCode: statusCode,
            headers: headers,
            body: body,
            duration: duration,
            size: size,
            savedAt: date
        )
    }
}

extension HTTPSavedResponse {
    var snapshot: HTTPResponseSnapshot {
        HTTPResponseSnapshot(
            url: url,
            statusCode: statusCode,
            headers: headers,
            body: JSONPrettyPrinter.format(body) ?? body,
            duration: duration,
            size: size
        )
    }
}

struct HTTPRequestClient: Sendable {
    typealias Download = @Sendable (URLRequest) async throws -> (URL, URLResponse)

    static let defaultMaximumResponseBytes = 50 * 1_024 * 1_024

    private let maximumResponseBytes: Int
    private let download: Download

    init(
        session: URLSession = .shared,
        maximumResponseBytes: Int = HTTPRequestClient.defaultMaximumResponseBytes
    ) {
        self.maximumResponseBytes = maximumResponseBytes
        self.download = { request in
            try await session.download(for: request)
        }
    }

    init(maximumResponseBytes: Int, download: @escaping Download) {
        self.maximumResponseBytes = maximumResponseBytes
        self.download = download
    }

    func send(_ request: URLRequest) async throws -> HTTPResponseSnapshot {
        let startedAt = Date()
        let (temporaryURL, response) = try await download(request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let response = response as? HTTPURLResponse else { throw HTTPRequestError.nonHTTPResponse }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let declaredSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard declaredSize <= maximumResponseBytes else {
            throw HTTPRequestError.responseTooLarge(maximumBytes: maximumResponseBytes)
        }
        let data = try Data(contentsOf: temporaryURL, options: [.mappedIfSafe])
        guard data.count <= maximumResponseBytes else {
            throw HTTPRequestError.responseTooLarge(maximumBytes: maximumResponseBytes)
        }
        let headers = response.allHeaderFields
            .map { HTTPResponseHeader(name: String(describing: $0.key), value: String(describing: $0.value)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return HTTPResponseSnapshot(
            url: response.url,
            statusCode: response.statusCode,
            headers: headers,
            body: HTTPResponseSnapshot.displayText(for: data),
            duration: Date().timeIntervalSince(startedAt),
            size: data.count
        )
    }
}
