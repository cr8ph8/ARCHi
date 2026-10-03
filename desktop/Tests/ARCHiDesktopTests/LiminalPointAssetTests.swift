import Foundation
import XCTest
@testable import ARCHiDesktop

/// Small synthetic contract fixtures only. None is a qualified Houdini package.
final class LiminalPointAssetTests: XCTestCase {
    func testSeedRestorationKeepsBodyFramingAndBoundedReversibleTransition() {
        let center = SIMD3<Float>(0.1, 1.24, 0), span: Float = 5.51
        for frame in [1, 24, 66, 90] {
            let view = LiminalSeedStyle.framing(center: center, span: span, frame: frame)
            XCTAssertEqual(view.center, center)
            XCTAssertEqual(view.span, span)
            XCTAssertEqual(LiminalSeedStyle.weight(frame: frame), 0)
        }
        let forward = (90...108).map { LiminalSeedStyle.weight(frame: $0) }
        XCTAssertEqual(forward, forward.sorted())
        XCTAssertEqual(forward, (90...108).reversed().map { LiminalSeedStyle.weight(frame: $0) }.reversed())
        let seed = LiminalSeedStyle.framing(center: center, span: span, frame: 108)
        XCTAssertEqual(seed.center.y, 1.15, accuracy: 0.00001)
        XCTAssertEqual(seed.span, 1.90, accuracy: 0.00001)
        XCTAssertEqual(LiminalSeedStyle.weight(frame: 120), 1)
        XCTAssertEqual(LiminalSeedStyle.color(.original), .garnet)
        XCTAssertEqual(LiminalSeedStyle.color(.violet), .violet)
    }
    func testSourceClockRoundsHalfUpAndRejectsLegacyLinearManifest() throws {
        for (frame, expected) in [(36.25, 35), (36.49, 35), (36.5, 36), (36.75, 36)] {
            XCTAssertEqual(try LiminalPointAsset.sourceFrameIndex(progress: (frame - 1) / 119), expected)
        }
        XCTAssertEqual(try LiminalPointAsset.sourceFrameIndex(progress: -1), 0)
        XCTAssertEqual(try LiminalPointAsset.sourceFrameIndex(progress: 2), 119)
        XCTAssertThrowsError(try LiminalPointAsset.sourceFrameIndex(progress: .nan))
        var legacy = manifest(); legacy["schema"] = "archi-liminal-point-asset/v1"
        try assertRejected(legacy)
        var linear = manifest(), timeline = linear["timeline"] as! [String: Any]
        timeline["interpolation"] = "linear"; linear["timeline"] = timeline
        try assertRejected(linear)
    }
    private let digest = String(repeating: "a", count: 64)
    private var bounds: LiminalPointAsset.Manifest.Bounds {
        .init(min: [-3, -3, -3], max: [3, 3, 3], maximumRadius: 0.01, maximumEmission: 8)
    }

    func testPinnedManifestAcceptsExactShapeAndHoldsAll120FrameReferences() throws {
        let data = try json(manifest())
        let decoded = try LiminalPointAsset.decodeManifest(data, expectedSHA256: LiminalPointAsset.digest(data))
        XCTAssertEqual(decoded.source.hipSHA256, LiminalPointAsset.sourceSHA256)
        XCTAssertEqual(decoded.pointCount, 800_000)
        XCTAssertEqual(decoded.frames.count, 120)
        XCTAssertEqual(decoded.frames[107].frame, 108)
        XCTAssertEqual(decoded.lod.counts, [50_000, 100_000, 200_000])
        XCTAssertEqual(decoded.endpointImages.status, "unavailable")
        XCTAssertThrowsError(try LiminalPointAsset.decodeManifest(data, expectedSHA256: String(repeating: "0", count: 64)))
        XCTAssertThrowsError(try LiminalPointAsset.load(packageURL: URL(fileURLWithPath: "/not-a-qualified-package"), expectedManifestSHA256: ""))
    }

    func testDuplicateEscapedKeysUnknownFieldsAndChangedSourceFailClosed() throws {
        let encoded = String(decoding: try json(manifest()), as: UTF8.self)
        let duplicate = Data(("{\"\\u0073chema\":\"archi-liminal-point-asset/v2\"," + encoded.dropFirst()).utf8)
        XCTAssertThrowsError(try LiminalPointAsset.decodeManifest(duplicate, expectedSHA256: LiminalPointAsset.digest(duplicate)))
        var unknown = manifest(); unknown["acceptAnyway"] = true
        try assertRejected(unknown)
        var old = manifest(), source = old["source"] as! [String: Any]
        source["hipSHA256"] = String(repeating: "2", count: 64); old["source"] = source
        try assertRejected(old)
        var altered = manifest(), controls = altered["motionControls"] as! [String: Double]
        controls["local_spin_turns"] = 1.2; altered["motionControls"] = controls
        try assertRejected(altered)
    }

