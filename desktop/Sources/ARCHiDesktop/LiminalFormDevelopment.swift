import Foundation
import simd

/// A rebuildable view of retained knowledge. There is no new progression save,
/// neural counter, or authority to mutate the qualified point asset here.
enum LiminalFormDevelopment {
    static let revision = "liminal-memory-structure/v1"
    static let maximumNodes = 64
    static let maximumVisibleNodes = 24

    /// These are evidence states, not truth scores or grades of intelligence.
    /// A retained/source-derived lesson becomes practiced only when the existing
    /// outcome owner supplies an exact, current, user-reviewed application.
    enum EvidenceState: String, Equatable, Sendable {
        case retainedKnowledge, reviewedApplication
    }
    struct Node: Equatable, Identifiable, Sendable {
        let id: String
        let lessonIDs: [String]
        let graphNodeIDs: [String]
        let title: String
        /// Bounded artistic input; it must not truncate the evidence history.
        let applications: Int
        let reviewedApplicationCount: Int
        let supportDigest: String?
        var evidenceState: EvidenceState { reviewedApplicationCount > 0 ? .reviewedApplication : .retainedKnowledge }

        init(id: String, lessonIDs: [String], graphNodeIDs: [String], title: String,
             applications: Int, reviewedApplicationCount: Int? = nil, supportDigest: String? = nil) {
            self.id = id; self.lessonIDs = lessonIDs; self.graphNodeIDs = graphNodeIDs; self.title = title
            self.applications = applications
            self.reviewedApplicationCount = reviewedApplicationCount ?? applications
            self.supportDigest = supportDigest
        }
    }
    struct Snapshot: Equatable, Sendable {
        let originDigest: String
        let nodes: [Node]
        let unavailableLessons: Int
        let duplicateLessons: Int
        let evidenceAvailable: Bool
        let unavailableKnowledgePages: Int
        let duplicateKnowledgePages: Int
        init(originDigest: String, nodes: [Node], unavailableLessons: Int, duplicateLessons: Int,
             evidenceAvailable: Bool, unavailableKnowledgePages: Int = 0, duplicateKnowledgePages: Int = 0) {
            self.originDigest = originDigest; self.nodes = nodes; self.unavailableLessons = unavailableLessons
            self.duplicateLessons = duplicateLessons; self.evidenceAvailable = evidenceAvailable
            self.unavailableKnowledgePages = unavailableKnowledgePages; self.duplicateKnowledgePages = duplicateKnowledgePages
        }
        var practicedNodes: Int { nodes.filter { $0.evidenceState == .reviewedApplication }.count }
        var retainedOnlyNodes: Int { nodes.count - practicedNodes }
        var reviewedApplicationCount: Int { nodes.reduce(0) { $0 + $1.reviewedApplicationCount } }
        /// Artistic construction limits, not intelligence or gameplay power.
        var availableDetail: Int {
            guard !nodes.isEmpty else { return 0 }
            if nodes.count >= 12 && practicedNodes >= 6 { return 4 }
            if nodes.count >= 6 && practicedNodes >= 3 { return 3 }
            if nodes.count >= 3 && practicedNodes >= 2 { return 2 }
            return 1
        }
        var visibleNodes: [Node] { Array(nodes.prefix(maximumVisibleNodes)) }
        var hiddenNodes: Int { max(0, nodes.count - maximumVisibleNodes) }
    }

