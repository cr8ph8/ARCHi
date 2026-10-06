import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// A window observed from Window Server metadata, without reading its contents.
struct DesktopInterestTarget: Equatable, Sendable {
    let windowID: UInt32
    let processID: Int32
    let appName: String
    let title: String
    /// AppKit global coordinates: bottom-left origin, in points.
    let frame: CGRect
    let observedAt: Date

    var id: String { "\(processID):\(windowID)" }
}

struct DesktopInterestCapture: Equatable, Sendable {
    let target: DesktopInterestTarget
    let text: String
    let method: String
    let capturedAt: Date
}

enum DesktopInterestReadError: Error, LocalizedError, Equatable, Sendable {
    case accessibilityPermissionRequired
    case screenRecordingPermissionRequired
    case staleTarget
    case ambiguousWindow
    case noReadableText
    case contentTooLarge(limit: Int)
    case temporarilyUnavailable
    case protectedContent

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Allow ARCHi in Accessibility to read app-provided text, or in Screen Recording to read visible text with local OCR. Then choose the window again."
        case .screenRecordingPermissionRequired:
            "This app did not expose readable document text. Allow ARCHi in Screen Recording to try local OCR of this window, then choose it again."
        case .staleTarget:
            "The selected window changed, moved, or closed. Choose it again before reading."
        case .ambiguousWindow:
            "ARCHi could not identify one matching document window. Move the intended window apart from other windows and choose it again."
        case .noReadableText:
            "No readable text was found in this window. Image understanding and reading hidden document pages are not available here."
        case .contentTooLarge(let limit):
            "This window exceeds the \(limit.formatted())-byte text limit. Show a smaller passage and choose the window again."
        case .temporarilyUnavailable:
            "The selected app did not finish responding. Try again when its document is ready."
        case .protectedContent:
            "This window contains a protected text field. Choose a document window without protected fields."
        }
    }
}

@MainActor
protocol DesktopInterestReading: AnyObject {
    func target(at point: CGPoint) -> DesktopInterestTarget?
    func read(_ target: DesktopInterestTarget) async throws -> DesktopInterestCapture
    func isCurrent(_ target: DesktopInterestTarget) -> Bool
    /// Refresh metadata for the explicitly chosen window, never its contents.
    func refreshedTarget(for target: DesktopInterestTarget) -> DesktopInterestTarget?
}

extension DesktopInterestReading {
    func refreshedTarget(for target: DesktopInterestTarget) -> DesktopInterestTarget? {
        isCurrent(target) ? target : nil
    }
}

/// This service observes metadata on hover. Only `read` accesses AX text or pixels.
/// It never requests a permission, activates a foreign app, accesses a file URL,
/// writes an image, touches the clipboard, or sends content to a model/provider.
@MainActor
final class NativeDesktopInterestReader: DesktopInterestReading {
    func target(at point: CGPoint) -> DesktopInterestTarget? {
        guard point.x.isFinite, point.y.isFinite, let desktop = desktopGeometry else { return nil }
        return DesktopInterestWindowCatalog.windows(in: desktop).first { $0.frame.contains(point) }
    }

    func isCurrent(_ target: DesktopInterestTarget) -> Bool {
        guard let desktop = desktopGeometry else { return false }
        return DesktopInterestWindowCatalog.isCurrent(target, in: desktop)
    }

    func refreshedTarget(for target: DesktopInterestTarget) -> DesktopInterestTarget? {
        guard let desktop = desktopGeometry else { return nil }
        return DesktopInterestWindowCatalog.refreshedTarget(for: target, in: desktop)
    }

    func read(_ target: DesktopInterestTarget) async throws -> DesktopInterestCapture {
        try Task.checkCancellation()
        guard let desktop = desktopGeometry,
              DesktopInterestWindowCatalog.isCurrent(target, in: desktop) else {
            throw DesktopInterestReadError.staleTarget
        }
        // AX calls and synchronous Vision recognition must not block AppKit.
        // Cancellation is forwarded to this worker and checked before each stage.
        let worker = Task.detached(priority: .userInitiated) {
            try await DesktopInterestReadWorker.read(target, in: desktop)
        }
        let capture = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        guard isCurrent(target) else { throw DesktopInterestReadError.staleTarget }
        return capture
    }

    private var desktopGeometry: DesktopInterestGeometry? {
        // NSScreen.main follows the key window; the first screen is the global
        // coordinate anchor. Flip once about that screen, including other displays
        // above/below it and displays with negative horizontal origins.
        guard let primary = NSScreen.screens.first else { return nil }
        return DesktopInterestGeometry(primaryTopY: primary.frame.maxY,
                                       screenFrames: NSScreen.screens.map(\.frame),
                                       ownProcessID: ProcessInfo.processInfo.processIdentifier)
    }
}

