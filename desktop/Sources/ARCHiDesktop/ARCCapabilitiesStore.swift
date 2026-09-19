import Foundation
import Combine
import CryptoKit
import Darwin

struct ARCCapabilitiesEvent: Sendable {
    let taskID: String
    let evidenceID: String?
    let passed: Bool?
    let startedAt: Date
    let finishedAt: Date
    let sourceStatus: String?
    let error: String?
    var localSolver = false
    var cancelled = false
    var proposalInference: ARCQwenProposalInference? = nil
    var proposalInProgress = false
}

struct ARCCapabilitiesRecord: Identifiable, Sendable {
    let taskID: String
    let recordedAt: Date
    let bundle: Data
    let summary: ARCCapabilitiesSummary
    var solverEvidence: ARCSolverEvidence? = nil
    var id: String { summary.proposalHash }
    var bundleHash: String { "sha256:" + SHA256.hash(data: bundle).map { String(format: "%02x", $0) }.joined() }
}

/// A profile-scoped evidence shelf. Every reopen scores the raw bundle again.
/// This owner has no access to evolution, permissions or memories. Local proposal
/// generation is a separate explicit request through a bounded Qwen client.
@MainActor
final class ARCCapabilitiesStore: ObservableObject {
    @Published private(set) var records: [ARCCapabilitiesRecord] = []
    @Published private(set) var lastError: String?
    /// Transient inspector selection, never written into the evidence archive.
    @Published private(set) var selectedRecordID: String?
    @Published private(set) var selectionNotice: String?
    @Published private(set) var solverDocument: ARCSolverDocument?
    @Published private(set) var solverReview: ARCSolverReview?
    @Published private(set) var isSolving = false
    @Published private(set) var solverStatus = "Choose a task or load the rotation sample."
    @Published private(set) var qwenProposalStatus = "Ask local Qwen for one bounded rule proposal."
    @Published private(set) var qwenProposalReview: ARCQwenProposalReview?
    @Published private(set) var isProposing = false
    let qwenProposalClientFactory: @MainActor (String) -> any ARCQwenProposalClient
    var qwenProposalOwner: ARCQwenProposalSession?
    private let solverExecutor: @Sendable (ARCSolverInput, ARCSolverConfiguration) async throws -> ARCSolverExecution
    private var solverWorker: Task<ARCSolverExecution, Error>?
    private var solverOwner: SolverOwner?
    private struct SolverOwner {
        let id: UUID
        let startedAt: Date
        let onEvaluation: @MainActor (ARCCapabilitiesEvent) -> Void
    }
    private let storageURL: URL?
    private var storageNeedsRecovery = false
    private var persistedDigest: String?
    private static let maximumArchiveBytes = 16 * 1024 * 1024

    private struct StoredRecord: Codable {
        let taskID: String
        let recordedAt: Date
        let bundle: Data
        var solverEvidence: ARCSolverEvidence? = nil
    }
    private struct Archive: Codable {
        let schemaVersion: Int
        let records: [StoredRecord]
    }

    @discardableResult
    func selectRecord(id: String) -> Bool {
        guard records.contains(where: { $0.id == id }) else {
            selectedRecordID = nil
            selectionNotice = "That ARC receipt is no longer available in this profile. No replacement was selected."
            return false
        }
        selectedRecordID = id
        selectionNotice = nil
        return true
    }

    func clearRecordSelection(notice: String? = nil) {
        selectedRecordID = nil
        selectionNotice = notice
    }

