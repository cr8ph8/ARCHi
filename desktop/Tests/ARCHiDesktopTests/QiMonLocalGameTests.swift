import XCTest
@testable import ARCHiDesktop

@MainActor
final class QiMonLocalGameTests: XCTestCase {
    private func fixture(_ body: @MainActor (URL, UserDefaults) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QiMonLocalGameTests-" + UUID().uuidString)
        let suite = "QiMonLocalGameTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try await body(root, defaults)
    }

    private func app(_ root: URL, name: String = "QiMon First Signal.app", identifier: String = QiMonLocalGame.bundleIdentifier,
                     executable: String = "QiMon") throws -> URL {
        let url = root.appendingPathComponent(name)
        let binaries = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL", "CFBundleExecutable": executable]
        let bytes = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try bytes.write(to: url.appendingPathComponent("Contents/Info.plist"))
        let binary = binaries.appendingPathComponent("QiMon")
        try Data("test fixture only".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        return url
    }

    private func chapterBuild(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker: [String: Any] = ["schema": 1, "game": "qimon-first-signal", "entry": "index.html"]
        try JSONSerialization.data(withJSONObject: marker).write(to: directory.appendingPathComponent("qimon-build.json"))
        try Data("<!doctype html><title>First Signal fixture</title>".utf8)
            .write(to: directory.appendingPathComponent("index.html"))
    }

    func testEmbeddedDiscoveryPrefersDeliveredBuildAndFallsBackOnlyToValidSibling() async throws {
        try await fixture { root, defaults in
            let host = root.appendingPathComponent("ARCHi.app")
            let bundled = host.appendingPathComponent("Contents/Resources/QiMonFirstSignalWeb")
            let adjacent = root.appendingPathComponent("QiMonFirstSignalWeb")
            try chapterBuild(at: bundled)
            try chapterBuild(at: adjacent)
            let owner = QiMonEmbeddedGame(defaults: defaults, hostApplicationURL: host)
            XCTAssertEqual(owner.directory?.path, bundled.path)
            XCTAssertNil(defaults.object(forKey: QiMonEmbeddedGame.selectionKey))
            XCTAssertNil(owner.webView)
            XCTAssertFalse(owner.isOpening)

            try FileManager.default.removeItem(at: bundled.appendingPathComponent("qimon-build.json"))
            owner.refreshLocation()
            XCTAssertEqual(owner.directory?.path, adjacent.path)
            try FileManager.default.removeItem(at: adjacent.appendingPathComponent("index.html"))
            owner.refreshLocation()
            XCTAssertNil(owner.directory)
            XCTAssertNil(defaults.object(forKey: QiMonEmbeddedGame.selectionKey))
            XCTAssertNil(owner.webView)
        }
    }

    func testEmbeddedDiscoveryDoesNotSearchUndeliveredDevelopmentBuilds() async throws {
        try await fixture { root, defaults in
            let development = root.appendingPathComponent("worktree/dist-qimon")
            try chapterBuild(at: development)
            XCTAssertTrue(QiMonEmbeddedAssets.isBuild(development))
            let owner = QiMonEmbeddedGame(defaults: defaults, hostApplicationURL: root.appendingPathComponent("ARCHi.app"))
            XCTAssertNil(owner.directory)
            XCTAssertNil(owner.webView)
            XCTAssertNil(defaults.object(forKey: QiMonEmbeddedGame.selectionKey))
        }
    }

    func testEmbeddedExplicitBuildRemainsSelectedAndMissingSelectionDoesNotSwitchBuilds() async throws {
        try await fixture { root, defaults in
            let chosen = root.appendingPathComponent("Chosen chapter")
            let host = root.appendingPathComponent("ARCHi.app")
            let bundled = host.appendingPathComponent("Contents/Resources/QiMonFirstSignalWeb")
            try chapterBuild(at: chosen)
            try chapterBuild(at: bundled)
            let bookmark = try chosen.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: QiMonEmbeddedGame.selectionKey)
            let earlierSelection = Data("earlier adventure selection".utf8)
            defaults.set(earlierSelection, forKey: QiMonLocalGame.selectionKey)

            let owner = QiMonEmbeddedGame(defaults: defaults, hostApplicationURL: host)
            XCTAssertEqual(owner.directory?.standardizedFileURL, chosen.standardizedFileURL)
            let reloaded = QiMonEmbeddedGame(defaults: defaults, hostApplicationURL: host)
            XCTAssertEqual(reloaded.directory?.standardizedFileURL, chosen.standardizedFileURL)
            try FileManager.default.removeItem(at: chosen)
            owner.refreshLocation()
            XCTAssertNil(owner.directory)
            XCTAssertEqual(defaults.data(forKey: QiMonEmbeddedGame.selectionKey), bookmark)
            XCTAssertEqual(defaults.data(forKey: QiMonLocalGame.selectionKey), earlierSelection)
            XCTAssertNil(owner.webView)
            XCTAssertFalse(owner.isOpening)
        }
    }

