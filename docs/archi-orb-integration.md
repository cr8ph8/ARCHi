# ARCHi Orb integration

This optional orb presentation uses the existing ARCHi desktop and Unity connection. The spatial particle update is based on `45cb514866ed8e3d8ee288e09eb10b0adfaebde9`, including the First Signal installation safeguard. Reconcile accepted changes into the current authoring owners before delivery. This remains a source candidate; the installed application has not been replaced.

## Existing owners and reused code

| Responsibility | Owner reused by this build |
| --- | --- |
| Assistant/model choice, question submission, reviewed dictation | `CompanionStore`, `AssistantRouting`, `VoiceInputController` |
| Identity, saved appearance, memory and development | Existing native profile/preference, reading and development owners |
| Native-to-Unity publication, ACKs, cancellation and current revision | `UnityPresentationConnection`, `NativePresentationSnapshot`, `NativeEvolutionBridge` |
| Native memory navigation and exact source inspection | Existing memory workspace and particle selection paths |
| Actual QiMon chapter | `QiMonEmbeddedGame.shared`; the existing card still selects its separate game build |
| Arena and observed practice outcomes | Existing `ArenaWorkspace`, `ArenaRehearsal` and `WorldOutcome` paths |
| SIGGRAPH-origin Broken Relay | Existing `broken-relay.ts`, Journey admission and `RelayPractice.cs`; no duplicate game owner |
| Bloom | Existing `ArenaBloom`, used by the desktop orb camera |

The complete SIGGRAPH authoring tree and separately authored QiMon gameplay source were not present in this checkout. This build reuses their verified existing integration surfaces. The KIN/Relay preview is not relabeled as the full QiMon game. Opening a chapter does not read or import its save into a second database.

## What is implemented

- `OrbBody` builds a luminous core, 720 deterministic particle samples and four segmented, independently rotating rings without new artwork dependencies. The same body is used by desktop and spatial presenters.
- `OrbRoomTheme` implements one set of procedural studio, lantern/fantasy, voxel and neon room materials shared by desktop and spatial presenters. Changes reveal radially across room surfaces.
- `OrbRoomStage` renders a desktop room through the existing Unity UI. `OrbSpatialPresenter` places the same orb beside a tracked camera and binds overlays to a host-supplied room mesh. Studio mode restores passthrough surfaces. It does not scan a room by itself.
- Native activity drives idle/thinking/reply-arriving/error states. Dictation drives listening. Native `AVSpeechSynthesizer` start/finish/cancel callbacks drive speaking; final text arrival does not end speaking prematurely. Completed-reply playback is explicit and defaults off.
- Closed local commands such as `make this room voxel`, `make this room fantasy`, `make this room neon`, `show memories`, `open QiMon`, `follow me` and `pause orb` use the existing native Send path. Unknown questions continue through current assistant routing. Dictation remains review-before-Send.
- Renderer requests carry the current identity/session/revision, timestamp and monotonic sequence. Native checks them against current acknowledged presentation before invoking existing operations. A transport response means delivered, not accepted game progress or completed action.
- `scripts/orb-session-bridge.mjs` carries that same file protocol to a paired external renderer over HTTPS. It exposes only presentation, ACK and closed action routes, never arbitrary files. TLS certificate pinning and an ephemeral bearer token are required. The bridge owns no identity, model, memory or game save.

## Particle body and local exploration

In the existing desktop orb room, select the desk, reading shelf, lamp or window by clicking its visible bounds or using its named button. The orb highlights the object and travels to its registered approach point. **Explore room** visits the reachable objects once, dwells at each, then returns home. **Return home** cancels the tour and selection; **Clear selection** stops the route at its current location. Escape retains the existing Pause motion behavior. The object buttons are keyboard accessible and retain stable focus names across native presentation updates.

The simulation has three distinct responsibilities:

