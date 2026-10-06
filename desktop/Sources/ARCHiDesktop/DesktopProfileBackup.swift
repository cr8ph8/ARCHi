import Foundation
import CryptoKit
import Darwin

/// A portable checkpoint of existing companion and document owners.
/// Call while the app has stopped its writers. The journal must be resolved
/// before admitting either owner at startup. Other processes are not locked.
@MainActor
enum DesktopProfileBackup {
    enum ProfileKind: String, Codable, Sendable { case review, preview, custom }
    static let journalFilename = ".archi-desktop-profile-restore.json"
    // Entries preserve exact bytes as base64. Permit every owner at its bound,
    // plus bounded entry/digest/date metadata, without truncating a large library.
    static var maximumArchiveBytes: Int {
        4_096 + Slot.allCases.reduce(0) { $0 + (($1.limit + 2) / 3) * 4 }
    }

    struct ArchiveSummary: Equatable, Sendable {
        let profile: ProfileKind
        let createdAt: Date
        let preferencesPresent: Bool
        let evolutionPresent: Bool
        let lessonCount: Int
        let hasKIN: Bool
        let companionName: String?
        let bodyLabel: String?
        let byteCount: Int
        let includesDocumentWork: Bool
        let documentRecordCount: Int
        let procedureCount: Int
        let readingSourceCount: Int
        let knowledgePageVersionCount: Int
        let knowledgeLinkVersionCount: Int
    }
    struct RestorePreview: Sendable {
        let summary: ArchiveSummary
        let destinationPreferencesPresent: Bool
        let destinationEvolutionPresent: Bool
        fileprivate let archive: Archive
        fileprivate let expected: Pair
        fileprivate let preferenceURL: URL
    }
    struct RestoreReport: Sendable {
        let summary: ArchiveSummary
        let rollbackArchiveURL: URL
        fileprivate let preferenceURL: URL
        fileprivate let journalData: Data
        fileprivate let restoredPair: Pair
    }
    struct RecoveryPreview: Sendable {
        let profile: ProfileKind
        let rollbackArchiveURL: URL
        fileprivate let preferenceURL: URL
        fileprivate let journalData: Data
        fileprivate let journal: Journal
        fileprivate let old: Pair
        fileprivate let target: Pair
        fileprivate let expected: Pair
    }
    enum Failure: LocalizedError {
        case invalidLocation, oversized, invalidArchive, invalidSavedState, profileMismatch
        case stalePreview, recoveryRequired, existingArtifact, io, rolledBack(URL)
        case legacyWorkConflict
        var rollbackArchiveURL: URL? { if case .rolledBack(let url) = self { return url }; return nil }
        var errorDescription: String? {
            switch self {
            case .invalidLocation: "Use regular local files and folders, without symbolic links."
            case .oversized: "A profile file or backup exceeds its size limit. Nothing was replaced."
            case .invalidArchive: "The backup or recovery journal could not be verified."
            case .invalidSavedState: "The saved files did not pass their existing owner validation."
            case .profileMismatch: "This backup belongs to a different desktop profile."
            case .stalePreview: "The destination changed after preview. Review it again before restoring."
            case .recoveryRequired: "An unfinished restore needs recovery before the profile can be used or saved."
            case .existingArtifact: "That backup filename already exists. Choose a new filename."
            case .io: "A local backup or recovery operation could not complete."
            case .legacyWorkConflict: "This older backup excludes document work. Restore it into an empty profile; this profile’s reviewed work and reading copies must stay together."
            case .rolledBack: "Restore failed. The earlier saved pair was restored and its rollback archive was retained."
            }
        }
    }
    /// Synchronous fault seam for synthetic partial-write/crash recovery tests.
    enum Checkpoint { case journalPrepared, firstFileInstalled, documentWorkInstalled, pairInstalled }
    struct Interrupted: Error {}

