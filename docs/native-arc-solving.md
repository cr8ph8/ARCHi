# Native ARC solving

ARCHi means **ARC Hampton Interphase**. ARC Lab runs a bounded native Swift search over static ARC grids, retains its proposed predictions, and checks any supplied test targets independently. No model, provider, generated code or subprocess participates in the search. This is a local experimental solver, not an official ARC benchmark result, Q2E validation or an interactive ARC3 agent.

## Use

Open **More tools → ARC Lab**, or choose **Open ARC Lab** on Home. The **Solve a puzzle** tab contains the task canvas. **Load sample** loads a clearly labeled synthetic rotation task. **Import ARC task…** accepts a local JSON task with `train` and `test` arrays; each training example needs `input` and `output`, while each test example needs `input` and may include an `output` reserved for the checker. **Solve locally** generates predictions before the independent checker compares any provided targets.

The task canvas shows training examples and test inputs, followed by input/prediction pairs when a result exists. **How this works** contains the format and algorithm details. **Stop** immediately retires the active attempt; loading another task also retires it. Late results from a retired worker cannot save or replace the current task.

**Saved results** keeps the existing evidence shelf separate from the task canvas. Reopening a saved result validates its retained inputs, predictions and metadata without executing another search. **Run again** explicitly reruns its frozen input/configuration and compares deterministic outcomes, program IDs and traces; each rerun receives a separate accounting event. A match establishes local repeatability, not authenticity or certification.

Result actions open the corresponding run in **Usage** or retained evidence in the **Activity map**. These are navigation actions; opening either view does not run the solver or grant permissions. Missing or unrelated records produce an explicit notice. Advanced evidence-bundle import remains a separate operation. See [ARC Lab workspace integration](native-arc-workspace-integration.md) for the exact routing and ownership rules.

## Fixed hypothesis language

The default v3 catalog has **174 candidates**: the original 170-program v2 catalog and four standalone object rules. Historical v2 replay retains its original catalog. The shared geometric language contains identity, seven nonidentity rotations/reflections, nonzero bounding-box crop, integer upscaling by 2/3, tiling by 2/3, ordered geometric compositions of depth at most two, and training-derived consistent color mappings after identity or one geometric operation.

Every candidate must fit every training pair. Predictions are returned only after the complete search establishes that all fitting candidates produce the same complete test outputs. Divergent or undefined test predictions cause abstention. A changed palette is undefined for colors absent from its learned mapping; redundant identity palettes are omitted so ordinary geometric rules can handle new colors. Zero background and this palette behavior are explicit language assumptions.

The four object operations are `cropLargest`, `cropSmallest`, `keepLargest` and `keepSmallest`. Components use same-color, four-neighbor connectivity with zero background. Selection matches the inspected pythonProjects donor ordering `(-area, color, bbox)`, where `bbox` is `(minRow, maxRow, minColumn, maxColumn)` and exact ties retain discovery order. The native implementation uses one-pass minimum/maximum selection equivalent to choosing the first/last component under that ordering. Equal-area ties therefore have defined donor-matching behavior. All-zero grids are undefined for these operations.

Crop copies original pixels inside the selected component's bounding box, including other components inside that box. Keep preserves the original grid dimensions and selected component cells, setting everything else to zero. These four rules have no additional compositions or palette variants. They do not implement arbitrary object counting, relational reasoning, object motion or general planning.

Inputs and intermediate grids are bounded to 30×30, colors 0–9, and 1–20 training/test examples. The standard budget is 1,500 program attempts, 2,000,000 counted cell operations and 1,500 trace entries. The catalogs currently use at most 174 or 170 attempts. Object rules reserve 20 abstract cell-work units per input cell; this accounting is not a measurement of primitive operations, CPU time or energy. Cancellation is checked during work. Any incomplete search abstains, and missing predictions remain in the checker's test-example denominator.

## Task-local Hampton feedback

