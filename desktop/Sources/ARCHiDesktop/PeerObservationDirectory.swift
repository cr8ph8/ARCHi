import Foundation

struct PeerDirectoryLimits: Equatable, Sendable {
    var maxPeers = 16
    var maxObservations = 128
    var maxDeliveries = 512
    var maxEvidenceRecords = 256
    var maxHistory = 96
    var maxRepresentationsPerObservation = 12
    var maxEvidencePerObservation = 24
    var maxLinksPerObservation = 24
    var maxPayloadBytes = 65_536
    var maxTTL: TimeInterval = 120

    var isValid: Bool {
        (1...256).contains(maxPeers) && (1...4_096).contains(maxObservations)
            && (1...16_384).contains(maxDeliveries) && (1...8_192).contains(maxEvidenceRecords)
            && (1...1_024).contains(maxHistory) && (1...64).contains(maxRepresentationsPerObservation)
            && (1...128).contains(maxEvidencePerObservation) && (1...128).contains(maxLinksPerObservation)
            && (256...1_048_576).contains(maxPayloadBytes) && maxTTL.isFinite && maxTTL > 0 && maxTTL <= 3_600
    }
}

struct PeerDirectoryEntry: Identifiable, Codable, Equatable, Sendable {
    let peerID: String
    var reportedStatus: PeerReportedStatus?
    var reportedObservationID: String?
    var reportSequence: UInt64?
    var reportedAt: TimeInterval?
    var reportExpiresAt: TimeInterval?
    var lastDirectContactAt: TimeInterval?
    var directContactExpiresAt: TimeInterval?

    var id: String { peerID }

    func reportIsFresh(at now: TimeInterval) -> Bool {
        guard PeerFieldValidation.time(now, after: reportedAt), let expiry = reportExpiresAt else { return false }
        return now < expiry
    }

    func directContactIsFresh(at now: TimeInterval) -> Bool {
        guard PeerFieldValidation.time(now, after: lastDirectContactAt), let expiry = directContactExpiresAt else { return false }
        return now < expiry
    }
}

struct PeerStoredObservation: Identifiable, Codable, Equatable, Sendable {
    let observation: PeerObservation
    let firstReceivedAt: TimeInterval
    let expiresAt: TimeInterval
    var id: PeerObservationIdentity { observation.id }

    func isFresh(at now: TimeInterval) -> Bool {
        PeerFieldValidation.time(now, after: firstReceivedAt) && now < expiresAt
    }
}

/// A bounded, session-scoped observation directory. It has no executor or network
/// dependency. Replay ledgers fail closed at capacity; TTL expiry never erases them.
struct PeerObservationDirectory: Sendable {
    let sessionID: String
    let localPeerID: String
    let allowedPeerIDs: Set<String>
    let allowedOrigins: Set<PeerDataOrigin>
    let limits: PeerDirectoryLimits
    private(set) var history: [PeerReceipt] = []
    private(set) var now: TimeInterval?
    private var entries: [String: PeerDirectoryEntry] = [:]
    private var deliveries: [DeliveryKey: PeerEnvelope] = [:]
    private var records: [OriginKey: PeerStoredObservation] = [:]
    private var events: [OriginKey: PeerObservation] = [:]
    private var sequences: [SequenceKey: PeerObservation] = [:]
    private var evidenceRecords: [OriginKey: PeerEvidenceReference] = [:]
    private var highestOriginSequences: [String: UInt64] = [:]
    private var receiptSequence: UInt64 = 0

    init(sessionID: String, localPeerID: String, allowedPeerIDs: Set<String>,
         limits: PeerDirectoryLimits = .init(), allowedOrigins: Set<PeerDataOrigin> = [.simulation]) {
        self.sessionID = sessionID
        self.localPeerID = localPeerID
        self.allowedPeerIDs = allowedPeerIDs
        self.limits = limits
        self.allowedOrigins = allowedOrigins
    }

    var peers: [PeerDirectoryEntry] { entries.values.sorted { $0.peerID < $1.peerID } }
    var observationRecords: [PeerStoredObservation] {
        records.values.sorted {
            if $0.observation.originPeerID != $1.observation.originPeerID { return $0.observation.originPeerID < $1.observation.originPeerID }
            return $0.observation.sequence < $1.observation.sequence
        }
    }
    var observations: [PeerObservation] { observationRecords.map(\.observation) }
    var deliveryCount: Int { deliveries.count }

    /// Expiry changes freshness only. Retained identities prevent TTL-based replay.
    @discardableResult
    mutating func expire(now proposedTime: TimeInterval) -> Bool {
        guard PeerFieldValidation.time(proposedTime, after: now) else { return false }
        now = proposedTime
        return true
    }

