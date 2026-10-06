"""Hash-pinned, opt-in text-only adapter for the existing Ollama Qwen3.5 blob."""
from pathlib import Path
import hashlib
import shutil

BACKEND = "llama.cpp:161755f29+archi-qwen35-text-v1"
MODEL_BLOB = "dec52a44569a2a25341c4e4d3fee25846eed4f6f0b936278e3a3c900bb99d37c"
TARGET = "src/llama-model-loader.cpp"
UPSTREAM_SHA256 = "efdb5f273bd1ab77301f2cadea1a5a804bafb28040aca033e45605a97a450242"
HERE = Path(__file__).resolve().parent


def apply(source):
    target = source / TARGET
    before = target.read_bytes()
    if hashlib.sha256(before).hexdigest() != UPSTREAM_SHA256:
        raise ValueError("Text compatibility patch requires exact pinned loader source")
    text = before.decode()
    anchor = '        get_key(llm_kv(LLM_KV_GENERAL_ARCHITECTURE), arch_name, false);\n        llm_kv = LLM_KV(llm_arch_from_string(arch_name));'
    if text.count(anchor) != 3:
        raise ValueError("Loader metadata hook count changed")
    # Only the filename and verified FILE* branches have a parsed GGUF/context.
    replacement = ('        const bool archi_qwen35_text_only = archi_qwen35_prepare_text(metadata, ctx, load_mtp);\n' + anchor)
    text = text.replace(anchor, replacement, 2)
    index_anchor = '\n            std::string tensor_name = std::string(cur->name);'
    if text.count(index_anchor) != 2:
        raise ValueError("Main-file loader tensor index hook count changed")
    text = text.replace(index_anchor, index_anchor + '\n            if (archi_qwen35_text_only && archi_qwen35_auxiliary(tensor_name)) continue;')
    # Split-model paths are outside the exact single-blob worker binding.
    target.write_text('#include "archi-qwen35-text-compat.h"\n' + text)
    header = source / "src/archi-qwen35-text-compat.h"
    shutil.copyfile(HERE / "qwen35_text_compat.h", header)
    return {"id": "archi-qwen35-text-v1", "backend_revision": BACKEND,
            "target": TARGET, "upstream_sha256": UPSTREAM_SHA256,
            "patched_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "header_sha256": hashlib.sha256(header.read_bytes()).hexdigest(),
            "recipe_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "model_blob_sha256": MODEL_BLOB, "model_bytes_modified": False,
            "base_text_tensor_count": 427, "alias_count": 24,
            "excluded_auxiliary_tensors": {"vision": 441, "mtp": 15},
            "official_ollama_revision": "b2da9e468af2479058ae18c6d908ed29de410684"}
