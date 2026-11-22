import XCTest

/// The UI driver runs in its own process. Only the app can write preferences.
final class MemoryUITests: XCTestCase {
    @MainActor
    func testReviewAcrossFourLaunches() throws {
        continueAfterFailure = false
        let configFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("run.json")
        let config = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: configFile))
        let app = XCUIApplication(url: URL(fileURLWithPath: try XCTUnwrap(config["app"])))
        let session = try XCTUnwrap(config["session"])
        let topic = try XCTUnwrap(config["topic"]), text = try XCTUnwrap(config["text"])
        let profile = URL(fileURLWithPath: try XCTUnwrap(config["profile"]))
        let output = URL(fileURLWithPath: try XCTUnwrap(config["out"]))
        app.launchArguments = ["--session", session]

        func capture(_ phase: String) throws {
            let data: Data?
            do { data = try Data(contentsOf: profile) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { data = nil }
            let hex = data?.map { String(format: "%02x", $0) }.joined()
            let fields: [String: Any] = ["present": data != nil, "profile_hex": hex as Any? ?? NSNull()]
            try JSONSerialization.data(withJSONObject: fields).write(to: output.appendingPathComponent(phase + ".json"))
        }
        func control(_ id: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        func launch() {
            app.launch()
            XCTAssertTrue(control("lesson-new").waitForExistence(timeout: 20))
        }
        func quit() {
            app.typeKey("q", modifierFlags: .command)
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 20), "Expected normal app exit")
        }
        func fill(_ phrase: String, _ words: String) {
            control("lesson-new").click()
            let t = control("lesson-topic"), content = control("lesson-text")
            XCTAssertTrue(t.waitForExistence(timeout: 8))
            t.click(); t.typeText(phrase)
            content.click(); content.typeText(words)
        }
        func assertSheetClosed() {
            let done = NSPredicate(format: "exists == false")
            let wait = XCTNSPredicateExpectation(predicate: done, object: control("lesson-keep"))
            XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 8), .completed)
        }
        try capture("baseline")
        launch()
        fill(topic, text)
        control("lesson-discard").click()
        assertSheetClosed()
        quit()
        try capture("discard")

        launch()
        XCTAssertTrue(app.staticTexts["No lessons saved. A good answer does not automatically become a memory."].exists)
        fill(topic, text)
        control("lesson-keep").click()
        assertSheetClosed()
        quit()
        try capture("keep")

        launch()
        fill("screenplay", "Wrong source")
        control("lesson-scope").click()
        control("lesson-demo-switch").click()
        control("lesson-keep").click()
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
                                                            "shared copy changed", "shared copy changed")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 8))
        control("lesson-discard").click()
        quit()
        try capture("stale")

        launch()
        let disclosure = app.disclosureTriangles.firstMatch
        if disclosure.exists { disclosure.click() }
        else { app.staticTexts[topic].firstMatch.click() }
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 8), "Exact lesson must be visible after reopening")
        quit()
        try capture("reopen")
    }
}
