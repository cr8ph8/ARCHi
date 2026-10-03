import CryptoKit
import Darwin
import Foundation
import ImageIO
import simd

/// Source-bound presentation data. Loading requires an independently qualified
/// manifest digest supplied by the app's registry; a package cannot approve itself.
struct LiminalPointAsset: Sendable {
    static let sourceSHA256 = "2a56c4faf40a8920109df44e8bc2dad599b2b45b67a26bf2bc4fd0c93dd60cc1"
    static let sourceNode = "/obj/LIMINAL_POINTFORM/PARTICLE_CHOREOGRAPHY"
    static let maximumPackageBytes = 1_073_741_824
    static let maximumJSONBytes = 1_048_576

    enum Failure: Error, Equatable {
        case unqualifiedManifest, invalidManifest, invalidComparison, invalidPath, invalidFile
        case wrongLength, wrongDigest, invalidValues, invalidIDs, unavailableImage
    }
    enum Detail: Int, CaseIterable, Sendable { case low = 50_000, medium = 100_000, high = 200_000 }
    struct FileReference: Codable, Equatable, Sendable {
        let file: String
        let sha256: String
        let bytes: Int
    }
    struct FrameReference: Codable, Equatable, Sendable {
        let frame: Int
        let file: String
        let sha256: String
        let bytes: Int
        var reference: FileReference { .init(file: file, sha256: sha256, bytes: bytes) }
    }
    struct Manifest: Codable, Sendable {
        struct Source: Codable, Sendable {
            let hipSHA256: String
            let houdiniVersion: String
            let node: String
            let originalUnchanged: Bool
            let dependencies: [FileReference]
        }
        struct Encoding: Codable, Sendable {
            let byteOrder: String
            let float: String
            let masterStride: Int
            let cohortStride: Int
            let idStride: Int
            let sampleStride: Int
        }
        struct Coordinates: Codable, Sendable {
            let space: String
            let handedness: String
            let upAxis: String
            let units: String
            let nativeMapping: [Int]
            let unityMapping: [Int]
            let objectToWorldRowMajor: [Double]
        }
        struct Appearance: Codable, Sendable {
            let colorSpace: String
            let radiusAttribute: String
            let emissionAttribute: String
            let emissionRule: String
        }
        struct Timeline: Codable, Sendable {
            let fps: Int
            let firstFrame: Int
            let lastFrame: Int
            let interpolation: String
            let poseFrames: [String: Int]
        }
        struct Bounds: Codable, Sendable {
            let min: [Double]
            let max: [Double]
            let maximumRadius: Double
            let maximumEmission: Double
        }
        struct LOD: Codable, Sendable {
            let algorithm: String
            let counts: [Int]
            let ids: FileReference
        }
        struct EndpointImages: Codable, Sendable {
            struct Camera: Codable, Equatable, Sendable {
                let projection: String
                let center: [Double]
                let span: Double
                let direction: [Int]
                let up: [Int]
            }
            struct Image: Codable, Equatable, Sendable {
                let pose: String
                let frame: Int
                let file: String
                let sha256: String
                let bytes: Int
                var reference: FileReference { .init(file: file, sha256: sha256, bytes: bytes) }
            }
            let status: String
            let renderer: String?
            let camera: Camera?
            let images: [Image]
            let receipt: FileReference?
            let reason: String?
        }
        let schema: String
        let assetID: String
        let source: Source
        let pointCount: Int
        let runtimePointCount: Int
        let encoding: Encoding
        let coordinates: Coordinates
        let appearance: Appearance
        let timeline: Timeline
        let bounds: Bounds
        let master: FileReference
        let cohorts: FileReference
        let lod: LOD
        let frames: [FrameReference]
        let motionControls: [String: Double]
        let endpointImages: EndpointImages
        let comparison: FileReference
    }
    struct Sample: Equatable, Sendable {
        let position: SIMD3<Float>
        let color: SIMD3<Float>
        let radius: Float
        let emission: Float
    }
    struct Frame: Sendable {
        let frame: Int
        let pointCount: Int
        /// Packed P.xyz, Cd.rgb, radius, emission, exactly 32 bytes per point.
        let data: Data
        func sample(at index: Int) -> Sample? {
            guard (0..<pointCount).contains(index), index < data.count / 32 else { return nil }
            return data.withUnsafeBytes { LiminalPointAsset.sample($0, offset: index * 32) }
        }
    }
    struct FramePair: Sendable {
        let lower: Frame
        let upper: Frame
        let fraction: Float
        func sample(at index: Int) -> Sample? {
            guard fraction.isFinite, (0...1).contains(fraction),
                  let a = lower.sample(at: index), let b = upper.sample(at: index) else { return nil }
            if fraction == 0 { return a }
            if fraction == 1 { return b }
            return .init(position: a.position + (b.position - a.position) * fraction,
                         color: a.color + (b.color - a.color) * fraction,
                         radius: a.radius + (b.radius - a.radius) * fraction,
                         emission: a.emission + (b.emission - a.emission) * fraction)
        }
    }

