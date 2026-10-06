import SwiftUI

/// A read-only link from an outcome to its existing method family. A use of an
/// earlier version must never silently become a new method or the latest one.
enum DocumentMethodFollowThroughState: Equatable {
    case used(DocumentProcedure, isHistorical: Bool)
    case kept([DocumentProcedure])
    case newMethod
    case unavailable(String)
}

@MainActor
extension CompanionStore {
    func documentMethodFollowThrough(for record: DocumentWorkRecord) -> DocumentMethodFollowThroughState {
        guard !isShuttingDown, profileRecoveryBlock == nil,
              documentWork.isCurrentOnDisk, documentProcedures.isCurrentOnDisk,
              documentWork.records.filter({ $0.id == record.id }) == [record] else {
            return .unavailable("The profile, history or saved methods changed. Reopen this review from the current history before continuing.")
        }

        if let binding = record.procedureUse {
            guard let method = documentProcedures.procedure(matching: binding) else {
                return .unavailable("This edit used a saved method at v\(binding.revision), but that exact version is unavailable. Its reference remains in the receipt.")
            }
            return .used(method, isHistorical: !documentProcedures.latestProcedures.contains(method))
        }

        // Keep the original relationship visible after correction, withdrawal
        // or supersession. Availability controls reuse, not historical identity.
        let origins = documentProcedures.procedures.filter { $0.originRecordID == record.id }
        let kept = origins.filter { method in
            !origins.contains { $0.id == method.id && $0.revision > method.revision }
        }
        return kept.isEmpty ? .newMethod : .kept(kept)
    }
}

/// Shared by the immediate outcome and the review queue after restart. It uses
/// the existing feedback, method-history and preparation owners; opening it
/// neither saves a method nor credits the outcome as useful.
@MainActor
struct DocumentMethodFollowThroughView: View {
    @ObservedObject var store: CompanionStore
    let record: DocumentWorkRecord
    var startsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch store.documentMethodFollowThrough(for: record) {
            case let .used(method, isHistorical):
                Label("Used: \(method.title) · v\(method.revision)", systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.medium))
                Text("Your review is linked to this exact method version.")
                    .font(.caption).foregroundStyle(.secondary)
                MethodLearningView(store: store, procedure: method, isHistorical: isHistorical)
                mapButton(method)
            case let .kept(methods):
                ForEach(methods) { method in
                    Label("Kept: \(method.title) · v\(method.revision)", systemImage: "bookmark")
                        .font(.caption.weight(.medium))
                    MethodLearningView(store: store, procedure: method,
                        isHistorical: !store.documentProcedures.latestProcedures.contains(method))
                    mapButton(method)
                }
            case .newMethod:
                KeepDocumentProcedureView(store: store, record: record, startsExpanded: startsExpanded)
            case let .unavailable(reason):
                Text(reason).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("document.method-follow-through.unavailable")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.method-follow-through.\(record.id)")
    }

    private func mapButton(_ method: DocumentProcedure) -> some View {
        Button("Show method in memory map", systemImage: "point.3.connected.trianglepath.dotted") {
            _ = store.openDocumentMethodMap(method.binding)
        }
        .buttonStyle(.borderless).font(.caption)
        .accessibilityIdentifier("document.method-follow-through.map.\(method.id).\(method.revision)")
    }
}
