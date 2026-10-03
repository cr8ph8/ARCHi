import XCTest
@testable import ARCHiDesktop

final class KnowledgeParticleFieldTests: XCTestCase {
    private func node(_ id: String, _ kind: CompanionGraphKind = .knowledge) -> CompanionGraphNode {
        .init(id: id, title: "Private title", subtitle: "Private subtitle", kind: kind,
            status: "Private status", details: [.init(label: "Your note", value: "Private body")], target: .memory)
    }

    func testStableIdentityAndLayoutIgnoreInputOrderAndRejectPhantomEdges() {
        let nodes = [node("root", .companion), node("b"), node("a", .source)]
        let edges = [CompanionGraphEdge(id: "ab", source: "a", target: "b", label: "source passage"),
                     .init(id: "bad", source: "absent", target: "b", label: "never drawn")]
        let first = KnowledgeParticleField(snapshot: .init(nodes: nodes, edges: edges, truncatedCount: 0))
        let second = KnowledgeParticleField(snapshot: .init(nodes: nodes.reversed(), edges: edges.reversed(), truncatedCount: 0))
        XCTAssertEqual(first.particles, second.particles)
        XCTAssertEqual(Set(first.particles.map(\.nodeID)), Set(nodes.map(\.id)))
        XCTAssertEqual(first.edges.map(\.id), ["ab"])
    }

    func testTopologyIgnoresPresentationChangesButTracksFieldInputs() {
        let edges = [CompanionGraphEdge(id: "ab", source: "a", target: "b", label: "source passage")]
        let original = CompanionGraphSnapshot(nodes: [node("a", .source), node("b")], edges: edges, truncatedCount: 2)
        let renamed = CompanionGraphNode(id: "a", title: "Edited title", subtitle: "Edited subtitle", kind: .source,
            status: "New status", details: [], target: .assistant)
        let updated = CompanionGraphSnapshot(nodes: [node("b"), renamed], edges: edges, truncatedCount: 2)
        let topology = KnowledgeParticleField.topology(of: original)
        XCTAssertEqual(topology, KnowledgeParticleField.topology(of: updated))
        XCTAssertEqual(KnowledgeParticleField(topology: topology).particles,
            KnowledgeParticleField(snapshot: original).particles)
        XCTAssertNotEqual(topology, KnowledgeParticleField.topology(of:
            .init(nodes: [node("a", .lesson), node("b")], edges: edges, truncatedCount: 2)))
        XCTAssertNotEqual(topology, KnowledgeParticleField.topology(of:
            .init(nodes: original.nodes, edges: [.init(id: "ab", source: "b", target: "a", label: "source passage")], truncatedCount: 2)))
        XCTAssertNotEqual(topology, KnowledgeParticleField.topology(of:
            .init(nodes: original.nodes, edges: [.init(id: "ab", source: "a", target: "b", label: "revised relation")], truncatedCount: 2)))
        XCTAssertNotEqual(topology, KnowledgeParticleField.topology(of:
            .init(nodes: original.nodes, edges: edges, truncatedCount: 3)))
    }

    func testFramingAllParticlesPreservesMarginAcrossMotion() {
        let field = KnowledgeParticleField(snapshot: .init(nodes: [node("root", .companion), node("a"), node("b", .source)],
            edges: [], truncatedCount: 0))
        for spread in [0.0, 0.4, 1.0] {
            for reduceMotion in [false, true] {
                let frame = KnowledgeParticleField.framing(particles: field.particles,
                    spread: spread, reduceMotion: reduceMotion)
                XCTAssertTrue(frame.center.x.isFinite && frame.center.y.isFinite)
                XCTAssertGreaterThanOrEqual(frame.halfExtent, 0.24)
                for particle in field.particles {
                    let point = frame.normalize(KnowledgeParticleField.position(particle, spread: spread, reduceMotion: reduceMotion))
                    XCTAssertLessThanOrEqual(abs(point.x), 0.72)
                    XCTAssertLessThanOrEqual(abs(point.y), 0.72)
                }
                XCTAssertEqual(frame, KnowledgeParticleField.framing(particles: field.particles.reversed(),
                    spread: spread, reduceMotion: reduceMotion))
            }
        }
    }

    func testFocusFramingUsesStableIDsAndIgnoresUnrelatedParticles() {
        let particles: [KnowledgeParticleField.Particle] = [
            .init(nodeID: "a", kind: .knowledge, orb: .zero, constellation: .init(x: 0.10, y: 0.10), phase: 0),
            .init(nodeID: "b", kind: .source, orb: .zero, constellation: .init(x: 0.20, y: 0.30), phase: 0),
            .init(nodeID: "outside", kind: .lesson, orb: .zero, constellation: .init(x: -0.80, y: -0.70), phase: 0)
        ]
        let focusIDs: Set<String> = ["a", "b"]
        let frame = KnowledgeParticleField.framing(particles: particles, spread: 1, reduceMotion: true, focusIDs: focusIDs)
        let whole = KnowledgeParticleField.framing(particles: particles, spread: 1, reduceMotion: true)
        XCTAssertLessThan(frame.halfExtent, whole.halfExtent)
        XCTAssertEqual(frame.center.x, 0.15, accuracy: 1e-12)
        XCTAssertEqual(frame.center.y, 0.20, accuracy: 1e-12)
        XCTAssertEqual(frame, KnowledgeParticleField.framing(particles: Array(particles.prefix(2)).reversed(),
            spread: 1, reduceMotion: true, focusIDs: focusIDs))
        // A search may hide b, but the caller retains the unfiltered focus IDs
        // and full field, so a stays at the same normalized point.
        let searchedVisibleIDs: Set<String> = ["a"]
        let searchFrame = KnowledgeParticleField.framing(particles: particles,
            spread: 1, reduceMotion: true, focusIDs: focusIDs)
        let visible = particles.filter { searchedVisibleIDs.contains($0.nodeID) }
        XCTAssertEqual(searchFrame, frame)
        XCTAssertEqual(visible.map { searchFrame.normalize($0.constellation) },
            [frame.normalize(particles[0].constellation)])
        for particle in particles where focusIDs.contains(particle.nodeID) {
            let point = frame.normalize(particle.constellation)
            XCTAssertLessThanOrEqual(abs(point.x), 0.72)
            XCTAssertLessThanOrEqual(abs(point.y), 0.72)
        }
    }

