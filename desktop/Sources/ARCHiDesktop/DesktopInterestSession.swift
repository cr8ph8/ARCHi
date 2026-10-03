import Combine
import Foundation

enum DesktopInterestPhase: String, Sendable { case idle, aiming, targeted, reading, review, failed }

/// Transient acquisition only. CompanionStore remains the owner of the adopted
/// working copy, edits, model requests and retention. Hover reads no content.
@MainActor
final class DesktopInterestSession: ObservableObject {
    @Published private(set) var phase: DesktopInterestPhase = .idle
    @Published private(set) var target: DesktopInterestTarget?
    @Published private(set) var capture: DesktopInterestCapture?
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
        message = "Window selected. Read a local text snapshot when ready."
    }

    func refreshBoundary() {
        guard phase == .targeted || phase == .reading, let target else { return }
        if !reader.isCurrent(target) { cancel(reason: "That window moved or closed. Point again.") }
    }

    func read() {
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
        generation &+= 1
        task?.cancel(); task = nil
        deadline?.cancel(); deadline = nil
        target = nil; capture = nil; phase = .idle; message = reason
    }

    private func fail(_ reason: String, ticket: UInt64) {
        guard ticket == generation else { return }
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