    @discardableResult
    mutating func receive(_ envelope: PeerEnvelope, now proposedTime: TimeInterval) -> PeerReceipt {
        guard PeerFieldValidation.time(proposedTime, after: now) else {
            return receipt(envelope, .invalidTime, "Local monotonic time must be finite, nonnegative and nondecreasing.", at: nil)
        }
        now = proposedTime
        guard configurationIsValid else {
            return receipt(envelope, .rejected, "The directory configuration is outside its bounded session scope.", at: proposedTime)
        }
        guard validScope(envelope) else {
            return receipt(envelope, .rejected, "Wrong protocol, session, recipient, peer or declared origin.", at: proposedTime)
        }
        guard PeerFieldValidation.identifier(envelope.deliveryID) else {
            return receipt(envelope, .rejected, "Malformed delivery identity.", at: proposedTime)
        }
        let deliveryKey = DeliveryKey(sender: envelope.senderPeerID, id: envelope.deliveryID)
        if let previous = deliveries[deliveryKey] {
            return receipt(envelope, previous == envelope ? .duplicateDelivery : .conflict,
                previous == envelope ? "Duplicate delivery; no freshness was renewed." : "A delivery ID was reused with a changed body.", at: proposedTime)
        }
        let observation = envelope.observation
        let observationKey = OriginKey(origin: observation.originPeerID, id: observation.observationID)
        let eventKey = OriginKey(origin: observation.originPeerID, id: observation.eventID)
        let sequenceKey = SequenceKey(origin: observation.originPeerID, sequence: observation.sequence)
        if let previous = records[observationKey], previous.observation != observation {
            return receipt(envelope, .conflict, "An observation ID was reused with a changed body.", at: proposedTime)
        }
        if let previous = events[eventKey], previous != observation {
            return receipt(envelope, .conflict, "An origin event ID was reused with a changed observation.", at: proposedTime)
        }
        if let previous = sequences[sequenceKey], previous != observation {
            return receipt(envelope, .conflict, "An origin sequence was reused with a changed observation.", at: proposedTime)
        }
        for evidence in observation.evidence {
            let key = OriginKey(origin: evidence.producerPeerID, id: evidence.id)
            if let previous = evidenceRecords[key], previous != evidence {
                return receipt(envelope, .conflict, "An evidence ID was reused with changed provenance or content.", at: proposedTime)
            }
        }
        guard validShape(envelope), let bytes = PeerCanonicalEncoding.data(envelope), bytes.count <= limits.maxPayloadBytes else {
            return receipt(envelope, .rejected, "Malformed or oversized typed observation.", at: proposedTime)
        }
        guard deliveries.count < limits.maxDeliveries else {
            return receipt(envelope, .capacity, "Delivery ledger is full; start a new session to receive more events.", at: proposedTime)
        }
        if records[observationKey] != nil {
            deliveries[deliveryKey] = envelope
            return receipt(envelope, .duplicateObservation, "A new delivery relayed an already retained observation; freshness was not renewed.", at: proposedTime)
        }
        let newEvidence = observation.evidence.filter {
            evidenceRecords[OriginKey(origin: $0.producerPeerID, id: $0.id)] == nil
        }
        guard records.count < limits.maxObservations,
              newEvidence.count <= limits.maxEvidenceRecords - evidenceRecords.count else {
            return receipt(envelope, .capacity, "Observation or evidence ledger is full; identities are retained to prevent replay.", at: proposedTime)
        }
        let involvedPeers = Set([envelope.senderPeerID, observation.originPeerID])
        var nextEntries = entries
        let missingCount = involvedPeers.filter { nextEntries[$0] == nil }.count
        if missingCount > limits.maxPeers - nextEntries.count {
            let expired = nextEntries.values.filter {
                !involvedPeers.contains($0.peerID) && !$0.reportIsFresh(at: proposedTime) && !$0.directContactIsFresh(at: proposedTime)
            }.sorted { $0.peerID < $1.peerID }
            for stale in expired where missingCount > limits.maxPeers - nextEntries.count {
                nextEntries.removeValue(forKey: stale.peerID)
            }
        }
        guard missingCount <= limits.maxPeers - nextEntries.count else {
            return receipt(envelope, .capacity, "Live peer directory is full; no live peer was displaced.", at: proposedTime)
        }
        let expiry = proposedTime + envelope.ttl
        guard expiry.isFinite else {
            return receipt(envelope, .rejected, "The local expiry is outside the supported clock range.", at: proposedTime)
        }
        for peerID in involvedPeers where nextEntries[peerID] == nil {
            nextEntries[peerID] = PeerDirectoryEntry(peerID: peerID)
        }
        var sender = nextEntries[envelope.senderPeerID]!
        sender.lastDirectContactAt = proposedTime
        sender.directContactExpiresAt = expiry
        nextEntries[envelope.senderPeerID] = sender
        var origin = nextEntries[observation.originPeerID]!
        if observation.sequence > (highestOriginSequences[observation.originPeerID] ?? 0) {
            origin.reportedStatus = observation.status
            origin.reportedObservationID = observation.observationID
            origin.reportSequence = observation.sequence
            origin.reportedAt = proposedTime
            origin.reportExpiresAt = expiry
            highestOriginSequences[observation.originPeerID] = observation.sequence
        }
        nextEntries[observation.originPeerID] = origin
        entries = nextEntries
        deliveries[deliveryKey] = envelope
        records[observationKey] = .init(observation: observation, firstReceivedAt: proposedTime, expiresAt: expiry)
        events[eventKey] = observation
        sequences[sequenceKey] = observation
        for evidence in newEvidence { evidenceRecords[OriginKey(origin: evidence.producerPeerID, id: evidence.id)] = evidence }
        return receipt(envelope, .accepted, "Typed observation retained. This receipt grants no execution authority.", at: proposedTime)
    }

