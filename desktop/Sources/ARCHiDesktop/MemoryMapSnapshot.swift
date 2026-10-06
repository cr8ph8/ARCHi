import Foundation

/// The memory surface projects retained sources, authored pages and kept lessons.
/// Request activity, evaluation fixtures and usage accounting remain in the full
/// activity map. Both surfaces reuse the same record IDs and inspection targets.
@MainActor
enum MemoryMapSnapshot {
    static func build(library: ReadingSourceLibrary, lessons: [KeptLesson],
                      at date: Date = Date()) -> CompanionGraphSnapshot {
        let base = CompanionGraph.build(receipts: [], lessons: lessons, source: nil, now: date)
        return KnowledgePageGraph.append(to: base, library: library)
    }
}
