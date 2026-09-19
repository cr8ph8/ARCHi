import AppKit
import ApplicationServices
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// A disposable native window and profile exercise the actual SwiftUI controls.
/// Import uses decoded fixture bytes; this is not NSOpenPanel or VoiceOver proof.
final class MarketplaceInteractionTests: XCTestCase {
    @MainActor
    func testNativeSearchKeepsDetailsWithinResultsAndFirstCollectionItemAppears() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_NATIVE"] == "1" else {
            throw XCTSkip("Set ARCHI_MARKETPLACE_NATIVE=1 for disposable native marketplace interaction evidence.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-marketplace-browse-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifacts = ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_RENDER_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("browse-\(UUID())") }
        if let artifacts { try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true) }
        let app = NSApplication.shared, policy = app.activationPolicy()
        let previousApp = NSWorkspace.shared.frontmostApplication
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer {
            _ = app.setActivationPolicy(policy)
            if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: []) }
        }
        let assistant = MarketplaceInteractionNoCalls()
        let profile = directory.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: profile,
            assistant: assistant, assistantFactory: { _, _ in assistant }, allowsPlay: false)
        let before = store.preferences
        let appearance = store.reactor.appearanceID
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 1100, height: 800),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "ARCHi · synthetic marketplace browsing"
        panel.contentView = NSHostingView(rootView: MarketplaceWorkspace(store: store)
            .frame(width: 1100, height: 800).preferredColorScheme(.dark)
            .background(WorkspaceTheme.background))
        panel.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { panel.contentView = nil; panel.close() }
        try await settle()
        await initializeFixtureAccessibility()
        guard node("marketplace.search", in: panel) != nil else {
            throw XCTSkip("The visible panel did not expose SwiftUI accessibility proxies; browsing acceptance remains unverified.")
        }
        try capture("01-wide-discover", panel: panel, directory: artifacts)
        XCTAssertTrue(try text("marketplace.detail.title", in: panel).contains(CompanionItemCatalog.designs[0].title))
        try setValue("Grove", on: "marketplace.search", in: panel)
        try await waitUntil { (try? self.text("marketplace.detail.title", in: panel).contains("Grove Staff")) == true }
        XCTAssertNil(node("marketplace.design.\(CompanionItemCatalog.designs[0].id.prefix(12))", in: panel))
        try capture("02-filtered-result", panel: panel, directory: artifacts)
        try setValue("No matching local recipe", on: "marketplace.search", in: panel)
        try await waitUntil { self.node("marketplace.detail.title", in: panel) == nil }
        XCTAssertNotNil(node("marketplace.empty-state", in: panel))
        XCTAssertNil(node("marketplace.collect", in: panel), "A hidden recipe must never retain an Add action.")
        try await settle()
        try press("marketplace.search.clear", in: panel)
        try await waitUntil { self.node("marketplace.detail.title", in: panel) != nil }
        XCTAssertEqual(store.preferences, before)
        XCTAssertEqual(store.reactor.appearanceID, appearance)
        XCTAssertNil(store.activeQiMon)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.path))
        try await settle()
        try capture("03-cleared-search", panel: panel, directory: artifacts)
        try selectSection("On this Mac", in: panel)
        try await waitUntil { self.node("marketplace.empty-state", in: panel) != nil }
        XCTAssertNil(node("marketplace.detail.title", in: panel))
        let grove = CompanionItemCatalog.designs[2]
        XCTAssertTrue(store.collectMarketItem(grove))
        try await waitUntil { self.node("marketplace.equip", in: panel) != nil }
        XCTAssertTrue(try text("marketplace.detail.title", in: panel).contains(grove.title))
        XCTAssertEqual(store.preferences, before, "Arrival in the collection never equips implicitly.")
        try capture("04-first-collected-item", panel: panel, directory: artifacts)
        // Model a checked download finishing while this workspace is unmounted.
        // Returning must offer review and must never silently install/equip it.
        let libraryBeforeReturn = store.itemLibrary
        panel.contentView = nil
        store.marketplaceCatalog.downloadedRecipe = CompanionItemCatalog.designs[0]
        panel.contentView = NSHostingView(rootView: MarketplaceWorkspace(store: store)
            .frame(width: 1100, height: 800).preferredColorScheme(.dark)
            .background(WorkspaceTheme.background))
        try await waitUntil { panel.attachedSheet != nil }
        XCTAssertEqual(store.importedMarketItem, CompanionItemCatalog.designs[0])
        XCTAssertEqual(store.itemLibrary, libraryBeforeReturn)
        XCTAssertEqual(store.preferences, before)
        let returnedReview = try XCTUnwrap(panel.attachedSheet)
        try await settle()
        try capture("05-download-review-on-return", panel: returnedReview, directory: artifacts)
        try press("marketplace.import.done", in: returnedReview)
        try await waitUntil { panel.attachedSheet == nil }
        XCTAssertEqual(assistant.calls, 0)
        await store.shutdownAssistant()
    }

    @MainActor
    func testNativeFullCollectionReviewExplainsLimitAndStillOpensCreate() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_NATIVE"] == "1" else {
            throw XCTSkip("Set ARCHI_MARKETPLACE_NATIVE=1 for disposable native marketplace interaction evidence.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-marketplace-capacity-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifacts = ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_RENDER_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("capacity-\(UUID())") }
        if let artifacts { try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true) }
        let app = NSApplication.shared, policy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer { _ = app.setActivationPolicy(policy) }
        let assistant = MarketplaceInteractionNoCalls()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"),
            assistant: assistant, assistantFactory: { _, _ in assistant }, allowsPlay: false)
        for index in 1...CompanionItemPackage.maximumLibraryCount {
            var item = CompanionItemPackage.creatorDefault; item.title = "Capacity \(index)"
            XCTAssertTrue(store.collectMarketItem(item))
        }
        let before = store.itemLibrary
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 630, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "ARCHi · synthetic collection limit"
        panel.contentView = NSHostingView(rootView: MarketplaceWorkspace(store: store)
            .frame(width: 630, height: 500).background(Color(nsColor: .windowBackgroundColor)))
        panel.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { panel.contentView = nil; panel.close() }
        try await settle()
        await initializeFixtureAccessibility()
        try capture("01-full-discover", panel: panel, directory: artifacts)
        guard node("marketplace.import", in: panel) != nil else {
            throw XCTSkip("The visible panel did not expose SwiftUI accessibility proxies; collection-limit native acceptance remains unverified.")
        }
        store.importedMarketItem = try CompanionItemPackage.decode(CompanionItemCatalog.designs[0].encoded())
        try await waitUntil { panel.attachedSheet != nil }
        let review = try XCTUnwrap(panel.attachedSheet)
        try await settle()
        XCTAssertTrue(try text("marketplace.collection-full", in: review).contains("collection is full"))
        let collect = try XCTUnwrap(node("marketplace.collect", in: review))
        XCTAssertFalse(try isEnabled(collect))
        XCTAssertNotNil(node("marketplace.import.status", in: review))
        try capture("02-full-import-review", panel: review, directory: artifacts)
        try press("marketplace.variation", in: review)
        try await waitUntil { panel.attachedSheet == nil && self.node("marketplace.create.title", in: panel) != nil }
        XCTAssertEqual(store.itemLibrary, before)
        XCTAssertTrue(store.preferences.equipment.isEmpty)
        XCTAssertEqual(assistant.calls, 0)
        await store.shutdownAssistant()
    }

    @MainActor
    func testNativeImportVariationOutfitAndWorkTogetherHandoff() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_NATIVE"] == "1" else {
            throw XCTSkip("Set ARCHI_MARKETPLACE_NATIVE=1 for disposable native marketplace interaction evidence.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-marketplace-native-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifactDirectory = ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_RENDER_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("native-\(UUID())") }
        if let artifactDirectory { try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true) }

        let app = NSApplication.shared, policy = app.activationPolicy()
        let previousApp = NSWorkspace.shared.frontmostApplication
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer {
            _ = app.setActivationPolicy(policy)
            if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApp?.activate(options: [])
            }
        }
        let assistant = MarketplaceInteractionNoCalls()
        let profile = directory.appendingPathComponent("preferences.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64),
                             welcomedAt: Date(timeIntervalSince1970: 1_800_000_000))
        _ = try NativePreferencePersistence.write(document: NativePreferenceDocument(qiMon: kin), to: profile, expected: nil)
        let store = CompanionStore(preferenceURL: profile, assistant: assistant,
            assistantFactory: { _, _ in assistant }, allowsPlay: false)
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let identity = try XCTUnwrap(store.activeQiMon)
        let source = "A useful passage. Another sentence."
        store.share(text: source, name: "synthetic-workshop.txt")
        store.open(.marketplace)
        let host = WorkspaceView.makeHostingView(store: store, playHost: play)
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 880, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "ARCHi · synthetic marketplace acceptance"
        panel.contentView = host
        WorkspaceView.applyWindowMinimum(to: panel)
        panel.setContentSize(CGSize(width: 880, height: 640))
        panel.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { store.stopFocusGesture(); panel.contentView = nil; panel.close() }
        try await settle()
        await initializeFixtureAccessibility()
        try capture("01-discover", panel: panel, directory: artifactDirectory)
        guard node("marketplace.import", in: panel) != nil else {
            throw XCTSkip("The visible disposable panel did not expose SwiftUI accessibility proxies. Screenshots were captured; native action acceptance remains unverified.")
        }
        XCTAssertTrue(panel.isVisible)
        XCTAssertLessThanOrEqual(host.bounds.width, 881)
        XCTAssertLessThanOrEqual(host.bounds.height, 641)
        XCTAssertTrue(try text("marketplace.outfit.current", in: panel).contains("No item"))
        XCTAssertTrue(try text("marketplace.outfit.saved", in: panel).contains("no saved outfit"))

        // Exercise the same review sheet using a strictly decoded recipe, without
        // opening a native file chooser or claiming that the chooser was tested.
        let imported = try CompanionItemPackage.decode(CompanionItemCatalog.designs[0].encoded())
        store.marketplaceMessage = "Decoded synthetic recipe. Review it before adding."
        store.importedMarketItem = imported
        try await waitUntil { panel.attachedSheet != nil }
        let review = try XCTUnwrap(panel.attachedSheet)
        try await settle()
        XCTAssertTrue(try text("marketplace.import.status", in: review).contains("Decoded synthetic recipe"))
        try capture("02-import-review", panel: review, directory: artifactDirectory)
        try press("marketplace.variation", in: review)
        try await waitUntil { panel.attachedSheet == nil && self.node("marketplace.create.title", in: panel) != nil }
        XCTAssertNil(store.importedMarketItem)
        XCTAssertNil(panel.attachedSheet, "Create must be revealed after the review sheet closes.")
        XCTAssertTrue(try text("marketplace.create.title", in: panel).contains(imported.title))
        try capture("03-create-variation", panel: panel, directory: artifactDirectory)

        try press("marketplace.collect", in: panel)
        try await waitUntil { store.itemLibrary.count == 1 && self.node("marketplace.equip", in: panel) != nil }
        let variation = try XCTUnwrap(store.itemLibrary.first)
        XCTAssertEqual(variation.title, imported.title)
        XCTAssertEqual(variation.creator, "Local creator")
        XCTAssertNotEqual(variation.id, imported.id)
        XCTAssertTrue(store.preferences.equipment.isEmpty, "Adding a recipe must not equip it implicitly.")
        XCTAssertNil(try NativePreferencePersistence.read(profile).document.preferences)
        try press("marketplace.equip", in: panel)
        try await waitUntil { store.preferences.equipment.design == variation && self.node("marketplace.use-work-together", in: panel) != nil }
        XCTAssertTrue(try text("marketplace.outfit.current", in: panel).contains(variation.title))
        XCTAssertTrue(try text("marketplace.outfit.saved", in: panel).contains("no saved outfit"))

        try press("marketplace.use-work-together", in: panel)
        try await waitUntil { store.section == .context && self.node("work.focus-staff", in: panel) != nil }
        XCTAssertEqual(store.sharedText, source)
        XCTAssertEqual(store.sourceName, "synthetic-workshop.txt")
        XCTAssertNil(store.textSelection, "Navigation cannot invent a selection or read another source.")
        XCTAssertNil(store.focusGesturePlayback)
        XCTAssertEqual(assistant.calls, 0)
        let document = try XCTUnwrap(nodes(panel).compactMap { $0 as? NSTextView }
            .first { $0.identifier?.rawValue == "shared-document-text" })
        XCTAssertEqual(document.string, source, "The app's actual document view must contain the shared copy.")
        panel.makeFirstResponder(document)
        document.setSelectedRange(NSRange(location: 0, length: 17))
        try await waitUntil { store.textSelection?.quote == "A useful passage." }
        try await settle()
        XCTAssertTrue(try text("work.selection-status", in: panel).contains("17"))
        try capture("04-work-together-selection", panel: panel, directory: artifactDirectory)

        // Return through the existing store navigation, then activate the native
        // route to the one existing preference owner and its Save controls.
        store.open(.marketplace)
        try await waitUntil { self.node("marketplace.outfit.review", in: panel) != nil }
        try press("marketplace.outfit.review", in: panel)
        try await waitUntil { store.section == .memory }
        try await settle()
        try capture("05-memory-save-controls", panel: panel, directory: artifactDirectory)
        try pressLabel("Remember my preferences", in: panel)
        try await waitUntil { store.rememberPreferences }
        try pressLabel("Save preferences", in: panel)
        try await waitUntil { store.savedMarketplaceEquipment?.design == variation }
        XCTAssertEqual(try NativePreferencePersistence.read(profile).document.preferences?.equipment.design, variation)
        store.open(.marketplace)
        try await waitUntil { self.node("marketplace.outfit.saved", in: panel) != nil }
        XCTAssertTrue(try text("marketplace.outfit.saved", in: panel).contains(variation.title))
        try capture("05-saved-outfit", panel: panel, directory: artifactDirectory)

        // An imported collected variation displays the real Unequip control.
        store.importedMarketItem = try CompanionItemPackage.decode(variation.encoded())
        try await waitUntil { panel.attachedSheet != nil }
        let equippedReview = try XCTUnwrap(panel.attachedSheet)
        try await settle()
        try press("marketplace.equip", in: equippedReview)
        try await waitUntil { store.preferences.equipment.isEmpty }
        try await settle()
        XCTAssertTrue(try text("marketplace.import.status", in: equippedReview).localizedCaseInsensitiveContains("unequip"))
        XCTAssertNil(node("marketplace.use-work-together", in: equippedReview))
        try press("marketplace.import.done", in: equippedReview)
        try await waitUntil { panel.attachedSheet == nil }
        XCTAssertTrue(try text("marketplace.outfit.current", in: panel).contains("No item"))
        XCTAssertTrue(try text("marketplace.outfit.saved", in: panel).contains(variation.title),
                      "This visit's unequip must not claim to erase the saved outfit.")
        try capture("06-current-vs-next-visit", panel: panel, directory: artifactDirectory)
        let beforeUnity = try Data(contentsOf: profile)
        let currentOutfit = store.preferences.equipment
        try press("marketplace.open-unity", in: panel)
        try await waitUntil { store.section == .unity && self.node("unity.workspace", in: panel) != nil }
        XCTAssertFalse(store.unityPresentation.isSharing, "Opening the Unity workspace must not begin sharing a presentation.")
        XCTAssertEqual(store.preferences.equipment, currentOutfit)
        XCTAssertEqual(try Data(contentsOf: profile), beforeUnity)
        try capture("07-unity-navigation", panel: panel, directory: artifactDirectory)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.presentationForm(for: store.preferences, role: .cursor), .kinSeed)
        XCTAssertEqual(assistant.calls, 0)
        XCTAssertNil(play.webView, "Arena stays absent from this acceptance host.")
        await store.shutdownAssistant()
        await play.shutdown()
        let reopened = CompanionStore(preferenceURL: profile, assistant: assistant,
            assistantFactory: { _, _ in assistant }, allowsPlay: false)
        XCTAssertEqual(reopened.itemLibrary, [variation])
        XCTAssertEqual(reopened.preferences.equipment.design, variation)
        XCTAssertEqual(reopened.activeQiMon, identity)
        XCTAssertEqual(assistant.calls, 0)
        await reopened.shutdownAssistant()
    }

    @MainActor
    func testNativeCreatorAccountPublishAcquireAndExplicitInstall() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_NATIVE"] == "1",
              let endpoint = ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_SERVICE_URL"] else {
            throw XCTSkip("Set ARCHI_MARKETPLACE_NATIVE=1 and an isolated ARCHI_MARKETPLACE_SERVICE_URL for creator UI acceptance.")
        }
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-native-creator-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifacts = ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_RENDER_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("creator-\(UUID())") }
        if let artifacts { try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true) }
        let app = NSApplication.shared, policy = app.activationPolicy()
        let previousApp = NSWorkspace.shared.frontmostApplication
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer {
            _ = app.setActivationPolicy(policy)
            if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: []) }
        }
        let assistant = MarketplaceInteractionNoCalls()
        let profile = directory.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: profile, assistant: assistant, assistantFactory: { _, _ in assistant }, allowsPlay: false)
        let service = store.marketplaceCatalog
        let preferences = store.preferences
        let panel = NSPanel(contentRect: CGRect(x: 90, y: 80, width: 1100, height: 820),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "ARCHi · disposable creator catalog acceptance"
        panel.contentView = NSHostingView(rootView: MarketplaceWorkspace(store: store)
            .frame(width: 1100, height: 820).preferredColorScheme(.dark).background(WorkspaceTheme.background))
        panel.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { panel.contentView = nil; panel.close() }
        try await settle(); await initializeFixtureAccessibility()
        try press("marketplace.account", in: panel)
        try await waitUntil { panel.attachedSheet != nil }
        let account = try XCTUnwrap(panel.attachedSheet)
        try await settle()
        try capture("01-explicit-connection", panel: account, directory: artifacts)
        try setValue(endpoint, on: "marketplace.account.endpoint", in: account)
        try press("marketplace.account.connect", in: account)
        try await waitUntil { service.connected && !service.isBusy }
        try selectSection("Create account", in: account)
        try await settle()
        try setValue("native_" + suffix, on: "marketplace.account.handle", in: account)
        try setValue("Synthetic Native Creator", on: "marketplace.account.display-name", in: account)
        try setValue("synthetic-native-password", on: "marketplace.account.password", in: account)
        try await settle()
        try press("marketplace.account.submit", in: account)
        try await waitUntil { !service.isBusy && service.message.contains("Account created") }
        try await settle()
        try setValue("synthetic-native-password", on: "marketplace.account.password", in: account)
        try await settle(); try press("marketplace.account.submit", in: account)
        try await waitUntil { service.account != nil && panel.attachedSheet == nil && !service.isBusy }
        XCTAssertEqual(service.account?.handle, "native_" + suffix)
        try selectSection("Create", in: panel)
        try await settle()
        try setValue("Native " + suffix, on: "marketplace.create.title", in: panel)
        // Rights text is deliberately authored fixture data; publish/save/add
        // below still activate the actual native actions and real HTTP service.
        service.provenance.attribution = "Synthetic native creator fixture"
        try press("marketplace.creator.rights", in: panel)
        try await settle()
        XCTAssertTrue(service.canSaveDraft)
        try press("marketplace.creator.save-draft", in: panel)
        try await waitUntil { service.editingListing != nil && !service.isBusy }
        let draft = try XCTUnwrap(service.editingListing)
        XCTAssertEqual(draft.version, 1)
        try capture("02-saved-listing-draft", panel: panel, directory: artifacts)
        try press("marketplace.creator.publish.\(draft.id)", in: panel)
        try await settle()
        try capture("02b-publish-confirmation", panel: panel.attachedSheet ?? panel, directory: artifacts)
        try pressLabel("Publish \(draft.recipe.title)", in: panel.attachedSheet ?? panel)
        try await waitUntil { service.listings.contains { $0.id == draft.id && $0.status == .published } && !service.isBusy }
        try selectSection("Discover", in: panel)
        try await settle()
        try press("marketplace.catalog.listing.\(draft.id)", in: panel)
        try await settle()
        try capture("03-published-catalog", panel: panel, directory: artifacts)
        try press("marketplace.catalog.acquire", in: panel)
        try await waitUntil { service.inventory.contains { $0.recipeID == draft.recipeID } && !service.isBusy }
        XCTAssertTrue(store.itemLibrary.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.path), "Publishing/acquiring must not write the companion profile.")
        try selectSection("Account library", in: panel)
        try await settle()
        let entry = try XCTUnwrap(service.inventory.first { $0.recipeID == draft.recipeID })
        try capture("04-account-library", panel: panel, directory: artifacts)
        try press("marketplace.library.download.\(entry.id)", in: panel)
        try await waitUntil { panel.attachedSheet != nil && store.importedMarketItem != nil }
        let review = try XCTUnwrap(panel.attachedSheet)
        try await settle()
        XCTAssertTrue(store.itemLibrary.isEmpty, "Download must stop at review.")
        try capture("05-downloaded-review", panel: review, directory: artifacts)
        try press("marketplace.collect", in: review)
        try await waitUntil { store.itemLibrary.contains(entry.recipe) && self.node("marketplace.equip", in: review) != nil }
        XCTAssertEqual(store.preferences, preferences, "The user must equip separately after installation.")
        try press("marketplace.equip", in: review)
        try await waitUntil { store.preferences.equipment.design == entry.recipe }
        try press("marketplace.import.done", in: review)
        try await waitUntil { panel.attachedSheet == nil }
        try capture("06-installed-and-equipped", panel: panel, directory: artifacts)
        XCTAssertEqual(assistant.calls, 0)
        XCTAssertNil(store.activeQiMon)
        await service.signOut(); await store.shutdownAssistant()
    }

    @MainActor private func settle() async throws { try await Task.sleep(for: .milliseconds(180)) }

    /// Request only the fixture process through the public AX client API. This
    /// installs SwiftUI's lazy native proxies without requesting permission or
    /// touching accessibility settings or another application's content.
    @MainActor private func initializeFixtureAccessibility() async {
        let pid = ProcessInfo.processInfo.processIdentifier
        let status = await Task.detached {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 1)
            var windows: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
            if status == .success, let windows = windows as? [AXUIElement] {
                for window in windows.prefix(2) {
                    var children: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)
                }
            }
            return status.rawValue
        }.value
        print("Marketplace fixture AX client initialization: \(status)")
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(15))
        }
        _ = try XCTUnwrap(condition() ? true : nil,
                          "Native presentation did not reach its expected state within three seconds.")
    }

    @MainActor private func nodes(_ root: NSObject) -> [NSObject] {
        var found: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject, depth: Int) {
            guard depth < 35, found.count < 2500, seen.insert(ObjectIdentifier(node)).inserted else { return }
            found.append(node)
            let selector = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: selector), let children = node.perform(selector)?.takeUnretainedValue() as? [NSObject] {
                for child in children { visit(child, depth: depth + 1) }
            }
            if node.accessibilityAttributeNames().contains(.children) {
                for child in node.accessibilityAttributeValue(.children) as? [NSObject] ?? [] { visit(child, depth: depth + 1) }
            }
            if let window = node as? NSWindow {
                if let content = window.contentView { visit(content, depth: depth + 1) }
                for child in window.childWindows ?? [] { visit(child, depth: depth + 1) }
            }
            if let view = node as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0); return found
    }

    @MainActor private func identifier(_ node: NSObject) -> String? {
        let selector = NSSelectorFromString("accessibilityIdentifier")
        return (node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil)
            ?? (node.accessibilityAttributeNames().contains(.identifier) ? node.accessibilityAttributeValue(.identifier) as? String : nil)
    }

    @MainActor private func role(_ node: NSObject) -> String? {
        let selector = NSSelectorFromString("accessibilityRole")
        return (node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil)
            ?? (node.accessibilityAttributeNames().contains(.role) ? node.accessibilityAttributeValue(.role) as? String : nil)
    }

    @MainActor private func isEnabled(_ node: NSObject) throws -> Bool {
        let selector = NSSelectorFromString("isAccessibilityEnabled")
        if node.responds(to: selector) {
            let getter = unsafeBitCast(node.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            return getter(node, selector)
        }
        return try XCTUnwrap(node.accessibilityAttributeValue(.enabled) as? NSNumber,
                             "The native action must expose its enabled state.").boolValue
    }

    @MainActor private func texts(_ node: NSObject) -> [String] {
        let modern = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].compactMap { name -> String? in
            let selector = NSSelectorFromString(name)
            return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil
        }
        return modern + [.title, .value, .description].compactMap { attribute -> String? in
            node.accessibilityAttributeNames().contains(attribute) ? node.accessibilityAttributeValue(attribute) as? String : nil
        }
    }

    @MainActor private func node(_ id: String, in root: NSObject) -> NSObject? { nodes(root).first { identifier($0) == id } }
    @MainActor private func text(_ id: String, in root: NSObject) throws -> String {
        texts(try XCTUnwrap(node(id, in: root), "Missing accessible text \(id)")).joined(separator: " | ")
    }
    @MainActor private func press(_ id: String, in root: NSObject) throws {
        try performPress(XCTUnwrap(node(id, in: root), "Missing native control \(id)"))
    }
    @MainActor private func pressLabel(_ label: String, in root: NSObject) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        // NSAlert exposes its button cell as AXButton, while the actual
        // NSButton can report AXUnknown through this in-process fixture. Send
        // the real native control action before considering proxy/cell Press.
        if let button = nodes(root).compactMap({ $0 as? NSButton }).first(where: { $0.title == label || texts($0).contains(label) }) {
            XCTAssertTrue(button.isEnabled)
            button.performClick(nil)
            return
        }
        let actionableRoles: Set<String> = ["AXButton", "AXCheckBox", "AXSwitch"]
        let matches = nodes(root).filter {
            texts($0).contains(label) && actionableRoles.contains(role($0) ?? "") && $0.responds(to: selector)
        }
        if let button = matches.compactMap({ $0 as? NSButton }).first {
            XCTAssertTrue(button.isEnabled)
            button.performClick(nil)
            return
        }
        try performPress(XCTUnwrap(matches.first, "Missing native action \(label)"))
    }
    @MainActor private func selectSection(_ title: String, in root: NSObject) throws {
        let control = try XCTUnwrap(nodes(root).compactMap { $0 as? NSSegmentedControl }.first { control in
            (0..<control.segmentCount).contains { control.label(forSegment: $0) == title }
        }, "Missing native segmented control for \(title)")
        let index = try XCTUnwrap((0..<control.segmentCount).first { control.label(forSegment: $0) == title })
        control.selectedSegment = index
        XCTAssertTrue(control.sendAction(control.action, to: control.target), "The native segmented control must send its selection action.")
    }
    @MainActor private func setValue(_ value: String, on id: String, in root: NSObject) throws {
        let placeholders = ["marketplace.search": "Find a design or creator",
            "marketplace.account.endpoint": "Service address", "marketplace.account.handle": "creator_name",
            "marketplace.account.display-name": "Your creator name", "marketplace.account.password": "12–128 characters",
            "marketplace.create.title": "24-character limit"]
        let field = try XCTUnwrap(nodes(root).compactMap { $0 as? NSTextField }.first {
            identifier($0) == id || (placeholders[id] != nil && $0.placeholderString == placeholders[id])
        }, "Missing native text field \(id)")
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView, "The native search field must become editable.")
        editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    }
    @MainActor private func performPress(_ node: NSObject) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        _ = try XCTUnwrap(node.responds(to: selector) ? true : nil, "Native element has no accessibility press action.")
        let action = unsafeBitCast(node.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        _ = try XCTUnwrap(action(node, selector) ? true : nil,
                          "The native accessibility press action failed: \(identifier(node) ?? texts(node).joined(separator: " | ")).")
    }

    @MainActor private func capture(_ name: String, panel: NSWindow, directory: URL?) throws {
        guard let directory, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        let evidence: [String: Any] = ["windowShown": panel.isVisible, "width": content.bounds.width,
            "height": content.bounds.height, "nodes": nodes(panel).map {
                ["id": identifier($0) ?? "", "role": role($0) ?? "", "type": String(describing: type(of: $0)), "text": texts($0).joined(separator: " | ")]
            },
            "boundary": "Native SwiftUI action controls with a disposable profile and decoded import fixture. No native Open/Save panel, keyboard navigation, VoiceOver, model or external service proof."]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(name + ".json"))
    }
}

@MainActor private final class MarketplaceInteractionNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
}
