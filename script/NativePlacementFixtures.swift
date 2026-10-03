import Foundation

/// Compiled with the production desktop sources. These are synthetic rectangles;
/// no NSApplication, window, account connection, camera, or actual move is used.
@main
struct NativePlacementFixtures {
    private struct Layout {
        let name: String
        let category: String
        let screen: CGRect
        let visible: CGRect
        let viewport: CGRect
        let window: CGRect
        let body: CGRect
        let targets: [CGRect]
    }

    private struct CaseManifest: Encodable {
        let id: UUID
        let name: String
        let category: String
        let expectedOutcome: String
        let syntheticDisplayOrigin: [String: Double]
        let expectedNormalizedFrame: SpatialRecordedRect
        let expectedStaysPut: Bool
    }

    private struct Manifest: Encodable {
        let schema = "archi-cross-runtime-placement-fixtures/v1"
        let evidenceKind = "synthetic-test-inputs"
        let actualUIObserved = false
        let actualMovementObserved = false
        let explanation = "Programmatically supplied rectangles exercise the real Swift planner and recorder. The recording's recorded-native tag names the producer schema; these fixtures do not establish actual desktop observations, user actions, or movement."
        let displayOriginGrid = "Integral AppKit points. Fractional target glyph bounds and body origins are included."
        let recordingFile = "synthetic-native-recording.json"
        let recordingSchema = "archi-native-placement-recording/v1"
        let plannerVersion = SpatialPlacementPlanner.version
        let expectedRecordCount: Int
        let expectedOutcomeKinds: [String]
        let coverageCategories: [String]
        let cases: [CaseManifest]
    }

