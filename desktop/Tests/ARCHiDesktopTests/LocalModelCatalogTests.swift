import Foundation
import Testing
@testable import ARCHiDesktop

@Suite(.serialized)
@MainActor
struct LocalModelCatalogTests {
    @Test func registryMapsOnlyExplicitSupportedModelsAndIdentifiesSmallModels() {
        #expect(QwenAssistant.supportedModels == ["qwen3.5:9b", "qwen3:8b", "qwen3:0.6b", "qwen3:1.7b", "qwen3:4b"])
        #expect(LocalModelCatalog.smallModels == ["qwen3:0.6b", "qwen3:1.7b", "qwen3:4b"])
        #expect(LocalModelCatalog.family(for: "qwen3.5:9b") == "qwen35")
        #expect(LocalModelCatalog.family(for: "qwen3:0.6b") == "qwen3")
        #expect(LocalModelCatalog.family(for: "qwen3:latest") == nil)
        #expect(!LocalModelCatalog.isSmallModel("qwen3:8b"))
    }

    @Test func advisoryInventoryUsesRegistryOrderAndRequiresUnambiguousLocalIdentity() throws {
        let small = CatalogFixture.tag("qwen3:0.6b")
        let large = CatalogFixture.tag("qwen3.5:9b")
        var unsupported = CatalogFixture.tag("qwen3:8b").object!
        unsupported["name"] = .string("unlisted:8b")
        unsupported["model"] = .string("unlisted:8b")
        let models = try LocalModelCatalog.installedModels(from: CatalogFixture.inventory([small, .object(unsupported), large]))
        #expect(models.map(\.name) == ["qwen3.5:9b", "qwen3:0.6b"])
        #expect(models.last?.family == "qwen3")
        #expect(models.last?.digest == String(repeating: "a", count: 64))
        #expect(try LocalModelCatalog.installedModels(from: CatalogFixture.inventory([small, small])).isEmpty)
        #expect(try LocalModelCatalog.installedModels(from: CatalogFixture.inventory([])).isEmpty)
    }

    @Test func rejectsRemoteMismatchedMalformedOrExplicitlyIncapableTags() throws {
        for mutation in ["remote_host", "nestedRemote", "model", "family", "format", "digest", "size", "quantization", "capabilities", "cloud"] {
            var tag = CatalogFixture.tag("qwen3:4b").object!
            var details = tag["details"]!.object!
            switch mutation {
            case "remote_host": tag["remote_host"] = .string("https://example.invalid")
            case "nestedRemote": details["remote_model"] = .string("cloud")
            case "model": tag["model"] = .string("qwen3:latest")
            case "family": details["family"] = .string("llama")
            case "format": details["format"] = .string("remote")
            case "digest": tag["digest"] = .string("unverified")
            case "size": details["parameter_size"] = .string(String(repeating: "x", count: 81))
            case "quantization": details["quantization_level"] = .string("")
            case "capabilities": tag["capabilities"] = .array([.string("embedding")])
            default: tag["capabilities"] = .array([.string("completion"), .string("cloud")])
            }
            tag["details"] = .object(details)
            #expect(try LocalModelCatalog.installedModels(from: CatalogFixture.inventory([.object(tag)])).isEmpty)
        }
        var capable = CatalogFixture.tag("qwen3:1.7b").object!
        capable["capabilities"] = .array([.string("completion")])
        #expect(try LocalModelCatalog.installedModels(from: CatalogFixture.inventory([.object(capable)])).count == 1)
    }

