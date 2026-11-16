# ARCHi native desktop

From the repository root, prepare a separate locally signed candidate without launching or installing it:

    ./script/build_and_run.sh --verify --review --stage-only

Requires macOS 14+ and Swift 6 with the macOS SDK. The current desktop build bundles native art/branding and does not build or start the retained Habitat/Arena. Native assistance and memory remain the product owners; the separate Unity project is a disconnected companion/play preview.

Package-only checks are available through SwiftPM:

    swift build --package-path desktop
    swift test --package-path desktop

Some tests require opt-in windowed or provider prerequisites; read skipped checks separately. Quit a selected app normally before replacing its generated bundle. The build script checks running copies and preserves existing bundles during promotion.

Relationship-admission source evidence can be collected with
`python3 script/accept_relationship_admission.py` from the repository root. It
records missing native prerequisites as SKIPPED and keeps installed-app/restart
qualification separate. See [the acceptance guide](../docs/RELATIONSHIP_ADMISSION_ACCEPTANCE.md)
for paired QiMovi tests and the explicit local-model receipt option.

See [the root guide](../README.md), [architecture](../docs/ARCHITECTURE.md), [Node Lab](../docs/NODE_LAB.md), and [validation](../docs/ALPHA_VALIDATION.md). These commands describe available checks, not a claim that this exported revision passed them.
