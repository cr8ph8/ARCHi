#!/usr/bin/env python3
"""Build only an arm64 CPU observation worker and its pinned llama.cpp libraries.

No model files, inference, servers, test targets, system installation, or settings
are touched. --fetch authorizes downloading the source archive only. Supply a
CMake executable, or use --bootstrap-cmake for an output-local PyPI install.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile

REVISION = "161755f29e415e2c33efe906e91843c068efd664"
ARCHIVE_SHA256 = "ea7b03494c2e9f24b5bcb6602c921fa413b868eb7f68fcf299eb6e84e361ea42"
ARCHIVE_URL = "https://github.com/ggml-org/llama.cpp/archive/161755f29.tar.gz"
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def run(*args: str | Path, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPO / "output/gguf-calibration-runtime-2026-09-25")
    parser.add_argument("--cmake", type=Path)
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--bootstrap-cmake", action="store_true")
    parser.add_argument("--qwen35-mrope-compat", action="store_true",
                        help="Opt in to the hash-pinned Qwen3.5 three-section loader patch with a distinct backend identity")
    parser.add_argument("--qwen35-text-compat", action="store_true",
                        help="Opt in to the exact-blob Ollama Qwen3.5 base-text adapter")
    args = parser.parse_args()
    if args.qwen35_mrope_compat and args.qwen35_text_compat:
        parser.error("Choose exactly one compatibility adapter")
    if sys.platform != "darwin" or platform.machine() != "arm64":
        raise SystemExit("This recipe supports native macOS arm64 only; no translation fallback.")
    output = args.output.resolve()
    if not output.is_relative_to(REPO / "output"):
        raise SystemExit("Build output must be under this checkout's ignored output/ directory.")
    if (args.qwen35_mrope_compat or args.qwen35_text_compat) and (output / "runtime").exists():
        raise SystemExit("Compatibility builds need a new output directory; preserve existing sealed runtimes.")
    downloads = output / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    archive = downloads / "llama.cpp-161755f29.tar.gz"
    if not archive.exists():
        if not args.fetch:
            raise SystemExit("Pinned source archive missing; use --fetch for source-only download.")
        run("/usr/bin/curl", "--fail", "--location", "--max-time", "120", ARCHIVE_URL, "--output", archive)
    if digest(archive) != ARCHIVE_SHA256:
        raise SystemExit("Source archive digest mismatch; refusing to compile.")
    source = output / "source"
    source.mkdir(exist_ok=True)
    # Restore exact archived files on every build; a prior cache edit is not authority.
    with tarfile.open(archive, "r:gz") as tar:
        prefix = f"llama.cpp-{REVISION}/"
        for member in tar.getmembers():
            if member.name == prefix[:-1]:
                continue
            if not member.name.startswith(prefix) or member.issym() or member.islnk():
                raise SystemExit("Unexpected archive member.")
            member.name = member.name[len(prefix):]
            if not member.name or not (source / member.name).resolve().is_relative_to(source):
                raise SystemExit("Unsafe archive path.")
            tar.extract(member, source, filter="data")
    compatibility_patch = None
    backend_revision = "llama.cpp:161755f29"
    if args.qwen35_mrope_compat:
        import loader_compat
        compatibility_patch = loader_compat.apply(source)
        backend_revision = loader_compat.BACKEND
    model_compile_flags = []
    if args.qwen35_text_compat:
        import text_loader_compat
        compatibility_patch = text_loader_compat.apply(source)
        backend_revision = text_loader_compat.BACKEND
        model_compile_flags = ['-DARCHI_QWEN35_BLOB="' + text_loader_compat.MODEL_BLOB + '"']
    cmake = args.cmake or output / "build-tools/cmake/data/bin/cmake"
    if not cmake.exists():
        system_cmake = shutil.which("cmake")
        if system_cmake:
            cmake = Path(system_cmake)
        elif args.bootstrap_cmake:
            run(sys.executable, "-m", "pip", "install", "--target", output / "build-tools", "cmake==4.1.3")
        else:
            raise SystemExit("CMake is missing; pass --cmake or --bootstrap-cmake for output-local installation.")
    build = output / "cmake"
    flags = ["-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DBUILD_SHARED_LIBS=ON",
             "-DLLAMA_BUILD_COMMON=OFF", "-DLLAMA_BUILD_TESTS=OFF", "-DLLAMA_BUILD_EXAMPLES=OFF",
             "-DLLAMA_BUILD_TOOLS=OFF", "-DLLAMA_BUILD_SERVER=OFF", "-DLLAMA_CURL=OFF",
             "-DGGML_METAL=OFF", "-DGGML_ACCELERATE=OFF", "-DGGML_BLAS=OFF", "-DGGML_OPENMP=OFF",
             "-DGGML_NATIVE=OFF", "-DGGML_BACKEND_DL=OFF", "-DLLAMA_BUILD_COMMIT=161755f29", "-DGIT_EXE:FILEPATH="]
    with (output / "configure.log").open("w") as log:
        run(cmake, "-S", source, "-B", build, *flags, stdout=log, stderr=subprocess.STDOUT)
    with (output / "compile.log").open("w") as log:
        run(cmake, "--build", build, "--target", "llama", "-j", "4", stdout=log, stderr=subprocess.STDOUT)
    runtime = output / "runtime"
    runtime.mkdir(exist_ok=True)
    # Copy real files to their ABI SONAMEs, avoiding fragile symlink chains.
    libraries = ["libllama.0.dylib", "libggml.0.dylib", "libggml-base.0.dylib", "libggml-cpu.0.dylib"]
    for library in libraries:
        target = runtime / library
        shutil.copyfile((build / "bin" / library).resolve(), target)
        # Strip absolute build rpaths. Dependencies use @rpath and the worker owns @loader_path.
        load_commands = run("/usr/bin/otool", "-l", target, capture_output=True, text=True).stdout
        for rpath in re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset", load_commands):
            run("/usr/bin/install_name_tool", "-delete_rpath", rpath, target)
        run("/usr/bin/install_name_tool", "-id", "@rpath/" + library, target)
        run("/usr/bin/codesign", "--force", "--sign", "-", target)
    worker = runtime / "archi-gguf-shadow"
    run("xcrun", "clang++", "-std=c++17", "-O2", "-arch", "arm64", "-Wno-deprecated-declarations",
        '-DARCHI_GGUF_BACKEND="' + backend_revision + '"',
        *model_compile_flags,
        HERE / "worker.cpp", "-I", source / "include", "-I", source / "ggml/include",
        "-I", source / "vendor/nlohmann", "-L", build / "bin", "-Wl,-rpath,@loader_path",
        "-lllama", "-lggml", "-lggml-base", "-o", worker)
    run("/usr/bin/codesign", "--force", "--sign", "-", worker)
    shutil.copyfile(HERE / "LLAMA_CPP_LICENSE", runtime / "LICENSE")
    shutil.copyfile(HERE / "JSON_LICENSE.MIT", runtime / "JSON_LICENSE.MIT")
    upstream_files = ["include/llama.h", "ggml/include/ggml.h", "ggml/include/ggml-cpu.h",
                      "ggml/include/ggml-backend.h", "ggml/include/ggml-opt.h", "ggml/include/gguf.h",
                      "ggml/include/ggml-alloc.h", "src/models/qwen3.cpp", "src/models/qwen35.cpp", "src/llama-model-loader.cpp", "vendor/nlohmann/json.hpp"]
    manifest = {
        "schema": "archi-gguf-worker-build/v1", "backend_revision": backend_revision,
        "upstream_revision": REVISION, "source_archive_url": ARCHIVE_URL,
        "source_archive_sha256": ARCHIVE_SHA256, "architecture": "arm64", "execution": "cpu",
        "mode": "shadow", "research_modes": ["acquire-calibration", "validate-calibration"],
        "shadow_token_rules": ["last", "prompt-last"],
        "model_loaded": False, "inference_executed": False,
        "worker_source_sha256": digest(HERE / "worker.cpp"), "recipe_sha256": digest(Path(__file__)),
        "task_assay_header_sha256": digest(HERE / "task_assay.h"),
        "compatibility_patch": compatibility_patch,
        "upstream_file_sha256": {
            path: (compatibility_patch["upstream_sha256"]
                   if compatibility_patch and path == compatibility_patch["target"] else digest(source / path))
            for path in upstream_files},
        "compiled_source_file_sha256": {path: digest(source / path) for path in upstream_files},
        "cmake_flags": flags,
        "runtime_sha256": {path.name: digest(path) for path in sorted(runtime.iterdir()) if path.name != "build-manifest.json" and path.is_file()},
        "compiler": run("xcrun", "clang++", "--version", capture_output=True, text=True).stdout.strip(),
        "cmake": run(cmake, "--version", capture_output=True, text=True).stdout.splitlines()[0],
    }
    (runtime / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(runtime)


if __name__ == "__main__":
    main()