| Responsibility | Implementation and boundary |
| --- | --- |
| Where the orb can move | `OrbRoomNavigation` uses a bounded room-local 3D grid, conservative sphere clearance, line-of-sight smoothing and swept segment checks. A `.64` radius includes the outer rings. Movement uses fixed 120 Hz steps with a maximum eight-step catch-up; a paused or hidden period never becomes a movement backlog. |
| Which object is selected | `OrbRoomTarget` describes an explicitly registered object, its display bounds and its separate approach point. `OrbTargetRef` binds space ID, scene revision, object ID and generation. Invalid references leave the current intent unchanged. Scene replacement, session change and native Stop retire selection and routes. |
| How attention looks | `OrbParticleBody` uses one mesh and one material. During selection, 576 samples remain in the core, 48 form a bounded visual stream and 96 mark the target's local bounding-box edges. The stream and contour are visual cues; the orb center remains the collision owner. |

The particle mesh is generated once; animation happens in `OrbParticles.shader`. The clock, reach and billboard size are bounded. Target coordinates are transformed into the orb's local frame, including the desktop stage's isolated `y = -100` offset. Culling bounds include the body, stream, contour and billboard extent. Missing, disabled or invalid targets clear their highlight. Runtime mesh and material ownership ends with the body.

Navigation scene data are copied at admission and remain immutable during a route. Geometry changes create a new local scene revision and clear existing intent. A bounded in-memory per-space revision fence prevents references from reviving after leaving and reentering a space. An unsupported geometry change fails closed with an unavailable status. Only the known renderers are registered; the room does not recognize unseen objects or inspect the operating system. Picking uses the actual centered `ScaleToFit` image rectangle and refuses an object hidden by a nearer opaque room surface.

Ordinary native replies, activity changes and themes preserve the current center and route. An explicit world/follow anchor change rebuilds the local home placement. Pause, Quiet and Reduce Motion stop both navigation and particle clocks while retaining a static selection. Selecting an object during those modes updates its static highlight; navigation waits until motion is permitted. Session expiry, hidden/inactive presentation and explicit native Stop cancel local intent. No selection, tour or visual particle writes memory, awards development, calls a model or changes a game save.

This implements the registered 3D room adapter and shared particle body. `OrbSpatialPresenter` receives the new body through `OrbBody`, but keeps its existing head-follow/world-anchor behavior. A future desktop, game or headset navigation adapter must supply its own coordinate frame, current object registry, bounds, obstacles and valid approach points. Semantic vectors, pixels and physical room coordinates are not interchangeable without that adapter; this update does not add physical object detection, OS-wide exploration or automatic room scanning.

## Desktop candidate

Use the existing Unity 6000.5.4f1 Built-in project and normal authoring/build workflow. No render-pipeline or package migration is included.

1. Run the isolated room acceptance below, then the existing Unity preparation/validation and build helper (`script/build_unity_port.sh`). Orb protocol and room-navigation checks are part of `ARCHiPortBuild` validation, along with import/support checks for all three orb shaders. The helper advertises `ARCHiOrbPresentationVersion = 1` in the Mac player bundle; this local interaction update does not change the bridge schema.
2. Run native focused tests, then stage the native candidate through the existing `script/build_and_run.sh --stage-only --stage-dir <new-directory> --unity-player <exact-new-player.app>` workflow. Supplying the exact player prevents an older installed helper from standing in for this change. Preserve the installed app and its normal Quit/rollback rules.
3. In Arena, the ARCHi Orb card opens the new view. Old helpers remain usable for their existing features but do not falsely advertise an orb.
4. Select a room object, run one exploration tour, return home and verify Pause/Resume before changing themes. Use existing Ask ARCHi dictation and optionally read completed replies. Quiet, Reduce Motion, Stop, profile change and shutdown retain their native behavior.

This candidate has not been built or installed on the authoring Mac. Source tests are not installation or visible acceptance.

## Isolated Unity runtime acceptance

The opt-in `OrbRoomRuntimeValidation` runner exercises the real `OrbRoomStage`, `OrbBody` and `OrbParticleBody` in an empty Play Mode scene. It uses a synthetic session and the procedural room, so it does not require the withheld Proto or Liminal artwork. The whole Unity project must still import and compile successfully. It does not create the native bridge, load a profile or invoke the desktop app.

On the machine with the pinned Unity **6000.5.4f1** Editor and a working graphics device, run from the reconciled authoring source:

```sh
bash script/run_orb_runtime_acceptance.sh
```

