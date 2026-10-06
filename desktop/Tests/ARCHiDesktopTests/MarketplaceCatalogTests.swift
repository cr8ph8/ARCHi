import Foundation
import XCTest
@testable import ARCHiDesktop

final class MarketplaceCatalogTests: XCTestCase {
    func testOnlyExplicitLoopbackEndpointIsAccepted() throws {
        for endpoint in ["https://example.com", "http://127.0.0.1:47831/path", "http://user:secret@127.0.0.1:47831",
                         "http://127.0.0.1:47831?token=x", "http://127.0.0.1:47831#fragment", "file:///tmp/catalog", "http://localhost:47831", "http://[::1]:47831"] {
            XCTAssertThrowsError(try MarketplaceCatalogClient(endpoint: endpoint))
        }
        XCTAssertNoThrow(try MarketplaceCatalogClient(endpoint: "http://127.0.0.1:47839"))
        XCTAssertEqual(try MarketplaceCatalogClient(endpoint: "http://127.0.0.1").endpoint.port, 47831)
    }

    @MainActor
    func testConstructionAndDraftingHaveNoIO() async throws {
        let transport = MarketplaceScriptTransport([])
        let store = MarketplaceCatalogStore(transport: transport)
        store.draft.title = "A local draft"
        store.makeVariation(CompanionItemCatalog.designs[0])
        XCTAssertFalse(store.connected)
        XCTAssertNil(store.account)
        XCTAssertNil(store.editingListing)
        XCTAssertFalse(store.provenance.rightsConfirmed)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testUnknownMutationSurvivesUnrelatedReadErrorAndReusesExactRequest() async throws {
        let listing = fixtureListing()
        let transport = MarketplaceScriptTransport([
            .json(health), .json(page([MarketplaceListing]())), .json(session),
            .json(page([MarketplaceInventoryEntry]())), .json(page([MarketplaceListing]())),
            .interrupted, .json("{\"error\":{\"code\":\"not_found\"}}", status: 404),
            .json(try encoded(["listing": listing]), status: 201),
            .json(page([MarketplaceListing]())), .json(page([listing])), .json(page([MarketplaceInventoryEntry]()))
        ])
        let store = MarketplaceCatalogStore(transport: transport)
        await store.connect()
        await store.signIn(handle: "fixture_creator", password: "synthetic-password")
        store.draft = listing.recipe; store.provenance = listing.provenance
        await store.saveDraft()
        XCTAssertTrue(store.hasPendingMutation)
        XCTAssertNil(store.editingListing)
        await store.refreshCatalog()
        XCTAssertTrue(store.hasPendingMutation, "An unrelated failing read must not erase mutation recovery.")
        await store.retryPending()
        XCTAssertFalse(store.hasPendingMutation)
        XCTAssertEqual(store.editingListing, listing)
        let requests = await transport.requests
        XCTAssertEqual(requests[5].httpBody, requests[7].httpBody)
        XCTAssertEqual(requests[5].url, requests[7].url)
        XCTAssertEqual(requests[5].value(forHTTPHeaderField: "Idempotency-Key"), requests[7].value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertNotNil(requests[5].value(forHTTPHeaderField: "Idempotency-Key"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[5].httpBody)) as? [String: Any])
        XCTAssertNil(body["expectedVersion"], "A new draft uses the API's exact create body, without null expectedVersion.")
    }

    @MainActor
    func testServerFailureRetainsMutationButExactConflictClosesIt() async throws {
        let listing = fixtureListing()
        let transport = MarketplaceScriptTransport([
            .json(health), .json(page([MarketplaceListing]())), .json(session),
            .json(page([MarketplaceInventoryEntry]())), .json(page([MarketplaceListing]())),
            .json("{\"error\":{\"code\":\"storage_unavailable\"}}", status: 503),
            .json("{\"error\":{\"code\":\"version_conflict\"}}", status: 409)
        ])
        let store = MarketplaceCatalogStore(transport: transport)
        await store.connect(); await store.signIn(handle: "fixture_creator", password: "synthetic-password")
        store.draft = listing.recipe; store.provenance = listing.provenance
        await store.saveDraft()
        XCTAssertTrue(store.hasPendingMutation)
        await store.retryPending()
        XCTAssertFalse(store.hasPendingMutation)
        XCTAssertNil(store.editingListing)
        XCTAssertTrue(store.errorMessage?.contains("changed") == true)
    }

    @MainActor
    func testExpiredSessionDropsPrivateViewsButPreservesLocalDraft() async throws {
        let transport = MarketplaceScriptTransport([
            .json(health), .json(page([MarketplaceListing]())), .json(session),
            .json(page([MarketplaceInventoryEntry]())), .json(page([MarketplaceListing]())),
            .json("{\"error\":{\"code\":\"unauthorized\"}}", status: 401)
        ])
        let store = MarketplaceCatalogStore(transport: transport)
        await store.connect(); await store.signIn(handle: "fixture_creator", password: "synthetic-password")
        store.draft.title = "Retained work"
        store.provenance.rightsConfirmed = true
        await store.refreshInventory()
        XCTAssertNil(store.account)
        XCTAssertTrue(store.inventory.isEmpty)
        XCTAssertEqual(store.draft.title, "Retained work")
        XCTAssertFalse(store.provenance.rightsConfirmed, "A new sign-in must make its own distribution declaration.")
        XCTAssertTrue(store.errorMessage?.contains("Sign in") == true)
    }

    @MainActor
    func testUntrustedCatalogCannotMisstateRecipeFingerprint() async throws {
        var listing = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded(fixtureListing(status: .published, version: 2))) as? [String: Any])
        listing["recipeID"] = String(repeating: "0", count: 64)
        let invalid = try JSONSerialization.data(withJSONObject: ["items": [listing], "total": 1, "offset": 0, "limit": 40])
        let transport = MarketplaceScriptTransport([.json(health), .data(invalid)])
        let store = MarketplaceCatalogStore(transport: transport)
        await store.connect()
        XCTAssertTrue(store.catalog.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    func testRawDownloadRequiresStrictRecipeAndMatchingHeader() async throws {
        let listing = fixtureListing()
        let valid = try listing.recipe.encoded()
        let malformed = Data((String(decoding: valid, as: UTF8.self).dropLast() + ",\"title\":\"Repeated\"}").utf8)
        let transport = MarketplaceScriptTransport([
            .data(valid, headers: ["X-ARCHi-Recipe-ID": "wrong"]),
            .data(malformed, headers: ["X-ARCHi-Recipe-ID": listing.recipeID]),
            .data(valid, headers: ["X-ARCHi-Recipe-ID": listing.recipeID])
        ])
        let client = try MarketplaceCatalogClient(transport: transport)
        do { _ = try await client.download(listingID: listing.id, version: 1, recipeID: listing.recipeID, token: nil); XCTFail("Wrong header admitted") } catch {}
        do { _ = try await client.download(listingID: listing.id, version: 1, recipeID: listing.recipeID, token: nil); XCTFail("Duplicate key admitted") } catch {}
        let downloaded = try await client.download(listingID: listing.id, version: 1, recipeID: listing.recipeID, token: nil)
        XCTAssertEqual(downloaded, listing.recipe)
    }

    func testDuplicateResponseKeysAreRejectedBeforeDecoding() async throws {
        let transport = MarketplaceScriptTransport([.json("{\"account\":{},\"account\":{}}")])
        let client = try MarketplaceCatalogClient(transport: transport)
        do { _ = try await client.value(MarketplaceAccountResponse.self, request: client.request(path: "me")); XCTFail("Duplicate envelope key admitted") } catch {}
    }

    func testAcquiredTimestampUsesTheViewersLocalCalendarDate() throws {
        let listing = fixtureListing()
        let entry = MarketplaceInventoryEntry(id: UUID().uuidString, listingID: listing.id, version: 2,
            recipeID: listing.recipeID, recipe: listing.recipe, publisher: listing.publisher,
            provenance: listing.provenance, acquiredAt: "2026-09-17T01:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let components = calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(entry.acquiredDate))
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 16, "An acquisition shortly after UTC midnight belongs to the previous local day here.")
    }

    private var health: String { "{\"service\":\"archi-marketplace\",\"apiVersion\":1,\"mode\":\"development\",\"commerce\":false,\"recipeSchema\":\"archi-item-design/v1\",\"maximumRecipeBytes\":4096}" }
    private var session: String {
        "{\"account\":\(String(decoding: try! encoded(fixtureAccount()), as: UTF8.self)),\"token\":\"synthetic-token\",\"expiresAt\":\"2026-09-17T12:00:00Z\"}"
    }
    private func fixtureAccount() -> MarketplaceAccount {
        .init(id: "550e8400-e29b-41d4-a716-446655440000", handle: "fixture_creator", displayName: "Fixture Creator", createdAt: "2026-09-16T12:00:00Z")
    }
    private func fixtureListing(status: MarketplaceListing.Status = .draft, version: Int = 1) -> MarketplaceListing {
        let recipe = CompanionItemPackage.creatorDefault
        return .init(id: "550e8400-e29b-41d4-a716-446655440001", version: version, status: status,
            publishedVersion: status == .published ? version : nil, publisher: fixtureAccount(), recipeID: recipe.id,
            recipe: recipe, provenance: .init(attribution: "Synthetic fixture design", rightsConfirmed: true),
            createdAt: "2026-09-16T12:00:00Z", updatedAt: "2026-09-16T12:00:00Z")
    }
    private func encoded<Value: Encodable>(_ value: Value) throws -> Data { try JSONEncoder().encode(value) }
    private func page<Value: Encodable>(_ items: [Value]) -> String {
        return String(decoding: try! encoded(MarketplaceTestPage(items: items, total: items.count, limit: 40, offset: 0)), as: UTF8.self)
    }
}

actor MarketplaceScriptTransport: MarketplaceHTTPTransport {
    enum Response: Sendable {
        case bytes(Data, Int, [String: String]), interrupted
        static func json(_ value: String, status: Int = 200) -> Self { .bytes(Data(value.utf8), status, [:]) }
        static func json(_ value: Data, status: Int = 200) -> Self { .bytes(value, status, [:]) }
        static func data(_ value: Data, headers: [String: String] = [:]) -> Self { .bytes(value, 200, headers) }
    }
    private var responses: [Response]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [Response]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.resourceUnavailable) }
        switch responses.removeFirst() {
        case .interrupted: throw URLError(.networkConnectionLost)
        case .bytes(let data, let status, let headers):
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: headers.merging(["Content-Type": "application/json"]) { a, _ in a })!)
        }
    }
}

private struct MarketplaceTestPage<T: Encodable>: Encodable { let items: [T]; let total: Int; let limit: Int; let offset: Int }
