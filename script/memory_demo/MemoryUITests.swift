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

    func testDiscard() throws {
        try launch()
        fill(topic, words)
        control("lesson-discard").click()
        assertSheetClosed()
        quit()
    }

    func testKeep() throws {
        try launch()
        XCTAssertTrue(app.staticTexts["No lessons saved. A good answer does not automatically become a memory."].exists)
        fill(topic, words)
        control("lesson-keep").click()
        assertSheetClosed()
        quit()
    }

    func testStale() throws {
        try launch()
        fill("screenplay", "Wrong source")
        control("lesson-scope").click()
        control("lesson-demo-switch").click()
        control("lesson-keep").click()
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
                                                            "shared copy changed", "shared copy changed")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 8))
        control("lesson-discard").click()
        assertSheetClosed()
        quit()
    }

    func testReopen() throws {
        try launch()
        let disclosure = app.disclosureTriangles.firstMatch
        if disclosure.exists { disclosure.click() }
        else { app.staticTexts[topic].firstMatch.click() }
        XCTAssertTrue(app.staticTexts[words].waitForExistence(timeout: 8), "Exact lesson must be visible after reopening")
        quit()
    }
}
