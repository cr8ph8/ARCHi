import Foundation

struct ARC3PlannedAction: Codable, Equatable, Hashable, Sendable {
    let action: Int
    let x: Int?
    let y: Int?

    var title: String {
        if let x, let y { return "Action \(action) at \(x), \(y)" }
        return "Action \(action)"
    }
}

/// A proposal bound to an observation, retained before any transport dispatch.
/// Its expected digest is an observed transition prediction, never a win target.
struct ARC3PlanDecision: Codable, Equatable, Sendable {
    let gameID: String
    let level: Int
    let baseFrameDigest: String
    let baseDispatches: Int
    let controller: HamptonQ2EDecision
    let goal: String
    let strategy: String
    let reason: String
    let action: ARC3PlannedAction?
    let expectedDigest: String?
}

/// Bounded planning over validated public observations only. Visible color
/// regions supply candidate points, not object identities or game semantics.
/// The graph is a partial observation model; every replay is checked anew.
enum ARC3Planner {
    private static let maximumHistory = 63
    private static let maximumRouteDepth = 6
    private static let maximumRegionPoints = 24

    static func plan(current: ARC3Observation, transitions: [ARC3Transition],
                     previous: ARC3PlanDecision? = nil, remainingBatch: Int = 8,
                     attempts: [ARC3ActionAttempt] = []) -> ARC3PlanDecision {
        let history = currentLevelHistory(current, transitions: transitions)
        let episode = Array(transitions.suffix(maximumHistory))
        let sinceReset = episode.dropFirst(episode.lastIndex(where: { $0.action == 0 }).map { $0 + 1 } ?? 0)
            .filter { $0.before.gameID == current.gameID && $0.after.gameID == current.gameID }
        let progress = sinceReset.filter { !$0.invalidated && $0.verdict != .refuted &&
            ($0.after.levelsCompleted > $0.before.levelsCompleted || $0.after.state == "WIN") }
        let groups = Dictionary(grouping: history, by: { key($0.before, action: choice($0)) })
        let edges = history.filter { transition in
            guard !transition.invalidated, transition.verdict != .refuted,
                  transition.verdict != .inconclusive, !transition.after.isTerminal,
                  transition.beforeDigest != transition.afterDigest,
                  transition.before.levelsCompleted == transition.after.levelsCompleted else { return false }
            let peers = groups[key(transition.before, action: choice(transition))] ?? []
            // Refuted, variable, repeatedly traversed and no-op edges cannot
            // support an autonomous route, even if one old result looked useful.
            return peers.count < 3 && peers.allSatisfy {
                !$0.invalidated && $0.verdict != .refuted &&
                stateKey($0.after) == stateKey(transition.after) && $0.beforeDigest != $0.afterDigest
            }
        }
        let novel = untried(current, groups: groups)
        let route = routeToFrontier(current, edges: edges, groups: groups,
            depthLimit: min(maximumRouteDepth, max(0, min(remainingBatch, current.remainingActions) - 1)))
        let unchanged = stalledSteps(history)
        let alternatives = novel.count + (route == nil ? 0 : 1)
        let signals = HamptonQ2ESignals(observations: history.count + 1,
            retainedSupport: history.filter { !$0.invalidated && $0.verdict == .supported && $0.beforeDigest != $0.afterDigest }.count,
            contradictions: history.filter { $0.verdict == .refuted }.count,
            unchangedSteps: unchanged, availableAlternatives: alternatives,
            remainingBudget: current.remainingActions, totalBudget: current.budget,
            prerequisitesSatisfied: !current.isTerminal && remainingBatch > 0,
            strategyResults: strategyResults(history: sinceReset, attempts: attempts))
        let compatible = previous.flatMap {
            $0.gameID == current.gameID && $0.level == current.levelsCompleted &&
                $0.baseDispatches >= (history.first?.before.dispatches ?? current.dispatches) &&
                $0.baseDispatches <= current.dispatches ? $0.controller : nil
        }
        let control = HamptonQ2EController.decide(domain: "arc3", contextID: "\(current.gameID)|level:\(current.levelsCompleted)",
            signals: signals, previous: compatible)
        func decision(_ action: ARC3PlannedAction?, strategy: String, reason: String,
                      expected: String? = nil) -> ARC3PlanDecision {
            ARC3PlanDecision(gameID: current.gameID, level: current.levelsCompleted,
                baseFrameDigest: current.frameDigest, baseDispatches: current.dispatches, controller: control,
                goal: "Discover a new transition and seek environment-reported level progress.",
                strategy: strategy, reason: control.reason + " " + reason, action: action, expectedDigest: expected)
        }
        guard control.lane != .stop, unchanged < 8 else {
            return decision(nil, strategy: "paused", reason: "No action dispatched. Manual review or an explicit reset can establish a new starting point.")
        }
        // Retain reuses a concrete observed route; expand/repair first try an
        // untested alternative. A route is also the fallback at an exhausted node.
        if let route, control.lane == .retain || novel.isEmpty {
            return decision(choice(route.first), strategy: "observed-route",
                reason: "Follow a \(route.length)-step observed route to a frame with untried actions; replan after this step. Hidden game state may differ.",
                expected: route.first.afterDigest)
        }
        let ranked = novel.sorted { left, right in
            let l = rank(left, history: history, progress: progress, repairing: control.lane == .repair)
            let r = rank(right, history: history, progress: progress, repairing: control.lane == .repair)
            // Candidate order keeps visible region centroids ahead of the grid
            // fallback when transition evidence does not distinguish them.
            if l != r { return l > r }
            return (novel.firstIndex(of: left) ?? 0) < (novel.firstIndex(of: right) ?? 0)
        }
        if let action = ranked.first {
            let hasProgress = action.action != 6 && progress.contains { $0.action == action.action }
            return decision(action, strategy: control.lane == .repair ? "different-alternative" : "untried-action",
                reason: hasProgress
                    ? "Try an untested action of a kind previously followed by reported progress. That result is not guaranteed at this frame."
                    : "Try a legal action not yet observed at this frame. Visible change alone will not count as level progress.")
        }
        return decision(nil, strategy: "paused", reason: "No untried candidate or bounded observed route remains. Known no-ops, contradictions and repeated cycles are excluded.")
    }

