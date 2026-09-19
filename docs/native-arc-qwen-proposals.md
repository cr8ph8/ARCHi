# Local Qwen proposals in ARC

ARC offers two explicit routes for a loaded puzzle:

- **Solve locally** searches the existing finite symbolic catalog.
- **Ask Qwen for a rule** asks the installed local Qwen model for one short, structured transformation. ARCHi validates and executes that transformation.

The model comes from the desktop's existing local-model selection. Only the puzzle's training pairs, test inputs, request identity and transformation vocabulary are supplied. Expected test outputs, companion memories, profile notes, documents and account credentials are excluded. The transport is the existing verified loopback Ollama client. There are no downloads, remote endpoints, automatic retries or cloud fallback in this route.

## Proposal to checked result

Qwen can propose at most three typed operations and a training-derived color mapping, or abstain. It cannot return executable code, shell commands, arbitrary tools or authoritative state. The parser rejects unexpected fields, mismatched request/input identities, unsupported operations and malformed values. A completed response still needs validation.

The restricted evaluator reuses the native symbolic transformations with a bounded work budget. It checks the proposed rule against every training example. A mismatch, undefined transformation, cancellation or exhausted budget prevents a test prediction. When training passes and every test input can be transformed, the independent checker compares the predictions with any retained targets.

One rule fitting training is not consensus across a complete language. A failed training fit is not an execution error, and a missing test target is unscored rather than correct. These distinctions remain visible. This proposal lane leaves the original symbolic catalog and historical replay behavior intact.

## Integration

The result panel presents the rule, training coverage, predictions and independent exact counts. Evidence uses the existing profile-scoped archive. Usage and Activity map links select the corresponding attempt and retained evidence. Reopening saved evidence reruns its deterministic checker; it does not invoke Qwen again. A symbolic replay is not offered for a model proposal.

Changing the loaded puzzle, stopping the request, switching the local model or shutting down retires request ownership. A late completion cannot save into a replacement task. Usage distinguishes local Qwen proposal attempts from symbolic search, records reported telemetry when available and preserves missing tokens/cost as unknown. Viewing or evaluating a result grants no memory, Seed evolution, XP or permission changes.

## Scope

This is a local proposal workflow, not a trained ARC model, official benchmark result or complete Hampton/Q2E implementation. The broader public-corpus baseline was deferred after its strict parser rejected task metadata before any solve ran. That attempt supplies no score. Development in this increment uses focused checks of the new proposal path rather than a complete test-suite or corpus run.

The active assistant dispatch is described in [Active ARC](active-arc-assistant.md). Chat, Work together and the Seed bubble invoke this same capability; the ARC workspace provides management and inspection.
