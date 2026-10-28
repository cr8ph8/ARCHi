import SwiftUI

@MainActor
struct DocumentMethodMemoryInfluenceSummary: View {
    @ObservedObject var store: CompanionStore
    let procedure: DocumentProcedure

    var body: some View {
        if let evaluation = store.documentMethodMemoryInfluence(procedure), !evaluation.rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Memory influence \(evaluation.influence.formatted(.number.precision(.fractionLength(3)))) · \(evaluation.assessedCount) assessed")
                Text("Attraction \(evaluation.positiveMass.formatted(.number.precision(.fractionLength(3)))) · Detraction \(evaluation.negativeMass.formatted(.number.precision(.fractionLength(3)))) · Neutral \(evaluation.neutralMass.formatted(.number.precision(.fractionLength(3))))")
                if evaluation.hasOpposingEvidence { Text("Opposing assessments remain visible.") }
                Button("Inspect memory relationships") { store.open(.memory) }.buttonStyle(.borderless)
            }
            .font(.caption2).foregroundStyle(.secondary)
            .accessibilityIdentifier("document.method-memory-influence.\(procedure.id).\(procedure.revision)")
        }
    }
}

@MainActor
struct LessonMemoryInfluenceControls: View {
    @ObservedObject var store: CompanionStore
    let lesson: KeptLesson
    @State private var editSession: EditSession?

    private struct EditSession: Identifiable {
        let id = UUID()
        let lesson: LessonSnapshot
        let preferenceRevision: UInt64
        let relations: [LessonMemoryInfluence]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Attraction / detraction").font(.caption.weight(.medium))
            Text("\(store.memoryInfluences(for: LessonSnapshot(lesson: lesson)).count) saved method relationships. A caution remains retrievable while discouraging a method.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("Edit method influence…") {
                editSession = EditSession(lesson: LessonSnapshot(lesson: lesson),
                    preferenceRevision: store.lessonRevision,
                    relations: store.memoryInfluences(for: LessonSnapshot(lesson: lesson)))
            }
            .disabled(store.currentKeptLesson(matching: LessonSnapshot(lesson: lesson)) == nil)
            .accessibilityIdentifier("memory-influence.edit.\(lesson.id)")
        }
        .sheet(item: $editSession) { session in
            LessonMemoryInfluenceEditor(store: store, lesson: session.lesson,
                expectedRevision: session.preferenceRevision, savedRelations: session.relations)
        }
    }
}

@MainActor
private struct LessonMemoryInfluenceEditor: View {
    @ObservedObject var store: CompanionStore
    let lesson: LessonSnapshot
    let expectedRevision: UInt64
    let savedRelations: [LessonMemoryInfluence]
    @Environment(\.dismiss) private var dismiss
    @State private var targetID = ""
    @State private var choice: Choice = .unassessed
    @State private var magnitude = 1.0
    @State private var confidence = 1.0
    @State private var salience = 1.0
    @State private var saveFailed = false

    private enum Choice: String, CaseIterable, Identifiable {
        case unassessed = "Unassessed"
        case attraction = "Attraction (+1)"
        case neutral = "Neutral (0)"
        case detraction = "Detraction (−1)"
        var id: String { rawValue }
        var polarity: ContextualMemoryInfluence.Polarity? {
            switch self {
            case .unassessed: nil
            case .attraction: .attraction
            case .neutral: .neutral
            case .detraction: .detraction
            }
        }
        init(_ polarity: ContextualMemoryInfluence.Polarity?) {
            switch polarity {
            case .attraction: self = .attraction
            case .neutral: self = .neutral
            case .detraction: self = .detraction
            case nil: self = .unassessed
            }
        }
    }

    private struct TargetChoice: Identifiable {
        let binding: DocumentProcedureUse
        let title: String
        var id: DocumentProcedureUse { binding }
    }

    private var choices: [TargetChoice] {
        var result = store.documentProcedures.latestProcedures.map {
            TargetChoice(binding: $0.binding, title: "\($0.title) · v\($0.revision)")
        }
        for relation in savedRelations where !result.contains(where: { $0.binding == relation.procedure }) {
            result.append(TargetChoice(binding: relation.procedure,
                title: "Earlier method \(relation.procedure.id.prefix(8)) · v\(relation.procedure.revision)"))
        }
        return result
    }

