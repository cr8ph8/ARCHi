# ARC as an active ARCHi capability

ARCHi is the ARC Hampton Interphase. ARC belongs in the task execution system: it receives a bounded problem, reasons with supported tools, checks the proposed result, and returns an inspectable answer. The desktop ARC workspace manages those tasks and retained results. Benchmarks are one way to measure the capability; they are not its product purpose.

## This implemented increment

Chat, Work together and the Seed's attached chat expose the same **ARC task** action. They invoke the existing profile-scoped ARC service directly. **Solve shared or loaded task** performs native symbolic search without an LLM connection. **Propose a rule with local Qwen** makes one explicit local request and independently executes/checks its typed rule. These are the same engines, work bounds, evidence archive and Usage entries used by the ARC workspace.

The assistant also recognizes `/arc solve`, `/arc propose`, and the exact requests “solve this ARC puzzle” and “solve the loaded ARC task”. The shared working-copy ARC JSON is used when present; otherwise the currently loaded ARC task is used. A missing or invalid input is a local actionable failure. Source document instructions cannot dispatch tools, and an ARC request does not silently fall through to an external provider.

The result is shown in the conversation with grid predictions, checker counts and links to Usage, Activity map and retained evidence. It is a native task result, not a fabricated Qwen/Codex reply. Changing context, replacing the task, stopping, switching the profile or shutting down invalidates the request owner. Old completions cannot become the new task's answer. The shared message draft is retained when using the action menu.

Hampton's existing separation between proposal, execution, verification and accepted state remains the controlling architecture. A prediction or task result grants no companion evolution, memory, permission or benchmark standing. Training fit and independently scored test accuracy remain distinct; missing expected answers are unscored.

## Scope and next capability layers

This increment activates the current grid-task capability. The subsequent [interactive ARC3 increment](active-arc3.md) adds installed offline public environments, bounded actions, actual observations, and task-local transition predictions through the same native task surface. Neither increment establishes unrestricted autonomous planning, complete Q2E, or the performance of a frontier model on ARC Prize. The unavailable proposer-evolution-v4 report remains an evidence gap. Imported research and benchmarks must retain their own provenance and evaluation conditions.

The Astra and Astra-for-Law comparison motivates the next layers: versioned domain capability packs with explicit inputs, supported operations and native verifiers; then a revision-aware job registry for multiple dependent tasks. Any premium external proposer remains separately configured, explicitly selected, cost-reserved and independently checked. Domain retrieval, inference quality, task verification and authorization are separate responsibilities. A model upgrade does not replace these contracts.

Keep baseline evaluation and release qualification available as developer tools, while prioritizing useful assistant tasks and a coherent user interface. This pass uses only focused dispatch/lifecycle checks and observed native interactions, not an all-tests or corpus run.
