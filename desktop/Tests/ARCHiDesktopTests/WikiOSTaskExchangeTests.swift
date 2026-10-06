import Foundation
import XCTest
@testable import ARCHiDesktop

final class WikiOSTaskExchangeTests: XCTestCase {
    @MainActor
    func testOpeningStagesReviewWithoutReplacingDraftAndQueueDoesNotOverwrite() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.store.share(text: "Existing draft", name: "existing.txt")
        f.store.sharedText = "Unsaved existing draft"
        f.store.prompt = "Keep this question"
        let revision = f.store.sourceRevision
        f.store.section = .memory
        let draft = KnowledgePageDraft()
        f.store.knowledgePageDraft = draft
        XCTAssertTrue(f.store.stageWikiOSTask(from: f.file.url))
        XCTAssertEqual(f.store.section, .memory)
        XCTAssertEqual(f.store.knowledgePageDraft?.id, draft.id)
        XCTAssertFalse(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { XCTFail("Knowledge draft must remain open"); return true }))
        f.store.knowledgePageDraft = nil
        XCTAssertEqual(f.store.sharedText, "Unsaved existing draft")
        XCTAssertEqual(f.store.prompt, "Keep this question")
        XCTAssertEqual(f.store.sourceRevision, revision)
        XCTAssertFalse(f.store.stageWikiOSTask(from: f.file.url))
        XCTAssertFalse(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { false }))
        XCTAssertEqual(f.store.sharedText, "Unsaved existing draft")
        XCTAssertNil(f.store.wikiOSTask)
        XCTAssertTrue(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { true }))
        XCTAssertEqual(f.store.sharedText, f.file.request.brief)
        XCTAssertEqual(f.store.prompt, "Keep this question")
        XCTAssertEqual(f.store.wikiOSTask, f.file)
        XCTAssertEqual(f.client.requests, 0)
        XCTAssertNil(f.store.wikiOSExchangeReview)
        await f.store.shutdownAssistant()
    }

    @MainActor
    func testImportRechecksOwnerAfterReviewAndNeverConsumesBusyWork() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        f.store.share(text: "Existing", name: "old.txt")
        XCTAssertTrue(f.store.stageWikiOSTask(from: f.file.url))
        f.store.isWorking = true
        XCTAssertFalse(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { XCTFail("Busy import must not offer discard"); return true }))
        f.store.isWorking = false
        var pending = DocumentWorkRecord(id: UUID().uuidString, requestID: UUID().uuidString, provider: "qwen",
            targetID: UUID().uuidString, sourceDigest: QiWorkExchange.digest(Data("Existing".utf8)),
            sourceRevision: f.store.sourceRevision, selectionStart: 0, selectionLength: 8, state: .ready)
        try f.store.documentWork.save(pending)
        XCTAssertFalse(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { XCTFail("Pending proposal must remain reviewable"); return true }))
        XCTAssertEqual(f.store.documentWork.records.first?.state, .ready)
        pending.state = .dismissed; pending.updatedAt = Date()
        try f.store.documentWork.save(pending)
        XCTAssertFalse(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: {
            f.store.sharedText = "A newer edit"; return true
        }))
        XCTAssertEqual(f.store.sharedText, "A newer edit")
        XCTAssertNil(f.store.wikiOSTask)
        XCTAssertFalse(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: {
            f.store.prompt = "A newer question"; return true
        }))
        XCTAssertEqual(f.store.prompt, "A newer question")
        XCTAssertEqual(f.client.requests, 0)
        await f.store.shutdownAssistant()
    }

    @MainActor
    func testChangedSourcePackageCannotImportAndRestartDoesNotRestoreAssociation() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        XCTAssertTrue(f.store.stageWikiOSTask(from: f.file.url))
        let bytes = try Data(contentsOf: f.file.url)
        try (bytes + Data(" ".utf8)).write(to: f.file.url)
        XCTAssertFalse(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { true }))
        XCTAssertNil(f.store.sourceName)
        try bytes.write(to: f.file.url)
        XCTAssertTrue(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { true }))
        let reopened = CompanionStore(preferenceURL: f.root.appendingPathComponent("preferences.json"), assistant: ExchangeClient(), allowsPlay: false)
        XCTAssertNil(reopened.wikiOSTask)
        XCTAssertTrue(reopened.sharedText.isEmpty)
        XCTAssertNil(reopened.wikiOSExchangeReview)
        await reopened.shutdownAssistant()
        await f.store.shutdownAssistant()
    }

    @MainActor
    func testReturnBindsExactRequestAndCopyAndKeepsSeparateVerifiedExport() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let original = try Data(contentsOf: f.file.url)
        XCTAssertTrue(f.store.stageWikiOSTask(from: f.file.url))
        XCTAssertTrue(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { true }))
        f.store.sharedText = "Reviewed café 🌱 result"
        f.store.sourceRevision += 1
        XCTAssertTrue(f.store.hasUnexportedWorkingCopy)
        XCTAssertTrue(f.store.beginWikiOSReturnReview())
        guard case .outgoing(let preview) = f.store.wikiOSExchangeReview else { return XCTFail("Missing return review") }
        let saved = try f.store.exportWikiOSResult(preview, summary: "Prepared for owner review.", directory: f.root.appendingPathComponent("Outbox"))
        try saved.result.validate(request: f.file)
        XCTAssertEqual(saved.result.text, "Reviewed café 🌱 result")
        XCTAssertEqual(saved.result.requestSHA256, QiWorkExchange.digest(original))
        XCTAssertEqual(saved.result.taskRevision, "revision-7")
        XCTAssertFalse(f.store.hasUnexportedWorkingCopy)
        XCTAssertEqual(try Data(contentsOf: f.file.url), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.url.path))
        f.store.sharedText += " later"
        XCTAssertThrowsError(try f.store.exportWikiOSResult(preview, summary: "Stale", directory: f.root.appendingPathComponent("Outbox")))
        XCTAssertTrue(f.store.hasUnexportedWorkingCopy)
        XCTAssertEqual(f.client.requests, 0)
        await f.store.shutdownAssistant()
    }

    @MainActor
    func testChangingDocumentAndStoppingSharingClearReturnAuthority() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        XCTAssertTrue(f.store.stageWikiOSTask(from: f.file.url))
        XCTAssertTrue(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { true }))
        XCTAssertTrue(f.store.beginWikiOSReturnReview())
        guard case .outgoing(let preview) = f.store.wikiOSExchangeReview else { return XCTFail("Missing return review") }
        f.store.share(text: preview.text, name: preview.sourceName)
        XCTAssertNil(f.store.wikiOSTask)
        XCTAssertThrowsError(try f.store.exportWikiOSResult(preview, summary: "Unrelated", directory: f.root.appendingPathComponent("Outbox")))
        f.store.wikiOSExchangeReview = nil
        XCTAssertTrue(f.store.stageWikiOSTask(from: f.file.url))
        XCTAssertTrue(f.store.acceptWikiOSTask(f.file, reviewWorkingCopy: { true }))
        f.store.stopSharing()
        XCTAssertNil(f.store.wikiOSTask)
        XCTAssertFalse(f.store.beginWikiOSReturnReview())
        await f.store.shutdownAssistant()
    }

    @MainActor
    func testDeliveryRequiresExactAppIdentityAndIntegerCapability() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("archi-exchange-app-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("WikiOS.app")
        let info = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        func write(_ id: String, _ version: Any) throws {
            let bytes = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "QiWorkExchangeVersion": version], format: .xml, options: 0)
            try bytes.write(to: info)
        }
        try write("com.quotient.wikios.native", 1)
        XCTAssertNoThrow(try WikiOSExchangeDelivery.validateApplication(app))
        try write("com.quotient.wikios.native", true)
        XCTAssertThrowsError(try WikiOSExchangeDelivery.validateApplication(app))
        try write("com.quotient.wikios.native", 1.5)
        XCTAssertThrowsError(try WikiOSExchangeDelivery.validateApplication(app))
        try write("other.app", 1)
        XCTAssertThrowsError(try WikiOSExchangeDelivery.validateApplication(app))
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let client = ExchangeClient()
    let store: CompanionStore
    let file: QiWorkRequestFile
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("archi-task-exchange-\(UUID())")
        let brief = "Review the current project wording. No work has been completed."
        let request = QiWorkRequest(requestID: UUID().uuidString, taskID: "task-123", projectID: "project-456",
            projectName: "ARCHi", taskTitle: "Review project wording", taskRevision: "revision-7",
            createdAtUnix: Date().timeIntervalSince1970, brief: brief, briefSHA256: QiWorkExchange.digest(Data(brief.utf8)))
        let url = root.appendingPathComponent("request.qitask")
        try QiWorkExchange.writeNew(QiWorkExchange.encode(request), to: url)
        file = try QiWorkRequestFile.read(url)
        store = CompanionStore(preferenceURL: root.appendingPathComponent("preferences.json"), assistant: client,
            assistantFactory: { _, _ in ExchangeClient() }, allowsPlay: false)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class ExchangeClient: AssistantClient {
    var requests = 0
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws { requests += 1 }
}
