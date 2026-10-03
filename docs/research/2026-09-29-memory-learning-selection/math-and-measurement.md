# Mathematics and measurement boundaries

29 September 2026. Paper equations and engineering reconstructions are labeled separately. These are selected mechanisms for implementation decisions, not a transcription of every equation or an independent reproduction.

## Linked propagation

WFM §§3.1–3.2 represents entities, relations and passages together. Its equations 4–5 aggregate relation-bearing neighbor messages:

\[
m_v=\sum_{(r,u):u\in\mathcal N(v)}\alpha(v,r,u)(W_vh_u+e_r),
\qquad \alpha=\operatorname{softmax}_{(r,u)}\pi(v,r,u).
\]

The displayed score has no explicit query argument; query dependence also enters through neighborhood selection. This distinction matters when designing a query-conditioned implementation. These learned weights are not evidence-confidence scores. See [primary text](https://arxiv.org/html/2609.18182v1#S3).

**Proposed ARCHi rule, not WFM mathematics:** a candidate relation can contribute context only when its reviewed revision and both exact endpoints are current:

\[
\operatorname{Eligible}(e)=\operatorname{Reviewed}(e)\land
\operatorname{Current}(e)\land\operatorname{Current}(e.from)\land
\operatorname{Current}(e.to)\land\operatorname{AuthorizedContext}(e).
\]

This rule establishes eligibility to retrieve a declared relationship, not its truth. Preserve contradiction and provenance in the returned path. Do not interpret graph degree or duplicate paraphrases as independent corroboration.

## Recursive distillation

A simplified restatement of DCE's token-level guidance uses the student distribution and a detached privileged teacher:

\[
p_{k,t}(v)=p_{\theta_k}(v\mid x,h_t),\qquad
q_{k,t}(v)=\operatorname{stopgrad}p_{\theta_k}(v\mid x,g,h_t),
\]
\[
\mathcal L_G=\frac1T\sum_tD_{KL}(q_{k,t}\Vert p_{k,t}).
\]

Here \(g\) is privileged reference information. Exact prompts, masks and batching are omitted. SRCL supplies filtered shorter rewrite targets; endpoint correctness does not prove every intermediate step. See [paper §3 and appendices](https://arxiv.org/html/2609.30652v1).

**Proposed checkpoint decision:** let \(\hat\theta\) be a training candidate and \(E\) independent evidence tied to that candidate's hash. Promotion requires a separate, declared acceptance decision; otherwise the previous admitted checkpoint remains. A change to Hampton's runtime quotient vector \(\mathbf q\), retrieved memory or method ranking is not a change to model parameters \(\theta\).

Reported Average@12 averages sampled answer correctness; it is not pass@12. Report training compute, generated tokens, retained quality and source coverage separately. Shorter output is useful only if it preserves the task's required content and verified outcome.

## Bounded selection

**Interface reconstruction, not disclosed OpenAI internals:**

\[
\hat a=D_\theta(x,q,\mathcal A),\qquad \hat a\in\mathcal A.
\]

Membership, correctness and authorization are separate predicates. Include clarification/abstention where appropriate. Validate the selected label against the exact request's allowed set, freshness and policy before dispatch. Softmax, KL, thresholds and Hampton potential/force equations are not published Decisions API internals merely because they could describe a selector. [Official announcement](https://openai.com/index/devday-2026-recap/). Schema compliance also does not imply correctness in [OpenAI's Structured Outputs guidance](https://developers.openai.com/api/docs/guides/structured-outputs#handling-mistakes).

## Attention and actual cost

DA restricts the positions visible to attention. A standard masked-attention restatement is:

\[
o_t=\operatorname{softmax}\left(q_tK_{S_t}^{\top}/\sqrt d\right)V_{S_t},
\qquad C=\sum_t|S_t|.
\]

\(C\) counts repeatedly attended positions, not output tokens or billed API tokens. Full KV storage remains resident in the described mechanism. Model-generated tags only alter computation when the serving runtime implements their masks. [Paper §2 and §4–5](https://arxiv.org/html/2609.02737v1).

**ARCHi measurement proposal:** retain separate retrieval, prefill, decode and coordination durations; input/output tokens; model/runtime identity; and supported task outcome. Never label a byte-budget reduction as measured KV savings. A fresh permitted context is the security boundary: masking an earlier token cannot erase its prior influence on cached representations.

The immediate engineering target is useful, attributable context within a budget. Improved research metrics, a changed quotient state and a successful user task remain different observations.
