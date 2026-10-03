import Foundation

/// Checks the internal consistency of a supplied synthetic qualification report.
/// This does not authenticate its author or independently replay activations.
enum GGUFReaderQualification {
    static func validate(_ report: String, digest expectedDigest: String,
                         modelName: String, modelDigest: String, modelBlobDigest: String,
                         templateDigest: String, backendRevision: String, layer: String,
                         readerDigest: String, directions: [[Double]], center: [Double],
                         scoreOffset: [Double], scoreScale: [Double]) throws -> GGUFReaderCalibrationSummary {
        let bytes = Data(report.utf8)
        guard !bytes.isEmpty, bytes.count <= 64 * 1024,
              GGUFReaderArtifact.digest(bytes) == expectedDigest,
              GGUFReaderArtifact.hasUniqueKeys(bytes, maximumDepth: 16),
              let value = try? JSONDecoder().decode(Report.self, from: bytes),
              value.schema == "archi-gguf-reader-calibration/v1",
              value.status == "limited-shadow-pass", value.prefillOnly,
              value.qualificationEligible, value.plan.qualificationEligible,
              value.measurementScope == GGUFReaderArtifact.promptFinalMeasurementScope,
              value.tokenRule == "prompt-last",
              value.fitCount == 8, value.calibrationCount == 8, value.holdoutCount == 8,
              value.holdoutCorrect == 8, value.holdoutAccuracy == 1,
              value.calibrationSeparation.isFinite, value.calibrationSeparation > 0,
              value.minimumSignedMargin == 0.1,
              value.readerDigest == readerDigest,
              value.numericDigest == numericDigest(directions: directions, center: center,
                                                  offsets: scoreOffset, scales: scoreScale),
              [value.planDigest, value.activationDigest, value.acquisitionReceiptDigest,
               value.acquisitionStartDigest, value.frozenFitDigest, value.readerDigest,
               value.numericDigest].allSatisfy(LocalRepresentationBasis.digest),
              value.corpusProvenance == value.plan.corpusProvenance,
              value.corpusProvenance.isEligible,
              value.plan.modelName == modelName, value.plan.modelDigest == modelDigest,
              value.plan.modelBlobDigest == modelBlobDigest,
              value.plan.templateDigest == templateDigest,
              value.plan.backendRevision == backendRevision, value.plan.layer == layer,
              value.plan.isFixedProtocol,
              value.results.count == 16,
              scoreOffset.count == 1, scoreScale.count == 1, scoreScale[0] > 1e-12 else {
            throw GGUFReaderArtifactError.invalidCalibrationReport
        }
        let planBytes = Data(value.planPayload.utf8)
        guard planBytes.count <= 16 * 1024,
              GGUFReaderArtifact.digest(planBytes) == value.planDigest,
              GGUFReaderArtifact.hasUniqueKeys(planBytes, maximumDepth: 8),
              let frozenPlan = try? JSONDecoder().decode(Plan.self, from: planBytes),
              frozenPlan == value.plan,
              let outer = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let reportedPlan = outer["plan"] as? NSDictionary,
              let frozenObject = try? JSONSerialization.jsonObject(with: planBytes) as? NSDictionary,
              reportedPlan.isEqual(to: frozenObject as? [AnyHashable: Any] ?? [:]) else {
            throw GGUFReaderArtifactError.invalidCalibrationReport
        }
        var sampleIDs = Set<String>()
        var groups: [String: [Result]] = [:]
        for result in value.results {
            let standardized = (result.rawScore - scoreOffset[0]) / scoreScale[0]
            let signed = Double(result.label) * standardized
            let coordinate = 0.5 * (tanh(standardized / 2) + 1)
            guard ["calibration", "holdout"].contains(result.split),
                  [-1, 1].contains(result.label),
                  !result.sampleID.isEmpty, result.sampleID.utf8.count <= 128,
                  !result.group.isEmpty, result.group.utf8.count <= 128,
                  sampleIDs.insert(result.sampleID).inserted,
                  [result.rawScore, result.coordinate, result.signedMargin, standardized].allSatisfy(\.isFinite),
                  abs(result.signedMargin - signed) <= 1e-8 * max(1, abs(signed)),
                  abs(result.coordinate - coordinate) <= 1e-9,
                  result.signedMargin >= value.minimumSignedMargin,
                  result.correct, result.marginPass else {
                throw GGUFReaderArtifactError.invalidCalibrationReport
            }
            groups[result.group, default: []].append(result)
        }
        guard groups.count == 8, groups.values.allSatisfy({ pair in
            pair.count == 2 && Set(pair.map(\.label)) == [-1, 1] && Set(pair.map(\.split)).count == 1
        }), value.results.filter({ $0.split == "calibration" }).count == 8,
            value.results.filter({ $0.split == "holdout" }).count == 8 else {
            throw GGUFReaderArtifactError.invalidCalibrationReport
        }
        let calibration = value.results.filter { $0.split == "calibration" }
        let separation = calibration.filter { $0.label == 1 }.map(\.rawScore).min()!
            - calibration.filter { $0.label == -1 }.map(\.rawScore).max()!
        guard abs(separation - value.calibrationSeparation) <= 1e-8 * max(1, abs(separation)) else {
            throw GGUFReaderArtifactError.invalidCalibrationReport
        }
        return .init(fitCount: 8, calibrationCount: 8, holdoutCount: 8,
                     holdoutCorrect: 8, holdoutAccuracy: 1)
    }

