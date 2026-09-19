import Foundation
import CryptoKit
import Darwin

enum AssistantConnectionState: String { case disconnected = "Disconnected", connecting = "Connecting", ready = "Connected", failed = "Unavailable" }

struct AssistantRequest: Sendable {
    static let inputContract = "native-assistant-input/v4"

    let prompt: String
    let sourceName: String?
    let sourceText: String
    let sourceRevision: UInt64
    let placementRevision: UInt64
    let settings: AssistantSettingsSnapshot
    let localLessons: [LessonSnapshot]
    let localProfile: PersonalContextSnapshot?
    let localConversation: [AssistantConversationExchange]
    let localControl: HamptonQ2EDecision?
    let localReading: DocumentReadingPlan?
    let revisionTarget: RevisionTarget?
    let companion: LocalQiMon.Character?
    var selection: DocumentSelection? = nil

    var tone: String { settings.tone }
    var replyLength: Double { settings.replyLength }

    init(prompt: String, sourceName: String?, sourceText: String, sourceRevision: UInt64,
         placementRevision: UInt64, tone: String, replyLength: Double, selection: DocumentSelection? = nil,
         role: EvolutionRole? = nil, helpStyle: EvolutionHelpStyle? = nil,
         localLessons: [LessonSnapshot] = [], revisionTarget: RevisionTarget? = nil,
         companion: LocalQiMon.Character? = nil, localConversation: [AssistantConversationExchange] = [],
         localProfile: PersonalContextSnapshot? = nil, localControl: HamptonQ2EDecision? = nil,
         localReading: DocumentReadingPlan? = nil) {
        self.init(prompt: prompt, sourceName: sourceName, sourceText: sourceText,
            sourceRevision: sourceRevision, placementRevision: placementRevision,
            settings: AssistantSettingsSnapshot(tone: tone, replyLength: replyLength, role: role, helpStyle: helpStyle),
            selection: selection, localLessons: localLessons, revisionTarget: revisionTarget, companion: companion,
            localConversation: localConversation, localProfile: localProfile, localControl: localControl,
            localReading: localReading)
    }

    init(prompt: String, sourceName: String?, sourceText: String, sourceRevision: UInt64,
         placementRevision: UInt64, settings: AssistantSettingsSnapshot, selection: DocumentSelection? = nil,
         localLessons: [LessonSnapshot] = [], revisionTarget: RevisionTarget? = nil,
         companion: LocalQiMon.Character? = nil, localConversation: [AssistantConversationExchange] = [],
         localProfile: PersonalContextSnapshot? = nil, localControl: HamptonQ2EDecision? = nil,
         localReading: DocumentReadingPlan? = nil) {
        self.prompt = prompt
        self.sourceName = sourceName
        self.sourceText = sourceText
        self.sourceRevision = sourceRevision
        self.placementRevision = placementRevision
        self.settings = settings
        self.selection = selection
        self.localLessons = localLessons
        self.localProfile = localProfile
        self.localConversation = localConversation
        self.localControl = localControl
        self.localReading = localReading
        self.revisionTarget = revisionTarget
        self.companion = companion
    }

    var hasValidSelection: Bool {
        selection == nil || (sourceName != nil && selection?.matches(text: sourceText, sourceRevision: sourceRevision) == true)
    }

    var hasValidLocalLessons: Bool { NativePreferenceDocument.validateLessonSnapshots(localLessons) }
    var hasValidLocalProfile: Bool { localProfile?.isValid ?? true }
    var hasValidLocalConversation: Bool { AssistantConversation.validate(localConversation) }
    var hasValidLocalControl: Bool {
        if let localReading {
            guard revisionTarget == nil, sourceName != nil,
                  localReading.matches(text: sourceText, question: prompt, selection: selection),
                  let localControl, localControl.isValid, localControl.domain == "document-reading",
                  localControl.contextID == localReading.sourceDigest, localControl.lane != .stop else { return false }
            return true
        }
        guard let localControl else { return true }
        guard let revisionTarget else { return false }
        return localControl.isValid && localControl.domain == "document-revision"
            && localControl.contextID == revisionTarget.sourceDigest && localControl.lane != .stop
    }

    var localConversationDigest: String? { AssistantConversation.digest(for: localConversation) }
    var localConversationUTF8Bytes: Int { AssistantConversation.utf8ByteCount(for: localConversation) }
    var localSourceIDs: [String] {
        sourceIDs + (localReading?.sourceIDs ?? []) + AssistantConversation.sourceIDs(for: localConversation)
    }

