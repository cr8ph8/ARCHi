import Foundation

enum LocalQwenRuntimeFailure: Error, LocalizedError, Equatable {
    case notInstalled, startFailed, timedOut

    var errorDescription: String? {
        switch self {
        case .notInstalled: "Local Qwen could not start because Ollama is not installed on this Mac."
        case .startFailed: "The installed Ollama runtime could not start on this Mac."
        case .timedOut: "The local Qwen runtime did not become ready in time."
        }
    }
}

@MainActor
protocol LocalQwenRuntimeManaging: AnyObject {
    func ensureRunning() async throws
}

@MainActor
protocol LocalQwenRuntimeProcess: AnyObject {
    var isRunning: Bool { get }
    /// Signals only this child. Implementations must never search for or kill
    /// a process by port, name, or an independently discovered PID.
    func terminate()
}

/// App-owned lifecycle for an installed local inference runtime. Model identity
/// and local-only inference are still verified by QwenAssistant after readiness.
/// This owner has no installer, model pull, remote endpoint, or prompt API.
@MainActor
final class LocalQwenRuntime: LocalQwenRuntimeManaging {
    static let shared = LocalQwenRuntime()

    struct LaunchConfiguration: Equatable {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
    }

    struct Dependencies {
        var probe: @MainActor () async throws -> Bool
        var executable: @MainActor () -> URL?
        var launch: @MainActor (LaunchConfiguration) throws -> any LocalQwenRuntimeProcess
        var now: @MainActor () -> Duration
        var sleep: @MainActor (Duration) async throws -> Void
        var environment: [String: String]

        static func live() -> Self {
            let started = ContinuousClock.now
            return Self(probe: { try await LocalQwenRuntime.probeService() },
                        executable: { LocalQwenRuntime.discoverExecutable() },
                        launch: { try LocalQwenOwnedProcess(configuration: $0) },
                        now: { started.duration(to: .now) },
                        sleep: { try await Task.sleep(for: $0) },
                        environment: ProcessInfo.processInfo.environment)
        }
    }

    private let dependencies: Dependencies
    private let startupTimeout: Duration
    private let pollInterval: Duration
    private var startupID: UUID?
    private var startupTask: Task<Void, Never>?
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var ownedProcess: (any LocalQwenRuntimeProcess)?
    private var startingProcess: (any LocalQwenRuntimeProcess)?
    private var retiringProcesses: [any LocalQwenRuntimeProcess] = []

    init(dependencies: Dependencies = .live(), startupTimeout: Duration = .seconds(8),
         pollInterval: Duration = .milliseconds(150)) {
        self.dependencies = dependencies
        self.startupTimeout = max(.milliseconds(1), startupTimeout)
        self.pollInterval = max(.milliseconds(1), pollInterval)
    }

