import Foundation
import Testing
@testable import ARCHiDesktop

@MainActor
struct PersonalContextTests {
    private func context() -> PersonalContext {
        PersonalContext(name: "Test Person", preferredName: "Tester", entries: [
            .init(id: UUID().uuidString, title: "Working style", text: "Lead with a practical next step.", status: .confirmed,
                  source: "Explicit user preference · synthetic fixture", useInAssistance: true),
            .init(id: UUID().uuidString, title: "Private reference", text: "Private birthday fixture", status: .confirmed,
                  source: "/private/profile-source", useInAssistance: false),
            .init(id: UUID().uuidString, title: "Design suggestion", text: "Try a gold arc.", status: .proposed,
                  source: "Assistant design proposal", useInAssistance: false)
        ])
    }
    private func request(_ profile: PersonalContextSnapshot?) -> AssistantRequest {
        AssistantRequest(prompt: "Help me plan this task.", sourceName: nil, sourceText: "", sourceRevision: 0,
                         placementRevision: 0, tone: "Calm", replyLength: 0.5, localProfile: profile)
    }

    @Test func profileSnapshotKeepsPrivateAndProposedDetailsOutOfEveryModel() throws {
        let profile = context()
        let captured = try #require(profile.assistantSnapshot)
        #expect(captured.isValid)
        #expect(captured.facts.count == 1)
        let r = request(captured)
        #expect(r.localInput.contains("practical next step"))
        #expect(r.localContextInput.contains("practical next step"), "Structured Hampton path gets the same local context.")
        for input in [r.input, r.codexInput, r.localInput, r.localContextInput] {
            #expect(!input.contains("birthday"))
            #expect(!input.contains("gold arc"))
            #expect(!input.contains("/private/"))
        }
        #expect(!r.codexInput.contains("localProfile"))
        #expect(!r.input.contains("Tester"))
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(request(nil).localInput.utf8)) == JSONDecoder().decode(JSONValue.self, from: Data(request(nil).input.utf8)))
        #expect(r.replacingLocalConversation([]).localProfile == captured)
    }

    @Test func cannotPromoteProposalOrUnknownIntoAssistance() {
        var profile = context()
        profile.entries[2].useInAssistance = true
        #expect(!profile.isValid)
        #expect(profile.assistantSnapshot == nil)
        profile.entries[2].status = .unknown
        #expect(!profile.isValid)
    }

    @Test func snapshotIsImmutableAndExactContentChangesItsDigest() throws {
        var profile = context()
        let before = try #require(profile.assistantSnapshot)
        profile.entries[0].text = "Give a short answer."
        profile.revision += 1
        let after = try #require(profile.assistantSnapshot)
        #expect(before.digest != after.digest)
        #expect(before.facts[0].text == "Lead with a practical next step.")
        #expect(before.revision == 1 && after.revision == 2)
    }

    @Test func oldV5MigratesWithoutCreatingPersonalDataAndNewEnvelopeRoundTrips() throws {
        let legacy = Data(#"{"schema":"archi-native-preferences/v5","revision":0,"lessons":[],"itemLibrary":[]}"#.utf8)
        let old = try NativePreferenceDocument.decode(legacy)
        #expect(old.personalContext == nil)
        #expect(old.schema == NativePreferenceDocument.currentSchema)
        var doc = old; doc.personalContext = context()
        #expect(try NativePreferenceDocument.decode(doc.encoded()) == doc)
    }

    @Test func profileOnlySaveSurvivesWithoutOrdinaryPreferencesAndBackupRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("preferences.json")
        var doc = NativePreferenceDocument(); doc.personalContext = context()
        _ = try NativePreferencePersistence.write(document: doc, to: url, expected: nil)
        #expect(try NativePreferencePersistence.read(url).document.personalContext == doc.personalContext)
        let backup = root.appendingPathComponent("profile.archibackup")
        _ = try DesktopProfileBackup.create(profile: .custom, preferenceURL: url, archiveURL: backup)
        let preview = try DesktopProfileBackup.preview(archiveURL: backup, profile: .custom, preferenceURL: url)
        #expect(preview.summary.preferencesPresent)
    }

    @Test func correctionClearsSessionWithoutCreatingDevelopmentAndStaleEditFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: url, allowsPlay: false)
        let original = context()
        #expect(store.updatePersonalContext(original, expected: nil))
        #expect(store.evolution.usefulReceipts.isEmpty)
        var corrected = original; corrected.entries[0].text = "A corrected preference."
        #expect(store.updatePersonalContext(corrected, expected: original))
        #expect(store.personalContext?.revision == 2)
        #expect(!store.updatePersonalContext(original, expected: original))
        #expect(store.updatePersonalContext(nil, expected: store.personalContext))
        #expect(store.personalContext == nil)
        #expect(store.evolution.usefulReceipts.isEmpty)
        #expect(!String(decoding: try store.lessonExportData(), as: UTF8.self).contains("personalContext"))
    }

    @Test func oversizedDuplicateAndInvalidPersonalContextAreRejected() {
        var profile = context()
        profile.entries.append(profile.entries[0]); #expect(!profile.isValid)
        profile = context(); profile.entries[0].text = String(repeating: "x", count: 1_201)
        #expect(!profile.isValid)
        profile = context(); profile.version = "unknown"
        #expect(!profile.isValid)
        let invalid = PersonalContextSnapshot(revision: 0, preferredName: "Tester", facts: [])
        #expect(!request(invalid).hasValidLocalProfile)
    }
}
