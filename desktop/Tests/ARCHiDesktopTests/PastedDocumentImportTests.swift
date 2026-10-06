import Foundation
import XCTest
@testable import ARCHiDesktop

/// Intake stays in a disposable working copy. No model, native modal or personal profile.
@MainActor
final class PastedDocumentImportTests: XCTestCase {
    func testPastePreservesExactBytesAndUnsentPromptWithoutCallsOrMemoryWrites() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.store.prompt = "Keep this unsent request exactly.\r\n"
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        let saved = try fixture.savedFiles()
        let evolutionRevision = fixture.store.evolution.revision
        let body = "  Café · Cafe\u{301} 👩🏽‍💻\r\n\tSecond line.\n\n"

        XCTAssertTrue(fixture.store.importPastedDocument(text: body, title: "  Project status  ",
            context: context, reviewWorkingCopy: { true }))
        XCTAssertEqual(Data(fixture.store.sharedText.utf8), Data(body.utf8))
        XCTAssertEqual(fixture.store.sourceName, "Project status")
        XCTAssertEqual(fixture.store.prompt, "Keep this unsent request exactly.\r\n")
        XCTAssertTrue(fixture.store.workingCopyIsPasted)
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy)
        XCTAssertNil(fixture.store.textSelection)
        XCTAssertFalse(fixture.store.canUndoWorkingCopyEdit)
        XCTAssertTrue(fixture.store.documentWork.records.isEmpty)
        XCTAssertTrue(fixture.store.documentProcedures.procedures.isEmpty)
        XCTAssertTrue(fixture.store.readingSources.sources.isEmpty)
        XCTAssertTrue(fixture.store.keptLessons.isEmpty)
        XCTAssertTrue(fixture.store.tokenSteward.tasks.isEmpty)
        XCTAssertEqual(fixture.store.evolution.revision, evolutionRevision)
        XCTAssertEqual(try fixture.savedFiles(), saved)
        XCTAssertEqual(fixture.client.connections, 0)
        XCTAssertEqual(fixture.client.requests, 0)

        let next = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        XCTAssertTrue(fixture.store.importPastedDocument(text: "Next draft.", title: " \t ",
            context: next, reviewWorkingCopy: { true }))
        XCTAssertEqual(fixture.store.sourceName, "Pasted text")
    }

    func testPastedCopyNeedsVerifiedExactExportAndFileShareOrStopResetsItsOrigin() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let body = "Café\r\n"
        try fixture.paste(body)
        fixture.store.sharedText = "Later edits."
        fixture.store.sharedText = body
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy,
            "Restoring the original pasted bytes is not evidence that any file contains them.")
        let revision = fixture.store.sourceRevision
        let draft = fixture.directory.appendingPathComponent("export.txt")
        XCTAssertFalse(fixture.store.exportWorkingCopy(to: draft, expectedRevision: revision + 1))
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy)
        XCTAssertFalse(fixture.store.exportWorkingCopy(to: fixture.directory.appendingPathComponent("missing/export.txt"),
            expectedRevision: revision))
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy)
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        XCTAssertTrue(fixture.store.exportWorkingCopy(to: draft, expectedRevision: revision))
        XCTAssertEqual(try Data(contentsOf: draft), Data(body.utf8))
        XCTAssertFalse(fixture.store.hasUnexportedWorkingCopy)
        fixture.store.sharedText = "Cafe\u{301}\r\n"
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy, "Canonically equal Unicode is not the exported byte sequence.")
        fixture.store.sharedText = body
        XCTAssertFalse(fixture.store.hasUnexportedWorkingCopy)

        XCTAssertTrue(fixture.store.importWorkingCopy(from: draft))
        XCTAssertFalse(fixture.store.workingCopyIsPasted)
        XCTAssertFalse(fixture.store.hasUnexportedWorkingCopy)
        try fixture.paste("Another paste.")
        fixture.store.share(text: "File-backed copy.", name: "file.txt")
        XCTAssertFalse(fixture.store.workingCopyIsPasted)
        XCTAssertFalse(fixture.store.hasUnexportedWorkingCopy)
        try fixture.paste("Final paste.")
        fixture.store.stopSharing()
        XCTAssertFalse(fixture.store.workingCopyIsPasted)
        XCTAssertFalse(fixture.store.hasUnexportedWorkingCopy)
        XCTAssertNil(fixture.store.sourceName)
    }

    func testInvalidBodyAndTitlePreserveCurrentWorkAndEnforceUTF8Limit() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        try fixture.paste("Original draft.")
        fixture.store.prompt = "My unsent question."
        fixture.store.selectText(range: NSRange(location: 0, length: 8), sourceRevision: fixture.store.sourceRevision)
        let before = fixture.snapshot()
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        let invalid: [(String, String)] = [
            (" \t\r\n", "Blank"),
            ("Embedded\0NUL", "NUL"),
            (String(repeating: "a", count: 100_001), "Too large"),
            (String(repeating: "界", count: 33_334), "Too many UTF-8 bytes"),
            ("Valid body.", String(repeating: "x", count: 161)),
            ("Valid body.", "Status\nupdate"),
            ("Valid body.", "Status\tupdate")
        ]
        for (body, title) in invalid {
            var reviews = 0
            XCTAssertFalse(fixture.store.importPastedDocument(text: body, title: title, context: context,
                reviewWorkingCopy: { reviews += 1; return true }))
            XCTAssertEqual(reviews, 0, "Invalid intake must not request replacement approval.")
            XCTAssertEqual(fixture.snapshot(), before)
        }
        let boundary = String(repeating: "🌱", count: 25_000)
        XCTAssertEqual(boundary.utf8.count, 100_000)
        XCTAssertTrue(fixture.store.importPastedDocument(text: boundary, title: String(repeating: "é", count: 160),
            context: context, reviewWorkingCopy: { true }))
        XCTAssertEqual(Data(fixture.store.sharedText.utf8), Data(boundary.utf8))
        XCTAssertEqual(fixture.store.sourceName?.count, 160)
        XCTAssertEqual(fixture.store.prompt, before.prompt)
    }

    func testChangedBytesNewSourceAndDifferentOwnerInvalidateOpenPasteContext() throws {
        let fixture = Fixture(), other = Fixture()
        defer { fixture.clean(); other.clean() }
        fixture.store.share(text: "Café", name: "same.txt")
        let initial = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        let originalRevision = fixture.store.sourceRevision
        fixture.store.sharedText = "Cafe\u{301}"
        XCTAssertEqual(fixture.store.sourceRevision, originalRevision)
        let changedBytes = fixture.snapshot()
        XCTAssertNotNil(fixture.store.pastedDocumentImportBlockReason(initial))
        XCTAssertFalse(fixture.store.importPastedDocument(text: "Replacement.", title: "New", context: initial,
            reviewWorkingCopy: { XCTFail("A stale context must stop before review."); return true }))
        XCTAssertEqual(fixture.snapshot(), changedBytes)

        let beforeNewSource = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        fixture.store.share(text: fixture.store.sharedText, name: "same.txt")
        XCTAssertNotNil(fixture.store.pastedDocumentImportBlockReason(beforeNewSource))
        let current = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        other.store.share(text: "Café", name: "same.txt")
        other.store.share(text: fixture.store.sharedText, name: "same.txt")
        XCTAssertEqual(other.store.sourceRevision, fixture.store.sourceRevision)
        XCTAssertEqual(Data(other.store.sharedText.utf8), Data(fixture.store.sharedText.utf8))
        let otherBefore = other.snapshot()
        XCTAssertNotNil(other.store.pastedDocumentImportBlockReason(current))
        XCTAssertFalse(other.store.importPastedDocument(text: "Replacement.", title: "New", context: current,
            reviewWorkingCopy: { XCTFail("A different owner cannot admit this context."); return true }))
        XCTAssertEqual(other.snapshot(), otherBefore)
    }

    func testDeclinedOrReentrantReplacementPreservesTheLatestWork() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        try fixture.paste("Unsaved pasted work.")
        fixture.store.prompt = "Keep this unsent request."
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        let before = fixture.snapshot()
        var reviews = 0
        XCTAssertFalse(fixture.store.importPastedDocument(text: "Replacement.", title: "New", context: context,
            reviewWorkingCopy: { reviews += 1; return false }))
        XCTAssertEqual(reviews, 1)
        XCTAssertEqual(fixture.snapshot(), before)

        XCTAssertFalse(fixture.store.importPastedDocument(text: "Replacement.", title: "New", context: context,
            reviewWorkingCopy: {
                fixture.store.share(text: "A newer source arrived.", name: "newer.txt")
                return true
            }))
        XCTAssertEqual(fixture.store.sharedText, "A newer source arrived.")
        XCTAssertEqual(fixture.store.sourceName, "newer.txt")
        XCTAssertFalse(fixture.store.workingCopyIsPasted)
        XCTAssertEqual(fixture.store.prompt, before.prompt)

        let current = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        let newer = fixture.snapshot()
        XCTAssertFalse(fixture.store.importPastedDocument(text: "Replacement.", title: "New", context: current,
            reviewWorkingCopy: { fixture.store.isWorking = true; return true }))
        XCTAssertEqual(fixture.snapshot(), newer)
        fixture.store.isWorking = false
    }

    func testBusyProposalRecoveryAndShutdownBlockBeginAndPreviouslyCapturedContext() async throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        fixture.store.isWorking = true
        assertBlocked(fixture.store, context: context)
        fixture.store.isWorking = false
        XCTAssertNotNil(fixture.store.beginPastedDocumentImport())

        let request = UUID().uuidString
        var proposal = DocumentWorkRecord(id: request + "-Qwen", requestID: request, provider: "Qwen",
            targetID: UUID().uuidString, sourceDigest: String(repeating: "a", count: 64), sourceRevision: 1,
            selectionStart: 0, selectionLength: 1, state: .ready)
        try fixture.store.documentWork.save(proposal)
        assertBlocked(fixture.store, context: context)
        proposal.state = .dismissed
        try fixture.store.documentWork.save(proposal)
        XCTAssertNotNil(fixture.store.beginPastedDocumentImport())

        let recoveryContext = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        fixture.store.blockProfileForRecovery("Disposable recovery fixture.")
        assertBlocked(fixture.store, context: recoveryContext)

        let closing = Fixture()
        defer { closing.clean() }
        let closingContext = try XCTUnwrap(closing.store.beginPastedDocumentImport())
        await closing.store.shutdownAssistant()
        assertBlocked(closing.store, context: closingContext)
        XCTAssertEqual(fixture.client.connections + closing.client.connections, 0)
        XCTAssertEqual(fixture.client.requests + closing.client.requests, 0)
    }

    func testUnimportedDraftBlocksQuitAndRestoreAndOnlySuccessfulImportClearsIt() throws {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.store.share(text: "Existing working document.", name: "existing.txt")
        fixture.store.prompt = "An unfinished request."
        let before = fixture.snapshot()
        let files = try fixture.savedFiles()
        let title = "  Pending draft  "
        let body = "  Pending Cafe\u{301} 👩🏽‍💻\r\n\n"
        fixture.store.pastedDocumentDraft = PastedDocumentDraft(title: title, text: body)
        XCTAssertTrue(fixture.store.pastedDocumentDraft.hasContent)
        var workingCopyReviews = 0
        var evolutionReviews = 0

        XCTAssertFalse(fixture.store.confirmQuitRetainingWork(reviewWorkingCopy: {
            workingCopyReviews += 1
            return true
        }, chooseEvolution: {
            evolutionReviews += 1
            return .quitWithoutSaving
        }))
        XCTAssertEqual(workingCopyReviews, 0)
        XCTAssertEqual(evolutionReviews, 0)
        XCTAssertNotNil(fixture.store.recoveryRestoreBlockReason)
        XCTAssertEqual(fixture.snapshot(), before)
        XCTAssertEqual(Data(fixture.store.pastedDocumentDraft.title.utf8), Data(title.utf8))
        XCTAssertEqual(Data(fixture.store.pastedDocumentDraft.text.utf8), Data(body.utf8))
        XCTAssertEqual(try fixture.savedFiles(), files)

        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        XCTAssertFalse(fixture.store.importPastedDocument(text: body, title: title,
            context: context, reviewWorkingCopy: { false }))
        XCTAssertEqual(Data(fixture.store.pastedDocumentDraft.text.utf8), Data(body.utf8))
        XCTAssertTrue(fixture.store.pastedDocumentDraft.hasContent)
        XCTAssertTrue(fixture.store.importPastedDocument(text: body, title: title,
            context: context, reviewWorkingCopy: { true }))
        XCTAssertFalse(fixture.store.pastedDocumentDraft.hasContent)
        XCTAssertTrue(fixture.store.pastedDocumentDraft.title.isEmpty)
        XCTAssertTrue(fixture.store.pastedDocumentDraft.text.isEmpty)
        XCTAssertEqual(Data(fixture.store.sharedText.utf8), Data(body.utf8))
        XCTAssertEqual(fixture.store.sourceName, "Pending draft")
        XCTAssertEqual(fixture.store.prompt, before.prompt)
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy,
            "Moving the draft into the working copy is not an export.")
        XCTAssertNil(fixture.store.recoveryRestoreBlockReason)
        XCTAssertEqual(try fixture.savedFiles(), files)
        XCTAssertEqual(fixture.client.connections, 0)
        XCTAssertEqual(fixture.client.requests, 0)
    }

    private func assertBlocked(_ store: CompanionStore, context: PastedDocumentImportContext,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(store.beginPastedDocumentImport(), file: file, line: line)
        XCTAssertNotNil(store.pastedDocumentImportBlockReason(context), file: file, line: line)
        XCTAssertFalse(store.importPastedDocument(text: "Replacement.", title: "New", context: context,
            reviewWorkingCopy: { XCTFail("Blocked work must stop before replacement review.", file: file, line: line); return true }),
            file: file, line: line)
    }

    private struct SourceSnapshot: Equatable {
        let bytes: Data
        let name: String?
        let revision: UInt64
        let prompt: String
        let selection: DocumentSelection?
        let pasted: Bool
        let unexported: Bool
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-paste-intake-\(UUID())")
        let client = NoCallsClient()
        lazy var store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: client, assistantFactory: { [client] _, _ in client }, allowsPlay: false,
            tokenSteward: TokenStewardStore())

        func paste(_ text: String) throws {
            let context = try XCTUnwrap(store.beginPastedDocumentImport())
            XCTAssertTrue(store.importPastedDocument(text: text, title: "Pasted draft", context: context,
                reviewWorkingCopy: { true }), store.status)
        }

        func snapshot() -> SourceSnapshot {
            SourceSnapshot(bytes: Data(store.sharedText.utf8), name: store.sourceName, revision: store.sourceRevision,
                prompt: store.prompt, selection: store.textSelection, pasted: store.workingCopyIsPasted,
                unexported: store.hasUnexportedWorkingCopy)
        }

        func savedFiles() throws -> [String: Data] {
            guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            var files: [String: Data] = [:]
            for url in urls where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files[url.lastPathComponent] = try Data(contentsOf: url)
            }
            return files
        }

        func clean() {
            store.isWorking = false
            store.disconnectAssistant()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @MainActor private final class NoCallsClient: AssistantClient {
        private(set) var connections = 0
        private(set) var requests = 0
        func connect() async throws { connections += 1; XCTFail("Pasted intake must not connect.") }
        func disconnect() {}
        func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
            requests += 1
            XCTFail("Pasted intake must not generate a response.")
            throw AssistantFailure.unavailable
        }
    }
}
