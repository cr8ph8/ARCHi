# Directional learning, calibration and provider continuity

Reviewed 2 October 2026. This intake checks four supplied conversation previews against primary sources and the current ARCHi source. It records integration decisions, not an installed upgrade or a reproduction of the papers. No model calls, puzzles, training, application installation or profile changes were performed. File hashes and source locations are recorded in [sources.json](sources.json).

## Where this belongs in Hampton's stack

Hampton's scope includes representation, reasoning, coupled state updates, resource allocation, memory, learning, coordination and embodiment. These references contribute to representation, learning, inference and evidence handling; they do not replace that stack with an output filter.

The existing update notation remains

\[
Q_i(t+1)=Q_i(t)+\Delta Q_i(t).
\]

Here a Hampton quotient is a specified state coordinate. It is not necessarily a ratio or a mathematical quotient space. Writing another method as an additive update establishes an algebraic correspondence; it does not establish matching coordinate definitions, feedback, memory, stability conditions or patent coverage. Current native domain coordinates, archived controller coordinates and neural hidden states must retain their separate definitions.

| Reference | Intended owner | Decision for ARCHi |
|---|---|---|
| RIDE | A future model-training pipeline, with candidate checkpoint review | Retain a training specification. Do not represent the ordinary Qwen adapter as a trainer. |
| LoopCD | A future inference adapter exposing recurrent hidden states or logits | Require an explicitly compatible execution path before offering a decoding option. |
| Semantic calibration | Reader qualification, evaluation records and answer-evidence presentation | Keep measured confidence tied to task, model and decoding conditions; never turn it into permission. |
| Encrypted reasoning | Provider adapters, conversation ownership, exports and diagnostics | Keep opaque continuation material outside shared text, memory, lessons and fallback payloads. |

## 1. RIDE: learn from a measured representation change

For a base model \(B\), its RL teacher \(T\), and student \(S\), all processing the same student-generated prefix:

\[
\Delta_t^{(\ell)}=h_{T,t}^{(\ell)}-h_{B,t}^{(\ell)},\qquad
h_t^{*(\ell)}=h_{T,t}^{(\ell)}+(\lambda-1)\Delta_t^{(\ell)}.
\]

The student minimizes masked, normalized squared distance to the stop-gradient target. At \(\lambda=1\), it matches the teacher; larger values extrapolate. Conditional on the trajectory, the equivalent directional objective is

\[
(\lambda-1)\langle h-h_T,\Delta\rangle-\tfrac12\|h-h_T\|^2.
\]

This combines directional drive with a restoring penalty. It does not make every component of the residual beneficial. Within each experimental triple, architecture, tokenizer and representation origin align; the paper does not license subtracting unrelated models' activations. [Primary paper, §§3–5](https://arxiv.org/html/2609.36484v1).

The [official repository](https://github.com/xixixixixxxx/RIDE) currently supplies an overview, but no training code, evaluation scripts or checkpoints. The controller kit and 48 checks mentioned in the supplied chat were not recovered or rerun in this intake.

**Our integration decision:** a future candidate needs pinned legitimate checkpoints, aligned token/layer positions, separate training and evaluation data, a bounded update policy, and an attributable checkpoint receipt. Native Q2E outcome records can evaluate downstream usefulness; their authored domain coefficients are not substitutes for neural training. Retain a known-good serving checkpoint until a candidate qualifies.

## 2. LoopCD: change decoding within a recurrent model

The requested paper's two forms are

\[
h'=h_R+\omega(h_R-h_1),\qquad
z'=\operatorname{lm\_head}(\operatorname{coda}(h')),
\]

or

\[
z'=z_R+\omega(z_R-z_1).
\]

