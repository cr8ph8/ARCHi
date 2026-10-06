# Task-specific local Qwen reader

26 September 2026 · `archi-task-reader-plan/v1`

This workflow builds an actual linear reader from the installed Qwen3.5:9b's hidden activations. Its narrow target is **whether the supplied synthetic records contain the exact requested ID and field**. It does not measure honesty, consciousness, intelligence, general truth or permission. The source lookup rule supplies the labels; model confidence does not supply its own answer key.

## Why this implementation

The earlier four-pair, layer-15 mean-contrast reader failed calibration. Its calibration classes overlapped and one pair reversed direction. A threshold adjustment cannot repair that ordering. Those original artifacts remain failed and unchanged.

The new protocol fixes the final text block (`l_out-31`) before acquisition, increases the fit set to 48 matched pairs, and uses regularized linear fitting. Twelve separate pairs calibrate the scale and threshold; twelve further pairs are reserved for qualification. Every pair has the same lexical inventory with opposite labels derived by exchanging record IDs. Layouts and domains recur across splits, while record identities are disjoint. This measures new instances of the **same generator**, not cross-domain transfer. These synthetic examples were generated locally, not independently collected from real users.

The [RepE paper](https://arxiv.org/abs/2310.01405) motivates reading directions in model representations. Its [reference implementation](https://github.com/andyzoujm/representation-engineering/blob/main/repe/rep_readers.py) includes centered projection, PCA and cluster-mean directions. The grouped ridge objective here is an ARCHi engineering choice; it is not attributed to that paper as an original result.

## Exact fitting rule

For fit activations `H` and labels `y ∈ {−1,+1}`, compute the fit-only mean `c`, centered matrix `X = H − c`, and `K = X Xᵀ`. For each predeclared strength `λ ∈ {0.01, 0.1, 1, 10}`:

`α = λ tr(K)/n`

`a = (K + α I)⁻¹ y`, solved numerically without forming the inverse

`w = Xᵀ a`.

This minimizes `||Xw − y||² + α||w||²`. Equal-sized pairs give equal group weight. With pair half-difference `d_g` and midpoint `m_g`, the data term is also `2 Σ_g [(wᵀd_g − 1)² + (wᵀ(m_g − c))²]`. This penalizes response to observed nuisance variation between groups as well as fitting their contrast.

Leave-one-whole-pair-out cross-validation selects strength using **fit rows only**, recomputing the center and regularization scale inside each fold. The criterion is the number of misclassified held-out fit rows; zero counts as an error. Ties prefer stronger regularization. This selection score is a development diagnostic, not independent qualification.

After the final fit, normalize `v = w/||w||` and project `s(h) = vᵀ(h − c)`. Calibration sets `b = (min s_positive + max s_negative)/2` and `σ = std(s_calibration)`. The signed standardized margin is `m = y(s − b)/σ`. These are coordinates, not calibrated probabilities. Zero variance, nonfinite values, overlapping classes or insufficient margins do not qualify.

The fixed gate requires **every calibration margin ≥ 0.1** and positive class separation. Only then may qualification acquisition run. The candidate and exact acquisition digests are sealed before it starts. Every held-out margin must also be ≥ 0.1. There is no held-out retry, layer search, threshold relaxation or refitting after qualification. This small-set gate does not supply a population guarantee.

## Execution and artifacts

Use [`task_reader.py`](task_reader.py), [`task_reader_math.py`](task_reader_math.py) and the already built `archi-qwen35-text-v1` worker. Explicit stages are `prepare`, `development`, `fit`, and conditionally `qualify`. Every stage takes `--output`; acquisition stages also take `--worker`. Preparation creates a **new** directory under ignored `output/`. Existing runs are never overwritten. Use an arm64 Python with NumPy; no new model installation is required.

Each subprocess handles at most 24 samples, 512 tokens per sample and 8,192 input tokens, with zero generated tokens and fresh model context per sample. Five development batches plus at most one qualification batch stay within 49,152 input tokens. Every batch has a 550-second parent timeout and bounded teardown, plus the worker's own deadline/CPU limits. Process completion and validated acquisition have separate receipts.

The workflow binds source hashes, model manifest and blob, tokenizer, template, backend, layer, prompt components, sample positions and runtime members. A copied candidate from another run or a changed plan cannot authorize held-out acquisition. These are local integrity checks, not cryptographic authentication against someone rewriting the entire evidence set.

`reader.candidate.json` stores fitted numerical weights even when calibration fails, visibly marked **unqualified-candidate**. It is deliberately a different format from the older native reader. `development-report.json` records calibration and actual tokens; `qualification-report.json` exists only if that separate stage runs. Raw synthetic activation files stay in ignored local output.

## Where this belongs in Hampton's stack

The intended consumer is a task-scoped measurement adapter: current source-addressed records → exact lookup task → qualified representation coordinate → attributable observation. That could later inform uncertainty or work allocation alongside independent outcomes. It must not replace deterministic record lookup, claim verification, source freshness, permissions, memory admission or companion-development evidence.

The existing native v1/v2 imports qualify no ordinary-chat task. `canMeasureGeneralReplies` is therefore false, enforced both when enabling and when constructing the assistant; inspection remains available. A new qualified task contract and matching native runtime/consumer are required before this candidate can be admitted. A passing synthetic result alone does not authorize widening that scope or enabling activation steering.

## Executed run

The first run of this protocol passed all 24 calibration and all 24 held-out examples. Minimum signed margins were 0.349168 and 0.228235, respectively; the threshold remained 0.1. Training-only CV selected strength 0.1 (1/96 errors, tied with 0.01; stronger wins). These CV rows were used for model selection and are not an independent accuracy estimate. The six acquisition batches processed 20,004 input tokens with zero generation in 395.80 seconds. No cloud calls or model reinstall occurred.

[`task_reader_export.py`](task_reader_export.py) revalidates the exact run, regenerates margins from its sealed activations and writes a read-only native review plus a qualified research bundle only when the gate passes. The new native report view accepts that review file; it cannot enable inference. See the [public result receipt](../../../docs/research/task-reader-result-2026-09-26.json). Locally retained run: `output/task-reader-2026-09-26/run-01/`.

The subsequent [Record lookup integration](../../../docs/native-record-lookup.md)
adds a separate native task consumer with a scalar-only, zero-generation worker
endpoint. Its single historical-prefill compatibility check reproduced the
original projection exactly. The existing report view and ordinary reader
import retain their boundaries; everyday record transfer is not newly qualified
by connecting this consumer.
