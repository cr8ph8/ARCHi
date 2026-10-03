# Find a method for the work at hand

26 September 2026 · native development alpha

**Work together → Find a saved method** connects the existing method library to
an explicitly described task. Search and preview use no model calls and write no
new memory. The full Saved procedures history remains directly below it.

1. Describe the task, such as “summarize project status”, or choose **Use current
   request** to copy the composer into this local search. Choose **Find**.
2. Review the matched words, method version and Helpful/awaiting-review counts.
   Results already match the current length and exact-number/link requirements
   and have current source support. No matches means no matching saved method;
   ARCHi does not invent one or relax its requirements.
3. Select a passage and choose **Revise passage**. Choose **Preview for this
   passage…**. The preview shows the instruction and any draft it would replace.
4. Choose **Replace draft with method** or **Use this method** only when it fits.
   Cancel leaves the draft alone. Preparation sends nothing; Send, review, Apply
   and Helpful/correction feedback remain separate actions.

The full library's **Use for this passage** button now opens the same preview.
**Prepare next step** keeps a current, explicitly selected method, but no longer
chooses the first historically Helpful method merely because two mechanical
requirements match. A new draft, selection, source version, requirement, profile
or supporting-source change retires an old preview. Confirmation checks the
current owners again, including changes made outside this ARCHi session.

If a supporting source is withdrawn, the prepared method stays attached and
blocked so its instruction cannot silently continue as an ordinary request.
The existing method status and **Detach** control are visible in Chat as well
as Work together. Detaching is an explicit choice; it does not restore the
withdrawn source or certify the instruction.

## Connection to Hampton's learning loop

This improves the runtime consumer of existing method memory: retained method
→ task-directed retrieval → explicit selection → attributed request → checked
Apply → user outcome → later ordering. It does not create a second memory store
or award a capability for finding a method.

The new retrieval heuristic is ordinary implementation work, not a recovered
Hampton equation. For distinct task terms after stop-word filtering:

`wordScore = 2 × |taskTerms ∩ titleTerms| + |taskTerms ∩ instructionTerms|`.

Repeated words do not add weight. Highest score comes first; equal scores retain
the existing native ordering. That ordering uses the established Beta(1,1)
Helpful/correction statistic `(helpful + 1) / (helpful + correction + 2)`, followed
by comparable measured resource usage. The implementation uses exact integer
cross-products in `HamptonMethodOutcomes`, with existing resource comparability
rules in `HamptonMethodResourceOutcomes`. Neither statistic is a calibrated
success probability. A word match does not establish semantic fit, entailment,
general transfer, or permission to act.

The search is bounded to 512 UTF-8 bytes, 32 distinct tokenized terms, 64 eligible
methods and five results. It reports omitted matches. It searches titles and
instructions only; the document is not scanned or sent for retrieval. No model
weights, RepE qualification, source schemas or companion development rules change.

## Evidence and limits

Nineteen focused cases exercise relevance/order, malformed/duplicate scopes,
preview ownership, draft/source invalidation, restart recovery, existing local
source boundaries and the former unrelated-method selection failure. They use disposable production owners and
make no generation or external requests. The installed empty-library search is
checked separately. One opt-in local `qwen3.5:9b` call then exercised actual
find → preview → explicit choice → proposal using a disposable project update,
without a supplied target answer. All eight mechanical checks passed, the exact
source/method binding and Token Steward usage matched, and the working copy
remained unchanged: **2,033 input tokens, 198 output tokens, one invocation, zero
external calls**. No Apply, feedback or growth occurred. The report retains the
actual replacement and explanation; this is not a Helpful judgment.

Populated native interaction and everyday helpfulness still
need owner-authored methods and outcomes. This is a working bounded integration,
not proof of the full Hampton stack, patent claims or beta readiness.

See [method lifecycle](native-document-procedures.md),
[concept-to-method learning](native-knowledge-methods.md), and
[everyday outcome review](everyday-learning-and-world-outcomes.md).
