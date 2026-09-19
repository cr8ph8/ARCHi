import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class WorkspaceAppearanceTests: XCTestCase {
    func testLegacyPreferencesFollowSystemAndEachChoiceRoundTrips() throws {
        var original = CompanionPreferences()
        original.form = .kinSeed
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "workspaceAppearance")
        let old = try JSONDecoder().decode(CompanionPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.workspaceAppearance, .system)
        XCTAssertEqual(old.form, .kinSeed)
        for appearance in WorkspaceAppearance.allCases {
            var selected = old
            selected.workspaceAppearance = appearance
            XCTAssertEqual(try JSONDecoder().decode(CompanionPreferences.self, from: JSONEncoder().encode(selected)), selected)
        }
        XCTAssertNil(WorkspaceAppearance.system.colorScheme)
        XCTAssertNil(WorkspaceAppearance.system.appKitAppearance)
        XCTAssertEqual(WorkspaceAppearance.dark.appKitAppearance?.name, .darkAqua)
        XCTAssertEqual(WorkspaceAppearance.light.appKitAppearance?.name, .aqua)
    }

    @MainActor
    func testExplicitPreferenceSaveKeepsDarkAcrossRestartWithoutChangingKIN() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("archi-workspace-theme-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("preferences.json")
        let kin = LocalQiMon(character: .kin, originDigest: String(repeating: "a", count: 64), welcomedAt: Date(timeIntervalSince1970: 100))
        var preferences = CompanionPreferences()
        preferences.form = .kinSeed
        let original = NativePreferenceDocument(preferences: preferences, lessons: [], qiMon: kin)
        try original.encoded().write(to: file)
        let store = CompanionStore(preferenceURL: file, allowsPlay: false)
        defer { store.disconnectAssistant() }
        let originalBytes = try Data(contentsOf: file)
        let form = store.cursorPresentationForm
        let seed = store.preferences.seedAppearance
        let session = UUID(), now = Date(timeIntervalSince1970: 200)
        let before = try XCTUnwrap(UnityPresentationSnapshot.capture(store: store, sessionID: session,
            revision: 1, active: true, now: now, systemReduceMotion: false))
        store.preferences.workspaceAppearance = .dark
        XCTAssertEqual(try Data(contentsOf: file), originalBytes, "Selecting a theme follows existing explicit save behavior")
        store.savePreferences()
        let reopened = CompanionStore(preferenceURL: file, allowsPlay: false)
        defer { reopened.disconnectAssistant() }
        XCTAssertEqual(reopened.preferences.workspaceAppearance, .dark)
        XCTAssertEqual(reopened.activeQiMon, kin)
        XCTAssertEqual(reopened.cursorPresentationForm, form)
        XCTAssertEqual(reopened.preferences.seedAppearance, seed)
        let after = try XCTUnwrap(UnityPresentationSnapshot.capture(store: reopened, sessionID: session,
            revision: 1, active: true, now: now, systemReduceMotion: false))
        XCTAssertEqual(before, after, "Workspace theme must not recolor or replace the Unity/cursor identity")
    }

    @MainActor
    func testAppearanceControlRendersDistinctReadableLightAndDarkSurfaces() throws {
        for appearance in [WorkspaceAppearance.light, .dark] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 110),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = appearance.appKitAppearance
            defer { window.contentView = nil; window.close() }
            let hosting = NSHostingView(rootView: WorkspaceAppearancePicker(selection: .constant(appearance))
                .padding(24).frame(width: 600, height: 110)
                .background(WorkspaceTheme.background)
                .preferredColorScheme(appearance.colorScheme))
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let pixel = try XCTUnwrap(bitmap.colorAt(x: 3, y: 3)?.usingColorSpace(.sRGB))
            let luminance = (pixel.redComponent + pixel.greenComponent + pixel.blueComponent) / 3
            if appearance == .dark { XCTAssertLessThan(luminance, 0.25) }
            else { XCTAssertGreaterThan(luminance, 0.8) }
            if let path = ProcessInfo.processInfo.environment["ARCHI_THEME_RENDER_DIR"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent("appearance-\(appearance.rawValue).png"))
            }
        }
    }
}
