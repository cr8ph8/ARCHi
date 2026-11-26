import Foundation

@MainActor
protocol ReactorWorkerPort: AnyObject {
    func launch(onLine: @escaping @MainActor @Sendable (Data) -> Void,
                onExit: @escaping @MainActor @Sendable () -> Void) throws
    func send(_ message: Data)
    func terminate()
}

/// One stdio child, never a listener or a second provider session owner.
@MainActor
final class ReactorWorkerConnection: ReactorWorkerPort {
    let python: URL
    let script: URL
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private let writer = DispatchQueue(label: "archi.reactor.input")
    var isRunning: Bool { process?.isRunning == true }

    init(python: URL, script: URL) { self.python = python; self.script = script }

    func launch(onLine: @escaping @MainActor @Sendable (Data) -> Void,
                onExit: @escaping @MainActor @Sendable () -> Void) throws {
        guard process == nil else { throw CocoaError(.executableLoad) }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = python; child.arguments = ["-I", "-u", script.path]
        child.currentDirectoryURL = script.deletingLastPathComponent()
        // The credential is sent once on stdin, never in argv, environment or a log.
        child.environment = ["PATH": "/usr/bin:/bin", "PYTHONUNBUFFERED": "1", "PYTHONDONTWRITEBYTECODE": "1"]
        child.standardInput = stdin; child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        let reader = LocalWorkerLineBuffer(onLine: onLine)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            reader.append(bytes)
        }
        child.terminationHandler = { _ in Task { @MainActor in onExit() } }
        try child.run()
        process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
    }

    func send(_ message: Data) {
        guard let handle = input, message.count <= 2_500_000 else { return }
        var framed = message; framed.append(10)
        let bytes = framed
        writer.async { try? handle.write(contentsOf: bytes) }
    }

    func terminate() {
        let child = process; process = nil
        output?.readabilityHandler = nil
        try? output?.close(); output = nil
        try? input?.close(); input = nil
        guard let child, child.isRunning else { return }
        child.terminate()
        // A stuck decoder must not survive the native owner's shutdown.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
}

final class LocalWorkerLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var invalid = false
    private let onLine: @MainActor @Sendable (Data) -> Void
    init(onLine: @escaping @MainActor @Sendable (Data) -> Void) { self.onLine = onLine }
    func append(_ bytes: Data) {
        lock.lock()
        guard !invalid else { lock.unlock(); return }
        buffer.append(bytes)
        guard buffer.count <= 4_000_000 else { invalid = true; buffer.removeAll(); lock.unlock(); return }
        var lines: [Data] = []
        while let index = buffer.firstIndex(of: 10) {
            lines.append(Data(buffer[..<index])); buffer.removeSubrange(...index)
        }
        lock.unlock()
        for line in lines { Task { @MainActor [onLine] in onLine(line) } }
    }
}
