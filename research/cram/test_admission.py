"""Behavioral checks for a disposable owner; these do not test native ARCHi."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import nullcontext
import copy
from dataclasses import replace
import itertools
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from admission import DisposableGate
from scheduling import exact_reference, make_tasks, validate_schedule


def exercise_admission() -> list[dict]:
    task = make_tasks(count=1)[0]
    valid = exact_reference(task)["assignment"]
    invalid = {s["id"]: 0 for s in task["scenes"]}
    rows = []
    scenarios = [
        ("explicit_commit", "COMMIT", {}),
        ("dry_run", "DAMP", {"dry_run": True}),
        ("no_commit", "DAMP", {"explicit_commit": False}),
        ("string_commit_flag", "REJECT", {"explicit_commit": "true"}),
        ("integer_dry_run_flag", "REJECT", {"dry_run": 0}),
        ("invalid_schedule", "REJECT", {}),
        ("missing_scene", "REJECT", {}),
        ("boolean_slot", "REJECT", {}),
        ("wrong_target", "REJECT", {}),
        ("path_target", "REJECT", {}),
        ("wrong_authority", "REJECT", {"authorized_target": "another_owner"}),
        ("stale_state", "ESCALATE", {}),
        ("stale_context", "ESCALATE", {}),
        ("validator_error", "ESCALATE", {}),
        ("validator_skipped", "DAMP", {}),
        ("validator_abstain", "ESCALATE", {}),
        ("governance_edit", "ESCALATE", {}),
        ("substituted_evidence", "ESCALATE", {}),
        ("forged_status", "ESCALATE", {}),
        ("mutated_proposal", "ESCALATE", {}),
        ("context_slot_range", "ESCALATE", {}),
        ("context_duration", "ESCALATE", {}),
        ("context_duplicate_scene", "ESCALATE", {}),
        ("context_unknown_precedence", "ESCALATE", {}),
        ("context_empty_domain", "ESCALATE", {}),
        ("context_extra_field", "ESCALATE", {}),
        ("commit_validator_exception", "ESCALATE", {}),
    ]
    for name, expected, overrides in scenarios:
        with tempfile.TemporaryDirectory(prefix="archi-cram-case-") as tmp:
            gate = DisposableGate(Path(tmp))
            local_task = copy.deepcopy(task)
            if name == "context_slot_range":
                local_task["slots"] = 1
            elif name == "context_duration":
                local_task["duration_slots"] = 2
            elif name == "context_duplicate_scene":
                local_task["scenes"][1]["id"] = local_task["scenes"][0]["id"]
            elif name == "context_unknown_precedence":
                local_task["precedence"] = [["scene-0", "unknown"]]
            elif name == "context_empty_domain":
                local_task["scenes"][0]["allowed_slots"] = []
            elif name == "context_extra_field":
                local_task["model_authorized"] = True
            p = gate.propose(local_task, invalid if name in {"invalid_schedule", "forged_status"} else valid)
            if name == "missing_scene":
                p = replace(p, assignment={})
            elif name == "boolean_slot":
                p = replace(p, assignment={**valid, "scene-0": True})
            elif name == "wrong_target":
                p = replace(p, target="native_profile")
            elif name == "path_target":
                p = replace(p, target="../../outside")
            elif name == "stale_state":
                p = replace(p, pre_state_hash="0"*64)
            elif name == "governance_edit":
                p = replace(p, operation="change_policy")
            status = {"validator_error": "ERROR", "validator_skipped": "SKIPPED",
                      "validator_abstain": "ABSTAIN"}.get(name)
            evidence = gate.evaluate(local_task, p, test_validator_status=status)
            current_task = local_task
            if name == "stale_context":
                current_task = {**task, "revision": task["revision"]+1}
            elif name == "substituted_evidence":
                evidence = gate.evaluate(task, gate.propose(task, invalid))
            elif name == "forged_status":
                evidence = replace(evidence, status="PASS", reasons=())
            elif name == "mutated_proposal":
                p.assignment["scene-0"] = 99
            failure = patch("admission.validate_schedule", side_effect=RuntimeError("simulated validator crash")) if name == "commit_validator_exception" else nullcontext()
            with failure:
                event = gate.decide(current_task, p, evidence,
                    **({"explicit_commit": True, "dry_run": False} | overrides))
            passed = event["decision"] == expected and event["state_bytes_changed"] == (expected == "COMMIT")
            if name.startswith("context_") or name == "commit_validator_exception":
                passed = passed and event["validator_status"] == "ERROR"
            rows.append({"case": name, "expected": expected, "check_status": "PASS" if passed else "FAIL", **event})
            if not passed:
                raise AssertionError(rows[-1])
    with tempfile.TemporaryDirectory(prefix="archi-cram-persist-") as tmp:
        root = Path(tmp)
        gate = DisposableGate(root)
        p = gate.propose(task, valid)
        e = gate.evaluate(task, p)
        gate.decide(task, p, e, explicit_commit=True, dry_run=False)
        event = gate.decide(task, p, e, explicit_commit=True, dry_run=False)
        assert event["decision"] == "ESCALATE" and event["reason"] == "replay" and not event["state_bytes_changed"]
        rows.append({"case": "replay", "expected": "ESCALATE", "check_status": "PASS", **event})
        restored = DisposableGate(root)
        assert restored.state_hash() == gate.state_hash() and restored.state()["assignment"] == valid
        child = subprocess.run([sys.executable, "-c",
            "import json,sys; from pathlib import Path; from admission import DisposableGate; g=DisposableGate(Path(sys.argv[1])); print(json.dumps({'state':g.state(),'hash':g.state_hash()}))",
            str(root)], cwd=Path(__file__).resolve().parent, text=True, capture_output=True, check=True)
        child_state = json.loads(child.stdout)
        assert child_state == {"state": gate.state(), "hash": gate.state_hash()}
        rows.append({"case": "subprocess_reopen_disposable_state", "check_status": "PASS", "revision": restored.state()["revision"],
            "state_hash": restored.state_hash(), "native_integration": "none"})
    with tempfile.TemporaryDirectory(prefix="archi-cram-race-") as tmp:
        gate = DisposableGate(Path(tmp))
        p1, p2 = gate.propose(task, valid), gate.propose(task, valid)
        e1, e2 = gate.evaluate(task, p1), gate.evaluate(task, p2)
        with ThreadPoolExecutor(max_workers=2) as pool:
            events = list(pool.map(lambda pe: gate.decide(task, *pe, explicit_commit=True, dry_run=False), [(p1,e1),(p2,e2)]))
        assert sorted(e["decision"] for e in events) == ["COMMIT", "ESCALATE"]
        assert gate.state()["revision"] == 1
        rows.append({"case": "two_threads_one_owner", "check_status": "PASS", "events": events,
                     "scope": "same_instance_only"})
    with tempfile.TemporaryDirectory(prefix="archi-cram-review-") as tmp:
        gate = DisposableGate(Path(tmp))
        p = gate.propose(task, valid)
        e = gate.evaluate(task, p)
        assert gate.decide(task, p, e)["decision"] == "DAMP"
        event = gate.decide(task, p, e, explicit_commit=True, dry_run=False)
        assert event["decision"] == "ESCALATE" and event["reason"] == "replay" and not event["state_bytes_changed"]
        rows.append({"case": "dry_run_is_terminal_attempt", "check_status": "PASS", **event})
    alternative = next(candidate for values in itertools.product(*(s["allowed_slots"] for s in task["scenes"]))
        if (candidate := dict(zip((s["id"] for s in task["scenes"]), values))) != valid
        and validate_schedule(task, candidate)["status"] == "PASS")
    with tempfile.TemporaryDirectory(prefix="archi-cram-stale-race-") as tmp:
        gate = DisposableGate(Path(tmp))
        p1, p2 = gate.propose(task, valid), gate.propose(task, alternative)
        e1, e2 = gate.evaluate(task, p1), gate.evaluate(task, p2)
        with ThreadPoolExecutor(max_workers=2) as pool:
            events = list(pool.map(lambda pe: gate.decide(task, *pe, explicit_commit=True, dry_run=False), [(p1,e1),(p2,e2)]))
        assert sorted(e["decision"] for e in events) == ["COMMIT", "ESCALATE"]
        loser = next(e for e in events if e["decision"] == "ESCALATE")
        assert loser["reason"] == "stale_state" and not loser["state_bytes_changed"]
        assert gate.state()["revision"] == 1
        rows.append({"case": "different_proposals_one_revision", "check_status": "PASS", "events": events,
                     "scope": "same_instance_only"})
    return rows


class AdmissionTests(unittest.TestCase):
    def test_disposable_admission_contract(self):
        rows = exercise_admission()
        self.assertEqual(len(rows), 32)
        self.assertTrue(all(row["check_status"] == "PASS" for row in rows))

    def test_explicit_impossible_requirements(self):
        task = make_tasks(count=4)[3]
        self.assertEqual(exact_reference(task)["status"], "UNSAT")

    def test_bool_is_not_a_valid_slot(self):
        task = make_tasks(count=1)[0]
        assignment = exact_reference(task)["assignment"]
        assignment["scene-0"] = True
        self.assertEqual(validate_schedule(task, assignment)["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
