import SwiftUI
import AppKit

enum ARC3AssistantCommand: Equatable {
    case open, explore, stop, invalid

    static func select(_ prompt: String) -> Self? {
        let command = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch command {
        case "/arc3", "/arc3 open", "open arc3": return .open
        case "/arc3 explore", "explore this arc3 environment": return .explore
        case "/arc3 stop": return .stop
        default:
            return command.hasPrefix("/arc3 ") || command.hasPrefix("/arc3\t") || command.hasPrefix("/arc3\n") ? .invalid : nil
        }
    }
}

@MainActor
struct ARC3Workspace: View {
    @ObservedObject var owner: CompanionStore
    @ObservedObject var session: ARC3SessionStore
    @State private var budget = 32
    @State private var x = 32
    @State private var y = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Interactive ARC3", systemImage: "square.grid.3x3.fill").font(.title2)
                Text("Observe. Try an action. Learn what changed.").foregroundStyle(.secondary)
                Text("Runs your installed public environments locally. ARCHi plans from visible frames, legal actions and observed transitions; game source is never supplied to its planning policy.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Find local environments") { session.discover() }
                    .disabled(session.isWorking || session.isSessionActive)
                    .accessibilityIdentifier("arc3.discover")
                Button("Choose runtime folder…", action: chooseRuntime)
                    .disabled(session.isWorking || session.isSessionActive)
                    .accessibilityIdentifier("arc3.runtime-folder")
            }
            if !session.games.isEmpty {
                Picker("Environment", selection: $session.selectedGameID) {
                    Text("Choose an environment").tag(String?.none)
                    ForEach(session.games, id: \.id) { game in
                        Text(game.title + " · " + game.id).tag(Optional(game.id))
                    }
                }.disabled(session.isWorking || session.isSessionActive)
                    .accessibilityIdentifier("arc3.game")
            }
            HStack {
                Stepper("Action budget: \(budget)", value: $budget, in: 1...64)
                    .disabled(session.isWorking || session.isSessionActive)
                Spacer()
                Button("Start environment") { if owner.prepareARC3Action() { session.start(budget: budget) } }
                    .buttonStyle(WorkspaceActionStyle())
                    .disabled(session.selectedGameID == nil || session.isWorking || session.isSessionActive || owner.isWorking)
                    .accessibilityIdentifier("arc3.start")
            }
            Text("The initial reset counts toward this budget. Explore replans after each observation, uses up to eight actions, and pauses earlier when no useful next step remains.")
                .font(.caption).foregroundStyle(.secondary)
            Label(session.status, systemImage: session.isWorking ? "hourglass" : "circle.dotted")
                .textSelection(.enabled).accessibilityIdentifier("arc3.status")
            if let error = session.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if let plan = session.latestPlan {
                ARC3PlanView(plan: plan, outcome: session.attempts.last(where: { $0.decision == plan })?.outcome)
            }
            if let observation = session.observation {
                HStack {
                    Text(observation.state).font(.headline)
                    Spacer()
                    Text("Levels \(observation.levelsCompleted)/\(observation.winLevels) · Actions \(observation.dispatches)/\(observation.budget)")
                        .font(.caption).monospacedDigit()
                }
                ARC3FrameView(frame: observation.frame) { column, row in x = column; y = row }
                    .frame(maxWidth: 460).aspectRatio(1, contentMode: .fit)
                    .accessibilityIdentifier("arc3.frame")
                HStack {
                    Button("Explore up to 8 actions") { owner.runARC3(.explore) }
                        .buttonStyle(WorkspaceActionStyle())
                        .disabled(session.isWorking || !session.isSessionActive || owner.isWorking)
                        .accessibilityIdentifier("arc3.explore")
                    Button("Stop & keep record") { owner.runARC3(.stop) }
                        .disabled(!session.isWorking && !session.isSessionActive)
                        .accessibilityIdentifier("arc3.stop")
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Manual actions").font(.headline)
                        Spacer()
                        Button("Reset · 1 action") {
                            guard owner.prepareARC3Action() else { return }
                            session.step(action: 0)
                        }.disabled(session.isWorking || !session.isSessionActive || owner.isWorking)
                            .accessibilityIdentifier("arc3.reset")
                    }
                    Text("Action meanings are discovered within each environment.").font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], alignment: .leading) {
                        ForEach(observation.availableActions, id: \.self) { action in
                            Button("Action \(action)") {
                                guard owner.prepareARC3Action() else { return }
                                session.step(action: action, x: action == 6 ? x : nil, y: action == 6 ? y : nil)
                            }.disabled(session.isWorking || !session.isSessionActive || owner.isWorking)
                                .accessibilityIdentifier("arc3.action.\(action)")
                        }
                    }
                    if observation.availableActions.contains(6) {
                        Text("Click the frame to choose a point, then use Action 6.").font(.caption)
                        HStack {
                            Stepper("Column \(x)", value: $x, in: 0...63)
                            Stepper("Row \(y)", value: $y, in: 0...63)
                        }.monospacedDigit()
                    }
                }
            } else if session.isWorking {
                ProgressView().controlSize(.small)
                Button("Stop") { owner.runARC3(.stop) }.accessibilityIdentifier("arc3.stop")
            }
            if !session.transitions.isEmpty {
                DisclosureGroup("Observed transitions · \(session.transitions.count)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(session.transitions.enumerated()), id: \.offset) { index, transition in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(index + 1). Action \(transition.action) · \(transition.verdict.rawValue)").font(.caption.bold())
                                Text("\(transition.beforeDigest.prefix(10)) → \(transition.afterDigest.prefix(10))")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                if transition.invalidated { Text("Earlier prediction contradicted; it is no longer used.").font(.caption).foregroundStyle(.orange) }
                            }
                        }
                    }.padding(.top, 8)
                }
            }
            HStack {
                Button("Activity map") { owner.open(.nodeLab) }
                if let summary = owner.lastARC3Summary {
                    Button("Session usage") { _ = owner.openARCUsage(taskID: summary.sessionID) }
                }
            }
            if let receipt = session.receiptURL {
                Button("Show episode record") { NSWorkspace.shared.activateFileViewerSelecting([receipt]) }
                    .accessibilityIdentifier("arc3.receipt")
            }
            Text("Progress comes from the environment. This authored planning policy uses task-local transition evidence; it is not a trained global quotient, does not award companion growth, and establishes no ARC Prize score. It does not call a model.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).modifier(WorkspaceSurface())
    }

    private func chooseRuntime() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "Choose the ARC runtime folder containing .venv/bin/python and environment_files."
        if panel.runModal() == .OK, let url = panel.url { session.configureRuntimeRoot(url) }
    }
}

