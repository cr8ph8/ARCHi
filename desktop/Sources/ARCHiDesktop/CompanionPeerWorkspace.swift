import Foundation
import CryptoKit
import SwiftUI

/// This visit's inspection state. It is deliberately absent from preferences,
/// lessons, evolution, the working copy, and every external provider request.
struct CompanionPeerLabState {
    var inspection = PeerWorkSession(sessionID: UUID().uuidString)
    var simulation: PeerGossipSimulation?
    var simulationTime: TimeInterval = 0
    var inspectedNodeCount = 0
    var inspectedEdgeCount = 0
    var inspectedTruncatedCount = 0
    var inspectedSourceRevision: UInt64?
    var lastDecision: PeerAdmissionRecord?
    var inspectionMessage = "Inspect the current bounded graph on this Mac. The report stays in this visit."
    var simulationMessage = "Start an offline example with four virtual workers."
}

@MainActor
extension CompanionStore {
    /// Host-owned bindings include both the exact source and the current request
    /// ticket. Only graph IDs, types, statuses, and endpoints enter the worker.
    func peerInspectionInput() -> PeerInspectionInput {
        let graph = peerInspectionGraph()
        let ticket = contextTicket()
        let nodeRows = graph.nodes.map { [$0.id, $0.kind.rawValue, $0.status] }
            .sorted { $0.lexicographicallyPrecedes($1) }
        let edgeRows = graph.edges.map { [$0.id, $0.source, $0.target] }
            .sorted { $0.lexicographicallyPrecedes($1) }
        let sourceDigest = Self.peerDigest(sharedText)
        let sourceID = sourceName.map { Self.peerDigest($0) } ?? "no-shared-source"
        let binding = PeerNativeBinding(sourceID: sourceID, sourceDigest: sourceDigest,
            generation: ticket.generation, placement: ticket.placement,
            source: ticket.source, selection: ticket.selection,
            lessonRevision: lessonRevision, nodes: nodeRows, edges: edgeRows,
            truncatedCount: graph.truncatedCount)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Every value is a bounded integer or string from the current projection.
        // An encoding failure produces an invalid digest which the worker rejects.
        let contextDigest = (try? encoder.encode(binding)).map(Self.peerDigest) ?? ""
        return PeerInspectionInput(graphID: "native-node-lab", sourceID: sourceID,
            sourceDigest: sourceDigest, contextDigest: contextDigest,
            nodes: nodeRows.map { PeerGraphNode(id: $0[0], kind: $0[1], status: $0[2]) },
            edges: edgeRows.map { PeerGraphEdge(id: $0[0], sourceID: $0[1], targetID: $0[2]) },
            truncatedCount: graph.truncatedCount)
    }

    func preparePeerInspection() {
        guard !isShuttingDown else { return }
        let input = peerInspectionInput()
        let now = peerInspectionTime()
        do {
            _ = try peerLab.inspection.prepare(input: input, now: now, permitDuration: 60)
            peerLab.lastDecision = nil
            peerLab.inspectedNodeCount = input.nodes.count
            peerLab.inspectedEdgeCount = input.edges.count
            peerLab.inspectedTruncatedCount = input.truncatedCount
            peerLab.inspectedSourceRevision = sourceRevision
            if peerLab.inspection.execute(now: now) != nil {
                peerLab.inspectionMessage = "Local inspection complete. Review the checks before accepting the session report."
            } else {
                peerLab.inspectionMessage = "The inspection did not produce an eligible report. Start a fresh inspection."
            }
        } catch {
            peerLab.inspectionMessage = "Inspection could not start: \(error.localizedDescription)"
        }
    }

    func admitPeerInspection() {
        guard !isShuttingDown else { return }
        let current = peerInspectionInput()
        let decision = peerLab.inspection.admit(currentContextDigest: current.contextDigest,
            now: peerInspectionTime())
        peerLab.lastDecision = decision
        peerLab.inspectionMessage = "\(decision.decision.rawValue) · \(decision.detail)"
    }

