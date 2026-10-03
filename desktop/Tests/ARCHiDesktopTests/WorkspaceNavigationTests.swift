import XCTest
import Combine
@testable import ARCHiDesktop

final class WorkspaceNavigationTests: XCTestCase {
    @MainActor
    func testReopeningTheCurrentSectionKeepsTheWindowActionWithoutRepublishingSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), allowsPlay: false)
        store.open(.appearance)
        var publications = 0, windowRequests = 0
        let observation = store.objectWillChange.sink { publications += 1 }
        store.onOpenWorkspace = { section in
            XCTAssertEqual(section, .appearance)
            windowRequests += 1
        }
        store.open(.appearance)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(windowRequests, 1)
        observation.cancel()
        await store.shutdownAssistant()
    }

    func testEveryCurrentDestinationHasOneReachableSidebarOwner() {
        let sidebar = WorkspaceNavigation.allSidebarDestinations
        XCTAssertEqual(Set(sidebar).count, sidebar.count)
        XCTAssertFalse(sidebar.contains(.play), "Unity Area owns active practice; retained WebKit is not another primary game.")
        for destination in WorkspaceSection.allCases where destination != .play {
            let parent = WorkspaceNavigation.parent(of: destination)
            XCTAssertTrue(sidebar.contains(parent), "Missing route to \(destination)")
            if !sidebar.contains(destination) {
                XCTAssertTrue(WorkspaceNavigation.tabs(for: parent).contains(destination))
            }
        }
    }

    @MainActor
    func testHomeDirectoryContainsEveryCurrentFeatureExactlyOnce() {
        let destinations = WorkspaceNavigation.allHomeFeatures
        XCTAssertEqual(Set(destinations), Set(WorkspaceSection.allCases.filter { $0 != .home && $0 != .play }))
        XCTAssertEqual(destinations.count, Set(destinations).count)
        XCTAssertEqual(Set(destinations.map(HomeFeatureDirectory.identifier)).count, destinations.count)
    }

    @MainActor
    func testGroupedNavigationPreservesDraftPreferencesAndExplicitSaveState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let original = try NativePreferenceDocument().encoded()
        try original.write(to: url)
        let store = CompanionStore(preferenceURL: url, allowsPlay: false)
        store.prompt = "Keep this unsent question."
        store.preferences.tone = "Warm"
        store.preferences.size = 1.2
        for section in [.appearance, .evolution, .connections, .rhythm, .accessibility, .advanced] as [WorkspaceSection] {
            store.open(section)
            XCTAssertEqual(store.section, section)
            XCTAssertTrue(WorkspaceNavigation.tabs(for: section).contains(section))
            XCTAssertEqual(store.prompt, "Keep this unsent question.")
            XCTAssertEqual(store.preferences.tone, "Warm")
            XCTAssertEqual(store.preferences.size, 1.2)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertFalse(store.unityPresentation.isSharing)
        }
        await store.shutdownAssistant()
    }
}
