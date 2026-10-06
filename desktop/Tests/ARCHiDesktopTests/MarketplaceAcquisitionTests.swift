import Foundation
import XCTest
@testable import ARCHiDesktop

/// Disposable profiles and scripted transport only. These checks establish
/// retained attribution, never the legal validity of a publisher's declaration.
@MainActor
final class MarketplaceAcquisitionTests: XCTestCase {
    private var recipe: CompanionItemPackage { CompanionItemCatalog.designs[0] }
    private var account: MarketplaceAccount {
        .init(id: "550e8400-e29b-41d4-a716-446655440002", handle: "fixture_reader",
              displayName: "Reader", createdAt: "2026-09-16T12:00:00Z")
    }
    private var entry: MarketplaceInventoryEntry {
        .init(id: "550e8400-e29b-41d4-a716-446655440003", listingID: "550e8400-e29b-41d4-a716-446655440001",
              version: 2, recipeID: recipe.id, recipe: recipe,
              publisher: .init(id: "550e8400-e29b-41d4-a716-446655440000", handle: "fixture_publisher",
                               displayName: "Publisher", createdAt: "2026-09-16T12:00:00Z"),
              provenance: .init(attribution: "Synthetic publisher declaration", rightsConfirmed: true),
              acquiredAt: "2026-10-02T12:00:00.000Z")
    }
    private var acquisition: MarketplaceItemAcquisition {
        .init(entry: entry, endpoint: URL(string: MarketplaceCatalogClient.defaultEndpoint)!, account: account)
    }

