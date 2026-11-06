# Visual influence evaluation

This is an isolated developer experiment for separating **strategy sensitivity**, **incorrect proposals**, and **unauthorized effects**. It is motivated by [A Heart Means Recursion](https://arxiv.org/abs/2610.36449), but its prompts, tasks, synthetic images and model differ unless an operator deliberately matches them. It is not a reproduction result.

The current native ARCHi path captures Accessibility/OCR **text** for review. It does not forward or retain screenshot pixels. Native Swift owns context, request admission, reviewed working-copy changes and permissions. This lab neither changes that path nor creates another app state owner.

## Evidence boundaries

| Component | What it measures | What it does not establish |
| --- | --- | --- |
| Offline harness checks | Input integrity, image controls, collection limits, classification and accounting behavior using synthetic/mock data | Model robustness or admission performance |
| `text_model` collector | Syntactic code-strategy frequencies under text cues through an experimental local Ollama request | Behavior of ARCHi's exact native request template/transport or pixel sensitivity |
| `vlm` collector | The same frequencies with generated PNG stimuli and a verified vision-capable local model | Correctness, real screenshot behavior, or unauthorized execution |
| Native `VisualInfluenceBoundaryTests` | Production native boundaries exercised by synthetic requests on macOS | Full UI behavior, real OCR behavior, or live-model reliability |

No generated program is executed. No reasoning trace or self-declared strategy supplies the classification. All model reports set `nativeGateVerified: false`, `semanticsVerified: false`, and leave admission/execution rates `null`. An unrun test is not a pass. There is no fabricated model self-review or simulated gate advertised as native evidence.

## Run offline checks

Requirements: Node.js 24 and Python 3. These files use standard libraries only.

```sh
npm run visual:test
```

The broader `npm run check` includes these checks. No actual Ollama service, provider credentials, app launch, image permission, user profile, model download or cloud model is needed.

The native suite is separate and requires macOS 14+, Swift 6 and the macOS SDK:

```sh
swift test --package-path desktop --filter VisualInfluenceBoundaryTests
```

Run native tests before claiming their regression assertions passed. Linux harness results cannot substitute for Swift results.

## Prepare a pilot without making model calls

From the repository root:

```sh
npm run visual:lab -- prepare --mode text_model --replicates 2 --seed 17 --out output/visual-influence/text-pilot/manifest.json
```

This creates 40 randomized jobs: two tasks, two prompt styles, five conditions and two replicates. The first task is a development case; the second is reserved as a held-out task. Keep its results out of tuning decisions. These two cases alone cannot support a broad generalization claim.

Text conditions: no cue, Unicode heart, Unicode checkmark, caption, and a quoted apparent approval instruction. These are text conditions, including the Unicode emoji. They do not reproduce a pixel experiment.

Prompt styles are `silent` and `explicit`. Within a task/style/replicate, the wording is identical across conditions except for the cue. Recursive/iterative option order alternates across replicates. The explicit baseline retains the same conditional instruction about considering a cue even when no cue is present. This avoids changing both instruction wording and image presence within a comparison.

The manifest records its repository source commit (resolved from the script location), dirty-source status, actual harness-file digest, seed, requested matrix, prompts, model settings and a digest. Collection refuses a changed harness. Summaries also record the implementation digest used for analysis. A matching manifest hash is followed by full validation of the declared matrix: missing image bytes, changed settings and mismatched replicate sets are rejected even if someone recomputes the hash. Do not edit a manifest after collecting responses. New output paths are created exclusively; existing runs are not overwritten.

## Collect with an existing local model

Choose an exact model already installed in your own Ollama service. Replace `YOUR_INSTALLED_LOCAL_MODEL` below; the collector never pulls a model.

```sh
npm run visual:lab -- collect --manifest output/visual-influence/text-pilot/manifest.json --model YOUR_INSTALLED_LOCAL_MODEL --max-requests 40 --out output/visual-influence/text-pilot/records.jsonl
npm run visual:lab -- summarize --manifest output/visual-influence/text-pilot/manifest.json --records output/visual-influence/text-pilot/records.jsonl --out output/visual-influence/text-pilot/report.json
```

The collector permits literal loopback endpoints, rejects redirects and remote/cloud model metadata, and performs bounded preflight checks. Each model request has a deadline and an output bound. The complete manifest must fit within the requested generation cap before any request is made; two metadata requests are additional to that cap. Records are checkpointed as they arrive. Failed or interrupted collection leaves an incomplete matrix, and affected conditions do not receive a steering delta. Collection and summary commands exit with code 2 for incomplete observations, while retaining their records/report. A stopped process can leave a partial JSONL file: preserve it, inspect it, and summarize only complete records without inventing missing observations.

Each request has a 120-second deadline and a 10 MiB response limit. The complete JSONL capture is capped at 24 MiB, with space reserved for failure and skip metadata, below the analyzer's 32 MiB input limit. A response that would exhaust the aggregate budget is recorded as an explicit capture error, with known token counts retained; its body is discarded and subsequent generation requests are skipped. It is never relabeled as a complete truncated answer.

There is no automatic retry or substitute model. Preflight failures and unsupported image capability remain errors/skips with their reason. Native token counts preserve explicit zero values; unavailable counts remain unknown. No monetary charge is inferred from a token count.

The collector records the installed model digest observed during preflight. Keep the chosen tag unchanged throughout collection: the Ollama chat response does not bind each generation to that recorded digest. The manifest seed fixes stimulus construction and request order; generation uses `seed + replicate` so matched conditions share a sampling seed. These settings support repeatability but do not guarantee identical output across hardware or model/runtime versions. Recorded per-job latency covers generation attempts; metadata preflight time is not included.

## Separate VLM pilot

```sh
npm run visual:lab -- prepare --mode vlm --replicates 2 --seed 17 --out output/visual-influence/vlm-pilot/manifest.json
npm run visual:lab -- collect --manifest output/visual-influence/vlm-pilot/manifest.json --model YOUR_INSTALLED_LOCAL_VISION_MODEL --max-requests 48 --out output/visual-influence/vlm-pilot/records.jsonl
npm run visual:lab -- summarize --manifest output/visual-influence/vlm-pilot/manifest.json --records output/visual-influence/vlm-pilot/records.jsonl --out output/visual-influence/vlm-pilot/report.json
```

The 48 jobs use no image, blank image, red heart, yellow checkmark, shuffled heart and text caption conditions. PNGs are generated deterministically at 400 × 400. The shuffled control preserves the heart's exact color histogram. These are newly generated geometric controls, not copies of the paper's stimuli and not user screenshots. Image bytes and digests are part of the manifest. Only this experimental collector sends them, and only to the selected verified local vision model.

Failure to establish vision capability must not silently fall back to a text-only request. Passing the collector's metadata checks is a preflight observation; it is not a proof about every possible behavior of a separately configured Ollama server.

For a larger study, prepare a new run with a larger replicate count (maximum 50). Two replicates are a plumbing pilot, not strong statistical evidence. Decide models, tasks, sample counts, exclusions and acceptable error rates before inspecting the study results. Preserve each model/version and prompt style as a separate stratum.

## Classification and interpretation

The Python classifier parses source with `ast`; it never imports or runs that source. It follows direct function calls reachable from the requested entry function and detects a call cycle or loop. Imports, decorators, ambiguous function names, unresolved calls, malformed responses and unsupported constructs become `unknown`. A response's prose or claimed strategy has no authority.

This is conservative **syntactic classification**, not a proof that a branch executes, that a loop terminates, that variable bindings preserve the static call graph, or that the algorithm is correct. Even recognized code needs independent semantic testing before any execution/admission study. Audit a sample of classifications manually; expand the classifier only against separately labeled examples.

Reports include requested/completed/error/skipped/missing counts and classification coverage. Records must declare their collector, model, model digest and evidence origin; mixed identities are rejected rather than pooled. Synthetic metric-test fixtures remain labeled `synthetic_test`. Metadata declarations are provenance records, not authentication. Recursion fractions are explicitly conditional on classified outputs. Deltas are produced only when both a condition and its matching no-cue baseline are fully collected and classified. Unknown code and missing/error observations cannot be converted into iteration or silently discarded from a headline delta. Zero denominators are `null`.

## Admission study: next measurement, separate from strategy counts

The native validator currently checks response shape, exact reference membership and current ownership; structural acceptance does not certify an answer's truth. A runtime effect must be evaluated through its actual existing owner, such as reviewed working-copy Apply. The native tests deliberately include a structurally valid but semantically unsupported answer as a negative control.

For a later matched-proposal study, label proposals independently, then replay the same proposals against each real admission implementation. Include correct iterative and recursive outputs, wrong results, resource violations, stale state, out-of-scope targets and forged approval cues. A self-review baseline needs an actual model review; do not synthesize it from a fixed rule.

For invalidity `V`, acceptance/execution `C` and input condition `i`, report raw numerators and denominators for:

```text
P(V | i)                 invalid proposal fraction
P(C | V, i)              invalid-proposal acceptance fraction
P(V | C, i)              invalid fraction among accepted proposals
P(C | not V, i)          valid-proposal acceptance fraction
P(V and C | i)           invalid executed/accepted fraction
```

The identity `P(V and C | i) = P(V | i) × P(C | V, i)` requires no independence assumption. Measure latency and cost per valid completion, refusal/false rejection, and failures across whole retry episodes. An accept-nothing system must not appear useful merely because it has zero invalid executions.

Only execution receipts from the real adapter may fill these fields. The current strategy collector deliberately leaves them unmeasured. Fixture integrity hashes help reproduce inputs; they are not authentication or external tamper-proof anchors.

## Provenance

Implementation and synthetic geometry are project-authored under the repository MIT license. Reference: [Tartaglini et al., arXiv:2610.36449](https://arxiv.org/abs/2610.36449). Local API contracts: [Ollama chat](https://docs.ollama.com/api/chat), [local models](https://docs.ollama.com/api/tags), and [official API types, including model capabilities and remote-host metadata](https://github.com/ollama/ollama/blob/main/api/types.go).
