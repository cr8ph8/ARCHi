import AppKit
import ApplicationServices
import SwiftUI
import XCTest
@testable import ARCHiDesktop

/// Opt-in native sheets over disposable records. No installed app, personal
/// profile, live assistant, game, or external accessibility target is used.
final class KnowledgeRecordInspectionPresentationTests: XCTestCase {
    @MainActor
    func testNativeMethodWorkReviewAndReopenUseTheSameRecords() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ARCHI_GRAPH_NATIVE_ACTIONS"] == "1",
              let path = environment["ARCHI_GRAPH_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("Opt in to disposable native method-flow interaction with ARCHI_GRAPH_NATIVE_ACTIONS and ARCHI_GRAPH_RENDER_DIR.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("method-journey-\(UUID())")
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-method-journey-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let preference = profile.appendingPathComponent("preferences.json")
        let usage = profile.appendingPathComponent("usage.json")
        var preferences = CompanionPreferences()
        preferences.reduceMotion = true; preferences.quiet = true
        try NativePreferenceDocument(preferences: preferences).encoded().write(to: preference)
        let client = MethodJourneyFixtureAssistant()
        func makeStore() -> CompanionStore {
            CompanionStore(preferenceURL: preference, assistant: client,
                assistantFactory: { _, _ in client }, allowsPlay: false, tokenSteward: TokenStewardStore(url: usage))
        }
        var store = makeStore()
        defer { store.cancelWork(); store.disconnectAssistant() }
        // Synthetic setup is explicit. Only later Press actions qualify native controls;
        // neither the fixed reply nor scripted Helpful review is learning evidence.
        let source = try store.readingSources.keep(title: "Synthetic plain-language guidance",
            text: "Use plain words and retain the requested action.")
        let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
            range: NSRange(location: 0, length: source.text.utf16.count))
        let draft = try store.readingSources.saveKnowledgePage(title: "Synthetic plain requests",
            body: "Use plain words and retain the requested action.", kind: .concept, anchors: [anchor])
        let page = try store.readingSources.reviewKnowledgePage(id: draft.id, expectedRevision: draft.revision)
        XCTAssertTrue(store.keepKnowledgeProcedure(page: page, title: "Synthetic plain-language method",
            instruction: "Use plain words and retain the requested action.", requirements: .init()))
        let method = try XCTUnwrap(store.documentProcedures.latestProcedures.first)
        let methodNodeID = DocumentMethodGraph.nodeID(method.binding)
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        let previousApp = NSWorkspace.shared.frontmostApplication
        _ = app.setActivationPolicy(.accessory); app.finishLaunching()
        defer {
            _ = app.setActivationPolicy(previousPolicy)
            if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: []) }
        }
        let window = WorkspaceWindow(contentRect: NSRect(x: 60, y: 60, width: 1200, height: 900),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Disposable method journey · scripted replies"
        window.isReleasedWhenClosed = false
        defer {
            for sheet in window.sheets { window.endSheet(sheet) }
            window.contentView = nil; window.close()
        }
        var previousRecord: DocumentWorkRecord?
        var previousTask: TokenStewardTask?
        for pass in 0..<2 {
            if pass == 1 {
                let retained = try files(in: profile)
                await store.shutdownAssistant()
                store = makeStore()
                XCTAssertEqual(try files(in: profile), retained, "Reopening must not rewrite retained records.")
                XCTAssertEqual(store.documentWork.records.first { $0.id == previousRecord?.id }, previousRecord)
                XCTAssertEqual(store.tokenSteward.tasks.first { $0.id == previousTask?.id }, previousTask)
                XCTAssertTrue(store.documentFeedbackUsageCurrent(try XCTUnwrap(previousRecord)))
                XCTAssertEqual(store.documentProcedures.procedures, [method])
                XCTAssertEqual(store.outcomes(for: method)?.helpful, 1)
                XCTAssertTrue(store.sharedText.isEmpty, "History cannot restore a discarded session-only copy.")
            }
            // Passage import/selection is fixture setup, not a tested text-entry action.
            let passage = pass == 0 ? "Please undertake a review of the report." : "Please conduct a review of the report."
            store.share(text: passage, name: "disposable-\(pass).txt")
            store.section = .nodeLab
            window.contentView = WorkspaceView.makeHostingView(store: store, playHost: play)
            window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
            try await settle(window)
            await initializeAccessibility()
            try await expect { self.node("companion-graph.list-toggle", in: window) != nil }
            if node("companion-graph.list-node.\(methodNodeID)", in: window) == nil {
                try press("companion-graph.list-toggle", in: window)
            }
            try await expect { self.node("companion-graph.list-node.\(methodNodeID)", in: window) != nil }
            try press("companion-graph.list-node.\(methodNodeID)", in: window)
            try await settle(window)
            XCTAssertEqual(store.selectedGraphNodeID, methodNodeID)
            try capture("selected-method-\(pass)", window: window, output: output)
            try await expect { self.node("companion-graph.open-target", in: window) != nil }
            try press("companion-graph.open-target", in: window)
            try await expect { window.attachedSheet != nil }
            let methodSheet = try XCTUnwrap(window.attachedSheet)
            try await settle(methodSheet)
            try capture("method-sheet-\(pass)", window: methodSheet, output: output)
            XCTAssertEqual(store.inspectedDocumentMethod?.binding, method.binding)
            XCTAssertFalse(store.isWorking)
            XCTAssertFalse(store.hasOpenKnowledgeDraft)
            XCTAssertTrue(store.documentProcedures.latestProcedures.contains(method))
            XCTAssertNil(store.documentProcedureUnavailable(method.binding))
            try press("document.inspect-method.try", in: methodSheet)
            try await expect { window.attachedSheet == nil && store.section == .context }
            store.selectText(range: NSRange(location: 0, length: passage.utf16.count), sourceRevision: store.sourceRevision)
            store.preparePassageRevision()
            store.documentRequirements = .init()
            store.setAssistantRoute(.automatic); store.setLocalWorkPreference(.reasoning)
            try await settle(window)
            XCTAssertTrue(store.canPrepareDocumentProcedure(method))
            try await expect { self.node("document.method-to-try.preview", in: window) != nil }
            try press("document.method-to-try.preview", in: window)
            try await expect { window.attachedSheet != nil }
            let preview = try XCTUnwrap(window.attachedSheet)
            try await settle(preview)
            try await expect { self.node("document.method-preview.confirm", in: preview) != nil }
            try press("document.method-preview.confirm", in: preview)
            try await expect { window.attachedSheet == nil }
            XCTAssertEqual(store.preparedDocumentProcedure, method.binding)
            XCTAssertEqual(client.requests.count, pass)
            try press("work.send", in: window)
            try await expect { client.requests.count == pass + 1 && !store.isWorking }
            XCTAssertEqual(client.requests.last?.prompt, method.instruction)
            XCTAssertEqual(client.requests.last?.localProcedureKnowledge, [page.binding])
            XCTAssertEqual(store.sharedText, passage, "Completion must not apply the edit.")
            try await expect { self.node("work.apply.qwen", in: window) != nil }
            try press("work.apply.qwen", in: window)
            try await expect { store.currentDocumentOutcome != nil }
            let applied = try XCTUnwrap(store.currentDocumentOutcome)
            XCTAssertEqual(store.sharedText, "Please review the report.")
            XCTAssertNil(applied.feedback)
            try await expect { self.node("document.helpful.\(applied.id)", in: window) != nil }
            try press("document.helpful.\(applied.id)", in: window)
            try await expect { store.currentDocumentOutcome?.feedback?.verdict == .helpful }
            let reviewed = try XCTUnwrap(store.currentDocumentOutcome)
            XCTAssertTrue(store.documentFeedbackUsageCurrent(reviewed))
            XCTAssertEqual(store.outcomes(for: method)?.helpful, pass + 1)
            let task = try XCTUnwrap(store.tokenSteward.tasks.first { $0.id == reviewed.requestID })
            XCTAssertEqual(task.requestProvenance?.knowledgeDependencies, [page.binding])
            XCTAssertEqual(task.requestProvenance?.readingDependencies, [source.binding])
            XCTAssertEqual(task.outcomes.last(where: { $0.kind == .userUseful })?.evidenceID,
                "document-review-" + (try XCTUnwrap(reviewed.feedback)).id)
            try await settle(window)
            try capture("0\(pass + 1)-reviewed-use", window: window, output: output)
            try press("document.method-follow-through.map.\(method.id).\(method.revision)", in: window)
            try await expect { store.section == .nodeLab && store.selectedGraphNodeID == methodNodeID }
            previousRecord = reviewed; previousTask = task
        }
        XCTAssertEqual(store.documentProcedures.procedures, [method], "Reusing a method must not create another family.")
        let historical = store.documentWork.records
        store.withdrawKnowledgePage(page)
        XCTAssertNotNil(store.documentProcedureUnavailable(method.binding))
        XCTAssertEqual(store.documentWork.records, historical, "Losing support must retain exact historical records.")
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertNil(play.webView)
        try await settle(window)
        try capture("03-source-withdrawn", window: window, output: output)
        await store.shutdownAssistant(); await play.shutdown()
        print("Disposable native method journey evidence: \(output.path)")
    }

    @MainActor
    func testNativeExactRecordSheetsPreserveMapAndMethodInspection() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ARCHI_GRAPH_NATIVE_ACTIONS"] == "1",
              let path = environment["ARCHI_GRAPH_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("Set ARCHI_GRAPH_NATIVE_ACTIONS=1 and ARCHI_GRAPH_RENDER_DIR for disposable exact-record sheet acceptance.")
        }
        let output = URL(fileURLWithPath: path).appendingPathComponent("record-inspection-\(UUID())")
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("archi-record-sheet-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        var preferences = CompanionPreferences()
        preferences.reduceMotion = true
        preferences.quiet = true
        let preference = profile.appendingPathComponent("preferences.json")
        try NativePreferenceDocument(preferences: preferences).encoded().write(to: preference)
        let client = RecordSheetNoCallsAssistant()
        let store = CompanionStore(preferenceURL: preference, assistant: client,
            assistantFactory: { _, _ in client }, allowsPlay: false, tokenSteward: TokenStewardStore())
        defer { store.disconnectAssistant() }
        let source = try store.readingSources.keep(title: "Synthetic original source",
            text: "Retain the original attribution beside each claim.")
        let anchor = try store.readingSources.makeAnchor(sourceID: source.id,
            range: NSRange(location: 0, length: source.text.utf16.count))
        let firstDraft = try store.readingSources.saveKnowledgePage(title: "Earlier synthetic concept",
            body: "Earlier fixture meaning: retain the original source attribution.", kind: .concept, anchors: [anchor])
        let original = try store.readingSources.reviewKnowledgePage(id: firstDraft.id, expectedRevision: firstDraft.revision)
        XCTAssertTrue(store.keepKnowledgeProcedure(page: original, title: "Synthetic attribution method",
            instruction: "Retain attribution beside each claim.", requirements: .init()))
        let method = try XCTUnwrap(store.documentProcedures.latestProcedures.first)
        let revisedDraft = try store.readingSources.saveKnowledgePage(id: original.id,
            expectedRevision: original.revision, title: "Later synthetic concept",
            body: "Later fixture meaning must never replace the earlier reference.", kind: .concept, anchors: [anchor])
        let current = try store.readingSources.reviewKnowledgePage(id: revisedDraft.id,
            expectedRevision: revisedDraft.revision)
        let historicalNode = try XCTUnwrap(store.memoryMapSnapshot().nodes.first {
            $0.target == .knowledgePage(original.binding)
        })
        store.section = .nodeLab
        store.prompt = "Keep this synthetic unsent draft."
        let prompt = store.prompt
        let before = try files(in: profile)
        let play = HostedPlayHost(profile: .acceptance, assetDirectory: nil)
        let app = NSApplication.shared, previousPolicy = app.activationPolicy()
        let previousApp = NSWorkspace.shared.frontmostApplication
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        defer {
            _ = app.setActivationPolicy(previousPolicy)
            if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: []) }
        }
        let window = WorkspaceWindow(contentRect: NSRect(x: 60, y: 60, width: 1100, height: 800),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ARCHi · Disposable exact-record inspection"
        window.isReleasedWhenClosed = false
        let host = WorkspaceView.makeHostingView(store: store, playHost: play)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer {
            for sheet in window.sheets {
                for nested in sheet.sheets { sheet.endSheet(nested) }
                window.endSheet(sheet)
            }
            window.contentView = nil
            window.close()
        }
        try await settle(window)
        guard window.isVisible else { throw XCTSkip("The disposable native window is unavailable; sheet acceptance remains unverified.") }
        await initializeAccessibility()
        guard await becomesReady({ self.node("companion-graph.list-toggle", in: window) != nil }) else {
            throw XCTSkip("The disposable window did not expose SwiftUI accessibility controls; exact-record sheet acceptance remains unverified.")
        }

        try press("companion-graph.list-toggle", in: window)
        try await settle(window)
        try press("companion-graph.list-node.\(historicalNode.id)", in: window)
        try await settle(window)
        XCTAssertEqual(store.selectedGraphNodeID, historicalNode.id)
        try press("companion-graph.open-target", in: window)
        try await expect { window.attachedSheet != nil }
        let pageSheet = try XCTUnwrap(window.attachedSheet)
        try await settle(pageSheet)
        try await expect { self.node("knowledge.inspect-record.page-body", in: pageSheet) != nil }
        XCTAssertEqual(store.inspectedKnowledgeRecord?.reference, .page(original.binding))
        try assertPage(original, excluding: current, in: pageSheet)
        try capture("01-historical-page", window: pageSheet, output: output)
        try pressLabel("Done", in: pageSheet)
        try await expect { window.attachedSheet == nil }
        XCTAssertNil(store.inspectedKnowledgeRecord)
        XCTAssertEqual(store.section, .nodeLab)
        XCTAssertEqual(store.selectedGraphNodeID, historicalNode.id)

        try press("companion-graph.list-node.\(DocumentMethodGraph.nodeID(method.binding))", in: window)
        try await settle(window)
        try press("companion-graph.open-target", in: window)
        try await expect { window.attachedSheet != nil }
        let methodSheet = try XCTUnwrap(window.attachedSheet)
        try await settle(methodSheet)
        let methodSelection = try XCTUnwrap(store.inspectedDocumentMethod)
        let showSource = "document.procedure-show-source.\(method.id).\(method.revision)"
        try await expect { self.node(showSource, in: methodSheet) != nil }
        try press(showSource, in: methodSheet)
        try await expect { methodSheet.attachedSheet != nil }
        let nested = try XCTUnwrap(methodSheet.attachedSheet)
        try await settle(nested)
        try await expect { self.node("knowledge.inspect-record.page-body", in: nested) != nil }
        XCTAssertNil(store.inspectedKnowledgeRecord, "Nested Show source must not activate the competing root presenter.")
        try assertPage(original, excluding: current, in: nested)
        try capture("02-method-origin-nested", window: nested, output: output)
        try pressLabel("Done", in: nested)
        try await expect { methodSheet.attachedSheet == nil }
        XCTAssertTrue(window.attachedSheet === methodSheet)
        XCTAssertEqual(store.inspectedDocumentMethod?.id, methodSelection.id)
        XCTAssertEqual(store.inspectedDocumentMethod?.binding, method.binding)
        XCTAssertNotNil(node("document.inspect-method", in: methodSheet))
        try pressLabel("Done", in: methodSheet)
        try await expect { window.attachedSheet == nil }
        XCTAssertNil(store.inspectedDocumentMethod)
        XCTAssertEqual(store.selectedGraphNodeID, DocumentMethodGraph.nodeID(method.binding))
        XCTAssertEqual(try files(in: profile), before)

        // The owner deliberately replaces fixture text; opening the remaining
        // exact historical source must show unavailability, never its new copy.
        let replacement = try store.readingSources.replace(id: source.id,
            title: "Synthetic replacement", text: "Replacement text must not appear for the original binding.")
        let unavailableNode = try XCTUnwrap(store.memoryMapSnapshot().nodes.first {
            $0.target == .readingSource(.init(binding: source.binding))
        })
        let afterReplacement = try files(in: profile)
        try await settle(window)
        try press("companion-graph.list-node.\(unavailableNode.id)", in: window)
        try await settle(window)
        try press("companion-graph.open-target", in: window)
        try await expect { window.attachedSheet != nil }
        let unavailableSheet = try XCTUnwrap(window.attachedSheet)
        try await settle(unavailableSheet)
        try await expect { self.node("knowledge.inspect-record.unavailable", in: unavailableSheet) != nil }
        XCTAssertEqual(store.inspectedKnowledgeRecord?.reference, .source(.init(binding: source.binding)))
        XCTAssertNil(node("knowledge.inspect-record.source-body", in: unavailableSheet))
        XCTAssertFalse(allText(in: unavailableSheet).contains(replacement.text))
        try capture("03-unavailable-source", window: unavailableSheet, output: output)
        try pressLabel("Done", in: unavailableSheet)
        try await expect { window.attachedSheet == nil }
        XCTAssertEqual(try files(in: profile), afterReplacement)
        XCTAssertEqual(store.section, .nodeLab)
        XCTAssertEqual(store.prompt, prompt)
        XCTAssertTrue(store.selectedKnowledgePages.isEmpty)
        XCTAssertTrue(store.selectedReadingSourceIDs.isEmpty)
        XCTAssertTrue(store.documentWork.records.isEmpty)
        XCTAssertTrue(store.tokenSteward.tasks.isEmpty)
        XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
        XCTAssertEqual(client.calls, 0)
        XCTAssertNil(play.webView)
        print("Exact-record native sheet evidence: \(output.path)")
        await store.shutdownAssistant()
        await play.shutdown()
    }

    @MainActor private func assertPage(_ page: KnowledgePage, excluding other: KnowledgePage, in sheet: NSWindow) throws {
        let body = try XCTUnwrap(node("knowledge.inspect-record.page-body", in: sheet))
        XCTAssertTrue(texts(body).contains(page.body))
        let content = allText(in: sheet)
        XCTAssertTrue(content.contains(page.title))
        XCTAssertTrue(content.contains("v\(page.revision)"))
        XCTAssertTrue(content.contains("Read only"))
        XCTAssertFalse(content.contains(other.body))
        XCTAssertNotNil(button(label: "Done", in: sheet))
        XCTAssertNil(button(label: "Use in local chat", in: sheet))
        XCTAssertNil(button(label: "Revise…", in: sheet))
    }

    @MainActor private func initializeAccessibility() async {
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
        print("Exact-record fixture AX initialization: \(status)")
    }

    @MainActor private func becomesReady(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<160 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    @MainActor private func expect(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let ready = await becomesReady(condition)
        _ = try XCTUnwrap(ready ? true : nil, "Native sheet did not reach its expected state.", file: file, line: line)
    }

    @MainActor private func settle(_ window: NSWindow) async throws {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    @MainActor private func value(_ object: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        if object.responds(to: selector), let result = object.perform(selector)?.takeUnretainedValue() { return result }
        let attribute: NSAccessibility.Attribute? = switch name {
        case "accessibilityIdentifier": .identifier
        case "accessibilityLabel": .description
        case "accessibilityTitle": .title
        case "accessibilityValue": .value
        case "accessibilityRole": .role
        default: nil
        }
        if let attribute, object.accessibilityAttributeNames().contains(attribute) { return object.accessibilityAttributeValue(attribute) }
        return nil
    }

    @MainActor private func objects(_ root: NSObject) -> [NSObject] {
        var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, _ depth: Int) {
            guard depth < 40, result.count < 3000, seen.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object)
            for child in value(object, "accessibilityChildren") as? [NSObject] ?? [] { visit(child, depth + 1) }
            if object.accessibilityAttributeNames().contains(.children) {
                for child in object.accessibilityAttributeValue(.children) as? [NSObject] ?? [] { visit(child, depth + 1) }
            }
            if let window = object as? NSWindow, let content = window.contentView { visit(content, depth + 1) }
            if let view = object as? NSView { for child in view.subviews { visit(child, depth + 1) } }
        }
        visit(root, 0)
        return result
    }

    @MainActor private func node(_ identifier: String, in root: NSObject) -> NSObject? {
        objects(root).first { value($0, "accessibilityIdentifier") as? String == identifier }
    }

    @MainActor private func texts(_ object: NSObject) -> [String] {
        ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].compactMap { value(object, $0) as? String }
    }

    @MainActor private func allText(in root: NSObject) -> String { objects(root).flatMap(texts).joined(separator: "\n") }

    @MainActor private func button(label: String, in root: NSObject) -> NSObject? {
        let candidates = objects(root)
        if let native = candidates.compactMap({ $0 as? NSButton }).first(where: { $0.title == label }) { return native }
        return candidates.first {
            texts($0).contains(label) && value($0, "accessibilityRole") as? String == "AXButton"
                && $0.responds(to: NSSelectorFromString("accessibilityPerformPress"))
        }
    }

    @MainActor private func pressLabel(_ label: String, in root: NSObject) throws {
        try performPress(XCTUnwrap(button(label: label, in: root), "Missing native button: \(label)"))
    }

    @MainActor private func press(_ identifier: String, in root: NSObject) throws {
        print("Native Press:", identifier)
        try performPress(XCTUnwrap(node(identifier, in: root), "Missing native control: \(identifier)"))
    }

    @MainActor private func performPress(_ object: NSObject) throws {
        if let button = object as? NSButton {
            XCTAssertTrue(button.isEnabled)
            button.performClick(nil)
            return
        }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        _ = try XCTUnwrap(object.responds(to: selector) ? true : nil, "Native control has no Press implementation.")
        let action = unsafeBitCast(object.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        _ = try XCTUnwrap(action(object, selector) ? true : nil, "Native Press action failed.")
    }

    @MainActor private func capture(_ name: String, window: NSWindow, output: URL) throws {
        guard let content = window.contentView else {
            throw XCTSkip("The disposable sheet has no native content view; visual acceptance remains unverified.")
        }
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw XCTSkip("Native bitmap capture is unavailable; exact-record visual acceptance remains unverified.")
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]), !png.isEmpty else {
            throw XCTSkip("Native sheet capture produced no PNG; visual acceptance remains unverified.")
        }
        try png.write(to: output.appendingPathComponent(name + ".png"))
        let evidence: [String: Any] = ["windowVisible": window.isVisible,
            "size": NSStringFromSize(content.bounds.size), "text": allText(in: window),
            "captureMethod": "NSView.cacheDisplay view-layer bitmap; final window compositing, vibrancy and color contrast are not qualified.",
            "compositorVisualAcceptance": false,
            "boundary": "Disposable native SwiftUI sheet and accessibility evidence only; no installed app, live profile, model, or release acceptance."]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent(name + ".json"))
    }

private func files(in directory: URL) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        var result: [String: Data] = [:]
        for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[url.path] = try Data(contentsOf: url)
        }
        return result
    }
}

@MainActor private final class RecordSheetNoCallsAssistant: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; XCTFail("Record inspection cannot connect an assistant.") }
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        XCTFail("Record inspection cannot dispatch a model.")
    }
}

/// Fixed in-process proposal for native interaction checks; no network or model.
@MainActor private final class MethodJourneyFixtureAssistant: AssistantClient {
    private(set) var requests: [AssistantRequest] = []
    func connect() async throws {}
    func disconnect() {}
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        requests.append(request)
        let target = try XCTUnwrap(request.revisionTarget)
        onEvent(.revision(PassageRevisionProposal(target: target, decision: .propose,
            replacement: "Please review the report.", explanation: "Synthetic proposal for interaction checks.",
            sourceIDs: ["selected-passage"], memoryIDs: [])))
    }
}
