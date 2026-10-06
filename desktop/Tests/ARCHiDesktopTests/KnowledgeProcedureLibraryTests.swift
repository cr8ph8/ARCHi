import Foundation
import CryptoKit
import XCTest
@testable import ARCHiDesktop

@MainActor
final class KnowledgeProcedureLibraryTests: XCTestCase {
    func testCandidateNeedsCurrentReviewedConceptAndIsIdempotentWithoutHelpfulEvidence() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let library = fixture.methods
        let page = fixture.page
        XCTAssertThrowsError(try library.keepCandidate(from: page, title: "Clarity", instruction: "Use direct verbs.",
            requirements: fixture.requirements))
        let draft = try XCTUnwrap(fixture.sources.knowledgePages.first)
        XCTAssertThrowsError(try library.keepCandidate(from: draft, title: "Clarity", instruction: "Use direct verbs.",
            requirements: fixture.requirements, knowledgeIsCurrent: { _ in true }))
        let claim = KnowledgePage(id: page.id, revision: page.revision, title: page.title, body: page.body,
            kind: .claim, anchors: page.anchors, state: page.state, createdAt: page.createdAt,
            updatedAt: page.updatedAt, review: page.review)
        XCTAssertThrowsError(try library.keepCandidate(from: claim, title: "Clarity", instruction: "Use direct verbs.",
            requirements: fixture.requirements, knowledgeIsCurrent: { _ in true }))
        let candidate = try fixture.candidate()
        XCTAssertEqual(candidate.knowledgeOrigin, page.binding)
        XCTAssertTrue(candidate.originRecordID.isEmpty)
        XCTAssertTrue(candidate.originFeedbackID.isEmpty)
        XCTAssertNil(library.availability(of: candidate, records: [], knowledgeIsCurrent: fixture.current))
        XCTAssertNotNil(library.availability(of: candidate, records: []), "Source checks default to deny.")
        let bytes = try Data(contentsOf: fixture.methodsURL)
        XCTAssertEqual(try fixture.candidate(), candidate)
        XCTAssertEqual(try Data(contentsOf: fixture.methodsURL), bytes)
        var rejected = appliedRecord()
        rejected.procedureUse = candidate.binding
        rejected.procedureUseRejected = true
        XCTAssertNotNil(library.availability(of: candidate, records: [rejected], knowledgeIsCurrent: fixture.current))
        try library.withdraw(binding: candidate.binding)
        XCTAssertTrue(try fixture.candidate().withdrawn, "Repeated saving cannot resurrect a withdrawn exact candidate.")
        XCTAssertEqual(library.procedures.count, 1)
    }

    func testDescendantsAndRevisionsRetainConceptAndCannotLaunderChangedSources() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let candidate = try fixture.candidate()
        var applied = appliedRecord()
        applied.procedureUse = candidate.binding
        XCTAssertThrowsError(try fixture.methods.keep(from: applied, title: "Derived", instruction: "Keep one idea per sentence.",
            records: [applied]))
        let child = try fixture.methods.keep(from: applied, title: "Derived", instruction: "Keep one idea per sentence.",
            records: [applied], knowledgeIsCurrent: fixture.current)
        XCTAssertEqual(child.knowledgeOrigin, candidate.knowledgeOrigin)
        let support = appliedRecord()
        let records = [applied, support]
        XCTAssertFalse(fixture.methods.canSupportRevision(of: candidate.binding, with: support, records: records))
        let rootRevision = try fixture.methods.revise(binding: candidate.binding, title: "Clarity refined",
            instruction: "Prefer precise direct verbs.", changeNote: "Refined after applied review.", from: support,
            records: records, knowledgeIsCurrent: fixture.current)
        let childRevision = try fixture.methods.revise(binding: child.binding, title: "Derived refined",
            instruction: "Use short sentences for separate ideas.", changeNote: "Refined after applied review.", from: support,
            records: records, knowledgeIsCurrent: fixture.current)
        XCTAssertEqual(rootRevision.knowledgeOrigin, candidate.knowledgeOrigin)
        XCTAssertEqual(childRevision.knowledgeOrigin, candidate.knowledgeOrigin)
        XCTAssertNil(fixture.methods.availability(of: childRevision, records: records, knowledgeIsCurrent: fixture.current))
        _ = try fixture.sources.replace(id: fixture.source.id, title: "Source", text: "Changed supporting text.")
        for method in [candidate, child, rootRevision, childRevision] {
            XCTAssertNotNil(fixture.methods.availability(of: method, records: records, knowledgeIsCurrent: fixture.current))
        }
        XCTAssertFalse(fixture.methods.canSupportRevision(of: childRevision.binding, with: support, records: records,
            knowledgeIsCurrent: fixture.current))
        XCTAssertThrowsError(try fixture.methods.revise(binding: childRevision.binding, title: "Unsafe repair",
            instruction: "Reuse without the old concept.", changeNote: "Must stay blocked.", from: support,
            records: records, knowledgeIsCurrent: fixture.current))
        let reopened = DocumentProcedureLibrary(url: fixture.methodsURL)
        XCTAssertNil(reopened.loadError)
        XCTAssertNotNil(reopened.availability(of: childRevision, records: records, knowledgeIsCurrent: fixture.current))

        let withdrawnFixture = try Fixture()
        defer { withdrawnFixture.clean() }
        let withdrawnCandidate = try withdrawnFixture.candidate()
        _ = try withdrawnFixture.sources.withdrawKnowledgePage(id: withdrawnFixture.page.id,
            expectedRevision: withdrawnFixture.page.revision)
        XCTAssertNotNil(withdrawnFixture.methods.availability(of: withdrawnCandidate, records: [],
            knowledgeIsCurrent: withdrawnFixture.current))
        XCTAssertThrowsError(try withdrawnFixture.candidate(), "The exact reviewed page cannot be silently upgraded after withdrawal.")
    }

    func testLegacyBindingsRemainExactAndLegacyFilesMigrateOnlyOnWrite() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let record = appliedRecord()
        let original = try fixture.methods.keep(from: record, title: "Existing", instruction: "Keep direct verbs.", records: [record])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let methodBytes = try encoder.encode(original)
        let methodObject = try XCTUnwrap(JSONSerialization.jsonObject(with: methodBytes) as? [String: Any])
        XCTAssertNil(methodObject["knowledgeOrigin"], "Nil must not alter the encoded bytes of prior methods.")
        XCTAssertEqual(original.binding.digest, SHA256.hash(data: methodBytes).map { String(format: "%02x", $0) }.joined())
        for schema in ["archi-document-procedures/v1", "archi-document-procedures/v2"] {
            let legacy = try JSONSerialization.data(withJSONObject: ["schema": schema, "procedures": [methodObject]], options: [.sortedKeys])
            try legacy.write(to: fixture.methodsURL, options: .atomic)
            let reopened = DocumentProcedureLibrary(url: fixture.methodsURL)
            XCTAssertNil(reopened.loadError)
            XCTAssertEqual(try XCTUnwrap(reopened.procedures.first).binding, original.binding)
            XCTAssertEqual(try Data(contentsOf: fixture.methodsURL), legacy)
            _ = try reopened.keepCandidate(from: fixture.page, title: "Candidate", instruction: "Try direct verbs.",
                requirements: fixture.requirements, knowledgeIsCurrent: fixture.current)
            XCTAssertEqual(try XCTUnwrap(reopened.procedures.first).binding, original.binding)
            let migrated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.methodsURL)) as? [String: Any])
            XCTAssertEqual(migrated["schema"] as? String, "archi-document-procedures/v3")
        }
    }

    func testRevisionCannotDropOrSubstituteTheSupportingMethodsKnowledgeOrigin() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let first = try fixture.candidate()
        let secondDraft = try fixture.sources.saveKnowledgePage(title: "Other concept", body: "Keep distinct ideas separate.",
            kind: .concept, anchors: fixture.page.anchors)
        let secondPage = try fixture.sources.reviewKnowledgePage(id: secondDraft.id, expectedRevision: secondDraft.revision)
        let second = try fixture.methods.keepCandidate(from: secondPage, title: "Second candidate",
            instruction: "Keep one idea per sentence.", requirements: fixture.requirements, knowledgeIsCurrent: fixture.current)
        let ordinaryOrigin = appliedRecord()
        let ordinary = try fixture.methods.keep(from: ordinaryOrigin, title: "Ordinary method",
            instruction: "Review sentence structure.", records: [ordinaryOrigin])
        var fromFirst = appliedRecord(); fromFirst.procedureUse = first.binding
        var fromSecond = appliedRecord(); fromSecond.procedureUse = second.binding
        var fromOrdinary = appliedRecord(); fromOrdinary.procedureUse = ordinary.binding
        let records = [ordinaryOrigin, fromFirst, fromSecond, fromOrdinary]
        for (previous, support) in [(ordinary, fromFirst), (first, fromSecond)] {
            XCTAssertFalse(fixture.methods.canSupportRevision(of: previous.binding, with: support, records: records,
                knowledgeIsCurrent: fixture.current))
            XCTAssertThrowsError(try fixture.methods.revise(binding: previous.binding, title: "Changed",
                instruction: "Use the newly supported approach.", changeNote: "Must not lose the source concept.",
                from: support, records: records, knowledgeIsCurrent: fixture.current))
        }
        let child = try fixture.methods.keep(from: fromFirst, title: "New family",
            instruction: "Try this independently named method.", records: records, knowledgeIsCurrent: fixture.current)
        XCTAssertEqual(child.knowledgeOrigin, first.knowledgeOrigin, "Keeping a new family retains the supporting origin.")
        XCTAssertTrue(fixture.methods.canSupportRevision(of: first.binding, with: fromOrdinary, records: records,
            knowledgeIsCurrent: fixture.current), "Ordinary corrective work can support a method that retains its concept.")
        let corrected = try fixture.methods.revise(binding: first.binding, title: "Corrected candidate",
            instruction: "Check sentence structure and direct verbs.", changeNote: "Refined through ordinary corrective work.",
            from: fromOrdinary, records: records, knowledgeIsCurrent: fixture.current)
        XCTAssertEqual(corrected.knowledgeOrigin, first.knowledgeOrigin)
        XCTAssertNil(fixture.methods.availability(of: corrected, records: records, knowledgeIsCurrent: fixture.current))

        // A syntactically valid single-version family still needs the live
        // journal to validate its cross-family origin dependency.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.methodsURL)) as? [String: Any])
        var rows = try XCTUnwrap(object["procedures"] as? [[String: Any]])
        let childIndex = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == child.id })
        rows[childIndex].removeValue(forKey: "knowledgeOrigin")
        object["procedures"] = rows
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: fixture.methodsURL)
        let reopened = DocumentProcedureLibrary(url: fixture.methodsURL)
        XCTAssertNil(reopened.loadError)
        let missingOrigin = try XCTUnwrap(reopened.procedures.first { $0.id == child.id })
        XCTAssertNotNil(reopened.availability(of: missingOrigin, records: records, knowledgeIsCurrent: fixture.current),
            "A forged descendant cannot omit a bound ancestor even while that ancestor remains current.")
    }

    func testKnowledgeArchivesRejectUnsupportedFieldsAndOriginErasureWithoutOverwriting() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let candidate = try fixture.candidate()
        let support = appliedRecord()
        _ = try fixture.methods.revise(binding: candidate.binding, title: "Refined", instruction: "Use precise verbs.",
            changeNote: "Refined candidate.", from: support, records: [support], knowledgeIsCurrent: fixture.current)
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.methodsURL)) as? [String: Any])
        let rows = try XCTUnwrap(base["procedures"] as? [[String: Any]])
        var corruptions: [[String: Any]] = []
        for version in ["archi-document-procedures/v1", "archi-document-procedures/v2"] {
            var changed = base; changed["schema"] = version; corruptions.append(changed)
        }
        var changed = base
        var edited = rows
        var binding = try XCTUnwrap(edited[0]["knowledgeOrigin"] as? [String: Any])
        binding["body"] = "Source prose must not enter this reference."
        edited[0]["knowledgeOrigin"] = binding; changed["procedures"] = edited; corruptions.append(changed)
        edited = rows; edited[1].removeValue(forKey: "knowledgeOrigin")
        changed = base; changed["procedures"] = edited; corruptions.append(changed)
        edited = rows; edited[0].removeValue(forKey: "knowledgeOrigin")
        changed = base; changed["procedures"] = edited; corruptions.append(changed)
        edited = rows; edited[0]["originFeedbackID"] = UUID().uuidString
        changed = base; changed["procedures"] = edited; corruptions.append(changed)
        for object in corruptions {
            let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try bytes.write(to: fixture.methodsURL, options: .atomic)
            let blocked = DocumentProcedureLibrary(url: fixture.methodsURL)
            XCTAssertNotNil(blocked.loadError)
            XCTAssertThrowsError(try blocked.keepCandidate(from: fixture.page, title: "New", instruction: "Try again.",
                requirements: fixture.requirements, knowledgeIsCurrent: fixture.current))
            XCTAssertEqual(try Data(contentsOf: fixture.methodsURL), bytes)
        }
    }

    private func appliedRecord() -> DocumentWorkRecord {
        let request = UUID().uuidString
        let date = Date().addingTimeInterval(1)
        return DocumentWorkRecord(id: request + "-Qwen", requestID: request, provider: "Qwen", targetID: UUID().uuidString,
            sourceDigest: String(repeating: "a", count: 64), sourceRevision: 1, selectionStart: 0, selectionLength: 12,
            preserveNumbersAndLinks: true, createdAt: date, updatedAt: date, state: .applied,
            proposedDigest: String(repeating: "b", count: 64), expectedAfterDigest: String(repeating: "c", count: 64),
            actualAfterDigest: String(repeating: "c", count: 64), afterRevision: 2,
            checks: [.init(id: "source", title: "Exact source", passed: true)],
            learning: .init(requestBinding: .init(inputDigest: String(repeating: "d", count: 64),
                                                   contextDigest: String(repeating: "e", count: 64))),
            feedback: .init(revision: 1, verdict: .helpful, recordedAt: date))
    }

    @MainActor
    private struct Fixture {
        let directory: URL
        let sources: ReadingSourceLibrary
        let source: ReadingSourceSnapshot
        let page: KnowledgePage
        let methods: DocumentProcedureLibrary
        let requirements = DocumentWorkRequirements(mustBeShorter: false, preserveNumbersAndLinks: true)
        var methodsURL: URL { directory.appendingPathComponent("methods.json") }

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-knowledge-method-\(UUID().uuidString)")
            sources = ReadingSourceLibrary(url: directory.appendingPathComponent("sources.json"))
            source = try sources.keep(title: "Source", text: "Prefer clear direct verbs.")
            let anchor = try sources.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
            let draft = try sources.saveKnowledgePage(title: "Direct language", body: "A direct verb can make an action clearer.",
                kind: .concept, anchors: [anchor])
            page = try sources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
            methods = DocumentProcedureLibrary(url: directory.appendingPathComponent("methods.json"))
        }

        func current(_ binding: KnowledgePageBinding) -> Bool {
            guard let page = sources.latestKnowledgePages.first(where: { $0.binding == binding }) else { return false }
            return page.kind == .concept && sources.availability(of: page) == nil
        }

        func candidate() throws -> DocumentProcedure {
            try methods.keepCandidate(from: page, title: "Clarity", instruction: "Use direct verbs.",
                requirements: requirements, knowledgeIsCurrent: current)
        }

        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
}
