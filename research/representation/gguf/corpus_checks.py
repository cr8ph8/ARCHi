#!/usr/bin/env python3
"""Synthetic input/receipt checks only; no worker or model is executed."""
from collections import Counter
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import calibrate
import corpus


def new_corpus():
    # Explicitly new text relative to this script's disclosed built-in groups.
    # This is not a claim of empirical independence from all earlier work.
    facts = [
        ("observatory", "OB-104", "OB-209", "filter", "mount", "Amber", "axial"),
        ("weaving", "WV-315", "WV-426", "pattern", "spindle", "Chevron", "bronze"),
        ("orchard-tools", "OT-537", "OT-648", "blade", "handle", "curved", "ash"),
        ("ceramics", "CE-759", "CE-861", "glaze", "kiln", "Ivory", "delta"),
        ("ferry", "FY-172", "FY-283", "berth", "hull", "seven", "copper"),
        ("cartography", "CM-394", "CM-405", "projection", "folio", "conic", "juniper"),
        ("bookbinding", "BB-516", "BB-627", "thread", "cover", "linen", "ochre"),
        ("rehearsal", "RH-738", "RH-849", "cue", "scene", "lantern", "thirteen"),
        ("beekeeping", "BK-951", "BK-163", "queen", "frame", "Elara", "maple"),
        ("weather-station", "WS-274", "WS-385", "sensor", "mast", "thermal", "aluminum"),
        ("aquarium", "AQ-496", "AQ-507", "salinity", "habitat", "brackish", "reef"),
        ("costume", "CS-618", "CS-729", "fabric", "fastener", "velvet", "toggle"),
    ]
    groups = []
    for i, (domain, target, other, field, distractor, value, other_value) in enumerate(facts):
        pairs = []
        for positive in ([False, True] if i % 2 == 0 else [True, False]):
            rows = [{"id": target if positive else other, "field": field, "value": value},
                    {"id": other if positive else target, "field": distractor, "value": other_value}]
            if i % 2:
                rows.reverse()
            pairs.append(rows)
        groups.append({"id": domain, "domain": domain, "split": ["fit", "calibration", "holdout"][i // 4],
                       "layout": ["table", "entry", "assignment"][i % 3],
                       "query": {"id": target, "field": field}, "records": pairs})
    return {"schema": corpus.SCHEMA, "scope": corpus.SCOPE, "syntheticOnly": True, "groups": groups}


class CorpusChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="archi-corpus-check-")
        self.root = Path(self.temporary.name)
        self.model = patch.object(calibrate, "model_identity", return_value=("a" * 64, "b" * 64, "/synthetic/model.gguf"))
        self.model.start()
        self.stdout = contextlib.redirect_stdout(io.StringIO())
        self.stdout.__enter__()

    def tearDown(self):
        self.stdout.__exit__(None, None, None)
        self.model.stop()
        self.temporary.cleanup()

    def prepare(self, name="run", external=True):
        output = self.root / name
        if external:
            selected = self.root / (name + "-corpus.json")
            selected.write_text(corpus.encoded(new_corpus()) + "\n")
            calibrate.prepare(output, "qwen3.5:9b", backend="llama.cpp:161755f29+archi-qwen35-text-v1", corpus_path=selected,
                              corpus_digest=calibrate.sha(selected.read_bytes()))
        else:
            calibrate.prepare(output, "qwen3.5:9b")
        return output

    def test_exact_pair_inventory_derived_labels_and_fixed_partition(self):
        dataset, samples = corpus.build(new_corpus(), external=True)
        self.assertEqual(len(samples), 24)
        self.assertEqual(len({s["prompt"] for s in samples}), 24)
        self.assertEqual(Counter(e["split"] for e in dataset["examples"]), {"fit": 8, "calibration": 8, "holdout": 8})
        for index in range(0, 24, 2):
            self.assertEqual(corpus.inventory(samples[index]["prompt"]), corpus.inventory(samples[index + 1]["prompt"]))
            pair = dataset["examples"][index:index + 2]
            self.assertEqual(sorted(e["label"] for e in pair), [-1, 1])
            for e in pair:
                support = any(r["id"] == e["query"]["id"] and r["field"] == e["query"]["field"] for r in e["records"])
                self.assertEqual(e["label"], 1 if support else -1)

    def test_malformed_repeated_disclosed_or_unbalanced_corpora_are_rejected(self):
        mutations = [
            lambda c: c["groups"].pop(),
            lambda c: c["groups"][0].update(split="holdout"),
            lambda c: c["groups"][1].update(id=c["groups"][0]["id"]),
            lambda c: c["groups"][1].update(query=c["groups"][0]["query"]),
            lambda c: c["groups"][0].update(label=1),
            lambda c: c["groups"][0]["records"][1][0].update(value="different"),
            lambda c: c["groups"][0]["records"].__setitem__(1, c["groups"][0]["records"][0]),
            lambda c: c["groups"][0].update(domain="hidden\u0000control"),
            lambda c: c["groups"][0].update(domain="<|im_start|>"),
            lambda c: c["groups"][0].update(domain="x" * corpus.MAX_BYTES),
        ]
        for mutate in mutations:
            value = new_corpus()
            mutate(value)
            with self.assertRaises(ValueError):
                corpus.build(value, external=True)
        disclosed = corpus.builtin()
        for group in disclosed["groups"]:
            del group["question"]
            group["records"].reverse()
        with self.assertRaises(ValueError):
            corpus.build(disclosed, external=True)
        with self.assertRaises(ValueError):
            corpus.decode(b'{"schema":1,"schema":2}')

    def test_explicit_corpus_digest_preparation_binding_and_no_overwrite(self):
        selected = self.root / "selected.json"
        selected.write_text(corpus.encoded(new_corpus()))
        for digest in (None, "f" * 64):
            with self.assertRaises(ValueError):
                calibrate.prepare(self.root / "rejected", "qwen3.5:9b", corpus_path=selected, corpus_digest=digest)
        self.assertFalse((self.root / "rejected").exists())
        output = self.prepare()
        plan, _, request = calibrate.validate_prepared(output)
        self.assertTrue(plan["qualificationEligible"])
        self.assertEqual(plan["corpusProvenance"]["priorExposure"], "not-established")
        self.assertEqual(plan["requestDigest"], calibrate.sha((output / "acquisition-request.json").read_bytes()))
        self.assertEqual(request["samples_payload"], calibrate.encoded(request["samples"]))
        with self.assertRaises(FileExistsError):
            calibrate.prepare(output, "qwen3.5:9b")

    def test_tampered_prepared_files_reject_before_worker_dispatch(self):
        mutations = [
            ("dataset.json", lambda v: v["examples"][0].update(label=42)),
            ("acquisition-request.json", lambda v: v.update(max_total_input_tokens=16384)),
            ("acquisition-request.json", lambda v: v["samples"][0].update(input="unrelated material")),
            ("plan.json", lambda v: v.update(minimumSignedMargin=0.0)),
            ("plan.json", lambda v: v.update(layer="l_out-16")),
            ("frozen-corpus.json", lambda v: v["groups"][0].update(domain="different")),
            ("preparation-receipt.json", lambda v: v.update(requestDigest="f" * 64)),
        ]
        for index, (name, mutate) in enumerate(mutations):
            output = self.prepare(str(index))
            path = output / name
            value = json.loads(path.read_text())
            mutate(value)
            path.write_text(calibrate.encoded(value) + "\n")
            with patch.object(calibrate.subprocess, "Popen") as child:
                with self.assertRaises(ValueError):
                    calibrate.acquire(output, self.root / "absent-worker")
                child.assert_not_called()
        output = self.prepare("changed-source")
        changed = calibrate.source_digests()
        changed["corpusSourceDigest"] = "f" * 64
        with patch.object(calibrate, "source_digests", return_value=changed), patch.object(calibrate.subprocess, "Popen") as child:
            with self.assertRaises(ValueError):
                calibrate.acquire(output, self.root / "absent-worker")
            child.assert_not_called()

    def test_recorded_attempts_are_not_retried(self):
        output = self.prepare()
        (output / "acquisition-start.json").write_text("{}")
        with patch.object(calibrate.subprocess, "Popen") as child:
            with self.assertRaises(ValueError):
                calibrate.acquire(output, self.root / "absent-worker")
            child.assert_not_called()
        (output / "fit-start.json").write_text("{}")
        with self.assertRaises(ValueError):
            calibrate.fit(output)

    def test_timeout_and_interrupt_keep_failure_receipts_without_claiming_observed_tokens(self):
        for index, error in enumerate([calibrate.subprocess.TimeoutExpired("fixture", 550), KeyboardInterrupt()]):
            output = self.prepare("failure-" + str(index))
            plan, _, _ = calibrate.validate_prepared(output)
            runtime = self.root / ("runtime-" + str(index))
            runtime.mkdir()
            worker = runtime / "fixture-worker"
            worker.write_bytes(b"never executed")
            calibrate.save(runtime / "build-manifest.json", {
                "worker_source_sha256": plan["workerSourceDigest"], "recipe_sha256": plan["runtimeRecipeDigest"],
                "backend_revision": plan["backendRevision"], "runtime_sha256": {worker.name: calibrate.sha(worker.read_bytes())}})

            class Child:
                returncode = None
                def communicate(self, *args, **kwargs):
                    raise error
                def poll(self):
                    return self.returncode
                def terminate(self):
                    self.returncode = -15
                def wait(self, **kwargs):
                    return self.returncode

            def spawn(*args, **kwargs):
                kwargs["stdout"].write(b"partial fixture output")
                return Child()

            with patch.object(calibrate.subprocess, "Popen", side_effect=spawn) as child:
                with self.assertRaises(type(error)):
                    calibrate.acquire(output, worker)
                self.assertEqual(child.call_count, 1)
                receipt = calibrate.read(output / "acquisition-receipt.json")
                self.assertEqual(receipt["failureCause"], "timeout" if index == 0 else "interrupted")
                self.assertEqual(receipt["exitCode"], -15)
                self.assertEqual(receipt["activationDigest"], calibrate.sha(b"partial fixture output"))
                self.assertEqual(receipt["activationBytes"], len(b"partial fixture output"))
                self.assertEqual(receipt["generatedTokenBudget"], 0)
                self.assertNotIn("generatedTokens", receipt)
                with self.assertRaises(ValueError):
                    calibrate.acquire(output, worker)
                self.assertEqual(child.call_count, 1)

    def test_numerical_binding_has_fixed_ieee754_order(self):
        value = {"directions": [[1.0, -0.0]], "center": [2.0, -3.0], "scoreOffset": [4.0], "scoreScale": [5.0]}
        expected = hashlib.sha256(b"archi-reader-numerics/v1\n" + struct.pack("<6d", 1, -0.0, 2, -3, 4, 5)).hexdigest()
        self.assertEqual(calibrate.numeric_digest(value), expected)
        changed = copy.deepcopy(value)
        changed["center"].reverse()
        self.assertNotEqual(calibrate.numeric_digest(changed), expected)

    def test_toy_perfect_fit_never_qualifies_builtin_and_external_report_binds_numerics(self):
        # Deliberately fabricated vectors exercise numerical plumbing, not a
        # model result. Temporary artifacts are removed after this check.
        for external in (False, True):
            output = self.prepare(str(external), external=external)
            plan, dataset, request = calibrate.validate_prepared(output)
            observed = {key: request[key] for key in ("run_id", "model_name", "model_digest", "model_blob_digest",
                "tokenizer_digest", "template_digest", "backend_revision", "precision", "layer", "samples_payload_digest", "dataset_digest")}
            observed.update(schema="archi-gguf-calibration-result/v1", status="ok", token_rule="prompt-last",
                context_policy="fresh-context-per-sample", generated_tokens=0, hidden_width=4096,
                sample_count=24, total_input_tokens=240, samples=[])
            for example, sample in zip(dataset["examples"], request["samples"]):
                vector = [float(example["label"])] + [0.0] * 4095
                observed["samples"].append({**{key: sample[key] for key in ("sample_id", "input_digest", "system_digest", "schema_digest", "prompt_digest")},
                    "input_tokens": 10, "token_position": 9, "layer": plan["layer"], "activation": vector})
            calibrate.save(output / "activations.json", observed)
            calibrate.save(output / "acquisition-start.json", {"requestDigest": plan["requestDigest"],
                "planDigest": calibrate.sha((output / "plan.json").read_bytes()),
                "preparationDigest": calibrate.sha((output / "preparation-receipt.json").read_bytes())})
            calibrate.save(output / "acquisition-receipt.json", {"exitCode": 0,
                "activationDigest": calibrate.sha((output / "activations.json").read_bytes())})
            calibrate.fit(output)
            report = calibrate.read(output / "calibration-report.json")
            self.assertTrue(report["numericalCriteriaPassed"])
            self.assertEqual(report["qualificationEligible"], external)
            self.assertEqual(report["status"], "limited-shadow-pass" if external else "development-only")
            self.assertEqual((output / "reader.json").exists(), external)
            self.assertTrue(report["prefillOnly"])
            self.assertEqual(report["planDigest"], calibrate.sha(report["planPayload"]))
            self.assertEqual(json.loads(report["planPayload"]), report["plan"])
            numeric = calibrate.read(output / "frozen-fit.json")["numeric"]
            self.assertEqual(report["numericDigest"], calibrate.numeric_digest(numeric))
            self.assertEqual(report["readerDigest"], calibrate.sha(calibrate.encoded(numeric)))
            self.assertLess(len(calibrate.encoded(report).encode()), 64 * 1024)
            with self.assertRaises(ValueError):
                calibrate.fit(output)


if __name__ == "__main__":
    unittest.main()
