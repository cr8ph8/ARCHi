import SwiftUI

/// One anchor per retained memory. Satellites show reviewed use of that same
/// memory, never additional records or an inferred capability score.
enum CompanionMemoryParticles {
    struct Anchor: Equatable, Identifiable {
        let id: String
        let x: Double
        let y: Double
        let applications: Int
    }
    static func anchors(_ snapshot: LiminalFormDevelopment.Snapshot) -> [Anchor] {
        snapshot.visibleNodes.map { node in
            let phase = Double(UInt32(node.id.prefix(8), radix: 16) ?? 0) / Double(UInt32.max) * 2 * .pi
            return Anchor(id: node.id, x: 0.5 + 0.40 * cos(phase), y: 0.5 + 0.40 * sin(phase),
                          applications: min(8, max(0, node.applications)))
        }
    }
    @MainActor static func identity(_ snapshot: LiminalFormDevelopment.Snapshot?) -> String {
        guard let snapshot else { return "memory-unavailable" }
        let value = snapshot.originDigest + "\n" + snapshot.nodes.map {
            "\($0.id):\($0.reviewedApplicationCount):\($0.supportDigest ?? "")"
        }.joined(separator: "\n")
        return LiminalKnowledgeBindings.sha256(Data(value.utf8))
    }
    static func applies(form: CompanionForm, family: EvolutionFamily?, treatment: CompanionVisualTreatment) -> Bool {
        family == nil && (form == .kin || form == .kinSeed || form == .particleSeed || form == .corePearl
            || form == .hamptonSeed || (form == .companion && treatment == .protoStudy))
    }
}

struct CompanionMemoryParticleField: View {
    let snapshot: LiminalFormDevelopment.Snapshot
    let reduceMotion: Bool
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if reduceMotion {
                drawing(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !visible || scenePhase != .active)) { tick in
                    drawing(phase: !visible || scenePhase != .active ? 0 : tick.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .onAppear { visible = true }.onDisappear { visible = false }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func drawing(phase: Double) -> some View {
        let anchors = CompanionMemoryParticles.anchors(snapshot)
        return Canvas { context, size in
                let side = min(size.width, size.height)
                for anchor in anchors {
                    let center = CGPoint(x: anchor.x * side + (size.width - side) / 2,
                                         y: anchor.y * side + (size.height - side) / 2)
                    let radius = side * (anchor.applications > 0 ? 0.012 : 0.008)
                    let brightness = phase == 0 ? 0.85 : 0.78 + 0.12 * sin(phase * 0.8 + anchor.x * 9)
                    let color = anchor.applications > 0 ? Color(red: 1, green: 0.73, blue: 0.32)
                        : Color(red: 0.64, green: 0.68, blue: 0.75)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - radius * 2, y: center.y - radius * 2,
                                                       width: radius * 4, height: radius * 4)), with: .color(color.opacity(0.12)))
                    context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                       width: radius * 2, height: radius * 2)), with: .color(color.opacity(brightness)))
                    for index in 0..<anchor.applications {
                        let angle = Double(index) / Double(anchor.applications) * 2 * .pi
                        let point = CGPoint(x: center.x + cos(angle) * side * 0.025,
                                            y: center.y + sin(angle) * side * 0.025)
                        let dot = side * 0.0035
                        context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)),
                                     with: .color(color.opacity(0.65)))
                    }
                }
        }
    }
}