    init(storageURL: URL? = nil,
         solverExecutor: @escaping @Sendable (ARCSolverInput, ARCSolverConfiguration) async throws -> ARCSolverExecution = ARCSolverExecution.local,
         qwenProposalClientFactory: @escaping @MainActor (String) -> any ARCQwenProposalClient = { QwenAssistant(model: $0, runtime: LocalQwenRuntime.shared) }) {
        self.storageURL = storageURL
        self.solverExecutor = solverExecutor
        self.qwenProposalClientFactory = qwenProposalClientFactory
        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let values = try storageURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= Self.maximumArchiveBytes else {
                throw ARCCapabilitiesError.invalid("ARC evidence archive exceeds its local size limit.")
            }
            let data = try Data(contentsOf: storageURL)
            guard data.count <= Self.maximumArchiveBytes else { throw ARCCapabilitiesError.invalid("ARC evidence archive is too large.") }
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.schemaVersion == 1, archive.records.count <= 16 else { throw ARCCapabilitiesError.invalid("Unsupported ARC evidence archive.") }
            var seen = Set<String>()
            records = try archive.records.map {
                guard UUID(uuidString: $0.taskID) != nil, $0.recordedAt.timeIntervalSince1970.isFinite else {
                    throw ARCCapabilitiesError.invalid("Invalid ARC record identity.")
                }
                let summary = try ARCCapabilitiesEvaluator.evaluate($0.bundle)
                try $0.solverEvidence?.validate(bundle: $0.bundle)
                guard seen.insert(summary.proposalHash).inserted else { throw ARCCapabilitiesError.invalid("Duplicate archived ARC evidence.") }
                return ARCCapabilitiesRecord(taskID: $0.taskID, recordedAt: $0.recordedAt, bundle: $0.bundle,
                                            summary: summary, solverEvidence: $0.solverEvidence)
            }
            persistedDigest = Self.digest(data)
        } catch {
            lastError = "Saved ARC evidence could not be checked: \(error.localizedDescription) The original file has been preserved."
            storageNeedsRecovery = true
        }
    }

    func updateQwenProposal(status: String, review: ARCQwenProposalReview?, isProposing: Bool) {
        qwenProposalStatus = status
        qwenProposalReview = review
        self.isProposing = isProposing
    }

    func prepareQwenProposal() -> ARCSolverDocument? {
        guard !isProposing else { return nil }
        guard let document = solverDocument else {
            qwenProposalStatus = "Choose a task first."
            return nil
        }
        guard !storageNeedsRecovery else {
            qwenProposalStatus = "Repair or restore the preserved evidence archive before proposing."
            return nil
        }
        stopSolving(reason: "Replaced by a local Qwen proposal.")
        solverReview = nil
        return document
    }

    func retainQwenProposal(bundle: Data, ownerID: UUID, startedAt: Date) -> ARCCapabilitiesEvent? {
        guard qwenProposalOwner?.id == ownerID else { return nil }
        // Owner check, independent checker and archive commit share one actor
        // turn; cancelled or replaced work cannot publish a late proposal.
        return retainEvaluation(data: bundle, taskID: ownerID.uuidString, startedAt: startedAt)
    }

    @discardableResult
    func evaluate(fileURL: URL) throws -> ARCCapabilitiesEvent {
        guard fileURL.isFileURL else { throw ARCCapabilitiesError.invalid("Choose a local JSON file.") }
        // Read through one descriptor, bounded even if the selected file grows
        // after the picker closes. Pipes/directories cannot become an import.
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else { throw ARCCapabilitiesError.invalid("The selected ARC file could not be opened.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_size <= ARCCapabilitiesEvaluator.maximumBytes else {
            throw ARCCapabilitiesError.invalid("Choose a regular JSON file no larger than 2 MiB.")
        }
        var data = Data()
        while data.count <= ARCCapabilitiesEvaluator.maximumBytes {
            let remaining = ARCCapabilitiesEvaluator.maximumBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= ARCCapabilitiesEvaluator.maximumBytes else {
            throw ARCCapabilitiesError.invalid("The selected ARC file exceeds 2 MiB.")
        }
        return evaluate(data: data)
    }

    @discardableResult
    func evaluate(data: Data) -> ARCCapabilitiesEvent {
        retainEvaluation(data: data, taskID: UUID().uuidString, startedAt: Date())
    }

    private func retainEvaluation(data: Data, taskID: String, startedAt: Date, solverEvidence: ARCSolverEvidence? = nil) -> ARCCapabilitiesEvent {
        do {
            guard !storageNeedsRecovery else { throw ARCCapabilitiesError.invalid("Repair or restore the preserved ARC evidence archive before saving another evaluation.") }
            let summary = try ARCCapabilitiesEvaluator.evaluate(data)
            try solverEvidence?.validate(bundle: data)
            if !records.contains(where: { $0.id == summary.proposalHash }) {
                guard records.count < 16 else { throw ARCCapabilitiesError.invalid("The local ARC evidence shelf has reached 16 evaluations. Existing records were preserved.") }
                let new = ARCCapabilitiesRecord(taskID: taskID, recordedAt: Date(), bundle: data,
                                               summary: summary, solverEvidence: solverEvidence)
                let proposed = [new] + records
                try persist(proposed)
                records = proposed
            } else {
                // A duplicate still claims that its evidence is retained. Check
                // the archive under the same lock without rewriting its bytes.
                try withCurrentArchive { _ in }
            }
            lastError = nil
            return ARCCapabilitiesEvent(taskID: taskID, evidenceID: summary.proposalHash, passed: summary.allExact,
                startedAt: startedAt, finishedAt: max(startedAt, Date()), sourceStatus: summary.sourceStatus, error: nil,
                localSolver: solverEvidence != nil)
        } catch {
            lastError = error.localizedDescription
            return ARCCapabilitiesEvent(taskID: taskID, evidenceID: nil, passed: nil,
                startedAt: startedAt, finishedAt: max(startedAt, Date()), sourceStatus: nil, error: error.localizedDescription,
                localSolver: solverEvidence != nil)
        }
    }

    @discardableResult
    func runSyntheticDemonstration() -> ARCCapabilitiesEvent {
        evaluate(data: ARCCapabilitiesEvaluator.syntheticBundle)
    }

    private func persist(_ records: [ARCCapabilitiesRecord]) throws {
        let archive = Archive(schemaVersion: 1, records: records.map {
            StoredRecord(taskID: $0.taskID, recordedAt: $0.recordedAt, bundle: $0.bundle, solverEvidence: $0.solverEvidence)
        })
        let data = try JSONEncoder().encode(archive)
        guard data.count <= Self.maximumArchiveBytes else { throw ARCCapabilitiesError.invalid("The local ARC evidence shelf is full. Current evidence was preserved.") }
        try withCurrentArchive { storageURL in
            try data.write(to: storageURL, options: .atomic)
            persistedDigest = Self.digest(data)
        }
    }

    private func withCurrentArchive(_ operation: (URL) throws -> Void) throws {
        guard let storageURL else { return }
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = storageURL.appendingPathExtension("lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ARCCapabilitiesError.invalid("Cannot lock ARC evidence for saving.") }
        defer { _ = Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ARCCapabilitiesError.invalid("ARC evidence is being saved in another session. Try again after it finishes.") }
        defer { _ = flock(descriptor, LOCK_UN) }
        let currentDigest: String?
        if FileManager.default.fileExists(atPath: storageURL.path) {
            let values = try storageURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= Self.maximumArchiveBytes else {
                throw ARCCapabilitiesError.invalid("ARC evidence changed outside this session. Reopen before saving.")
            }
            let current = try Data(contentsOf: storageURL)
            guard current.count <= Self.maximumArchiveBytes else { throw ARCCapabilitiesError.invalid("ARC evidence changed outside this session.") }
            currentDigest = Self.digest(current)
        } else { currentDigest = nil }
        guard currentDigest == persistedDigest else {
            throw ARCCapabilitiesError.invalid("ARC evidence changed in another session. Reopen to review it before saving. Existing records were preserved.")
        }
        try operation(storageURL)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension ARCCapabilitiesStore {
    func loadSolverTask(fileURL: URL) throws {
        stopSolving(reason: "Task replaced.")
        try loadSolverTask(data: ARCSolverDocument.readFile(fileURL), name: fileURL.lastPathComponent)
    }

    func loadSolverTask(data: Data, name: String) throws {
        stopSolving(reason: "Task replaced.")
        let document = try ARCSolverDocument.parse(data, name: name)
        solverDocument = document
        solverReview = nil
        updateQwenProposal(status: "Task ready for one local Qwen proposal.", review: nil, isProposing: false)
        solverStatus = "Task ready. Expected test outputs, if present, are reserved for the checker."
    }

    func loadSolverSample() throws {
        stopSolving(reason: "Task replaced.")
        solverDocument = try ARCSolverDocument.parse(ARCSolverDocument.sample, name: "Synthetic rotation sample", isSynthetic: true)
        solverReview = nil
        updateQwenProposal(status: "Synthetic sample ready for one local Qwen proposal.", review: nil, isProposing: false)
        solverStatus = "Synthetic sample ready. Solve locally to generate a new prediction."
    }

    func startSolving(onEvaluation: @escaping @MainActor (ARCCapabilitiesEvent) -> Void) {
        guard let document = solverDocument else { solverStatus = "Choose a task first."; return }
        startSolving(document: document, replay: nil, onEvaluation: onEvaluation)
    }

    func replaySolver(recordID: String, onEvaluation: @escaping @MainActor (ARCCapabilitiesEvent) -> Void) {
        guard !isSolving, let record = records.first(where: { $0.id == recordID }),
              let previous = record.solverEvidence else { return }
        do {
            try previous.validate(bundle: record.bundle)
            let document = try ARCSolverDocument.fromBundle(record.bundle)
            solverDocument = document
            startSolving(document: document, replay: previous.run, configuration: previous.configuration, onEvaluation: onEvaluation)
        } catch { solverStatus = error.localizedDescription }
    }

    private func startSolving(document: ARCSolverDocument, replay: ARCSolverRun?,
                              configuration: ARCSolverConfiguration = .standard,
                              onEvaluation: @escaping @MainActor (ARCCapabilitiesEvent) -> Void) {
        guard !isSolving else { return }
        stopQwenProposal(reason: "Symbolic solve started.")
        updateQwenProposal(status: "Ask local Qwen for one bounded rule proposal.", review: nil, isProposing: false)
        guard !storageNeedsRecovery else {
            solverStatus = "Repair or restore the preserved evidence archive before solving."
            return
        }
        let owner = SolverOwner(id: UUID(), startedAt: Date(), onEvaluation: onEvaluation)
        solverOwner = owner
        solverReview = nil
        isSolving = true
        solverStatus = "Testing bounded local rules against the training examples…"
        let input = document.input, executor = solverExecutor
        // The detached worker captures no expected test targets, source labels,
        // checker, stores, instructions or authority-bearing objects.
        let worker = Task.detached(priority: .userInitiated) { try await executor(input, configuration) }
        solverWorker = worker
        Task { @MainActor [weak self] in
            do {
                let execution = try await worker.value
                guard let self, self.solverOwner?.id == owner.id, !worker.isCancelled else { return }
                guard execution.configuration == configuration else {
                    throw ARCCapabilitiesError.invalid("Solver returned a different configuration than requested.")
                }
                let elapsed = max(0, Int(Date().timeIntervalSince(owner.startedAt) * 1_000))
                let evidence = ARCSolverEvidence(run: execution.run, configuration: execution.configuration,
                    inputDigest: document.inputDigest, codeHash: execution.codeHash, elapsedMilliseconds: elapsed)
                let bundle = try document.bundle(run: execution.run, codeHash: execution.codeHash)
                // No suspension from owner check through validation, persistence and publication.
                let event = self.retainEvaluation(data: bundle, taskID: owner.id.uuidString,
                                                 startedAt: owner.startedAt, solverEvidence: evidence)
                self.solverReview = ARCSolverReview(taskID: owner.id.uuidString, document: document, run: execution.run,
                    elapsedMilliseconds: elapsed, evidenceID: event.evidenceID, error: event.error,
                    replayMatched: replay.map { $0 == execution.run })
                self.isSolving = false
                self.solverWorker = nil
                self.solverOwner = nil
                if let error = event.error { self.solverStatus = "Result could not be retained: \(error)" }
                else {
                    switch execution.run.outcome {
                    case .predicted: self.solverStatus = "Prediction generated and checked. A training fit is not a certified capability."
                    case .ambiguous: self.solverStatus = "Abstained: fitting rules disagree or cannot predict every test input."
                    case .noMatch: self.solverStatus = "Abstained: no rule in this small catalog fits every training example."
                    case .budgetExhausted: self.solverStatus = "Abstained: the search budget ended before the catalog was checked."
                    }
                }
                owner.onEvaluation(event)
            } catch {
                guard let self, self.solverOwner?.id == owner.id else { return }
                self.isSolving = false
                self.solverOwner = nil
                self.solverWorker = nil
                let cancelled = error is CancellationError
                self.solverStatus = cancelled ? "Stopped. Previous evidence is unchanged." : "Solving failed: \(error.localizedDescription)"
                owner.onEvaluation(ARCCapabilitiesEvent(taskID: owner.id.uuidString, evidenceID: nil, passed: nil,
                    startedAt: owner.startedAt, finishedAt: max(owner.startedAt, Date()),
                    sourceStatus: document.isSynthetic ? "synthetic-fixture" : "unverified-offline-snapshot",
                    error: self.solverStatus, localSolver: true, cancelled: cancelled))
            }
        }
    }

    func stopSolving() { stopSolving(reason: "Stopped.") }

    private func stopSolving(reason: String) {
        stopQwenProposal(reason: reason)
        guard let owner = solverOwner else { return }
        // Retire ownership synchronously; even an executor ignoring cancellation
        // cannot revive a stopped task or write into the next task's archive.
        solverOwner = nil
        solverWorker?.cancel()
        solverWorker = nil
        isSolving = false
        solverStatus = reason + " Previous evidence is unchanged."
        owner.onEvaluation(ARCCapabilitiesEvent(taskID: owner.id.uuidString, evidenceID: nil, passed: nil,
            startedAt: owner.startedAt, finishedAt: max(owner.startedAt, Date()), sourceStatus: nil,
            error: solverStatus, localSolver: true, cancelled: true))
    }
}
