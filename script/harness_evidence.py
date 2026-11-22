#!/usr/bin/env python3
"""Check a bounded source-test evidence bundle without authorizing app effects.

Pins establish consistency with the coordinator's evaluation request. They do
not authenticate execution, isolate agents, or make source-controlled tests an
independent oracle. Build scratch is opaque; every consumed evidence path and
every enumerated source path is checked for symlink traversal.
"""
from __future__ import annotations

import ast
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess


SUITES = (
    "HamptonProposalValidationTests", "HamptonSessionContextTests",
    "WorkingCopyRevisionTests", "WorkingCopyStoreTests",
    "EvolutionRequestBindingTests",
)
STATUSES = ("PASS", "FAIL", "SKIPPED", "ERROR", "ABSTAIN", "ESCALATE")
EVALUATOR_FILES = (
    "script/accept_relationship_admission.py", "script/harness_evidence.py",
    "script/run_agent_harness.py", "script/harness_process.py",
)
SOURCE_SCHEMA = "archi-agent-harness-source/v1"
RESULT_SCHEMA = "archi-agent-harness-evaluation/v1"
QUALIFICATION = "INCOMPLETE: installed-app and complete-restart acceptance require separate observed evidence."
MAX_JSON_BYTES = 16 * 1024 * 1024
MAX_LOG_BYTES = 64 * 1024 * 1024
TRUST_LIMITATIONS = [
    "Hashes establish consistency with an externally retained request pin, not authenticated execution.",
    "Coordinator, evaluator code and acceptance tests must be trusted; coordinated evidence forgery is outside this check.",
    "The Git source manifest excludes ignored files and does not establish full dependency or built-application identity.",
    "Source-test evidence does not qualify installed-app interaction, restart, or native business-state admission.",
]


