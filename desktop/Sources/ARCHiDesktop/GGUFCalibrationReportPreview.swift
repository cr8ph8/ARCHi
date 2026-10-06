import Foundation

/// An inspectable report projection only. It has no reader, model-client,
/// persistence, companion, or setting-changing operation.
struct GGUFCalibrationReportPreview: Sendable {
    enum Status: String, Decodable, Sendable {
        case limitedPass = "limited-shadow-pass"
        case failed = "qualification-failed"

        var title: String { self == .failed ? "Qualification failed" : "Limited synthetic pass" }
    }

    static let maximumBytes = 128 * 1024
    let filename: String
    let contentDigest: String
    let modelName: String
    let status: Status
    let measurementScope: String
    let fitCount: Int
    let calibrationCount: Int
    let holdoutCount: Int
    let holdoutCorrect: Int
    let holdoutAccuracy: Double
    let minimumSignedMargin: Double?
    let minimumObservedHoldoutMargin: Double?
    let limitations: [String]

    static func load(from url: URL) throws -> Self {
        guard url.isFileURL else { throw PreviewError.invalid }
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              let size = properties.fileSize, size > 0, size <= maximumBytes else { throw PreviewError.invalid }
        let bytes = try Data(contentsOf: url)
        guard !bytes.isEmpty, bytes.count <= maximumBytes,
              GGUFReaderArtifact.hasUniqueKeys(bytes, maximumDepth: 16),
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw PreviewError.invalid
        }
        if object["schema"] as? String == "archi-task-reader-review/v1" {
            return try taskReview(bytes, filename: url.lastPathComponent, object: object)
        }
        guard let report = try? JSONDecoder().decode(Report.self, from: bytes),
              report.schema == "archi-gguf-reader-calibration/v1",
              report.tokenRule == "prompt-last", report.prefillOnly != false,
              report.measurementScope == GGUFReaderArtifact.promptFinalMeasurementScope,
              (1...24).contains(report.fitCount), (1...24).contains(report.calibrationCount),
              (1...24).contains(report.holdoutCount),
              report.fitCount + report.calibrationCount + report.holdoutCount <= 24,
              (0...report.holdoutCount).contains(report.holdoutCorrect),
              report.holdoutAccuracy.isFinite, (0...1).contains(report.holdoutAccuracy),
              abs(report.holdoutAccuracy - Double(report.holdoutCorrect) / Double(report.holdoutCount)) <= 1e-9,
              validLabel(report.plan.modelName, maximum: 160),
              report.minimumSignedMargin.map({ $0.isFinite && (0...1e6).contains($0) }) ?? true,
              (report.limitations?.count ?? 0) <= 16,
              report.limitations?.allSatisfy({ validLabel($0, maximum: 2_000) }) ?? true else {
            throw PreviewError.invalid
        }
        if report.status == .limitedPass {
            guard report.holdoutCount >= 8, report.holdoutCorrect == report.holdoutCount else {
                throw PreviewError.invalid
            }
        }
        var minimumObserved: Double?
        if let results = report.results {
            guard results.count <= 24,
                  results.allSatisfy({ ["fit", "calibration", "holdout"].contains($0.split)
                      && $0.signedMargin.isFinite && abs($0.signedMargin) <= 1e12 }) else {
                throw PreviewError.invalid
            }
            let heldout = results.filter { $0.split == "holdout" }
            guard heldout.count == report.holdoutCount,
                  heldout.filter({ $0.signedMargin > 0 }).count == report.holdoutCorrect else {
                throw PreviewError.invalid
            }
            if report.status == .limitedPass, let requiredMargin = report.minimumSignedMargin {
                guard results.filter({ $0.split != "fit" }).allSatisfy({ $0.signedMargin >= requiredMargin }) else {
                    throw PreviewError.invalid
                }
            }
            minimumObserved = heldout.map(\.signedMargin).min()
        }
        return Self(filename: url.lastPathComponent, contentDigest: GGUFReaderArtifact.digest(bytes),
            modelName: report.plan.modelName, status: report.status, measurementScope: report.measurementScope,
            fitCount: report.fitCount, calibrationCount: report.calibrationCount,
            holdoutCount: report.holdoutCount, holdoutCorrect: report.holdoutCorrect,
            holdoutAccuracy: report.holdoutAccuracy, minimumSignedMargin: report.minimumSignedMargin,
            minimumObservedHoldoutMargin: minimumObserved, limitations: report.limitations ?? [])
    }

    private static func taskReview(_ bytes: Data, filename: String, object: [String: Any]) throws -> Self {
        let fields: Set<String> = ["schema", "status", "modelName", "measurementScope", "fitCount",
            "calibrationCount", "calibrationCorrect", "holdoutCount", "holdoutCorrect", "minimumSignedMargin",
            "calibrationSeparation", "scoreOffset", "scoreScale", "results", "candidateDigest", "qualificationDigest", "planDigest", "limitations"]
        let resultFields: Set<String> = ["sampleID", "split", "label", "rawScore", "signedMargin"]
        guard Set(object.keys) == fields,
              let rows = object["results"] as? [[String: Any]], rows.count == 48,
              rows.allSatisfy({ Set($0.keys) == resultFields }),
              let report = try? JSONDecoder().decode(TaskReview.self, from: bytes),
              ["limited-synthetic-pass", "qualification-failed"].contains(report.status),
              report.modelName == "qwen3.5:9b",
              report.measurementScope == "synthetic-record-field-support/prompt-final/ridge-v1",
              report.fitCount == 96, report.calibrationCount == 24, report.holdoutCount == 24,
              (0...24).contains(report.calibrationCorrect), (0...24).contains(report.holdoutCorrect),
              report.minimumSignedMargin == 0.1, report.calibrationSeparation.isFinite,
              [report.scoreOffset, report.scoreScale].allSatisfy({ $0.isFinite && abs($0) <= 1e6 }),
              report.scoreScale >= 1e-12,
              [report.candidateDigest, report.qualificationDigest, report.planDigest].allSatisfy(LocalRepresentationBasis.digest),
              (1...16).contains(report.limitations.count),
              report.limitations.allSatisfy({ validLabel($0, maximum: 2_000) }),
              report.results.count == 48 else { throw PreviewError.invalid }
        var identifiers = Set<String>()
        let signedMargin = { (result: TaskReview.Result) in
            Double(result.label) * (result.rawScore - report.scoreOffset) / report.scoreScale
        }
        for result in report.results {
            let margin = signedMargin(result)
            guard validLabel(result.sampleID, maximum: 128), identifiers.insert(result.sampleID).inserted,
                  ["calibration", "holdout"].contains(result.split), [-1, 1].contains(result.label),
                  result.rawScore.isFinite, result.signedMargin.isFinite, margin.isFinite,
                  abs(result.signedMargin - margin) <= 1e-8 * max(1, abs(margin)) else { throw PreviewError.invalid }
        }
        let calibration = report.results.filter { $0.split == "calibration" }
        let holdout = report.results.filter { $0.split == "holdout" }
        guard calibration.count == report.calibrationCount, holdout.count == report.holdoutCount,
              calibration.filter({ signedMargin($0) > 0 }).count == report.calibrationCorrect,
              holdout.filter({ signedMargin($0) > 0 }).count == report.holdoutCorrect,
              let positiveMinimum = calibration.filter({ $0.label == 1 }).map(\.rawScore).min(),
              let negativeMaximum = calibration.filter({ $0.label == -1 }).map(\.rawScore).max(),
              Set(holdout.map(\.label)) == [-1, 1] else { throw PreviewError.invalid }
        let separation = positiveMinimum - negativeMaximum
        guard separation.isFinite,
              abs(separation - report.calibrationSeparation) <= 1e-8 * max(1, abs(separation)) else {
            throw PreviewError.invalid
        }
        let passed = report.status == "limited-synthetic-pass"
        if passed {
            guard separation > 0, report.calibrationCorrect == 24, report.holdoutCorrect == 24,
                  report.results.allSatisfy({ $0.signedMargin >= report.minimumSignedMargin
                      && signedMargin($0) >= report.minimumSignedMargin }) else {
                throw PreviewError.invalid
            }
        }
        return Self(filename: filename, contentDigest: GGUFReaderArtifact.digest(bytes), modelName: report.modelName,
            status: passed ? .limitedPass : .failed, measurementScope: report.measurementScope,
            fitCount: report.fitCount, calibrationCount: report.calibrationCount,
            holdoutCount: report.holdoutCount, holdoutCorrect: report.holdoutCorrect,
            holdoutAccuracy: Double(report.holdoutCorrect) / Double(report.holdoutCount),
            minimumSignedMargin: report.minimumSignedMargin,
            minimumObservedHoldoutMargin: holdout.map(signedMargin).min(), limitations: report.limitations)
    }

    private static func validLabel(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private struct Report: Decodable {
        struct Plan: Decodable { let modelName: String }
        struct Result: Decodable { let split: String; let signedMargin: Double }
        let schema: String
        let status: Status
        let measurementScope: String
        let tokenRule: String
        let prefillOnly: Bool?
        let fitCount: Int
        let calibrationCount: Int
        let holdoutCount: Int
        let holdoutCorrect: Int
        let holdoutAccuracy: Double
        let plan: Plan
        let minimumSignedMargin: Double?
        let limitations: [String]?
        let results: [Result]?
    }

    private struct TaskReview: Decodable {
        struct Result: Decodable {
            let sampleID: String
            let split: String
            let label: Int
            let rawScore: Double
            let signedMargin: Double
        }
        let status: String
        let modelName: String
        let measurementScope: String
        let fitCount: Int
        let calibrationCount: Int
        let calibrationCorrect: Int
        let holdoutCount: Int
        let holdoutCorrect: Int
        let minimumSignedMargin: Double
        let calibrationSeparation: Double
        let scoreOffset: Double
        let scoreScale: Double
        let results: [Result]
        let candidateDigest: String
        let qualificationDigest: String
        let planDigest: String
        let limitations: [String]
    }

    enum PreviewError: Error, LocalizedError {
        case invalid
        var errorDescription: String? {
            "Choose a regular calibration report JSON file no larger than 128 KiB with the supported prompt-final scope and consistent counts, accuracy, and status."
        }
    }
}
