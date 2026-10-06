// Scoped text-only interpretation of the installed Ollama Qwen3.5:9b GGUF.
// Semantics: ollama/ollama b2da9e468af2479058ae18c6d908ed29de410684,
// llama/compat/llama-ollama-compat.cpp, apply_qwen35_text_fixes.
// The worker additionally pins the complete original model-blob SHA256.
#pragma once
#include "gguf.h"
#include "ggml.h"
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

inline bool archi_qwen35_auxiliary(const std::string & name) {
    return name.rfind("v.", 0) == 0 || name.rfind("mtp.", 0) == 0;
}

inline void archi_qwen35_require(bool condition, const char * message) {
    if (!condition) throw std::runtime_error(message);
}

inline bool archi_qwen35_prepare_text(gguf_context * meta, ggml_context * ctx, bool load_mtp) {
    const int64_t architecture = gguf_find_key(meta, "general.architecture");
    if (architecture < 0 || gguf_get_kv_type(meta, architecture) != GGUF_TYPE_STRING ||
            std::strcmp(gguf_get_val_str(meta, architecture), "qwen35") != 0) return false;
    archi_qwen35_require(!load_mtp, "ARCHi Qwen3.5 compatibility supports the base text graph only");
    const int64_t reordered = gguf_find_key(meta, "qwen35.ssm.v_head_reordered");
    archi_qwen35_require(reordered >= 0 && gguf_get_kv_type(meta, reordered) == GGUF_TYPE_BOOL &&
                        gguf_get_val_bool(meta, reordered), "Expected already-reordered Ollama Qwen3.5 V heads");
    const int64_t nextn = gguf_find_key(meta, "qwen35.nextn_predict_layers");
    archi_qwen35_require(nextn < 0, "Native NextN metadata is outside this scoped legacy text adapter");
    const int64_t blocks = gguf_find_key(meta, "qwen35.block_count");
    archi_qwen35_require(blocks >= 0 && gguf_get_kv_type(meta, blocks) == GGUF_TYPE_UINT32 &&
                        gguf_get_val_u32(meta, blocks) == 32, "Expected the installed 32-block Qwen3.5 layout");
    const int64_t heads = gguf_find_key(meta, "qwen35.attention.head_count_kv");
    archi_qwen35_require(heads >= 0 && gguf_get_kv_type(meta, heads) == GGUF_TYPE_ARRAY &&
                        gguf_get_arr_type(meta, heads) == GGUF_TYPE_UINT32 && gguf_get_arr_n(meta, heads) == 32,
                        "Expected the installed per-layer KV-head array");
    const auto * values = static_cast<const uint32_t *>(gguf_get_arr_data(meta, heads));
    for (size_t i = 0; i < 32; ++i)
        archi_qwen35_require(values[i] == (i % 4 == 3 ? 4u : 0u), "Unexpected Qwen3.5 hybrid KV-head layout");
    const int64_t rope = gguf_find_key(meta, "qwen35.rope.dimension_sections");
    archi_qwen35_require(rope >= 0 && gguf_get_kv_type(meta, rope) == GGUF_TYPE_ARRAY &&
                        gguf_get_arr_type(meta, rope) == GGUF_TYPE_INT32 && gguf_get_arr_n(meta, rope) == 3,
                        "Expected the installed three-section Qwen3.5 RoPE layout");
    const auto * sections = static_cast<const int32_t *>(gguf_get_arr_data(meta, rope));
    archi_qwen35_require(sections[0] == 11 && sections[1] == 11 && sections[2] == 10,
                        "Unexpected Qwen3.5 RoPE sections");
    const int64_t count = gguf_get_n_tensors(meta);
    archi_qwen35_require(count == 883, "Unexpected installed Qwen3.5 tensor inventory");
    size_t vision = 0, mtp = 0;
    for (int64_t i = 0; i < count; ++i) {
        const std::string name = gguf_get_tensor_name(meta, i);
        vision += name.rfind("v.", 0) == 0;
        mtp += name.rfind("mtp.", 0) == 0;
    }
    archi_qwen35_require(vision == 441 && mtp == 15, "Unexpected Qwen3.5 auxiliary tensor inventory");
    std::vector<std::string> aliases;
    for (int i = 0; i < 32; ++i) {
        if (i % 4 == 3) continue;
        const std::string name = "blk." + std::to_string(i) + ".ssm_dt";
        const auto * tensor = ggml_get_tensor(ctx, name.c_str());
        archi_qwen35_require(tensor != nullptr && tensor->type == GGML_TYPE_F32 &&
                            tensor->ne[0] == 32 && tensor->ne[1] == 1 && tensor->ne[2] == 1 && tensor->ne[3] == 1 &&
                            gguf_find_tensor(meta, (name + ".bias").c_str()) < 0,
                            "Unexpected or ambiguous Qwen3.5 dt-bias tensor");
        aliases.push_back(name);
    }
    // Change in-memory metadata only. Tensor offsets, bytes and values stay exact.
    gguf_remove_key(meta, "qwen35.attention.head_count_kv");
    gguf_set_val_u32(meta, "qwen35.attention.head_count_kv", 4);
    const int32_t padded[4] = {11, 11, 10, 0};
    gguf_set_arr_data(meta, "qwen35.rope.dimension_sections", GGUF_TYPE_INT32, padded, 4);
    for (const auto & from : aliases) {
        const std::string to = from + ".bias";
        const int64_t id = gguf_find_tensor(meta, from.c_str());
        // Matches Ollama's rename_tensor helper: this API exposes the mutable
        // fixed char name storage with a const view, not a read-only allocation.
        char * name = const_cast<char *>(gguf_get_tensor_name(meta, id));
        std::strncpy(name, to.c_str(), GGML_MAX_NAME - 1);
        name[GGML_MAX_NAME - 1] = '\0';
        ggml_set_name(ggml_get_tensor(ctx, from.c_str()), to.c_str());
    }
    return true;
}