    func testIncompleteTimelineCountsEncodingAndPathTraversalAreRejected() throws {
        var incomplete = manifest()
        incomplete["frames"] = Array((incomplete["frames"] as! [[String: Any]]).dropLast())
        try assertRejected(incomplete)
        var wrongCount = manifest(); wrongCount["pointCount"] = 799_999
        try assertRejected(wrongCount)
        var wrongEncoding = manifest(), encoding = wrongEncoding["encoding"] as! [String: Any]
        encoding["byteOrder"] = "big"; wrongEncoding["encoding"] = encoding
        try assertRejected(wrongEncoding)
        var traversal = manifest(), frames = traversal["frames"] as! [[String: Any]]
        frames[0]["file"] = "frames/../../outside.bin"; traversal["frames"] = frames
        try assertRejected(traversal)
        var forwardReference = manifest(); frames = forwardReference["frames"] as! [[String: Any]]
        frames[0]["file"] = "frames/0002.bin"; forwardReference["frames"] = frames
        try assertRejected(forwardReference)
        for path in ["/tmp/a", "../a", "frames/../a", "frames//a", "frames/./a", "frames\\a", "frames/a\u{0}", ".hidden/a"] {
            XCTAssertThrowsError(try LiminalPointAsset.validateRelativePath(path), path)
        }
        XCTAssertNoThrow(try LiminalPointAsset.validateRelativePath("frames/0001.bin"))
    }

    func testBinarySamplesInterpolateAllAuthoredFieldsWithoutProceduralMotion() throws {
        let a = packed([0, 1, -1, 0.2, 0.4, 0.6, 0.002, 2])
        let b = packed([2, -1, 1, 0.6, 0.8, 1, 0.006, 6])
        try LiminalPointAsset.validateFrameValues(a, bounds: bounds)
        try LiminalPointAsset.validateFrameValues(b, bounds: bounds)
        let first = LiminalPointAsset.Frame(frame: 24, pointCount: 1, data: a)
        let last = LiminalPointAsset.Frame(frame: 25, pointCount: 1, data: b)
        let pair = LiminalPointAsset.FramePair(lower: first, upper: last, fraction: 0.25)
        let point = try XCTUnwrap(pair.sample(at: 0))
        XCTAssertEqual(point.position.x, 0.5)
        XCTAssertEqual(point.position.y, 0.5)
        XCTAssertEqual(point.position.z, -0.5)
        XCTAssertEqual(point.color.x, 0.3, accuracy: 0.000001)
        XCTAssertEqual(point.radius, 0.003, accuracy: 0.000001)
        XCTAssertEqual(point.emission, 3)
        XCTAssertEqual(LiminalPointAsset.FramePair(lower: first, upper: last, fraction: 0).sample(at: 0), first.sample(at: 0))
        XCTAssertEqual(LiminalPointAsset.FramePair(lower: first, upper: last, fraction: 1).sample(at: 0), last.sample(at: 0))
        XCTAssertNil(pair.sample(at: 1))
    }

    func testNonfiniteNegativeAndOutOfBoundsBinaryValuesAreRejected() throws {
        let valid: [Float] = [0, 1, -1, 0.2, 0.4, 0.6, 0.002, 2]
        for (index, value) in [(0, Float.nan), (4, Float.infinity), (0, Float(4)), (6, Float(-0.001)),
                               (6, Float(0.1)), (7, Float(-1)), (7, Float(9))] {
            var changed = valid; changed[index] = value
            XCTAssertThrowsError(try LiminalPointAsset.validateFrameValues(packed(changed), bounds: bounds))
        }
        XCTAssertThrowsError(try LiminalPointAsset.validateFrameValues(Data([0]), bounds: bounds))
        XCTAssertThrowsError(try LiminalPointAsset.validateBounds(.init(min: [.nan, 0, 0], max: [1, 1, 1], maximumRadius: 1, maximumEmission: 1)))
        XCTAssertThrowsError(try LiminalPointAsset.validateBounds(.init(min: [0, 0, 0], max: [0, 0, 0], maximumRadius: 0, maximumEmission: 1)))
    }

