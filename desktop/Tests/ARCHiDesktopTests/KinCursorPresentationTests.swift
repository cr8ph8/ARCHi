import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// The memory avatar and a kept body are projections of the same personal record.
/// All data, windows and completed-answer fixtures here are local and disposable.
final class KinCursorPresentationTests: XCTestCase {
    @MainActor
    func testLiminalSelectionCannotEmitRejectedFirstLightCombination() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        _ = try keepGrowth(in: fixture)
        let store = fixture.store, growth = store.evolution.kinGrowthRecord
        let individual = store.activeQiMon
        store.chooseSeedAppearance(.hamptonLiminal)
        XCTAssertEqual(store.presentationForm, .hamptonSeed)
        let snapshot = try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(), revision: 1,
                                                                      active: true, now: Date(), systemReduceMotion: true))
        XCTAssertEqual(snapshot.body, "seed")
        XCTAssertEqual(snapshot.seedAppearance, "hamptonLiminal")
        XCTAssertEqual(store.evolution.kinGrowthRecord, growth)
        store.chooseSeedAppearance(.kinParticles)
        XCTAssertEqual(store.presentationForm, .kin)
        XCTAssertEqual(store.activeQiMon, individual)
        XCTAssertEqual(store.evolution.kinGrowthRecord, growth)
    }
    @MainActor
    func testLightAppearanceKeepsOneIdentityAndBodyMilestoneAcrossSaveAndReturn() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        _ = try keepGrowth(in: fixture)
        let identity = store.activeQiMon, growth = store.evolution.kinGrowthRecord
        let history = store.evolution.history, position = store.position
        let originalBytes = try Data(contentsOf: fixture.preferenceURL)
        store.chooseSeedAppearance(.archiLight)
        XCTAssertEqual(store.presentationForm, .kin)
        XCTAssertEqual(store.cursorPresentationForm, .corePearl)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.evolution.kinGrowthRecord, growth)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), originalBytes, "A look choice alone is not a save")
        let snapshot = try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: UUID(), revision: 1,
            active: true, now: Date(), systemReduceMotion: true))
        XCTAssertEqual(snapshot.seedAppearance, "archiLight")
        XCTAssertEqual(snapshot.seedAssetSHA256, CompanionVisualAsset.lightSeedDigest)
        XCTAssertEqual(snapshot.body, "firstLight")
        store.returnKinToSeed()
        XCTAssertEqual(store.presentationForm, .corePearl)
        store.rememberPreferences = true
        store.savePreferences()
        XCTAssertTrue(store.evolution.save())
        let reopened = fixture.reopen()
        XCTAssertEqual(reopened.preferences.seedAppearance, .archiLight)
        XCTAssertEqual(reopened.presentationForm, .corePearl)
        XCTAssertEqual(reopened.activeQiMon, identity)
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertTrue(reopened.resumeKinFirstLight())
        XCTAssertEqual(reopened.presentationForm, .kin)
        XCTAssertEqual(reopened.cursorPresentationForm, .corePearl)
        reopened.chooseSeedAppearance(.kinParticles)
        XCTAssertEqual(reopened.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(reopened.presentationForm, .kin)
        await reopened.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor
    func testMemoryAvatarKeepsSavedSeedIdentityAcrossBodyKeepLoadReturnResumeAndLessonWithdrawal() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let identity = store.activeQiMon, preferences = store.preferences
        let position = store.position, placement = store.placementRevision
        let initialPreferenceBytes = try Data(contentsOf: fixture.preferenceURL)
        XCTAssertEqual(store.presentationForm, .kinSeed)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        let requestID = try retainUse(in: fixture)
        XCTAssertTrue(store.previewKinGrowth(receiptID: requestID))
        XCTAssertEqual(store.presentationForm, .kinSeed)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed)
        XCTAssertTrue(store.keepKinGrowth())
        let growth = try XCTUnwrap(store.evolution.kinGrowthRecord)
        assertFirstLightBodyAndMemoryAvatar(store)
        XCTAssertTrue(store.evolution.save())
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), initialPreferenceBytes)

        let reopened = fixture.reopen()
        XCTAssertEqual(reopened.presentationForm, .kinSeed, "Evolution Load remains explicit")
        XCTAssertEqual(reopened.cursorPresentationForm, .kinSeed)
        XCTAssertTrue(reopened.evolution.load())
        assertFirstLightBodyAndMemoryAvatar(reopened)
        XCTAssertEqual(reopened.activeQiMon, identity)
        XCTAssertEqual(reopened.preferences, preferences)
        XCTAssertEqual(reopened.evolution.kinGrowthRecord, growth)
        reopened.returnKinToSeed()
        XCTAssertEqual(reopened.presentationForm, .kinSeed)
        XCTAssertEqual(reopened.cursorPresentationForm, .kinSeed)
        XCTAssertTrue(reopened.resumeKinFirstLight())
        assertFirstLightBodyAndMemoryAvatar(reopened)

        let lesson = try XCTUnwrap(reopened.keptLessons.first)
        XCTAssertTrue(reopened.withdrawLesson(id: lesson.id, expectedRevision: reopened.lessonRevision))
        XCTAssertTrue(reopened.keptLessons.isEmpty)
        XCTAssertTrue(reopened.kinGrowthEvidence.isEmpty)
        assertFirstLightBodyAndMemoryAvatar(reopened)
        XCTAssertTrue(reopened.evolution.save())
        let afterWithdrawal = fixture.reopen()
        XCTAssertTrue(afterWithdrawal.evolution.load())
        assertFirstLightBodyAndMemoryAvatar(afterWithdrawal)
        XCTAssertTrue(afterWithdrawal.keptLessons.isEmpty)
        XCTAssertEqual(afterWithdrawal.activeQiMon, identity)
        XCTAssertEqual(afterWithdrawal.preferences, preferences)
        XCTAssertEqual(afterWithdrawal.evolution.kinGrowthRecord, growth)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(fixture.client.calls, 0)
        await afterWithdrawal.shutdownAssistant()
        await reopened.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor
    func testBothPresentationsRequireTheSameActiveIndividualAcrossNativeAndRetainedOriginRules() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        _ = try keepGrowth(in: fixture)
        XCTAssertTrue(fixture.store.evolution.save())
        let bytes = try Data(contentsOf: fixture.preferenceURL)

        // Native-only mode uses the validated saved personal record. It does not
        // require or invent a live game host, even if stale projection data exists.
        fixture.store.observeQiMonJourney(projection(String(repeating: "b", count: 64)))
        assertFirstLightBodyAndMemoryAvatar(fixture.store)
        let nativeIdentity = fixture.store.activeQiMon

        // This checks the retained origin contract with synthetic projection
        // values only. No HostedPlayHost, WebKit view or server is constructed.
        let originBound = fixture.reopen(allowsPlay: true)
        XCTAssertTrue(originBound.evolution.load())
        XCTAssertNil(originBound.activeQiMon)
        XCTAssertEqual(originBound.presentationForm, .companion)
        XCTAssertEqual(originBound.cursorPresentationForm, .companion)
        XCTAssertFalse(originBound.cursorAccessibilityValue.contains("Seed cursor"))
        originBound.observeQiMonJourney(projection(fixture.origin))
        assertFirstLightBodyAndMemoryAvatar(originBound)
        XCTAssertEqual(originBound.activeQiMon, nativeIdentity)
        for invalid in [projection(String(repeating: "b", count: 64)),
                        projection(fixture.origin, storage: .sessionOnly), projection(nil)] {
            originBound.observeQiMonJourney(invalid)
            XCTAssertNil(originBound.activeQiMon)
            XCTAssertEqual(originBound.presentationForm, .companion)
            XCTAssertEqual(originBound.cursorPresentationForm, .companion)
            XCTAssertFalse(originBound.cursorAccessibilityValue.contains("KIN"))
        }
        originBound.observeQiMonJourney(projection(fixture.origin))
        assertFirstLightBodyAndMemoryAvatar(originBound)
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), bytes)

        // A legacy appearance string without a personal record cannot recreate
        // KIN on either surface. Generic appearances still share their one form.
        let unnamed = try makeFixture(includeKin: false, form: .kin)
        defer { unnamed.clean() }
        XCTAssertNil(unnamed.store.activeQiMon)
        XCTAssertEqual(unnamed.store.presentationForm, .companion)
        XCTAssertEqual(unnamed.store.cursorPresentationForm, .companion)
        unnamed.store.preferences.form = .light
        XCTAssertEqual(unnamed.store.presentationForm, .light)
        XCTAssertEqual(unnamed.store.cursorPresentationForm, .light)
        XCTAssertEqual(unnamed.store.cursorAccessibilityValue, unnamed.store.assistantAccessibilityValue)

        // A well-formed growth archive for a different individual cannot put
        // either that body or a fabricated cursor identity onto the active KIN.
        let foreign = try makeFixture()
        defer { foreign.clean() }
        _ = try retainUse(in: foreign)
        let receipt = try XCTUnwrap(foreign.store.evolution.usefulReceipts.first)
        let candidate = try XCTUnwrap(foreign.store.evolution.proposeKinGrowth(
            originDigest: String(repeating: "d", count: 64), receipt: receipt))
        XCTAssertTrue(foreign.store.evolution.keepKinGrowth(candidate))
        XCTAssertEqual(foreign.store.presentationForm, .kinSeed)
        XCTAssertEqual(foreign.store.cursorPresentationForm, .kinSeed)
        XCTAssertEqual(foreign.store.activeQiMon?.originDigest, foreign.origin)
        XCTAssertEqual(fixture.client.calls + unnamed.client.calls + foreign.client.calls, 0)
        await foreign.store.shutdownAssistant()
        await unnamed.store.shutdownAssistant()
        await originBound.shutdownAssistant()
        await fixture.store.shutdownAssistant()
    }

    @MainActor
    func testActualLiveAndFloatingRenderersShareTheGrowingMemoryAvatarWhileBodyUnfolds() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        // The body milestone and reviewed memory support have distinct gates.
        // Connect the existing origin owner explicitly, as the development study
        // does; keeping a body alone must never claim bound memory experience.
        XCTAssertTrue(store.connectLiminalLearningStudy())
        XCTAssertEqual(store.evolution.practiceJourneyOriginDigest, fixture.origin)
        let initialDevelopment = try XCTUnwrap(store.liminalFormDevelopment(at: fixture.now))
        XCTAssertTrue(initialDevelopment.evidenceAvailable)
        XCTAssertEqual(initialDevelopment.reviewedApplicationCount, 0)
        let initialFiles = try fixture.files()
        let initialScene = try XCTUnwrap(store.companionParticleScene())
        XCTAssertEqual(initialScene.graph, store.memoryMapSnapshot())
        XCTAssertFalse(initialScene.field.edges.isEmpty, "The floating avatar must include the map's real connections")
        let cursorBefore = try render(LiveCompanionPresence(store: store, size: 128, role: .cursor))
        let floatingBefore = try render(FloatingCompanionBody(store: store).frame(width: 128, height: 154))
        let referenceBefore = try render(CompanionMemoryAvatar(scene: initialScene, size: 128,
            reduceMotion: true, expression: store.kinLightExpression))
        try save(cursorBefore, name: "cursor-before.png")
        try save(referenceBefore, name: "cursor-reference-before.png")
        assertSameAvatarPixels(cursorBefore, referenceBefore, "initial live cursor and current memory field")
        XCTAssertEqual(try fixture.files(), initialFiles, "Rendering does not retain experience")
        let identity = store.activeQiMon, position = store.position, preferences = store.preferences
        let placement = store.placementRevision
        _ = try keepGrowth(in: fixture)
        XCTAssertTrue(store.evolution.save(), "Only this explicit action persists reviewed growth")
        let retainedFiles = try fixture.files()
        let memory = try XCTUnwrap(store.companionParticleScene())
        let reviewedDevelopment = try XCTUnwrap(store.liminalFormDevelopment(at: fixture.now))
        XCTAssertTrue(reviewedDevelopment.evidenceAvailable)
        XCTAssertEqual(reviewedDevelopment.reviewedApplicationCount, 1,
            "Only the current, origin-bound reviewed lesson application supplies the satellite")
        XCTAssertEqual(memory.graph, store.memoryMapSnapshot())
        XCTAssertEqual(Set(memory.field.particles.map(\.nodeID)), Set(initialScene.field.particles.map(\.nodeID)),
            "A reviewed application decorates the same records; it does not manufacture memory nodes")
        XCTAssertNotEqual(memory.growthByRecordID, initialScene.growthByRecordID)
        let cursor = try render(LiveCompanionPresence(store: store, size: 128, role: .cursor))
        let body = try render(LiveCompanionPresence(store: store, size: 128))
        let floating = try render(FloatingCompanionBody(store: store).frame(width: 128, height: 154))
        let memoryReference = try render(CompanionMemoryAvatar(scene: memory, size: 128,
            reduceMotion: true, expression: store.kinLightExpression))
        let bodyReference = try render(CompanionPresenceArt(form: .kin, family: nil, size: 128, reduceMotion: true)
            .environment(\.companionParticleScene, memory))
        assertSameAvatarPixels(cursor, memoryReference, "live cursor and current Memory Map avatar")
        assertSamePixels(body, bodyReference, "live body and First Light")
        assertChangedPixels(cursorBefore, cursor, "Retained reviewed use must appear on the cursor's existing records")
        assertChangedPixels(floatingBefore, floating, "The actual floating host must show the same reviewed growth")
        assertChangedPixels(body, cursor, "The developed body remains available independently of its memory-avatar presentation")
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed, "Presentation does not migrate the saved identity or form")
        XCTAssertEqual(try fixture.files(), retainedFiles)

        let reopened = fixture.reopen()
        XCTAssertTrue(reopened.evolution.load())
        XCTAssertEqual(reopened.activeQiMon, identity)
        XCTAssertEqual(reopened.preferences, preferences)
        XCTAssertEqual(reopened.companionParticleScene(), memory)
        assertSameAvatarPixels(cursor, try render(LiveCompanionPresence(store: reopened, size: 128, role: .cursor)),
            "Reopening the same retained records preserves the memory avatar")
        XCTAssertEqual(try fixture.files(), retainedFiles, "Rendering and reopening cannot append another outcome")
        XCTAssertEqual(fixture.client.calls, 0)
        try save(cursor, name: "live-memory-avatar.png")
        try save(body, name: "live-first-light-body.png")
        try save(floating, name: "floating-memory-avatar.png")
        if ProcessInfo.processInfo.environment["ARCHI_KIN_CURSOR_RENDER_DIR"] != nil {
            let guide = VStack(spacing: 20) {
                Text("KIN · ONE CONTINUING COMPANION")
                    .font(.system(size: 15, weight: .medium, design: .rounded)).tracking(2)
                HStack(spacing: 40) {
                    VStack(spacing: 12) {
                        LiveCompanionPresence(store: store, size: 200, role: .cursor)
                        Text("Desktop cursor · Memory avatar")
                    }
                    VStack(spacing: 12) {
                        LiveCompanionPresence(store: store, size: 200, role: .body)
                        Text("Kept body · First Light")
                    }
                }
                Text("Shared identity, knowledge, light and activity")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Color(red: 0.94, green: 0.87, blue: 0.73))
            .padding(28).background(Color(red: 0.07, green: 0.065, blue: 0.08))
            try save(try render(guide), name: "kin-cursor-and-body.png")
        }
        await reopened.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor
    func testMemoryAvatarPreservesEquipmentAppReducedMotionAndQuietWithoutSaving() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store
        let scene = try XCTUnwrap(store.companionParticleScene())
        let files = try fixture.files(), identity = store.activeQiMon
        let position = store.position, placement = store.placementRevision
        let history = store.evolution.history
        let unequipped = try render(LiveCompanionPresence(store: store, size: 128, role: .cursor))
        let staff = CompanionEquipment(hand: .focusStaff)
        store.preferences.equipment = staff
        let equipped = try render(LiveCompanionPresence(store: store, size: 128, role: .cursor))
        let reference = try render(CompanionMemoryAvatar(scene: scene, size: 128, reduceMotion: true,
            equipment: staff, expression: store.kinLightExpression))
        assertSameAvatarPixels(equipped, reference, "The live network must retain the existing equipment renderer")
        assertChangedPixels(unequipped, equipped, "The staff must remain visible on the memory avatar")
        let baseline = try XCTUnwrap(NSBitmapImageRep(data: unequipped))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: equipped))
        XCTAssertEqual(bitmap.pixelsWide, baseline.pixelsWide)
        XCTAssertEqual(bitmap.pixelsHigh, baseline.pixelsHigh)
        XCTAssertTrue(bitmap.hasAlpha)
        for offset in 0..<bitmap.pixelsWide {
            for point in [(offset, 0), (offset, bitmap.pixelsHigh - 1), (0, offset), (bitmap.pixelsWide - 1, offset)] {
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)).alphaComponent,
                    try XCTUnwrap(baseline.colorAt(x: point.0, y: point.1)).alphaComponent,
                    "Equipment must not add pixels at the transparent frame edges")
            }
        }
        // The baseline above uses the app's Reduce Motion preference. The OS
        // setting is read-only in this SDK and remains a separate manual check.
        store.preferences.reduceMotion = false
        store.preferences.quiet = true
        assertSameAvatarPixels(equipped, try render(LiveCompanionPresence(store: store, size: 128, role: .cursor)),
            "Quiet uses the resting static network")
        XCTAssertEqual(store.companionParticleScene(), scene)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.client.calls, 0)
        await store.shutdownAssistant()
    }

    @MainActor
    func testCursorWithoutCurrentPersonalSceneKeepsAuthoredProfileFallback() async throws {
        let fixture = try makeFixture(includeKin: false, form: .light)
        defer { fixture.clean() }
        let store = fixture.store
        let files = try fixture.files(), preferences = store.preferences
        XCTAssertNil(store.activeQiMon)
        XCTAssertNil(store.companionParticleScene())
        let cursor = try render(LiveCompanionPresence(store: store, size: 128, role: .cursor))
        let reference = try render(CompanionPresenceArt(form: .light, family: nil, size: 128, reduceMotion: true,
            treatment: preferences.visualTreatment, equipment: preferences.equipment, seedColor: preferences.seedColor))
        assertSamePixels(cursor, reference, "A profile without a current personal scene keeps its existing authored fallback")
        let reopened = fixture.reopen()
        XCTAssertNil(reopened.companionParticleScene())
        assertSamePixels(cursor, try render(LiveCompanionPresence(store: reopened, size: 128, role: .cursor)),
            "Reopening the fallback cannot borrow another individual's network")
        XCTAssertEqual(reopened.preferences, preferences)
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.client.calls, 0)
        await reopened.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor
    func testExternalPreferenceChangeRetiresMemoryAvatarAndRefreshesNativeAccessibilityWithoutWriting() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store, panel = CompanionPanelController(store: fixture.store)
        defer { panel.window.close() }
        let content = try XCTUnwrap(panel.window.contentView)
        let identity = store.activeQiMon, preferences = store.preferences
        let frame = panel.window.frame, position = store.position, placement = store.placementRevision
        let before = try Data(contentsOf: fixture.preferenceURL)
        XCTAssertNotNil(store.companionParticleScene())
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)
        XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Memory avatar") == true)

        // Another writer changed a valid profile file without sending a store
        // publication. On-demand AX must recheck the same freshness gate as art.
        var externalPreferences = preferences
        externalPreferences.quiet.toggle()
        let externalDocument = NativePreferenceDocument(preferences: externalPreferences,
            lessons: store.keptLessons, qiMon: identity)
        let externalBytes = try externalDocument.encoded()
        XCTAssertNotEqual(externalBytes, before)
        try externalBytes.write(to: fixture.preferenceURL, options: .atomic)
        let externalFiles = try fixture.files()
        XCTAssertNil(store.companionParticleScene())
        let fallbackValue = try XCTUnwrap(content.accessibilityValue() as? String)
        XCTAssertEqual(fallbackValue, store.cursorAccessibilityValue)
        XCTAssertTrue(fallbackValue.contains("Seed cursor"))
        XCTAssertFalse(fallbackValue.contains("Memory avatar"))
        let cursor = try render(LiveCompanionPresence(store: store, size: 128, role: .cursor))
        let reference = try render(CompanionPresenceArt(form: .kinSeed, family: nil, size: 128, reduceMotion: true,
            treatment: preferences.visualTreatment, equipment: preferences.equipment,
            lightExpression: store.kinLightExpression, seedColor: preferences.seedColor))
        assertSamePixels(cursor, reference, "Stale records retire the network and retain this profile's authored fallback")
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.preferences, preferences, "A read does not silently adopt external settings")
        XCTAssertEqual(panel.window.frame, frame)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(try fixture.files(), externalFiles, "Readback and rendering must preserve the external writer's bytes")
        XCTAssertFalse(panel.window.isVisible)
        XCTAssertEqual(fixture.client.calls, 0)
        await store.shutdownAssistant()
    }

    @MainActor
    func testFloatingPanelSuspendsParticleAnimationWhenHiddenOrPresentedInHabitatWithoutChangingRecords() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let store = fixture.store, panel = CompanionPanelController(store: fixture.store)
        defer { panel.window.close() }
        let scene = try XCTUnwrap(store.companionParticleScene())
        let files = try fixture.files(), identity = store.activeQiMon
        let preferences = store.preferences, history = store.evolution.history
        let position = store.position, placement = store.placementRevision
        XCTAssertFalse(panel.particleAnimationVisible)
        XCTAssertFalse(panel.window.isVisible)
        panel.show()
        await Task.yield()
        XCTAssertTrue(panel.window.isVisible)
        XCTAssertTrue(store.isVisible)
        XCTAssertEqual(panel.particleAnimationVisible,
            panel.window.isOnActiveSpace && panel.window.occlusionState.contains(.visible),
            "Drawing resumes only when AppKit reports this actual window visible on the active space")
        panel.setPresentedInHabitat(true)
        XCTAssertFalse(panel.particleAnimationVisible)
        XCTAssertFalse(panel.window.isVisible)
        XCTAssertTrue(store.isVisible, "A surface handoff must preserve the user's show preference")
        panel.setPresentedInHabitat(false)
        await Task.yield()
        XCTAssertTrue(panel.window.isVisible)
        XCTAssertEqual(panel.particleAnimationVisible,
            panel.window.isOnActiveSpace && panel.window.occlusionState.contains(.visible))
        panel.hide()
        XCTAssertFalse(panel.particleAnimationVisible)
        XCTAssertFalse(panel.window.isVisible)
        XCTAssertFalse(store.isVisible)
        XCTAssertEqual(store.companionParticleScene(), scene)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.evolution.history, history)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(try fixture.files(), files)
        XCTAssertEqual(fixture.client.calls, 0)
        await store.shutdownAssistant()
    }

    @MainActor
    func testActualFloatingPanelAccessibilityTracksGrowthIncomingPreferencesAndActivityWithoutMoving() async throws {
        let activityClient = CursorActivityClient()
        let fixture = try makeFixture(assistant: activityClient)
        defer { fixture.clean() }
        let store = fixture.store, panel = CompanionPanelController(store: fixture.store)
        defer { panel.window.close() }
        let content = try XCTUnwrap(panel.window.contentView)
        let frame = panel.window.frame, position = store.position, placement = store.placementRevision
        let identity = store.activeQiMon, preferences = store.preferences
        let bytes = try Data(contentsOf: fixture.preferenceURL)
        XCTAssertFalse(panel.window.isVisible)
        XCTAssertFalse(panel.window.isKeyWindow)
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)
        XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Memory avatar") == true)
        _ = try keepGrowth(in: fixture)
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)
        XCTAssertFalse((content.accessibilityValue() as? String)?.contains("First Light") == true)
        XCTAssertTrue(store.assistantAccessibilityValue.contains("First Light"))
        XCTAssertTrue(store.evolution.save())
        store.returnKinToSeed()
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)
        XCTAssertTrue(store.evolution.load())
        assertFirstLightBodyAndMemoryAvatar(store)
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)

        // A @Published preference is delivered before storage is updated. AX
        // must use the supplied value immediately, not the previous equipment.
        store.preferences.equipment = CompanionEquipment(hand: .focusStaff)
        XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Focus Staff") == true)
        XCTAssertEqual(content.accessibilityValue() as? String, store.cursorAccessibilityValue)
        for expected in [AssistantActivity.ready, .failed, .stopped] {
            store.connectAssistant(provider: .qwen)
            try await waitUntil { store.connection(for: .qwen) == .ready }
            store.prompt = "Describe this synthetic cursor test."
            store.submit()
            try await waitUntil { activityClient.hasPending }
            XCTAssertEqual(store.assistantActivity, .working)
            try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
            XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Assistant: Working") == true)
            switch expected {
            case .ready:
                activityClient.emit("Synthetic completed answer.")
                XCTAssertEqual(store.assistantActivity, .responding)
                try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
                XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Assistant: Responding") == true)
                activityClient.finish()
            case .failed: activityClient.fail()
            default: store.cancelWork()
            }
            try await waitUntil { !store.isWorking && store.assistantActivity == expected }
            try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
            XCTAssertEqual(store.assistantActivity, expected)
            let value = try XCTUnwrap(content.accessibilityValue() as? String)
            XCTAssertTrue(value.contains("Assistant: " + expected.title))
            XCTAssertTrue(value.contains("Memory avatar"))
            XCTAssertFalse(value.contains("First Light"))
        }
        store.connectAssistant(provider: .qwen)
        try await waitUntil { store.connection(for: .qwen) == .ready }
        store.prompt = "Describe another synthetic cursor test."
        store.submit()
        try await waitUntil { activityClient.hasPending }
        activityClient.emit("Synthetic answer for a Quiet cue.")
        activityClient.finish()
        try await waitUntil { !store.isWorking && store.assistantActivity == .ready }
        try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
        let activeValue = try XCTUnwrap(content.accessibilityValue() as? String)
        store.preferences.quiet = true
        let quietValue = try XCTUnwrap(content.accessibilityValue() as? String)
        XCTAssertEqual(quietValue, store.cursorAccessibilityValue)
        XCTAssertNotEqual(quietValue, activeValue, "Quiet must immediately report the resting light")
        // A deliberate local route change clears results through the supported
        // owner; this does not connect or send to an external model.
        store.setAssistantRoute(.automatic)
        store.setAssistantRoute(.local)
        store.preferences = preferences
        try await waitUntil { (content.accessibilityValue() as? String) == store.cursorAccessibilityValue }
        XCTAssertTrue((content.accessibilityValue() as? String)?.contains("Assistant: Idle") == true)
        XCTAssertEqual(panel.window.frame, frame)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(try Data(contentsOf: fixture.preferenceURL), bytes)
        XCTAssertFalse(panel.window.isVisible)
        XCTAssertFalse(panel.window.isKeyWindow)
        XCTAssertEqual(fixture.client.calls, 0)
        XCTAssertEqual(activityClient.requests.count, 4, "Four in-process scripted requests; no model transport is present")
        await store.shutdownAssistant()
    }

    @MainActor private func assertFirstLightBodyAndMemoryAvatar(_ store: CompanionStore,
                                                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(store.presentationForm, .kin, file: file, line: line)
        XCTAssertEqual(store.cursorPresentationForm, .kinSeed, file: file, line: line)
        XCTAssertTrue(store.assistantAccessibilityValue.contains("First Light"), file: file, line: line)
        XCTAssertTrue(store.cursorAccessibilityValue.contains("Memory avatar"), file: file, line: line)
        XCTAssertTrue(store.cursorAccessibilityValue.contains("Connected memory particles"), file: file, line: line)
        XCTAssertFalse(store.cursorAccessibilityValue.contains("First Light"), file: file, line: line)
    }

    @MainActor private func makeFixture(includeKin: Bool = true, form: CompanionForm = .companion,
                                       assistant: (any AssistantClient)? = nil) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kin-cursor-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferenceURL = directory.appendingPathComponent("preferences.json")
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let origin = String(repeating: "a", count: 64)
        let lesson = KeptLesson(topic: "Writing plans", text: "Begin with one useful next step.", createdAt: now)
        var preferences = CompanionPreferences()
        preferences.form = form
        preferences.reduceMotion = true
        preferences.tone = "Warm"
        let kin = LocalQiMon(character: .kin, originDigest: origin, welcomedAt: now)
        try NativePreferenceDocument(preferences: preferences, lessons: [lesson], qiMon: includeKin ? kin : nil)
            .encoded().write(to: preferenceURL)
        let client = CursorNoCalls()
        let actualAssistant: any AssistantClient = assistant ?? client
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: actualAssistant,
            assistantFactory: { _, _ in actualAssistant }, wallClock: { now }, allowsPlay: false)
        store.placed(at: CGPoint(x: 500, y: 350))
        return Fixture(directory: directory, preferenceURL: preferenceURL, origin: origin, now: now,
            lesson: lesson, client: client, store: store)
    }

    @MainActor private func retainUse(in fixture: Fixture) throws -> UUID {
        let requestID = UUID(), snapshot = LessonSnapshot(lesson: fixture.lesson)
        let source = String(repeating: "b", count: 64)
        var receipt = AssistantLaneReceipt(requestID: requestID.uuidString, route: .local, provider: .qwen,
            context: fixture.store.contextTicket(), inputDigest: String(repeating: "c", count: 64),
            sourceDigest: source, inputContract: "native-assistant-input/v4", deadline: .distantFuture,
            modelIdentity: "synthetic-cursor-fixture", state: .complete)
        receipt.localLessons = [snapshot]
        receipt.usedLessonIDs = [snapshot.modelID]
        XCTAssertTrue(fixture.store.evolution.markUseful(receipt: receipt, sourceDigest: source, confirmedLesson: snapshot))
        return requestID
    }

    @MainActor @discardableResult private func keepGrowth(in fixture: Fixture) throws -> UUID {
        let requestID = try retainUse(in: fixture)
        XCTAssertTrue(fixture.store.previewKinGrowth(receiptID: requestID))
        XCTAssertTrue(fixture.store.keepKinGrowth())
        return requestID
    }

    private func projection(_ origin: String?, storage: HostedPlayProjection.Storage = .localBrowser) -> HostedPlayProjection {
        HostedPlayProjection(version: 3, host: "archi-desktop", sessionId: UUID().uuidString,
            sequence: 1, kind: "journey-projection", readiness: .ready, storage: storage, mode: .habitat,
            journeyId: "ARCHI-AAAAAAAA", revision: "synthetic-revision", eventCount: 0, visible: false,
            originDigest: origin, practices: [], arena: nil)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Native cursor accessibility did not reflect the existing store within its bounded delivery time")
    }

    private func assertSamePixels(_ first: Data, _ second: Data, _ reason: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        do {
            let comparison = try NaturalPresentationComparison.compare(first, second)
            XCTAssertTrue(comparison.withinAlphaPresentationBound, "\(reason): \(comparison.receipt)", file: file, line: line)
        } catch { XCTFail("\(reason): \(error)", file: file, line: line) }
    }

    /// Avatar references can differ by one interior alpha byte when the same
    /// Canvas is nested inside the native host. Compare visible color over one
    /// fixed black surface, while independently checking the original PNG frame
    /// and transparent border. Authored body art retains assertSamePixels above.
    private func assertSameAvatarPixels(_ first: Data, _ second: Data, _ reason: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        do {
            let a = try XCTUnwrap(NSBitmapImageRep(data: first)), b = try XCTUnwrap(NSBitmapImageRep(data: second))
            XCTAssertEqual(a.pixelsWide, b.pixelsWide, reason, file: file, line: line)
            XCTAssertEqual(a.pixelsHigh, b.pixelsHigh, reason, file: file, line: line)
            XCTAssertTrue(a.hasAlpha && b.hasAlpha, "\(reason): preserve the original transparent PNGs", file: file, line: line)
            guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return }
            let border = (0..<a.pixelsWide).flatMap { [($0, 0), ($0, a.pixelsHigh - 1)] }
                + (0..<a.pixelsHigh).flatMap { [(0, $0), (a.pixelsWide - 1, $0)] }
            for (x, y) in border {
                XCTAssertEqual(try XCTUnwrap(a.colorAt(x: x, y: y)).alphaComponent, 0,
                    "\(reason): original frame edge (\(x), \(y)) must stay transparent", file: file, line: line)
                XCTAssertEqual(try XCTUnwrap(b.colorAt(x: x, y: y)).alphaComponent, 0,
                    "\(reason): reference frame edge (\(x), \(y)) must stay transparent", file: file, line: line)
            }
            let comparison = try NaturalPresentationComparison.compare(overBlack(first), overBlack(second))
            XCTAssertTrue(comparison.withinAlphaPresentationBound,
                "\(reason), fixed black composite: \(comparison.receipt)", file: file, line: line)
        } catch { XCTFail("\(reason): \(error)", file: file, line: line) }
    }

    private func assertChangedPixels(_ first: Data, _ second: Data, _ reason: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        do {
            let comparison = try NaturalPresentationComparison.compare(overBlack(first), overBlack(second))
            XCTAssertTrue(comparison.dimensionsEqual, "\(reason): the frame must stay fixed", file: file, line: line)
            XCTAssertGreaterThan(comparison.maximumRGBDifference, 2,
                "\(reason): visible change must exceed the 2/255 raster allowance, not merely differ in alpha: \(comparison.receipt)",
                file: file, line: line)
        } catch { XCTFail("\(reason): \(error)", file: file, line: line) }
    }

    /// Decode at the original dimensions and composite without interpolation;
    /// this never replaces the transparent snapshots kept as diagnostic output.
    private func overBlack(_ data: Data) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let source = try XCTUnwrap(bitmap.cgImage)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: source.width, height: source.height,
            bitsPerComponent: 8, bytesPerRow: source.width * 4, space: space,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        let frame = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(frame)
        context.interpolationQuality = .none
        context.draw(source, in: frame)
        return try XCTUnwrap(NSBitmapImageRep(cgImage: XCTUnwrap(context.makeImage()))
            .representation(using: .png, properties: [:]))
    }

    @MainActor private func render<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private func save(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_KIN_CURSOR_RENDER_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
    }

    @MainActor private struct Fixture {
        let directory: URL
        let preferenceURL: URL
        let origin: String
        let now: Date
        let lesson: KeptLesson
        let client: CursorNoCalls
        let store: CompanionStore
        func reopen(allowsPlay: Bool = false) -> CompanionStore {
            CompanionStore(preferenceURL: preferenceURL, assistant: client,
                assistantFactory: { _, _ in client }, wallClock: { now }, allowsPlay: allowsPlay)
        }
        func files() throws -> [String: Data] {
            let entries = try XCTUnwrap(FileManager.default.enumerator(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]))
            var result: [String: Data] = [:]
            for case let file as URL in entries where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(directory.path.count))] = try Data(contentsOf: file)
            }
            return result
        }
        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
}

@MainActor private final class CursorNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        throw AssistantFailure.configuration
    }
    func disconnect() {}
}

/// Controls the real CompanionStore request lifecycle entirely in process.
/// There is no Ollama, Codex, network or other model invocation in this client.
@MainActor private final class CursorActivityClient: AssistantClient {
    private(set) var requests: [AssistantRequest] = []
    private var pending: CheckedContinuation<Void, Error>?
    private var onEvent: (@MainActor (AssistantEvent) -> Void)?
    var hasPending: Bool { pending != nil }
    func connect() async throws {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request)
        self.onEvent = onEvent
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func emit(_ text: String) { onEvent?(.text(text)) }
    func finish() {
        let continuation = pending
        pending = nil; onEvent = nil
        continuation?.resume()
    }
    func fail() {
        let continuation = pending
        pending = nil; onEvent = nil
        continuation?.resume(throwing: AssistantFailure.turnFailed)
    }
    func disconnect() {
        let continuation = pending
        pending = nil; onEvent = nil
        continuation?.resume(throwing: AssistantFailure.stopped)
    }
}
