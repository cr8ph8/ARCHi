import Foundation
import XCTest
@testable import ARCHiDesktop

/// All files are disposable. No UI, provider connection, or real profile is used.
@MainActor
final class MarketplacePersistenceTests: XCTestCase {
    private var staff: CompanionItemPackage { CompanionItemCatalog.designs[0] }
    private var star: CompanionItemPackage { CompanionItemCatalog.designs[1] }
    private var grove: CompanionItemPackage { CompanionItemCatalog.designs[2] }
    private let instant = Date(timeIntervalSince1970: 1_789_000_000)

    func testCollectPersistsWithoutRememberingAppearanceAndRestartsWithoutEquipping() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        store.preferences.tone = "Warm"
        store.preferences.reduceMotion = true
        let visitingPreferences = store.preferences
        XCTAssertFalse(store.rememberPreferences)
        XCTAssertTrue(store.collectMarketItem(staff), store.marketplaceMessage)
        XCTAssertEqual(store.itemLibrary, [staff])
        XCTAssertEqual(store.preferences, visitingPreferences)
        let persisted = try NativePreferencePersistence.read(fixture.preferences)
        XCTAssertNil(persisted.document.preferences)
        XCTAssertEqual(persisted.document.itemLibrary, [staff])
        XCTAssertEqual(persisted.document.revision, 1)
        XCTAssertFalse(store.rememberPreferences)

