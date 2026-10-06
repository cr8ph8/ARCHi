import SwiftUI

/// Visit-only references into the existing library. Inspection never selects
/// request context, restores forgotten bytes, or creates a new memory owner.
enum KnowledgeRecordReference: Equatable, Sendable {
    case page(KnowledgePageBinding)
    case source(ReadingSourceParent)
}

struct KnowledgeRecordInspectionSelection: Identifiable {
    let id = UUID()
    let reference: KnowledgeRecordReference
    let sourceOwner: ObjectIdentifier
}

enum KnowledgeRecordInspection {
    case page(KnowledgePage)
    case source(ReadingSourceSnapshot)
    case unavailable(String)
}

@MainActor
extension CompanionStore {
    func knowledgeRecordForInspection(_ selection: KnowledgeRecordInspectionSelection) -> KnowledgeRecordInspection {
        guard !isShuttingDown, profileRecoveryBlock == nil,
              selection.sourceOwner == ObjectIdentifier(readingSources) else {
            return .unavailable("This inspection belongs to an earlier library session. Reopen the record from the current Memory Map.")
        }
        guard readingSources.isCurrentOnDisk else {
            return .unavailable("The library changed outside this session or needs recovery. Reopen ARCHi before inspecting its records.")
        }
        switch selection.reference {
        case .page(let binding):
            guard binding.isValid,
                  let page = readingSources.knowledgePages.first(where: { $0.binding == binding }) else {
                return .unavailable("This exact page version is unavailable. No later revision was substituted.")
            }
            return .page(page)
        case .source(let binding):
            guard binding.isValid,
                  let source = readingSources.sources.first(where: { binding.matches($0.binding) }) else {
                return .unavailable("This source version was replaced or forgotten. Its earlier text is not retained; no newer copy was substituted.")
            }
            return .source(source)
        }
    }
}

@MainActor
struct KnowledgeRecordInspectionView: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var library: ReadingSourceLibrary
    let selection: KnowledgeRecordInspectionSelection
    @Environment(\.dismiss) private var dismiss
    @State private var refreshRevision = 0

    init(store: CompanionStore, selection: KnowledgeRecordInspectionSelection) {
        self.store = store
        self.library = store.readingSources
        self.selection = selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Memory record", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                Text("Read only").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    record
                    referenceDetails
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            HStack {
                Text("Your map and current work stay in place.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 600, height: 540)
        .accessibilityIdentifier("knowledge.inspect-record")
        // The owner publishes in-session changes. Recheck disk freshness when
        // returning from another application too, without a watcher or writer.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshRevision &+= 1
        }
    }

    @ViewBuilder private var record: some View {
        let _ = refreshRevision
        switch store.knowledgeRecordForInspection(selection) {
        case .page(let page):
            Text(page.title).font(.title2.bold()).textSelection(.enabled)
            Text("\(page.kind.title) · v\(page.revision) · \(page.state.title)")
                .font(.caption).foregroundStyle(.secondary)
            if let issue = library.availability(of: page) {
                Label(issue, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            Text(page.body).textSelection(.enabled)
                .accessibilityIdentifier("knowledge.inspect-record.page-body")
            KnowledgePageEvidence(store: store, anchors: page.anchors)
        case .source(let source):
            Text(source.title).font(.title2.bold()).textSelection(.enabled)
            Text("Kept source · v\(source.revision)").font(.caption).foregroundStyle(.secondary)
            if let issue = ReadingSourceLineage.availability(of: source.binding, in: library.sources) {
                Label(issue, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            if let provenance = source.provenance {
                Text("Declared origin: \(provenance.origin.title) · \(provenance.acquisition.title)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(source.text).textSelection(.enabled)
                .accessibilityIdentifier("knowledge.inspect-record.source-body")
        case .unavailable(let reason):
            Label("Record unavailable", systemImage: "doc.questionmark").font(.title2)
            Text(reason).foregroundStyle(.secondary)
                .accessibilityIdentifier("knowledge.inspect-record.unavailable")
        }
    }

    private var referenceDetails: some View {
        DisclosureGroup("Exact reference") {
            VStack(alignment: .leading, spacing: 4) {
                switch selection.reference {
                case .page(let binding):
                    Text("Page \(binding.id) · v\(binding.revision)")
                    Text("SHA-256 \(binding.digest)")
                case .source(let binding):
                    Text("Source \(binding.id) · v\(binding.revision)")
                    Text("SHA-256 \(binding.digest)")
                    Text("Provenance \(binding.provenanceDigest ?? "Not declared")")
                }
            }.font(.caption.monospaced()).textSelection(.enabled)
                .padding(.vertical, 6)
        }.font(.caption).foregroundStyle(.secondary)
    }
}
