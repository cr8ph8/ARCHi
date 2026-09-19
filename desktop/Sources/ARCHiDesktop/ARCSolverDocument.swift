import Foundation
import CryptoKit
import CoreFoundation
import Darwin

/// Test targets belong to the checker side of the boundary. Only `input` is
/// passed to the solver worker. Labels, targets and provenance cannot select rules.
struct ARCSolverDocument: Equatable, Sendable {
    let name: String
    let input: ARCSolverInput
    let targets: [ARCGrid?]
    let isSynthetic: Bool
    let inputDigest: String
    let sourceDigest: String

    static func parse(_ data: Data, name: String, isSynthetic: Bool = false) throws -> Self {
        guard data.count <= ARCCapabilitiesEvaluator.maximumBytes else { throw invalid("Choose an ARC task no larger than 2 MiB.") }
        let root = try object(JSONSerialization.jsonObject(with: data), required: ["train", "test"])
        guard let training = root["train"] as? [Any], (1...20).contains(training.count),
              let tests = root["test"] as? [Any], (1...20).contains(tests.count) else {
            throw invalid("An ARC task needs 1–20 training examples and 1–20 test inputs.")
        }
        let pairs = try training.map { value -> ARCTrainingPair in
            let pair = try object(value, required: ["input", "output"])
            return ARCTrainingPair(input: try grid(pair["input"]), output: try grid(pair["output"]))
        }
        var inputs: [ARCGrid] = [], targets: [ARCGrid?] = []
        for value in tests {
            let test = try object(value, required: ["input"], optional: ["output"])
            inputs.append(try grid(test["input"]))
            targets.append(try test["output"].map { try grid($0) })
        }
        let solverInput = ARCSolverInput(training: pairs, testInputs: inputs)
        let publicInput: [String: Any] = ["train": pairs.map { ["input": $0.input, "output": $0.output] },
                                         "test": inputs.map { ["input": $0] }]
        let label = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(120))
        return Self(name: label.isEmpty ? "Local ARC task" : label, input: solverInput, targets: targets,
                    isSynthetic: isSynthetic, inputDigest: try ARCCapabilitiesEvaluator.digest(publicInput),
                    sourceDigest: try ARCCapabilitiesEvaluator.digest(root))
    }

    var taskID: String { "local-" + String(sourceDigest.dropFirst(7).prefix(24)) }

    private var task: [String: Any] {
        ["taskId": taskID,
         "train": input.training.map { ["input": $0.input, "output": $0.output] },
         "test": zip(input.testInputs, targets).map { input, target -> [String: Any] in
             var example: [String: Any] = ["input": input]
             if let target { example["output"] = target }
             return example
         }]
    }

    func bundle(run: ARCSolverRun, codeHash: String) throws -> Data {
        guard validDigest(codeHash) else { throw Self.invalid("The solver executable identity is missing.") }
        let task = task
        let configurationHash = try ARCCapabilitiesEvaluator.digest([
            "catalog": run.catalogIdentity, "configuration": run.configurationIdentity,
            "solverInput": inputDigest])
        let manifest: [String: Any] = [
            "schemaVersion": 1, "manifestId": "solve-" + String(sourceDigest.dropFirst(7).prefix(24)),
            "mode": isSynthetic ? "fixture" : "offline-dataset", "integration": "none",
            "scorerVersion": ARCCapabilitiesEvaluator.scorer,
            "source": ["label": name, "status": isSynthetic ? "synthetic-fixture" : "unverified-offline-snapshot",
                       "snapshot": "local-json-v1", "contentHash": sourceDigest], "split": "local-task",
            "tasks": [["taskId": taskID, "taskHash": try ARCCapabilitiesEvaluator.digest(task),
                       "testExamples": input.testInputs.count]]]
        // Whole-task abstention keeps every test index in the existing denominator.
        let result: [String: Any] = ["schema": ARCCapabilitiesEvaluator.schema, "manifest": manifest,
            "solver": ["id": "archi-native-symbolic", "version": run.solverVersion,
                       "codeHash": codeHash, "configurationHash": configurationHash],
            "evaluations": [["task": task, "predictions": run.predictions ?? []]]]
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    static func fromBundle(_ data: Data) throws -> Self {
        _ = try ARCCapabilitiesEvaluator.evaluate(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let evaluations = root["evaluations"] as? [[String: Any]], evaluations.count == 1,
              let task = evaluations[0]["task"] as? [String: Any],
              let manifest = root["manifest"] as? [String: Any],
              let source = manifest["source"] as? [String: Any], let name = source["label"] as? String else {
            throw invalid("This record is not a single local solving task.")
        }
        let standard: [String: Any] = ["train": task["train"]!, "test": task["test"]!]
        return try parse(JSONSerialization.data(withJSONObject: standard), name: name,
                         isSynthetic: source["status"] as? String == "synthetic-fixture")
    }

    static func readFile(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw invalid("Choose a local JSON file.") }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else { throw invalid("The ARC task could not be opened.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= ARCCapabilitiesEvaluator.maximumBytes else { throw invalid("Choose a regular JSON file no larger than 2 MiB.") }
        var data = Data()
        while data.count <= ARCCapabilitiesEvaluator.maximumBytes {
            let chunk = try handle.read(upToCount: ARCCapabilitiesEvaluator.maximumBytes + 1 - data.count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= ARCCapabilitiesEvaluator.maximumBytes else { throw invalid("The ARC task grew beyond 2 MiB.") }
        return data
    }

    private static func object(_ value: Any, required: Set<String>, optional: Set<String> = []) throws -> [String: Any] {
        guard let object = value as? [String: Any], required.isSubset(of: Set(object.keys)),
              Set(object.keys).isSubset(of: required.union(optional)) else {
            throw invalid("Use standard ARC JSON with only train/test and input/output fields. Instructions and authority fields are not accepted.")
        }
        return object
    }

    private static func grid(_ value: Any?) throws -> ARCGrid {
        guard let rows = value as? [Any], (1...30).contains(rows.count) else { throw invalid("ARC grids must have 1–30 rows.") }
        var width: Int?
        return try rows.map { row in
            guard let cells = row as? [Any], (1...30).contains(cells.count), width == nil || width == cells.count else {
                throw invalid("ARC grids must be rectangular with 1–30 columns.")
            }
            width = cells.count
            return try cells.map { value in
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
                      (0...9).contains(number.doubleValue) else { throw invalid("ARC colors must be integers 0–9, not Boolean values.") }
                return number.intValue
            }
        }
    }

    private static func invalid(_ text: String) -> ARCCapabilitiesError { .invalid(text) }

    static let sample = Data(#"""
    {"train":[{"input":[[1,2,3],[4,5,6]],"output":[[4,1],[5,2],[6,3]]},{"input":[[1,0],[2,3],[4,5]],"output":[[4,2,1],[5,3,0]]}],"test":[{"input":[[7,0,1],[2,8,3]],"output":[[2,7],[8,0],[3,1]]}]}
    """#.utf8)
}

struct ARCSolverEvidence: Codable, Equatable, Sendable {
    let run: ARCSolverRun
    let configuration: ARCSolverConfiguration
    let inputDigest: String
    /// Hash of the compiled host executable containing the solver. Not a signature.
    let codeHash: String
    let elapsedMilliseconds: Int

    func validate(bundle: Data) throws {
        let document = try ARCSolverDocument.fromBundle(bundle)
        guard traceIsConsistent(trainingCount: document.input.training.count) else {
            throw ARCCapabilitiesError.invalid("Saved search trace is inconsistent with its attempts and training fits.")
        }
        guard inputDigest == document.inputDigest, validDigest(codeHash), elapsedMilliseconds >= 0,
              elapsedMilliseconds <= 86_400_000,
              (0...1_500).contains(configuration.maxProgramAttempts),
              (0...20_000_000).contains(configuration.maxCellOperations),
              (0...1_500).contains(configuration.maxTraceEntries),
              run.configurationIdentity == configuration.identity,
              run.solverVersion == ARCSymbolicSolver.version(for: configuration),
              run.catalogIdentity == ARCSymbolicSolver.catalogIdentity(for: configuration),
              (0...configuration.maxProgramAttempts).contains(run.attemptedPrograms),
              (0...run.attemptedPrograms).contains(run.matchingPrograms),
              (0...configuration.maxCellOperations).contains(run.cellOperations),
              run.programIDs.count == run.matchingPrograms, Set(run.programIDs).count == run.programIDs.count,
              run.trace.count <= configuration.maxTraceEntries,
              run.programIDs.allSatisfy({ $0.utf8.count <= 512 }),
              run.trace.allSatisfy({ $0.programID.utf8.count <= 512 && (0...document.input.training.count).contains($0.trainingExamplesChecked) }),
              (run.outcome == .predicted) == (run.predictions != nil),
              run.predictions == nil || run.predictions?.count == document.input.testInputs.count,
              run.predictions?.allSatisfy({ grid in
                  (1...30).contains(grid.count) && (1...30).contains(grid.first?.count ?? 0) &&
                  grid.allSatisfy { $0.count == grid.first?.count && $0.allSatisfy { (0...9).contains($0) } }
              }) != false,
              run.outcome != .predicted || run.matchingPrograms > 0,
              run.outcome == .budgetExhausted || run.attemptedPrograms == ARCSymbolicSolver.catalogProgramCount(for: configuration),
              try ARCCapabilitiesEvaluator.evaluate(document.bundle(run: run, codeHash: codeHash)).proposalHash == ARCCapabilitiesEvaluator.evaluate(bundle).proposalHash else {
            throw ARCCapabilitiesError.invalid("Saved solving details do not match their frozen task and predictions.")
        }
    }

    private func traceIsConsistent(trainingCount: Int) -> Bool {
        guard run.attemptedPrograms >= 0, configuration.maxTraceEntries >= 0,
              run.attemptedPrograms <= ARCSymbolicSolver.catalogProgramCount(for: configuration),
              run.trace.count == min(run.attemptedPrograms, configuration.maxTraceEntries),
              run.traceTruncated == (run.attemptedPrograms > configuration.maxTraceEntries),
              run.outcome != .noMatch || run.matchingPrograms == 0 else { return false }
        let fits = run.trace.filter { $0.status == .matched || $0.status == .predictionUndefined }.map(\.programID)
        guard Array(run.programIDs.prefix(fits.count)) == fits else { return false }
        guard var schedule = try? HamptonARCTrainingOrder(exampleCount: trainingCount) else { return false }
        for (index, entry) in run.trace.enumerated() {
            let visited = entry.checkedTrainingIndices
            let expectedOrder = configuration.trainingOrder == .adaptive ? schedule.order : Array(0..<trainingCount)
            guard (0...trainingCount).contains(entry.trainingExamplesChecked),
                  Set(visited).count == visited.count,
                  visited.allSatisfy({ (0..<trainingCount).contains($0) }),
                  visited == Array(expectedOrder.prefix(visited.count)),
                  visited.count >= entry.trainingExamplesChecked,
                  visited.count <= entry.trainingExamplesChecked + 1 else { return false }
            switch entry.status {
            case .matched, .predictionUndefined, .redundantPalette:
                guard entry.trainingExamplesChecked == trainingCount, visited.count == trainingCount else { return false }
                if run.outcome == .predicted && entry.status == .predictionUndefined { return false }
            case .trainingMismatch:
                guard !visited.isEmpty, visited.count == entry.trainingExamplesChecked else { return false }
            case .trainingUndefined:
                guard visited.count == entry.trainingExamplesChecked + 1 else { return false }
            case .budgetExhausted:
                guard index == run.trace.count - 1, run.outcome == .budgetExhausted else { return false }
            }
            // Reconstruct only the observations retained by this trace prefix.
            // A budget exit is terminal; its last visit may be unfinished.
            if entry.status != .budgetExhausted {
                for (position, example) in visited.enumerated() {
                    let rejected = position == visited.count - 1 &&
                        (entry.status == .trainingMismatch || entry.status == .trainingUndefined)
                    do { try schedule.observe(index: example, falsified: rejected) }
                    catch { return false }
                }
            }
        }
        if !run.traceTruncated && fits != run.programIDs {
            // A fit is recorded before prediction; its prediction can exhaust the budget.
            guard run.outcome == .budgetExhausted, run.programIDs.count == fits.count + 1,
                  let last = run.trace.last, last.status == .budgetExhausted,
                  last.trainingExamplesChecked == trainingCount,
                  run.programIDs.last?.components(separatedBy: ":map=").first == last.programID else { return false }
        }
        return true
    }
}

struct ARCSolverReview: Sendable {
    /// This attempt's accounting identity, distinct from a deduplicated receipt's original task.
    let taskID: String
    let document: ARCSolverDocument
    let run: ARCSolverRun
    let elapsedMilliseconds: Int
    let evidenceID: String?
    let error: String?
    let replayMatched: Bool?
}

struct ARCSolverExecution: Sendable {
    let run: ARCSolverRun
    let configuration: ARCSolverConfiguration
    let codeHash: String

    static func local(_ input: ARCSolverInput, configuration: ARCSolverConfiguration) async throws -> Self {
        try Task.checkCancellation()
        guard let executable = Bundle.main.executableURL else { throw ARCCapabilitiesError.invalid("Cannot identify this solver build.") }
        let handle = try FileHandle(forReadingFrom: executable)
        defer { try? handle.close() }
        var digest = SHA256(), size = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            size += chunk.count
            guard size <= 512 * 1_048_576 else { throw ARCCapabilitiesError.invalid("Solver executable exceeds its identity limit.") }
            digest.update(data: chunk)
        }
        guard size > 0 else { throw ARCCapabilitiesError.invalid("Solver executable is empty.") }
        let codeHash = "sha256:" + digest.finalize().map { String(format: "%02x", $0) }.joined()
        let result = try ARCSymbolicSolver.solve(input, configuration: configuration, isCancelled: { Task.isCancelled })
        return Self(run: result, configuration: configuration, codeHash: codeHash)
    }
}

private func validDigest(_ value: String) -> Bool {
    value.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil
}
