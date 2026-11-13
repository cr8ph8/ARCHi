# Continuity during transformation

ARCHi and the retained QiMon game source check a complete requested change at the existing owner before accepting its result. Preserving a valid identity and record shape is necessary, but a structurally valid result can still be the wrong action. These checks bind the intended effect separately from the candidate that implements it.

This is a classical software application of a lesson from Kuehnke et al., *Hardware-tailored logical Clifford circuits for stabilizer codes* ([journal](https://www.nature.com/articles/s41534-026-01404-x), [preprint](https://arxiv.org/abs/2505.20261)). Their work optimizes encoded Clifford operations under hardware constraints; particular flag constructions detect specified faults. Quantum circuit synthesis and fault tolerance remain distinct tasks. This repository implements no quantum hardware, Clifford compiler, or general fault-tolerance theorem.

## The contract

For a base state x, requested effect p, candidate x', and current authority G, acceptance requires all three relationships:

```text
I_G(x')                 protected invariants hold
R_p(x, x')              the candidate performs the requested effect
A_G(p, x, context)      the current owner permits the effect in this context
```

The existing owner establishes authority and freshness. The added guard checks the candidate's identity, history, scope and exact requested effect. Its failure can block a change; a passing guard cannot grant authority that the existing owner withheld. A flag detects a discrepancy. Recovery remains a separate supported operation.

The quantum distinction motivating this is that preserving a code space, U Pi U† = Pi, does not by itself establish the desired encoded action, U V = exp(i theta) V C. Binary symplectic agreement also omits Pauli signs. The classical transfer is to verify the intended actor, recipient and effect as well as structural validity; software authorization is not a quantum phase.

## Native companion body changes

`KinGrowthContinuity` is a pure value check called by `EvolutionStore` immediately before its existing body-record assignment. It covers Keep First Light, Return to Core Seed, and Resume First Light.

- Bind the origin, current revision, complete prior record, and requested body state.
- Bind an initial Keep to the exact reviewed proposal ID and its complete evidence reference.
- Preserve that ID and evidence when returning or resuming.
- Reject a valid record for a different individual, an unrequested body state, replaced evidence, an overwritten record, or an obsolete revision.

`CompanionStore` still decides whether the operation belongs to active KIN. Existing structural and lesson checks remain in place. The guard preserves a retained evidence reference; it does not renew the truth or availability of that evidence. Changes are session state until the existing explicit Save succeeds. No new identity owner, persistence schema or save file is introduced.

## Retained Journey and QiMon practice

The existing care, field-play, Relay Keep and practice Keep functions use a private `commitJourneyOperation` boundary. The owner captures the full pre-operation authority and exact intended event as immutable strings before reducing the action. It keeps a detached canonical base so a reducer cannot rewrite the snapshot it is checked against.

Eight checks must all pass:

| Check | Required relationship |
| --- | --- |
| Contract | Closed owner-created contract and plain, finite, non-cyclic data |
| Snapshot | The current base still matches the captured authority and projections |
| Identity | The full origin and core identity are preserved |
| History | The complete existing event prefix is unchanged and exactly one event is added |
| Requested effect | The new event exactly matches the requested action, receipt, session and time |
| Scope | Only fields permitted for this operation change; nested projections have closed shapes |
| Replay | The new event extends the verified prefix under the existing rules |
| Projection | The candidate's derived state agrees with that replay |

`FAIL` and `ERROR` both block the operation. The checker derives these results itself; there is no submitted PASS field or unchecked success override. Exact duplicate Relay/practice Keep retains its existing idempotent behavior before this one-event guard.

The replay check uses induction over the verified prefix. If P is already verified and the candidate is exactly P followed by e, checking e against P verifies that extension. The private runtime path reuses its already canonical base. The exported adversarial checker verifies the contract's base itself. No caller can submit an "already verified" boolean. Replay uses the production reducer; independent effect and allowed-field checks add coverage without claiming a second independent implementation.

| Operation | Permitted derived changes |
| --- | --- |
| Care | Care values and update time |
| Field play | Play count, bond, expression, affinities and update time |
| Relay Keep | Supported schema transition, update time and its completion receipt |
| Practice Keep | Supported schema transition, update time and its replay receipt |

All four preserve origin, prior history and core. Existing browser locks, cancellation, source checks and persistence remain the caller's responsibility. Care/field still support the existing clearly labeled session-only fallback; Relay/practice still require verified persistence outside QA. This guard does not create cross-tab atomic storage, a second game save, or a universal rollback mechanism.

## Story and gameplay requirements

A continuing QiMon can learn, change preferences and choose another form while retaining attributable identity and history. Equipment changes the supported means of action. A familiar appearance cannot stand in for a verified consequence. A pause should isolate the dependent action and leave its reason visible; a correction retains the record it corrects and names unresolved gaps.

ARCHi retains identity, preferences and authorized device-session ownership. QiMon retains ownership of fictional quests, inventory, abilities, relationships and consequences. A fictional reward does not grant device authority. A real observation becomes a game consequence only through a declared supported rule. No body, renderer or adapter becomes a new memory or canon authority.

The current Unity project remains a disconnected preview. Its presence is not evidence that the authored QiMon game or a physical handoff has been installed. This change does not enable the paused native Habitat/Arena.

## Future whole-plan optimization

Any future optimizer must search only among plans that satisfy the same effect contract, authority, dependency snapshot and relevant intermediate limits. Its cost can include operations, latency, resource use and recovery cost. It may not remove required checks, change the intended effect, or acquire new permissions to make a plan cheaper. This change supplies postconditions for bounded current operations; it does not add an optimizer or claim lower failure rates.

Evaluate both accepted outcome quality and coverage. If q is the fraction accepted and e is the invalid fraction among accepted attempts, report both; e is undefined when q is zero. Distinct validators may share failures, so do not assume their false-pass probabilities multiply. A demote-only check can reduce absolute invalid admissions while increasing the invalid fraction of the smaller accepted set. Comparison requires fixed tasks, fault labels and denominators.

## Validation and installation

See [validation and native handoff](CONTINUITY_VALIDATION.md) for executed checks and remaining qualification. Source changes, a successful portable test and an installed native application are separate evidence states.
