import CryptoKit
import Darwin
import Foundation

// Versioned file exchange shared verbatim by WikiOS and ARCHi. Files carry
// reviewed work, never executable instructions, credentials or completion authority.
struct QiWorkRequest: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var kind = "wikios.task"
    let requestID: String
    let taskID: String
    let projectID: String
    let projectName: String
    let taskTitle: String
    let taskRevision: String
    let createdAtUnix: Double
    let brief: String
    let briefSHA256: String

    func validate() throws {
        guard schemaVersion == 1, kind == "wikios.task", QiWorkExchange.isID(requestID),
              QiWorkExchange.isText(taskID, limit: 128), QiWorkExchange.isText(projectID, limit: 128),
              QiWorkExchange.isText(projectName, limit: 512), QiWorkExchange.isText(taskTitle, limit: 1_024),
              QiWorkExchange.isText(taskRevision, limit: 128), QiWorkExchange.isDate(createdAtUnix),
              QiWorkExchange.isText(brief, limit: 80_000), briefSHA256 == QiWorkExchange.digest(Data(brief.utf8)) else {
            throw QiWorkExchangeError.invalid
        }
    }
}

struct QiWorkResult: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var kind = "archi.result"
    let resultID: String
    let requestID: String
    let requestSHA256: String
    let taskID: String
    let projectID: String
    let taskRevision: String
    let createdAtUnix: Double
    let summary: String
    let text: String
    let textSHA256: String
    let sourceRevision: UInt64

    func validate() throws {
        guard schemaVersion == 1, kind == "archi.result", QiWorkExchange.isID(resultID), QiWorkExchange.isID(requestID),
              QiWorkExchange.isHash(requestSHA256), QiWorkExchange.isText(taskID, limit: 128),
              QiWorkExchange.isText(projectID, limit: 128), QiWorkExchange.isText(taskRevision, limit: 128),
              QiWorkExchange.isDate(createdAtUnix), QiWorkExchange.isText(summary, limit: 4_000),
              QiWorkExchange.isText(text, limit: 100_000), textSHA256 == QiWorkExchange.digest(Data(text.utf8)),
              sourceRevision > 0 else { throw QiWorkExchangeError.invalid }
    }

    func validate(request: QiWorkRequestFile) throws {
        try validate()
        guard requestID == request.request.requestID, requestSHA256 == request.digest,
              taskID == request.request.taskID, projectID == request.request.projectID,
              taskRevision == request.request.taskRevision,
              createdAtUnix >= request.request.createdAtUnix - 5 else { throw QiWorkExchangeError.unmatched }
    }
}

struct QiWorkRequestFile: Equatable, Sendable, Identifiable {
    let url: URL
    let request: QiWorkRequest
    let digest: String
    var id: String { request.requestID }
    static func read(_ url: URL) throws -> Self {
        guard url.pathExtension.lowercased() == "qitask" else { throw QiWorkExchangeError.invalid }
        let bytes = try QiWorkExchange.read(url)
        let value = try JSONDecoder().decode(QiWorkRequest.self, from: bytes)
        try value.validate()
        return Self(url: url.standardizedFileURL, request: value, digest: QiWorkExchange.digest(bytes))
    }
    func verifyUnchanged() throws {
        guard try Self.read(url).digest == digest else { throw QiWorkExchangeError.changed }
    }
}

struct QiWorkResultFile: Sendable, Identifiable {
    let url: URL
    let result: QiWorkResult
    let digest: String
    var id: String { result.resultID }
    static func read(_ url: URL) throws -> Self {
        guard url.pathExtension.lowercased() == "qiresult" else { throw QiWorkExchangeError.invalid }
        let bytes = try QiWorkExchange.read(url)
        let value = try JSONDecoder().decode(QiWorkResult.self, from: bytes)
        try value.validate()
        return Self(url: url.standardizedFileURL, result: value, digest: QiWorkExchange.digest(bytes))
    }
    func verifyUnchanged() throws {
        guard try Self.read(url).digest == digest else { throw QiWorkExchangeError.changed }
    }
}

enum QiWorkExchange {
    static let maximumBytes = 524_288
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func isID(_ value: String) -> Bool { UUID(uuidString: value) != nil && !value.contains("/") }
    static func isHash(_ value: String) -> Bool { value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    static func isDate(_ value: Double) -> Bool { value.isFinite && (1...253_402_300_799).contains(value) }
    static func isText(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= limit && !value.contains("\0")
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(value)
        guard bytes.count <= maximumBytes else { throw QiWorkExchangeError.oversized }
        return bytes
    }
    static func read(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw QiWorkExchangeError.unreadable }
        let fd = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard fd >= 0 else { throw QiWorkExchangeError.unreadable }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? file.close() }
        var stat = Darwin.stat()
        guard fstat(fd, &stat) == 0, stat.st_mode & S_IFMT == S_IFREG else { throw QiWorkExchangeError.unreadable }
        guard stat.st_size > 0, stat.st_size <= maximumBytes else { throw QiWorkExchangeError.oversized }
        let bytes = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { throw QiWorkExchangeError.oversized }
        return bytes
    }
    /// Creates a new owned file only. Never overwrites a source or another export.
    static func writeNew(_ bytes: Data, to url: URL) throws {
        guard url.isFileURL, !bytes.isEmpty, bytes.count <= maximumBytes else { throw QiWorkExchangeError.oversized }
        // Hold each directory descriptor while traversing. Ancestor symlinks
        // cannot redirect an owned export into another application's files.
        var parentFD = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parentFD >= 0 else { throw QiWorkExchangeError.unreadable }
        defer { Darwin.close(parentFD) }
        for component in url.standardizedFileURL.deletingLastPathComponent().pathComponents.dropFirst() {
            let made = component.withCString { mkdirat(parentFD, $0, 0o700) }
            guard made == 0 || errno == EEXIST else { throw QiWorkExchangeError.writeFailed }
            let next = component.withCString { openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { throw QiWorkExchangeError.unreadable }
            Darwin.close(parentFD); parentFD = next
        }
        let fd = url.lastPathComponent.withCString { openat(parentFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw QiWorkExchangeError.writeFailed }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try file.write(contentsOf: bytes); try file.synchronize(); try file.close()
            guard try read(url) == bytes else { throw QiWorkExchangeError.writeFailed }
        } catch { try? file.close(); throw error }
    }
}

enum QiWorkExchangeError: LocalizedError {
    case invalid, unreadable, oversized, changed, unmatched, writeFailed
    var errorDescription: String? {
        switch self {
        case .invalid: "This file is not a supported Qi task or result. Its content was not imported."
        case .unreadable: "Choose a regular local task or result file. Symbolic links are not accepted."
        case .oversized: "This exchange file is empty or too large. Shorten the work before sending it."
        case .changed: "The file changed after review. Open it again before continuing."
        case .unmatched: "This result does not match the original task sent by this WikiOS workspace."
        case .writeFailed: "The exchange file could not be saved as a new verified copy. Nothing was sent."
        }
    }
}
