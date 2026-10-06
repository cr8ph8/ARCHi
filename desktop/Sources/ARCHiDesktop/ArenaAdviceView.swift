import SwiftUI

/// A native advice consumer; all game input remains explicit in Unity.
@MainActor
struct ArenaAdviceView: View {
    @ObservedObject var connection: UnityPresentationConnection

    var body: some View {
        if let tracked = connection.arenaAdviceTracking {
            VStack(alignment: .leading, spacing: 8) {
                Label("Try a move together", systemImage: "sparkle").font(.headline)
                Text("Tracked suggestion · \(tracked.advice.selectedMove.capitalized)")
                    .font(.subheadline.weight(.semibold))
                Text(statusText(tracked)).font(.callout)
                    .accessibilityIdentifier("arena.advice-status")
                if let outcome = tracked.outcome {
                    Text("Round \(outcome.round) · \(outcome.action.capitalized) · \(outcome.damageDealt) dealt / \(outcome.damageTaken) taken")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let reason = tracked.reason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                Text("A matching action shows that the suggestion was followed. It does not show that the suggestion caused a better result.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(tracked.status == .pending ? "Cancel tracking" : "Clear suggestion") {
                    connection.clearArenaAdvice()
                }.accessibilityIdentifier("arena.clear-advice")
                details(tracked.advice)
            }.padding(.vertical, 8).accessibilityElement(children: .contain)
                .accessibilityIdentifier("arena.advice")
        } else if let advice = connection.arenaMoveAdvice() {
            VStack(alignment: .leading, spacing: 8) {
                Label("Try a move together", systemImage: "sparkle").font(.headline)
                Text("Suggestion after observed round \(advice.baseOutcome.round): \(advice.selectedMove.capitalized)")
                    .font(.subheadline.weight(.semibold))
                Text("Based on the integrity exchanged by retained \(advice.baseOutcome.field.capitalized) actions. If you are still in that round's bout, track this suggestion, then choose a move in Arena.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Track this suggestion") { connection.trackArenaAdvice(advice) }
                    .buttonStyle(WorkspaceActionStyle())
                    .accessibilityIdentifier("arena.track-advice")
                Text("Arena reports resolved actions, so ARCHi cannot confirm the current bout before you move. Only the exact next matching context can be linked. Nothing is played automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                details(advice)
            }.padding(.vertical, 8).accessibilityElement(children: .contain)
                .accessibilityIdentifier("arena.advice")
        }
    }

    private func statusText(_ tracked: ArenaAdviceTracking) -> String {
        switch tracked.status {
        case .pending: "Waiting for the next observed solo action."
        case .matched: "The next observed action matched the suggestion."
        case .differentAction: "You chose a different move in the matching context."
        case .unlinked: "This suggestion could not be linked to an action."
        }
    }

    private func details(_ advice: ArenaMoveAdvice) -> some View {
        DisclosureGroup("Why this suggestion") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(advice.rankedMoves, id: \.move) { move in
                    HStack {
                        Text(move.move.capitalized)
                        Spacer()
                        Text(move.score, format: .number.precision(.fractionLength(3)))
                            .monospacedDigit()
                        Text(move.observationCount == 0 ? "Neutral prior" : "\(move.observationCount) observed")
                    }.font(.caption)
                }
                Text("Hampton's bounded update changes only the observed move coordinate. Scores summarize exchanges; they are not win probabilities. Unobserved moves keep a neutral prior. Equal scores use Guard, Pulse, then Signature.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("The retained window is replayed from neutral values each time. This session-only advice does not train a model or change your companion's saved growth.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 6)
        }
    }
}
