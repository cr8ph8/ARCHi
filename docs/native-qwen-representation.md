# Local Qwen representation integration

Updated 29 September 2026. Current scope follows the 26 September qualification and native record-consumer delivery. Dated failed attempts below remain evidence of those particular models, layers and protocols.

## Current reader and native consumer

A new final-layer grouped-ridge reader has now been built from the existing Qwen3.5 model: **24/24 calibration and 24/24 held-out synthetic examples passed**, with minimum signed margins 0.3492 and 0.2282 against a fixed 0.1 requirement. Ninety-six examples fitted the direction. Acquisition used 20,004 local input tokens, zero generated tokens and no paid API. The frozen synthetic-only fitted bundle is now packaged for the task consumer; [source, mathematics and scope](../research/representation/gguf/task-reader.md) and the [machine-readable result](research/task-reader-result-2026-09-26.json) are retained. This is not a controlled improvement comparison with the older, different corpus below.

Native ordinary-reply routing refuses synthetic readers at both enablement and construction. A read-only report view supports the new result. The [Record lookup consumer](native-record-lookup.md) now has a separate matching runtime route: exact source lookup plus an optional zero-generation prefill returning only a scalar. The frozen bundle is admitted only to this pinned task consumer; the ordinary reader import contract is unchanged. Everyday data remains an unqualified transfer distribution. No ordinary-chat or steering qualification is claimed.

The [record-consumer delivery receipt](accountability/evidence/r26-record-consumer-2026-09-26.json) records an installed task-scoped consumer and a native walkthrough using a visit-only example. This supersedes the earlier missing-consumer blocker; the older loader and report-viewer observations remain dated below. It does not establish accuracy on owner-authored records or ordinary conversation.

## Preserved 25–26 September attempts

On 26 September, the existing Qwen3.5:9b GGUF loaded through a separate, exactly identified text adapter, resolving the earlier loader incompatibility for this scoped route. A bounded local probe acquired one finite 4,096-value residual at `l_out-15`, using 124 input tokens and zero generated tokens in 15.55 seconds. The adapter is grounded in pinned Ollama compatibility source and preserves the original model bytes. Successful extraction alone did not qualify a reader. [Adapter and provenance](../research/representation/gguf/compatibility-and-qualification.md).

Native v2 reader import now requires the complete supplied qualification record: a frozen plan matching the model, layer, template and backend; eligible corpus provenance; numeric weights bound to the report; all 16 calibration/holdout results and their recomputed margins; positive calibration separation; and fixed acceptance rules. A headline pass is insufficient. Legacy readers remain available for inspection but cannot enable measurements. These are consistency checks on supplied evidence, not authentication or independent scientific reproduction.

The fitting workflow accepts a bounded, frozen external synthetic corpus, derives support labels from its exact records, and rejects altered plans, requests or source inputs before invoking the worker. Previously disclosed built-in examples are permanently marked development-only and cannot emit a reader. External provenance does not prove examples were never seen elsewhere. Ordinary Qwen remains available while experimental measurement is off.

The 26 September contrast-reader attempt completed all 24 prefills in 58.88 seconds, using 3,234 input tokens and zero generated tokens. Fitting failed: calibration separation was −0.315378 and 6/8 held-out examples were correct. The fixed gate required positive separation and every calibration/holdout margin at least 0.1. No reader was exported or enabled from that attempt. It used a different corpus from the earlier 4/8 Qwen3 run; it is not a measured improvement over that run. The scoped loader worked, but that reader remained unqualified. The later final-layer grouped-ridge study is a separate protocol, not a reclassification of this failed result.

## Historical implementation checkpoint: 25 September 2026

At that checkpoint, ARCHi had an installed native adapter targeting its existing Qwen GGUF models, using a locally built Apple Silicon CPU runtime. The delivered increment included bounded synthetic activation acquisition, a separate fitting workflow, scoped v2 reader imports and session-only report-review source. The Qwen3:8b acquisition completed, but the fitted reader failed its predeclared qualification gate. No reader was produced or enabled by that attempt. Qwen3.5:9b then had a separate loader incompatibility, resolved by the scoped 26 September adapter above. Delivery, report-viewer interaction and reader qualification remain separate results.

## Everyday use and scope restriction

