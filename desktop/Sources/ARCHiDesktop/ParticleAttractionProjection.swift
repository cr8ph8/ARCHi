import Foundation
import ARCHiSpatial

/// A presentation transform for the same record IDs, not another simulation.
/// AppKit desktop coordinates are converted once at the overlay boundary.
enum ParticleAttractionProjection {
    typealias Vector = KnowledgeParticleField.Vector

    /// One coordinate scale for the entire producer lifetime. Desktop callers
    /// use the virtual desktop extent so moving a target cannot rescale motion.
    static func scale(for canvas: CGSize) -> Double {
        guard canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0 else { return 0 }
        let value = hypot(Double(canvas.width), Double(canvas.height)) / 0.6
        return value.isFinite && value > 0 ? value : 0
    }

    static func localFrame(_ screenFrame: CGRect, in overlay: CGRect) -> CGRect? {
        guard valid(screenFrame), valid(overlay), overlay.contains(screenFrame) else { return nil }
        return CGRect(x: screenFrame.minX - overlay.minX, y: overlay.maxY - screenFrame.maxY,
                      width: screenFrame.width, height: screenFrame.height)
    }

    /// Marked regions use top-left normalized coordinates. Window Server
    /// metadata reaches this boundary in AppKit bottom-left desktop points.
    static func desktopAreaFrame(_ region: ImageRegionRect?, in window: CGRect) -> CGRect? {
        guard valid(window) else { return nil }
        guard let region else { return window }
        guard region.isValid else { return nil }
        return CGRect(x: window.minX + region.x * window.width,
            y: window.maxY - (region.y + region.height) * window.height,
            width: region.width * window.width, height: region.height * window.height)
    }

    static func imageFrame(pixels: CGSize, canvas: CGSize) -> CGRect {
        guard pixels.width > 0, pixels.height > 0, canvas.width > 0, canvas.height > 0,
              [pixels.width, pixels.height, canvas.width, canvas.height].allSatisfy(\.isFinite) else { return .zero }
        let scale = min(canvas.width / pixels.width, canvas.height / pixels.height)
        let size = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func base(field: KnowledgeParticleField, canvas: CGSize, origin: CGRect? = nil) -> [String: Vector] {
        let frame = origin ?? CGRect(origin: .zero, size: canvas)
        guard valid(frame) else { return [:] }
        let camera = KnowledgeParticleField.framing(particles: field.particles, spread: 1, reduceMotion: true)
        // The floating avatar draws in a 256-point square, then scales its
        // artwork. Preserve its fixed inset instead of applying it twice.
        if origin != nil {
            return KnowledgeParticleField.displayPositions(particles: field.particles, frame: camera, spread: 1,
                reduceMotion: true, width: 256, height: 256).mapValues {
                    .init(x: frame.minX + $0.x * frame.width / 256,
                          y: frame.minY + $0.y * frame.height / 256)
                }
        }
        return KnowledgeParticleField.displayPositions(particles: field.particles, frame: camera, spread: 1,
            reduceMotion: true, width: frame.width, height: frame.height)
            .mapValues { $0 + .init(x: frame.minX, y: frame.minY) }
    }

    /// Fixed for one desktop lease. Moving the target cannot crop particles
    /// that are still travelling from its previous position.
    static func desktopOverlay(displayFrames: [CGRect]) -> CGRect? {
        guard !displayFrames.isEmpty, displayFrames.allSatisfy(valid) else { return nil }
        let desktop = displayFrames.reduce(CGRect.null) { $0.union($1) }
        return valid(desktop) ? desktop.insetBy(dx: -26, dy: -26) : nil
    }

    static func offsets(field: KnowledgeParticleField, canvas: CGSize, target: CGRect,
                        origin: CGRect? = nil, pointsPerUnit: Double? = nil) -> [String: Vector] {
        guard valid(target), CGRect(origin: .zero, size: canvas).contains(target) else { return [:] }
        let pointsPerUnit = pointsPerUnit ?? scale(for: canvas)
        guard pointsPerUnit.isFinite, pointsPerUnit > 0 else { return [:] }
        let starts = base(field: field, canvas: canvas, origin: origin)
        let ends = KnowledgeParticleField.regionPositions(base: starts, target: target, canvas: canvas, progress: 1)
        return field.particles.reduce(into: [:]) { result, particle in
            guard particle.kind != .companion, let start = starts[particle.nodeID], let end = ends[particle.nodeID] else { return }
            let delta = end - start
            guard delta.length > 1e-6 else { return }
            // Preserve actual distance. A closer target must produce a smaller
            // force even when it lies along the same ray from this record.
            result[particle.nodeID] = delta * (1 / pointsPerUnit)
        }
    }

    /// Withdrawn anchors stay inspectable in the field, but the motion owner
    /// deliberately removes their bodies. Do not submit them as force targets.
    static func offsets(scene: CompanionParticleScene, canvas: CGSize, target: CGRect,
                        origin: CGRect? = nil, pointsPerUnit: Double? = nil) -> [String: Vector] {
        let eligible = Set(scene.graph.nodes.filter { $0.presentationState != .withdrawn }.map(\.id))
        return offsets(field: scene.field, canvas: canvas, target: target, origin: origin,
                       pointsPerUnit: pointsPerUnit).filter { eligible.contains($0.key) }
    }

    /// Draw only the simulation's admitted displacement. No target geometry or
    /// target progress enters here, so retargeting cannot teleport a held frame.
    static func positions(base: [String: Vector], offsets: [String: Vector],
                          pointsPerUnit: Double) -> [String: Vector] {
        guard pointsPerUnit.isFinite, pointsPerUnit > 0 else { return base }
        return base.reduce(into: [:]) { result, entry in
            let (id, start) = entry
            guard let offset = offsets[id], offset.x.isFinite, offset.y.isFinite else {
                result[id] = start; return
            }
            let position = start + offset * pointsPerUnit
            result[id] = position.x.isFinite && position.y.isFinite ? position : start
        }
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.maxX, rect.maxY, rect.size.width, rect.size.height].allSatisfy(\.isFinite)
            && rect.size.width > 0 && rect.size.height > 0
    }
}
