# Local GGUF shadow worker

**September 26 task integration:** the [Record lookup consumer](../../../docs/native-record-lookup.md)
adds a distinct `--measure-record` endpoint for one bounded, zero-generation
prefill. It uses a frozen task reader and returns only scalar measurements.
The ordinary reply protocol described below remains outside that qualification.
The original build/probe descriptions below retain their historical scope;
see the [task-reader qualification](task-reader.md) for the later fitted result.

This worker connects an explicitly imported reader to intermediate Qwen GGUF
activations. It runs in a private child process, loads one verified model blob,
generates a bounded answer, and returns scalar reader measurements. It does not
steer activations, train readers, fetch models, provide a service, or certify the
answer. A compatible calibrated reader must be supplied. The desktop keeps its
existing answer/schema validators as the admission boundary.

The worker is implemented and can be compiled; this delivery does not load a
model or execute inference. Successful protocol validation proves JSON handling
and local linking only. It does not prove the model loader, tensor callback,
numerical reader, or native answer path against the installed weights.

## Build and provenance

Run from the checkout root:

```sh
python3 research/representation/gguf/build.py
```

If the pinned source archive or CMake is absent, add `--fetch` and/or
`--bootstrap-cmake` explicitly. These fetch source and an output-local CMake
package; they do not download weights. All runtime/source/build caches are under
ignored `output/gguf-representation-build-2026-09-25`. Only the `llama` target is
built, with CPU execution, four build jobs, and tests/examples/tools/server/GPU
backends disabled. The portable `runtime/` directory contains the worker, four
ad hoc signed arm64 dylibs, licenses, and `build-manifest.json` with file hashes.

