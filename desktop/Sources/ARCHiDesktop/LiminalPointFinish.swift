import Foundation
import simd

/// A pinned, display-only translation of the preserved Blender v11 study.
/// Source samples, source IDs, memory and evolution authority remain unchanged.
struct LiminalPointFinish: Sendable {
    static let revision = "liminal-internal-gold/v11"
    static let expectedSHA256 = "392f3f6aae7a6f550b417cf75a92e25071be37851489ccf19bfbebb4d20becdf"
    struct Manifest: Decodable {
        let schemaVersion: Int
        let revision: String
        let sourceManifestSHA256: String
        let lodSHA256: String
        let pointCount: Int
        let stride: Int
        let annotations: LiminalPointAsset.FileReference
        let blenderSHA256: String
    }
    let digest: String
    /// float32 direction.xyz, uint32 flags, in authenticated runtime LOD order.
    let annotations: Data

    static func load(root: URL, sourceManifestSHA256: String, lodSHA256: String) throws -> Self {
        let manifestURL = root.appendingPathComponent("manifest.json")
        let values = try manifestURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, let size = values.fileSize, size > 0, size <= 65536,
              root.resolvingSymlinksInPath().standardizedFileURL == root.standardizedFileURL else {
            throw LiminalPointAsset.Failure.invalidFile
        }
        let bytes = try Data(contentsOf: manifestURL)
        guard LiminalPointAsset.digest(bytes) == expectedSHA256 else { throw LiminalPointAsset.Failure.wrongDigest }
        let m = try JSONDecoder().decode(Manifest.self, from: bytes)
        guard m.schemaVersion == 1, m.revision == revision,
              m.sourceManifestSHA256 == sourceManifestSHA256, m.lodSHA256 == lodSHA256,
              m.pointCount == 200000, m.stride == 16, m.annotations.file == "annotations.bin",
              m.annotations.bytes == 3200000,
              m.blenderSHA256 == "22b5fad91cc15cd1fd84c1091ad6a2474bfe4dd483e4fd488910712fa17cf147" else {
            throw LiminalPointAsset.Failure.invalidManifest
        }
        let data = try LiminalPointAsset.readFile(root: root, reference: m.annotations, keepingPrefix: m.annotations.bytes)
        try data.withUnsafeBytes { raw in
            for i in 0..<m.pointCount {
                let flag = raw.loadUnaligned(fromByteOffset: i * 16 + 12, as: UInt32.self).littleEndian
                let direction = SIMD3((0..<3).map { Float(bitPattern: raw.loadUnaligned(fromByteOffset: i * 16 + $0 * 4, as: UInt32.self).littleEndian) })
                guard flag < 16, direction.x.isFinite, direction.y.isFinite, direction.z.isFinite,
                      abs(simd_length(direction) - 1) < 0.0001,
                      flag & 1 == 0 || flag == 1 else {
                    throw LiminalPointAsset.Failure.invalidValues
                }
            }
        }
        return .init(digest: expectedSHA256, annotations: data)
    }

    /// The source holds each pose. Only the finish interpolates between those holds.
    static func weights(frame: Int) -> SIMD3<Float> {
        func ease(_ t: Float) -> Float { let c = min(1, max(0, t)); return c * c * (3 - 2 * c) }
        if frame <= 60 { let t = ease(Float(frame - 24) / 36); return SIMD3(1 - t, t, 0) }
        let t = ease(Float(frame - 72) / 36); return SIMD3(0, 1 - t, t)
    }
    static func seed(frame: Int) -> SIMD4<Float> {
        let w = weights(frame: frame)
        return SIMD4<Float>(0, 1.045, 1.65, 0.072) * w.x
            + SIMD4<Float>(0.02, 0.915, 0.20, 0.075) * w.y
            + SIMD4<Float>(0, 1.15, 0, 0.092) * w.z
    }
    func display(_ source: LiminalPointAsset.Sample, rank: Int, frame: Int) -> LiminalPointAsset.Sample {
        guard rank >= 0, rank < annotations.count / 16 else { return source }
        return annotations.withUnsafeBytes { raw in
            let flags = raw.loadUnaligned(fromByteOffset: rank * 16 + 12, as: UInt32.self).littleEndian
            var p = source.position, cd = source.color, r = source.radius, heat = source.emission
            if flags & 1 != 0 {
                let d = SIMD3((0..<3).map { Float(bitPattern: raw.loadUnaligned(fromByteOffset: rank * 16 + $0 * 4, as: UInt32.self).littleEndian) })
                let core = Self.seed(frame: frame)
                p = SIMD3(core.x, core.y, core.z) + d * core.w
                cd = SIMD3(1, 0.40, 0.028); heat = 1.8; r = min(r, 0.0007)
            } else {
                let w = Self.weights(frame: frame)
                let residual = (flags & 2 != 0 ? w.x : 0) + (flags & 4 != 0 ? w.y : 0)
                cd += (SIMD3<Float>(0.16, 0.004, 0.0015) - cd) * residual
                heat += (0.4 - heat) * residual
                let tail = flags & 8 != 0 ? w.x : 0
                cd += (SIMD3<Float>(0.55, 0.055, 0.008) - cd) * tail
                heat += (0.5 - heat) * tail
            }
            return .init(position: p, color: cd, radius: r * 2, emission: heat * 0.5)
        }
    }
}
