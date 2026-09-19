import ApplicationServices
import Foundation
import XCTest

/// Initializes SwiftUI's lazy AX proxies through the public client path used
/// by the existing object-of-interest and Home native acceptance fixtures.
/// It queries only this test process, never requests permission, and leaves
/// each caller's actual native control and geometry assertions authoritative.
enum NativeAccessibilityFixture {
    @MainActor
    static func initialize(waitingFor identifier: String, isReady: @MainActor () -> Bool) async throws {
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
        print("Native fixture AX client initialization for \(identifier): \(status)")
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while clock.now < deadline {
            if isReady() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(isReady(), "Native control did not become ready after AX initialization: \(identifier)")
    }
}