        let reopened = makeStore(at: fixture.preferences, client: client)
        XCTAssertEqual(reopened.itemLibrary, [staff])
        XCTAssertEqual(reopened.preferences, CompanionPreferences())
        XCTAssertFalse(reopened.rememberPreferences)
        XCTAssertTrue(reopened.preferences.equipment.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), persisted.baseline)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.evolution.path))
        XCTAssertEqual(client.calls, 0)
    }

    func testEquipRequiresCollectionAndOnlyExplicitSaveRetainsTheOutfit() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        XCTAssertFalse(store.equipMarketItem(staff))
        XCTAssertTrue(store.preferences.equipment.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.preferences.path))
        XCTAssertTrue(store.collectMarketItem(staff))
        let collected = try Data(contentsOf: fixture.preferences)
        XCTAssertTrue(store.equipMarketItem(staff))
        XCTAssertEqual(store.preferences.equipment.design, staff)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), collected)
        store.savePreferences()
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), collected,
                       "Save must respect the existing appearance opt-in.")
        let visitOnly = makeStore(at: fixture.preferences, client: client)
        XCTAssertTrue(visitOnly.preferences.equipment.isEmpty)
        XCTAssertEqual(visitOnly.itemLibrary, [staff])

        store.rememberPreferences = true
        store.savePreferences()
        let saved = try NativePreferencePersistence.read(fixture.preferences)
        XCTAssertEqual(saved.document.preferences?.equipment.design, staff)
        XCTAssertEqual(saved.document.itemLibrary, [staff])
        XCTAssertEqual(saved.document.revision, 2)
        let reopened = makeStore(at: fixture.preferences, client: client)
        XCTAssertTrue(reopened.rememberPreferences)
        XCTAssertEqual(reopened.preferences.equipment.design, staff)
        XCTAssertEqual(reopened.itemLibrary, [staff])
        XCTAssertEqual(client.calls, 0)
    }

    func testInvalidItemReviewExplainsRejectionWithoutChangingExistingProfileOrOutfit() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let document = savedDocument(equipped: staff, library: [staff, star])
        _ = try NativePreferencePersistence.write(document: document, to: fixture.preferences, expected: nil)
        let original = try Data(contentsOf: fixture.preferences)
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        let preferences = store.preferences
        let identity = store.activeQiMon
        let revision = store.lessonRevision

        var missing = CompanionItemPackage.creatorDefault
        missing.title = " "
        missing.creator = ""
        var malformed = CompanionItemPackage.creatorDefault
        malformed.title = "private\u{0000}name"
        malformed.summary = String(repeating: "x", count: 161)
        for item in [missing, malformed] {
            XCTAssertFalse(store.collectMarketItem(item))
            XCTAssertEqual(store.marketplaceMessage, item.review.correctionMessage)
            XCTAssertFalse(store.marketplaceMessage.isEmpty)
            XCTAssertFalse(store.marketplaceMessage.contains("private"))
            XCTAssertEqual(store.itemLibrary, document.itemLibrary)
            XCTAssertEqual(store.preferences, preferences)
            XCTAssertEqual(store.activeQiMon, identity)
            XCTAssertEqual(store.keptLessons, document.lessons)
            XCTAssertEqual(store.lessonRevision, revision)
            XCTAssertEqual(try Data(contentsOf: fixture.preferences), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.evolution.path))
            XCTAssertEqual(client.calls, 0)
        }
    }

    func testRemovingCurrentAndSavedDesignCommitsTogetherAndPreservesOtherProfileData() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let document = savedDocument(equipped: staff, library: [staff, star])
        _ = try NativePreferencePersistence.write(document: document, to: fixture.preferences, expected: nil)
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        store.preferences.tone = "Direct"
        XCTAssertTrue(store.removeMarketItem(staff), store.marketplaceMessage)
        XCTAssertEqual(store.itemLibrary, [star])
        XCTAssertTrue(store.preferences.equipment.isEmpty)
        XCTAssertEqual(store.preferences.tone, "Direct", "Unrelated visit choices must stay temporary.")
        let saved = try NativePreferencePersistence.read(fixture.preferences).document
        XCTAssertEqual(saved.revision, document.revision + 1, "Removal is one profile transaction.")
        XCTAssertEqual(saved.itemLibrary, [star])
        XCTAssertEqual(saved.preferences?.equipment, .empty)
        XCTAssertEqual(saved.preferences?.tone, "Warm")
        XCTAssertEqual(saved.lessons, document.lessons)
        XCTAssertEqual(saved.focusGesture, document.focusGesture)
        XCTAssertEqual(saved.qiMon, document.qiMon)
        let reopened = makeStore(at: fixture.preferences, client: client)
        XCTAssertTrue(reopened.preferences.equipment.isEmpty)
        XCTAssertEqual(reopened.itemLibrary, [star])
        XCTAssertEqual(reopened.keptLessons, document.lessons)
        XCTAssertEqual(client.calls, 0)
    }

    func testRemovalDistinguishesSavedOutfitFromDifferentCurrentOutfit() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let document = savedDocument(equipped: staff, library: [staff, star, grove])
        _ = try NativePreferencePersistence.write(document: document, to: fixture.preferences, expected: nil)
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        XCTAssertTrue(store.equipMarketItem(star))
        XCTAssertTrue(store.removeMarketItem(staff))
        XCTAssertEqual(store.preferences.equipment.design, star, "Removing the saved design must preserve a different visit outfit.")
        XCTAssertEqual(try NativePreferencePersistence.read(fixture.preferences).document.preferences?.equipment, .empty)

        store.rememberPreferences = true
        store.savePreferences()
        XCTAssertTrue(store.equipMarketItem(grove))
        XCTAssertTrue(store.removeMarketItem(grove))
        XCTAssertTrue(store.preferences.equipment.isEmpty)
        let saved = try NativePreferencePersistence.read(fixture.preferences).document
        XCTAssertEqual(saved.preferences?.equipment.design, star, "Removing a visit outfit must preserve a different saved outfit.")
        XCTAssertEqual(saved.itemLibrary, [star])
        XCTAssertEqual(client.calls, 0)
    }

    func testExternalConflictDoesNotPublishCollectionOrOutfitChanges() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let document = savedDocument(equipped: staff, library: [staff])
        _ = try NativePreferencePersistence.write(document: document, to: fixture.preferences, expected: nil)
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        let currentOutfit = store.preferences.equipment
        let revision = store.lessonRevision
        var external = document
        external.revision += 4
        external.preferences?.tone = "Direct"
        let externalBytes = try external.encoded()
        try externalBytes.write(to: fixture.preferences)

        XCTAssertFalse(store.collectMarketItem(star))
        XCTAssertEqual(store.itemLibrary, [staff])
        XCTAssertEqual(store.preferences.equipment, currentOutfit)
        XCTAssertEqual(store.lessonRevision, revision)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), externalBytes)
        XCTAssertFalse(store.removeMarketItem(staff))
        XCTAssertEqual(store.itemLibrary, [staff])
        XCTAssertEqual(store.preferences.equipment, currentOutfit)
        XCTAssertEqual(store.lessonRevision, revision)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), externalBytes)
        store.savePreferences()
        XCTAssertEqual(store.itemLibrary, [staff])
        XCTAssertEqual(store.preferences.equipment, currentOutfit)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), externalBytes)
        XCTAssertTrue(store.status.contains("changed outside this session"))
        XCTAssertEqual(client.calls, 0)
    }

    func testVersionFourMigratesInMemoryAndOnlyAnExplicitCollectWritesVersionFive() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        var legacyPreferences = CompanionPreferences()
        legacyPreferences.tone = "Warm"
        legacyPreferences.equipment = CompanionEquipment(hand: .focusStaff)
        let source = NativePreferenceDocument(revision: 12, preferences: legacyPreferences,
            lessons: [lesson()], focusGesture: .init(pace: .unhurried, sparkle: .none, hold: .brief))
        var fields = try object(source.encoded())
        fields["schema"] = "archi-native-preferences/v4"
        fields.removeValue(forKey: "itemLibrary")
        let legacyBytes = try JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys])
        try legacyBytes.write(to: fixture.preferences)
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        XCTAssertEqual(store.preferences, legacyPreferences)
        XCTAssertEqual(store.preferences.equipment.canonicalIdentity, "archi-companion-equipment/v1\nhand=focus-staff/v1\n")
        XCTAssertEqual(store.keptLessons, source.lessons)
        XCTAssertEqual(store.keptFocusGesture, source.focusGesture)
        XCTAssertTrue(store.itemLibrary.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), legacyBytes)
        XCTAssertEqual(try NativePreferencePersistence.read(fixture.preferences).baseline, legacyBytes)
        XCTAssertTrue(store.collectMarketItem(staff))
        let migrated = try NativePreferencePersistence.read(fixture.preferences).document
        XCTAssertEqual(migrated.schema, NativePreferenceDocument.currentSchema)
        XCTAssertEqual(migrated.revision, 13)
        XCTAssertEqual(migrated.preferences, legacyPreferences)
        XCTAssertEqual(migrated.lessons, source.lessons)
        XCTAssertEqual(migrated.focusGesture, source.focusGesture)
        XCTAssertEqual(migrated.itemLibrary, [staff])
        XCTAssertEqual(client.calls, 0)
    }

    func testSavedDesignMustExistInTheExactCollectionAndInvalidFilesArePreserved() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let valid = savedDocument(equipped: staff, library: [staff])
        var missing = valid
        missing.itemLibrary = []
        XCTAssertFalse(missing.isValid)
        XCTAssertThrowsError(try missing.encoded())
        var changed = staff
        changed.revision += 1
        missing.itemLibrary = [changed]
        XCTAssertFalse(missing.isValid, "A different revision must not satisfy saved equipment membership.")

        var fields = try object(valid.encoded())
        fields["itemLibrary"] = []
        let damaged = try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
        XCTAssertThrowsError(try NativePreferenceDocument.decode(damaged))
        try damaged.write(to: fixture.preferences)
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        XCTAssertTrue(store.itemLibrary.isEmpty)
        XCTAssertTrue(store.preferences.equipment.isEmpty)
        XCTAssertFalse(store.collectMarketItem(star))
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), damaged)
        XCTAssertEqual(client.calls, 0)
    }

    func testSavedOutfitCannotBeWrittenFromAnUncollectedDraft() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        XCTAssertTrue(store.collectMarketItem(staff))
        let before = try Data(contentsOf: fixture.preferences)
        // The public preferences value can be edited by existing appearance UI;
        // profile admission must still enforce collection membership at Save.
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff, design: star)
        store.rememberPreferences = true
        store.savePreferences()
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), before)
        XCTAssertEqual(store.itemLibrary, [staff])
        XCTAssertNil(try NativePreferencePersistence.read(fixture.preferences).document.preferences)
        XCTAssertEqual(client.calls, 0)
    }

    func testLessonExportExcludesCollectionOutfitAndIdentityWithoutChangingTheProfile() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let document = savedDocument(equipped: staff, library: [staff, star])
        _ = try NativePreferencePersistence.write(document: document, to: fixture.preferences, expected: nil)
        let before = try Data(contentsOf: fixture.preferences)
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        let data = try store.lessonExportData()
        let exported = try NativePreferenceDocument.decode(data)
        XCTAssertEqual(exported.lessons, document.lessons)
        XCTAssertTrue(exported.itemLibrary.isEmpty)
        XCTAssertNil(exported.preferences)
        XCTAssertNil(exported.focusGesture)
        XCTAssertNil(exported.qiMon)
        let serialized = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(serialized.contains(staff.summary))
        XCTAssertFalse(serialized.contains(star.title))
        XCTAssertEqual(store.itemLibrary, [staff, star])
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), before)
        XCTAssertEqual(client.calls, 0)
    }

    func testForgettingAppearanceRetainsTheCollectionAndLastRemovalClearsAnEmptyProfile() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        XCTAssertTrue(store.collectMarketItem(staff))
        XCTAssertTrue(store.equipMarketItem(staff))
        store.rememberPreferences = true
        store.savePreferences()
        store.forgetPreferences()
        let forgotten = try NativePreferencePersistence.read(fixture.preferences).document
        XCTAssertNil(forgotten.preferences)
        XCTAssertEqual(forgotten.itemLibrary, [staff])
        XCTAssertEqual(store.preferences.equipment.design, staff, "Forgetting saved choices leaves the current visit unchanged.")
        XCTAssertFalse(store.rememberPreferences)
        XCTAssertTrue(store.removeMarketItem(staff))
        XCTAssertTrue(store.itemLibrary.isEmpty)
        XCTAssertTrue(store.preferences.equipment.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.preferences.path))
        let reopened = makeStore(at: fixture.preferences, client: client)
        XCTAssertTrue(reopened.itemLibrary.isEmpty)
        XCTAssertTrue(reopened.preferences.equipment.isEmpty)
        XCTAssertEqual(client.calls, 0)
    }

    func testDuplicateAndNinthCollectDoNotCreateAnotherWrite() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        for revision in 1...8 {
            var design = CompanionItemPackage.creatorDefault
            design.revision = revision
            XCTAssertTrue(store.collectMarketItem(design))
        }
        let fullBytes = try Data(contentsOf: fixture.preferences)
        let fullRevision = store.lessonRevision
        XCTAssertTrue(store.collectMarketItem(.creatorDefault))
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), fullBytes)
        XCTAssertEqual(store.lessonRevision, fullRevision)
        var ninth = CompanionItemPackage.creatorDefault
        ninth.revision = 9
        XCTAssertFalse(store.collectMarketItem(ninth))
        XCTAssertEqual(store.itemLibrary.count, 8)
        XCTAssertEqual(store.lessonRevision, fullRevision)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), fullBytes)
        XCTAssertEqual(client.calls, 0)
    }

    func testBackupRestoreAndRollbackReloadCollectionThroughTheExistingOwner() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let sourceURL = fixture.root.appendingPathComponent("source/preferences.json")
        let source = savedDocument(equipped: star, library: [star, grove])
        let destination = savedDocument(equipped: staff, library: [staff])
        _ = try NativePreferencePersistence.write(document: source, to: sourceURL, expected: nil)
        _ = try NativePreferencePersistence.write(document: destination, to: fixture.preferences, expected: nil)
        let sourceBytes = try Data(contentsOf: sourceURL)
        let destinationBytes = try Data(contentsOf: fixture.preferences)
        let client = MarketplacePersistenceNoCalls()
        let store = makeStore(at: fixture.preferences, client: client)
        store.importedMarketItem = .creatorDefault
        let archive = fixture.root.appendingPathComponent("collection.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: sourceURL,
            archiveURL: archive, now: instant)
        let preview = try DesktopProfileBackup.preview(archiveURL: archive, profile: .custom,
            preferenceURL: fixture.preferences)
        let report = try DesktopProfileBackup.restore(preview,
            rollbackDirectory: fixture.root.appendingPathComponent("rollback"))
        XCTAssertEqual(store.itemLibrary, [staff], "File restore is followed by explicit native admission.")
        try store.admitRestoredProfile()
        XCTAssertEqual(store.itemLibrary, [star, grove])
        XCTAssertEqual(store.preferences.equipment.design, star)
        XCTAssertEqual(store.keptLessons, source.lessons)
        XCTAssertNil(store.importedMarketItem)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), sourceBytes, "Reload must not rewrite restored bytes.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.evolution.path))

        _ = try DesktopProfileBackup.undoRestore(report)
        try store.admitRestoredProfile()
        XCTAssertEqual(store.itemLibrary, [staff])
        XCTAssertEqual(store.preferences.equipment.design, staff)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), destinationBytes)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(client.calls, 0)
    }

    private func savedDocument(equipped: CompanionItemPackage, library: [CompanionItemPackage]) -> NativePreferenceDocument {
        var preferences = CompanionPreferences()
        preferences.tone = "Warm"
        preferences.reduceMotion = true
        preferences.equipment = CompanionEquipment(hand: .focusStaff, design: equipped)
        return NativePreferenceDocument(revision: 7, preferences: preferences, lessons: [lesson()],
            focusGesture: .init(pace: .unhurried, sparkle: .none, hold: .lingering),
            qiMon: LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: instant),
            itemLibrary: library)
    }

    private func lesson() -> KeptLesson {
        KeptLesson(id: "CB0E1CDD-08C4-4B66-845B-E48BDB82AF6F", topic: "Drawing practice",
            text: "Start with a simple outline.", reason: "Synthetic marketplace persistence fixture.", createdAt: instant)
    }

    private func makeStore(at url: URL, client: MarketplacePersistenceNoCalls) -> CompanionStore {
        let now = instant
        return CompanionStore(preferenceURL: url, assistant: client, assistantFactory: { _, _ in client },
            wallClock: { now }, allowsPlay: false)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private struct Fixture {
        let root: URL
        var preferences: URL { root.appendingPathComponent("preferences.json") }
        var evolution: URL { root.appendingPathComponent("preferences.evolution.json") }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-marketplace-tests-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

@MainActor
private final class MarketplacePersistenceNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        throw AssistantFailure.configuration
    }
    func disconnect() {}
}
