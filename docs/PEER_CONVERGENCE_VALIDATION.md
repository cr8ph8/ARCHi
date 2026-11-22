# Bounded peer convergence validation

The peer fixture needs a reference and fresh evidence before agreement can be
interpreted as useful progress. Four peers agreeing on empty or incorrect sets
must not be presented as a successful reference match. Acceptance of a graph
inspection remains a separate explicit operation owned by PeerWorkSession.

This change extends the actual Swift tests from the peer representation change
at `3f5e8d6dad1b80a02ccb19de14b6f1f541cdc281`. It does not add a new admission
policy or change production owners. The earlier independent Python experiment
is not counted as a Swift result.

## Declared reference and observed window

The reference U consists of the four complete synthetic fixture observations.
For peer i, K_i(t) contains only observation records for which `isFresh(at: t)`
is true. Stored records survive expiry for replay protection; their raw count
does not measure fresh evidence.

- Reference error: maximum `|K_i symmetricDifference U|` over peers.
- Disagreement: maximum `|K_i symmetricDifference K_j|` over peer pairs.
- Fresh coverage: the number of correct peer-observation pairs, out of 16.
- Full observation equality: every fresh record must equal its canonical
  fixture value, including evidence, origin, revision, representations and links.

Seeds 0, 1 and 2 cover the three `seed % 3` fanout classes. The declared
expectations are:

| Observation | Reference error | Disagreement | Fresh coverage |
| --- | ---: | ---: | ---: |
| Start at t=0 | 3 | 2 | 4/16 |
| Round 1 at t=0.1 | 1 | 2 | 12/16 |
| Round 2 at t=0.2 | 0 | 0 | 16/16 |
| Rounds 3-4 at t=0.3-0.4 | 0 | 0 | 16/16 |
| After expiry at t=7 | 4 | 0 | 0/16 |

The final row compares against the original fixed reference. It means that no
original observation remains fresh; it is expected TTL behavior, not a protocol
defect. These finite fixture observations do not prove infinite convergence.

## Test populations

`BoundedConvergenceTests` adds four cases: the fresh trajectory and complete
value equality across the three fanout classes; valid expiry with retained
history; refusal of an unprepared session; and a valid fresh attempt recovering
after a stale-context refusal and committing exactly once. The latter inspects
a hand-specified two-node, one-edge graph. A rejected attempt is not counted as
accepted useful work.

The Mac runner executes separate populations:

| Stage | Expected XCTest cases | Scope |
| --- | ---: | --- |
| Foundation core | 16 | 12 existing RepresentationPeerTests plus 4 BoundedConvergenceTests, using the production source files |
| Native integration | 7 | CompanionPeerIntegrationTests in the full desktop package, using disposable profiles and in-process model stubs |

The core stage does not validate SwiftUI or native owners. The native stage
checks source changes, request completion, permit expiry, cancellation, reset,
shutdown and an explicitly accepted graph inspection. Neither stage qualifies
the installed app, accessibility, real model inference or real peer networking.

## Run on a Mac

Requirements: macOS 14 or newer, Swift 6 or newer, the macOS SDK, Python 3.10 or
newer, and a clean checkout with the peer change in its history. Use a new
output directory outside the tracked source. The runner records the exact HEAD
and source hashes before and after testing; an explicit expected HEAD can be
provided by CI or a reviewer.

```sh
python3 script/test_peer_convergence_macos.py \
  --output /absolute/path/to/new-peer-test-evidence \
  --expected-head "$(git rev-parse HEAD)"
```

The focused portable core harness also includes the four new cases:

```sh
script/test_representation_peers.sh
```

The Python checks exercise result accounting and execution safeguards only:

```sh
python3 -m unittest discover -s scripts/tests -p test_peer_convergence_macos.py
```

The GitHub workflow uses macOS, checks out the explicit PR head, supplies a
read-only repository token without persisted checkout credentials, and retains
JSON/log evidence. No secrets or live-provider opt-ins are provided.

## Interpret a run

PASS requires the expected nonempty XCTest populations, passing assertions,
no skipped required tests, and stable source provenance. A successful process
exit with absent or ambiguous test accounting is ERROR. Missing prerequisites
are SKIPPED. Build/launch failures, timeouts and source changes are ERROR;
observed assertion failures are FAIL. Exit codes are 0 for complete PASS,
1 for FAIL/ERROR and 2 for incomplete SKIPPED validation.

The runner stops the Swift process group on timeout before hashing its log.
It records toolchain details, commands, timing, source evidence and individual
stage outcomes. It strips inherited `ARCHI_*` opt-ins while retaining the names
of removed variables, without recording their values.

Consult the generated report or CI run for actual results. A test source file,
workflow definition or prepared runner is not evidence that its tests executed.
