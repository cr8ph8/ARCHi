import Foundation
import Combine
import CryptoKit
import Darwin

/// Exact reusable-method version captured with a document request. No source text.
struct DocumentProcedureUse: Codable, Equatable, Hashable, Sendable {
    let id: String
    let revision: UInt64
    let digest: String

    var isValid: Bool {
        UUID(uuidString: id) != nil && revision > 0 && ProcedureValidation.digest(digest)
    }

    private enum CodingKeys: String, CodingKey { case id, revision, digest }
    init(id: String, revision: UInt64, digest: String) {
        self.id = id; self.revision = revision; self.digest = digest
    }
    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: ProcedureCodingKey.self)
        guard Set(keys.allKeys.map(\.stringValue)) == ["id", "revision", "digest"] else {
            throw DocumentProcedureError.invalid("Unsupported procedure reference fields.")
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        revision = try values.decode(UInt64.self, forKey: .revision)
        digest = try values.decode(String.self, forKey: .digest)
        guard isValid else { throw DocumentProcedureError.invalid("Invalid procedure version reference.") }
    }
}

/// Explicitly authored guidance retained after reviewing a helpful applied edit.
/// The instruction is the user's saved method, never an automatically copied
/// document, prompt, response, or claim that the method works on later documents.
struct DocumentProcedure: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let revision: UInt64
    let title: String
    let instruction: String
    let mustBeShorter: Bool
    let preserveNumbersAndLinks: Bool
    let originRecordID: String
    let originFeedbackID: String
    let createdAt: Date
    var withdrawn: Bool
    /// Revision lineage is history, distinct from the evidence dependency below.
    /// Nil fields preserve the encoded bytes and bindings of existing v1 methods.
    var supersedes: DocumentProcedureUse? = nil
    var revisionNote: String? = nil

    var binding: DocumentProcedureUse {
        // Withdrawal changes availability, never the identity of an old request.
        var snapshot = self
        snapshot.withdrawn = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(snapshot)) ?? Data()
        return DocumentProcedureUse(id: id, revision: revision, digest: ProcedureValidation.hash(bytes))
    }

    var isValid: Bool {
        UUID(uuidString: id) != nil && revision > 0
            && ProcedureValidation.text(title, characters: 80, bytes: 320)
            && ProcedureValidation.text(instruction, characters: 1_200, bytes: 4_800)
            && ProcedureValidation.text(originRecordID, characters: 384, bytes: 1_536)
            && UUID(uuidString: originFeedbackID) != nil
            && createdAt.timeIntervalSinceReferenceDate.isFinite
            && createdAt > .distantPast && createdAt < .distantFuture
            && validRevision
    }

    private var validRevision: Bool {
        if revision == 1 { return supersedes == nil && revisionNote == nil }
        guard let supersedes, let revisionNote else { return false }
        return supersedes.isValid && supersedes.id == id && supersedes.revision == revision - 1
            && ProcedureValidation.text(revisionNote, characters: 600, bytes: 2_400)
    }

    func matches(requirements: DocumentWorkRequirements) -> Bool {
        mustBeShorter == requirements.mustBeShorter
            && preserveNumbersAndLinks == requirements.preserveNumbersAndLinks
    }
}

enum DocumentProcedureError: LocalizedError {
    case invalid(String), unreadable, changed, locked, full

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .unreadable: return "Saved procedures could not be read. Their existing bytes were preserved."
        case .changed: return "Saved procedures changed outside this session. Reopen ARCHi before saving or reusing them."
        case .locked: return "Another session is saving procedures. Try again after it finishes."
        case .full: return "The procedure library is full. Its reviewed history has been preserved."
        }
    }
}

/// Separate bounded owner for reviewed methods; opening never writes or resumes
/// work. A method remains inspectable after its evidence becomes unavailable.
@MainActor
final class DocumentProcedureLibrary: ObservableObject {
    @Published private(set) var procedures: [DocumentProcedure] = []
    @Published private(set) var loadError: String?
    private let url: URL
    private var baselineDigest: String?
    private var requiresRecovery = false
    static let maximumProcedures = 64
    private static let maximumBytes = 512 * 1_024
    private static let schema = "archi-document-procedures/v2"

