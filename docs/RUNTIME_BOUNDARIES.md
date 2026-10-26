# Protected checks and runtime integration decisions

Engineering follow-through for the October 19–25, 2026 agent-runtime brief. The integrity checker below is implemented as a bounded source comparison. Production isolation, remote-action admission, integrations and the transaction experiment are separate work; none is implied by a passing source check.

## Protecting the controls and their tests

`scripts/runtime-integrity-guard.mjs` compares 25 explicitly protected source, fixture, dependency, test and workflow files against a separately provisioned policy. It uses only Node standard-library imports, executes no candidate code and ignores the candidate's `SOURCE_SHA256SUMS`. Missing, changed, oversized or linked protected files reject. The CLI also rejects checker/policy locations inside the candidate checkout. A policy digest supplied independently by the controller is mandatory.

The attack regression weakens the real Episode evidence verifier (`validateEpisodeTrace`) and replaces its tests with one that accepts an absent record. The rewritten candidate test passes; the external checker rejects both changes. This models removal of a verification control, not a live monitoring deployment. Another case replaces the candidate's copy of the checker; the separately invoked checker still rejects it.

The protected file set is deliberately conservative: edits to the large native owner or protected tests require maintainer review and a new approved baseline. A legitimate change is held for review rather than automatically classified as malicious. A new unprotected bypass is outside this comparison's coverage. Independent behavioral evaluation remains required.

### Provisioning contract

1. A maintainer approves a full source commit and its actual contents. Provision the checker and approved checkout in a controller-owned account, read-only image or volume unavailable for proposer writes. The `sourceRevision` field is provenance supplied by the controller; the tool does not prove that a worktree matches that commit.
2. The controller seals the policy from that approved checkout before exposing the candidate to an optimizer. Keep the policy and its expected digest outside the candidate. Store the digest in controller configuration; never read it from candidate output or silently reseal after a rejection.
3. Stop candidate writers and create an immutable candidate snapshot. The controller invokes its absolute, trusted Node binary and verifier path with a scrubbed environment. Do not load candidate plugins, dependencies, startup files or test runners first.
4. Require exit code zero **and** a valid JSON report with `decision: PASS`, the expected policy digest, and the expected approved revision. This only means the enumerated surfaces matched at inspection. `actionAuthorized` stays false. Subsequent evaluation/admission must bind to the same immutable candidate snapshot.

For example, with these absolute paths provisioned by the controller:

```sh
/trusted/node /trusted/approved/scripts/runtime-integrity-guard.mjs seal \
  --trusted-root /trusted/approved \
  --source-revision APPROVED_FULL_COMMIT_SHA \
  --output /trusted/policy.json

env -i /trusted/node /trusted/approved/scripts/runtime-integrity-guard.mjs verify \
  --candidate-root /staged/candidate \
  --policy /trusted/policy.json \
  --policy-sha256 sha256:INDEPENDENTLY_PINNED_POLICY_DIGEST
```

Replace the uppercase placeholders with independently approved values. `seal` refuses an existing output file. Copying the verifier to another directory under the same writable account does not establish isolation. Read-only file modes alone do not protect files from their owner. Control the directory, principal, mount permissions, runtime binary, launch environment and pin together.

`npm run runtime:boundary:test` exercises the comparison and CLI. The separate-UID test additionally checks OS denial of writes to the trusted checker and policy, while allowing a proposer-owned file to change. It requires a disposable Linux root runner with UID/GID 65534 mapped; other environments report a skip. To run just that fixture in such a runner:

```sh
ARCHI_REQUIRE_UID_ISOLATION=1 node --test --test-name-pattern='separate Linux UID' scripts/runtime-integrity-guard.test.mjs
```

The Ubuntu source workflow has a separate fixture-only step using the disposable runner's root account to create controller-owned files and launch the attack as UID/GID 65534. It has no real credentials, network requests or deployment actions. Its `ARCHI_REQUIRE_UID_ISOLATION=1` flag makes missing isolation prerequisites fail rather than skip. The default developer test run may skip this fixture; check the separate step's logs before claiming OS isolation was demonstrated.

Default source CI runs the development tests from the PR, so it can be modified by a PR author. It is not an independently installed required check. The external controller must be provisioned separately before granting an optimizer write access. This patch installs no production controller and provides no signature, transactional commit, continuous monitoring or concurrent-writer/power-loss guarantee.

## AAIF compatibility map — design only

