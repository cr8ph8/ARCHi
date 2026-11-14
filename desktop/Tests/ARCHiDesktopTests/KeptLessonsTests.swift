import Foundation
import XCTest
@testable import ARCHiDesktop

final class KeptLessonsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTopicMatchingUsesWholeNormalizedPhraseAndNoInference() {
        let lesson = lesson(topic: "Café planning")
        XCTAssertTrue(lesson.matches(question: "Help with CAFE, planning today", sourceName: nil, sourceText: "", now: now))
        XCTAssertFalse(lesson.matches(question: "Help with cafeteria planning", sourceName: nil, sourceText: "", now: now))
        XCTAssertFalse(lesson.matches(question: "Help with cafe and planning", sourceName: nil, sourceText: "", now: now))
        XCTAssertFalse(lesson.matches(question: "Plan my coffee shop", sourceName: nil, sourceText: "", now: now))
        XCTAssertFalse(lesson.matches(question: "Nothing related", sourceName: nil, sourceText: "", now: now))
    }

    func testSourceAndExpiryMustRemainExact() {
        var lesson = lesson(topic: "drawing")
        lesson.source = LessonSource(name: "Practice.txt", digest: LessonSource.digest(of: "Use soft lines."))
        lesson.expiresAt = now.addingTimeInterval(60)
        XCTAssertTrue(lesson.matches(question: "Drawing today", sourceName: "Practice.txt", sourceText: "Use soft lines.", now: now))
        XCTAssertFalse(lesson.matches(question: "Drawing today", sourceName: "Practice.txt", sourceText: "Use sharp lines.", now: now))
        XCTAssertFalse(lesson.matches(question: "Drawing today", sourceName: "practice.txt", sourceText: "Use soft lines.", now: now))
        XCTAssertFalse(lesson.matches(question: "Drawing today", sourceName: nil, sourceText: "Use soft lines.", now: now))
        XCTAssertFalse(lesson.matches(question: "Drawing today", sourceName: "Practice.txt", sourceText: "Use soft lines.", now: now.addingTimeInterval(60)))
    }

    func testSnapshotPreservesOldRevisionAndExposesOnlyModelFields() {
        var lesson = lesson()
        lesson.reason = "I am revising yesterday's answer."
        lesson.origin = LessonOrigin(requestID: UUID().uuidString, inputDigest: String(repeating: "a", count: 64))
        let snapshot = LessonSnapshot(lesson: lesson)
        lesson.revision += 1
        lesson.text = "Use a different practice routine."
        XCTAssertEqual(snapshot.revision, 1)
        XCTAssertNotEqual(snapshot.text, lesson.text)
        XCTAssertEqual(snapshot.modelInput["id"], .string("kept-\(lesson.id)-r1"))
        XCTAssertEqual(snapshot.modelInput["kind"], .string("user-confirmed-lesson"))
        XCTAssertEqual(snapshot.modelInput.object?.count, 4)
        XCTAssertNil(snapshot.modelInput["reason"])
        XCTAssertNil(snapshot.modelInput["origin"])
        XCTAssertNil(snapshot.modelInput["source"])
    }

    func testBoundedContentRejectsInvalidIdentityAndCharacterOrByteOverflows() {
        var valid = lesson()
        XCTAssertTrue(valid.isValid)
        valid.text = String(repeating: "a", count: 600)
        XCTAssertTrue(valid.isValid)
        valid.text += "b"
        XCTAssertFalse(valid.isValid)
        // A single extended grapheme can contain many scalars. Character count
        // alone must not admit an unbounded retained prompt.
        valid.text = "a" + String(repeating: "\u{301}", count: 1_201)
        XCTAssertLessThan(valid.text.count, 600)
        XCTAssertFalse(valid.isValid)
        valid = lesson()
        valid.topic = "! "
        XCTAssertFalse(valid.isValid)
        valid.topic = "x"
        XCTAssertFalse(valid.isValid)
        valid.topic = String(repeating: "a", count: 81)
        XCTAssertFalse(valid.isValid)
        valid = lesson()
        valid.reason = String(repeating: "a", count: 301)
        XCTAssertFalse(valid.isValid)
        XCTAssertFalse(lesson(id: "not-an-id").isValid)
        valid = lesson()
        valid.revision = 0
        XCTAssertFalse(valid.isValid)
        valid = lesson()
        valid.source = LessonSource(name: "file", digest: String(repeating: "z", count: 64))
        XCTAssertFalse(valid.isValid)
        valid.source = nil
        valid.origin = LessonOrigin(requestID: "not-a-request", inputDigest: String(repeating: "a", count: 64))
        XCTAssertFalse(valid.isValid)
    }

    func testDatesMustBeFiniteOrderedAndUsable() {
        var value = lesson()
        value.updatedAt = value.createdAt.addingTimeInterval(-1)
        XCTAssertFalse(value.isValid)
        value = lesson()
        value.updatedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertFalse(value.isValid)
        value = lesson()
        value.expiresAt = value.createdAt
        XCTAssertFalse(value.isValid)
        value = lesson()
        value.expiresAt = now.addingTimeInterval(-1)
        XCTAssertTrue(value.isValid, "A valid save may retain an expired lesson for inspection.")
        XCTAssertFalse(value.matches(question: "drawing", sourceName: nil, sourceText: "", now: now))
    }

    func testMigrationReadsKnownBarePreferencesWithoutWriting() throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("preferences.json")
        let legacy = Data("""
        {"form":"Guide light","tone":"Warm","replyLength":0.2,"size":1.1,"adaptive":true,"reduceMotion":true,"quiet":false}
        """.utf8)
        try legacy.write(to: url)
        let loaded = try NativePreferencePersistence.read(url)
        XCTAssertEqual(loaded.document.schema, NativePreferenceDocument.currentSchema)
        XCTAssertEqual(loaded.document.revision, 0)
        XCTAssertEqual(loaded.document.preferences?.form, .light)
        XCTAssertEqual(loaded.document.preferences?.visualTreatment, .original)
        XCTAssertEqual(loaded.document.preferences?.tone, "Warm")
        XCTAssertTrue(loaded.document.lessons.isEmpty)
        XCTAssertEqual(loaded.baseline, legacy)
        XCTAssertEqual(try Data(contentsOf: url), legacy)
    }

    func testEnvelopeRejectsUnknownOrMissingSchemaAndInvalidLegacy() throws {
        let good = try NativePreferenceDocument(preferences: CompanionPreferences(), lessons: [lesson()]).encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
        object["schema"] = "archi-native-preferences/v99"
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "schema")
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try NativePreferenceDocument.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try NativePreferenceDocument.decode(Data("[]".utf8)))
        XCTAssertThrowsError(try NativePreferenceDocument.decode(Data(repeating: 32, count: NativePreferenceDocument.maximumBytes + 1)))
        var invalid = CompanionPreferences()
        invalid.replyLength = 2
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONEncoder().encode(invalid)))
    }

    func testDuplicateIdentifiersAndSeventeenthRecordAreRejected() throws {
        let first = lesson()
        var duplicate = lesson(id: first.id.lowercased())
        duplicate.revision = 2
        let duplicates = NativePreferenceDocument(lessons: [first, duplicate])
        XCTAssertFalse(duplicates.isValid)
        XCTAssertThrowsError(try duplicates.encoded())
        XCTAssertFalse(NativePreferenceDocument.validateLessonSnapshots(duplicates.lessons.map(LessonSnapshot.init(lesson:))))
        let sixteen = NativePreferenceDocument(lessons: (0..<16).map { lesson(topic: "topic \($0)") })
        XCTAssertTrue(sixteen.isValid)
        var seventeen = sixteen
        seventeen.lessons.append(lesson())
        XCTAssertFalse(seventeen.isValid)
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONEncoder().encode(seventeen)))
    }

    func testUnknownAndDuplicateKeysAreRejectedAtEveryRetainedLevel() throws {
        var value = lesson()
        value.source = LessonSource(name: "Practice.txt", digest: String(repeating: "a", count: 64))
        let good = try NativePreferenceDocument(preferences: CompanionPreferences(), lessons: [value]).encoded()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
        var unknownEnvelope = original
        unknownEnvelope["unrecognizedState"] = true
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: unknownEnvelope)))
        var unknownLesson = original
        var lessons = try XCTUnwrap(unknownLesson["lessons"] as? [[String: Any]])
        lessons[0]["authority"] = "generated"
        unknownLesson["lessons"] = lessons
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: unknownLesson)))
        var unknownSource = original
        lessons = try XCTUnwrap(unknownSource["lessons"] as? [[String: Any]])
        var source = try XCTUnwrap(lessons[0]["source"] as? [String: Any])
        source["secretCopy"] = "must not be silently dropped"
        lessons[0]["source"] = source
        unknownSource["lessons"] = lessons
        XCTAssertThrowsError(try NativePreferenceDocument.decode(JSONSerialization.data(withJSONObject: unknownSource)))
        let text = try XCTUnwrap(String(data: good, encoding: .utf8))
        let duplicateRevision = text.replacingOccurrences(of: "\"revision\":0", with: "\"revision\":0,\"revis\\u0069on\":1")
        XCTAssertNotEqual(duplicateRevision, text)
        XCTAssertThrowsError(try NativePreferenceDocument.decode(Data(duplicateRevision.utf8)))
        let duplicateText = text.replacingOccurrences(of: "\"text\":", with: "\"text\":\"shadow\",\"text\":")
        XCTAssertThrowsError(try NativePreferenceDocument.decode(Data(duplicateText.utf8)))
    }

    func testSaveReloadUsesSingleEnvelopeAndPrivatePermissions() throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("native/preferences.json")
        let absent = try NativePreferencePersistence.read(url)
        XCTAssertEqual(absent.document, NativePreferenceDocument())
        XCTAssertNil(absent.baseline)
        let document = NativePreferenceDocument(revision: 1, preferences: CompanionPreferences(), lessons: [lesson()])
        let bytes = try XCTUnwrap(NativePreferencePersistence.write(document: document, to: url, expected: nil))
        let reloaded = try NativePreferencePersistence.read(url)
        XCTAssertEqual(reloaded.document, document)
        XCTAssertEqual(reloaded.baseline, bytes)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)),
                       ["preferences.json", DesktopProfileLock.filename])
    }

    func testOutsideEditAndDeletionConflictPreserveExternalState() throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("preferences.json")
        let original = NativePreferenceDocument(revision: 1, lessons: [lesson()])
        let before = try NativePreferencePersistence.write(document: original, to: url, expected: nil)
        let outside = NativePreferenceDocument(revision: 2, lessons: [lesson(topic: "music")])
        let outsideBytes = try outside.encoded()
        try outsideBytes.write(to: url, options: .atomic)
        XCTAssertThrowsError(try NativePreferencePersistence.write(document: original, to: url, expected: before))
        XCTAssertThrowsError(try NativePreferencePersistence.write(document: NativePreferenceDocument(), to: url, expected: before))
        XCTAssertEqual(try Data(contentsOf: url), outsideBytes)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try NativePreferencePersistence.write(document: original, to: url, expected: outsideBytes))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testConcurrentWritersFromSameBaselineKeepExactlyOneLesson() async throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("preferences.json")
        let initial = NativePreferenceDocument(revision: 1, preferences: CompanionPreferences())
        let baseline = try NativePreferencePersistence.write(document: initial, to: url, expected: nil)
        let candidates = [lesson(topic: "first writer"), lesson(topic: "second writer")]
        let attempts = candidates.map { lesson in
            Task.detached {
                Result {
                    var document = initial
                    document.revision += 1
                    document.lessons.append(lesson)
                    return try NativePreferencePersistence.write(document: document, to: url, expected: baseline)
                }
            }
        }
        let results = [await attempts[0].value, await attempts[1].value]
        let winners = zip(candidates, results).compactMap { lesson, result -> KeptLesson? in
            switch result {
            case .success: return lesson
            case .failure(let error):
                switch error {
                case DesktopProfileLock.Failure.busy, NativePreferenceError.conflict: break
                default: XCTFail("Unexpected write failure: \(error)")
                }
                return nil
            }
        }
        XCTAssertEqual(winners.count, 1)
        let reopened = try NativePreferencePersistence.read(url).document
        XCTAssertEqual(reopened.revision, 2)
        XCTAssertEqual(reopened.preferences, initial.preferences)
        XCTAssertEqual(reopened.lessons, winners)
    }

    func testOccupiedProfileLockPreventsReplacementAndDeletion() throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("preferences.json")
        let initial = NativePreferenceDocument(revision: 1, lessons: [lesson()])
        let baseline = try NativePreferencePersistence.write(document: initial, to: url, expected: nil)
        try DesktopProfileLock.withLock(at: url) {
            for proposed in [NativePreferenceDocument(revision: 2, lessons: [lesson()]), NativePreferenceDocument(revision: 2)] {
                XCTAssertThrowsError(try NativePreferencePersistence.write(document: proposed, to: url, expected: baseline)) { error in
                    guard case DesktopProfileLock.Failure.busy = error else { return XCTFail("Unexpected write failure: \(error)") }
                }
            }
        }
        XCTAssertEqual(try NativePreferencePersistence.read(url).document, initial)
    }

    func testReadRepeatsIfFirstWriteCreatesTheLockDuringCapture() throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("preferences.json")
        XCTAssertNil(try NativePreferencePersistence.read(url).baseline)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.path).isEmpty)

        let committed = NativePreferenceDocument(revision: 1, lessons: [lesson()])
        var reads = 0
        let saved = try DesktopProfileLock.read(at: url) {
            let bytes = try? Data(contentsOf: url)
            reads += 1
            if reads == 1 { try NativePreferencePersistence.write(document: committed, to: url, expected: nil) }
            return bytes
        }
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(saved, try committed.encoded())
    }

    func testFailedWritesLeavePriorBytesUntouchedAndDoNotCreatePartialSave() throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("preferences.json")
        let original = NativePreferenceDocument(revision: 1, lessons: [lesson()])
        let before = try NativePreferencePersistence.write(document: original, to: url, expected: nil)
        var invalid = original
        invalid.lessons[0].text = ""
        XCTAssertThrowsError(try NativePreferencePersistence.write(document: invalid, to: url, expected: before))
        XCTAssertEqual(try Data(contentsOf: url), before)
        // A file in place of the parent directory produces a real filesystem
        // failure without changing permissions on a shared or user directory.
        let blocked = fixture.appendingPathComponent("blocked")
        try Data("occupied".utf8).write(to: blocked)
        XCTAssertThrowsError(try NativePreferencePersistence.write(document: original,
            to: blocked.appendingPathComponent("preferences.json"), expected: nil))
        XCTAssertEqual(try String(contentsOf: blocked, encoding: .utf8), "occupied")
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testForgettingPreferencesPreservesLessonsAndFinalWithdrawalRemovesFile() throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = fixture.appendingPathComponent("preferences.json")
        var document = NativePreferenceDocument(revision: 1, preferences: CompanionPreferences(), lessons: [lesson()])
        var baseline = try NativePreferencePersistence.write(document: document, to: url, expected: nil)
        document.preferences = nil
        document.revision += 1
        baseline = try NativePreferencePersistence.write(document: document, to: url, expected: baseline)
        XCTAssertEqual(try NativePreferencePersistence.read(url).document.lessons, document.lessons)
        document.lessons = []
        document.revision += 1
        XCTAssertNil(try NativePreferencePersistence.write(document: document, to: url, expected: baseline))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSymbolicLinkTargetIsNeverReadOrOverwritten() throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let target = fixture.appendingPathComponent("actual.json")
        let bytes = try NativePreferenceDocument(preferences: CompanionPreferences()).encoded()
        try bytes.write(to: target)
        let link = fixture.appendingPathComponent("preferences.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try NativePreferencePersistence.read(link))
        XCTAssertThrowsError(try NativePreferencePersistence.write(document: NativePreferenceDocument(lessons: [lesson()]), to: link, expected: bytes))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    private func lesson(id: String = UUID().uuidString, topic: String = "drawing") -> KeptLesson {
        KeptLesson(id: id, topic: topic, text: "Start with a simple outline.",
                   createdAt: now.addingTimeInterval(-300), updatedAt: now.addingTimeInterval(-200))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archi-lesson-persistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
