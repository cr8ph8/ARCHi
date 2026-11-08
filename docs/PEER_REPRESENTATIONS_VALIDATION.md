# Local representation and peer validation

This record covers the source increment on `codex/peer-representation-admission`, based on `ffee7ea9e77632de7cb13d816bff85dc498d9c1a`. Implementation and the executed checks used a real local Linux checkout. They did not access, update, build or install the owner's Mac project.

## Executed checks

| Check | Observed result | Scope |
| --- | --- | --- |
| Foundation core typecheck | Passed with Swift 6.0.3 and warnings treated as errors | The four new representation, directory, worker-session and gossip-simulation files |
| Portable XCTest harness | 12 tests passed; 0 failures, 0 unexpected failures; no test was skipped | Compiled and executed the same four core files and shared `RepresentationPeerTests.swift` in a disposable SwiftPM package |
| Native syntax parsing | Passed with no diagnostics | Native peer workspace, both modified existing owners, and the seven-case native integration test file; parsing is not typechecking or execution |
| Fixture digest references | All four matched SHA-256 of their documented fixed manifest strings | Fixture reference consistency; no real image, renderer or model output was verified |
| Harness shell syntax and cleanup | Passed | Temporary build/cache/package removed after the run |
| Diff whitespace | Passed | The source change |
| Complete source manifest | Passed for all 1134 tracked source files | Content hashes, path uniqueness and full coverage |

The portable run reported:

```text
Build complete! (11.12s)
Executed 12 tests, with 0 failures (0 unexpected) in 0.54 seconds
```

The executed command used the locally installed Swift 6.0.3 binary through `SWIFT_BIN`:

```sh
SWIFT_BIN=/absolute/path/to/swift script/test_representation_peers.sh
```

The tests exercise delivery/observation deduplication; source-preserving relays; scoped identity collisions; session and recipient boundaries; invalid representations, capacity and time; explicit report admission; stale, missing, expired, cancelled and superseded attempts; skipped/error/failed checks; deterministic gossip convergence and round bounds; and isolated peers receiving no undelivered knowledge. These are in-process protocol tests, not real network or failure-detector tests.

Source review also corrected a local-conversation reset path that previously could leave an idle candidate pending. Both ordinary cancellation and local-work cancellation now fence peer inspection. The new native reset regression is authored but has not executed on macOS.

## Pending or blocked

| Check | Status | What remains |
| --- | --- | --- |
| Native package compile | Not run | macOS SDK and the current local authoring checkout |
| Seven native peer integration tests | Authored and syntax parsed; not executed | Run on macOS with the existing synthetic fixture clients |
| Existing desktop regression suite | Not run for this increment | Run the relevant native owner and graph tests on macOS |
| SwiftUI presentation, keyboard and VoiceOver | Not observed | Review the actual Mac app at representative window sizes |
| Codex CLI review | Blocked before review | Installed CLI was authenticated but its app-server initialization failed with a read-only-filesystem error, including the documented temporary-state retry |
| GitHub Actions | Not run | The repository still contains a workflow template, not an enabled workflow |
| Local Mac application/installation | Not performed | Reconcile this increment with the existing Mac folder, then use its established build workflow |

The [local Codex handoff](CODEX_LOCAL_PEER_HANDOFF.md) provides a concrete continuation task. Passing portable core tests does not qualify native runtime behavior, production network peers, remote authentication, distributed writes, model learning, image understanding or particle/rendering integration.
