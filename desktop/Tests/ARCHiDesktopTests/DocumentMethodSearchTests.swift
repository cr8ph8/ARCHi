import Foundation
import XCTest
@testable import ARCHiDesktop

final class DocumentMethodSearchTests: XCTestCase {
    func testTaskWordsExcludeUnrelatedMethodDespiteItsEarlierLearnedOrder() throws {
        let unrelated = method("Dialogue", instruction: "Revise the selected passage to preserve character voice.")
        let useful = method("Meeting follow-up", instruction: "Clarify the owner of each commitment.")
        let result = try DocumentMethodSearch.search(query: "Please revise this text for meeting commitments.",
            orderedEligibleMethods: [unrelated, useful])
        XCTAssertEqual(result.hits.map(\.procedure), [useful])
        XCTAssertEqual(result.hits.first?.matchedTerms, ["meeting"])
        XCTAssertEqual(result.queryTerms, ["commitments", "meeting"])
        XCTAssertEqual(result.matchingCount, 1)
        XCTAssertEqual(result.omittedCount, 0)
    }

    func testTitleWeightAndEqualScoresPreserveSuppliedLearnedOrder() throws {
        let bodyOnly = method("Review details", instruction: "Describe budget changes.")
        let preferredTie = method("Budget planning", instruction: "Clarify decisions.")
        let laterTie = method("Budget discussion", instruction: "Clarify responsibilities.")
        let result = try DocumentMethodSearch.search(query: "Budget",
            orderedEligibleMethods: [bodyOnly, preferredTie, laterTie])
        XCTAssertEqual(result.hits.map(\.procedure), [preferredTie, laterTie, bodyOnly])
        XCTAssertEqual(result.hits.map(\.score), [2, 2, 1])
        let reversed = try DocumentMethodSearch.search(query: "Budget",
            orderedEligibleMethods: [laterTie, preferredTie, bodyOnly])
        XCTAssertEqual(reversed.hits.map(\.procedure), [laterTie, preferredTie, bodyOnly])
    }

    func testRepeatedWordsDoNotOutrankWiderDistinctCoverage() throws {
        let repetition = method("Budget budget budget", instruction: "Budget budget budget budget.")
        let wider = method("Budget timeline", instruction: "Explain the budget and timeline.")
        let result = try DocumentMethodSearch.search(query: "budget budget timeline timeline",
            orderedEligibleMethods: [repetition, wider])
        XCTAssertEqual(result.hits.map(\.procedure), [wider, repetition])
        XCTAssertEqual(result.hits.map(\.score), [6, 3])
        XCTAssertEqual(result.hits.first?.matchedTerms, ["budget", "timeline"])
    }

    func testEmptyBoilerplateAndAbsentWordsReturnNoCandidate() throws {
        let candidate = method("Dialogue", instruction: "Please revise the selected passage and preserve exact meaning.")
        for query in ["", " \n\t ", "Please revise the selected text and keep exact meaning.", "astronomy"] {
            let result = try DocumentMethodSearch.search(query: query, orderedEligibleMethods: [candidate])
            XCTAssertTrue(result.hits.isEmpty, query)
            XCTAssertEqual(result.matchingCount, 0)
            XCTAssertEqual(result.omittedCount, 0)
        }
    }

    func testNormalizationIsExactTokenMatchingWithoutStemming() throws {
        let candidate = method("CAFÉ planning", instruction: "Review a commitment.")
        let result = try DocumentMethodSearch.search(query: "café commitments",
            orderedEligibleMethods: [candidate])
        XCTAssertEqual(result.queryTerms, ["cafe", "commitments"])
        XCTAssertEqual(result.hits.first?.matchedTerms, ["cafe"])
        XCTAssertEqual(result.hits.first?.score, 2)
        let absent = try DocumentMethodSearch.search(query: "commitments", orderedEligibleMethods: [candidate])
        XCTAssertTrue(absent.hits.isEmpty)
    }

    func testQueryBoundsAndUnsupportedControlsAreRejected() throws {
        for query in [String(repeating: "a", count: 513), String(repeating: "é", count: 257),
                      (0..<33).map { "word\($0)" }.joined(separator: " "), "budget\u{0000}timeline"] {
            XCTAssertThrowsError(try DocumentMethodSearch.search(query: query, orderedEligibleMethods: [])) {
                XCTAssertEqual($0 as? DocumentMethodSearchError, .invalidQuery)
            }
        }
        XCTAssertNoThrow(try DocumentMethodSearch.search(query: String(repeating: "é", count: 256), orderedEligibleMethods: []))
        XCTAssertNoThrow(try DocumentMethodSearch.search(query: (0..<32).map { "word\($0)" }.joined(separator: " "), orderedEligibleMethods: []))
    }

    func testInvalidWithdrawnAndDuplicateMethodsFailBeforeEmptyQueryReturn() throws {
        let valid = method("Budget", instruction: "Explain allocations.")
        var withdrawn = valid
        withdrawn.withdrawn = true
        for invalid in [method("", instruction: "Explain allocations."),
                        method("Budget", instruction: "Explain allocations.", id: "invalid"), withdrawn] {
            XCTAssertThrowsError(try DocumentMethodSearch.search(query: "", orderedEligibleMethods: [valid, invalid])) {
                XCTAssertEqual($0 as? DocumentMethodSearchError, .invalidMethod)
            }
        }
        let sameIdentity = method("Another title", instruction: "Explain another allocation.", id: valid.id.lowercased())
        var nextVersion = DocumentProcedure(id: valid.id, revision: 2, title: "Budget revision",
            instruction: "Explain allocations.", mustBeShorter: false, preserveNumbersAndLinks: true,
            originRecordID: UUID().uuidString, originFeedbackID: UUID().uuidString,
            createdAt: valid.createdAt, withdrawn: false)
        nextVersion.supersedes = valid.binding
        nextVersion.revisionNote = "Clarified instruction."
        for duplicate in [valid, sameIdentity, nextVersion] {
            XCTAssertThrowsError(try DocumentMethodSearch.search(query: "", orderedEligibleMethods: [valid, duplicate])) {
                XCTAssertEqual($0 as? DocumentMethodSearchError, .duplicateMethod)
            }
        }
    }

    func testResultCapReportsAllMatchesAndMethodLimitFailsClosed() throws {
        let methods = (0..<64).map { method("Budget \($0)", instruction: "Explain allocations.") }
        let result = try DocumentMethodSearch.search(query: "budget", orderedEligibleMethods: methods)
        XCTAssertEqual(result.hits.map(\.procedure), Array(methods.prefix(5)))
        XCTAssertEqual(result.matchingCount, 64)
        XCTAssertEqual(result.omittedCount, 59)
        XCTAssertEqual(Set(result.hits.map(\.id)).count, 5)
        XCTAssertEqual(result.hits.first?.id,
                       "\(methods[0].id).\(methods[0].revision).\(methods[0].binding.digest)")
        XCTAssertThrowsError(try DocumentMethodSearch.search(query: "", orderedEligibleMethods: methods + [method("Budget", instruction: "Explain allocations.")])) {
            XCTAssertEqual($0 as? DocumentMethodSearchError, .methodLimit)
        }
    }

    private func method(_ title: String, instruction: String, id: String = UUID().uuidString) -> DocumentProcedure {
        DocumentProcedure(id: id, revision: 1, title: title, instruction: instruction,
            mustBeShorter: false, preserveNumbersAndLinks: true, originRecordID: UUID().uuidString,
            originFeedbackID: UUID().uuidString, createdAt: Date(timeIntervalSince1970: 900), withdrawn: false)
    }
}
