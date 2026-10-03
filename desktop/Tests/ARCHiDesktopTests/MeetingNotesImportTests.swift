import CryptoKit
import Foundation
import XCTest
@testable import ARCHiDesktop

final class MeetingNotesImportTests: XCTestCase {
    func testGranolaSummaryPreservesReviewedBytesAndDoesNotClaimTranscript() throws {
        let raw = "# Planning\r\n- Renée will bring the 🌱 prototype.\r\n"
        let result = try MeetingNotesImport.prepare(text: raw, title: "Planning", provider: .granola, kind: .summary)
        XCTAssertTrue(result.sharedText.contains(raw))
        XCTAssertEqual(result.sourceName, "Granola · Planning")
        XCTAssertTrue(result.sharedText.contains("Content type: Summary"))
        XCTAssertFalse(result.sharedText.contains("Content type: Transcript"))
        XCTAssertEqual(result.contentDigest, SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined())
        XCTAssertNil(result.cueCount)
    }

    func testZoomVTTKeepsCueIDsTimesSpeakersAndLiteralArrows() throws {
        let raw = "\u{FEFF}WEBVTT\r\n\r\nNOTE a comment\r\nignored\r\n\r\n1\r\n00:00:01.200 --> 00:00:04.600 align:start\r\n<v Pat>Use A --> B in the diagram.</v>\r\n\r\n2\r\n00:05.000 --> 00:06.000\r\nSam: Friday works.\r\n"
        let result = try MeetingNotesImport.prepare(text: raw, title: "Design", provider: .zoom, kind: .transcript, filename: "design.vtt")
        XCTAssertEqual(result.cueCount, 2)
        XCTAssertTrue(result.sharedText.contains(raw))
        XCTAssertTrue(result.sharedText.contains("Transcript (WebVTT)"))
    }

    func testMalformedVTTAndWrongKindAreRejected() {
        for raw in ["1\n00:01.000 --> 00:02.000\nHi", "WEBVTT\n\nNo timestamp", "WEBVTT\n\n00:99.000 --> 00:99.001\nHi", "WEBVTT\n\n00:01.000 --> 00:02.000", "WEBVTT\n\n00:02.000 --> 00:01.000\nHi"] {
            XCTAssertThrowsError(try MeetingNotesImport.prepare(text: raw, title: "", provider: .zoom, kind: .transcript, filename: "x.vtt"))
        }
        XCTAssertThrowsError(try MeetingNotesImport.prepare(text: "WEBVTT\n\n00:01.000 --> 00:02.000\nHi", title: "", provider: .zoom, kind: .summary))
        let missingSeparator = "WEBVTT\n1\n00:01.000 --> 00:02.000\nHidden first cue\n\n2\n00:03.000 --> 00:04.000\nSecond cue"
        XCTAssertThrowsError(try MeetingNotesImport.prepare(text: missingSeparator, title: "", provider: .zoom, kind: .transcript, filename: "x.vtt"))
    }

    func testEmptyBinaryAndByteLimitIncludingMetadataRejectWithoutTruncation() {
        for raw in [" \n\t", "Note\0binary", String(repeating: "é", count: 50_001), String(repeating: "a", count: 100_000)] {
            XCTAssertThrowsError(try MeetingNotesImport.prepare(text: raw, title: "", provider: .granola, kind: .notes))
        }
        XCTAssertThrowsError(try MeetingNotesImport.prepare(text: "Hi", title: String(repeating: "a", count: 161), provider: .other, kind: .notes))
    }

