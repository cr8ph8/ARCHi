import Foundation
import XCTest
@testable import ARCHiDesktop

/// Opt-in real HTTP + SQLite service evidence. The caller must start an empty
/// disposable database; no default service, account, or person profile is used.
final class MarketplaceServiceIntegrationTests: XCTestCase {
    @MainActor
    func testCreatorPublishAcquireDownloadInstallUpdateArchiveAndReturn() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_SERVICE_URL"] else {
            throw XCTSkip("Set ARCHI_MARKETPLACE_SERVICE_URL to an isolated development service for the real creator lifecycle.")
        }
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let creatorHandle = "creator_" + suffix, readerHandle = "reader_" + suffix
        let password = "synthetic-fixture-password"
        let creator = MarketplaceCatalogStore(), reader = MarketplaceCatalogStore()
        creator.endpointText = endpoint; reader.endpointText = endpoint
        await creator.connect(); await reader.connect()
        XCTAssertTrue(creator.connected, creator.errorMessage ?? "Not connected")
        XCTAssertTrue(reader.connected, reader.errorMessage ?? "Not connected")
        let created = await creator.createAccount(handle: creatorHandle, displayName: "Synthetic Creator", password: password)
        XCTAssertTrue(created, creator.errorMessage ?? "Account failed")
        XCTAssertNil(creator.account, "Creating an account does not imply authentication.")
        await creator.signIn(handle: creatorHandle, password: password)
        XCTAssertEqual(creator.account?.handle, creatorHandle)
        creator.draft = .init(title: "Test " + suffix, creator: "Declared credit", summary: "An isolated creator lifecycle fixture.", palette: .mint)
        creator.provenance = .init(attribution: "Synthetic design for integration acceptance", rightsConfirmed: true)
        let firstRecipe = creator.draft
        await creator.saveDraft()
        let initial = try XCTUnwrap(creator.editingListing, creator.errorMessage ?? "Draft missing")
        XCTAssertEqual(initial.version, 1); XCTAssertEqual(initial.status, .draft)
        XCTAssertFalse(creator.catalog.contains { $0.id == initial.id })
        await creator.publish(initial)
        let published = try XCTUnwrap(creator.listings.first { $0.id == initial.id })
        XCTAssertEqual(published.version, 2); XCTAssertEqual(published.status, .published)
        XCTAssertEqual(published.publisher.handle, creatorHandle)
        XCTAssertEqual(published.recipe.creator, "Declared credit", "Authenticated publisher and declared credit remain separate.")
        XCTAssertEqual(published.recipeID, firstRecipe.id)

        let readerCreated = await reader.createAccount(handle: readerHandle, displayName: "Synthetic Reader", password: password)
        XCTAssertTrue(readerCreated, reader.errorMessage ?? "Reader failed")
        await reader.signIn(handle: readerHandle, password: password)
        reader.search = firstRecipe.title
        await reader.refreshCatalog()
        let offered = try XCTUnwrap(reader.catalog.first { $0.id == initial.id }, reader.errorMessage ?? "Published listing unavailable")
        await reader.acquire(offered)
        let acquisition = try XCTUnwrap(reader.inventory.first { $0.recipeID == firstRecipe.id }, reader.errorMessage ?? "Acquisition missing")
        await reader.acquire(offered)
        XCTAssertEqual(reader.inventory.filter { $0.recipeID == firstRecipe.id }.count, 1, "Repeat acquisition must not create duplicates.")
        await reader.download(acquisition)
        XCTAssertEqual(reader.downloadedRecipe, firstRecipe)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-catalog-install-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = directory.appendingPathComponent("preferences.json")
        let native = CompanionStore(preferenceURL: profile, allowsPlay: false)
        let preferences = native.preferences
        XCTAssertTrue(native.itemLibrary.isEmpty, "Account acquisition is separate from local installation.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.path))
        let downloaded = try XCTUnwrap(reader.downloadedRecipe)
        XCTAssertTrue(native.collectMarketItem(downloaded))
        XCTAssertEqual(native.preferences, preferences, "Installing a recipe must never equip it.")
        XCTAssertTrue(native.equipMarketItem(downloaded))
        XCTAssertEqual(native.preferences.equipment.design, downloaded)
        XCTAssertEqual(native.savedMarketplaceEquipment?.design, nil, "Equip affects this visit until explicitly saved.")
        let restored = CompanionStore(preferenceURL: profile, allowsPlay: false)
        XCTAssertTrue(restored.itemLibrary.contains(downloaded), "Explicit installation survives reopen.")
        XCTAssertTrue(restored.preferences.equipment.isEmpty)

        creator.edit(published)
        creator.draft.title = "Update " + suffix
        creator.draft.revision = 2
        await creator.saveDraft()
        let revision = try XCTUnwrap(creator.editingListing)
        XCTAssertEqual(revision.version, 3); XCTAssertEqual(revision.publishedVersion, 2)
        await reader.refreshCatalog()
        XCTAssertEqual(reader.catalog.first { $0.id == initial.id }?.recipe, firstRecipe, "Editing must preserve the last published version.")
        await creator.publish(published)
        XCTAssertTrue(creator.errorMessage?.contains("changed") == true, "A stale expected version must fail.")
        XCTAssertEqual(creator.editingListing?.version, 3)
        await creator.publish(revision)
        let revisedPublished = try XCTUnwrap(creator.listings.first { $0.id == initial.id })
        XCTAssertEqual(revisedPublished.version, 4)
        await creator.loadHistory(revisedPublished)
        XCTAssertEqual(creator.history.map(\.version), [4, 3, 2, 1])
        await creator.archive(revisedPublished)
        XCTAssertEqual(creator.listings.first { $0.id == initial.id }?.status, .archived)
        reader.search = ""; await reader.refreshCatalog()
        XCTAssertFalse(reader.catalog.contains { $0.id == initial.id })
        reader.downloadedRecipe = nil
        await reader.download(acquisition)
        XCTAssertEqual(reader.downloadedRecipe, firstRecipe, "Acquired immutable versions remain downloadable after archive.")
        await reader.signOut()
        XCTAssertNil(reader.account); XCTAssertTrue(reader.inventory.isEmpty)
        let returning = MarketplaceCatalogStore()
        returning.endpointText = endpoint
        await returning.connect(); await returning.signIn(handle: readerHandle, password: password)
        XCTAssertEqual(returning.inventory.first { $0.recipeID == firstRecipe.id }, acquisition, "Account inventory survives a fresh client session.")
        XCTAssertEqual(native.preferences.equipment.design, downloaded, "Sign-out cannot change the native outfit.")
        await returning.signOut(); await creator.signOut()
        await native.shutdownAssistant(); await restored.shutdownAssistant()
    }
}