    static func hasPendingJournal(preferenceURL: URL) -> Bool {
        var info = stat()
        let result = journalURL(preferenceURL).path.withCString { lstat($0, &info) }
        return result == 0 || errno != ENOENT
    }

    static func create(profile: ProfileKind, preferenceURL: URL, archiveURL: URL,
                       now: Date = Date()) throws -> ArchiveSummary {
        try requireNoJournal(preferenceURL)
        // The export contract also prevents case-insensitive aliases such as
        // Preferences.JSON from becoming a newly created profile file. Resolve
        // ancestor links for custom locations whose own suffix is archibackup.
        guard archiveURL.isFileURL, archiveURL.pathExtension.lowercased() == "archibackup" else {
            throw Failure.invalidLocation
        }
        // Resolve the existing parent separately: Foundation may leave an
        // ancestor alias unresolved when the final file does not exist yet.
        func resolvedDestination(_ url: URL) -> String {
            url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
                .appendingPathComponent(url.lastPathComponent).standardizedFileURL.path
        }
        let outputPath = resolvedDestination(archiveURL)
        guard !(Slot.allCases.map { $0.url(preferenceURL) } + [journalURL(preferenceURL)])
            .map(resolvedDestination)
            .contains(where: { $0.caseInsensitiveCompare(outputPath) == .orderedSame }) else { throw Failure.invalidLocation }
        let pair = try readPair(preferenceURL)
        let archive = Archive(profile: profile, createdAt: now, purpose: .checkpoint, pair: pair)
        let summary = try validateOwners(archive)
        guard try readPair(preferenceURL) == pair else { throw Failure.stalePreview }
        try writeNew(try encode(archive), to: archiveURL)
        guard try readArchive(archiveURL) == archive else { throw Failure.invalidArchive }
        guard try readPair(preferenceURL) == pair else { throw Failure.stalePreview }
        return summary
    }

    static func preview(archiveURL: URL, profile: ProfileKind, preferenceURL: URL) throws -> RestorePreview {
        try requireNoJournal(preferenceURL)
        let archive = try readArchive(archiveURL)
        guard archive.profile == profile else { throw Failure.profileMismatch }
        // A rollback can be deliberately restored later only if its raw prior
        // state also passes the normal owners. Invalid rollback bytes remain recovery-only.
        let summary = try validateOwners(archive)
        try requireCompatibleDestination(archive, preferenceURL: preferenceURL)
        let expected = try readPair(preferenceURL, includingWork: archive.pair.includesDocumentWork)
        return RestorePreview(summary: summary, destinationPreferencesPresent: expected.preferences.data != nil,
            destinationEvolutionPresent: expected.evolution.data != nil,
            archive: archive, expected: expected, preferenceURL: preferenceURL)
    }

