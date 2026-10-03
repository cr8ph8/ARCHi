import AppKit
import SwiftUI
import XCTest
import simd
@testable import ARCHiDesktop

final class LiminalFormDevelopmentTests: XCTestCase {
    private let origin = String(repeating: "a", count: 64)
    private let now = Date(timeIntervalSince1970: 1_789_000_000)
    private func lesson(_ index: Int) -> KeptLesson {
        KeptLesson(topic: "Planning \(index)", text: "Remember distinct reviewed procedure number \(index).", createdAt: now.addingTimeInterval(-10))
    }
    private func receipt(_ lesson: KeptLesson, input: String = "b", id: UUID = UUID()) -> EvolutionUsefulReceipt {
        .init(requestID: id, sourceDigest: lesson.source?.digest,
              requestBinding: .init(inputDigest: String(repeating: input, count: 64), contextDigest: origin),
              lessonUse: EvolutionLessonUse.make(snapshot: .init(lesson: lesson)))
    }
    @MainActor private func build(_ lessons: [KeptLesson], _ receipts: [EvolutionUsefulReceipt] = [],
                                  currentIDs: Set<String>? = nil, bound: Bool = true,
                                  pages: [KnowledgePage] = []) -> LiminalFormDevelopment.Snapshot {
        LiminalFormDevelopment.build(originDigest: origin, lessons: lessons,
            currentLessonIDs: currentIDs ?? Set(lessons.map(\.id)), receipts: receipts,
            evidenceOrigin: bound ? origin : nil, now: now, currentKnowledgePages: pages)
    }
    private func page(_ body: String, id: String = UUID().uuidString, revision: UInt64 = 1,
                      state: KnowledgePageState = .reviewed,
                      relationship: RelationshipMemoryMetadata? = nil) -> KnowledgePage {
        let date = now.addingTimeInterval(-5)
        return KnowledgePage(id: id, revision: revision, title: "Reviewed record", body: body,
            kind: relationship == nil ? .concept : .claim,
            anchors: [.init(source: .init(id: UUID().uuidString, revision: 1, digest: origin),
                            location: 0, length: 1, quoteDigest: origin)],
            state: state, createdAt: date, updatedAt: date,
            review: state == .draft ? nil : .init(state: state, recordedAt: date), relationship: relationship)
    }

