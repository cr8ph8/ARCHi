import Foundation
import XCTest
@testable import ARCHiDesktop

final class DocumentWorkCapabilityTests: XCTestCase {
    func testUTF16TargetChangesOnlySelectedDuplicateAndPredictsExactDigest() throws {
        let quote = "Keep all 12 items at https://example.test/items"
        let text = "😀 Opening\r\n\(quote)\r\n\(quote)\r\nCafé"
        let selected = (text as NSString).range(of: quote, options: .backwards)
        let target = try makeTarget(text, range: selected)
        let replacement = "12 items: https://example.test/items"
        let requirements = DocumentWorkRequirements(mustBeShorter: true)
        let result = DocumentWorkCapability.verify(proposal: proposal(target, replacement), text: text,
                                                   sourceRevision: 3, requirements: requirements)
        let expected = "😀 Opening\r\n\(quote)\r\n\(replacement)\r\nCafé"
        XCTAssertTrue(result.canApply)
        XCTAssertTrue(result.checks.allSatisfy(\.passed))
        XCTAssertEqual(result.predictedDigest, WorkingCopyEditReceipt.digest(expected))
        XCTAssertEqual(requirements.input["mustBeShorter"], .bool(true))
        XCTAssertEqual(requirements.input["preserveNumbersAndLinks"], .bool(true))
    }

    func testNumberAndURLPreservationUsesExactTokensAndMultisets() throws {
        let text = "Pay 1,000.00 for 2 items; keep 2 backups. See https://example.test/cafe\u{301}"
        let target = try makeTarget(text)
        let preserved = "Keep 2 backups and 2 items for 1,000.00. See https://example.test/cafe\u{301}"
        let good = DocumentWorkCapability.verify(proposal: proposal(target, preserved), text: text,
                                                 sourceRevision: 3, requirements: .init())
        XCTAssertTrue(good.canApply, "Token order may change while exact tokens and multiplicities are retained.")
        let changes: [(String, String)] = [
            (preserved.replacingOccurrences(of: "1,000.00", with: "1000.00"), "numbers"),
            ("Keep backups and 2 items for 1,000.00. See https://example.test/cafe\u{301}", "numbers"),
            (preserved.replacingOccurrences(of: "example.test", with: "other.test"), "links"),
            (preserved.precomposedStringWithCanonicalMapping, "links")
        ]
        for (replacement, failedCheck) in changes {
            let checked = DocumentWorkCapability.verify(proposal: proposal(target, replacement), text: text,
                                                        sourceRevision: 3, requirements: .init())
            XCTAssertFalse(checked.canApply)
            XCTAssertEqual(checked.checks.first { $0.id == failedCheck }?.passed, false)
        }
        let allowed = DocumentWorkCapability.verify(proposal: proposal(target, "New wording"), text: text,
            sourceRevision: 3, requirements: .init(preserveNumbersAndLinks: false))
        XCTAssertTrue(allowed.canApply)
    }

    func testShorteningCountsCharactersAndStaleSourceCannotApply() throws {
        let text = "👨‍👩‍👧‍👦👩‍💻"
        let target = try makeTarget(text)
        let edit = proposal(target, "abc")
        let checked = DocumentWorkCapability.verify(proposal: edit, text: text,
            sourceRevision: 3, requirements: .init(mustBeShorter: true))
        XCTAssertFalse(checked.canApply, "Fewer bytes or scalars do not mean fewer user-perceived characters.")
        XCTAssertEqual(checked.checks.first { $0.id == "shorter" }?.passed, false)
        for (current, revision) in [(text + "!", UInt64(3)), (text, UInt64(4))] {
            let stale = DocumentWorkCapability.verify(proposal: edit, text: current,
                                                      sourceRevision: revision, requirements: .init())
            XCTAssertFalse(stale.canApply)
            XCTAssertNil(stale.predictedDigest)
            XCTAssertEqual(stale.checks.first { $0.id == "source" }?.passed, false)
        }
        let original = "Å"
        let normalizedTarget = try makeTarget(original)
        let differentBytes = DocumentWorkCapability.verify(proposal: proposal(normalizedTarget, "A"), text: "Å",
                                                           sourceRevision: 3, requirements: .init())
        XCTAssertFalse(differentBytes.canApply, "Canonical string equality cannot substitute for the source digest.")
    }

    func testNonProposalsAndOversizedResultsStayUnavailable() throws {
        let target = try makeTarget("Original")
        for decision in [RevisionDecision.clarify, .abstain] {
            let checked = DocumentWorkCapability.verify(proposal: proposal(target, "", decision: decision), text: "Original",
                                                        sourceRevision: 3, requirements: .init(mustBeShorter: true))
            XCTAssertFalse(checked.canApply)
            XCTAssertNil(checked.predictedDigest)
            XCTAssertEqual(checked.checks.count, 1, "Non-edit decisions should not present irrelevant failed edit checks.")
        }
        let invalid = DocumentWorkCapability.verify(proposal: proposal(target, "Original"), text: "Original",
                                                    sourceRevision: 3, requirements: .init())
        XCTAssertFalse(invalid.canApply)
        XCTAssertEqual(invalid.checks.first { $0.id == "proposal" }?.passed, false)
        let full = "x" + String(repeating: "y", count: 99_999)
        let fullTarget = try makeTarget(full, range: NSRange(location: 0, length: 1))
        let oversized = DocumentWorkCapability.verify(proposal: proposal(fullTarget, "😀"), text: full,
                                                      sourceRevision: 3, requirements: .init())
        XCTAssertFalse(oversized.canApply)
        XCTAssertNil(oversized.predictedDigest)
        XCTAssertEqual(oversized.checks.first { $0.id == "size" }?.passed, false)
    }

    private func makeTarget(_ text: String, range: NSRange? = nil) throws -> RevisionTarget {
        let selection = try XCTUnwrap(DocumentSelection(range: range ?? NSRange(location: 0, length: text.utf16.count),
                                                       text: text, sourceRevision: 3))
        return try XCTUnwrap(RevisionTarget(text: text, sourceRevision: 3, selection: selection))
    }

    private func proposal(_ target: RevisionTarget, _ replacement: String,
                          decision: RevisionDecision = .propose) -> PassageRevisionProposal {
        PassageRevisionProposal(target: target, decision: decision, replacement: replacement,
                                explanation: "A proposed passage revision.", sourceIDs: [], memoryIDs: [])
    }
}
