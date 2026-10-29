# Local ARCHi system readiness

Use this workflow to distinguish available source, working prerequisites, a
packaged candidate and an exercised installed app. These are separate facts.
Run it from the main authoring workspace on the Mac that owns the installation.
Reconcile reviewed changes from this curated distribution into that workspace;
do not replace authored work with the publication checkout.

## Read-only inspection

```sh
python3 script/check_local_system.py
```

To retain a new report:

```sh
python3 script/check_local_system.py \
  --report /private/tmp/archi-system-readiness-NEW.json
```

The checker inspects platform/tool versions, source and dependency metadata,
required resources, the installed app's build identity and its bundled helper.
It does not install, build or launch an app; download dependencies or models;
contact providers; inspect bookmarks or preferences; or read profiles and saves.
The report destination must be new. Read `--help` for alternate repository,
app and Editor paths.

The current native source identity includes packaging scripts and local Swift
dependencies, including dirty/untracked native inputs. An older installed
identity can legitimately differ after a recipe or diagnostic changes. The
comparison reports that mismatch; it does not establish that every feature in
the older app is broken. Build identity records pre-sign payload bytes and does
not replace strict signature verification or a final signed-artifact inventory.

An absent Editor blocks authoring and renderer acceptance. It does not by itself
prevent use of an already-built Unity player. Conversely, an installed player
cannot prove that this checkout imports or builds in the Editor.

## What each layer requires

| Layer | Existing implementation | Required evidence |
| --- | --- | --- |
| Native shell and owner state | Swift desktop, local `ARCHiSpatial` package | macOS SDK build, exact installed candidate identity, normal startup/Quit and owner-preserving workflow |
| Q2E numerical control | Shared bounded numerical policy; document, reading, ARC3 and Arena consumers | Synthetic dynamics/attribution/domain tests and observed results in the applicable task owner |
| Memory influence | Reviewed, source-bound evidence through existing native and retained QiMon owners | Migration, persistence, withdrawal, freshness and actual legal ordering tests |
| Desktop orb | Particle body, four registered objects, navigation, highlighting and viewport mapping | Portable checks, real Unity graphics acceptance, native input and installed-player interaction |
| Retained QiMon | Existing TypeScript/game owners | Lockfile dependencies, source tests, production build and synthetic browser interaction |
| Creator Marketplace | Existing loopback service, SQLite store and native collection owner | Synthetic recipe/store/HTTP/restart checks, then actual native connection and installed-service acceptance |
| Local Qwen | Existing native local-model route | Installed Ollama and supported model, metadata check, then a deliberately selected synthetic request when runtime acceptance is intended |
| Optional Reactor | Existing expression owner and packaged Python helper | Helper preserved across updates; separate connection/API trial evidence if that feature is being qualified |
| First Signal | Existing selection/save owner and preserved chapter | Independent qualified chapter resources, preservation receipt and installed continuity |
| Spatial Q2E agent | Not implemented by the current orb feature | Versioned task/target/outcome bridge, attributed feedback and comparative task acceptance |
| Physical headset space | Host adapter accepts tracked pose/room surfaces | Platform sensing/input, real object registration, packaged device app and target-device acceptance |

Finding a source file is not proof of a runtime caller. A successful route is not
proof of object recognition, a useful observation or permission to save learning.
Installing the current source does not implement the last two rows.

## Repeatable source checks

The existing workflows cover portable orb/protocol checks, native presentation,
contextual memory, retained QiMon and installation safeguards. The native memory
workflow also runs the focused Q2E numerical/domain suites and the shared geometry
package as a separate command. The latter matters because testing the desktop
package does not automatically execute a dependency package's own tests.

On the authoring Mac:

```sh
swift test --package-path desktop \
  --filter 'HamptonNumericalDynamicsTests|HamptonQ2EOutcomeAdapterTests|HamptonNumericalDocumentControlTests|HamptonNumericalReadingControlTests|HamptonNumericalARC3ControlTests|HamptonArenaAdviceTests'

swift test --package-path shared/ARCHiSpatial --filter ImageRegionTests
```

The selected mathematical tests use synthetic observations and temporary
journals. They do not start an installed app, model, Unity player or official ARC
benchmark. Their presence in a workflow is not evidence that a particular run
passed; inspect the run for the exact commit.

For the retained web layer, install the existing lockfile with
`npm ci --ignore-scripts`. `npm run check` includes an archived ARC replay whose
exact Darwin arm64 Node identity is pinned in `scripts/arc-replay-pins.json`.
A different host can pass the ordinary source tests and build while failing
that replay prerequisite. Report it separately; keep the qualification pin.

## Unity and native candidate

The isolated procedural orb acceptance does not need the withheld character
rigs. It still needs the pinned **Unity 6000.5.4f1**, successful project import
and a real graphics device:

```sh
bash script/run_orb_runtime_acceptance.sh
```

Review the generated receipt and captures. This validates the runner's room
scenario, not native UI delivery, installed behavior, stereo or device performance.
See [orb integration](archi-orb-integration.md) for its precise scope.

A full player additionally needs the macOS build module and qualified character
resources. The curated source intentionally omits some required art; installing
the Editor cannot supply those originals. Use the authoring workspace's qualified
assets and preserve applicable Liminal finish/light selections. Do not invent
replacement hashes or disable resource guards to pass a build.

Build a fresh player through the existing helper, then stage the native app with
that exact player. Use new output names:

```sh
bash script/build_unity_port.sh \
  -archiBuildOutput "$PWD/output/unity-port-2026-09-16/ARCHi-Orb-NEW.app"

bash script/build_and_run.sh --stage-only \
  --stage-dir /private/tmp/archi-candidate-NEW \
  --unity-player "$PWD/output/unity-port-2026-09-16/ARCHi-Orb-NEW.app"
```

Add the existing qualified Liminal arguments when the chosen player requires
them. First installation requires a qualified First Signal build and independent
manifest; an update preserves the existing qualified chapter or selected source.
See [First Signal preservation](first-signal-installation-safeguard.md).

`--stage-only` prepares without installing or launching. **`--build-only` still
installs; it suppresses launch only.** The normal installation entry point remains
`script/build_and_run.sh`, with process, source, resource, signature, preservation
and rollback checks. Quit through ARCHi's normal menu before replacement so its
existing owners can finish their cleanup.

The optional Reactor runtime comes from the authoring runtime when present,
otherwise from the installed app. A malformed selected runtime stops packaging;
the absence of both remains optional. No installer path downloads a runtime or
starts a paid session.

## Installed acceptance

Before calling the system fully installed, bind observations to the actual
candidate/source identity and verify normal launch, reopen and Quit; retained
identity and explicit save/load behavior; document and reading outcomes; memory
review/withdrawal; local Arena; and the new orb's selection, tour, pause, resume
and return controls. Include First Signal continuity for the existing installation.
Use disposable data for the initial candidate checks. Observe required real-owner
continuity on the authoring Mac without rewriting profiles or saves as a test.

The static checker deliberately leaves runtime and future spatial/device gates
unverified. It cannot turn source checks into an installed-app acceptance receipt.
