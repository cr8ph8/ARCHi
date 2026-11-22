#!/usr/bin/env python3
"""Freeze requirements, evaluate a candidate, or reverify scoped ARCHi evidence.

This is a bounded source-test coordinator. It does not call a model, install an
application, change a profile, or authorize Hampton COMMIT. The evaluator runs
the existing acceptance recipe from its own checkout against --candidate.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
import uuid

sys.dont_write_bytecode = True
from harness_evidence import (  # noqa: E402
    EvidenceError, canonical_bytes, file_sha256, load_object, snapshot_source,
    validate_contract, verify_bundle,
)
from harness_process import run_bounded  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
EVALUATOR_FILES = (
    "script/accept_relationship_admission.py",
    "script/harness_evidence.py",
    "script/run_agent_harness.py",
    "script/harness_process.py",
)


def emit(value: dict) -> None:
    print(json.dumps(value, indent=2, sort_keys=True), flush=True)


def pin(value: str) -> str:
    if not re.fullmatch(r"[a-f0-9]{64}", value):
        raise argparse.ArgumentTypeError("Expected a lowercase SHA-256 digest")
    return value


def new_target(path: Path) -> Path:
    path = path.expanduser().absolute()
    if path.is_symlink():
        raise EvidenceError("Refusing a symlink output target")
    target = path.parent.resolve() / path.name
    if target.exists():
        raise EvidenceError("Output already exists; use a new evidence destination")
    return target


def write_new(path: Path, raw: bytes) -> None:
    # O_EXCL avoids overwriting previous receipts, including a dangling symlink.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(raw)


def write_json(path: Path, value: dict) -> None:
    write_new(path, canonical_bytes(value) + b"\n")


def freeze(args: argparse.Namespace) -> int:
    contract_path = args.contract.expanduser().resolve(strict=True)
    contract = load_object(contract_path)
    validate_contract(contract)
    # Freeze exactly the validated input bytes; hash is held by the coordinator.
    raw = contract_path.read_bytes()
    # Recheck bytes before publishing the new frozen copy; validate it again below.
    if hashlib.sha256(raw).hexdigest() != file_sha256(contract_path):
        raise EvidenceError("Contract changed while freezing")
    target = new_target(args.output)
    target.parent.mkdir(parents=True, exist_ok=True)
    write_new(target, raw)
    validate_contract(load_object(target))
    emit({"contract": str(target), "contract_sha256": file_sha256(target),
          "scope": contract["scope"], "authorizes_commit": False})
    return 0


def exit_for(result: dict) -> int:
    return {"SOURCE_CHECKS_PASS": 0, "INCOMPLETE": 2}.get(result.get("decision"), 1)


def blocked(reason: str, request_id: str | None = None) -> dict:
    return {"schema": "archi-agent-harness-evaluation/v1", "request_id": request_id,
            "integrity": "ERROR", "source_status": "ERROR", "decision": "BLOCKED",
            "findings": [{"status": "ERROR", "reason": reason}],
            "installed_app_qualified": False, "authorizes_commit": False}


def evaluate(args: argparse.Namespace) -> int:
    candidate = args.candidate.expanduser().resolve(strict=True)
    contract_path = args.contract.expanduser().resolve(strict=True)
    if contract_path.is_relative_to(candidate):
        raise EvidenceError("Freeze the contract outside the candidate checkout")
    contract_raw = contract_path.read_bytes()
    if hashlib.sha256(contract_raw).hexdigest() != args.contract_sha256:
        raise EvidenceError("Frozen contract digest does not match the coordinator pin")
    contract = load_object(contract_path)
    validate_contract(contract)
    if file_sha256(contract_path) != args.contract_sha256:
        raise EvidenceError("Contract changed while preparing evaluation")
    if not (candidate / "desktop/Package.swift").is_file():
        raise EvidenceError("Candidate is missing desktop/Package.swift")
    before = snapshot_source(candidate)
    output = new_target(args.output)
    if output.is_relative_to(candidate) or output.is_relative_to(ROOT):
        raise EvidenceError("Evidence must be outside both candidate and evaluator checkouts")
    output.mkdir(parents=True, exist_ok=False)
    write_new(output / "contract.json", contract_raw)
    write_json(output / "source-before.json", before)
    command = [sys.executable, str(ROOT / EVALUATOR_FILES[0]),
               "--archi-repo", str(candidate), "--output", str(output / "raw"),
               "--command-timeout", str(args.command_timeout)]
    request = {
        "schema": "archi-agent-harness-request/v1",
        "request_id": uuid.uuid4().hex,
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "contract_sha256": args.contract_sha256,
        "source_before_sha256": file_sha256(output / "source-before.json"),
        "source_manifest_sha256": before["manifest_sha256"],
        "candidate_root": str(candidate), "candidate_commit": before["commit"],
        "evaluator_files": {relative: file_sha256(ROOT / relative)
                            for relative in EVALUATOR_FILES},
        "host": {"system": platform.system(), "release": platform.release(),
                 "macos": platform.mac_ver()[0], "python": platform.python_version()},
        "raw_report_path": "raw/acceptance.json",
        "runner_command": command,
    }
    write_json(output / "request.json", request)
    request_pin = file_sha256(output / "request.json")
    # Emit BEFORE subprocess execution so the controller can retain the pin in
    # a context the generator cannot edit. A copy in the bundle is not authority.
    emit({"event": "EVALUATION_REQUEST_BOUND", "request_id": request["request_id"],
          "request_sha256": request_pin, "evidence": str(output),
          "candidate_manifest_sha256": before["manifest_sha256"]})
    env = {key: value for key, value in os.environ.items() if not key.startswith("ARCHI_")}
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    started = time.monotonic()
    started_utc = datetime.now(timezone.utc).isoformat()
    execution_error = None
    timed_out = False
    returncode = None
    try:
        with (output / "runner-console.log").open("x", encoding="utf-8") as handle:
            process = run_bounded(
                command, cwd=candidate, env=env, stdout=handle, stderr=subprocess.STDOUT,
                timeout=args.command_timeout * 5 + 90,
            )
        returncode = process.returncode
    except subprocess.TimeoutExpired as error:
        timed_out = True
        execution_error = str(error)
    except OSError as error:
        execution_error = str(error)
    execution = {
        "schema": "archi-agent-harness-execution/v1", "request_sha256": request_pin,
        "command": command, "exit_code": returncode, "timed_out": timed_out,
        "error": execution_error,
        "elapsed_seconds": round(time.monotonic() - started, 3),
        "console_sha256": file_sha256(output / "runner-console.log")
        if (output / "runner-console.log").is_file() else None,
        "started_at_utc": started_utc,
        "completed_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    write_json(output / "execution.json", execution)
    try:
        write_json(output / "source-after.json", snapshot_source(candidate))
        result = verify_bundle(output, candidate, request_pin)
        if execution_error is not None:
            result = blocked("Acceptance runner execution failed: " + execution_error,
                             request["request_id"])
        else:
            report = load_object(output / "raw/acceptance.json")
            if type(report.get("exit_code")) is not int or returncode != report["exit_code"]:
                result = blocked("Observed runner exit code disagrees with report",
                                 request["request_id"])
    except (EvidenceError, OSError, ValueError) as error:
        result = blocked(str(error), request["request_id"])
    result["execution_sha256"] = file_sha256(output / "execution.json")
    result["request_sha256"] = request_pin
    write_json(output / "evaluation.json", result)
    emit({"evaluation": str(output / "evaluation.json"), **result})
    return exit_for(result)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    freezing = commands.add_parser("freeze", help="Copy a reviewed contract to a new frozen file")
    freezing.add_argument("--contract", type=Path, required=True)
    freezing.add_argument("--output", type=Path, required=True)
    evaluating = commands.add_parser("evaluate", help="Run the fixed native source-test recipe")
    evaluating.add_argument("--candidate", type=Path, required=True)
    evaluating.add_argument("--contract", type=Path, required=True)
    evaluating.add_argument("--contract-sha256", type=pin, required=True)
    evaluating.add_argument("--output", type=Path, required=True)
    evaluating.add_argument("--command-timeout", type=int, default=900)
    verifying = commands.add_parser("verify", help="Recheck existing evidence without executing tests")
    verifying.add_argument("--candidate", type=Path, required=True)
    verifying.add_argument("--evidence", type=Path, required=True)
    verifying.add_argument("--request-sha256", type=pin, required=True)
    args = parser.parse_args()
    if args.command == "evaluate" and not 1 <= args.command_timeout <= 3600:
        parser.error("--command-timeout must be between 1 and 3600 seconds")
    try:
        if args.command == "freeze":
            return freeze(args)
        if args.command == "evaluate":
            return evaluate(args)
        result = verify_bundle(args.evidence.expanduser().absolute(),
                               args.candidate.expanduser().resolve(strict=True),
                               args.request_sha256)
        emit(result)
        return exit_for(result)
    except (EvidenceError, OSError, ValueError) as error:
        emit(blocked(str(error)))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
