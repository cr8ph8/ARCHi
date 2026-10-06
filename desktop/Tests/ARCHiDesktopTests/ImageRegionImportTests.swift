import ARCHiSpatial
import Combine
import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import ARCHiDesktop

/// Disposable image intake exercises the existing document owner, without
/// invoking OCR, models, native dialogs or a person's saved profile.
@MainActor
final class ImageRegionImportTests: XCTestCase {
    func testImportSelectsExactReviewedBodyAndPreservesUnsentWorkWithoutSaving() async throws {
        let fixture = try await Fixture()
        defer { fixture.clean() }
        fixture.store.prompt = "Keep this unsent request exactly.\r\n"
        fixture.store.pastedDocumentDraft = .init(title: "Pending paste", text: "Unimported text.")
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        let saved = try fixture.savedFiles()
        let evolutionRevision = fixture.store.evolution.revision
        let body = "Café · Cafe\u{301} 🌱\n\tSecond line.\n"
        let document = try fixture.document(body: body, original: "Cafe · original OCR proposal.", title: body.components(separatedBy: "\n")[0])

        XCTAssertTrue(fixture.store.importImageRegion(document, image: fixture.image, context: context,
                                                       reviewWorkingCopy: { true }))
        XCTAssertEqual(Data(fixture.store.sharedText.utf8), Data(document.text.utf8))
        XCTAssertEqual(fixture.store.sourceName, document.title)
        XCTAssertEqual(fixture.store.imageRegionWorkingSource, document)
        XCTAssertEqual(fixture.store.imageRegionWorkingImage?.imageSHA256, fixture.image.imageSHA256)
        let selection = try XCTUnwrap(fixture.store.textSelection)
        XCTAssertEqual(selection.range, document.contentRange)
        XCTAssertEqual(Data(selection.quote.utf8), Data(body.utf8), "Matching text in the title must not steal the selected body.")
        XCTAssertEqual(selection.sourceRevision, fixture.store.sourceRevision)
        XCTAssertTrue(fixture.store.sharedText.contains("Coordinate space: upright-image-normalized-top-left"))
        XCTAssertTrue(fixture.store.sharedText.contains("Source image SHA-256: \(fixture.image.imageSHA256)"))
        XCTAssertTrue(fixture.store.sharedText.contains("Original OCR SHA-256: \(document.originalRecognitionDigest)"))
        XCTAssertEqual(fixture.store.prompt, "Keep this unsent request exactly.\r\n")
        XCTAssertEqual(fixture.store.pastedDocumentDraft.title, "Pending paste")
        XCTAssertEqual(fixture.store.pastedDocumentDraft.text, "Unimported text.")
        XCTAssertFalse(fixture.store.workingCopyIsPasted)
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy)
        XCTAssertFalse(fixture.store.canUndoWorkingCopyEdit)
        XCTAssertTrue(fixture.store.documentWork.records.isEmpty)
        XCTAssertTrue(fixture.store.documentProcedures.procedures.isEmpty)
        XCTAssertTrue(fixture.store.readingSources.sources.isEmpty)
        XCTAssertTrue(fixture.store.keptLessons.isEmpty)
        XCTAssertTrue(fixture.store.tokenSteward.tasks.isEmpty)
        XCTAssertEqual(fixture.store.evolution.revision, evolutionRevision)
        XCTAssertEqual(try fixture.savedFiles(), saved)
    }

    func testWrongImageDigestOrDimensionsRejectBeforeReplacementReview() async throws {
        let fixture = try await Fixture()
        defer { fixture.clean() }
        fixture.store.share(text: "Existing document.", name: "existing.txt")
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        let before = fixture.snapshot()
        let candidates = [
            try fixture.document(imageDigest: String(repeating: "a", count: 64)),
            try fixture.document(width: fixture.image.pixelWidth + 1)
        ]
        for document in candidates {
            XCTAssertFalse(fixture.store.importImageRegion(document, image: fixture.image, context: context,
                reviewWorkingCopy: { XCTFail("Mismatched pixels must be rejected before review."); return true }))
            XCTAssertEqual(fixture.snapshot(), before)
            XCTAssertNil(fixture.store.imageRegionWorkingSource)
            XCTAssertNil(fixture.store.imageRegionWorkingImage)
        }
    }

    func testChangedSourceBytesAndDifferentOwnerRejectCapturedIntakeContext() async throws {
        let fixture = try await Fixture(), other = try await Fixture()
        defer { fixture.clean(); other.clean() }
        let document = try fixture.document()
        fixture.store.share(text: "Café", name: "same.txt")
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        fixture.store.sharedText = "Cafe\u{301}"
        let changed = fixture.snapshot()
        XCTAssertFalse(fixture.store.importImageRegion(document, image: fixture.image, context: context,
            reviewWorkingCopy: { XCTFail("Changed source bytes cannot reach review."); return true }))
        XCTAssertEqual(fixture.snapshot(), changed)

        let current = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        other.store.share(text: fixture.store.sharedText, name: "same.txt")
        let otherBefore = other.snapshot()
        XCTAssertFalse(other.store.importImageRegion(document, image: fixture.image, context: current,
            reviewWorkingCopy: { XCTFail("Another store cannot admit the captured owner."); return true }))
        XCTAssertEqual(other.snapshot(), otherBefore)
        XCTAssertNil(other.store.imageRegionWorkingSource)
    }

    func testDeclinedAndReentrantReviewsPreserveLatestSource() async throws {
        let fixture = try await Fixture()
        defer { fixture.clean() }
        fixture.store.share(text: "Original document.", name: "original.txt")
        fixture.store.sharedText = "Unsaved edited document."
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        let document = try fixture.document()
        let before = fixture.snapshot()
        var reviews = 0
        XCTAssertFalse(fixture.store.importImageRegion(document, image: fixture.image, context: context,
            reviewWorkingCopy: { reviews += 1; return false }))
        XCTAssertEqual(reviews, 1)
        XCTAssertEqual(fixture.snapshot(), before)

        XCTAssertFalse(fixture.store.importImageRegion(document, image: fixture.image, context: context,
            reviewWorkingCopy: {
                fixture.store.share(text: "A newer source arrived.", name: "newer.txt")
                return true
            }))
        XCTAssertEqual(fixture.store.sharedText, "A newer source arrived.")
        XCTAssertEqual(fixture.store.sourceName, "newer.txt")
        XCTAssertNil(fixture.store.imageRegionWorkingSource)
        XCTAssertNil(fixture.store.imageRegionWorkingImage)
    }

    func testRegionCopyNeedsExactExportAndTextEditsNeverChangeOriginalPixels() async throws {
        let fixture = try await Fixture()
        defer { fixture.clean() }
        let originalBytes = try Data(contentsOf: fixture.imageURL)
        let document = try fixture.importRegion()
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy)
        fixture.store.sharedText = document.text + "Edited working text."
        fixture.store.sharedText = document.text
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy, "Restoring imported text is not an export receipt.")
        let export = fixture.directory.appendingPathComponent("region-copy.txt")
        let revision = fixture.store.sourceRevision
        XCTAssertFalse(fixture.store.exportWorkingCopy(to: export, expectedRevision: revision + 1))
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy)
        XCTAssertTrue(fixture.store.exportWorkingCopy(to: export, expectedRevision: revision))
        XCTAssertEqual(try Data(contentsOf: export), Data(document.text.utf8))
        XCTAssertFalse(fixture.store.hasUnexportedWorkingCopy)
        fixture.store.sharedText = document.text + "A later correction."
        XCTAssertTrue(fixture.store.hasUnexportedWorkingCopy)
        XCTAssertEqual(try Data(contentsOf: fixture.imageURL), originalBytes)
        let reread = try await ImageRegionReader.load(url: fixture.imageURL)
        XCTAssertEqual(reread.imageSHA256, fixture.image.imageSHA256)
    }

    func testSharingAnotherSourceAndStoppingRetireTransientImagePreview() async throws {
        let fixture = try await Fixture()
        defer { fixture.clean() }
        _ = try fixture.importRegion()
        XCTAssertNotNil(fixture.store.imageRegionWorkingSource)
        XCTAssertNotNil(fixture.store.imageRegionWorkingImage)
        fixture.store.share(text: "A normal file-backed copy.", name: "next.txt")
        XCTAssertNil(fixture.store.imageRegionWorkingSource)
        XCTAssertNil(fixture.store.imageRegionWorkingImage)
        XCTAssertFalse(fixture.store.hasUnexportedWorkingCopy)

        _ = try fixture.importRegion()
        fixture.store.stopSharing()
        XCTAssertNil(fixture.store.imageRegionWorkingSource)
        XCTAssertNil(fixture.store.imageRegionWorkingImage)
        XCTAssertNil(fixture.store.sourceName)
        XCTAssertNil(fixture.store.textSelection)
        XCTAssertFalse(fixture.store.hasUnexportedWorkingCopy)
    }

    func testExplicitRetainedSourceReopensWithRegionProvenanceAndOriginalHash() async throws {
        let fixture = try await Fixture()
        defer { fixture.clean() }
        let originalBytes = try Data(contentsOf: fixture.imageURL)
        let document = try fixture.document(body: "User-described shape and position.", original: "", method: .userDescription)
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        XCTAssertTrue(fixture.store.importImageRegion(document, image: fixture.image, context: context,
                                                       reviewWorkingCopy: { true }))
        XCTAssertTrue(fixture.store.readingSources.sources.isEmpty)
        fixture.store.keepCurrentReadingSource()
        let kept = try XCTUnwrap(fixture.store.readingSources.sources.first)
        XCTAssertEqual(Data(kept.text.utf8), Data(document.text.utf8))
        XCTAssertEqual(kept.provenance?.origin, .unknown)
        XCTAssertEqual(kept.provenance?.acquisition, .userCopy)
        XCTAssertTrue(kept.text.contains("Method: User description"))
        XCTAssertTrue(kept.text.contains("Original OCR: Not used."))
        XCTAssertTrue(kept.text.contains(document.source.identifier))
        XCTAssertTrue(kept.text.contains(fixture.image.imageSHA256))

        let url = fixture.directory.appendingPathComponent("preferences.reading-sources.json")
        let archiveBytes = try Data(contentsOf: url)
        let reopened = ReadingSourceLibrary(url: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.sources, [kept])
        XCTAssertNil(reopened.availability(of: kept.binding))
        XCTAssertEqual(try Data(contentsOf: url), archiveBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.imageURL), originalBytes)
        XCTAssertTrue(fixture.store.documentWork.records.isEmpty, "Retaining text is not a completed method outcome.")
        XCTAssertTrue(fixture.store.keptLessons.isEmpty)
    }

    func testOpenRegionDraftBlocksQuitAndRestoreBeforeOtherReviewCallbacks() async throws {
        let fixture = try await Fixture()
        defer { fixture.clean() }
        fixture.store.share(text: "Existing work.", name: "existing.txt")
        let before = fixture.snapshot()
        let saved = try fixture.savedFiles()
        XCTAssertNil(fixture.store.recoveryRestoreBlockReason)
        fixture.store.isImageRegionImportPresented = true
        var workingReviews = 0, evolutionReviews = 0
        XCTAssertFalse(fixture.store.confirmQuitRetainingWork(reviewWorkingCopy: {
            workingReviews += 1
            return true
        }, chooseEvolution: {
            evolutionReviews += 1
            return .quitWithoutSaving
        }))
        XCTAssertEqual(workingReviews, 0)
        XCTAssertEqual(evolutionReviews, 0)
        XCTAssertTrue(try XCTUnwrap(fixture.store.recoveryRestoreBlockReason).contains("image region"))
        XCTAssertEqual(fixture.snapshot(), before)
        XCTAssertEqual(try fixture.savedFiles(), saved)
        fixture.store.isImageRegionImportPresented = false
        XCTAssertNil(fixture.store.recoveryRestoreBlockReason)
    }

    func testOpenRegionDraftRetainsItsHostUntilSuccessfulImportConsumesIt() async throws {
        let fixture = try await Fixture()
        defer { fixture.clean() }
        fixture.store.open(.nodeLab)
        let context = try XCTUnwrap(fixture.store.beginPastedDocumentImport())
        var opened: [WorkspaceSection] = []
        var draftPresentedAtOpen: [Bool] = []
        var published: [WorkspaceSection] = []
        // Observe every change, without deduplication that could hide a
        // rejected intermediate route or recursive setter publication.
        let routeSubscription = fixture.store.$presentedSection.dropFirst().sink { published.append($0) }
        defer { routeSubscription.cancel() }
        fixture.store.onOpenWorkspace = { section in
            opened.append(section)
            draftPresentedAtOpen.append(fixture.store.isImageRegionImportPresented)
        }
        defer { fixture.store.onOpenWorkspace = nil }
        fixture.store.isImageRegionImportPresented = true
        fixture.store.section = .memory
        XCTAssertEqual(fixture.store.section, .nodeLab, "Direct menu routing cannot destroy the sheet's host.")
        XCTAssertTrue(fixture.store.isImageRegionImportPresented)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(published.isEmpty, "A rejected assignment must not publish a transient host.")

        fixture.store.open(.assistant)
        XCTAssertEqual(fixture.store.section, .nodeLab)
        XCTAssertTrue(fixture.store.isImageRegionImportPresented)
        XCTAssertTrue(opened.isEmpty, "A denied route must not invoke the native window callback.")
        XCTAssertTrue(published.isEmpty, "A denied open must not publish a route.")

        let invalid = try fixture.document(imageDigest: String(repeating: "a", count: 64))
        XCTAssertFalse(fixture.store.importImageRegion(invalid, image: fixture.image, context: context,
            reviewWorkingCopy: { XCTFail("Invalid intake cannot review or consume a draft."); return true }))
        XCTAssertTrue(fixture.store.isImageRegionImportPresented)
        XCTAssertEqual(fixture.store.section, .nodeLab)
        let document = try fixture.document()
        XCTAssertFalse(fixture.store.importImageRegion(document, image: fixture.image, context: context,
                                                       reviewWorkingCopy: { false }))
        XCTAssertTrue(fixture.store.isImageRegionImportPresented)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(published.isEmpty, "Failed or declined intake keeps the existing host unpublished.")

        XCTAssertTrue(fixture.store.importImageRegion(document, image: fixture.image, context: context,
                                                      reviewWorkingCopy: { true }))
        XCTAssertFalse(fixture.store.isImageRegionImportPresented)
        XCTAssertEqual(fixture.store.section, .context)
        XCTAssertEqual(opened, [.context])
        XCTAssertEqual(published, [.context], "Only the accepted destination is published, exactly once.")
        XCTAssertEqual(draftPresentedAtOpen, [false], "Consume only the accepted draft before switching its host.")
        XCTAssertEqual(fixture.store.imageRegionWorkingSource, document)
        XCTAssertEqual(Data(fixture.store.sharedText.utf8), Data(document.text.utf8))
    }

    private struct SourceSnapshot: Equatable {
        let bytes: Data
        let name: String?
        let revision: UInt64
        let prompt: String
        let selection: DocumentSelection?
        let region: ImageRegionDocument?
        let imageDigest: String?
        let unexported: Bool
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-image-region-import-\(UUID())")
        let client = NoCallsClient()
        let image: ImageRegionImage
        var imageURL: URL { directory.appendingPathComponent("original.png") }
        lazy var store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: client, assistantFactory: { [client] _, _ in client }, allowsPlay: false,
            tokenSteward: TokenStewardStore())

        init() async throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("original.png")
            let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8,
                bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 0.6, green: 0.1, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            context.setFillColor(CGColor(red: 0.9, green: 0.7, blue: 0.3, alpha: 1))
            context.fill(CGRect(x: 16, y: 12, width: 24, height: 20))
            let pixels = try XCTUnwrap(context.makeImage())
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, pixels, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            image = try await ImageRegionReader.load(url: url)
        }

        func document(body: String = "Reviewed region text.", original: String = "Original OCR text.",
                      title: String = "Selected image region", method: ImageRegionDocument.Method = .localOCR,
                      imageDigest: String? = nil, width: Int? = nil) throws -> ImageRegionDocument {
            let region = try XCTUnwrap(ImageRegionRect(x: 0.25, y: 0.125, width: 0.5, height: 0.75))
            let source = try XCTUnwrap(ImageRegionSource(imageSHA256: imageDigest ?? image.imageSHA256,
                pixelWidth: width ?? image.pixelWidth, pixelHeight: image.pixelHeight, region: region))
            return try XCTUnwrap(ImageRegionDocument(source: source, originalRecognition: original,
                reviewedText: body, title: title, method: method))
        }

        func importRegion() throws -> ImageRegionDocument {
            let document = try document()
            let context = try XCTUnwrap(store.beginPastedDocumentImport())
            XCTAssertTrue(store.importImageRegion(document, image: image, context: context,
                                                  reviewWorkingCopy: { true }), store.status)
            return document
        }

        func snapshot() -> SourceSnapshot {
            .init(bytes: Data(store.sharedText.utf8), name: store.sourceName, revision: store.sourceRevision,
                  prompt: store.prompt, selection: store.textSelection, region: store.imageRegionWorkingSource,
                  imageDigest: store.imageRegionWorkingImage?.imageSHA256, unexported: store.hasUnexportedWorkingCopy)
        }

        func savedFiles() throws -> [String: Data] {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            var files: [String: Data] = [:]
            for url in urls where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files[url.lastPathComponent] = try Data(contentsOf: url)
            }
            return files
        }

        func clean() {
            XCTAssertEqual(client.connections, 0)
            XCTAssertEqual(client.requests, 0)
            store.disconnectAssistant()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @MainActor private final class NoCallsClient: AssistantClient {
        private(set) var connections = 0
        private(set) var requests = 0
        func connect() async throws { connections += 1; XCTFail("Region import must not connect to a model.") }
        func disconnect() {}
        func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
            requests += 1
            XCTFail("Region import must not generate a model reply.")
            throw AssistantFailure.unavailable
        }
    }
}
