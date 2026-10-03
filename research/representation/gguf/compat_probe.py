#!/usr/bin/env python3
"""Prepare or execute one bounded fit-sample extraction, never calibration fitting.

The original sample is public synthetic data from the failed loader run. Only
its first fit sample is used. This probe cannot produce an importable reader.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import resource
import subprocess
import time
import uuid

from calibrate import encoded, read, save, sha, REPO
from loader_compat import BACKEND


def file_sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def prepare(output, original, worker, backend=BACKEND):
    request = read(original, 1024 * 1024)
    if request["model_name"] != "qwen3.5:9b" or request["samples"][0]["sample_id"] != "record-01-1":
        raise ValueError("Probe requires the original Qwen3.5 first fit sample")
    request["samples"] = request["samples"][:1]
    request.update(run_id=str(uuid.uuid4()), backend_revision=backend,
                   samples_payload=encoded(request["samples"]), max_total_input_tokens=512, deadline_ms=120000)
    request["samples_payload_digest"] = sha(request["samples_payload"])
    output.mkdir(parents=True, exist_ok=False)
    save(output / "request.json", request)
    save(output / "plan.json", {"schema": "archi-qwen35-loader-probe/v1", "model": request["model_name"],
        "sourceRequestDigest": file_sha(original), "requestDigest": file_sha(output / "request.json"),
        "workerDigest": file_sha(worker), "backendRevision": backend, "maxCalls": 1,
        "maxInputTokens": 512, "maxGeneratedTokens": 0, "deadlineSeconds": 120,
        "estimatedPeakRAMGiB": 8, "readerQualification": False, "heldoutSamples": 0})


def execute(output, worker):
    request, plan = read(output / "request.json"), read(output / "plan.json")
    manifest = read(worker.parent / "build-manifest.json")
    if (manifest["backend_revision"] != plan["backendRevision"] or request["backend_revision"] != plan["backendRevision"]
            or file_sha(worker) != plan["workerDigest"]
            or file_sha(output / "request.json") != plan["requestDigest"]):
        raise ValueError("Probe/runtime binding changed")
    for name, digest in manifest["runtime_sha256"].items():
        if Path(name).name != name or file_sha(worker.parent / name) != digest:
            raise ValueError("Runtime member changed")
    validation = subprocess.run([str(worker), "--validate-calibration"], input=encoded(request),
                                text=True, capture_output=True, timeout=8, check=True)
    save(output / "validation.json", json.loads(validation.stdout))
    save(output / "started.json", {"startedUnix": time.time(), "requestDigest": plan["requestDigest"]})
    started = time.monotonic()
    timed_out = False
    with (output / "result.json").open("xb") as stdout, (output / "worker.log").open("xb") as stderr:
        child = subprocess.Popen([str(worker), "--acquire-calibration"], stdin=subprocess.PIPE,
                                 stdout=stdout, stderr=stderr, env={"PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"})
        try:
            child.communicate(encoded(request).encode(), timeout=125)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            timed_out = True
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill(); child.wait()
    receipt = {"schema": "archi-qwen35-loader-probe-receipt/v1", "exitCode": child.returncode,
        "timedOut": timed_out, "elapsedSeconds": time.monotonic() - started,
        "maxResidentBytes": resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
        "resultDigest": file_sha(output / "result.json"), "requestDigest": plan["requestDigest"],
        "workerDigest": plan["workerDigest"], "readerProduced": False, "qualificationAttempted": False,
        "extractionValidated": False}
    if child.returncode == 0:
        observed = read(output / "result.json")
        valid = (observed.get("status") == "ok" and observed.get("sample_count") == 1
                 and observed.get("generated_tokens") == 0 and observed.get("hidden_width") == 4096
                 and observed.get("context_policy") == "fresh-context-per-sample"
                 and observed.get("token_rule") == "prompt-last")
        for key in ("run_id", "model_name", "model_digest", "model_blob_digest", "tokenizer_digest",
                    "template_digest", "backend_revision", "precision", "layer", "dataset_digest", "samples_payload_digest"):
            valid = valid and observed.get(key) == request[key]
        rows = observed.get("samples", [])
        valid = valid and len(rows) == 1
        if valid:
            row, offered = rows[0], request["samples"][0]
            vector = row.get("activation", [])
            valid = (len(vector) == 4096 and all(isinstance(v, (float, int)) and math.isfinite(v) for v in vector)
                     and any(v != 0 for v in vector) and row.get("layer") == request["layer"]
                     and 1 <= row.get("input_tokens", 0) <= 512
                     and row.get("token_position") == row["input_tokens"] - 1)
            for key in ("sample_id", "prompt_digest", "input_digest", "system_digest", "schema_digest"):
                valid = valid and row.get(key) == offered[key]
            valid = valid and observed.get("total_input_tokens") == row["input_tokens"]
        receipt["extractionValidated"] = bool(valid)
        receipt["inputTokens"] = observed.get("total_input_tokens")
    save(output / "receipt.json", receipt)
    print(encoded(receipt))
    if not receipt["extractionValidated"]:
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["prepare", "execute"])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--source-request", type=Path)
    parser.add_argument("--backend", choices=[BACKEND, "llama.cpp:161755f29+archi-qwen35-text-v1"], default=BACKEND)
    args = parser.parse_args()
    output, worker = args.output.resolve(), args.worker.resolve()
    if not output.is_relative_to(REPO / "output"):
        raise ValueError("Probe artifacts must remain under checkout output/")
    if args.stage == "prepare":
        if not args.source_request:
            raise ValueError("Pass the preserved source request")
        prepare(output, args.source_request.resolve(), worker, args.backend)
    else:
        execute(output, worker)


if __name__ == "__main__":
    main()
