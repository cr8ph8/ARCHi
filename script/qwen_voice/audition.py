"""Render two takes of the same line with the installed ARCHi voice environment."""
import json
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

root = Path(__file__).resolve().parents[2]
worker = root / "desktop/Sources/ARCHiDesktop/Resources/QwenVoice/speech.py"
destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
for speaker, instruction in [("Ryan", "Warm and conversational."), ("Vivian", "Bright and curious.")]:
    path = destination / f"{speaker}.wav"
    request = dict(text="Aloha. Ready for another take?", voice=speaker, instruction=instruction)
    subprocess.run([sys.executable, str(worker), "--wav", str(path)], check=True,
                   input=json.dumps(request), text=True)
    with wave.open(str(path)) as reader:
        rate = reader.getframerate()
        frames = reader.getnframes()
        samples = np.frombuffer(reader.readframes(frames), dtype="<i2").astype(float)
        if not (rate == 24000 and rate // 2 < frames < 30 * rate and np.sqrt(np.mean(samples**2)) > 30):
            raise ValueError(f"{speaker}: invalid or silent audio")
        print(f"{speaker}: {frames / rate:.2f} seconds at {rate} Hz", flush=True)
