import Foundation
import XCTest
@testable import ARCHiDesktop

final class ARCQwenProposalTests: XCTestCase {
    private let model = QwenModelMetadata(name: "qwen3.5:9b", family: "qwen35", parameterSize: "9.7B",
                                          quantization: "Q4_K_M", digest: String(repeating: "a", count: 64))
    private let codeHash = "sha256:" + String(repeating: "b", count: 64) // Explicit fixture-only executable identity.

    func testClosedProgramSchemaAndRequestModelBindingRejectUntrustedContent() throws {
        let input = ARCSolverInput(training: [.init(input: [[1]], output: [[1]])], testInputs: [[[2]]])
        let request = try ARCQwenProposalEngine.request(input: input, requestID: UUID().uuidString)
        let accepted = try ARCQwenProposalEngine.evaluate(response(request), request: request, input: input, expectedModel: model)
        XCTAssertEqual(accepted.status, .predicted)
        XCTAssertEqual(accepted.predictions, [[[2]]], "Empty steps and no palette is a valid identity proposal.")
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["output"] = [[1]] },
            { $0["steps"] = ["executePython"] },
            { $0["steps"] = Array(repeating: "rotate90", count: 4) },
            { $0["learnPalette"] = 1 },
            { $0["requestID"] = UUID().uuidString },
            { $0["inputDigest"] = "sha256:" + String(repeating: "0", count: 64) },
            { $0["decision"] = "ABSTAIN"; $0["steps"] = ["rotate90"] }
        ]
        for mutation in mutations {
            XCTAssertThrowsError(try ARCQwenProposalEngine.evaluate(response(request, change: mutation), request: request, input: input, expectedModel: model))
        }
        let valid = try response(request)
        let duplicate = LocalRoleResult(requestID: valid.requestID, role: valid.role,
            text: String(valid.text.dropLast()) + ",\"steps\":[]}", model: model, elapsedMilliseconds: 1)
        XCTAssertThrowsError(try ARCQwenProposalEngine.evaluate(duplicate, request: request, input: input, expectedModel: model))
        let changedModel = QwenModelMetadata(name: model.name, family: model.family, parameterSize: model.parameterSize,
                                             quantization: model.quantization, digest: String(repeating: "c", count: 64))
        XCTAssertThrowsError(try ARCQwenProposalEngine.evaluate(valid, request: request, input: input, expectedModel: changedModel))
        var changedRequest = request
        changedRequest.systemInstructionOverride = nil
        XCTAssertThrowsError(try ARCQwenProposalEngine.evaluate(valid, request: changedRequest, input: input, expectedModel: model))
    }

    func testTargetPoisoningChangesOnlyIndependentCheckerAndNeverTheModelRequest() throws {
        let original = try ARCSolverDocument.parse(ARCSolverDocument.sample, name: "Fixture label", isSynthetic: true)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: ARCSolverDocument.sample) as? [String: Any])
        var tests = try XCTUnwrap(raw["test"] as? [[String: Any]])
        tests[0]["output"] = [[9]]
        raw["test"] = tests
        let changed = try ARCSolverDocument.parse(JSONSerialization.data(withJSONObject: raw), name: "Different label", isSynthetic: true)
        let id = UUID().uuidString
        let firstRequest = try ARCQwenProposalEngine.request(input: original.input, requestID: id)
        let secondRequest = try ARCQwenProposalEngine.request(input: changed.input, requestID: id)
        XCTAssertEqual(firstRequest.input, secondRequest.input)
        XCTAssertEqual(firstRequest.outputSchema, secondRequest.outputSchema)
        XCTAssertEqual(Set(try XCTUnwrap(firstRequest.input.object).keys), ["requestID", "inputDigest", "input"])
        XCTAssertEqual(Set(try XCTUnwrap(firstRequest.input["input"]?.object).keys), ["training", "testInputs"])
        XCTAssertNotNil(firstRequest.systemInstructionOverride)
        let terminal = try response(firstRequest) { $0["steps"] = ["rotate90"] }
        let first = try ARCQwenProposalEngine.evaluate(terminal, request: firstRequest, input: original.input, expectedModel: model)
        let second = try ARCQwenProposalEngine.evaluate(terminal, request: secondRequest, input: changed.input, expectedModel: model)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.trainingPassed, original.input.training.count)
        let firstBundle = try ARCQwenProposalEngine.bundle(document: original, result: first, codeHash: codeHash, model: model)
        let secondBundle = try ARCQwenProposalEngine.bundle(document: changed, result: second, codeHash: codeHash, model: model)
        let summary = try ARCCapabilitiesEvaluator.evaluate(firstBundle)
        XCTAssertEqual(summary.solverID, "archi-local-qwen-proposal")
        XCTAssertEqual(summary.counts.exact, 1)
        XCTAssertEqual(try ARCCapabilitiesEvaluator.evaluate(secondBundle).counts.exact, 0)
        XCTAssertEqual(summary.certification, "not-certified")
        XCTAssertFalse(summary.permitsStateChanges)
    }

    func testSingleProgramVisitsAllTrainingBeforeTestsAndKeepsGeometryPaletteAndWorkBounds() throws {
        let mismatch = ARCSolverInput(training: [
            .init(input: [[1]], output: [[9]]), .init(input: [[2]], output: [[2]])
        ], testInputs: [[[0]]])
        let rejected = try ARCSymbolicSolver.evaluateProposal(mismatch, steps: [.cropNonzero], learnPalette: false)
        XCTAssertEqual(rejected.status, .trainingMismatch)
        XCTAssertEqual(rejected.trainingPassed, 1, "The later training pair is checked after the first pair fails.")
        XCTAssertEqual(rejected.trainingCount, 2)
        XCTAssertNil(rejected.predictions, "No test transform runs after training rejection.")

        let mapping = ARCSolverInput(training: [.init(input: [[1,1], [0,1]], output: [[2,2], [0,2]])], testInputs: [[[7,7], [0,7]]])
        let unseen = try ARCSymbolicSolver.evaluateProposal(mapping, steps: [.cropLargest], learnPalette: true)
        XCTAssertEqual(unseen.status, .predictionUndefined)
        XCTAssertEqual(unseen.trainingPassed, 1)
        XCTAssertNil(unseen.predictions)

        let grid = Array(repeating: Array(repeating: 1, count: 30), count: 30)
        let bounded = ARCSolverInput(training: [.init(input: grid, output: grid)], testInputs: [grid])
        XCTAssertEqual(try ARCSymbolicSolver.evaluateProposal(bounded, steps: [.scale2], learnPalette: false).status, .trainingUndefined)
        let expensive = ARCSolverInput(training: Array(repeating: .init(input: grid, output: grid), count: 20), testInputs: Array(repeating: grid, count: 20))
        let exhausted = try ARCSymbolicSolver.evaluateProposal(expensive, steps: [.keepLargest, .keepLargest, .keepLargest], learnPalette: false)
        XCTAssertEqual(exhausted.status, .budgetExhausted)
        XCTAssertLessThanOrEqual(exhausted.cellOperations, 2_000_000)
        XCTAssertNil(exhausted.predictions)
    }

    func testAbstentionDoesNotExecuteAProgramAndCancellationStopsBeforeAdmission() throws {
        let input = ARCSolverInput(training: [.init(input: [[1]], output: [[2]])], testInputs: [[[3]]])
        let request = try ARCQwenProposalEngine.request(input: input, requestID: UUID().uuidString)
        let abstain = try response(request) { $0["decision"] = "ABSTAIN" }
        let result = try ARCQwenProposalEngine.evaluate(abstain, request: request, input: input, expectedModel: model)
        XCTAssertEqual(result.status, .abstained)
        XCTAssertEqual(result.cellOperations, 0)
        XCTAssertEqual(result.trainingPassed, 0)
        XCTAssertNil(result.predictions)
        XCTAssertThrowsError(try ARCQwenProposalEngine.evaluate(abstain, request: request, input: input, expectedModel: model, isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertThrowsError(try ARCSymbolicSolver.evaluateProposal(input, steps: [], learnPalette: false, isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
        let invalid = ARCSolverInput(training: [.init(input: [[10]], output: [[1]])], testInputs: [[[1]]])
        XCTAssertThrowsError(try ARCQwenProposalEngine.request(input: invalid, requestID: UUID().uuidString))
    }

    private func response(_ request: LocalRoleRequest, change: (inout [String: Any]) -> Void = { _ in }) throws -> LocalRoleResult {
        var object: [String: Any] = ["requestID": request.id, "inputDigest": try XCTUnwrap(request.input["inputDigest"]?.string),
                                    "decision": "PROPOSE", "steps": [String](), "learnPalette": false]
        change(&object)
        return LocalRoleResult(requestID: request.id, role: .reasoning,
            text: String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self),
            model: model, elapsedMilliseconds: 1)
    }
}
