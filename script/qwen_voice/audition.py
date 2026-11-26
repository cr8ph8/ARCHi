"""Record the nine ARCHi voices and compare cold and warm reads of the same line."""
import hashlib
import json
import statistics
import subprocess
import sys
import uuid
import wave
from contextlib import contextmanager
from pathlib import Path
from time import perf_counter

import numpy as np

root = Path(__file__).resolve().parents[2]
worker = root / "desktop/Sources/ARCHiDesktop/Resources/QwenVoice/speech.py"
destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
line = "Aloha. Ready for another take?"
direction = "Warm and conversational."
voices = ["Ryan", "Aiden", "Vivian", "Serena", "Dylan", "Eric", "Sohee", "Ono_Anna", "Uncle_Fu"]


@contextmanager
def session():
    with subprocess.Popen([sys.executable, str(worker), "--session", "--audition-dir", str(destination)],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as child:
        try:
            yield child
        finally:
            child.stdin.close()
            if child.wait(timeout=20):
                raise RuntimeError("Qwen worker exited with an error")


def record(child, speaker, start):
    key = str(uuid.uuid4())
    child.stdin.write(json.dumps(dict(id=key, text=line, voice=speaker, instruction=direction)) + "\n")
    child.stdin.flush()
    if child.stdout.readline().strip() != key:
        raise RuntimeError(f"{speaker}: missing completion")
    elapsed = perf_counter() - start
    path = destination / f"{key}.wav"
    with wave.open(str(path)) as reader:
        rate, frames = reader.getframerate(), reader.getnframes()
        samples = np.frombuffer(reader.readframes(frames), dtype="<i2").astype(float)
        if not (rate == 24000 and reader.getsampwidth() == 2 and reader.getnchannels() == 1 and
                rate // 2 < frames < 30 * rate and np.sqrt(np.mean(samples**2)) > 30):
            raise ValueError(f"{speaker}: invalid or silent WAV")
    data = {"speaker": speaker, "seconds": round(frames / rate, 3),
            "render_seconds": round(elapsed, 3), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    print(f"{speaker}: {elapsed:.2f}s for {frames / rate:.2f}s of audio", flush=True)
    return path, data


pairs, assets = [], []
for index, speaker in enumerate(voices[:3]):
    cold_start = perf_counter()
    with session() as child:
        cold_path, cold = record(child, speaker, cold_start)
        cold_path.unlink()
        warm_path, warm = record(child, speaker, perf_counter())
        warm_path.replace(destination / f"{speaker}.wav")
        pairs.append({"speaker": speaker, "cold_seconds": cold["render_seconds"],
                      "warm_seconds": warm["render_seconds"], "same_wav": warm["sha256"] == cold["sha256"]})
        assets.append(warm)
        if index == 2:
            for remaining in voices[3:]:
                wav, asset = record(child, remaining, perf_counter())
                wav.replace(destination / f"{remaining}.wav")
                assets.append(asset)

report = {"text": line, "instruction": direction, "seed": 42,
          "model": "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-4bit",
          "revision": "f35faf19b0cc2160865af64ecf0f22f83d335135", "mlx_audio": "0.6.8",
          "measurement": "Host wall time through completed WAV on one Mac runner; cold includes process startup.",
          "paired_runs": pairs, "median_cold_seconds": statistics.median(p["cold_seconds"] for p in pairs),
          "median_warm_seconds": statistics.median(p["warm_seconds"] for p in pairs), "assets": assets}
(destination / "auditions.json").write_text(json.dumps(report, indent=2) + "\n")
