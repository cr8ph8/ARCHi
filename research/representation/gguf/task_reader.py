#!/usr/bin/env python3
"""Build a bounded record-support RepE candidate on the existing local Qwen.

This new research protocol does not impersonate the older native v2 reader.
All choices and inputs are frozen before acquisition. Fit-only grouped selection
precedes calibration; qualification is consumed at most once and never refits.
No cloud, generated tokens, model weight updates, or native state writes.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import random
import subprocess
import time
import uuid

import calibrate as base
import corpus

HERE = Path(__file__).resolve().parent
BACKEND = "llama.cpp:161755f29+archi-qwen35-text-v1"
SCOPE = "synthetic-record-field-support/prompt-final/ridge-v1"
COUNTS = {"fit": 48, "calibration": 12, "holdout": 12}
MODEL = "qwen3.5:9b"
LAYER = "l_out-31"  # Fixed final text block; no layer search.
MIN_MARGIN = 0.1
FIELDS = ["location", "owner", "deadline", "color", "material", "status",
          "destination", "size", "quantity", "category", "label", "priority"]
VALUES = ["amber", "violet", "north", "south", "copper", "paper", "maple", "cedar",
          "morning", "evening", "small", "large", "four", "eight", "quiet", "ready"]
DOMAINS = ["meeting", "inventory", "delivery", "workshop", "project", "reservation"]
LAYOUTS = ["assignment", "table", "entry"]


def sources():
    return {name: base.sha((HERE / name).read_bytes()) for name in
            ("task_reader.py", "task_reader_math.py", "calibrate.py", "corpus.py", "worker.cpp", "task_assay.h", "build.py")}


def make_dataset(seed):
    """Structural pairs have identical words and derived, opposing labels.

    Split identities are disjoint; domains, fields and layouts intentionally recur.
    This is within-generator evaluation, not evidence of cross-domain transfer.
    """
    rng = random.Random(seed)
    examples, samples = [], []
    schema = base.encoded({"type": "object", "properties": {"answer": {"type": "string"}},
                           "required": ["answer"], "additionalProperties": False})
    for split, count in COUNTS.items():
        for group_index in range(count):
            group = f"{split}-{group_index:03d}"
            # Each query ID appears in exactly one group and neither implies label.
            target, other = [f"R{rng.getrandbits(40):010x}" for _ in range(2)]
            field, distractor = rng.sample(FIELDS, 2)
            values = rng.sample(VALUES, 2)
            domain = DOMAINS[group_index % len(DOMAINS)]
            layout = LAYOUTS[group_index % len(LAYOUTS)]
            system = (f"Read the supplied {domain} records. Answer only the exact record and field asked for. "
                      "Use only those records. If that field is absent for that record, answer NEED_SOURCE. Return one JSON object.")
            query = {"id": target, "field": field}
            labels = [1, -1] if rng.randrange(2) else [-1, 1]
            reverse_rows = bool(rng.randrange(2))
            pair_inputs = []
            for member, intended in enumerate(labels):
                rows = [{"id": target if intended == 1 else other, "field": field, "value": values[0]},
                        {"id": other if intended == 1 else target, "field": distractor, "value": values[1]}]
                if reverse_rows:
                    rows.reverse()
                label = 1 if any(r["id"] == target and r["field"] == field for r in rows) else -1
                if layout == "assignment":
                    records = "\n".join(f"{r['id']}: {r['field']} = {r['value']}." for r in rows)
                elif layout == "table":
                    records = "record | field | value\n" + "\n".join(f"{r['id']} | {r['field']} | {r['value']}" for r in rows)
                else:
                    records = "\n".join(f"Entry {r['id']} records {r['field']} as {r['value']}." for r in rows)
                user_input = records + f"\n\nWhich {field} is listed for {target}?"
                prompt = ("<|im_start|>system\n" + system + "<|im_end|>\n<|im_start|>user\n" + user_input
                          + "\n\nReturn exactly one JSON object matching this schema:\n" + schema
                          + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
                sid = group + f"-{member}"
                sample = {"sample_id": sid, "input": user_input, "system": system,
                          "response_schema": schema, "prompt": prompt}
                for key, digest_key in (("input", "input_digest"), ("system", "system_digest"),
                                        ("response_schema", "schema_digest"), ("prompt", "prompt_digest")):
                    sample[digest_key] = base.sha(sample[key])
                samples.append(sample)
                examples.append({"sampleID": sid, "group": group, "split": split, "label": label,
                                 "layout": layout, "records": rows, "query": query, "promptDigest": base.sha(prompt)})
                pair_inputs.append(prompt)
            if corpus.inventory(pair_inputs[0]) != corpus.inventory(pair_inputs[1]):
                raise ValueError("Pair leaked label through lexical inventory")
    if len({x["prompt_digest"] for x in samples}) != len(samples):
        raise ValueError("Repeated prompts")
    return {"schema": "archi-task-reader-dataset/v1", "scope": SCOPE, "syntheticOnly": True,
            "seed": seed, "examples": examples, "samples": samples}


def runtime(worker):
    manifest = base.read(worker.parent / "build-manifest.json", 128 * 1024)
    if (manifest["backend_revision"] != BACKEND
            or manifest["worker_source_sha256"] != base.sha((HERE / "worker.cpp").read_bytes())
            or manifest["recipe_sha256"] != base.sha((HERE / "build.py").read_bytes())
            or manifest.get("task_assay_header_sha256") != base.sha((HERE / "task_assay.h").read_bytes())):
        raise ValueError("Runtime and selected source revision differ")
    for name, digest in manifest["runtime_sha256"].items():
        path = worker.parent / name
        if Path(name).name != name or path.is_symlink() or base.sha(path.read_bytes()) != digest:
            raise ValueError("Runtime member changed")
    if worker.name != "archi-gguf-shadow" or worker.name not in manifest["runtime_sha256"]:
        raise ValueError("Unsealed worker")
    return base.sha((worker.parent / "build-manifest.json").read_bytes())


def make_plan(dataset_digest, manifest_digest):
    model_digest, blob_digest, _ = base.model_identity(MODEL)
    return {"schema": "archi-task-reader-plan/v1", "algorithm": "grouped-ridge-reader/v1",
            "measurementScope": SCOPE, "tokenRule": "prompt-last", "layer": LAYER, "hiddenWidth": 4096,
            "modelName": MODEL, "modelDigest": model_digest, "modelBlobDigest": blob_digest,
            "templateDigest": base.sha(corpus.TEMPLATE), "backendRevision": BACKEND, "precision": "Q4_K_M",
            "datasetDigest": dataset_digest, "sources": sources(),
            "runtimeManifestDigest": manifest_digest, "pairs": COUNTS, "minimumSignedMargin": MIN_MARGIN,
            "fitSelection": {"strengths": [0.01, 0.1, 1.0, 10.0], "folds": "leave-whole-pair-out",
                             "criterion": "misclassified-examples", "tieBreak": "larger-strength"},
            "layerSearch": False, "heldoutRetries": False, "requiresAllCalibrationAndHoldoutMargins": True,
            "maxSamplesPerBatch": 24, "maxTotalInputTokens": 49152, "generatedTokenBudget": 0,
            "maxBatchSeconds": 550, "maxBatches": 6,
            "corpusProvenance": "New deterministic synthetic pairs generated before acquisition; same generator across splits.",
            "qualification": "Small synthetic assay only; no general chat, truth, steering or authority."}


def prepare(output, worker, seed):
    if output.exists():
        raise ValueError("Choose a new run directory; historical runs are immutable")
    manifest_digest = runtime(worker)
    model_digest, blob_digest, _ = base.model_identity(MODEL)
    dataset = make_dataset(seed)
    output.mkdir(parents=True)
    base.save(output / "dataset.json", dataset)
    plan = make_plan(base.sha((output / "dataset.json").read_bytes()), manifest_digest)
    base.save(output / "plan.json", plan)
    base.save(output / "preparation.json", {"planDigest": base.sha((output / "plan.json").read_bytes()),
                                          "datasetDigest": plan["datasetDigest"], "preparedAtUnix": time.time()})
    print(base.encoded({"status": "prepared", "pairs": COUNTS, "layer": LAYER}), flush=True)


def prepared(output, worker=None):
    plan = base.read(output / "plan.json")
    seal = base.read(output / "preparation.json")
    if (seal["planDigest"] != base.sha((output / "plan.json").read_bytes())
            or plan["sources"] != sources() or seal["datasetDigest"] != plan["datasetDigest"]
            or plan["datasetDigest"] != base.sha((output / "dataset.json").read_bytes())):
        raise ValueError("Frozen protocol, source or corpus changed")
    if plan != make_plan(plan["datasetDigest"], plan["runtimeManifestDigest"]):
        raise ValueError("Frozen plan differs from executable protocol or installed model identity")
    dataset = base.read(output / "dataset.json")
    if dataset != make_dataset(dataset["seed"]):
        raise ValueError("Dataset labels or prompts differ from frozen generator")
    if worker and runtime(worker) != plan["runtimeManifestDigest"]:
        raise ValueError("Worker bundle changed since preparation")
    return plan, dataset


def batch(output, worker, plan, samples, name):
    directory = output / name
    directory.mkdir()  # A failed or interrupted batch cannot be retried invisibly.
    request = base.make_request(plan, samples, str(uuid.uuid4()))
    base.save(directory / "request.json", request)
    base.save(directory / "started.json", {"startedAtUnix": time.time(),
                                          "planDigest": base.sha((output / "plan.json").read_bytes()),
                                          "requestDigest": base.sha((directory / "request.json").read_bytes())})
    start = time.monotonic()
    child, cause = None, None
    try:
        with (directory / "activations.json").open("xb") as stdout, (directory / "worker.log").open("xb") as stderr:
            child = subprocess.Popen([str(worker), "--acquire-calibration"], stdin=subprocess.PIPE, stdout=stdout,
                                     stderr=stderr, env={"PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"})
            child.communicate(base.encoded(request).encode(), timeout=plan["maxBatchSeconds"])
        if child.returncode:
            cause = "worker-exit"
    except BaseException as error:
        cause = type(error).__name__
        raise
    finally:
        if child and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        path = directory / "activations.json"
        base.save(directory / "receipt.json", {"status": "failed" if cause else "process-complete", "failure": cause,
                  "exitCode": child.returncode if child else None, "elapsedSeconds": time.monotonic() - start,
                  "activationDigest": base.sha(path.read_bytes()) if path.exists() else None,
                  "requestDigest": base.sha((directory / "request.json").read_bytes())})
    if cause:
        raise ValueError(cause)
    try:
        validate_batch(directory, plan, samples, accept_unreviewed=True)
    except Exception as error:
        base.save(directory / "validation.json", {"status": "rejected", "error": str(error)})
        raise
    base.save(directory / "validation.json", {"status": "accepted",
              "receiptDigest": base.sha((directory / "receipt.json").read_bytes())})
    print(base.encoded({"batch": name, "status": "acquired", "samples": len(samples)}), flush=True)


def validate_batch(directory, plan, samples, *, accept_unreviewed=False):
    receipt = base.read(directory / "receipt.json")
    request = base.read(directory / "request.json")
    result = base.read(directory / "activations.json")
    expected = base.make_request(plan, samples, request["run_id"])
    start = base.read(directory / "started.json")
    if (receipt["status"] != "process-complete" or receipt["exitCode"] != 0 or request != expected
            or receipt["activationDigest"] != base.sha((directory / "activations.json").read_bytes())
            or receipt["requestDigest"] != base.sha((directory / "request.json").read_bytes())
            or start["requestDigest"] != receipt["requestDigest"]
            or start["planDigest"] != base.sha((directory.parent / "plan.json").read_bytes())):
        raise ValueError("Acquisition receipt mismatch")
    if not accept_unreviewed:
        validation = base.read(directory / "validation.json")
        if (validation["status"] != "accepted"
                or validation["receiptDigest"] != base.sha((directory / "receipt.json").read_bytes())):
            raise ValueError("Acquisition validation missing or changed")
    for key in ("run_id", "model_name", "model_digest", "model_blob_digest", "tokenizer_digest", "template_digest",
                "backend_revision", "precision", "layer", "dataset_digest", "samples_payload_digest"):
        if result.get(key) != request[key]:
            raise ValueError("Activation identity mismatch: " + key)
    if (result.get("status") != "ok" or result.get("schema") != "archi-gguf-calibration-result/v1"
            or result.get("generated_tokens") != 0 or result.get("token_rule") != "prompt-last"
            or result.get("context_policy") != "fresh-context-per-sample"
            or result.get("sample_count") != len(samples) or len(result["samples"]) != len(samples)):
        raise ValueError("Invalid activation result")
    import numpy as np
    vectors = {}
    total = 0
    for incoming, original in zip(result["samples"], samples):
        for key in ("sample_id", "input_digest", "system_digest", "schema_digest", "prompt_digest"):
            if incoming.get(key) != original[key]:
                raise ValueError("Sample binding mismatch")
        vector = np.asarray(incoming["activation"], dtype=np.float64)
        if (vector.shape != (4096,) or not np.isfinite(vector).all() or incoming["layer"] != LAYER
                or not 0 < incoming["input_tokens"] <= 512
                or incoming["token_position"] != incoming["input_tokens"] - 1):
            raise ValueError("Invalid final-prompt activation")
        vectors[original["sample_id"]] = vector
        total += incoming["input_tokens"]
    if total != result["total_input_tokens"] or total > 8192:
        raise ValueError("Token accounting mismatch")
    return vectors, total


def selected(dataset, splits):
    ids = {x["sampleID"] for x in dataset["examples"] if x["split"] in splits}
    return [s for s in dataset["samples"] if s["sample_id"] in ids]


def development(output, worker):
    plan, dataset = prepared(output, worker)
    base.save(output / "development-started.json", {"startedAtUnix": time.time()})
    samples = selected(dataset, ["fit", "calibration"])
    for i in range(0, len(samples), 24):
        batch(output, worker, plan, samples[i:i + 24], f"development-{i // 24:02d}")


def fit(output):
    import numpy as np
    from task_reader_math import fit_ridge_reader
    plan, dataset = prepared(output)
    base.save(output / "fit-started.json", {"startedAtUnix": time.time()})
    samples = selected(dataset, ["fit", "calibration"])
    vectors, tokens = {}, 0
    activation_digests = {}
    for i in range(0, len(samples), 24):
        name = f"development-{i // 24:02d}"
        values, count = validate_batch(output / name, plan, samples[i:i + 24])
        vectors.update(values)
        tokens += count
        activation_digests[name] = base.sha((output / name / "activations.json").read_bytes())
    training = [e for e in dataset["examples"] if e["split"] == "fit"]
    calibration = [e for e in dataset["examples"] if e["split"] == "calibration"]
    model = fit_ridge_reader(np.array([vectors[e["sampleID"]] for e in training]),
        [e["label"] for e in training], [e["group"] for e in training],
        np.array([vectors[e["sampleID"]] for e in calibration]), [e["label"] for e in calibration])
    numeric = {"directions": [model.direction.tolist()], "center": model.center.tolist(),
               "scoreOffset": [float(model.score_offset)], "scoreScale": [float(model.score_scale)]}
    candidate = {"schema": "archi-task-reader-candidate/v1", "status": "unqualified-candidate",
                 "measurementScope": SCOPE, "planDigest": base.sha((output / "plan.json").read_bytes()),
                 "modelDigest": plan["modelDigest"], "modelBlobDigest": plan["modelBlobDigest"],
                 "backendRevision": BACKEND, "layer": LAYER, "tokenRule": "prompt-last",
                 "numeric": numeric, "numericDigest": base.numeric_digest(numeric),
                 "selectedStrength": float(model.selected_strength), "selectedAlpha": float(model.selected_alpha),
                 "cv": model.cv_summary, "activationDigests": activation_digests}
    # Write once BEFORE any qualification acquisition or report.
    base.save(output / "reader.candidate.json", candidate)
    base.save(output / "fit-seal.json", {"candidateDigest": base.sha((output / "reader.candidate.json").read_bytes()),
              "planDigest": candidate["planDigest"], "frozenAtUnix": time.time()})
    margins = [e["label"] * (float(score) - model.score_offset) / model.score_scale
               for e, score in zip(calibration, model.calibration_scores)] if model.score_scale >= 1e-12 else []
    passed = len(margins) == len(calibration) and model.calibration_separation > 0 and all(m >= MIN_MARGIN for m in margins)
    report = {"schema": "archi-task-reader-development/v1", "status": "ready-for-heldout" if passed else "calibration-failed",
              "calibrationCorrect": sum(m > 0 for m in margins), "calibrationCount": len(calibration),
              "calibrationSeparation": float(model.calibration_separation), "signedMargins": margins,
              "inputTokens": tokens, "generatedTokens": 0, "holdoutAcquired": False,
              "candidateDigest": base.sha((output / "reader.candidate.json").read_bytes()),
              "limitations": ["Candidate is not a qualified native reader.", "Repeated generator, new synthetic identities; not general chat evidence."]}
    base.save(output / "development-report.json", report)
    print(base.encoded({k: report[k] for k in ("status", "calibrationCorrect", "calibrationCount", "calibrationSeparation", "inputTokens", "holdoutAcquired")}), flush=True)


def qualify(output, worker):
    import numpy as np
    plan, dataset = prepared(output, worker)
    development_report = base.read(output / "development-report.json")
    if (development_report["status"] != "ready-for-heldout"
            or development_report["candidateDigest"] != base.sha((output / "reader.candidate.json").read_bytes())):
        raise ValueError("Development candidate failed or changed; held-out input remains unused")
    candidate = base.read(output / "reader.candidate.json")
    seal = base.read(output / "fit-seal.json")
    if (seal["candidateDigest"] != development_report["candidateDigest"]
            or seal["planDigest"] != base.sha((output / "plan.json").read_bytes())
            or candidate["planDigest"] != seal["planDigest"]
            or candidate["measurementScope"] != SCOPE or candidate["layer"] != LAYER
            or candidate["backendRevision"] != BACKEND
            or candidate["modelDigest"] != plan["modelDigest"] or candidate["modelBlobDigest"] != plan["modelBlobDigest"]
            or candidate["numericDigest"] != base.numeric_digest(candidate["numeric"])):
        raise ValueError("Candidate numerics changed")
    # Rebind actual development acquisitions and recompute the gate before any
    # holdout load. A report's status string alone never authorizes acquisition.
    dev_samples = selected(dataset, ["fit", "calibration"])
    dev_vectors, total = {}, 0
    for i in range(0, len(dev_samples), 24):
        name = f"development-{i // 24:02d}"
        values, count = validate_batch(output / name, plan, dev_samples[i:i + 24])
        if candidate["activationDigests"][name] != base.sha((output / name / "activations.json").read_bytes()):
            raise ValueError("Fit acquisition changed")
        dev_vectors.update(values)
        total += count
    num = candidate["numeric"]
    direction, center = np.array(num["directions"][0]), np.array(num["center"])
    offset, scale = num["scoreOffset"][0], num["scoreScale"][0]
    if (direction.shape != (4096,) or center.shape != (4096,)
            or not np.isfinite(np.r_[direction, center, offset, scale]).all()
            or abs(np.linalg.norm(direction) - 1) > 1e-5 or scale < 1e-12):
        raise ValueError("Invalid candidate basis")
    for e in (e for e in dataset["examples"] if e["split"] == "calibration"):
        margin = e["label"] * (float(np.dot(dev_vectors[e["sampleID"]] - center, direction)) - offset) / scale
        if margin < MIN_MARGIN:
            raise ValueError("Recomputed calibration gate failed")
    if total != development_report["inputTokens"] or total + 8192 > plan["maxTotalInputTokens"]:
        raise ValueError("Aggregate acquisition budget mismatch")
    base.save(output / "qualification-started.json", {"startedAtUnix": time.time(), "candidateDigest": development_report["candidateDigest"]})
    samples = selected(dataset, ["holdout"])
    batch(output, worker, plan, samples, "qualification-00")
    vectors, tokens = validate_batch(output / "qualification-00", plan, samples)
    num = candidate["numeric"]
    results = []
    for e in (e for e in dataset["examples"] if e["split"] == "holdout"):
        score = float(np.dot(vectors[e["sampleID"]] - np.array(num["center"]), num["directions"][0]))
        margin = e["label"] * (score - num["scoreOffset"][0]) / num["scoreScale"][0]
        results.append({"sampleID": e["sampleID"], "label": e["label"], "rawScore": score,
                        "signedMargin": margin, "correct": margin > 0, "marginPass": margin >= MIN_MARGIN})
    passed = all(e["marginPass"] for e in results)
    report = {"schema": "archi-task-reader-qualification/v1", "status": "limited-synthetic-pass" if passed else "qualification-failed",
              "candidateDigest": development_report["candidateDigest"], "measurementScope": SCOPE,
              "planDigest": base.sha((output / "plan.json").read_bytes()), "holdoutCorrect": sum(e["correct"] for e in results),
              "holdoutCount": len(results), "results": results, "inputTokens": tokens, "generatedTokens": 0,
              "nativeImportable": False, "limitations": ["Synthetic final-prompt assay only; does not qualify general chat, truth, steering or authority."]}
    base.save(output / "qualification-report.json", report)
    print(base.encoded({k: report[k] for k in ("status", "holdoutCorrect", "holdoutCount", "inputTokens")}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["prepare", "development", "fit", "qualify"])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--worker", type=Path)
    parser.add_argument("--seed", type=int, default=2026092603)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(base.REPO / "output"):
        raise ValueError("Keep raw research activations in ignored checkout output/")
    if args.stage == "fit":
        fit(output)
    else:
        if not args.worker:
            raise ValueError("Choose the existing pinned local worker")
        worker = args.worker.resolve()
        if args.stage == "prepare":
            prepare(output, worker, args.seed)
        elif args.stage == "development":
            development(output, worker)
        else:
            qualify(output, worker)


if __name__ == "__main__":
    main()
