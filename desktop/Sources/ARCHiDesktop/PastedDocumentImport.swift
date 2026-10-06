import Foundation

/// A sheet can only replace the exact source and profile it was opened from.
struct PastedDocumentImportContext: Identifiable {
    let id = UUID()
    let sourceRevision: UInt64
    let sourceName: String?
    let sourceBytes: Data
    let journalOwner: ObjectIdentifier
    let companion: LocalQiMon?
}

struct PastedDocumentDraft {
    var title = ""
    var text = ""
    var hasContent: Bool { !title.isEmpty || !text.isEmpty }
}
