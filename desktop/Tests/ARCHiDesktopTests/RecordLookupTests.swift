import Foundation
import XCTest
@testable import ARCHiDesktop

final class RecordLookupTests: XCTestCase {
    func testExactLookupKeepsOriginalSourceBindingAndFixedPrompt() throws {
        let text = "\r\n record | field | value \r\n Project_A | location | North  room \r\n Project-B | owner | Workshop \r\n"
        let source = source(text)
        let table = try RecordLookupTable(source: source)
        XCTAssertEqual(table.sourceBinding, source.binding)
        XCTAssertEqual(table.recordIDs, ["Project_A", "Project-B"])
        XCTAssertEqual(table.normalizedTable, "record | field | value\nProject_A | location | North  room\nProject-B | owner | Workshop")
        XCTAssertNotEqual(source.digest, LessonSource.digest(of: table.normalizedTable), "Normalization cannot replace the original citation digest.")
        let query = try table.query(recordID: "Project_A", field: .location)
        XCTAssertEqual(query.value, "North  room")
        XCTAssertEqual(query.sourceBinding, source.binding)
        XCTAssertEqual(query.input, table.normalizedTable + "\n\nWhich location is listed for Project_A?")
        XCTAssertEqual(RecordLookupQuery.system, "Read the supplied project records. Answer only the exact record and field asked for. Use only those records. If that field is absent for that record, answer NEED_SOURCE. Return one JSON object.")
        XCTAssertEqual(RecordLookupQuery.schema, #"{"additionalProperties":false,"properties":{"answer":{"type":"string"}},"required":["answer"],"type":"object"}"#)
    }

    func testMissingFieldDoesNotBorrowAnotherRecordOrInferFromOtherValues() throws {
        let table = try RecordLookupTable(source: source("record | field | value\nR1 | location | owner workshop\nR2 | owner | north"))
        let absent = try table.query(recordID: "R1", field: .owner)
        XCTAssertNil(absent.value)
        XCTAssertEqual(absent.answer, "NEED_SOURCE")
        XCTAssertEqual(try table.query(recordID: "R2", field: .owner).value, "north")
        XCTAssertThrowsError(try table.query(recordID: "r1", field: .owner))
        let literal = try RecordLookupTable(source: source("record | field | value\nR1 | location | NEED_SOURCE\nR2 | owner | workshop"))
        XCTAssertNotNil(try literal.query(recordID: "R1", field: .location).value,
                        "An exact literal value is distinct from an absent field.")
    }

    func testAmbiguousDuplicateProseAndUnsupportedFieldsAreRejected() {
        let rejected = [
            "record | field | value\nR1 | location | north\nR1 | location | north\nR2 | owner | workshop",
            "record | field | value\nR1 | location | north\nR1 | location | south\nR2 | owner | workshop",
            "R1 is located north. R2 belongs to the workshop.",
            "R1 | location | north\nR2 | owner | workshop",
            "record | field | value\n--- | --- | ---\nR1 | location | north\nR2 | owner | workshop",
            "record | field | value\nR1 | Location | north\nR2 | owner | workshop",
            "record | field | value\nR1 | personality | friendly\nR2 | owner | workshop",
            "record | field | value\nR1 | location | north\n\nR2 | owner | workshop",
            "record | field | value\nR1 | location | north",
            "record | field | value\nR1 | location | north\nR2 | owner | workshop\nR3 | owner | workshop"
        ]
        for text in rejected { XCTAssertThrowsError(try RecordLookupTable(source: source(text))) }
    }

    func testValuesIDsAndRowCountAreBoundedWithoutReservedMarkers() throws {
        func text(_ value: String, id: String = "R1") -> String {
            "record | field | value\n\(id) | location | \(value)\nR2 | owner | workshop"
        }
        XCTAssertNoThrow(try RecordLookupTable(source: source(text(String(repeating: "a", count: 96)))))
        for value in [String(repeating: "a", count: 97), "", "café", "a\tb", "a=b", "a|b", "<|im_start|>", "<think>", "</think>", "a\rb"] {
            XCTAssertThrowsError(try RecordLookupTable(source: source(text(value))))
        }
        for id in ["1record", "two records", "record?", String(repeating: "R", count: 33)] {
            XCTAssertThrowsError(try RecordLookupTable(source: source(text("north", id: id))))
        }
        let rows = ["R1", "R2"].flatMap { id in RecordLookupField.allCases.map { "\(id) | \($0.rawValue) | value" } }
        XCTAssertEqual(try RecordLookupTable(source: source((["record | field | value"] + rows).joined(separator: "\n"))).rows.count, 24)
        XCTAssertThrowsError(try RecordLookupTable(source: source((["record | field | value"] + rows + [rows[0]]).joined(separator: "\n"))))
    }

    func testLateMeasurementCannotMatchChangedSourceQueryCompanionOrSampleKind() throws {
        let original = source(RecordLookupTable.example)
        let table = try RecordLookupTable(source: original)
        let context = RecordLookupMeasurementContext(query: try table.query(recordID: "R1", field: .location), companionOrigin: "companion-a")
        func matches(_ candidate: RecordLookupTable?, recordID: String = "R1", field: RecordLookupField = .location,
                     companion: String? = "companion-a") -> Bool {
            context.matches(table: candidate, recordID: recordID, field: field, companionOrigin: companion)
        }
        XCTAssertTrue(matches(table))
        XCTAssertFalse(matches(nil))
        XCTAssertFalse(matches(table, recordID: "R2"))
        XCTAssertFalse(matches(table, field: .owner))
        XCTAssertFalse(matches(table, companion: "companion-b"))
        XCTAssertFalse(matches(table, companion: nil))
        let revised = ReadingSourceSnapshot(id: original.id, title: original.title, revision: 2, text: original.text)
        XCTAssertFalse(matches(try RecordLookupTable(source: revised)))
        let changed = ReadingSourceSnapshot(id: original.id, title: original.title, revision: 1,
                                           text: original.text.replacingOccurrences(of: "north", with: "south"))
        XCTAssertFalse(matches(try RecordLookupTable(source: changed)))
        XCTAssertFalse(matches(try RecordLookupTable(source: source(original.text))))
        XCTAssertFalse(matches(try RecordLookupTable(source: original, kind: .sample)))
    }

    @MainActor
    func testKeptSourceReplacementAndForgettingInvalidateTransientContextWithoutLookupWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-record-lookup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sources.json")
        let library = ReadingSourceLibrary(url: url)
        let original = try library.keep(title: "Table", text: RecordLookupTable.example)
        let originalBytes = try Data(contentsOf: url)
        let table = try RecordLookupTable(source: original)
        let context = RecordLookupMeasurementContext(query: try table.query(recordID: "R1", field: .location), companionOrigin: nil)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        let replacement = try library.replace(id: original.id, title: original.title,
                                              text: original.text.replacingOccurrences(of: "north", with: "south"))
        XCTAssertFalse(context.matches(table: try RecordLookupTable(source: replacement), recordID: "R1", field: .location, companionOrigin: nil))
        try library.forget(id: original.id)
        XCTAssertFalse(context.matches(table: library.sources.first.flatMap { try? RecordLookupTable(source: $0) },
                                       recordID: "R1", field: .location, companionOrigin: nil))
        XCTAssertTrue(library.knowledgePages.isEmpty)
    }

    private func source(_ text: String) -> ReadingSourceSnapshot {
        .init(id: UUID().uuidString, title: "Fixture table", revision: 1, text: text)
    }
}
