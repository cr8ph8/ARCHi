#!/usr/bin/env python3
"""Exercise the text adapter against an in-memory metadata fixture, no weights."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

import text_loader_compat

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    args = parser.parse_args()
    inventory = json.loads(args.inventory.read_text())
    declarations = []
    for item in inventory["tensors"]:
        dims = ",".join(str(v) for v in item["shape"])
        declarations.append('{ const int64_t dims[] = {' + dims + '}; auto * t = ggml_new_tensor(ctx, (ggml_type)'
            + str(item["ggmlType"]) + ', ' + str(len(item["shape"])) + ', dims); ggml_set_name(t, '
            + json.dumps(item["name"]) + '); gguf_add_tensor(meta, t); }')
    code = '''#include "qwen35_text_compat.h"
#include <cassert>
#include <iostream>
struct Fixture {
    gguf_context * meta;
    ggml_context * ctx;
    Fixture() {
        ggml_init_params params{ggml_tensor_overhead() * 900, nullptr, true};
        ctx = ggml_init(params); meta = gguf_init_empty();
        gguf_set_val_str(meta, "general.architecture", "qwen35");
        gguf_set_val_bool(meta, "qwen35.ssm.v_head_reordered", true);
        gguf_set_val_u32(meta, "qwen35.block_count", 32);
        uint32_t heads[32]; for (int i=0; i<32; ++i) heads[i]=i%4==3?4:0;
        gguf_set_arr_data(meta, "qwen35.attention.head_count_kv", GGUF_TYPE_UINT32, heads, 32);
        const int32_t rope[3]={11,11,10};
        gguf_set_arr_data(meta, "qwen35.rope.dimension_sections", GGUF_TYPE_INT32, rope, 3);
        DECLARATIONS
    }
    ~Fixture() { gguf_free(meta); ggml_free(ctx); }
};
template<typename Edit> void rejected(Edit edit, bool mtp=false) {
    Fixture f; edit(f); bool threw=false;
    try { archi_qwen35_prepare_text(f.meta, f.ctx, mtp); } catch (const std::runtime_error &) { threw=true; }
    assert(threw);
}
int main() {
    {
        Fixture f;
        std::vector<size_t> offsets;
        for (int i=0; i<883; ++i) offsets.push_back(gguf_get_tensor_offset(f.meta, i));
        assert(archi_qwen35_prepare_text(f.meta, f.ctx, false));
        int kept=0, skipped=0;
        for (int i=0; i<883; ++i) {
            assert(offsets[i] == gguf_get_tensor_offset(f.meta, i));
            if (archi_qwen35_auxiliary(gguf_get_tensor_name(f.meta, i))) ++skipped; else ++kept;
        }
        assert(kept==427 && skipped==456);
        for (int i=0; i<32; ++i) if (i%4!=3) {
            auto name="blk."+std::to_string(i)+".ssm_dt";
            assert(gguf_find_tensor(f.meta, name.c_str()) < 0);
            assert(gguf_find_tensor(f.meta, (name+".bias").c_str()) >= 0);
            assert(ggml_get_tensor(f.ctx, (name+".bias").c_str())->ne[0] == 32);
        }
        assert(gguf_get_val_u32(f.meta, gguf_find_key(f.meta, "qwen35.attention.head_count_kv"))==4);
        assert(gguf_get_arr_n(f.meta, gguf_find_key(f.meta, "qwen35.rope.dimension_sections"))==4);
    }
    rejected([](Fixture &f){ gguf_set_val_bool(f.meta,"qwen35.ssm.v_head_reordered",false); });
    rejected([](Fixture &f){ gguf_set_val_u32(f.meta,"qwen35.block_count",31); });
    rejected([](Fixture &f){ gguf_set_val_u32(f.meta,"qwen35.nextn_predict_layers",1); });
    rejected([](Fixture &f){ uint32_t h[32]={}; gguf_set_arr_data(f.meta,"qwen35.attention.head_count_kv",GGUF_TYPE_UINT32,h,32); });
    rejected([](Fixture &f){ const int32_t s[3]={10,11,11}; gguf_set_arr_data(f.meta,"qwen35.rope.dimension_sections",GGUF_TYPE_INT32,s,3); });
    rejected([](Fixture &f){ auto * t=ggml_new_tensor_1d(f.ctx,GGML_TYPE_F32,32); ggml_set_name(t,"unexplained.text"); gguf_add_tensor(f.meta,t); });
    rejected([](Fixture &f){ ggml_set_name(ggml_get_tensor(f.ctx,"blk.0.ssm_dt"),"blk.0.ssm_dt.bias"); });
    rejected([](Fixture &f){ (void)f; }, true);
    assert(!archi_qwen35_auxiliary("blk.99.unexplained.weight"));
    assert(!archi_qwen35_auxiliary("mm.unexplained.weight"));
    assert(!archi_qwen35_auxiliary("vision.weight"));
    std::cout << "12 metadata fixture checks passed; no weights loaded\\n";
}
'''.replace("DECLARATIONS", "\n".join(declarations))
    with tempfile.TemporaryDirectory(prefix="archi-qwen35-text-check-") as scratch:
        root = Path(scratch)
        cpp = root / "check.cpp"
        cpp.write_text(code)
        runtime = args.runtime.resolve()
        subprocess.run(["xcrun", "clang++", "-std=c++17", "-I", str(HERE), "-I", str(args.source / "ggml/include"),
                        str(cpp), str(runtime / "libggml-base.0.dylib"), "-Wl,-rpath," + str(runtime), "-o", str(root / "check")], check=True)
        result = subprocess.run([str(root / "check")], text=True, capture_output=True, check=True)
        changed = root / text_loader_compat.TARGET
        changed.parent.mkdir(parents=True)
        changed.write_text("altered source")
        try:
            text_loader_compat.apply(root)
        except ValueError:
            pass
        else:
            raise AssertionError("Unpinned source accepted")
    print(json.dumps({"schema": "archi-qwen35-text-compat-checks/v1", "checksPassed": 13,
                      "metadataFixtureTensors": len(inventory["tensors"]), "modelLoaded": False,
                      "tensorDataRead": False, "result": result.stdout.strip()}))


if __name__ == "__main__":
    main()
