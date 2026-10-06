#!/usr/bin/env python3
"""Focused fabricated-fixture checks. Never reads a live run or invokes a model."""
from __future__ import annotations

from collections import defaultdict
from contextlib import ExitStack, redirect_stdout
import io
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np

import task_reader as pipeline
import task_reader_math


class TaskReaderChecks(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.temporary = self.stack.enter_context(tempfile.TemporaryDirectory(
            prefix="task-reader-checks-", dir=pipeline.base.REPO / "output"))
        self.root = Path(self.temporary)
        self.worker = self.root / "archi-gguf-shadow"
        self.stack.enter_context(patch.object(pipeline.base, "model_identity",
            return_value=("a" * 64, "b" * 64, str(self.root / "fabricated.gguf"))))
        self.stack.enter_context(patch.object(pipeline, "runtime", return_value="c" * 64))
        self.process = self.stack.enter_context(patch.object(pipeline.subprocess, "Popen",
            side_effect=AssertionError("These checks must never start a worker")))
        self.stack.enter_context(redirect_stdout(io.StringIO()))

    def prepare(self, name, seed):
        output = self.root / name
        pipeline.prepare(output, self.worker, seed)
        return output

    def write_fixture(self, path, value):
        path.write_text(pipeline.base.encoded(value) + "\n", encoding="utf-8")

    def test_generated_pairs_have_derived_opposing_labels_identical_inventory_and_disjoint_ids(self):
        # A separate test seed, never the frozen live-run dataset.
        dataset = pipeline.make_dataset(734901)
        samples = {sample["sample_id"]: sample for sample in dataset["samples"]}
        groups = defaultdict(list)
        for example in dataset["examples"]:
            groups[example["group"]].append(example)
            supported = any(row["id"] == example["query"]["id"]
                            and row["field"] == example["query"]["field"] for row in example["records"])
            self.assertEqual(example["label"], 1 if supported else -1)
            sample = samples[example["sampleID"]]
            self.assertEqual(example["promptDigest"], pipeline.base.sha(sample["prompt"]))
        seen_record_ids = set()
        split_counts = defaultdict(int)
        for examples in groups.values():
            self.assertEqual(len(examples), 2)
            self.assertEqual({example["label"] for example in examples}, {-1, 1})
            self.assertEqual(len({example["split"] for example in examples}), 1)
            split_counts[examples[0]["split"]] += 1
            left, right = [samples[example["sampleID"]]["prompt"] for example in examples]
            self.assertEqual(pipeline.corpus.inventory(left), pipeline.corpus.inventory(right))
            record_ids = {row["id"] for example in examples for row in example["records"]}
            self.assertEqual(len(record_ids), 2)
            self.assertFalse(record_ids & seen_record_ids)
            seen_record_ids.update(record_ids)
        self.assertEqual(dict(split_counts), pipeline.COUNTS)
        self.assertEqual(len(samples), 2 * sum(pipeline.COUNTS.values()))
        self.assertEqual(len({sample["prompt_digest"] for sample in samples.values()}), len(samples))
        self.process.assert_not_called()

    def test_tampered_plan_with_rehashed_local_seal_is_refused_before_acquisition(self):
        output = self.prepare("plan-check", 734902)
        plan = pipeline.base.read(output / "plan.json")
        plan["fitSelection"]["tieBreak"] = "smaller-strength"
        self.write_fixture(output / "plan.json", plan)
        seal = pipeline.base.read(output / "preparation.json")
        seal["planDigest"] = pipeline.base.sha((output / "plan.json").read_bytes())
        self.write_fixture(output / "preparation.json", seal)
        with patch.object(pipeline, "batch") as acquire:
            with self.assertRaisesRegex(ValueError, "Frozen plan differs"):
                pipeline.qualify(output, self.worker)
            acquire.assert_not_called()
        self.assertFalse((output / "qualification-started.json").exists())
        self.process.assert_not_called()

    def test_foreign_candidate_and_its_genuine_local_seal_cannot_authorize_current_run(self):
        first = self.prepare("foreign-source", 734903)
        second = self.prepare("foreign-target", 734904)
        first_plan = pipeline.base.read(first / "plan.json")
        numeric = {"directions": [[1.0] + [0.0] * 4095], "center": [0.0] * 4096,
                   "scoreOffset": [0.0], "scoreScale": [1.0]}
        candidate = {"schema": "archi-task-reader-candidate/v1", "status": "unqualified-candidate",
                     "measurementScope": pipeline.SCOPE,
                     "planDigest": pipeline.base.sha((first / "plan.json").read_bytes()),
                     "modelDigest": first_plan["modelDigest"], "modelBlobDigest": first_plan["modelBlobDigest"],
                     "backendRevision": pipeline.BACKEND, "layer": pipeline.LAYER, "tokenRule": "prompt-last",
                     "numeric": numeric, "numericDigest": pipeline.base.numeric_digest(numeric),
                     "selectedStrength": 1.0, "selectedAlpha": 1.0, "cv": [], "activationDigests": {}}
        self.write_fixture(first / "reader.candidate.json", candidate)
        digest = pipeline.base.sha((first / "reader.candidate.json").read_bytes())
        self.write_fixture(first / "development-report.json", {"status": "ready-for-heldout", "candidateDigest": digest})
        self.write_fixture(first / "fit-seal.json", {"candidateDigest": digest, "planDigest": candidate["planDigest"]})
        for name in ("reader.candidate.json", "development-report.json", "fit-seal.json"):
            (second / name).write_bytes((first / name).read_bytes())
        with patch.object(pipeline, "batch") as acquire:
            with self.assertRaises(ValueError):
                pipeline.qualify(second, self.worker)
            acquire.assert_not_called()
        self.assertFalse((second / "qualification-started.json").exists())
        self.process.assert_not_called()

    def test_zero_calibration_scale_records_failed_fit_without_qualification(self):
        output = self.prepare("zero-scale", 734905)
        dataset = pipeline.base.read(output / "dataset.json")
        development = pipeline.selected(dataset, ["fit", "calibration"])
        for index in range(0, len(development), 24):
            directory = output / f"development-{index // 24:02d}"
            directory.mkdir()
            (directory / "activations.json").write_text("{}\n", encoding="utf-8")
        calibration_count = len(pipeline.selected(dataset, ["calibration"]))
        fitted = SimpleNamespace(direction=np.r_[1.0, np.zeros(4095)], center=np.zeros(4096),
            score_offset=0.0, score_scale=0.0, calibration_scores=np.zeros(calibration_count),
            calibration_separation=0.0, selected_strength=1.0, selected_alpha=1.0, cv_summary=())

        def fabricated_batch(_directory, _plan, samples):
            return {sample["sample_id"]: np.zeros(4096) for sample in samples}, len(samples)

        with patch.object(pipeline, "validate_batch", side_effect=fabricated_batch), \
             patch.object(task_reader_math, "fit_ridge_reader", return_value=fitted), \
             patch.object(pipeline, "batch") as acquire:
            pipeline.fit(output)
            report = pipeline.base.read(output / "development-report.json")
            self.assertEqual(report["status"], "calibration-failed")
            self.assertEqual(report["signedMargins"], [])
            self.assertEqual(report["calibrationCount"], calibration_count)
            self.assertEqual(report["inputTokens"], len(development))
            self.assertFalse(report["holdoutAcquired"])
            candidate = pipeline.base.read(output / "reader.candidate.json")
            self.assertEqual(candidate["status"], "unqualified-candidate")
            with self.assertRaisesRegex(ValueError, "Development candidate failed"):
                pipeline.qualify(output, self.worker)
            acquire.assert_not_called()
        self.assertFalse((output / "qualification-started.json").exists())
        self.process.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
