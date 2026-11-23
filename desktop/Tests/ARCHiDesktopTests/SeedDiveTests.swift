import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import ARCHiDesktop

final class SeedDiveTests: XCTestCase {
    @MainActor
    func testBundledPageLoadsLiveProjectionAndClearsRemovedContent() async throws {
        let application = NSApplication.shared
        let oldPolicy = application.activationPolicy()
        _ = application.setActivationPolicy(.accessory)
        application.finishLaunching()
        defer { _ = application.setActivationPolicy(oldPolicy) }
        let node = CompanionGraphNode(id: "synthetic", title: "Synthetic seed record", subtitle: "",
            kind: .lesson, status: "Kept", details: [.init(label: "Example", value: "Local test text")], target: .memory)
        let snapshot = CompanionGraphSnapshot(nodes: [node], edges: [], truncatedCount: 0)
        let failed = { XCTFail("The bundled page or snapshot delivery failed") }
        let host = NSHostingView(rootView: SeedDivePage(snapshot: snapshot, still: true, failed: failed))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 850, height: 620),
            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer { panel.contentView = nil; panel.close() }
        host.layoutSubtreeIfNeeded()
        try await waitForPage(in: host, script: """
            document.querySelector('#rail')?.textContent.includes('Local test text') === true
            && document.querySelector('#mode')?.textContent === 'Local snapshot'
            """)
        let web = try XCTUnwrap(webView(in: host))
        XCTAssertFalse(web.configuration.websiteDataStore.isPersistent)
        host.rootView = SeedDivePage(snapshot: .empty, still: true, failed: failed)
        try await waitForPage(in: host, script: """
            document.querySelector('#counts')?.textContent === '0 records / 0 links'
            && !document.body.innerText.includes('Local test text')
            """)
    }

    @MainActor
    private func webView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews {
            if let found = webView(in: child) { return found }
        }
        return nil
    }

    @MainActor
    private func waitForPage(in host: NSView, script: String) async throws {
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if let web = webView(in: host), !web.isHidden,
               let result = try? await web.evaluateJavaScript(script), result as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Timed out waiting for the seed inspector to reflect the current projection")
    }
}
