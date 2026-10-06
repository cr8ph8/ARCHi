import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A session-scoped opt-in on the existing local reply path, not a second app
/// or a source of companion development points.
@MainActor
struct RepresentationSettingsView: View {
    @ObservedObject var store: CompanionStore
    @State private var reviewedCalibration: GGUFCalibrationReportPreview?
    @State private var calibrationReviewError: String?

    var body: some View {
        DisclosureGroup("Read-only model measurements") {
            VStack(alignment: .leading, spacing: 10) {
                Text(GGUFRepresentationClient.bundledWorkerAvailable
                     ? "Local measurement runtime included"
                     : "Local measurement runtime is not included in this build")
                    .font(.system(size: 12, weight: .medium))
                Text("Use a reader fitted for the selected Qwen model to read a specified internal activation without steering the model. These experimental signals do not establish truth or change your companion.")
                if let reader = store.representationReader {
                    Text("\(reader.readerName) · \(reader.modelName) · \(reader.layer)")
                        .textSelection(.enabled)
                    if let summary = reader.calibrationSummary, let scope = reader.measurementScope {
                        Text("Measurement scope: \(scope)").textSelection(.enabled)
                            .accessibilityIdentifier("assistant.representation.scope")
                        Text(summary.summary).textSelection(.enabled)
                        Text("The supplied report covers synthetic record lookup at the final prompt token, before generation. It is not independently authenticated and does not qualify answer correctness, general truth detection, or other tasks.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Unqualified import · no supported calibration report")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("assistant.representation.unqualified")
                        Text("This legacy reader is available for inspection. It does not qualify ordinary reply measurements.")
                            .foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Reader provenance") {
                        Text(reader.provenance).textSelection(.enabled)
                        Text("Token selection: \(reader.tokenRule)").textSelection(.enabled)
                    }
                } else {
                    Text("No reader imported. Standard local Qwen remains available.")
                }
                HStack {
                    Button("Import reader…", action: importReader)
                        .accessibilityIdentifier("assistant.representation.import")
                    if store.representationReader != nil {
                        Button("Remove reader") { store.removeRepresentationReader() }
                            .accessibilityIdentifier("assistant.representation.remove")
                    }
                }
                Toggle("Measure ordinary replies (unavailable for synthetic readers)", isOn: Binding(
                    get: { store.representationMeasurementsEnabled },
                    set: { store.setRepresentationMeasurementsEnabled($0) }))
                    .disabled(store.representationReader?.canMeasureGeneralReplies != true
                              || store.representationReader?.hasLimitedShadowReport != true
                              || !GGUFRepresentationClient.bundledWorkerAvailable)
                    .accessibilityIdentifier("assistant.representation.enabled")
                Text(store.representationNotice).textSelection(.enabled)
                Text("Imported readers remain available for inspection. Synthetic calibration does not qualify ordinary reply measurements. Reader selection resets when ARCHi closes.")
                    .foregroundStyle(.secondary)
                Divider()
                Button("Review calibration report…", action: reviewCalibrationReport)
                    .accessibilityIdentifier("assistant.representation.review-report")
                Text("Report review only displays the selected file for this visit. It never imports or enables a reader, calls a model, or changes your companion.")
                    .foregroundStyle(.secondary)
                if let calibrationReviewError {
                    Text(calibrationReviewError).foregroundStyle(.orange)
                        .accessibilityIdentifier("assistant.representation.report-error")
                }
                if let report = reviewedCalibration {
                    CalibrationReportPreviewCard(report: report)
                    Button("Clear report review") {
                        reviewedCalibration = nil
                        calibrationReviewError = nil
                    }.accessibilityIdentifier("assistant.representation.clear-report")
                }
            }
            .font(.system(size: 11))
            .lineSpacing(3)
            .padding(.top, 8)
        }
        .disabled(store.isShuttingDown)
        .accessibilityIdentifier("assistant.representation.settings")
    }

    private func importReader() {
        let panel = NSOpenPanel()
        panel.title = "Import a Qwen measurement reader"
        panel.prompt = "Import reader"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        store.importRepresentationReader(from: url)
    }

    private func reviewCalibrationReport() {
        let panel = NSOpenPanel()
        panel.title = "Review a calibration report"
        panel.prompt = "Review report"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        reviewedCalibration = nil
        calibrationReviewError = nil
        do { reviewedCalibration = try GGUFCalibrationReportPreview.load(from: url) }
        catch { calibrationReviewError = "Report could not be reviewed: \(error.localizedDescription)" }
    }
}

private struct CalibrationReportPreviewCard: View {
    let report: GGUFCalibrationReportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(report.status.title).fontWeight(.semibold)
                .foregroundStyle(report.status == .failed ? Color.orange : Color.primary)
                .accessibilityIdentifier("assistant.representation.report-status")
            Text("Supplied report · not independently authenticated").foregroundStyle(.secondary)
            Text("\(report.filename) · \(report.modelName)").textSelection(.enabled)
            Text("\(report.holdoutCorrect)/\(report.holdoutCount) held-out synthetic cases correct · \(report.fitCount) fit · \(report.calibrationCount) calibration")
                .accessibilityIdentifier("assistant.representation.report-counts")
            Text("Measurement scope: \(report.measurementScope)").textSelection(.enabled)
            if let minimum = report.minimumSignedMargin {
                Text("Required signed margin: \(minimum.formatted(.number.precision(.fractionLength(0...4))))")
            }
            if let observed = report.minimumObservedHoldoutMargin {
                Text("Lowest held-out signed margin: \(observed.formatted(.number.precision(.fractionLength(0...4))))")
            }
            ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, limitation in
                Text(limitation).foregroundStyle(.secondary)
            }
            DisclosureGroup("Selected file identity") {
                Text("SHA-256 · \(report.contentDigest)").textSelection(.enabled)
                Text("This digest identifies the bytes reviewed; it does not authenticate the report or independently verify its claims.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("assistant.representation.report-preview")
    }
}
