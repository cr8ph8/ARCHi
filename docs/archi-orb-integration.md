# ARCHi Orb integration

This change adds an optional orb presentation to the existing ARCHi desktop and Unity connection. It is a source candidate against desktop review `c4cc639684dd520469930232f49dfc11af626547`. Reconcile it into the current authoring owners before delivery. It does not replace the installed application.

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

- `OrbBody` builds the luminous core and four segmented, independently rotating rings without new artwork dependencies.
- `OrbRoomTheme` implements one set of procedural studio, lantern/fantasy, voxel and neon room materials shared by desktop and spatial presenters. Changes reveal radially across room surfaces.
- `OrbRoomStage` renders a desktop room through the existing Unity UI. `OrbSpatialPresenter` places the same orb beside a tracked camera and binds overlays to a host-supplied room mesh. Studio mode restores passthrough surfaces. It does not scan a room by itself.
- Native activity drives idle/thinking/reply-arriving/error states. Dictation drives listening. Native `AVSpeechSynthesizer` start/finish/cancel callbacks drive speaking; final text arrival does not end speaking prematurely. Completed-reply playback is explicit and defaults off.
- Closed local commands such as `make this room voxel`, `make this room fantasy`, `make this room neon`, `show memories`, `open QiMon`, `follow me` and `pause orb` use the existing native Send path. Unknown questions continue through current assistant routing. Dictation remains review-before-Send.
- Renderer requests carry the current identity/session/revision, timestamp and monotonic sequence. Native checks them against current acknowledged presentation before invoking existing operations. A transport response means delivered, not accepted game progress or completed action.
- `scripts/orb-session-bridge.mjs` carries that same file protocol to a paired external renderer over HTTPS. It exposes only presentation, ACK and closed action routes, never arbitrary files. TLS certificate pinning and an ephemeral bearer token are required. The bridge owns no identity, model, memory or game save.

## Desktop candidate

Use the existing Unity 6000.5.4f1 Built-in project and normal authoring/build workflow. No render-pipeline or package migration is included.

1. Run the existing Unity preparation/validation and build helper (`script/build_unity_port.sh`). Orb checks are part of `ARCHiPortBuild` validation. The helper advertises `ARCHiOrbPresentationVersion = 1` in the Mac player bundle.
2. Run native focused tests, then stage the native candidate through the existing `script/build_and_run.sh --stage-only --stage-dir <new-directory>` workflow. Preserve the installed app and its normal Quit/rollback rules.
3. In Arena, the ARCHi Orb card opens the new view. Old helpers remain usable for their existing features but do not falsely advertise an orb.
4. Choose a theme, use existing Ask ARCHi dictation, and optionally read completed replies. Quiet, Reduce Motion, Stop, profile change and shutdown retain their native behavior.

This candidate has not been built or installed on the authoring Mac. Source tests are not installation or visible acceptance.

## Headset development connection

This is an explicit developer setup, not a shipped automatic pairing interface.

1. Supply an XR camera rig, passthrough and room geometry using the actual target platform SDK (for example Meta MRUK). Keep this desktop project's Built-in shader compatibility or deliberately port and verify its two shaders for another pipeline.
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

Executed in the Linux code workspace:

- 37 C# orb boundary/expression checks compiled against the actual `OrbPresentation`, `NativePresentationSnapshot` and `OrbPresentationChecks` source. A clearly separated test JSON adapter substitutes for Unity serialization; this does not compile shaders or Unity rendering APIs.
- 10 HTTPS transport tests cover certificate pins, pairing, exact projection delivery, duplicate/concurrent action requests, closed commands, stale/retired sessions, bounded input, symlink refusal and route scope.
- 79 existing SIGGRAPH Relay, Journey activity, battle and presence tests passed.
- Existing TypeScript/PWA production build passed.

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

No state is unified by copying every store into a new one. The native companion remains its existing individual; the game keeps its own rules and saves; the orb and room are versioned presentations of those owners.