    private static func currentLevelHistory(_ current: ARC3Observation, transitions: [ARC3Transition]) -> [ARC3Transition] {
        let bounded = Array(transitions.suffix(maximumHistory))
        // Explicit RESET and level changes are evidence boundaries, including a
        // return to the same numbered level after a reset.
        let boundary = bounded.lastIndex {
            $0.action == 0 || $0.before.gameID != current.gameID || $0.after.gameID != current.gameID ||
            $0.before.levelsCompleted != current.levelsCompleted || $0.after.levelsCompleted != current.levelsCompleted
        }
        return Array(bounded.dropFirst(boundary.map { $0 + 1 } ?? 0))
    }

    private static func choice(_ transition: ARC3Transition) -> ARC3PlannedAction {
        ARC3PlannedAction(action: transition.action, x: transition.x, y: transition.y)
    }

    private static func stateKey(_ observation: ARC3Observation) -> String {
        "\(observation.gameID)|\(observation.levelsCompleted)|\(observation.state)|\(observation.frameDigest)|\(observation.availableActions.sorted())"
    }

    private static func key(_ observation: ARC3Observation, action: ARC3PlannedAction) -> String {
        "\(stateKey(observation))|\(action.action)|\(action.x ?? -1)|\(action.y ?? -1)"
    }

    private static func untried(_ observation: ARC3Observation, groups: [String: [ARC3Transition]]) -> [ARC3PlannedAction] {
        candidates(observation).filter { groups[key(observation, action: $0)] == nil }
    }

    private static func sameKind(_ first: ARC3PlannedAction, _ second: ARC3PlannedAction) -> Bool {
        // Coordinate evidence is specific to its point; there is no inferred
        // target transfer between unrelated visible regions.
        first == second
    }

    private static func rank(_ action: ARC3PlannedAction, history: [ARC3Transition],
                             progress: [ARC3Transition], repairing: Bool) -> Int {
        // Prior level progress may rank a non-coordinate action kind, never a
        // previously successful click coordinate or a claim about this level.
        let progressWeight = action.action == 6 ? 0 : 20 * progress.filter { $0.action == action.action }.count
        return history.reduce(progressWeight) { value, transition in
            guard sameKind(action, choice(transition)) else { return value }
            if transition.invalidated || transition.verdict == .refuted || transition.after.state == "GAME_OVER" {
                return value - (repairing ? 12 : 4)
            }
            if transition.after.levelsCompleted > transition.before.levelsCompleted || transition.after.state == "WIN" { return value + 20 }
            if transition.beforeDigest == transition.afterDigest { return value - 2 }
            return value + (transition.verdict == .supported ? 4 : 1)
        }
    }

    private static func strategyResults(history: [ARC3Transition], attempts: [ARC3ActionAttempt]) -> [String: HamptonQ2EStrategyEvidence] {
        var counts: [String: (helpful: Int, corrections: Int)] = [:]
        var counted = Set<String>()
        for attempt in attempts.suffix(64) {
            guard counted.insert(attempt.id).inserted, attempt.state == "observed", let proposal = attempt.decision,
                  proposal.controller.isValid, proposal.controller.domain == "arc3",
                  proposal.controller.contextID == "\(proposal.gameID)|level:\(proposal.level)",
                  proposal.controller.lane != .stop,
                  let transition = history.first(where: {
                      $0.before.dispatches == attempt.baseDispatches && $0.beforeDigest == attempt.baseFrameDigest &&
                      $0.afterDigest == attempt.actualDigest && $0.predictedDigest == attempt.predictedDigest &&
                      $0.action == attempt.action && $0.x == attempt.x && $0.y == attempt.y &&
                      $0.before.gameID == proposal.gameID && $0.before.levelsCompleted == proposal.level &&
                      proposal.baseFrameDigest == $0.beforeDigest && proposal.baseDispatches == $0.before.dispatches &&
                      proposal.action == choice($0)
                  }) else { continue }
            let helpful = transition.after.levelsCompleted > transition.before.levelsCompleted || transition.after.state == "WIN"
            let correction = transition.verdict == .refuted || transition.after.state == "GAME_OVER"
            guard helpful || correction else { continue }
            let lane = proposal.controller.lane.rawValue
            var value = counts[lane] ?? (helpful: 0, corrections: 0)
            if correction { value.corrections += 1 } else { value.helpful += 1 }
            counts[lane] = value
        }
        return counts.mapValues { HamptonQ2EStrategyEvidence(helpful: $0.helpful, corrections: $0.corrections) }
    }

