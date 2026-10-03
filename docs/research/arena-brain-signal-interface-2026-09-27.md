# Arena brain-signal interface — 27 September 2026

Patrick requested optional brain-signal-driven colors and a distinctive battle
experience, with comparisons among ARCHi–ARCHi, human–human and hybrid play.
He confirmed **no device yet; prepare the interface**. This is a product direction,
not evidence that EEG changes battle performance or reveals a person's emotions.

## Delivered in source

The existing native Arena practice page includes a collapsed **Brain-signal
colors · preview** panel. Manual sample and quality sliders exercise an ephemeral
mapping over the current companion portrait. No device, Bluetooth scan, server,
account or model is started. Saved colors, identity, lessons, permissions and
gameplay are untouched. Changing profiles or leaving the view resets the preview.

`ArenaBiosignalSource` is a device-neutral asynchronous input port. A future
adapter must supply session/participant IDs, sequence, acquisition time translated
to the host monotonic clock, origin (preview/recorded/live), calibration identity,
feature identity, dimensionless feature fraction, quality and artifact flag.
Actual adapters must document channels, window, filters, units, clock conversion,
feature computation, dropout behavior and calibration provenance separately.
This port alone neither computes EEG features nor authenticates a device.

`ArenaBiosignalSession` rejects incorrect owners, origin, calibration or feature;
nonfinite/out-of-range input; artifacts; quality below the chosen 0.8 presentation
threshold; duplicate/reordered input; future input; and input older than two
seconds. Unavailable
current-stream input restores neutral; foreign session/participant input is ignored
without clearing the current expression. Stop retires a session permanently, and
reset creates a new session identity so delayed frames cannot reactivate it.
These defaults are engineering policies, not clinical cutoffs. Unavailable
input restores neutral offsets. The live consumer must reevaluate freshness on
its render clock. The manual preview explicitly holds its simulated clock for
review and cannot be exported as live evidence.

For a calibrated feature fraction x and low/high bounds a < b:

```
u = clamp((x - a) / (b - a), 0, 1)
s[t] = s[t-1] + (1 - exp(-dt / 1 second)) * (u - s[t-1])
hue offset = 12 degrees * (2*s - 1)
brightness offset = 0.06 * (2*s - 1)
```

The initial state is neutral (s = 0.5). Each update caps dt at one second.
Reduce Motion, Quiet or hidden presentation returns neutral. There is no rhythmic
flashing or mapping from EEG frequency to visible flash frequency. The limits and
palette are artistic choices. No alpha = calm, beta = intelligence or similar
unvalidated state labels are assigned.

## Primary-source implementation references

- [BrainFlow supported boards](https://brainflow.readthedocs.io/en/stable/SupportedBoards.html)
  documents multiple device families, explicit synthetic sources and playback
  boards. This supports a common adapter surface while keeping source origin
  visible. Playback may regenerate timestamps, so an adapter must retain the
  recorded origin regardless of timestamp appearance.
- [BrainFlow examples](https://brainflow.readthedocs.io/en/stable/Examples.html)
  provide signal processing and band-power examples. Their availability does not
  qualify a feature as emotion, intent or capability. No library/code was copied.
- [Lab Streaming Layer](https://labstreaminglayer.readthedocs.io/info/intro.html)
  addresses synchronized measurement streams and metadata. Consider it at the
  adapter boundary if chosen hardware supports it; it does not authorize game
  actions or establish outcome causality.

No hardware or SDK dependency was installed. Choose the device before qualifying
channels, contact/artifact checks, per-person calibration and native capture.
Raw recordings remain local and opt-in in a future adapter, separate from graph
memories, public replays, model prompts and investor-facing evidence.

## Battle ownership and attribution

| Comparison | Required controller record |
|---|---|
| ARCHi–ARCHi | Both seats explicitly automated, each controller/version/budget recorded |
| Human–human | Both seats human; assistance disabled and input availability recorded |
| Hybrid | Record each seat separately: human, ARCHi or human + ARCHi; log whether suggestions or shared control are used |

An EEG visual effect does not make a seat hybrid. The current scripted RivalChoice
opponent is not a model-controlled ARCHi and must not be labeled as one. Existing
multiplayer commands already pass the authenticated-seat and match/round/revision
checks in `ArenaMultiplayerSession.Submit`. A future explicit EEG command adapter
must enter that route, never write the match state from the renderer.

Current WorldOutcome v1/ ArenaPracticeReport summarize explicit solo practice.
They must not be reused as evidence of paired or hybrid performance. A later
comparison receipt needs match ID, rules/asset/controller versions, map/seed,
seat roles and side assignment, assistance mode, input origin/calibration,
accepted/rejected actions, dropout periods, outcome and resource cost.

To estimate a difference, preselect a primary outcome, use matched scenarios and
counterbalanced sides/order, preserve failures and dropout, and distinguish
participant/match-level replication from repeated frames. Compare visual-only
EEG with a neutral palette separately from EEG control. Report uncertainty and
possible no-effect outcomes. No experiment or superiority claim is made here.

## Remaining integration

- Hardware adapter and real feature/calibration qualification.
- Optional accepted expression descriptor shared by native and Unity. The current
  manual panel is a native preview only, not a live battle effect.
- Explicit controller roster and paired/hybrid receipts within existing Arena
  owners, then user-authorized comparisons.
- Broader profile, motion and accessibility review. The installed manual preview
  was opened, its quality reduced to 50%, and its neutral-return message observed,
  then reset. No real sensor or Unity signal effect was exercised. The real v008
  source package and its installed walkthrough remain delivery requirements.