    @Test func inventoryRejectsMalformedOrOversizedEnvelopes() throws {
        for data in [Data("not JSON".utf8), Data("{}".utf8), Data(#"{"models":{}}"#.utf8),
                     Data(repeating: 32, count: LocalModelCatalog.maximumResponseBytes + 1),
                     try CatalogFixture.inventory(Array(repeating: CatalogFixture.tag("qwen3:4b"), count: 513))] {
            #expect(throws: QwenFailure.invalidResponse) { try LocalModelCatalog.installedModels(from: data) }
        }
    }

    @Test func discoveryOnlyReadsLoopbackTagsAndDoesNotConnectOrSendCredentials() async throws {
        let configuration = makeConfiguration(.normal)
        configuration.httpAdditionalHeaders = ["Authorization": "fixture-secret", "Cookie": "fixture-cookie"]
        let models = try await QwenAssistant.discoverInstalledModels(configuration: configuration)
        #expect(models.map(\.name) == ["qwen3.5:9b", "qwen3:0.6b"])
        let requests = CatalogFixtureProtocol.state.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/tags")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.timeoutInterval == 3)
    }

    @Test func emptyInventoryIsValidButTransportAndBoundsFailuresThrow() async throws {
        #expect(try await QwenAssistant.discoverInstalledModels(configuration: makeConfiguration(.empty)).isEmpty)
        for (mode, failure) in [(CatalogFixtureMode.unavailable, QwenFailure.unavailable),
                                (.timedOut, .timedOut), (.redirect, .nonLocalModel), (.oversized, .invalidResponse)] {
            await #expect(throws: failure) {
                try await QwenAssistant.discoverInstalledModels(configuration: makeConfiguration(mode))
            }
            #expect(CatalogFixtureProtocol.state.requests.count == 1)
            #expect(CatalogFixtureProtocol.state.requests.allSatisfy { $0.url?.path == "/api/tags" })
        }
    }

    @Test func smallModelConnectionStillVerifiesShowCompletionBeforeUse() async throws {
        for model in LocalModelCatalog.smallModels {
            let client = QwenAssistant(model: model, configuration: makeConfiguration(.allSmallModels))
            defer { client.disconnect() }
            try await client.connect()
            #expect(client.metadata?.name == model)
            #expect(client.metadata?.family == "qwen3")
            #expect(CatalogFixtureProtocol.state.requests.map { $0.url?.path } == ["/api/tags", "/api/show"])
        }
        let client = QwenAssistant(model: "qwen3:0.6b", configuration: makeConfiguration(.noCompletion))
        defer { client.disconnect() }
        await #expect(throws: QwenFailure.nonLocalModel) { try await client.connect() }
        #expect(client.metadata == nil)
        #expect(!CatalogFixtureProtocol.state.requests.contains { $0.url?.path == "/api/chat" })
    }

    private func makeConfiguration(_ mode: CatalogFixtureMode) -> URLSessionConfiguration {
        CatalogFixtureProtocol.state.reset(mode)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogFixtureProtocol.self]
        return configuration
    }
}

private enum CatalogFixture {
    static func tag(_ model: String) -> JSONValue {
        .object(["name": .string(model), "model": .string(model),
                 "digest": .string(String(repeating: "a", count: 64)),
                 "details": .object(["family": .string(LocalModelCatalog.family(for: model)!),
                    "format": .string("gguf"), "parameter_size": .string("fixture"),
                    "quantization_level": .string("Q4_K_M")])])
    }
    static func inventory(_ tags: [JSONValue]) throws -> Data {
        try JSONEncoder().encode(JSONValue.object(["models": .array(tags)]))
    }
}

private enum CatalogFixtureMode: Sendable {
    case normal, empty, unavailable, timedOut, redirect, oversized, allSmallModels, noCompletion
}

private final class CatalogFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []
    private var mode: CatalogFixtureMode = .normal
    var requests: [URLRequest] { lock.withLock { stored } }
    func reset(_ mode: CatalogFixtureMode) { lock.withLock { stored = []; self.mode = mode } }
    func record(_ request: URLRequest) -> CatalogFixtureMode {
        lock.withLock { stored.append(request); return mode }
    }
}

private final class CatalogFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = CatalogFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let mode = Self.state.record(request)
        if mode == .unavailable || mode == .timedOut {
            client?.urlProtocol(self, didFailWithError: URLError(mode == .timedOut ? .timedOut : .cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: mode == .redirect ? 307 : 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Location": "https://example.invalid"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data: Data
        if mode == .oversized {
            data = Data(repeating: 32, count: LocalModelCatalog.maximumResponseBytes + 1)
        } else if request.url?.path == "/api/show" {
            // All connection fixtures request a small Qwen3 model.
            let details = CatalogFixture.tag("qwen3:0.6b")["details"]!
            data = try! JSONEncoder().encode(JSONValue.object(["details": details,
                "model_info": .object(["general.architecture": .string("qwen3")]),
                "capabilities": .array(mode == .noCompletion ? [.string("embedding")] : [.string("completion")])]))
        } else {
            let names = mode == .allSmallModels ? LocalModelCatalog.smallModels : ["qwen3:0.6b", "qwen3.5:9b"]
            data = try! CatalogFixture.inventory(mode == .empty ? [] : names.map(CatalogFixture.tag))
        }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
