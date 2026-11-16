# Relationship admission: native acceptance evidence

`script/accept_relationship_admission.py` runs existing source tests and records
their evidence. It keeps native source tests, an optional live local-model
receipt, and installed-application qualification separate.

This runner does not create a second app-launch workflow. Continue to use
`script/build_and_run.sh` for app staging/build/launch. The acceptance runner does
not install, launch, stop or replace an application, download a model, select a
user profile, or change native business logic.

## Run

Requires Python 3.10 or newer. Native tests require macOS 14+ and Swift 6 with the
macOS SDK. A Linux invocation is useful for the portable runner checks and an
optional QiMovi source suite; it records native prerequisites as SKIPPED.

From the ARCHi repository root:

```bash
python3 script/accept_relationship_admission.py
```

The default evidence directory is a new unique directory under
`output/relationship-admission/`. To choose one, pass `--output` with a path that
does not exist. Existing evidence directories are refused, so a previous receipt
cannot silently satisfy a later run.

The runner records:

- The exact Git commit, worktree status and SHA-256 source manifest.
- Each executed command, working directory and explicit environment overrides.
- Command exit status, elapsed time and the output-log digest.
- PASS, FAIL, SKIPPED and ERROR separately; ABSTAIN and ESCALATE are retained as
  separate zero-count categories when no check produces them.
- Separate XCTest and Swift Testing counts. These populations are not added.
- A separate filtered command and exact observed completion for every selected
  Swift suite, so one matching suite cannot conceal another missing selection.
- Unobserved installed-app interaction, complete restart, and native media bridge
  checks as SKIPPED.

A command exit code of zero is insufficient for PASS: recognizable, nonempty
test results must confirm execution, and each filtered native command must
identify the exact expected suite in its completion output. A run containing skipped/todo cases remains
SKIPPED even when its executed cases pass. Test assertion failures produce FAIL;
missing commands, build failures, missing selected test files, unrecognized test
accounting and timeouts produce ERROR.

The runner exits **1** for FAIL/ERROR and **2** for incomplete qualification with
SKIPPED checks. It currently always includes unobserved installed-app checks, so
passing source tests alone does not produce a complete qualification or exit 0.
Read the per-check results in `acceptance.json`.

## Native source boundary selection

The focused SwiftPM selection is:

- `HamptonProposalValidationTests`
- `HamptonSessionContextTests`
- `WorkingCopyRevisionTests`
- `WorkingCopyStoreTests`
- `EvolutionRequestBindingTests`

These existing tests exercise shape/reference validation, current context,
explicit working-copy edits and request/revision binding. The selected store
tests use in-memory state or explicit temporary/invalid profile paths rather
than the installed user's profile. The Swift build scratch directory is inside
the new evidence directory.

These tests do not establish that every factual assertion is true.
`HamptonProposalValidator` deliberately validates structure and exact reference
membership. Native `accepted` is not permission for an external action.

## Paired QiMovi attachment suite

The owning QiMovi service can be tested in the same evidence run:

```bash
python3 script/accept_relationship_admission.py \
  --qimovi-repo '/absolute/path/to/QiMovi' \
  --qimovi-test 'tests/movie-selection-binding.test.mjs'
```

The test must exist inside the chosen repository. The runner invokes Node's test
runner directly with the TAP reporter and records that repository's commit and
source manifest. It performs no dependency installation. Missing dependencies or
an unsupported Node runtime produce ERROR. The selected test file is
configurable, so the exact paired branch can be identified in its evidence.

QiMovi remains the owner of the attachment operation and its current records.
The paired proof concerns a local owner's reviewed editorial selection under the
application's contract. It does not invent a rights clearance, a final production
approval, a remote approver or an authenticated external signature. A label,
model-produced actor ID or caller-supplied PASS is not an independent authority.

No native QiMovi media-attachment consumer exists in the inspected ARCHi source.
The runner records that bridge as SKIPPED; it does not add an unused native gate
or route a chat answer into an attachment write.

## Explicit local-model receipt

Opt in to the existing native receipt demonstration:

```bash
python3 script/accept_relationship_admission.py --live-receipt
```

This runs `AssistantReceiptLiveTests` only after the focused native source tests
pass. The existing test constructs a disposable synthetic profile and requests
one local 2+2 answer through the production `CompanionStore` and
`HamptonReasonsAssistant`. It records the actual model digest, generation
metrics, request/input/output bindings and evidence decisions. It refuses hosted
model routes. The runner neither downloads nor starts Ollama/models.

The native source currently defaults to `qwen3.5:9b`; this documentation is not a
claim that the tag is installed or reachable. Missing connection/model
prerequisites remain visible in the test result. The one-generation receipt
demonstration is not the 48-case relationship benchmark.

The runner removes inherited `ARCHI_*` test opt-ins from subprocess environments
and adds back only the explicit live-receipt settings. A passing test command
also must produce a fresh receipt with successful checks, zero external calls
and matching receipt-accounting results before this check receives PASS.
The receipt and its nonempty checks must be JSON objects, with boolean check
values. Malformed evidence records ERROR in `acceptance.json` rather than
aborting report creation.

## Installed-app acceptance remains a separate observation

Source execution is useful evidence, but it does not demonstrate the behavior of
the installed bundle. Qualification still requires an observed, disposable-profile
native session that:

1. Opens the exact staged/installed revision under test.
2. Reviews the intended candidate and target.
3. Rejects substituted identity, revision or evidence without changing business state.
4. Uses the explicit save/commit action.
5. Closes the entire application and reopens it.
6. Confirms the same identity, committed state and evidence, and the absence of
   rejected proposals from durable business state.

Those steps cannot be marked PASS by this runner, by file existence, by an
unrelated archive roundtrip, or by successful compilation. The independently
authored QiMon Unity game is outside this acceptance scope.

## Portable runner checks

```bash
python3 -m unittest discover -s scripts/tests \
  -p 'test_relationship_admission_acceptance.py'
```

These checks test evidence classification, including zero-test and skipped-test
cases. Their success is not a substitute for native or installed-app acceptance.