    func replacingLocalConversation(_ exchanges: [AssistantConversationExchange]) -> AssistantRequest {
        AssistantRequest(prompt: prompt, sourceName: sourceName, sourceText: sourceText,
            sourceRevision: sourceRevision, placementRevision: placementRevision, settings: settings,
            selection: selection, localLessons: localLessons, revisionTarget: revisionTarget,
            companion: companion, localConversation: exchanges, localProfile: localProfile, localControl: localControl,
            localReading: localReading)
    }

    /// The common v4 input is unchanged. Local context and the fixed native work
    /// instruction stay on the local route; none of them cross to Codex.
    var localContextInput: String {
        guard var value = try? JSONDecoder().decode(JSONValue.self, from: Data(input.utf8)).object else { return input }
        if let conversation = AssistantConversation.modelInput(for: localConversation) { value["localConversation"] = conversation }
        if let localProfile { value["localProfile"] = localProfile.modelInput }
        let workControl = localWorkControl
        if let workControl { value["workControl"] = workControl }
        if let localReading, hasValidLocalControl {
            // Keep the full original in the native request for freshness and
            // external-route disclosure. Only local reading uses these excerpts.
            value["source"] = .object([
                "name": .string(sourceName ?? "Shared copy"),
                "revision": .string(String(sourceRevision)),
                "fullDocumentSHA256": .string(localReading.sourceDigest),
                "partial": .bool(localReading.isPartial),
                "totalSections": .number(Double(localReading.totalSections)),
                "sections": .array(localReading.sections.map { section in .object([
                    "id": .string(section.id), "title": .string(section.title),
                    "text": .string(section.text), "sha256": .string(section.sha256),
                    "utf16Location": .number(Double(section.location)),
                    "utf16Length": .number(Double(section.length))
                ]) })
            ])
        }
        if localProfile == nil && localConversation.isEmpty && workControl == nil && localReading == nil { return input }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(JSONValue.object(value))) ?? Data(), as: UTF8.self)
    }

    /// Only application-authored lane guidance reaches generation. Reasons,
    /// scores, source bindings and historical observations remain native data.
    private var localWorkControl: JSONValue? {
        guard let localControl, hasValidLocalControl else { return nil }
        let instruction: String
        if localReading != nil {
            switch localControl.lane {
            case .retain: instruction = "Use the supplied source sections, including previously helpful context where available, to answer the current question. Recheck each claim against the current excerpts."
            case .expand: instruction = "Build the answer from the supplied relevant sections. Identify missing coverage and avoid conclusions about omitted document content."
            case .repair: instruction = "Reconsider the reading using the supplied wider context. Check for conflicting statements and explain remaining gaps before answering."
            case .stop: return nil
            }
            return .object(["version": .string(localControl.version), "lane": .string(localControl.lane.rawValue),
                            "instruction": .string(instruction)])
        }
        switch localControl.lane {
        case .retain:
            instruction = "Follow the user's supplied method and requirements."
        case .expand:
            instruction = "Propose one bounded solution to the current request, following the user's chosen method and requirements when supplied."
        case .repair:
            instruction = "Reassess the approach and check the current stated constraints before proposing a corrected solution."
        case .stop:
            return nil
        }
        return .object(["version": .string(localControl.version), "lane": .string(localControl.lane.rawValue),
                        "instruction": .string(instruction)])
    }

    var hasValidRevisionTarget: Bool {
        guard let revisionTarget else { return true }
        return sourceName != nil && selection == revisionTarget.selection
            && revisionTarget.matches(text: sourceText, sourceRevision: sourceRevision)
    }

    var sourceIDs: [String] {
        ["current-question"] + (sourceName == nil ? [] : ["shared-copy"])
            + (selection == nil ? [] : ["selected-passage"])
    }

    /// Captures the exact ordered lesson revisions offered locally, including
    /// provenance retained by the app. This digest never enters the Codex input.
    var localLessonDigest: String? {
        guard !localLessons.isEmpty else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(localLessons) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Direct local Qwen uses the same public input plus explicit lesson context.
    /// The structured Hampton path supplies these records in its memories array.
    var localInput: String { providerInput(includeLocalLessons: true) }
    var codexInput: String { providerInput(includeLocalLessons: false) }

    private func providerInput(includeLocalLessons: Bool) -> String {
        let lessons = includeLocalLessons ? localLessons : []
        let base = includeLocalLessons ? localContextInput : input
        let suppliedSourceIDs = includeLocalLessons ? localSourceIDs : sourceIDs
        guard revisionTarget != nil || !lessons.isEmpty || (includeLocalLessons && !localConversation.isEmpty),
              var value = try? JSONDecoder().decode(JSONValue.self, from: Data(base.utf8)).object else { return base }
        if !lessons.isEmpty { value["memories"] = .array(lessons.map(\.modelInput)) }
        if includeLocalLessons && !localConversation.isEmpty {
            value["sources"] = .array(suppliedSourceIDs.map { .object(["id": .string($0), "label": .string($0)]) })
        }
        if let revisionTarget {
            value["sources"] = .array(suppliedSourceIDs.map { .object(["id": .string($0), "label": .string($0)]) })
            value["outputSchema"] = PassageRevisionValidator.schema(target: revisionTarget,
                sourceIDs: suppliedSourceIDs, memoryIDs: lessons.map(\.modelID))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(JSONValue.object(value))) ?? Data(), as: UTF8.self)
    }

    var input: String {
        var data: [String: JSONValue] = [
            "task": .string(revisionTarget == nil ? "answer" : "revise"),
            "question": .string(prompt), "tone": .string(tone),
            "length": .string(settings.lengthLabel),
            "source": sourceName.map { .object([
                "name": .string($0), "text": .string(sourceText),
                "revision": .string(String(sourceRevision)),
                "sha256": .string(SHA256.hash(data: Data(sourceText.utf8)).map { String(format: "%02x", $0) }.joined())
            ]) } ?? .null,
            "placementRevision": .string(String(placementRevision)),
            "selection": sourceName != nil && selection?.matches(text: sourceText, sourceRevision: sourceRevision) == true
                ? selection!.input : .null
        ]
        if let revisionTarget { data["revisionTarget"] = revisionTarget.input }
        // Only a fixed display name crosses the assistant boundary. The local
        // owner association, origin digest and welcome date remain on this Mac.
        if let companion { data["companion"] = .object(["displayName": .string(companion == .kin ? "KIN" : "Liminal")]) }
        if let role = settings.role { data["role"] = .string(role.rawValue) }
        if let helpStyle = settings.helpStyle { data["helpStyle"] = .string(helpStyle.rawValue) }
        return String(decoding: (try? JSONEncoder().encode(JSONValue.object(data))) ?? Data(), as: UTF8.self)
    }
}

