import importlib.util
import tempfile
import unittest
import wave
from pathlib import Path
from types import SimpleNamespace

import numpy as np

work = Path(__file__).resolve().parents[2] / "desktop/Sources/ARCHiDesktop/Resources/QwenVoice/speech.py"
spec = importlib.util.spec_from_file_location("speech", work)
speech = importlib.util.module_from_spec(spec)
spec.loader.exec_module(speech)


class ModelFixture:
    def __init__(self):
        self.requests = []

    def get_supported_speakers(self):
        return ["serena", "vivian", "uncle_fu", "ryan", "aiden", "ono_anna", "sohee", "eric", "dylan"]

    def generate_custom_voice(self, **request):
        self.requests.append(request)
        yield SimpleNamespace(sample_rate=24000, audio=np.full(240, 0.2))


class VoiceWorkerTests(unittest.TestCase):
    def test_long_multilingual_passages_preserve_all_text(self):
        for text in ["First take. Second take! " * 30, "聲音。" * 240, "x" * 900, "One\nTwo\n" * 70]:
            parts = list(speech.passages(text))
            self.assertEqual("".join(parts), text)
            self.assertLessEqual(max(map(len, parts)), 220)

    def test_all_presets_keep_words_separate_from_direction_and_produce_wav(self):
        model = ModelFixture()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "take.wav"
            for voice in speech.VOICES:
                request = dict(voice=voice, text="Aloha, pH.", instruction="Pause after the greeting.")
                speech.render(model, request, path)
                self.assertEqual(model.requests[-1], dict(speaker=voice, text=request["text"],
                    instruct=request["instruction"], language="auto", verbose=False))
                with wave.open(str(path)) as reader:
                    self.assertEqual((reader.getframerate(), reader.getsampwidth(), reader.getnchannels(),
                                      reader.getnframes()), (24000, 2, 1, 240))
                    self.assertTrue(any(reader.readframes(240)))

    def test_invalid_requests_never_invoke_model(self):
        model = ModelFixture()
        for patch in [dict(voice="missing"), dict(text=" "), dict(instruction="x"*1025)]:
            request = dict(voice="Ryan", text="Aloha.", instruction="")
            request.update(patch)
            with self.assertRaises(ValueError):
                list(speech.speech_chunks(model, request))
        self.assertEqual(model.requests, [])


if __name__ == "__main__":
    unittest.main()