    /// The caller must resolve pages through ReadingSourceLibrary.availability
    /// immediately before projection; this pure recipe cannot re-read its files.
    @MainActor static func build(originDigest: String, lessons: [KeptLesson], currentLessonIDs: Set<String>,
                      receipts: [EvolutionUsefulReceipt], evidenceOrigin: String?, now: Date,
                      currentKnowledgePages: [KnowledgePage] = []) -> Snapshot {
        let identityValid = LiminalKnowledgeBindings.isDigest(originDigest)
        let evidenceAvailable = identityValid && evidenceOrigin == originDigest
            && receipts.count <= EvolutionStore.maximumUsefulReceipts
        guard identityValid, now.timeIntervalSince1970.isFinite,
              lessons.count + currentKnowledgePages.count <= maximumNodes,
              Set(lessons.map(\.id)).count == lessons.count,
              Set(currentKnowledgePages.map { $0.id.lowercased() }).count == currentKnowledgePages.count else {
            return .init(originDigest: originDigest, nodes: [], unavailableLessons: lessons.count,
                         duplicateLessons: 0, evidenceAvailable: false,
                         unavailableKnowledgePages: currentKnowledgePages.count)
        }
        let current = lessons.filter {
            $0.isValid && currentLessonIDs.contains($0.id) && $0.createdAt <= now && $0.updatedAt <= now
                && ($0.expiresAt.map { $0 > now } ?? true)
        }
        // Rewording a title, changing case, or copying a lesson is not a new fact.
        // These are exact normalized duplicates only, not semantic equivalence.
        let groups = Dictionary(grouping: current, by: contentID)
        let pages = currentKnowledgePages.filter {
            $0.isValid && $0.state == .reviewed && $0.binding.isValid && $0.createdAt <= now && $0.updatedAt <= now
        }
        // Only reviewed semantic records enter here, never their raw source
        // copies. Identical untyped prose shares an anchor with an exact lesson.
        // People and encounters retain their own identities despite similar text.
        let pageGroups = Dictionary(grouping: pages, by: pageContentID)
        let byRequest = Dictionary(grouping: evidenceAvailable ? receipts : [], by: \.requestID)
        let admitted = evidenceAvailable ? byRequest.values.compactMap { copies -> EvolutionUsefulReceipt? in
            guard let first = copies.first, copies.allSatisfy({ $0 == first }),
                  first.hasValidEvidence, first.requestBinding?.isValid == true else { return nil }
            return first
        } : []
        let nodes = Set(groups.keys).union(pageGroups.keys).map { id -> Node in
            let ordered = (groups[id] ?? []).sorted { $0.id < $1.id }
            let orderedPages = (pageGroups[id] ?? []).sorted { $0.id < $1.id }
            var uses = Set<String>()
            var support = Set<String>()
            // Keep current source/revision provenance even before practical use.
            // The content ID stays stable when this same knowledge is reinforced.
            for record in ordered {
                if let reference = EvolutionLessonUse.make(snapshot: LessonSnapshot(lesson: record)) {
                    support.insert(evidenceKey(["lesson", reference.lessonID,
                                                String(reference.lessonRevision), reference.snapshotDigest]))
                }
            }
            for page in orderedPages {
                let binding = page.binding
                support.insert(evidenceKey(["reviewed-page", binding.id, String(binding.revision), binding.digest]))
            }
            for receipt in admitted {
                guard let use = receipt.lessonUse, let binding = receipt.requestBinding,
                      ordered.contains(where: {
                          use.matches(snapshot: LessonSnapshot(lesson: $0))
                              && ($0.source == nil || $0.source?.digest == receipt.sourceDigest)
                              // Producing a lesson is acquisition. It cannot also
                              // count as applying that lesson in the same request.
                              && UUID(uuidString: $0.origin?.requestID ?? "") != receipt.requestID
                      }) else { continue }
                // Retrying identical input with a different request UUID does not
                // multiply practice; exact current lesson revision is checked above.
                uses.insert(binding.inputDigest + ":" + (receipt.sourceDigest ?? "conversation"))
                support.insert(evidenceKey(["application", receipt.requestID.uuidString,
                    binding.inputDigest, binding.contextDigest, receipt.sourceDigest ?? "conversation",
                    use.lessonID, String(use.lessonRevision), use.snapshotDigest]))
            }
            return Node(id: id, lessonIDs: ordered.map(\.id),
                        graphNodeIDs: (ordered.map(CompanionGraph.lessonNodeID)
                            + orderedPages.map { KnowledgePageGraph.nodeID($0.binding) }).sorted(),
                        title: ordered.first?.topic ?? orderedPages[0].title,
                        applications: min(8, uses.count), reviewedApplicationCount: uses.count,
                        supportDigest: evidenceKey(["liminal-current-support/v2"] + support.sorted()))
        }.sorted { $0.id < $1.id }
        return .init(originDigest: originDigest, nodes: nodes, unavailableLessons: lessons.count - current.count,
                     duplicateLessons: current.count - groups.count, evidenceAvailable: evidenceAvailable,
                     unavailableKnowledgePages: currentKnowledgePages.count - pages.count,
                     duplicateKnowledgePages: pages.count - Set(pageGroups.keys).subtracting(groups.keys).count)
    }

