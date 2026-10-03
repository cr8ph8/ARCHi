# Contributing to ARCHi

Start with a small reproducible issue or focused change. Include the source commit, platform/toolchain, expected behavior and synthetic reproduction. Separate observed results from untested behavior. Do not attach credentials, personal profiles, private documents, kept lessons or real conversation fixtures.

## Source and publication

The main ARCHi workspace is the authored source. The curated publication checkout is a generated review and distribution artifact. Submit focused patches against the published snapshot; maintainers reconcile accepted changes into their existing owners in the authored workspace, then regenerate the publication candidate. Do not let fixes accumulate only in an export checkout or copy the publication tree wholesale over authored work. See [one-app source and delivery](docs/one-app-system.md#source-and-delivery).

User profiles never belong in Git, including fixtures, issue attachments, logs and commit history. Use disposable synthetic profiles for reproductions. Source promotion must exclude private records, credentials, local databases, model weights, caches and application bundles. An ignore rule alone does not review tracked files or history.

## Preserve the existing owners

Native Swift owns assistance, permissions, shared working copies, kept lessons and saved companion development. KIN Seed and body are one continuing individual. Changes to presentation or graph inspection must not silently invoke a provider, save a remembered fact, award development or duplicate state.

Unity receives a bounded native presentation snapshot and supports explicitly entered local Arena practice. It acknowledges presentation and reports bounded practice observations; it cannot write native memories or commit saved development. Arena also hosts native ARCHi Trials through the existing reasoning owners. The retained TypeScript Journey/battle code keeps its own domain boundaries. Read [architecture](docs/ARCHITECTURE.md) and [native authority](docs/native-authority-and-lineage.md) before changing these contracts. Source freshness, cancellation, explicit review and external-copy allowances belong in the current owners rather than parallel stores.

Local model runtimes, the creator service and optional external model routes supply their defined services. WikiOS and future companion panels must use native owner operations instead of creating another writable profile or memory database.

## Local checks

Choose checks for the changed behavior. Documentation-only changes need link, source-consistency and diff review. Native behavior changes should build and run the affected suites with synthetic data; use `swift test --package-path desktop --filter <AffectedTestSuite>` to select them. Broad ARC runs, live models and the full benchmark suite are not prerequisites for a focused fix or for entering Marketplace/Arena.

For broader retained TypeScript verification with Node.js 24 and npm:

    npm ci
    npm run check

For native source on macOS 14+ with Swift 6 and the macOS SDK:

    swift build --package-path desktop
    swift test --package-path desktop

The [CI workflow template](docs/source-checks.yml.example) documents a smaller deterministic native subset suitable for unattended runners; a template is not evidence that CI ran. The full suite intentionally skips opt-in tests whose external or windowed prerequisites are absent. Report skips separately. Do not enable live-provider, real-profile or native capture tests merely to make a skipped count smaller; use explicitly chosen synthetic fixtures and required permissions when validating those paths.

The [Unity guide](unity/ARCHi/README.md) covers the pinned Editor, build helper and resource validation. A build is separate from runtime interaction, accessibility, long-session and distribution qualification.

This is a source review draft. Some later artwork is withheld; artwork-dependent tests and full Unity reproduction have separate prerequisites. Results from a complete local candidate do not qualify the reduced public artifact. Keep source checks, installed-app interaction, missing resources and release acceptance separate in reports. See [validation scope](docs/ALPHA_VALIDATION.md); no Beta or downloadable application release is declared.

At publication preparation, regenerate SOURCE_SHA256SUMS after final edits and verify both the hashes and coverage of the intended source files. The manifest is evidence about bytes, not publication permission. Keep generated caches, screenshots, build outputs and user data outside the tracked source tree. See [security reporting and data boundaries](SECURITY.md).

## License and attribution

Project-authored contributions use the repository's [MIT license](LICENSE). Preserve applicable third-party license notices and describe the provenance of added runtime assets. The [asset attribution](ASSET_ATTRIBUTION.md) and [third-party notices](THIRD_PARTY_NOTICES.md) identify the current distribution.

MIT permission is separate from official Hampton Designed endorsement. Contributing, forking, copying a mark or assigning a local UID does not authenticate a creator edition, ownership or scarcity. The [Hampton Designed policy](docs/HAMPTON_DESIGNED.md) adds no restrictions to MIT permissions; private assistant data remains outside transferable character records.
