import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class RecordMeasurementClientTests: XCTestCase {
    private let input = RecordLookupTable.example + "\n\nWhich location is listed for R1?"

    func testFrozenBundleDecodesAndAnyByteChangeIsRejected() throws {
        let bytes = try fixtureBytes()
        let reader = try RecordMeasurementReader.decode(bytes)
        XCTAssertEqual(GGUFReaderArtifact.digest(bytes), RecordMeasurementReader.artifactDigest)
        XCTAssertEqual(reader.directions.first?.count, 4096)
        XCTAssertEqual(reader.center.count, 4096)
        XCTAssertEqual(GGUFReaderQualification.numericDigest(directions: reader.directions,
            center: reader.center, offsets: reader.scoreOffset, scales: reader.scoreScale), RecordMeasurementReader.numericDigest)
        var altered = bytes
        altered.append(10)
        XCTAssertThrowsError(try RecordMeasurementReader.decode(altered))
        XCTAssertThrowsError(try RecordMeasurementReader.decode(Data("{}".utf8)))
    }

    func testPreflightPrecedesOneZeroGenerationMeasurement() async throws {
        let reader = try reader()
        let validation = ScriptTransport(reader: reader, validated: true)
        let measurement = ScriptTransport(reader: reader, validated: false)
        var calls: [([String], TimeInterval)] = []
        let client = client(reader: reader) { _, arguments, timeout in
            calls.append((arguments, timeout))
            return calls.count == 1 ? validation : measurement
        }
        let result = try await client.measure(input: input, system: RecordLookupQuery.system, schema: RecordLookupQuery.schema)
        XCTAssertEqual(calls.map(\.0), [["--validate-record"], ["--measure-record"]])
        XCTAssertEqual(calls.map(\.1), [15, 180])
        XCTAssertEqual(validation.payload, measurement.payload)
        XCTAssertEqual(measurement.payload?["max_input_tokens"], .number(512))
        XCTAssertEqual(measurement.payload?["max_new_tokens"], .number(0))
        XCTAssertEqual(measurement.payload?["input"]?.string, input)
        XCTAssertEqual(measurement.payload?["measurement_scope"]?.string, RecordMeasurementReader.measurementScope)
        XCTAssertEqual(result.outputTokens, 0)
        XCTAssertEqual(result.inputTokens, 40)
        XCTAssertEqual(result.standardizedScore, 1, accuracy: 1e-10)
        XCTAssertEqual(result.readerDigest, RecordMeasurementReader.artifactDigest)
        XCTAssertNotNil(UUID(uuidString: result.requestID))
        client.shutdown()
    }

    func testResponseRejectsGenerationIdentityDriftNonfiniteAndExtraData() throws {
        let reader = try reader()
        let payload = JSONValue.object(Dictionary(uniqueKeysWithValues:
            RecordMeasurementClient.echoedKeys.map { ($0, JSONValue.string($0)) }))
        let good = ScriptTransport.response(payload: payload, reader: reader, validated: false)
        try RecordMeasurementClient.validateResponse(good, payload: payload, reader: reader, validationOnly: false)
        let changes: [(String, JSONValue)] = [
            ("output_tokens", .number(1)), ("input_tokens", .number(513)), ("input_tokens", .bool(true)),
            ("token_position", .number(40)), ("request_id", .string(UUID().uuidString)),
            ("numeric_digest", .string(String(repeating: "f", count: 64))),
            ("raw_score", .number(.infinity)), ("standardized_score", .number(2)),
            ("text", .string("must not be returned")), ("samples", .array([]))
        ]
        for (key, value) in changes {
            var changed = good.object!
            changed[key] = value
            XCTAssertThrowsError(try RecordMeasurementClient.validateResponse(.object(changed),
                payload: payload, reader: reader, validationOnly: false), key)
        }
        XCTAssertThrowsError(try RecordMeasurementClient.validateResponse(good, payload: payload,
            reader: reader, validationOnly: true), "No scores may appear in validation-only output")
    }

    func testUnsupportedEndpointAndChangedModelCannotStartMeasurement() async throws {
        let reader = try reader()
        var calls = 0
        let unsupported = ScriptTransport(reader: reader, validated: true,
            overrides: ["schema": .string("archi-gguf-shadow-result/v1")])
        let client = client(reader: reader) { _, _, _ in calls += 1; return unsupported }
        do {
            _ = try await client.measure(input: input, system: RecordLookupQuery.system, schema: RecordLookupQuery.schema)
            XCTFail("An old endpoint must not run a measurement")
        } catch { XCTAssertEqual(error as? RecordMeasurementError, .invalidResponse) }
        XCTAssertEqual(calls, 1)
        client.shutdown()

        var resolutions = 0, changedCalls = 0
        let changed = RecordMeasurementClient(readerLoader: { reader }, modelResolver: {
            resolutions += 1
            return URL(fileURLWithPath: resolutions == 1 ? "/synthetic/model-a" : "/synthetic/model-b")
        }, workerURL: { URL(fileURLWithPath: "/synthetic/worker") }, transportFactory: { _, _, _ in
            changedCalls += 1
            return ScriptTransport(reader: reader, validated: true)
        })
        do {
            _ = try await changed.measure(input: input, system: RecordLookupQuery.system, schema: RecordLookupQuery.schema)
            XCTFail("A replaced named model must lose readiness")
        } catch { XCTAssertEqual(error as? RecordMeasurementError, .unavailable) }
        XCTAssertEqual(changedCalls, 1)
        changed.shutdown()
    }

    func testCancelRejectsLateResultWithoutRetiringNextRequest() async throws {
        let reader = try reader()
        let started = expectation(description: "first scalar request pending")
        let late = ScriptTransport(reader: reader, validated: false, delayed: true, onRequest: { started.fulfill() })
        var count = 0
        let client = client(reader: reader) { _, arguments, _ in
            count += 1
            if count == 2 { return late }
            return ScriptTransport(reader: reader, validated: arguments == ["--validate-record"])
        }
        let first = Task { try await client.measure(input: input, system: RecordLookupQuery.system, schema: RecordLookupQuery.schema) }
        await fulfillment(of: [started], timeout: 2)
        client.cancel()
        XCTAssertGreaterThan(late.stopCount, 0)
        let next = try await client.measure(input: input, system: RecordLookupQuery.system, schema: RecordLookupQuery.schema)
        late.finish()
        do { _ = try await first.value; XCTFail("Cancelled request published its late scalar") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(next.outputTokens, 0)
        XCTAssertNotEqual(late.payload?["request_id"]?.string, next.requestID)
        XCTAssertEqual(count, 4)
        client.shutdown()
    }

    func testTaskCancellationAndShutdownRejectLateResultsAndPreventFurtherWork() async throws {
        let reader = try reader()
        let started = expectation(description: "validation pending")
        let late = ScriptTransport(reader: reader, validated: true, delayed: true, onRequest: { started.fulfill() })
        var count = 0
        let client = client(reader: reader) { _, _, _ in count += 1; return late }
        let request = Task { try await client.measure(input: input, system: RecordLookupQuery.system, schema: RecordLookupQuery.schema) }
        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        client.shutdown()
        late.finish()
        do { _ = try await request.value; XCTFail("A cancelled validation started measurement") }
        catch { XCTAssertTrue(error is CancellationError) }
        do {
            _ = try await client.measure(input: input, system: RecordLookupQuery.system, schema: RecordLookupQuery.schema)
            XCTFail("A retired client accepted another request")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(count, 1)
        XCTAssertGreaterThan(late.stopCount, 0)
    }

    private func fixtureBytes() throws -> Data {
        let desktop = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: desktop.appendingPathComponent("Sources/ARCHiDesktop/Resources/RecordReader/reader.qualified.json"))
    }

    private func reader() throws -> RecordMeasurementReader { try RecordMeasurementReader.decode(fixtureBytes()) }

    private func client(reader: RecordMeasurementReader,
                        factory: @escaping (URL, [String], TimeInterval) -> any RecordMeasurementTransport) -> RecordMeasurementClient {
        RecordMeasurementClient(readerLoader: { reader }, modelResolver: { URL(fileURLWithPath: "/synthetic/model") },
            workerURL: { URL(fileURLWithPath: "/synthetic/worker") }, transportFactory: factory)
    }
}

/// Synthetic in-memory worker. Deliberately ignores stop until finish() to
/// exercise the client's rejection of late replies, not a fake process kill.
private final class ScriptTransport: RecordMeasurementTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let reader: RecordMeasurementReader
    private let validated: Bool
    private let delayed: Bool
    private let overrides: [String: JSONValue]
    private let onRequest: @Sendable () -> Void
    private var captured: JSONValue?
    private var continuation: CheckedContinuation<Data, any Error>?
    private var stops = 0

    init(reader: RecordMeasurementReader, validated: Bool, delayed: Bool = false,
         overrides: [String: JSONValue] = [:], onRequest: @escaping @Sendable () -> Void = {}) {
        self.reader = reader; self.validated = validated; self.delayed = delayed
        self.overrides = overrides; self.onRequest = onRequest
    }

    var payload: JSONValue? { lock.withLock { captured } }
    var stopCount: Int { lock.withLock { stops } }
    func stop() { lock.withLock { stops += 1 } }

    func request(_ data: Data) async throws -> Data {
        let payload = try JSONDecoder().decode(JSONValue.self, from: data)
        lock.withLock { captured = payload }
        if !delayed { onRequest(); return try encoded(payload) }
        return try await withCheckedThrowingContinuation { value in
            lock.withLock { continuation = value }
            onRequest()
        }
    }

    func finish() {
        let pending = lock.withLock { () -> (CheckedContinuation<Data, any Error>?, JSONValue?) in
            defer { continuation = nil }
            return (continuation, captured)
        }
        guard let continuation = pending.0, let payload = pending.1 else { return }
        do { continuation.resume(returning: try encoded(payload)) }
        catch { continuation.resume(throwing: error) }
    }

    private func encoded(_ payload: JSONValue) throws -> Data {
        var value = Self.response(payload: payload, reader: reader, validated: validated).object!
        for (key, replacement) in overrides { value[key] = replacement }
        return try JSONEncoder().encode(JSONValue.object(value))
    }

    static func response(payload: JSONValue, reader: RecordMeasurementReader, validated: Bool) -> JSONValue {
        let excluded = Set(["schema", "model_path", "input", "system", "response_schema", "prompt",
                            "max_input_tokens", "max_new_tokens", "deadline_ms", "basis"])
        var response = (payload.object ?? [:]).filter { !excluded.contains($0.key) }
        response["schema"] = .string("archi-record-measurement-result/v1")
        response["status"] = .string(validated ? "validated" : "ok")
        response["backend_execution"] = .string("arm64-cpu")
        if !validated {
            response["raw_score"] = .number(reader.scoreOffset[0] + reader.scoreScale[0])
            response["standardized_score"] = .number(1)
            response["input_tokens"] = .number(40)
            response["output_tokens"] = .number(0)
            response["token_position"] = .number(39)
        }
        return .object(response)
    }
}
