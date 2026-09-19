import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import ARCHiDesktop

final class HostedPlayLayoutTests: XCTestCase {
    @MainActor
    func testHabitatUsesTheNativePresenceArtworkForEveryStartingForm() throws {
        var formsByImage: [Data: Set<CompanionForm>] = [:]
        for form in CompanionForm.allCases {
            let data = try XCTUnwrap(CompanionPresenceArt.png(form: form, family: nil))
            let image = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(image.pixelsWide, 512)
            XCTAssertEqual(image.pixelsHigh, 512)
            XCTAssertLessThan(data.count, 1_400_000)
            formsByImage[data, default: []].insert(form)
        }
        // The selectable Particle Seed look and the personal KIN Seed deliberately
        // share the same portrait. Every other form keeps its own native drawing.
        let sharedImages = formsByImage.values.filter { $0.count > 1 }
        XCTAssertEqual(sharedImages, [Set([CompanionForm.kinSeed, .particleSeed])],
                       "Only the explicit Particle Seed alias may reuse a form's Habitat artwork")
        XCTAssertEqual(formsByImage.count, CompanionForm.allCases.count - 1)
        XCTAssertEqual(CompanionSeedAppearance.archiLight.starterForm, .corePearl)
        XCTAssertEqual(CompanionSeedAppearance.kinParticles.starterForm, .particleSeed)
    }