    private struct Archive: Codable {
        let schema: String
        let procedures: [DocumentProcedure]
    }

    init(url: URL) {
        self.url = url
        do {
            if let bytes = try Self.readBounded(url) {
                procedures = try Self.decode(bytes).procedures
                baselineDigest = ProcedureValidation.hash(bytes)
            }
        } catch {
            requiresRecovery = true
            loadError = error.localizedDescription
        }
    }

    func procedure(matching binding: DocumentProcedureUse) -> DocumentProcedure? {
        guard binding.isValid else { return nil }
        return procedures.first { $0.binding == binding }
    }

    var latestProcedures: [DocumentProcedure] {
        procedures.filter { value in !procedures.contains { $0.id == value.id && $0.revision > value.revision } }
    }

    func versions(of id: String) -> [DocumentProcedure] {
        procedures.filter { $0.id == id }.sorted { $0.revision > $1.revision }
    }

    /// A blocked version needs a later, independently helpful applied result.
    /// Its former origin or failed reuse cannot be recycled as corrective support.
    func canSupportRevision(of binding: DocumentProcedureUse, with record: DocumentWorkRecord,
                            records: [DocumentWorkRecord]) -> Bool {
        guard Set(records.map(\.id)).count == records.count,
              let previous = procedure(matching: binding), latestProcedures.contains(previous),
              previous.revision < UInt64.max,
              records.filter({ $0.id == record.id }) == [record], Self.validOrigin(record),
              record.procedureUseRejected != true else { return false }
        if let dependency = record.procedureUse {
            guard let parent = procedure(matching: dependency), availability(of: parent, records: records) == nil else { return false }
        }
        if availability(of: previous, records: records) != nil {
            let lastProblem = records.filter {
                ($0.procedureUse == binding && ($0.procedureUseRejected == true || [.undoing, .undone].contains($0.state)
                    || $0.feedback.map { $0.verdict != .helpful } == true))
                || ($0.id == previous.originRecordID && (!Self.validOrigin($0) || $0.feedback?.id != previous.originFeedbackID))
            }.map(\.updatedAt).max() ?? previous.createdAt
            guard record.id != previous.originRecordID,
                  record.createdAt > max(previous.createdAt, lastProblem) else { return false }
        }
        return true
    }

    @discardableResult
    func revise(binding: DocumentProcedureUse, title: String, instruction: String, changeNote: String,
                from record: DocumentWorkRecord, records: [DocumentWorkRecord]) throws -> DocumentProcedure {
        try assertCurrent()
        guard canSupportRevision(of: binding, with: record, records: records),
              let previous = procedure(matching: binding), let feedback = record.feedback else {
            throw DocumentProcedureError.invalid("Choose the latest method and a current helpful applied result. A blocked version needs later corrective work.")
        }
        let value = DocumentProcedure(id: previous.id, revision: previous.revision + 1,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            mustBeShorter: record.mustBeShorter, preserveNumbersAndLinks: record.preserveNumbersAndLinks,
            originRecordID: record.id, originFeedbackID: feedback.id, createdAt: Date(), withdrawn: false,
            supersedes: binding, revisionNote: changeNote.trimmingCharacters(in: .whitespacesAndNewlines))
        guard value.isValid else {
            throw DocumentProcedureError.invalid("Use a name of 1–80 characters, instruction of 1–1,200 characters and change note of 1–600 characters.")
        }
        guard value.title != previous.title || value.instruction != previous.instruction
                || value.mustBeShorter != previous.mustBeShorter
                || value.preserveNumbersAndLinks != previous.preserveNumbersAndLinks else {
            throw DocumentProcedureError.invalid("Change the method or its requirements before saving a new version.")
        }
        guard procedures.count < Self.maximumProcedures else { throw DocumentProcedureError.full }
        try persist(procedures + [value])
        return value
    }

    /// Nil means eligible for explicit selection, not automatic use or success.
    func availability(of procedure: DocumentProcedure, records: [DocumentWorkRecord]) -> String? {
        do { try assertCurrent() }
        catch { return error.localizedDescription }
        guard Set(records.map(\.id)).count == records.count else { return "Document history has duplicate evidence identities." }
        return unavailable(procedure, records: records, visiting: [])
    }