    @MainActor func testUsefulEvidenceRaisesDetailWithoutInventingNodesOrForcingForm() {
        let lessons = (0..<12).map(lesson)
        let keptOnly = build(lessons)
        XCTAssertEqual(keptOnly.nodes.count, 12)
        XCTAssertEqual(keptOnly.availableDetail, 1)
        for (count, expected) in [(2, 2), (3, 3), (6, 4)] {
            let snapshot = build(lessons, lessons.prefix(count).map { receipt($0) })
            XCTAssertEqual(snapshot.nodes.count, 12)
            XCTAssertEqual(snapshot.practicedNodes, count)
            XCTAssertEqual(snapshot.availableDetail, expected)
            for form in LiminalFormDevelopment.Form.allCases {
                let shape = LiminalFormDevelopment.structure(snapshot, form: form, requestedDetail: 99)
                XCTAssertEqual(shape.form, form)
                XCTAssertEqual(shape.detail, expected)
                XCTAssertLessThanOrEqual(shape.particles.count, 24 * 14)
                XCTAssertTrue(shape.particles.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
            }
        }
        let empty = build([])
        XCTAssertEqual(empty.availableDetail, 0)
        XCTAssertTrue(LiminalFormDevelopment.structure(empty, form: .beast, requestedDetail: 4).particles.isEmpty)
    }

    @MainActor func testDuplicateContentRepeatedInputAndConflictingRequestDoNotInflateGrowth() {
        let one = lesson(1)
        var duplicate = lesson(1)
        duplicate.text = "  REMEMBER   DISTINCT reviewed procedure number 1. \n"
        duplicate.taskScope = .conversation
        duplicate.topic = "Different title, same retained statement"
        let use = receipt(one)
        let copy = receipt(one)
        let snapshot = build([one, duplicate], [use, use, copy])
        XCTAssertEqual(snapshot.nodes.count, 1)
        XCTAssertEqual(snapshot.duplicateLessons, 1)
        XCTAssertEqual(snapshot.nodes[0].applications, 1)
        let conflict = receipt(one, input: "c", id: use.requestID)
        XCTAssertEqual(build([one], [use, conflict]).practicedNodes, 0)
        let strengthened = build([one], [use, receipt(one, input: "c"), receipt(one, input: "d")])
        XCTAssertEqual(strengthened.nodes[0].applications, 3)
        XCTAssertEqual(strengthened.nodes.count, 1)
        XCTAssertFalse(build([one], Array(repeating: use, count: 32) + [conflict]).evidenceAvailable)
        XCTAssertEqual(build([one], Array(repeating: use, count: 32) + [conflict]).practicedNodes, 0)
    }

    @MainActor func testRetainedSourceKnowledgeCanGainAndWithdrawReviewedExperienceOnTheSameNode() throws {
        var one = lesson(1)
        one.source = .init(name: "Retained research", digest: String(repeating: "e", count: 64))
        let original = one
        let retained = build([one])
        XCTAssertEqual(retained.nodes[0].evidenceState, .retainedKnowledge)
        XCTAssertEqual(retained.retainedOnlyNodes, 1)
        let reviewed = receipt(one)
        let wrongSource = EvolutionUsefulReceipt(requestID: UUID(), sourceDigest: nil,
            requestBinding: reviewed.requestBinding, lessonUse: reviewed.lessonUse)
        XCTAssertEqual(build([one], [wrongSource]).nodes[0].evidenceState, .retainedKnowledge,
                       "A source-bound lesson cannot claim use on another document or a source-free request")
        let practiced = build([one], [reviewed])
        XCTAssertEqual(practiced.nodes[0].id, retained.nodes[0].id)
        XCTAssertEqual(practiced.nodes[0].lessonIDs, retained.nodes[0].lessonIDs)
        XCTAssertEqual(practiced.nodes[0].evidenceState, .reviewedApplication)
        XCTAssertEqual(practiced.nodes[0].reviewedApplicationCount, 1)
        XCTAssertEqual(practiced.reviewedApplicationCount, 1)
        XCTAssertNotEqual(practiced.nodes[0].supportDigest, retained.nodes[0].supportDigest)
        XCTAssertEqual(build([one]), retained, "Withdrawal rebuilds retained knowledge without deleting it")
        XCTAssertEqual(one, original, "Presentation never edits the source lesson")
        one.revision += 1
        let corrected = build([one], [reviewed])
        XCTAssertEqual(corrected.nodes[0].id, retained.nodes[0].id)
        XCTAssertEqual(corrected.nodes[0].evidenceState, .retainedKnowledge)
        XCTAssertNotEqual(corrected.nodes[0].supportDigest, retained.nodes[0].supportDigest)
        XCTAssertEqual(build([one], [receipt(one)]).nodes[0].evidenceState, .reviewedApplication,
                       "A corrected record can acquire new experience against its current revision")
    }

    @MainActor func testLessonAcquisitionCannotBeItsOwnApplication() {
        var one = lesson(1)
        let acquisition = UUID()
        one.origin = .init(requestID: acquisition.uuidString.lowercased(), inputDigest: origin)
        let circularUse = receipt(one, id: acquisition)
        XCTAssertEqual(build([one], [circularUse]).practicedNodes, 0)
        let laterUse = receipt(one, input: "c")
        XCTAssertEqual(build([one], [circularUse, laterUse]).nodes[0].reviewedApplicationCount, 1)
    }

    @MainActor func testLaterExperienceRemainsVisibleAfterArtDampingLimitAndRebindsPresentation() throws {
        let one = lesson(1)
        let eight = (1...8).map { receipt(one, input: String($0, radix: 16)) }
        let before = build([one], eight)
        let after = build([one], eight + [receipt(one, input: "9")])
        XCTAssertEqual(before.nodes[0].applications, 8)
        XCTAssertEqual(after.nodes[0].applications, 8, "Existing motion bound stays finite")
        XCTAssertEqual(after.nodes[0].reviewedApplicationCount, 9, "Evidence is not truncated by a graphics cap")
        XCTAssertEqual(after.nodes[0].id, before.nodes[0].id)
        let session = UUID().uuidString
        let first = try XCTUnwrap(LiminalPointStructure.make(before, sessionID: session,
            manifestSHA256: origin, lowDetailIDs: Array(0..<64)))
        let next = try XCTUnwrap(LiminalPointStructure.make(after, sessionID: session,
            manifestSHA256: origin, lowDetailIDs: Array(0..<64)))
        XCTAssertEqual(first.nodes, next.nodes, "Reinforcement does not reshuffle art anchors")
        XCTAssertNotEqual(first.evidenceDigest, next.evidenceDigest)
        XCTAssertNotEqual(first.digest, next.digest)
    }

    @MainActor func testReplacingCurrentSupportAtSameCountInvalidatesOldPresentation() throws {
        let one = lesson(1)
        let firstUse = receipt(one)
        let otherUse = receipt(one, input: "c")
        let before = build([one], [firstUse])
        let after = build([one], [otherUse])
        XCTAssertEqual(before.nodes[0].applications, after.nodes[0].applications)
        XCTAssertNotEqual(before.nodes[0].supportDigest, after.nodes[0].supportDigest)
        XCTAssertEqual(build([one], [firstUse, firstUse]), before)
        XCTAssertEqual(build([one], [firstUse, receipt(one)]).reviewedApplicationCount, 1,
                       "Retrying the same input does not create another experience")
        let session = UUID().uuidString
        let first = try XCTUnwrap(LiminalPointStructure.make(before, sessionID: session,
            manifestSHA256: origin, lowDetailIDs: Array(0..<64)))
        let next = try XCTUnwrap(LiminalPointStructure.make(after, sessionID: session,
            manifestSHA256: origin, lowDetailIDs: Array(0..<64)))
        XCTAssertEqual(first.nodes, next.nodes)
        XCTAssertNotEqual(first.evidenceDigest, next.evidenceDigest)
    }

    @MainActor func testReviewedPagesAddBaseMemoriesAndCoalesceExactCopiesWithoutPracticeCredit() {
        let one = lesson(1)
        let concept = page("  " + one.text.uppercased() + "\n")
        let copy = page(one.text)
        let retained = build([], pages: [concept, copy])
        XCTAssertEqual(retained.nodes.count, 1)
        XCTAssertEqual(retained.duplicateKnowledgePages, 1)
        XCTAssertTrue(retained.nodes[0].lessonIDs.isEmpty)
        XCTAssertEqual(Set(retained.nodes[0].graphNodeIDs),
                       Set([KnowledgePageGraph.nodeID(concept.binding), KnowledgePageGraph.nodeID(copy.binding)]))
        XCTAssertEqual(retained.practicedNodes, 0)
        XCTAssertEqual(retained.availableDetail, 1)
        let combined = build([one], pages: [concept, copy])
        XCTAssertEqual(combined.nodes.count, 1)
        XCTAssertEqual(combined.nodes[0].id, retained.nodes[0].id)
        XCTAssertEqual(combined.nodes[0].graphNodeIDs.count, 3)
        XCTAssertEqual(combined.duplicateKnowledgePages, 2)
        let practiced = build([one], [receipt(one)], pages: [concept, copy])
        XCTAssertEqual(practiced.nodes[0].id, combined.nodes[0].id)
        XCTAssertEqual(practiced.reviewedApplicationCount, 1)
        XCTAssertNotEqual(practiced.nodes[0].supportDigest, combined.nodes[0].supportDigest)
        XCTAssertTrue(build([], pages: [page("Draft", state: .draft), page("Withdrawn", state: .withdrawn)]).nodes.isEmpty)
    }

    @MainActor func testTypedRelationshipRecordsKeepIdentityAndNeverBecomeApplicationReceipts() {
        let person = page("Same words", relationship: .init(kind: .person))
        let otherPerson = page("Same words", relationship: .init(kind: .person))
        let encounter = page("Same words", relationship: .init(kind: .encounter, person: person.binding))
        let commitment = page("Same words", relationship: .init(kind: .commitment,
            person: person.binding, commitmentStatus: .completed))
        let first = build([], pages: [person, otherPerson, encounter, commitment])
        XCTAssertEqual(first.nodes.count, 4)
        XCTAssertEqual(first.practicedNodes, 0, "User-reported completion is not an observed application receipt")
        XCTAssertEqual(first.reviewedApplicationCount, 0)
        let revisedPerson = page("Corrected words", id: person.id, revision: 2, relationship: .init(kind: .person))
        let before = build([], pages: [person])
        let after = build([], pages: [revisedPerson])
        XCTAssertEqual(before.nodes[0].id, after.nodes[0].id)
        XCTAssertNotEqual(before.nodes[0].graphNodeIDs, after.nodes[0].graphNodeIDs)
        XCTAssertNotEqual(before.nodes[0].supportDigest, after.nodes[0].supportDigest)
        XCTAssertTrue(build([], pages: [person, person]).nodes.isEmpty, "Caller must supply unique current heads")
    }

    @MainActor func testSourceOwnerCorrectionWithdrawalAndRestartControlProjectedKnowledgePages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("memory-page-development-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sources.json")
        let library = ReadingSourceLibrary(url: url)
        let source = try library.keep(title: "Evidence", text: "An original source passage.")
        let anchor = try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: 11))
        func projection(_ owner: ReadingSourceLibrary) -> LiminalFormDevelopment.Snapshot {
            LiminalFormDevelopment.build(originDigest: origin, lessons: [], currentLessonIDs: [],
                receipts: [], evidenceOrigin: origin, now: Date().addingTimeInterval(1),
                currentKnowledgePages: owner.latestKnowledgePages.filter { owner.availability(of: $0) == nil })
        }
        XCTAssertTrue(projection(library).nodes.isEmpty, "A kept raw source does not create a semantic memory node")
        let draft = try library.saveKnowledgePage(title: "Concept", body: "An explicitly reviewed concept.", kind: .concept, anchors: [anchor])
        XCTAssertTrue(projection(library).nodes.isEmpty)
        let reviewed = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let saved = projection(library)
        XCTAssertEqual(saved.nodes.count, 1)
        XCTAssertEqual(saved, projection(ReadingSourceLibrary(url: url)))
        _ = try library.withdrawKnowledgePage(id: reviewed.id, expectedRevision: reviewed.revision)
        XCTAssertTrue(projection(library).nodes.isEmpty)
        let replacement = try library.saveKnowledgePage(title: "New concept", body: "Another reviewed concept.", kind: .concept, anchors: [anchor])
        _ = try library.reviewKnowledgePage(id: replacement.id, expectedRevision: replacement.revision)
        XCTAssertEqual(projection(library).nodes.count, 1)
        _ = try library.replace(id: source.id, title: "Corrected source", text: "Changed source passage.")
        XCTAssertTrue(projection(library).nodes.isEmpty)
        XCTAssertTrue(projection(ReadingSourceLibrary(url: url)).nodes.isEmpty)
    }

    @MainActor func testCorrectionExpiryUnavailableSourceAndUnboundHistoryRemoveOnlyCurrentSupport() {
        var one = lesson(1)
        let old = receipt(one)
        XCTAssertEqual(build([one], [old]).practicedNodes, 1)
        XCTAssertEqual(build([one], [old], bound: false).practicedNodes, 0)
        XCTAssertEqual(build([one], [.init(requestID: UUID(), sourceDigest: origin, lessonUse: old.lessonUse)]).practicedNodes, 0)
        one.revision += 1
        XCTAssertEqual(build([one], [old]).practicedNodes, 0)
        XCTAssertEqual(build([one], [old]).nodes.count, 1)
        XCTAssertEqual(build([one], [old], currentIDs: []).nodes.count, 0)
        one.expiresAt = now
        XCTAssertEqual(build([one], [old]).unavailableLessons, 1)
        let shape = LiminalFormDevelopment.structure(build([one], [old]), form: .beast, requestedDetail: 4)
        XCTAssertEqual(shape.form, .beast)
        XCTAssertEqual(shape.core, SIMD2(0.38, 0.53))
    }

    @MainActor func testDeterministicNodePositionsAndPhysicsDoNotDependOnFrameCountOrPixels() throws {
        let lessons = (0..<6).map(lesson)
        let receipts = lessons.prefix(3).map { receipt($0) }
        let snapshot = build(lessons, receipts)
        XCTAssertEqual(snapshot, build(lessons.reversed(), receipts.reversed()))
        for form in LiminalFormDevelopment.Form.allCases {
            let shape = LiminalFormDevelopment.structure(snapshot, form: form, requestedDetail: 3)
            let particle = try XCTUnwrap(shape.particles.first)
            var lastDistance = Double.infinity
            for t in stride(from: 0.0, through: 3, by: 1.0 / 120) {
                let p = LiminalFormDevelopment.displaced(particle, elapsed: t, reducedMotion: false, stopped: false)
                let distance = simd_length(p - particle.position)
                XCTAssertLessThanOrEqual(distance, 0.035000001)
                XCTAssertLessThanOrEqual(distance, lastDistance + 1e-12)
                lastDistance = distance
            }
            XCTAssertLessThan(lastDistance, 0.000001)
            for bad in [Double.nan, .infinity, -.infinity, -1] {
                XCTAssertEqual(LiminalFormDevelopment.displaced(particle, elapsed: bad, reducedMotion: false, stopped: false), particle.position)
            }
            XCTAssertEqual(LiminalFormDevelopment.displaced(particle, elapsed: 0, reducedMotion: true, stopped: false), particle.position)
            XCTAssertEqual(LiminalFormDevelopment.displaced(particle, elapsed: 0, reducedMotion: false, stopped: true), particle.position)
            let morePractice = LiminalFormDevelopment.Particle(id: particle.id, nodeID: particle.nodeID, position: particle.position, applications: 8)
            let novice = LiminalFormDevelopment.Particle(id: particle.id, nodeID: particle.nodeID, position: particle.position, applications: 0)
            XCTAssertLessThan(simd_length(LiminalFormDevelopment.displaced(morePractice, elapsed: 0.4, reducedMotion: false, stopped: false) - particle.position),
                              simd_length(LiminalFormDevelopment.displaced(novice, elapsed: 0.4, reducedMotion: false, stopped: false) - particle.position))
        }
    }

    @MainActor func testInvalidInputsFailClosedAndDetailBudgetDoesNotInventRecords() {
        let one = lesson(1)
        XCTAssertTrue(build([one, one]).nodes.isEmpty)
        XCTAssertTrue(build((0..<65).map(lesson)).nodes.isEmpty)
        let snapshot = build((0..<32).map(lesson))
        XCTAssertEqual(snapshot.nodes.count, 32)
        XCTAssertEqual(snapshot.visibleNodes.count, 24)
        XCTAssertEqual(snapshot.hiddenNodes, 8)
        XCTAssertTrue(LiminalFormDevelopment.structure(snapshot, form: .ball, requestedDetail: -1).particles.isEmpty)
    }

    @MainActor func testCurrentStoreProjectionSurvivesExplicitSaveLoadAndPreservesBodyAndFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liminal-development-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let lessons = (0..<6).map(lesson)
        let individual = LocalQiMon(character: .hampton, originDigest: origin, welcomedAt: now)
        let baseline = try NativePreferenceDocument(lessons: lessons, qiMon: individual).encoded()
        try baseline.write(to: url)
        let client = LiminalDevelopmentNoCalls()
        func store() -> CompanionStore {
            CompanionStore(preferenceURL: url, assistant: client, assistantFactory: { _, _ in client }, wallClock: { self.now }, allowsPlay: false)
        }
        let current = store()
        current.preferences.liminalPointProgress = LiminalV008Runtime.standingProgress
        XCTAssertTrue(current.connectLiminalLearningStudy())
        for lesson in lessons.prefix(3) {
            var use = AssistantLaneReceipt(requestID: UUID().uuidString, route: .local, provider: .qwen,
                context: current.contextTicket(), inputDigest: origin, sourceDigest: nil,
                inputContract: "native-assistant-input/v4", deadline: now.addingTimeInterval(60),
                modelIdentity: "synthetic-fixture", state: .complete)
            let snapshot = LessonSnapshot(lesson: lesson)
            use.localLessons = [snapshot]; use.usedLessonIDs = [snapshot.modelID]
            XCTAssertTrue(current.evolution.markUseful(receipt: use, sourceDigest: nil, confirmedLesson: snapshot))
        }
        let projection = try XCTUnwrap(current.liminalFormDevelopment(at: now))
        XCTAssertEqual(projection.availableDetail, 3)
        if let output = ProcessInfo.processInfo.environment["ARCHI_LIMINAL_DEVELOPMENT_RENDER_DIR"] {
            let view = LiminalDevelopmentCard(store: current, evolution: current.evolution)
                .frame(width: 596).fixedSize(horizontal: false, vertical: true).preferredColorScheme(.dark)
            let hosting = NSHostingView(rootView: view)
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 596, height: 1400),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.contentView = hosting
            defer { panel.contentView = nil; panel.close() }
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let height = hosting.fittingSize.height
            XCTAssertGreaterThan(height, 300); XCTAssertLessThan(height, 1400)
            panel.setContentSize(CGSize(width: 596, height: height)); hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let target = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: target.appendingPathComponent("native-card.png"))
            XCTAssertFalse(panel.isVisible)
        }
        XCTAssertTrue(current.evolution.save())
        let savedEvolution = try Data(contentsOf: directory.appendingPathComponent("preferences.evolution.json"))
        let revision = current.evolution.revision
        for _ in 0..<120 {
            XCTAssertEqual(current.liminalFormDevelopment(at: now), projection)
            _ = LiminalFormDevelopment.structure(projection, form: .beast, requestedDetail: 4)
        }
        XCTAssertEqual(current.evolution.revision, revision)
        XCTAssertEqual(current.preferences.liminalPointProgress, LiminalV008Runtime.standingProgress)
        XCTAssertEqual(current.activeQiMon, individual)
        XCTAssertEqual(try Data(contentsOf: url), baseline)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("preferences.evolution.json")), savedEvolution)
        let reopened = store()
        XCTAssertTrue(reopened.evolution.load(), reopened.evolution.status)
        XCTAssertEqual(reopened.liminalFormDevelopment(at: now), projection)
        let stewardURL = url.deletingPathExtension().appendingPathExtension("steward.json")
        try Data("unreadable external feedback".utf8).write(to: stewardURL)
        let held = try XCTUnwrap(reopened.liminalFormDevelopment(at: now))
        XCTAssertEqual(held.nodes.count, projection.nodes.count)
        XCTAssertFalse(held.evidenceAvailable)
        XCTAssertEqual(held.practicedNodes, 0)
        XCTAssertFalse(reopened.connectLiminalLearningStudy())
        XCTAssertEqual(reopened.evolution.usefulReceipts.count, 3, "Read-only freshness cannot withdraw or persist receipts")
        current.evolution.observeJourneyOrigin(String(repeating: "d", count: 64))
        XCTAssertNil(current.liminalFormDevelopment(at: now))
        try Data("external edit".utf8).write(to: url)
        XCTAssertNil(reopened.liminalFormDevelopment(at: now))
        XCTAssertEqual(client.calls, 0)
        await current.shutdownAssistant(); await reopened.shutdownAssistant()
    }

    @MainActor func testDirectSharedSourceChangeMakesSupportUnavailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liminal-source-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        var one = lesson(1)
        one.source = .init(name: "Original", digest: LessonSource.digest(of: "Original copy"))
        try NativePreferenceDocument(lessons: [one], qiMon: .init(character: .hampton, originDigest: origin, welcomedAt: now)).encoded().write(to: url)
        let client = LiminalDevelopmentNoCalls()
        let store = CompanionStore(preferenceURL: url, assistant: client, assistantFactory: { _, _ in client }, wallClock: { self.now }, allowsPlay: false)
        XCTAssertNotNil(store.currentKeptLesson(matching: .init(lesson: one)))
        XCTAssertEqual(store.liminalFormDevelopment(at: now)?.nodes.count, 0)
        XCTAssertEqual(store.liminalFormDevelopment(at: now)?.unavailableLessons, 1)
        await store.shutdownAssistant()
    }

    @MainActor func testStructureStudyRendersAtNativeSizes() throws {
        let lessons = (0..<12).map(lesson)
        let snapshot = build(lessons, lessons.prefix(6).map { receipt($0) })
        for form in LiminalFormDevelopment.Form.allCases {
            let shape = LiminalFormDevelopment.structure(snapshot, form: form, requestedDetail: 4)
            let drawing = LiminalStructureDrawing(structure: shape, elapsed: 0, reducedMotion: true, stopped: true)
                .frame(width: 640, height: 360).background(Color(red: 0.025, green: 0.019, blue: 0.028))
            let renderer = ImageRenderer(content: drawing)
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size, NSSize(width: 640, height: 360))
            if let output = ProcessInfo.processInfo.environment["ARCHI_LIMINAL_DEVELOPMENT_RENDER_DIR"] {
                let target = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let data = try XCTUnwrap(image.tiffRepresentation)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: target.appendingPathComponent(form.rawValue + ".png"))
                let exported = try LiminalFormDevelopment.export(snapshot, form: form, requestedDetail: 4, synthetic: true)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
                XCTAssertEqual(json["retainedNodeCount"] as? Int, 12)
                XCTAssertEqual(json["representedNodeCount"] as? Int, 12)
                XCTAssertEqual(json["synthetic"] as? Bool, true)
                XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains(lessons[0].text))
                XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains(lessons[0].topic))
                try exported.write(to: target.appendingPathComponent(form.rawValue + ".json"))
            }
        }
    }
}

@MainActor private final class LiminalDevelopmentNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
}
