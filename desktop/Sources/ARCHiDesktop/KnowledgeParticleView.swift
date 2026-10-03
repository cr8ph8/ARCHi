import SwiftUI

/// One selectable anchor per current graph record. Satellite motes are artwork,
/// not records; only the owner's recorded edges connect anchors.
struct KnowledgeParticleView: View, @MainActor Animatable {
    let field: KnowledgeParticleField
    let nodes: [CompanionGraphNode]
    let selectedID: String?
    var spread: Double
    var animatableData: Double {
        get { spread }
        set { spread = newValue }
    }
    let pulses: Bool
    let reduceMotion: Bool
    let tint: Color
    var showsLabels = true
    var expression: KinLightExpression = .resting
    var preparedIDs: Set<String> = []
    var focusIDs: Set<String>?
    var compact = false
    var interactive = true
    var growthByRecordID: [String: CompanionParticleScene.Growth] = [:]
    let onSelect: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var hoveredID: String?
    @State private var isPresented = false

    var body: some View {
        let still = reduceMotion || systemReduceMotion
        let visible = Set(nodes.map(\.id))
        let particles = field.particles.filter { visible.contains($0.nodeID) }
        let edges = field.edges.filter { visible.contains($0.source) && visible.contains($0.target) }
        let active = interactive ? (hoveredID.flatMap { visible.contains($0) ? $0 : nil }
            ?? selectedID.flatMap { visible.contains($0) ? $0 : nil }) : nil
        let neighbours = Set(edges.filter { $0.source == active || $0.target == active }.flatMap { [$0.source, $0.target] })
        let framing = KnowledgeParticleField.framing(particles: field.particles, spread: spread,
            reduceMotion: still, focusIDs: focusIDs)
        GeometryReader { proxy in
            let scale = max(0, min(proxy.size.width, proxy.size.height) * 0.43 - 12)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let points = KnowledgeParticleField.displayPositions(particles: particles, frame: framing,
                spread: spread, reduceMotion: still, width: proxy.size.width, height: proxy.size.height)
                .mapValues { CGPoint(x: $0.x, y: $0.y) }
            ZStack {
                if still {
                    // ImageRenderer can capture this deterministic Canvas directly.
                    // A paused TimelineView may omit its subtree in a snapshot.
                    particleCanvas(particles: particles, edges: edges, points: points,
                        center: center, scale: scale, active: active, neighbours: neighbours,
                        time: 0, still: true)
                        .allowsHitTesting(false)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 15,
                        paused: !pulses || scenePhase != .active || !isPresented)) { tick in
                        particleCanvas(particles: particles, edges: edges, points: points,
                            center: center, scale: scale, active: active, neighbours: neighbours,
                            time: pulses ? tick.date.timeIntervalSinceReferenceDate : 0, still: false)
                    }.allowsHitTesting(false)
                }
                ForEach(nodes) { node in
                    if let position = points[node.id] {
                        if interactive { nodeButton(node).position(position) }
                        // Nearby records can overlap; name the focused record and keep all titles in List.
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
            }
        }.accessibilityIdentifier("companion-graph.particles")
            .allowsHitTesting(interactive)
            .onAppear { isPresented = true }
            .onDisappear { isPresented = false }
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
                if !compact && preparedIDs.contains(particle.nodeID) {
                    context.stroke(Path(ellipseIn: CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)),
                        with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
        .accessibilityValue(preparedIDs.contains(node.id) ? "Selected as context for the next local reply" : "")
        .accessibilityAddTraits(node.id == selectedID ? [.isSelected] : [])
        .accessibilityIdentifier("companion-graph.particle.\(node.id)")
        .onHover { isHovered in
            if isHovered { hoveredID = node.id }
            else if hoveredID == node.id { hoveredID = nil }
        }
    }
}