    /// Concurrent role connections share one bounded readiness attempt. A
    /// cancelled caller leaves promptly; other callers keep their own attempt.
    func ensureRunning() async throws {
        try Task.checkCancellation()
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters[waiterID] = continuation
                if startupID == nil {
                    let id = UUID()
                    startupID = id
                    startupTask = Task { [weak self] in
                        guard let self else { return }
                        await self.start(id: id)
                    }
                }
            }
            try Task.checkCancellation()
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelWaiter(waiterID) }
        }
    }

    /// Cancels readiness work and a child launched by that pending attempt.
    /// A previously ready child and a pre-existing external service are retained.
    func cancelStartup() {
        startupTask?.cancel()
        startupTask = nil
        startupID = nil
        stopStartingProcess()
        let pending = waiters.values
        waiters.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
    }

    /// Call once from the app's termination owner, never per Qwen role/client.
    /// Termination is a non-blocking SIGTERM to the child this owner launched.
    /// Keep its handle while alive so a later startup cannot reuse it as ready.
    func shutdown() {
        cancelStartup()
        if let child = ownedProcess { retire(child) }
        ownedProcess = nil
    }

    private func start(id: UUID) async {
        let deadline = dependencies.now() + startupTimeout
        do {
            // A signalled child can still answer the port while shutting down.
            // Observe its exit before probing or launching another service.
            try await waitForRetiringProcesses(id: id, deadline: deadline)
            guard dependencies.now() < deadline else { throw LocalQwenRuntimeFailure.timedOut }
            // Probe before discovery/launch: an existing Ollama belongs to its
            // external owner and is never adopted for shutdown purposes.
            if try await dependencies.probe() {
                try requireCurrent(id)
                finish(id: id, result: .success(()))
                return
            }
            try requireCurrent(id)
            guard dependencies.now() < deadline else { throw LocalQwenRuntimeFailure.timedOut }
            if ownedProcess?.isRunning != true {
                ownedProcess = nil
                guard let executable = dependencies.executable() else { throw LocalQwenRuntimeFailure.notInstalled }
                let child: any LocalQwenRuntimeProcess
                do {
                    child = try dependencies.launch(Self.launchConfiguration(executable: executable,
                                                                              environment: dependencies.environment))
                } catch { throw LocalQwenRuntimeFailure.startFailed }
                ownedProcess = child
                startingProcess = child
            }
            while true {
                try requireCurrent(id)
                guard dependencies.now() < deadline else { throw LocalQwenRuntimeFailure.timedOut }
                if try await dependencies.probe() {
                    try requireCurrent(id)
                    guard dependencies.now() < deadline else { throw LocalQwenRuntimeFailure.timedOut }
                    finish(id: id, result: .success(()))
                    return
                }
                try requireCurrent(id)
                guard ownedProcess?.isRunning == true else { throw LocalQwenRuntimeFailure.startFailed }
                let remaining = deadline - dependencies.now()
                guard remaining > .zero else { throw LocalQwenRuntimeFailure.timedOut }
                try await dependencies.sleep(min(pollInterval, remaining))
            }
        } catch {
            guard startupID == id else { return }
            stopStartingProcess()
            finish(id: id, result: .failure(error))
        }
    }

    private func requireCurrent(_ id: UUID) throws {
        try Task.checkCancellation()
        guard startupID == id else { throw CancellationError() }
    }

    private func finish(id: UUID, result: Result<Void, any Error>) {
        guard startupID == id else { return }
        startingProcess = nil
        startupID = nil
        startupTask = nil
        let pending = waiters.values
        waiters.removeAll()
        for continuation in pending { continuation.resume(with: result) }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
        if waiters.isEmpty { cancelStartup() }
    }

    private func stopStartingProcess() {
        guard let child = startingProcess else { return }
        retire(child)
        if ownedProcess === child { ownedProcess = nil }
        startingProcess = nil
    }

    private func retire(_ child: any LocalQwenRuntimeProcess) {
        guard child.isRunning, !retiringProcesses.contains(where: { $0 === child }) else { return }
        retiringProcesses.append(child)
        child.terminate()
    }

    private func waitForRetiringProcesses(id: UUID, deadline: Duration) async throws {
        while true {
            try requireCurrent(id)
            retiringProcesses.removeAll { !$0.isRunning }
            guard !retiringProcesses.isEmpty else { return }
            let remaining = deadline - dependencies.now()
            guard remaining > .zero else { throw LocalQwenRuntimeFailure.timedOut }
            try await dependencies.sleep(min(pollInterval, remaining))
        }
    }

    static func launchConfiguration(executable: URL, environment: [String: String]) -> LaunchConfiguration {
        // Do not inherit proxies, DYLD injection, remote Ollama configuration,
        // arbitrary origins, or a shell PATH from the containing application.
        let retained = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "OLLAMA_MODELS"]
        var local = environment.filter { retained.contains($0.key) }
        local["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        local["OLLAMA_HOST"] = "127.0.0.1:11434"
        local["OLLAMA_NO_CLOUD"] = "1"
        local["OLLAMA_NOPRUNE"] = "1"
        local["OLLAMA_ORIGINS"] = "http://127.0.0.1,http://localhost"
        return LaunchConfiguration(executableURL: executable, arguments: ["serve"], environment: local)
    }

    static func discoverExecutable() -> URL? {
        let paths = [
            "/Applications/Ollama.app/Contents/Resources/ollama",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Ollama.app/Contents/Resources/ollama").path,
            "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"
        ]
        for path in paths {
            let candidate = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard candidate.lastPathComponent == "ollama",
                  FileManager.default.isExecutableFile(atPath: candidate.path),
                  (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            return candidate
        }
        return nil
    }

    private static func probeService() async throws -> Bool {
        let url = URL(string: "http://127.0.0.1:11434/api/version")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0]
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 0.75
        configuration.timeoutIntervalForResource = 1
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 0.75)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request, delegate: LocalQwenRuntimeRedirectPolicy())
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.url == url, http.statusCode == 200 else { return false }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                data.append(byte)
                guard data.count <= 4096 else { return false }
            }
            guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = value["version"] as? String else { return false }
            return !version.isEmpty && version.utf8.count <= 80
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            return false
        }
    }
}

@MainActor
private final class LocalQwenOwnedProcess: LocalQwenRuntimeProcess {
    private let process: Process

    init(configuration: LocalQwenRuntime.LaunchConfiguration) throws {
        let child = Process()
        child.executableURL = configuration.executableURL
        child.arguments = configuration.arguments
        child.environment = configuration.environment
        child.currentDirectoryURL = configuration.executableURL.deletingLastPathComponent()
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        process = child
    }

    var isRunning: Bool { process.isRunning }
    func terminate() { if process.isRunning { process.terminate() } }
}

private final class LocalQwenRuntimeRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
