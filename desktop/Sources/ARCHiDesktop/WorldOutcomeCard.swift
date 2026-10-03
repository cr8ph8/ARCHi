import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct WorldOutcomeCard: View {
    @ObservedObject var connection: UnityPresentationConnection
    @State private var exportMessage: String?

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Practice outcomes", systemImage: "arrow.triangle.branch").font(.headline)
                Text(connection.worldOutcomeStatus).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("arena.outcomes-status")
                if let report = connection.practiceReport() {
                    summary(report)
                }
                ArenaAdviceView(connection: connection)
                if !connection.worldOutcomes.isEmpty {
                    DisclosureGroup("Recent actions · \(connection.worldOutcomes.count)") {
                        ForEach(connection.worldOutcomes.reversed()) { outcome in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Round \(outcome.round) · \(outcome.action.capitalized) → \(outcome.damageDealt) dealt, \(outcome.damageTaken) taken")
                                    .font(.callout)
                                Text("Integrity \(outcome.integrityBefore) → \(outcome.integrityAfter) · Spark \(outcome.sparkBefore) → \(outcome.sparkAfter) · rival \(outcome.rivalAction)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if outcome.complete {
                                    Text(outcome.winner == "one" ? "Practice win" : outcome.winner == "two" ? "Practice loss" : "Practice draw")
                                        .font(.caption)
                                }
                                Text("Action \(outcome.actionID.prefix(8)) · session sequence \(outcome.sequence) · \(Date(timeIntervalSince1970: outcome.atUnix).formatted(date: .omitted, time: .standard))")
                                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                            }.padding(.vertical, 6)
                        }
                    }
                }
                Text("Unity rule outcomes from your solo inputs. They do not certify a skill, change saved growth or confirm a real-world action. Up to 32 recent actions stay for this session.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("arena.outcomes")
            .onChange(of: connection.isSharing) { _, _ in exportMessage = nil }
    }

    private func summary(_ report: ArenaPracticeReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This practice · retained actions").font(.subheadline.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { metrics(report) }
                VStack(alignment: .leading, spacing: 10) { metrics(report) }
            }
            Text(report.actionSummary).font(.caption).foregroundStyle(.secondary)
            Text(report.outcomeSummary).font(.caption).foregroundStyle(.secondary)
            Text(report.coverageSummary)
                .font(.caption)
                .foregroundStyle(report.missingCount > 0 || report.retiredCount > 0 ? .orange : .secondary)
                .accessibilityIdentifier("arena.report-coverage")
            Text("Last checked report · \(Date(timeIntervalSince1970: report.snapshotUpdatedAtUnix).formatted(date: .abbreviated, time: .standard))")
                .font(.caption2).foregroundStyle(.secondary)
            Button {
                saveReport()
            } label: {
                Label("Save practice report…", systemImage: "square.and.arrow.up")
            }.buttonStyle(WorkspaceActionStyle())
                .accessibilityIdentifier("arena.export-report")
            Text("Save the current observations before ending practice. The JSON includes actions and coverage; companion notes and identity are excluded.")
                .font(.caption).foregroundStyle(.secondary)
            if let exportMessage {
                Text(exportMessage).font(.caption).textSelection(.enabled)
                    .accessibilityIdentifier("arena.export-status")
            }
        }.padding(.vertical, 6)
            .accessibilityElement(children: .contain).accessibilityIdentifier("arena.practice-summary")
    }

    @ViewBuilder private func metrics(_ report: ArenaPracticeReport) -> some View {
        metric("Actions", value: report.retainedCount)
        metric("Damage dealt", value: report.damageDealt)
        metric("Damage taken", value: report.damageTaken)
        metric("Damage blocked", value: report.damageAbsorbed)
    }

    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number).font(.title2.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func saveReport() {
        guard let report = connection.practiceReport() else {
            exportMessage = "No checked solo actions are available to save yet."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ARCHi-practice-\(report.sessionID.prefix(8)).json"
        panel.message = "Save the currently retained practice observations. Coverage and limitations are included."
        // The Unity player can still own app focus when accessibility or a
        // background workspace button invokes Save. Attach to ARCHi's actual
        // workspace instead of depending on an ephemeral key/main window.
        guard let window = (NSApp.keyWindow as? WorkspaceWindow)
                ?? NSApp.windows.compactMap({ $0 as? WorkspaceWindow }).first(where: \.isVisible) else {
            exportMessage = "Open the ARCHi workspace before saving a report."
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            writeReport(report, to: url)
        }
    }

    private func writeReport(_ report: ArenaPracticeReport, to url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try connection.exportPracticeReport(report, to: url)
            exportMessage = "Saved \(report.retainedCount) actions to \(url.lastPathComponent)."
        } catch {
            exportMessage = "Report was not saved. \(error.localizedDescription)"
        }
    }
}
