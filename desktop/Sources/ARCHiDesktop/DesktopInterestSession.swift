import Combine
import Foundation
import ARCHiSpatial

enum DesktopInterestPhase: String, Sendable { case idle, aiming, targeted, reading, review, failed }

/// Transient acquisition only. CompanionStore remains the owner of the adopted
/// working copy, edits, model requests and retention. Hover reads no content.
@MainActor
final class DesktopInterestSession: ObservableObject {
    struct AreaMarking: Equatable {
        let id = UUID()
        let target: DesktopInterestTarget
    }
    @Published private(set) var phase: DesktopInterestPhase = .idle
    @Published private(set) var target: DesktopInterestTarget?
    @Published private(set) var capture: DesktopInterestCapture?
    @Published private(set) var attracting = false
    @Published private(set) var attractionTarget: DesktopInterestTarget?
    @Published private(set) var areaMarking: AreaMarking?
    @Published private(set) var markedArea: ImageRegionRect?
    @Published private(set) var areaTarget: DesktopInterestTarget?
    @Published private(set) var message = "Point ARCHi at a window to choose what to work with."
    private let reader: any DesktopInterestReading
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    var cue: DesktopInterestCue { .init(phase: phase, target: target) }

    init(reader: (any DesktopInterestReading)? = nil) {
        self.reader = reader ?? NativeDesktopInterestReader()
    }

    func begin() {
        cancel()
        phase = .aiming
        message = "Drag ARCHi over a window. Release to choose it. Nothing is being read."
    }

    func hover(at point: CGPoint) {
        guard phase == .aiming, point.x.isFinite, point.y.isFinite else { return }
        let next = reader.target(at: point)
        if let target, let next, Self.sameTarget(target, next) { return }
        target = next
        message = next.map { "\($0.appName) · release ARCHi to choose this window" }
            ?? "No readable window here. Move ARCHi onto a document or app window."
    }

    func finishAim() {
        guard phase == .aiming else { return }
        guard let target, reader.isCurrent(target) else {
            cancel(reason: "No current window selected. Point again."); return
        }
        phase = .targeted
        message = "Window selected. Attract your particles here, or choose a separate text read."
    }

    func refreshBoundary() {
        if areaMarking != nil { refreshMarkingBoundary(); return }
        if markedArea != nil { refreshAreaBoundary(); return }
        guard phase == .targeted || phase == .reading, let target else { return }
        if !reader.isCurrent(target) { cancel(reason: "That window moved or closed. Point again.") }
    }

    /// An explicit user action follows only refreshed metadata for the chosen
    /// window. The selected capture/read boundary remains unchanged.
    @discardableResult
    func startAttraction() -> Bool {
        guard areaMarking == nil, phase == .targeted || phase == .review, let target,
              let current = reader.refreshedTarget(for: target),
              let qualified = DesktopInterestWindowCatalog.refreshedTarget(for: target, candidates: [current]) else {
            stopAttraction(reason: "That window is no longer available for following. Point at it again.")
            return false
        }
        attractionTarget = qualified
        attracting = true
        return true
    }

    @discardableResult
    func beginMarkingArea() -> Bool {
        guard phase == .targeted || phase == .review, let target,
              let refreshed = reader.refreshedTarget(for: target),
              let current = DesktopInterestWindowCatalog.refreshedTarget(for: target, candidates: [refreshed]) else {
            message = "That window is no longer available. Point at it again before marking an area."
            return false
        }
        stopAttraction()
        areaMarking = AreaMarking(target: current)
        message = "Drag inside the selected window to mark an area. Escape cancels. No content is read."
        return true
    }

    func cancelMarkingArea(reason: String? = "Area marking cancelled. Your previous selection is unchanged.") {
        guard areaMarking != nil else { return }
        areaMarking = nil
        if let reason { message = reason }
    }

    func refreshMarkingBoundary() {
        guard let marking = areaMarking else { return }
        guard let refreshed = reader.refreshedTarget(for: marking.target),
              let current = DesktopInterestWindowCatalog.refreshedTarget(for: marking.target, candidates: [refreshed]),
              Self.sameTarget(current, marking.target) else {
            cancelMarkingArea(reason: "The window moved or changed while marking. Mark the area again."); return
        }
    }

