import Foundation
import CryptoKit
import CoreFoundation

struct ARCCapabilitiesCounts: Codable, Equatable, Sendable {
    let exact: Int
    let incorrect: Int
    let missing: Int
    let invalid: Int
    let unscored: Int
    let totalExamples: Int
    let exactTasks: Int
    let totalTasks: Int
}

struct ARCCapabilitiesSummary: Equatable, Sendable {
    let manifestID: String
    let manifestHash: String
    let proposalHash: String
    let receiptHashes: [String]
    let sourceLabel: String
    let sourceStatus: String
    let solverID: String
    let counts: ARCCapabilitiesCounts
    let receiptCoverageComplete: Bool
    let scoredCoverageComplete: Bool
    let status = "proposed"
    let certification = "not-certified"
    let attestation = "unattested"
    let reproducible = false
    let permitsStateChanges = false
    var allExact: Bool { counts.totalExamples > 0 && counts.exact == counts.totalExamples }
}

enum ARCCapabilitiesError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let detail) = self { detail } else { nil } }
}

/// Native implementation of archi-arc-exact-v1. Only raw frozen inputs are admitted.
/// Hashes are interoperability checks, never signatures or authority to evolve.
enum ARCCapabilitiesEvaluator {
    static let maximumBytes = 2 * 1024 * 1024
    static let maximumTasks = 64
    static let schema = "archi-arc-evaluation-bundle/v1"
    static let scorer = "archi-arc-exact-v1"
    private static var authority: [String: Any] { [
        "canonWritable": false, "journeyWritable": false, "memoryWritable": false,
        "permissionGrant": false, "actionWritable": false, "xpDelta": 0,
    ] }