    let packageURL: URL
    let manifestSHA256: String
    let manifest: Manifest
    let artIDs: [UInt32]
    let finish: LiminalPointFinish?
    let surfaceLight: LiminalSurfaceLight?
    var lowDetailIDs: [UInt32] { Array(artIDs.prefix(Detail.low.rawValue)) }
    var center: SIMD3<Float> {
        SIMD3(Float((manifest.bounds.min[0] + manifest.bounds.max[0]) / 2),
              Float((manifest.bounds.min[1] + manifest.bounds.max[1]) / 2),
              Float((manifest.bounds.min[2] + manifest.bounds.max[2]) / 2))
    }
    var span: Float {
        Float(((0..<3).map { manifest.bounds.max[$0] - manifest.bounds.min[$0] }.max()!
               + 2 * manifest.bounds.maximumRadius) * 1.12)
    }

    static func load(packageURL: URL, expectedManifestSHA256: String, finishURL: URL? = nil, lightURL: URL? = nil) throws -> Self {
        guard validDigest(expectedManifestSHA256) else { throw Failure.unqualifiedManifest }
        let bytes = try readSmall(root: packageURL, file: "manifest.json", maximum: maximumJSONBytes)
        let manifest = try decodeManifest(bytes, expectedSHA256: expectedManifestSHA256)
        let comparisonBytes = try readFile(root: packageURL, reference: manifest.comparison,
                                           keepingPrefix: manifest.comparison.bytes)
        try validateComparison(comparisonBytes)
        try validateEndpointReceipt(root: packageURL, manifest: manifest)
        let ids = try readFile(root: packageURL, reference: manifest.lod.ids, keepingPrefix: manifest.lod.ids.bytes)
        let artIDs = try decodeIDs(ids)
        // Master and cohort files must exist with their declared lengths. Full
        // master/rank/cross-renderer qualification is an installation gate; the
        // renderer does not rescan 800k endpoints on every app launch or frame.
        for reference in [manifest.master, manifest.cohorts] {
            let handle = try openFile(root: packageURL, file: reference.file, expectedBytes: reference.bytes)
            try handle.close()
        }
        return .init(packageURL: packageURL, manifestSHA256: expectedManifestSHA256,
                     manifest: manifest, artIDs: artIDs,
                     finish: try? LiminalPointFinish.load(root: finishURL ?? packageURL.appendingPathComponent("finish-v11"),
                         sourceManifestSHA256: expectedManifestSHA256, lodSHA256: manifest.lod.ids.sha256),
                     surfaceLight: try? LiminalSurfaceLight.load(root: lightURL ?? packageURL.appendingPathComponent("light-v12"),
                         manifestSHA256: expectedManifestSHA256, lodSHA256: manifest.lod.ids.sha256, lowIDs: Array(artIDs.prefix(50000))))
    }

