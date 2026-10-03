import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// Native owner integration with synthetic, already-completed local receipts.
/// These checks make no provider calls and never open the suspended game.
final class KinGrowthIntegrationTests: XCTestCase {
    @MainActor
    func testPreviewKeepSaveReopenReturnAndResumePreserveExistingOwners() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let requestID = try retainUse(in: fixture)
        let identity = store.activeQiMon, preferences = store.preferences
        let lessons = store.keptLessons, position = store.position, placement = store.placementRevision
        let guidance = store.evolution.preferences
        let source = try Data(contentsOf: fixture.preferenceURL)
        XCTAssertEqual(store.presentationForm, .kinSeed)
        // The appearance title uses the selected Seed look; the existing form's
        // accessibility label retains its canonical Core Seed name.
        XCTAssertEqual(store.kinBodyTitle, "Particle Seed")
        XCTAssertTrue(store.assistantAccessibilityValue.contains("Core Seed"))
        XCTAssertEqual(store.kinGrowthEvidence.count, 1)
        XCTAssertTrue(store.previewKinGrowth(receiptID: requestID))
        XCTAssertTrue(store.canKeepKinGrowth)
        XCTAssertEqual(store.presentationForm, .kinSeed, "A card preview cannot replace the floating body")
        XCTAssertNil(store.evolution.kinGrowthRecord)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.evolutionURL.path))
        try await renderCard(store, name: "kin-growth-preview", previewReceiptID: requestID)
        // Removing the preview card dismisses its ephemeral invitation. A fresh
        // explicit preview still cannot change the actual body by itself.
        XCTAssertTrue(store.previewKinGrowth(receiptID: requestID))
        XCTAssertEqual(store.presentationForm, .kinSeed)

        XCTAssertTrue(store.keepKinGrowth())
        let kept = try XCTUnwrap(store.evolution.kinGrowthRecord)
        XCTAssertEqual(kept.originDigest, identity?.originDigest)
        XCTAssertEqual(kept.receipt.requestID, requestID)
        XCTAssertEqual(store.presentationForm, .kin)
        XCTAssertEqual(store.kinBodyTitle, "First Light")
        XCTAssertTrue(store.assistantAccessibilityValue.contains("First Light"))
        XCTAssertFalse(store.assistantAccessibilityValue.contains("Core Seed"))
        XCTAssertNil(store.evolution.kinGrowthProposal)
        XCTAssertFalse(store.keepKinGrowth(), "An old Keep action cannot commit twice")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.evolutionURL.path))
        try await renderCard(store, name: "kin-growth-kept")
        XCTAssertTrue(store.evolution.save(), store.evolution.status)

        let reopened = fixture.reopen()
        XCTAssertEqual(reopened.presentationForm, .kinSeed, "Existing Evolution Load remains explicit")
        XCTAssertNil(reopened.evolution.kinGrowthRecord)
        XCTAssertTrue(reopened.evolution.load(), reopened.evolution.status)
        XCTAssertEqual(reopened.evolution.kinGrowthRecord, kept)
        XCTAssertEqual(reopened.presentationForm, .kin)
        XCTAssertEqual(reopened.activeQiMon, identity)
        XCTAssertEqual(reopened.preferences, preferences)
        XCTAssertEqual(reopened.keptLessons, lessons)
        let saved = try Data(contentsOf: fixture.evolutionURL)

        reopened.returnKinToSeed()
        XCTAssertEqual(reopened.presentationForm, .kinSeed)
        XCTAssertEqual(reopened.kinBodyTitle, "Particle Seed")
        XCTAssertTrue(reopened.assistantAccessibilityValue.contains("Core Seed"))
        XCTAssertEqual(reopened.evolution.kinGrowthRecord?.id, kept.id)
        XCTAssertEqual(reopened.evolution.kinGrowthRecord?.receipt, kept.receipt)
        XCTAssertEqual(reopened.evolution.kinGrowthRecord?.active, false)
        XCTAssertEqual(try Data(contentsOf: fixture.evolutionURL), saved, "Return keeps explicit Save semantics")
        try await renderCard(reopened, name: "kin-growth-returned")
        XCTAssertTrue(reopened.evolution.save())
        let returned = fixture.reopen()
        XCTAssertTrue(returned.evolution.load())
        XCTAssertEqual(returned.presentationForm, .kinSeed)
        XCTAssertEqual(returned.evolution.kinGrowthRecord?.id, kept.id)
        XCTAssertTrue(returned.resumeKinFirstLight())
        XCTAssertEqual(returned.presentationForm, .kin)
        XCTAssertEqual(returned.evolution.kinGrowthRecord, kept)
        XCTAssertTrue(returned.evolution.save())

        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.preferences.equipment.hand, .focusStaff)
        XCTAssertEqual(store.keptLessons, lessons)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.evolution.preferences, guidance)
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), source)
        XCTAssertEqual(fixture.client.calls, 0)
        await returned.shutdownAssistant()
        await reopened.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor
    func testChangedWithdrawnExpiredOrUnconfirmedEvidenceCannotKeepAnOldPreview() async throws {
        for cause in ["revision", "lesson withdrawn", "expiry", "reference withdrawn", "request withdrawn", "guidance changed"] {
            let fixture = try makeFixture(expiresAfter: 60)
            defer { fixture.clean() }
            let store = fixture.store, requestID = try retainUse(in: fixture)
            let originalLesson = try XCTUnwrap(store.keptLessons.first)
            let identity = store.activeQiMon, position = store.position, preferences = store.preferences
            XCTAssertTrue(store.previewKinGrowth(receiptID: requestID), cause)
            switch cause {
            case "revision":
                store.beginLessonCorrection(revisingID: originalLesson.id)
                var draft = try XCTUnwrap(store.lessonDraft)
                draft.text = "Begin with the decision and one small action."
                XCTAssertTrue(store.keepLesson(draft))
                XCTAssertEqual(store.keptLessons.first?.revision, originalLesson.revision + 1)
            case "lesson withdrawn":
                XCTAssertTrue(store.withdrawLesson(id: originalLesson.id, expectedRevision: store.lessonRevision))
            case "expiry": fixture.clock.now = fixture.clock.now.addingTimeInterval(60)
            case "reference withdrawn": store.evolution.withdrawLessonUse(requestID: requestID)
            case "request withdrawn": store.evolution.withdrawUseful(requestID: requestID)
            default: store.evolution.confirmHelpStyle(.concise)
            }
            XCTAssertFalse(store.canKeepKinGrowth, cause)
            XCTAssertFalse(store.keepKinGrowth(), cause)
            XCTAssertNil(store.evolution.kinGrowthRecord, cause)
            XCTAssertNil(store.evolution.kinGrowthProposal, cause)
            XCTAssertEqual(store.presentationForm, .kinSeed)
            XCTAssertEqual(store.activeQiMon, identity)
            XCTAssertEqual(store.position, position)
            XCTAssertEqual(store.preferences, preferences)
            if cause != "guidance changed" { XCTAssertTrue(store.kinGrowthEvidence.isEmpty, cause) }
            XCTAssertEqual(fixture.client.calls, 0)
            await store.shutdownAssistant()
        }
    }

    @MainActor
    func testMissingLessonPlainUseAndWorkingCannotUnlockGrowth() async throws {
        let missing = try makeFixture(keepLesson: false)
        defer { missing.clean() }
        let orphan = try retainUse(in: missing)
        XCTAssertTrue(missing.store.kinGrowthEvidence.isEmpty)
        XCTAssertFalse(missing.store.previewKinGrowth(receiptID: orphan))
        XCTAssertFalse(missing.store.keepKinGrowth())
        XCTAssertEqual(missing.store.presentationForm, .kinSeed)

        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let plain = try retainUse(in: fixture, confirmedLesson: false)
        XCTAssertTrue(store.kinGrowthEvidence.isEmpty)
        XCTAssertFalse(store.previewKinGrowth(receiptID: plain))
        let qualified = try retainUse(in: fixture)
        store.isWorking = true
        XCTAssertFalse(store.kinGrowthControlsAvailable)
        XCTAssertFalse(store.previewKinGrowth(receiptID: qualified))
        store.isWorking = false
        XCTAssertTrue(store.previewKinGrowth(receiptID: qualified))
        store.isWorking = true
        XCTAssertFalse(store.keepKinGrowth())
        XCTAssertEqual(store.presentationForm, .kinSeed)
        store.isWorking = false
        XCTAssertTrue(store.previewKinGrowth(receiptID: qualified))
        XCTAssertTrue(store.keepKinGrowth())
        store.isWorking = true
        store.returnKinToSeed()
        XCTAssertEqual(store.presentationForm, .kin)
        store.isWorking = false
        store.returnKinToSeed()
        XCTAssertEqual(store.presentationForm, .kinSeed)
        store.isWorking = true
        XCTAssertFalse(store.resumeKinFirstLight())
        XCTAssertEqual(store.presentationForm, .kinSeed)
        store.isWorking = false
        XCTAssertEqual(fixture.client.calls + missing.client.calls, 0)
        await store.shutdownAssistant()
        await missing.store.shutdownAssistant()
    }

    @MainActor
    func testForeignIndividualGrowthCannotChangeTheCurrentKinsBody() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        _ = try retainUse(in: fixture)
        let receipt = try XCTUnwrap(store.evolution.usefulReceipts.first)
        let foreign = String(repeating: "d", count: 64)
        let proposal = try XCTUnwrap(store.evolution.proposeKinGrowth(originDigest: foreign, receipt: receipt))
        XCTAssertFalse(store.canKeepKinGrowth)
        // The Evolution owner can decode another valid individual's record;
        // CompanionStore must never present it as this personal KIN.
        XCTAssertTrue(store.evolution.keepKinGrowth(proposal))
        XCTAssertEqual(store.evolution.kinGrowthRecord?.originDigest, foreign)
        XCTAssertEqual(store.presentationForm, .kinSeed)
        let before = store.evolution.kinGrowthRecord
        store.returnKinToSeed()
        XCTAssertFalse(store.resumeKinFirstLight())
        XCTAssertEqual(store.evolution.kinGrowthRecord, before)
        XCTAssertTrue(store.evolution.save())
        let reopened = fixture.reopen()
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertEqual(reopened.evolution.kinGrowthRecord, before)
        XCTAssertEqual(reopened.presentationForm, .kinSeed)
        XCTAssertEqual(reopened.activeQiMon, store.activeQiMon)
        XCTAssertEqual(fixture.client.calls, 0)
        await reopened.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor
    func testForgettingAUsedLessonDoesNotThreatenAnAlreadyKeptBodyOrRestoreLessonText() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store, requestID = try retainUse(in: fixture)
        XCTAssertTrue(store.previewKinGrowth(receiptID: requestID))
        XCTAssertTrue(store.keepKinGrowth())
        let record = try XCTUnwrap(store.evolution.kinGrowthRecord)
        let lesson = try XCTUnwrap(store.keptLessons.first)
        XCTAssertTrue(store.withdrawLesson(id: lesson.id, expectedRevision: store.lessonRevision))
        XCTAssertTrue(store.kinGrowthEvidence.isEmpty)
        XCTAssertEqual(store.presentationForm, .kin)
        XCTAssertTrue(store.lessonUseDescription(try XCTUnwrap(record.receipt.lessonUse)).contains("no longer kept"))
        store.returnKinToSeed()
        XCTAssertTrue(store.resumeKinFirstLight(), "A reviewed historical body choice does not require keeping unwanted knowledge")
        XCTAssertEqual(store.evolution.kinGrowthRecord, record)
        XCTAssertTrue(store.evolution.save())
        let reopened = fixture.reopen()
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertTrue(reopened.keptLessons.isEmpty)
        XCTAssertEqual(reopened.presentationForm, .kin)
        XCTAssertEqual(reopened.evolution.kinGrowthRecord, record)
        XCTAssertFalse(String(decoding: try Data(contentsOf: fixture.evolutionURL), as: UTF8.self).contains(lesson.text))
        XCTAssertEqual(fixture.client.calls, 0)
        await reopened.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor private func makeFixture(keepLesson: Bool = true, expiresAfter: TimeInterval? = nil) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kin-growth-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferenceURL = directory.appendingPathComponent("preferences.json")
        let clock = GrowthClock()
        let lesson = KeptLesson(topic: "Writing plans", text: "Begin with a short outline and one next step.",
            createdAt: clock.now, expiresAt: expiresAfter.map { clock.now.addingTimeInterval($0) })
        var preferences = CompanionPreferences()
        preferences.seedAppearance = .kinParticles
        preferences.tone = "Warm"
        preferences.reduceMotion = true
        preferences.equipment = CompanionEquipment(hand: .focusStaff)
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: clock.now)
        try NativePreferenceDocument(preferences: preferences, lessons: keepLesson ? [lesson] : [], qiMon: kin)
            .encoded().write(to: preferenceURL)
        let client = GrowthNoCalls()
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, wallClock: { clock.now }, allowsPlay: false)
        store.placed(at: CGPoint(x: 500, y: 350))
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.reflective)
        return Fixture(directory: directory, preferenceURL: preferenceURL, clock: clock, lesson: lesson, client: client, store: store)
    }

    @MainActor private func retainUse(in fixture: Fixture, confirmedLesson: Bool = true) throws -> UUID {
        let id = UUID(), snapshot = LessonSnapshot(lesson: fixture.lesson)
        let source = String(repeating: "b", count: 64)
        var receipt = AssistantLaneReceipt(requestID: id.uuidString, route: .local, provider: .qwen,
            context: fixture.store.contextTicket(), inputDigest: String(repeating: "c", count: 64),
            sourceDigest: source, inputContract: "native-assistant-input/v4", deadline: .distantFuture,
            modelIdentity: "synthetic-growth-fixture", state: .complete)
        receipt.localLessons = [snapshot]
        receipt.usedLessonIDs = [snapshot.modelID]
        XCTAssertTrue(fixture.store.evolution.markUseful(receipt: receipt, sourceDigest: source,
            confirmedLesson: confirmedLesson ? snapshot : nil))
        return id
    }

    @MainActor private func renderCard(_ store: CompanionStore, name: String, previewReceiptID: UUID? = nil) async throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_KIN_GROWTH_RENDER_DIR"] else { return }
        let width: CGFloat = 596
        let view = KinGrowthCard(store: store, evolution: store.evolution,
            showStudy: previewReceiptID != nil, selectedReceiptID: previewReceiptID)
            .frame(width: width).fixedSize(horizontal: false, vertical: true)
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: width, height: 1200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        defer { panel.contentView = nil; panel.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let height = hosting.fittingSize.height
        XCTAssertGreaterThan(height, 100)
        XCTAssertLessThan(height, 1200)
        panel.setContentSize(CGSize(width: width, height: height))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
    }

    @MainActor private struct Fixture {
        let directory: URL
        let preferenceURL: URL
        let clock: GrowthClock
        let lesson: KeptLesson
        let client: GrowthNoCalls
        let store: CompanionStore
        var evolutionURL: URL { preferenceURL.deletingPathExtension().appendingPathExtension("evolution.json") }
        func reopen() -> CompanionStore {
            CompanionStore(preferenceURL: preferenceURL, assistant: client,
                assistantFactory: { _, _ in client }, wallClock: { clock.now }, allowsPlay: false)
        }
        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
}

@MainActor private final class GrowthClock {
    var now = Date(timeIntervalSince1970: 1_789_000_000)
}

@MainActor private final class GrowthNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        throw AssistantFailure.configuration
    }
    func disconnect() {}
}