    func cancelPeerInspection(reason: String = "Inspection stopped.") {
        let hadCandidate = peerLab.inspection.candidate != nil
        guard peerLab.inspection.currentAttempt != nil else { return }
        let record = peerLab.inspection.cancel(now: peerInspectionTime())
        if hadCandidate {
            peerLab.lastDecision = record
            peerLab.inspectionMessage = reason
        }
    }

    func startPeerGossipExample() {
        guard !isShuttingDown else { return }
        var example = PeerGossipSimulation(seed: 42)
        example.start(now: 0)
        peerLab.simulation = example
        peerLab.simulationTime = 0
        peerLab.simulationMessage = "Offline example · four virtual workers · no network connection."
    }

    func stepPeerGossipExample() {
        guard !isShuttingDown else { return }
        guard var example = peerLab.simulation else {
            startPeerGossipExample()
            return
        }
        guard example.round < 32 else {
            peerLab.simulationMessage = "This example reached its 32-round limit. Start again to replay it."
            return
        }
        peerLab.simulationTime += 1
        example.step(now: peerLab.simulationTime)
        peerLab.simulation = example
    }

    private static func peerDigest(_ text: String) -> String { peerDigest(Data(text.utf8)) }
    private static func peerDigest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

private struct PeerNativeBinding: Encodable {
    let sourceID: String
    let sourceDigest: String
    let generation: UInt64
    let placement: UInt64
    let source: UInt64
    let selection: UInt64
    let lessonRevision: UInt64
    let nodes: [[String]]
    let edges: [[String]]
    let truncatedCount: Int
}

/// A representation reference addresses a specific artifact. The four views do
/// not imply physical equivalence, perception, or access to model activations.
@MainActor
struct CompanionPeerWorkspace: View {
    @ObservedObject var store: CompanionStore
    @State private var selectedPeerID = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Particles, Nodes, Neurons & Pixels").font(.title2)
                Text("Typed representations connected by explicit evidence. Peer messages carry observations; accepted results keep their existing owner.")
                    .foregroundStyle(.secondary)
                representationGuide
                Divider()
                inspectionSection
                Divider()
                gossipSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("node-lab.peers")
    }