    static func evaluate(_ data: Data) throws -> ARCCapabilitiesSummary {
        guard data.count <= maximumBytes else { throw failure("Bundle exceeds 2 MiB.") }
        let root = try object(JSONSerialization.jsonObject(with: data), keys: ["schema", "manifest", "solver", "evaluations"])
        guard root["schema"] as? String == schema else { throw failure("Unsupported ARC bundle schema.") }
        let manifest = try object(root["manifest"], keys: ["schemaVersion", "manifestId", "mode", "integration", "scorerVersion", "source", "split", "tasks"])
        guard integer(manifest["schemaVersion"]) == 1, manifest["integration"] as? String == "none",
              manifest["scorerVersion"] as? String == scorer else { throw failure("Unsupported manifest contract.") }
        let manifestID = try identifier(manifest["manifestId"])
        let split = try identifier(manifest["split"])
        let source = try object(manifest["source"], keys: ["label", "status", "snapshot", "contentHash"])
        guard let label = source["label"] as? String, (1...160).contains(label.utf16.count) else { throw failure("Invalid source label.") }
        _ = try identifier(source["snapshot"])
        let datasetHash = try digestString(source["contentHash"])
        let mode = manifest["mode"] as? String
        let sourceStatus = source["status"] as? String
        guard (mode == "fixture" && sourceStatus == "synthetic-fixture") ||
              (mode == "offline-dataset" && sourceStatus == "unverified-offline-snapshot") else {
            throw failure("Source must remain synthetic or an unverified offline snapshot.")
        }
        let solver = try object(root["solver"], keys: ["id", "version", "codeHash", "configurationHash"])
        let solverID = try identifier(solver["id"])
        _ = try identifier(solver["version"])
        _ = try digestString(solver["codeHash"])
        _ = try digestString(solver["configurationHash"])
        guard let entries = manifest["tasks"] as? [Any], entries.count <= maximumTasks else { throw failure("A desktop bundle supports at most 64 manifest tasks.") }
        var taskManifest: [String: (hash: String, count: Int)] = [:]
        for entry in entries {
            let item = try object(entry, keys: ["taskId", "taskHash", "testExamples"])
            let id = try identifier(item["taskId"])
            let hash = try digestString(item["taskHash"])
            guard let count = integer(item["testExamples"]), (1...20).contains(count), taskManifest[id] == nil else {
                throw failure("Invalid example count or duplicate manifest task.")
            }
            taskManifest[id] = (hash, count)
        }
        guard let evaluations = root["evaluations"] as? [Any], evaluations.count <= entries.count else { throw failure("Evaluation list exceeds manifest.") }
        let manifestHash = try digest(manifest)
        var seen = Set<String>()
        var results: [String: [String]] = [:]
        var receiptHashes: [String] = []
        for evaluation in evaluations {
            let item = try object(evaluation, keys: ["task", "predictions"])
            let task = try object(item["task"], keys: ["taskId", "train", "test"])
            let id = try identifier(task["taskId"])
            guard let frozen = taskManifest[id], seen.insert(id).inserted else { throw failure("Duplicate task or task outside manifest.") }
            let train = try examples(task["train"], requiresOutput: true)
            let test = try examples(task["test"], requiresOutput: false)
            // Validate all training content before its digest is trusted.
            guard !train.isEmpty, test.count == frozen.count, try digest(task) == frozen.hash else {
                throw failure("Task content or example count does not match the frozen manifest.")
            }
            guard let predictions = item["predictions"] as? [Any], predictions.count <= test.count else { throw failure("Invalid prediction list.") }
            var taskResults: [String] = []
            for (index, example) in test.enumerated() {
                let expected = example["output"]
                var result = "missing"
                var exact: Any = NSNull()
                var reason: Any = "missing-prediction"
                var predictionHash: Any = NSNull()
                if index < predictions.count {
                    if let predicted = try? grid(predictions[index]) {
                        predictionHash = try digest(predicted)
                        reason = NSNull()
                        if let expected {
                            let matches = try grid(expected) == predicted
                            exact = matches
                            result = matches ? "exact" : "incorrect"
                        } else { result = "unscored" }
                    } else {
                        result = "invalid"
                        reason = "invalid-prediction"
                    }
                }
                let receipt: [String: Any] = [
                    "schemaVersion": 1, "scorerVersion": scorer, "mode": mode!, "integration": "none",
                    "manifestHash": manifestHash, "datasetHash": datasetHash, "split": split,
                    "taskId": id, "taskHash": frozen.hash, "testIndex": index,
                    "taskInputHash": try digest(["taskId": id, "testIndex": index, "input": example["input"]!] as [String: Any]),
                    "solver": solver, "predictionHash": predictionHash,
                    "expectedOutputHash": try expected.map { try digest($0) } as Any? ?? NSNull(),
                    "result": result, "exact": exact, "reason": reason, "attestation": "unattested",
                    "reproducible": false, "authority": authority,
                ]
                receiptHashes.append(try digest(receipt))
                taskResults.append(result)
            }
            results[id] = taskResults
        }
        var totals = ["exact": 0, "incorrect": 0, "missing": 0, "invalid": 0, "unscored": 0]
        var exactTasks = 0
        for (id, frozen) in taskManifest {
            let outcomes = results[id] ?? Array(repeating: "missing", count: frozen.count)
            for outcome in outcomes { totals[outcome, default: 0] += 1 }
            if outcomes.allSatisfy({ $0 == "exact" }) { exactTasks += 1 }
        }
        let total = taskManifest.values.reduce(0) { $0 + $1.count }
        let counts: [String: Int] = totals.merging(["totalExamples": total, "exactTasks": exactTasks, "totalTasks": entries.count]) { _, rhs in rhs }
        let receiptCoverageComplete = receiptHashes.count == total
        let scoredCoverageComplete = totals["exact"]! + totals["incorrect"]! == total
        let proposal: [String: Any] = [
            "schemaVersion": 1, "status": "proposed", "capability": "abstract-reasoning-evidence",
            "certification": "not-certified", "integration": "none", "scorerVersion": scorer,
            "manifestHash": manifestHash, "datasetHash": datasetHash, "sourceStatus": sourceStatus!,
            "split": split, "solver": solver, "counts": counts,
            "exactRate": total == 0 ? NSNull() : Double(totals["exact"]!) / Double(total),
            "taskExactRate": entries.isEmpty ? NSNull() : Double(exactTasks) / Double(entries.count),
            "receiptCoverageComplete": receiptCoverageComplete, "scoredCoverageComplete": scoredCoverageComplete,
            "receiptHashes": receiptHashes.sorted(), "authority": authority,
        ]
        return ARCCapabilitiesSummary(manifestID: manifestID, manifestHash: manifestHash,
            proposalHash: try digest(proposal), receiptHashes: receiptHashes.sorted(), sourceLabel: label,
            sourceStatus: sourceStatus!, solverID: solverID,
            counts: ARCCapabilitiesCounts(exact: totals["exact"]!, incorrect: totals["incorrect"]!, missing: totals["missing"]!,
                invalid: totals["invalid"]!, unscored: totals["unscored"]!, totalExamples: total, exactTasks: exactTasks, totalTasks: entries.count),
            receiptCoverageComplete: receiptCoverageComplete, scoredCoverageComplete: scoredCoverageComplete)
    }