    func testRejectsOtherApplicationsAndEscapingExecutables() async throws {
        try await fixture { root, _ in
            let other = try app(root, name: "Other.app", identifier: "example.other")
            let escaping = try app(root, name: "Escaping.app", executable: "../QiMon")
            let correct = try app(root)
            XCTAssertFalse(QiMonLocalGame.isCompatibleApp(other))
            XCTAssertFalse(QiMonLocalGame.isCompatibleApp(escaping))
            XCTAssertTrue(QiMonLocalGame.isCompatibleApp(correct))
            try FileManager.default.removeItem(at: correct.appendingPathComponent("Contents/MacOS/QiMon"))
            XCTAssertFalse(QiMonLocalGame.isCompatibleApp(correct))
        }
    }

    func testAdjacentDiscoveryDoesNotSaveASelectionOrLaunch() async throws {
        try await fixture { root, defaults in
            let game = try app(root)
            var launches = 0
            let owner = QiMonLocalGame(defaults: defaults,
                candidates: QiMonLocalGame.discoveryCandidates(in: root.appendingPathComponent("ARCHi.app")),
                launch: { _ in launches += 1; return "opened" })
            XCTAssertEqual(owner.availableApp?.path, game.path)
            XCTAssertNil(defaults.object(forKey: QiMonLocalGame.selectionKey))
            XCTAssertEqual(launches, 0)
        }
    }

    func testExplicitSelectionSurvivesReloadAndRejectingAnotherApp() async throws {
        try await fixture { root, defaults in
            let game = try app(root)
            let other = try app(root, name: "Other.app", identifier: "example.other")
            let owner = QiMonLocalGame(defaults: defaults, candidates: [])
            XCTAssertTrue(owner.selectApp(game))
            let saved = defaults.data(forKey: QiMonLocalGame.selectionKey)
            XCTAssertFalse(owner.selectApp(other))
            XCTAssertEqual(defaults.data(forKey: QiMonLocalGame.selectionKey), saved)
            XCTAssertEqual(QiMonLocalGame(defaults: defaults, candidates: []).availableApp?.standardizedFileURL, game.standardizedFileURL)
        }
    }

    func testMissingChosenAppDoesNotSilentlySwitchToAnotherBuild() async throws {
        try await fixture { root, defaults in
            let chosen = try app(root, name: "Chosen.app")
            let included = try app(root)
            let owner = QiMonLocalGame(defaults: defaults, candidates: [included])
            XCTAssertTrue(owner.selectApp(chosen))
            try FileManager.default.removeItem(at: chosen)
            owner.refresh()
            XCTAssertNil(owner.availableApp)
            XCTAssertTrue(owner.hasExplicitSelection)
            owner.useIncludedApp()
            XCTAssertEqual(owner.availableApp, included)
            XCTAssertFalse(owner.hasExplicitSelection)
        }
    }

    func testLaunchFailureIsVisibleAndRetryKeepsSelection() async throws {
        try await fixture { root, defaults in
            let game = try app(root)
            var launches = 0
            let owner = QiMonLocalGame(defaults: defaults, candidates: [game], launch: { _ in
                launches += 1
                throw NSError(domain: "QiMonLocalGameTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Launch denied"])
            })
            await owner.play()
            XCTAssertEqual(launches, 1)
            XCTAssertTrue(owner.status.contains("Launch denied"))
            XCTAssertFalse(owner.isOpening)
            XCTAssertEqual(owner.availableApp?.path, game.path)
            await owner.play()
            XCTAssertEqual(launches, 2)
        }
    }
}