    @discardableResult
    func keep(from record: DocumentWorkRecord, title: String, instruction: String,
              records: [DocumentWorkRecord]) throws -> DocumentProcedure {
        try assertCurrent()
        guard Set(records.map(\.id)).count == records.count,
              records.filter({ $0.id == record.id }) == [record], Self.validOrigin(record),
              let feedback = record.feedback else {
            throw DocumentProcedureError.invalid("Save a procedure only from the current helpful review of a verified applied edit.")
        }
        if let reference = record.procedureUse {
            guard let parent = procedure(matching: reference), record.procedureUseRejected != true,
                  availability(of: parent, records: records) == nil else {
                throw DocumentProcedureError.invalid("The procedure used for this edit is no longer available.")
            }
        }
        let value = DocumentProcedure(id: UUID().uuidString, revision: 1,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            mustBeShorter: record.mustBeShorter, preserveNumbersAndLinks: record.preserveNumbersAndLinks,
            originRecordID: record.id, originFeedbackID: feedback.id, createdAt: Date(), withdrawn: false)
        guard value.isValid else {
            throw DocumentProcedureError.invalid("Use a title of 1–80 characters and an instruction of 1–1,200 characters.")
        }
        // Repeated Save after a completed write returns the same admitted method.
        if let prior = procedures.first(where: {
            !$0.withdrawn && $0.originRecordID == value.originRecordID && $0.originFeedbackID == value.originFeedbackID
                && $0.title == value.title && $0.instruction == value.instruction
        }) { return prior }
        guard procedures.count < Self.maximumProcedures else { throw DocumentProcedureError.full }
        try persist(procedures + [value])
        return value
    }

    func withdraw(binding: DocumentProcedureUse) throws {
        try assertCurrent()
        guard let index = procedures.firstIndex(where: { $0.binding == binding }) else {
            throw DocumentProcedureError.invalid("That exact procedure version is no longer available.")
        }
        guard !procedures[index].withdrawn else { return }
        var next = procedures
        next[index].withdrawn = true
        try persist(next)
    }

    private func unavailable(_ value: DocumentProcedure, records: [DocumentWorkRecord],
                             visiting: Set<DocumentProcedureUse>) -> String? {
        guard value.isValid, procedure(matching: value.binding) == value else { return "This exact procedure version is unavailable." }
        guard !value.withdrawn else { return "You withdrew this procedure." }
        guard !visiting.contains(value.binding) else { return "Procedure evidence contains a dependency cycle." }
        guard let origin = records.first(where: { $0.id == value.originRecordID }), Self.validOrigin(origin),
              origin.feedback?.id == value.originFeedbackID else {
            return "The original helpful applied result or its exact review is no longer available."
        }
        guard value.mustBeShorter == origin.mustBeShorter,
              value.preserveNumbersAndLinks == origin.preserveNumbersAndLinks else {
            return "The saved requirements no longer match the original result."
        }
        let uses = records.filter { $0.procedureUse == value.binding }
        if uses.contains(where: { $0.procedureUseRejected == true || [.undoing, .undone].contains($0.state)
            || $0.feedback.map({ $0.verdict != .helpful }) == true }) {
            return "A later use of this version was corrected, withdrawn, or undone."
        }
        if let dependency = origin.procedureUse {
            guard origin.procedureUseRejected != true, let parent = procedure(matching: dependency) else {
                return "A procedure used by the original result is unavailable."
            }
            var next = visiting
            next.insert(value.binding)
            if let reason = unavailable(parent, records: records, visiting: next) {
                return "An earlier procedure is unavailable: " + reason
            }
        }
        return nil
    }

    private static func validOrigin(_ record: DocumentWorkRecord) -> Bool {
        record.state == .applied && record.feedback?.verdict == .helpful && record.feedback?.isValid == true
            && record.learning?.isValid == true && UUID(uuidString: record.requestID) != nil
            && !record.checks.isEmpty && record.checks.allSatisfy(\.passed)
            && record.proposedDigest != nil && record.expectedAfterDigest != nil
            && [record.sourceDigest, record.proposedDigest, record.expectedAfterDigest, record.actualAfterDigest]
                .compactMap { $0 }.allSatisfy(ProcedureValidation.recordDigest)
            && record.actualAfterDigest == record.expectedAfterDigest
            && record.afterRevision.map({ $0 > record.sourceRevision }) == true
    }

