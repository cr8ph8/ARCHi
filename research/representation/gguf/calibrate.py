#!/usr/bin/env python3
"""Prepare, acquire and fit one bounded synthetic-record reader; no cloud calls.

Each stage has a separate explicit command. Qualification failure produces a
report, never an importable reader. No held-out-driven retry or search exists.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import struct
import sys
import time
import uuid

import corpus

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SCOPE = corpus.SCOPE
BACKEND = "llama.cpp:161755f29"
TEMPLATE = corpus.TEMPLATE


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def sha(value):
    return hashlib.sha256(value if isinstance(value, bytes) else value.encode()).hexdigest()


def save(path, value):
    with path.open("x", encoding="utf-8") as stream:
        stream.write(encoded(value) + "\n")


def read(path, limit=16 * 1024 * 1024):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > limit:
        raise ValueError("Expected a bounded regular file: " + str(path))
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON key")
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite JSON")))


def source_digests():
    return {"numericsSourceDigest": sha((HERE.parent / "archi_repe/numerics.py").read_bytes()),
            "workflowSourceDigest": sha(Path(__file__).read_bytes()),
            "corpusSourceDigest": sha((HERE / "corpus.py").read_bytes()),
            "workerSourceDigest": sha((HERE / "worker.cpp").read_bytes()),
            "runtimeRecipeDigest": sha((HERE / "build.py").read_bytes())}


def model_identity(model_name):
    if model_name not in ("qwen3:8b", "qwen3.5:9b"):
        raise ValueError("Unsupported model")
    model_root = Path.home() / ".ollama/models"
    family, tag = model_name.split(":")
    manifest_path = model_root / "manifests/registry.ollama.ai/library" / family / tag
    manifest = read(manifest_path, 256 * 1024)
    model_layers = [v for v in manifest["layers"] if v["mediaType"] == "application/vnd.ollama.image.model"]
    if len(model_layers) != 1:
        raise ValueError("Expected exactly one installed GGUF blob")
    blob_digest = model_layers[0]["digest"].removeprefix("sha256:")
    if not re.fullmatch(r"[a-f0-9]{64}", blob_digest):
        raise ValueError("Invalid installed model digest")
    return sha(manifest_path.read_bytes()), blob_digest, str(model_root / ("blobs/sha256-" + blob_digest))


def provenance(value, raw, external):
    return {"kind": "external-frozen-synthetic" if external else "builtin-disclosed-development",
            "sourceDigest": sha(raw), "corpusDigest": sha(raw), "canonicalDigest": sha(encoded(value)),
            "validation": corpus.VALIDATION, "pairInventory": "exact-lexical-words-and-punctuation",
            "priorExposure": "not-established" if external else "disclosed-development-input",
            "limitation": "Frozen for this local attempt. Prior inspection or use elsewhere is not established."
                if external else "Disclosed built-in corpus: development diagnostics only; never qualifies a reader."}


def make_plan(model_name, backend, dataset_digest, corpus_provenance, eligible):
    if backend not in (BACKEND, "llama.cpp:161755f29+archi-qwen35-mrope-v1", "llama.cpp:161755f29+archi-qwen35-text-v1"):
        raise ValueError("Unsupported backend")
    manifest_digest, blob_digest, _ = model_identity(model_name)
    return {"schema": "archi-reader-plan/v1", "algorithm": "mean_contrast_reader", "layer": "l_out-15",
            "tokenRule": "prompt-last", "measurementScope": SCOPE, "hiddenWidth": 4096,
            "fitPairs": 4, "calibrationPairs": 4, "holdoutPairs": 4, "minimumSignedMargin": 0.1,
            "requiresPerfectCalibrationSeparation": True, "requiresAllHoldoutCorrect": True,
            "layerSearch": False, "algorithmSearch": False, "heldoutRetries": False,
            "modelName": model_name, "modelDigest": manifest_digest, "modelBlobDigest": blob_digest,
            "templateDigest": sha(TEMPLATE), "backendRevision": backend, "datasetDigest": dataset_digest,
            **source_digests(), "corpusProvenance": corpus_provenance, "qualificationEligible": eligible,
            "limitation": "Twelve synthetic record-lookup groups, four held out. Not general chat or truth qualification."}


def make_request(plan, samples, run_id):
    if str(uuid.UUID(run_id)) != run_id:
        raise ValueError("Invalid acquisition identity")
    payload = encoded(samples)
    return {"schema": "archi-gguf-calibration-request/v1", "run_id": run_id,
            "purpose": "synthetic-reader-calibration", "synthetic_only": True,
            "model_name": plan["modelName"], "model_digest": plan["modelDigest"], "model_blob_digest": plan["modelBlobDigest"],
            "model_path": model_identity(plan["modelName"])[2], "tokenizer_digest": plan["modelBlobDigest"],
            "template_digest": plan["templateDigest"], "backend_revision": plan["backendRevision"],
            "precision": "Q4_K_M", "layer": plan["layer"], "max_input_tokens": 512,
            "max_total_input_tokens": 8192, "deadline_ms": 540000, "samples": samples,
            "samples_payload": payload, "samples_payload_digest": sha(payload), "dataset_digest": plan["datasetDigest"]}


def prepare(output, model_name, backend=BACKEND, corpus_path=None, corpus_digest=None):
    external = corpus_path is not None
    if external:
        if (corpus_path.is_symlink() or not corpus_path.is_file() or corpus_path.stat().st_size > corpus.MAX_BYTES
                or not isinstance(corpus_digest, str) or not re.fullmatch(r"[a-f0-9]{64}", corpus_digest)):
            raise ValueError("Supply a bounded regular --corpus and its explicit --corpus-sha256 before preparing")
        raw = corpus_path.read_bytes()
        if sha(raw) != corpus_digest:
            raise ValueError("Selected corpus digest mismatch")
        value = corpus.decode(raw)
    else:
        if corpus_digest is not None:
            raise ValueError("A corpus digest requires an external corpus")
        value = corpus.builtin()
        raw = (encoded(value) + "\n").encode()
    dataset, samples = corpus.build(value, external=external)
    plan = make_plan(model_name, backend, sha(encoded(dataset) + "\n"), provenance(value, raw, external), external)
    request = make_request(plan, samples, str(uuid.uuid4()))
    plan["requestDigest"] = sha(encoded(request) + "\n")
    output.mkdir(parents=True, exist_ok=False)
    with (output / "frozen-corpus.json").open("xb") as stream:
        stream.write(raw)
    save(output / "dataset.json", dataset)
    save(output / "plan.json", plan)
    save(output / "acquisition-request.json", request)
    save(output / "preparation-receipt.json", {"schema": "archi-reader-preparation/v1",
         "planDigest": sha((output / "plan.json").read_bytes()), "requestDigest": plan["requestDigest"],
         "datasetDigest": plan["datasetDigest"], "corpusDigest": sha(raw), "preparedAtUnix": time.time()})
    print("Prepared 24 synthetic prefills: 8 fit, 8 calibration, 8 held out in this frozen split. "
          + ("Eligible for one local qualification attempt; prior exposure elsewhere is unknown. " if external
             else "Disclosed development-only corpus; reader export is disabled. ") + "No model loaded.", flush=True)


def validate_prepared(output):
    """Reconstruct all data and fixed decisions before any worker starts."""
    plan, dataset, request, preparation = [read(output / name, 1024 * 1024) for name in
        ("plan.json", "dataset.json", "acquisition-request.json", "preparation-receipt.json")]
    frozen_path = output / "frozen-corpus.json"
    value = read(frozen_path, corpus.MAX_BYTES)
    raw = frozen_path.read_bytes()
    kind = plan.get("corpusProvenance", {}).get("kind")
    if kind not in ("external-frozen-synthetic", "builtin-disclosed-development"):
        raise ValueError("Missing explicit frozen corpus provenance")
    external = kind == "external-frozen-synthetic"
    if not external and encoded(value) != encoded(corpus.builtin()):
        raise ValueError("Development corpus differs from disclosed built-in")
    regenerated_dataset, samples = corpus.build(value, external=external)
    expected_plan = make_plan(plan["modelName"], plan["backendRevision"], sha(encoded(regenerated_dataset) + "\n"),
                              provenance(value, raw, external), external)
    expected_request = make_request(expected_plan, samples, request["run_id"])
    expected_plan["requestDigest"] = sha(encoded(expected_request) + "\n")
    if (encoded(dataset) != encoded(regenerated_dataset) or encoded(plan) != encoded(expected_plan)
            or encoded(request) != encoded(expected_request)):
        raise ValueError("Prepared corpus, labels, sources, plan or request changed")
    if (preparation.get("schema") != "archi-reader-preparation/v1"
            or preparation.get("planDigest") != sha((output / "plan.json").read_bytes())
            or preparation.get("requestDigest") != sha((output / "acquisition-request.json").read_bytes())
            or preparation.get("datasetDigest") != sha((output / "dataset.json").read_bytes())
            or preparation.get("corpusDigest") != sha(raw)
            or plan["datasetDigest"] != preparation["datasetDigest"]
            or plan["requestDigest"] != preparation["requestDigest"]):
        raise ValueError("Preparation receipt does not bind the exact frozen files")
    return plan, dataset, request


def require_fresh(output, names):
    if any((output / name).exists() or (output / name).is_symlink() for name in names):
        raise ValueError("This output already records an attempt; retries and overwrites are forbidden")


def numeric_digest(numeric):
    """Cross-language binding: prefix then little-endian Float64 in fixed order."""
    values = numeric["directions"][0] + numeric["center"] + numeric["scoreOffset"] + numeric["scoreScale"]
    return sha(b"archi-reader-numerics/v1\n" + struct.pack("<" + "d" * len(values), *values))


def reader_eligible(plan, numerical_pass):
    return numerical_pass and plan["qualificationEligible"] is True and plan["corpusProvenance"]["kind"] == "external-frozen-synthetic"


def acquire(output, worker):
    require_fresh(output, ["acquisition-start.json", "activations.json", "acquisition.log", "acquisition-receipt.json",
                           "fit-start.json", "frozen-fit.json", "calibration-report.json", "reader.json"])
    plan, _, request = validate_prepared(output)
    manifest = read(worker.parent / "build-manifest.json", 65536)
    if (manifest.get("worker_source_sha256") != plan["workerSourceDigest"]
            or manifest.get("recipe_sha256") != plan["runtimeRecipeDigest"]):
        raise ValueError("Prepared worker sources and sealed runtime differ")
    if manifest["backend_revision"] != plan["backendRevision"] or request["backend_revision"] != plan["backendRevision"]:
        raise ValueError("Prepared plan and worker backend differ")
    if sha(worker.read_bytes()) != manifest["runtime_sha256"][worker.name]:
        raise ValueError("Worker hash mismatch")
    for name, expected in manifest["runtime_sha256"].items():
        if Path(name).name != name or sha((worker.parent / name).read_bytes()) != expected:
            raise ValueError("Runtime member changed")
    # One explicit acquisition per prepared output directory. Failed runs remain
    # attributable; creating a new run cannot preserve 'untouched' after review.
    save(output / "acquisition-start.json", {"requestDigest": sha((output / "acquisition-request.json").read_bytes()),
         "workerDigest": sha(worker.read_bytes()), "planDigest": sha((output / "plan.json").read_bytes()),
         "preparationDigest": sha((output / "preparation-receipt.json").read_bytes()), "startedAtUnix": time.time()})
    stdout_path = output / "activations.json"
    started = time.monotonic()
    child, failure, cause = None, None, None
    try:
        with stdout_path.open("xb") as stdout, (output / "acquisition.log").open("xb") as stderr:
            child = subprocess.Popen([str(worker), "--acquire-calibration"], stdin=subprocess.PIPE,
                                     stdout=stdout, stderr=stderr, env={"PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"})
            child.communicate(encoded(request).encode(), timeout=550)
    except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        failure = error
        cause = "timeout" if isinstance(error, subprocess.TimeoutExpired) else "interrupted"
    except Exception as error:
        failure, cause = error, "launch-or-transport-error"
    finally:
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    elapsed = time.monotonic() - started
    exit_code = child.returncode if child is not None else None
    if cause is None and exit_code != 0:
        cause = "worker-exit"
    digest = hashlib.sha256()
    byte_count = 0
    if stdout_path.is_file():
        with stdout_path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                byte_count += len(block)
                digest.update(block)
    receipt = {"status": "complete" if cause is None else "failed", "failureCause": cause,
               "exitCode": exit_code, "elapsedSeconds": elapsed,
               "activationBytes": byte_count, "activationDigest": digest.hexdigest() if stdout_path.is_file() else None,
               "generatedTokenBudget": 0, "inputBudget": 8192,
               "requestDigest": sha((output / "acquisition-request.json").read_bytes()),
               "planDigest": sha((output / "plan.json").read_bytes())}
    # A budget is not an observation. Only a completed worker result may report
    # actual generated tokens; partial/error output leaves that quantity unknown.
    if cause is None:
        try:
            observed = read(stdout_path)
            if (observed.get("schema") == "archi-gguf-calibration-result/v1" and observed.get("status") == "ok"
                    and observed.get("run_id") == request["run_id"]
                    and type(observed.get("generated_tokens")) is int):
                receipt["generatedTokens"] = observed["generated_tokens"]
        except (ValueError, OSError):
            pass
    save(output / "acquisition-receipt.json", receipt)
    if failure is not None:
        raise failure
    if cause is not None:
        raise RuntimeError("Calibration acquisition failed; see acquisition receipt, log and activations")
    print("Activation acquisition complete; no answer-generation budget was provided.", flush=True)


def fit(output):
    require_fresh(output, ["fit-start.json", "frozen-fit.json", "calibration-report.json", "reader.json"])
    plan, dataset, request = validate_prepared(output)
    observed = read(output / "activations.json")
    start, receipt = [read(output / name) for name in ("acquisition-start.json", "acquisition-receipt.json")]
    if (receipt.get("exitCode") != 0
            or receipt.get("activationDigest") != sha((output / "activations.json").read_bytes())
            or start.get("requestDigest") != sha((output / "acquisition-request.json").read_bytes())
            or start.get("planDigest") != sha((output / "plan.json").read_bytes())
            or start.get("preparationDigest") != sha((output / "preparation-receipt.json").read_bytes())):
        raise ValueError("Acquisition receipts do not bind a successful unchanged result")
    if (sha((output / "dataset.json").read_bytes()) != plan["datasetDigest"]
            or sha((HERE.parent / "archi_repe/numerics.py").read_bytes()) != plan["numericsSourceDigest"]
            or sha(Path(__file__).read_bytes()) != plan["workflowSourceDigest"]):
        raise ValueError("Frozen plan sources changed")
    save(output / "fit-start.json", {"planDigest": sha((output / "plan.json").read_bytes()),
         "activationDigest": sha((output / "activations.json").read_bytes()), "startedAtUnix": time.time()})
    import numpy as np
    sys.path.insert(0, str(HERE.parent))
    from archi_repe.numerics import mean_contrast_reader, standardized_assay
    if observed.get("schema") != "archi-gguf-calibration-result/v1" or observed.get("status") != "ok":
        raise ValueError("No successful calibration acquisition")
    if (observed.get("token_rule") != "prompt-last"
            or observed.get("context_policy") != "fresh-context-per-sample"
            or type(observed.get("generated_tokens")) is not int or observed["generated_tokens"] != 0
            or type(observed.get("hidden_width")) is not int or observed["hidden_width"] != 4096
            or type(observed.get("sample_count")) is not int or observed["sample_count"] != 24
            or not isinstance(observed.get("samples"), list) or len(observed["samples"]) != 24):
        raise ValueError("Acquisition did not preserve the prompt-only measurement contract")
    for key in ("run_id", "model_name", "model_digest", "model_blob_digest", "tokenizer_digest", "template_digest",
                "backend_revision", "precision", "layer", "samples_payload_digest", "dataset_digest"):
        if observed.get(key) != request[key]:
            raise ValueError("Acquisition identity mismatch: " + key)
    vectors = {}
    offered = {v["sample_id"]: v for v in request["samples"]}
    for sample in observed["samples"]:
        sid = sample["sample_id"]
        if sid not in offered or sid in vectors:
            raise ValueError("Unexpected/duplicate acquired sample")
        for key in ("prompt_digest", "input_digest", "system_digest", "schema_digest"):
            if sample[key] != offered[sid][key]:
                raise ValueError("Sample binding mismatch")
        if (type(sample.get("input_tokens")) is not int or not 1 <= sample["input_tokens"] <= 512
                or type(sample.get("token_position")) is not int
                or sample["token_position"] != sample["input_tokens"] - 1
                or sample.get("layer") != plan["layer"]):
            raise ValueError("Sample was not acquired at the declared prompt-final position")
        vector = np.asarray(sample["activation"], dtype=np.float64)
        if vector.shape != (4096,) or not np.isfinite(vector).all():
            raise ValueError("Invalid acquired residual")
        vectors[sid] = vector
    if set(vectors) != set(offered) or len(vectors) != 24:
        raise ValueError("Incomplete acquisition")
    total_tokens = sum(x["input_tokens"] for x in observed["samples"])
    if total_tokens > 8192 or type(observed.get("total_input_tokens")) is not int or observed["total_input_tokens"] != total_tokens:
        raise ValueError("Acquisition token accounting mismatch")
    examples = dataset["examples"]
    partitions = {s: [v for v in examples if v["split"] == s] for s in ("fit", "calibration", "holdout")}
    positive = [vectors[x["sampleID"]] for x in partitions["fit"] if x["label"] == 1]
    negative = [vectors[x["sampleID"]] for x in partitions["fit"] if x["label"] == -1]
    fitted = mean_contrast_reader(positive, negative)
    if not fitted.available:
        raise ValueError("Fitted reader unavailable: " + str(fitted.reason))
    direction = fitted.direction
    center = np.mean([vectors[x["sampleID"]] for x in partitions["fit"]], axis=0)
    def scores(split):
        return [float(direction @ (vectors[x["sampleID"]] - center)) for x in partitions[split]]
    calibration = scores("calibration")
    positive_cal = [s for x, s in zip(partitions["calibration"], calibration) if x["label"] == 1]
    negative_cal = [s for x, s in zip(partitions["calibration"], calibration) if x["label"] == -1]
    separation = min(positive_cal) - max(negative_cal)
    offset = (min(positive_cal) + max(negative_cal)) / 2
    scale = float(np.std(calibration))
    if not math.isfinite(scale) or scale <= 1e-12:
        raise ValueError("Calibration scale is unavailable")
    numeric = {"directions": [direction.tolist()], "center": center.tolist(), "scoreOffset": [offset], "scoreScale": [scale]}
    # Freeze every parameter before inspecting holdout labels/scores.
    save(output / "frozen-fit.json", {"algorithm": plan["algorithm"], "numeric": numeric,
                                     "planDigest": sha((output / "plan.json").read_bytes())})
    results = []
    for split in ("calibration", "holdout"):
        for example in partitions[split]:
            assay = standardized_assay(vectors[example["sampleID"]], direction, center,
                                       score_mean=offset, score_scale=scale)
            if not assay.available:
                raise ValueError("Assay unavailable")
            signed = example["label"] * assay.standardized_score
            results.append({"sampleID": example["sampleID"], "group": example["group"], "split": split,
                            "label": example["label"], "rawScore": assay.raw_score,
                            "coordinate": assay.bounded_score, "signedMargin": signed,
                            "correct": signed > 0, "marginPass": signed >= plan["minimumSignedMargin"]})
    holdout = [x for x in results if x["split"] == "holdout"]
    passed = separation > 0 and all(x["marginPass"] for x in results)
    qualifies = reader_eligible(plan, passed)
    report = {"schema": "archi-gguf-reader-calibration/v1", "status": ("limited-shadow-pass" if qualifies else "qualification-failed")
                  if plan["qualificationEligible"] else "development-only",
              "numericalCriteriaPassed": passed, "qualificationEligible": plan["qualificationEligible"],
              "prefillOnly": True, "readerDigest": sha(encoded(numeric)), "numericDigest": numeric_digest(numeric),
              "corpusProvenance": plan["corpusProvenance"],
              "preparationReceiptDigest": sha((output / "preparation-receipt.json").read_bytes()),
              "measurementScope": SCOPE, "tokenRule": "prompt-last", "fitCount": 8, "calibrationCount": 8,
              "holdoutCount": 8, "holdoutCorrect": sum(x["correct"] for x in holdout),
              "holdoutAccuracy": sum(x["correct"] for x in holdout) / 8,
              "plan": plan, "planPayload": (output / "plan.json").read_text(),
              "planDigest": sha((output / "plan.json").read_bytes()),
              "activationDigest": sha((output / "activations.json").read_bytes()),
              "acquisitionReceiptDigest": sha((output / "acquisition-receipt.json").read_bytes()),
              "acquisitionStartDigest": sha((output / "acquisition-start.json").read_bytes()),
              "frozenFitDigest": sha((output / "frozen-fit.json").read_bytes()),
              "calibrationSeparation": separation, "minimumSignedMargin": 0.1, "results": results,
              "limitations": ["Four held-out synthetic lookup groups; no population error guarantee.",
                              "Not calibrated for ordinary ARCHi chat prompts, generated-token states, truth, or authority.",
                              "No weight training, activation steering or response-quality comparison."]}
    report_text = encoded(report)
    save(output / "calibration-report.json", report)
    if qualifies:
        reader = {"schemaVersion": "archi-gguf-reader/v2", "modelName": plan["modelName"],
                  "modelDigest": plan["modelDigest"], "modelBlobDigest": plan["modelBlobDigest"],
                  "namespace": "hampton.experimental.synthetic-record-field-support.v1",
                  "tokenizerDigest": plan["modelBlobDigest"], "templateDigest": plan["templateDigest"],
                  "backendRevision": plan["backendRevision"], "precision": "Q4_K_M", "layer": plan["layer"],
                  "readerName": "synthetic-record-field-support", "basisDigest": sha(encoded({"plan": plan, "numeric": numeric})),
                  "readerDigest": sha(encoded(numeric)), "calibrationDigest": sha(report_text),
                  "tokenRule": "prompt-last", "measurementScope": SCOPE, "calibrationReport": report_text,
                  "provenance": "Locally fitted from synthetic, paired record-lookup examples. Limited prefill-only qualification; not general truth or chat qualification.", **numeric}
        save(output / "reader.json", reader)
    print(encoded({"status": report["status"], "holdoutCorrect": report["holdoutCorrect"],
                   "holdoutCount": 8, "readerProduced": qualifies}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["prepare", "acquire", "fit"])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--worker", type=Path)
    parser.add_argument("--corpus", type=Path, help="Explicit external synthetic paired corpus (prepare only)")
    parser.add_argument("--corpus-sha256", help="Exact selected corpus bytes SHA256, required with --corpus")
    parser.add_argument("--model", choices=["qwen3:8b", "qwen3.5:9b"], default="qwen3:8b")
    parser.add_argument("--backend", choices=[BACKEND, "llama.cpp:161755f29+archi-qwen35-mrope-v1", "llama.cpp:161755f29+archi-qwen35-text-v1"], default=BACKEND)
    args = parser.parse_args()
    if args.stage != "prepare" and (args.corpus is not None or args.corpus_sha256 is not None):
        raise ValueError("Corpus selection is only permitted during preparation, before acquisition")
    output = args.output.resolve()
    if not output.is_relative_to(REPO / "output"):
        raise ValueError("Keep calibration artifacts inside this checkout's ignored output/ directory")
    if args.stage == "prepare":
        prepare(output, args.model, args.backend, args.corpus, args.corpus_sha256)
    elif args.stage == "acquire":
        if not args.worker:
            raise ValueError("Choose the explicitly built local worker")
        acquire(output, args.worker.resolve())
    else:
        fit(output)


if __name__ == "__main__":
    main()
