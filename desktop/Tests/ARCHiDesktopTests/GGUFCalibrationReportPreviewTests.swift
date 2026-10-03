import XCTest
@testable import ARCHiDesktop

final class GGUFCalibrationReportPreviewTests: XCTestCase {
    func testTaskReviewPassProjectsOnlyTheDeclaredSyntheticScope() throws {
        let bytes = try json(report())
        let preview = try load(bytes)
        XCTAssertEqual(preview.status, .limitedPass)
        XCTAssertEqual(preview.status.title, "Limited synthetic pass")
        XCTAssertEqual(preview.measurementScope, "synthetic-record-field-support/prompt-final/ridge-v1")
        XCTAssertEqual(preview.fitCount, 96)
        XCTAssertEqual(preview.calibrationCount, 24)
        XCTAssertEqual(preview.holdoutCorrect, 24)
        XCTAssertEqual(preview.holdoutAccuracy, 1)
        XCTAssertEqual(preview.minimumObservedHoldoutMargin, 1)
        XCTAssertEqual(preview.contentDigest, GGUFReaderArtifact.digest(bytes))
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(bytes), "A review report cannot become an imported reader")
    }

    func testFailedReviewRetainsIncorrectAndBelowMarginResults() throws {
        var value = report()
        value["status"] = "qualification-failed"
        value["holdoutCorrect"] = 23
        changeResult(&value, index: 24) { $0["rawScore"] = 2.5; $0["signedMargin"] = -1.0 }
        changeResult(&value, index: 25) { $0["rawScore"] = 0.6; $0["signedMargin"] = 0.05 }
        let preview = try load(json(value))
        XCTAssertEqual(preview.status, .failed)
        XCTAssertEqual(preview.holdoutCorrect, 23)
        XCTAssertEqual(preview.holdoutAccuracy, 23.0 / 24)
        XCTAssertEqual(preview.minimumObservedHoldoutMargin, -1)
        value["status"] = "limited-synthetic-pass"
        XCTAssertThrowsError(try load(json(value)))
        value = report()
        changeResult(&value, index: 25) { $0["rawScore"] = 0.6; $0["signedMargin"] = 0.05 }
        XCTAssertThrowsError(try load(json(value)), "Perfect sign accuracy is insufficient when a margin is below 0.1")
    }

    func testTaskReviewRejectsTamperedCountsIdentityAndCalibrationMath() throws {
        for (key, replacement): (String, Any) in [
            ("fitCount", 95), ("calibrationCorrect", 23), ("holdoutCorrect", 23),
            ("holdoutCount", 23), ("modelName", "qwen3:8b"), ("measurementScope", "general-truth"),
            ("status", "limited-shadow-pass"), ("candidateDigest", String(repeating: "A", count: 64)),
            ("qualificationDigest", "short"), ("planDigest", ""), ("minimumSignedMargin", 0.01),
            ("calibrationSeparation", 3), ("scoreOffset", 1), ("scoreScale", 0),
            ("scoreScale", 1e-13), ("scoreOffset", 1e7), ("scoreScale", "NaN")
        ] {
            var value = report()
            value[key] = replacement
            XCTAssertThrowsError(try load(json(value)), key)
        }
    }

    func testTaskReviewRejectsMalformedOrRepeatedRowsAndUnknownFields() throws {
        for (key, replacement): (String, Any) in [
            ("sampleID", "holdout-0"), ("sampleID", ""), ("split", "fit"), ("label", 0),
            ("rawScore", -3), ("signedMargin", 0.5), ("signedMargin", "Infinity"), ("extra", true)
        ] {
            var value = report()
            changeResult(&value, index: 0) { $0[key] = replacement }
            XCTAssertThrowsError(try load(json(value)), key)
        }
        var value = report()
        value["extra"] = true
        XCTAssertThrowsError(try load(json(value)))
        value = report()
        value.removeValue(forKey: "scoreOffset")
        XCTAssertThrowsError(try load(json(value)))
    }

    func testTaskReviewRejectsDuplicateKeysAndOversizedFiles() throws {
        let text = String(decoding: try json(report()), as: UTF8.self)
        let duplicateRoot = text.replacingOccurrences(of: "\"fitCount\":96", with: "\"fitCount\":96,\"fitCount\":96")
        XCTAssertThrowsError(try load(Data(duplicateRoot.utf8)))
        let duplicateRow = text.replacingOccurrences(of: "\"label\":-1", with: "\"label\":-1,\"label\":-1")
        XCTAssertThrowsError(try load(Data(duplicateRow.utf8)))
        XCTAssertThrowsError(try load(Data(repeating: 32, count: GGUFCalibrationReportPreview.maximumBytes + 1)))
    }

    private func load(_ bytes: Data) throws -> GGUFCalibrationReportPreview {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try bytes.write(to: url)
        return try GGUFCalibrationReportPreview.load(from: url)
    }

    private func json(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func changeResult(_ value: inout [String: Any], index: Int, change: (inout [String: Any]) -> Void) {
        var rows = value["results"] as! [[String: Any]]
        change(&rows[index])
        value["results"] = rows
    }

    private func report() -> [String: Any] {
        let rows: [[String: Any]] = ["calibration", "holdout"].flatMap { split in
            (0..<24).map { index in
                let label = index % 2 == 0 ? -1 : 1
                return ["sampleID": "\(split)-\(index)", "split": split, "label": label,
                        "rawScore": Double(label) * 2 + 0.5, "signedMargin": 1.0]
            }
        }
        return ["schema": "archi-task-reader-review/v1", "status": "limited-synthetic-pass",
            "modelName": "qwen3.5:9b", "measurementScope": "synthetic-record-field-support/prompt-final/ridge-v1",
            "fitCount": 96, "calibrationCount": 24, "calibrationCorrect": 24,
            "holdoutCount": 24, "holdoutCorrect": 24, "minimumSignedMargin": 0.1,
            "calibrationSeparation": 4.0, "scoreOffset": 0.5, "scoreScale": 2.0,
            "candidateDigest": String(repeating: "a", count: 64),
            "qualificationDigest": String(repeating: "b", count: 64),
            "planDigest": String(repeating: "c", count: 64), "results": rows,
            "limitations": ["Synthetic parser fixture only; no real reader qualification or native enablement."]]
    }
}
