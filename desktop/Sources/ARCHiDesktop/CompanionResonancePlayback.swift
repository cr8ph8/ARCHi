import AppKit
import Foundation

/// A disposable, explicit audition of one current record. This request never
/// enters a profile, memory, outcome journal or model payload.
struct CompanionResonancePlaybackRequest: Equatable, Sendable {
    enum Scope: Equatable, Sendable { case memory, activity }

    let id: UUID
    let originDigest: String
    let graphDigest: String
    let nodeID: String
    let kind: CompanionGraphKind
    let scope: Scope
}

/// Admission is checked when requested and again by the existing audio owner.
/// Identical record IDs in another profile or revision do not preserve a sound.
struct CompanionResonancePlaybackContext: Equatable, Sendable {
    let originDigest: String?
    let graphDigest: String?
    let selectedNodeID: String?
    let selectedNodeKind: CompanionGraphKind?
    let enabled: Bool
    let quiet: Bool
    let visible: Bool
    let inMemoryMap: Bool

    func permits(_ request: CompanionResonancePlaybackRequest) -> Bool {
        enabled && !quiet && visible && inMemoryMap
            && originDigest == request.originDigest && graphDigest == request.graphDigest
            && selectedNodeID == request.nodeID && selectedNodeKind == request.kind
            && LiminalKnowledgeBindings.isDigest(request.originDigest)
            && LiminalKnowledgeBindings.isDigest(request.graphDigest)
    }
}

enum CompanionResonancePlaybackDecision: Equatable, Sendable {
    case none, stop
    case play(CompanionResonancePlaybackRequest)
}

/// Requests observed while sound is unavailable are consumed, never queued for
/// a later preference change. One newer request replaces the current audition.
struct CompanionResonancePlaybackGate: Sendable {
    private var lastRequestID: UUID?
    private var activeRequest: CompanionResonancePlaybackRequest?

    mutating func update(request: CompanionResonancePlaybackRequest?,
                         context: CompanionResonancePlaybackContext?) -> CompanionResonancePlaybackDecision {
        let isNew = request != nil && request?.id != lastRequestID
        if let request { lastRequestID = request.id }
        if isNew, let request, context?.permits(request) == true {
            activeRequest = request
            return .play(request)
        }
        if let activeRequest,
           request != activeRequest || context?.permits(activeRequest) != true {
            self.activeRequest = nil
            return .stop
        }
        return .none
    }

    mutating func finish(_ id: UUID) {
        if activeRequest?.id == id { activeRequest = nil }
    }
}

@MainActor extension CompanionStore {
    func canPreviewResonance(nodeID: String, in graph: CompanionGraphSnapshot,
                             particleScene: CompanionParticleScene?, capturedOriginDigest: String?) -> Bool {
        resonanceRequest(nodeID: nodeID, graph: graph, particleScene: particleScene,
                         capturedOriginDigest: capturedOriginDigest) != nil
    }

    @discardableResult
    func previewResonance(nodeID: String, in graph: CompanionGraphSnapshot,
                          particleScene: CompanionParticleScene?, capturedOriginDigest: String?) -> Bool {
        guard let request = resonanceRequest(nodeID: nodeID, graph: graph, particleScene: particleScene,
                                              capturedOriginDigest: capturedOriginDigest) else {
            return false
        }
        stopKinLightPreview()
        stopHarmonyTheme()
        resonancePlaybackRequest = request
        return true
    }

    func stopResonancePlayback() {
        if resonancePlaybackRequest != nil { resonancePlaybackRequest = nil }
    }

    func resonancePlaybackContext(for request: CompanionResonancePlaybackRequest,
                                   visible: Bool) -> CompanionResonancePlaybackContext {
        let scene = companionParticleScene()
        let graph = request.scope == .memory ? scene?.graph : companionGraphSnapshot()
        let node = graph?.nodes.first { $0.id == selectedGraphNodeID }
        return .init(originDigest: scene?.originDigest,
            graphDigest: graph.map(LiminalKnowledgeBindings.digest),
            selectedNodeID: node?.id, selectedNodeKind: node?.kind,
            enabled: preferences.musicalCues && preferences.musicalVolume.isFinite
                && preferences.musicalVolume > 0,
            quiet: preferences.quiet,
            visible: visible && isVisible && !isShuttingDown && activeQiMon != nil
                && profileRecoveryBlock == nil,
            inMemoryMap: section == .nodeLab)
    }

    private func resonanceRequest(nodeID: String, graph: CompanionGraphSnapshot,
                                  particleScene: CompanionParticleScene?, capturedOriginDigest: String?) -> CompanionResonancePlaybackRequest? {
        guard let current = companionParticleScene(),
              capturedOriginDigest == current.originDigest,
              let node = graph.nodes.first(where: { $0.id == nodeID }) else { return nil }
        if let particleScene,
           !particleScene.isCurrent(graph: current.graph, originDigest: current.originDigest, sessionID: current.sessionID) { return nil }
        let request = CompanionResonancePlaybackRequest(id: UUID(), originDigest: current.originDigest,
            graphDigest: LiminalKnowledgeBindings.digest(graph), nodeID: node.id, kind: node.kind,
            scope: particleScene == nil ? .activity : .memory)
        guard resonancePlaybackContext(for: request, visible: !(NSApp?.isHidden ?? false)).permits(request) else {
            return nil
        }
        return request
    }
}
