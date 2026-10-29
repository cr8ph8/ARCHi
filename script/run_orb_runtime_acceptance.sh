#!/bin/bash
set -euo pipefail

# Opt-in synthetic Play Mode acceptance. Uses the installed Editor and a real
# graphics device; does not build/install the native app or open a user profile.
ARCHI_REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARCHI_PROJECT="$ARCHI_REPO/unity/ARCHi"
ARCHI_EDITOR="/Applications/Unity/Hub/Editor/6000.5.4f1/Unity.app/Contents/MacOS/Unity"
ARCHI_OUTPUT=""

usage() {
    cat <<'USAGE'
Usage: bash script/run_orb_runtime_acceptance.sh [--editor PATH] [--output NEW_DIRECTORY]

Runs OrbRoomRuntimeValidation.Validate in Unity 6000.5.4f1 with graphics enabled.
The default Editor is the pinned installation on the authoring Mac. --editor
selects another installed copy of that version; no Editor is downloaded.
The output directory must be new. The runner writes acceptance.json and PNG
captures; the adjacent .editor.log records import and Play Mode diagnostics.
The launcher stops its own Editor process after ten minutes without completion.
This is isolated room-renderer acceptance, separate from native app acceptance.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --editor|--output)
            [[ $# -ge 2 && -n "$2" ]] || { echo "$1 needs a value." >&2; exit 2; }
            if [[ "$1" == --editor ]]; then ARCHI_EDITOR="$2"; else ARCHI_OUTPUT="$2"; fi
            shift 2
            ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ ! -x "$ARCHI_EDITOR" ]]; then
    echo "Unity 6000.5.4f1 is unavailable at: $ARCHI_EDITOR" >&2
    echo "Run on the authoring Mac or use --editor with that installed Editor. No Unity run occurred." >&2
    exit 1
fi
if [[ ! -f "$ARCHI_PROJECT/ProjectSettings/ProjectVersion.txt" ]]; then
    echo "The ARCHi Unity source project is unavailable." >&2
    exit 1
fi
command -v python3 >/dev/null || { echo "Python 3 is required to verify the acceptance receipt." >&2; exit 1; }

if [[ -z "$ARCHI_OUTPUT" ]]; then
    ARCHI_OUTPUT="$ARCHI_REPO/output/orb-runtime-acceptance/run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi
# Resolve the destination once, before any output or Editor launch. A fresh
# evidence directory must not overlap source/assets or replace another run.
ARCHI_OUTPUT="$(python3 - "$ARCHI_REPO" "$ARCHI_OUTPUT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1]).resolve()
requested = pathlib.Path(sys.argv[2]).expanduser()
target = requested.resolve()
if requested.is_symlink() or target.exists():
    sys.exit('The acceptance output must be a new directory.')
if target == root or (root in target.parents and root / 'output' not in target.parents):
    sys.exit('Inside the source checkout, acceptance output must be beneath output/.')
if target == root / 'output':
    sys.exit('Use a new run directory beneath output/.')
print(target)
PY
)"
ARCHI_LOG="$ARCHI_OUTPUT.editor.log"
[[ ! -e "$ARCHI_LOG" && ! -L "$ARCHI_LOG" ]] || { echo "The adjacent Editor log already exists." >&2; exit 1; }
mkdir -p "$(dirname "$ARCHI_OUTPUT")"

export DISABLE_TELEMETRY=true
export UNITY_MCP_DISABLE_TELEMETRY=true
export UNITY_MCP_STATUS_DIR="${ARCHI_OUTPUT}.mcp-status"
export UNITY_MCP_LOG_DIR="${ARCHI_OUTPUT}.mcp-logs"
echo "Running isolated ARCHi orb acceptance. Editor log: $ARCHI_LOG"
# The runner must finish its asynchronous Play Mode work before exiting.
# Do not add -quit or -nographics: either can invalidate rendering evidence.
if python3 - "$ARCHI_EDITOR" "$ARCHI_PROJECT" "$ARCHI_OUTPUT" "$ARCHI_LOG" <<'PY'
import os, signal, subprocess, sys
editor, project, output, log = sys.argv[1:]
command = [editor, '-batchmode', '-projectPath', project,
           '-executeMethod', 'OrbRoomRuntimeValidation.Validate',
           '-archiOrbAcceptanceOutput', output, '-logFile', log]
# Only this invocation's process group is stopped on timeout/interruption.
process = subprocess.Popen(command, start_new_session=True)
try:
    code = process.wait(timeout=600)
    sys.exit(code if code >= 0 else 128 - code)
except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
    timed_out = isinstance(error, subprocess.TimeoutExpired)
    print('Orb acceptance timed out.' if timed_out else 'Orb acceptance interrupted.', file=sys.stderr)
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=10)
    except ProcessLookupError:
        pass
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(124 if timed_out else 130)
PY
then
    :
else
    ARCHI_EXIT=$?
    echo "Unity acceptance exited with status $ARCHI_EXIT. Inspect $ARCHI_LOG and any acceptance.json." >&2
    exit "$ARCHI_EXIT"
fi

python3 "$ARCHI_REPO/script/orb_runtime_receipt.py" --repo "$ARCHI_REPO" --output "$ARCHI_OUTPUT"
