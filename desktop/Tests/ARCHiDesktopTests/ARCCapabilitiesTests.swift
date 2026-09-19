import XCTest
@testable import ARCHiDesktop

final class ARCCapabilitiesTests: XCTestCase {
    private func bundle(_ modify: (inout [String: Any]) throws -> Void = { _ in }) throws -> Data {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: ARCCapabilitiesEvaluator.syntheticBundle) as? [String: Any])
        try modify(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }

    func testNativeScoringMatchesFrozenTypeScriptGoldenHashes() throws {
        let result = try ARCCapabilitiesEvaluator.evaluate(ARCCapabilitiesEvaluator.syntheticBundle)
        XCTAssertEqual(result.manifestHash, "sha256:03156b46f2f5cf4b925bc7944eb1e976d9bb5b3ac1aed56a2bfef05829b9d924")
        XCTAssertEqual(result.proposalHash, "sha256:d07944169a6ee25b3e43ecf445a5644a7abadba13a855706ae562ad9bf67c4b7")
        XCTAssertEqual(result.receiptHashes, ["sha256:4084b8b731852f3759322143a5136f30be4c6130eb42879ed7722e03808fb7c0", "sha256:71f6c24fbd68853ac439e8077f5d1e6ae6ea77da5b59c92e40248022bfb9677a"])
        XCTAssertEqual(result.counts.exact, 1)
        XCTAssertEqual(result.counts.incorrect, 1)
        XCTAssertEqual(result.counts.totalExamples, 2)
        XCTAssertEqual(result.status, "proposed")
        XCTAssertFalse(result.permitsStateChanges)
        XCTAssertFalse(result.reproducible)
    }

    func testNativeDemoIsIdenticalToPortableLabFixture() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let exported = try Data(contentsOf: root.appendingPathComponent("arc/fixtures/portable/smoke-evaluation-v1.json"))
        XCTAssertEqual(try ARCCapabilitiesEvaluator.evaluate(exported), try ARCCapabilitiesEvaluator.evaluate(ARCCapabilitiesEvaluator.syntheticBundle))
    }

    func testFractionalRateMatchesTypeScriptGoldenCanonicalization() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let exported = try Data(contentsOf: root.appendingPathComponent("arc/fixtures/portable/third-rate-evaluation-v1.json"))
        let result = try ARCCapabilitiesEvaluator.evaluate(exported)
        XCTAssertEqual(result.counts.exact, 1)
        XCTAssertEqual(result.counts.totalExamples, 3)
        XCTAssertEqual(result.proposalHash, "sha256:f7fb816bfae94adb637517602305c10968ad0f6db30243211fda6f334099c629")
    }

    func testMissingTasksAndPredictionsStayInDenominator() throws {
        let omitted = try bundle { $0["evaluations"] = [] }
        let result = try ARCCapabilitiesEvaluator.evaluate(omitted)
        XCTAssertEqual(result.counts.missing, 2)
        XCTAssertEqual(result.counts.totalExamples, 2)
        XCTAssertFalse(result.receiptCoverageComplete)
        let noPredictions = try bundle {
            var evaluations = $0["evaluations"] as! [[String: Any]]
            evaluations[0]["predictions"] = []
            $0["evaluations"] = evaluations
        }
        let missing = try ARCCapabilitiesEvaluator.evaluate(noPredictions)
        XCTAssertEqual(missing.counts.missing, 2)
        XCTAssertTrue(missing.receiptCoverageComplete)
        XCTAssertFalse(missing.scoredCoverageComplete)
    }

    func testInvalidPredictionRemainsVisibleAndCannotBeCoercedFromBoolean() throws {
        let input = try bundle {
            var evaluations = $0["evaluations"] as! [[String: Any]]
            evaluations[0]["predictions"] = [[[true]], NSNull()]
            $0["evaluations"] = evaluations
        }
        let result = try ARCCapabilitiesEvaluator.evaluate(input)
        XCTAssertEqual(result.counts.invalid, 2)
        XCTAssertEqual(result.counts.totalExamples, 2)
    }

    func testHiddenTargetIsUnscoredAndExactResultStillHasNoAuthority() throws {
        let hidden = try bundle { root in
            var evaluations = root["evaluations"] as! [[String: Any]]
            var task = evaluations[0]["task"] as! [String: Any]
            var tests = task["test"] as! [[String: Any]]
            tests[0].removeValue(forKey: "output")
            task["test"] = tests
            evaluations[0]["task"] = task
            root["evaluations"] = evaluations
            var manifest = root["manifest"] as! [String: Any]
            var entries = manifest["tasks"] as! [[String: Any]]
            entries[0]["taskHash"] = try ARCCapabilitiesEvaluator.digest(task)
            manifest["tasks"] = entries
            root["manifest"] = manifest
        }
        let result = try ARCCapabilitiesEvaluator.evaluate(hidden)
        XCTAssertEqual(result.counts.unscored, 1)
        XCTAssertEqual(result.counts.incorrect, 1)
        let perfect = try bundle {
            var evaluations = $0["evaluations"] as! [[String: Any]]
            evaluations[0]["predictions"] = [[[2, 0, 2]], [[6, 6], [0, 6]]]
            $0["evaluations"] = evaluations
        }
        let correct = try ARCCapabilitiesEvaluator.evaluate(perfect)
        XCTAssertTrue(correct.allExact)
        XCTAssertEqual(correct.certification, "not-certified")
        XCTAssertFalse(correct.permitsStateChanges)
    }

    func testTamperedFrozenTaskAndForgedSummaryAreRejected() throws {
        let mutated = try bundle {
            var evaluations = $0["evaluations"] as! [[String: Any]]
            var task = evaluations[0]["task"] as! [String: Any]
            task["train"] = [["input": [[1]], "output": [[2]]]]
            evaluations[0]["task"] = task
            $0["evaluations"] = evaluations
        }
        XCTAssertThrowsError(try ARCCapabilitiesEvaluator.evaluate(mutated))
        XCTAssertThrowsError(try ARCCapabilitiesEvaluator.evaluate(bundle { $0["accepted"] = true }))
        XCTAssertThrowsError(try ARCCapabilitiesEvaluator.evaluate(bundle { $0["taskID"] = UUID().uuidString }))
        XCTAssertThrowsError(try ARCCapabilitiesEvaluator.evaluate(bundle { $0["evaluations"] = [["receiptHash": "forged"]] }))
    }

    func testDuplicateTasksExcessPredictionsAndLargeInputAreRejected() throws {
        XCTAssertThrowsError(try ARCCapabilitiesEvaluator.evaluate(bundle {
            let evaluations = $0["evaluations"] as! [[String: Any]]
            $0["evaluations"] = evaluations + evaluations
        }))
        XCTAssertThrowsError(try ARCCapabilitiesEvaluator.evaluate(bundle {
            var evaluations = $0["evaluations"] as! [[String: Any]]
            evaluations[0]["predictions"] = [[[1]], [[1]], [[1]]]
            $0["evaluations"] = evaluations
        }))
        XCTAssertThrowsError(try ARCCapabilitiesEvaluator.evaluate(Data(repeating: 0x20, count: ARCCapabilitiesEvaluator.maximumBytes + 1)))
    }

    func testEmptyManifestCannotProduceSuccessfulCapabilityAndSourceCannotSelfCertify() throws {
        let empty = try bundle {
            var manifest = $0["manifest"] as! [String: Any]
            manifest["tasks"] = []
            $0["manifest"] = manifest
            $0["evaluations"] = []
        }
        let result = try ARCCapabilitiesEvaluator.evaluate(empty)
        XCTAssertEqual(result.counts.totalExamples, 0)
        XCTAssertFalse(result.allExact)
        XCTAssertThrowsError(try ARCCapabilitiesEvaluator.evaluate(bundle {
            var manifest = $0["manifest"] as! [String: Any]
            var source = manifest["source"] as! [String: Any]
            source["status"] = "certified"
            manifest["source"] = source
            $0["manifest"] = manifest
        }))
        XCTAssertThrowsError(try ARCCapabilitiesEvaluator.evaluate(bundle {
            var solver = $0["solver"] as! [String: Any]
            solver["attestation"] = "certified"
            $0["solver"] = solver
        }))
    }

    @MainActor
    func testPersistedRawInputsAreRescoredAndRepeatedEvidenceIsDeduplicated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("evidence.json")
        let store = ARCCapabilitiesStore(storageURL: url)
        let first = store.runSyntheticDemonstration()
        XCTAssertNotNil(UUID(uuidString: first.taskID))
        XCTAssertEqual(first.passed, false)
        XCTAssertNil(first.error)
        let repeated = store.runSyntheticDemonstration()
        XCTAssertNotEqual(first.taskID, repeated.taskID)
        XCTAssertEqual(first.evidenceID, repeated.evidenceID)
        XCTAssertEqual(store.records.count, 1)
        let reopened = ARCCapabilitiesStore(storageURL: url)
        XCTAssertNil(reopened.lastError)
        XCTAssertEqual(reopened.records.first?.summary, store.records.first?.summary)
        let before = try Data(contentsOf: url)
        let invalid = reopened.evaluate(data: Data("{}".utf8))
        XCTAssertNil(invalid.passed)
        XCTAssertNil(invalid.evidenceID)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    @MainActor
    func testCorruptArchiveAndWriteFailureNeverOverwriteOrPresentSuccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("evidence.json")
        let bytes = Data("corrupt evidence".utf8)
        try bytes.write(to: url)
        let store = ARCCapabilitiesStore(storageURL: url)
        XCTAssertNotNil(store.lastError)
        XCTAssertNotNil(store.runSyntheticDemonstration().error)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let impossible = ARCCapabilitiesStore(storageURL: url.appendingPathComponent("cannot-write.json"))
        XCTAssertNotNil(impossible.runSyntheticDemonstration().error)
        XCTAssertTrue(impossible.records.isEmpty)
    }

    @MainActor
    func testTwoSessionsCannotOverwriteAnEvidenceShelfFromAStaleSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("evidence.json")
        let first = ARCCapabilitiesStore(storageURL: url)
        let stale = ARCCapabilitiesStore(storageURL: url)
        XCTAssertNil(first.runSyntheticDemonstration().error)
        let saved = try Data(contentsOf: url)
        let event = stale.runSyntheticDemonstration()
        XCTAssertNotNil(event.error)
        XCTAssertNil(event.evidenceID)
        XCTAssertNil(event.passed)
        XCTAssertTrue(stale.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), saved)
        let reopened = ARCCapabilitiesStore(storageURL: url)
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertNil(reopened.runSyntheticDemonstration().error)
    }
}
