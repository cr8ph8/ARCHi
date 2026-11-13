# Contributing to ARCHi

Start with a small reproducible issue or focused change. Include the source commit, platform/toolchain, expected behavior and synthetic reproduction. Separate observed results from untested behavior. Do not attach credentials, personal profiles, private documents, kept lessons or real conversation fixtures.

## Preserve the existing owners

Native Swift owns assistance, permissions, shared working copies, kept lessons and saved companion development. KIN Seed and body are one continuing individual. Changes to presentation or graph inspection must not silently invoke a provider, save a remembered fact, award development or duplicate state.

The Unity companion/play preview is disconnected from native saves. The retained TypeScript Journey/battle engine remains its existing source owner, and Habitat/Arena is disabled in the current native desktop build. Read [architecture](docs/ARCHITECTURE.md) before changing these boundaries. Source freshness, cancellation, explicit review and external-copy allowances belong in the current owners rather than parallel stores.

For changes to companion form or Journey transitions, preserve the [continuity contract](docs/CONTINUITY_UNDER_TRANSFORMATION.md): bind the exact requested effect before constructing a candidate, retain the existing identity and history, and reject unrelated changes. A candidate passing schema checks does not establish that it performs the requested action. Extend the owner-side postconditions and negative tests when adding a new operation; do not let an optimizer, renderer or submitted PASS field bypass them.

## Local checks

For retained TypeScript source with Node.js 24 and npm:

    npm ci
    npm run check

For native source on macOS 14+ with Swift 6 and the macOS SDK:

    swift build --package-path desktop
    swift test --package-path desktop

The [CI workflow template](docs/source-checks.yml.example) uses a smaller deterministic native subset suitable for unattended runners. It is not enabled because the current publishing credential lacks workflow permission. The full suite intentionally skips opt-in tests whose external or windowed prerequisites are absent. Report skips separately. Do not enable live-provider, real-profile or native capture tests merely to make a skipped count smaller; use explicitly chosen synthetic fixtures and required permissions when validating those paths.

The [Unity guide](unity/ARCHi/README.md) covers the pinned Editor, build helper and explicit smoke runner. A build is separate from runtime interaction, accessibility, long-session and distribution qualification.

SOURCE_SHA256SUMS covers every tracked source file except itself. Regenerate it after final edits and verify both the hashes and complete file coverage before submitting. Keep generated caches, screenshots, build outputs and user data outside the tracked source tree.

## License and attribution

Project-authored contributions use the repository's [MIT license](LICENSE). Preserve applicable third-party license notices and describe the provenance of added runtime assets. The [asset attribution](ASSET_ATTRIBUTION.md) and [third-party notices](THIRD_PARTY_NOTICES.md) identify the current distribution.

MIT permission is separate from official Hampton Designed endorsement. Contributing, forking, copying a mark or assigning a local UID does not authenticate a creator edition, ownership or scarcity. The [Hampton Designed policy](docs/HAMPTON_DESIGNED.md) adds no restrictions to MIT permissions; private assistant data remains outside transferable character records.
