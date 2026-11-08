import Foundation

struct PeerSimulationDelivery: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let round: Int
    let senderPeerID: String
    let recipientPeerID: String
    let originPeerID: String
    let observationID: String
    let eventID: String
    let evidenceIDs: [String]
    let receipt: PeerReceipt
}

/// A closed transport exercise, not a LAN connector. All four peers, artifacts,
/// deliveries and elapsed-time values are in process and explicitly simulated.
/// One seed and the same time inputs produce the same fanout and receipts.
struct PeerGossipSimulation: Sendable {
    let seed: UInt64
    let sessionID: String
    let peerIDs = ["peer-particles", "peer-nodes", "peer-neurons", "peer-pixels"]
    let fixtureObservations: [PeerObservation]
    let fanout = 2
    let maximumRounds = 32
    let observationTTL: TimeInterval = 6
    private(set) var directories: [String: PeerObservationDirectory] = [:]
    private(set) var round = 0
    private(set) var now: TimeInterval?
    private(set) var lastRoundDeliveries: [PeerSimulationDelivery] = []
    private(set) var history: [PeerSimulationDelivery] = []
    private(set) var lastError: String?

    init(seed: UInt64 = 42) {
        self.seed = seed
        self.sessionID = "offline-simulation-\(seed)"
        self.fixtureObservations = Self.fixtures(sessionID: "offline-simulation-\(seed)")
    }

    @discardableResult
    mutating func start(now proposedTime: TimeInterval) -> Bool {
        guard now == nil else {
            lastError = "This example already started; create a new simulation to replay it."
            return false
        }
        guard PeerFieldValidation.time(proposedTime, after: nil), (proposedTime + observationTTL).isFinite else {
            lastError = "Simulation time must be finite and nonnegative."
            return false
        }
        now = proposedTime
        let peers = Set(peerIDs)
        for peerID in peerIDs {
            directories[peerID] = .init(sessionID: sessionID, localPeerID: peerID, allowedPeerIDs: peers)
        }
        lastRoundDeliveries = []
        for observation in fixtureObservations {
            let envelope = PeerEnvelope(sessionID: sessionID, deliveryID: "seed-\(observation.originPeerID)",
                senderPeerID: observation.originPeerID, recipientPeerID: observation.originPeerID,
                observation: observation, ttl: observationTTL)
            deliver(envelope, at: proposedTime)
        }
        lastError = nil
        return true
    }

    /// Uses a snapshot of the previous round, so iteration order cannot cause
    /// hidden same-round propagation. Only locally fresh observations are relayed.
    @discardableResult
    mutating func step(now proposedTime: TimeInterval) -> Bool {
        guard let previousTime = now else {
            lastError = "Start the offline example before advancing a round."
            return false
        }
        guard PeerFieldValidation.time(proposedTime, after: previousTime),
              (proposedTime + observationTTL).isFinite else {
            lastError = "Simulation time must be finite, nonnegative and nondecreasing."
            return false
        }
        guard round < maximumRounds else {
            lastError = "This example reached its bounded round limit; start a new example to replay it."
            return false
        }
        now = proposedTime
        round += 1
        lastRoundDeliveries = []
        let previousDirectories = directories
        for peerID in peerIDs { _ = directories[peerID]?.expire(now: proposedTime) }
        var firstDelivery: PeerEnvelope?
        for (senderIndex, sender) in peerIDs.enumerated() {
            guard let previous = previousDirectories[sender] else { continue }
            let records = previous.observationRecords.filter { $0.isFresh(at: proposedTime) }
            let others = peerIDs.filter { $0 != sender }
            let offset = (Int(seed % UInt64(others.count)) + round + senderIndex) % others.count
            let recipients = (0..<fanout).map { others[(offset + $0) % others.count] }
            for recipient in recipients {
                for record in records {
                    let observation = record.observation
                    let envelope = PeerEnvelope(sessionID: sessionID,
                        deliveryID: "round-\(round)-\(sender)-to-\(recipient)-\(observation.originPeerID)-\(observation.sequence)",
                        senderPeerID: sender, recipientPeerID: recipient, observation: observation, ttl: observationTTL)
                    if firstDelivery == nil { firstDelivery = envelope }
                    deliver(envelope, at: proposedTime)
                }
            }
        }
        // Exercise transport deduplication with the identical envelope, separately
        // from the new delivery IDs carrying already known observations above.
        if let firstDelivery { deliver(firstDelivery, at: proposedTime) }
        lastError = nil
        return true
    }