These operate during inference. Hidden-state guidance uses one output pass; logit guidance adds another. Nonlinear coda operations mean the two forms are not generally equivalent. The maximum 48.2% saving is an analytical forward-FLOP estimate for Huginn with a 512-token prefill. Reduced-depth quality experiments cover multiple-choice tasks, not ARCHi workflows or measured API cost. [Primary paper, §3 and Appendix D](https://arxiv.org/html/2610.02185v1).

No official implementation link for this paper was located. A repository bearing the same name belongs to [a different LoopCD paper, 2609.24196](https://arxiv.org/abs/2609.24196); it must not be presented as the implementation of 2610.02185.

**Our integration decision:** require access to the actual early/final recurrent states and model-specific output path. Ordinary Qwen text output and the read-only GGUF reader do not supply this capability. A future adapter must report executed depth and measured latency separately from estimated FLOPs. Changing decoding also creates a new calibration configuration.

## 3. Semantic calibration: measure meaning, not confident wording

In explanatory notation, let \(B_x(y)\) assign an answer to a semantic class:

\[
\pi_x(k)=\sum_{y:B_x(y)=k}p_\theta(y\mid x),\quad
\hat k=\arg\max_k\pi_x(k),\quad c(x)=\max_k\pi_x(k).
\]

Calibration asks whether correctness frequency matches the assigned confidence:

\[
\Pr[\hat k(X)=k^*(X)\mid c(X)=s]=s.
\]

The paper studies sampling-based semantic calibration and conditions under which pretraining can produce it. Post-training or chain-of-thought can disrupt the mechanism; that is not a proof that RLHF alone causes hallucinations or that every base model is calibrated. [Primary paper, §§2–4](https://arxiv.org/html/2511.04869v1).

**Our integration decision:** preserve model digest, prompt mode, temperature, task scope, semantic-class rule and reference-answer provenance with any calibration result. Agreement among samples is not external verification. A changed checkpoint or decoding method requires fresh qualification for its intended scope. Do not add repeated sampling to every chat or relabel a mechanical check as a truth probability.

## 4. Opaque reasoning: encryption does not grant reuse authority

The reported failure is misuse of provider-side decryption and cross-context compatibility, rather than a weaker model breaking cryptography. Opaque continuation artifacts can still contain sensitive context. The paper discusses context binding and limiting replay. [Primary paper, §5 and Appendix A](https://arxiv.org/html/2608.09867v1).

**Our integration decision:** if ARCHi later needs opaque continuation, use a dedicated provider-owned type with account, session, model/compatibility policy, endpoint, format version and expiry bindings. Do not merge it into user-visible text, source nodes, learned methods, training data or generic fallback. Exclude its bytes from routine logs and exports. Local metadata checks do not prove that a provider enforces cryptographic binding. This review does not assert the current patch state of every provider or host, and performs no trace extraction.

## Current source connections and limits

Paths below are relative to the repository root. Line numbers and hashes describe this checkout on the review date, not the installed binary.

| Source | Observed behavior | Relevant boundary |
|---|---|---|
| `desktop/Sources/ARCHiDesktop/HamptonNumericalDynamics.swift:74` | Clipped, norm-capped updates with potential-based backtracking | Native numerical control, not RIDE training or LoopCD decoding |
| `desktop/Sources/ARCHiDesktop/HamptonQ2EController.swift:52` | Admitted domain observations and authored coefficients drive adaptation | Neither model confidence nor a universal intelligence score |
| `desktop/Sources/ARCHiDesktop/QwenAssistant.swift:33` | Ordinary Qwen is output-only; request disables thinking; parser rejects unexpected thinking | No access to recurrent hidden-state control through this adapter |
| `desktop/Sources/ARCHiDesktop/GGUFRepresentationClient.swift:15` | Separate read-only activation measurement client | Measurements do not perform decoding interventions |
| `desktop/Sources/ARCHiDesktop/GGUFReaderArtifact.swift:33` | `canMeasureGeneralReplies` is false | A synthetic support reader exists; general-answer calibration remains unavailable |
| `desktop/Sources/ARCHiDesktop/CompanionStore.swift:2907` | Ordinary reply measurement cannot be enabled without that qualification | Do not remove the guard simply because Qwen is installed |
| `desktop/Sources/ARCHiDesktop/AssistantConversation.swift:4` | Bounded, in-memory question/answer continuity | No new cross-provider opaque-payload store is needed |
| `desktop/Sources/ARCHiDesktop/AssistantReplyStream.swift:67` | Non-`agentMessage` completion items are ignored | Current visible-answer handling is not evidence of hidden-trace retention |
| `desktop/Sources/ARCHiDesktop/CompanionStore.swift:3172` | Fallback removes local lessons, personal context and conversation | Preserve this separation in any future provider feature |
| `desktop/Sources/ARCHiDesktop/HamptonProposalValidation.swift:17` | Typed proposal validation explicitly does not establish factual accuracy | Valid structure, factual support, calibrated uncertainty and authority stay separate |

The narrow reader corrects historical descriptions saying that all activation reading is missing. It does not justify claiming general reply measurement is active. See [native Qwen representation](../../native-qwen-representation.md) and [the retained Hampton status audit](../../hampton-work-status-2026-09-30.md) for their separately dated evidence.

## Next implementation sequence

1. **Improve everyday proposal fidelity through the existing document owner.** The retained [30 September receipt](../../accountability/evidence/r30-paste-intake-2026-09-30.json) records changed numeric literals and an omitted limitation in one Qwen revision; Apply remained blocked. Preserve explicit constraints and source caveats before claiming a useful learned method. This is the immediate observed product failure, not a hypothetical benchmark gap.
2. **Make provider-continuity boundaries explicit in the existing adapters.** Add a typed opaque-data boundary only if a real provider integration needs it. Focus acceptance on absence from text persistence, memory, export and fallback, plus cancellation/session mismatch. No second broker or memory store.
3. **Qualify one useful representation measurement in its actual task.** Reuse the existing reader report and exact identity bindings. A held-out support measurement can inform inspection; only attributable observed outcomes can support method learning. Any general-answer extension needs its own evidence and UI wording.
4. **Then evaluate training or recurrent decoding as separately identified candidates.** RIDE changes weights; LoopCD changes inference. Neither should silently replace Qwen or inherit an old reader's qualification. Use comparable real task outcomes, resource costs and a rollback checkpoint before adoption.

These are proposed implementation steps. This intake changes documentation only. It does not establish paper reproduction, improvement in Hampton's equations, patent validity/infringement, release readiness, or new installed capability.