    @MainActor
    func testProductionNativeAppearanceReachesSceneWithoutChangingJourney() async throws {
        guard let assets = ProcessInfo.processInfo.environment["ARCHI_HOSTED_ASSETS_DIR"] else {
            throw XCTSkip("Provide bundled native assets to verify appearance delivery.")
        }
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: URL(fileURLWithPath: assets))
        host.updateAppearance(form: .companion, family: nil, reduceMotion: true)
        host.start()
        do {
            let deadline = Date().addingTimeInterval(15)
            while host.state != .ready {
                guard host.state != .unavailable, Date() < deadline else { throw NSError(domain: "NativeAppearance", code: 1, userInfo: [NSLocalizedDescriptionKey: host.status]) }
                try await Task.sleep(for: .milliseconds(30))
            }
            let view = try XCTUnwrap(host.webView)
            func waitForForm(_ id: String) async throws -> String {
                let deadline = Date().addingTimeInterval(15)
                var lastAppearance: [String: Any] = [:]
                while Date() < deadline {
                    let raw = try await view.callAsyncJavaScript("const state=JSON.parse(window.render_game_to_text()); return {id:state.companion.nativeAppearance?.id, ready:state.companion.nativeAppearance?.ready, revision:state.journey.revision};", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
                    lastAppearance = raw ?? [:]
                    if raw?["id"] as? String == id, raw?["ready"] as? Bool == true {
                        return try XCTUnwrap(raw?["revision"] as? String)
                    }
                    try await Task.sleep(for: .milliseconds(30))
                }
                throw NSError(domain: "NativeAppearance", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected \(id); last Habitat appearance: \(lastAppearance); native delivery: \(host.appearanceDeliveryDiagnostics)"])
            }
            let before = try await waitForForm("Companion:origin")
            print("Initial production appearance delivery: \(host.appearanceDeliveryDiagnostics)")
            let originalSession = host.sessionID
            let reference = try XCTUnwrap(CompanionPresenceArt.png(form: .companion, family: nil))
            let candidate = try ReactorFrameCompositor.makeLocalPreviewFrame(approvedReferencePNG: reference, phase: 0.5)
            let expression = try ReactorFrameCompositor.composite(candidatePNG: candidate, approvedReferencePNG: reference)
            host.updateAppearance(form: .companion, family: nil, reduceMotion: false, expressionPNG: expression.pngData, expressionRevision: 1)
            let moving = try await waitForForm("Companion:origin-expression-1")
            XCTAssertEqual(before, moving, "Expression frames must not change Journey")
            XCTAssertEqual(host.sessionID, originalSession, "Expression must retain the existing play session")
            // A queued frame must not overtake the immediate static restoration.
            host.updateAppearance(form: .companion, family: nil, reduceMotion: false, expressionPNG: expression.pngData, expressionRevision: 2)
            host.updateAppearance(form: .companion, family: nil, reduceMotion: true, expressionPNG: expression.pngData, expressionRevision: 3)
            let still = try await waitForForm("Companion:origin")
            XCTAssertEqual(before, still, "Reduce Motion must restore art without changing Journey")
            XCTAssertEqual(host.sessionID, originalSession)
            host.updateAppearance(form: .companion, family: nil, reduceMotion: true, treatment: .pearlStudy)
            let pearl = try await waitForForm("Companion:origin:\(CompanionVisualAsset.revision)")
            XCTAssertEqual(before, pearl, "A finish change must invalidate art without changing Journey")
            let journeyOrigin = try XCTUnwrap(host.projection?.originDigest,
                "Production v2 projection must supply the existing individual before natural delivery")
            let natural = try XCTUnwrap(CompanionNaturalVariation.make(originDigest: journeyOrigin))
            for family in [EvolutionFamily?.none, .some(.lumen)] {
                let id = CompanionVisualAsset.appearanceID(form: .companion, family: family,
                    treatment: .pearlStudy, naturalVariation: natural)
                host.updateAppearance(form: .companion, family: family, reduceMotion: true,
                    treatment: .pearlStudy, naturalVariation: natural)
                let delivered = try await waitForForm(id)
                XCTAssertEqual(before, delivered, "Natural details are presentation and must not rewrite Journey")
                XCTAssertEqual(host.projection?.originDigest, journeyOrigin)
                XCTAssertEqual(host.sessionID, originalSession, "Natural variation must retain the mounted Habitat session")
                XCTAssertTrue(host.webView === view, "Appearance delivery must not replace the retained WebKit view")
            }
            for origin in ["a", "b"] {
                let recipe = try XCTUnwrap(CompanionAppearanceRecipe.make(originDigest: String(repeating: origin, count: 64),
                    family: .lumen, role: .muse, helpStyle: .reflective, basisKind: .usefulWork))
                let id = CompanionVisualAsset.appearanceID(form: .companion, family: .lumen, treatment: .pearlStudy, recipe: recipe)
                host.updateAppearance(form: .companion, family: .lumen, reduceMotion: true, treatment: .pearlStudy, recipe: recipe)
                let individual = try await waitForForm(id)
                XCTAssertEqual(before, individual, "Individual details must not rewrite Journey")
                XCTAssertEqual(host.sessionID, originalSession, "Same-family recipe changes must retain the mounted Habitat")
            }
            let equipped = CompanionEquipment(hand: .focusStaff)
            let equippedID = CompanionVisualAsset.appearanceID(form: .companion, family: nil,
                treatment: .pearlStudy, naturalVariation: natural, equipment: equipped)
            host.updateAppearance(form: .companion, family: nil, reduceMotion: true,
                treatment: .pearlStudy, naturalVariation: natural, equipment: equipped)
            let equippedRevision = try await waitForForm(equippedID)
            XCTAssertEqual(before, equippedRevision, "Equipping changes artwork without changing Journey")
            XCTAssertEqual(host.projection?.originDigest, journeyOrigin)
            XCTAssertEqual(host.sessionID, originalSession)
            XCTAssertTrue(host.webView === view)
            host.updateAppearance(form: .companion, family: nil, reduceMotion: true,
                treatment: .pearlStudy, naturalVariation: natural, equipment: .empty)
            let unequippedID = CompanionVisualAsset.appearanceID(form: .companion, family: nil,
                treatment: .pearlStudy, naturalVariation: natural)
            let unequippedRevision = try await waitForForm(unequippedID)
            XCTAssertEqual(before, unequippedRevision, "Removing the staff restores the same individual")
            host.updateAppearance(form: .companion, family: nil, reduceMotion: true, treatment: .original)
            let returned = try await waitForForm("Companion:origin")
            XCTAssertEqual(before, returned)
            let particleID = CompanionVisualAsset.appearanceID(form: .particle, family: nil,
                treatment: .original, naturalVariation: natural)
            host.updateAppearance(form: .particle, family: nil, reduceMotion: true,
                naturalVariation: natural)
            let particleRevision = try await waitForForm(particleID)
            XCTAssertEqual(before, particleRevision, "Particle light must retain the existing Journey")
            XCTAssertEqual(host.projection?.originDigest, journeyOrigin)
            XCTAssertEqual(host.sessionID, originalSession)
            XCTAssertTrue(host.webView === view, "Particle light must reuse the retained native Habitat view")
            let equippedParticleID = CompanionVisualAsset.appearanceID(form: .particle, family: nil,
                treatment: .original, naturalVariation: natural, equipment: equipped)
            host.updateAppearance(form: .particle, family: nil, reduceMotion: true,
                naturalVariation: natural, equipment: equipped)
            let equippedParticleRevision = try await waitForForm(equippedParticleID)
            XCTAssertEqual(before, equippedParticleRevision, "Particle light's staff is presentation, not new Journey state")
            XCTAssertEqual(host.projection?.originDigest, journeyOrigin)
            XCTAssertEqual(host.sessionID, originalSession)
            XCTAssertTrue(host.webView === view)
            for form in [CompanionForm.kinSeed, .kinSimple, .kin, .kinSeed] {
                let id = CompanionVisualAsset.appearanceID(form: form, family: nil, treatment: .original)
                host.updateAppearance(form: form, family: nil, reduceMotion: true)
                let delivered = try await waitForForm(id)
                XCTAssertEqual(before, delivered, "KIN's form changes must retain the existing Journey")
                XCTAssertEqual(host.projection?.originDigest, journeyOrigin)
                XCTAssertEqual(host.sessionID, originalSession)
                XCTAssertTrue(host.webView === view, "KIN reuses the existing Habitat host")
            }
            host.updateAppearance(form: .light, family: nil, reduceMotion: true)
            let after = try await waitForForm("Guide light:origin")
            XCTAssertEqual(before, after, "Changing the native body must retain the same Journey")
            XCTAssertEqual(host.projection?.originDigest, journeyOrigin, "Returning to Guide light must preserve the individual")
            XCTAssertEqual(host.sessionID, originalSession)
            XCTAssertTrue(host.webView === view)
            await host.shutdown()
        } catch {
            await host.shutdown()
            throw error
        }
    }

    @MainActor
    func testInitialUnavailableArtworkRetriesOnlyTheLatestRequestAtValidatedReady() async throws {
        guard let assets = ProcessInfo.processInfo.environment["ARCHI_HOSTED_ASSETS_DIR"] else {
            throw XCTSkip("Set bundled assets to exercise deterministic initial-render failure recovery in the real native host.")
        }
        var rendered: [CompanionForm] = []
        var renderedEquipment: [CompanionEquipment] = []
        let equipped = CompanionEquipment(hand: .focusStaff)
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: URL(fileURLWithPath: assets),
            appearanceRenderer: { form, family, treatment, recipe, natural, equipment, seedColor in
                rendered.append(form)
                renderedEquipment.append(equipment)
                // Only the native image availability is controlled. The actual
                // bundled page, readiness projection, PNG decode and storage run.
                if rendered.count <= 2 { return nil }
                return CompanionPresenceArt.png(form: form, family: family, treatment: treatment,
                    recipe: recipe, naturalVariation: natural, equipment: equipment, seedColor: seedColor)
            })
        host.updateAppearance(form: .light, family: nil, reduceMotion: true)
        host.updateAppearance(form: .companion, family: nil, reduceMotion: true, equipment: equipped)
        let equippedID = CompanionVisualAsset.appearanceID(form: .companion, family: nil,
            treatment: .original, equipment: equipped)
        XCTAssertEqual(rendered, [.light, .companion])
        XCTAssertFalse(host.appearanceDeliveryDiagnostics.contains { $0.hasPrefix("scheduled") })
        host.start()
        do {
            try await waitForHiddenReady(host, label: "failed-initial-render readiness recovery")
            let view = try XCTUnwrap(host.webView), session = host.sessionID
            let revision = try XCTUnwrap(host.projection?.revision)
            let events = try XCTUnwrap(host.projection?.eventCount)
            let deadline = Date().addingTimeInterval(10)
            var last: [String: Any] = [:]
            while Date() < deadline {
                last = try await view.callAsyncJavaScript("""
                    const state = JSON.parse(window.render_game_to_text());
                    return {id: state.companion.nativeAppearance?.id, ready: state.companion.nativeAppearance?.ready,
                            revision: state.journey.revision, eventCount: state.journey.ledger.eventCount};
                    """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
                if last["id"] as? String == equippedID, last["ready"] as? Bool == true,
                   host.appearanceDeliveryDiagnostics.contains(where: { $0.hasPrefix("ack=true") }) { break }
                try await Task.sleep(for: .milliseconds(30))
            }
            XCTAssertEqual(last["id"] as? String, equippedID,
                "Latest startup appearance did not recover: \(last); \(host.appearanceDeliveryDiagnostics)")
            XCTAssertEqual(last["ready"] as? Bool, true)
            XCTAssertEqual(rendered, [.light, .companion, .companion],
                "Ready retries only the latest failed inputs once; an older request cannot revive")
            XCTAssertEqual(renderedEquipment, [.empty, equipped, equipped],
                "The one readiness retry must retain the latest equipment with the body")
            XCTAssertEqual(last["revision"] as? String, revision)
            XCTAssertEqual(last["eventCount"] as? Int, events)
            XCTAssertEqual(host.sessionID, session)
            XCTAssertTrue(host.webView === view)
            let scheduled = host.appearanceDeliveryDiagnostics.filter { $0.hasPrefix("scheduled") }
            XCTAssertFalse(scheduled.isEmpty)
            XCTAssertTrue(scheduled.allSatisfy { $0.contains("state=ready") }, "Document completion alone cannot authorize delivery before the bridge is ready")
            XCTAssertTrue(host.appearanceDeliveryDiagnostics.contains { $0.hasPrefix("ack=true") })
            print("Controlled initial-render recovery: \(host.appearanceDeliveryDiagnostics)")
            await host.shutdown()
        } catch {
            print("Initial-render recovery failed: \(host.appearanceDeliveryDiagnostics)")
            await host.shutdown()
            throw error
        }
    }

    /// Starts the same production host used at app launch without mounting or
    /// activating a window. It observes existing persistence and never creates
    /// a second identity, confirms preferences, or performs game actions.
    @MainActor
    func testHiddenProductionStartupAndReopenRestoreNaturalIndividualWithoutActivity() async throws {
        guard let assets = ProcessInfo.processInfo.environment["ARCHI_HOSTED_ASSETS_DIR"] else {
            throw XCTSkip("Set bundled assets to verify hidden native startup and same-profile individual continuity.")
        }
        let directory = URL(fileURLWithPath: assets)
        let first = HostedPlayHost(profile: .acceptance, assetDirectory: directory)
        let evolution = EvolutionStore()
        first.onJourneyOriginChanged = { [weak evolution] origin in evolution?.observeJourneyOrigin(origin) }
        var second: HostedPlayHost?
        var stage = "first-hidden-startup"
        do {
            XCTAssertFalse(first.isVisible)
            XCTAssertNil(evolution.naturalVariation)
            first.start()
            try await waitForHiddenReady(first, label: stage)
            let projection = try XCTUnwrap(first.projection)
            let origin = try XCTUnwrap(projection.originDigest)
            let natural = try XCTUnwrap(evolution.naturalVariation,
                "The production origin callback must establish natural details before any settings or task")
            XCTAssertEqual(natural.originDigest, origin)
            XCTAssertEqual(projection.storage, .localBrowser, "Reopen continuity requires an actual persistent acceptance-profile Journey")
            XCTAssertNil(evolution.practiceJourneyOriginDigest, "No explicit practice-history binding is needed for natural details")
            assertNoEvolutionActivity(evolution)
            let view = try XCTUnwrap(first.webView)
            XCTAssertNil(view.window, "Hidden startup must not manufacture a presented app or browser window")
            let before = try await hiddenReadback(view)
            XCTAssertEqual(before["inert"] as? Bool, true)
            XCTAssertEqual(before["mode"] as? String, "habitat")
            let persisted = try XCTUnwrap(before["savedJourney"] as? String,
                "A local persistent Journey must be present for this continuity check")
            let session = first.sessionID
            let initialRevision = try XCTUnwrap(projection.revision)
            let initialCount = try XCTUnwrap(projection.eventCount)

            stage = "hidden-idle-without-activity"
            try await Task.sleep(for: .milliseconds(650))
            let after = try await hiddenReadback(view)
            XCTAssertEqual(NSDictionary(dictionary: after), NSDictionary(dictionary: before),
                "Hidden idle must leave canonical Journey, player position, presentation phase, and stored bytes unchanged")
            XCTAssertFalse(first.isVisible)
            XCTAssertEqual(first.projection?.visible, false)
            XCTAssertEqual(first.projection?.revision, initialRevision)
            XCTAssertEqual(first.projection?.eventCount, initialCount)
            XCTAssertEqual(first.sessionID, session)
            XCTAssertEqual(evolution.naturalVariation, natural)
            assertNoEvolutionActivity(evolution)
            await first.shutdown()
            XCTAssertNil(first.webView)

            stage = "fresh-hidden-host-same-profile"
            let reopened = HostedPlayHost(profile: .acceptance, assetDirectory: directory)
            second = reopened
            let reopenedEvolution = EvolutionStore()
            reopened.onJourneyOriginChanged = { [weak reopenedEvolution] origin in
                reopenedEvolution?.observeJourneyOrigin(origin)
            }
            reopened.start()
            try await waitForHiddenReady(reopened, label: stage)
            XCTAssertNotEqual(reopened.sessionID, session, "A fresh transport session must read the same individual")
            XCTAssertEqual(reopened.projection?.originDigest, origin)
            XCTAssertEqual(reopened.projection?.revision, initialRevision)
            XCTAssertEqual(reopened.projection?.eventCount, initialCount)
            XCTAssertEqual(reopenedEvolution.naturalVariation, natural)
            XCTAssertEqual(reopenedEvolution.naturalVariation?.fingerprint, natural.fingerprint)
            XCTAssertNil(reopenedEvolution.practiceJourneyOriginDigest)
            assertNoEvolutionActivity(reopenedEvolution)
            let reopenedView = try XCTUnwrap(reopened.webView)
            XCTAssertNil(reopenedView.window)
            let reopenedState = try await hiddenReadback(reopenedView)
            XCTAssertEqual(reopenedState["savedJourney"] as? String, persisted,
                "Simply reopening the hidden host must not append work or rewrite the Journey")
            XCTAssertEqual(reopenedState["inert"] as? Bool, true)
            XCTAssertFalse(reopened.isVisible)
            XCTAssertEqual(reopened.projection?.visible, false)
            print("Hidden individual continuity: same origin and fingerprint; unchanged Journey revision \(initialRevision), \(initialCount) events; no preferences or activities added.")
            await reopened.shutdown()
        } catch {
            print("Hidden individual acceptance failed at \(stage): \(error.localizedDescription). First host: \(first.state.rawValue), \(first.status). Second host: \(second?.status ?? "not started")")
            await first.shutdown()
            await second?.shutdown()
            throw error
        }
    }

    @MainActor
    private func waitForHiddenReady(_ host: HostedPlayHost, label: String) async throws {
        let deadline = Date().addingTimeInterval(20)
        while host.state != .ready || host.projection?.originDigest == nil {
            guard host.state != .unavailable, Date() < deadline else {
                throw NSError(domain: "HiddenNativeIndividual", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(label): expected a ready v2 origin projection; state=\(host.state.rawValue), projectionVersion=\(host.projection?.version.description ?? "none"), status=\(host.status)"])
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertFalse(host.isVisible, label)
        XCTAssertEqual(host.projection?.visible, false, label)
    }

    @MainActor
    private func hiddenReadback(_ view: WKWebView) async throws -> [String: Any] {
        let value = try await view.callAsyncJavaScript("""
            const state = JSON.parse(window.render_game_to_text());
            return {
              inert: document.getElementById('app').inert,
              mode: state.mode,
              journeyRevision: state.journey.revision,
              eventCount: state.journey.ledger.eventCount,
              savedJourney: localStorage.getItem('archi.journey.v3'),
              player: {x: state.companion.x, y: state.companion.y, vx: state.companion.vx, vy: state.companion.vy},
              presentation: state.presentation.sequence,
              activityMilestones: state.activityMilestones,
              practice: state.battle
            };
            """, arguments: [:], in: nil, contentWorld: .page)
        return try XCTUnwrap(value as? [String: Any], "Expected actual hidden production-game read-back")
    }

    @MainActor
    private func assertNoEvolutionActivity(_ evolution: EvolutionStore, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(evolution.preferences.confirmedCount, 0, file: file, line: line)
        XCTAssertTrue(evolution.usefulReceipts.isEmpty, file: file, line: line)
        XCTAssertTrue(evolution.reviewedPractices.isEmpty, file: file, line: line)
        XCTAssertTrue(evolution.history.isEmpty, file: file, line: line)
        XCTAssertNil(evolution.proposal, file: file, line: line)
        XCTAssertNil(evolution.activeFamily, file: file, line: line)
        XCTAssertFalse(evolution.hasUnsavedChanges, file: file, line: line)
    }

    @MainActor
    func testViewportSizingHonorsFiniteAndZeroProposalsWithoutDocumentSize() {
        XCTAssertEqual(HostedPlayViewContainer.proposedSize(ProposedViewSize(width: 816, height: 530)), CGSize(width: 816, height: 530))
        XCTAssertEqual(HostedPlayViewContainer.proposedSize(.zero), .zero)
        XCTAssertEqual(HostedPlayViewContainer.proposedSize(.unspecified), CGSize(width: 640, height: 420))
        XCTAssertEqual(HostedPlayViewContainer.proposedSize(ProposedViewSize(width: .infinity, height: .infinity)), CGSize(width: 640, height: 420))
    }

    @MainActor
    func testRetiredContainerCannotDetachRetainedViewFromReplacement() {
        let webView = WKWebView(frame: .zero)
        let oldContainer = HostedPlayViewContainer(frame: NSRect(x: 0, y: 0, width: 816, height: 530))
        let newContainer = HostedPlayViewContainer(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        oldContainer.install(webView)
        newContainer.install(webView)
        oldContainer.detach()
        XCTAssertTrue(webView.superview === newContainer, "SwiftUI may dismantle an old wrapper after mounting the retained view elsewhere")
        XCTAssertEqual(newContainer.subviews.count, 1)
        XCTAssertEqual(webView.frame, newContainer.bounds)
    }

    @MainActor
    func testContainerResizesAndReplacesWebViewWithoutLeavingOldChild() {
        let first = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 2000))
        let second = WKWebView(frame: .zero)
        let container = HostedPlayViewContainer(frame: NSRect(x: 0, y: 0, width: 816, height: 530))
        container.install(first)
        XCTAssertEqual(first.frame, container.bounds)
        container.setFrameSize(NSSize(width: 616, height: 420))
        container.layout()
        XCTAssertEqual(first.frame, container.bounds)
        container.install(second)
        XCTAssertNil(first.superview)
        XCTAssertTrue(second.superview === container)
        XCTAssertEqual(container.subviews.count, 1)
        XCTAssertEqual(second.frame, container.bounds)
        container.detach()
        XCTAssertNil(second.superview)
        XCTAssertTrue(container.subviews.isEmpty)
    }

    /// Uses the actual WorkspaceView, retained WKWebView and production assets.
    /// Geometry proof is independent of document visibility and game actions.
    @MainActor
    func testProductionWorkspaceKeepsWebKitWithinWindowAcrossResize() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let assetPath = environment["ARCHI_HOSTED_ASSETS_DIR"],
              let fixturePath = environment["ARCHI_HOSTED_FIXTURES_DIR"] else {
            throw XCTSkip("Set bundled assets and fixture paths for actual SwiftUI/WebKit workspace layout acceptance.")
        }
        let output = URL(fileURLWithPath: fixturePath, isDirectory: true)
            .appendingPathComponent("layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let application = NSApplication.shared
        let oldPolicy = application.activationPolicy()
        _ = application.setActivationPolicy(.accessory)
        defer { _ = application.setActivationPolicy(oldPolicy) }
        application.finishLaunching()
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: URL(fileURLWithPath: assetPath))
        let store = CompanionStore(preferenceURL: output.appendingPathComponent("unused-preferences.json"))
        store.section = .play
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1080, height: 750),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Isolated Workspace Layout Acceptance"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 880, height: 640)
        let hosting = NSHostingView(rootView: WorkspaceView(store: store, playHost: host))
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        application.activate()
        var samples: [[String: Any]] = []
        do {
            let deadline = Date().addingTimeInterval(25)
            while host.state != .ready && host.state != .unavailable {
                guard Date() < deadline else { throw NSError(domain: "HostedPlayLayoutTests", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Production workspace readiness timed out"] ) }
                try await Task.sleep(for: .milliseconds(30))
            }
            XCTAssertEqual(host.state, .ready, host.status)
            let webView = try XCTUnwrap(host.webView)
            for size in [NSSize(width: 1080, height: 750), NSSize(width: 880, height: 640), NSSize(width: 1080, height: 750)] {
                window.setContentSize(size)
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                let webRect = webView.convert(webView.bounds, to: nil)
                let contentRect = window.contentLayoutRect
                let viewport = try await webView.callAsyncJavaScript(
                    "return {width: innerWidth, height: innerHeight, visibility: document.visibilityState};",
                    arguments: [:], in: nil, contentWorld: .page)
                var ancestors: [[String: Any]] = []
                var current: NSView? = webView
                while let view = current {
                    ancestors.append(["type": String(describing: type(of: view)), "frame": NSStringFromRect(view.frame),
                        "bounds": NSStringFromRect(view.bounds), "fittingSize": NSStringFromSize(view.fittingSize)])
                    current = view.superview
                }
                samples.append(["requestedContentSize": NSStringFromSize(size), "windowContentRect": NSStringFromRect(contentRect),
                    "hostingFrame": NSStringFromRect(hosting.frame), "hostingBounds": NSStringFromRect(hosting.bounds),
                    "webRectInWindow": NSStringFromRect(webRect), "viewport": viewport ?? NSNull(), "ancestors": ancestors])
                try JSONSerialization.data(withJSONObject: ["schema": "archi-hosted-layout/v1", "samples": samples],
                    options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("layout.json"))
                XCTAssertEqual(hosting.frame.height, size.height, accuracy: 1)
                XCTAssertGreaterThan(webRect.width, 300)
                XCTAssertGreaterThan(webRect.height, 200)
                XCTAssertTrue(contentRect.insetBy(dx: -1, dy: -1).contains(webRect),
                    "WebKit must fit inside native content; web=\(webRect), content=\(contentRect)")
            }
            print("Actual workspace layout artifacts: \(output.path)")
            await host.shutdown()
            await store.shutdownAssistant()
            window.contentView = nil; window.close()
        } catch {
            print("Workspace layout failure artifacts: \(output.path)")
            await host.shutdown()
            await store.shutdownAssistant()
            window.contentView = nil; window.close()
            throw error
        }
    }
}
