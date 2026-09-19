import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct MeetingNotesImportSheet: View {
    @ObservedObject var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    @State private var provider: MeetingNotesProvider = .granola
    @State private var kind: MeetingNotesKind = .summary
    @State private var title = ""
    @State private var content = ""
    @State private var sourceURL: URL?
    @State private var review: MeetingNotesImport?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(review == nil ? "Bring in meeting notes" : "Review this meeting copy")
                        .font(.title2.weight(.medium))
                    Text("Granola notes or a Zoom transcript can become context for your next question.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let review {
                        Text(review.sourceName).font(.headline)
                        ScrollView {
                            Text(review.sharedText).font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .frame(height: 190)
                        .accessibilityIdentifier("meeting-notes.preview")
                        if let cues = review.cueCount {
                            Text("\(cues) transcript cues · timestamps and speaker labels retained")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !store.canImportMeetingNotes(review) {
                            Text(store.meetingNotesBudgetNotice).font(.callout).foregroundStyle(.orange)
                                .accessibilityIdentifier("meeting-notes.budget-warning")
                        } else {
                            Text("Fits the current local request budget. The selected provider still validates the request at Send.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Picker("Source", selection: $provider) {
                                ForEach(MeetingNotesProvider.allCases) { Text($0.rawValue).tag($0) }
                            }.accessibilityIdentifier("meeting-notes.provider")
                            Picker("Content", selection: $kind) {
                                ForEach(MeetingNotesKind.allCases) { Text($0.rawValue).tag($0) }
                            }.accessibilityIdentifier("meeting-notes.kind")
                        }
                        TextField("Meeting title", text: $title).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("meeting-notes.title")
                        TextEditor(text: $content).font(.system(size: 12))
                            .frame(height: 170)
                            .border(.quaternary).accessibilityLabel("Meeting notes to review")
                            .accessibilityIdentifier("meeting-notes.content")
                        HStack {
                            Button("Choose file…", action: chooseFile)
                                .accessibilityIdentifier("meeting-notes.choose-file")
                            Button("Paste clipboard") {
                                if let text = NSPasteboard.general.string(forType: .string) {
                                    content = text; sourceURL = nil; error = nil
                                    if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") { kind = .transcript }
                                } else { error = "The clipboard does not contain text." }
                            }.accessibilityIdentifier("meeting-notes.paste")
                            Spacer()
                            Text("\(content.utf8.count.formatted()) bytes · up to 100 KB for review")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Granola: Copy text gives a summary; copy from its transcript panel for the full transcript. Zoom: use a downloaded .vtt transcript or paste your notes. Text and Markdown files are also supported.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("The local assistant's full request must fit 22 KB including instructions and lessons. Long meetings need a shorter, deliberately reviewed excerpt. Keep its timestamps and source wording; content is never cut automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("meeting-notes.error") }
                    Text("Import is local. Send starts a request using your chosen route. Review any proposed facts before keeping them in Lessons. This meeting copy is session-only; retain your export for later.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if let review {
                    Button("Back") { self.review = nil; error = nil }
                    Button("Use in Work together") {
                        if store.importMeetingNotes(review, sourceURL: sourceURL) { dismiss() }
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!store.canImportMeetingNotes(review))
                    .accessibilityIdentifier("meeting-notes.use")
                } else {
                    Button("Review notes") {
                        do {
                            review = try MeetingNotesImport.prepare(text: content, title: title,
                                provider: provider, kind: kind, filename: sourceURL?.lastPathComponent)
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("meeting-notes.review")
                }
            }
        }
        .padding(22).frame(width: 580, height: 460)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["txt", "md", "markdown", "vtt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose meeting notes or a transcript to review locally."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try MeetingNotesImport.readFile(at: url)
            content = text; sourceURL = url; error = nil
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            if url.pathExtension.lowercased() == "vtt" || text.hasPrefix("WEBVTT") { kind = .transcript }
        } catch { self.error = error.localizedDescription }
    }
}
