import Foundation
import Testing
@testable import ARCHiDesktop

@Suite(.serialized)
@MainActor
struct LocalQwenRuntimeTests {
    @Test func existingServiceIsReusedWithoutDiscoveryLaunchOrTermination() async throws {
        let fixture = RuntimeFixture(probes: [true])
        let runtime = fixture.runtime()
        try await runtime.ensureRunning()
        runtime.cancelStartup()
        runtime.shutdown()
        #expect(fixture.probeCount == 1)
        #expect(fixture.discoveryCount == 0)
        #expect(fixture.launches.isEmpty)
        #expect(fixture.child.terminationCount == 0)
    }

    @Test func installedRuntimeStartsOnceAndRemainsOwnedUntilAppShutdown() async throws {
        let fixture = RuntimeFixture(probes: [false, false, true, true])
        let runtime = fixture.runtime()
        try await runtime.ensureRunning()
        try await runtime.ensureRunning()
        runtime.cancelStartup()
        #expect(fixture.launches.count == 1)
        #expect(fixture.child.terminationCount == 0)
        runtime.shutdown()
        runtime.shutdown()
        #expect(fixture.child.terminationCount == 1)
    }

    @Test func launchUsesExplicitExecutableWithLocalOnlyEnvironmentAndNoPull() async throws {
        let fixture = RuntimeFixture(probes: [false, true])
        fixture.environment = ["HOME": "/Users/fixture", "OLLAMA_MODELS": "/Models",
            "OLLAMA_HOST": "0.0.0.0:9999", "OLLAMA_ORIGINS": "*", "OLLAMA_NO_CLOUD": "0",
            "HTTP_PROXY": "https://proxy.invalid", "HTTPS_PROXY": "https://proxy.invalid",
            "ALL_PROXY": "https://proxy.invalid", "DYLD_INSERT_LIBRARIES": "/bad.dylib",
            "PATH": "/untrusted", "SECRET": "not-inherited"]
        let runtime = fixture.runtime()
        defer { runtime.shutdown() }
        try await runtime.ensureRunning()
        let configuration = try #require(fixture.launches.first)
        #expect(configuration.executableURL == fixture.executable)
        #expect(configuration.arguments == ["serve"])
        #expect(configuration.environment == ["HOME": "/Users/fixture", "OLLAMA_MODELS": "/Models",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "OLLAMA_HOST": "127.0.0.1:11434",
            "OLLAMA_NO_CLOUD": "1", "OLLAMA_NOPRUNE": "1",
            "OLLAMA_ORIGINS": "http://127.0.0.1,http://localhost"])
    }

    @Test func missingInstallationFailsWithoutLaunchingAnything() async {
        let fixture = RuntimeFixture(probes: [false])
        fixture.executable = nil
        let runtime = fixture.runtime()
        await #expect(throws: LocalQwenRuntimeFailure.notInstalled) { try await runtime.ensureRunning() }
        #expect(fixture.launches.isEmpty)
    }

    @Test func failedLaunchReportsFailureWithoutRetainingAChild() async {
        let fixture = RuntimeFixture(probes: [false])
        fixture.launchFails = true
        let runtime = fixture.runtime()
        await #expect(throws: LocalQwenRuntimeFailure.startFailed) { try await runtime.ensureRunning() }
        runtime.shutdown()
        #expect(fixture.child.terminationCount == 0)
    }

    @Test func startupTimeoutStopsOnlyTheNewOwnedChild() async {
        let fixture = RuntimeFixture(probes: [false])
        let runtime = fixture.runtime(timeout: .seconds(1))
        await #expect(throws: LocalQwenRuntimeFailure.timedOut) { try await runtime.ensureRunning() }
        #expect(fixture.elapsed == .seconds(1))
        #expect(fixture.launches.count == 1)
        #expect(fixture.child.terminationCount == 1)
        runtime.shutdown()
        #expect(fixture.child.terminationCount == 1)
    }

    @Test func aProcessThatExitsBeforeReadinessFailsWithoutWaitingForDeadline() async {
        let fixture = RuntimeFixture(probes: [false])
        fixture.child.isRunning = false
        let runtime = fixture.runtime()
        await #expect(throws: LocalQwenRuntimeFailure.startFailed) { try await runtime.ensureRunning() }
        #expect(fixture.elapsed == .zero)
        #expect(fixture.child.terminationCount == 0)
    }

    @Test func concurrentCallersShareLaunchAndCancellingOnePreservesTheOther() async throws {
        let fixture = RuntimeFixture(probes: [false])
        fixture.holdProbe = 2
        let runtime = fixture.runtime()
        defer { runtime.shutdown() }
        let first = Task { try await runtime.ensureRunning() }
        try await eventually { fixture.heldProbe != nil }
        var secondStarted = false
        let second = Task {
            secondStarted = true
            try await runtime.ensureRunning()
        }
        try await eventually { secondStarted }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(fixture.child.terminationCount == 0)
        fixture.releaseProbe(true)
        try await second.value
        #expect(fixture.launches.count == 1)
    }

    @Test func cancellingLastCallerStopsItsPendingChildAndRejectsLateReadiness() async throws {
        let fixture = RuntimeFixture(probes: [false])
        fixture.holdProbe = 2
        let runtime = fixture.runtime()
        let first = Task { try await runtime.ensureRunning() }
        try await eventually { fixture.heldProbe != nil }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(fixture.child.terminationCount == 1)
        fixture.releaseProbe(true)
        await Task.yield()
        runtime.shutdown()
        #expect(fixture.child.terminationCount == 1)
    }

    @Test func cancelledStartupRetainsSlowChildAndBlocksReuseUntilObservedExit() async throws {
        let fixture = RuntimeFixture(probes: [false])
        fixture.child.exitsOnTerminate = false
        fixture.holdProbe = 2
        let runtime = fixture.runtime(timeout: .seconds(1))
        defer { runtime.shutdown() }
        let pending = Task { try await runtime.ensureRunning() }
        try await eventually { fixture.heldProbe != nil }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(fixture.child.terminationCount == 1)
        #expect(fixture.child.isRunning)
        fixture.releaseProbe(true)
        // A dying service would still answer. Retirement must prevent this probe.
        fixture.probes = [true]
        let probesBeforeRetry = fixture.probeCount
        await #expect(throws: LocalQwenRuntimeFailure.timedOut) { try await runtime.ensureRunning() }
        #expect(fixture.elapsed == .seconds(1))
        #expect(fixture.probeCount == probesBeforeRetry)
        #expect(fixture.discoveryCount == 1)
        #expect(fixture.launches.count == 1)
        #expect(fixture.child.terminationCount == 1)

        fixture.child.isRunning = false
        let replacement = RuntimeFixtureProcess()
        fixture.nextLaunchChild = replacement
        fixture.probes = [false, true]
        try await runtime.ensureRunning()
        #expect(fixture.launches.count == 2)
        #expect(fixture.discoveryCount == 2)
        #expect(replacement.terminationCount == 0)
        runtime.shutdown()
        #expect(replacement.terminationCount == 1)
        #expect(fixture.child.terminationCount == 1)
    }

    @Test func startupTimeoutRetainsSlowChildInsteadOfLaunchingAnother() async {
        let fixture = RuntimeFixture(probes: [false])
        fixture.child.exitsOnTerminate = false
        let runtime = fixture.runtime(timeout: .seconds(1))
        defer { runtime.shutdown() }
        await #expect(throws: LocalQwenRuntimeFailure.timedOut) { try await runtime.ensureRunning() }
        #expect(fixture.child.isRunning)
        #expect(fixture.child.terminationCount == 1)
        let probesBeforeRetry = fixture.probeCount
        fixture.probes = [true]
        await #expect(throws: LocalQwenRuntimeFailure.timedOut) { try await runtime.ensureRunning() }
        #expect(fixture.elapsed == .seconds(2))
        #expect(fixture.probeCount == probesBeforeRetry)
        #expect(fixture.launches.count == 1)
        #expect(fixture.child.terminationCount == 1)
    }

    @Test func shutdownRetainsSlowReadyChildAndDoesNotSignalItAgain() async throws {
        let fixture = RuntimeFixture(probes: [false, true])
        fixture.child.exitsOnTerminate = false
        let runtime = fixture.runtime(timeout: .seconds(1))
        try await runtime.ensureRunning()
        runtime.shutdown()
        runtime.shutdown()
        #expect(fixture.child.isRunning)
        #expect(fixture.child.terminationCount == 1)
        let probesBeforeRetry = fixture.probeCount
        await #expect(throws: LocalQwenRuntimeFailure.timedOut) { try await runtime.ensureRunning() }
        #expect(fixture.elapsed == .seconds(1))
        #expect(fixture.probeCount == probesBeforeRetry)
        #expect(fixture.launches.count == 1)
        #expect(fixture.child.terminationCount == 1)
    }

    @Test func cancelledProbeCannotCompleteANewAttemptOrStartAnOldChild() async throws {
        let fixture = RuntimeFixture(probes: [false])
        fixture.holdProbe = 1
        let runtime = fixture.runtime()
        let first = Task { try await runtime.ensureRunning() }
        try await eventually { fixture.heldProbe != nil }
        runtime.cancelStartup()
        await #expect(throws: CancellationError.self) { try await first.value }
        fixture.executable = nil
        await #expect(throws: LocalQwenRuntimeFailure.notInstalled) { try await runtime.ensureRunning() }
        fixture.releaseProbe(false)
        await Task.yield()
        #expect(fixture.launches.isEmpty)
    }

    @Test func shutdownDuringStartupCancelsWaitersAndStopsOwnedChild() async throws {
        let fixture = RuntimeFixture(probes: [false])
        fixture.holdProbe = 2
        let runtime = fixture.runtime()
        let pending = Task { try await runtime.ensureRunning() }
        try await eventually { fixture.heldProbe != nil }
        runtime.shutdown()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(fixture.child.terminationCount == 1)
        fixture.releaseProbe(true)
    }

    @Test func failedLaterProbeDoesNotTerminateAnAlreadyReadyOwnedService() async throws {
        let fixture = RuntimeFixture(probes: [false, true, false])
        let runtime = fixture.runtime(timeout: .seconds(1))
        try await runtime.ensureRunning()
        await #expect(throws: LocalQwenRuntimeFailure.timedOut) { try await runtime.ensureRunning() }
        #expect(fixture.launches.count == 1)
        #expect(fixture.child.terminationCount == 0)
        runtime.shutdown()
        #expect(fixture.child.terminationCount == 1)
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        throw RuntimeFixtureFailure.waitTimedOut
    }
}

