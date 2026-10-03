# Qwen3.5 compatibility and reader qualification

## Subsequent full text adapter, September 26

The separately built `llama.cpp:161755f29+archi-qwen35-text-v1` adapter now
loads the exact installed Qwen3.5:9b blob and extracts a finite prompt-final
residual. One bounded probe acquired 4096 finite, nonzero components at
`l_out-15`, from 124 input tokens, with no generated tokens. It took 15.55
seconds and peaked at 5,776,080,896 resident bytes. This is extraction evidence;
no reader was fitted or qualified and no native backend was switched.

The adapter follows the official
[Ollama v0.34.4 compatibility handler](https://github.com/ollama/ollama/blob/b2da9e468af2479058ae18c6d908ed29de410684/llama/compat/llama-ollama-compat.cpp):
collapse the per-layer KV-head metadata to four, pad RoPE sections, and alias
`ssm_dt` to `ssm_dt.bias` with unchanged bytes and dimensions. It explicitly
excludes the 441 vision and 15 MTP tensors from the base-text index. MTP is
disabled, as it already was in this worker; the upstream base graph does not
execute MTP. The remaining 427 base-text tensors retain upstream shape and
strict count validation. Unknown text tensors are not ignored.

The worker pins the complete original GGUF SHA256
`dec52a44569a2a25341c4e4d3fee25846eed4f6f0b936278e3a3c900bb99d37c`.
The header adapter also checks the exact published metadata and inventory before
changing any in-memory names. It rejects altered V-head ordering, hybrid layout,
tensor inventory, ambiguous aliases, native NextN metadata, or MTP enablement.
It does not rewrite the source file or transform tensor values. The original
runtime and the earlier RoPE-only experimental runtime are preserved.

Build this opt-in adapter in a fresh output directory with
`build.py --qwen35-text-compat --output <fresh-checkout-output-directory>` and
the existing pinned source archive/CMake. Its source patch is hash-bound to
the pinned upstream loader. `text_compat_checks.py` exercises the actual C++
helper using metadata-only tensors; it never allocates model weights.

The new receipt and official-source provenance are in
`output/hampton-qwen-compatibility-2026-09-26/`. Thirteen adapter/source-guard
checks and fifteen protocol checks passed before the one finite-residual probe.
The initial failures below remain historical evidence. Fresh reader
qualification and native admission are still required; finite extraction is
not independent behavioral equivalence or response-quality evidence.

## Earlier RoPE-only increment

The installed Ollama Qwen3.5:9b blob and the pinned upstream llama.cpp loader
use different container conventions. The September 26 probe resolves the first
loader error but does **not** establish model compatibility or a qualified reader.

## Delivered compatibility change

`build.py --qwen35-mrope-compat` applies one hash-checked source patch to a new
output directory. It accepts the observed three RoPE sections `[11,11,10]` as
`[11,11,10,0]`. Four-section inputs keep their original values; other
three-section layouts and unexpected lengths are rejected. The original GGUF
is never rewritten. This follows the pinned source's
`conversion/base.py` padding rule and `conversion/qwen.py` Qwen3.5 default.

The patched worker has the distinct identity
`llama.cpp:161755f29+archi-qwen35-mrope-v1`. Existing default builds retain
`llama.cpp:161755f29`. Requests/readers for either identity are rejected by the
other worker. Native admission still pins the original identity; this change
does not switch native execution or enable measurements.

The model-free checks compile the actual normalization helper, check rejection
of malformed layouts and altered upstream source, and validate both workers'
protocol behavior. These checks establish neither tensor compatibility nor
reader quality.

## Measured result, September 26

One bounded extraction attempt used the original first **fit** example from
the failed September 25 Qwen3.5 run. The budget was one prefill, 512 input
tokens, zero generated tokens, a 120-second worker deadline, and a 125-second
parent deadline. No held-out sample or reader fitting was used.

The attempt ended after approximately 2.97 seconds, with a peak child resident
size of 93,274,112 bytes. It passed the former RoPE hyperparameter failure and
then failed loading `blk.0.ssm_dt.bias`. It returned no activation vector.

A read-only header inspection identifies the remaining known mismatches:

- All 24 recurrent layers use `blk.N.ssm_dt`, while this loader expects
  `blk.N.ssm_dt.bias`.
- The GGUF contains 441 vision and 15 MTP tensors in addition to text tensors.
  The upstream text model's strict tensor-count check requires an explicit,
  validated handling route for those components.

The header reports `qwen35.ssm.v_head_reordered = true`. That metadata is not
proof that an alias/skip patch would preserve the intended graph or logits.
No tensor aliasing, tensor dropping, or installed-runtime change was performed.

Evidence is under
`output/hampton-repe-completion-2026-09-26/`: `load-probe/receipt.json`,
`load-probe/worker.log`, `qwen35-preflight.json`, and `delivery-receipt.json`.
`inspect_gguf.py` can identify these container mismatches without model loading
or reading tensor data. A clean preflight would still require a live probe.

## Qualification route

1. Establish complete model compatibility. Either retain the already exercised
   Qwen3:8b adapter, or separately implement and validate a Qwen3.5 text adapter
   with complete tensor semantics and explicit handling of auxiliary components.
   A successful load is followed by finite residual extraction and independent
   behavioral comparison. Keep each patched backend identity distinct.
2. Use the already disclosed September 25 dataset only for development and
   regression diagnosis. Its Qwen3:8b reader scored 4/8 on held-out examples
   with negative calibration separation. The failed reader remains unqualified.
   Do not reuse those examples as an untouched holdout or retry until they pass.
3. Freeze a new synthetic corpus and split before acquisition. Permit design
   selection only within development partitions. Freeze the selected model,
   layer, fitting algorithm, normalization, template, scope, corpus digest,
   runtime hashes, and numerical source before evaluating a fresh final holdout.
4. Keep the existing acceptance thresholds: positive calibration separation,
   every calibration and final holdout example correctly signed, and signed
   standardized margin at least 0.1. Failure emits a report and no reader.
   `calibrate.py` now binds the selected backend consistently through plan,
   runtime acquisition, and emitted reader, but its built-in historical corpus
   is not a new qualification dataset.
5. A passing fresh experiment may admit only its documented prompt-final
   synthetic field-support scope. Native import/admission must validate the
   exact backend and report bindings before a measured request is tried.
   Ordinary assistance, generated-token trajectories, truth, and steering each
   remain outside that qualification. No threshold or scope is relaxed here.

No qualified reader, measured native reply, activation steering, or general
response-quality improvement is established by this delivery.
