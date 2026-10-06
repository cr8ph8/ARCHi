# Reviewed methods and local resource use

Introduced 25 September 2026. This native integration connects the saved document-method library to Token Steward's measured local invocations. It orders eligible method options without generating a reply. Choosing and confirming a method remains explicit.

Status clarification, 29 September 2026: the numerical-domain and representation-reader gaps recorded at this increment have since narrowed. The current boundaries below link the implemented consumers; the original accounting mechanism and historical verification remain unchanged. [Explicit method selection](native-method-finder.md) now owns choosing and confirming a saved method; resource ordering does not select one automatically.

## Mechanism

The established domain-specific critic remains primary:

\[
p_m=\frac{h_m+1}{h_m+c_m+2}.
\]

Here \(h_m\) counts this exact method version's checked, applied and currently reviewed Helpful provider-lane results; \(c_m\) counts its corrections or withdrawals. This Beta(1,1) statistic is a suggestion rule, not a calibrated probability of semantic correctness. Availability and current requirements still precede it.

For a whole group tied on that statistic, fully accounted comparable local work can supply a second criterion:

\[
T_m=\sum_{u\in U_m}\sum_{a\in A_u}
\bigl(t^{\rm input}_a+t^{\rm output}_a\bigr),
\qquad C_m=\frac{T_m}{h_m},\quad h_m>0.
\]

Lower observed tokens per Helpful result comes first. The numerator includes all retained uses of that exact version, with failed attempts, recovery calls and context preparation. Cache and reasoning counts are already included in input/output; they are not added again. Withdrawn approval removes support from the denominator without erasing incurred usage. Cross-products compare the ratios exactly without integer overflow or rounded display values influencing the order.

This is a new, explicitly authored extension of the existing Hampton resource-allocation path. It connects reviewed outcomes and measured resource cost to a real reuse decision. It does not instantiate the separate latent quotient controller, its potential function, or a physical energy law.

## Evidence and eligibility

`HamptonMethodResourceOutcomes` joins existing owners by exact method version, document record, request and Qwen lane. It creates no additional journal. A group can be reordered only when every member has complete qualifying local measurements and the same multiset of source digests, selected ranges, requirements and model/role identities. Model identity includes its native artifact digest, not just its mutable name. A wholly local closed lane and at least one verified Helpful result are required.

Missing costs, legacy model identities, conflicting copies, active work, mixed external delivery or incompatible workloads preserve the established order for the entire tied group. This whole-group rule avoids a cyclic pairwise comparator around unknown data. Overflow or malformed measurements are unavailable rather than zero cost.

Token Steward now retains an optional model artifact digest on new native observations. Old records stay readable. Replaying an old receipt does not enrich or overwrite its missing identity. Same-identity observations with different retained digests conflict. The digest identifies the observed model artifact; the local journal is not a cryptographic attestation service.

The saved-method details show measured local usage or an explicit unavailable state. The user still selects a method; Apply, feedback, permissions, model routing, resource ceilings and companion development retain their existing owners. Neither selection nor a low token count awards skill or growth.

## Research placement and limits

This is resource-aware task learning: experience can change which already available method is suggested. It is an observed-token heuristic on a matched retained workload, not a controlled causal estimate of method efficiency. Authored instructions, other context and hardware can still differ. It does not promise savings, estimate dollars, compare providers, or replace quality checks with cost.

[Cowsik et al., *Self-Play Pretraining with Zero Data*, v1](https://arxiv.org/abs/2609.30063v1) supplies a separate research direction: learning to generate useful training experience. Its gradient/optimizer/history reward requires a training environment beyond the current inference client. No self-play training or generated practice is enabled here. The retained local research note records its equations, results and limits separately.

Declared numerical adapters now exist for [document revision](native-numerical-adaptation.md), [document reading](native-numerical-reading.md), [interactive ARC3](native-numerical-arc3.md) and [Arena advice](native-arena-advice.md), each with domain-specific measurements, targets, gains and coupling. These operational coordinates are not relabeled IQ/EQ/AQ, and their implementation does not establish general calibrated transfer or a learned latent quotient mapping.

The separately qualified synthetic record-field reader also has an installed [native Record lookup consumer](native-record-lookup.md). Earlier failed readers remain failed. Ordinary-chat measurement, representation steering and useful transfer to everyday records remain unqualified; another Qwen installation does not provide that evidence. See the [current representation guide](native-qwen-representation.md) for the dated attempts and exact scope.

## Historical verification scope: 25 September 2026 increment

Focused synthetic checks cover accounting completeness, retry cost, exact model identity, review reversals, unequal Helpful denominators and stable ordering with unknown evidence. Build, installed binary, preserved profile and publication are recorded in the increment's delivery receipt. No puzzle campaign, paid API request, model generation or empirical savings comparison is part of this increment.

Implementation: `HamptonMethodResourceOutcomes.swift`, `HamptonTaskWork.swift`, `DocumentProcedureViews.swift` and `TokenSteward.swift` in the existing native application.
