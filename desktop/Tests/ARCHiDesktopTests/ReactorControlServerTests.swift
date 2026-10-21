import Darwin
import Foundation
import Testing
@testable import ARCHiDesktop

@Suite("Local Reactor control", .serialized)
@MainActor
struct ReactorControlServerTests {
    private func directory() -> URL {
        URL(fileURLWithPath: "/private/tmp/archi-rctl-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func privateSocketRoutesLocalActionsToMainActor() async throws {
        let root = directory()
        var actions: [String] = []
        let server = ReactorControlServer(profile: .review, directoryURL: root) { request in
            MainActor.assertIsolated()
            actions.append(request["action"] as! String)
            return ["ok": true, "state": "localPreview", "providerCalls": 0]
        }
        defer { server.stop(); try? FileManager.default.removeItem(at: root) }
        try server.start()
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        let socketAttributes = try FileManager.default.attributesOfItem(atPath: server.socketURL.path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((socketAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        for action in ["status", "prepare", "preview", "stop"] {
            let response = try await roundTrip(server.socketURL.path, "{\"action\":\"\(action)\"}\n")
            let object = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
            #expect(object["ok"] as? Bool == true)
            #expect(object["providerCalls"] as? Int == 0)
        }
        #expect(actions == ["status", "prepare", "preview", "stop"])
    }

    @Test func liveCredentialMalformedAndOversizeRequestsNeverReachOwner() async throws {
        let root = directory(); var calls = 0
        let server = ReactorControlServer(profile: .review, directoryURL: root) { _ in calls += 1; return ["ok": true] }
        defer { server.stop(); try? FileManager.default.removeItem(at: root) }
        try server.start()
        for payload in ["{\"action\":\"start\"}\n", "{\"action\":\"preview\",\"apiKey\":\"PRIVATE\"}\n",
                        "[]\n", "not-json\n", "{\"action\":\"status\"}\n{\"action\":\"preview\"}\n"] {
            let response = try await roundTrip(server.socketURL.path, payload)
            let object = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
            #expect(object["ok"] as? Bool == false)
            #expect(!String(decoding: response, as: UTF8.self).contains("PRIVATE"))
        }
        let response = try await roundTrip(server.socketURL.path, String(repeating: "x", count: ReactorControlServer.maximumMessageBytes + 1) + "\n")
        #expect(String(decoding: response, as: UTF8.self).contains("false"))
        #expect(calls == 0)
    }

    @Test func privateResponseKeysAreNotExposed() async throws {
        let root = directory()
        let server = ReactorControlServer(profile: .review, directoryURL: root) { _ in ["nested": ["api_key": "PRIVATE"]] }
        defer { server.stop(); try? FileManager.default.removeItem(at: root) }
        try server.start()
        let response = try await roundTrip(server.socketURL.path, "{\"action\":\"status\"}\n")
        #expect(String(decoding: response, as: UTF8.self).contains("false"))
        #expect(!String(decoding: response, as: UTF8.self).contains("PRIVATE"))
    }

    @Test func connectionMayArriveBeforeItsPayload() async throws {
        let root = directory()
        let server = ReactorControlServer(profile: .review, directoryURL: root) { _ in ["ok": true] }
        defer { server.stop(); try? FileManager.default.removeItem(at: root) }
        try server.start()
        let response = try await roundTrip(server.socketURL.path, "{\"action\":\"prepare\"}\n", delayBeforeWrite: true)
        let object = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
        #expect(object["ok"] as? Bool == true)
    }

    @Test func profileLockPreventsStealingLiveSocketAndAllowsRestart() async throws {
        let root = directory()
        let first = ReactorControlServer(profile: .review, directoryURL: root) { _ in ["owner": "first"] }
        let second = ReactorControlServer(profile: .review, directoryURL: root) { _ in ["owner": "second"] }
        defer { first.stop(); second.stop(); try? FileManager.default.removeItem(at: root) }
        try first.start()
        #expect(throws: (any Error).self) { try second.start() }
        let oldResponse = try await roundTrip(first.socketURL.path, "{\"action\":\"status\"}\n")
        #expect(String(decoding: oldResponse, as: UTF8.self).contains("first"))
        first.stop()
        #expect(!FileManager.default.fileExists(atPath: first.socketURL.path))
        try second.start()
        let newResponse = try await roundTrip(second.socketURL.path, "{\"action\":\"status\"}\n")
        #expect(String(decoding: newResponse, as: UTF8.self).contains("second"))
    }

    @Test func unsafeDirectoryAndForeignSocketEntryRemainUntouched() throws {
        let root = directory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: root) }
        let server = ReactorControlServer(profile: .review, directoryURL: root) { _ in [:] }
        #expect(throws: (any Error).self) { try server.start() }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try Data("authored".utf8).write(to: server.socketURL)
        #expect(throws: (any Error).self) { try server.start() }
        #expect(try String(contentsOf: server.socketURL, encoding: .utf8) == "authored")
    }

    @Test func stopNeverUnlinksReplacementEntry() throws {
        let root = directory()
        let server = ReactorControlServer(profile: .review, directoryURL: root) { _ in [:] }
        defer { server.stop(); try? FileManager.default.removeItem(at: root) }
        try server.start()
        let displaced = root.appendingPathComponent("displaced.sock")
        try FileManager.default.moveItem(at: server.socketURL, to: displaced)
        try Data("replacement".utf8).write(to: server.socketURL)
        server.stop()
        #expect(try String(contentsOf: server.socketURL, encoding: .utf8) == "replacement")
    }

    private func roundTrip(_ path: String, _ payload: String, delayBeforeWrite: Bool = false) async throws -> Data {
        try await Task.detached {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw TestError.socket(operation: "create", code: errno) }
            defer { close(fd) }
            // Concurrent MainActor rendering exceeded seven seconds on the CI host.
            // Bound the test client independently of the production server's three-second input timeout.
            var timeout = timeval(tv_sec: 15, tv_usec: 0), noSignal: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                for (index, byte) in path.utf8CString.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
            }
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else { throw TestError.socket(operation: "connect", code: errno) }
            if delayBeforeWrite { try await Task.sleep(for: .milliseconds(100)) }
            try Data(payload.utf8).withUnsafeBytes { bytes in
                var sent = 0
                while sent < bytes.count {
                    let count = write(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw TestError.socket(operation: "write", code: errno) }
                    sent += count
                }
            }
            var response = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while response.count <= ReactorControlServer.maximumMessageBytes {
                let count = read(fd, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw TestError.socket(operation: "read", code: count == 0 ? 0 : errno) }
                response.append(contentsOf: buffer.prefix(count))
                if let newline = response.firstIndex(of: 10) { return Data(response[..<newline]) }
            }
            throw TestError.socket(operation: "response size", code: EMSGSIZE)
        }.value
    }

    private enum TestError: Error { case socket(operation: String, code: Int32) }
}