    private static func stalledSteps(_ history: [ARC3Transition]) -> Int {
        var seen = Set<String>(), stalled = 0
        for transition in history {
            seen.insert(stateKey(transition.before))
            let novel = seen.insert(stateKey(transition.after)).inserted
            let progress = transition.after.levelsCompleted > transition.before.levelsCompleted || transition.after.state == "WIN"
            stalled = progress || (novel && transition.beforeDigest != transition.afterDigest) ? 0 : stalled + 1
        }
        return stalled
    }

    private struct Route {
        let first: ARC3Transition
        let length: Int
    }

    private static func routeToFrontier(_ current: ARC3Observation, edges: [ARC3Transition],
        groups: [String: [ARC3Transition]], depthLimit: Int) -> Route? {
        guard depthLimit > 0 else { return nil }
        let outgoing = Dictionary(grouping: edges, by: { stateKey($0.before) })
        var queue: [(observation: ARC3Observation, first: ARC3Transition?, depth: Int)] = [(current, nil, 0)]
        var seen: Set<String> = [stateKey(current)]
        var index = 0
        while index < queue.count, index < 64 {
            let node = queue[index]; index += 1
            guard node.depth < depthLimit else { continue }
            for edge in outgoing[stateKey(node.observation)] ?? [] {
                guard seen.insert(stateKey(edge.after)).inserted else { continue }
                let first = node.first ?? edge
                if !untried(edge.after, groups: groups).isEmpty { return Route(first: first, length: node.depth + 1) }
                if queue.count < 64 { queue.append((edge.after, first, node.depth + 1)) }
            }
        }
        return nil
    }

    private static func candidates(_ observation: ARC3Observation) -> [ARC3PlannedAction] {
        var result: [ARC3PlannedAction] = []
        for action in observation.availableActions.sorted() where action != 0 {
            if action == 6 {
                result += regionPoints(observation.frame).map { ARC3PlannedAction(action: 6, x: $0.x, y: $0.y) }
                for y in stride(from: 8, through: 56, by: 16) {
                    for x in stride(from: 8, through: 56, by: 16) {
                        let point = ARC3PlannedAction(action: 6, x: x, y: y)
                        if !result.contains(point) { result.append(point) }
                    }
                }
            } else { result.append(ARC3PlannedAction(action: action, x: nil, y: nil)) }
        }
        return result
    }

    private static func regionPoints(_ frame: [[Int]]) -> [(x: Int, y: Int)] {
        guard (1...64).contains(frame.count), let width = frame.first?.count,
              (1...64).contains(width), frame.allSatisfy({ $0.count == width }) else { return [] }
        let height = frame.count
        var frequencies: [Int: Int] = [:]
        for row in frame { for color in row { frequencies[color, default: 0] += 1 } }
        // The most frequent color is only a background heuristic. The fixed
        // grid remains available when that heuristic omits an interesting area.
        let background = frequencies.keys.sorted().max {
            frequencies[$0, default: 0] == frequencies[$1, default: 0] ? $0 > $1 : frequencies[$0, default: 0] < frequencies[$1, default: 0]
        } ?? frame[0][0]
        var visited = Set<Int>(), regions: [(x: Int, y: Int, size: Int)] = []
        for y in 0..<height {
            for x in 0..<width {
                let origin = y * width + x
                guard visited.insert(origin).inserted, frame[y][x] != background else { continue }
                let color = frame[y][x]
                var pixels = [origin], index = 0, sumX = 0, sumY = 0
                while index < pixels.count {
                    let pixel = pixels[index]; index += 1
                    let px = pixel % width, py = pixel / width
                    sumX += px; sumY += py
                    for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] {
                        guard nx >= 0, nx < width, ny >= 0, ny < height, frame[ny][nx] == color else { continue }
                        let next = ny * width + nx
                        if visited.insert(next).inserted { pixels.append(next) }
                    }
                }
                let cx = sumX / pixels.count, cy = sumY / pixels.count
                // Snap a centroid in a hole/concavity to a pixel of the region.
                let point = pixels.min {
                    let l = abs($0 % width - cx) + abs($0 / width - cy)
                    let r = abs($1 % width - cx) + abs($1 / width - cy)
                    return l == r ? $0 < $1 : l < r
                } ?? origin
                regions.append((point % width, point / width, pixels.count))
            }
        }
        return regions.sorted {
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
        }.prefix(maximumRegionPoints).map { (x: $0.x, y: $0.y) }
    }
}