    private var configurationIsValid: Bool {
        limits.isValid && PeerFieldValidation.identifier(sessionID) && PeerFieldValidation.identifier(localPeerID)
            && !allowedPeerIDs.isEmpty && allowedPeerIDs.count <= 256
            && allowedPeerIDs.allSatisfy(PeerFieldValidation.identifier) && allowedPeerIDs.contains(localPeerID)
            && !allowedOrigins.isEmpty
    }

    private func validScope(_ envelope: PeerEnvelope) -> Bool {
        envelope.protocolVersion == 1 && envelope.sessionID == sessionID && envelope.observation.sessionID == sessionID
            && envelope.recipientPeerID == localPeerID && allowedPeerIDs.contains(envelope.senderPeerID)
            && allowedPeerIDs.contains(envelope.observation.originPeerID) && allowedOrigins.contains(envelope.observation.origin)
            && envelope.observation.evidence.allSatisfy {
                allowedPeerIDs.contains($0.producerPeerID) && allowedOrigins.contains($0.origin)
                    && $0.origin == envelope.observation.origin
            }
    }

    private func validShape(_ envelope: PeerEnvelope) -> Bool {
        let observation = envelope.observation
        guard PeerFieldValidation.identifier(envelope.deliveryID),
              [observation.eventID, observation.observationID, observation.semanticObjectID].allSatisfy(PeerFieldValidation.identifier),
              observation.sequence > 0, envelope.ttl.isFinite, envelope.ttl > 0, envelope.ttl <= limits.maxTTL,
              !observation.representations.isEmpty, observation.representations.count <= limits.maxRepresentationsPerObservation,
              !observation.evidence.isEmpty, observation.evidence.count <= limits.maxEvidencePerObservation,
              observation.links.count <= limits.maxLinksPerObservation,
              observation.representations.allSatisfy({ $0.isWellFormed && $0.semanticObjectID == observation.semanticObjectID }),
              Set(observation.representations).count == observation.representations.count,
              observation.evidence.allSatisfy(\.isWellFormed),
              Set(observation.evidence.map(\.id)).count == observation.evidence.count,
              Set(observation.links.map(\.id)).count == observation.links.count else { return false }
        let evidenceIDs = Set(observation.evidence.map(\.id))
        return observation.links.allSatisfy { link in
            PeerFieldValidation.identifier(link.id) && !link.evidenceIDs.isEmpty
                && link.evidenceIDs.count <= limits.maxEvidencePerObservation
                && Set(link.evidenceIDs).count == link.evidenceIDs.count
                && link.evidenceIDs.allSatisfy { evidenceIDs.contains($0) }
                && observation.representations.contains(link.from) && observation.representations.contains(link.to)
                && (link.relation != .rendersTo || link.to.kind == .pixels)
                && (link.relation != .proposesEditTo || link.to.kind == .node)
        }
    }

    private mutating func receipt(_ envelope: PeerEnvelope, _ disposition: PeerReceiptDisposition,
                                  _ detail: String, at time: TimeInterval?) -> PeerReceipt {
        if receiptSequence < .max { receiptSequence += 1 }
        let value = PeerReceipt(id: receiptSequence, deliveryID: PeerFieldValidation.diagnosticID(envelope.deliveryID),
            observationID: PeerFieldValidation.diagnosticID(envelope.observation.observationID),
            senderPeerID: PeerFieldValidation.diagnosticID(envelope.senderPeerID), disposition: disposition, detail: detail, receivedAt: time)
        history.append(value)
        let maximum = min(1_024, max(1, limits.maxHistory))
        if history.count > maximum { history.removeFirst(history.count - maximum) }
        return value
    }

    private struct OriginKey: Hashable, Sendable { let origin: String; let id: String }
    private struct DeliveryKey: Hashable, Sendable { let sender: String; let id: String }
    private struct SequenceKey: Hashable, Sendable { let origin: String; let sequence: UInt64 }
}
