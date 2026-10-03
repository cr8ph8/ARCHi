#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash script/check_native_placement_cross_runtime.sh OUTPUT_DIRECTORY" >&2
  exit 2
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$1"
output_dir="$(cd "$1" && pwd)"
# Replace this runner's prior result immediately, so a failed compilation cannot
# leave an earlier passing report looking like the result of the current run.
printf '%s\n' '{"schema":"archi-cross-runtime-placement-report/v1","status":"pending","evidenceKind":"synthetic-test-inputs","actualUIObserved":false}' > "$output_dir/cross-runtime-report.json"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/archi-placement-fixtures.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

native_sources=()
for source in "$repo_root"/desktop/Sources/ARCHiDesktop/*.swift; do
  if [[ "$(basename "$source")" != "ARCHiDesktopApp.swift" ]]; then native_sources+=("$source"); fi
done
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
architecture="$(uname -m)"
xcrun --sdk macosx swiftc -parse-as-library -swift-version 6 \
  -target "$architecture-apple-macosx14.0" -sdk "$sdk_path" \
  -module-name ARCHiPlacementCrossRuntimeFixtures -module-cache-path "$build_dir/module-cache" \
  "${native_sources[@]}" "$repo_root/script/NativePlacementFixtures.swift" \
  -o "$build_dir/NativePlacementFixtures"
"$build_dir/NativePlacementFixtures" "$output_dir"
node "$repo_root/script/check_native_placement_fixtures.mjs" "$output_dir"
