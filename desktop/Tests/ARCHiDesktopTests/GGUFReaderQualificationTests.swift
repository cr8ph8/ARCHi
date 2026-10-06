import XCTest
@testable import ARCHiDesktop

final class GGUFReaderQualificationTests: XCTestCase {
    private let identity = String(repeating: "a", count: 64)
    private var direction: [Double] { [1] + Array(repeating: 0, count: 4095) }
    private var center: [Double] { Array(repeating: 0, count: 4096) }

    func testCompleteConsistentReportCanBeImported() throws {
        let artifact = try GGUFReaderArtifact.decode(try artifactBytes(report()))
        XCTAssertTrue(artifact.hasLimitedShadowReport)
        XCTAssertEqual(artifact.calibrationSummary?.holdoutCorrect, 8)
        XCTAssertFalse(artifact.canMeasureGeneralReplies)
    }

    @MainActor
    func testPassingSyntheticReaderCannotEnableOrRerouteOrdinaryReplies() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let readerURL = directory.appendingPathComponent("reader.json")
        try artifactBytes(report()).write(to: readerURL)
        var clients: [InspectionOnlyReaderClient] = []
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistantFactory: { _, _ in
                let client = InspectionOnlyReaderClient()
                clients.append(client)
                return client
            }, allowsPlay: false)
        store.selectQwenModel("qwen3:8b")
        store.importRepresentationReader(from: readerURL)
        XCTAssertTrue(store.representationReader?.hasLimitedShadowReport == true)
        let clientCount = clients.count, route = store.route
        let ticket = store.contextTicket()

        store.setRepresentationMeasurementsEnabled(true)

        XCTAssertFalse(store.representationMeasurementsEnabled)
        XCTAssertNotNil(store.representationReader, "Inspection remains available after the refused enable request")
        XCTAssertTrue(store.representationNotice.contains("synthetic"), "Reject on task scope even when no worker is bundled")
        XCTAssertEqual(clients.count, clientCount, "Refused enablement must not replace the ordinary client")
        XCTAssertEqual(store.route, route)
        XCTAssertTrue(store.isCurrent(ticket, requireVisible: false))
        XCTAssertTrue(clients.allSatisfy { $0.connectCount == 0 && $0.replyCount == 0 })
        await store.shutdownAssistant()
    }

    func testHeadlinePassWithoutEvidenceIsRejected() throws {
        var value = report()
        value.removeValue(forKey: "results")
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(artifactBytes(value)))
    }

    func testDevelopmentCorpusCannotBecomeQualifiedByChangingHeadline() throws {
        var value = report()
        value["qualificationEligible"] = false
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(artifactBytes(value)))
        value = report()
        var provenance = value["corpusProvenance"] as! [String: Any]
        provenance["kind"] = "builtin-disclosed-development"
        value["corpusProvenance"] = provenance
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(artifactBytes(value)))
    }

    func testPlanMustMatchExactModelLayerAndFrozenPayload() throws {
        for field in ["modelDigest", "layer", "minimumSignedMargin", "heldoutRetries"] {
            var value = report()
            var plan = value["plan"] as! [String: Any]
            plan[field] = ["modelDigest": String(repeating: "b", count: 64), "layer": "l_out-16",
                           "minimumSignedMargin": 0.01, "heldoutRetries": true][field]
            value["plan"] = plan
            freeze(&value)
            XCTAssertThrowsError(try GGUFReaderArtifact.decode(artifactBytes(value)), field)
        }
        var value = report()
        value["planPayload"] = (value["planPayload"] as! String) + " "
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(artifactBytes(value)))
    }

    func testNumericalValuesCannotBeSwappedUnderPassingReport() throws {
        var artifact = artifactObject(report())
        var changed = center
        changed[0] = 0.1
        artifact["center"] = changed
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(json(artifact)))
        artifact = artifactObject(report())
        artifact["readerDigest"] = String(repeating: "b", count: 64)
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(json(artifact)))
    }

    func testResultMathAndMarginMustAgreeWithNumericalReader() throws {
        for (field, bad): (String, Any) in [("coordinate", 0.99), ("signedMargin", 0.01),
                                           ("rawScore", 100.0), ("correct", false), ("marginPass", false)] {
            var value = report()
            var results = value["results"] as! [[String: Any]]
            results[0][field] = bad
            value["results"] = results
            XCTAssertThrowsError(try GGUFReaderArtifact.decode(artifactBytes(value)), field)
        }
        var value = report()
        value["calibrationSeparation"] = 3.0
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(artifactBytes(value)))
    }

    func testDuplicatedSamplesAndSplitOverlapAreRejected() throws {
        var value = report()
        var results = value["results"] as! [[String: Any]]
        results[1]["sampleID"] = results[0]["sampleID"]
        value["results"] = results
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(artifactBytes(value)))
        value = report()
        results = value["results"] as! [[String: Any]]
        results[8]["group"] = results[0]["group"]
        value["results"] = results
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(artifactBytes(value)))
    }

    func testLegacyImportRemainsInspectionOnly() throws {
        var value = artifactObject(report())
        value["schemaVersion"] = GGUFReaderArtifact.legacySchemaVersion
        for key in ["tokenRule", "measurementScope", "calibrationReport"] { value.removeValue(forKey: key) }
        let artifact = try GGUFReaderArtifact.decode(json(value))
        XCTAssertFalse(artifact.hasLimitedShadowReport)
        XCTAssertFalse(artifact.canMeasureGeneralReplies)
    }

    func testNumericalBindingMatchesIndependentPythonFloat64Vector() {
        XCTAssertEqual(GGUFReaderQualification.numericDigest(directions: [direction], center: center,
                                                             offsets: [0], scales: [1]),
                       "e645878f43acf056f4dfcd3b06e6dcb91ac702900a87a1df6934bb71edb0965e")
    }

    func testSuppliedPythonToyFixtureInteroperability() throws {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_READER_TOY_FIXTURE"] else {
            throw XCTSkip("Opt-in fixture generated by Python contract checks; never a real calibrated reader.")
        }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let summary = try GGUFReaderQualification.validate(value["calibrationReport"] as! String,
            digest: value["calibrationDigest"] as! String, modelName: value["modelName"] as! String,
            modelDigest: value["modelDigest"] as! String, modelBlobDigest: value["modelBlobDigest"] as! String,
            templateDigest: value["templateDigest"] as! String, backendRevision: value["backendRevision"] as! String,
            layer: value["layer"] as! String, readerDigest: value["readerDigest"] as! String,
            directions: value["directions"] as! [[Double]], center: value["center"] as! [Double],
            scoreOffset: value["scoreOffset"] as! [Double], scoreScale: value["scoreScale"] as! [Double])
        XCTAssertEqual(summary.holdoutCorrect, 8)
        // The experimental backend remains outside the bundled native pin even
        // when its report is internally consistent. Do not relabel the fixture.
        XCTAssertNotEqual(value["backendRevision"] as? String, GGUFReaderArtifact.backendRevision)
        XCTAssertThrowsError(try GGUFReaderArtifact.decode(bytes))
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func freeze(_ value: inout [String: Any]) {
        let bytes = try! json(value["plan"]!) + Data([10])
        value["planPayload"] = String(decoding: bytes, as: UTF8.self)
        value["planDigest"] = GGUFReaderArtifact.digest(bytes)
    }

    private func report() -> [String: Any] {
        let provenance: [String: Any] = ["kind": "external-frozen-synthetic", "sourceDigest": identity,
            "corpusDigest": identity, "canonicalDigest": identity,
            "validation": "archi-synthetic-paired-corpus-validation/v1",
            "pairInventory": "exact-lexical-words-and-punctuation", "priorExposure": "not-established"]
        let plan: [String: Any] = ["schema": "archi-reader-plan/v1", "algorithm": "mean_contrast_reader",
            "layer": "l_out-15", "tokenRule": "prompt-last", "measurementScope": GGUFReaderArtifact.promptFinalMeasurementScope,
            "hiddenWidth": 4096, "fitPairs": 4, "calibrationPairs": 4, "holdoutPairs": 4, "minimumSignedMargin": 0.1,
            "requiresPerfectCalibrationSeparation": true, "requiresAllHoldoutCorrect": true,
            "layerSearch": false, "algorithmSearch": false, "heldoutRetries": false,
            "modelName": "qwen3:8b", "modelDigest": identity, "modelBlobDigest": identity,
            "templateDigest": GGUFReaderArtifact.templateDigest, "backendRevision": GGUFReaderArtifact.backendRevision,
            "datasetDigest": identity, "numericsSourceDigest": identity, "workflowSourceDigest": identity,
            "corpusSourceDigest": identity, "workerSourceDigest": identity,
            "runtimeRecipeDigest": identity, "requestDigest": identity,
            "qualificationEligible": true, "corpusProvenance": provenance]
        var results: [[String: Any]] = []
        for split in ["calibration", "holdout"] {
            for group in 0..<4 {
                for label in [-1, 1] {
                    results.append(["sampleID": "\(split)-\(group)-\(label)", "group": "\(split)-\(group)",
                        "split": split, "label": label, "rawScore": Double(label),
                        "coordinate": 1 / (1 + exp(-Double(label))), "signedMargin": 1,
                        "correct": true, "marginPass": true])
                }
            }
        }
        var value: [String: Any] = ["schema": "archi-gguf-reader-calibration/v1", "status": "limited-shadow-pass",
            "measurementScope": GGUFReaderArtifact.promptFinalMeasurementScope, "tokenRule": "prompt-last",
            "prefillOnly": true, "qualificationEligible": true, "corpusProvenance": provenance,
            "fitCount": 8, "calibrationCount": 8, "holdoutCount": 8, "holdoutCorrect": 8, "holdoutAccuracy": 1,
            "calibrationSeparation": 2, "minimumSignedMargin": 0.1,
            "plan": plan, "activationDigest": identity, "acquisitionReceiptDigest": identity,
            "acquisitionStartDigest": identity, "frozenFitDigest": identity, "readerDigest": identity,
            "numericDigest": GGUFReaderQualification.numericDigest(directions: [direction], center: center, offsets: [0], scales: [1]),
            "results": results]
        freeze(&value)
        return value
    }

    private func artifactObject(_ report: [String: Any]) -> [String: Any] {
        let bytes = try! json(report)
        return ["schemaVersion": GGUFReaderArtifact.schemaVersion, "modelName": "qwen3:8b",
            "modelDigest": identity, "modelBlobDigest": identity, "namespace": "hampton.experimental.synthetic-record-field-support.v1",
            "tokenizerDigest": identity, "templateDigest": GGUFReaderArtifact.templateDigest,
            "backendRevision": GGUFReaderArtifact.backendRevision, "precision": "Q4_K_M", "layer": "l_out-15",
            "readerName": "synthetic-record-field-support", "basisDigest": identity, "readerDigest": identity,
            "calibrationDigest": GGUFReaderArtifact.digest(bytes), "directions": [direction], "center": center,
            "scoreOffset": [0], "scoreScale": [1], "provenance": "Synthetic test fixture, not a real reader.",
            "tokenRule": "prompt-last", "measurementScope": GGUFReaderArtifact.promptFinalMeasurementScope,
            "calibrationReport": String(decoding: bytes, as: UTF8.self)]
    }

    private func artifactBytes(_ report: [String: Any]) throws -> Data { try json(artifactObject(report)) }
}

@MainActor
private final class InspectionOnlyReaderClient: AssistantClient {
    var connectCount = 0
    var replyCount = 0
    func connect() async throws { connectCount += 1 }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        replyCount += 1
    }
    func disconnect() {}
}