    private mutating func deliver(_ envelope: PeerEnvelope, at time: TimeInterval) {
        guard var directory = directories[envelope.recipientPeerID] else { return }
        let receipt = directory.receive(envelope, now: time)
        directories[envelope.recipientPeerID] = directory
        let value = PeerSimulationDelivery(id: "\(round):\(envelope.recipientPeerID):\(receipt.id)", round: round,
            senderPeerID: envelope.senderPeerID, recipientPeerID: envelope.recipientPeerID,
            originPeerID: envelope.observation.originPeerID, observationID: envelope.observation.observationID,
            eventID: envelope.observation.eventID, evidenceIDs: envelope.observation.evidence.map(\.id), receipt: receipt)
        lastRoundDeliveries.append(value)
        history.append(value)
        if history.count > 128 { history.removeFirst(history.count - 128) }
    }

    private static func fixtures(sessionID: String) -> [PeerObservation] {
        let objectID = "fixture-orbit-object"
        func object(_ artifact: String) -> RepresentationObjectReference {
            .init(semanticObjectID: objectID, artifactID: artifact, revision: "fixture-v1")
        }
        let particle = RepresentationReference.particles(.init(object: object("fixture-particle-checkpoint"),
            emitterID: "fixture-orbit-emitter", checkpointID: "fixture-t0"))
        let node = RepresentationReference.node(.init(object: object("fixture-semantic-node"),
            graphID: "fixture-graph", nodeID: "fixture-orbit-node"))
        let neural = RepresentationReference.neural(.init(object: object("fixture-model-checkpoint"),
            modelID: "fixture-model", checkpointID: "fixture-checkpoint"))
        let pixel = RepresentationReference.pixels(.init(object: object("fixture-pixel-frame"),
            frameIndex: 0, frameWidth: 64, frameHeight: 64, region: .init(x: 16, y: 16, width: 32, height: 32)))
        // SHA-256 references to the corresponding fixed manifest strings
        // "ARCHi offline fixture <name> v1". They are fixture provenance, not
        // evidence that a real renderer, model or capture ran in this application.
        let specifications: [(String, String, String, [RepresentationReference], RepresentationEvidenceLink.Relation)] = [
            ("peer-particles", "particle-render", "9d010ed23cd1d3864861e240f3144ad9e22f2b001c4c489faf2a661bbfd06ac9", [particle, pixel], .rendersTo),
            ("peer-nodes", "node-annotation", "9d4fbf6d8147368b3e5f40f2fd0c2b4bd9249012a436075ed233b3a345a07f0d", [node, particle], .annotates),
            ("peer-neurons", "neural-checkpoint-annotation", "0ac279f54e80ff05875ed093f61a3d25f7c9b7084e7b3ce34e90cdc8d6c05666", [node, neural], .annotates),
            ("peer-pixels", "pixel-annotation", "068171ddfd5b39302f7ee76e929364786099ba3de446b24108dd2fd074dfa352", [node, pixel], .annotates)
        ]
        return specifications.map { peerID, name, digest, representations, relation in
            let evidence = PeerEvidenceReference(id: "fixture-evidence-\(name)", artifactID: "fixture-manifest-\(name)",
                revision: "fixture-v1", contentDigest: digest, producerPeerID: peerID, origin: .simulation)
            let link = RepresentationEvidenceLink(id: "fixture-link-\(name)", from: representations[0], to: representations[1],
                relation: relation, evidenceIDs: [evidence.id])
            return PeerObservation(sessionID: sessionID, originPeerID: peerID, eventID: "fixture-event-\(name)",
                observationID: "fixture-observation-\(name)", sequence: 1, semanticObjectID: objectID, origin: .simulation,
                status: .ready, representations: representations, evidence: [evidence], links: [link])
        }
    }
}
