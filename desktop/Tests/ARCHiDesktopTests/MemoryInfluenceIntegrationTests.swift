import Foundation
import XCTest
@testable import ARCHiDesktop

/// Real preference/source/method owners with disposable synthetic data. These
/// checks never invoke a provider, inspect a personal profile or execute a method.
@MainActor
final class MemoryInfluenceIntegrationTests: XCTestCase {
    func testExplicitAssessmentPersistsWithSourceIntactAndReloadDoesNotWrite() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let original = try fixture.keepLesson()
        let snapshot = LessonSnapshot(lesson: original)
        let beforeRevision = fixture.store.lessonRevision
        XCTAssertTrue(fixture.store.memoryInfluences.isEmpty)

        XCTAssertTrue(fixture.assess(original, for: fixture.first, polarity: -1))
        let updated = try XCTUnwrap(fixture.store.keptLessons.first)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.text, original.text)
        XCTAssertEqual(updated.topic, original.topic)
        XCTAssertEqual(updated.reason, original.reason)
        XCTAssertEqual(updated.source, original.source)
        XCTAssertEqual(updated.origin, original.origin)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.revision, original.revision)
        XCTAssertEqual(updated.updatedAt, original.updatedAt)
        XCTAssertEqual(fixture.store.lessonRevision, beforeRevision + 1)
        XCTAssertEqual(fixture.store.currentKeptLesson(matching: snapshot), original,
                       "An influence annotation must preserve the source memory's immutable version.")
        XCTAssertEqual(fixture.store.memoryInfluences.count, 1)

        let saved = try Data(contentsOf: fixture.preference)
        let reopened = fixture.makeStore(); defer { reopened.disconnectAssistant() }
        XCTAssertEqual(reopened.keptLessons, [updated])
        XCTAssertEqual(reopened.memoryInfluences, fixture.store.memoryInfluences)
        XCTAssertEqual(try Data(contentsOf: fixture.preference), saved, "Opening must not rewrite the archive.")
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testPolarityReversalReranksEqualMethodsAndKeepsCautionRetrievable() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        XCTAssertEqual(fixture.store.orderedDocumentProcedures.map(\.id), [fixture.first.id, fixture.second.id])

        XCTAssertTrue(fixture.assess(lesson, for: fixture.first, polarity: -1))
        let negative = try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(fixture.first))
        XCTAssertLessThan(negative.influence, 0)
        XCTAssertEqual(fixture.store.orderedDocumentProcedures.map(\.id), [fixture.second.id, fixture.first.id])
        let retrievedNegative = fixture.store.matchingLessons(question: fixture.store.prompt, taskScope: .passageRevision)
        XCTAssertEqual(retrievedNegative.map(\.id), [lesson.id], "A caution remains available to retrieval.")

        let current = try XCTUnwrap(fixture.store.keptLessons.first)
        XCTAssertTrue(fixture.assess(current, for: fixture.first, polarity: 1))
        let positive = try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(fixture.first))
        XCTAssertEqual(positive.influence, -negative.influence, accuracy: 1e-12)
        XCTAssertEqual(positive.totalWeight, negative.totalWeight, accuracy: 1e-12)
        XCTAssertEqual(fixture.store.orderedDocumentProcedures.map(\.id), [fixture.first.id, fixture.second.id])
        XCTAssertEqual(fixture.store.matchingLessons(question: fixture.store.prompt, taskScope: .passageRevision).map(\.id),
                       retrievedNegative.map(\.id))
        XCTAssertNil(fixture.store.preparedDocumentProcedure, "Ranking cannot select or execute a method.")
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testZeroConfidenceAndMagnitudeRemoveInfluenceWithoutHidingMemory() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        var lesson = try fixture.keepLesson()
        for pair in [(confidence: 0.0, magnitude: 1.0), (confidence: 1.0, magnitude: 0.0)] {
            XCTAssertTrue(fixture.assess(lesson, for: fixture.first, polarity: -1,
                                         magnitude: pair.magnitude, confidence: pair.confidence))
            let evaluation = try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(fixture.first))
            XCTAssertEqual(evaluation.influence, 0)
            XCTAssertEqual(evaluation.totalWeight, 0)
            XCTAssertEqual(fixture.store.matchingLessons(question: fixture.store.prompt, taskScope: .passageRevision).map(\.id), [lesson.id])
            lesson = try XCTUnwrap(fixture.store.keptLessons.first)
        }
    }

    func testNeutralAndUnassessedHaveDifferentEvidenceMass() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        XCTAssertTrue(fixture.assess(lesson, for: fixture.first, polarity: nil))
        let unassessed = try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(fixture.first))
        XCTAssertEqual(unassessed.influence, 0)
        XCTAssertEqual(unassessed.totalWeight, 0)
        XCTAssertTrue(fixture.assess(try XCTUnwrap(fixture.store.keptLessons.first), for: fixture.first, polarity: 0))
        let neutral = try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(fixture.first))
        XCTAssertEqual(neutral.influence, 0)
        XCTAssertGreaterThan(neutral.neutralMass, 0)
        XCTAssertEqual(neutral.totalWeight, neutral.neutralMass, accuracy: 1e-12)
    }

    func testIndependentTargetsAndExplicitRemovalPreserveOtherAssessment() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        XCTAssertTrue(fixture.assess(lesson, for: fixture.first, polarity: -1))
        XCTAssertTrue(fixture.assess(try XCTUnwrap(fixture.store.keptLessons.first), for: fixture.second, polarity: 1))
        let first = try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(fixture.first))
        let second = try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(fixture.second))
        XCTAssertLessThan(first.influence, 0)
        XCTAssertGreaterThan(second.influence, 0)

        let current = try XCTUnwrap(fixture.store.keptLessons.first)
        XCTAssertTrue(fixture.store.updateLessonMemoryInfluence(lesson: LessonSnapshot(lesson: current),
            expectedRevision: fixture.store.lessonRevision, procedure: fixture.first.binding, assessment: nil))
        XCTAssertEqual(fixture.store.memoryInfluences.count, 1)
        XCTAssertEqual(fixture.store.documentMethodMemoryInfluence(fixture.first)?.influence ?? 0, 0)
        XCTAssertEqual(try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(fixture.second)).influence,
                       second.influence, accuracy: 1e-12)
    }

    func testWrongScopeTargetAndStaleSnapshotCannotMutateTheArchive() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let original = try fixture.keepLesson()
        XCTAssertTrue(fixture.assess(original, for: fixture.first, polarity: -1))
        let current = try XCTUnwrap(fixture.store.keptLessons.first)
        let bytes = try Data(contentsOf: fixture.preference)
        let wrongScope = ContextualMemoryInfluence.Assessment(scope: "qimon.encounter", targetID: LessonMemoryInfluence.targetID(for: fixture.first.binding),
            polarity: .init(rawValue: 1), magnitude: 1, confidence: 1, retrievalSalience: 1)
        let wrongTarget = ContextualMemoryInfluence.Assessment(scope: LessonMemoryInfluence.scope, targetID: LessonMemoryInfluence.targetID(for: fixture.second.binding),
            polarity: .init(rawValue: 1), magnitude: 1, confidence: 1, retrievalSalience: 1)
        for assessment in [wrongScope, wrongTarget] {
            XCTAssertFalse(fixture.store.updateLessonMemoryInfluence(lesson: LessonSnapshot(lesson: current),
                expectedRevision: fixture.store.lessonRevision, procedure: fixture.first.binding, assessment: assessment))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.preference), bytes)
        fixture.store.beginLessonCorrection(revisingID: original.id)
        var draft = try XCTUnwrap(fixture.store.lessonDraft)
        draft.text = "A revised synthetic source is a different memory version."
        XCTAssertTrue(fixture.store.keepLesson(draft))
        let revisedBytes = try Data(contentsOf: fixture.preference)
        XCTAssertFalse(fixture.store.updateLessonMemoryInfluence(lesson: LessonSnapshot(lesson: original),
            expectedRevision: fixture.store.lessonRevision, procedure: fixture.first.binding,
            assessment: fixture.assessment(for: fixture.first, polarity: 1)))
        XCTAssertEqual(fixture.store.documentMethodMemoryInfluence(fixture.first)?.influence ?? 0, 0,
                       "A new source version cannot inherit an old assessment.")
        XCTAssertEqual(try Data(contentsOf: fixture.preference), revisedBytes)
    }

    func testIdenticalAssessmentIsIdempotentWithSeveralTargets() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        XCTAssertTrue(fixture.assess(lesson, for: fixture.first, polarity: -1))
        XCTAssertTrue(fixture.assess(try XCTUnwrap(fixture.store.keptLessons.first), for: fixture.second, polarity: 1))
        let current = try XCTUnwrap(fixture.store.keptLessons.first)
        let revision = fixture.store.lessonRevision
        let bytes = try Data(contentsOf: fixture.preference)
        XCTAssertTrue(fixture.assess(current, for: fixture.first, polarity: -1))
        XCTAssertEqual(fixture.store.keptLessons, [current])
        XCTAssertEqual(fixture.store.lessonRevision, revision)
        XCTAssertEqual(try Data(contentsOf: fixture.preference), bytes,
                       "An unchanged relation cannot create a new revision just by moving within an array.")
    }

    func testExternalWriterBlocksStaleAssessmentWithoutOverwriting() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        let stale = fixture.makeStore(); defer { stale.disconnectAssistant() }
        XCTAssertTrue(fixture.assess(lesson, for: fixture.first, polarity: -1))
        let admitted = try Data(contentsOf: fixture.preference)
        XCTAssertFalse(stale.updateLessonMemoryInfluence(lesson: LessonSnapshot(lesson: lesson),
            expectedRevision: stale.lessonRevision, procedure: fixture.first.binding,
            assessment: fixture.assessment(for: fixture.first, polarity: 1)))
        XCTAssertEqual(try Data(contentsOf: fixture.preference), admitted)
        XCTAssertEqual(stale.documentMethodMemoryInfluence(fixture.first)?.influence ?? 0, 0)
    }

    func testExpiredAndWithdrawnMemoriesCannotContribute() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let expiring = try fixture.keepLesson(expiresAt: fixture.clock.now.addingTimeInterval(60))
        XCTAssertTrue(fixture.assess(expiring, for: fixture.first, polarity: 1))
        XCTAssertGreaterThan(try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(fixture.first)).influence, 0)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(60)
        XCTAssertEqual(fixture.store.documentMethodMemoryInfluence(fixture.first)?.influence ?? 0, 0)
        XCTAssertEqual(fixture.store.keptLessons.count, 1, "Expiry retains inspectable history.")
        XCTAssertTrue(fixture.store.matchingLessons(question: fixture.store.prompt, taskScope: .passageRevision).isEmpty)
        let expired = try XCTUnwrap(fixture.store.keptLessons.first)
        XCTAssertTrue(fixture.store.withdrawLesson(id: expired.id, expectedRevision: fixture.store.lessonRevision))
        XCTAssertTrue(fixture.store.keptLessons.isEmpty)
        let reopened = fixture.makeStore(); defer { reopened.disconnectAssistant() }
        XCTAssertTrue(reopened.keptLessons.isEmpty, "Metadata cannot resurrect withdrawn memory text.")
    }

    func testChangedSourceAndWithdrawnTargetCannotBePromotedByAttraction() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        XCTAssertTrue(fixture.assess(lesson, for: fixture.first, polarity: 1))
        try fixture.store.documentProcedures.withdraw(binding: fixture.first.binding)
        let withdrawn = try XCTUnwrap(fixture.store.documentProcedures.procedure(matching: fixture.first.binding))
        XCTAssertNil(fixture.store.documentMethodMemoryInfluence(withdrawn))
        XCTAssertEqual(fixture.store.orderedDocumentProcedures.first?.id, fixture.second.id)
        XCTAssertNotNil(fixture.store.documentProcedureUnavailable(withdrawn.binding))

        XCTAssertTrue(fixture.assess(try XCTUnwrap(fixture.store.keptLessons.first), for: fixture.second, polarity: 1))
        _ = try fixture.store.readingSources.replace(id: fixture.source.id, title: fixture.source.title,
                                                     text: "Changed synthetic source; the previous concept requires review.")
        XCTAssertNil(fixture.store.documentMethodMemoryInfluence(fixture.second))
        XCTAssertNotNil(fixture.store.documentProcedureUnavailable(fixture.second.binding))
        XCTAssertEqual(fixture.store.keptLessons.first?.text, lesson.text)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testAssessmentDoesNotInvalidateMethodDerivedFromTheSameMemory() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        let method = try fixture.methodDerivedFrom(lesson)
        let snapshot = LessonSnapshot(lesson: lesson)
        let binding = try XCTUnwrap(EvolutionLessonUse.make(snapshot: snapshot))
        XCTAssertNil(fixture.store.documentProcedureUnavailable(method.binding))
        XCTAssertTrue(fixture.assess(lesson, for: method, polarity: -1))
        XCTAssertEqual(fixture.store.keptLessons, [lesson])
        XCTAssertEqual(EvolutionLessonUse.make(snapshot: LessonSnapshot(lesson: try XCTUnwrap(fixture.store.keptLessons.first))), binding)
        XCTAssertNil(fixture.store.documentProcedureUnavailable(method.binding),
                     "Changing an advisory relationship cannot withdraw its underlying source dependency.")
        XCTAssertLessThan(try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(method)).influence, 0)
        XCTAssertTrue(fixture.assess(lesson, for: method, polarity: 1))
        XCTAssertNil(fixture.store.documentProcedureUnavailable(method.binding))
        XCTAssertGreaterThan(try XCTUnwrap(fixture.store.documentMethodMemoryInfluence(method)).influence, 0)
    }

    func testNoAssessmentOrInspectionCreatesPersistentInfluence() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        let bytes = try Data(contentsOf: fixture.preference)
        for _ in 0..<3 {
            _ = fixture.store.orderedDocumentProcedures
            _ = fixture.store.documentMethodMemoryInfluence(fixture.first)
            _ = fixture.store.matchingLessons(question: fixture.store.prompt, taskScope: .passageRevision)
        }
        XCTAssertEqual(fixture.store.keptLessons, [lesson])
        XCTAssertTrue(fixture.store.memoryInfluences.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.preference), bytes)
        XCTAssertNil(fixture.store.preparedDocumentProcedure)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testSelectiveForgetExportAndProfileRecoveryPreserveTheSameRelationship() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        XCTAssertTrue(fixture.assess(lesson, for: fixture.first, polarity: -1))
        let relationships = fixture.store.memoryInfluences
        fixture.store.rememberPreferences = true
        fixture.store.savePreferences()
        fixture.store.forgetPreferences()
        XCTAssertEqual(fixture.store.memoryInfluences, relationships)
        XCTAssertEqual(fixture.store.keptLessons, [lesson])
        let exported = try NativePreferenceDocument.decode(fixture.store.lessonExportData())
        XCTAssertNil(exported.preferences)
        XCTAssertNil(exported.personalContext)
        XCTAssertEqual(exported.memoryInfluences, relationships)
        XCTAssertEqual(exported.lessons, [lesson])

        let original = try Data(contentsOf: fixture.preference)
        let archive = fixture.directory.appendingPathComponent("synthetic.archibackup")
        let restoredURL = fixture.directory.appendingPathComponent("restored/preferences.json")
        try FileManager.default.createDirectory(at: restoredURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.preference, archiveURL: archive)
        let preview = try DesktopProfileBackup.preview(archiveURL: archive, profile: .custom, preferenceURL: restoredURL)
        _ = try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.directory.appendingPathComponent("rollbacks"))
        XCTAssertEqual(try Data(contentsOf: restoredURL), original)
        let restored = CompanionStore(preferenceURL: restoredURL, assistant: fixture.client,
            wallClock: { fixture.clock.now }, allowsPlay: false)
        defer { restored.disconnectAssistant() }
        restored.prompt = fixture.store.prompt
        XCTAssertEqual(restored.memoryInfluences, relationships)
        XCTAssertEqual(restored.keptLessons, [lesson])
        XCTAssertEqual(restored.documentMethodMemoryInfluence(fixture.first)?.influence,
                       fixture.store.documentMethodMemoryInfluence(fixture.first)?.influence)
        XCTAssertEqual(fixture.client.calls, 0)
    }

    func testLegacyEnvelopeAndSnapshotKeepTheirOriginalBytesUntilExplicitSave() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        let snapshot = LessonSnapshot(lesson: lesson)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let snapshotBytes = try encoder.encode(snapshot)
        var legacySnapshot: [String: Any] = ["id": lesson.id, "revision": lesson.revision, "topic": lesson.topic, "text": lesson.text]
        legacySnapshot["taskScope"] = HamptonTaskScope.passageRevision.rawValue
        XCTAssertEqual(snapshotBytes, try JSONSerialization.data(withJSONObject: legacySnapshot, options: [.sortedKeys]))

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.preference)) as? [String: Any])
        legacy["schema"] = "archi-native-preferences/v10"
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
        try legacyBytes.write(to: fixture.preference)
        let loaded = try NativePreferencePersistence.read(fixture.preference)
        XCTAssertEqual(loaded.document.schema, NativePreferenceDocument.currentSchema)
        XCTAssertNil(loaded.document.memoryInfluences)
        XCTAssertEqual(loaded.baseline, legacyBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.preference), legacyBytes)
        XCTAssertEqual(try encoder.encode(LessonSnapshot(lesson: try XCTUnwrap(loaded.document.lessons.first))), snapshotBytes)
    }

    func testArchiveRejectsUnknownDuplicateAndOutOfRangeAssessmentFields() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let lesson = try fixture.keepLesson()
        XCTAssertTrue(fixture.assess(lesson, for: fixture.first, polarity: 1))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.preference)) as? [String: Any])
        let originalRelations = try XCTUnwrap(original["memoryInfluences"] as? [[String: Any]])

        for (key, value) in [("authority", true as Any), ("polarity", 7 as Any), ("magnitude", -0.1 as Any),
                             ("confidence", 1.1 as Any), ("retrievalSalience", NSNull() as Any)] {
            var archive = original, relations = originalRelations
            var assessment = try XCTUnwrap(relations[0]["assessment"] as? [String: Any])
            assessment[key] = value; relations[0]["assessment"] = assessment
            archive["memoryInfluences"] = relations
            XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: archive)), key)
        }
        var repeated = original
        repeated["memoryInfluences"] = originalRelations + originalRelations
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: repeated)))
        var injected = original, relations = originalRelations
        var source = try XCTUnwrap(relations[0]["source"] as? [String: Any])
        source["authority"] = true
        relations[0]["source"] = source; injected["memoryInfluences"] = relations
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: injected)))
        for (key, value) in [("lessonID", UUID().uuidString as Any),
                             ("lessonRevision", (lesson.revision + 1) as Any),
                             ("snapshotDigest", String(repeating: "f", count: 64) as Any)] {
            var archive = original, references = originalRelations
            var binding = try XCTUnwrap(references[0]["source"] as? [String: Any])
            binding[key] = value; references[0]["source"] = binding
            archive["memoryInfluences"] = references
            XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: archive)), key)
        }
        var legacyWithNewField = original
        legacyWithNewField["schema"] = "archi-native-preferences/v10"
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: legacyWithNewField)))
    }

    @MainActor
    private final class Clock {
        var now = Date()
    }

    @MainActor
    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-memory-influence-\(UUID())")
        let clock = Clock()
        let client = NoCallsClient()
        var preference: URL { directory.appendingPathComponent("preferences.json") }
        lazy var store = makeStore()
        var source: ReadingSourceSnapshot!
        var page: KnowledgePage!
        var first: DocumentProcedure!
        var second: DocumentProcedure!

        init() throws {
            source = try store.readingSources.keep(title: "Synthetic review guidance", text: "Check a source before reviewing its derived candidate.")
            let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
                range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try store.readingSources.saveKnowledgePage(title: "Synthetic review concept",
                body: "Source checking supports a deliberate review.", kind: .concept, anchors: [anchor])
            page = try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
            first = try method("First method")
            second = try method("Second method")
            store.share(text: "The synthetic project is ready for review.", name: "synthetic-review.txt")
            store.requestsRevision = true
            store.prompt = "Revise this synthetic review."
        }

        func makeStore() -> CompanionStore {
            CompanionStore(preferenceURL: preference, assistant: client,
                assistantFactory: { [client] _, _ in client }, wallClock: { [clock] in clock.now }, allowsPlay: false)
        }

        func method(_ title: String) throws -> DocumentProcedure {
            try store.documentProcedures.keepCandidate(from: page, title: title,
                instruction: "Check the current source and preserve its meaning.",
                requirements: .init(mustBeShorter: false, preserveNumbersAndLinks: true),
                knowledgeIsCurrent: { [store] in store.knowledgeDependenciesAreCurrent([$0]) })
        }

        func methodDerivedFrom(_ lesson: KeptLesson) throws -> DocumentProcedure {
            let request = UUID().uuidString
            let date = clock.now
            let digest = String(repeating: "a", count: 64)
            let supplied = try XCTUnwrap(EvolutionLessonUse.make(snapshot: LessonSnapshot(lesson: lesson)))
            var record = DocumentWorkRecord(id: request + "-Qwen", requestID: request, provider: "Qwen",
                targetID: UUID().uuidString, sourceDigest: digest, sourceRevision: 1,
                selectionStart: 0, selectionLength: 12, preserveNumbersAndLinks: true,
                createdAt: date, updatedAt: date.addingTimeInterval(20), state: .applying,
                proposedDigest: digest, expectedAfterDigest: digest, actualAfterDigest: digest, afterRevision: 2,
                checks: [.init(id: "source", title: "Exact source", passed: true)],
                learning: .init(requestBinding: .init(inputDigest: digest, contextDigest: digest),
                                suppliedLessons: [supplied]))
            try store.documentWork.save(record)
            record.state = .applied
            record.feedback = .init(revision: 1, verdict: .helpful, recordedAt: date.addingTimeInterval(10))
            try store.documentWork.save(record)
            return try store.documentProcedures.keep(from: record, title: "Derived synthetic method",
                instruction: "Review the source before applying its candidate.", records: store.documentWork.records)
        }

        func keepLesson(expiresAt: Date? = nil) throws -> KeptLesson {
            store.beginLessonCorrection()
            var draft = try XCTUnwrap(store.lessonDraft)
            draft.topic = "synthetic review"
            draft.text = "A prior synthetic review failed after its source changed."
            draft.reason = "Explicit synthetic caution for the integration check."
            draft.taskScope = .passageRevision
            draft.expiresAt = expiresAt
            XCTAssertTrue(store.keepLesson(draft), store.lessonMessage)
            return try XCTUnwrap(store.keptLessons.last)
        }

        func assessment(for method: DocumentProcedure, polarity: Int?, magnitude: Double = 1, confidence: Double = 1)
            -> ContextualMemoryInfluence.Assessment {
            .init(scope: LessonMemoryInfluence.scope, targetID: LessonMemoryInfluence.targetID(for: method.binding),
                  polarity: polarity.flatMap(ContextualMemoryInfluence.Polarity.init(rawValue:)),
                  magnitude: magnitude, confidence: confidence, retrievalSalience: 1)
        }

        @discardableResult
        func assess(_ lesson: KeptLesson, for method: DocumentProcedure, polarity: Int?, magnitude: Double = 1, confidence: Double = 1) -> Bool {
            store.updateLessonMemoryInfluence(lesson: LessonSnapshot(lesson: lesson), expectedRevision: store.lessonRevision,
                procedure: method.binding, assessment: assessment(for: method, polarity: polarity, magnitude: magnitude, confidence: confidence))
        }

        func clean() {
            store.cancelWork(); store.disconnectAssistant()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @MainActor
    private final class NoCallsClient: AssistantClient {
        private(set) var calls = 0
        func connect() async throws {
            calls += 1
            XCTFail("Assessing or ranking memory must not connect a provider.")
            throw AssistantFailure.stopped
        }
        func disconnect() {}
        func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
            calls += 1
            XCTFail("Assessing or ranking memory must not generate an answer.")
            throw AssistantFailure.stopped
        }
    }
}