    @discardableResult
    func completeMarkingArea(_ region: ImageRegionRect, markingID: UUID) -> Bool {
        guard let marking = areaMarking, marking.id == markingID else { return false }
        refreshMarkingBoundary()
        guard areaMarking?.id == markingID else { return false }
        guard region.isValid, region.width * marking.target.frame.width >= 4,
              region.height * marking.target.frame.height >= 4 else {
            cancelMarkingArea(reason: "Mark an area at least four points wide and high."); return false
        }
        markedArea = region
        areaTarget = marking.target
        areaMarking = nil
        message = "Area marked. Attract particles to this area when ready. Marking does not read content."
        return true
    }

    func useWholeWindow() {
        cancelMarkingArea(reason: nil)
        markedArea = nil; areaTarget = nil
        message = "Whole window selected for particle following. This choice does not read content."
    }

    private func refreshAreaBoundary() {
        guard let target, let refreshed = reader.refreshedTarget(for: target),
              let current = DesktopInterestWindowCatalog.refreshedTarget(for: target, candidates: [refreshed]) else {
            markedArea = nil; areaTarget = nil
            stopAttraction(reason: "The marked window changed or closed. Point again to mark an area.")
            return
        }
        if areaTarget.map({ !Self.sameTarget($0, current) }) ?? true { areaTarget = current }
    }

    func stopAttraction(reason: String? = nil) {
        if attracting { attracting = false }
        if attractionTarget != nil { attractionTarget = nil }
        if let reason, message != reason { message = reason }
    }

    /// The panel polls this while following instead of the exact-frame read
    /// boundary. Failure stops following without replacing a reviewed snapshot.
    @discardableResult
    func refreshAttraction() -> Bool {
        guard attracting else { return false }
        guard phase == .targeted || phase == .review, let target,
              let current = reader.refreshedTarget(for: target),
              let qualified = DesktopInterestWindowCatalog.refreshedTarget(for: target, candidates: [current]) else {
            stopAttraction(reason: "Particle following stopped because the selected window changed or closed.")
            return false
        }
        if attractionTarget.map({ !Self.sameTarget($0, qualified) }) ?? true { attractionTarget = qualified }
        return true
    }

    func read() {
        cancelMarkingArea(reason: nil)
        stopAttraction()
        guard phase == .targeted, let target else { return }
        guard reader.isCurrent(target) else { cancel(reason: "That window changed. Point again."); return }
        generation &+= 1
        let ticket = generation
        phase = .reading
        message = "Reading this window locally…"
        task = Task { [weak self, reader] in
            do {
                let result = try await reader.read(target)
                guard let self, self.generation == ticket, !Task.isCancelled else { return }
                guard Self.sameTarget(result.target, target), reader.isCurrent(target),
                      !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      result.text.utf8.count <= 60_000 else {
                    self.fail("The snapshot was empty, oversized or no longer matched this window.", ticket: ticket)
                    return
                }
                self.capture = result
                self.phase = .review
                self.message = "Review this snapshot. The original window stays unchanged."
                self.deadline?.cancel(); self.deadline = nil; self.task = nil
            } catch {
                guard let self, self.generation == ticket, !Task.isCancelled else { return }
                self.fail(error.localizedDescription, ticket: ticket)
            }
        }
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.generation == ticket, self.phase == .reading else { return }
            self.fail("This window took too long to read. Your current working copy is unchanged.", ticket: ticket)
        }
    }

    func cancel(reason: String = "Pointing stopped. Your working copy is unchanged.") {
        cancelMarkingArea(reason: nil)
        markedArea = nil; areaTarget = nil
        stopAttraction()
        generation &+= 1
        task?.cancel(); task = nil
        deadline?.cancel(); deadline = nil
        target = nil; capture = nil; phase = .idle; message = reason
    }

    private func fail(_ reason: String, ticket: UInt64) {
        guard ticket == generation else { return }
        stopAttraction()
        generation &+= 1
        task?.cancel(); task = nil; deadline?.cancel(); deadline = nil
        capture = nil; phase = .failed; message = reason
    }

    static func sameTarget(_ lhs: DesktopInterestTarget, _ rhs: DesktopInterestTarget) -> Bool {
        lhs.windowID == rhs.windowID && lhs.processID == rhs.processID
            && lhs.frame == rhs.frame && lhs.appName == rhs.appName && lhs.title == rhs.title
    }
}

struct DesktopInterestSource: Equatable {
    let appName: String
    let title: String
    let method: String
    let capturedAt: Date
    let digest: String
}