    static func restore(_ preview: RestorePreview, rollbackDirectory: URL,
                        checkpoint: (Checkpoint) throws -> Void = { _ in }) throws -> RestoreReport {
        let preferenceURL = preview.preferenceURL
        try requireNoJournal(preferenceURL)
        _ = try validateOwners(preview.archive)
        try requireCompatibleDestination(preview.archive, preferenceURL: preferenceURL)
        guard try readPair(preferenceURL, includingWork: preview.expected.includesDocumentWork) == preview.expected else { throw Failure.stalePreview }
        try makePrivateDirectory(rollbackDirectory)
        let before = Archive(profile: preview.archive.profile, createdAt: Date(), purpose: .rollback, pair: preview.expected)
        let beforeData = try encode(before), targetData = try encode(preview.archive)
        let rollbackURL = rollbackDirectory.appendingPathComponent("before-restore-\(UUID().uuidString).archibackup")
        try writeNew(beforeData, to: rollbackURL)
        guard try readArchive(rollbackURL) == before else { throw Failure.invalidArchive }
        let parent = preferenceURL.deletingLastPathComponent()
        try makePrivateDirectory(parent)
        let transactionName = ".archi-restore-\(UUID().uuidString)"
        let transaction = parent.appendingPathComponent(transactionName)
        try makePrivateDirectory(transaction)
        let oldURL = transaction.appendingPathComponent("before.archibackup")
        let targetURL = transaction.appendingPathComponent("target.archibackup")
        try writeNew(beforeData, to: oldURL)
        try writeNew(targetData, to: targetURL)
        let journal = Journal(profile: before.profile, preferenceName: preferenceURL.lastPathComponent,
            transaction: transactionName, beforeHash: digest(beforeData), targetHash: digest(targetData))
        let journalData = try encode(journal)
        // A second check follows all staging IO. An exclusive journal admits at
        // most one restoring process, although ordinary profile writers do not share that lock.
        try requireCompatibleDestination(preview.archive, preferenceURL: preferenceURL)
        guard try readPair(preferenceURL, includingWork: preview.expected.includesDocumentWork) == preview.expected else { throw Failure.stalePreview }
        try writeNew(journalData, to: journalURL(preferenceURL))
        do {
            try checkpoint(.journalPrepared)
            var expected = preview.expected
            for slot in expected.slots {
                try replacePairSlot(slot, with: preview.archive.pair[slot], expected: expected, preferenceURL: preferenceURL)
                expected[slot] = preview.archive.pair[slot]
                if slot == .preferences { try checkpoint(.firstFileInstalled) }
                if slot == .documentWork { try checkpoint(.documentWorkInstalled) }
            }
            try checkpoint(.pairInstalled)
            try requireCompatibleDestination(preview.archive, preferenceURL: preferenceURL)
            guard try readPair(preferenceURL, includingWork: expected.includesDocumentWork) == preview.archive.pair else { throw Failure.stalePreview }
            try removeJournal(preferenceURL, expected: journalData)
            return RestoreReport(summary: preview.summary, rollbackArchiveURL: rollbackURL,
                preferenceURL: preferenceURL, journalData: journalData, restoredPair: preview.archive.pair)
        } catch {
            if error is Interrupted { throw Failure.recoveryRequired }
            do {
                try rollback(old: before.pair, target: preview.archive.pair, preferenceURL: preferenceURL)
                try removeJournal(preferenceURL, expected: journalData)
            } catch { throw Failure.recoveryRequired }
            throw Failure.rolledBack(rollbackURL)
        }
    }

    /// Immediate admission failure after a successful pair install can return
    /// to the captured prior bytes, provided nobody has changed the installed pair.
    static func undoRestore(_ report: RestoreReport) throws -> URL {
        try requireNoJournal(report.preferenceURL)
        guard try readPair(report.preferenceURL, includingWork: report.restoredPair.includesDocumentWork) == report.restoredPair else { throw Failure.stalePreview }
        try writeNew(report.journalData, to: journalURL(report.preferenceURL))
        guard let pending = try pendingRecovery(profile: report.summary.profile, preferenceURL: report.preferenceURL)
        else { throw Failure.recoveryRequired }
        return try recover(pending)
    }

