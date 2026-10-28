import Foundation

/// A pure advisory calculation. Existing memory and candidate owners supply
/// current source bindings and eligibility; this type neither retains memories
/// nor grants permission to select, execute, learn from, or publish a candidate.
enum ContextualMemoryInfluence {
    static let schema = "contextual-memory-influence/v1"
    static let maximumInputs = 256

    enum Polarity: Int, Codable, CaseIterable, Sendable {
        case detraction = -1
        case neutral = 0
        case attraction = 1

        var title: String {
            switch self {
            case .detraction: "Detraction"
            case .neutral: "Neutral"
            case .attraction: "Attraction"
            }
        }
    }

    /// A sign belongs to a memory's relationship to one target in one scope.
    /// Nil means unassessed. Zero is an explicit, assessed neutral relation.
    struct Assessment: Codable, Equatable, Sendable {
        let scope: String
        let targetID: String
        let polarity: Polarity?
        let magnitude: Double
        let confidence: Double
        let retrievalSalience: Double

        init(scope: String, targetID: String, polarity: Polarity? = nil,
             magnitude: Double = 1, confidence: Double = 1,
             retrievalSalience: Double = 1) {
            self.scope = scope
            self.targetID = targetID
            self.polarity = polarity
            self.magnitude = magnitude
            self.confidence = confidence
            self.retrievalSalience = retrievalSalience
        }

        var isValid: Bool {
            validIdentifier(scope, maximumBytes: 96)
                && validIdentifier(targetID)
                && unitInterval(magnitude) && unitInterval(confidence)
                && unitInterval(retrievalSalience)
        }

        private enum CodingKeys: String, CodingKey {
            case scope, targetID, polarity, magnitude, confidence, retrievalSalience
        }

        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: AnyKey.self)
            let keys = Set(fields.allKeys.map(\.stringValue))
            let required: Set<String> = ["scope", "targetID", "magnitude", "confidence", "retrievalSalience"]
            guard required.isSubset(of: keys), keys.isSubset(of: required.union(["polarity"])) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Unsupported memory influence assessment fields."))
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(scope: try c.decode(String.self, forKey: .scope),
                      targetID: try c.decode(String.self, forKey: .targetID),
                      polarity: try c.decodeIfPresent(Polarity.self, forKey: .polarity),
                      magnitude: try c.decode(Double.self, forKey: .magnitude),
                      confidence: try c.decode(Double.self, forKey: .confidence),
                      retrievalSalience: try c.decode(Double.self, forKey: .retrievalSalience))
            guard isValid else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Invalid memory influence assessment."))
            }
        }
    }

    struct Input: Equatable, Sendable {
        let sourceID: String
        let sourceRevision: UInt64
        let sourceDigest: String
        /// Stable identity of the independent origin, supplied by its owner.
        /// Copying a source must not manufacture another independent origin.
        let originID: String
        let assessment: Assessment
        let contextMatch: Double
        let eligible: Bool

        var isValid: Bool {
            validIdentifier(sourceID) && sourceRevision > 0
                && sourceDigest.utf8.count == 64
                && sourceDigest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
                && validIdentifier(originID) && assessment.isValid && unitInterval(contextMatch)
        }
    }

    struct Row: Equatable, Sendable {
        let sourceID: String
        let sourceRevision: UInt64
        let sourceDigest: String
        let originID: String
        let eligible: Bool
        let polarity: Polarity?
        let retrieval: Double
        let weight: Double
        let contribution: Double

        var assessed: Bool { polarity != nil }
    }

    struct Evaluation: Equatable, Sendable {
        let scope: String
        let targetID: String
        let rows: [Row]
        let positiveMass: Double
        let negativeMass: Double
        let neutralMass: Double

        var totalWeight: Double { positiveMass + negativeMass + neutralMass }
        var denominator: Double { 1 + totalWeight }
        var influence: Double { (positiveMass - negativeMass) / denominator }
        var hasOpposingEvidence: Bool { positiveMass > 0 && negativeMass > 0 }
        var assessedCount: Int { rows.filter { $0.eligible && $0.assessed }.count }
        var unassessedCount: Int { rows.filter { $0.eligible && !$0.assessed }.count }
    }

    enum EvaluationError: Error, Equatable, LocalizedError {
        case invalidContext
        case tooManyInputs
        case invalidInput(String)
        case duplicateSource(String)
        case duplicateOrigin(String)

        var errorDescription: String? {
            switch self {
            case .invalidContext: "The memory influence context is invalid."
            case .tooManyInputs: "Too many memory relations were supplied for this assessment."
            case .invalidInput: "A memory influence relation or source binding is invalid."
            case .duplicateSource: "A source appears more than once in this assessment."
            case .duplicateOrigin: "Copied memories cannot count as independent evidence."
            }
        }
    }

    /// Retrieval is independent of polarity, magnitude and assessed confidence.
    /// Eligible unassessed memories remain retrievable but contribute no weight.
    /// Neutral assessments contribute denominator mass and no signed numerator.
    /// The unit prior prevents weak evidence normalizing to a full-strength push.
    static func evaluate(inputs: [Input], scope: String, targetID: String) throws -> Evaluation {
        guard validIdentifier(scope, maximumBytes: 96), validIdentifier(targetID) else {
            throw EvaluationError.invalidContext
        }
        guard inputs.count <= maximumInputs else { throw EvaluationError.tooManyInputs }
        for input in inputs where !input.isValid { throw EvaluationError.invalidInput(input.sourceID) }

        var sourceIDs = Set<String>()
        var originIDs = Set<String>()
        var rows: [Row] = []
        var positiveMass = 0.0
        var negativeMass = 0.0
        var neutralMass = 0.0
        for input in inputs where input.assessment.scope == scope && input.assessment.targetID == targetID {
            if input.eligible {
                guard sourceIDs.insert(input.sourceID).inserted else {
                    throw EvaluationError.duplicateSource(input.sourceID)
                }
                guard originIDs.insert(input.originID).inserted else {
                    throw EvaluationError.duplicateOrigin(input.originID)
                }
            }
            let assessment = input.assessment
            let retrieval = input.eligible ? input.contextMatch * assessment.retrievalSalience : 0
            let weight = input.eligible && assessment.polarity != nil
                ? retrieval * assessment.confidence * assessment.magnitude : 0
            let contribution = weight * Double(assessment.polarity?.rawValue ?? 0)
            switch assessment.polarity {
            case .attraction: positiveMass += weight
            case .detraction: negativeMass += weight
            case .neutral: neutralMass += weight
            case nil: break
            }
            rows.append(Row(sourceID: input.sourceID, sourceRevision: input.sourceRevision,
                            sourceDigest: input.sourceDigest, originID: input.originID,
                            eligible: input.eligible, polarity: assessment.polarity,
                            retrieval: retrieval, weight: weight, contribution: contribution))
        }
        return Evaluation(scope: scope, targetID: targetID, rows: rows,
                          positiveMass: positiveMass, negativeMass: negativeMass, neutralMass: neutralMass)
    }

    private static func unitInterval(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }

    private static func validIdentifier(_ value: String, maximumBytes: Int = 512) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
