# Native memory correction and learning dependencies

ARCHi's document answers now carry content-minimal derivation links in the existing Token Steward journal. When a user marks an answer **Needs correction**, its retained generated conversation is retired, its usefulness credit is removed from the current development review, and dependent reading answers stop supplying positive evidence. The visible answer and accounting history remain available for review. Explicitly kept lessons and the companion's chosen body remain under their existing owners.

This implements the supplied Hampton Stack R2 L07 / Milestone 2 correction path for ordinary document reading. It does not depend on an ARC puzzle, a cloud provider, model retraining, or a second memory database.

## Runtime connection

1. `CompanionStore` captures request identities alongside temporary local conversation. For document readings, `DocumentReadingTrace.conversationRequestIDs` retains those dependencies before dispatch.
2. `TokenSteward` requires parent requests to be earlier completed local reading answers. Missing parents, duplicate or invalid identities, oversized ancestry and cycles cannot be admitted. Older records decode with absent ancestry; historical links are not invented.
3. `HamptonMemoryDependencies` reads the latest specific reading review and traverses its downstream request edges. Generic Useful feedback cannot replace a specific negative reading review.
4. The native conversation owner reloads the journal before consuming context and rechecks before dispatch and response admission. A correction from another journal writer therefore invalidates the retained continuation. Result recording checks parent validity within its transaction.
5. The reading outcome projection withdraws dependent observations from the next strategy decision without fabricating additional negative judgments. Evolution removes affected usefulness receipts and pending proposals. The same exclusions are reapplied when loading a previously saved evolution state.

The journal stores request identities and existing digests, not duplicated prompts, source text or answers. Temporary ancestry is limited to 128 request identities; ARCHi starts fresh conversation context at that boundary. The source-span bank contains user/document text, so a judgment about generated output does not erase that input history.

## Operational definition

Let `C` be the requests whose latest specific reading review is negative, and let `(u,v)` mean that answer `v` consumed generated context derived from answer `u`:

```
I_0 = C
I_(k+1) = I_k union { v | exists u in I_k with (u,v) }
I = the fixed point of this traversal
```

Requests in `I` are ineligible for current development credit. Direct corrections remain attributable negative reviews; descendants are withdrawn evidence, not new negative observations. Positive reading evidence is recomputed from eligible owner records. Historical costs remain incurred costs.

Reversing a reading review to Helpful changes the current evidence projection. It does not restore an old temporary conversation or automatically restore removed development credit. Development withdrawal uses the retained correction history, so an older saved usefulness receipt cannot reappear after a reversal and reload. A fresh answer and a new explicit usefulness action are required for development credit.

## Scope and evidence

Focused in-process checks exercise real native owners with deterministic role-client fixtures. They establish correction propagation and persistence behavior, not improved language-model accuracy or validation of a universal intelligence theory. No puzzle campaign, model generation, paid API call or broad test suite is required for this increment.

This is one installed memory/development dependency path. It is not a complete universal memory graph, automatic procedure induction, the manuscript's scalar MQ recurrence, a calibrated RepE reader, or measured transfer across every development channel. Those mechanisms retain their separate definitions and qualification requirements. The supplied patent manuscript is an engineering source; this implementation makes no claim about patent validity or claim satisfaction.
