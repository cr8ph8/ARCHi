import Foundation

protocol MarketplaceHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Ephemeral transport: no cookies, cache, credential store, redirects or profile
/// access. A bounded stream avoids admitting an unbounded catalog response.
struct MarketplaceURLTransport: MarketplaceHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: MarketplaceNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MarketplaceServiceError(code: "invalid_response", status: nil)
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < MarketplaceCatalogClient.maximumResponseBytes else {
                throw MarketplaceServiceError(code: "response_too_large", status: nil)
            }
            data.append(byte)
        }
        return (data, response)
    }
}

private final class MarketplaceNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct MarketplaceCatalogClient: Sendable {
    static let defaultEndpoint = "http://127.0.0.1:47831"
    static let maximumResponseBytes = 2_000_000
    let endpoint: URL
    private let transport: any MarketplaceHTTPTransport

    init(endpoint: String = Self.defaultEndpoint, transport: any MarketplaceHTTPTransport = MarketplaceURLTransport()) throws {
        guard var parts = URLComponents(string: endpoint), parts.scheme == "http",
              parts.host == "127.0.0.1",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port!) else {
            throw MarketplaceServiceError(code: "endpoint", status: nil)
        }
        parts.port = parts.port ?? 47831
        guard let url = parts.url else { throw MarketplaceServiceError(code: "endpoint", status: nil) }
        self.endpoint = url
        self.transport = transport
    }

    /// A retained mutation is a literal request, so uncertain retries cannot
    /// accidentally change the body, expected version, account or idempotency key.
    func request(path: String, method: String = "GET", token: String? = nil,
                 body: Data? = nil, key: String? = nil, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: endpoint.appendingPathComponent("v1").appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        return request
    }

    func value<Value: Decodable & Sendable>(_ type: Value.Type, request: URLRequest) async throws -> Value {
        let (data, _) = try await response(request)
        do {
            var keys = UniqueJSONKeys(bytes: Array(data))
            try keys.validate()
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MarketplaceServiceError(code: "invalid_response", status: nil)
        }
    }

    func download(listingID: String, version: Int, recipeID: String, token: String?) async throws -> CompanionItemPackage {
        guard UUID(uuidString: listingID) != nil, version > 0 else { throw MarketplaceServiceError(code: "invalid_request", status: nil) }
        let (data, response) = try await response(request(path: "listings/\(listingID)/versions/\(version)/package", token: token))
        let recipe = try CompanionItemPackage.decode(data)
        guard recipe.id == recipeID, response.value(forHTTPHeaderField: "X-ARCHi-Recipe-ID") == recipeID else {
            throw MarketplaceServiceError(code: "digest_mismatch", status: nil)
        }
        return recipe
    }

    private func response(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await transport.send(request)
        guard data.count <= Self.maximumResponseBytes else { throw MarketplaceServiceError(code: "response_too_large", status: nil) }
        guard (200...299).contains(response.statusCode) else {
            struct ErrorEnvelope: Decodable { struct Detail: Decodable { let code: String }; let error: Detail }
            let code = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.code) ?? "http_error"
            throw MarketplaceServiceError(code: response.statusCode == 401 ? "unauthorized" : code, status: response.statusCode)
        }
        guard response.mimeType?.lowercased() == "application/json", response.url == request.url else {
            throw MarketplaceServiceError(code: "invalid_response", status: nil)
        }
        return (data, response)
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
