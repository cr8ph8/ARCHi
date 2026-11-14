import Foundation
import Darwin

/// Both saved owners and the recovery journal live in the same directory.
/// Lock a stable file there so replacing or deleting a save never drops the lock.
enum DesktopProfileLock {
    static let filename = ".archi-desktop-profile.lock"

    enum Failure: LocalizedError {
        case busy, invalidLocation

        var errorDescription: String? {
            switch self {
            case .busy: "Another ARCHi session is using this profile. Try again when it finishes."
            case .invalidLocation: "The profile lock must be a regular local file."
            }
        }
    }

    static func withLock<T>(at member: URL, _ operation: () throws -> T) throws -> T {
        guard member.isFileURL else { throw Failure.invalidLocation }
        try FileManager.default.createDirectory(at: member.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let result = try withLockIfDirectoryExists(at: member, operation) else {
            throw Failure.invalidLocation
        }
        return result
    }

    static func withLockIfDirectoryExists<T>(at member: URL, _ operation: () throws -> T) throws -> T? {
        try withOpenLock(at: member, forWriting: true, operation)
    }

    /// Capture profile bytes without creating files. The snapshot may be read twice.
    static func read<T>(at member: URL, _ snapshot: () throws -> T) throws -> T {
        if let saved = try withOpenLock(at: member, forWriting: false, snapshot) { return saved }
        // A first writer creates the stable lock before touching either file.
        // If it appeared during the read, discard that snapshot and read under it.
        let first = Result(catching: snapshot)
        if let saved = try withOpenLock(at: member, forWriting: false, snapshot) { return saved }
        return try first.get()
    }

    private static func withOpenLock<T>(at member: URL, forWriting: Bool, _ operation: () throws -> T) throws -> T? {
        guard member.isFileURL else { throw Failure.invalidLocation }
        let lock = member.deletingLastPathComponent().appendingPathComponent(filename)
        let access = forWriting ? O_RDWR | O_CREAT : O_RDONLY
        let descriptor = lock.path.withCString {
            Darwin.open($0, access | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        }
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        // Closing releases the lock. Leave the file in place so all sessions lock the same inode.
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError() }
        guard info.st_mode & S_IFMT == S_IFREG else { throw Failure.invalidLocation }
        let mode = forWriting ? LOCK_EX : LOCK_SH
        while flock(descriptor, mode | LOCK_NB) != 0 {
            if errno == EINTR { continue }
            if errno == EWOULDBLOCK { throw Failure.busy }
            throw posixError()
        }
        return .some(try operation())
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
