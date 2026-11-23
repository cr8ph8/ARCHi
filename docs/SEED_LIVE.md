# Animated Seed: memory and harness inspection

Seed Dive now animates changes in ARCHi's existing local graph and exposes the
latest request, invocation, admission and peer-inspection metadata beside it.
Open **Seed Dive** in the workspace sidebar, or **Dive into Seed** from the
companion's menu or KIN card.

## The four views

| View | What it can show | What its animation means |
| --- | --- | --- |
| Memory | Companion, source references, kept lessons, temporary context, requests, invocations, answers and omissions from Node Lab | A bounded record or relationship changed in the current projection. |
| Harness | Existing provider lanes, request state and phase, recorded model identity, invocation outcomes, admission status, and peer-inspection metadata | A reported state changed between two received snapshots. |
| Neural | Whether a neural activation recorder is connected | No neuron activity is drawn as measured data while the recorder is unavailable. |
| First form | An optional raindrop interpretation of Sol, with a continuous amber Core and rounded bear features | A user-controlled visual preview. Growth is not measured learning or an identity update. |

The inspector, searchable record list, type filters and directed **Path from
seed** remain available. Source details stay attached to their existing records.
An answer or accepted inspection report does not become a kept lesson through
this page.

The view starts from a baseline. Reopening an existing graph does not invent a
stream of newly observed events. Changes can produce brief pulses and a bounded
activity feed; idle data settles. Pausing motion does not cancel a request. The
native **Stop request** button retains that separate purpose.

## Provenance stays visible

**Local snapshot** means the native application supplied the current projection.
It does not mean a remote neural network is being sampled. **Synthetic replay**
identifies the standalone design demonstration. The offline four-worker peer
example remains explicitly synthetic even when its state appears inside a
native snapshot.

The visual design uses cyan and amber to help follow records and reported
transitions. It is not a probability map, a physical brain scan or a proof that
the model learned something. Node coordinates are layout positions. They are
not measured embedding distances, error bounds or epsilon balls. A stable
picture does not establish mathematical convergence or semantic truth.

## Data ownership and freshness

`CompanionStore` and its existing request and peer owners remain authoritative.
`SeedTelemetrySnapshot` is a bounded, read-only value projection. The page
receives an additive payload through the existing `seedDive.replace` entry
point. It receives no file handle, persistence API, provider client or
JavaScript-to-native message handler.

The payload retains `nodes`, `edges` and `truncatedCount`, and adds a schema
version, origin, context identifier and telemetry for memory, harness, peer and
neural status. Metadata excludes raw prompts, reply bodies and token streams.
The graph inspector still displays the bounded record details already available
in Node Lab; those details are not duplicated into the activity feed.

Native published changes update the page. A periodic presentation refresh can
re-evaluate time-sensitive records; unchanged values do not manufacture activity.
This is a view of the latest observed state, not a lossless event journal. SwiftUI
may coalesce rapid intermediate updates, and elapsed values mean what the
underlying receipt records. The UI does not interpolate missing model stages.

Replacing a context, withdrawing a record, or clearing the snapshot invalidates
the corresponding presentation history. The host hides the previous frame while
replacement is delivered and ignores superseded delivery callbacks. Quiet mode,
reduced motion, page visibility and teardown bound animation work.

## Standalone demonstration

The bundled `desktop/Sources/ARCHiDesktop/Resources/SeedDive/interior.html` is
self-contained and has no network dependencies. Its explicit synthetic replay
demonstrates observation, connection and review states without opening a model
or writing a memory. The application supplies native snapshots instead.

The replay is useful for design review and explanation. Its timestamps and
events must not be reported as operational measurements. A recorded preview
made from this mode must retain the synthetic label.

## First form: Sol as a raindrop

Open **First form** to explore a possible first appearance for Sol. **Grow the
Seed** shows the amber Core gathering water and taking shape. The Core remains
visible while the translucent body develops rounded bear ears, a broad muzzle
and compact paws. This is a proposed visual design, not a new canon or a measured
biological or neural process.

Reaching the final stage reveals an option; it does not change the selected
form. **Preview Sol · Raindrop** explicitly selects the local appearance, and
**Return to Seed** resets it. The direct preview is also available without
watching the transition. The visible **Form preview · not saved** label applies
in both the native app and the standalone page.

These controls update only presentation state in the current page. They do not
save a form, alter the companion's identity, create a lesson, change the graph,
or call a provider. The existing one-way native boundary is unchanged. Choosing
a permanent companion appearance would require a separate native action.

Pausing growth freezes its progress. Leaving the view or hiding the page stops
the animation without accumulating hidden time; returning requires explicit
resume. Native context or provenance replacement resets the preview. Reduced
motion provides the final option immediately and renders a static form. The
completed form settles rather than running an unbounded idle animation.

## Neural recorder integration boundary

The shipped projection reports `neural.available = false`. Model names and
invocation receipts do not establish access to activations.

A future recorder should bind each sample to a request, model identity, layer or
unit group, sequence number, sample time and explicit sampling policy. The
recorder needs bounded retention and a stop/withdrawal boundary before any
samples are displayed. The view should distinguish activation measurements,
aggregations and illustrative connections. Similarity alone should never create
a kept memory or an authority-bearing graph edge.

## Validation

Portable checks:

```sh
node --test scripts/seed-*.test.mjs
python3 -m unittest discover -s scripts/tests -p 'test_*_macos.py'
```

Focused native execution on a clean macOS 14+ checkout with Swift 6+:

```sh
python3 script/test_seed_live_macos.py \
  --output /tmp/archi-seed-live-evidence \
  --expected-head "$(git rev-parse HEAD)"
```

Use a new output directory each time. The runner validates complete source
manifest coverage before and after execution, limits the test process lifetime,
and requires the exact selected XCTest population. A missing suite or zero-test
run cannot pass. The selection includes peer and graph regression fixtures,
telemetry projection tests and actual bundled WebKit tests. It strips all
`ARCHI_*` opt-ins and uses synthetic data. It does not connect a provider, use a
real profile, install the app or run an external peer network.

The `Animated Seed on macOS` workflow runs the same commands at the exact PR
head. Native logs, result accounting and WebKit captures are retained as CI
artifacts. A portable JavaScript result alone is not evidence of browser layout,
native compilation or visible animation.

Motion qualification requires an actual motion-enabled OS/browser environment.
The disposable GitHub-hosted workflow uses `--configure-ci-motion` to temporarily
set the two OS motion booleans before launching tests, records their prior values,
and restores them afterward. The flag refuses other environments and never uses
elevation to retry a denied preference write. Native/WebKit readback and the
observed pulse assertion still decide the result. Local test runs and production
never alter system accessibility settings. Reduced motion remains respected,
including a usable Pause/Resume replay control for the timed synthetic sequence.
After the 47-case motion-enabled population passes, CI repeats only the replay
and first-form accessibility regressions with the actual OS reduced-motion
preference enabled. This is 49 native test executions across 47 distinct cases;
both variants require matching
AppKit and WebKit preference readback. The focused repeat reuses the built binary
and does not capture another frame sequence. The normal-motion run retains a
timestamped first-form capture sequence and wide/compact stills. These captures
show the actual UI displaying a visual preview, not inference or learning.
