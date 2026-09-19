# Interactive ARC3 in ARCHi

September 18, 2026. This increment connects ARCHi's native task interface to installed public ARC-AGI-3 environments through the official local SDK. It displays actual frames, executes bounded actions, retains outcomes, and checks repeated transition predictions. The explorer is deterministic and uses no language model.

## Use an existing local runtime

The default runtime folder is `~/ARC-AGI-3-Agents`. It must contain `.venv/bin/python` and `environment_files`. **Choose runtime folder…** selects another existing folder with the same layout. This integration does not install packages or download games.

The bridge requires Python 3.12 or later and checks the exact installed versions `arc-agi==0.9.8` and `arcengine==0.9.3`. The exercised local interpreter was Python 3.12.11. Discovery lists metadata for locally provisioned, versioned environments; the available local smoke environment was `ls20-9607627b`. Availability elsewhere depends on that machine's installed files. Starting requires the full versioned ID, so a short name cannot silently select a different version.

The [official ARC-AGI Toolkit API reference](https://github.com/arcprize/ARC-AGI#api-reference) documents `Arcade`, offline operation, environment wrappers, actions, and scorecards. The [official ARC3 documentation](https://docs.arcprize.org/) describes the wider toolkit. ARCHi explicitly selects `OperationMode.OFFLINE`; it does not use the online defaults shown in the general quickstart.

The installed Toolkit and [ARCEngine](https://github.com/arcprize/ARCEngine) package metadata identify ARC Prize Foundation and the MIT license. Their upstream sources remain separately attributed: [Toolkit license](https://github.com/arcprize/ARC-AGI/blob/main/LICENSE) and [engine license](https://github.com/arcprize/ARCEngine/blob/main/LICENSE). ARCHi's bridge is authored here and imports the installed SDK, not the donor's agent or benchmarking harness. Local game source is executed by the SDK and hashed for provenance; it is not supplied to the exploration policy. Environment files and their own provenance remain external runtime assets.

## Controls and assistant commands

1. Open **ARC → Interactive ARC3**, or choose **ARC task → Open interactive ARC3** from Chat, Work together, or the Seed's attached chat.
2. Use **Find local environments**, select an environment, choose a budget, and press **Start environment**. The default budget is 32; the allowed range is 1–64. The SDK's initial RESET consumes one dispatch.
3. Choose a published manual action, or **Explore up to 8 actions**. For Action 6, select a point on the frame or use the column/row controls. SDK coordinates are `x = column`, `y = row`, each from 0–63.
4. Use **Stop & keep record** to end the session. **Show episode record**, **Activity map**, and **Session usage** expose the retained evidence and accounting.

Home exposes the same ARC action menu as the assistant surfaces. An active ARC task bar stays available across the desktop workspace, including while using Memories, Marketplace or other sections. Open task returns to the existing owner; Stop retires it. Navigating creates no duplicate session. The Seed, Chat and Work together share the same result and cancellation lifecycle.

| Assistant input | Behavior |
| --- | --- |
| `/arc3`, `/arc3 open`, or `open arc3` | Open the interactive controls and discover installed environments when needed. |
| `/arc3 explore` or `explore this arc3 environment` | Explore an already started session for up to eight actions, within its remaining budget. |
| `/arc3 stop` | Stop the current operation/session and retain its record. |

An exploration batch chooses the least previously tried legal action for the current visible frame. Ties follow a deterministic order. Action 6 uses a fixed 4×4 grid of points. Each action is checked again against the latest observation. This is a small observation-driven explorer, with no LLM planner or generated-code execution lane.

## Observation, prediction, action, outcome

The native store owns one session and one serialized child transport. The child creates a local scorecard, calls SDK `make()` with seed 0, and captures its implicit RESET observation. The public observation includes the exact game ID, state, completed/winning level counts, available action IDs, and a rectangular frame of color indices 0–15, at most 64×64. The final returned visual frame is shown; the bridge receipt retains all returned frames.

Before each action, ARCHi records the source frame digest, action, coordinates, and any existing predicted next-frame digest. Predictions are indexed by exact game ID, completed-level count, source frame digest, action, and coordinates. The bridge validates the payload, current action availability, terminal state, and remaining budget. It increments its local dispatch count before executing. Native code then validates response identity, frame bounds, SHA-256 digest, game identity, budget, and exactly one dispatch-count increment before accepting the outcome.

| Verdict | Meaning in this implementation |
| --- | --- |
| `observed` | A valid transition was retained without a prior prediction for that exact key. |
| `supported` | A prior prediction for that key matched the returned final-frame digest. |
| `refuted` | The returned digest differed. The prediction is removed, and earlier transitions with the same key are marked invalidated. |
| `inconclusive` | RESET, a level transition, or a terminal result prevents applying the ordinary same-level comparison. |

RESET and level transitions clear the prediction/visit caches. A refuted expectation stops influencing subsequent prediction checks; retained history is not deleted. Identical visible pixels can conceal different environment state, so even `supported` applies only to this observation/action comparison. It is not a universal rule, a hidden-state proof, or a completed implementation of general dependency invalidation. The Activity map is a read-only view of the current episode and recent transitions.

## Local API and records

[ARC3Runtime.swift](../desktop/Sources/ARCHiDesktop/ARC3Runtime.swift) launches the [bundled Python bridge](../desktop/Sources/ARCHiDesktop/Resources/ARC3Bridge/archi_arc3_bridge.py) with `-I -B`, `--environments-dir`, and `--recordings-dir`. Newline-delimited JSON travels over stdin/stdout. There is no local HTTP server. SDK incidental stdout is redirected away from the protocol.

| Command | Required request fields beyond string `id` and `command` |
| --- | --- |
| `discover` | None; returns local `games` with `id` and `title`. |
| `start` | `gameID`, integer `budget` from 1–64. Rejects a second start while active. |
| `step` | Integer `action`; Action 6 also requires integer `x` and `y`. Optional `gameID` must match. RESET is action 0 and must be explicit. |
| `close` | None; finalizes the local scorecard and receipt when possible. |

Responses contain `id`, `ok`, and either typed `error` or applicable `games`, `observation`, and `receiptPath` fields. The frame digest is lowercase SHA-256 of the final two-dimensional frame encoded as compact JSON. The bridge rejects booleans/coerced numbers as action parameters and bounds each request line to 64 KiB. SDK startup has a 45-second bound; individual bridge requests have a 10-second bound, with separately bounded cleanup.

The native [session store](../desktop/Sources/ARCHiDesktop/ARC3SessionStore.swift) writes `ARC3Episodes/<session UUID>/native-episode.json` alongside the active profile's storage. It retains initial/latest observations, predictions, transitions, action attempts, outcome, and the bridge receipt reference. The bridge adds its own `session-<UUID>/receipt.json` plus SDK recordings beneath that episode directory. Its receipt includes SDK versions, seed, source-environment file digests, bridge digest, actual observations, dispatch attempts, errors, and local scorecard data. These are local integrity records, not independent attestations.

Usage records distinguish confirmed observations, requested attempts, and unreconciled requests. Native requested attempts can include work cancelled before the bridge dispatches; bridge dispatch attempts and SDK scorecard counts are separate quantities. Session completion does not mean the game was won: retain the explicit final state (`WIN` or `GAME_OVER`) and the recorded outcome (`complete`, `budget-exhausted`, `stopped`, `failed`, or `profile-reset`). No provider cost or token usage is invented for this model-free route.

## Privacy, stopping, and limits of the evidence

The launcher constructs a fresh environment and puts the child's home/temp directories inside its episode folder. The bridge retains only a small environment-variable allowlist, disables dotenv before SDK import, forces offline mode, and guards outbound HTTP/socket/DNS operations. No provider keys are passed, no model is called, and no online scorecard is submitted. The guard is an accidental-networking safeguard, not an adversarial operating-system sandbox; installed environment Python remains trusted code.

Stop, replacement work, source/context invalidation, profile reset, and shutdown retire the current native owner before cancellation. Late results cannot become a replacement session's observation. An in-flight request without a validated response becomes `unreconciled`; it is not automatically retried and no rollback is claimed. The bridge attempts scorecard cleanup on EOF or termination, but a forced stop cannot guarantee a final SDK scorecard. The native record preserves that distinction. Normal terminal/budget completion requests a clean close.

This increment establishes a local interactive execution path and narrowly scoped transition evidence. It does not establish ARC Prize performance, frontier-model performance, complete Q2E/Hampton validation, persistent trusted skill learning, or companion/Seed growth. The earlier grid-solving and optional Qwen proposal paths retain their separate contracts in [ARC as an active capability](active-arc-assistant.md). Focused bridge tests and a bounded public-game smoke are mechanism evidence; native acceptance and release readiness require their own current receipts.