private struct ARC3PlanView: View {
    let plan: ARC3PlanDecision
    let outcome: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last plan · \(plan.action?.title ?? "Pause for review")").font(.callout.bold())
            Text(plan.goal).font(.caption)
            Text(plan.reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let outcome {
                Text("Observed: \(outcome.replacingOccurrences(of: "-", with: " "))").font(.caption)
            }
        }.accessibilityIdentifier("arc3.plan")
    }
}

struct ARC3FrameView: View {
    let frame: [[Int]]
    var onPoint: ((Int, Int) -> Void)? = nil
    private let palette: [UInt32] = [0xFFFFFF,0xCCCCCC,0x999999,0x666666,0x333333,0x000000,0xE53AA3,0xFF7BCC,0xF93C31,0x1E93FF,0x88D8F1,0xFFDC00,0xFF851B,0x921231,0x4FCC30,0xA356D6]
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let height = max(frame.count, 1), width = max(frame.first?.count ?? 0, 1)
                for row in frame.indices {
                    for column in frame[row].indices {
                        let value = palette[min(max(frame[row][column], 0), 15)]
                        let color = Color(red: Double((value >> 16) & 255) / 255,
                            green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
                        context.fill(Path(CGRect(x: Double(column) * size.width / Double(width),
                            y: Double(row) * size.height / Double(height), width: size.width / Double(width) + 0.1,
                            height: size.height / Double(height) + 0.1)), with: .color(color))
                    }
                }
            }.gesture(SpatialTapGesture().onEnded { value in
                guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                onPoint?(min(63, max(0, Int(value.location.x / geometry.size.width * 64))),
                         min(63, max(0, Int(value.location.y / geometry.size.height * 64))))
            })
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("ARC3 environment frame, \(frame.count) rows by \(frame.first?.count ?? 0) columns")
    }
}

@MainActor
struct ARC3AssistantReply: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var session: ARC3SessionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ARCHi · Interactive ARC3", systemImage: "square.grid.3x3.fill").font(.headline)
            Text(session.status).textSelection(.enabled)
            if let plan = session.latestPlan {
                ARC3PlanView(plan: plan, outcome: session.attempts.last(where: { $0.decision == plan })?.outcome)
            }
            if let observation = session.observation {
                ARC3FrameView(frame: observation.frame).frame(width: 220, height: 220)
                Text("\(observation.state) · \(observation.dispatches)/\(observation.budget) actions · \(observation.levelsCompleted)/\(observation.winLevels) levels").font(.caption)
            }
            if let error = session.error { Text(error).foregroundStyle(.orange) }
            HStack {
                Button("Open ARC3 controls") { store.runARC3(.open) }
                if session.isWorking || session.isSessionActive { Button("Stop") { store.runARC3(.stop) } }
            }
        }.padding(12).modifier(WorkspaceSurface()).accessibilityIdentifier("assistant.arc3-result")
    }
}
