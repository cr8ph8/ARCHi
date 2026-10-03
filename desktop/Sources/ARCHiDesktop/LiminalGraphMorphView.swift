import SwiftUI

/// References captured from the existing native owners, never another store.
struct LiminalGraphMorphSource {
    let asset: LiminalPointAsset
    let bindings: LiminalKnowledgeBindings.Sidecar
    let fullGraph: CompanionGraphSnapshot
    let originDigest: String
}

/// The graph and authored body share one point surface. Preparation is keyed by
/// source/version and viewport; changing only the interpolation uploads no asset.
@MainActor struct LiminalGraphMorphView: View {
    let source: LiminalGraphMorphSource
    let graph: CompanionGraphSnapshot
    let field: KnowledgeParticleField
    let nodes: [CompanionGraphNode]
    let selectedID: String?
    let progress: Double
    let reduceMotion: Bool
    let seedColor: CompanionSeedColor
    let focusIDs: Set<String>?
    let growthByRecordID: [String: CompanionParticleScene.Growth]
    let preparedIDs: Set<String>
    let expression: KinLightExpression
    let onSelect: (String) -> Void

    private struct Key: Equatable {
        let session: String
        let origin: String
        let graph: String
        let map: String
        let manifest: String
        let finish: String?
        let viewport: CGSize
        let visible: Set<String>
        let focus: Set<String>?
    }
    private struct Prepared {
        let key: Key
        let morph: LiminalGraphMorph
        let frame: LiminalPointAsset.Frame
    }
    @State private var prepared: Prepared?
    @State private var failed = false
    @State private var readyKey: Key?
    @State private var displayedProgress = 0.0
    @State private var presented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            let key = Key(session: source.bindings.sessionID, origin: source.originDigest,
                graph: source.bindings.graphDigest, map: LiminalKnowledgeBindings.digest(graph),
                manifest: source.asset.manifestSHA256, finish: source.asset.finish?.digest,
                viewport: proxy.size, visible: Set(nodes.map(\.id)), focus: focusIDs)
            ZStack(alignment: .bottomLeading) {
                if let prepared {
                    LiminalGraphMorphSurface(asset: source.asset, morph: prepared.morph, frame: prepared.frame,
                        nodes: nodes, edges: graph.edges, selectedID: selectedID, progress: progress,
                        seedColor: seedColor, reduceMotion: reduceMotion,
                        isVisible: presented && scenePhase == .active && prepared.key == key,
                        ready: readyKey == key && prepared.key == key,
                        growthByRecordID: growthByRecordID, preparedIDs: preparedIDs,
                        expression: expression,
                        displayedProgress: displayedProgress,
                        onDisplayedProgress: { displayedProgress = $0 },
                        onAvailability: { ready in readyKey = ready ? prepared.key : nil }, onSelect: onSelect)
                        .opacity(prepared.key == key ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.15), value: progress)
                }
                if prepared?.key != key || readyKey != key {
                    KnowledgeParticleView(field: field, nodes: nodes, selectedID: selectedID,
                        spread: 1, pulses: false, reduceMotion: true, tint: seedColor.accent, expression: expression,
                        preparedIDs: preparedIDs, focusIDs: focusIDs, growthByRecordID: growthByRecordID, onSelect: onSelect)
                    if failed || prepared?.key == key {
                        Text("Point form is not available yet. Your records remain in the map.")
                            .font(.caption).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .allowsHitTesting(false)
                    }
                }
            }
            .task(id: key) {
                failed = false; readyKey = nil
                guard let morph = LiminalGraphMorph.make(asset: source.asset, bindings: source.bindings,
                    fullGraph: source.fullGraph, mapGraph: graph, field: field, originDigest: source.originDigest,
                    viewport: proxy.size, visibleNodeIDs: key.visible, focusIDs: focusIDs) else {
                    failed = true; return
                }
                let asset = source.asset
                if let previous = prepared, previous.key.manifest == key.manifest,
                   previous.key.finish == key.finish {
                    prepared = Prepared(key: key, morph: morph, frame: previous.frame)
                    return
                }
                let loading = Task.detached(priority: .userInitiated) {
                    try asset.framePair(progress: LiminalGraphMorph.targetProgress, detail: .low).lower
                }
                do {
                    let frame = try await withTaskCancellationHandler(operation: { try await loading.value },
                        onCancel: { loading.cancel() })
                    guard !Task.isCancelled else { return }
                    prepared = Prepared(key: key, morph: morph, frame: frame)
                } catch { if !Task.isCancelled { failed = true } }
            }
        }
        .onAppear { presented = true }
        .onDisappear { presented = false }
        .accessibilityIdentifier("companion-graph.liminal-morph")
    }
}