    /// Call off the main thread. One chosen prefix is shared by both shader inputs. All bytes
    /// in each opened sample are hashed and validated before a prefix reaches GPU.
    func framePair(progress: Double, detail: Detail = .medium) throws -> FramePair {
        let index = try Self.sourceFrameIndex(progress: progress)
        let frame = try loadFrame(manifest.frames[index], detail: detail)
        return .init(lower: frame, upper: frame, fraction: 0)
    }

    static func sourceFrameIndex(progress: Double) throws -> Int {
        guard progress.isFinite else { throw Failure.invalidValues }
        // The pinned source uses $F rather than $FF: half frames round up.
        return Int(floor(min(1, max(0, progress)) * 119 + 0.5))
    }

    /// Explicit CPU reference image from actual endpoint samples, when supplied.
    /// This is not a snapshot of live Metal shading or a substitute for v008.
    func endpointPNGData(progress: Double) throws -> Data? {
        guard progress.isFinite else { throw Failure.invalidValues }
        guard manifest.endpointImages.status == "qualified" else { return nil }
        let frame = min(1, max(0, progress)) * 119 + 1
        guard let image = manifest.endpointImages.images.min(by: { abs(Double($0.frame) - frame) < abs(Double($1.frame) - frame) }) else {
            throw Failure.unavailableImage
        }
        let data = try Self.readFile(root: packageURL, reference: image.reference, keepingPrefix: image.bytes)
        try Self.validatePNG(data)
        return data
    }

    /// Optional installation audit of complete endpoint/cohort bytes. A passed
    /// binary audit still does not establish a Houdini run or visual acceptance.
    func validateMasterFiles() throws {
        _ = try Self.readFile(root: packageURL, reference: manifest.master, keepingPrefix: 0, stride: 100) { bytes, start in
            try bytes.withUnsafeBytes { buffer in
                for offset in stride(from: 0, to: buffer.count, by: 100) {
                    guard Self.uint32(buffer, offset: offset) == UInt32(start / 100 + offset / 100) else { throw Failure.invalidIDs }
                    for pose in 0..<3 { try Self.validateSample(Self.sample(buffer, offset: offset + 4 + pose * 32), bounds: manifest.bounds) }
                }
            }
        }
        _ = try Self.readFile(root: packageURL, reference: manifest.cohorts, keepingPrefix: 0, stride: 8) { bytes, _ in
            try bytes.withUnsafeBytes { buffer in
                for offset in stride(from: 0, to: buffer.count, by: 4) {
                    guard Self.uint32(buffer, offset: offset) < 64 else { throw Failure.invalidValues }
                }
            }
        }
    }

    private func loadFrame(_ frame: FrameReference, detail: Detail) throws -> Frame {
        let bytes = try Self.readFile(root: packageURL, reference: frame.reference,
                                     keepingPrefix: detail.rawValue * 32, stride: 32) { data, _ in
            try Self.validateFrameValues(data, bounds: manifest.bounds)
        }
        return .init(frame: frame.frame, pointCount: detail.rawValue, data: bytes)
    }