Settings → Connections → Qwen → **Read-only model measurements** retains explicit reader import and report inspection. The ordinary-reply measurement toggle is disabled for all currently admitted v1/v2 readers. Their synthetic record-lookup scope does not qualify general chat. This is enforced by the store and assistant construction as well as the UI; changing a setting or supplying a report cannot widen the scope.

Standard Qwen remains connected through its existing local route. A reader must still match the selected model, blob, fixed prompt template, runtime and layer. Importing it does not independently authenticate its report or enable measurement. Imported readers are temporary and disappear when ARCHi closes. Seeds, profiles, memories and Unity retain their existing owners.

**Review calibration report…** displays the older bounded report format without invoking a model. The ridge bundle uses a distinct research format and remains ineligible for ordinary-reply reader import. Its exact frozen bytes are admitted separately by the installed Record lookup consumer. See the [task-reader protocol and mathematics](../research/representation/gguf/task-reader.md) and [consumer contract](native-record-lookup.md#frozen-basis-and-runtime).

## Where it connects

The ordinary-reply adapter path is `HamptonReasonsAssistant → GGUFRepresentationClient → bundled archi-gguf-shadow → native invocation receipt`. It is unavailable to ordinary replies because no admitted reader qualifies that task. Record lookup has a separate source-addressed native consumer and pinned task worker: the user selects a supported table, record and field, then explicitly chooses **Measure locally** for one zero-generation prefill. Exact source lookup works without the measurement. Only a scalar returns to the app; raw model activations do not enter conversation or companion state.

That consumer binds source ID, revision and digest separately from the request, prompt, model and reader identities. Selection changes and cancellation invalidate pending measurements. Everyday tables remain an unqualified transfer distribution despite satisfying the supported format. One synthetic final-prompt coordinate must not be applied to arbitrary chat or generated-token states. No native activation steering, automatic learning award, truth decision or external-action permission is enabled.

## Historical contrast-reader calibration protocol: 25–26 September

[`calibrate.py`](../research/representation/gguf/calibrate.py) has explicit prepare, acquire and fit stages. Its frozen target is whether a supplied synthetic record contains the exact field requested for that record. Twelve matched pairs yield eight fitting examples, eight calibration examples and eight untouched holdout examples, separated by source group and prompt family. Positive/negative members preserve their word inventory while record IDs exchange the supporting and distractor rows.

The [acquisition contract](../research/representation/gguf/calibration-acquisition.md) describes a separate research-only command: one verified model load, a fresh context for each of at most 24 prefills, no generated tokens, no steering, and one final-prompt residual from `l_out-15`. Limits are 512 input tokens per sample, 8,192 total and a 540-second acquisition deadline with bounded teardown. Raw vectors are returned only to the local fitting workflow, not to native answer receipts or Token Steward.

This earlier fitting plan selected `mean_contrast_reader` in advance, used fitting data for direction/center and calibration data for offset/scale, then froze the numerical payload before evaluating holdout. Passing required strict calibration separation and a signed standardized margin of at least `0.1` on every calibration and holdout example. No search or retry used heldout results. A completed failed qualification kept its report and emitted no reader; acquisition or numerical failure could not emit a reader either. The qualified grouped-ridge bundle has its own [frozen plan](../research/representation/gguf/task-reader.md).

Only a pass produces `archi-gguf-reader/v2` with scope `synthetic-record-field-support/prompt-final/v1`, `tokenRule: prompt-last`, and a content-bound calibration report. The native importer checks a declared `limited-shadow-pass`, bounded split counts and a perfect reported holdout result. The UI calls this a **supplied limited shadow report**: checking its bytes and structure is different from independently reproducing it. Four held-out synthetic groups cannot qualify ordinary chat, general source relevance, honesty, truth detection, answer quality or performance gains.

The [R3 intake note](research/2026-09-25-stack-and-representation/r3-reference-intake.md) reinforces task-specific measurement, independent outcomes and evaluation rules. Its 20,000-character conversation preview and unrecovered atlas are research context, not an additional validation result for this reader.

## Historical acquisition and installation: 25 September 2026

The earlier GGUF increment established source/transport and delivery evidence without a fitted reader or real-model measured-answer result. The final runtime refresh from `output/gguf-calibration-runtime-2026-09-25/runtime` was installed at that checkpoint. The [installation receipt](../output/reader-calibration-2026-09-25/installation.json) records executable SHA-256 `8855631e8c73c20c5054f22caa0f5f5adcb4ef0f4a6b5ac072d4cfbfec7681a3`, matching runtime hashes, passing signature verification, and seven known profile files plus 218 Unity resources unchanged; the [install log](../output/reader-calibration-2026-09-25/install-delivered.log) retains delivery output. ARCHi reopened at Light & sound with KIN Original/Liminal retained and nothing sent. The [native observation](../output/reader-calibration-2026-09-25/native-observation.json) recorded report-viewer interaction as pending: file selection was confirmed in accessibility state, but **Review report** remained disabled. No report-decoder failure was established.

That same installed increment contained padded KIN portraits and activity-colored gentle pulsing, preserving the original core and profile. The Light & sound cards and Warm rose Respond preview were observed with Qwen still reporting nothing sent. This is presentation evidence, not model calibration, an all-angle animation review or a complete accessibility pass.

The first calibration attempt against the installed Qwen3.5:9b GGUF failed in the pinned upstream loader before any activation was acquired: `qwen35.rope.dimension_sections` had three entries where four were expected. The [run-01 receipt](../output/reader-calibration-2026-09-25/run-01/acquisition-receipt.json) records exit code 1 and zero generated tokens; the [loader log](../output/reader-calibration-2026-09-25/run-01/acquisition.log) retains the exact error. This is a compatibility failure, not a negative result for a fitted reader and not evidence that Qwen is missing.

The separately selected Qwen3:8b run completed all **24 prefills in 53.34 seconds**, using **3,082 input tokens**, with **1,953,107 bytes** of retained activation output and **zero generated tokens**. Its [acquisition receipt](../output/reader-calibration-2026-09-25/run-02/acquisition-receipt.json) records exit code 0, and the [activation output](../output/reader-calibration-2026-09-25/run-02/activations.json) records the actual input count. This demonstrates bounded real-weight residual extraction, not a measured answer or reader qualification.

The [fit report](../output/reader-calibration-2026-09-25/run-02/calibration-report.json) records **qualification-failed**: calibration separation **−0.526166**, and **4/8 holdout examples correct**. The frozen gate required positive calibration separation and signed margin at least `0.1` on every calibration and holdout example. No importable `reader.json` was emitted, no measurements were enabled, and no holdout-driven retry occurred. The eight holdout examples comprise four matched synthetic groups; this small result supplies no general-chat, truth-detection or population-error claim. Changing models creates a separate model-bound experiment, not an automatic fallback. Installing the workflow does not change this failed qualification.

## Boundaries implemented

- Read-only shadow mode; no activation writes, steering, or automatic development.
- Fixed bundled executable; imported files cannot select a command or executable path.
- Pinned source revision, source archive digest, native architecture, runtime hashes and license notices.
- Bounded reader, request, output, token count, deadline and stderr; owned process termination on Stop.
- Complete output and normal child exit required; token-limit partial replies are rejected.
- Exact prompt reconstruction and special-marker rejection prevent source text introducing ChatML delimiters. Inputs containing `<|` fail closed in this initial adapter.
- External providers and Compare are blocked while measurements are enabled; no automatic external fallback, including the store-owned timeout path. Ordinary routing remains available when measurements are off.
- No model/reader substitution on failure. Return to standard local Qwen explicitly to resume that route.

## What remains after the 26 September delivery

The synthetic record-field reader and native task consumer are available; installing another copy of Qwen is not the missing step. Remaining work is qualification on the intended everyday record distribution, ordinary-chat measurement, any generated-answer validity claim, and measured usefulness or latency in those tasks. A broader study needs its own frozen protocol and fresh holdout. Earlier failed qualifications remain failed; thresholds, retries or inherited test counts cannot relabel them.

Separate native numerical adapters now consume attributable outcomes in [document revision](native-numerical-adaptation.md), [document reading](native-numerical-reading.md), [interactive ARC3](native-numerical-arc3.md) and [Arena advice](native-arena-advice.md). Those declared operational coordinates do not supply a calibrated latent model-to-quotient mapping. Connecting this representation signal to adaptation, broader learned coupling or steering remains separate work; the existing consumer does not award capability, growth or permissions.

Build details and protocol: [GGUF worker](../research/representation/gguf/README.md). Delivery observations: `output/gguf-representation-build-2026-09-25/delivery-receipt.json` and the appended developer-ledger evidence manifest.