    private func assertCurrent() throws {
        guard !requiresRecovery else { throw DocumentProcedureError.unreadable }
        guard try Self.readBounded(url).map(ProcedureValidation.hash) == baselineDigest else {
            throw DocumentProcedureError.changed
        }
    }

    private func persist(_ next: [DocumentProcedure]) throws {
        guard Self.validHistory(next) else {
            throw DocumentProcedureError.invalid("Invalid procedure library.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Archive(schema: Self.schema, procedures: next))
        guard bytes.count <= Self.maximumBytes else { throw DocumentProcedureError.full }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let lock = Darwin.open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw DocumentProcedureError.locked }
        defer { _ = Darwin.close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw DocumentProcedureError.locked }
        defer { _ = flock(lock, LOCK_UN) }
        try assertCurrent()
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".procedure-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw DocumentProcedureError.unreadable }
        var open = true
        defer {
            if open { _ = Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: temporary)
        }
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw DocumentProcedureError.unreadable }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw DocumentProcedureError.unreadable }
        let closeResult = Darwin.close(descriptor)
        open = false
        guard closeResult == 0 else { throw DocumentProcedureError.unreadable }
        try assertCurrent()
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw DocumentProcedureError.unreadable }
        baselineDigest = ProcedureValidation.hash(bytes)
        procedures = next
        loadError = nil
    }

    private static func decode(_ data: Data) throws -> Archive {
        var scanner = UniqueJSONKeys(bytes: Array(data))
        try scanner.validate()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schema", "procedures"],
              let rows = object["procedures"] as? [[String: Any]], rows.count <= maximumProcedures,
              rows.allSatisfy({
                  let required: Set<String> = ["id", "revision", "title", "instruction", "mustBeShorter",
                      "preserveNumbersAndLinks", "originRecordID", "originFeedbackID", "createdAt", "withdrawn"]
                  let keys = Set($0.keys)
                  return required.isSubset(of: keys) && keys.isSubset(of: required.union(["supersedes", "revisionNote"]))
              }) else {
            throw DocumentProcedureError.unreadable
        }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard [schema, "archi-document-procedures/v1"].contains(archive.schema), Self.validHistory(archive.procedures),
              archive.schema != "archi-document-procedures/v1" || archive.procedures.allSatisfy({ $0.revision == 1 }) else {
            throw DocumentProcedureError.unreadable
        }
        return archive
    }

    private static func validHistory(_ values: [DocumentProcedure]) -> Bool {
        guard values.count <= maximumProcedures, values.allSatisfy(\.isValid) else { return false }
        let families = Dictionary(grouping: values, by: { UUID(uuidString: $0.id)! })
        for family in families.values {
            let ordered = family.sorted { $0.revision < $1.revision }
            for (index, value) in ordered.enumerated() {
                guard value.id == ordered[0].id, value.revision == UInt64(index + 1) else { return false }
                if index > 0 {
                    guard value.supersedes == ordered[index - 1].binding,
                          value.createdAt >= ordered[index - 1].createdAt else { return false }
                }
            }
        }
        return true
    }

    private static func readBounded(_ url: URL) throws -> Data? {
        guard url.isFileURL else { throw DocumentProcedureError.unreadable }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw DocumentProcedureError.unreadable
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw DocumentProcedureError.unreadable }
        var data = Data()
        while data.count <= maximumBytes {
            guard let part = try handle.read(upToCount: maximumBytes + 1 - data.count), !part.isEmpty else { break }
            data.append(part)
        }
        guard data.count <= maximumBytes else { throw DocumentProcedureError.unreadable }
        return data
    }
}

private enum ProcedureValidation {
    static func digest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func recordDigest(_ text: String) -> Bool {
        digest(text.hasPrefix("sha256:") ? String(text.dropFirst(7)) : text)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func text(_ text: String, characters: Int, bytes: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.count <= characters && text.utf8.count <= bytes
            && !text.unicodeScalars.contains { CharacterSet.controlCharacters.subtracting(.newlines).contains($0) }
    }
}

private struct ProcedureCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