The launcher writes each run to a fresh directory beneath `output/orb-runtime-acceptance/`, with an adjacent Editor log. `--editor /absolute/path/to/Unity` selects another installed copy of the pinned version; `--output /absolute/new/run-directory` selects a fresh evidence directory. It does not download Unity. It refuses existing output and source-directory destinations, propagates an unsuccessful Editor exit, and requires a passing `acceptance.json` even if Unity exits with status zero. A ten-minute external timeout also covers failures before the runner starts.

The Editor menu entry **ARCHi / Orb / Validate Room Runtime** runs the same fixture. Preserve unsaved scenes before using the menu: the runner refuses to discard or save them. It temporarily clears any Play Mode start-scene override, uses an empty scene, and restores the prior scene setup and Editor settings after normal completion or handled failure. Use the launcher for unattended runs and keep graphics enabled; `-quit` would interrupt the asynchronous run and `-nographics` cannot qualify rendering.

The runner produces an `archi-orb-room-runtime-acceptance/v1` receipt and frame captures. Its checks cover:

- Shader support and diagnostics, room texture creation and the actual particle mesh/material.
- RGB frame differences with the particle renderer enabled and disabled at a frozen pose, so an opaque room alone cannot satisfy the rendering check.
- The four registered targets, target approach and attention, room-local movement clearance, and programmatic viewport picking.
- Theme/activity updates retaining position and navigation, pause holding the body and shader clock, and one exploration tour ending at home.
- Invalidated targets, stale references, changed sessions and stopped presentation clearing local attention.
- Repeated creation/destruction with real frame yields and release of the owned mesh, materials and render texture.

These are programmatic room-renderer checks. Pointer/keyboard delivery through the real UI, native Stop/expiry delivery, app speech, visual quality and target-device performance still need the built app. Screenshot readback establishes a rendered image; it does not establish a performance budget or acceptable art direction. A receipt records only the machine and source exercised by that run.

After a passing receipt and image review, build a new player into the build helper's evidence directory, then stage the native candidate with that exact player:

```sh
bash script/build_unity_port.sh \
  -archiBuildOutput "$PWD/output/unity-port-2026-09-16/ARCHi-Orb-NEW.app"

bash script/build_and_run.sh --stage-only \
  --stage-dir /private/tmp/archi-orb-review-NEW \
  --unity-player "$PWD/output/unity-port-2026-09-16/ARCHi-Orb-NEW.app"
```

Replace both `NEW` destinations with fresh paths and retain the applicable existing resource-qualification arguments from the authoring workflow. Full player/native builds still require their qualified artwork and resources. `--stage-only` creates a review candidate without installing or launching it; `--build-only` is not a substitute because that path still installs. Follow [First Signal installation safeguards](first-signal-installation-safeguard.md) and inspect the candidate's resource and build-identity receipts before app acceptance.

The runner and launcher were authored in the Linux source workspace. The launch attempt there stops because the pinned Editor is absent; no real Unity acceptance receipt or capture is claimed. Run the command above in the Unity environment to obtain that evidence.

## Headset development connection

This is an explicit developer setup, not a shipped automatic pairing interface.

1. Supply an XR camera rig, passthrough and room geometry using the actual target platform SDK (for example Meta MRUK). Keep this desktop project's Built-in shader compatibility or deliberately port and verify its three shaders for another pipeline.
2. Add `OrbSpatialPresenter` and `OrbRemoteConnection` to a renderer-owned object. Assign the tracked camera/head. If using MRUK, assign a dedicated EffectMesh root to `roomSurfaceRoot`; the presenter copies its meshes into visual overlays and leaves the room geometry/collision owner unchanged. Late-created mesh surfaces are detected once per second. No colliders are added. Room anchors remain SDK-owned and session placement is not a cross-launch persistent anchor.
3. In native ARCHi's orb card, expand Headset setup and choose Prepare headset session. Copy the current session file path. This starts the same native publisher without a desktop rendering process.
4. From this source checkout, start the transport with the copied path and a new private pairing-file destination:

```sh
node scripts/orb-session-bridge.mjs \
  --snapshot /private/current-session/presentation.json \
  --host 0.0.0.0 \
  --pairing-file /private/tmp/archi-orb-pairing.json
```

