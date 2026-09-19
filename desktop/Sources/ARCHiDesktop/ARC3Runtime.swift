import Foundation
import CryptoKit
import Darwin

struct ARC3Game: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
}

struct ARC3Observation: Codable, Equatable, Sendable {
    let gameID: String
    let state: String
    let levelsCompleted: Int
    let winLevels: Int
    let availableActions: [Int]
    let frame: [[Int]]
    let frameDigest: String
    let dispatches: Int
    let budget: Int
    var isTerminal: Bool { state == "WIN" || state == "GAME_OVER" }
    var remainingActions: Int { max(0, budget - dispatches) }

    func validate(gameID expectedGame: String, budget expectedBudget: Int) throws {
        guard gameID == expectedGame, ["NOT_PLAYED", "NOT_FINISHED", "WIN", "GAME_OVER"].contains(state),
              levelsCompleted >= 0, winLevels >= levelsCompleted, winLevels <= 254,
              budget == expectedBudget, (1...64).contains(budget), (1...budget).contains(dispatches),
              availableActions.count <= 8, Set(availableActions).count == availableActions.count,
              availableActions.allSatisfy({ (0...7).contains($0) }),
              (1...64).contains(frame.count), let width = frame.first?.count, (1...64).contains(width),
              frame.allSatisfy({ $0.count == width && $0.allSatisfy { (0...15).contains($0) } }) else {
            throw ARC3RuntimeError.invalid("Invalid ARC3 observation.")
        }
        let bytes = try JSONEncoder().encode(frame)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard frameDigest == digest else { throw ARC3RuntimeError.invalid("ARC3 frame digest mismatch.") }
    }
}

struct ARC3Request: Codable, Sendable {
    var id = UUID().uuidString
    let command: String
    var gameID: String? = nil
    var action: Int? = nil
    var x: Int? = nil
    var y: Int? = nil
    var budget: Int? = nil
}

struct ARC3Response: Codable, Sendable {
    let id: String
    let ok: Bool
    var error: String? = nil
    var games: [ARC3Game]? = nil
    var observation: ARC3Observation? = nil
    var receiptPath: String? = nil
}

enum ARC3RuntimeError: LocalizedError {
    case invalid(String)
    case stopped
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .stopped: return "ARC3 session stopped."
        }
    }
}

protocol ARC3Transport: Sendable {
    func request(_ request: ARC3Request) async throws -> ARC3Response
    func stop()
}

/// One owned offline child. The serial worker handles all blocking pipe work.
/// The lock guards process retirement only; no SDK or model runs on the main actor.
final class ARC3Runtime: ARC3Transport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ARCHi.ARC3.transport", qos: .userInitiated)
    private let lock = NSLock()
    private let runtimeRoot: URL
    private let outputDirectory: URL
    private let bridgeURL: URL?
    private let timeout: TimeInterval
    private var retired = false
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()
    private static let maximumResponseBytes = 512 * 1024

    init(runtimeRoot: URL, outputDirectory: URL, bridgeURL: URL? = nil, timeout: TimeInterval = 45) {
        self.runtimeRoot = runtimeRoot
        self.outputDirectory = outputDirectory
        // The installed app packages resources directly, like ReactorBridge.
        // Bundle.module traps when SwiftPM's development bundle is absent.
        self.bridgeURL = bridgeURL ?? Bundle.main.resourceURL?.appendingPathComponent("ARC3Bridge/archi_arc3_bridge.py")
        self.timeout = timeout
    }

    func request(_ request: ARC3Request) async throws -> ARC3Response {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do { continuation.resume(returning: try exchange(request)) }
                    catch { stop(); continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.stop() }
    }

    func stop() {
        lock.lock()
        retired = true
        let child = process
        lock.unlock()
        guard let child, child.isRunning else { return }
        child.terminate()
        // Retain the Process object and check liveness before killing this child.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.75) {
            if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
        }
    }

    private func ensureRunning() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !retired else { throw ARC3RuntimeError.stopped }
        if let process {
            guard process.isRunning else { throw ARC3RuntimeError.invalid("ARC3 runtime exited.") }
            return
        }
        guard let bridgeURL, FileManager.default.fileExists(atPath: bridgeURL.path) else {
            throw ARC3RuntimeError.invalid("The bundled ARC3 bridge is missing.")
        }
        let interpreter = runtimeRoot.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: interpreter.path),
              FileManager.default.fileExists(atPath: runtimeRoot.appendingPathComponent("environment_files").path) else {
            throw ARC3RuntimeError.invalid("Local ARC3 SDK or games are unavailable at \(runtimeRoot.path).")
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let child = Process()
        child.executableURL = interpreter
        child.arguments = ["-I", "-B", bridgeURL.path,
                           "--environments-dir", runtimeRoot.appendingPathComponent("environment_files").path,
                           "--recordings-dir", outputDirectory.path]
        child.currentDirectoryURL = outputDirectory
        // Deliberately construct a fresh environment: no inherited tokens, Python
        // paths, proxy settings, provider config, or .env loading authority.
        child.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
                             "HOME": outputDirectory.path, "TMPDIR": outputDirectory.path,
                             "OPERATION_MODE": "offline", "PYTHON_DOTENV_DISABLED": "1",
                             "MPLBACKEND": "Agg", "MPLCONFIGDIR": outputDirectory.appendingPathComponent("matplotlib").path]
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = FileHandle.nullDevice
        try child.run()
        process = child
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        // Nonblocking reads plus poll enforce a deadline even on partial JSON.
        _ = fcntl(stdoutPipe.fileHandleForReading.fileDescriptor, F_SETFL, O_NONBLOCK)
    }

    private func exchange(_ request: ARC3Request) throws -> ARC3Response {
        try ensureRunning()
        guard let input, let output else { throw ARC3RuntimeError.stopped }
        var encoded = try JSONEncoder().encode(request)
        guard encoded.count <= 4096 else { throw ARC3RuntimeError.invalid("ARC3 request is too large.") }
        encoded.append(10)
        try input.write(contentsOf: encoded)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            lock.lock(); let stopped = retired; lock.unlock()
            if stopped { throw ARC3RuntimeError.stopped }
            if let newline = pending.firstIndex(of: 10) {
                let line = pending[..<newline]
                pending.removeSubrange(...newline)
                let response: ARC3Response
                do { response = try JSONDecoder().decode(ARC3Response.self, from: line) }
                catch { throw ARC3RuntimeError.invalid("ARC3 runtime returned malformed data.") }
                guard response.id == request.id else { throw ARC3RuntimeError.invalid("ARC3 response identity mismatch.") }
                guard response.ok else { throw ARC3RuntimeError.invalid("ARC3 request failed: \(String((response.error ?? "unknown error").prefix(160)))") }
                return response
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw ARC3RuntimeError.invalid("ARC3 runtime timed out.") }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let readiness = Darwin.poll(&descriptor, 1, Int32(min(remaining * 1000, 100)))
            if readiness < 0 && errno == EINTR { continue }
            guard readiness >= 0 else { throw ARC3RuntimeError.invalid("ARC3 response pipe failed.") }
            if readiness == 0 { continue }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(output.fileDescriptor, &buffer, buffer.count)
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard count > 0 else { throw ARC3RuntimeError.invalid("ARC3 runtime closed its response pipe.") }
            pending.append(contentsOf: buffer.prefix(count))
            guard pending.count <= Self.maximumResponseBytes else { throw ARC3RuntimeError.invalid("ARC3 response exceeded its size limit.") }
        }
    }

    deinit { stop() }
}