    /// Language-independent numerical binding, shared with the local fitter.
    /// Fixed 4096 + 4096 + 1 + 1 Float64 values, IEEE754 little endian.
    static func numericDigest(directions: [[Double]], center: [Double], offsets: [Double], scales: [Double]) -> String {
        var data = Data("archi-reader-numerics/v1\n".utf8)
        for value in directions.flatMap({ $0 }) + center + offsets + scales {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return GGUFReaderArtifact.digest(data)
    }

    private struct Provenance: Decodable, Equatable {
        let kind: String
        let sourceDigest: String
        let corpusDigest: String
        let canonicalDigest: String
        let validation: String
        let pairInventory: String
        let priorExposure: String
        var isEligible: Bool {
            kind == "external-frozen-synthetic" && sourceDigest == corpusDigest &&
            [sourceDigest, corpusDigest, canonicalDigest].allSatisfy(LocalRepresentationBasis.digest) &&
            validation == "archi-synthetic-paired-corpus-validation/v1" &&
            pairInventory == "exact-lexical-words-and-punctuation" && priorExposure == "not-established"
        }
    }

    private struct Plan: Decodable, Equatable {
        let schema: String
        let algorithm: String
        let layer: String
        let tokenRule: String
        let measurementScope: String
        let hiddenWidth: Int
        let fitPairs: Int
        let calibrationPairs: Int
        let holdoutPairs: Int
        let minimumSignedMargin: Double
        let requiresPerfectCalibrationSeparation: Bool
        let requiresAllHoldoutCorrect: Bool
        let layerSearch: Bool
        let algorithmSearch: Bool
        let heldoutRetries: Bool
        let modelName: String
        let modelDigest: String
        let modelBlobDigest: String
        let templateDigest: String
        let backendRevision: String
        let datasetDigest: String
        let numericsSourceDigest: String
        let workflowSourceDigest: String
        let corpusSourceDigest: String
        let workerSourceDigest: String
        let runtimeRecipeDigest: String
        let requestDigest: String
        let qualificationEligible: Bool
        let corpusProvenance: Provenance
        var isFixedProtocol: Bool {
            schema == "archi-reader-plan/v1" && algorithm == "mean_contrast_reader" &&
            layer == "l_out-15" && tokenRule == "prompt-last" &&
            measurementScope == GGUFReaderArtifact.promptFinalMeasurementScope && hiddenWidth == 4096 &&
            fitPairs == 4 && calibrationPairs == 4 && holdoutPairs == 4 && minimumSignedMargin == 0.1 &&
            requiresPerfectCalibrationSeparation && requiresAllHoldoutCorrect &&
            !layerSearch && !algorithmSearch && !heldoutRetries &&
            [datasetDigest, numericsSourceDigest, workflowSourceDigest, corpusSourceDigest,
             workerSourceDigest, runtimeRecipeDigest, requestDigest].allSatisfy(LocalRepresentationBasis.digest)
        }
    }

    private struct Result: Decodable {
        let sampleID: String
        let group: String
        let split: String
        let label: Int
        let rawScore: Double
        let coordinate: Double
        let signedMargin: Double
        let correct: Bool
        let marginPass: Bool
    }

    private struct Report: Decodable {
        let schema: String
        let status: String
        let measurementScope: String
        let tokenRule: String
        let prefillOnly: Bool
        let qualificationEligible: Bool
        let corpusProvenance: Provenance
        let fitCount: Int
        let calibrationCount: Int
        let holdoutCount: Int
        let holdoutCorrect: Int
        let holdoutAccuracy: Double
        let calibrationSeparation: Double
        let minimumSignedMargin: Double
        let plan: Plan
        let planPayload: String
        let planDigest: String
        let activationDigest: String
        let acquisitionReceiptDigest: String
        let acquisitionStartDigest: String
        let frozenFitDigest: String
        let readerDigest: String
        let numericDigest: String
        let results: [Result]
    }
}