    private var representationGuide: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), alignment: .topLeading)],
                  alignment: .leading, spacing: 12) {
            representation("Particles", symbol: "sparkles",
                detail: "Motion samples, emitters and simulation checkpoints.",
                scope: "A checkpoint describes one simulation state.")
            representation("Nodes", symbol: "point.3.connected.trianglepath.dotted",
                detail: "Named graph entities, relationships and proposed edits.",
                scope: "A drawn connection carries no permission.")
            representation("Neurons", symbol: "cpu",
                detail: "Model checkpoints and explicitly captured activations.",
                scope: "An activation needs a measured tensor reference.")
            representation("Pixels", symbol: "square.grid.3x3",
                detail: "Image frames and regions within their actual bounds.",
                scope: "An image reference does not establish visual understanding.")
        }
    }

    private func representation(_ title: String, symbol: String, detail: String, scope: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol).font(.headline)
                Text(detail)
                Text(scope).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var inspectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inspect this graph").font(.headline)
            Text("A local worker checks the current projection's record IDs and link endpoints. It receives no document text or lesson words.")
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { inspectionActions }
                VStack(alignment: .leading) { inspectionActions }
            }
            Text(store.peerLab.inspectionMessage)
                .accessibilityIdentifier("node-lab.peer-inspection-status")
            if let revision = store.peerLab.inspectedSourceRevision {
                Text("Latest inspection attempt · source revision \(revision) · \(store.peerLab.inspectedNodeCount) records · \(store.peerLab.inspectedEdgeCount) links")
                    .font(.callout).monospacedDigit()
                if store.peerLab.inspectedTruncatedCount > 0 {
                    Text("Projection is truncated: \(store.peerLab.inspectedTruncatedCount) items were omitted. This report covers the visible projection only.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            inspectionChecks
            Text("Accepted session reports: \(store.peerLab.inspection.reports.count). Acceptance does not save a lesson, edit a document, or change a model.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var inspectionActions: some View {
        Button("Inspect current graph") { store.preparePeerInspection() }
            .disabled(store.isShuttingDown)
            .accessibilityIdentifier("node-lab.peer-inspect")
        Button("Accept session report") { store.admitPeerInspection() }
            .disabled(store.isShuttingDown || store.peerLab.inspection.candidate == nil)
            .accessibilityIdentifier("node-lab.peer-admit")
        Button("Discard report") { store.cancelPeerInspection() }
            .disabled(store.peerLab.inspection.candidate == nil)
            .accessibilityIdentifier("node-lab.peer-stop")
    }

    @ViewBuilder
    private var inspectionChecks: some View {
        if let report = store.peerLab.inspection.candidate ?? store.peerLab.inspection.reports.last {
            Text(store.peerLab.inspection.candidate == nil ? "Last accepted session report" : "Candidate report")
                .font(.subheadline)
            Text("\(report.attemptID) · source digest \(report.sourceDigest.prefix(12))")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(report.scopeDescription).font(.caption).foregroundStyle(.secondary)
            ForEach(report.checks, id: \.id) { check in
                HStack(alignment: .firstTextBaseline) {
                    Text(check.status.rawValue).font(.system(.caption, design: .monospaced))
                        .frame(width: 68, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.id).font(.callout)
                        Text(check.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var gossipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How observations travel").font(.headline)
            Text(store.peerLab.simulationMessage).foregroundStyle(.secondary)
            HStack {
                Button(store.peerLab.simulation == nil ? "Start offline example" : "Replay example") {
                    store.startPeerGossipExample()
                }
                .disabled(store.isShuttingDown)
                .accessibilityIdentifier("node-lab.peer-example")
                Button("Next gossip round") { store.stepPeerGossipExample() }
                    .disabled(store.isShuttingDown || store.peerLab.simulation == nil || (store.peerLab.simulation?.round ?? 0) >= 32)
                    .accessibilityIdentifier("node-lab.peer-round")
            }
            if let example = store.peerLab.simulation {
                Text("Round \(example.round) · original evidence stays attached through every relay")
                    .font(.callout).monospacedDigit()
                ForEach(example.peerIDs, id: \.self) { peerID in
                    HStack(alignment: .firstTextBaseline) {
                        Label(peerID, systemImage: "desktopcomputer")
                        Spacer()
                        if let directory = example.directories[peerID] {
                            Text("\(directory.peers.count) worker records")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                gossipObservations(example)
                Text("The example uses fixture artifacts. It does not discover real devices, run inference, or inspect image content.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func gossipObservations(_ example: PeerGossipSimulation) -> some View {
        let selectedID = example.peerIDs.contains(selectedPeerID)
            ? selectedPeerID : (example.peerIDs.first ?? "")
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Inspect worker", selection: Binding(
                get: { selectedID }, set: { selectedPeerID = $0 })) {
                ForEach(example.peerIDs, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 420)
            .accessibilityIdentifier("node-lab.peer-selection")
            if let directory = example.directories[selectedID] {
                ForEach(directory.observationRecords) { record in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Object: \(record.observation.semanticObjectID)")
                            Text("Origin: \(record.observation.originPeerID) · event: \(record.observation.eventID)")
                            ForEach(record.observation.representations, id: \.self) { reference in
                                Text("\(reference.kind.title): \(reference.artifactID) · revision \(reference.revision)")
                            }
                            ForEach(record.observation.links) { link in
                                Text("\(link.from.kind.title) → \(link.to.kind.title) · \(link.relation.rawValue) · evidence: \(link.evidenceIDs.joined(separator: ", "))")
                            }
                            ForEach(record.observation.evidence) { evidence in
                                Text("Evidence \(evidence.id) · producer \(evidence.producerPeerID) · \(evidence.origin.rawValue)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("\(record.observation.originPeerID) · \(record.observation.status.rawValue) · \(record.isFresh(at: store.peerLab.simulationTime) ? "fresh report" : "expired report")")
                            .font(.callout)
                    }
                }
                if !directory.history.isEmpty {
                    Text("Recent deliveries").font(.subheadline)
                    ForEach(Array(directory.history.suffix(6))) { receipt in
                        Text("\(receipt.senderPeerID) · \(receipt.disposition.rawValue) · \(receipt.observationID)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Relaying the same observation preserves one source of evidence. Expiry means the report is stale; it does not prove that a worker failed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
