import SwiftUI

/// One selectable anchor per current graph record. Satellite motes are artwork,
/// not records; only the owner's recorded edges connect anchors.
struct KnowledgeParticleView: View, @MainActor Animatable {
    let field: KnowledgeParticleField
    let nodes: [CompanionGraphNode]
    let selectedID: String?
    var spread: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { .init(spread, regionProgress) }
        set { spread = newValue.first; regionProgress = newValue.second }
    }
    let pulses: Bool
    let reduceMotion: Bool
    let tint: Color
    var showsLabels = true
    var expression: KinLightExpression = .resting
    var preparedIDs: Set<String> = []
    var requestIDs: Set<String> = []
    var focusIDs: Set<String>?
    var compact = false
    var interactive = true
    var growthByRecordID: [String: CompanionParticleScene.Growth] = [:]
    /// Transient image-space attention. This never changes record bindings.
    var regionTarget: CGRect?
    var regionProgress: Double = 1
    var usesPhysicalAttraction = false
    var presentationOrigin: CGRect?
    var attractionPointsPerUnit: Double?
    /// AppKit's floating host supplies real window visibility; scene-based views
    /// retain their ordinary SwiftUI lifecycle. This controls drawing only.
    var animationVisible: Bool? = nil
    var motionSceneDigest: String? = nil
    let onSelect: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.companionParticleMotionEnabled) private var sharedMotionEnabled
    @Environment(\.companionParticleMotion) private var motion
    @State private var hoveredID: String?
    @State private var isPresented = false
    @State private var windowVisible = false
    @State private var draggedID: String?
    @State private var dragSceneDigest: String?
    @State private var dragStart = KnowledgeParticleField.Vector.zero
    @State private var clock = ParticlePresentationClock()

    var body: some View {
        let still = reduceMotion || systemReduceMotion || !sharedMotionEnabled
        let visible = Set(nodes.map(\.id))
        let particles = field.particles.filter { visible.contains($0.nodeID) }
        let edges = field.edges.filter { visible.contains($0.source) && visible.contains($0.target) }
        let active = (interactive ? hoveredID.flatMap { visible.contains($0) ? $0 : nil } : nil)
            ?? selectedID.flatMap { visible.contains($0) ? $0 : nil }
        let neighbours = Set(edges.filter { $0.source == active || $0.target == active }.flatMap { [$0.source, $0.target] })
        let framing = KnowledgeParticleField.framing(particles: field.particles, spread: spread,
            reduceMotion: still, focusIDs: focusIDs)
        GeometryReader { proxy in
            let moving = !still && pulses && isPresented && (animationVisible ?? windowVisible)
            if still || !pulses || motionSceneDigest == nil && motion == nil {
                frameContent(size: proxy.size, particles: particles, edges: edges, framing: framing,
                    active: active, neighbours: neighbours, time: 0, still: still, moving: false)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving)) { tick in
                    frameContent(size: proxy.size, particles: particles, edges: edges, framing: framing,
                        active: active, neighbours: neighbours,
                        time: tick.date.timeIntervalSinceReferenceDate, still: still, moving: moving)
                }
            }
        }
        .background(ParticlePresentationVisibility { windowVisible = $0 }.frame(width: 0, height: 0))
        .accessibilityIdentifier("companion-graph.particles")
        .allowsHitTesting(interactive)
        .onAppear { isPresented = true }
        .onDisappear { isPresented = false; endDrag() }
        .onChange(of: motionSceneDigest) { _, _ in endDrag() }
        .onChange(of: animationVisible ?? windowVisible) { _, visible in if !visible { endDrag() } }
        .onChange(of: still || !pulses) { _, paused in if paused { endDrag() } }
    }

    /// Canvas, labels and hit targets are built from one sampled simulation frame.
    /// The shared runtime advances once, even when the map and avatar both draw.
    private func frameContent(size: CGSize, particles: [KnowledgeParticleField.Particle],
                              edges: [CompanionGraphEdge], framing: KnowledgeParticleField.Frame,
                              active: String?, neighbours: Set<String>, time: Double,
                              still: Bool, moving: Bool) -> some View {
        let sample = motionFrame(moving: moving, time: clock.time(for: Date(timeIntervalSinceReferenceDate: time)))
        let scale = max(0, min(size.width, size.height) * 0.43 - 12)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let basePoints = usesPhysicalAttraction
            ? ParticleAttractionProjection.base(field: field, canvas: size, origin: presentationOrigin)
            : KnowledgeParticleField.displayPositions(particles: particles, frame: framing,
            spread: spread, reduceMotion: still, width: size.width, height: size.height,
            motionOffsets: sample.offsets)
        let points = (usesPhysicalAttraction
            ? ParticleAttractionProjection.positions(base: basePoints, offsets: sample.offsets,
                pointsPerUnit: attractionPointsPerUnit ?? ParticleAttractionProjection.scale(for: size))
            : KnowledgeParticleField.regionPositions(base: basePoints, target: regionTarget,
                canvas: size, progress: still ? 1 : regionProgress))
            .mapValues { CGPoint(x: $0.x, y: $0.y) }
        let t = spread.isFinite ? min(1, max(0, spread)) : 1
        let motionScale = scale / framing.halfExtent * (0.4 + 0.6 * t)
        return ZStack {
            particleCanvas(particles: particles, edges: edges, points: points,
                center: center, scale: scale, active: active, neighbours: neighbours,
                time: time, still: still).allowsHitTesting(false)
            ForEach(nodes) { node in
                if let position = points[node.id] {
                    if interactive {
                        nodeButton(node)
                            .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("memory-particles"))
                                .onChanged { value in
                                    guard moving, !still, pulses, regionTarget == nil,
                                          let motion, let motionSceneDigest, motionScale > 0 else { return }
                                    if draggedID != node.id {
                                        endDrag()
                                        draggedID = node.id
                                        dragSceneDigest = motionSceneDigest
                                        dragStart = sample.offsets[node.id] ?? .zero
                                    }
                                    _ = motion.grab(nodeID: node.id, offset: dragStart + .init(
                                        x: value.translation.width / motionScale,
                                        y: value.translation.height / motionScale), sceneDigest: motionSceneDigest)
                                }.onEnded { _ in endDrag() })
                            .position(position)
                    }
                    if !compact && showsLabels && (node.id == active || node.kind == .companion || preparedIDs.contains(node.id)) {
                        Text(node.kind == .companion ? node.title + " · " + expression.label : node.title)
                            .font(.system(size: 10, weight: .medium)).lineLimit(2)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                            .frame(maxWidth: 145).position(x: position.x, y: position.y + 23)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
        }.coordinateSpace(name: "memory-particles")
    }

    private func motionFrame(moving: Bool, time: Double) -> CompanionParticleMotion.Frame {
        guard let motion, let motionSceneDigest else { return .still }
        return moving ? motion.sample(sceneDigest: motionSceneDigest, time: time,
            active: true, reduceMotion: false) : motion.snapshot(sceneDigest: motionSceneDigest)
    }

    private func endDrag() {
        if let draggedID, let dragSceneDigest { motion?.release(nodeID: draggedID, sceneDigest: dragSceneDigest) }
        draggedID = nil; dragSceneDigest = nil
    }

    private func particleCanvas(particles: [KnowledgeParticleField.Particle], edges: [CompanionGraphEdge],
                                points: [String: CGPoint], center: CGPoint, scale: Double,
                                active: String?, neighbours: Set<String>, time: Double, still: Bool) -> some View {
        Canvas { context, _ in
            if !compact {
                // This diffuse halo is artwork, not another record.
                context.fill(Path(ellipseIn: CGRect(x: center.x - scale * 0.70, y: center.y - scale * 0.70,
                    width: scale * 1.40, height: scale * 1.40)), with: .radialGradient(
                        Gradient(colors: [tint.opacity(0.08), .clear]), center: center, startRadius: 0, endRadius: scale * 0.70))
                for edge in edges {
                    guard let a = points[edge.source], let b = points[edge.target] else { continue }
                    let highlighted = edge.source == active || edge.target == active
                    var line = Path(); line.move(to: a); line.addLine(to: b)
                    context.stroke(line, with: .color(highlighted ? tint.opacity(0.80) : Color.secondary.opacity(active == nil ? 0.26 : 0.10)),
                        style: StrokeStyle(lineWidth: highlighted ? 1.4 : 0.6, dash: edge.relationship.dash.map { CGFloat($0) }))
                    if highlighted {
                        let angle = atan2(b.y - a.y, b.x - a.x)
                        let tip = CGPoint(x: a.x + (b.x - a.x) * 0.66, y: a.y + (b.y - a.y) * 0.66)
                        var arrow = Path(); arrow.move(to: CGPoint(x: tip.x - cos(angle - 0.5) * 5, y: tip.y - sin(angle - 0.5) * 5))
                        arrow.addLine(to: tip); arrow.addLine(to: CGPoint(x: tip.x - cos(angle + 0.5) * 5, y: tip.y - sin(angle + 0.5) * 5))
                        context.stroke(arrow, with: .color(tint.opacity(0.8)), lineWidth: 1)
                    }
                }
            }
            for particle in particles {
                guard let point = points[particle.nodeID] else { continue }
                let focused = particle.nodeID == active || neighbours.contains(particle.nodeID)
                    || preparedIDs.contains(particle.nodeID) || requestIDs.contains(particle.nodeID)
                let color = particle.kind == .companion
                    ? (expression.mode == .rest ? tint : KinLightPalette(mode: expression.mode).accent)
                    : graphColor(particle.kind)
                let animated = !still && pulses && !(particle.kind == .companion
                    && (expression.mode == .rest || expression.mode == .hold))
                let phase = KinLightEffectsGeometry.phase(at: time, reduceMotion: !animated, systemReduceMotion: still)
                let pulse = particle.kind == .companion
                    ? 0.75 + KinLightEmission.intensity(mode: expression.mode, phase: phase) * 0.6
                    : (still || !pulses ? 1 : 0.86 + 0.14 * sin(time * 0.8 + particle.phase))
                let radius = particle.kind == .companion ? 7.0 : 3.7
                let opacity = active == nil || focused ? pulse : 0.36
                // Satellites mark current reviewed applications of this content.
                // Retained/context records have an anchor even without support.
                if let growth = growthByRecordID[particle.nodeID] {
                    let count = KnowledgeParticleField.reviewedSatelliteCount(applications: growth.applications,
                        reviewedApplicationCount: growth.reviewedApplicationCount)
                    let contentPhase = KnowledgeParticleField.fraction(growth.contentID, salt: "reviewed-motif") * 2 * .pi
                    for index in 0..<count {
                        let orbit = 9.0 + Double(index % 3) * 3.2
                        let angle = contentPhase + Double(index) * 2.39996
                            + (!animated ? 0 : time * 0.12 * (index.isMultiple(of: 2) ? 1 : -1))
                        let mote = CGPoint(x: point.x + cos(angle) * orbit,
                            y: point.y + sin(angle) * orbit * 0.65)
                        let reviewedAccent = Color(red: 0.96, green: 0.73, blue: 0.40)
                        context.fill(Path(ellipseIn: CGRect(x: mote.x - 0.8, y: mote.y - 0.8,
                            width: 1.6, height: 1.6)), with: .color(reviewedAccent.opacity(opacity * 0.85)))
                    }
                }
                if !compact {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - radius * 4, y: point.y - radius * 4,
                        width: radius * 8, height: radius * 8)), with: .radialGradient(
                            Gradient(colors: [color.opacity(0.45 * opacity), .clear]), center: point, startRadius: 0, endRadius: radius * 4))
                }
                context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2)), with: .color(color.opacity(opacity)))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 1.2, y: point.y - 1.2, width: 2.4, height: 2.4)), with: .color(.white.opacity(opacity)))
                if particle.nodeID == selectedID {
                    context.stroke(Path(ellipseIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)), with: .color(color), lineWidth: 1)
                }
                if !compact {
                    MemoryParticleContextCue.draw(in: &context, at: point,
                        prepared: preparedIDs.contains(particle.nodeID), requested: requestIDs.contains(particle.nodeID))
                }
            }
        }.accessibilityHidden(true)
    }

    private func nodeButton(_ node: CompanionGraphNode) -> some View {
        Button { onSelect(node.id) } label: {
            Circle().fill(Color.clear).frame(width: 24, height: 24).contentShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if !compact && node.presentationState.needsAttention {
                        Image(systemName: node.presentationState.symbol)
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.primary)
                            .padding(2).background(.regularMaterial, in: Circle())
                            .offset(x: 5, y: -5).accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain).help("\(node.title) · \(node.status)")
        .accessibilityLabel("\(node.kind.title): \(node.title). \(node.status)")
        .accessibilityValue(MemoryParticleContextCue.description(prepared: preparedIDs.contains(node.id),
            requested: requestIDs.contains(node.id)))
        .accessibilityAddTraits(node.id == selectedID ? [.isSelected] : [])
        .accessibilityIdentifier("companion-graph.particle.\(node.id)")
        .onHover { isHovered in
            if isHovered { hoveredID = node.id }
            else if hoveredID == node.id { hoveredID = nil }
        }
    }
}

/// The same cue in the map, floating avatar and authored-body overlay. Rings
/// describe request references, never model attention, approval or new growth.
enum MemoryParticleContextCue {
    static func description(prepared: Bool, requested: Bool) -> String {
        [prepared ? "Prepared for the next local reply" : nil,
         requested ? "Referenced by the current local request" : nil].compactMap { $0 }.joined(separator: ". ")
    }

    static func draw(in context: inout GraphicsContext, at point: CGPoint, prepared: Bool, requested: Bool) {
        if requested {
            for radius in [15.0, 18.0] {
                context.stroke(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        } else if prepared {
            context.stroke(Path(ellipseIn: CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)),
                with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }
}
