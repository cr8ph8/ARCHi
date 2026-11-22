#!/usr/bin/env python3
"""Record source-test evidence without launching or replacing an installed app.

Uses the existing SwiftPM tests. An optional QiMovi test runs with Node, and an
explicit --live-receipt opt-in invokes the existing disposable-profile local
receipt test. No model installation, native launch or user-profile mutation is
performed by this runner. Installed-app/restart acceptance stays unobserved.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
SUITES = (
    "HamptonProposalValidationTests",
    "HamptonSessionContextTests",
    "WorkingCopyRevisionTests",
    "WorkingCopyStoreTests",
    "EvolutionRequestBindingTests",
)
STATUSES = ("PASS", "FAIL", "SKIPPED", "ERROR", "ABSTAIN", "ESCALATE")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def git_value(root: Path, *arguments: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *arguments], capture_output=True,
            text=True, timeout=10, check=False,
        )
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def source_record(root: Path, paths: list[Path]) -> dict:
    files = []
    for file in sorted(set(paths)):
        if file.is_file():
            files.append({"path": str(file.relative_to(root)), "sha256": sha256(file)})
    return {
        "root": str(root), "commit": git_value(root, "rev-parse", "HEAD"),
        "working_tree_status": git_value(root, "status", "--porcelain"),
        "files": files,
        "manifest_sha256": hashlib.sha256(
            json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest(),
    }


def classify_node(text: str, returncode: int) -> dict:
    counts = {}
    for name in ("tests", "pass", "fail", "cancelled", "skipped", "todo"):
        matches = re.findall(r"^# " + name + r"\s+(\d+)\s*$", text, re.MULTILINE)
        if matches:
            counts[name] = int(matches[-1])
    if counts.get("fail", 0) or counts.get("cancelled", 0):
        status, reason = "FAIL", "TEST_FAILURE"
    elif returncode != 0:
        status, reason = "ERROR", "TEST_COMMAND_FAILED"
    elif not counts.get("tests") or "pass" not in counts or "fail" not in counts:
        status, reason = "ERROR", "NO_CONFIRMED_TEST_RESULTS"
    elif counts.get("skipped", 0) or counts.get("todo", 0):
        status, reason = "SKIPPED", "TEST_RUN_HAS_UNEXECUTED_CASES"
    elif counts.get("pass") != counts["tests"]:
        status, reason = "ERROR", "INCOMPLETE_TEST_ACCOUNTING"
    else:
        status, reason = "PASS", "EXECUTED_TESTS_PASSED"
    return {"status": status, "reason": reason, "node_test_counts": counts}


def classify_swift(text: str, returncode: int, expected_suite: str | None = None) -> dict:
    # XCTest and Swift Testing report different populations. Keep their counts
    # separate; take only XCTest's final aggregate, not every nested suite.
    clean = re.sub(r"\x1b\[[0-9;]*m", "", text)
    rows = re.findall(
        r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?",
        clean,
    )
    xctest = None
    if rows:
        total, skipped, failures = rows[-1]
        xctest = {"executed": int(total), "skipped": int(skipped or 0), "failures": int(failures)}
    testing_rows = re.findall(
        r"Test run with (\d+) tests?(?: in \d+ suites?)? (passed|failed)", clean,
    )
    testing = None
    if testing_rows:
        total, outcome = testing_rows[-1]
        testing = {"reported_tests": int(total), "outcome": outcome}
    skipped_lines = sorted(set(re.findall(r"^.*(?:Test|test) .*\bskipped\b.*$", clean, re.MULTILINE)))
    completed_suites = set(re.findall(r"Test Suite '([^']+)' (?:passed|failed)\b", clean))
    for quoted, plain in re.findall(r'Suite (?:"([^"]+)"|([A-Za-z_][\w.]*)) (?:passed|failed)\b', clean):
        completed_suites.add(quoted or plain)
    suite_observed = expected_suite is None or any(
        name == expected_suite or name == "ARCHiDesktopTests." + expected_suite
        for name in completed_suites
    )
    failures = bool(xctest and xctest["failures"]) or bool(testing and testing["outcome"] == "failed")
    confirmed = bool(xctest and xctest["executed"] > xctest["skipped"]) or bool(testing and testing["reported_tests"] > 0)
    skipped = bool(xctest and xctest["skipped"]) or bool(skipped_lines)
    if failures:
        status, reason = "FAIL", "TEST_FAILURE"
    elif returncode != 0:
        status, reason = "ERROR", "BUILD_OR_TEST_COMMAND_FAILED"
    elif skipped:
        status, reason = "SKIPPED", "TEST_RUN_HAS_UNEXECUTED_CASES"
    elif not confirmed:
        status, reason = "ERROR", "NO_CONFIRMED_TEST_RESULTS"
    elif not suite_observed:
        status, reason = "ERROR", "EXPECTED_SUITE_NOT_OBSERVED"
    else:
        status, reason = "PASS", "EXECUTED_TESTS_PASSED"
    return {"status": status, "reason": reason, "xctest": xctest,
            "swift_testing": testing, "skip_lines": skipped_lines,
            "expected_suite": expected_suite, "completed_suites": sorted(completed_suites)}


def validate_live_receipt(receipt_path: Path) -> dict:
    """Malformed JSON shapes are evidence errors, never runner exceptions."""
    metadata = {"path": str(receipt_path)}
    try:
        raw = receipt_path.read_bytes()
        metadata["sha256"] = hashlib.sha256(raw).hexdigest()
        receipt = json.loads(raw)
        if not isinstance(receipt, dict):
            raise ValueError("Live receipt must be a JSON object")
        checks = receipt.get("checks")
        if not isinstance(checks, dict) or not checks or any(type(value) is not bool for value in checks.values()):
            raise ValueError("Live receipt checks must be a nonempty object of booleans")
        if (type(receipt.get("receiptAccountingPassed")) is not bool
                or type(receipt.get("currentInstructionFollowed")) is not bool
                or type(receipt.get("externalCalls")) is not int
                or receipt.get("result") not in ("passed", "failed")):
            raise ValueError("Live receipt outcome fields have unsupported types or values")
        metadata.update(model=receipt.get("model"), result=receipt["result"])
        expected = (receipt["result"] == "passed" and receipt["receiptAccountingPassed"] is True
                    and receipt["currentInstructionFollowed"] is True and receipt["externalCalls"] == 0
                    and all(value is True for value in checks.values()))
        return {"status": "PASS" if expected else "FAIL",
                "reason": "LIVE_RECEIPT_CHECKS_PASSED" if expected else "LIVE_RECEIPT_REQUIREMENTS_NOT_MET",
                "receipt": metadata}
    except (OSError, ValueError, TypeError) as error:
        return {"status": "ERROR", "reason": "LIVE_RECEIPT_EVIDENCE_UNAVAILABLE",
                "error": str(error), "receipt": metadata}


def run_command(name: str, command: list[str], cwd: Path, output: Path,
                timeout: int, overrides: dict[str, str] | None = None) -> dict:
    from harness_process import run_bounded

    log = output / f"{name}.log"
    started = time.monotonic()
    record = {"name": name, "command": command, "cwd": str(cwd),
              "environment_overrides": overrides or {}, "started_at_utc": utc_now(),
              "log": str(log), "command_started": False}
    env = os.environ.copy()
    # Existing opt-in native tests must never be enabled accidentally by an
    # inherited shell setting. --live-receipt adds back only its two variables.
    for key in list(env):
        if key.startswith("ARCHI_"):
            env.pop(key)
    env.update(overrides or {})
    print(f"Running {name}", flush=True)
    try:
        with log.open("w", encoding="utf-8") as handle:
            record["command_started"] = True
            process = run_bounded(command, cwd=cwd, env=env, stdout=handle,
                                  stderr=subprocess.STDOUT, timeout=timeout)
        record["exit_code"] = process.returncode
    except subprocess.TimeoutExpired:
        record.update(status="ERROR", reason="COMMAND_TIMEOUT", exit_code=None)
    except OSError as error:
        record.update(status="ERROR", reason="COMMAND_UNAVAILABLE", exit_code=None, error=str(error))
    record["elapsed_seconds"] = round(time.monotonic() - started, 3)
    if log.exists():
        record["log_sha256"] = sha256(log)
    return record


def skipped(name: str, reason: str, *, command: list[str] | None = None) -> dict:
    return {"name": name, "status": "SKIPPED", "reason": reason,
            "command_started": False, "command": command}


def existing_test(root: Path, relative: str) -> Path:
    if Path(relative).is_absolute():
        raise ValueError("--qimovi-test must be a path relative to the QiMovi repository")
    resolved = (root / relative).resolve()
    if not resolved.is_relative_to(root.resolve()) or not resolved.is_file():
        raise ValueError("QiMovi test must exist inside the selected repository")
    return resolved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New evidence directory; existing paths are refused")
    parser.add_argument("--archi-repo", type=Path, default=ROOT,
                        help="Candidate source checkout; defaults to this runner's repository")
    parser.add_argument("--qimovi-repo", type=Path)
    parser.add_argument("--qimovi-test", default="tests/movie-selection-binding.test.mjs")
    parser.add_argument("--live-receipt", action="store_true",
                        help="Explicitly run one existing local Qwen receipt test on macOS")
    parser.add_argument("--command-timeout", type=int, default=900)
    args = parser.parse_args()
    if args.command_timeout < 1 or args.command_timeout > 3600:
        parser.error("--command-timeout must be between 1 and 3600 seconds")
    archi_root = args.archi_repo.resolve()
    if not (archi_root / "desktop/Package.swift").is_file():
        parser.error("--archi-repo must contain desktop/Package.swift")
    output = (args.output or ROOT / "output" / "relationship-admission" /
              (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8])).resolve()
    try:
        output.mkdir(parents=True, exist_ok=False)
    except OSError as error:
        parser.error(f"Use a new writable evidence directory: {error}")
    source_paths = [archi_root / "desktop/Package.swift"]
    runner_path = Path(__file__).resolve()
    if runner_path.is_relative_to(archi_root):
        source_paths.append(runner_path)
    source_paths += list((archi_root / "desktop/Sources").rglob("*.swift"))
    source_paths += list((archi_root / "desktop/Tests").rglob("*.swift"))
    report = {"schema": "archi-relationship-admission-acceptance/v1", "started_at_utc": utc_now(),
              "scope": "Source-test execution evidence. No installed application launch or restart is performed.",
              "host": {"system": platform.system(), "release": platform.release(),
                       "macos": platform.mac_ver()[0], "python": platform.python_version()},
              "archi_source": source_record(archi_root, source_paths),
              "runner": {"path": str(runner_path), "sha256": sha256(runner_path)},
              "checks": []}
    checks = report["checks"]

    if args.qimovi_repo is None:
        checks.append(skipped("qimovi_attachment_source_tests", "NO_QIMOVI_REPOSITORY_SELECTED"))
    else:
        qimovi = args.qimovi_repo.resolve()
        try:
            test = existing_test(qimovi, args.qimovi_test)
            relevant = [qimovi / "package.json", test]
            for folder in ["local/server", "local/contracts", "local/kernel/src"]:
                relevant += list((qimovi / folder).rglob("*.mjs"))
            report["qimovi_source"] = source_record(qimovi, relevant)
            command = [shutil.which("node") or "node", "--test", "--test-reporter=tap", str(test)]
            result = run_command("qimovi_attachment_source_tests", command, qimovi, output, args.command_timeout)
            if "status" not in result:
                result.update(classify_node(Path(result["log"]).read_text(errors="replace"), result["exit_code"]))
            checks.append(result)
        except (OSError, ValueError) as error:
            checks.append({"name": "qimovi_attachment_source_tests", "status": "ERROR",
                           "reason": "INVALID_QIMOVI_TEST_SELECTION", "error": str(error), "command_started": False})

    swift = shutil.which("swift")
    native_commands = {
        suite: [swift or "swift", "test", "--package-path", str(archi_root / "desktop"),
                "--scratch-path", str(output / "swift-build"), "--filter", suite]
        for suite in SUITES
    }
    prerequisite = None
    if platform.system() != "Darwin":
        prerequisite = "MACOS_REQUIRED"
    elif not swift:
        prerequisite = "SWIFT_TOOLCHAIN_UNAVAILABLE"
    else:
        version = run_command("swift_version", [swift, "--version"], archi_root, output, 30)
        if "status" in version or version.get("exit_code") != 0:
            version.update(status="ERROR", reason="SWIFT_TOOLCHAIN_UNAVAILABLE")
            prerequisite = "SWIFT_TOOLCHAIN_UNAVAILABLE"
        else:
            version_text = Path(version["log"]).read_text(errors="replace")
            match = re.search(r"Swift version (\d+)", version_text)
            if not match or int(match.group(1)) < 6:
                version.update(status="SKIPPED", reason="SWIFT_6_REQUIRED")
                prerequisite = "SWIFT_6_REQUIRED"
            else:
                version.update(status="PASS", reason="SWIFT_VERSION_OBSERVED", version_output=version_text.strip())
        checks.append(version)
        try:
            if int(platform.mac_ver()[0].split(".")[0]) < 14:
                prerequisite = "MACOS_14_REQUIRED"
        except (ValueError, IndexError):
            prerequisite = "MACOS_VERSION_UNVERIFIED"
    if prerequisite:
        result = skipped("native_source_tests", prerequisite)
        result["planned_commands"] = native_commands
        checks.append(result)
    else:
        suite_results = []
        for suite, command in native_commands.items():
            result = run_command("native_" + suite, command, archi_root, output, args.command_timeout)
            if "status" not in result:
                result.update(classify_swift(Path(result["log"]).read_text(errors="replace"),
                                             result["exit_code"], expected_suite=suite))
            suite_results.append(result)
        statuses = {result["status"] for result in suite_results}
        status = next((value for value in ["ERROR", "FAIL", "SKIPPED"] if value in statuses), "PASS")
        checks.append({"name": "native_source_tests", "status": status,
                       "reason": "ALL_SELECTED_SUITES_PASSED" if status == "PASS" else "SELECTED_SUITES_NOT_ALL_PASS",
                       "command_started": any(result["command_started"] for result in suite_results),
                       "selected_suites": list(SUITES), "suite_results": suite_results,
                       "profile_scope": "Existing tests use in-memory state or explicit disposable/invalid profile paths. No installed profile selected."})

    live_command = [swift or "swift", "test", "--package-path", str(archi_root / "desktop"),
                    "--scratch-path", str(output / "swift-build"), "--filter", "AssistantReceiptLiveTests"]
    if not args.live_receipt:
        checks.append(skipped("native_live_receipt", "EXPLICIT_LIVE_RECEIPT_OPT_IN_NOT_REQUESTED", command=live_command))
    elif prerequisite:
        checks.append(skipped("native_live_receipt", prerequisite, command=live_command))
    elif next(c for c in checks if c["name"] == "native_source_tests")["status"] != "PASS":
        checks.append(skipped("native_live_receipt", "NATIVE_SOURCE_TESTS_NOT_PASS", command=live_command))
    else:
        live_output = output / "live-receipt"
        result = run_command("native_live_receipt", live_command, archi_root, output, args.command_timeout,
                             {"ARCHI_RECEIPT_LIVE": "1", "ARCHI_RECEIPT_LIVE_OUTPUT": str(live_output)})
        if "status" not in result:
            result.update(classify_swift(Path(result["log"]).read_text(errors="replace"), result["exit_code"],
                                         expected_suite="AssistantReceiptLiveTests"))
        receipt_path = live_output / "assistant-receipt-live.json"
        if result["status"] == "PASS":
            result.update(validate_live_receipt(receipt_path))
        result["scope"] = "Existing one-generation 2+2 receipt test through production store in disposable profile; not a binding benchmark."
        checks.append(result)

    checks.append(skipped("installed_app_interaction", "NOT_OBSERVED_RUNNER_DOES_NOT_LAUNCH_APP"))
    checks.append(skipped("installed_app_save_close_reopen", "NOT_OBSERVED_SOURCE_TESTS_DO_NOT_ESTABLISH_FULL_RESTART"))
    checks.append(skipped("native_qimovi_attachment_bridge", "NO_NATIVE_MEDIA_ATTACHMENT_CONSUMER_IN_TESTED_SOURCE"))
    counts = Counter(c["status"] for c in checks)
    report["status_counts"] = {name: counts[name] for name in STATUSES}
    report["completed_at_utc"] = utc_now()
    report["qualification"] = "INCOMPLETE: installed-app and complete-restart acceptance require separate observed evidence."
    report["exit_code"] = 1 if counts["FAIL"] or counts["ERROR"] else 2 if counts["SKIPPED"] else 0
    target = output / "acceptance.json"
    target.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"evidence": str(target), "status_counts": report["status_counts"],
                      "qualification": report["qualification"], "exit_code": report["exit_code"]}, indent=2))
    return report["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