    static func pendingRecovery(profile: ProfileKind, preferenceURL: URL) throws -> RecoveryPreview? {
        guard hasPendingJournal(preferenceURL: preferenceURL) else { return nil }
        guard let journalData = try read(journalURL(preferenceURL), limit: 4096) else { throw Failure.invalidArchive }
        let journal: Journal = try decodeCanonical(journalData)
        guard journal.schema == Journal.schemaName, journal.profile == profile,
              journal.preferenceName == preferenceURL.lastPathComponent,
              journal.transaction.hasPrefix(".archi-restore-"),
              UUID(uuidString: String(journal.transaction.dropFirst(".archi-restore-".count))) != nil
        else { throw Failure.invalidArchive }
        let directory = preferenceURL.deletingLastPathComponent().appendingPathComponent(journal.transaction)
        try requireDirectory(directory)
        let beforeURL = directory.appendingPathComponent("before.archibackup")
        let targetURL = directory.appendingPathComponent("target.archibackup")
        guard let oldData = try read(beforeURL, limit: maximumArchiveBytes),
              let targetData = try read(targetURL, limit: maximumArchiveBytes),
              digest(oldData) == journal.beforeHash, digest(targetData) == journal.targetHash else { throw Failure.invalidArchive }
        let old = try decodeArchive(oldData), target = try decodeArchive(targetData)
        guard old.profile == profile, target.profile == profile, old.purpose == .rollback else { throw Failure.invalidArchive }
        guard old.pair.includesDocumentWork == target.pair.includesDocumentWork else { throw Failure.invalidArchive }
        let expected = try readPair(preferenceURL, includingWork: old.pair.includesDocumentWork)
        guard expected.isKnownMixture(old: old.pair, target: target.pair) else { throw Failure.stalePreview }
        return RecoveryPreview(profile: profile, rollbackArchiveURL: beforeURL, preferenceURL: preferenceURL,
            journalData: journalData, journal: journal, old: old.pair, target: target.pair, expected: expected)
    }

    /// Recovery preserves the raw prior pair even when a prior file was invalid.
    /// Re-admit through the usual owners afterward; this does not bless its contents.
    static func recover(_ preview: RecoveryPreview) throws -> URL {
        let fresh = try pendingRecovery(profile: preview.profile, preferenceURL: preview.preferenceURL)
        guard let fresh, fresh.journalData == preview.journalData, fresh.old == preview.old,
              fresh.target == preview.target, fresh.expected == preview.expected else { throw Failure.stalePreview }
        try rollback(old: preview.old, target: preview.target, preferenceURL: preview.preferenceURL)
        try removeJournal(preview.preferenceURL, expected: preview.journalData)
        return preview.rollbackArchiveURL
    }

