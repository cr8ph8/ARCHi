#!/usr/bin/env python3
"""Check the exact loader exception and source guard without loading a model."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import loader_compat

HERE = Path(__file__).resolve().parent


def main():
    with tempfile.TemporaryDirectory(prefix="archi-mrope-compat-") as scratch:
        root = Path(scratch)
        source = root / "check.cpp"
        source.write_text('''#include "qwen35_mrope_compat.h"
#include <cassert>
int main() {
    assert((archi_qwen35_mrope_sections({11,11,10}) == std::array<int32_t,4>{11,11,10,0}));
    assert((archi_qwen35_mrope_sections({11,11,10,0}) == std::array<int32_t,4>{11,11,10,0}));
    assert((archi_qwen35_mrope_sections({4,3,2,1}) == std::array<int32_t,4>{4,3,2,1}));
    for (const auto & value : std::vector<std::vector<int32_t>>{{}, {11}, {11,11}, {10,11,11}, {-1,11,10}, {11,11,10,0,0}}) {
        bool rejected = false;
        try { archi_qwen35_mrope_sections(value); } catch (const std::runtime_error &) { rejected = true; }
        assert(rejected);
    }
}
''')
        subprocess.run(["xcrun", "clang++", "-std=c++17", "-I", str(HERE), str(source), "-o", str(root / "check")], check=True)
        subprocess.run([str(root / "check")], check=True)
        changed = root / loader_compat.TARGET
        changed.parent.mkdir(parents=True)
        changed.write_text("changed source")
        try:
            loader_compat.apply(root)
        except ValueError:
            pass
        else:
            raise AssertionError("Unpinned source accepted")
    print(json.dumps({"schema": "archi-qwen35-compat-checks/v1", "checksPassed": 10,
                      "backendRevision": loader_compat.BACKEND, "modelLoaded": False,
                      "headerDigest": hashlib.sha256((HERE / "qwen35_mrope_compat.h").read_bytes()).hexdigest()}))


if __name__ == "__main__":
    main()
