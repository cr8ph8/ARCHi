"""Bounded, synthetic identity-link experiment using an explicit SQLite owner.

No native profile discovery, model invocation, network access, or app integration.
PASS is computed by trusted code. Receipts are consistency records, not signatures.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sqlite3
from typing import Callable


HERE = Path(__file__).resolve().parent
PROPOSAL_SCHEMA = "archi-memory-merge-proposal/v1"
EVIDENCE_SCHEMA = "archi-memory-merge-evidence/v1"
STORE_KIND = "archi-synthetic-memory-admission/v1"
STATUSES = frozenset({"PASS", "FAIL", "SKIPPED", "ERROR", "ABSTAIN", "ESCALATE"})
DECISIONS = frozenset({"COMMIT", "REJECT", "DAMP", "ESCALATE"})
GOVERNANCE_KEYS = frozenset({"governance", "policy", "validators", "permissions", "authority"})
PROPOSAL_KEYS = frozenset({"schema", "proposal_id", "operation", "left_id", "right_id",
                          "pre_state_hash", "pre_revision", "policy_hash", "source_hash"})


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"),
                      allow_nan=False).encode("utf-8")


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def load_policy() -> dict:
    return json.loads((HERE / "contract.json").read_text(encoding="utf-8"))


def state_hash(state: dict) -> str:
    # Content and monotonic revision are intentionally separate bindings. The
    # independent revision rejects ABA even if all other content is restored.
    return digest({key: value for key, value in state.items() if key != "revision"})


def initial_state(records: dict, sources: dict) -> dict:
    return {"revision": 0, "records": copy.deepcopy(records), "sources": copy.deepcopy(sources),
            "aliases": {}, "commits": []}


def proposal(state: dict, proposal_id: str, left_id: str = "r1", right_id: str = "r2",
             policy: dict | None = None) -> dict:
    policy = load_policy() if policy is None else policy
    return {"schema": PROPOSAL_SCHEMA, "proposal_id": proposal_id, "operation": "merge_records",
            "left_id": left_id, "right_id": right_id, "pre_state_hash": state_hash(state),
            "pre_revision": state["revision"], "policy_hash": digest(policy),
            "source_hash": digest(state["sources"])}


def _check(name: str, status: str, detail: str, policy: dict) -> dict:
    return {"validator": name, "version": policy["validators"][name], "status": status,
            "claim": detail}


def _recommend(checks: list[dict], governance: bool) -> str:
    if governance:
        return "ESCALATE"
    statuses = {check["status"] for check in checks}
    if statuses & {"FAIL", "ERROR"}:
        return "REJECT"
    if "ESCALATE" in statuses:
        return "ESCALATE"
    if statuses & {"SKIPPED", "ABSTAIN"}:
        return "DAMP"
    return "COMMIT" if statuses == {"PASS"} else "REJECT"


def evaluate(candidate: dict, state: dict, policy: dict | None = None,
             *, test_statuses: dict[str, str] | None = None) -> dict:
    """Evaluate without writing. COMMIT here is a recommendation, never an effect.

    test_statuses is trusted test-runner fault injection, never a candidate field.
    It can only replace an outcome with a non-PASS outcome.
    """
    policy = copy.deepcopy(load_policy() if policy is None else policy)
    governance = isinstance(candidate, dict) and (
        candidate.get("operation") == "edit_governance" or bool(GOVERNANCE_KEYS & candidate.keys()))
    expected_names = {"shape", "binding", "identity", "provenance", "relation_scope"}
    if set(policy["validators"]) != expected_names:
        raise ValueError("Unsupported validator population")
    shape = (isinstance(candidate, dict) and set(candidate) == PROPOSAL_KEYS
             and candidate.get("schema") == PROPOSAL_SCHEMA
             and candidate.get("operation") == "merge_records"
             and type(candidate.get("pre_revision")) is int
             and candidate["pre_revision"] >= 0
             and all(isinstance(candidate.get(k), str) and 0 < len(candidate[k]) <= 128
                     for k in PROPOSAL_KEYS - {"pre_revision"})
             and candidate.get("left_id") != candidate.get("right_id"))
    checks = [_check("shape", "PASS" if shape else "FAIL", "Closed proposal schema and bounded fields", policy)]
    bound = shape and (candidate["pre_state_hash"] == state_hash(state)
                       and candidate["pre_revision"] == state["revision"]
                       and candidate["policy_hash"] == digest(policy)
                       and candidate["source_hash"] == digest(state["sources"]))
    checks.append(_check("binding", "PASS" if bound else "FAIL",
                         "Exact state content, revision, source catalog and policy", policy))
    left = candidate.get("left_id") if isinstance(candidate, dict) else None
    right = candidate.get("right_id") if isinstance(candidate, dict) else None
    in_scope = (shape and left in state["records"] and right in state["records"]
                and left not in state["aliases"] and right not in state["aliases"])
    checks.append(_check("relation_scope", "PASS" if in_scope else "FAIL",
                         "Two explicit unaliased records; similarity paths confer no identity", policy))
    subject_sets: list[set[str]] = []
    origin_sets: list[set[str]] = []
    incomplete = False
    invalid_source = False
    if in_scope:
        for record_id in (left, right):
            subjects: set[str] = set()
            origins: set[str] = set()
            ids = state["records"][record_id].get("source_ids", [])
            if not isinstance(ids, list) or any(not isinstance(x, str) for x in ids):
                invalid_source = True
                ids = []
            for source_id in set(ids):
                source = state["sources"].get(source_id)
                if not source:
                    incomplete = True
                    continue
                if source.get("active") is not True:
                    continue
                if source.get("record_id") != record_id:
                    invalid_source = True
                    continue
                key, origin = source.get("subject_key"), source.get("origin")
                if not isinstance(key, str) or not key or not isinstance(origin, str) or not origin:
                    incomplete = True
                    continue
                subjects.add(key)
                origins.add(origin)
            subject_sets.append(subjects)
            origin_sets.append(origins)
    if not in_scope or invalid_source:
        identity_status = provenance_status = "FAIL"
    elif any(len(keys) > 1 for keys in subject_sets):
        identity_status = "FAIL"
        provenance_status = "PASS" if all(len(x) >= policy["minimum_origins_per_record"] for x in origin_sets) else "ABSTAIN"
    elif any(not keys for keys in subject_sets):
        identity_status = provenance_status = "ABSTAIN"
    else:
        identity_status = "PASS" if subject_sets[0] == subject_sets[1] else "FAIL"
        provenance_status = ("PASS" if not incomplete and all(
            len(x) >= policy["minimum_origins_per_record"] for x in origin_sets) else "ABSTAIN")
    checks.extend([
        _check("identity", identity_status, "Active designated source claims agree on one subject key", policy),
        _check("provenance", provenance_status,
               "Required active distinct designated provenance roots per record; no absent cited evidence", policy),
    ])
    if test_statuses:
        for name, status in test_statuses.items():
            if name not in expected_names or status not in STATUSES - {"PASS"}:
                raise ValueError("Fault injection must name a known validator and a non-PASS status")
        for check in checks:
            if check["validator"] in test_statuses:
                check["status"] = test_statuses[check["validator"]]
                check["claim"] += "; explicit test-runner fault injection"
    checks.sort(key=lambda x: x["validator"])
    return {"schema": EVIDENCE_SCHEMA, "proposal_hash": digest(candidate),
            "pre_state_hash": state_hash(state), "pre_revision": state["revision"],
            "policy_hash": digest(policy), "source_hash": digest(state["sources"]),
            "checks": checks, "recommendation": _recommend(checks, governance),
            "scope": "Synthetic source-assertion consistency under contract assumptions",
            "native_authority": False}


class Owner:
    """Explicit disposable SQLite owner. Each call uses its own connection.

    BEGIN IMMEDIATE serializes read/revalidate/write across processes. A durable
    replay entry and alias effect are in the same JSON row/transaction. Rejections
    leave that entire row unchanged; experiment traces live outside this owner.
    """
    def __init__(self, path: str | Path, policy: dict | None = None):
        self.path = Path(path).resolve()
        self.policy = copy.deepcopy(load_policy() if policy is None else policy)
        connection = self._connect()
        try:
            if connection.execute("SELECT value FROM metadata WHERE name='kind'").fetchone() != (STORE_KIND,):
                raise ValueError("Not a disposable memory-admission store")
        finally:
            connection.close()

    @classmethod
    def create(cls, path: str | Path, state: dict, policy: dict | None = None) -> "Owner":
        path = Path(path).resolve()
        # Exclusive creation avoids clobbering any existing file/profile.
        with path.open("xb"):
            pass
        selected = copy.deepcopy(load_policy() if policy is None else policy)
        connection = sqlite3.connect(path)
        try:
            connection.execute("CREATE TABLE metadata (name TEXT PRIMARY KEY, value TEXT NOT NULL)")
            connection.execute("INSERT INTO metadata VALUES ('kind', ?)", (STORE_KIND,))
            connection.execute("INSERT INTO metadata VALUES ('policy_hash', ?)", (digest(selected),))
            connection.execute("CREATE TABLE state (id INTEGER PRIMARY KEY CHECK(id=1), document TEXT NOT NULL)")
            connection.execute("INSERT INTO state VALUES (1, ?)", (canonical(state).decode(),))
            connection.commit()
        finally:
            connection.close()
        return cls(path, selected)

    def _connect(self) -> sqlite3.Connection:
        # mode=rw never silently creates a store on a typo or a missing path.
        connection = sqlite3.connect(self.path.as_uri() + "?mode=rw", uri=True,
                                     timeout=10, isolation_level=None)
        connection.execute("PRAGMA busy_timeout=10000")
        return connection

    def snapshot(self) -> dict:
        connection = self._connect()
        try:
            return json.loads(connection.execute("SELECT document FROM state WHERE id=1").fetchone()[0])
        finally:
            connection.close()

    def commit(self, candidate: dict, evidence: dict, *, reviewed_candidate_hash: str | None = None,
               omega: str | None = None, test_statuses: dict[str, str] | None = None,
               failpoint: Callable[[], None] | None = None) -> dict:
        connection = self._connect()
        before: dict | None = None
        try:
            connection.execute("BEGIN IMMEDIATE")
            before = json.loads(connection.execute("SELECT document FROM state WHERE id=1").fetchone()[0])

            def refuse(decision: str, reason: str) -> dict:
                connection.execute("ROLLBACK")
                return {"decision": decision, "reason": reason, "changed": False,
                        "pre_revision": before["revision"], "post_revision": before["revision"],
                        "pre_state_hash": state_hash(before), "post_state_hash": state_hash(before)}

            if not isinstance(candidate, dict):
                return refuse("REJECT", "invalid_candidate")
            if (candidate.get("operation") == "edit_governance"
                    or bool(GOVERNANCE_KEYS & candidate.keys())):
                return refuse("ESCALATE", "governance_change")
            if reviewed_candidate_hash is None or reviewed_candidate_hash != digest(candidate):
                return refuse("REJECT", "owner_review_missing_or_changed")
            stored_policy = connection.execute("SELECT value FROM metadata WHERE name='policy_hash'").fetchone()[0]
            if stored_policy != digest(self.policy):
                return refuse("ESCALATE", "policy_changed")
            if any(event["proposal_id"] == candidate.get("proposal_id") for event in before["commits"]):
                return refuse("REJECT", "replay")
            if (candidate.get("pre_revision") != before["revision"]
                    or candidate.get("pre_state_hash") != state_hash(before)):
                return refuse("REJECT", "stale_state")
            fresh = evaluate(candidate, before, self.policy, test_statuses=test_statuses)
            if canonical(evidence) != canonical(fresh):
                return refuse("REJECT", "evidence_mismatch")
            recommendation = fresh["recommendation"]
            if recommendation != "COMMIT":
                return refuse(recommendation, "required_checks_not_passed")
            if omega is not None:
                if omega not in DECISIONS:
                    return refuse("REJECT", "invalid_omega_decision")
                if omega != "COMMIT":
                    return refuse(omega, "omega_demotion")
            after = copy.deepcopy(before)
            after["aliases"][candidate["right_id"]] = candidate["left_id"]
            after["revision"] += 1
            after["commits"].append({"proposal_id": candidate["proposal_id"],
                                     "proposal_hash": digest(candidate), "evidence_hash": digest(fresh),
                                     "revision": after["revision"]})
            connection.execute("UPDATE state SET document=? WHERE id=1", (canonical(after).decode(),))
            if failpoint is not None:
                failpoint()
            connection.execute("COMMIT")
            return {"decision": "COMMIT", "reason": "admitted", "changed": True,
                    "pre_revision": before["revision"], "post_revision": after["revision"],
                    "pre_state_hash": state_hash(before), "post_state_hash": state_hash(after)}
        except Exception as error:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            if before is None:
                raise
            return {"decision": "REJECT", "reason": "transaction_error", "changed": False,
                    "error_type": type(error).__name__, "pre_revision": before["revision"],
                    "post_revision": before["revision"], "pre_state_hash": state_hash(before),
                    "post_state_hash": state_hash(before)}
        finally:
            connection.close()
