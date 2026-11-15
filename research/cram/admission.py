"""Disposable admission reference. NOT ARCHi's native owner or a production API.

Every mutation is confined to the one scratch file selected by the harness.
The caller supplies authority separately from the untrusted proposal. Evidence
is issued here and bound to the proposal, context and state. A model's own
status, energy or confidence never authorizes an application change.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import threading
import uuid

from scheduling import canonical, digest, validate_schedule, validate_task


@dataclass(frozen=True)
class Proposal:
    assignment: object
    pre_state_hash: str
    context_hash: str
    target: str = "disposable_schedule"
    operation: str = "replace_schedule"

    def content_hash(self) -> str:
        return digest({"assignment": self.assignment, "target": self.target, "operation": self.operation})


@dataclass(frozen=True)
class Evidence:
    token: str
    proposal_hash: str
    context_hash: str
    pre_state_hash: str
    status: str
    reasons: tuple[str, ...]
    validator: str = "independent-schedule-checker-v1"


class DisposableGate:
    """A single-process test owner, deliberately disconnected from native saves.

    Locking protects threads in THIS instance. No multi-process locking,
    production access control, durable replay cache or authenticated ledger is
    claimed. Instantiation and explicit COMMIT are the only protected writes.
    """
    def __init__(self, directory: Path):
        self.root = directory.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "disposable_state.json"
        self.lock = threading.Lock()
        self.issued: dict[str, Evidence] = {}
        self.seen: set[tuple[str, str]] = set()
        self.events: list[dict] = []
        if not self.path.exists():
            self._write({"revision": 0, "assignment": None, "context_hash": None})

    def _write(self, state: dict):
        temporary = self.path.with_suffix(".tmp")
        with temporary.open("w", encoding="utf-8") as stream:
            stream.write(canonical(state) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, self.path)

    def state(self) -> dict:
        return json.loads(self.path.read_text(encoding="utf-8"))

    def state_hash(self) -> str:
        return digest(self.state())

    def propose(self, task: dict, assignment: object, **kwargs) -> Proposal:
        # Copy the caller's mutable value so later producer mutation cannot
        # silently alter an issued proposal.
        copied = json.loads(canonical(assignment))
        return Proposal(copied, self.state_hash(), digest(task), **kwargs)

    def evaluate(self, task: dict, proposal: Proposal, *, test_validator_status: str | None = None) -> Evidence:
        """The test-only status override belongs to the harness, never the proposal."""
        if test_validator_status is not None:
            if test_validator_status not in {"ERROR", "SKIPPED", "ABSTAIN"}:
                raise ValueError("only unavailable-validator fixtures may override evaluation")
            result = {"status": test_validator_status, "reasons": ["test_fixture"]}
        else:
            try:
                result = validate_schedule(task, proposal.assignment)
            except Exception as exc:
                result = {"status": "ERROR", "reasons": [type(exc).__name__]}
        evidence = Evidence(uuid.uuid4().hex, proposal.content_hash(), digest(task),
                            proposal.pre_state_hash, result["status"], tuple(result["reasons"]))
        self.issued[evidence.token] = evidence
        return evidence

    def decide(self, task: dict, proposal: Proposal, evidence: Evidence, *,
               explicit_commit: bool = False, dry_run: bool = True,
               authorized_target: str = "disposable_schedule") -> dict:
        with self.lock:
            before_bytes = self.path.read_bytes()
            before = self.state_hash()
            decision, reason = "ESCALATE", "unclassified"
            effective_validator_status = evidence.status
            content_hash = proposal.content_hash()
            key = (content_hash, proposal.pre_state_hash)
            if validate_task(task)["status"] != "PASS":
                decision, reason = "ESCALATE", "invalid_context"
                effective_validator_status = "ERROR"
            elif proposal.operation != "replace_schedule":
                decision, reason = "ESCALATE", "governance_or_unsupported_operation"
            elif proposal.target != "disposable_schedule" or authorized_target != proposal.target:
                decision, reason = "REJECT", "target_or_scope_mismatch"
            elif key in self.seen:
                decision, reason = "ESCALATE", "replay"
            elif proposal.pre_state_hash != before:
                decision, reason = "ESCALATE", "stale_state"
            elif proposal.context_hash != digest(task):
                decision, reason = "ESCALATE", "stale_context"
            elif self.issued.get(evidence.token) != evidence or (
                evidence.proposal_hash, evidence.context_hash, evidence.pre_state_hash
            ) != (content_hash, digest(task), before):
                decision, reason = "ESCALATE", "unbound_or_substituted_evidence"
            elif evidence.status == "FAIL":
                decision, reason = "REJECT", "validator_fail"
            elif evidence.status in {"ERROR", "ABSTAIN"}:
                decision, reason = "ESCALATE", "validator_" + evidence.status.lower()
            elif evidence.status != "PASS":
                decision, reason = "DAMP", "validator_incomplete"
            elif type(explicit_commit) is not bool or type(dry_run) is not bool:
                decision, reason = "REJECT", "malformed_authority_flags"
            elif not explicit_commit or dry_run:
                decision, reason = "DAMP", "explicit_commit_required"
            else:
                # Recheck under this owner's lock against the current context.
                try:
                    check = validate_schedule(task, proposal.assignment)
                except Exception as exc:
                    check = {"status": "ERROR", "reasons": [type(exc).__name__]}
                effective_validator_status = check["status"]
                if check["status"] in {"ERROR", "ABSTAIN"}:
                    decision, reason = "ESCALATE", "commit_revalidation_error"
                elif check["status"] != "PASS":
                    decision, reason = "REJECT", "commit_revalidation_failed"
                else:
                    state = self.state()
                    self._write({"revision": state["revision"] + 1,
                        "assignment": proposal.assignment, "context_hash": digest(task)})
                    decision, reason = "COMMIT", "explicit_disposable_commit"
            self.seen.add(key)
            after = self.state_hash()
            event = {"decision": decision, "reason": reason, "validator_status": effective_validator_status,
                "pre_state_hash": before, "post_state_hash": after, "proposal_hash": content_hash,
                "context_hash": digest(task), "state_bytes_changed": before_bytes != self.path.read_bytes(),
                "production_authority": False, "native_integration": "none"}
            self.events.append(event)
            return event
