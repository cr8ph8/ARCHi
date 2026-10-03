import Foundation

/// A preference interview, not a personality test or an evolution award.
/// Reuses the user's existing PersonalContext entries and save boundary.
enum SeedDesignTest {
    struct Question: Identifiable, Equatable {
        let id: String
        let prompt: String
        let choices: [String]
        var contextTitle: String { "Seed design · \(id)" }
    }
    static let questions: [Question] = [
        .init(id: "color", prompt: "Which light would you enjoy living with?", choices: ["Green-blue", "Garnet", "Warm gold", "Violet", "Soft white", "Let me discover it"]),
        .init(id: "shape", prompt: "What should hold its core?", choices: ["Clear orb", "Open constellation", "Soft organic shell", "Faceted crystal", "Let me discover it"]),
        .init(id: "motion", prompt: "How much movement feels right?", choices: ["Still", "Gentle drift", "Playful pulses", "Let me discover it"]),
        .init(id: "detail", prompt: "Which details feel inviting?", choices: ["Connected points", "Optical petals", "Clean light", "Nature-like markings", "Let me discover it"]),
        .init(id: "purpose", prompt: "What should your companion help you practice?", choices: ["Creating", "Learning", "Getting things done", "Reflection", "Connecting with people", "Let me discover it"])
    ]
    static let source = "Your answers in ARCHi’s Seed design test. These are preferences, not personality measurements."
    static let unknown = "Let me discover it"

    struct Brief: Equatable {
        struct Decision: Equatable { let questionID: String; let choice: String; let reason: String }
        let decisions: [Decision]
        let unanswered: [String]
        var isReady: Bool { decisions.count >= 3 }
        var summary: String { decisions.map(\.choice).joined(separator: " · ") }
    }

    static func brief(answers: [String: String]) -> Brief? {
        guard Set(answers.keys).isSubset(of: Set(questions.map(\.id))),
              questions.allSatisfy({ question in answers[question.id].map { question.choices.contains($0) } ?? true }) else { return nil }
        return Brief(decisions: questions.compactMap { question in
            guard let value = answers[question.id], value != unknown else { return nil }
            return .init(questionID: question.id, choice: value, reason: "You chose this in: \(question.prompt)")
        }, unanswered: questions.filter { answers[$0.id] == nil || answers[$0.id] == unknown }.map(\.prompt))
    }

    static func answers(in context: PersonalContext?) -> [String: String] {
        guard let context, context.isValid else { return [:] }
        var result: [String: String] = [:]
        for question in questions {
            let matches = context.entries.filter { $0.title == question.contextTitle && $0.source == source && $0.status == .confirmed }
            if matches.count == 1, let entry = matches.first, question.choices.contains(entry.text) { result[question.id] = entry.text }
        }
        return result
    }

    static func keeping(answers: [String: String], in context: PersonalContext) -> PersonalContext? {
        guard context.isValid, let brief = brief(answers: answers), brief.isReady else { return nil }
        var updated = context
        let titles = Set(questions.map(\.contextTitle))
        updated.entries.removeAll { titles.contains($0.title) && $0.source == source }
        for question in questions {
            guard let value = answers[question.id] else { continue }
            updated.entries.append(.init(id: UUID().uuidString, title: question.contextTitle, text: value,
                status: .confirmed, source: source, useInAssistance: false))
        }
        return updated.isValid ? updated : nil
    }
}