    private static func evidenceKey(_ pieces: [String]) -> String {
        LiminalKnowledgeBindings.sha256(Data(pieces.map { "\($0.utf8.count):\($0)" }.joined().utf8))
    }

    private static func contentID(_ lesson: KeptLesson) -> String {
        contentID(lesson.text)
    }

    private static func pageContentID(_ page: KnowledgePage) -> String {
        if page.relationship != nil {
            return evidenceKey(["liminal-relationship-identity/v1", page.id.lowercased()])
        }
        return contentID(page.body)
    }

    private static func contentID(_ text: String) -> String {
        let normalized = text.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return LiminalKnowledgeBindings.sha256(Data((revision + ":" + normalized).utf8))
    }

    enum Form: String, CaseIterable, Identifiable {
        case seed, ball, beast
        var id: String { rawValue }
        var title: String {
            switch self { case .seed: "Seed"; case .ball: "Ball / Coin"; case .beast: "Beast" }
        }
    }
    struct Particle: Equatable, Identifiable {
        let id: String
        let nodeID: String
        let position: SIMD2<Double>
        let applications: Int
    }
    struct Thread: Equatable { let from: String; let to: String }
    struct Structure: Equatable {
        let form: Form
        let detail: Int
        let particles: [Particle]
        /// Construction threads are visual constraints, not asserted semantic links.
        let threads: [Thread]
        let core: SIMD2<Double>
    }

