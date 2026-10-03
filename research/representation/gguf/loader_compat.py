"""Apply one hash-pinned source patch; never rewrite installed model bytes."""
from pathlib import Path
import hashlib
import shutil

BACKEND = "llama.cpp:161755f29+archi-qwen35-mrope-v1"
UPSTREAM_SHA256 = "ef973e9c789eb52ef27a77e0b1f36c6f41a378733a994d41b5924e3be012f671"
TARGET = "src/models/qwen35.cpp"
HERE = Path(__file__).resolve().parent


def apply(source):
    target = source / TARGET
    before = target.read_bytes()
    if hashlib.sha256(before).hexdigest() != UPSTREAM_SHA256:
        raise ValueError("Qwen3.5 compatibility patch requires the exact pinned upstream source")
    original = "    ml.get_key_or_arr(LLM_KV_ROPE_DIMENSION_SECTIONS,    hparams.rope_sections, 4, true);"
    replacement = ("    std::vector<int32_t> archi_rope_sections;\n"
                   "    ml.get_arr(LLM_KV_ROPE_DIMENSION_SECTIONS, archi_rope_sections, true);\n"
                   "    hparams.rope_sections = archi_qwen35_mrope_sections(archi_rope_sections);")
    text = before.decode()
    if text.count(original) != 1:
        raise ValueError("Qwen3.5 patch anchor mismatch")
    target.write_text('#include "archi-qwen35-mrope-compat.h"\n' + text.replace(original, replacement))
    header = source / "src/models/archi-qwen35-mrope-compat.h"
    shutil.copyfile(HERE / "qwen35_mrope_compat.h", header)
    return {"id": "archi-qwen35-mrope-v1", "backend_revision": BACKEND,
            "target": TARGET, "upstream_sha256": UPSTREAM_SHA256,
            "patched_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "header_sha256": hashlib.sha256(header.read_bytes()).hexdigest(),
            "recipe_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "accepted_legacy_sections": [11, 11, 10], "normalized_sections": [11, 11, 10, 0],
            "model_bytes_modified": False}