    func testFileReaderSupportsLocalExportsAndRejectsBulkOrBinary() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for suffix in ["txt", "md", "markdown", "vtt"] {
            let url = folder.appendingPathComponent("notes.\(suffix)")
            try Data("Some notes".utf8).write(to: url)
            XCTAssertEqual(try MeetingNotesImport.readFile(at: url), "Some notes")
        }
        let csv = folder.appendingPathComponent("all.csv")
        try Data("title,summary".utf8).write(to: csv)
        XCTAssertThrowsError(try MeetingNotesImport.readFile(at: csv))
        let binary = folder.appendingPathComponent("binary.txt")
        try Data([0xff, 0xfe, 0x12]).write(to: binary)
        XCTAssertThrowsError(try MeetingNotesImport.readFile(at: binary))
        let large = folder.appendingPathComponent("large.txt")
        try Data(repeating: 65, count: 100_001).write(to: large)
        XCTAssertThrowsError(try MeetingNotesImport.readFile(at: large))
    }

    @MainActor
    func testImportUsesExistingSourceAndPreservesDraftWithoutCallsOrMemoryWrites() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = folder.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: profile)
        store.share(text: "Previous source", name: "old.txt")
        let ticket = store.contextTicket()
        store.prompt = "Keep my unsent question"
        let notes = try MeetingNotesImport.prepare(text: "May will email the draft.", title: "Weekly", provider: .granola, kind: .summary)
        XCTAssertTrue(store.importMeetingNotes(notes))
        XCTAssertFalse(store.isCurrent(ticket))
        XCTAssertEqual(store.sharedText, notes.sharedText)
        XCTAssertEqual(store.sourceName, notes.sourceName)
        XCTAssertEqual(store.prompt, "Keep my unsent question")
        XCTAssertEqual(store.section, .context)
        XCTAssertFalse(store.isWorking)
        XCTAssertTrue(store.compareResults.isEmpty)
        XCTAssertTrue(store.keptLessons.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.path))
    }

    @MainActor
    func testPreparedDigestClearsPassageAndRetainsSameSourceInBothRouteInputs() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CompanionStore(preferenceURL: folder.appendingPathComponent("unused.json"))
        let notes = try MeetingNotesImport.prepare(text: "Sam: I can send it on Friday.", title: "Weekly", provider: .zoom, kind: .transcript)
        XCTAssertTrue(store.importMeetingNotes(notes))
        XCTAssertEqual(store.prompt, MeetingNotesImport.digestQuestion)
        store.selectText(range: NSRange(location: 0, length: 3), sourceRevision: store.sourceRevision)
        store.prepareMeetingDigest()
        XCTAssertNil(store.textSelection)
        let request = AssistantRequest(prompt: store.prompt, sourceName: store.sourceName, sourceText: store.sharedText,
            sourceRevision: store.sourceRevision, placementRevision: 0, tone: "Warm", replyLength: 0.5)
        for input in [request.localInput, request.codexInput] {
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let source = try XCTUnwrap(value["source"] as? [String: Any])
            XCTAssertEqual(source["text"] as? String, notes.sharedText)
            XCTAssertEqual(source["name"] as? String, notes.sourceName)
            XCTAssertEqual(value["question"] as? String, MeetingNotesImport.digestQuestion)
        }
        XCTAssertTrue(store.compareResults.isEmpty)
    }

    @MainActor
    func testExportCannotOverwriteImportedMeetingFile() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("notes.md")
        try Data("Original summary".utf8).write(to: original)
        let notes = try MeetingNotesImport.prepare(text: MeetingNotesImport.readFile(at: original), title: "Weekly", provider: .granola, kind: .summary, filename: original.lastPathComponent)
        let store = CompanionStore(preferenceURL: folder.appendingPathComponent("unused.json"))
        XCTAssertTrue(store.importMeetingNotes(notes, sourceURL: original))
        XCTAssertFalse(store.exportWorkingCopy(to: original, expectedRevision: store.sourceRevision))
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "Original summary")
    }

    @MainActor
    func testDeclinedDiscardAndChangesDuringReviewPreserveCurrentCopy() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CompanionStore(preferenceURL: folder.appendingPathComponent("unused.json"))
        store.share(text: "Original", name: "draft.txt")
        store.sharedText = "Unexported edits"
        store.prompt = "Unsent question"
        let ticket = store.contextTicket()
        let notes = try MeetingNotesImport.prepare(text: "New meeting", title: "Weekly", provider: .granola, kind: .notes)
        XCTAssertFalse(store.importMeetingNotes(notes, reviewWorkingCopy: { false }))
        XCTAssertEqual(store.sharedText, "Unexported edits")
        XCTAssertEqual(store.prompt, "Unsent question")
        XCTAssertTrue(store.isCurrent(ticket))
        XCTAssertFalse(store.importMeetingNotes(notes, reviewWorkingCopy: {
            store.sharedText = "A newer edit during review"
            return true
        }))
        XCTAssertEqual(store.sharedText, "A newer edit during review")
        XCTAssertTrue(store.hasUnexportedWorkingCopy)
        XCTAssertTrue(store.importMeetingNotes(notes, reviewWorkingCopy: { true }))
        XCTAssertEqual(store.sharedText, notes.sharedText)
        XCTAssertEqual(store.prompt, "Unsent question")
    }

    @MainActor
    func testThirtyKBTranscriptNeedsExplicitShorterReviewBeforeImport() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CompanionStore(preferenceURL: folder.appendingPathComponent("unused.json"))
        store.share(text: "Current draft", name: "keep.txt")
        store.prompt = "Keep this question"
        let ticket = store.contextTicket()
        let raw = "WEBVTT\n\n1\n00:00:01.000 --> 00:00:20.000\nSam: " + String(repeating: "Meeting detail. ", count: 2_100)
        let long = try MeetingNotesImport.prepare(text: raw, title: "Long meeting", provider: .zoom, kind: .transcript, filename: "meeting.vtt")
        XCTAssertGreaterThan(long.sharedText.utf8.count, 30_000)
        XCTAssertTrue(long.sharedText.contains(raw), "Review never cuts the source to fit a model")
        XCTAssertFalse(store.canImportMeetingNotes(long))
        XCTAssertFalse(store.importMeetingNotes(long, reviewWorkingCopy: {
            XCTFail("An unusable request must fail before asking to replace current work")
            return true
        }))
        XCTAssertTrue(store.isCurrent(ticket))
        XCTAssertEqual(store.sharedText, "Current draft")
        XCTAssertEqual(store.prompt, "Keep this question")
        XCTAssertTrue(store.status.contains("22 KB"))
        XCTAssertFalse(store.status.contains("ready to send"))
        XCTAssertTrue(store.compareResults.isEmpty)

        let chosenExcerpt = "WEBVTT\n\n1\n00:00:01.000 --> 00:00:20.000\nSam: Meeting detail."
        let short = try MeetingNotesImport.prepare(text: chosenExcerpt, title: "Long meeting — excerpt", provider: .zoom, kind: .transcript, filename: "meeting.vtt")
        XCTAssertTrue(store.canImportMeetingNotes(short))
        XCTAssertTrue(store.importMeetingNotes(short))
        XCTAssertTrue(store.sharedText.contains(chosenExcerpt))
        XCTAssertNotEqual(short.contentDigest, long.contentDigest)
        XCTAssertTrue(store.sharedText.contains("completeness of the meeting is unverified"))
    }

    @MainActor
    func testSelectingShortPassageDoesNotPretendToReduceFullMeetingContext() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CompanionStore(preferenceURL: folder.appendingPathComponent("unused.json"))
        let raw = String(repeating: "Full transcript. ", count: 2_000)
        store.share(text: raw, name: "Meeting imported through ordinary document flow")
        store.prompt = "An existing question"
        store.selectText(range: NSRange(location: 0, length: 16), sourceRevision: store.sourceRevision)
        let selection = store.textSelection
        store.prepareMeetingDigest()
        XCTAssertEqual(store.prompt, "An existing question")
        XCTAssertEqual(store.textSelection, selection)
        XCTAssertEqual(store.sharedText, raw)
        XCTAssertTrue(store.status.contains("Selecting a passage does not remove the full shared copy"))
        let request = AssistantRequest(prompt: MeetingNotesImport.digestQuestion, sourceName: store.sourceName,
            sourceText: raw, sourceRevision: store.sourceRevision, placementRevision: 0,
            tone: "Warm", replyLength: 0.5, selection: selection)
        XCTAssertFalse(HamptonReasonsAssistant.fitsMandatoryReasoningInput(request))
    }

    @MainActor
    func testCompareReceivesSameMeetingOnlyAfterSendAndLateRepliesCannotReviveOldSource() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let local = MeetingNotesFixtureClient(), external = MeetingNotesFixtureClient()
        defer { local.finish(); external.finish() }
        let store = CompanionStore(preferenceURL: folder.appendingPathComponent("unused.json"), assistant: local,
            assistantFactory: { provider, _ in provider == .qwen ? local : external })
        store.setAssistantRoute(.compare)
        store.connectAssistant()
        try await waitUntil { store.connection(for: .qwen) == .ready && store.connection(for: .codex) == .ready }
        let first = try MeetingNotesImport.prepare(text: "Sam will send the draft.", title: "First", provider: .zoom, kind: .transcript)
        XCTAssertTrue(store.importMeetingNotes(first))
        XCTAssertTrue(local.requests.isEmpty)
        XCTAssertTrue(external.requests.isEmpty)
        store.submit()
        try await waitUntil { local.requests.count == 1 && external.requests.count == 1 }
        XCTAssertEqual(local.requests.first?.sourceText, first.sharedText)
        XCTAssertEqual(external.requests.first?.sourceText, first.sharedText)
        XCTAssertEqual(local.requests.first?.sourceName, first.sourceName)
        XCTAssertEqual(external.requests.first?.sourceName, first.sourceName)
        XCTAssertEqual(local.requests.first?.prompt, external.requests.first?.prompt)
        XCTAssertTrue(store.isWorking)
        let next = try MeetingNotesImport.prepare(text: "Second meeting", title: "Second", provider: .granola, kind: .summary)
        XCTAssertTrue(store.importMeetingNotes(next))
        let status = store.status, reply = store.reply
        local.finish(); external.finish()
        try await waitUntil { local.finished && external.finished }
        await Task.yield()
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.sharedText, next.sharedText)
        XCTAssertEqual(store.sourceName, next.sourceName)
        XCTAssertEqual(store.status, status)
        XCTAssertEqual(store.reply, reply)
        XCTAssertTrue(store.compareResults.isEmpty)
        XCTAssertEqual(local.requests.count, 1)
        XCTAssertEqual(external.requests.count, 1)
        XCTAssertTrue(store.keptLessons.isEmpty)
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Fixture did not reach the expected state")
        throw AssistantFailure.timedOut
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-notes-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

@MainActor
private final class MeetingNotesFixtureClient: AssistantClient {
    var requests: [AssistantRequest] = []
    var finished = false
    private var pending: CheckedContinuation<Void, Never>?
    private var event: (@MainActor (AssistantEvent) -> Void)?

    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request)
        event = onEvent
        await withCheckedContinuation { pending = $0 }
        finished = true
    }
    func finish() {
        event?(.text("Late answer from the previous meeting"))
        event = nil
        let held = pending; pending = nil; held?.resume()
    }
}