    fileprivate struct Entry: Codable, Equatable, Sendable {
        let present: Bool
        let byteCount: Int
        let sha256: String?
        let data: Data?
        init(_ data: Data?) {
            self.data = data; present = data != nil; byteCount = data?.count ?? 0
            sha256 = data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        }
        func valid(limit: Int) -> Bool {
            byteCount >= 0 && byteCount <= limit && self == Entry(data)
        }
    }
    fileprivate struct Pair: Codable, Equatable, Sendable {
        var preferences: Entry
        var evolution: Entry
        // Missing keys identify the legacy two-file archive. V2 always encodes
        // all three entries, including explicit absence. No paths come from JSON.
        var documentWork: Entry? = nil
        var documentProcedures: Entry? = nil
        var readingSources: Entry? = nil
        var includesDocumentWork: Bool { documentWork != nil && documentProcedures != nil && readingSources != nil }
        var slots: [Slot] { includesDocumentWork ? Slot.allCases : [.preferences, .evolution] }
        subscript(slot: Slot) -> Entry {
            get {
                switch slot {
                case .preferences: preferences
                case .evolution: evolution
                case .documentWork: documentWork ?? Entry(nil)
                case .documentProcedures: documentProcedures ?? Entry(nil)
                case .readingSources: readingSources ?? Entry(nil)
                }
            }
            set {
                switch slot {
                case .preferences: preferences = newValue
                case .evolution: evolution = newValue
                case .documentWork: documentWork = newValue
                case .documentProcedures: documentProcedures = newValue
                case .readingSources: readingSources = newValue
                }
            }
        }
        func isKnownMixture(old: Pair, target: Pair) -> Bool {
            slots == old.slots && slots == target.slots
                && slots.allSatisfy { self[$0] == old[$0] || self[$0] == target[$0] }
        }
    }
    fileprivate struct Archive: Codable, Equatable, Sendable {
        enum Purpose: String, Codable, Sendable { case checkpoint, rollback }
        static let schemaName = "archi-desktop-profile-backup/v2"
        static let legacySchemaName = "archi-desktop-profile-backup/v1"
        let schema: String
        let profile: ProfileKind
        let createdAt: Date
        let purpose: Purpose
        let pair: Pair
        init(profile: ProfileKind, createdAt: Date, purpose: Purpose, pair: Pair) {
            schema = pair.includesDocumentWork ? Self.schemaName : Self.legacySchemaName; self.profile = profile
            self.createdAt = Date(timeIntervalSince1970: (createdAt.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
            self.purpose = purpose; self.pair = pair
        }
    }
    fileprivate struct Journal: Codable, Sendable {
        static let schemaName = "archi-desktop-profile-restore/v1"
        var schema = Self.schemaName
        let profile: ProfileKind
        let preferenceName: String
        let transaction: String
        let beforeHash: String
        let targetHash: String
    }
    fileprivate enum Slot: CaseIterable {
        case preferences, evolution, documentWork, documentProcedures, readingSources
        @MainActor var limit: Int {
            switch self {
            case .preferences: NativePreferenceDocument.maximumBytes
            case .evolution: EvolutionStore.maximumSaveBytes
            case .documentWork: 1_048_576
            case .documentProcedures: 512 * 1_024
            // Source copies and page history are one ReadingSourceLibrary archive.
            case .readingSources: 8 * 1_024 * 1_024
            }
        }
        func url(_ preferenceURL: URL) -> URL {
            let suffix: String
            switch self {
            case .preferences: return preferenceURL
            case .evolution: suffix = "evolution.json"
            case .documentWork: suffix = "document-work.json"
            case .documentProcedures: suffix = "document-procedures.json"
            case .readingSources: suffix = "reading-sources.json"
            }
            return preferenceURL.deletingPathExtension().appendingPathExtension(suffix)
        }
    }
    private static func journalURL(_ preferenceURL: URL) -> URL {
        preferenceURL.deletingLastPathComponent().appendingPathComponent(journalFilename)
    }
    private static func requireNoJournal(_ preferenceURL: URL) throws {
        guard preferenceURL.isFileURL else { throw Failure.invalidLocation }
        guard !hasPendingJournal(preferenceURL: preferenceURL) else { throw Failure.recoveryRequired }
    }
    private static func readPair(_ preferenceURL: URL, includingWork: Bool = true) throws -> Pair {
        var pair = Pair(preferences: Entry(nil), evolution: Entry(nil))
        for slot in includingWork ? Slot.allCases : [.preferences, .evolution] {
            pair[slot] = Entry(try read(slot.url(preferenceURL), limit: slot.limit))
        }
        return pair
    }
    private static func requireCompatibleDestination(_ archive: Archive, preferenceURL: URL) throws {
        if !archive.pair.includesDocumentWork {
            for slot in [Slot.documentWork, .documentProcedures, .readingSources] {
                if try read(slot.url(preferenceURL), limit: slot.limit) != nil { throw Failure.legacyWorkConflict }
            }
        }
    }
    private static func readArchive(_ url: URL) throws -> Archive {
        guard let data = try read(url, limit: maximumArchiveBytes) else { throw Failure.invalidArchive }
        return try decodeArchive(data)
    }
    private static func decodeArchive(_ data: Data) throws -> Archive {
        guard data.count <= maximumArchiveBytes else { throw Failure.oversized }
        let archive: Archive = try decodeCanonical(data)
        let validShape = archive.schema == Archive.schemaName ? archive.pair.includesDocumentWork
            : archive.schema == Archive.legacySchemaName && archive.pair.documentWork == nil
                && archive.pair.documentProcedures == nil && archive.pair.readingSources == nil
        guard validShape, archive.createdAt.timeIntervalSince1970.isFinite,
              archive.createdAt.timeIntervalSince1970 >= 0,
              archive.pair.slots.allSatisfy({ archive.pair[$0].valid(limit: $0.limit) }) else { throw Failure.invalidArchive }
        return archive
    }
    private static func validateOwners(_ archive: Archive) throws -> ArchiveSummary {
        // Validate presence/hash/size even for internally generated captures.
        _ = try decodeArchive(encode(archive))
        let document: NativePreferenceDocument
        do { document = try archive.pair.preferences.data.map(NativePreferenceDocument.decode) ?? NativePreferenceDocument() }
        catch { throw Failure.invalidSavedState }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-backup-validation-\(UUID())")
        try makePrivateDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.evolution.json")
        let evolution = EvolutionStore(saveURL: url)
        if let bytes = archive.pair.evolution.data {
            try writeNew(bytes, to: url)
            guard evolution.load() else { throw Failure.invalidSavedState }
        }
        let temporaryPreferences = directory.appendingPathComponent("preferences.json")
        for slot in [Slot.documentWork, .documentProcedures, .readingSources] {
            if let bytes = archive.pair[slot].data { try writeNew(bytes, to: slot.url(temporaryPreferences)) }
        }
        let work = DocumentWorkJournal(url: Slot.documentWork.url(temporaryPreferences))
        let methods = DocumentProcedureLibrary(url: Slot.documentProcedures.url(temporaryPreferences))
        let sources = ReadingSourceLibrary(url: Slot.readingSources.url(temporaryPreferences))
        guard work.loadError == nil, methods.loadError == nil, sources.loadError == nil else { throw Failure.invalidSavedState }
        let body: String?
        if let kin = document.qiMon {
            if kin.character == .hampton { body = kin.stageTitle }
            else if let growth = evolution.kinGrowthRecord, growth.originDigest != kin.originDigest { body = nil }
            else { body = evolution.kinGrowthRecord?.active == true ? "First Light" : "Core Seed" }
        } else { body = evolution.activeFamily?.title }
        return ArchiveSummary(profile: archive.profile, createdAt: archive.createdAt,
            preferencesPresent: archive.pair.preferences.present, evolutionPresent: archive.pair.evolution.present,
            lessonCount: document.lessons.count, hasKIN: document.qiMon?.character == .kin,
            companionName: document.qiMon?.name, bodyLabel: body,
            byteCount: archive.pair.slots.reduce(0) { $0 + archive.pair[$1].byteCount },
            includesDocumentWork: archive.pair.includesDocumentWork,
            documentRecordCount: work.records.count, procedureCount: methods.procedures.count,
            readingSourceCount: sources.sources.count,
            knowledgePageVersionCount: sources.knowledgePages.count,
            knowledgeLinkVersionCount: sources.knowledgeLinks.count)
    }
    private static func replacePairSlot(_ slot: Slot, with entry: Entry, expected: Pair, preferenceURL: URL) throws {
        guard try readPair(preferenceURL, includingWork: expected.includesDocumentWork) == expected else { throw Failure.stalePreview }
        let url = slot.url(preferenceURL)
        let old = expected[slot]
        if entry == old { return }
        if let bytes = entry.data {
            let staged = url.deletingLastPathComponent().appendingPathComponent(".archi-profile-stage-\(UUID())")
            try writeNew(bytes, to: staged)
            defer { try? FileManager.default.removeItem(at: staged) }
            guard try readPair(preferenceURL, includingWork: expected.includesDocumentWork) == expected else { throw Failure.stalePreview }
            guard staged.path.withCString({ source in url.path.withCString { Darwin.rename(source, $0) } }) == 0 else { throw Failure.io }
        } else {
            guard try readPair(preferenceURL, includingWork: expected.includesDocumentWork) == expected else { throw Failure.stalePreview }
            guard url.path.withCString({ unlink($0) }) == 0 else { throw Failure.io }
        }
        try syncDirectory(url.deletingLastPathComponent())
    }
    private static func rollback(old: Pair, target: Pair, preferenceURL: URL) throws {
        var current = try readPair(preferenceURL, includingWork: old.includesDocumentWork)
        guard current.isKnownMixture(old: old, target: target) else { throw Failure.stalePreview }
        for slot in old.slots {
            try replacePairSlot(slot, with: old[slot], expected: current, preferenceURL: preferenceURL)
            current[slot] = old[slot]
        }
        guard try readPair(preferenceURL, includingWork: old.includesDocumentWork) == old else { throw Failure.stalePreview }
    }
    private static func removeJournal(_ preferenceURL: URL, expected: Data) throws {
        let url = journalURL(preferenceURL)
        guard try read(url, limit: 4096) == expected else { throw Failure.recoveryRequired }
        guard url.path.withCString({ unlink($0) }) == 0 else { throw Failure.io }
        try syncDirectory(url.deletingLastPathComponent())
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }
    private static func decodeCanonical<T: Codable>(_ data: Data) throws -> T {
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            let value = try decoder.decode(T.self, from: data)
            // Exported archives are canonical JSON. Round-trip equality rejects
            // unknown/duplicate keys, ambiguous numbers and altered encodings.
            guard try encode(value) == data else { throw Failure.invalidArchive }
            return value
        } catch { throw Failure.invalidArchive }
    }
    private static func read(_ url: URL, limit: Int) throws -> Data? {
        guard url.isFileURL else { throw Failure.invalidLocation }
        let parent = url.deletingLastPathComponent().path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        if parent < 0 {
            if errno == ENOENT { return nil }
            throw Failure.invalidLocation
        }
        defer { Darwin.close(parent) }
        let descriptor = url.lastPathComponent.withCString { openat(parent, $0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw Failure.invalidLocation
        }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG else { throw Failure.invalidLocation }
        guard before.st_size >= 0, before.st_size <= limit else { throw Failure.oversized }
        var bytes = [UInt8](repeating: 0, count: limit + 1), count = 0
        while count < bytes.count {
            let amount = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!.advanced(by: count), $0.count - count) }
            if amount < 0 && errno == EINTR { continue }
            guard amount >= 0 else { throw Failure.io }
            if amount == 0 { break }
            count += amount
        }
        guard count <= limit else { throw Failure.oversized }
        var after = stat()
        guard fstat(descriptor, &after) == 0, before.st_size == after.st_size, count == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw Failure.stalePreview }
        return Data(bytes.prefix(count))
    }
    private static func requireDirectory(_ url: URL) throws {
        guard url.isFileURL else { throw Failure.invalidLocation }
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard descriptor >= 0 else { throw Failure.invalidLocation }
        Darwin.close(descriptor)
    }
    private static func makePrivateDirectory(_ url: URL) throws {
        guard url.isFileURL else { throw Failure.invalidLocation }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try requireDirectory(url)
    }
    private static func syncDirectory(_ url: URL) throws {
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard descriptor >= 0 else { throw Failure.invalidLocation }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw Failure.io }
    }
    private static func writeNew(_ bytes: Data, to url: URL) throws {
        guard url.isFileURL, bytes.count <= maximumArchiveBytes else { throw Failure.oversized }
        try requireDirectory(url.deletingLastPathComponent())
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".archi-backup-write-\(UUID())")
        let descriptor = temporary.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard descriptor >= 0 else { throw Failure.io }
        defer { Darwin.close(descriptor); try? FileManager.default.removeItem(at: temporary) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let amount = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if amount < 0 && errno == EINTR { continue }
                guard amount > 0 else { throw Failure.io }
                offset += amount
            }
        }
        guard fsync(descriptor) == 0 else { throw Failure.io }
        let result = temporary.path.withCString { source in url.path.withCString { renamex_np(source, $0, UInt32(RENAME_EXCL)) } }
        guard result == 0 else { throw errno == EEXIST ? Failure.existingArtifact : Failure.io }
        try syncDirectory(url.deletingLastPathComponent())
    }
}