    private static func examples(_ value: Any?, requiresOutput: Bool) throws -> [[String: Any]] {
        guard let values = value as? [Any], (1...20).contains(values.count) else { throw failure("Task sections require 1–20 examples.") }
        return try values.map { value in
            guard let raw = value as? [String: Any] else { throw failure("Invalid task example.") }
            let example = try object(raw, keys: requiresOutput || raw["output"] != nil ? ["input", "output"] : ["input"])
            _ = try grid(example["input"])
            if let output = example["output"] { _ = try grid(output) }
            return example
        }
    }

    private static func grid(_ value: Any?) throws -> [[Int]] {
        guard let rows = value as? [Any], (1...30).contains(rows.count) else { throw failure("Invalid grid.") }
        var width: Int?
        return try rows.map { row in
            guard let cells = row as? [Any], (1...30).contains(cells.count), width == nil || width == cells.count else { throw failure("Invalid grid dimensions.") }
            width = cells.count
            return try cells.map { value in
                guard let value = integer(value), (0...9).contains(value) else { throw failure("Grid cells must be integers 0–9.") }
                return value
            }
        }
    }

    private static func object(_ value: Any?, keys: Set<String>) throws -> [String: Any] {
        guard let value = value as? [String: Any], Set(value.keys) == keys else { throw failure("Unexpected or missing fields in ARC data.") }
        return value
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
              value.doubleValue >= Double(Int.min), value.doubleValue < Double(Int.max) else { return nil }
        return value.intValue
    }
    private static func identifier(_ value: Any?) throws -> String {
        guard let value = value as? String, value.range(of: "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$", options: .regularExpression) != nil else { throw failure("Invalid bounded identifier.") }
        return value
    }
    private static func digestString(_ value: Any?) throws -> String {
        guard let value = value as? String, value.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil else { throw failure("Invalid SHA-256 digest.") }
        return value
    }
    private static func failure(_ text: String) -> ARCCapabilitiesError { .invalid(text) }

    /// ASCII contract keys; strings use JSON escaping, numbers are bounded integers or rates.
    static func canonicalJSON(_ value: Any) throws -> String {
        if value is NSNull { return "null" }
        if let value = value as? [String: Any] {
            return "{" + (try value.keys.sorted().map { try canonicalJSON($0) + ":" + canonicalJSON(value[$0]!) }).joined(separator: ",") + "}"
        }
        if let value = value as? [Any] { return "[" + (try value.map(canonicalJSON)).joined(separator: ",") + "]" }
        if let value = value as? String {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return value.boolValue ? "true" : "false" }
            if let int = integer(value) { return String(int) }
            guard value.doubleValue.isFinite else { throw failure("Nonfinite JSON number.") }
            return String(value.doubleValue)
        }
        throw failure("Unsupported JSON value.")
    }
    static func digest(_ value: Any) throws -> String {
        "sha256:" + SHA256.hash(data: Data(try canonicalJSON(value).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
