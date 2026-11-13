# Continuity validation and native handoff

Validated 13 November 2026 against base commit `ffee7ea9e77632de7cb13d816bff85dc498d9c1a` in an isolated Linux checkout. The change adds continuity postconditions to existing state owners. It is not an installed application or an integration into the separately authored QiMon game.

## Executed checks

| Check | Observed result |
| --- | --- |
| Retained TypeScript source suite | 275 tests passed, including 15 new continuity cases |
| Foundation contracts | 11 tests passed |
| PWA contracts | 10 tests passed |
| Synthetic ARC lab | 23 tests passed |
| TypeScript typechecking and production/PWA build | Passed |
| Exact native continuity guard and exact XCTest source in an isolated SwiftPM target | 9 tests passed with warnings treated as errors |
| Five changed/new native files | Swift syntax parsing passed |
| Independent review of the guards and the inductive replay path | No remaining blocking issue found |

TypeScript validation used Node 24.22.1, the repository's locked dependencies, and `VITEST_MAX_WORKERS=1 npm run check`. Tests ran without skipped cases. An earlier concurrent run hit the test runner's five-second default timeout on the existing 64-practice capacity test. The unchanged baseline was also close to that limit. The final complete suite passed with one worker and without increasing the timeout. No application speed or reliability improvement is inferred from these timings.

The portable Swift check used the official Swift 6.0.3 Linux toolchain and compiles the actual production `KinGrowthContinuity.swift` and its actual nine-test file. Synthetic evidence values exercise the guard. Full AppKit/SwiftUI compilation, the added actual-record adapter test in `KinGrowthStoreTests`, native UI behavior and installed persistence were not executed in this environment.

Independent review found an extra-field fault in the initial TypeScript projection comparison: an unknown role entry could disappear from the projection tuple. Exact nested field-shape checks now reject that case, and the regression is included. Review was performed by another assistant agent; it is not external certification.

## Reproduce portable checks

```sh
npm ci
VITEST_MAX_WORKERS=1 npm run check
./script/check_kin_continuity.sh
```

The Swift command requires Swift 6 on PATH. `SWIFT_BIN=/absolute/path/to/swift` selects an isolated toolchain. The script copies the exact guard and tests into a temporary package, runs them and removes the package. It does not open a user profile, install ARCHi, invoke a provider or modify companion saves.

## Native qualification

Use the current Mac authoring checkout, inspect its local changes, and reconcile this focused change with its actual revision. The repository has other unmerged work; do not replace the authoring directory with this source snapshot.

On macOS 14 or later with the supported Swift toolchain and macOS SDK:

```sh
swift build --package-path desktop
swift test --package-path desktop
```

Report opt-in skips separately. Do not activate live providers, screen capture or real personal-profile tests to remove skips. Include `KinGrowthContinuityTests` and `KinGrowthStoreTests` in the native result. Follow the existing packaging, profile-preservation and installation workflow only after native qualification.

Using a disposable profile, verify this complete sequence:

1. Establish the existing supported useful-lesson evidence and review First Light for the current KIN origin.
2. Keep that exact preview. Confirm the retained body record has the reviewed proposal ID and unchanged evidence reference.
3. Return to Core Seed and resume First Light. Confirm the same origin, record ID and evidence remain, and the selected body matches the request.
4. Change a relevant revision or submit a foreign-origin, substituted-ID, changed-evidence or wrong-target candidate. Confirm it is rejected and the existing record is preserved.
5. Save explicitly, close the app completely, reopen, and verify the same identity, retained history and requested body choice. Inspect the saved bytes and displayed state through the existing owner.

Successful completion is the missing evidence for native installation acceptance. Syntax checks and the portable guard tests do not replace it.

## Authored QiMon game qualification

The retained Journey/practice implementation was changed and tested here. The current native app does not launch that retained Habitat/Arena. The Unity project in this repository is a disconnected preview, and the intended independently authored QiMon game source was not available in this checkout.

Connect the actual game project and its save owner before adapting these contracts there. Preserve its existing assets and identity/progression schema. Demonstrate a clean fresh-save playthrough and a cold reopen; verify that rejected transitions do not duplicate rewards, erase prior history or change the companion's identity. Robot and human-coupled actions require their own device-specific qualification. Do not label a source patch or a story document as installation evidence.

## Mathematical and operational limits

- The checks protect the declared bounded transitions. They do not solve arbitrary planning or implement an optimizer.
- The retained Journey's one-step replay is sound because the original chain has already been verified and the exact old prefix must be unchanged. Future call sites must preserve that private precondition.
- Effect and scope checks complement replay, but replay shares the production reducer. Shared implementation errors remain possible.
- Failure detection, verified repair, persistence and physical stopping are distinct obligations.
- There is no claim of quantum fault tolerance, quadratic software-error suppression, consciousness measurement or guaranteed recovery.

See [continuity during transformation](CONTINUITY_UNDER_TRANSFORMATION.md) for the system contract and research attribution.
