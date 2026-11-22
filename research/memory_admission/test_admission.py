"""Behavioral checks for the disposable reference owner, not native ARCHi.

Fixtures state their identity evidence directly. No experiment oracle or expected
decision field enters the validator. Process tests use spawn on Linux and macOS.
"""
from __future__ import annotations

import copy
import json
import multiprocessing
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from admission import Owner, digest, evaluate, initial_state, load_policy, proposal, state_hash


def fictional_state() -> dict:
    """Two real fixture identities with an intentionally ambiguous shared name."""
    records, sources = {}, {}
    for record_id, subject, name in (
        ("r1", "fictional-person-a", "Rowan Vale"),
        ("r2", "fictional-person-a", "R. Vale"),
        ("r3", "fictional-person-b", "Rowan Vale"),
        ("r4", "fictional-person-b", "Rowan V."),
    ):
        ids = []
        for suffix, origin in (("a", "fixture-registry-a"), ("b", "fixture-registry-b")):
            source_id = f"{record_id}-{suffix}"
            ids.append(source_id)
            sources[source_id] = {"record_id": record_id, "subject_key": subject,
                                  "origin": origin, "active": True}
        records[record_id] = {"name": name, "source_ids": ids}
    return initial_state(records, sources)


def _competing_worker(path, candidate, evidence, ready, results):
    try:
        owner = Owner(path)
        ready.wait(timeout=10)
        result = owner.commit(candidate, evidence, reviewed_candidate_hash=digest(candidate))
        results.put({"result": result})
    except BaseException as error:
        results.put({"error": type(error).__name__, "detail": str(error)})


def _interrupted_worker(path, candidate, evidence, updated, release):
    def after_update():
        updated.set()
        if not release.wait(timeout=20):
            raise TimeoutError("Parent did not finish interruption test")

    Owner(path).commit(candidate, evidence, reviewed_candidate_hash=digest(candidate),
                       failpoint=after_update)


def _stop_process(process):
    if process.is_alive():
        process.terminate()
    process.join(timeout=5)
    if process.is_alive():
        process.kill()
        process.join(timeout=5)


class AdmissionBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="archi-admission-tests-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "reference.sqlite"
        self.policy = load_policy()
        self.owner = Owner.create(self.path, fictional_state(), self.policy)

    def prepared(self, proposal_id="p-1", left_id="r1", right_id="r2"):
        current = self.owner.snapshot()
        candidate = proposal(current, proposal_id, left_id, right_id, self.policy)
        return candidate, evaluate(candidate, current, self.policy)

    def commit(self, candidate, evidence, **kwargs):
        kwargs.setdefault("reviewed_candidate_hash", digest(candidate))
        return self.owner.commit(candidate, evidence, **kwargs)

    def replace_fixture_state(self, state):
        """Test-only trusted catalog/ABA change; not a production transition."""
        connection = sqlite3.connect(self.path)
        try:
            connection.execute("UPDATE state SET document=? WHERE id=1", (json.dumps(state),))
            connection.commit()
        finally:
            connection.close()

    def assert_unchanged(self, before, result, decision):
        self.assertEqual(result["decision"], decision)
        self.assertFalse(result["changed"])
        self.assertEqual(Owner(self.path, self.policy).snapshot(), before)
        self.assertEqual(result["pre_revision"], result["post_revision"])
        self.assertEqual(result["pre_state_hash"], result["post_state_hash"])

    def test_evaluation_is_only_a_recommendation(self):
        before = self.owner.snapshot()
        _, evidence = self.prepared()
        self.assertEqual(evidence["recommendation"], "COMMIT")
        self.assertIs(evidence["native_authority"], False)
        self.assertEqual(self.owner.snapshot(), before)

    def test_valid_merge_preserves_originals_and_survives_reopen(self):
        before = self.owner.snapshot()
        candidate, evidence = self.prepared()
        result = self.commit(candidate, evidence)
        self.assertEqual(result["decision"], "COMMIT")
        self.assertTrue(result["changed"])
        after = Owner(self.path).snapshot()
        self.assertEqual(after["aliases"], {"r2": "r1"})
        self.assertEqual(after["records"], before["records"])
        self.assertEqual(after["sources"], before["sources"])
        self.assertEqual(after["revision"], 1)
        self.assertEqual(len(after["commits"]), 1)
        self.assertEqual(after["commits"][0]["proposal_id"], "p-1")

    def test_equal_names_do_not_merge_distinct_identities(self):
        before = self.owner.snapshot()
        self.assertEqual(before["records"]["r1"]["name"], before["records"]["r3"]["name"])
        candidate, evidence = self.prepared(left_id="r1", right_id="r3")
        self.assertEqual(next(c["status"] for c in evidence["checks"] if c["validator"] == "identity"), "FAIL")
        self.assert_unchanged(before, self.commit(candidate, evidence), "REJECT")

    def test_copied_documents_are_not_independent_origins(self):
        state = self.owner.snapshot()
        state["sources"]["r2-b"]["origin"] = state["sources"]["r2-a"]["origin"]
        self.replace_fixture_state(state)
        candidate, evidence = self.prepared()
        self.assertEqual(next(c["status"] for c in evidence["checks"] if c["validator"] == "provenance"), "ABSTAIN")
        self.assert_unchanged(state, self.commit(candidate, evidence), "DAMP")

    def test_missing_unknown_and_inactive_sources_withhold_admission(self):
        for condition in ("missing", "unknown", "inactive"):
            with self.subTest(condition=condition):
                state = fictional_state()
                if condition == "missing":
                    state["records"]["r2"]["source_ids"] = []
                elif condition == "unknown":
                    state["records"]["r2"]["source_ids"].append("absent-source")
                else:
                    state["sources"]["r2-b"]["active"] = False
                self.replace_fixture_state(state)
                candidate, evidence = self.prepared()
                self.assert_unchanged(state, self.commit(candidate, evidence), "DAMP")

    def test_source_assertion_for_another_record_is_refused(self):
        state = self.owner.snapshot()
        state["records"]["r2"]["source_ids"] = ["r1-a", "r1-b"]
        self.replace_fixture_state(state)
        candidate, evidence = self.prepared()
        self.assert_unchanged(state, self.commit(candidate, evidence), "REJECT")

    def test_conflicting_active_assertions_are_refused(self):
        state = self.owner.snapshot()
        state["sources"]["r2-b"]["subject_key"] = "fictional-person-b"
        self.replace_fixture_state(state)
        candidate, evidence = self.prepared()
        self.assert_unchanged(state, self.commit(candidate, evidence), "REJECT")

    def test_similarity_path_does_not_establish_identity(self):
        state = self.owner.snapshot()
        state["similarity_links"] = [["r1", "r2"], ["r2", "r3"]]
        self.replace_fixture_state(state)
        candidate, evidence = self.prepared(left_id="r1", right_id="r3")
        self.assert_unchanged(state, self.commit(candidate, evidence), "REJECT")

    def test_forged_pass_receipt_cannot_upgrade_wrong_identity(self):
        before = self.owner.snapshot()
        candidate, evidence = self.prepared(left_id="r1", right_id="r3")
        evidence["recommendation"] = "COMMIT"
        for check in evidence["checks"]:
            check["status"] = "PASS"
        result = self.commit(candidate, evidence)
        self.assertEqual(result["reason"], "evidence_mismatch")
        self.assert_unchanged(before, result, "REJECT")

    def test_missing_and_duplicate_receipt_checks_are_refused(self):
        before = self.owner.snapshot()
        for fault in ("missing", "duplicate"):
            with self.subTest(fault=fault):
                candidate, evidence = self.prepared()
                if fault == "missing":
                    evidence["checks"].pop()
                else:
                    evidence["checks"].append(copy.deepcopy(evidence["checks"][0]))
                result = self.commit(candidate, evidence)
                self.assertEqual(result["reason"], "evidence_mismatch")
                self.assert_unchanged(before, result, "REJECT")

    def test_changed_candidate_requires_new_evidence(self):
        before = self.owner.snapshot()
        candidate, evidence = self.prepared()
        candidate["left_id"], candidate["right_id"] = candidate["right_id"], candidate["left_id"]
        # A fresh review alone cannot make evidence for the old effect applicable.
        result = self.commit(candidate, evidence)
        self.assertEqual(result["reason"], "evidence_mismatch")
        self.assert_unchanged(before, result, "REJECT")

    def test_missing_or_mismatched_owner_review_blocks_an_eligible_candidate(self):
        before = self.owner.snapshot()
        candidate, evidence = self.prepared()
        for review in (None, "0" * 64):
            with self.subTest(review=review):
                result = self.commit(candidate, evidence, reviewed_candidate_hash=review)
                self.assertEqual(result["reason"], "owner_review_missing_or_changed")
                self.assert_unchanged(before, result, "REJECT")

    def test_changed_source_catalog_invalidates_earlier_evidence(self):
        candidate, evidence = self.prepared()
        state = self.owner.snapshot()
        state["sources"]["r2-b"]["active"] = False
        self.replace_fixture_state(state)
        self.assert_unchanged(state, self.commit(candidate, evidence), "REJECT")

    def test_changed_policy_is_escalated_without_writing(self):
        before = self.owner.snapshot()
        candidate, evidence = self.prepared()
        changed = copy.deepcopy(self.policy)
        changed["minimum_origins_per_record"] += 1
        other_owner = Owner(self.path, changed)
        result = other_owner.commit(candidate, evidence, reviewed_candidate_hash=digest(candidate))
        self.assertEqual(result["reason"], "policy_changed")
        self.assert_unchanged(before, result, "ESCALATE")

    def test_nonpass_validator_statuses_remain_visible_and_fail_closed(self):
        before = self.owner.snapshot()
        expected = {"FAIL": "REJECT", "SKIPPED": "DAMP", "ERROR": "REJECT",
                    "ABSTAIN": "DAMP", "ESCALATE": "ESCALATE"}
        candidate, _ = self.prepared()
        for status, decision in expected.items():
            with self.subTest(status=status):
                injected = {"identity": status}
                evidence = evaluate(candidate, before, self.policy, test_statuses=injected)
                self.assertEqual(next(c["status"] for c in evidence["checks"] if c["validator"] == "identity"), status)
                self.assert_unchanged(before, self.commit(candidate, evidence, test_statuses=injected), decision)

    def test_fault_injection_cannot_claim_a_pass(self):
        before = self.owner.snapshot()
        candidate, _ = self.prepared(left_id="r1", right_id="r3")
        with self.assertRaises(ValueError):
            evaluate(candidate, before, self.policy, test_statuses={"identity": "PASS"})
        self.assertEqual(self.owner.snapshot(), before)

    def test_governance_attempts_escalate_without_writing(self):
        before = self.owner.snapshot()
        for key in ("operation", "policy", "validators", "permissions", "authority"):
            with self.subTest(key=key):
                candidate, _ = self.prepared()
                candidate[key] = "edit_governance" if key == "operation" else {}
                evidence = evaluate(candidate, before, self.policy)
                result = self.commit(candidate, evidence)
                self.assertEqual(result["reason"], "governance_change")
                self.assert_unchanged(before, result, "ESCALATE")

    def test_omega_cannot_upgrade_a_rejected_candidate(self):
        before = self.owner.snapshot()
        candidate, evidence = self.prepared(left_id="r1", right_id="r3")
        self.assert_unchanged(before, self.commit(candidate, evidence, omega="COMMIT"), "REJECT")

    def test_omega_can_demote_an_eligible_candidate(self):
        before = self.owner.snapshot()
        candidate, evidence = self.prepared()
        for decision in ("REJECT", "DAMP", "ESCALATE"):
            with self.subTest(decision=decision):
                result = self.commit(candidate, evidence, omega=decision)
                self.assertEqual(result["reason"], "omega_demotion")
                self.assert_unchanged(before, result, decision)

    def test_exact_replay_is_refused_after_reopening(self):
        candidate, evidence = self.prepared()
        self.assertEqual(self.commit(candidate, evidence)["decision"], "COMMIT")
        self.owner = Owner(self.path)
        before = self.owner.snapshot()
        result = self.commit(candidate, evidence)
        self.assertEqual(result["reason"], "replay")
        self.assert_unchanged(before, result, "REJECT")

    def test_reused_proposal_id_cannot_authorize_a_different_valid_effect(self):
        candidate, evidence = self.prepared()
        self.assertEqual(self.commit(candidate, evidence)["decision"], "COMMIT")
        before = self.owner.snapshot()
        altered, fresh = self.prepared(left_id="r3", right_id="r4")
        self.assertEqual(fresh["recommendation"], "COMMIT")
        result = self.commit(altered, fresh)
        self.assertEqual(result["reason"], "replay")
        self.assert_unchanged(before, result, "REJECT")

    def test_monotonic_revision_rejects_content_aba(self):
        candidate, evidence = self.prepared()
        original = self.owner.snapshot()
        restored = copy.deepcopy(original)
        restored["revision"] += 2
        self.replace_fixture_state(restored)
        self.assertEqual(state_hash(original), state_hash(restored))
        result = self.commit(candidate, evidence)
        self.assertEqual(result["reason"], "stale_state")
        self.assert_unchanged(restored, result, "REJECT")

    def test_exception_after_update_rolls_back_effect_and_replay_entry(self):
        before = self.owner.snapshot()
        candidate, evidence = self.prepared()

        def fail():
            raise RuntimeError("Injected after SQL UPDATE and before COMMIT")

        result = self.commit(candidate, evidence, failpoint=fail)
        self.assertEqual(result["reason"], "transaction_error")
        self.assert_unchanged(before, result, "REJECT")
        self.assertEqual(self.commit(candidate, evidence)["decision"], "COMMIT")

    def test_two_spawned_processes_compete_for_one_snapshot(self):
        before = self.owner.snapshot()
        candidate_a, evidence_a = self.prepared(proposal_id="race-a")
        candidate_b, evidence_b = self.prepared(proposal_id="race-b", left_id="r3", right_id="r4")
        context = multiprocessing.get_context("spawn")
        ready, results = context.Barrier(3), context.Queue()
        processes = [context.Process(target=_competing_worker,
                     args=(str(self.path), candidate, evidence, ready, results))
                     for candidate, evidence in ((candidate_a, evidence_a), (candidate_b, evidence_b))]
        try:
            for process in processes:
                process.start()
            ready.wait(timeout=10)
            outcomes = [results.get(timeout=15) for _ in processes]
            for process in processes:
                process.join(timeout=10)
                self.assertFalse(process.is_alive(), "Competing worker did not finish")
                self.assertEqual(process.exitcode, 0)
            self.assertTrue(all("result" in item for item in outcomes), outcomes)
            self.assertEqual(sorted(item["result"]["decision"] for item in outcomes), ["COMMIT", "REJECT"])
            after = self.owner.snapshot()
            self.assertEqual(after["revision"], before["revision"] + 1)
            self.assertEqual(len(after["commits"]), 1)
            self.assertIn(after["aliases"], ({"r2": "r1"}, {"r4": "r3"}))
            self.assertEqual(after["records"], before["records"])
            self.assertEqual(after["sources"], before["sources"])
        finally:
            for process in processes:
                if process.pid is not None:
                    _stop_process(process)
            results.close()
            results.join_thread()

    def test_terminated_process_after_update_leaves_no_partial_commit(self):
        before = self.owner.snapshot()
        candidate, evidence = self.prepared()
        context = multiprocessing.get_context("spawn")
        updated, release = context.Event(), context.Event()
        process = context.Process(target=_interrupted_worker,
                  args=(str(self.path), candidate, evidence, updated, release))
        try:
            process.start()
            self.assertTrue(updated.wait(timeout=10), "Worker did not reach post-UPDATE failpoint")
            self.assertTrue(process.is_alive())
            process.terminate()
            process.join(timeout=10)
            self.assertFalse(process.is_alive())
            self.assertNotEqual(process.exitcode, 0)
            self.assertEqual(Owner(self.path).snapshot(), before)
            self.assertEqual(self.commit(candidate, evidence)["decision"], "COMMIT")
        finally:
            if process.pid is not None:
                _stop_process(process)


if __name__ == "__main__":
    unittest.main()
