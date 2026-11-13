#!/usr/bin/env bash
set -euo pipefail

# Exercises the exact production value check without importing AppKit, opening
# a personal profile, running a provider, or installing a native application.
repo_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
continuity_tmp="$(mktemp -d "${TMPDIR:-/tmp}/archi-continuity.XXXXXX")"
trap 'rm -rf -- "$continuity_tmp"' EXIT
swift_bin="${SWIFT_BIN:-swift}"

mkdir -p "$continuity_tmp/Sources/ARCHiDesktop" "$continuity_tmp/Tests/ARCHiDesktopTests"
cp "$repo_dir/desktop/Sources/ARCHiDesktop/KinGrowthContinuity.swift" "$continuity_tmp/Sources/ARCHiDesktop/"
cp "$repo_dir/desktop/Tests/ARCHiDesktopTests/KinGrowthContinuityTests.swift" "$continuity_tmp/Tests/ARCHiDesktopTests/"
cat > "$continuity_tmp/Package.swift" <<'SWIFT_PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ARCHiContinuityReplay", targets: [
    .target(name: "ARCHiDesktop"),
    .testTarget(name: "ARCHiDesktopTests", dependencies: ["ARCHiDesktop"])
])
SWIFT_PACKAGE

"$swift_bin" test --package-path "$continuity_tmp" -Xswiftc -warnings-as-errors "$@"