enum AssistantEvent { case text(String), revision(PassageRevisionProposal) }

@MainActor
protocol AssistantClient: AnyObject {
    func connect() async throws
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws
    func disconnect()
    func shutdown() async
}

extension AssistantClient { func shutdown() async { disconnect() } }

enum AssistantFailure: Error, LocalizedError {
    case unavailable, signedOut, configuration, protocolError, timedOut, stopped, turnFailed
    var errorDescription: String? {
        switch self {
        case .unavailable: "Could not start the installed Codex connection. Open Codex and try again."
        case .signedOut: "Sign in to Codex with ChatGPT, then connect again."
        case .configuration: "This Codex configuration could not be limited to shared-text assistance. Nothing was sent."
        case .protocolError: "The Codex connection returned an unexpected event and was stopped."
        case .timedOut: "Codex did not respond in time. Connect again to retry."
        case .stopped: "The response was stopped."
        case .turnFailed: "Codex could not finish this reply. Connect again to retry."
        }
    }
}

/// Codable values keep transport data Sendable without passing untyped dictionaries across tasks.
enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSONValue? { object?[key] }
    var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
}

/// One owned stdio process. No TCP listener, copied credential, shell command, or background retry.
@MainActor
final class CodexAssistant: AssistantClient {
    private(set) var configurationChecks: [String: Bool] = [:]
    private(set) var diagnosticStage = "Not started"
    static let disabledFeatures = ["shell_tool", "unified_exec", "apps", "plugins", "remote_plugin", "hooks",
        "memories", "multi_agent", "multi_agent_v2", "goals", "browser_use", "browser_use_external",
        "computer_use", "image_generation", "view_image", "code_mode_host", "code_mode", "skill_search",
        "skill_mcp_dependency_install", "tool_suggest", "workspace_dependencies", "shell_snapshot", "chronicle"]
    private let executable: URL
    private var directory: URL?
    private var process: Process?
    private var retired: [UUID: (process: Process, directory: URL?)] = [:]
    private var input: FileHandle?
    private var output: FileHandle?
    private var epoch: UInt64 = 0
    private var ownership: UInt64 = 0
    private var nextID = 1
    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var turnCompletion: CheckedContinuation<Void, Error>?
    private var turnTimeout: Task<Void, Never>?
    private var activeThread: String?
    private var activeTurn: String?
    private var startingTurn = false
    private var earlyEvents: [JSONValue] = []
    private var stream = AssistantReplyStream()
    private var eventHandler: (@MainActor (AssistantEvent) -> Void)?
    private var connected = false
    private var busy = false

