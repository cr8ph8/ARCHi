#!/bin/bash
set -euo pipefail

# Reuse the pinned, already installed Editor. No dependency installers or
# native-profile operations belong to this companion/play build.
ARCHI_REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARCHI_UNITY="/Applications/Unity/Hub/Editor/6000.5.4f1/Unity.app/Contents/MacOS/Unity"
ARCHI_PROJECT="$ARCHI_REPO/unity/ARCHi"
ARCHI_EVIDENCE="$ARCHI_REPO/output/unity-port-2026-09-16"
if [[ ! -x "$ARCHI_UNITY" || ! -f "$ARCHI_PROJECT/ProjectSettings/ProjectVersion.txt" ]]; then
    echo "The pinned Unity Editor or source project is unavailable." >&2
    exit 1
fi
mkdir -p "$ARCHI_EVIDENCE"
ARCHI_LOG="$ARCHI_EVIDENCE/editor-build-$(date +%Y%m%d-%H%M%S)-$$.log"
export DISABLE_TELEMETRY=true
export UNITY_MCP_DISABLE_TELEMETRY=true
export UNITY_MCP_STATUS_DIR="$ARCHI_EVIDENCE/mcp-status"
export UNITY_MCP_LOG_DIR="$ARCHI_EVIDENCE/mcp-logs"
echo "Building the Unity companion/play port. Log: $ARCHI_LOG"
"$ARCHI_UNITY" -batchmode -quit -projectPath "$ARCHI_PROJECT" \
    -buildTarget StandaloneOSX -executeMethod ARCHiPortBuild.BuildMac \
    -logFile "$ARCHI_LOG" "$@"
echo "Unity build finished. Inspect its build receipt before claiming runtime validation."