/// Animation advances only the presentation scalar. The buttons, recorded links
/// and the GPU use the same endpoint projection and interpolation.
@MainActor private struct LiminalGraphMorphSurface: View, @MainActor Animatable {
    let asset: LiminalPointAsset
    let morph: LiminalGraphMorph
    let frame: LiminalPointAsset.Frame
    let nodes: [CompanionGraphNode]
    let edges: [CompanionGraphEdge]
    let selectedID: String?
    var progress: Double
    let seedColor: CompanionSeedColor
    let reduceMotion: Bool
    let isVisible: Bool
    let ready: Bool
    let growthByRecordID: [String: CompanionParticleScene.Growth]
    let preparedIDs: Set<String>
    let expression: KinLightExpression
    let displayedProgress: Double
    let onDisplayedProgress: (Double) -> Void
    let onAvailability: (Bool) -> Void
    let onSelect: (String) -> Void
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let points = morph.anchorPositions(asset: asset, frame: frame, progress: displayedProgress)
        let weight = Double(LiminalGraphMorph.smoothstep(displayedProgress))
        ZStack {
            LiminalMetalView(asset: asset, progress: LiminalGraphMorph.targetProgress,
                reduceMotion: reduceMotion, isVisible: isVisible, seedColor: seedColor,
                lightExpression: expression,
                inspection: true, graphMorph: morph, graphMorphProgress: progress,
                onGraphMorphAvailability: onAvailability,
                onGraphMorphDisplayedProgress: onDisplayedProgress)
                .allowsHitTesting(false)
            if ready {
                Canvas { context, _ in
                    for edge in edges {
                        guard let a = points[edge.source], let b = points[edge.target] else { continue }
                        let active = edge.source == selectedID || edge.target == selectedID
                        var path = Path(); path.move(to: a); path.addLine(to: b)
                        context.stroke(path, with: .color(active ? seedColor.accent.opacity(0.7) : .secondary.opacity(0.22 * (1 - weight))),
                            style: StrokeStyle(lineWidth: active ? 1.2 : 0.6, dash: edge.relationship.dash.map { CGFloat($0) }))
                    }
                    if let selectedID, let p = points[selectedID] {
                        context.stroke(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)),
                            with: .color(seedColor.accent), lineWidth: 1.2)
                    }
                    for (id, point) in points {
                        if let node = nodes.first(where: { $0.id == id }) {
                            let color = node.kind == .companion
                                ? (expression.mode == .rest ? seedColor.accent : KinLightPalette(mode: expression.mode).accent)
                                : graphColor(node.kind)
                            let radius = node.kind == .companion ? 6.0 : 3.7
                            let opacity = (1 - weight) * 0.85 + 0.15
                            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                width: radius * 2, height: radius * 2)), with: .color(color.opacity(opacity)))
                        }
                        if let growth = growthByRecordID[id] {
                            let count = KnowledgeParticleField.reviewedSatelliteCount(applications: growth.applications,
                                reviewedApplicationCount: growth.reviewedApplicationCount)
                            let phase = KnowledgeParticleField.fraction(growth.contentID, salt: "reviewed-motif") * 2 * .pi
                            for index in 0..<count {
                                let angle = phase + Double(index) * 2.39996
                                let radius = 9.0 + Double(index % 3) * 3.2
                                let x = point.x + cos(angle) * radius, y = point.y + sin(angle) * radius * 0.65
                                context.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)),
                                    with: .color(Color(red: 0.96, green: 0.73, blue: 0.40)))
                            }
                        }
                        if preparedIDs.contains(id) {
                            context.stroke(Path(ellipseIn: CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)),
                                with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
                ForEach(nodes) { node in
                    if let point = points[node.id] {
                        Button { onSelect(node.id) } label: {
                            Circle().fill(.clear).frame(width: 24, height: 24).contentShape(Circle())
                        }.buttonStyle(.plain).position(point)
                            .help("\(node.title) · \(node.status)")
                            .accessibilityLabel("\(node.kind.title): \(node.title). \(node.status)")
                            .accessibilityValue(preparedIDs.contains(node.id) ? "Selected as context for the next local reply" : "")
                            .accessibilityAddTraits(node.id == selectedID ? [.isSelected] : [])
                            .accessibilityIdentifier("companion-graph.form-particle.\(node.id)")
                        if node.id == selectedID || preparedIDs.contains(node.id) || node.kind == .companion && weight < 0.5 {
                            Text(node.kind == .companion ? node.title + " · " + expression.label : node.title)
                                .font(.system(size: 10, weight: .medium)).lineLimit(2)
                                .padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                                .frame(maxWidth: 150).position(x: point.x, y: point.y + 25)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}
