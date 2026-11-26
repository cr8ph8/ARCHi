import XCTest

/// Python captures the file after each successful test and normal process exit.
@MainActor
final class MemoryUITests: XCTestCase {
    private var app: XCUIApplication!
    private var topic = ""
    private var words = ""

    private func launch() throws {
        continueAfterFailure = false
        let configFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("run.json")
        let config = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: configFile))
        app = XCUIApplication(url: URL(fileURLWithPath: try XCTUnwrap(config["app"])))
        app.launchArguments = ["--session", try XCTUnwrap(config["session"])]
        topic = try XCTUnwrap(config["topic"])
        words = try XCTUnwrap(config["text"])
        app.launch()
        XCTAssertTrue(control("lesson-new").waitForExistence(timeout: 20))
    }

    private func control(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func quit() {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 20), "Expected normal app exit")
    }

    private func fill(_ phrase: String, _ text: String) {
        control("lesson-new").click()
        let t = control("lesson-topic"), content = control("lesson-text")
        XCTAssertTrue(t.waitForExistence(timeout: 8))
        t.click()
        t.typeText(phrase)
        content.click()
        content.typeText(text)
    }

    private func assertSheetClosed() {
        let done = NSPredicate(format: "exists == false")
        let wait = XCTNSPredicateExpectation(predicate: done, object: control("lesson-keep"))
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 8), .completed)
    }

    private func openSeedRecords() -> XCUIElement {
        control("review-open-seed").click()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Local snapshot"].waitForExistence(timeout: 12), app.debugDescription)
        // WebKit exposes aria-pressed buttons as toggles on macOS.
        let records = web.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@ OR title == %@", "listTab", "Records", "Records"))
            .firstMatch
        XCTAssertTrue(records.waitForExistence(timeout: 8), web.debugDescription)
        records.click()
        return web
    }

    private func record(_ title: String, in web: XCUIElement) -> XCUIElement {
        web.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ OR title BEGINSWITH %@", title, title))
            .firstMatch
    }

    private func assertSeedLesson(status: String, absentTopic: String? = nil) {
        let web = openSeedRecords()
        let item = record(topic, in: web)
        XCTAssertTrue(item.waitForExistence(timeout: 8), web.debugDescription)
        item.click()
        XCTAssertTrue(web.staticTexts["Your kept words"].waitForExistence(timeout: 8))
        XCTAssertTrue(web.staticTexts[words].exists, web.debugDescription)
        XCTAssertTrue(web.staticTexts[status].exists, web.debugDescription)
        if let absentTopic {
            XCTAssertFalse(record(absentTopic, in: web).exists)
        }
    }

    func testDiscard() throws {
        try launch()
        fill(topic, words)
        control("lesson-discard").click()
        assertSheetClosed()
        let web = openSeedRecords()
        XCTAssertTrue(record("Screenplay A", in: web).waitForExistence(timeout: 8), web.debugDescription)
        XCTAssertFalse(record(topic, in: web).exists)
        XCTAssertFalse(web.staticTexts[words].exists)
        quit()
    }

    func testKeep() throws {
        try launch()
        XCTAssertTrue(app.staticTexts["No lessons saved. A good answer does not automatically become a memory."].exists)
        fill(topic, words)
        control("lesson-scope").click()
        control("lesson-keep").click()
        assertSheetClosed()
        assertSeedLesson(status: "Current")
        quit()
    }

    func testStale() throws {
        try launch()
        fill("rejected draft", "Wrong source")
        control("lesson-scope").click()
        control("lesson-demo-switch").click()
        control("lesson-keep").click()
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
                                                            "shared copy changed", "shared copy changed")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 8))
        control("lesson-discard").click()
        assertSheetClosed()
        assertSeedLesson(status: "Waiting for shared copy", absentTopic: "rejected draft")
        quit()
    }

    func testReopen() throws {
        try launch()
        let disclosure = app.disclosureTriangles.firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(disclosure.label.contains(topic))
        // On macOS the accessible row spans the whole label, but the clickable
        // disclosure arrow is at its leading edge. The row centre is inert.
        // The card's leading content edge is aligned with the New button.
        let leading = control("lesson-new").frame.minX
        let arrow = disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        arrow.withOffset(CGVector(dx: leading - disclosure.frame.minX + 5, dy: 0)).click()
        if (disclosure.value as? String) == "0" || (disclosure.value as? NSNumber)?.intValue == 0 {
            disclosure.click()
            app.typeKey(.rightArrow, modifierFlags: [])
        }
        let reviewed = control("kept-lesson-text")
        let exact = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", words, words)).firstMatch
        let found = exact.waitForExistence(timeout: 8)
        XCTAssertTrue(found, "Expected the exact reviewed text in the expanded row. " + app.debugDescription)
        XCTAssertTrue(exact.isHittable || reviewed.isHittable, "Reviewed text must be on screen")
        assertSeedLesson(status: "Current")
        quit()
    }
}
