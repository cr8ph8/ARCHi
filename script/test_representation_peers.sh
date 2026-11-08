#!/usr/bin/env bash
set -euo pipefail

# Run the same Foundation-only source and XCTest files used by the desktop target.
# SwiftUI/AppKit and the native desktop application are not exercised here.
if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [swift-executable]\n' "$0" >&2
  exit 2
fi
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  printf 'Usage: %s [swift-executable]\nUses SWIFT_BIN or swift on PATH when no argument is supplied.\n' "$0"
  exit 0
fi

swift_bin=${1:-${SWIFT_BIN:-swift}}
if [[ "$swift_bin" != */* ]]; then
  swift_bin=$(command -v "$swift_bin") || {
    printf 'Swift executable not found: %s\n' "${1:-${SWIFT_BIN:-swift}}" >&2
    exit 2
  }
fi
if [[ ! -f "$swift_bin" || ! -x "$swift_bin" ]]; then
  printf 'Swift executable must be an executable file: %s\n' "$swift_bin" >&2
  exit 2
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_workspace=$(mktemp -d "${TMPDIR:-/tmp}/archi-peer-tests.XXXXXXXX")
trap 'rm -rf -- "$test_workspace"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$test_workspace/Sources/ARCHiDesktop" "$test_workspace/Tests/RepresentationPeerTests" \
  "$test_workspace/module-cache" "$test_workspace/cache"

for source_file in RepresentationPeerDomain.swift PeerObservationDirectory.swift PeerWorkSession.swift PeerGossipSimulation.swift; do
  cp -- "$repo_root/desktop/Sources/ARCHiDesktop/$source_file" "$test_workspace/Sources/ARCHiDesktop/$source_file"
done
cp -- "$repo_root/desktop/Tests/ARCHiDesktopTests/RepresentationPeerTests.swift" \
  "$test_workspace/Tests/RepresentationPeerTests/RepresentationPeerTests.swift"

cat > "$test_workspace/Package.swift" <<'SWIFT_PACKAGE'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARCHiPeerCoreValidation",
    products: [.library(name: "ARCHiDesktop", targets: ["ARCHiDesktop"])],
    targets: [
        .target(name: "ARCHiDesktop"),
        .testTarget(name: "RepresentationPeerTests", dependencies: ["ARCHiDesktop"])
    ]
)
SWIFT_PACKAGE

printf 'Running actual ARCHi Foundation core and shared XCTest file. Native SwiftUI/AppKit tests are excluded.\n'
"$swift_bin" --version
CLANG_MODULE_CACHE_PATH="$test_workspace/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$test_workspace/module-cache" \
  "$swift_bin" test --package-path "$test_workspace" --scratch-path "$test_workspace/build" \
  --cache-path "$test_workspace/cache" --disable-sandbox --jobs 2