Training-example scheduling adapts a Beta(1,1) mechanism from the Qi Experiments critic. For each training example, retain actual checks `n` and observed falsifications `f`; prioritize larger `(f + 1) / (n + 2)` values, using original example index for exact ties. The engine freezes the order for each candidate, records actual visited indices, and starts fresh on every solve. No state transfers between tasks, and no test target enters the scheduler.

All fitting candidates still pass every training example. A fixed/adaptive regression compares the same complete catalog and requires identical predictions and fitting-program IDs while demonstrating fewer checks and counted cell operations on a constructed fixture. This is bounded scheduling evidence, not calibrated correctness, permission, general learning or demonstrated official-task performance.

The component operators and scheduler are small native adaptations of inspected local donor source. The requested pythonProjects v4 discovery report was unavailable during that inspection; older reports do not establish a current v4 result. ARC3's interactive environment/action harness remains a separate integration target. No Q2E validation is claimed.

## Ownership and retained evidence

- `ARCSolverDocument` separates solver input from optional test targets. The worker receives training pairs and test input grids only. Parsing rejects extra instruction/authority fields, Boolean colors, ragged or oversized grids, pipes and files larger than 2 MiB.
- `ARCSymbolicSolver` executes a fixed, finite language. It cannot run imported code, contact a provider, change a checker or train weights.
- `ARCCapabilitiesStore` persists task/prediction bundles before publication and detects stale writers. Identical evidence can deduplicate while separate attempts retain distinct accounting IDs.
- The existing independent evaluator continues to label evidence proposed and not certified, with source provenance unattested. The compiled host executable is hashed as `codeHash`; this identifies binary bytes, not a source-tree signature or trustworthy objective.
- Usage records elapsed evaluation time, cancellation and failure separately from model tasks. Zero model requests or API charges does not imply zero local CPU or energy cost. Synthetic checks never become accepted assistance outcomes.
- The Activity map projects existing evidence/accounting owners. A score or navigation action does not alter Seed identity, evolution, lessons or permissions.

Optional `solverEvidence` remains compatible with older schema-1 archives. Its bounded fields and trace are checked against the retained task/configuration/prediction bundle, including reconstruction of the declared training-example schedule. Impossible orders, repeated examples and out-of-range indices are rejected. Explicit reruns preserve historical v2 semantics. These local unsigned records establish consistency without authenticating their origin.

## Validation scope

Development-checkout observations on 18 September 2026 are separate from qualification of this reduced public source checkout:

| Observation | Scope |
| --- | --- |
| v3 focused tests | 129 tests, zero failures, before the latest workspace integration |
| Object donor comparison | 44 comparisons over 11 cases, zero mismatches; isolated exact donor functions against transcribed native expectations, not a full Python suite or Swift execution |
| Installed v3 visit | Historical v2 replay matched at 170 attempts; a synthetic object task used 174 attempts and returned 1/1 exact output |
| Latest workspace focus | 146 tests executed, three opt-in skips, zero failures in the development checkout |
| Workspace native presentation | One separate opt-in test passed in the development checkout, covering native controls and retained replay with light/dark captures |

The public draft continues to omit the previously listed 15 artwork files and 11 Unity metadata sidecars. Full local-candidate validation does not qualify this reduced artifact. See [the retained public validation scope](ALPHA_VALIDATION.md) for artwork and broader release limitations.

Separately, the prepared public source checkout passed 32 source-export fixture tests, `swift build --package-path desktop`, and the same focused native selection: 146 tests executed, three Home presentation opt-in skips, zero failures. These fresh public checks include solver semantics, parsing, retention/replay, accounting, exact routing and workspace contracts. They do not run the opt-in ARC presentation fixture or establish an installed-app visit. Public artwork-dependent tests and full Unity acceptance remain blocked by the deliberate asset exclusions. The earlier build attempt failed at sandboxed compiler-cache access before compilation; the host-authorized retry used an isolated temporary build directory and passed.

These are bounded local and synthetic observations. They establish no official ARC score, unseen-set generalization, complete desktop acceptance, Q2E validation or interactive ARC3 performance. A perfect training fit may still produce an incorrect test output.