class EvidenceError(ValueError):
    """Missing, inconsistent, or unsupported evidence; never a passing result."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def canonical_bytes(value) -> bytes:
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"),
                          ensure_ascii=False, allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, UnicodeError) as error:
        raise EvidenceError("Cannot encode canonical JSON: " + str(error)) from error


def _read_regular(path: Path, limit: int | None = None) -> bytes:
    path = Path(path)
    try:
        before = path.lstat()
        _require(stat.S_ISREG(before.st_mode), f"Expected a regular nonsymlink file: {path}")
        if limit is not None:
            _require(before.st_size <= limit, f"Evidence file exceeds size limit: {path}")
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(descriptor, "rb") as handle:
            opened = os.fstat(handle.fileno())
            _require((before.st_dev, before.st_ino) == (opened.st_dev, opened.st_ino),
                     f"File changed while opening: {path}")
            raw = handle.read() if limit is None else handle.read(limit + 1)
            after = os.fstat(handle.fileno())
        _require((opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns) ==
                 (after.st_size, after.st_mtime_ns, after.st_ctime_ns),
                 f"File changed while reading: {path}")
        if limit is not None:
            _require(len(raw) <= limit, f"Evidence file exceeds size limit: {path}")
        return raw
    except OSError as error:
        raise EvidenceError(f"Cannot read {path}: {error}") from error


def file_sha256(path: Path) -> str:
    return hashlib.sha256(_read_regular(path)).hexdigest()


def _object_pairs(pairs: list[tuple]) -> dict:
    value = {}
    for key, item in pairs:
        _require(key not in value, f"Duplicate JSON key: {key}")
        value[key] = item
    return value


def _invalid_constant(value: str):
    raise EvidenceError("Nonfinite JSON number: " + value)


def _finite_float(value: str) -> float:
    parsed = float(value)
    _require(math.isfinite(parsed), "Nonfinite JSON number: " + value)
    return parsed


def _parse_object(raw: bytes, label: str) -> dict:
    try:
        value = json.loads(raw, object_pairs_hook=_object_pairs,
                           parse_constant=_invalid_constant, parse_float=_finite_float)
    except (ValueError, UnicodeError, RecursionError) as error:
        raise EvidenceError(f"Invalid JSON in {label}: {error}") from error
    _require(type(value) is dict, f"Expected JSON object: {label}")
    return value


def load_object(path: Path) -> dict:
    return _parse_object(_read_regular(Path(path), MAX_JSON_BYTES), str(path))


def _digest(value, label: str) -> str:
    _require(type(value) is str and re.fullmatch(r"[a-f0-9]{64}", value) is not None,
             f"Invalid SHA-256: {label}")
    return value


def _text(value, label: str, maximum: int = 8192) -> str:
    _require(type(value) is str and bool(value.strip()) and len(value) <= maximum
             and "\x00" not in value, f"Invalid text: {label}")
    return value


def _keys(value: dict, required: set[str], optional: set[str] | None = None,
          label: str = "object") -> None:
    _require(type(value) is dict, f"Expected object: {label}")
    _require(required <= set(value) <= required | (optional or set()),
             f"Missing or unexpected fields in {label}")


def _relative(value, label: str) -> str:
    _text(value, label, 4096)
    parsed = PurePosixPath(value)
    _require(not parsed.is_absolute() and parsed.as_posix() == value
             and "\\" not in value and all(part not in (".", "..") for part in parsed.parts),
             f"Unsafe relative path: {label}")
    return value


def _root(path: Path) -> Path:
    path = Path(path).absolute()
    try:
        _require(not path.is_symlink() and path.is_dir(), f"Expected nonsymlink directory: {path}")
        return path.resolve(strict=True)
    except OSError as error:
        raise EvidenceError(f"Cannot resolve directory {path}: {error}") from error


def _inside(root: Path, relative: str) -> Path:
    relative = _relative(relative, "file path")
    current = root
    try:
        for index, part in enumerate(PurePosixPath(relative).parts):
            current = current / part
            mode = current.lstat().st_mode
            _require(not stat.S_ISLNK(mode), f"Symlink is not permitted: {current}")
            if index < len(PurePosixPath(relative).parts) - 1:
                _require(stat.S_ISDIR(mode), f"Expected directory: {current}")
        _require(stat.S_ISREG(current.lstat().st_mode), f"Expected regular file: {current}")
        return current
    except OSError as error:
        raise EvidenceError(f"Missing or unreadable file {current}: {error}") from error


def _git(root: Path, *arguments: str) -> bytes:
    try:
        result = subprocess.run(["git", "-C", str(root), *arguments], capture_output=True,
                                timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise EvidenceError("Git source identity unavailable: " + str(error)) from error
    _require(result.returncode == 0, "Git source identity unavailable: " +
             result.stderr.decode("utf-8", errors="replace").strip())
    return result.stdout


def snapshot_source(root: Path) -> dict:
    """Hash tracked and untracked nonignored regular files, including modes.

    This is a working-tree snapshot, not a dependency closure or execution
    attestation. Missing tracked paths and unresolved Git index stages fail.
    """
    root = _root(root)
    try:
        top = Path(_git(root, "rev-parse", "--show-toplevel").decode("utf-8").strip()).resolve()
        _require(top == root, "Candidate must be the root of its Git worktree")
        commit = _git(root, "rev-parse", "HEAD").decode("ascii").strip()
        _require(re.fullmatch(r"(?:[a-f0-9]{40}|[a-f0-9]{64})", commit) is not None,
                 "Candidate has no real Git HEAD")
        paths = set()
        for entry in _git(root, "ls-files", "--cached", "--stage", "-z").split(b"\0"):
            if not entry:
                continue
            metadata, raw_path = entry.split(b"\t", 1)
            mode, _object_id, stage = metadata.decode("ascii").split()
            _require(stage == "0", "Unmerged Git index entry")
            _require(mode in ("100644", "100755"), "Tracked symlinks, submodules and special entries are unsupported")
            paths.add(_relative(raw_path.decode("utf-8"), "Git tracked path"))
        for raw_path in _git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0"):
            if raw_path:
                paths.add(_relative(raw_path.decode("utf-8"), "Git untracked path"))
        _require(bool(paths), "Candidate source manifest is empty")
        files = []
        for relative in sorted(paths):
            path = _inside(root, relative)
            mode = "100755" if path.stat().st_mode & 0o111 else "100644"
            files.append({"path": relative, "sha256": file_sha256(path), "mode": mode})
        return {"schema": SOURCE_SCHEMA, "root": str(root), "commit": commit,
                "files": files, "manifest_sha256": hashlib.sha256(canonical_bytes(files)).hexdigest()}
    except (UnicodeError, ValueError) as error:
        if isinstance(error, EvidenceError):
            raise
        raise EvidenceError("Unsupported Git source entry: " + str(error)) from error


def validate_contract(contract: dict) -> None:
    _keys(contract, {"schema", "id", "objective", "scope", "required_suites",
                     "installed_app_qualification", "authorizes_commit"}, {"requirements"}, "contract")
    _require(contract["schema"] == "archi-agent-harness-contract/v1"
             and contract["id"] == "ARCHI-HARNESS-001"
             and contract["scope"] == "native-source-tests", "Unsupported contract identity or scope")
    _text(contract["objective"], "contract objective")
    _require(contract["required_suites"] == list(SUITES), "Contract must require all five exact native suites")
    _require(contract["installed_app_qualification"] is False and contract["authorizes_commit"] is False,
             "Contract cannot authorize COMMIT or installed-app qualification")
    if "requirements" in contract:
        rows = contract["requirements"]
        _require(type(rows) is list and 0 < len(rows) <= 128, "Requirements must be a nonempty bounded list")
        seen = set()
        for row in rows:
            _keys(row, {"id", "description", "suites"}, label="contract requirement")
            identifier = _text(row["id"], "requirement ID", 128)
            _require(identifier not in seen, "Duplicate requirement ID")
            seen.add(identifier)
            _text(row["description"], "requirement description")
            suites = row["suites"]
            _require(type(suites) is list and bool(suites)
                     and all(type(suite) is str and suite in SUITES for suite in suites)
                     and len(suites) == len(set(suites)), "Invalid requirement suite selection")


def _snapshot(value: dict, candidate: Path, label: str) -> None:
    _keys(value, {"schema", "root", "commit", "files", "manifest_sha256"}, label=label)
    _require(value["schema"] == SOURCE_SCHEMA and value["root"] == str(candidate),
             f"Wrong source scope: {label}")
    _require(type(value["commit"]) is str and re.fullmatch(r"(?:[a-f0-9]{40}|[a-f0-9]{64})", value["commit"]),
             f"Invalid source commit: {label}")
    rows = value["files"]
    _require(type(rows) is list and bool(rows), f"Empty or malformed source manifest: {label}")
    paths = []
    for row in rows:
        _keys(row, {"path", "sha256", "mode"}, label="source manifest entry")
        paths.append(_relative(row["path"], "source manifest path"))
        _digest(row["sha256"], "source file")
        _require(row["mode"] in ("100644", "100755"), "Unsupported source mode")
    _require(paths == sorted(set(paths)), f"Unsorted or duplicate source paths: {label}")
    _require(_digest(value["manifest_sha256"], label) == hashlib.sha256(canonical_bytes(rows)).hexdigest(),
             f"Source manifest digest mismatch: {label}")


def _pinned_object(root: Path, relative: str, expected: str) -> dict:
    raw = _read_regular(_inside(root, relative), MAX_JSON_BYTES)
    _require(hashlib.sha256(raw).hexdigest() == _digest(expected, relative), f"Pinned file changed: {relative}")
    return _parse_object(raw, relative)


def _host(value: dict) -> None:
    _keys(value, {"system", "release", "macos", "python"}, label="host")
    for key, item in value.items():
        _require(type(item) is str and len(item) <= 1024 and "\x00" not in item, "Malformed host metadata")
        if key != "macos":
            _require(bool(item.strip()), "Missing host metadata")


def _request(value: dict, candidate: Path) -> None:
    _keys(value, {"schema", "request_id", "created_at_utc", "contract_sha256",
                  "source_before_sha256", "source_manifest_sha256", "candidate_root",
                  "candidate_commit", "evaluator_files", "host", "raw_report_path",
                  "runner_command"}, label="request")
    _require(value["schema"] == "archi-agent-harness-request/v1", "Unsupported request schema")
    _require(type(value["request_id"]) is str and re.fullmatch(r"[a-f0-9]{32}", value["request_id"]),
             "Request ID must be UUID hex")
    _text(value["created_at_utc"], "request time", 128)
    try:
        moment = datetime.fromisoformat(value["created_at_utc"].replace("Z", "+00:00"))
        _require(moment.tzinfo is not None and moment.utcoffset() == timezone.utc.utcoffset(moment),
                 "Request time must identify UTC")
    except ValueError as error:
        raise EvidenceError("Invalid request timestamp") from error
    for key in ("contract_sha256", "source_before_sha256", "source_manifest_sha256"):
        _digest(value[key], key)
    _require(value["candidate_root"] == str(candidate), "Candidate root differs from request")
    _require(value["raw_report_path"] == "raw/acceptance.json", "Unexpected raw report path")
    _keys(value["evaluator_files"], set(EVALUATOR_FILES), label="evaluator pins")
    for relative, digest in value["evaluator_files"].items():
        _digest(digest, relative)
    _host(value["host"])


def _runner_command(value, evaluator: Path, candidate: Path, evidence: Path) -> list[str]:
    _require(type(value) is list and len(value) == 8, "Unexpected coordinator command shape")
    python = _text(value[0], "Python executable", 4096)
    _require(Path(python).is_absolute() and str(Path(python)) == python,
             "Coordinator Python executable must be an absolute path")
    timeout = value[7]
    _require(type(timeout) is str and re.fullmatch(r"[1-9][0-9]{0,3}", timeout)
             and 1 <= int(timeout) <= 3600, "Unsupported coordinator command timeout")
    expected = [python, str(evaluator / EVALUATOR_FILES[0]), "--archi-repo", str(candidate),
                "--output", str(evidence / "raw"), "--command-timeout", timeout]
    _require(value == expected, "Coordinator command differs from the fixed acceptance recipe")
    return value


def _utc_time(value, label: str) -> datetime:
    _text(value, label, 128)
    try:
        moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
        _require(moment.tzinfo is not None and moment.utcoffset() == timezone.utc.utcoffset(moment),
                 f"{label} must identify UTC")
        return moment
    except ValueError as error:
        raise EvidenceError("Invalid UTC timestamp: " + label) from error


def _execution(evidence: Path, request: dict, expected_request_sha256: str, raw_exit: int) -> None:
    receipt = load_object(_inside(evidence, "execution.json"))
    _keys(receipt, {"schema", "request_sha256", "command", "exit_code", "timed_out",
                    "error", "elapsed_seconds", "console_sha256", "started_at_utc",
                    "completed_at_utc"}, label="coordinator execution receipt")
    _require(receipt["schema"] == "archi-agent-harness-execution/v1",
             "Unsupported execution receipt schema")
    _require(receipt["request_sha256"] == expected_request_sha256
             and receipt["command"] == request["runner_command"],
             "Execution receipt does not bind the requested invocation")
    _require(type(receipt["timed_out"]) is bool, "Execution timeout flag must be boolean")
    _require(receipt["exit_code"] is None or type(receipt["exit_code"]) is int,
             "Observed execution exit code must be an integer or null")
    _require(receipt["error"] is None or type(receipt["error"]) is str,
             "Execution error must be text or null")
    elapsed = receipt["elapsed_seconds"]
    _require((type(elapsed) is int or (type(elapsed) is float and math.isfinite(elapsed))) and elapsed >= 0,
             "Execution duration must be finite and nonnegative")
    started = _utc_time(receipt["started_at_utc"], "execution start")
    completed = _utc_time(receipt["completed_at_utc"], "execution completion")
    _require(completed >= started, "Execution completion precedes its start")
    console = _read_regular(_inside(evidence, "runner-console.log"), MAX_LOG_BYTES)
    _require(hashlib.sha256(console).hexdigest() == _digest(receipt["console_sha256"], "coordinator console"),
             "Coordinator console digest mismatch")
    _require(receipt["timed_out"] is False and receipt["error"] is None,
             "Coordinator recorded a timeout or execution error")
    _require(type(receipt["exit_code"]) is int and receipt["exit_code"] == raw_exit,
             "Observed runner exit code disagrees with raw report")


def _classifier(runner_raw: bytes, runner_path: Path):
    """Load just the pinned pure classifier, without executing process imports."""
    module = ast.parse(runner_raw, filename=str(runner_path))
    functions = [node for node in module.body
                 if isinstance(node, ast.FunctionDef) and node.name == "classify_swift"]
    suites = [node.value for node in module.body if isinstance(node, ast.Assign)
              and any(isinstance(target, ast.Name) and target.id == "SUITES" for target in node.targets)]
    _require(len(functions) == 1 and len(suites) == 1, "Trusted runner classifier or suite definition is ambiguous")
    _require(ast.literal_eval(suites[0]) == SUITES, "Trusted runner suite set differs from contract")
    namespace = {"re": re}
    exec(compile(ast.Module(body=functions, type_ignores=[]), str(runner_path), "exec"), namespace)
    return namespace["classify_swift"]


def _command(swift: str, candidate: Path, evidence: Path, suite: str) -> list[str]:
    return [swift, "test", "--package-path", str(candidate / "desktop"),
            "--scratch-path", str(evidence / "raw/swift-build"), "--filter", suite]


def _swift_executable(value) -> str:
    _text(value, "Swift executable", 4096)
    _require(value == "swift" or (Path(value).is_absolute() and str(Path(value)) == value),
             "Swift executable must be an absolute path or the missing-tool placeholder")
    return value


def _log(record: dict, evidence: Path, name: str) -> str:
    relative = f"raw/{name}.log"
    expected = evidence / relative
    _require(record.get("log") == str(expected), f"Unexpected log path: {name}")
    raw = _read_regular(_inside(evidence, relative), MAX_LOG_BYTES)
    _require(hashlib.sha256(raw).hexdigest() == _digest(record.get("log_sha256"), name),
             f"Log digest mismatch: {name}")
    return raw.decode("utf-8", errors="replace")


def _executed(record: dict, command: list[str], candidate: Path) -> None:
    _require(record.get("command") == command and record.get("cwd") == str(candidate)
             and record.get("environment_overrides") == {}, "Test command, cwd or environment differs from recipe")
    _require(record.get("command_started") is True, "Reported test command did not start")


def _infrastructure(record: dict) -> bool:
    if record.get("exit_code") is None:
        _require(record.get("status") == "ERROR"
                 and record.get("reason") in ("COMMAND_TIMEOUT", "COMMAND_UNAVAILABLE", "SWIFT_TOOLCHAIN_UNAVAILABLE"),
                 "Missing exit code cannot qualify a test")
        return True
    _require(type(record["exit_code"]) is int, "Test exit code must be an integer")
    return False


def _version(record: dict, evidence: Path, candidate: Path) -> tuple[str, str, str | None]:
    command = record.get("command")
    _require(type(command) is list and len(command) == 2 and command[1] == "--version",
             "Unexpected Swift version command")
    swift = _swift_executable(command[0])
    _executed(record, [swift, "--version"], candidate)
    text = _log(record, evidence, "swift_version")
    if _infrastructure(record) or record["exit_code"] != 0:
        status, reason, prerequisite = "ERROR", "SWIFT_TOOLCHAIN_UNAVAILABLE", "SWIFT_TOOLCHAIN_UNAVAILABLE"
    else:
        match = re.search(r"Swift version (\d+)", text)
        if not match or int(match.group(1)) < 6:
            status, reason, prerequisite = "SKIPPED", "SWIFT_6_REQUIRED", "SWIFT_6_REQUIRED"
        else:
            status, reason, prerequisite = "PASS", "SWIFT_VERSION_OBSERVED", None
            _require(record.get("version_output") == text.strip(), "Swift version output differs from log")
    _require(record.get("status") == status and record.get("reason") == reason,
             "Swift version status differs from observed log/exit")
    return swift, status, prerequisite


def _skip(record: dict, reason: str) -> None:
    _require(record.get("status") == "SKIPPED" and record.get("reason") == reason
             and record.get("command_started") is False, "Unexpected skipped-check evidence")
    _require("suite_results" not in record and "log" not in record and "log_sha256" not in record,
             "Skipped check cannot carry execution evidence")


def _raw_source(value: dict, before: dict, candidate: Path) -> None:
    _keys(value, {"root", "commit", "working_tree_status", "files", "manifest_sha256"}, label="raw source")
    _require(value["root"] == str(candidate) and value["commit"] == before["commit"], "Raw source identity differs")
    _require(type(value["working_tree_status"]) is str, "Raw Git status was not observed")
    _require(type(value["files"]) is list and bool(value["files"]), "Raw source manifest is empty")
    full = {row["path"]: row["sha256"] for row in before["files"]}
    paths = []
    for row in value["files"]:
        _keys(row, {"path", "sha256"}, label="raw source entry")
        relative = _relative(row["path"], "raw source path")
        paths.append(relative)
        _require(_digest(row["sha256"], relative) == full.get(relative), "Raw source differs from candidate snapshot")
    _require(paths == sorted(set(paths)), "Raw source paths must be unique and sorted")
    # The existing v1 runner uses json.dumps' default ASCII escaping. Keep its
    # hash format exact, including repositories containing Unicode filenames.
    legacy_manifest = json.dumps(value["files"], sort_keys=True, separators=(",", ":")).encode()
    _require(value["manifest_sha256"] == hashlib.sha256(legacy_manifest).hexdigest(),
             "Raw source manifest digest mismatch")


def _verify(evidence: Path, candidate: Path, expected_request_sha256: str) -> tuple[str, str]:
    request = _pinned_object(evidence, "request.json", expected_request_sha256)
    _request(request, candidate)
    contract = _pinned_object(evidence, "contract.json", request["contract_sha256"])
    validate_contract(contract)
    before = _pinned_object(evidence, "source-before.json", request["source_before_sha256"])
    after = load_object(_inside(evidence, "source-after.json"))
    _snapshot(before, candidate, "source before")
    _snapshot(after, candidate, "source after")
    _require(before == after, "Candidate source changed during evaluation")
    _require(before["manifest_sha256"] == request["source_manifest_sha256"]
             and before["commit"] == request["candidate_commit"], "Request does not bind the source snapshot")
    _require(snapshot_source(candidate) == before, "Current candidate differs from evaluated source")
    evaluator_root = Path(__file__).resolve().parents[1]
    _runner_command(request["runner_command"], evaluator_root, candidate, evidence)
    for relative, digest in request["evaluator_files"].items():
        _require(file_sha256(_inside(evaluator_root, relative)) == digest, f"Evaluator changed: {relative}")
    runner_path = _inside(evaluator_root, EVALUATOR_FILES[0])
    runner_raw = _read_regular(runner_path, MAX_JSON_BYTES)
    _require(hashlib.sha256(runner_raw).hexdigest() == request["evaluator_files"][EVALUATOR_FILES[0]],
             "Evaluator changed while loading classifier")
    classify = _classifier(runner_raw, runner_path)
    raw = load_object(_inside(evidence, "raw/acceptance.json"))
    _require(raw.get("schema") == "archi-relationship-admission-acceptance/v1", "Unsupported raw report schema")
    _require(raw.get("host") == request["host"], "Raw host differs from evaluation request")
    _require(raw.get("runner") == {"path": str(runner_path), "sha256": request["evaluator_files"][EVALUATOR_FILES[0]]},
             "Raw report is not bound to the pinned evaluator")
    _raw_source(raw.get("archi_source"), before, candidate)
    _require("qimovi_source" not in raw, "QiMovi execution is outside this contract")
    rows = raw.get("checks")
    _require(type(rows) is list and bool(rows), "Missing raw checks")
    checks = {}
    for row in rows:
        _require(type(row) is dict and type(row.get("name")) is str, "Malformed raw check")
        name = row["name"]
        _require(name not in checks and row.get("status") in STATUSES, "Duplicate check or unknown status")
        checks[name] = row
    required = {"qimovi_attachment_source_tests", "native_source_tests", "native_live_receipt",
                "installed_app_interaction", "installed_app_save_close_reopen", "native_qimovi_attachment_bridge"}
    allowed = required | ({"swift_version"} if request["host"]["system"] == "Darwin" else set())
    _require(required <= set(checks) <= allowed, "Missing or unexpected raw checks")
    reasons = {
        "qimovi_attachment_source_tests": "NO_QIMOVI_REPOSITORY_SELECTED",
        "native_live_receipt": "EXPLICIT_LIVE_RECEIPT_OPT_IN_NOT_REQUESTED",
        "installed_app_interaction": "NOT_OBSERVED_RUNNER_DOES_NOT_LAUNCH_APP",
        "installed_app_save_close_reopen": "NOT_OBSERVED_SOURCE_TESTS_DO_NOT_ESTABLISH_FULL_RESTART",
        "native_qimovi_attachment_bridge": "NO_NATIVE_MEDIA_ATTACHMENT_CONSUMER_IN_TESTED_SOURCE",
    }
    for name, reason in reasons.items():
        _skip(checks[name], reason)
        if name != "native_live_receipt":
            _require(checks[name].get("command") is None, "Out-of-scope check contains a command")
    statuses = {name: "SKIPPED" for name in reasons}
    native = checks["native_source_tests"]
    version_prerequisite = None
    swift = None
    if "swift_version" in checks:
        swift, version_status, version_prerequisite = _version(checks["swift_version"], evidence, candidate)
        statuses["swift_version"] = version_status
    prerequisite = None
    if request["host"]["system"] != "Darwin":
        prerequisite = "MACOS_REQUIRED"
    elif swift is None:
        prerequisite = "SWIFT_TOOLCHAIN_UNAVAILABLE"
    else:
        prerequisite = version_prerequisite
        try:
            if int(request["host"]["macos"].split(".")[0]) < 14:
                prerequisite = "MACOS_14_REQUIRED"
        except (ValueError, IndexError):
            prerequisite = "MACOS_VERSION_UNVERIFIED"
    if prerequisite:
        _skip(native, prerequisite)
        _require(native.get("command") is None, "Skipped native group cannot contain a command")
        plans = native.get("planned_commands")
        _keys(plans, set(SUITES), label="planned native commands")
        first = plans[SUITES[0]]
        _require(type(first) is list and len(first) == 8, "Malformed planned native command")
        planned_swift = _swift_executable(first[0])
        _require(swift is None or swift == planned_swift, "Native commands use a different Swift executable")
        swift = planned_swift
        for suite in SUITES:
            _require(plans[suite] == _command(swift, candidate, evidence, suite), "Planned native command differs from recipe")
        source_status = "ERROR" if statuses.get("swift_version") == "ERROR" else "SKIPPED"
        statuses["native_source_tests"] = "SKIPPED"
    else:
        _require(native.get("selected_suites") == list(SUITES) and native.get("command_started") is True,
                 "Native suite selection differs from contract")
        results = native.get("suite_results")
        _require(type(results) is list and len(results) == len(SUITES), "Missing or extra native suite results")
        seen, derived_statuses = set(), []
        for row in results:
            _require(type(row) is dict, "Malformed native suite result")
            name = row.get("name")
            _require(type(name) is str and name.startswith("native_"), "Invalid native suite name")
            suite = name[len("native_"):]
            _require(suite in SUITES and suite not in seen, "Unknown or duplicate native suite")
            seen.add(suite)
            _executed(row, _command(swift, candidate, evidence, suite), candidate)
            log = _log(row, evidence, name)
            if _infrastructure(row):
                derived_statuses.append("ERROR")
            else:
                derived = classify(log, row["exit_code"], expected_suite=suite)
                for key, value in derived.items():
                    _require(key in row and canonical_bytes(row[key]) == canonical_bytes(value),
                             f"Native {suite} disagrees with raw log: {key}")
                derived_statuses.append(derived["status"])
        source_status = next((status for status in ("ERROR", "FAIL", "SKIPPED")
                              if status in derived_statuses), "PASS")
        _require(native.get("status") == source_status and native.get("reason") ==
                 ("ALL_SELECTED_SUITES_PASSED" if source_status == "PASS" else "SELECTED_SUITES_NOT_ALL_PASS"),
                 "Native aggregate disagrees with suite evidence")
        statuses["native_source_tests"] = source_status
    _require(checks["native_live_receipt"].get("command") == _command(swift, candidate, evidence, "AssistantReceiptLiveTests"),
             "Live receipt plan differs from the disabled recipe")
    counts = Counter(statuses.values())
    expected_counts = {status: counts[status] for status in STATUSES}
    _require(raw.get("status_counts") == expected_counts
             and all(type(value) is int for value in raw["status_counts"].values()),
             "Raw status counts disagree with independently derived results")
    expected_exit = 1 if counts["FAIL"] or counts["ERROR"] else 2
    _require(type(raw.get("exit_code")) is int and raw["exit_code"] == expected_exit,
             "Raw exit code disagrees with independently derived results")
    _execution(evidence, request, expected_request_sha256, expected_exit)
    _require(raw.get("qualification") == QUALIFICATION, "Source report cannot qualify an installed application")
    return request["request_id"], source_status


def verify_bundle(evidence_root: Path, candidate_root: Path, expected_request_sha256: str) -> dict:
    """Read and verify evidence; perform no app action or source mutation."""
    result = {"schema": RESULT_SCHEMA, "request_id": None, "integrity": "ERROR",
              "source_status": "ERROR", "decision": "BLOCKED", "findings": [],
              "authorizes_commit": False, "installed_app_qualified": False,
              "trust_limitations": list(TRUST_LIMITATIONS)}
    try:
        evidence, candidate = _root(evidence_root), _root(candidate_root)
        request_id, source_status = _verify(evidence, candidate, expected_request_sha256)
        result.update(request_id=request_id, integrity="PASS", source_status=source_status,
                      decision="SOURCE_CHECKS_PASS" if source_status == "PASS" else
                      "INCOMPLETE" if source_status == "SKIPPED" else "BLOCKED")
        result["findings"] = [
            {"status": "PASS", "reason": "Pinned contract, source identity and required evidence are consistent."},
            {"status": source_status, "reason": "Required native source-test outcome: " + source_status},
            {"status": "SKIPPED", "reason": "Installed application and complete restart remain unqualified."},
        ]
    except (EvidenceError, OSError, ValueError, TypeError, KeyError, RecursionError, SyntaxError) as error:
        result["findings"] = [{"status": "ERROR", "reason": str(error)}]
    return result