    static func decodeManifest(_ data: Data, expectedSHA256: String) throws -> Manifest {
        guard data.count <= maximumJSONBytes, validDigest(expectedSHA256), digest(data) == expectedSHA256 else {
            throw Failure.unqualifiedManifest
        }
        let object = try StrictJSON.object(data)
        try exactKeys(object, ["schema", "assetID", "source", "pointCount", "runtimePointCount", "encoding", "coordinates", "appearance", "timeline", "bounds", "master", "cohorts", "lod", "frames", "motionControls", "endpointImages", "comparison"])
        let expectedKeys: [String: Set<String>] = [
            "source": ["hipSHA256", "houdiniVersion", "node", "originalUnchanged", "dependencies"],
            "encoding": ["byteOrder", "float", "masterStride", "cohortStride", "idStride", "sampleStride"],
            "coordinates": ["space", "handedness", "upAxis", "units", "nativeMapping", "unityMapping", "objectToWorldRowMajor"],
            "appearance": ["colorSpace", "radiusAttribute", "emissionAttribute", "emissionRule"],
            "timeline": ["fps", "firstFrame", "lastFrame", "interpolation", "poseFrames"],
            "bounds": ["min", "max", "maximumRadius", "maximumEmission"],
            "lod": ["algorithm", "counts", "ids"]
        ]
        for (name, keys) in expectedKeys {
            guard let nested = object[name] as? [String: Any] else { throw Failure.invalidManifest }
            try exactKeys(nested, keys)
        }
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: data) } catch { throw Failure.invalidManifest }
        try validateManifest(manifest)
        // File references have one exact shape, including dependency provenance.
        for name in ["master", "cohorts", "comparison"] { try fileShape(object[name]) }
        try fileShape((object["lod"] as? [String: Any])?["ids"])
        for value in (object["source"] as? [String: Any])?["dependencies"] as? [Any] ?? [] { try fileShape(value) }
        for value in object["frames"] as? [[String: Any]] ?? [] { try exactKeys(value, ["frame", "file", "sha256", "bytes"]) }
        guard let endpoints = object["endpointImages"] as? [String: Any] else { throw Failure.invalidManifest }
        try exactKeys(endpoints, manifest.endpointImages.status == "unavailable"
            ? ["status", "camera", "images", "reason"] : ["status", "renderer", "camera", "images", "receipt"])
        if manifest.endpointImages.status == "qualified" {
            try fileShape(endpoints["receipt"])
            guard let camera = endpoints["camera"] as? [String: Any] else { throw Failure.invalidManifest }
            try exactKeys(camera, ["projection", "center", "span", "direction", "up"])
            for image in endpoints["images"] as? [[String: Any]] ?? [] { try exactKeys(image, ["pose", "frame", "file", "sha256", "bytes"]) }
        }
        return manifest
    }

    private static func validateManifest(_ m: Manifest) throws {
        guard m.schema == "archi-liminal-point-asset/v2", m.assetID == "liminal-v008",
              m.source.hipSHA256 == sourceSHA256, m.source.node == sourceNode, m.source.originalUnchanged,
              !m.source.houdiniVersion.isEmpty, m.source.houdiniVersion.utf8.count <= 80, m.source.dependencies.count <= 64,
              m.pointCount == 800_000, m.runtimePointCount == 200_000,
              m.encoding.byteOrder == "little", m.encoding.float == "ieee754-binary32",
              m.encoding.masterStride == 100, m.encoding.cohortStride == 8, m.encoding.idStride == 4, m.encoding.sampleStride == 32,
              m.coordinates.space == "houdini-sop-local", m.coordinates.handedness == "right", m.coordinates.upAxis == "+Y",
              m.coordinates.units == "authored-scene-units", m.coordinates.nativeMapping == [1, 1, 1], m.coordinates.unityMapping == [1, 1, -1],
              m.coordinates.objectToWorldRowMajor.count == 16, m.coordinates.objectToWorldRowMajor.allSatisfy(\.isFinite),
              m.appearance.colorSpace == "linear-rec709", m.appearance.radiusAttribute == "pscale",
              m.appearance.emissionAttribute == "heat", m.appearance.emissionRule == "Cd*heat",
              m.timeline.fps == 24, m.timeline.firstFrame == 1, m.timeline.lastFrame == 120, m.timeline.interpolation == "nearest-half-up",
              m.timeline.poseFrames == ["standing": 24, "curled": 66, "orb": 108],
              m.lod.algorithm == "sha256-rank-v1", m.lod.counts == [50_000, 100_000, 200_000],
              m.master.file == "endpoints.bin", m.master.bytes == 80_000_000,
              m.cohorts.file == "master-cohorts.bin", m.cohorts.bytes == 6_400_000,
              m.lod.ids.file == "lod-ids.bin", m.lod.ids.bytes == 800_000,
              m.comparison.file == "comparison.json", m.comparison.bytes <= maximumJSONBytes,
              m.frames.map(\.frame) == Array(1...120) else { throw Failure.invalidManifest }
        try validateBounds(m.bounds)
        var endpointReferences: [FileReference] = []
        if m.endpointImages.status == "unavailable" {
            guard m.endpointImages.camera == nil, m.endpointImages.images.isEmpty,
                  let reason = m.endpointImages.reason, !reason.isEmpty, reason.utf8.count <= 1024 else { throw Failure.invalidManifest }
        } else {
            guard m.endpointImages.status == "qualified", m.endpointImages.renderer == "archi-point-reference/v1",
                  m.endpointImages.camera == referenceCamera(m.bounds), m.endpointImages.reason == nil,
                  m.endpointImages.images.map(\.pose) == ["standing", "curled", "orb"],
                  m.endpointImages.images.map(\.frame) == [24, 66, 108],
                  let receipt = m.endpointImages.receipt, receipt.file == "endpoint-images.json", receipt.bytes <= maximumJSONBytes else { throw Failure.invalidManifest }
            for image in m.endpointImages.images {
                guard image.file == "images/\(image.pose).png", image.bytes <= 2_097_152 else { throw Failure.invalidManifest }
            }
            endpointReferences = m.endpointImages.images.map(\.reference) + [receipt]
        }
        let controls: [String: Double] = ["point_count": 800_000, "size_gain": 0.4, "glow_gain": 1, "curl_frequency": 2.1,
            "release_stagger": 0.045, "lid_opening": 1.15, "lid_definition": 0.8, "local_spin_turns": 1.15,
            "local_spin_radius": 0.065, "micro_curl_amount": 0.01, "lion_initial_spin": 35, "lion_spin_max_offset": 0.3]
        guard m.motionControls == controls else { throw Failure.invalidManifest }
        var files: [String: FileReference] = [:]
        for reference in [m.master, m.cohorts, m.lod.ids, m.comparison] + m.frames.map(\.reference) + endpointReferences {
            try validateReference(reference)
            if let prior = files[reference.file], prior != reference { throw Failure.invalidManifest }
            files[reference.file] = reference
        }
        for reference in m.source.dependencies { try validateReference(reference) }
        for frame in m.frames {
            guard frame.bytes == 6_400_000, frame.file.range(of: #"^frames/[0-9]{4}\.bin$"#, options: .regularExpression) != nil else {
                throw Failure.invalidManifest
            }
            guard let sourceFrame = Int(URL(fileURLWithPath: frame.file).deletingPathExtension().lastPathComponent),
                  (1...frame.frame).contains(sourceFrame) else { throw Failure.invalidManifest }
        }
        var total = maximumJSONBytes
        for file in files.values {
            let (next, overflow) = total.addingReportingOverflow(file.bytes)
            guard !overflow, next <= maximumPackageBytes else { throw Failure.invalidManifest }
            total = next
        }
    }

    static func validateBounds(_ bounds: Manifest.Bounds) throws {
        guard bounds.min.count == 3, bounds.max.count == 3,
              bounds.min.allSatisfy(\.isFinite), bounds.max.allSatisfy(\.isFinite),
              bounds.maximumRadius.isFinite, bounds.maximumRadius >= 0,
              bounds.maximumEmission.isFinite, bounds.maximumEmission >= 0,
              Float(bounds.maximumRadius).isFinite, Float(bounds.maximumEmission).isFinite else { throw Failure.invalidValues }
        for i in 0..<3 {
            guard bounds.min[i] <= bounds.max[i], Float(bounds.min[i]).isFinite, Float(bounds.max[i]).isFinite,
                  Float((bounds.min[i] + bounds.max[i]) / 2).isFinite else { throw Failure.invalidValues }
        }
        let span = ((0..<3).map { bounds.max[$0] - bounds.min[$0] }.max()! + 2 * bounds.maximumRadius) * 1.12
        guard span > 0, Float(span).isFinite else { throw Failure.invalidValues }
    }

    private struct Comparison: Decodable {
        struct Interpolation: Decodable {
            let evaluated: Bool
            let subframes: [Double]
            let comparedPointCount: Int
            let position: Double
            let color: Double
            let radius: Double
            let emission: Double
        }
        let schema: String
        let status: String
        let hipSHA256: String
        let node: String
        let sourceCooked: Bool
        let sampleFrames: [Int]
        let runtimePointCount: Int
        let endpointFrames: [Int]
        let checks: [String: Double]
        let interpolation: Interpolation
        let limits: [String: Double]
    }
    static func validateComparison(_ data: Data) throws {
        guard data.count <= maximumJSONBytes else { throw Failure.invalidComparison }
        let object = try StrictJSON.object(data)
        try exactKeys(object, ["schema", "status", "hipSHA256", "node", "sourceCooked", "sampleFrames", "runtimePointCount", "endpointFrames", "checks", "interpolation", "limits"])
        guard let interpolation = object["interpolation"] as? [String: Any] else { throw Failure.invalidComparison }
        try exactKeys(interpolation, ["evaluated", "subframes", "comparedPointCount", "position", "color", "radius", "emission"])
        let c: Comparison
        do { c = try JSONDecoder().decode(Comparison.self, from: data) } catch { throw Failure.invalidComparison }
        let diagnostics = ["identityError", "pathLimitError", "endpointPoseError", "poseAttributeError", "widthError"]
        guard c.schema == "archi-liminal-motion-comparison/v2", c.status == "passed", c.hipSHA256 == sourceSHA256,
              c.node == sourceNode, c.sourceCooked, c.sampleFrames == Array(1...120), c.runtimePointCount == 200_000,
              c.endpointFrames == [24, 66, 108], Set(c.checks.keys) == Set(diagnostics + ["idMismatchCount"]),
              c.checks["idMismatchCount"] == 0,
              diagnostics.allSatisfy({ (c.checks[$0] ?? .infinity).isFinite && (0...0.00001).contains(c.checks[$0] ?? .infinity) }),
              c.interpolation.evaluated, c.interpolation.comparedPointCount == 200_000,
              c.interpolation.subframes == [24, 30, 36, 42, 48, 54, 59, 72, 78, 84, 90, 96, 102, 107].flatMap({ base in [0.25, 0.5, 0.75].map { Double(base) + $0 } }),
              (0...0.01).contains(c.interpolation.position), (0...0.01).contains(c.interpolation.color),
              (0...0.00001).contains(c.interpolation.radius), (0...0.05).contains(c.interpolation.emission),
              c.limits == ["position": 0.01, "color": 0.01, "radius": 0.00001, "emission": 0.05] else { throw Failure.invalidComparison }
    }

    private static func referenceCamera(_ bounds: Manifest.Bounds) -> Manifest.EndpointImages.Camera {
        .init(projection: "orthographic", center: (0..<3).map { (bounds.min[$0] + bounds.max[$0]) / 2 },
              span: ((0..<3).map { bounds.max[$0] - bounds.min[$0] + 2 * bounds.maximumRadius }.max()!) * 1.12,
              direction: [0, 0, -1], up: [0, 1, 0])
    }
    private static func validateEndpointReceipt(root: URL, manifest: Manifest) throws {
        guard manifest.endpointImages.status == "qualified", let reference = manifest.endpointImages.receipt else { return }
        let data = try readFile(root: root, reference: reference, keepingPrefix: reference.bytes)
        let actual = try StrictJSON.object(data)
        let camera = try JSONSerialization.jsonObject(with: JSONEncoder().encode(referenceCamera(manifest.bounds)))
        let images: [[String: Any]] = manifest.endpointImages.images.map { image in
            ["pose": image.pose, "frame": image.frame, "file": image.file, "sha256": image.sha256,
             "bytes": image.bytes, "sampleSHA256": manifest.frames[image.frame - 1].sha256]
        }
        let expected: [String: Any] = ["schema": "archi-liminal-endpoint-images/v1", "hipSHA256": sourceSHA256,
            "node": sourceNode, "masterSHA256": manifest.master.sha256, "renderer": "archi-point-reference/v1",
            "camera": camera, "resolution": [512, 512], "transparent": true, "images": images]
        guard NSDictionary(dictionary: actual).isEqual(to: expected) else { throw Failure.invalidManifest }
    }
    static func validatePNG(_ data: Data) throws {
        guard data.count <= 2_097_152, data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == 512, image.height == 512,
              [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo) else { throw Failure.unavailableImage }
    }

    static func decodeIDs(_ data: Data) throws -> [UInt32] {
        guard data.count == 800_000 else { throw Failure.wrongLength }
        let ids = data.withUnsafeBytes { buffer in (0..<200_000).map { uint32(buffer, offset: $0 * 4) } }
        guard ids.allSatisfy({ $0 < 800_000 }), Set(ids).count == ids.count else { throw Failure.invalidIDs }
        return ids
    }

    static func validateFrameValues(_ data: Data, bounds: Manifest.Bounds) throws {
        guard data.count % 32 == 0 else { throw Failure.wrongLength }
        try data.withUnsafeBytes { buffer in
            for offset in stride(from: 0, to: buffer.count, by: 32) { try validateSample(sample(buffer, offset: offset), bounds: bounds) }
        }
    }
    private static func validateSample(_ point: Sample, bounds: Manifest.Bounds) throws {
        guard (0..<3).allSatisfy({ point.position[$0].isFinite && point.color[$0].isFinite }),
              point.radius.isFinite, point.radius >= 0, Double(point.radius) <= bounds.maximumRadius + 0.00001,
              point.emission.isFinite, point.emission >= 0, Double(point.emission) <= bounds.maximumEmission + 0.00001 else { throw Failure.invalidValues }
        for axis in 0..<3 {
            let tolerance = max(0.00001, max(abs(bounds.min[axis]), abs(bounds.max[axis])) * 0.000001)
            guard Double(point.position[axis]) >= bounds.min[axis] - tolerance,
                  Double(point.position[axis]) <= bounds.max[axis] + tolerance else { throw Failure.invalidValues }
        }
    }
    private static func sample(_ bytes: UnsafeRawBufferPointer, offset: Int) -> Sample {
        func value(_ index: Int) -> Float { Float(bitPattern: uint32(bytes, offset: offset + index * 4)) }
        return .init(position: SIMD3(value(0), value(1), value(2)), color: SIMD3(value(3), value(4), value(5)),
                     radius: value(6), emission: value(7))
    }
    private static func uint32(_ bytes: UnsafeRawBufferPointer, offset: Int) -> UInt32 {
        UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func validateRelativePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.utf8.count <= 256, !path.contains("\\"), parts.count <= 8,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Failure.invalidPath }
    }
    private static func validateReference(_ value: FileReference) throws {
        try validateRelativePath(value.file)
        guard validDigest(value.sha256), value.bytes > 0, value.bytes <= maximumPackageBytes else { throw Failure.invalidManifest }
    }
    private static func fileShape(_ value: Any?) throws {
        guard let object = value as? [String: Any] else { throw Failure.invalidManifest }
        try exactKeys(object, ["file", "sha256", "bytes"])
    }
    private static func exactKeys(_ object: [String: Any], _ expected: Set<String>) throws {
        guard Set(object.keys) == expected else { throw Failure.invalidManifest }
    }

    private static func openFile(root: URL, file: String, expectedBytes: Int? = nil) throws -> FileHandle {
        guard root.isFileURL else { throw Failure.invalidPath }
        try validateRelativePath(file)
        var directory = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw Failure.invalidFile }
        defer { Darwin.close(directory) }
        let parts = file.split(separator: "/").map(String.init)
        for component in parts.dropLast() {
            let next = Darwin.openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw Failure.invalidFile }
            Darwin.close(directory); directory = next
        }
        let descriptor = Darwin.openat(directory, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.invalidFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_size > 0, info.st_size <= maximumPackageBytes else { try? handle.close(); throw Failure.invalidFile }
        if let expectedBytes, info.st_size != Int64(expectedBytes) {
            try? handle.close()
            throw Failure.wrongLength
        }
        return handle
    }
    private static func readSmall(root: URL, file: String, maximum: Int) throws -> Data {
        let handle = try openFile(root: root, file: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximum else { throw Failure.wrongLength }
        return data
    }
    static func readFile(root: URL, reference: FileReference, keepingPrefix: Int, stride: Int = 1,
                         validate: ((Data, Int) throws -> Void)? = nil) throws -> Data {
        try validateReference(reference)
        guard stride > 0, reference.bytes % stride == 0, keepingPrefix >= 0, keepingPrefix <= reference.bytes else { throw Failure.wrongLength }
        let handle = try openFile(root: root, file: reference.file, expectedBytes: reference.bytes)
        defer { try? handle.close() }
        var hash = SHA256(), result = Data(), offset = 0
        result.reserveCapacity(keepingPrefix)
        let chunkSize = max(stride, (65_536 / stride) * stride)
        while offset < reference.bytes {
            try Task.checkCancellation()
            let count = min(chunkSize, reference.bytes - offset)
            guard let chunk = try handle.read(upToCount: count), chunk.count == count else { throw Failure.wrongLength }
            hash.update(data: chunk)
            try validate?(chunk, offset)
            if offset < keepingPrefix { result.append(chunk.prefix(min(count, keepingPrefix - offset))) }
            offset += count
        }
        guard (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw Failure.wrongLength }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == reference.sha256 else { throw Failure.wrongDigest }
        return result
    }

    /// Foundation's JSON decoder accepts duplicate keys. Reject them before
    /// decoding, including equivalent escaped spellings such as a and \u0061.
    private struct StrictJSON {
        let bytes: [UInt8]
        var offset = 0
        static func object(_ data: Data) throws -> [String: Any] {
            var parser = Self(bytes: Array(data))
            try parser.value(depth: 0); parser.space()
            guard parser.offset == parser.bytes.count,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidManifest }
            return object
        }
        mutating func space() { while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 } }
        mutating func take(_ byte: UInt8) throws {
            space(); guard offset < bytes.count, bytes[offset] == byte else { throw Failure.invalidManifest }; offset += 1
        }
        mutating func string() throws -> String {
            space(); let start = offset
            try take(34)
            var escaped = false
            while offset < bytes.count {
                let byte = bytes[offset]; offset += 1
                if escaped { escaped = false; continue }
                if byte == 92 { escaped = true; continue }
                if byte == 34 {
                    guard let value = try JSONSerialization.jsonObject(with: Data(bytes[start..<offset]), options: .fragmentsAllowed) as? String else { throw Failure.invalidManifest }
                    return value
                }
            }
            throw Failure.invalidManifest
        }
        mutating func value(depth: Int) throws {
            space(); guard depth <= 32, offset < bytes.count else { throw Failure.invalidManifest }
            switch bytes[offset] {
            case 123:
                offset += 1; space(); var keys = Set<String>()
                if offset < bytes.count, bytes[offset] == 125 { offset += 1; return }
                while true {
                    let key = try string(); guard keys.insert(key).inserted else { throw Failure.invalidManifest }
                    try take(58); try value(depth: depth + 1); space()
                    if offset < bytes.count, bytes[offset] == 125 { offset += 1; return }
                    try take(44)
                }
            case 91:
                offset += 1; space()
                if offset < bytes.count, bytes[offset] == 93 { offset += 1; return }
                while true {
                    try value(depth: depth + 1); space()
                    if offset < bytes.count, bytes[offset] == 93 { offset += 1; return }
                    try take(44)
                }
            case 34: _ = try string()
            default:
                let start = offset
                while offset < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[offset]) { offset += 1 }
                guard offset > start else { throw Failure.invalidManifest }
            }
        }
    }
}
