import AppKit
import SwiftUI

@MainActor
struct WikiOSTaskImportView: View {
    @ObservedObject var store: CompanionStore
    let file: QiWorkRequestFile
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review task from WikiOS").font(.title2.weight(.medium))
            Text(file.request.taskTitle).font(.headline)
            Text(file.request.projectName).font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                Text(file.request.brief).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("wikios.incoming.brief")
            Text("This is a local task copy. Its text is context to review. Import does not send a request, run commands, or change the task in WikiOS.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Your existing question is kept. Work together is session-only: return or export any changes before closing ARCHi. Keep the task file to reopen it later.")
                .font(.caption).foregroundStyle(.secondary)
            if let reason = store.wikiOSExchangeBlockReason { Text(reason).font(.caption).foregroundStyle(.orange) }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("wikios.incoming.error") }
            HStack {
                Button("Cancel") { store.wikiOSExchangeReview = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use in Work together") {
                    if !store.acceptWikiOSTask(file) { error = store.wikiOSExchangeMessage }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(store.wikiOSExchangeBlockReason != nil)
                .accessibilityIdentifier("wikios.incoming.accept")
            }
        }.padding(22).frame(width: 620, height: 510)
            .accessibilityElement(children: .contain).accessibilityIdentifier("wikios.incoming.review")
    }
}

@MainActor
struct WikiOSTaskReturnView: View {
    @ObservedObject var store: CompanionStore
    let preview: WikiOSReturnPreview
    @State private var summary = ""
    @State private var error: String?
    @State private var saved: QiWorkResultFile?
    @State private var delivering = false
    @State private var delivered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Return work to WikiOS").font(.title2.weight(.medium))
            Text(preview.request.request.taskTitle).font(.headline)
            Text("Review the exact copy and add a brief note about what changed or what still needs attention.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                Text(preview.text).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("wikios.return.text")
            TextField("Summary for WikiOS", text: $summary, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4).disabled(saved != nil)
                .accessibilityIdentifier("wikios.return.summary")
            Text("Save creates a separate local result file. WikiOS will preview it before attaching it to the matching task. The task status stays under your control.")
                .font(.caption).foregroundStyle(.secondary)
            if let saved {
                Text(delivered ? "Saved. Delivery to WikiOS was requested; review and attach the result there."
                     : "Saved: \(saved.url.path)")
                    .font(.caption).textSelection(.enabled).accessibilityIdentifier("wikios.return.saved")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("wikios.return.error") }
            HStack {
                Button(saved == nil ? "Cancel" : "Done") { store.wikiOSExchangeReview = nil }
                    .keyboardShortcut(.cancelAction).disabled(delivering)
                Spacer()
                if let saved {
                    Button("Show saved result") { NSWorkspace.shared.activateFileViewerSelecting([saved.url]) }
                        .accessibilityIdentifier("wikios.return.reveal")
                    if !delivered { Button("Open in WikiOS") { deliver(saved) }.disabled(delivering) }
                } else {
                    Button("Save and return to WikiOS") {
                        do {
                            let file = try store.exportWikiOSResult(preview, summary: summary)
                            saved = file; error = nil; deliver(file)
                        } catch { self.error = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!QiWorkExchange.isText(summary, limit: 4_000) || store.wikiOSExchangeBlockReason != nil)
                    .accessibilityIdentifier("wikios.return.save")
                }
            }
        }.padding(22).frame(width: 640, height: 540)
            .accessibilityElement(children: .contain).accessibilityIdentifier("wikios.return.review")
    }
    private func deliver(_ file: QiWorkResultFile) {
        delivering = true; error = nil
        WikiOSExchangeDelivery.open(file) { message in
            delivering = false; delivered = message == nil
            error = message.map { "Your result is saved. WikiOS could not be opened: " + $0 }
        }
    }
}
