import Foundation
import Darwin
import XCTest
@testable import ARCHiDesktop

@MainActor
final class DesktopProfileBackupTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_789_000_000.125)

    func testExactTwoFileRoundTripSummaryPrivateArchiveAndLaterRollback() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try seed(fixture.source, text: "Use a short outline.")
        try seed(fixture.destination, text: "Keep the older preference.")
        let originalSource = try pair(fixture.source), originalDestination = try pair(fixture.destination)
        let archiveURL = fixture.root.appendingPathComponent("checkpoint.archibackup")
        let summary = try DesktopProfileBackup.create(profile: .review, preferenceURL: fixture.source,
            archiveURL: archiveURL, now: instant)
        XCTAssertEqual(summary.profile, .review)
        XCTAssertEqual(summary.createdAt, instant)
        XCTAssertEqual(summary.lessonCount, 1)
        XCTAssertTrue(summary.hasKIN)
        XCTAssertTrue(summary.preferencesPresent)
        XCTAssertTrue(summary.evolutionPresent)
        XCTAssertEqual(summary.bodyLabel, "Core Seed")
        let permissions = try FileManager.default.attributesOfItem(atPath: archiveURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let preview = try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .review, preferenceURL: fixture.destination)
        let report = try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks)
        XCTAssertEqual(report.summary, summary)
        XCTAssertEqual(try pair(fixture.destination), originalSource)
        XCTAssertEqual(try pair(fixture.source), originalSource)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        let rollback = try DesktopProfileBackup.preview(archiveURL: report.rollbackArchiveURL,
            profile: .review, preferenceURL: fixture.destination)
        _ = try DesktopProfileBackup.restore(rollback, rollbackDirectory: fixture.rollbacks)
        XCTAssertEqual(try pair(fixture.destination), originalDestination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.rollbackArchiveURL.path))
    }

    func testAbsentSlotsRemainAbsentAndCannotLeaveNewerEvolutionBehind() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try seed(fixture.destination, text: "A newer saved pair.")
        let sourceURL = fixture.root.appendingPathComponent("missing-folder/preferences.json")
        let archiveURL = fixture.root.appendingPathComponent("absent.archibackup")
        let summary = try DesktopProfileBackup.create(profile: .custom, preferenceURL: sourceURL, archiveURL: archiveURL)
        XCTAssertFalse(summary.preferencesPresent)
        XCTAssertFalse(summary.evolutionPresent)
        XCTAssertFalse(summary.hasKIN)
        XCTAssertEqual(summary.lessonCount, 0)
        XCTAssertEqual(summary.byteCount, 0)
        let preview = try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .custom, preferenceURL: fixture.destination)
        let report = try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks)
        XCTAssertEqual(try pair(fixture.destination), [nil, nil])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.deletingLastPathComponent().path),
            "Capturing an absent profile must not create one")
        _ = try DesktopProfileBackup.undoRestore(report)
        XCTAssertTrue(try pair(fixture.destination).allSatisfy { $0 != nil })
        // Presence of empty bytes is invalid, never silently converted to absence.
        try Data().write(to: fixture.source)
        XCTAssertThrowsError(try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source,
            archiveURL: fixture.root.appendingPathComponent("empty.archibackup")))
    }

    func testCorruptionForeignProfileUnknownFieldsAndUnsafeFilesFailBeforeMutation() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try seed(fixture.source, text: "A validated lesson.")
        let archiveURL = fixture.root.appendingPathComponent("checkpoint.archibackup")
        _ = try DesktopProfileBackup.create(profile: .review, preferenceURL: fixture.source, archiveURL: archiveURL)
        let original = try Data(contentsOf: archiveURL)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .preview, preferenceURL: fixture.destination))
        var object = try dictionary(original)
        var savedPair = try XCTUnwrap(object["pair"] as? [String: Any])
        var preferences = try XCTUnwrap(savedPair["preferences"] as? [String: Any])
        preferences["sha256"] = String(repeating: "0", count: 64)
        savedPair["preferences"] = preferences; object["pair"] = savedPair
        try canonical(object).write(to: archiveURL)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .review, preferenceURL: fixture.destination))
        object = try dictionary(original); object["unreviewed"] = true
        try canonical(object).write(to: archiveURL)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .review, preferenceURL: fixture.destination))
        let duplicate = try XCTUnwrap(String(data: original, encoding: .utf8))
            .replacingOccurrences(of: "\"profile\":\"review\"", with: "\"profile\":\"preview\",\"profile\":\"review\"")
        try Data(duplicate.utf8).write(to: archiveURL)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .review, preferenceURL: fixture.destination))
        try Data(repeating: 65, count: DesktopProfileBackup.maximumArchiveBytes + 1).write(to: archiveURL)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .review, preferenceURL: fixture.destination))
        try original.write(to: archiveURL)
        let symlink = fixture.root.appendingPathComponent("linked.archibackup")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: archiveURL)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: symlink, profile: .review, preferenceURL: fixture.destination))
        let fifo = fixture.root.appendingPathComponent("pipe.archibackup")
        XCTAssertEqual(fifo.path.withCString { mkfifo($0, 0o600) }, 0)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: fifo, profile: .review, preferenceURL: fixture.destination))
        XCTAssertEqual(try pair(fixture.destination), [nil, nil])
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        XCTAssertThrowsError(try DesktopProfileBackup.create(profile: .review, preferenceURL: fixture.source, archiveURL: archiveURL),
            "Backup export cannot replace an existing artifact")
        XCTAssertEqual(try Data(contentsOf: archiveURL), original)
    }

    func testStalePreviewAndOutputAliasingNeverReplaceDestination() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try seed(fixture.source, text: "Source lesson.")
        let archiveURL = fixture.root.appendingPathComponent("checkpoint.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: archiveURL)
        let preview = try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .custom, preferenceURL: fixture.destination)
        try seed(fixture.destination, text: "An external creation after preview.")
        let changed = try pair(fixture.destination)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks))
        XCTAssertEqual(try pair(fixture.destination), changed)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        let absent = fixture.root.appendingPathComponent("reserved.json")
        XCTAssertThrowsError(try DesktopProfileBackup.create(profile: .custom, preferenceURL: absent, archiveURL: absent))
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
    }

    func testExportRejectsAncestorSymlinkAndCaseAliasesWithoutCreatingProfileFiles() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let ancestorAlias = fixture.root.appendingPathComponent("ancestor-alias")
        try FileManager.default.createSymbolicLink(at: ancestorAlias, withDestinationURL: fixture.root)
        // The final parent (source/) is a real folder; only its ancestor is a link.
        for name in ["preferences.json", "Preferences.JSON", "preferences.evolution.json"] {
            let aliasedOutput = ancestorAlias.appendingPathComponent("source/\(name)")
            XCTAssertThrowsError(try DesktopProfileBackup.create(profile: .custom,
                preferenceURL: fixture.source, archiveURL: aliasedOutput))
            XCTAssertFalse(FileManager.default.fileExists(atPath: aliasedOutput.path))
        }
        // A custom injected preference URL can itself use the archive extension.
        // Extension filtering alone must not allow its resolved alias through.
        let customPreference = fixture.source.deletingLastPathComponent().appendingPathComponent("profile.archibackup")
        for name in ["profile.archibackup", "PROFILE.ARCHIBACKUP"] {
            XCTAssertThrowsError(try DesktopProfileBackup.create(profile: .custom,
                preferenceURL: customPreference,
                archiveURL: ancestorAlias.appendingPathComponent("source/\(name)")))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: customPreference.path))
        XCTAssertEqual(try pair(fixture.source), [nil, nil])
        let permitted = fixture.root.appendingPathComponent("checkpoint.ARCHIBACKUP")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: permitted)
        let renamed = fixture.root.appendingPathComponent("existing-backup.json")
        try Data(contentsOf: permitted).write(to: renamed)
        XCTAssertNoThrow(try DesktopProfileBackup.preview(archiveURL: renamed, profile: .custom,
            preferenceURL: fixture.destination), "Existing valid archives can still be opened regardless of filename")
    }

    func testPartialInstallRollsBackExactInvalidPriorBytesAndAbsence() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try seed(fixture.source, text: "Valid incoming lesson.")
        let invalid = Data("{ preserved invalid prior preferences".utf8)
        try invalid.write(to: fixture.destination)
        let original = try pair(fixture.destination)
        let archiveURL = fixture.root.appendingPathComponent("checkpoint.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: archiveURL)
        let preview = try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .custom, preferenceURL: fixture.destination)
        var rollbackURL: URL?
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks) { step in
            if case .firstFileInstalled = step { throw TestFailure.injected }
        }) { error in rollbackURL = (error as? DesktopProfileBackup.Failure)?.rollbackArchiveURL }
        XCTAssertEqual(try pair(fixture.destination), original)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        let archive = try dictionary(Data(contentsOf: XCTUnwrap(rollbackURL)))
        let archivedPair = try XCTUnwrap(archive["pair"] as? [String: Any])
        let prior = try XCTUnwrap(archivedPair["preferences"] as? [String: Any])
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(prior["data"] as? String)), invalid)
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: XCTUnwrap(rollbackURL), profile: .custom,
            preferenceURL: fixture.destination), "Raw invalid rollback is preserved, not accepted as valid saved state")
    }

    func testInterruptedRestoreRecoversBeforeOwnerAdmissionAndBlocksStaleRecovery() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try seed(fixture.source, text: "The incoming lesson.")
        try seed(fixture.destination, text: "The earlier lesson.", role: .guardian)
        let original = try pair(fixture.destination)
        let archiveURL = fixture.root.appendingPathComponent("checkpoint.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: archiveURL)
        let preview = try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .custom, preferenceURL: fixture.destination)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks) { step in
            if case .firstFileInstalled = step { throw DesktopProfileBackup.Interrupted() }
        })
        XCTAssertTrue(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        XCTAssertThrowsError(try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.destination,
            archiveURL: fixture.root.appendingPathComponent("must-not-capture-mixed-pair.archibackup")))
        XCTAssertThrowsError(try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .custom, preferenceURL: fixture.destination))
        let pending = try XCTUnwrap(DesktopProfileBackup.pendingRecovery(profile: .custom, preferenceURL: fixture.destination))
        let intermediate = try pair(fixture.destination)
        let external = Data("an unrelated external edit".utf8)
        try external.write(to: evolutionURL(fixture.destination))
        XCTAssertThrowsError(try DesktopProfileBackup.recover(pending))
        XCTAssertEqual(try Data(contentsOf: evolutionURL(fixture.destination)), external)
        XCTAssertTrue(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        // In this disposable rehearsal only, undo the synthetic external edit.
        try XCTUnwrap(intermediate[1]).write(to: evolutionURL(fixture.destination))
        let fresh = try XCTUnwrap(DesktopProfileBackup.pendingRecovery(profile: .custom, preferenceURL: fixture.destination))
        let preservedURL = try DesktopProfileBackup.recover(fresh)
        XCTAssertEqual(try pair(fixture.destination), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedURL.path))
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        XCTAssertNil(try DesktopProfileBackup.pendingRecovery(profile: .custom, preferenceURL: fixture.destination))
    }

    func testErrorAfterFullInstallRequiresReadbackRecoveryBeforeRetry() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try seed(fixture.source, text: "Incoming state.")
        try seed(fixture.destination, text: "Earlier state.", role: .guardian)
        let original = try pair(fixture.destination)
        let incoming = try pair(fixture.source)
        XCTAssertNotEqual(original[0], incoming[0], "Preferences must actually change")
        XCTAssertNotEqual(original[1], incoming[1], "Evolution must actually change")
        let archive = fixture.root.appendingPathComponent("checkpoint.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: archive)
        let preview = try DesktopProfileBackup.preview(archiveURL: archive, profile: .custom,
            preferenceURL: fixture.destination)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks) { step in
            if case .pairInstalled = step { throw DesktopProfileBackup.Interrupted() }
        })
        XCTAssertEqual(try pair(fixture.destination), incoming, "An error does not prove the mutation failed")
        XCTAssertTrue(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks),
            "Never blindly retry an operation with an unresolved outcome")
        XCTAssertEqual(try pair(fixture.destination), incoming)
        let pending = try XCTUnwrap(DesktopProfileBackup.pendingRecovery(profile: .custom,
            preferenceURL: fixture.destination))
        _ = try DesktopProfileBackup.recover(pending)
        XCTAssertEqual(try pair(fixture.destination), original)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        let fresh = try DesktopProfileBackup.preview(archiveURL: archive, profile: .custom,
            preferenceURL: fixture.destination)
        _ = try DesktopProfileBackup.restore(fresh, rollbackDirectory: fixture.rollbacks)
        XCTAssertEqual(try pair(fixture.destination), incoming)
    }

    func testOrdinaryErrorsAtEveryInstallCheckpointRollBackBothChangedSlots() throws {
        for failure in [DesktopProfileBackup.Checkpoint.journalPrepared, .firstFileInstalled, .pairInstalled] {
            let fixture = try Fixture(); defer { fixture.remove() }
            try seed(fixture.source, text: "Incoming state.")
            try seed(fixture.destination, text: "Earlier state.", role: .guardian)
            let original = try pair(fixture.destination), incoming = try pair(fixture.source)
            XCTAssertNotEqual(original[0], incoming[0])
            XCTAssertNotEqual(original[1], incoming[1])
            let archive = fixture.root.appendingPathComponent("checkpoint.archibackup")
            _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: archive)
            let preview = try DesktopProfileBackup.preview(archiveURL: archive, profile: .custom,
                preferenceURL: fixture.destination)
            var rollback: URL?
            XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks) { step in
                if step == failure {
                    switch step {
                    case .journalPrepared: XCTAssertEqual(try pair(fixture.destination), original)
                    case .firstFileInstalled: XCTAssertEqual(try pair(fixture.destination), [incoming[0], original[1]])
                    case .pairInstalled: XCTAssertEqual(try pair(fixture.destination), incoming)
                    }
                    throw TestFailure.injected
                }
            }) { rollback = ($0 as? DesktopProfileBackup.Failure)?.rollbackArchiveURL }
            XCTAssertNotNil(rollback, "An ordinary failure reports its retained rollback archive")
            XCTAssertEqual(try pair(fixture.destination), original)
            XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        }
    }

    func testPreparedJournalInterruptionPreservesPairAndBlocksRetry() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try seed(fixture.source, text: "Incoming state.")
        try seed(fixture.destination, text: "Earlier state.", role: .guardian)
        let original = try pair(fixture.destination)
        let archive = fixture.root.appendingPathComponent("checkpoint.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: fixture.source, archiveURL: archive)
        let preview = try DesktopProfileBackup.preview(archiveURL: archive, profile: .custom,
            preferenceURL: fixture.destination)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks) { step in
            if step == .journalPrepared { throw DesktopProfileBackup.Interrupted() }
        })
        XCTAssertEqual(try pair(fixture.destination), original)
        XCTAssertTrue(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks))
        let pending = try XCTUnwrap(DesktopProfileBackup.pendingRecovery(profile: .custom,
            preferenceURL: fixture.destination))
        _ = try DesktopProfileBackup.recover(pending)
        XCTAssertEqual(try pair(fixture.destination), original)
        XCTAssertFalse(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
    }

    func testConcurrentUnknownBytesArePreservedAndMalformedJournalBlocksRecovery() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try seed(fixture.source, text: "Incoming state.")
        try seed(fixture.destination, text: "Previous state.")
        let archiveURL = fixture.root.appendingPathComponent("checkpoint.archibackup")
        _ = try DesktopProfileBackup.create(profile: .preview, preferenceURL: fixture.source, archiveURL: archiveURL)
        let preview = try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .preview, preferenceURL: fixture.destination)
        let external = Data("concurrent bytes must survive".utf8)
        XCTAssertThrowsError(try DesktopProfileBackup.restore(preview, rollbackDirectory: fixture.rollbacks) { step in
            if case .firstFileInstalled = step { try external.write(to: evolutionURL(fixture.destination)) }
        })
        XCTAssertEqual(try Data(contentsOf: evolutionURL(fixture.destination)), external)
        XCTAssertTrue(DesktopProfileBackup.hasPendingJournal(preferenceURL: fixture.destination))
        XCTAssertThrowsError(try DesktopProfileBackup.pendingRecovery(profile: .preview, preferenceURL: fixture.destination))
        let journalURL = fixture.destination.deletingLastPathComponent().appendingPathComponent(DesktopProfileBackup.journalFilename)
        try Data("invalid recovery journal".utf8).write(to: journalURL)
        XCTAssertThrowsError(try DesktopProfileBackup.pendingRecovery(profile: .preview, preferenceURL: fixture.destination))
        XCTAssertEqual(try Data(contentsOf: evolutionURL(fixture.destination)), external)
    }

    private enum TestFailure: Error { case injected }
    private func seed(_ url: URL, text: String, role: EvolutionRole = .muse) throws {
        let document = NativePreferenceDocument(lessons: [KeptLesson(topic: "Planning", text: text, createdAt: instant)],
            qiMon: LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: instant))
        _ = try NativePreferencePersistence.write(document: document, to: url, expected: nil)
        let evolution = EvolutionStore(saveURL: evolutionURL(url))
        evolution.confirmRole(role); evolution.confirmHelpStyle(.reflective)
        XCTAssertTrue(evolution.save(), evolution.status)
    }
    private func evolutionURL(_ url: URL) -> URL { url.deletingPathExtension().appendingPathExtension("evolution.json") }
    private func pair(_ url: URL) throws -> [Data?] {
        try [url, evolutionURL(url)].map { FileManager.default.fileExists(atPath: $0.path) ? try Data(contentsOf: $0) : nil }
    }
    private func dictionary(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func canonical(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private struct Fixture {
        let root: URL
        let source: URL
        let destination: URL
        var rollbacks: URL { root.appendingPathComponent("Recovery") }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("archi-profile-backup-\(UUID())")
            source = root.appendingPathComponent("source/preferences.json")
            destination = root.appendingPathComponent("destination/preferences.json")
            for directory in [source.deletingLastPathComponent(), destination.deletingLastPathComponent()] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
