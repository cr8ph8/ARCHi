# Bounded synthetic activation acquisition

The research-only `--acquire-calibration` command reads the final prompt residual
for one batch of synthetic examples. It does not generate tokens or fit a reader.
It loads and verifies the installed GGUF once and creates and frees a separate
`llama_context` for every sample. No KV cache or recurrent context state is reused
between samples. The model weights are shared read-only during the batch.

This command is separate from the app's scalar-only shadow request schema. Raw
residual vectors are returned only in `archi-gguf-calibration-result/v1`, for a
local fitting script. They are never placed in native answer receipts. The
worker writes no files and performs no downloads. Its response does not include
prompt text or labels. `synthetic_only` is a caller declaration; the worker
cannot determine the provenance of arbitrary text.

The scope being fitted is
`synthetic-record-field-support/prompt-final/v1`. A contrast measured on a short
synthetic field-lookup corpus does not establish answer correctness, safety,
knowledge, or task performance on ordinary work.

## Build and execution boundary

The new build defaults to ignored
`output/gguf-calibration-runtime-2026-09-25`. The prior sealed runtime remains at
`output/gguf-representation-build-2026-09-25/runtime` and must not be overwritten.
The recipe can reuse the existing CMake executable without a new installation:

```sh
python3 research/representation/gguf/build.py \
  --output output/gguf-calibration-runtime-2026-09-25 \
  --cmake output/gguf-representation-build-2026-09-25/build-tools/cmake/data/bin/cmake
```

The new output needs its own copy of the pinned source archive in `downloads/`.
The recipe's `--fetch` option only downloads the pinned source if absent. It
does not fetch weights. Runtime libraries use the same exact upstream revision,
CPU build flags, four inference threads, and `l_out-N` observation point as the
normal shadow worker.

Invoke `runtime/archi-gguf-shadow --validate-calibration` to check a request
without opening the model. Invoke `--acquire-calibration` only for the authorized
acquisition. The worker accepts one request, performs at most one batch, writes
one result, and exits. The orchestration script owns the single-run limit and
persisted evidence.

## Request

Required top-level fields:

| Field | Contract |
| --- | --- |
| `schema` | `archi-gguf-calibration-request/v1` |
| `purpose` | `synthetic-reader-calibration` |
| `synthetic_only` | JSON `true` |
| `run_id` | UUID |
| `model_name` | `qwen3:8b` or `qwen3.5:9b` |
| `model_path` | Absolute regular-file path to installed GGUF |
| `model_digest` | SHA256 of the selected Ollama manifest bytes |
| `model_blob_digest` | SHA256 of actual GGUF bytes, verified before loading |
| `tokenizer_digest` | Equal to `model_blob_digest`, binding the embedded tokenizer |
| `template_digest` | `4b94cbc45ca52e5df957a2960327a9311bb1c37218865e7ffd626fa86d9056cc` |
| `backend_revision` | `llama.cpp:161755f29` |
| `precision` | `Q4_K_M`, also checked against loaded GGUF metadata |
| `layer` | Canonical `l_out-N`, where `0 <= N < 128` and the loaded model's layer count |
| `dataset_digest` | Caller-verified SHA256 of the complete synthetic dataset artifact |
| `samples_payload` | Exact UTF-8 serialized JSON array copied into `samples` |
| `samples_payload_digest` | Verified SHA256 of those payload bytes |
| `samples` | One array of 1–24 samples |
| `max_input_tokens` | 1–512 per sample |
| `max_total_input_tokens` | 1–8192 for the batch |
| `deadline_ms` | 1–540000 for hash/load/all sample processing |

Every sample has a unique `sample_id` (1–128 UTF-8 bytes), `input`, `system`,
`response_schema`, and the exact preformatted `prompt`. It also has
`input_digest`, `system_digest`, `schema_digest`, and `prompt_digest`. Each
component is at most 16384 bytes and must contain no NUL. All component hashes
and exact rendering through the app's pinned ChatML template are verified.
The three unformatted components must not contain `<|`, preventing data from
introducing ChatML role delimiters. Labels and train/calibration/holdout splits
belong to the fitting workflow; this worker neither reads nor uses them.

All prompts are tokenized and checked against individual and total limits before
the first decode. Overlong inputs fail without truncation. The model must have
4096 hidden components and architecture `qwen3` or `qwen35`. Prefill runs in
chunks of at most 256 tokens. Only the final chunk enables the callback, which
copies one F32 row from the selected layer's final token.

## Result and limits

Successful acquisition returns `schema: archi-gguf-calibration-result/v1`,
`status: ok`, `stop_reason: all_samples_acquired`, the top-level model/template/
backend/dataset/payload identity echoes, `token_rule: prompt-last`,
`context_policy: fresh-context-per-sample`, `generated_tokens: 0`,
`hidden_width: 4096`, `sample_count`, and `total_input_tokens`.

`samples` preserves request order. Each item contains `sample_id`, the four
component digest echoes, `layer`, `input_tokens`, `token_position` (zero-based,
equal to `input_tokens - 1`), and `activation` (4096 finite float values).
`activations_digest` hashes the worker's sorted-key compact JSON serialization of
the returned sample array. The fitting script should also hash the exact output
file bytes for cross-language provenance.

The whole acquisition has a wall deadline of at most 540 seconds, a two-second
hard-exit grace, and a 545-second process alarm covering stdin/startup as well.
The research child also has aggregate CPU soft/hard limits of 2160/2200 seconds
to accommodate four CPU threads within the wall budget. SIGTERM, SIGINT,
SIGXCPU, model-load progress, and CPU decode abort callbacks stop cooperatively.
The parent must terminate and reap its child if its own wall deadline expires.

After each successful sample, stderr includes only a line of bounded progress:
`archi_calibration_progress completed=N total=N input_tokens=N`. Other llama.cpp
diagnostics also use stderr. Neither progress nor result echoes prompt text.
A failure produces a calibration error response and nonzero exit, or a hard
timeout exit without a result. Partial vectors are not returned as success.

`--validate-calibration` returns `status: validated`, identity echoes, and no
`samples` or activations. It proves protocol handling only. It opens no model,
allocates no model context, and calls no decode.

## Applying a prompt-only reader

The existing shadow basis optionally accepts `token_rule`. Omission or `last`
retains the legacy per-decode scalar behavior. `prompt-last` additionally requires
`measurement_scope: synthetic-record-field-support/prompt-final/v1` and returns
exactly one scalar sample: `decode_index: 0` and
`token_position: input_tokens - 1`. Generation may continue, but later token
decodes do not observe or project activations. The basis identity echoes these
fields. This prevents a reader fitted only to prompt-final examples from being
silently applied to generated-token trajectories.
