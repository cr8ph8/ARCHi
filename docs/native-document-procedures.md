# Reviewed document procedures

19 September 2026 · Native selected-passage workflow

Work together now connects a helpful applied edit to an explicitly authored,
reusable procedure candidate. This is the first bounded procedure loop in ordinary
ARCHi work. It does not train Qwen, estimate general intelligence, certify a skill,
or change the companion's Seed/body identity.

## Use

1. Select a passage in a shared UTF-8 document. Choose Rewrite or Shorten, set
   the requirements, Send and review the proposed edit. Apply affects the app's
   working copy only.
2. In Document work history, mark the completed change Helpful. Open **Keep a
   procedure from this work**, write its name and instruction, and select **Keep
   procedure**. ARCHi does not extract or save an instruction automatically.
3. Select a later passage in Revise mode with the same shorter-text and
   exact-numbers/links requirements. Open **Saved procedures** and choose **Use
   for this passage**. Review the prepared instruction and Send through the
   selected assistant route. Preparation alone does not send or edit anything.
4. Review the new proposal, Apply if appropriate, and record Helpful or Needs
   correction. Undo and withdrawal remain separate explicit controls.
5. In **Saved procedures**, choose **Edit method**, update the name/instruction,
   describe what changed, and explicitly select a helpful applied result as
   support. **Save new version** retains a new candidate with its own binding.
   Earlier versions remain under **Previous versions**. Saving never sends a
   request or changes a prepared or in-flight instruction.

Changing the prepared instruction, passage, source, requirements or reply mode
blocks procedure Send until the user chooses it again or selects **Detach
procedure**. An explicitly detached draft is ordinary work and earns no procedure
use attribution. After Send, provider lanes and any eligible native-route fallback
share the same captured procedure reference. Existing exact-copy cloud permissions
still govern external routes; a deliberately selected instruction is part of the
current prompt, not automatic background memory injection.

## Evidence and correction

- Every saved procedure version has an immutable family ID/version, content digest, requirements,
  origin document-record ID and exact helpful-review event. Saving needs a
  verified **applied** result; undone, incomplete, unreviewed and legacy records
  without captured learning references are ineligible.
- A user-authored method is a **candidate**, even when inspired by a helpful
  result. That earlier edit does not establish that the newly authored instruction
  was the method executed, or that it generalizes. Later uses retain their own
  checked result and explicit user verdict.
- Send and Apply recheck the exact procedure, source review, supporting lessons
  and ancestor procedures. Missing, corrected, expired or withdrawn dependencies
  make the method unavailable. Relevant saved files are checked against the
  session's read baseline, so an external edit requires reopening before reuse.
- A Needs correction, Withdraw review or Undo on a reused result permanently marks
  that procedure version with a counterexample. A later Helpful verdict cannot
  erase the marker. Original-review changes also invalidate its exact event.
- Editing appends v2, v3 and later versions. The change note, preceding version
  binding and selected helpful review are retained. A blocked or withdrawn version
  needs different, later helpful applied work before a replacement candidate can
  be saved; a failed reuse or withdrawn supporting lesson is ineligible. Each
  version keeps its own counterexamples. A revision is a candidate, not certification
  that its new instruction works. The preceding version is lineage history;
  the chosen result supplies its actual evidence dependencies.
- Only the latest version is offered for new preparation. A request already
  prepared or sent keeps its exact old version, subject to that version's normal
  availability checks. Earlier versions remain inspectable and withdrawable.
- Activity map shows the captured procedure version and retained counterexample.
  Usage continues to account for actual requests; Keep and Use do not invent a
  model invocation or mark a task useful.

## Persistence

`preferences.document-procedures.json` belongs to the active native profile. It
contains explicitly authored names/instructions, requirements and provenance IDs,
with a 64-total-version/512-KiB limit. Atomic writes use a cooperative lock, fresh disk
comparison and private file permissions. Unknown fields, invalid references,
oversized files and symlinks are rejected without overwriting existing bytes.
The reader accepts existing v1 archives without rewriting them. The next explicit
save writes v2, preserving v1 content bindings. Revision chains must be complete
and bind the exact preceding version. An older app does not understand v2 archives.

The existing `preferences.document-work.json` remains a metadata journal. Its
optional `procedureUse` and monotonic `procedureUseRejected` fields are backward
compatible with records written before this increment. Procedure uses and reviewed
records are retained rather than pruned; the 64-record capacity can therefore
block new work. No automatic compaction or history deletion was introduced.

The Saved & this visit sheet identifies these files' scope. Companion recovery
packages currently exclude both sidecars. They require separate file preservation;
a two-file companion backup is not a backup of procedure/history data. Loading
never replays work or restores an unsaved document copy.

## Relation to Hampton's research

The implemented loop connects source-bound observation, a scoped method candidate,
checked action, observed outcome, user judgment and revisitable memory. This is an
engineering translation of the procedure-learning priority in the
[document-work priorities](active-document-work.md). The referenced
ARC3 master register is a research inventory, not authorization to connect every
historical equation as a live controller.

Remaining work includes automatic procedure induction, task-specific
capability measurements, more typed tasks, useful transfer across tasks,
and ARC3 planning adapters. No JEPA model, general Q2E updater, semantic critic or
automatic evolution award was added. Validation and installed observations are
recorded separately in the developer ledger.
