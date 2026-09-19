import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class MarketplacePresentationTests: XCTestCase {
    @MainActor
    func testCustomLabelsFitHostedUTF16LimitWithoutSplittingCharacters() throws {
        let names = [String(repeating: "W", count: 24), String(repeating: "🌱", count: 12),
            String(repeating: "e\u{301}", count: 12), "👩‍👩‍👧‍👦👩‍👩‍👧‍👦ab"]
        var truncated = false
        for family in EvolutionFamily.allCases {
            for role in EvolutionRole.allCases {
                for style in EvolutionHelpStyle.allCases {
                    let recipe = try XCTUnwrap(CompanionAppearanceRecipe.make(
                        originDigest: String(repeating: "a", count: 64), family: family,
                        role: role, helpStyle: style, basisKind: .usefulWork))
                    for treatment in CompanionVisualTreatment.allCases {
                        let base = CompanionVisualAsset.label(form: .companion, family: family,
                            treatment: treatment, recipe: recipe)
                        let legacy = CompanionVisualAsset.label(form: .companion, family: family,
                            treatment: treatment, recipe: recipe, equipment: .init(hand: .focusStaff))
                        XCTAssertEqual(legacy, base + " · Focus Staff", "Existing bundled labels remain exact.")
                        for name in names {
                            var design = CompanionItemPackage.creatorDefault
                            design.title = name
                            XCTAssertTrue(design.isValid)
                            let equipment = CompanionEquipment(hand: .focusStaff, design: design)
                            let displayTitle = try XCTUnwrap(equipment.item?.title)
                            let full = base + " · " + displayTitle
                            let actual = CompanionVisualAsset.label(form: .companion, family: family,
                                treatment: treatment, recipe: recipe, equipment: equipment)
                            XCTAssertLessThanOrEqual(actual.utf16.count, 80,
                                "JavaScript rejects labels over 80 UTF-16 units, including valid Unicode names.")
                            if full.utf16.count <= 80 {
                                XCTAssertEqual(actual, full)
                            } else {
                                truncated = true
                                XCTAssertTrue(actual.hasSuffix("…"))
                                let kept = Array(actual.dropLast())
                                XCTAssertEqual(kept, Array(full.prefix(kept.count)),
                                    "Truncation must preserve complete extended grapheme clusters.")
                            }
                            XCTAssertTrue(actual.contains(String(recipe.fingerprint.prefix(8))),
                                "Bounding the item name must preserve the companion recipe reference.")
                        }
                    }
                }
            }
        }
        XCTAssertTrue(truncated, "At least one fixture must exercise the overflow path.")
    }

    /// Opt-in evidence of the actual SwiftUI marketplace in the narrow content
    /// area. This never orders its panel front or activates an installed app.
    @MainActor
    func testHiddenMarketplaceAt630By500PreservesVisitState() async throws {
        _ = try await renderHiddenMarketplace()
    }

    @MainActor
    func testHiddenMarketplaceAccessibilityWhenNativeProxiesAreAvailable() async throws {
        let nodes = try await renderHiddenMarketplace()
        guard nodes.contains(where: { $0.id == "marketplace.search" }) else {
            throw XCTSkip("The hidden panel exposes AppKit children but no SwiftUI accessibility proxies. Native visible-window accessibility acceptance remains unverified.")
        }
        let labels = nodes.compactMap(\.label)
        XCTAssertTrue(labels.contains(where: { $0.contains("MARKETPLACE") }))
        XCTAssertTrue(labels.contains(where: { $0.contains("Free recipe access") }))
        XCTAssertTrue(nodes.contains(where: { $0.id == "marketplace.sections" }))
        for item in CompanionItemCatalog.designs {
            XCTAssertTrue(labels.contains(where: { $0.contains(item.title) }), item.title)
        }
    }

    @MainActor
    private func renderHiddenMarketplace() async throws -> [AccessibleText] {
        guard let path = ProcessInfo.processInfo.environment["ARCHI_MARKETPLACE_RENDER_DIR"] else {
            throw XCTSkip("Set ARCHI_MARKETPLACE_RENDER_DIR for hidden marketplace rendering evidence.")
        }
        let directory = URL(fileURLWithPath: path).appendingPathComponent("marketplace-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer { _ = app.setActivationPolicy(previousPolicy) }
        let client = MarketplacePresentationNoCalls()
        let preferenceURL = directory.appendingPathComponent("unused-preferences.json")
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: client, allowsPlay: false)
        let before = store.preferences
        let initialIdentity = store.reactor.appearanceID
        let hosting = NSHostingView(rootView: MarketplaceWorkspace(store: store)
            .frame(width: 630, height: 500).background(Color(nsColor: .windowBackgroundColor)))
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 630, height: 500),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        defer { panel.contentView = nil; panel.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(160))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.bounds.width, 630, accuracy: 1)
        XCTAssertEqual(hosting.bounds.height, 500, accuracy: 1)
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        let nodes = accessibleText(in: panel)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1_000)
        try png.write(to: directory.appendingPathComponent("discover-630x500.png"))
        let evidence: [String: Any] = ["width": 630, "height": 500, "windowShown": false,
            "realModelCalls": client.calls, "accessibility": nodes.map { ["id": $0.id ?? "", "label": $0.label ?? ""] },
            "swiftUIAccessibilityAvailable": nodes.contains(where: { $0.id == "marketplace.search" }),
            "boundary": "Hidden initial marketplace render; native clicks, scrolling and VoiceOver remain separate acceptance."]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("discover-630x500.json"))
        XCTAssertEqual(store.preferences, before)
        XCTAssertEqual(store.reactor.appearanceID, initialIdentity)
        XCTAssertTrue(store.itemLibrary.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferenceURL.path))
        XCTAssertEqual(client.calls, 0)
        await store.shutdownAssistant()
        return nodes
    }

    private struct AccessibleText {
        let id: String?
        let label: String?
    }

    @MainActor
    private func accessibleText(in root: NSObject) -> [AccessibleText] {
        var seen = Set<ObjectIdentifier>(), result: [AccessibleText] = []
        func visit(_ element: NSObject, depth: Int) {
            guard depth < 32, seen.count < 800, seen.insert(ObjectIdentifier(element)).inserted else { return }
            func value(_ name: String) -> Any? {
                let selector = NSSelectorFromString(name)
                return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
            }
            let attributes = element.accessibilityAttributeNames()
            let id = value("accessibilityIdentifier") as? String
                ?? (attributes.contains(.identifier) ? element.accessibilityAttributeValue(.identifier) as? String : nil)
            let values = [value("accessibilityLabel") as? String, value("accessibilityTitle") as? String,
                value("accessibilityValue") as? String, element.accessibilityAttributeValue(.title) as? String,
                element.accessibilityAttributeValue(.value) as? String]
            result.append(AccessibleText(id: id, label: values.compactMap { $0 }.first { !$0.isEmpty }))
            let modern = value("accessibilityChildren") as? [Any] ?? []
            let legacy = attributes.contains(.children) ? element.accessibilityAttributeValue(.children) as? [Any] ?? [] : []
            for child in modern + legacy { if let object = child as? NSObject { visit(object, depth: depth + 1) } }
            if let window = element as? NSWindow, let content = window.contentView { visit(content, depth: depth + 1) }
            if let view = element as? NSView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(root, depth: 0)
        return result
    }
}

@MainActor
private final class MarketplacePresentationNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1; throw AssistantFailure.configuration
    }
    func disconnect() {}
}
