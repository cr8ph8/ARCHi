import json
import unittest
import uuid
from run import PHASES, verify


class MemoryReaderTests(unittest.TestCase):
    def setUp(self):
        self.topic, self.words = "Sol core", "The Sol core is amber."
        self.lesson = dict(id=str(uuid.uuid4()), revision=1, topic=self.topic, text=self.words,
                           reason="", createdAt=123, updatedAt=123)
        self.doc = dict(schema="archi-native-preferences/v5", revision=1, lessons=[self.lesson])
        self.saved = json.dumps(self.doc).encode()
        self.data = dict(zip(PHASES, (None, None, self.saved, self.saved, self.saved)))

    def read(self):
        return verify(self.data, self.topic, self.words)

    def test_expected_session(self):
        self.assertEqual(self.read()["status"], "PASS")

    def test_discard_writes_to_disk(self):
        self.data["discard"] = b'{}'
        with self.assertRaises(ValueError): self.read()

    def test_broken_keep_never_writes(self):
        self.data.update(keep=None, stale=None, reopen=None)
        with self.assertRaises(ValueError): self.read()

    def test_stale_or_reopen_change_even_one_byte(self):
        for name in ("stale", "reopen"):
            with self.subTest(name=name):
                self.data[name] += b' '
                with self.assertRaises(ValueError): self.read()
                self.data[name] = self.saved

    def test_missing_checkpoint(self):
        del self.data["discard"]
        with self.assertRaises(ValueError): self.read()

    def test_wrong_record_same_at_all_checkpoints(self):
        for change in ({"text": "Different"}, {"revision": True}, {"source": {"name": "Screenplay B"}}):
            with self.subTest(change=change):
                bad = json.dumps(dict(self.doc, lessons=[dict(self.lesson, **change)])).encode()
                self.data.update(keep=bad, stale=bad, reopen=bad)
                with self.assertRaises(ValueError): self.read()
