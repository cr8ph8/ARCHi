"""Offline Qwen readings. A desktop session reuses its model until stopped."""
import argparse
from contextlib import redirect_stdout
import json
import os
import re
import sys
import uuid
import wave
from pathlib import Path

MODEL = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-4bit"
REVISION = "f35faf19b0cc2160865af64ecf0f22f83d335135"
VOICES = ("Ryan", "Aiden", "Vivian", "Serena", "Dylan", "Eric", "Sohee", "Ono_Anna", "Uncle_Fu")


def passages(text, limit=220):
    # Preserve all characters and prefer a natural break, including for CJK.
    while len(text) > limit:
        window = text[:limit]
        breaks = list(re.finditer(r"[.!?。！？](?:\s+|$)|\n+", window))
        if not breaks:
            breaks = list(re.finditer(r"\s+", window))
        end = breaks[-1].end() if breaks else limit
        yield text[:end]
        text = text[end:]
    if text:
        yield text


def speech_chunks(model, request):
    voice = request["voice"]
    text = request["text"]
    direction = request["instruction"]
    if (voice not in VOICES or voice.lower() not in {
        name.lower() for name in model.get_supported_speakers()
    } or not isinstance(text, str) or not text.strip() or len(text.encode()) > 65536
            or not isinstance(direction, str) or len(direction.encode()) > 1024):
        raise ValueError("Invalid voice, direction or reply")
    for part in passages(text):
        if part.strip():
            yield from model.generate_custom_voice(
                text=part, speaker=voice, language="auto", instruct=direction or None,
                verbose=False,
            )


def render(model, request, output=None):
    import numpy as np
    from contextlib import ExitStack

    with ExitStack() as stack:
        sink = None
        for result in speech_chunks(model, request):
            samples = np.asarray(result.audio, dtype=np.float32).reshape(-1)
            if result.sample_rate != 24000 or not len(samples) or not np.isfinite(samples).all():
                raise ValueError("Invalid Qwen audio")
            if sink is None:
                if output:
                    sink = stack.enter_context(wave.open(str(output), "wb"))
                    sink.setparams((1, 2, 24000, 0, "NONE", "not compressed"))
                else:
                    import sounddevice
                    sink = stack.enter_context(sounddevice.OutputStream(
                        samplerate=24000, channels=1, dtype="float32"))
            if output:
                sink.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())
            else:
                sink.write(samples)
        if sink is None:
            raise ValueError("Qwen returned no audio")


def serve(source, events, load, output_dir=None, seed=None):
    model = None
    for line in source:
        request = json.loads(line)
        request_id = str(uuid.UUID(request.pop("id")))
        with redirect_stdout(sys.stderr):
            if model is None:
                model = load()
            if seed is not None:
                import mlx.core as mx
                mx.random.seed(seed)
            path = output_dir / f"{request_id}.wav" if output_dir else None
            render(model, request, path)
        # The next utterance brings its own text, direction and speaker.
        del request, line
        events.write(request_id + "\n")
        events.flush()


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--install", action="store_true")
    mode.add_argument("--wav", type=Path, help="Write a single reading to a WAV")
    mode.add_argument("--session", action="store_true", help="Accept successive readings on stdin")
    parser.add_argument("--audition-dir", type=Path, help="Store seeded session takes for comparison")
    args = parser.parse_args()
    if args.audition_dir and not args.session:
        parser.error("--audition-dir requires --session")
    if not args.install:
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"
    from huggingface_hub import snapshot_download
    path = Path(snapshot_download(MODEL, revision=REVISION, local_files_only=not args.install))
    if args.install:
        config = json.loads((path / "config.json").read_text())
        installed = {name.lower() for name in config["talker_config"]["spk_id"]}
        if not {voice.lower() for voice in VOICES} <= installed:
            raise ValueError("Voice presets missing from snapshot")
        return

    def load():
        import mlx.core as mx
        if not mx.metal.is_available():
            mx.set_default_device(mx.cpu)
        from mlx_audio.tts.utils import load_model
        return load_model(path)

    if args.session:
        # Third-party native and Python libraries can both write to stdout.
        # Reserve a duplicate for the completion protocol before model loading.
        with os.fdopen(os.dup(1), "w", encoding="utf-8") as events:
            os.dup2(2, 1)
            serve(sys.stdin, events, load, args.audition_dir, 42 if args.audition_dir else None)
    else:
        render(load(), json.load(sys.stdin), args.wav)


if __name__ == "__main__":
    main()
