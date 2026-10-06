import XCTest
@testable import ARCHiDesktop

final class CompanionResonanceTests: XCTestCase {
    func testEveryRecordTypeHasDistinctFinitePitchInExistingHarmony() throws {
        let assignments = CompanionGraphKind.allCases.map(CompanionResonance.forKind)
        XCTAssertEqual(assignments.count, CompanionGraphKind.allCases.count)
        XCTAssertEqual(Set(assignments.map(\.midiNote)).count, assignments.count)
        XCTAssertEqual(Set(assignments.map(\.noteName)).count, assignments.count)
        for assignment in assignments {
            XCTAssertTrue(HarmonyCue.pitchClasses.contains(assignment.midiNote % 12))
            XCTAssertTrue(assignment.frequencyHz.isFinite)
            XCTAssertGreaterThan(assignment.frequencyHz, 0)
            XCTAssertLessThan(assignment.frequencyHz, Double(HarmonySynth.sampleRate) / 4)
            XCTAssertEqual(assignment.frequencyHz,
                           try XCTUnwrap(HarmonySynth.frequency(forMIDINote: assignment.midiNote)),
                           accuracy: 1e-12)
        }
    }

    func testCatalogueAssignmentsArePinnedIndependentOfEnumerationOrder() {
        let expected: [(CompanionGraphKind, Int, String, CompanionBrainwaveBand)] = [
            (.companion, 60, "C4", .alpha), (.source, 48, "C3", .delta),
            (.knowledge, 50, "D3", .theta), (.lesson, 52, "E3", .theta),
            (.method, 55, "G3", .beta), (.request, 57, "A3", .alpha),
            (.invocation, 62, "D4", .beta), (.answer, 64, "E4", .alpha),
            (.context, 67, "G4", .theta), (.omission, 69, "A4", .delta),
            (.evaluation, 72, "C5", .gamma), (.accounting, 74, "D5", .beta)
        ]
        XCTAssertEqual(Set(expected.map { $0.0 }), Set(CompanionGraphKind.allCases))
        for (kind, midiNote, name, band) in expected.reversed() {
            let assignment = CompanionResonance.forKind(kind)
            XCTAssertEqual(assignment.kind, kind)
            XCTAssertEqual(assignment.midiNote, midiNote)
            XCTAssertEqual(assignment.noteName, name)
            XCTAssertEqual(assignment.brainwaveBand, band)
        }
    }

    func testBandsAreFiniteReusedDesignLabels() {
        let assignments = CompanionGraphKind.allCases.map(CompanionResonance.forKind)
        let usedBands = Set(assignments.map(\.brainwaveBand))
        XCTAssertEqual(usedBands, Set(CompanionBrainwaveBand.allCases))
        XCTAssertEqual(usedBands.count, 5)
        XCTAssertLessThan(usedBands.count, assignments.count)
        XCTAssertTrue(CompanionResonance.associationLabel.lowercased().contains("designed"))
        XCTAssertTrue(CompanionResonance.associationExplanation.contains("do not measure brain activity"))
        XCTAssertTrue(CompanionBrainwaveBand.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testBindingsPreserveDifferentRecordIdentitiesWhileReusingTypeAssignment() throws {
        let graph = snapshot([node("lesson-one", kind: .lesson), node("lesson-two", kind: .lesson)])
        let first = try XCTUnwrap(CompanionResonance.forNodeID("lesson-one", in: graph))
        let second = try XCTUnwrap(CompanionResonance.forNodeID("lesson-two", in: graph))
        XCTAssertEqual(first.id, "lesson-one")
        XCTAssertEqual(second.id, "lesson-two")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.resonance, second.resonance)
        XCTAssertTrue(graph.edges.isEmpty)
    }

    func testDisplayChangesAndSnapshotOrderCannotChangeNodeAssignment() throws {
        let original = node("stable-record", kind: .knowledge)
        let firstGraph = snapshot([original, node("another", kind: .answer)])
        let changed = CompanionGraphNode(id: original.id, title: "Corrected title", subtitle: "Changed summary",
                                        kind: original.kind, status: "Source unavailable", details: [], target: nil)
        let secondGraph = snapshot([node("another", kind: .answer), changed])
        let first = try XCTUnwrap(CompanionResonance.forNodeID(original.id, in: firstGraph))
        XCTAssertEqual(first, CompanionResonance.forNodeID(original.id, in: secondGraph))
        XCTAssertEqual(firstGraph.nodes.first, original)
    }

    func testMissingEmptyMismatchedAndAmbiguousIDsCannotAcquireAssignment() {
        let valid = node("lesson-one", kind: .lesson)
        let graph = snapshot([valid])
        for invalidID in ["", " \n", "missing", "lesson-one ", "Lesson-one"] {
            XCTAssertNil(CompanionResonance.forNodeID(invalidID, in: graph))
        }
        XCTAssertNil(CompanionResonance.forNodeID("", in: snapshot([node("", kind: .lesson)])))
        XCTAssertNil(CompanionResonance.forNodeID(" \n", in: snapshot([node(" \n", kind: .lesson)])))
        XCTAssertNil(CompanionResonance.forNodeID(valid.id, in: .empty))
        XCTAssertNil(CompanionResonance.forNodeID(valid.id, in: snapshot([valid, valid])))
        XCTAssertNil(CompanionResonance.forNodeID(valid.id, in: snapshot([valid, node(valid.id, kind: .source)])))
    }

    private func node(_ id: String, kind: CompanionGraphKind) -> CompanionGraphNode {
        .init(id: id, title: "Record", subtitle: "Saved record", kind: kind,
              status: "Recorded", details: [], target: nil)
    }

    private func snapshot(_ nodes: [CompanionGraphNode]) -> CompanionGraphSnapshot {
        .init(nodes: nodes, edges: [], truncatedCount: 0)
    }
}