AAIF announced the four projects on [October 22, 2026](https://aaif.io/news/agentic-ai-foundation-announces-four-new-projects). The following mappings are architectural proposals; no protocol/version compatibility or adapter has been tested.

| Project | Announced role | Proposed boundary in ARCHi | Smallest conformance case |
| --- | --- | --- | --- |
| Agent Skills | Reusable instructions, scripts and resources | Treat packages as untrusted inputs; pin package content and provenance before loading; scripts receive only explicitly granted tools | A skill requesting a policy edit or external send cannot grant its own permission |
| Open Responses | Shared multi-provider request/output interface | Normalize model output to existing typed proposals; preserve provider, request and source identity | Unknown/extra fields or cross-request source references fail existing admission; never translate a model response directly into saved state |
| OpenEnv | Interoperable RL environments | Evaluation adapter only; pin environment, dataset, scorer and run configuration independently | An optimizer changing the expected result or reward logic cannot change the controller's frozen evaluation |
| OpenSandbox | Sandbox lifecycle and execution APIs | Execution substrate below the native owners; credentials and verdict authority remain outside the guest | Resume of a snapshot with an old permission epoch cannot revive revoked authority |

Keep proposal validation, admission decisions and evidence receipts independent of these transports. Pin exact specification/repository revisions before implementing an adapter. The current ARC receipt hashes are not signatures; existing `unattested`, `not-certified` and no-write-authority semantics remain in force.

## Combined revocation, restart and ambiguous-write experiment

**Status: specified, not executed.** ARCHi currently has local profile-recovery and exact-copy allowance checks, not a general remote mutation executor or delegated-credential broker. Use a disposable synthetic service and durable verifier/operation stores when implementing this experiment; do not use a user's account or production endpoint.

The [AWS/Keyfactor reference architecture, October 20](https://aws.amazon.com/blogs/machine-learning/securing-ai-agent-identity-with-x-509-pki-on-aws/), motivates revocation and request freshness checks. Its request nonce is distinct from the operation identity below. These requirements are our proposed experiment, not verified properties of that implementation.

| Step | Controlled event | Required observation |
| --- | --- | --- |
| 1 | Issue principal A a bounded delegation at permission epoch 1. Admit operation O1 with payload hash H and base version V0. | Durable intent binds principal, delegation, policy/verifier version, O1, H and V0 before dispatch |
| 2 | Receiver applies O1 once and commits its idempotency record; fault proxy drops the response. | Receiver's independent counter is 1; client records UNKNOWN, not failure or permission to resend |
| 3 | Revoke epoch 1 and its derived delegations/tokens; roll back the workspace and restart verifier/broker. | Revocation and operation history survive outside the rolled-back workspace; no restored credential becomes valid |
| 4 | Retry O1 using revoked authority, once with the original nonce and once with a fresh nonce. | Both denied before dispatch; receiver counter remains 1 |
| 5 | After new explicit approval, issue epoch 2 authority to the same principal for status reconciliation. Reconcile O1/H. | Read-back recovers the original effect/receipt; it issues no second mutation; counter stays 1 |
| 6 | Try O1 with a different payload or principal. | Reject identity/payload conflict; never reinterpret an operation key |
| 7 | Make receiver status unavailable. | Remain UNKNOWN/ESCALATE, with bounded polling and no blind resend |
| 8 | Issue distinct operation O2 with valid epoch 2 authority and the receiver's current base version. | One new effect is possible; stale V0 rejects |

Record verifier restart identity, credential and delegation fingerprints (never secrets), policy digest, epochs, operation/payload/base identifiers, durable status transitions, receiver count and receipt/effect hashes. Final acceptance requires counter 1 through step 7, no revoked dispatch, and successful legitimate progress in step 8. A signed envelope or in-memory nonce cache alone cannot establish this result. A receiver without atomic deduplication requires reconciliation/escalation; do not claim exactly-once delivery.

Follow-up variants: race two workers on O1, lose the revocation service, roll back the operation database, and lose the response during receipt persistence. Each must preserve denial or ambiguity until independent reconciliation. Do not rebuild authority from an older workspace snapshot.

## Adapter and partnership gates

Every consequential connector write must bind to a base version (or document an equivalent enforced precondition), stable operation identity and payload digest. The executor must enforce the precondition; recording a version in a receipt is insufficient. Remote APIs without deduplication or read-back need explicit unresolved-outcome handling.

For Google Substrate/OpenSandbox review, inspect identity renewal, permission epoch revalidation at resume, credential injection outside the guest, egress enforcement and outstanding-effect reconciliation. A memory checkpoint cannot undo an external send. Keep migration deferred until the bounded recovery experiment passes on the selected version.

For a potential Neo4j design-partner evaluation, require source-bound claims, conflicting evidence, correction/withdrawal propagation into derived memories, and replay/recovery without resurrecting withdrawn claims. A small synthetic corpus and those four acceptance cases should precede any platform adoption. No outreach or enrollment is authorized by this document.

Compare competitors and any future integration on enforced admission, verifier/test ownership, stale-base rejection, revocation persistence, operation reconciliation, provenance and recovery. Mark each cell documented, demonstrated, failed or unknown, with a source/version/run reference. Broad governance language is not a substitute for those observations.