    func testAcquisitionRestartsExactRetryDoesNotWriteAndConflictsPreserveRecord() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = makeStore(fixture.preferences)
        XCTAssertTrue(store.collectMarketItem(recipe, acquisition: acquisition), store.marketplaceMessage)
        let saved = try Data(contentsOf: fixture.preferences)
        let reopened = makeStore(fixture.preferences)
        XCTAssertEqual(reopened.marketItemAcquisition(for: recipe), acquisition)
        XCTAssertTrue(reopened.collectMarketItem(recipe, acquisition: acquisition))
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), saved, "A repeated review is not another acquisition.")
        let differentCatalog = MarketplaceItemAcquisition(entry: entry,
            endpoint: URL(string: "http://127.0.0.1:47839")!, account: account)
        XCTAssertFalse(reopened.collectMarketItem(recipe, acquisition: differentCatalog))
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), saved)
        XCTAssertEqual(reopened.marketItemAcquisition(for: recipe), acquisition)
        XCTAssertTrue(reopened.preferences.equipment.isEmpty, "An acquisition does not equip a design.")
    }

    func testManualRecipeCanGainOneExplicitRecordAndRemovalAndLessonExportExcludeIt() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = makeStore(fixture.preferences)
        XCTAssertTrue(store.collectMarketItem(recipe))
        XCTAssertNil(store.marketItemAcquisition(for: recipe), "Manual imports must not invent acquisition history.")
        XCTAssertTrue(store.collectMarketItem(recipe, acquisition: acquisition))
        let saved = try NativePreferencePersistence.read(fixture.preferences).document
        XCTAssertEqual(saved.revision, 2)
        XCTAssertEqual(saved.itemLibrary, [recipe])
        XCTAssertEqual(saved.itemAcquisitions, [acquisition])
        let lessonExport = try NativePreferenceDocument.decode(store.lessonExportData())
        XCTAssertNil(lessonExport.itemAcquisitions)
        XCTAssertTrue(lessonExport.itemLibrary.isEmpty)
        XCTAssertTrue(store.removeMarketItem(recipe))
        XCTAssertNil(store.marketItemAcquisition(for: recipe))
        XCTAssertNil(try NativePreferencePersistence.read(fixture.preferences).document.itemAcquisitions)
    }

    func testMismatchedRecipeAndExternallyChangedProfileCannotAcquire() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = makeStore(fixture.preferences)
        var changed = recipe; changed.revision += 1
        XCTAssertFalse(store.collectMarketItem(changed, acquisition: acquisition))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.preferences.path))
        XCTAssertTrue(store.collectMarketItem(recipe, acquisition: acquisition))
        var outside = try NativePreferencePersistence.read(fixture.preferences).document
        outside.itemAcquisitions = nil
        outside.revision += 1
        let bytes = try outside.encoded(); try bytes.write(to: fixture.preferences)
        XCTAssertFalse(store.collectMarketItem(recipe, acquisition: acquisition), "An exact in-memory retry cannot claim a withdrawn disk record remains saved.")
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), bytes)
    }

    func testV9MigrationPreservesLessonSourceBindingsWithoutInventingAcquisitions() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let binding = ReadingSourceBinding(id: UUID().uuidString, revision: 1, digest: String(repeating: "a", count: 64),
            provenance: ReadingSourceProvenance(origin: .human, acquisition: .userCopy,
                attribution: "Synthetic declared source", declaredAt: Date(timeIntervalSince1970: 1_789_000_000)).receipt)
        let lesson = KeptLesson(topic: "Planning", text: "A synthetic saved lesson.",
            origin: .init(requestID: UUID().uuidString, inputDigest: String(repeating: "b", count: 64), readingSources: [binding]),
            createdAt: Date(timeIntervalSince1970: 1_789_000_000), taskScope: .documentQuestion)
        let source = NativePreferenceDocument(revision: 9, lessons: [lesson], itemLibrary: [recipe])
        var object = try dictionary(source.encoded()); object["schema"] = "archi-native-preferences/v9"
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try bytes.write(to: fixture.preferences)
        let loaded = try NativePreferencePersistence.read(fixture.preferences)
        XCTAssertEqual(loaded.document.schema, NativePreferenceDocument.currentSchema)
        XCTAssertEqual(loaded.document.lessons, [lesson])
        XCTAssertNil(loaded.document.itemAcquisitions)
        XCTAssertEqual(loaded.baseline, bytes)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), bytes, "Opening migrates only in memory.")
        _ = try NativePreferencePersistence.write(document: loaded.document, to: fixture.preferences, expected: bytes)
        XCTAssertEqual(try NativePreferencePersistence.read(fixture.preferences).document.lessons, [lesson],
                       "Declared source provenance must survive a v10 save and reload.")
    }

    func testAcquisitionEnvelopeRejectsOrphansDuplicatesUnknownFieldsAndInvalidDates() throws {
        var document = NativePreferenceDocument(itemLibrary: [recipe], itemAcquisitions: [acquisition])
        XCTAssertEqual(try NativePreferenceDocument.decode(document.encoded()), document)
        document.itemLibrary = []
        XCTAssertThrowsError(try document.encoded())
        document.itemLibrary = [recipe]; document.itemAcquisitions = [acquisition, acquisition]
        XCTAssertThrowsError(try document.encoded())
        document.itemAcquisitions = [acquisition]
        for (key, value) in [("acquiredAt", "not-a-date"), ("catalogEndpoint", "http://user:secret@127.0.0.1:47831"),
                             ("recipeID", String(repeating: "f", count: 64)), ("secretToken", "must-not-persist")] {
            var object = try dictionary(document.encoded())
            var records = try XCTUnwrap(object["itemAcquisitions"] as? [[String: Any]])
            records[0][key] = value; object["itemAcquisitions"] = records
            XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)), key)
        }
        var object = try dictionary(document.encoded()); object["itemAcquisitions"] = NSNull()
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
        object["itemAcquisitions"] = []
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testAcquisitionIdentityCannotBeReboundToAnotherRecipe() throws {
        var second = recipe; second.revision += 1
        let duplicateIdentity = MarketplaceInventoryEntry(id: entry.id.uppercased(), listingID: UUID().uuidString,
            version: 3, recipeID: second.id, recipe: second, publisher: entry.publisher,
            provenance: entry.provenance, acquiredAt: entry.acquiredAt)
        let conflicting = MarketplaceItemAcquisition(entry: duplicateIdentity,
            endpoint: URL(string: MarketplaceCatalogClient.defaultEndpoint + "/")!, account: account)
        let document = NativePreferenceDocument(itemLibrary: [recipe, second], itemAcquisitions: [acquisition, conflicting])
        XCTAssertThrowsError(try document.encoded(), "One inventory identity cannot claim two different acquisitions.")
        let fixture = try Fixture(); defer { fixture.remove() }
        let store = makeStore(fixture.preferences)
        XCTAssertTrue(store.collectMarketItem(recipe, acquisition: acquisition))
        let before = try Data(contentsOf: fixture.preferences)
        XCTAssertFalse(store.collectMarketItem(second, acquisition: conflicting))
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), before)
    }

    func testDownloadBindsInventoryAndSessionThenExpiresOnSignOut() async throws {
        let transport = MarketplaceScriptTransport(try bootstrap + [
            .data(recipe.encoded(), headers: ["X-ARCHi-Recipe-ID": recipe.id]), .json("{\"signedOut\":true}")])
        let store = MarketplaceCatalogStore(transport: transport)
        await store.connect(); await store.signIn(handle: account.handle, password: "synthetic-password")
        await store.download(entry)
        let download = try XCTUnwrap(store.downloadedItem, store.errorMessage ?? "Missing download")
        XCTAssertEqual(download.recipe, recipe)
        XCTAssertEqual(download.acquisition, acquisition)
        XCTAssertTrue(store.isCurrent(download))
        let fixture = try Fixture(); defer { fixture.remove() }
        let client = MarketplaceAcquisitionNoCalls()
        let native = CompanionStore(preferenceURL: fixture.preferences, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false, marketplaceCatalog: store)
        XCTAssertTrue(native.collectMarketDownload(download), native.marketplaceMessage)
        let saved = try Data(contentsOf: fixture.preferences)
        await store.signOut()
        XCTAssertNil(store.downloadedItem)
        XCTAssertFalse(store.isCurrent(download), "A retained review cannot inherit a later account session.")
        XCTAssertFalse(native.collectMarketDownload(download))
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), saved)
        XCTAssertEqual(makeStore(fixture.preferences).marketItemAcquisition(for: recipe), acquisition)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(download.acquisition), as: UTF8.self).contains("synthetic-token"))
    }

    func testUnlistedInventoryAndMismatchedDownloadNeverStageProvenance() async throws {
        let transport = MarketplaceScriptTransport(try bootstrap + [
            .data(recipe.encoded(), headers: ["X-ARCHi-Recipe-ID": "mismatch"])])
        let store = MarketplaceCatalogStore(transport: transport)
        await store.connect(); await store.signIn(handle: account.handle, password: "synthetic-password")
        let unlisted = MarketplaceInventoryEntry(id: UUID().uuidString, listingID: entry.listingID,
            version: entry.version, recipeID: recipe.id, recipe: recipe, publisher: entry.publisher,
            provenance: entry.provenance, acquiredAt: entry.acquiredAt)
        await store.download(unlisted)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 5, "An arbitrary caller-supplied inventory entry must not be downloaded.")
        await store.download(entry)
        XCTAssertNil(store.downloadedItem)
        XCTAssertNotNil(store.errorMessage)
    }

    func testCancelledDownloadCannotStageLateCompletion() async throws {
        let transport = MarketplacePausedDownloadTransport(responses: try bootstrap,
            recipe: try recipe.encoded(), recipeID: recipe.id)
        let store = MarketplaceCatalogStore(transport: transport)
        await store.connect(); await store.signIn(handle: account.handle, password: "synthetic-password")
        let task = Task { await store.download(entry) }
        await transport.waitUntilDownload()
        task.cancel()
        await transport.release()
        await task.value
        XCTAssertNil(store.downloadedItem)
    }

    private var bootstrap: [MarketplaceScriptTransport.Response] {
        get throws {
            [.json("{\"service\":\"archi-marketplace\",\"apiVersion\":1,\"mode\":\"development\",\"commerce\":false,\"recipeSchema\":\"archi-item-design/v1\",\"maximumRecipeBytes\":4096}"),
             .json("{\"items\":[],\"total\":0,\"limit\":40,\"offset\":0}"),
             .json("{\"account\":\(String(decoding: try JSONEncoder().encode(account), as: UTF8.self)),\"token\":\"synthetic-token\",\"expiresAt\":\"2026-10-03T12:00:00Z\"}"),
             .json("{\"items\":[\(String(decoding: try JSONEncoder().encode(entry), as: UTF8.self))],\"total\":1,\"limit\":40,\"offset\":0}"),
             .json("{\"items\":[],\"total\":0,\"limit\":40,\"offset\":0}")]
        }
    }
    private func dictionary(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func makeStore(_ url: URL) -> CompanionStore {
        let client = MarketplaceAcquisitionNoCalls()
        return CompanionStore(preferenceURL: url, assistant: client, assistantFactory: { _, _ in client }, allowsPlay: false)
    }
    private struct Fixture {
        let root: URL
        var preferences: URL { root.appendingPathComponent("preferences.json") }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-acquisition-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

private actor MarketplacePausedDownloadTransport: MarketplaceHTTPTransport {
    let responses: MarketplaceScriptTransport
    let recipe: Data
    let recipeID: String
    private var started = false
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    init(responses: [MarketplaceScriptTransport.Response], recipe: Data, recipeID: String) {
        self.responses = MarketplaceScriptTransport(responses); self.recipe = recipe; self.recipeID = recipeID
    }
    func waitUntilDownload() async {
        if started { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { pending?.resume(); pending = nil }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.path.hasSuffix("/package") == true else { return try await responses.send(request) }
        started = true
        await withCheckedContinuation { continuation in
            pending = continuation
            observer?.resume(); observer = nil
        }
        return (recipe, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "X-ARCHi-Recipe-ID": recipeID])!)
    }
}

@MainActor
private final class MarketplaceAcquisitionNoCalls: AssistantClient {
    func connect() async throws { throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        throw AssistantFailure.configuration
    }
    func disconnect() {}
}
