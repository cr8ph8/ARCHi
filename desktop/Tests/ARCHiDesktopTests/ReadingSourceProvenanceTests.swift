import Foundation
import XCTest
@testable import ARCHiDesktop

@MainActor
final class ReadingSourceProvenanceTests: XCTestCase {
    func testProvenanceReachesKnowledgeRequestsAndMethodsAndParentCorrectionRevokesReuse() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let parent = try library.keep(title: "Evidence", text: "Prefer precise verbs.")
        let derived = try library.keep(title: "Interpretation", text: "Use precise verbs in a concise revision.",
            provenance: .init(origin: .mixed, acquisition: .derivedCopy,
                attribution: "Attribution stays in source details", parents: [.init(binding: parent.binding)]))
        let anchor = try fullAnchor(derived, in: library)
        let draft = try library.saveKnowledgePage(title: "Revision method", body: "Prefer precise verbs.", kind: .concept, anchors: [anchor])
        let page = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let context = try XCTUnwrap(KnowledgePageContext.make(page: page, quotes: [derived.text]))
        XCTAssertEqual(context.readingSources, [derived.binding])
        XCTAssertEqual(context.modelInput["pages"]?.array?.first?["passages"]?.array?.first?["provenance"],
                       derived.binding.provenance?.modelInput)
        let request = AssistantRequest(prompt: "Explain this method.", sourceName: nil, sourceText: "",
            sourceRevision: 0, placementRevision: 0, tone: "Calm", replyLength: 0.5, localKnowledge: context)
        XCTAssertTrue(request.localContextInput.contains("user-declared-not-verified"))
        XCTAssertFalse(request.localContextInput.contains("Attribution stays in source details"))
        XCTAssertFalse(request.codexInput.contains("provenance"))
        let methods = DocumentProcedureLibrary(url: fixture.directory.appendingPathComponent("methods.json"))
        let current: (KnowledgePageBinding) -> Bool = { binding in
            library.latestKnowledgePages.contains { $0.binding == binding && library.availability(of: $0) == nil }
        }
        let method = try methods.keepCandidate(from: page, title: "Precise revision", instruction: "Use precise verbs.",
            requirements: DocumentWorkRequirements(mustBeShorter: false, preserveNumbersAndLinks: true), knowledgeIsCurrent: current)
        XCTAssertNil(methods.availability(of: method, records: [], knowledgeIsCurrent: current))
        _ = try library.declareProvenance(source: parent, origin: .human, acquisition: .userCopy, attribution: "Corrected origin", parents: [])
        XCTAssertNotNil(library.availability(of: context.readingSources[0]))
        XCTAssertNotNil(methods.availability(of: method, records: [], knowledgeIsCurrent: current))
        XCTAssertEqual(methods.procedures.count, 1)
    }

    func testLegacyV1ThroughV3RemainUnknownAndPreserveBindingJSONWithoutWriting() throws {
        for version in 1...3 {
            let fixture = try Fixture()
            defer { fixture.clean() }
            let original = snapshot(text: "Legacy source bytes.")
            let sourceObject: [String: Any] = ["id": original.id, "title": original.title,
                "revision": original.revision, "text": original.text]
            var archive: [String: Any] = ["schema": "archi-reading-sources/v\(version)", "sources": [sourceObject]]
            if version != 1 { archive["knowledgePages"] = [] }
            let bytes = try json(archive)
            try bytes.write(to: fixture.url)

            let library = ReadingSourceLibrary(url: fixture.url)
            XCTAssertNil(library.loadError, "Legacy v\(version)")
            let loaded = try XCTUnwrap(library.sources.first)
            XCTAssertNil(loaded.provenance)
            XCTAssertEqual(loaded.provenance?.origin ?? .unknown, .unknown)
            XCTAssertNil(loaded.binding.provenance)
            XCTAssertNil(library.availability(of: loaded.binding))
            XCTAssertEqual(loaded, original)
            let bindingObject: [String: Any] = ["id": original.id, "revision": original.revision,
                                               "digest": original.digest]
            XCTAssertEqual(try encode(loaded.binding), try json(bindingObject),
                           "Absent provenance must not change historical binding bytes.")
            XCTAssertEqual(try encode(loaded), try json(sourceObject))
            XCTAssertEqual(try Data(contentsOf: fixture.url), bytes, "Opening is not migration authority.")
        }
    }

    func testMetadataDeclarationAdvancesRevisionNotTextDigestAndV4ReopensReadOnly() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let original = try library.keep(title: "Original title", text: "Unchanged source evidence.")
        let anchor = try fullAnchor(original, in: library)
        let draft = try library.saveKnowledgePage(title: "Interpretation", body: "A user-reviewed interpretation.",
            kind: .claim, anchors: [anchor])
        let reviewed = try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let declared = try library.declareProvenance(source: original, origin: .human, acquisition: .userCopy,
            attribution: "Typed by a contributor", parents: [])

        XCTAssertEqual(declared.id, original.id)
        XCTAssertEqual(declared.revision, original.revision + 1)
        XCTAssertEqual(declared.title, original.title)
        XCTAssertEqual(declared.text, original.text)
        XCTAssertEqual(declared.digest, original.digest)
        XCTAssertNotEqual(declared.binding, original.binding)
        XCTAssertEqual(declared.provenance?.origin, .human)
        XCTAssertEqual(declared.provenance?.reviewState, "user-declared-not-verified")
        XCTAssertNil(library.availability(of: declared.binding))
        XCTAssertNotNil(library.availability(of: original.binding))
        XCTAssertNil(library.quote(for: anchor))
        XCTAssertNotNil(library.availability(of: reviewed))
        XCTAssertEqual(library.knowledgePages, [draft, reviewed], "Metadata edits retain page history.")

        let bytes = try Data(contentsOf: fixture.url)
        XCTAssertEqual(try fixture.archive()["schema"] as? String, "archi-reading-sources/v4")
        let reopened = ReadingSourceLibrary(url: fixture.url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.sources, [declared])
        XCTAssertEqual(reopened.knowledgePages, library.knowledgePages)
        XCTAssertNil(reopened.availability(of: declared.binding))
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)

        let revised = try library.declareProvenance(source: declared, origin: .mixed,
            acquisition: .userCopy, attribution: "Human revision of model wording", parents: [])
        XCTAssertEqual(revised.revision, declared.revision + 1)
        XCTAssertEqual(revised.digest, original.digest)
        XCTAssertNotEqual(revised.binding.provenance?.digest, declared.binding.provenance?.digest)
        XCTAssertNotNil(library.availability(of: declared.binding))
        XCTAssertNil(library.availability(of: revised.binding))
    }

    func testAncestorReplacementAndForgettingBlockRetainedDescendantsPagesAndSearch() throws {
        for forgetAncestor in [false, true] {
            let fixture = try Fixture()
            defer { fixture.clean() }
            let library = ReadingSourceLibrary(url: fixture.url)
            let a = try library.keep(title: "Root", text: "Needle evidence from the root.",
                provenance: .init(origin: .human, acquisition: .externalPublication))
            let b = try library.keep(title: "First derivation", text: "Needle interpretation at B.",
                provenance: .init(origin: .model, acquisition: .derivedCopy,
                                  parents: [ReadingSourceParent(binding: a.binding)]))
            let c = try library.keep(title: "Second derivation", text: "Needle interpretation at C.",
                provenance: .init(origin: .mixed, acquisition: .derivedCopy,
                                  parents: [ReadingSourceParent(binding: b.binding)]))
            let anchors = try [b, c].map { try fullAnchor($0, in: library) }
            var reviewed: [KnowledgePage] = []
            for (index, anchor) in anchors.enumerated() {
                let draft = try library.saveKnowledgePage(title: "Needle note \(index)", body: "Needle local interpretation.",
                    kind: .concept, anchors: [anchor])
                reviewed.append(try library.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision))
            }
            for source in [a, b, c] { XCTAssertNil(library.availability(of: source.binding)) }
            for page in reviewed { XCTAssertNil(library.availability(of: page)) }
            let before = try search(library)
            XCTAssertEqual(before.searchedSourceCount, 3)
            XCTAssertEqual(before.searchedPageCount, 2)
            XCTAssertEqual(before.hits.filter { $0.kind == .page }.count, 2)
            let retainedPages = library.knowledgePages

            if forgetAncestor {
                try library.forget(id: a.id)
            } else {
                _ = try library.replace(id: a.id, title: a.title, text: "Needle corrected root evidence.")
            }
            let savedBytes = try Data(contentsOf: fixture.url)
            for descendant in [b, c] {
                XCTAssertTrue(library.sources.contains(descendant), "Invalidation does not erase retained derivations.")
                XCTAssertNotNil(library.availability(of: descendant.binding))
                XCTAssertThrowsError(try fullAnchor(descendant, in: library))
            }
            for anchor in anchors { XCTAssertNil(library.quote(for: anchor)) }
            for page in reviewed {
                XCTAssertNotNil(library.availability(of: page))
                XCTAssertFalse(library.markdown(for: page).contains("> Needle interpretation"))
            }
            XCTAssertEqual(library.knowledgePages, retainedPages)
            let after = try search(library)
            let blockedIDs = Set([b.id, c.id])
            XCTAssertFalse(after.hits.contains { hit in
                hit.kind == .page || hit.anchor.map { blockedIDs.contains($0.source.id) } == true
            })
            XCTAssertEqual(after.excludedSourceCount, 2)
            XCTAssertEqual(after.excludedPageCount, 2)
            XCTAssertEqual(after.searchedSourceCount, forgetAncestor ? 0 : 1)
            XCTAssertEqual(after.searchedPageCount, 0)
            XCTAssertEqual(try Data(contentsOf: fixture.url), savedBytes)

            let reopened = ReadingSourceLibrary(url: fixture.url)
            XCTAssertNil(reopened.loadError, "Unavailable lineage remains readable history.")
            XCTAssertEqual(reopened.sources, library.sources)
            XCTAssertEqual(reopened.knowledgePages, retainedPages)
            XCTAssertNotNil(reopened.availability(of: c.binding))
            XCTAssertFalse(try search(reopened).hits.contains { $0.kind == .page })
        }
    }

    func testMissingStaleSelfAndDuplicateParentsAndStaleDeclarationsCannotWrite() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let parent = try library.keep(title: "Parent", text: "Original parent evidence.")
        let child = try library.keep(title: "Child", text: "Child evidence.")
        let currentParent = try library.replace(id: parent.id, title: parent.title, text: "Corrected parent evidence.")
        let missing = ReadingSourceParent(binding: snapshot(text: "Not kept.").binding)
        let stale = ReadingSourceParent(binding: parent.binding)
        let selfParent = ReadingSourceParent(binding: child.binding)
        let current = ReadingSourceParent(binding: currentParent.binding)
        let bytes = try Data(contentsOf: fixture.url)
        let retainedSources = library.sources
        for parents in [[missing], [stale], [selfParent], [current, current], []] {
            XCTAssertThrowsError(try library.declareProvenance(source: child, origin: .model,
                acquisition: .derivedCopy, attribution: "Synthetic declaration", parents: parents))
        }
        for parents in [[missing], [stale], [current, current], []] {
            XCTAssertThrowsError(try library.keep(title: "Rejected derivation", text: "Do not keep.",
                provenance: .init(origin: .model, acquisition: .derivedCopy, parents: parents)))
        }
        XCTAssertEqual(library.sources, retainedSources)
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)

        let declared = try library.declareProvenance(source: child, origin: .model,
            acquisition: .derivedCopy, attribution: "Current declaration", parents: [current])
        let declaredBytes = try Data(contentsOf: fixture.url)
        XCTAssertThrowsError(try library.declareProvenance(source: child, origin: .human,
            acquisition: .userCopy, attribution: "Stale source snapshot", parents: []))
        XCTAssertEqual(library.sources.first { $0.id == child.id }, declared)
        XCTAssertEqual(try Data(contentsOf: fixture.url), declaredBytes)
    }

    func testTextReplacementResetsAuthorshipAndRetainsExactParentDependency() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let parent = try library.keep(title: "Parent", text: "Original evidence.",
            provenance: .init(origin: .human, acquisition: .userCopy, attribution: "Parent attribution"))
        let parents = [ReadingSourceParent(binding: parent.binding)]
        let original = try library.keep(title: "Derived", text: "Generated interpretation.",
            provenance: .init(origin: .model, acquisition: .derivedCopy,
                              attribution: "Earlier authorship declaration", parents: parents))
        let replacement = try library.replace(id: original.id, title: original.title, text: "Edited interpretation.")
        XCTAssertEqual(replacement.id, original.id)
        XCTAssertEqual(replacement.revision, original.revision + 1)
        XCTAssertNotEqual(replacement.digest, original.digest)
        let provenance = try XCTUnwrap(replacement.provenance)
        XCTAssertEqual(provenance.origin, .unknown)
        XCTAssertEqual(provenance.acquisition, .derivedCopy)
        XCTAssertEqual(provenance.attribution, "")
        XCTAssertEqual(provenance.parents, parents)
        XCTAssertEqual(provenance.reviewState, "user-declared-not-verified")
        XCTAssertNil(library.availability(of: replacement.binding))
        XCTAssertNotNil(library.availability(of: original.binding))

        let redeclaredParent = try library.declareProvenance(source: parent, origin: .mixed,
            acquisition: .userCopy, attribution: "Corrected metadata only", parents: [])
        XCTAssertEqual(redeclaredParent.digest, parent.digest)
        XCTAssertNotEqual(redeclaredParent.binding.provenance?.digest, parents.first?.provenanceDigest)
        XCTAssertNotNil(library.availability(of: replacement.binding),
                        "Resetting authorship cannot remove an upstream dependency.")
        XCTAssertTrue(library.sources.contains(replacement))
    }

    func testReceiptAndModelInputExcludeFreeTextAttributionButBindMetadataDigest() throws {
        let parent = snapshot(text: "Parent source body excluded from the receipt.")
        let privateAttribution = "Fixture attribution phrase must remain local to source metadata"
        let declaration = ReadingSourceProvenance(origin: .mixed, acquisition: .derivedCopy,
            attribution: privateAttribution, parents: [ReadingSourceParent(binding: parent.binding)],
            declaredAt: Date(timeIntervalSince1970: 1_800_000_000))
        let source = snapshot(text: "Child source body excluded from the receipt.", provenance: declaration)
        let receipt = declaration.receipt
        XCTAssertTrue(receipt.isValid)
        XCTAssertEqual(receipt.digest, LessonSource.digest(of: String(decoding: try encode(declaration), as: UTF8.self)))
        XCTAssertEqual(Set(try object(receipt).keys), Set(["origin", "acquisition", "parents", "digest"]))
        XCTAssertTrue(String(decoding: try encode(declaration), as: UTF8.self).contains(privateAttribution))
        for bytes in [try encode(receipt), try encode(source.binding), try encode(receipt.modelInput)] {
            let text = String(decoding: bytes, as: UTF8.self)
            XCTAssertFalse(text.contains(privateAttribution))
            XCTAssertFalse(text.contains("attribution"))
            XCTAssertFalse(text.contains(parent.text))
            XCTAssertFalse(text.contains(source.text))
        }
        let amended = ReadingSourceProvenance(origin: declaration.origin, acquisition: declaration.acquisition,
            attribution: "A different explicit attribution", parents: declaration.parents, declaredAt: declaration.declaredAt)
        XCTAssertNotEqual(amended.receipt.digest, receipt.digest)
        XCTAssertEqual(amended.receipt.parents, receipt.parents)
        XCTAssertEqual(try JSONDecoder().decode(ReadingSourceProvenanceReceipt.self, from: encode(receipt)), receipt)
    }

    func testProvenanceDecodersRejectNullMalformedAndUnknownFields() throws {
        let parent = ReadingSourceParent(binding: snapshot(text: "Parent.").binding)
        let provenance = ReadingSourceProvenance(origin: .model, acquisition: .derivedCopy,
            attribution: "Fixture", parents: [parent], declaredAt: Date(timeIntervalSince1970: 1_800_000_000))
        let source = snapshot(text: "Source.", provenance: provenance)
        try assertStrict(ReadingSourceProvenance.self, object(provenance),
                         required: ["origin", "acquisition", "attribution", "parents", "declaredAt", "reviewState"])
        try assertStrict(ReadingSourceProvenanceReceipt.self, object(provenance.receipt),
                         required: ["origin", "acquisition", "parents", "digest"])
        try assertStrict(ReadingSourceParent.self, object(parent), required: ["id", "revision", "digest"],
                         optional: ["provenanceDigest"])
        try assertStrict(ReadingSourceSnapshot.self, object(source), required: ["id", "title", "revision", "text"],
                         optional: ["provenance"])
        try assertStrict(ReadingSourceBinding.self, object(source.binding), required: ["id", "revision", "digest"],
                         optional: ["provenance"])

        let valid = try object(provenance)
        for (field, value) in [("origin", "detected-human"), ("acquisition", "auto-import"),
                               ("reviewState", "verified"), ("attribution", String(repeating: "a", count: 241)),
                               ("attribution", "not\nplain attribution")] {
            var invalid = valid
            invalid[field] = value
            XCTAssertThrowsError(try JSONDecoder().decode(ReadingSourceProvenance.self, from: json(invalid)))
        }
        let parentObject = try object(parent)
        let invalidParentSets: [[[String: Any]]] = [[], [parentObject, parentObject]]
        for parents in invalidParentSets {
            var invalid = valid
            invalid["parents"] = parents
            XCTAssertThrowsError(try JSONDecoder().decode(ReadingSourceProvenance.self, from: json(invalid)))
        }
        var badReceipt = try object(provenance.receipt)
        badReceipt["digest"] = "not-a-digest"
        XCTAssertThrowsError(try JSONDecoder().decode(ReadingSourceProvenanceReceipt.self, from: json(badReceipt)))
        var badParent = try object(parent)
        badParent["provenanceDigest"] = "not-a-digest"
        XCTAssertThrowsError(try JSONDecoder().decode(ReadingSourceParent.self, from: json(badParent)))
    }

    func testMalformedV4AndProvenanceInLegacyArchivesAreBlockedWithoutOverwrite() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let library = ReadingSourceLibrary(url: fixture.url)
        let source = try library.keep(title: "Source", text: "Evidence.",
            provenance: .init(origin: .human, acquisition: .userCopy))
        let anchor = try fullAnchor(source, in: library)
        _ = try library.saveKnowledgePage(title: "Note", body: "Interpretation.", kind: .claim, anchors: [anchor])
        let base = try fixture.archive()
        XCTAssertEqual(base["schema"] as? String, "archi-reading-sources/v4")
        let sourceObject = try object(source)
        var corruptions: [[String: Any]] = []

        var changed = base
        changed["unexpected"] = true
        corruptions.append(changed)
        changed = base
        changed["schema"] = "archi-reading-sources/v6"
        corruptions.append(changed)
        for version in 1...3 {
            changed = base
            changed["schema"] = "archi-reading-sources/v\(version)"
            if version == 1 { changed.removeValue(forKey: "knowledgePages") }
            corruptions.append(changed)
        }
        var invalidSource = sourceObject
        invalidSource["provenance"] = NSNull()
        changed = base; changed["sources"] = [invalidSource]; corruptions.append(changed)
        invalidSource = sourceObject
        invalidSource["originalPath"] = "/not-retained"
        changed = base; changed["sources"] = [invalidSource]; corruptions.append(changed)
        var invalidProvenance = try object(XCTUnwrap(source.provenance))
        invalidProvenance["modelPrompt"] = "Unexpected retained text"
        invalidSource = sourceObject; invalidSource["provenance"] = invalidProvenance
        changed = base; changed["sources"] = [invalidSource]; corruptions.append(changed)

        var pages = try XCTUnwrap(base["knowledgePages"] as? [[String: Any]])
        var anchors = try XCTUnwrap(pages[0]["anchors"] as? [[String: Any]])
        var binding = try XCTUnwrap(anchors[0]["source"] as? [String: Any])
        binding["provenance"] = NSNull()
        anchors[0]["source"] = binding; pages[0]["anchors"] = anchors
        changed = base; changed["knowledgePages"] = pages; corruptions.append(changed)
        var encoded = try corruptions.map(json)
        let baseText = String(decoding: try json(base), as: UTF8.self)
        encoded.append(Data(("{\"schema\":\"archi-reading-sources/v4\"," + String(baseText.dropFirst())).utf8))
        for bytes in encoded {
            try bytes.write(to: fixture.url, options: .atomic)
            let blocked = ReadingSourceLibrary(url: fixture.url)
            XCTAssertNotNil(blocked.loadError)
            XCTAssertFalse(blocked.isCurrentOnDisk)
            XCTAssertNotNil(blocked.availability(of: source.binding))
            XCTAssertThrowsError(try blocked.keep(title: "New", text: "Cannot replace malformed history."))
            XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
        }
    }

    func testV4ProfileBackupPreviewRestoreAndUndoPreserveExactProvenanceBytes() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let sourcePreference = fixture.directory.appendingPathComponent("source/preferences.json")
        let targetPreference = fixture.directory.appendingPathComponent("target/preferences.json")
        let archiveURL = fixture.directory.appendingPathComponent("provenance.archibackup")
        let recoveryURL = fixture.directory.appendingPathComponent("Recovery")
        func libraryURL(_ preference: URL) -> URL {
            preference.deletingPathExtension().appendingPathExtension("reading-sources.json")
        }
        for preference in [sourcePreference, targetPreference] {
            try FileManager.default.createDirectory(at: preference.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try NativePreferencePersistence.write(document: NativePreferenceDocument(), to: preference, expected: nil)
        }
        let incoming = ReadingSourceLibrary(url: libraryURL(sourcePreference))
        let parent = try incoming.keep(title: "External copy", text: "Incoming evidence.",
            provenance: .init(origin: .human, acquisition: .externalPublication, attribution: "Fixture attribution"))
        let child = try incoming.keep(title: "Local derivation", text: "Incoming interpretation.",
            provenance: .init(origin: .mixed, acquisition: .derivedCopy,
                              parents: [ReadingSourceParent(binding: parent.binding)]))
        let anchor = try fullAnchor(child, in: incoming)
        let draft = try incoming.saveKnowledgePage(title: "Derived note", body: "An explicit local interpretation.",
                                                   kind: .concept, anchors: [anchor])
        let reviewed = try incoming.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        let previous = ReadingSourceLibrary(url: libraryURL(targetPreference))
        _ = try previous.keep(title: "Earlier copy", text: "Earlier target evidence.")
        let captured = try Data(contentsOf: libraryURL(sourcePreference))
        let before = try Data(contentsOf: libraryURL(targetPreference))
        // An empty preference document deliberately preserves file absence.
        let sourcePreferences = try? Data(contentsOf: sourcePreference)
        let targetPreferences = try? Data(contentsOf: targetPreference)
        let capturedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: captured) as? [String: Any])
        XCTAssertEqual(capturedObject["schema"] as? String, "archi-reading-sources/v4")

        let summary = try DesktopProfileBackup.create(profile: .custom, preferenceURL: sourcePreference, archiveURL: archiveURL)
        XCTAssertEqual(summary.readingSourceCount, 2)
        XCTAssertEqual(summary.knowledgePageVersionCount, 2)
        let preview = try DesktopProfileBackup.preview(archiveURL: archiveURL, profile: .custom, preferenceURL: targetPreference)
        XCTAssertEqual(try Data(contentsOf: libraryURL(targetPreference)), before, "Preview must not install incoming sources.")
        let report = try DesktopProfileBackup.restore(preview, rollbackDirectory: recoveryURL)
        XCTAssertEqual(try Data(contentsOf: libraryURL(targetPreference)), captured)
        XCTAssertEqual(try? Data(contentsOf: targetPreference), sourcePreferences)
        let reopened = ReadingSourceLibrary(url: libraryURL(targetPreference))
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.sources, incoming.sources)
        XCTAssertEqual(reopened.knowledgePages, incoming.knowledgePages)
        XCTAssertNil(reopened.availability(of: child.binding))
        XCTAssertNil(reopened.availability(of: reviewed))
        XCTAssertEqual(reopened.quote(for: anchor), child.text)
        XCTAssertEqual(reopened.sources.first { $0.id == child.id }?.provenance?.parents,
                       [ReadingSourceParent(binding: parent.binding)])
        _ = try DesktopProfileBackup.undoRestore(report)
        XCTAssertEqual(try Data(contentsOf: libraryURL(targetPreference)), before)
        XCTAssertEqual(try? Data(contentsOf: targetPreference), targetPreferences)
        XCTAssertEqual(try Data(contentsOf: libraryURL(sourcePreference)), captured)
    }

    private func snapshot(text: String, provenance: ReadingSourceProvenance? = nil) -> ReadingSourceSnapshot {
        .init(id: UUID().uuidString, title: "Fixture source", revision: 1, text: text, provenance: provenance)
    }

    private func fullAnchor(_ source: ReadingSourceSnapshot, in library: ReadingSourceLibrary) throws -> KnowledgeAnchor {
        try library.makeAnchor(sourceID: source.id, range: NSRange(location: 0, length: source.text.utf16.count))
    }

    private func search(_ library: ReadingSourceLibrary) throws -> KnowledgeRetrievalResult {
        try KnowledgeRetrieval.search(query: "needle", sources: library.sources, pages: library.knowledgePages,
                                      libraryIsCurrent: library.isCurrentOnDisk)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: encode(value)) as? [String: Any])
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func assertStrict<T: Decodable>(_ type: T.Type, _ valid: [String: Any], required: [String],
                                            optional: [String] = [], file: StaticString = #filePath,
                                            line: UInt = #line) throws {
        XCTAssertNoThrow(try JSONDecoder().decode(type, from: json(valid)), file: file, line: line)
        var unexpected = valid
        unexpected["unrecognizedField"] = true
        XCTAssertThrowsError(try JSONDecoder().decode(type, from: json(unexpected)), file: file, line: line)
        for field in required {
            var missing = valid
            missing.removeValue(forKey: field)
            XCTAssertThrowsError(try JSONDecoder().decode(type, from: json(missing)), "Missing \(field)", file: file, line: line)
        }
        for field in required + optional {
            var null = valid
            null[field] = NSNull()
            XCTAssertThrowsError(try JSONDecoder().decode(type, from: json(null)), "Null \(field)", file: file, line: line)
        }
    }

    private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-source-provenance-\(UUID())")
        var url: URL { directory.appendingPathComponent("reading-sources.json") }
        init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        func archive() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
}
