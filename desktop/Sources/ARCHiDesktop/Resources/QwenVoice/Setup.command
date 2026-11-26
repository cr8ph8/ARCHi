#!/bin/bash
set -euo pipefail
[[ "$(uname -s)/$(uname -m)" == Darwin/arm64 ]] || { echo "Qwen voice setup requires an Apple silicon Mac."; exit 1; }
runtime="$HOME/Library/Application Support/ARCHi/QwenVoice"
worker="$(cd "$(dirname "$0")" && pwd)/speech.py"
interpreter=""
for candidate in "${ARCHI_VOICE_PYTHON:-}" python3.12 /opt/homebrew/bin/python3.12 python3.11 /opt/homebrew/bin/python3.11 python3; do
    if [[ -n "$candidate" ]] && command -v "$candidate" >/dev/null && "$candidate" -c 'import platform, sys; sys.exit(not (platform.machine() == "arm64" and (3, 11) <= sys.version_info[:2] <= (3, 13)))'; then
        interpreter="$candidate"
        break
    fi
done
[[ -n "$interpreter" ]] || { echo "Install arm64 Python 3.11–3.13 (for example python.org Python 3.12), then reopen Setup.command."; exit 1; }
mkdir -p "$runtime"
if [[ ! -x "$runtime/venv/bin/python" ]]; then "$interpreter" -m venv "$runtime/venv"; fi
python="$runtime/venv/bin/python"
echo "Installing the local voice engine and downloading the Qwen CustomVoice model."
"$python" -m pip install 'mlx-audio==0.6.8'
"$python" -c 'import mlx_audio.tts.models.qwen3_tts, sounddevice'
"$python" "$worker" --install
touch "$runtime/ready-0.6.8-f35faf1"
echo "ARCHi voices are ready. In ARCHi, open Connections and choose Preview voice."
