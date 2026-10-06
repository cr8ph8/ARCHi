# Evidence beside an ARCHi answer

Local document reading and selected knowledge-page answers expose **Sources for this reply** beside the answer in Chat, Work together, comparison lanes and the companion chat. Expand it to see each captured passage or authored interpretation. **Read captured text** shows the exact request snapshot, its version/range where available, and the declared origin carried from the reading library.

The three delivery labels have different meanings:

- **Prepared only:** the source was captured for the request, but dispatch to the reasoning client was not recorded for that ID.
- **Sent to local client:** the local reasoning client received this reference; the completed checked response did not cite it, or no completed response exists yet. This is not confirmation that a model server accepted the request.
- **Cited in checked reply:** the completed response cited an ID that was recorded as dispatched. This establishes reference membership, not that the passage supports the claim or that the answer helped.

An authored knowledge page remains an interpretation even after its user-review event. A passage with no declaration remains **Origin unknown**. Source declarations are not detected authorship. Failed, cancelled and pending replies never earn the cited label. Missing telemetry is reported as unavailable rather than inferred from the presence of an excerpt. Other references, such as earlier conversation, remain in Request details; they are not falsely mapped to a kept passage.

The captured text is ephemeral answer state. It is not a new memory store, journal field, model input or cloud route. Opening the disclosure does not save text, rate usefulness or train a model. Free-text attribution stays in the source owner and is excluded from this projection. Source changes still use the existing invalidation boundary; the view never silently resolves an old answer to a newer copy.

## Reviewed outcomes and method reuse

The existing method-selection path already ranks exact method versions by retained Helpful/correction outcomes, then refines equal-quality cohorts using comparable local usage. Lexical search keeps that order only for equal word-match scores. Selection remains explicit.

Quality evidence now reconciles request/provider ownership across the full supplied document journal before filtering a method or requirement set. Two different record IDs claiming one request/provider lane make the projection unavailable; neither contributes another Helpful observation or an advantage through recency. Exact duplicate copies of the same record are idempotent. Different provider lanes remain separate attempts. Existing corrections and undo semantics are retained.

This protects a runtime input to Hampton's adaptive selection. It does not measure causal improvement or establish cost per owner-accepted task. The journal schema/admission is unchanged: conflicting historical records remain inspectable and require separate recovery, rather than being silently rewritten. The method finder/history and revision-experience views disclose unavailable outcome history.

## Implementation and scope

`AssistantSourceContext` captures the already bounded local reading or knowledge context at request preparation. `AssistantSourceEvidence` joins that immutable context to the same lane's dispatch and terminal citation evidence. `AssistantSourceEvidenceView` is shared through the existing answer feedback surface. `HamptonMethodOutcomes` and `HamptonTaskWork` enforce the outcome-ownership boundary.

The focused checks exercise these contracts and in-process request ownership without model calls or puzzles. A build and installed startup do not establish new live-model performance. The earlier [source provenance guide](native-source-provenance.md) explains correction and parent-version handling.