    func testStableIDsAreBoundedUniqueAndHaveNestedRuntimePrefixes() throws {
        var data = Data(capacity: 800_000)
        for id in UInt32(0)..<UInt32(200_000) { append(id, to: &data) }
        let ids = try LiminalPointAsset.decodeIDs(data)
        XCTAssertEqual(ids.count, 200_000)
        XCTAssertEqual(Array(ids.prefix(50_000)), Array(ids.prefix(100_000).prefix(50_000)))
        var duplicate = data
        duplicate.replaceSubrange(4..<8, with: data.prefix(4))
        XCTAssertThrowsError(try LiminalPointAsset.decodeIDs(duplicate))
        var outOfRange = data, invalid = Data(); append(800_000, to: &invalid)
        outOfRange.replaceSubrange(0..<4, with: invalid)
        XCTAssertThrowsError(try LiminalPointAsset.decodeIDs(outOfRange))
        XCTAssertThrowsError(try LiminalPointAsset.decodeIDs(Data(data.dropLast())))
    }

    func testFileReadAuthenticatesWholeFileWhileKeepingOnlyRequestedPrefix() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data((0..<128).map(UInt8.init))
        try bytes.write(to: directory.appendingPathComponent("sample.bin"))
        let reference = LiminalPointAsset.FileReference(file: "sample.bin", sha256: LiminalPointAsset.digest(bytes), bytes: bytes.count)
        XCTAssertEqual(try LiminalPointAsset.readFile(root: directory, reference: reference, keepingPrefix: 16), bytes.prefix(16))
        var tampered = bytes; tampered[127] = 0
        try tampered.write(to: directory.appendingPathComponent("sample.bin"))
        XCTAssertThrowsError(try LiminalPointAsset.readFile(root: directory, reference: reference, keepingPrefix: 16),
                             "Changes beyond the retained prefix still invalidate the whole file digest.")
        try bytes.dropLast().write(to: directory.appendingPathComponent("sample.bin"))
        XCTAssertThrowsError(try LiminalPointAsset.readFile(root: directory, reference: reference, keepingPrefix: 16))
    }

    func testSymlinkFilesAndSymlinkDirectoryComponentsAreRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: directory.appendingPathComponent("real.bin"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link.bin"), withDestinationURL: directory.appendingPathComponent("real.bin"))
        let reference = LiminalPointAsset.FileReference(file: "link.bin", sha256: LiminalPointAsset.digest(bytes), bytes: 4)
        XCTAssertThrowsError(try LiminalPointAsset.readFile(root: directory, reference: reference, keepingPrefix: 4))
        let realDirectory = directory.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)
        try bytes.write(to: realDirectory.appendingPathComponent("sample.bin"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("frames"), withDestinationURL: realDirectory)
        let throughLink = LiminalPointAsset.FileReference(file: "frames/sample.bin", sha256: reference.sha256, bytes: 4)
        XCTAssertThrowsError(try LiminalPointAsset.readFile(root: directory, reference: throughLink, keepingPrefix: 4))
    }

    func testComparisonRequiresActualCookClaimEveryFrameAndFixedLimits() throws {
        let good = comparison()
        XCTAssertNoThrow(try LiminalPointAsset.validateComparison(json(good)))
        var uncooked = good; uncooked["sourceCooked"] = false
        XCTAssertThrowsError(try LiminalPointAsset.validateComparison(json(uncooked)))
        var incomplete = good; incomplete["sampleFrames"] = Array(1...119)
        XCTAssertThrowsError(try LiminalPointAsset.validateComparison(json(incomplete)))
        var relaxed = good; relaxed["limits"] = ["position": 1, "color": 0.01, "radius": 0.00001, "emission": 0.05]
        XCTAssertThrowsError(try LiminalPointAsset.validateComparison(json(relaxed)))
        var failed = good, interpolation = failed["interpolation"] as! [String: Any]
        interpolation["position"] = 0.011; failed["interpolation"] = interpolation
        XCTAssertThrowsError(try LiminalPointAsset.validateComparison(json(failed)))
    }

    func testEndpointAvailabilityCannotBeInventedOrUseWrongCamera() throws {
        var missing = manifest()
        missing["endpointImages"] = ["status": "qualified", "camera": NSNull(), "images": [], "reason": "pretend"]
        try assertRejected(missing)
        var qualified = manifest()
        qualified["endpointImages"] = ["status": "qualified", "renderer": "archi-point-reference/v1",
            "camera": ["projection": "orthographic", "center": [0, 0, 0], "span": 6.02 * 1.12,
                       "direction": [0, 0, -1], "up": [0, 1, 0]],
            "images": zip(["standing", "curled", "orb"], [24, 66, 108]).map { pose, frame in
                ["pose": pose, "frame": frame, "file": "images/\(pose).png", "sha256": digest, "bytes": 100] as [String: Any]
            }, "receipt": reference("endpoint-images.json", bytes: 100)] as [String: Any]
        let data = try json(qualified)
        XCTAssertNoThrow(try LiminalPointAsset.decodeManifest(data, expectedSHA256: LiminalPointAsset.digest(data)),
                         "Structural acceptance still requires the actual receipt, images and independent manifest qualification at load.")
        var endpoints = qualified["endpointImages"] as! [String: Any]
        var camera = endpoints["camera"] as! [String: Any]; camera["span"] = 4
        endpoints["camera"] = camera; qualified["endpointImages"] = endpoints
        try assertRejected(qualified)
        XCTAssertThrowsError(try LiminalPointAsset.validatePNG(Data("not a PNG".utf8)))
    }

    private func manifest() -> [String: Any] {
        ["schema": "archi-liminal-point-asset/v2", "assetID": "liminal-v008",
         "source": ["hipSHA256": LiminalPointAsset.sourceSHA256, "houdiniVersion": "22.0.429",
                    "node": LiminalPointAsset.sourceNode, "originalUnchanged": true, "dependencies": []] as [String: Any],
         "pointCount": 800_000, "runtimePointCount": 200_000,
         "encoding": ["byteOrder": "little", "float": "ieee754-binary32", "masterStride": 100, "cohortStride": 8,
                      "idStride": 4, "sampleStride": 32] as [String: Any],
         "coordinates": ["space": "houdini-sop-local", "handedness": "right", "upAxis": "+Y", "units": "authored-scene-units",
                         "nativeMapping": [1, 1, 1], "unityMapping": [1, 1, -1],
                         "objectToWorldRowMajor": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]] as [String: Any],
         "appearance": ["colorSpace": "linear-rec709", "radiusAttribute": "pscale", "emissionAttribute": "heat", "emissionRule": "Cd*heat"],
         "timeline": ["fps": 24, "firstFrame": 1, "lastFrame": 120, "interpolation": "nearest-half-up",
                      "poseFrames": ["standing": 24, "curled": 66, "orb": 108]] as [String: Any],
         "bounds": ["min": [-3, -3, -3], "max": [3, 3, 3], "maximumRadius": 0.01, "maximumEmission": 8] as [String: Any],
         "master": reference("endpoints.bin", bytes: 80_000_000), "cohorts": reference("master-cohorts.bin", bytes: 6_400_000),
         "lod": ["algorithm": "sha256-rank-v1", "counts": [50_000, 100_000, 200_000], "ids": reference("lod-ids.bin", bytes: 800_000)] as [String: Any],
         "frames": (1...120).map { frame in ["frame": frame, "file": "frames/0001.bin", "sha256": digest, "bytes": 6_400_000] as [String: Any] },
         "motionControls": ["point_count": 800_000, "size_gain": 0.4, "glow_gain": 1, "curl_frequency": 2.1,
            "release_stagger": 0.045, "lid_opening": 1.15, "lid_definition": 0.8, "local_spin_turns": 1.15,
            "local_spin_radius": 0.065, "micro_curl_amount": 0.01, "lion_initial_spin": 35, "lion_spin_max_offset": 0.3],
         "endpointImages": ["status": "unavailable", "camera": NSNull(), "images": [], "reason": "No qualified image in this fixture."] as [String: Any],
         "comparison": reference("comparison.json", bytes: 100)]
    }
    private func comparison() -> [String: Any] {
        ["schema": "archi-liminal-motion-comparison/v2", "status": "passed", "hipSHA256": LiminalPointAsset.sourceSHA256,
         "node": LiminalPointAsset.sourceNode, "sourceCooked": true, "sampleFrames": Array(1...120), "runtimePointCount": 200_000,
         "endpointFrames": [24, 66, 108], "checks": ["identityError": 0, "pathLimitError": 0, "endpointPoseError": 0,
            "poseAttributeError": 0, "widthError": 0, "idMismatchCount": 0],
         "interpolation": ["evaluated": true, "subframes": [24, 30, 36, 42, 48, 54, 59, 72, 78, 84, 90, 96, 102, 107].flatMap { base in [0.25, 0.5, 0.75].map { Double(base) + $0 } },
            "comparedPointCount": 200_000, "position": 0, "color": 0, "radius": 0, "emission": 0] as [String: Any],
         "limits": ["position": 0.01, "color": 0.01, "radius": 0.00001, "emission": 0.05]]
    }
    private func reference(_ file: String, bytes: Int) -> [String: Any] { ["file": file, "sha256": digest, "bytes": bytes] }
    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: .sortedKeys) }
    private func assertRejected(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try json(object)
        XCTAssertThrowsError(try LiminalPointAsset.decodeManifest(data, expectedSHA256: LiminalPointAsset.digest(data)), file: file, line: line)
    }
    private func append(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    private func packed(_ values: [Float]) -> Data {
        var data = Data()
        for value in values { append(value.bitPattern, to: &data) }
        return data
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("liminal-asset-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