The public ABI and model graphs are pinned to
[`161755f29e415e2c33efe906e91843c068efd664`](https://github.com/ggml-org/llama.cpp/tree/161755f29e415e2c33efe906e91843c068efd664).
The exact source archive SHA256 is
`ea7b03494c2e9f24b5bcb6602c921fa413b868eb7f68fcf299eb6e84e361ea42`.
The manifest records hashes of every used public ABI header and both Qwen graph
sources. The authored `worker.cpp` and build recipe are hashed separately.

Installed Ollama 0.34.4 reports this llama.cpp revision, but its separately
linkable dylibs on this machine are x86_64. Its arm64 runtime is statically linked
inside the signed universal server. This worker therefore compiles its own
arm64 CPU dependency from the exact upstream revision; it neither extracts nor
patches the signed app. It does not include Ollama's compatibility loader patch.
Compatibility with the installed Qwen blobs remains an unexercised gate.

The [September 26 compatibility work](compatibility-and-qualification.md) adds
an opt-in, separately identified Qwen3.5 RoPE loader fix. Its single bounded
probe progressed to a second tensor-format mismatch and produced no residual.
The original runtime remains unchanged; live reader qualification remains open.

A subsequent opt-in `--qwen35-text-compat` build implements the official Ollama
base-text metadata/tensor conventions for the exact installed Qwen3.5 blob.
Its one bounded probe successfully extracted a finite 4096-component residual.
See the same [compatibility record](compatibility-and-qualification.md) for
resource usage, provenance, and the remaining qualification boundary. The
new backend has its own identity; it is not enabled in native assistance.

## Protocol

One bounded UTF-8 JSON object arrives on stdin, followed by EOF. Exactly one JSON
object is written to stdout. Runtime diagnostics go to stderr. Maximum request
size is 8 MiB; JSON depth is 32; duplicate keys are rejected.

Request schema: `archi-gguf-shadow-request/v1`. Required fields:

- `request_id`, `role`, `model_name`, `mode` (`shadow` only).
- `model_path` (absolute regular file), `model_digest` (Ollama manifest),
  `model_blob_digest` (actual complete GGUF bytes).
- `input`, `system`, `response_schema`, `prompt`, each with its corresponding
  `input_digest`, `system_digest`, `schema_digest`, `prompt_digest`.
- `reader_artifact_digest`, `basis_payload`, `basis_payload_digest`, and `basis`.
  The payload is an exact serialized copy of the basis. Its hash and parsed
  equality are verified. The imported artifact digest is a caller assertion;
  the native importer verifies actual artifact bytes before launching.
- `max_input_tokens` (1–8192), `max_new_tokens` (1–1024), `deadline_ms` (1–180000).

The caller formats the prompt with its pinned template. The worker adds neither
a BOS token nor a template; it parses explicit special tokens. It verifies all
component digests, the pinned template digest, and exact reconstruction of the
prompt from those components. Version one rejects any component containing `<|`
so untrusted data cannot insert ChatML role delimiters. This bounded input
subset fails closed rather than changing Hampton's canonical input bytes.
Greedy generation has no grammar constraint. Native JSON validation
must reject malformed or incomplete role output.

`basis` requires `namespace`, `model_digest`, `model_blob_digest`,
`tokenizer_digest` (equal to the entire GGUF blob digest), `template_digest`,
`backend_revision` (`llama.cpp:161755f29`), `precision` (`Q4_K_M`), `basis_digest`,
`reader_digest`, `calibration_digest`, and `layer` (`l_out-N`). Exactly one reader
is accepted: `names: [name]`, `directions: [[hidden values]]`, `center: [hidden
values]`, `score_offset: [value]`, `score_scale: [positive value]`. The direction
must have unit norm. These digests bind caller-supplied identities; they do not
authenticate calibration quality. The actual hidden dimension and layer bounds
are checked against the loaded model.

Response schema: `archi-gguf-shadow-result/v1`. Successful execution returns
`status: ok`, identity/hash echoes, scalar-only basis identity, generated `text`,
`output_digest`, `stop_reason` (`eos` or `token_limit`), `input_tokens`,
`output_tokens`, and `samples`. Only `eos` is an acceptable normal finish for
native use. Output count excludes the terminal EOG token. An incomplete output
remains unaccepted even if its text happens to parse as JSON.

Each sample contains `decode_index`, `token_position` (zero-based absolute input
or generated-token position), `layer`, `raw_scores: [value]`, and
`coordinates: [value]`. The callback reads the final token row of the selected
layer's `l_out-N` F32 residual. Prefill uses chunks of at most 256 tokens and
captures only the final prompt chunk, then each generated-token decode. The
sample describes the context that predicts the next token, not a correctness
score for that token. At most `max_new_tokens` samples are returned.

`raw = dot(activation - center, direction)` and
`coordinate = sigmoid((raw - score_offset) / score_scale)`. Coordinates are not
probabilities. The local row buffer is discarded; only scalars enter the reply.
`numeric_payload_digest` hashes nlohmann's sorted-key compact serialization of
`{directions,center,score_offset,score_scale}`. Native identity binding uses the
exact supplied `basis_payload_digest`, avoiding cross-language float formatting
assumptions.

Errors return `status: error` and an error message with a nonzero exit code.
SIGTERM/SIGINT and CPU abort callbacks cooperate with cancellation; a process
watchdog exits if the execution deadline exceeds its two-second teardown grace.
The native owner must also terminate and reap its child on cancellation/timeout.
The worker never shares a context or emits a result after a decode error. It
hashes and loads through the same open file descriptor and checks file size and
mtime around loading. Concurrent hostile in-place writes are outside this local
artifact ownership contract.

## Validation without model work

`archi-gguf-shadow --validate-only` validates the request, basis, limits,
and byte digests and returns `status: validated`. It does not open the model
path, load weights, construct a context, or decode. It cannot certify a reader
or predict whether a model will run.

```sh
python3 research/representation/gguf/protocol_checks.py \
  output/gguf-representation-build-2026-09-25/runtime/archi-gguf-shadow
```

The small check uses a deliberately synthetic two-dimensional basis and a
nonexistent model path. It covers a valid binding and malformed/budget/mode/
hash/duplicate-key failures. It is protocol evidence only.
