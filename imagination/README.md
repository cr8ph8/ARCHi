# ARCHi advisory imagination pilot

This is the initial repository integration of a CPU-only Sokoban proposal reviewer. It accepts candidate actions and predicted boards, checks their consequences in a bounded deterministic simulator, and returns an advisory disposition. The included demonstration uses handwritten synthetic predictions.

The integration implements a provider contract and a review boundary inspired by [Agima, *Train an Imaginative Agent*](https://arxiv.org/abs/2610.26845v1). It does not contain Agima/BAGEL weights, neural image generation, supervised training, reinforcement learning, or a native app installation. Synthetic demonstrations establish behavior of this implementation; they do not measure learned planning quality or reproduce the paper's benchmarks.

## Run from the repository root

Use the repository's Node.js 24 and npm environment with its existing dependencies installed.

```bash
npm run imagination:demo
npm run imagination:agima
npm run imagination:test
npm run imagination:typecheck
npm run imagination:check
```

`imagination:demo` runs the synthetic suite. `imagination:agima` reports that the neural provider is unavailable; it does not download assets or substitute a fixture provider. `imagination:check` runs the focused checks configured in [package.json](../package.json). These commands do not install or launch the native app or Unity.

See [the dated validation receipt](VALIDATION.md) for executed checks and the
existing aggregate-check runtime mismatch. The availability command exits with
code 2 because no neural backend is configured. Imported reviews also exit with
code 2 when rejected, stale, unavailable or escalated; malformed CLI/file input
exits with code 1. `npm run --silent imagination:demo` emits JSON without npm's
command banner.

To review caller-supplied JSON files:

```bash
npm run imagination:review -- \
  --request request.json \
  --response response.json \
  --current current.json \
  --now-ms 1000
```

The filenames above are inputs prepared by the caller. Use an explicit time consistent with the request's lifetime. This command reviews imported data; it does not establish that the data came from a model, an authenticated owner, or the current application state.

## Data flow and ownership

The public types and functions are in [src/planner.ts](src/planner.ts). The closed board model is in [src/sokoban.ts](src/sokoban.ts).

1. The host supplies an observation, revision, authorization epoch, policy version, request lifetime, and work budget to `createImaginationRequest`.
2. The function validates and copies the observation, freezes the accepted data, and computes a SHA-256 digest over a canonical request. The response must echo that digest.
3. A provider returns candidate action sequences, one predicted board per action, and its predicted success flag. Provider identity is supplied by the host adapter; it is not accepted from response content.
4. `evaluateImagination` independently simulates each candidate in the closed board model and compares every visited board and final success flag with the predictions.
5. The result presents a selected proposal, a reduced proposal, or reasons to reject or escalate. All results carry `actionWritable: false`, `memoryWritable: false`, and `permissionGrant: false`.

An accepted response has schema `archi-imagination-candidates/v1` and exactly `schema`, `requestDigest`, and `candidates` fields. Each candidate has exactly `id`, `actions`, `predictedStates`, and `predictedSuccess`. The request and current-context shapes are defined by `ImaginationRequest` and `CurrentContext`; use `createImaginationRequest` to construct the bound request rather than manufacturing its digest.

The native owners described in [CONTRIBUTING.md](../CONTRIBUTING.md) retain assistance, permissions, memory, and saved development. This module receives no native dispatcher, profile store, memory writer, or external-action capability. It introduces no alternate profile or permission database.

### Freshness across asynchronous work

`proposeImagination` checks the current context before provider generation and again after the asynchronous result arrives. The host must supply `readCurrent` from its actual state owner. Changed board contents, revision, authorization epoch, policy version, or request lifetime prevent acceptance. The wrapper also handles cancellation and timeout, and aborts its provider signal when finished.

The wrapper samples time after owner reads, rejects backwards clock movement, and
rechecks elapsed time before accepting a result even if the timer callback has
not yet run. Results without candidate evaluation use `evidenceClass: "not-evaluated"`.

Revisions and authorization epochs are caller-owned values. The wrapper compares them; it does not issue them, enforce their monotonicity, or authenticate the caller. A SHA-256 digest binds data and is not a signature or permission grant. A host that restores an old epoch or supplies a stale `readCurrent` callback defeats its own freshness assumptions. Any later action still needs the existing owner's admission checks at execution time.

The provider is trusted host code, not arbitrary JavaScript received from a response. The wrapper is not an in-process sandbox, and an abort signal cannot forcibly stop a provider that ignores cancellation. Imported candidate responses are treated as bounded data.

## Advisory outcomes

| Disposition | Meaning |
| --- | --- |
| `PROPOSE` | A selected legal candidate has matching predictions and reaches the goal in this simulator. Its actions are available for review. |
| `DAMP` | A selected legal candidate has matching predictions but does not reach the goal. Only its first action is offered; another step needs fresh observation and review. |
| `REJECT` | The request/response is invalid or stale, generation was cancelled or timed out, or all assessed candidates violate the simulator's rules or detected corner condition. Inspect `status` and `issues`. |
| `ESCALATE` | The requested provider is unavailable, or legal simulated candidates disagree with their predictions and none is eligible for selection. |

There is no `COMMIT` outcome. `simulatedSuccess` reports the result of the closed simulator, not real execution. Results retain imagined and simulated boards separately. A malformed candidate invalidates the response rather than silently disappearing from the review.

Among eligible candidates, solved plans rank first and shorter plans rank next; equal ranks preserve input order. Prediction agreement is required, and provider confidence is not used as authorization.

## Bounds and simulator scope

- Requests allow at most 8 candidates, 8 actions per candidate, and 64 proposed transitions in total. Request lifetime is at most five minutes.
- Candidate response text is limited to 65,536 UTF-8 bytes. Duplicate JSON keys, unexpected fields, invalid actions, duplicate candidate IDs, and missing predicted boards are rejected.
- The async wrapper defaults to a five-second timeout and permits at most 30 seconds. A timeout limits waiting; it does not create a hard CPU sandbox around host code.
- Boards are rectangular, 3–12 cells on each side, enclosed by walls, and contain one player and 1–4 boxes with matching goal counts. Actions are `UP`, `DOWN`, `LEFT`, and `RIGHT`.
- Board characters use ordinary Sokoban notation: `#` wall, space floor, `.` goal, `$` box, `@` player, `*` box on goal, and `+` player on goal.

The simulator provides single-box pushes and no pulling. Blocked moves are illegal and preserve board contents. Solved boards are terminal. Its deadlock check detects only non-goal boxes trapped in wall corners. **The absence of a detected corner does not prove that a board remains solvable.** Wall traps, interacting box groups, and longer-horizon impossibility can remain undetected.

The synthetic suite has no statistical claim about unseen tasks, neural accuracy, world-model calibration, general agency, or physical safety. The handwritten predictions and this small simulator do not implement the paper's image-model training or its evaluation protocol. They provide a controlled place to test the separation between hypotheses and state admission.

## Upstream provenance and future neural provider

[upstream-reference.json](upstream-reference.json) records reference-only source and artifact pins. The upstream source commit was resolved through the public GitHub API. Referenced model weights and datasets are marked `not-downloaded`; published checksums, where recorded, have not been checked against local artifact bytes. No upstream runtime code or model asset is bundled here.

The inspected upstream source is [Agima commit 9d3878e](https://github.com/Agentic-Imagination/Agima/tree/9d3878edf8a72498519f9f92cac28d570a3e1a43). Its [installation contract](https://github.com/Agentic-Imagination/Agima/blob/9d3878edf8a72498519f9f92cac28d570a3e1a43/docs/installation.md) requires a Linux/CUDA model environment. Its [evaluation guide](https://github.com/Agentic-Imagination/Agima/blob/9d3878edf8a72498519f9f92cac28d570a3e1a43/docs/evaluation.md) requires compatible base assets, task weights, episode pool, decoder, preprocessing, and success criteria. The referenced Sokoban CoT K=5 checkpoint uses `perseg` decoding. Changing a flag does not convert a checkpoint to another protocol.

A real neural adapter still needs:

1. A separately provisioned CUDA environment and verified, pinned model assets. This pilot performs no large weight or dataset downloads.
2. An explicit transformation from model output into the bounded response schema, with the host recording the actual provider and model revision.
3. Isolation and cancellation appropriate for the inference process, followed by fresh owner context when reviewing its output.
4. An executed model evaluation with exact source, asset and episode identities, complete denominators, and measured outputs. A dry run, fixture result, or successful import is insufficient.

Unavailable neural inference must remain visible as `unavailable`/`ESCALATE`; it must not silently run the synthetic provider. Connecting this advisory module to a native owner, installing an app, training a model, and reproducing an upstream benchmark are distinct work items with separate evidence.

For source promotion, follow [source ownership](../docs/source-ownership.md) and refresh the repository source manifest after the complete reviewed change. Test results should be reported from the actual run; this document intentionally carries no fixed passing-test count.
