import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A local construction study. The user's qualified body and saved pose keep
/// their existing owners; this deliberately does not claim Unity parity.
@MainActor
struct LiminalDevelopmentCard: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var evolution: EvolutionStore
    @State private var form: LiminalFormDevelopment.Form = .beast
    @State private var detail = 4
    @State private var stopped = true
    @State private var impulseAt = Date.distantPast
    @State private var visible = false
    @State private var exportNotice: String?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        if store.activeQiMon?.character == .hampton {
            WorkspaceCard {
                TimelineView(.periodic(from: .now, by: 2)) { tick in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Liminal · growing structure").font(.headline)
                            Spacer()
                            Text(store.kinLightExpression.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Keep a distinct lesson to add a node. Confirm that it helped to strengthen that node. Together, supported nodes can carry more intricate patterns.")
                            .font(.callout).foregroundStyle(.secondary)
                        if let snapshot = store.liminalFormDevelopment(at: tick.date) {
                            content(snapshot)
                        } else {
                            Text("Current learning is unavailable. Your chosen body and Seed remain yours; reopen the current profile after resolving any source or recovery issue.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }.accessibilityIdentifier("liminal.development")
                .onAppear { visible = true }
                .onDisappear { visible = false; stopped = true }
        }
    }

    private func content(_ snapshot: LiminalFormDevelopment.Snapshot) -> some View {
        let reduced = systemReduceMotion || store.preferences.reduceMotion || store.preferences.quiet
        let structure = LiminalFormDevelopment.structure(snapshot, form: form, requestedDetail: detail)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(snapshot.nodes.count) distinct nodes · \(snapshot.practicedNodes) supported by confirmed use")
                .font(.callout.weight(.medium)).accessibilityIdentifier("liminal.development.counts")
            Picker("Structure study", selection: $form) {
                ForEach(LiminalFormDevelopment.Form.allCases) { form in Text(form.title).tag(form) }
            }.pickerStyle(.segmented)
            TimelineView(.animation(minimumInterval: 1 / 30,
                                    paused: !visible || stopped || reduced)) { time in
                LiminalStructureDrawing(structure: structure,
                    elapsed: time.date.timeIntervalSince(impulseAt), reducedMotion: reduced,
                    stopped: stopped || !visible)
            }.frame(height: 235)
                .background(Color(red: 0.025, green: 0.019, blue: 0.028), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(form.title) construction preview, detail \(structure.detail) of \(snapshot.availableDetail), \(snapshot.nodes.count) memory nodes. Golden Seed remains at the center. Construction lines are artistic constraints.")
            HStack {
                Stepper("Detail \(structure.detail) / \(snapshot.availableDetail)", value: Binding(
                    get: { min(detail, snapshot.availableDetail) }, set: { detail = $0 }), in: 0...max(0, snapshot.availableDetail))
                Button("Test response") { impulseAt = Date(); stopped = false }
                    .disabled(reduced || structure.particles.isEmpty)
                    .accessibilityIdentifier("liminal.development.impulse")
                Button("Stop") { stopped = true }.disabled(stopped)
                    .accessibilityIdentifier("liminal.development.stop")
            }.font(.caption)
            Text("Structure study · \(structure.particles.count) display particles. These particles represent the same \(snapshot.nodes.count) nodes; screen pixels and rendering detail add no memories.")
                .font(.caption).foregroundStyle(.secondary)
            Text("More practiced nodes recover their shape sooner after a test impulse. Rest and Stop preserve learning. All three forms remain available.")
                .font(.caption).foregroundStyle(.secondary)
            if snapshot.unavailableLessons > 0 || snapshot.duplicateLessons > 0 || snapshot.hiddenNodes > 0 {
                Text("\(snapshot.unavailableLessons) lessons need a current source or review; \(snapshot.duplicateLessons) duplicate copies share a node; \(snapshot.hiddenNodes) nodes are outside this drawing’s detail budget.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !snapshot.evidenceAvailable {
                if evolution.practiceJourneyOriginDigest == nil {
                    Text("Connect this study to Liminal’s Journey to use this profile’s reviewed learning references. They remain profile evidence, not a claim of personally earned ability.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Connect learning study") { _ = store.connectLiminalLearningStudy() }
                        .disabled(store.isWorking).accessibilityIdentifier("liminal.development.connect")
                } else {
                    Text("Current feedback needs review before it can support more detail. Retained nodes remain visible. Reopen the profile after resolving changes to the feedback records.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Review lessons") { store.open(.memory) }
                Button("Review useful work") { store.open(.evolution) }
            }.buttonStyle(.borderless)
            Button("Export Blender study…") { exportStudy() }
                .accessibilityIdentifier("liminal.development.export")
                .help("Exports node identifiers and construction geometry locally. No lesson text or source files.")
            if let exportNotice { Text(exportNotice).font(.caption).foregroundStyle(.secondary) }
            if evolution.hasUnsavedChanges {
                Button("Save evolution") { _ = evolution.save() }
                    .accessibilityIdentifier("liminal.development.save")
                Text(evolution.status).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("How detail develops") {
                Text("Detail 1: a retained node. Detail 2: 3 nodes, 2 with confirmed use. Detail 3: 6 nodes, 3 supported. Detail 4: 12 nodes, 6 supported. These are editable art rules, not intelligence scores or battle bonuses. Identical lesson copies share one node; repeating the same input does not add practice. Correcting or withdrawing support changes this study, never confiscates a kept body. Kept lessons and Evolution keep their existing Save and Load controls. This native study does not replace the qualified Blender/Unity body.")
                    .font(.caption).foregroundStyle(.secondary)
            }.font(.caption)
        }
        .task(id: impulseAt) {
            guard !stopped else { return }
            do {
                try await Task.sleep(for: .seconds(3))
                try Task.checkCancellation()
                stopped = true
            } catch { }
        }
        .onChange(of: reduced) { _, value in if value { stopped = true } }
        .onChange(of: snapshot.originDigest) { _, _ in stopped = true }
    }

    private func exportStudy() {
        let initialOrigin = store.activeQiMon?.originDigest
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "liminal-\(form.rawValue)-structure.json"
        panel.message = "Local Blender study. Includes private record identifiers and structure, but no lesson text, titles, prompts or source paths."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard store.activeQiMon?.originDigest == initialOrigin, let snapshot = store.liminalFormDevelopment() else {
            exportNotice = "The current learning changed or became unavailable. Review it before exporting."; return
        }
        do {
            try LiminalFormDevelopment.export(snapshot, form: form, requestedDetail: detail).write(to: url, options: .atomic)
            exportNotice = "Exported the current structure for Blender. Your body and saved learning are unchanged."
        } catch { exportNotice = "Could not export this study: \(error.localizedDescription)" }
    }
}

struct LiminalStructureDrawing: View {
    let structure: LiminalFormDevelopment.Structure
    let elapsed: Double
    let reducedMotion: Bool
    let stopped: Bool
    private let gold = Color(red: 1, green: 0.7, blue: 0.22)
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            func screen(_ value: SIMD2<Double>) -> CGPoint {
                CGPoint(x: (size.width - side) / 2 + value.x * side, y: value.y * side)
            }
            let positions = Dictionary(uniqueKeysWithValues: structure.particles.map {
                ($0.id, screen(LiminalFormDevelopment.displaced($0, elapsed: elapsed,
                    reducedMotion: reducedMotion, stopped: stopped)))
            })
            let guide = LiminalFormDevelopment.guide(form: structure.form).map(screen)
            var outline = Path()
            if let first = guide.first {
                outline.move(to: first)
                for point in guide.dropFirst() { outline.addLine(to: point) }
                outline.closeSubpath()
            }
            context.stroke(outline, with: .color(Color(red: 0.8, green: 0.12, blue: 0.22).opacity(0.34)),
                           style: StrokeStyle(lineWidth: 0.8, dash: [2, 4]))
            for thread in structure.threads {
                guard let a = positions[thread.from], let b = positions[thread.to] else { continue }
                var path = Path(); path.move(to: a); path.addLine(to: b)
                context.stroke(path, with: .color(gold.opacity(0.42)), lineWidth: 0.8)
            }
            let core = screen(structure.core)
            for particle in structure.particles {
                guard let p = positions[particle.id] else { continue }
                if particle.id.hasSuffix(":0") {
                    var tether = Path(); tether.move(to: core); tether.addQuadCurve(to: p,
                        control: CGPoint(x: core.x + (p.x - core.x) * 0.3, y: p.y))
                    context.stroke(tether, with: .color(gold.opacity(particle.applications > 0 ? 0.20 : 0.07)), lineWidth: 0.6)
                }
                let radius: CGFloat = particle.applications > 0 ? 2.1 : 1.5
                context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(particle.applications > 0 ? gold : Color(red: 0.85, green: 0.12, blue: 0.22)))
            }
            context.fill(Path(ellipseIn: CGRect(x: core.x - 13, y: core.y - 13, width: 26, height: 26)), with: .color(gold.opacity(0.12)))
            context.fill(Path(ellipseIn: CGRect(x: core.x - 5, y: core.y - 5, width: 10, height: 10)), with: .color(gold))
        }.allowsHitTesting(false)
    }
}