    enum ExportError: Error { case invalidIdentity, oversized }
    /// Explicit local authoring export. Record IDs describe private relationships
    /// even though no lesson text, titles, source paths or prompts are included.
    static func export(_ snapshot: Snapshot, form: Form, requestedDetail: Int, synthetic: Bool = false) throws -> Data {
        guard LiminalKnowledgeBindings.isDigest(snapshot.originDigest) else { throw ExportError.invalidIdentity }
        let shape = structure(snapshot, form: form, requestedDetail: requestedDetail)
        let object: [String: Any] = [
            "schema": "archi-liminal-structure-study/v1", "recipeVersion": revision,
            "originDigest": snapshot.originDigest, "synthetic": synthetic, "form": form.rawValue,
            "detail": shape.detail, "retainedNodeCount": snapshot.nodes.count,
            "representedNodeCount": shape.detail > 0 ? snapshot.visibleNodes.count : 0,
            "nodes": shape.detail > 0 ? snapshot.visibleNodes.map {
                ["id": $0.id, "graphNodeIDs": $0.graphNodeIDs, "applications": $0.applications] as [String: Any]
            } : [],
            "core": [shape.core.x, shape.core.y],
            "particles": shape.particles.map {
                ["id": $0.id, "nodeID": $0.nodeID, "position": [$0.position.x, $0.position.y], "applications": $0.applications] as [String: Any]
            },
            "threads": shape.threads.map { ["from": $0.from, "to": $0.to] }
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        guard data.count <= 262_144 else { throw ExportError.oversized }
        return data
    }

    static func structure(_ snapshot: Snapshot, form: Form, requestedDetail: Int) -> Structure {
        let detail = min(snapshot.availableDetail, max(0, requestedDetail))
        let core = form == .beast ? SIMD2<Double>(0.38, 0.53) : SIMD2<Double>(0.5, 0.5)
        guard detail > 0 else { return .init(form: form, detail: 0, particles: [], threads: [], core: core) }
        let samples = [0, 1, 6, 10, 14][detail]
        var particles: [Particle] = [], threads: [Thread] = []
        for node in snapshot.visibleNodes {
            // Position depends on persistent content identity, never array order,
            // frame rate, render resolution, or the number of other nodes.
            let seed = Double(UInt32(node.id.prefix(8), radix: 16) ?? 0) / Double(UInt32.max)
            let phase = seed * 2 * Double.pi
            let anchor = anchor(form: form, phase: phase)
            let radius = 0.017 + Double(detail - 1) * 0.007
            for index in 0..<samples {
                let angle = phase + Double(index) * 2 * .pi / Double(samples)
                let offset = samples == 1 ? SIMD2<Double>.zero : SIMD2(cos(angle), sin(angle)) * radius
                let particle = Particle(id: node.id + ":" + String(index), nodeID: node.id,
                                        position: anchor + offset, applications: node.applications)
                particles.append(particle)
                if index > 0 { threads.append(.init(from: node.id + ":" + String(index - 1), to: particle.id)) }
            }
            if samples > 1 { threads.append(.init(from: node.id + ":" + String(samples - 1), to: node.id + ":0")) }
        }
        return .init(form: form, detail: detail, particles: particles, threads: threads, core: core)
    }

    private static func anchor(form: Form, phase: Double) -> SIMD2<Double> {
        switch form {
        case .seed:
            return SIMD2(0.5 + 0.25 * cos(phase), 0.5 + 0.25 * sin(phase))
        case .ball:
            let radius = 0.22 + 0.06 * cos(phase * 3)
            return SIMD2(0.5 + radius * cos(phase), 0.5 + radius * sin(phase))
        case .beast:
            // Authored side silhouette: mane, shoulder, back, hindquarters and paws.
            let contour: [SIMD2<Double>] = [SIMD2(0.2,0.3), SIMD2(0.32,0.18), SIMD2(0.45,0.3),
                SIMD2(0.65,0.35), SIMD2(0.81,0.43), SIMD2(0.85,0.7), SIMD2(0.74,0.76),
                SIMD2(0.69,0.58), SIMD2(0.47,0.6), SIMD2(0.42,0.79), SIMD2(0.3,0.79),
                SIMD2(0.32,0.58), SIMD2(0.18,0.46)]
            let slot = phase / (2 * .pi) * Double(contour.count)
            let index = Int(slot) % contour.count
            return contour[index] + (contour[(index + 1) % contour.count] - contour[index]) * (slot - floor(slot))
        }
    }

    static func guide(form: Form) -> [SIMD2<Double>] {
        (0...120).map { anchor(form: form, phase: Double($0) / 120 * 2 * .pi) }
    }

    /// Analytic critically damped response in normalized image coordinates.
    /// It is time-step independent and bounded by 0.035; it never changes records.
    static func displaced(_ particle: Particle, elapsed: Double, reducedMotion: Bool, stopped: Bool) -> SIMD2<Double> {
        guard !reducedMotion, !stopped, elapsed.isFinite, elapsed >= 0 else { return particle.position }
        let rate = 5 + Double(min(8, max(0, particle.applications))) * 0.35
        let t = min(10, elapsed)
        let decay = (1 + rate * t) * exp(-rate * t)
        let value = Double(UInt32(particle.nodeID.suffix(8), radix: 16) ?? 0) / Double(UInt32.max)
        let direction = SIMD2(cos(value * 2 * .pi), sin(value * 2 * .pi))
        return particle.position + direction * (0.035 * decay)
    }
}
