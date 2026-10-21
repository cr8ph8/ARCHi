# OO-Harness research and hardening design

Prepared 21 October 2026. This note distinguishes published results, the original ARCHi pilot, and proposed experiments. It records no benchmark run or improvement in ARCHi task quality.

## Research basis

[Li et al., Object-Oriented Harness, v1](https://arxiv.org/html/2610.28380v1), sections 3-5: executable subclasses evolve on discovery clusters; a router selects using task and base-trajectory evidence. Executor weights and deployed lessons/code remain fixed. The reported maximum gain is 15.79 percentage points. Routing and inheritance ablations support their design, but do not prove reliability. Reported trajectory steps exclude auxiliary rollouts and selection calls.

The published selection equation is:

$$H^\star=\rho\bigl(t,\omega(t),\{H_0\}\cup\{H_c\}_{c\in\mathcal C},\mathcal L_\rho\bigr).$$

Here $t$ denotes a task, $\omega(t)$ its observable base execution, $H_0$ the base, $H_c$ cluster specialists and $\mathcal L_\rho$ routing lessons. Candidate acceptance requires a strict target-cluster score improvement and benchmark-specific checks; it is not a global no-regression theorem. Appendix A.6's 0.7 applicability confidence is self-reported, not a calibrated success probability.

[Wang et al., Rethinking the Evaluation of Harness Evolution for Agents, v4](https://arxiv.org/abs/2607.12227v4) identifies benchmark reuse and unmatched search budgets as evaluation problems. Its Terminal-Bench results find limited generalization and no consistent advantage over simple search; its long-horizon game experiments are more favorable. That motivates matched budgets and unseen task families, rather than assuming harness evolution is universally superior.

[Lee et al., Meta-Harness](https://arxiv.org/abs/2603.28052) searches harness code using previous candidate source, scores and execution records. It is a useful global-harness comparison, separate from hierarchical specialist selection.

## Our analytical model, not an equation claimed by those papers

Define $s$ as an admissible observation of a task and its execution. A fixed specialist catalogue is $\mathcal H$. Let $a=\rho(s)\in\mathcal H$ or abstain to the existing base. Selection is evidence; it does not grant a capability.

For an experiment, an economical objective is:

$$J(\rho,\mathcal H)=\mathbb E[R(s,a)-\lambda C(s,a)].$$

$R$ is independently verified task reward. $C$ includes the first base execution, routing, reruns, verification, training amortization and failed calls. Convert tokens, latency and money using declared weights instead of silently mixing units. Also report each measure separately.

Protected-state requirements belong in an admissibility predicate $A(x,p)$, evaluated by the existing owner against current state $x$ and the exact completed proposal $p$:

$$\operatorname{MayExecute}(x,p)\Rightarrow A(x,p)=1.$$

This is a required contract for future execution, not a property established by the current observer. The literal false authority flags and lack of executor make the current pilot incapable of exercising this path through its API. They do not protect an app that chooses to execute arbitrary imported code in the same process.

Target-cluster improvement need not improve deployment utility:

$$S_c(H')>S_c(H_c)\;\not\Rightarrow\;J(\rho',\mathcal H')>J(\rho,\mathcal H).$$

To see the failure, consider a hypothetical ten-task cluster where the new specialist solves one extra task but costs an extra call on every task. A router that mistakenly sends 100 unrelated tasks to that specialist can erase the gain. The example is illustrative arithmetic, not an observed ARCHi result.

## Why inheritance cannot own the enforcement boundary

A child can override a method without calling its parent. Consequently inherited checks are reusable implementation, not an authority guarantee. The prototype demonstrates check composition with `super()` in reviewed classes; it does not load generated subclasses. A future optimizer must submit candidate code into an isolated process with no protected stores or provider credentials. Native checks must remain outside the code it may edit.

Before importing candidate code, a trusted loader must verify a reviewed source identity. The candidate cannot edit its evaluator, labels, policy, audit owner, pins or promotion conditions. Mutable helpers are part of the candidate's identity. Runtime flags and signed metadata cannot rescue an unrestricted same-user process that can overwrite the enforcement code or inspect its credentials.

## Proposed experiment; not yet run

Use authorized synthetic or de-identified task fixtures with explicit source provenance, exact model revisions and unchanged graders. Separate discovery, validation and sealed final test by task family and source lineage; grouping should prevent lightly rewritten copies of one task from crossing splits. Candidate generation sees only discovery feedback. Select a final catalogue on validation, then evaluate the sealed test once. Repeated test inspection converts that test into development data and requires a new final test.

Compare five systems:

1. Existing base and its deterministic routing/eligibility owner.
2. Base with simple retry or parallel sampling, including selection overhead.
3. One globally optimized harness.
4. Flat specialists under the same router and budget.
5. Inherited specialists under that router and budget.

Hold the executor, input representation, graders and candidate opportunity set fixed where possible. Run a task-only versus task-plus-execution routing ablation on the same frozen catalogue. Separately test whether the inherited system benefits from its representation or merely received more search. The checked-in fixtures do not qualify any of these systems.

Predeclare strict completion, per-family regression limits, total cost and latency budgets, and admissibility conditions. Preserve all tasks in the denominator, including abstentions, errors, missing artifacts, unavailable services and timeouts. Record full initial and repeated execution cost. Keep expert allocation, requested clarification and permission eligibility as distinct questions.

For paired task outcomes let $d_i=R_i^{candidate}-R_i^{base}$. Report the mean paired difference, discordant success/failure counts and a task-family-aware confidence interval. Repeated executions of one task are not independent new tasks. A lower confidence bound above a predeclared practical threshold is stronger evidence than a raw best-of-search score. Report all inspected candidates and model/evaluator versions.

Zero observed violations is not proof of impossibility. Under an independent fixed-policy Bernoulli model, after $n$ trials with zero failures the one-sided 95% upper bound is:

$$p_{upper}=1-0.05^{1/n}.$$

At $n=100$ this is about 2.95%, not zero. Shared tasks, adaptive selection and correlated failures break that simple interpretation. Structural enforcement tests and sampled reliability measurements answer different questions.

## Promotion and rollback plan

Promotion remains unimplemented. A future gate should require a reviewed code/catalogue identity, independently recomputed validation evidence, fixed denominators, qualified model/policy/scope, no protected-state failures, acceptable per-family regressions and an explicit operator-controlled activation record. Imported result booleans and caller-supplied hashes do not satisfy those conditions.

Only after observation qualification should a narrowly scoped acting trial be considered. Revalidate the completed action against current state immediately before dispatch, through the existing native owner. Default to base on missing evidence, unknown scope, invalid schema, changed source, revocation, cancellation or expiry. Never turn a permission error into a provider switch or an authorization workaround.

If an action errors after dispatch, treat its side effects as unknown until the target owner verifies them. A retry is not a rollback. Use readback reconciliation and idempotency where supported. The offline pilot neither dispatches nor claims to solve remote mutation recovery.

Roll back a future acting trial on protected-state failure or a predeclared regression trigger. Preserve the failed candidate's exact provenance in an appropriately private audit record, disable its lineage, and return routing to the existing base. Parent revocation must retire descendants and pre-existing pending observations. Monitor on fresh held-out cohorts; do not feed final-test labels into online evolution.

## Present qualification

The code provides strict data envelopes, frozen reviewed classes, deterministic fallback, context/policy/model/source binding, inherited revocation, receipt reconstruction and bounded offline IO. Tests establish those contracts on synthetic inputs. It has no learned router, candidate generator, promotion service, native adapter, model call, application dispatch, proof of global safety, calibrated confidence, production rollback service or measured task-quality gain. Native installation requires a macOS build and a separate integration change.