private enum RuntimeFixtureFailure: Error { case launchFailed, waitTimedOut }

@MainActor
private final class RuntimeFixture {
    var probes: [Bool]
    var probeCount = 0
    var holdProbe: Int?
    var heldProbe: CheckedContinuation<Bool, Never>?
    var executable: URL? = URL(fileURLWithPath: "/fixture/Ollama.app/Contents/Resources/ollama")
    var discoveryCount = 0
    var launches: [LocalQwenRuntime.LaunchConfiguration] = []
    var launchFails = false
    var environment: [String: String] = [:]
    var elapsed: Duration = .zero
    let child = RuntimeFixtureProcess()
    var nextLaunchChild: RuntimeFixtureProcess?

    init(probes: [Bool]) { self.probes = probes }

    func runtime(timeout: Duration = .seconds(8)) -> LocalQwenRuntime {
        let dependencies = LocalQwenRuntime.Dependencies(
            probe: { [self] in
                probeCount += 1
                if probeCount == holdProbe {
                    return await withCheckedContinuation { heldProbe = $0 }
                }
                return probes.count > 1 ? probes.removeFirst() : probes.first ?? false
            },
            executable: { [self] in discoveryCount += 1; return executable },
            launch: { [self] configuration in
                launches.append(configuration)
                if launchFails { throw RuntimeFixtureFailure.launchFailed }
                if let nextLaunchChild {
                    self.nextLaunchChild = nil
                    return nextLaunchChild
                }
                return child
            },
            now: { [self] in elapsed },
            sleep: { [self] duration in
                try Task.checkCancellation()
                elapsed += duration
                await Task.yield()
            },
            environment: environment)
        return LocalQwenRuntime(dependencies: dependencies, startupTimeout: timeout, pollInterval: .milliseconds(250))
    }

    func releaseProbe(_ ready: Bool) {
        let continuation = heldProbe
        heldProbe = nil
        continuation?.resume(returning: ready)
    }
}

@MainActor
private final class RuntimeFixtureProcess: LocalQwenRuntimeProcess {
    var isRunning = true
    var exitsOnTerminate = true
    var terminationCount = 0
    func terminate() {
        terminationCount += 1
        if exitsOnTerminate { isRunning = false }
    }
}