    init(executable: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")) {
        self.executable = executable
    }

    func connect() async throws {
        disconnect()
        let owner = ownership
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("archi-assistant-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try AssistantInstructions.groundedText.write(to: location.appendingPathComponent("instructions.txt"), atomically: true, encoding: .utf8)
        directory = location
        do {
            try await start(disabledServers: [])
            try requireOwner(owner)
            let first = try await effectiveConfig()
            try requireOwner(owner)
            let servers = Array(first["mcp_servers"]?.object?.keys ?? Dictionary<String, JSONValue>().keys)
            if !servers.isEmpty {
                guard servers.allSatisfy({ $0.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil }) else { throw AssistantFailure.configuration }
                stopProcess(error: .stopped)
                try await start(disabledServers: servers)
                try requireOwner(owner)
            }
            let config = try await effectiveConfig()
            try requireOwner(owner)
            configurationChecks = Self.restrictionChecks(config)
            guard Self.isRestricted(config) else { throw AssistantFailure.configuration }
            let account = try await rpc("account/read", ["refreshToken": .bool(false)])
            try requireOwner(owner)
            guard account["account"]?["type"]?.string == "chatgpt" else { throw AssistantFailure.signedOut }
            try Task.checkCancellation()
            connected = true
        } catch {
            if ownership == owner { disconnect() }
            throw error
        }
    }

    static func isRestricted(_ config: JSONValue) -> Bool {
        restrictionChecks(config).values.allSatisfy { $0 }
    }

    static func restrictionChecks(_ config: JSONValue) -> [String: Bool] {
        var checks = Dictionary(uniqueKeysWithValues: disabledFeatures.map { ($0, config["features"]?[$0]?.bool == false) })
        checks["web_search_disabled"] = config["web_search"]?.string == "disabled"
        checks["notify_disabled"] = config["notify"]?.array?.isEmpty == true
        checks["openai_provider"] = config["model_provider"] == nil || config["model_provider"]?.string == "openai"
        checks["no_custom_openai_provider"] = config["model_providers"]?["openai"] == nil
        checks["mcp_disabled"] = (config["mcp_servers"]?.object ?? [:]).values.allSatisfy { $0["enabled"]?.bool == false }
        return checks
    }

    private func start(disabledServers: [String]) async throws {
        guard let directory, FileManager.default.isExecutableFile(atPath: executable.path) else { throw AssistantFailure.unavailable }
        epoch &+= 1
        let generation = epoch
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = executable
        child.currentDirectoryURL = directory
        var args = ["app-server", "--stdio"]
        for feature in Self.disabledFeatures { args += ["--disable", feature] }
        args += ["--enable", "skip_host_skill_discovery"]
        for config in ["web_search=\"disabled\"", "project_doc_max_bytes=0", "skills.max_context_tokens=1",
                       "history.persistence=\"none\"", "notify=[]", "developer_instructions=\"\"", "model_provider=\"openai\"",
                       "model_instructions_file=\"\(directory.path)/instructions.txt\""] { args += ["-c", config] }
        for server in disabledServers { args += ["-c", "mcp_servers.\(server).enabled=false"] }
        child.arguments = args
        let allowed = ["HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL", "CODEX_HOME"]
        child.environment = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
        process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.epoch == generation else { return }
                if data.isEmpty { self.stopProcess(error: .unavailable) }
                else { self.receive(data) }
            }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.epoch == generation else { return }
                self.stopProcess(error: .unavailable)
            }
        }
        do { try child.run() } catch { stopProcess(error: .unavailable); throw AssistantFailure.unavailable }
        _ = try await rpc("initialize", ["clientInfo": .object(["name": .string("archi_desktop"), "title": .string("ARCHi Desktop"), "version": .string("0.1.0")]), "capabilities": .object(["experimentalApi": .bool(true)])])
        guard epoch == generation else { throw AssistantFailure.stopped }
        try send(.object(["method": .string("initialized"), "params": .object([:])]))
        try Task.checkCancellation()
    }

    private func effectiveConfig() async throws -> JSONValue {
        let value = try await rpc("config/read", ["includeLayers": .bool(false), "cwd": .string(directory!.path)])
        guard let config = value["config"] else { throw AssistantFailure.protocolError }
        return config
    }

    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        guard request.hasValidSelection, request.hasValidRevisionTarget else { throw AssistantFailure.protocolError }
        guard connected, !busy, activeThread == nil, let directory else { throw AssistantFailure.unavailable }
        busy = true
        let owner = ownership
        do {
            try Task.checkCancellation()
            let started = try await rpc("thread/start", ["cwd": .string(directory.path), "ephemeral": .bool(true),
                "sandbox": .string("read-only"), "approvalPolicy": .string("never"), "dynamicTools": .array([]),
                "environments": .array([]), "runtimeWorkspaceRoots": .array([]), "selectedCapabilityRoots": .array([]),
                "modelProvider": .string("openai"),
                "baseInstructions": .string(request.revisionTarget == nil ? AssistantInstructions.groundedText : AssistantInstructions.passageRevisionText),
                "developerInstructions": .string("")])
            try requireOwner(owner)
            guard let thread = started["thread"]?["id"]?.string, !thread.isEmpty,
                  started["approvalPolicy"]?.string == "never", started["sandbox"]?["type"]?.string == "readOnly",
                  started["modelProvider"]?.string == "openai",
                  started["thread"]?["ephemeral"]?.bool == true,
                  started["cwd"]?.string == directory.path,
                  started["runtimeWorkspaceRoots"]?.array?.isEmpty == true,
                  started["sandbox"]?["networkAccess"]?.bool == false,
                  started["instructionSources"]?.array?.isEmpty == true else { throw AssistantFailure.configuration }
            try Task.checkCancellation()
            activeThread = thread; startingTurn = true
            // Revision JSON stays private until terminal completion and validation.
            eventHandler = request.revisionTarget == nil ? onEvent : nil
            let begun = try await rpc("turn/start", ["threadId": .string(thread), "input": .array([.object(["type": .string("text"), "text": .string(request.codexInput)])]),
                "approvalPolicy": .string("never"), "environments": .array([]), "runtimeWorkspaceRoots": .array([]),
                "sandboxPolicy": .object(["type": .string("readOnly"), "networkAccess": .bool(false)])])
            try requireOwner(owner)
            guard let turn = begun["turn"]?["id"]?.string, !turn.isEmpty else { throw AssistantFailure.protocolError }
            activeTurn = turn; startingTurn = false
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                turnCompletion = continuation
                let events = earlyEvents; earlyEvents = []
                for event in events { handleNotification(event) }
                if turnCompletion != nil {
                    let generation = epoch
                    turnTimeout = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(90))
                        guard !Task.isCancelled, let self, self.epoch == generation else { return }
                        self.stopProcess(error: .timedOut)
                    }
                }
            }
            // Each request has an ephemeral context; another document can never inherit this source.
            try requireOwner(owner)
            let revision: PassageRevisionProposal?
            if let target = request.revisionTarget {
                guard let raw = stream.finalText else { throw AssistantFailure.protocolError }
                do { revision = try PassageRevisionValidator.parse(raw, target: target, sourceIDs: request.sourceIDs, memoryIDs: []) }
                catch { throw AssistantFailure.protocolError }
            } else { revision = nil }
            _ = try await rpc("thread/unsubscribe", ["threadId": .string(thread)])
            try requireOwner(owner)
            activeThread = nil; activeTurn = nil; stream = AssistantReplyStream(); eventHandler = nil
            busy = false
            diagnosticStage = "Reply completed"
            if let revision { onEvent(.revision(revision)) }
        } catch {
            if ownership == owner { disconnect() }
            throw error
        }
    }

    func disconnect() {
        ownership &+= 1
        if let activeThread, let activeTurn {
            try? send(.object(["id": .number(Double(nextID)), "method": .string("turn/interrupt"), "params": .object(["threadId": .string(activeThread), "turnId": .string(activeTurn)])]))
            nextID += 1
        }
        let oldDirectory = directory
        stopProcess(error: .stopped)
        directory = nil
        if let oldDirectory { removeUnusedDirectory(oldDirectory) }
    }

    func shutdown() async {
        disconnect()
        while !retired.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func removeUnusedDirectory(_ location: URL) {
        guard directory != location, !retired.values.contains(where: { $0.directory == location }) else { return }
        try? FileManager.default.removeItem(at: location)
    }

    private func requireOwner(_ owner: UInt64) throws {
        try Task.checkCancellation()
        guard ownership == owner else { throw AssistantFailure.stopped }
    }

    private func stopProcess(error: AssistantFailure) {
        epoch &+= 1; connected = false; busy = false
        output?.readabilityHandler = nil
        process?.terminationHandler = nil
        if let child = process {
            let id = UUID(), location = directory
            retired[id] = (child, location)
            if child.isRunning { child.terminate() }
            Task { [self, child] in
                // Keep the exact process handle until exit; a delayed TERM cannot leave a live orphan.
                for _ in 0..<20 {
                    if !child.isRunning { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
                while child.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
                retired.removeValue(forKey: id)
                if let location { removeUnusedDirectory(location) }
            }
        }
        try? input?.close(); try? output?.close()
        process = nil; input = nil; output = nil; buffer = Data()
        let requests = pending; pending = [:]
        for timeout in timeouts.values { timeout.cancel() }; timeouts = [:]
        for continuation in requests.values { continuation.resume(throwing: error) }
        let completion = turnCompletion; turnCompletion = nil; completion?.resume(throwing: error)
        turnTimeout?.cancel(); turnTimeout = nil
        activeThread = nil; activeTurn = nil; startingTurn = false; earlyEvents = []
        stream = AssistantReplyStream(); eventHandler = nil
    }

    private func rpc(_ method: String, _ params: [String: JSONValue]) async throws -> JSONValue {
        diagnosticStage = method
        guard process?.isRunning == true else { throw AssistantFailure.unavailable }
        let id = nextID; nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self, self.pending[id] != nil else { return }
                self.stopProcess(error: .timedOut)
            }
            do { try send(.object(["id": .number(Double(id)), "method": .string(method), "params": .object(params)])) }
            catch { stopProcess(error: .unavailable) }
        }
    }

    private func send(_ message: JSONValue) throws {
        guard let input else { throw AssistantFailure.unavailable }
        var data = try JSONEncoder().encode(message); data.append(10)
        guard data.count <= 524_288 else { throw AssistantFailure.protocolError }
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        guard buffer.count + data.count <= 1_048_576 else { stopProcess(error: .protocolError); return }
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[..<end]; buffer.removeSubrange(...end)
            guard line.count <= 524_288, let value = try? JSONDecoder().decode(JSONValue.self, from: line) else { stopProcess(error: .protocolError); return }
            if value["method"] != nil && value["id"] != nil {
                // This client grants no server-initiated action, login, or approval request.
                stopProcess(error: .protocolError); return
            }
            if case .number(let number) = value["id"], number.isFinite, number.rounded() == number, number > 0, number < Double(Int.max), let request = pending.removeValue(forKey: Int(number)) {
                timeouts.removeValue(forKey: Int(number))?.cancel()
                if value["error"] != nil { request.resume(throwing: AssistantFailure.turnFailed) }
                else if let result = value["result"] { request.resume(returning: result) }
                else { request.resume(throwing: AssistantFailure.protocolError) }
            } else if value["method"] != nil { handleNotification(value) }
        }
    }

    private func handleNotification(_ value: JSONValue) {
        guard let method = value["method"]?.string, let params = value["params"],
              let activeThread, params["threadId"]?.string == activeThread else { return }
        if startingTurn {
            guard earlyEvents.count < 256 else { stopProcess(error: .protocolError); return }
            earlyEvents.append(value); return
        }
        let turn = params["turnId"]?.string ?? params["turn"]?["id"]?.string
        guard let activeTurn, turn == activeTurn, turnCompletion != nil else { return }
        if method == "item/started" || method == "item/completed" {
            guard let item = params["item"], let type = item["type"]?.string else { stopProcess(error: .protocolError); return }
            guard ["userMessage", "agentMessage", "reasoning", "plan"].contains(type) else { stopProcess(error: .protocolError); return }
        }
        if ["item/started", "item/completed", "item/agentMessage/delta"].contains(method) {
            do {
                if let text = try stream.consume(method: method, params: params) { eventHandler?(.text(text)) }
            } catch { stopProcess(error: .protocolError) }
        } else if method == "turn/completed" {
            let completion = turnCompletion; turnCompletion = nil
            turnTimeout?.cancel(); turnTimeout = nil
            if params["turn"]?["status"]?.string == "completed", let text = stream.finalText {
                eventHandler?(.text(text)); completion?.resume()
            }
            else { completion?.resume(throwing: AssistantFailure.turnFailed) }
        } else if method == "error" { stopProcess(error: .turnFailed) }
    }
}
