import Foundation

/// Model-specific assay identity. These coordinates are separate from native
/// Q2E pressures, the archived numerical controller, and companion state.
struct LocalRepresentationBasis: Codable, Equatable, Sendable {
    let namespace: String
    let modelDigest: String
    let tokenizerDigest: String
    let templateDigest: String
    let backendRevision: String
    let precision: String
    let layer: String
    let tokenRule: String
    let readerName: String
    let basisDigest: String
    let readerDigest: String
    let calibrationDigest: String
    /// Exact imported reader bytes, when a file-backed adapter supplies them.
    /// Declared reader/calibration lineage alone does not bind numerical weights.
    var artifactDigest: String? = nil
    var measurementScope: String? = nil

    var isValid: Bool {
        Self.identifier(namespace) && Self.identifier(backendRevision) && Self.identifier(layer) && Self.identifier(readerName)
            && [modelDigest, tokenizerDigest, templateDigest, basisDigest, readerDigest, calibrationDigest].allSatisfy(Self.digest)
            && (["float32", "float64"].contains(precision)
                || (precision == "Q4_K_M" && backendRevision == "llama.cpp:161755f29"))
            && (tokenRule == "last" || (tokenRule == "prompt-last"
                && precision == "Q4_K_M" && backendRevision == "llama.cpp:161755f29"))
            && (artifactDigest.map(Self.digest) ?? true)
            && (measurementScope.map(Self.identifier) ?? true)
    }

    static func digest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func identifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 160
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

enum LocalRepresentationMode: String, Codable, Sendable { case off, shadow, bounded }

struct LocalRepresentationConfiguration: Equatable, Sendable {
    let mode: LocalRepresentationMode
    let basis: LocalRepresentationBasis?
    static let off = Self(mode: .off, basis: nil)

    func supports(_ access: LocalRepresentationAccess) -> Bool {
        guard mode != .off else { return true }
        guard basis?.isValid == true else { return false }
        switch mode {
        case .off: return true
        case .shadow: return access == .activationReadOnly || access == .activationControl
        case .bounded: return access == .activationControl
        }
    }
}

/// Scalar observations only. No raw tensors, positive learning counters, or
/// conversion to HamptonQ2EStrategyEvidence is supplied by this contract.
struct LocalRepresentationAssay: Codable, Equatable, Sendable {
    struct Sample: Codable, Equatable, Sendable {
        /// Layer-call ordinal within one inference request, not a task episode.
        let tokenIndex: Int
        let rawScore: Double
        let coordinate: Double
    }
    let schemaVersion: String
    let requestID: String
    let inputDigest: String
    let systemDigest: String
    let schemaDigest: String
    let outputDigest: String
    let basis: LocalRepresentationBasis
    let mode: LocalRepresentationMode
    /// A pre-current-edit sample in a steered trajectory is still intervened.
    let phase: String
    let samples: [Sample]
}

enum LocalRepresentationContractError: Error, LocalizedError {
    case unavailable, mismatched
    var errorDescription: String? {
        switch self {
        case .unavailable: "The selected representation capability is unavailable. No substitute model or provider was selected."
        case .mismatched: "The representation result did not match this request and its configured model basis. It was not accepted."
        }
    }
}

struct LocalRepresentationReceipt: Equatable, Sendable {
    enum Status: String, Sendable { case notRecorded, off, pending, unavailable, rejected, recorded }
    let status: Status
    let detail: String
    let assay: LocalRepresentationAssay?
    static let notRecorded = Self(status: .notRecorded, detail: "No representation receipt recorded.", assay: nil)

    static func begin(_ configuration: LocalRepresentationConfiguration,
                      access: LocalRepresentationAccess) throws -> Self {
        guard configuration.mode != .off else {
            return Self(status: .off, detail: "Representation measurement and control are off for this request.", assay: nil)
        }
        guard configuration.supports(access) else { throw LocalRepresentationContractError.unavailable }
        return Self(status: .pending, detail: "Awaiting request-bound representation measurements.", assay: nil)
    }

    static func interrupted() -> Self {
        Self(status: .unavailable, detail: "The request ended before a matching representation result was received.", assay: nil)
    }

    static func complete(_ supplied: LocalRepresentationAssay?, invocation: HamptonInvocationReceipt,
                         result: LocalRoleResult, outputDigest: String) -> Self {
        let configuration = invocation.representationConfiguration
        if configuration.mode == .off {
            return Self(status: supplied == nil ? .off : .rejected,
                        detail: supplied == nil ? "Representation measurement and control were off."
                            : "An unrequested representation result was discarded.", assay: nil)
        }
        guard let assay = supplied else { return interrupted() }
        let modelDigest = result.model.digest.hasPrefix("sha256:")
            ? String(result.model.digest.dropFirst(7)) : result.model.digest
        var previousIndex = -1
        let validSamples = !assay.samples.isEmpty && assay.samples.count <= HamptonInvocationPolicy.outputTokens
            && assay.samples.allSatisfy { sample in
                defer { previousIndex = sample.tokenIndex }
                return (0..<HamptonInvocationPolicy.contextTokens).contains(sample.tokenIndex)
                    && sample.tokenIndex > previousIndex && sample.rawScore.isFinite
                    && sample.coordinate.isFinite && (0...1).contains(sample.coordinate)
            }
        guard configuration.supports(invocation.representationAccess),
              assay.schemaVersion == "archi-representation-assay/v1", assay.basis.isValid,
              assay.basis == configuration.basis, assay.mode == configuration.mode,
              assay.phase == (assay.mode == .shadow ? "unsteered" : "intervened"),
              UUID(uuidString: assay.requestID) != nil,
              result.requestID == invocation.id, result.role == invocation.role,
              UUID(uuidString: assay.requestID) == UUID(uuidString: invocation.id),
              [assay.inputDigest, assay.systemDigest, assay.schemaDigest, assay.outputDigest].allSatisfy(LocalRepresentationBasis.digest),
              assay.inputDigest == invocation.inputDigest, assay.systemDigest == invocation.systemDigest,
              assay.schemaDigest == invocation.schemaDigest, assay.outputDigest == outputDigest,
              assay.basis.modelDigest == modelDigest, validSamples,
              assay.basis.tokenRule != "prompt-last" || assay.samples.count == 1 else {
            return Self(status: .rejected, detail: "Representation bindings, phase or scalar values did not match this request. The supplied measurements were discarded.", assay: nil)
        }
        return Self(status: .recorded,
                    detail: "\(assay.mode.rawValue.capitalized) · \(assay.samples.count) scalar sample(s). Bindings match; coordinates are not truth probabilities or reviewed task outcomes.", assay: assay)
    }
}
