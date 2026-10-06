#!/usr/bin/env python3
"""Reconcile raw run evidence into an inspectable task-reader bundle.

This does no inference and never enables native conversation measurements.
Only a complete passing run emits reader.qualified.json; failed runs can still
produce an honest read-only review. The native import contract is unchanged.
"""
import argparse
from pathlib import Path

import numpy as np

import calibrate as base
import task_reader as task


def export(output):
    plan, dataset = task.prepared(output)
    candidate = base.read(output / "reader.candidate.json")
    candidate_digest = base.sha((output / "reader.candidate.json").read_bytes())
    seal = base.read(output / "fit-seal.json")
    development = base.read(output / "development-report.json")
    qualification = base.read(output / "qualification-report.json")
    started = base.read(output / "qualification-started.json")
    plan_digest = base.sha((output / "plan.json").read_bytes())
    if (any(record["candidateDigest"] != candidate_digest for record in (seal, development, qualification, started))
            or any(record["planDigest"] != plan_digest for record in (candidate, seal, qualification))
            or candidate["numericDigest"] != base.numeric_digest(candidate["numeric"])):
        raise ValueError("Run identity or frozen candidate differs")
    vectors, tokens = {}, 0
    dev_samples = task.selected(dataset, ["fit", "calibration"])
    for i in range(0, len(dev_samples), 24):
        name = f"development-{i // 24:02d}"
        rows, count = task.validate_batch(output / name, plan, dev_samples[i:i + 24])
        if candidate["activationDigests"][name] != base.sha((output / name / "activations.json").read_bytes()):
            raise ValueError("Fit acquisition differs")
        vectors.update(rows)
        tokens += count
    if tokens != development["inputTokens"]:
        raise ValueError("Development accounting differs")
    rows, count = task.validate_batch(output / "qualification-00", plan, task.selected(dataset, ["holdout"]))
    if count != qualification["inputTokens"]:
        raise ValueError("Qualification accounting differs")
    vectors.update(rows)
    tokens += count
    if tokens > plan["maxTotalInputTokens"]:
        raise ValueError("Aggregate token budget exceeded")
    num = candidate["numeric"]
    direction, center = np.array(num["directions"][0]), np.array(num["center"])
    offset, scale = num["scoreOffset"][0], num["scoreScale"][0]
    if (direction.shape != (4096,) or center.shape != (4096,)
            or not np.isfinite(np.r_[direction, center, offset, scale]).all()
            or abs(np.linalg.norm(direction) - 1) > 1e-5 or scale < 1e-12):
        raise ValueError("Invalid reader numerics")
    results = []
    for e in dataset["examples"]:
        if e["split"] == "fit":
            continue
        score = float(np.dot(vectors[e["sampleID"]] - center, direction))
        margin = e["label"] * (score - offset) / scale
        results.append({"sampleID": e["sampleID"], "split": e["split"], "label": e["label"],
                        "rawScore": score, "signedMargin": margin})
    cal = [r for r in results if r["split"] == "calibration"]
    held = [r for r in results if r["split"] == "holdout"]
    separation = min(r["rawScore"] for r in cal if r["label"] == 1) - max(r["rawScore"] for r in cal if r["label"] == -1)
    actual_held = [{k: r[k] for k in ("sampleID", "label", "rawScore", "signedMargin")} |
                   {"correct": r["signedMargin"] > 0, "marginPass": r["signedMargin"] >= task.MIN_MARGIN} for r in held]
    if (actual_held != qualification["results"]
            or not np.allclose([r["signedMargin"] for r in cal], development["signedMargins"], rtol=1e-8, atol=1e-10)
            or abs(separation - development["calibrationSeparation"]) > 1e-8 * max(1, abs(separation))):
        raise ValueError("Reported scores do not reproduce from sealed activations")
    passed = separation > 0 and all(r["signedMargin"] >= task.MIN_MARGIN for r in results)
    status = "limited-synthetic-pass" if passed else "qualification-failed"
    if qualification["status"] != status:
        raise ValueError("Reported qualification status differs")
    review = {"schema": "archi-task-reader-review/v1", "status": status, "modelName": task.MODEL,
              "measurementScope": task.SCOPE, "fitCount": 96, "calibrationCount": 24,
              "calibrationCorrect": sum(r["signedMargin"] > 0 for r in cal), "holdoutCount": 24,
              "holdoutCorrect": sum(r["signedMargin"] > 0 for r in held), "minimumSignedMargin": task.MIN_MARGIN,
              "calibrationSeparation": separation, "scoreOffset": offset, "scoreScale": scale,
              "results": results, "candidateDigest": candidate_digest,
              "qualificationDigest": base.sha((output / "qualification-report.json").read_bytes()),
              "planDigest": plan_digest, "limitations": [
                  "New synthetic ID instances from the same generator, not general chat or domain-transfer qualification.",
                  "Prompt-final residual only. No generated-answer, honesty, truth, steering or authority claim.",
                  "Read-only report inspection does not import or enable a native reader."]}
    base.save(output / "reader-review.json", review)
    if passed:
        base.save(output / "reader.qualified.json", {"schema": "archi-task-reader-bundle/v1", "status": status,
                  "nativeImportable": False, "modelName": task.MODEL, "measurementScope": task.SCOPE,
                  "plan": plan, "candidate": candidate, "review": review,
                  "reviewDigest": base.sha((output / "reader-review.json").read_bytes()),
                  "usage": "Scoped research projection from the pinned final-prompt activation; not ordinary native replies."})
    base.save(output / "export-receipt.json", {"status": status, "inputTokens": tokens, "generatedTokens": 0,
              "candidateDigest": candidate_digest, "reviewDigest": base.sha((output / "reader-review.json").read_bytes()),
              "qualifiedBundleProduced": passed, "exporterSourceDigest": base.sha(Path(__file__).read_bytes())})
    print(base.encoded({"status": status, "qualifiedBundleProduced": passed, "inputTokens": tokens,
                       "holdoutCorrect": review["holdoutCorrect"], "holdoutCount": 24}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(base.REPO / "output"):
        raise ValueError("Use the existing ignored run directory")
    export(output)