    private var selected: DocumentProcedureUse? {
        choices.first { LessonMemoryInfluence.targetID(for: $0.binding) == targetID }?.binding
    }
    private var prior: LessonMemoryInfluence? {
        savedRelations.first { LessonMemoryInfluence.targetID(for: $0.procedure) == targetID }
    }
    private var targetIssue: String? {
        guard let selected else { return "Keep a document method to choose an exact target." }
        return store.documentProcedureUnavailable(selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Memory influence").font(.title2.weight(.semibold))
            Text(lesson.topic).font(.headline)
            Text("For passage revision, assess how this memory bears on an exact saved method. Existing task, source and expiry rules still determine whether the memory is retrieved.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Target method", selection: $targetID) {
                Text("Choose a method").tag("")
                ForEach(choices) { item in
                    Text(item.title).tag(LessonMemoryInfluence.targetID(for: item.binding))
                }
            }
            .accessibilityIdentifier("memory-influence.target")
            .onChange(of: targetID) { _, _ in loadAssessment() }
            Picker("Direction", selection: $choice) {
                ForEach(Choice.allCases) { value in Text(value.rawValue).tag(value) }
            }
            .accessibilityIdentifier("memory-influence.polarity")
            setting("Magnitude", value: $magnitude, identifier: "magnitude")
            setting("Assessed confidence", value: $confidence, identifier: "confidence")
            setting("Retrieval salience", value: $salience, identifier: "salience")
            Text("Confidence is your assessment. Unassessed has no influence weight; neutral is assessed with zero direction. Sign, magnitude and confidence never remove a matching memory from retrieval.")
                .font(.caption).foregroundStyle(.secondary)
            if let selected,
               let procedure = store.documentProcedures.procedure(matching: selected),
               let evaluation = store.documentMethodMemoryInfluence(procedure) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current saved influence: \(evaluation.influence.formatted(.number.precision(.fractionLength(3))))")
                    Text("Attraction \(evaluation.positiveMass.formatted(.number.precision(.fractionLength(3)))) · Detraction \(evaluation.negativeMass.formatted(.number.precision(.fractionLength(3)))) · Neutral \(evaluation.neutralMass.formatted(.number.precision(.fractionLength(3))))")
                    if let row = evaluation.rows.first(where: { $0.sourceID == lesson.id }) {
                        Text("This memory’s retrieval: \(row.retrieval.formatted(.number.precision(.fractionLength(3))))")
                    } else {
                        Text("This memory is not contributing to the current passage question.")
                    }
                    if evaluation.hasOpposingEvidence { Text("Opposing assessments are present.") }
                }
                .font(.caption)
                .accessibilityIdentifier("memory-influence.saved-evaluation")
            }
            Text("After Save, influence orders methods within equal reviewed-outcome groups. You still choose a method and review its proposed edit. Each source/request contributes at most once, in retained lesson order.")
                .font(.caption).foregroundStyle(.secondary)
            if let targetIssue { Text(targetIssue).font(.caption).foregroundStyle(.orange) }
            if saveFailed { Text(store.lessonMessage).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Remove relationship") { save(removing: true) }
                    .disabled(prior == nil)
                    .accessibilityIdentifier("memory-influence.remove")
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save influence") { save(removing: false) }
                    .disabled(selected == nil || targetIssue != nil)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("memory-influence.save")
            }
        }
        .padding(24)
        .frame(width: 590)
        .onAppear {
            targetID = savedRelations.first.map { LessonMemoryInfluence.targetID(for: $0.procedure) }
                ?? choices.first.map { LessonMemoryInfluence.targetID(for: $0.binding) } ?? ""
            loadAssessment()
        }
    }

    private func setting(_ title: String, value: Binding<Double>, identifier: String) -> some View {
        HStack {
            Text(title).frame(width: 155, alignment: .leading)
            Slider(value: value, in: 0...1, step: 0.05)
                .accessibilityLabel(title)
                .accessibilityIdentifier("memory-influence.\(identifier)")
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                .monospacedDigit().frame(width: 42, alignment: .trailing)
        }.font(.callout)
    }

    private func loadAssessment() {
        choice = Choice(prior?.assessment.polarity)
        magnitude = prior?.assessment.magnitude ?? 1
        confidence = prior?.assessment.confidence ?? 1
        salience = prior?.assessment.retrievalSalience ?? 1
        saveFailed = false
    }

    private func save(removing: Bool) {
        guard let selected else { return }
        let assessment: ContextualMemoryInfluence.Assessment? = removing ? nil : .init(
            scope: LessonMemoryInfluence.scope, targetID: targetID, polarity: choice.polarity,
            magnitude: magnitude, confidence: confidence, retrievalSalience: salience)
        if store.updateLessonMemoryInfluence(lesson: lesson, expectedRevision: expectedRevision,
            procedure: selected, assessment: assessment) { dismiss() }
        else { saveFailed = true }
    }
}
