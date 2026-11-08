# Representations and local peer observations

This change adds a local foundation for relating particles, graph nodes, neural artifacts and pixels. It is part of the native Node Lab. The executable pieces are a typed observation directory, a deterministic in-process gossip example, and an explicitly requested read-only inspection of the current native graph.

The gossip example contains four virtual workers in one process. It opens no sockets, discovers no devices and authenticates no remote identity. The graph inspector operates on the actual native projection when invoked in the app; it is separate from the fixture example. Neither operation calls a model or writes a document, lesson, preference or development record.

## What the representations mean

| Representation | Addressable unit | Required binding | Meaning of a connection |
| --- | --- | --- | --- |
| Pixels | A frame or bounded region of a frame | Artifact, revision, frame index, dimensions and optional region | An explicit reference to image data; no claim that ARCHi interpreted its content |
| Particles | An emitter checkpoint | Artifact, revision, emitter and checkpoint | A particular simulation state; no per-particle network membership |
| Nodes | A graph entity and optional proposed edit | Artifact, revision, graph and node | An entity in a named graph; a proposed edit remains a proposal |
| Neurons | A model checkpoint, optionally an explicitly captured activation | Artifact, revision, model, checkpoint and, for an activation, layer/tensor/capture references | A model artifact or measured tensor reference; no access to hidden reasoning is implied |
| Splats | A splat set and optional frame segment | Artifact, revision, set and half-open frame interval | An addressable appearance/geometry representation reserved in the domain; no splat renderer is added |

Every reference includes a semantic object ID. Sharing that ID declares that the references concern the same named object; it does not establish physical equivalence. Links name their relation and their evidence IDs. Evidence retains its original producer, artifact revision, SHA-256 digest reference and declared origin (`simulation`, `localSnapshot` or `remoteClaim`). A syntactically valid digest is a reference, not proof that its artifact was fetched or verified.

The example uses a single synthetic orbit object. Its particle checkpoint references a pixel frame through `rendersTo`; a graph node annotates the checkpoint, model checkpoint and frame. All four observations are explicitly marked `simulation`. No image capture, renderer or inference execution is claimed by those fixtures, and the neural fixture has no invented activation.

## How gossip works here

Each virtual worker begins with its own observation. On a round it selects two other workers using a deterministic schedule derived from the seed and relays its locally fresh observations. The next round uses a snapshot of the previous round, so iteration order cannot create hidden propagation within a round.

The observation's origin, event, sequence, evidence and links remain unchanged. A relay gives the message a new delivery ID and routing envelope. An identical envelope is also repeated deliberately to exercise transport deduplication. Delivery identity and observation identity are tracked separately: five deliveries of one observation still represent one observation.

The directory enforces session, recipient and allowed-peer scope; validates representation bounds and evidence links; rejects reused identities with changed content; and caps payload, peer, delivery, observation, evidence and history sizes. Identity ledgers stay intact after expiry. When a replay ledger fills, new events are refused until a new session is created rather than silently making old identities acceptable again.

Freshness uses receiver-local monotonic time. Receiving an already retained observation does not renew it. A report about an origin is separate from direct contact with the sender. An expired report means that this directory lacks a fresh report; it does not establish that the origin process crashed. There are no SWIM probes, suspicion votes, automatic failover or membership-driven authority changes in this increment.

The example uses a six-second observation lifetime and a 32-round bound. Each UI round advances simulated time by one second. These are fixture settings, not network or production timing recommendations. The app's existing Node Lab presentation refresh remains separate from protocol time.

## A real local task with a review boundary

In Node Lab, select **Representations & peers**, then **Inspect current graph**. The native owner captures the current projection and authorizes one deterministic inspection attempt. The worker receives graph IDs, record kinds/statuses, edge endpoints and the omitted-item count. It receives no source text, lesson words, prompt text or answer text.

The host binds that metadata to SHA-256 digests of the shared source and canonical current context, including request generation, placement/source/selection revisions and lesson revision. These bindings stay within the local process. The input is frozen for the attempt, which has its own epoch and a 60-second monotonic permit.

The inspector checks duplicate node and edge IDs and unresolved edge endpoints, and reports counts by kind and status. Its report explicitly describes the supplied projection and any upstream omissions. A passing result does not validate semantic truth or project data outside that projection.

**Accept session report** asks the existing owner to recheck the current context, permit, attempt binding and exact locally produced report. It then applies this policy:

| Outcome | Effect in this increment |
| --- | --- |
| `COMMIT` | Append the checked report to a bounded in-memory session list |
| `DAMP` | Hold a candidate without accepting it; a fresh attempt is needed to reconsider it |
| `ESCALATE` | Refuse acceptance because checks are missing, errored, stale, expired or otherwise ineligible |
| `REJECT` | Refuse a failed or mismatched candidate |

Every check retains `PASS`, `FAIL`, `SKIPPED` or `ERROR`. Skipped and errored checks cannot produce `COMMIT`. An already completed attempt cannot accept a replay. A source change, local conversation reset, ordinary work cancellation or shutdown fences pending inspection work through the existing owner. Explicit cancellation also fences an attempt when its clock value is invalid. Previous accepted session reports remain historical reports; they do not become current facts or saved lessons.

`DAMP` is available in the core contract; the initial UI offers acceptance and discard. There is no generic command runner, remote execution grant, peer-selected owner or distributed write path. Gossip observations are not inputs to `PeerWorkSession` authority.

## Using the local implementation

The source lives in the existing native Swift package. On a Mac with the macOS 14+ SDK and Swift 6:

```sh
swift build --package-path desktop
swift test --package-path desktop --filter 'RepresentationPeerTests|CompanionPeerIntegrationTests|CompanionGraphTests'
```

Run those commands from the existing ARCHi checkout after reconciling the changes with its current branch. A remote branch does not update a local working tree or an installed app. This change does not replace a running build, create another companion identity or migrate a profile. Use the existing build workflow only after the native checks and local review.

The portable harness runs the same four Foundation source files and the same `RepresentationPeerTests` under Swift 6 without SwiftUI or AppKit. It creates a disposable package outside the repository and does not substitute a second implementation. This makes core protocol behavior testable on Linux and macOS; it does not qualify the native adapter or presentation.

```sh
script/test_representation_peers.sh
# If Swift is outside PATH:
SWIFT_BIN=/absolute/path/to/swift script/test_representation_peers.sh
```

The [local Codex handoff](CODEX_LOCAL_PEER_HANDOFF.md) records the remaining Mac-specific integration and review work.
The [validation record](PEER_REPRESENTATIONS_VALIDATION.md) separates executed core checks from pending native qualification.

## Sources and ownership

- [Typed representations and envelope contracts](../desktop/Sources/ARCHiDesktop/RepresentationPeerDomain.swift)
- [Bounded observation directory](../desktop/Sources/ARCHiDesktop/PeerObservationDirectory.swift)
- [Deterministic gossip example](../desktop/Sources/ARCHiDesktop/PeerGossipSimulation.swift)
- [Read-only worker, attempts and admission](../desktop/Sources/ARCHiDesktop/PeerWorkSession.swift)
- [Native adapter and controls](../desktop/Sources/ARCHiDesktop/CompanionPeerWorkspace.swift)

Actual network peers are a later extension. Before adding them, the transport needs explicit peer authentication, a real decoding-size boundary, end-to-end replay and freshness rules, cancellation propagation, privacy-aware artifact retrieval, failure detection and partition tests. Distributed authoritative writes would additionally require the existing owner or an appropriate consistency mechanism. The current in-process IDs and allowlist are not substitutes for those requirements.