struct DesktopInterestGeometry: Sendable {
    let primaryTopY: CGFloat
    let screenFrames: [CGRect]
    let ownProcessID: Int32

    func appKitFrame(fromScreenFrame frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: primaryTopY - frame.maxY, width: frame.width, height: frame.height)
    }

    func screenFrame(fromAppKitFrame frame: CGRect) -> CGRect {
        appKitFrame(fromScreenFrame: frame)
    }

    static func valid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.maxX.isFinite && frame.maxY.isFinite && frame.size.width > 0 && frame.size.height > 0
    }

    static func sameFrame(_ left: CGRect, _ right: CGRect) -> Bool {
        valid(left) && valid(right)
            && abs(left.minX - right.minX) <= 1 && abs(left.minY - right.minY) <= 1
            && abs(left.width - right.width) <= 1 && abs(left.height - right.height) <= 1
    }

    static func screenshotSize(for frame: CGRect) -> CGSize? {
        guard valid(frame), frame.width <= 16_384, frame.height <= 16_384,
              frame.width * frame.height <= 64_000_000 else { return nil }
        let scale = min(2, 1_600 / max(frame.width, frame.height))
        return CGSize(width: max(1, floor(frame.width * scale)), height: max(1, floor(frame.height * scale)))
    }

    /// A minimized sliver or malformed window is not a desktop attraction target.
    /// This geometry qualification grants no permission to capture its contents.
    static func validAttractionFrame(_ frame: CGRect) -> Bool {
        frame.width >= 80 && frame.height >= 60 && screenshotSize(for: frame) != nil
    }
}

enum DesktopInterestWindowCatalog {
    static func windows(in desktop: DesktopInterestGeometry) -> [DesktopInterestTarget] {
        // Apple's on-screen list is ordered front to back. No AX calls here.
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return targets(from: list, in: desktop, observedAt: Date())
    }

