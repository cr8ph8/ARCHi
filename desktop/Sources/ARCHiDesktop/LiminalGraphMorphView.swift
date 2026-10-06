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
    var requestIDs: Set<String> = []
    let expression: KinLightExpression
    var seedAppearance: CompanionParticleAppearance? = nil
    var motionSceneDigest: String? = nil
    var motionEnabled = true
    var compact = false
    var includesSeedEquipment = true
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
    @State private var displayedMotion = CompanionParticleMotion.Frame.still
    @State private var windowVisible = false
    @State private var presented = false
    @Environment(\.companionParticleMotionEnabled) private var sharedMotionEnabled

    var body: some View {
        GeometryReader { proxy in
            let key = Key(session: source.bindings.sessionID, origin: source.originDigest,
                graph: source.bindings.graphDigest, map: LiminalKnowledgeBindings.digest(graph),
                manifest: source.asset.manifestSHA256, finish: source.asset.finish?.digest,
                viewport: proxy.size, visible: Set(nodes.map(\.id)), focus: focusIDs)
            ZStack(alignment: .bottomLeading) {
                if let seedAppearance {
                    // Preserve the chosen authored Seed beneath its record motes.
                    // While Metal is ready, its completed frame owns the opacity.
                    let shown = readyKey == key && prepared?.key == key ? displayedProgress
                        : LiminalGraphMorph.boundedProgress(progress)
                    seedAppearance.art(size: min(proxy.size.width, proxy.size.height),
                        reduceMotion: reduceMotion || !presented || !windowVisible || !motionEnabled || !sharedMotionEnabled || shown >= 0,
                        includesEquipment: includesSeedEquipment)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(max(0, -shown))
                }
                if let prepared {
                    LiminalGraphMorphSurface(asset: source.asset, morph: prepared.morph, frame: prepared.frame,
                        nodes: nodes, edges: graph.edges, selectedID: selectedID, progress: progress,
                        seedColor: seedColor, reduceMotion: reduceMotion,
                        // ARCHi hosts this view in an AppKit NSHostingView, which
                        // has no SwiftUI Scene to publish an active scenePhase.
                        // Metal already checks its real window and occlusion.
                        isVisible: presented && windowVisible && prepared.key == key,
                        ready: readyKey == key && prepared.key == key,
                        growthByRecordID: growthByRecordID, preparedIDs: preparedIDs, requestIDs: requestIDs,
                        expression: expression,
                        displayedProgress: displayedProgress, displayedMotion: displayedMotion,
                        motionSceneDigest: motionSceneDigest, motionEnabled: motionEnabled, compact: compact,
                        onDisplayedFrame: { progress, motionFrame in
                            guard self.prepared?.key == key, prepared.key == key else { return }
                            displayedProgress = LiminalGraphMorph.boundedProgress(progress)
                            displayedMotion = motionFrame
                        },
                        onAvailability: { ready in
                            guard self.prepared?.key == key, prepared.key == key else { return }
                            readyKey = ready ? key : nil
                        }, onSelect: onSelect)
                        .opacity(prepared.key == key ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.15), value: progress)
                }
                if prepared?.key != key || readyKey != key {
                    KnowledgeParticleView(field: field, nodes: nodes, selectedID: selectedID,
                        spread: 1 + min(0, LiminalGraphMorph.boundedProgress(progress)),
                        pulses: false, reduceMotion: true, tint: seedColor.accent, expression: expression,
                        preparedIDs: preparedIDs, requestIDs: requestIDs, focusIDs: focusIDs,
                        growthByRecordID: growthByRecordID, motionSceneDigest: motionSceneDigest, onSelect: onSelect)
                    if failed {
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
        .background(ParticlePresentationVisibility { windowVisible = $0 }.frame(width: 0, height: 0))
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
    let requestIDs: Set<String>
    let expression: KinLightExpression
    let displayedProgress: Double
    let displayedMotion: CompanionParticleMotion.Frame
    let motionSceneDigest: String?
    let motionEnabled: Bool
    let compact: Bool
    let onDisplayedFrame: (Double, CompanionParticleMotion.Frame) -> Void
    let onAvailability: (Bool) -> Void
    let onSelect: (String) -> Void
    @Environment(\.companionParticleMotionEnabled) private var sharedMotionEnabled
    @Environment(\.companionParticleMotion) private var motion
    @State private var draggedID: String?
    @State private var dragSceneDigest: String?
    @State private var dragStart = KnowledgeParticleField.Vector.zero
    @State private var clock = ParticlePresentationClock()
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let moving = isVisible && motionEnabled && sharedMotionEnabled && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving)) { tick in
            let sample = motionFrame(moving: moving, time: clock.time(for: tick.date))
            surface(motionFrame: sample)
        }
        .onDisappear { endDrag() }
        .onChange(of: motionSceneDigest) { _, _ in endDrag() }
        .onChange(of: moving) { _, moving in if !moving { endDrag() } }
    }

    private func surface(motionFrame: CompanionParticleMotion.Frame) -> some View {
        let points = morph.anchorPositions(asset: asset, frame: frame, progress: displayedProgress, motion: displayedMotion)
        let weight = Double(abs(LiminalGraphMorph.signedSmoothstep(displayedProgress)))
        return ZStack {
            LiminalMetalView(asset: asset, progress: LiminalGraphMorph.targetProgress,
                reduceMotion: reduceMotion, isVisible: isVisible, seedColor: seedColor,
                lightExpression: expression,
                inspection: true, graphMorph: morph, graphMorphProgress: progress, graphMotion: motionFrame,
                onGraphMorphAvailability: onAvailability,
                onGraphMorphDisplayedMotion: onDisplayedFrame)
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
                        MemoryParticleContextCue.draw(in: &context, at: point,
                            prepared: preparedIDs.contains(id), requested: requestIDs.contains(id))
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
                ForEach(nodes) { node in
                    if let point = points[node.id] {
                        Button { onSelect(node.id) } label: {
                            Circle().fill(.clear).frame(width: 24, height: 24).contentShape(Circle())
                        }.buttonStyle(.plain)
                            .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("memory-morph"))
                                .onChanged { value in
                                    let scale = morph.motionPointScale(progress: displayedProgress)
                                    guard isVisible, !reduceMotion, motionEnabled, sharedMotionEnabled, let motion, let motionSceneDigest,
                                          ready, scale > 0 else { return }
                                    if draggedID != node.id {
                                        endDrag(); draggedID = node.id
                                        dragSceneDigest = motionSceneDigest
                                        dragStart = displayedMotion.offsets[node.id] ?? .zero
                                    }
                                    _ = motion.grab(nodeID: node.id, offset: dragStart + .init(
                                        x: value.translation.width / scale, y: value.translation.height / scale),
                                        sceneDigest: motionSceneDigest)
                                }.onEnded { _ in endDrag() })
                            .position(point)
                            .help("\(node.title) · \(node.status)")
                            .accessibilityLabel("\(node.kind.title): \(node.title). \(node.status)")
                            .accessibilityValue(MemoryParticleContextCue.description(prepared: preparedIDs.contains(node.id),
                                requested: requestIDs.contains(node.id)))
                            .accessibilityAddTraits(node.id == selectedID ? [.isSelected] : [])
                            .accessibilityIdentifier("companion-graph.form-particle.\(node.id)")
                        if !compact && (node.id == selectedID || preparedIDs.contains(node.id) || node.kind == .companion && weight < 0.5) {
                            Text(node.kind == .companion ? node.title + " · " + expression.label : node.title)
                                .font(.system(size: 10, weight: .medium)).lineLimit(2)
                                .padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                                .frame(maxWidth: 150).position(x: point.x, y: point.y + 25)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                }
            }
        }.coordinateSpace(name: "memory-morph")
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
}
