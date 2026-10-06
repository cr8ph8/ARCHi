import Foundation
import simd

/// Reviewed surface strokes: fixed art, never knowledge edges or memory grants.
struct LiminalSurfaceLight: Sendable {
    static let style = "liminal-light-flow/v12"
    static let expectedSHA256 = "451164aa6eee794ed2bcf4729ab6ef3cb408889ed318fd7239cb76ce119e7c29"
    struct Knot: Codable, Sendable { let position: [Float]; let sourceID: UInt32 }
    struct Path: Codable, Sendable {
        let id: Int
        let width: Float
        let color: [Float]
        let intensity: Float
        let trueKnots: [Knot]
        let ballKnots: [Knot]
        let seedKnots: [Knot]
    }
    struct Manifest: Decodable {
        let schemaVersion: Int
        let revision: String
        let sourceManifestSHA256: String
        let finishManifestSHA256: String
        let lodSHA256: String
        let coordinateSpace: String
        let curves: LiminalPointAsset.FileReference
        let pathCount: Int
        let knotsPerPath: Int
    }
    struct Curves: Decodable { let schemaVersion: Int; let paths: [Path] }
    struct Segment: Sendable {
        let start: SIMD3<Float>, end: SIMD3<Float>, color: SIMD3<Float>
        let width: Float, intensity: Float, u0: Float, u1: Float, phase: Float
    }
    let digest: String
    let paths: [Path]

    static func load(root: URL, manifestSHA256: String, lodSHA256: String, lowIDs: [UInt32]) throws -> Self {
        let url = root.appendingPathComponent("manifest.json")
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard info.isSymbolicLink != true, let size = info.fileSize, size > 0, size < 65536,
              root.resolvingSymlinksInPath().standardizedFileURL == root.standardizedFileURL else { throw LiminalPointAsset.Failure.invalidFile }
        let data = try Data(contentsOf: url)
        guard LiminalPointAsset.digest(data) == expectedSHA256 else { throw LiminalPointAsset.Failure.wrongDigest }
        let m = try JSONDecoder().decode(Manifest.self, from: data)
        guard m.schemaVersion == 1, m.revision == "liminal-surface-light/v12", m.coordinateSpace == "houdini-sop-local",
              m.sourceManifestSHA256 == manifestSHA256, m.lodSHA256 == lodSHA256,
              m.finishManifestSHA256 == LiminalPointFinish.expectedSHA256,
              m.pathCount == 32, m.knotsPerPath == 12, m.curves.file == "curves.json", m.curves.bytes <= 1048576 else {
            throw LiminalPointAsset.Failure.invalidManifest
        }
        let bytes = try LiminalPointAsset.readFile(root: root, reference: m.curves, keepingPrefix: m.curves.bytes)
        let curves = try JSONDecoder().decode(Curves.self, from: bytes), ids = Set(lowIDs)
        guard curves.schemaVersion == 1, curves.paths.count == 32,
              curves.paths.map(\.id) == Array(0..<32), curves.paths.allSatisfy({ path in
                  path.width.isFinite && (0.001...0.02).contains(path.width)
                  && path.intensity.isFinite && (0...8).contains(path.intensity)
                  && path.color.count == 3 && path.color.allSatisfy { $0.isFinite && (0...1).contains($0) }
                  && [path.trueKnots,path.ballKnots,path.seedKnots].allSatisfy { knots in
                      knots.count == 12 && knots.allSatisfy { knot in
                          ids.contains(knot.sourceID) && knot.position.count == 3
                          && knot.position.allSatisfy { $0.isFinite && abs($0) <= 8 }
                      }
                  }
              }) else { throw LiminalPointAsset.Failure.invalidValues }
        return .init(digest: expectedSHA256, paths: curves.paths)
    }
    static func phase(unixTime: Double, moving: Bool) -> Float {
        guard moving, unixTime.isFinite else { return 0 }
        return Float((unixTime.truncatingRemainder(dividingBy: 4) + 4).truncatingRemainder(dividingBy: 4) * .pi / 2)
    }
    static func breath(phase: Float) -> Float { 1 + 0.006 * sin(phase) }
    func segments(frame: Int) -> [Segment] {
        let w = LiminalPointFinish.weights(frame: frame)
        var result: [Segment] = []; result.reserveCapacity(1408)
        for path in paths {
            let knots: [SIMD3<Float>] = (0..<12).map { i in
                SIMD3(path.trueKnots[i].position) * w.x + SIMD3(path.ballKnots[i].position) * w.y + SIMD3(path.seedKnots[i].position) * w.z
            }
            var points: [SIMD3<Float>] = [knots[0]]
            for i in 0..<11 {
                let p0 = knots[max(0,i-1)], p1 = knots[i], p2 = knots[i+1], p3 = knots[min(11,i+2)]
                for step in 1...4 {
                    let t = Float(step) / 4, t2 = t * t, t3 = t2 * t
                    points.append(0.5 * ((2 * p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t2 + (-p0+3*p1-3*p2+p3)*t3))
                }
            }
            let lengths = (0..<44).map { simd_distance(points[$0],points[$0+1]) }
            let total = max(0.00001, lengths.reduce(0,+))
            var u: Float = 0
            for i in 0..<44 {
                let next = u + lengths[i] / total
                result.append(.init(start: points[i], end: points[i+1], color: SIMD3(path.color), width: path.width,
                    intensity: path.intensity, u0: u, u1: next, phase: Float(path.id) * 2.39996323))
                u = next
            }
        }
        return result
    }
    static func packed(_ segments: [Segment]) -> Data {
        var result = Data(capacity: segments.count * 64)
        for s in segments {
            for v in [s.start.x,s.start.y,s.start.z,s.width,s.end.x,s.end.y,s.end.z,s.intensity,
                      s.color.x,s.color.y,s.color.z,s.u0,s.u1,s.phase,0,0] {
                var bits = v.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { result.append(contentsOf: $0) }
            }
        }
        return result
    }
}