    private enum Failure: Error { case invalid(String) }

    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw Failure.invalid("Usage: NativePlacementFixtures OUTPUT_DIRECTORY")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let layouts = makeLayouts()
        guard (20...80).contains(layouts.count) else { throw Failure.invalid("Fixture set must contain 20–80 layouts") }
        let text = "Synthetic selected passage"
        guard let selection = DocumentSelection(range: NSRange(location: 0, length: text.utf16.count), text: text, sourceRevision: 1) else {
            throw Failure.invalid("Synthetic selection could not be constructed")
        }
        let recorder = SpatialRecorder()
        recorder.start()
        var manifestCases: [CaseManifest] = []
        var movingIndex = 0
        let terminalCycle: [SpatialRecordingOutcome] = [.moved, .dismissed, .invalidated, .expired, .unconfirmed]
        for (index, layout) in layouts.enumerated() {
            let geometry = SelectedPassageGeometry(selection: selection, rects: layout.targets,
                viewport: layout.viewport, windowFrame: layout.window, windowNumber: index + 1,
                screenID: UInt32(index + 1), screenFrame: layout.screen)
            guard let candidate = SpatialPlacementPlanner.propose(geometry: geometry,
                companionFrame: layout.body, visibleDisplay: layout.visible) else {
                throw Failure.invalid("No production candidate for \(layout.name)")
            }
            let suffix = String(index + 1, radix: 16)
            let id = UUID(uuidString: "10000000-0000-4000-8000-" + String(repeating: "0", count: 12 - suffix.count) + suffix)!
            let now = Double(index * 2)
            let environment = SpatialEnvironment(companionFrame: layout.body, displays: [
                SpatialDisplay(id: geometry.screenID, frame: layout.screen, visibleFrame: layout.visible)
            ])
            let preview = SpatialPreview(id: id, candidate: candidate, geometry: geometry,
                environment: environment, ticket: ContextTicket(generation: UInt64(index), placement: 1, source: 1, selection: 1),
                createdAt: now)
            recorder.capture(preview, now: now)
            guard recorder.isRecording, recorder.records.count == index + 1 else {
                throw Failure.invalid("Production recorder rejected \(layout.name)")
            }
            let kind: SpatialRecordingOutcome
            if index == layouts.count - 1 {
                kind = .recordingStopped
                recorder.stop(now: now + 1)
            } else if candidate.staysPut {
                kind = .stayed
                recorder.finish(previewID: id, kind: kind, actualFrame: candidate.frame, now: now + 1)
            } else {
                kind = terminalCycle[movingIndex % terminalCycle.count]
                let actual: CGRect?
                if kind == .moved { actual = candidate.frame }
                else if kind == .unconfirmed && movingIndex % 2 == 0 { actual = candidate.frame.offsetBy(dx: 1, dy: 0) }
                else { actual = nil }
                recorder.finish(previewID: id, kind: kind, actualFrame: actual, now: now + 1)
                movingIndex += 1
            }
            guard recorder.records[index].outcome.kind == kind else {
                throw Failure.invalid("Production recorder rejected synthetic outcome for \(layout.name)")
            }
            manifestCases.append(CaseManifest(id: id, name: layout.name, category: layout.category,
                expectedOutcome: kind.rawValue,
                syntheticDisplayOrigin: ["x": Double(layout.screen.minX), "y": Double(layout.screen.minY)],
                expectedNormalizedFrame: SpatialRecordedRect(
                    x: Double(candidate.frame.minX - layout.screen.minX), y: Double(candidate.frame.minY - layout.screen.minY),
                    width: Double(candidate.frame.width), height: Double(candidate.frame.height)),
                expectedStaysPut: candidate.staysPut))
        }
        let manifest = Manifest(expectedRecordCount: layouts.count,
            expectedOutcomeKinds: SpatialRecordingOutcome.allCases.filter { $0 != .pending }.map(\.rawValue).sorted(),
            coverageCategories: Array(Set(layouts.map(\.category))).sorted(), cases: manifestCases)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try recorder.exportData().write(to: directory.appendingPathComponent(manifest.recordingFile), options: .atomic)
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("synthetic-fixture-manifest.json"), options: .atomic)
        print("Exported \(layouts.count) synthetic layouts through the production Swift planner and recorder. No actual UI was observed.")
    }

    private static func r(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    private static func centeredBody(_ targets: [CGRect], size: CGSize) -> CGRect {
        let target = targets.dropFirst().reduce(targets[0]) { $0.union($1) }
        return r(target.midX - size.width / 2, target.midY - size.height / 2, size.width, size.height)
    }

    private static func standard(_ name: String, _ category: String, _ targets: [CGRect], _ body: CGRect,
                                 viewport: CGRect? = nil, window: CGRect? = nil) -> Layout {
        Layout(name: name, category: category, screen: r(0, 0, 1200, 900), visible: r(0, 24, 1200, 852),
            viewport: viewport ?? r(60, 60, 1080, 760), window: window ?? r(40, 40, 1120, 800), body: body, targets: targets)
    }

    private static func makeLayouts() -> [Layout] {
        var result: [Layout] = []
        let targets: [(String, CGRect)] = [
            ("center", r(420.25, 420.5, 220.5, 59.25)),
            ("left", r(68.25, 380.5, 200.5, 48.25)),
            ("right", r(945.25, 390.5, 180.5, 51.25)),
            ("bottom", r(430.25, 68.5, 210.5, 48.25)),
            ("top", r(420.75, 752.5, 220.25, 48.5))
        ]
        let sizes = [CGSize(width: 96, height: 116), CGSize(width: 129, height: 155), CGSize(width: 161, height: 194)]
        for (edge, target) in targets {
            for (index, size) in sizes.enumerated() {
                result.append(standard("\(edge)-fractional-target-size-\(index + 1)", "fractional-target-and-display-edge",
                    [target], centeredBody([target], size: size)))
            }
        }
        let stayTarget = [r(450, 400, 240, 50)]
        let stays: [(String, CGRect)] = [("left", r(338, 365, 100, 120)), ("right", r(702, 365, 100, 120)),
                                        ("above", r(520, 462, 100, 120)), ("below", r(520, 268, 100, 120))]
        for (side, body) in stays { result.append(standard("clear-stay-\(side)", "clear-stay", stayTarget, body)) }

        let outside: [(String, CGRect, CGRect)] = [
            ("left", r(330, 400, 140, 45), r(10, 30, 100, 120)),
            ("right", r(740, 410, 140, 45), r(1060, 410, 100, 120)),
            ("above", r(510, 635, 180, 45), r(550, 748, 100, 120)),
            ("below", r(530, 230, 160, 40), r(560, 40, 100, 120))
        ]
        for (side, target, body) in outside {
            result.append(standard("workspace-exterior-\(side)", "workspace-exterior", [target], body,
                viewport: r(320, 220, 560, 460), window: r(300, 200, 600, 500)))
        }
        result.append(standard("ragged-multiline-fractional", "individual-fragments",
            [r(420.25, 420.5, 240.5, 18.25), r(420.25, 445.75, 120.25, 18.25)], r(460, 425, 129, 155)))
        result.append(standard("clear-gap-between-fragments", "individual-fragments",
            [r(400, 360, 220, 20), r(400, 540, 80, 20)], r(430, 424, 72, 72)))
        result.append(standard("narrow-fragment-and-distant-fragment", "individual-fragments",
            [r(400, 420, 7.5, 20), r(800, 450, 40, 20)], r(420, 420, 128, 155)))
        result.append(standard("duplicate-observed-fragment", "individual-fragments",
            [r(430, 400, 100, 20), r(430, 400, 100, 20)], r(460, 400, 129, 155)))

        let displays: [(String, CGPoint, CGSize)] = [
            ("negative-left-and-below", CGPoint(x: -1920, y: -400), CGSize(width: 1440, height: 1080)),
            ("display-above", CGPoint(x: 0, y: 900), CGSize(width: 1600, height: 1000)),
            ("negative-left-and-above", CGPoint(x: -2560, y: 600), CGSize(width: 1920, height: 1080))
        ]
        for (index, item) in displays.enumerated() {
            let (name, origin, size) = item
            let localTarget = r(600.25 + CGFloat(index) * 60, 620.5 - CGFloat(index) * 30, 240.5, 60.25)
            let localBody = centeredBody([localTarget], size: CGSize(width: 129, height: 155))
            result.append(Layout(name: name, category: "integral-display-origin-translation",
                screen: r(origin.x, origin.y, size.width, size.height),
                visible: r(origin.x, origin.y + 24, size.width, size.height - 48),
                viewport: r(origin.x + 120, origin.y + 130, size.width - 240, size.height - 260),
                window: r(origin.x + 100, origin.y + 100, size.width - 200, size.height - 200),
                body: localBody.offsetBy(dx: origin.x, dy: origin.y), targets: [localTarget.offsetBy(dx: origin.x, dy: origin.y)]))
        }
        // This exact global edge exposes floating-point drift after translating
        // both origins while preserving widths. It must not be hidden by a pixel tolerance.
        let boundaryTarget = r(-3719.7, 400, 299.7, 20)
        result.append(Layout(name: "negative-origin-exact-contained-edge", category: "normalization-boundary-regression",
            screen: r(-3840, 0, 1920, 1080), visible: r(-3840, 24, 1920, 1032),
            viewport: r(-3740, 120, 320, 640), window: r(-3740, 100, 320, 700),
            body: centeredBody([boundaryTarget], size: CGSize(width: 128, height: 154)), targets: [boundaryTarget]))
        // A global midpoint can land exactly on an integer while the translated
        // x + width / 2 lands just above it, changing the floor/ceil candidate pool.
        result.append(Layout(name: "negative-origin-midpoint-grid-regression", category: "normalization-midpoint-regression",
            screen: r(-7680, 0, 1200, 900), visible: r(-7680, 24, 1200, 852),
            viewport: r(-7560, 120, 960, 660), window: r(-7580, 100, 1000, 700),
            body: r(-7442, 490, 128, 154), targets: [r(-7379.9, 500, 1.8, 16.7)]))
        return result
    }
}