The default host is loopback; LAN exposure requires the explicit host option. Node and the local OpenSSL executable are development prerequisites. The command prints the pairing file path, not the token. The file is created exclusively with mode 0600. Keep it outside the repository.

5. The headset host's temporary pairing UI/QR adapter calls:

```csharp
connection.Connect("https://<Mac-LAN-address>:<port>",
    certificateSHA256, token, sessionID);
```

The values come from that private pairing file. They are runtime parameters, not serialized scene/prefab credentials. Pin the exact certificate; the client does not accept all certificates. Use the host's own gesture/raycast/UI controls to call `RequestAction("theme", "voxel")`, `RequestAction("anchor", "world")`, or native navigation actions. `SetWorldAnchor` accepts the host's explicit placement result.

6. Use the target's normal microphone/voice integration only through an explicit input adapter. This slice retains native Mac dictation; headset microphone capture, a finished pairing UI, SDK installation, controller/hand action bindings and a packaged Quest APK are not supplied.
7. Stop the native session to revoke its projection. Expired/inactive/replaced sessions are refused; the spatial renderer freezes the orb and removes room overlays. Disconnect clears the client's runtime token. Stop the transport process when finished.

The source client uses the authenticated server clock to compare native timestamps across devices, then a local monotonic heartbeat to stop on connection loss. A request is never automatically retried after ambiguous delivery. An Arena navigation request switches to the existing desktop Arena; this does not claim a headset port of the complete QiMon game.

## Validation and remaining acceptance

Executed for the spatial particle update in the Linux code workspace:

- 37 existing C# orb boundary/expression checks and 64 room-navigation/viewport checks pass against the actual runtime and Editor-check source. The room fixture includes all furniture obstacles, both home placements, every object approach, swept collision checks, one complete tour and return. Freshness checks cover reused IDs, scene replacement and leaving/reentering a space. A test JSON adapter substitutes for Unity serialization.
- Actual pure orb/navigation runtime compiles as C# 9 against .NET Standard 2.1 references with warnings treated as errors.
- A separate temporary Unity/UI adapter compile checks the source integration of the body, particles, theme, stage and room controls. This is a syntax check, not a compile against Unity assemblies or a rendering test.
- All 10 existing HTTPS transport tests pass, including session expiry, duplicate delivery, certificate pinning and closed action routes.
- The runtime-acceptance launcher passes eight isolated command/receipt checks, including missing Editor, existing output, source-directory output, unsuccessful process status, and missing/failed receipts. The subprocess fixture is synthetic; it does not stand in for Unity rendering. All 25 existing source-export preflight tests pass with the launcher added to the explicit export scope.

The preceding orb integration also recorded 79 retained Relay/Journey/battle/presence tests and the TypeScript/PWA production build. Those earlier results do not establish this update's visible Unity behavior. The existing Actions workflow reruns its protocol, transport, TypeScript and native subsets on a pull request.

Reproduce the checks:

```sh
python3 scripts/check_orb_protocol.py --dotnet /path/to/dotnet
node --test scripts/orb-session-bridge.test.mjs
npx vitest run src/companion-activities/broken-relay.test.ts src/journey-activity.test.ts src/battle-engine.test.ts src/presence-sequence.test.ts
npm run build
swift test --package-path desktop --filter OrbPresentationTests
swift test --package-path desktop --filter UnityPresentationTests
```

Native tests are authored for the macOS owner boundary. Unity shader/API compilation, Play Mode, actual macOS speech playback, room scanning, stereo rendering, tracking loss, recentering, on-device frame time and an installed end-to-end workflow still require their real environments. No headset performance, native build or full-game integration result is inferred from protocol tests. The optional Actions workflow runs protocol and native focused checks; a passing run must be verified separately.

For the particle update's visible acceptance, verify all four named objects through both pointer and keyboard controls; no selection through walls or UI letterbox gutters; the complete orb and rings clearing furniture; one tour returning home; theme/reply updates preserving movement; Pause/Quiet/Reduce Motion preserving a static frame; target removal and session loss clearing highlights; and resource cleanup on repeated open/close. Test the built player and tracked-camera host separately, including stereo and target-device frame time where applicable.

No state is unified by copying every store into a new one. The native companion remains its existing individual; the game keeps its own rules and saves; the orb and room are versioned presentations of those owners.
