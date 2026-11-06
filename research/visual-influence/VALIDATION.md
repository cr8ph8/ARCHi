# Validation record

Recorded on 2026-11-06. Starting repository commit: `ffee7ea9e77632de7cb13d816bff85dc498d9c1a`.

Environment: Linux, Node.js `v24.22.1`, Python `3.12.14`. Dependencies were installed with `npm ci --ignore-scripts` from the existing lockfile. No dependency was added for this experiment.

## Executed checks

`npm run check` completed successfully with the final implementation and all new JavaScript tests present:

| Check | Observed result |
| --- | --- |
| Retained source Vitest suite | 260 passed |
| Foundation contracts | 11 passed |
| Visual influence harness | 27 passed |
| PWA contracts | 10 passed |
| ARC Vitest suite | 23 passed |
| ARC TypeScript check | Passed |
| Production TypeScript/Vite build | Passed |
| PWA build validation | Passed; 10 same-origin shell assets |
| Total automated tests in this command | **331 passed** |
| Whitespace/error check | `git diff --check` passed |

The 27 harness tests comprise 15 experiment/classifier/accounting tests, three CLI tests, seven collector tests and two aggregate-budget tests. Collector tests use ephemeral loopback HTTP fixtures. They do not invoke a model. Tests cover exact matrix validation, PNG controls, classifier uncertainty, mixed evidence rejection, source provenance, explicit incomplete reports, local-only request construction, vision-capability requirements, redirects, timeouts, response and aggregate byte limits, checkpoint failures, cancellation, and preservation of known native token counts on failed responses.

The runtime implementation fingerprint at verification was:

```text
5b516a951930ac40eefb73217358bd5ac4793cbefae30261628ac6f3e91aebfe
```

This is the CLI's SHA-256 over the named bytes of `experiment.mjs`, `classify.py`, `ollama.mjs` and `cli.mjs`. It is an integrity/provenance observation, not authentication. Each prepared manifest records its own source revision, dirty status and implementation fingerprint.

## Explicitly not run

| Measurement | Status and reason |
| --- | --- |
| Six `VisualInfluenceBoundaryTests` native tests | **NOT RUN.** This environment has no Swift toolchain or macOS SDK. Signatures and fixture assumptions were reviewed against production code. |
| Live text-model pilot | **NOT RUN.** No Ollama executable was available; `127.0.0.1:11434/api/tags` refused the connection. This says nothing about another computer's installed service. |
| Live VLM pilot | **NOT RUN.** No local vision model was reached. |
| Native screenshot/OCR integration or GUI test | **NOT RUN.** The added native suite exercises synthetic text through Hampton and working-copy primitives. |
| Unauthorized-action or invalid-execution rate | **UNMEASURED.** The strategy collector does not execute generated code or invoke native admission. |
| GitHub-hosted checks | Not used as evidence. `docs/source-checks.yml.example` is a workflow template, not an activated workflow. |

The native suite supplies a revoked publication callback; it does not test `CompanionStore` revoking a request during an in-flight generation. Its false-answer negative control tests structural admission and an empty session-context bank; it does not inspect durable preference or evolution files. The working-copy tests exercise current-target checks and exact selected-range replacement, without editing an external application.

## Next executable measurements

On a supported Mac, run:

```sh
swift build --package-path desktop
swift test --package-path desktop --filter VisualInfluenceBoundaryTests
```

Then prepare a fresh manifest from the intended revision and follow the [local text-model or VLM pilot commands](README.md). Select an exact model already installed locally. The default two replicates establish plumbing only; they are insufficient for a broad reliability claim.

There is no empirical model-steering result in this change. Native structural acceptance, semantic correctness and authorization must continue to be reported separately.