    /// Pure decoding also permits tests without enumerating actual user windows.
    static func targets(from list: [[String: Any]], in desktop: DesktopInterestGeometry,
                        observedAt now: Date) -> [DesktopInterestTarget] {
        return list.compactMap { entry in
            guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value, id != 0,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid > 0, pid != desktop.ownProcessID,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                  ((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let screenFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  DesktopInterestGeometry.valid(screenFrame),
                  let appName = entry[kCGWindowOwnerName as String] as? String,
                  !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let frame = desktop.appKitFrame(fromScreenFrame: screenFrame)
            guard desktop.screenFrames.contains(where: { $0.intersects(frame) }) else { return nil }
            return DesktopInterestTarget(windowID: id, processID: pid, appName: appName,
                title: entry[kCGWindowName as String] as? String ?? "", frame: frame, observedAt: now)
        }
    }

    static func isCurrent(_ target: DesktopInterestTarget, in desktop: DesktopInterestGeometry) -> Bool {
        windows(in: desktop).contains {
            $0.windowID == target.windowID && $0.processID == target.processID
                && DesktopInterestGeometry.sameFrame($0.frame, target.frame)
                && (target.title.isEmpty || $0.title == target.title)
        }
    }

    static func refreshedTarget(for target: DesktopInterestTarget,
                                in desktop: DesktopInterestGeometry) -> DesktopInterestTarget? {
        refreshedTarget(for: target, candidates: windows(in: desktop))
    }

    /// Keep the selected process/window identity. Geometry may change; title or
    /// app changes require a new explicit choice, including from an old review.
    static func refreshedTarget(for target: DesktopInterestTarget,
                                candidates: [DesktopInterestTarget]) -> DesktopInterestTarget? {
        guard target.windowID != 0, target.processID > 0 else { return nil }
        let matches = candidates.filter { $0.windowID == target.windowID && $0.processID == target.processID }
        guard matches.count == 1, let current = matches.first,
              current.appName == target.appName, current.title == target.title,
              !current.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              current.observedAt.timeIntervalSince1970.isFinite,
              DesktopInterestGeometry.validAttractionFrame(current.frame) else { return nil }
        return current
    }
}

/// An output cap in UTF-8 bytes, rather than characters, also bounds multibyte text.
struct DesktopInterestTextBuffer {
    static let byteLimit = 60_000
    private(set) var fragments: [String] = []
    private(set) var byteCount = 0

    mutating func append(_ text: String) throws {
        guard text.utf8.count <= Self.byteLimit else {
            throw DesktopInterestReadError.contentTooLarge(limit: Self.byteLimit)
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let additional = clean.utf8.count + (fragments.isEmpty ? 0 : 2)
        guard byteCount + additional <= Self.byteLimit else {
            throw DesktopInterestReadError.contentTooLarge(limit: Self.byteLimit)
        }
        fragments.append(clean)
        byteCount += additional
    }

    var text: String { fragments.joined(separator: "\n\n") }
}

private enum DesktopInterestReadWorker {
    static func read(_ target: DesktopInterestTarget, in desktop: DesktopInterestGeometry) async throws -> DesktopInterestCapture {
        try Task.checkCancellation()
        guard DesktopInterestWindowCatalog.isCurrent(target, in: desktop) else {
            throw DesktopInterestReadError.staleTarget
        }
        var accessibilityUnavailable = true
        if AXIsProcessTrusted() { // Deliberately use the non-prompting API.
            accessibilityUnavailable = false
            do {
                let capture = try DesktopInterestAXReader(target: target, desktop: desktop).read()
                guard DesktopInterestWindowCatalog.isCurrent(target, in: desktop) else {
                    throw DesktopInterestReadError.staleTarget
                }
                return capture
            } catch let error as DesktopInterestReadError {
                switch error {
                case .noReadableText, .temporarilyUnavailable, .ambiguousWindow: break
                default: throw error
                }
            }
        }
        try Task.checkCancellation()
        // Never call ScreenCaptureKit when access is absent: its content discovery
        // API may otherwise prompt. Grant/retry belongs to an explicit UI action.
        guard CGPreflightScreenCaptureAccess() else {
            throw accessibilityUnavailable ? DesktopInterestReadError.accessibilityPermissionRequired
                : DesktopInterestReadError.screenRecordingPermissionRequired
        }
        return try await DesktopInterestOCRReader.read(target, in: desktop)
    }
}

/// All AX objects are created, used, and released inside the off-main worker.
private final class DesktopInterestAXReader {
    private struct Node { let element: AXUIElement; let documentScope: Bool; let depth: Int }
    private enum LimitReached: Error { case traversal }
    private let target: DesktopInterestTarget
    private let desktop: DesktopInterestGeometry
    private let deadline = ProcessInfo.processInfo.systemUptime + 3
    private var callCount = 0
    private var hadFailures = false
    private var partial = false
    private var buffer = DesktopInterestTextBuffer()

    init(target: DesktopInterestTarget, desktop: DesktopInterestGeometry) {
        self.target = target
        self.desktop = desktop
    }

    func read() throws -> DesktopInterestCapture {
        do { return try readWindow() }
        catch is LimitReached { throw DesktopInterestReadError.temporarilyUnavailable }
    }

    private func readWindow() throws -> DesktopInterestCapture {
        let application = AXUIElementCreateApplication(target.processID)
        configure(application)
        let windows = try elements(application, attribute: kAXWindowsAttribute, limit: 100)
        // A truncated window list cannot establish a unique public-API match.
        guard !partial else { throw DesktopInterestReadError.temporarilyUnavailable }
        var matches: [AXUIElement] = []
        for window in windows {
            configure(window)
            if try matchesTarget(window) { matches.append(window) }
        }
        // No private AX window-number attribute is used. Public AX geometry and
        // title must identify a unique window in the already-verified process.
        guard matches.count == 1, let selected = matches.first else {
            throw matches.count > 1 ? DesktopInterestReadError.ambiguousWindow : DesktopInterestReadError.noReadableText
        }
        var pending = [Node(element: selected, documentScope: false, depth: 0)]
        var visited: [AXUIElement] = []
        do {
            while let node = pending.popLast() {
                try checkBudget()
                guard visited.count < 600 else { throw LimitReached.traversal }
                guard !visited.contains(where: { CFEqual($0, node.element) }) else { continue }
                visited.append(node.element)
                configure(node.element)
                let role = try string(node.element, attribute: kAXRoleAttribute) ?? ""
                let subrole = try string(node.element, attribute: kAXSubroleAttribute) ?? ""
                if subrole == kAXSecureTextFieldSubrole { throw DesktopInterestReadError.protectedContent }
                if (try value(node.element, attribute: kAXHiddenAttribute) as? NSNumber)?.boolValue == true { continue }
                if Self.excludedRoles.contains(role) { continue }
                let documentScope = node.documentScope || Self.documentRoles.contains(role)
                if role == kAXTextAreaRole || (role == kAXStaticTextRole && documentScope) {
                    if let text = try readableText(node.element) { try buffer.append(text) }
                    // A readable text node's children commonly repeat its value.
                    continue
                }
                guard node.depth < 32 else { partial = true; continue }
                let children = try elements(node.element, attribute: kAXChildrenAttribute,
                                            limit: min(128, max(0, 600 - visited.count - pending.count)))
                pending += children.reversed().map { Node(element: $0, documentScope: documentScope, depth: node.depth + 1) }
            }
        } catch is LimitReached {
            partial = true
        }
        try Task.checkCancellation()
        // Independent post-checks reject movement/navigation during the traversal.
        guard try matchesTarget(selected, allowExpired: true) else { throw DesktopInterestReadError.staleTarget }
        guard !buffer.fragments.isEmpty else {
            throw hadFailures || partial ? DesktopInterestReadError.temporarilyUnavailable : DesktopInterestReadError.noReadableText
        }
        return DesktopInterestCapture(target: target, text: buffer.text,
            method: partial || hadFailures ? "Accessibility · partial app-exposed text"
                : "Accessibility · app-exposed text; offscreen content may be omitted", capturedAt: Date())
    }

    private static let documentRoles: Set<String> = ["AXWebArea", "AXDocument", kAXScrollAreaRole, "AXLayoutArea"]
    private static let excludedRoles: Set<String> = [
        kAXToolbarRole, kAXMenuBarRole, kAXMenuRole, kAXMenuItemRole, kAXButtonRole,
        kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXComboBoxRole,
        kAXTextFieldRole, kAXSliderRole, kAXOutlineRole,
    ]

    private func readableText(_ element: AXUIElement) throws -> String? {
        let count = (try value(element, attribute: kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
        var range: CFRange?
        if let count, count > 0, count <= DesktopInterestTextBuffer.byteLimit {
            range = CFRange(location: 0, length: count)
        } else if let visible = try rangeValue(element, attribute: kAXVisibleCharacterRangeAttribute),
                  visible.location >= 0, visible.length > 0, visible.length <= DesktopInterestTextBuffer.byteLimit {
            range = visible
            partial = true
        } else if let count, count > DesktopInterestTextBuffer.byteLimit {
            throw DesktopInterestReadError.contentTooLarge(limit: DesktopInterestTextBuffer.byteLimit)
        }
        if var range, let axRange = AXValueCreate(.cfRange, &range) {
            try checkBudget()
            var result: CFTypeRef?
            let status = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                                     axRange, &result)
            if status == .success, let result, CFGetTypeID(result) == CFStringGetTypeID() {
                return try boundedString(result)
            }
            note(status)
        }
        // Some apps expose only Value. Its size is checked before Swift bridging.
        guard let result = try value(element, attribute: kAXValueAttribute), CFGetTypeID(result) == CFStringGetTypeID() else { return nil }
        return try boundedString(result)
    }

    private func matchesTarget(_ element: AXUIElement, allowExpired: Bool = false) throws -> Bool {
        var pid: pid_t = 0
        try checkBudget(allowExpired: allowExpired)
        guard AXUIElementGetPid(element, &pid) == .success, pid == target.processID,
              let position = try pointValue(element, allowExpired: allowExpired),
              let size = try sizeValue(element, allowExpired: allowExpired) else { return false }
        let frame = desktop.appKitFrame(fromScreenFrame: CGRect(origin: position, size: size))
        guard DesktopInterestGeometry.sameFrame(frame, target.frame) else { return false }
        if !target.title.isEmpty {
            return try string(element, attribute: kAXTitleAttribute, allowExpired: allowExpired) == target.title
        }
        return true
    }

    private func configure(_ element: AXUIElement) { AXUIElementSetMessagingTimeout(element, 0.15) }

    private func checkBudget(allowExpired: Bool = false) throws {
        try Task.checkCancellation()
        callCount += 1
        if !allowExpired && (callCount > 2_000 || ProcessInfo.processInfo.systemUptime > deadline) {
            throw LimitReached.traversal
        }
    }

    private func note(_ status: AXError) {
        if status == .cannotComplete || status == .failure { hadFailures = true }
    }

    private func value(_ element: AXUIElement, attribute: String, allowExpired: Bool = false) throws -> CFTypeRef? {
        try checkBudget(allowExpired: allowExpired)
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        note(status)
        return status == .success ? result : nil
    }

    private func string(_ element: AXUIElement, attribute: String, allowExpired: Bool = false) throws -> String? {
        guard let result = try value(element, attribute: attribute, allowExpired: allowExpired),
              CFGetTypeID(result) == CFStringGetTypeID() else { return nil }
        return try boundedString(result)
    }

    private func boundedString(_ result: CFTypeRef) throws -> String {
        let string = result as! CFString
        guard CFStringGetLength(string) <= DesktopInterestTextBuffer.byteLimit else {
            throw DesktopInterestReadError.contentTooLarge(limit: DesktopInterestTextBuffer.byteLimit)
        }
        let text = string as String
        guard text.utf8.count <= DesktopInterestTextBuffer.byteLimit else {
            throw DesktopInterestReadError.contentTooLarge(limit: DesktopInterestTextBuffer.byteLimit)
        }
        return text
    }

    private func elements(_ element: AXUIElement, attribute: String, limit: Int) throws -> [AXUIElement] {
        try checkBudget()
        var count = 0
        let status = AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)
        note(status)
        guard status == .success, count > 0 else { return [] }
        if count > limit { partial = true }
        guard limit > 0 else { return [] }
        try checkBudget()
        var values: CFArray?
        let copyStatus = AXUIElementCopyAttributeValues(element, attribute as CFString, 0, min(count, limit), &values)
        note(copyStatus)
        guard copyStatus == .success, let values else { return [] }
        return (values as [AnyObject]).compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
    }

    private func pointValue(_ element: AXUIElement, allowExpired: Bool) throws -> CGPoint? {
        guard let result = try value(element, attribute: kAXPositionAttribute, allowExpired: allowExpired),
              CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(result as! AXValue, .cgPoint, &point) ? point : nil
    }

    private func sizeValue(_ element: AXUIElement, allowExpired: Bool) throws -> CGSize? {
        guard let result = try value(element, attribute: kAXSizeAttribute, allowExpired: allowExpired),
              CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(result as! AXValue, .cgSize, &size) ? size : nil
    }

    private func rangeValue(_ element: AXUIElement, attribute: String) throws -> CFRange? {
        guard let result = try value(element, attribute: attribute), CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(result as! AXValue, .cfRange, &range) ? range : nil
    }
}

private enum DesktopInterestOCRReader {
    static func read(_ target: DesktopInterestTarget, in desktop: DesktopInterestGeometry) async throws -> DesktopInterestCapture {
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else { throw DesktopInterestReadError.screenRecordingPermissionRequired }
        guard let outputSize = DesktopInterestGeometry.screenshotSize(for: target.frame) else {
            throw DesktopInterestReadError.contentTooLarge(limit: DesktopInterestTextBuffer.byteLimit)
        }
        do {
            let available = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard DesktopInterestWindowCatalog.isCurrent(target, in: desktop),
                  let window = available.windows.first(where: {
                      $0.windowID == target.windowID && $0.owningApplication?.processID == target.processID
                  }), window.isOnScreen,
                  DesktopInterestGeometry.sameFrame(desktop.appKitFrame(fromScreenFrame: window.frame), target.frame) else {
                throw DesktopInterestReadError.staleTarget
            }
            guard CGPreflightScreenCaptureAccess() else { throw DesktopInterestReadError.screenRecordingPermissionRequired }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(outputSize.width)
            configuration.height = Int(outputSize.height)
            configuration.scalesToFit = true
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            // Only this window is captured, even when another window overlaps it.
            // The CGImage stays in memory until local OCR finishes.
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try Task.checkCancellation()
            guard DesktopInterestWindowCatalog.isCurrent(target, in: desktop) else { throw DesktopInterestReadError.staleTarget }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            try Task.checkCancellation()
            var buffer = DesktopInterestTextBuffer()
            let observations = request.results ?? []
            guard observations.count <= 2_000 else {
                throw DesktopInterestReadError.contentTooLarge(limit: DesktopInterestTextBuffer.byteLimit)
            }
            for observation in observations {
                try Task.checkCancellation()
                if let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.25 {
                    try buffer.append(candidate.string)
                }
            }
            guard DesktopInterestWindowCatalog.isCurrent(target, in: desktop) else { throw DesktopInterestReadError.staleTarget }
            guard !buffer.fragments.isEmpty else { throw DesktopInterestReadError.noReadableText }
            return DesktopInterestCapture(target: target, text: buffer.text,
                method: "Local OCR · visible window text only; recognition may be incomplete", capturedAt: Date())
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DesktopInterestReadError {
            throw error
        } catch {
            if !CGPreflightScreenCaptureAccess() { throw DesktopInterestReadError.screenRecordingPermissionRequired }
            throw DesktopInterestReadError.temporarilyUnavailable
        }
    }
}