    func testFramingHandlesEmptyUnknownAndNonfiniteInputs() {
        let empty = KnowledgeParticleField.framing(particles: [], spread: .nan, reduceMotion: false)
        XCTAssertEqual(empty.center, .zero)
        XCTAssertEqual(empty.halfExtent, 1)
        XCTAssertEqual(empty.normalize(.init(x: .infinity, y: .nan)), .zero)
        let invalid = KnowledgeParticleField.Particle(nodeID: "invalid", kind: .knowledge,
            orb: .init(x: .nan, y: 0), constellation: .init(x: .infinity, y: 0), phase: .nan)
        XCTAssertEqual(empty, KnowledgeParticleField.framing(particles: [invalid], spread: 1, reduceMotion: true))
        let huge = KnowledgeParticleField.Particle(nodeID: "huge", kind: .knowledge,
            orb: .zero, constellation: .init(x: 1e300, y: -1e300), phase: 0)
        let safe = KnowledgeParticleField.framing(particles: [huge], spread: .nan, reduceMotion: false)
        XCTAssertTrue(safe.center.x.isFinite && safe.center.y.isFinite && safe.halfExtent.isFinite)
        XCTAssertEqual(safe.normalize(huge.constellation), .zero)
        XCTAssertEqual(empty, KnowledgeParticleField.framing(particles: [huge], spread: 1,
            reduceMotion: true, focusIDs: ["missing"]))
        XCTAssertEqual(safe, KnowledgeParticleField.framing(particles: [huge], spread: 2, reduceMotion: false))
    }

    func testEndpointExactAndBoundedCurlForDenseSnapshot() {
        let field = KnowledgeParticleField(snapshot: .init(nodes: (0..<220).map { node("node-\($0)") }, edges: [], truncatedCount: 0))
        for p in field.particles {
            XCTAssertEqual(KnowledgeParticleField.position(p, spread: 0, reduceMotion: false), p.orb)
            XCTAssertEqual(KnowledgeParticleField.position(p, spread: 1, reduceMotion: false), p.constellation)
            for t in [0.01, 0.25, 0.5, 0.75, 0.99] {
                let straight = p.orb * (1-t) + p.constellation * t
                let limit = min(0.065, 0.16 * (p.constellation - p.orb).length)
                let actual = KnowledgeParticleField.position(p, spread: t, reduceMotion: false)
                XCTAssertLessThanOrEqual((actual - straight).length, limit + 1e-12)
                XCTAssertLessThanOrEqual(actual.length, 0.93)
                XCTAssertEqual(KnowledgeParticleField.position(p, spread: t, reduceMotion: true), straight)
            }
            XCTAssertEqual(KnowledgeParticleField.position(p, spread: .nan, reduceMotion: false), p.constellation)
        }
    }

    func testCapsAndExportPreserveIDsWithoutPrivateContents() throws {
        let nodes = (0..<230).map { node("node-\($0)") }
        let field = KnowledgeParticleField(snapshot: .init(nodes: nodes, edges: [], truncatedCount: 7))
        XCTAssertEqual(field.particles.count, 220)
        XCTAssertEqual(field.omittedCount, 17)
        let data = try KnowledgeParticleExport(field: field).data()
        let decoded = try JSONDecoder().decode(KnowledgeParticleExport.self, from: data)
        XCTAssertEqual(decoded.nodes.map(\.nodeID), field.particles.map(\.nodeID))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Private"))
        XCTAssertEqual(decoded.schema, "archi-knowledge-particles/v1")
    }

    func testExportFixtureForHoudiniAdapter() throws {
        let graph = CompanionGraphSnapshot(nodes: [node("root", .companion), node("source", .source), node("concept")],
            edges: [.init(id: "link-1", source: "concept", target: "source", label: "source passage")], truncatedCount: 0)
        let data = try KnowledgeParticleExport(field: KnowledgeParticleField(snapshot: graph)).data()
        let path = ProcessInfo.processInfo.environment["ARCHI_PARTICLE_EXPORT_FIXTURE"]
        if let path { try data.write(to: URL(fileURLWithPath: path)) }
        XCTAssertEqual(try JSONDecoder().decode(KnowledgeParticleExport.self, from: data).nodes.count, 3)
    }
}
