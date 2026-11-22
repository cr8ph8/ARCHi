"""Adversarial checks for the source-test evidence admission boundary.

Every Darwin-looking log in this file is an explicitly synthetic parser fixture.
No fixture executes Swift, establishes native acceptance, or qualifies an app.
The subprocess cases use the real host and therefore remain incomplete on Linux.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "script/run_agent_harness.py"
MODULE_PATH = ROOT / "script/harness_evidence.py"
SPEC = importlib.util.spec_from_file_location("harness_evidence_under_test", MODULE_PATH)
HARNESS = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = HARNESS
SPEC.loader.exec_module(HARNESS)

# Written independently of the implementation's constants: these are the
# existing native suites to which this first contract is deliberately limited.
SUITES = (
    "HamptonProposalValidationTests",
    "HamptonSessionContextTests",
    "WorkingCopyRevisionTests",
    "WorkingCopyStoreTests",
    "EvolutionRequestBindingTests",
)
EVALUATOR_FILES = (
    "script/accept_relationship_admission.py",
    "script/harness_evidence.py",
    "script/run_agent_harness.py",
    "script/harness_process.py",
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def save_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def git(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *arguments], capture_output=True, text=True,
        check=True, timeout=20,
    )
    return result.stdout.strip()


def make_candidate(path: Path) -> Path:
    """Create disposable source provenance, never a simulated installed app."""
    path.mkdir()
    (path / "desktop/Sources").mkdir(parents=True)
    (path / "desktop/Tests/ARCHiDesktopTests").mkdir(parents=True)
    (path / "script").mkdir()
    (path / ".gitignore").write_text("__pycache__/\n*.pyc\n.build/\n")
    (path / "desktop/Package.swift").write_text(
        "// swift-tools-version: 6.0\n"
        "// Synthetic source-hashing fixture; never compiled by these tests.\n"
        "import PackageDescription\n"
        'let package = Package(name: "SyntheticHarnessFixture")\n'
    )
    (path / "desktop/Sources/Synthetic.swift").write_text(
        "// Explicitly synthetic source fixture, not native test evidence.\n"
        "let syntheticFixtureVersion = 1\n"
    )
    for suite in SUITES:
        (path / f"desktop/Tests/ARCHiDesktopTests/{suite}.swift").write_text(
            f"// Synthetic source fixture for {suite}; no native execution.\n"
        )
    for relative in EVALUATOR_FILES:
        shutil.copyfile(ROOT / relative, path / relative)
    git(path, "init", "--quiet")
    git(path, "add", ".")
    git(path, "-c", "user.name=ARCHi Synthetic Fixture", "-c",
        "user.email=archi-harness-fixture@example.invalid", "commit", "--quiet",
        "-m", "Synthetic source provenance fixture")
    return path


def contract() -> dict:
    return {
        "schema": "archi-agent-harness-contract/v1",
        "id": "ARCHI-HARNESS-001",
        "objective": "Exercise only synthetic evidence verification in this unit test.",
        "scope": "native-source-tests",
        "required_suites": list(SUITES),
        "installed_app_qualification": False,
        "authorizes_commit": False,
        "requirements": [{
            "id": "SYNTHETIC-PARSER-FIXTURE",
            "description": "Synthetic records are used only to test the verifier.",
            "suites": list(SUITES),
        }],
    }


class SyntheticBundle:
    """Assemble explicit synthetic records without calling the acceptance runner."""

    def __init__(self, root: Path):
        self.candidate = make_candidate(root / "candidate")
        self.evidence = root / "synthetic-evidence"
        self.raw = self.evidence / "raw"
        self.raw.mkdir(parents=True)
        self.host = {
            "system": "Darwin", "release": "24.0.0",
            "macos": "15.0", "python": platform.python_version(),
        }
        save_json(self.evidence / "contract.json", contract())
        self.snapshot = HARNESS.snapshot_source(self.candidate)
        save_json(self.evidence / "source-before.json", self.snapshot)
        save_json(self.evidence / "source-after.json", self.snapshot)
        self.request = {
            "schema": "archi-agent-harness-request/v1",
            "request_id": "a" * 32,
            "created_at_utc": "2026-11-22T00:00:00+00:00",
            "contract_sha256": digest(self.evidence / "contract.json"),
            "source_before_sha256": digest(self.evidence / "source-before.json"),
            "source_manifest_sha256": self.snapshot["manifest_sha256"],
            "candidate_root": str(self.candidate.resolve()),
            "candidate_commit": git(self.candidate, "rev-parse", "HEAD"),
            "evaluator_files": {
                relative: digest(ROOT / relative) for relative in EVALUATOR_FILES
            },
            "host": self.host,
            "raw_report_path": "raw/acceptance.json",
            "runner_command": [sys.executable, str((ROOT / EVALUATOR_FILES[0]).resolve()),
                               "--archi-repo", str(self.candidate), "--output",
                               str(self.raw), "--command-timeout", "900"],
        }
        self.write_request()
        version_log = self.raw / "swift_version.log"
        version_log.write_text("Apple Swift version 6.0 (synthetic fixture)\n")
        version = {
            "name": "swift_version", "command": ["/synthetic/swift", "--version"],
            "cwd": str(self.candidate), "environment_overrides": {},
            "command_started": True, "exit_code": 0,
            "log": str(version_log), "log_sha256": digest(version_log),
            "status": "PASS", "reason": "SWIFT_VERSION_OBSERVED",
            "version_output": version_log.read_text().strip(),
        }
        results = []
        for suite in SUITES:
            log = self.raw / f"native_{suite}.log"
            log.write_text(
                f"Test Suite '{suite}' passed at synthetic-fixture-time\n"
                "Executed 2 tests, with 0 failures (0 unexpected) in 0.1 seconds\n"
            )
            results.append({
                "name": "native_" + suite,
                "command": ["/synthetic/swift", "test", "--package-path",
                            str(self.candidate / "desktop"), "--scratch-path",
                            str(self.raw / "swift-build"), "--filter", suite],
                "cwd": str(self.candidate), "environment_overrides": {},
                "command_started": True, "exit_code": 0,
                "log": str(log), "log_sha256": digest(log),
                "status": "PASS", "reason": "EXECUTED_TESTS_PASSED",
                "xctest": {"executed": 2, "skipped": 0, "failures": 0},
                "swift_testing": None, "skip_lines": [],
                "expected_suite": suite, "completed_suites": [suite],
            })
        files = [
            {"path": row["path"], "sha256": row["sha256"]}
            for row in self.snapshot["files"]
            if row["path"].startswith("desktop/")
            or row["path"] == "script/accept_relationship_admission.py"
        ]
        self.report = {
            "schema": "archi-relationship-admission-acceptance/v1",
            "scope": "Synthetic parser fixture; no installed or native execution.",
            "runner": {"path": str((ROOT / EVALUATOR_FILES[0]).resolve()),
                       "sha256": digest(ROOT / EVALUATOR_FILES[0])},
            "started_at_utc": "2026-11-22T00:00:00+00:00",
            "completed_at_utc": "2026-11-22T00:00:01+00:00",
            "host": self.host,
            "archi_source": {
                "root": str(self.candidate),
                "commit": self.request["candidate_commit"],
                "working_tree_status": "", "files": files,
                "manifest_sha256": hashlib.sha256(canonical(files)).hexdigest(),
            },
            "checks": [
                {"name": "qimovi_attachment_source_tests", "status": "SKIPPED",
                 "reason": "NO_QIMOVI_REPOSITORY_SELECTED", "command_started": False,
                 "command": None},
                version,
                {"name": "native_source_tests", "status": "PASS",
                 "reason": "ALL_SELECTED_SUITES_PASSED", "command_started": True,
                 "selected_suites": list(SUITES), "suite_results": results,
                 "profile_scope": "Synthetic evidence parser fixture only."},
                {"name": "native_live_receipt", "status": "SKIPPED",
                 "reason": "EXPLICIT_LIVE_RECEIPT_OPT_IN_NOT_REQUESTED",
                 "command_started": False,
                 "command": ["/synthetic/swift", "test", "--package-path",
                             str(self.candidate / "desktop"), "--scratch-path",
                             str(self.raw / "swift-build"), "--filter",
                             "AssistantReceiptLiveTests"]},
                {"name": "installed_app_interaction", "status": "SKIPPED",
                 "reason": "NOT_OBSERVED_RUNNER_DOES_NOT_LAUNCH_APP",
                 "command_started": False},
                {"name": "installed_app_save_close_reopen", "status": "SKIPPED",
                 "reason": "NOT_OBSERVED_SOURCE_TESTS_DO_NOT_ESTABLISH_FULL_RESTART",
                 "command_started": False},
                {"name": "native_qimovi_attachment_bridge", "status": "SKIPPED",
                 "reason": "NO_NATIVE_MEDIA_ATTACHMENT_CONSUMER_IN_TESTED_SOURCE",
                 "command_started": False},
            ],
            "status_counts": {"PASS": 2, "FAIL": 0, "SKIPPED": 5, "ERROR": 0,
                              "ABSTAIN": 0, "ESCALATE": 0},
            "qualification": "INCOMPLETE: installed-app and complete-restart acceptance require separate observed evidence.",
            "exit_code": 2,
        }
        self.save_report()
        console = self.evidence / "runner-console.log"
        console.write_text("Explicit synthetic execution-receipt parser fixture; nothing ran.\n")
        self.execution = {
            "schema": "archi-agent-harness-execution/v1",
            "request_sha256": self.request_digest,
            "command": list(self.request["runner_command"]),
            "exit_code": 2,
            "timed_out": False,
            "error": None,
            "elapsed_seconds": 0.1,
            "console_sha256": digest(console),
            "started_at_utc": "2026-11-22T00:00:00+00:00",
            "completed_at_utc": "2026-11-22T00:00:01+00:00",
        }
        self.save_execution()

    def write_request(self) -> None:
        save_json(self.evidence / "request.json", self.request)
        self.request_digest = digest(self.evidence / "request.json")
        if hasattr(self, "execution"):
            self.execution["request_sha256"] = self.request_digest
            self.execution["command"] = list(self.request["runner_command"])
            self.save_execution()

    def save_report(self) -> None:
        save_json(self.raw / "acceptance.json", self.report)

    def save_execution(self) -> None:
        save_json(self.evidence / "execution.json", self.execution)

    @property
    def native(self) -> dict:
        return next(row for row in self.report["checks"] if row["name"] == "native_source_tests")

    def replace_log(self, text: str, index: int = 0) -> None:
        row = self.native["suite_results"][index]
        path = Path(row["log"])
        path.write_text(text)
        row["log_sha256"] = digest(path)
        self.save_report()

    def verify(self) -> dict:
        return HARNESS.verify_bundle(self.evidence, self.candidate, self.request_digest)


class AgentHarnessEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="archi-synthetic-evidence-")
        self.addCleanup(self.temporary.cleanup)
        self.bundle = SyntheticBundle(Path(self.temporary.name))

    def assert_blocked(self, result: dict) -> None:
        self.assertEqual(result["decision"], "BLOCKED", result)
        self.assertEqual(result["integrity"], "ERROR", result)
        self.assertFalse(result["authorizes_commit"])
        self.assertFalse(result["installed_app_qualified"])
        self.assertTrue(result["findings"])

    def test_consistent_synthetic_native_records_only_pass_the_source_gate(self):
        result = self.bundle.verify()
        self.assertEqual(result["integrity"], "PASS", result)
        self.assertEqual(result["source_status"], "PASS", result)
        self.assertEqual(result["decision"], "SOURCE_CHECKS_PASS", result)
        self.assertFalse(result["authorizes_commit"])
        self.assertFalse(result["installed_app_qualified"])
        self.assertTrue(result["trust_limitations"])

    def test_reported_pass_cannot_override_failure_zero_or_skipped_log(self):
        suite = SUITES[0]
        cases = {
            "failure": f"Test Suite '{suite}' failed at synthetic-time\n"
                       "Executed 2 tests, with 1 failure (0 unexpected) in 0.1 seconds\n",
            "zero": f"Test Suite '{suite}' passed at synthetic-time\n"
                    "Executed 0 tests, with 0 failures (0 unexpected) in 0.1 seconds\n",
            "skipped": f"Test Suite '{suite}' passed at synthetic-time\n"
                       "Executed 2 tests, with 1 test skipped and 0 failures in 0.1 seconds\n",
            "build_only": "Build complete! (synthetic fixture)\n",
            "other_suite": "Test Suite 'UnrelatedTests' passed at synthetic-time\n"
                           "Executed 2 tests, with 0 failures in 0.1 seconds\n",
        }
        for name, text in cases.items():
            with self.subTest(case=name):
                self.bundle.replace_log(text)
                self.assert_blocked(self.bundle.verify())

    def test_truthful_nonpass_native_results_remain_distinct_from_corrupt_evidence(self):
        original = copy.deepcopy(self.bundle.report)
        suite = SUITES[0]
        cases = (
            ("FAIL", "TEST_FAILURE", 2, 0, 1, 1, "failed", "BLOCKED"),
            ("SKIPPED", "TEST_RUN_HAS_UNEXECUTED_CASES", 2, 1, 0, 0, "passed", "INCOMPLETE"),
            ("ERROR", "NO_CONFIRMED_TEST_RESULTS", 0, 0, 0, 0, "passed", "BLOCKED"),
        )
        for status, reason, total, skips, failures, exit_code, outcome, decision in cases:
            with self.subTest(source_status=status):
                self.bundle.report = copy.deepcopy(original)
                row = self.bundle.native["suite_results"][0]
                row.update(status=status, reason=reason, exit_code=exit_code,
                           xctest={"executed": total, "skipped": skips, "failures": failures})
                skip_text = f"{skips} test skipped and " if skips else ""
                summary = f"Executed {total} tests, with {skip_text}{failures} failures in 0.1 seconds"
                row["skip_lines"] = [summary] if skips else []
                self.bundle.replace_log(
                    f"Test Suite '{suite}' {outcome} at synthetic-fixture-time\n"
                    + summary + "\n"
                )
                self.bundle.native.update(status=status, reason="SELECTED_SUITES_NOT_ALL_PASS")
                counts = {"PASS": 1, "FAIL": 0, "SKIPPED": 5, "ERROR": 0,
                          "ABSTAIN": 0, "ESCALATE": 0}
                counts[status] += 1
                self.bundle.report["status_counts"] = counts
                self.bundle.report["exit_code"] = 2 if status == "SKIPPED" else 1
                self.bundle.execution["exit_code"] = self.bundle.report["exit_code"]
                self.bundle.save_report()
                self.bundle.save_execution()
                result = self.bundle.verify()
                self.assertEqual(result["integrity"], "PASS", result)
                self.assertEqual(result["source_status"], status, result)
                self.assertEqual(result["decision"], decision, result)
                self.assertFalse(result["authorizes_commit"])
                self.assertFalse(result["installed_app_qualified"])

    def test_pass_log_with_failed_command_is_not_accepted(self):
        self.bundle.native["suite_results"][0]["exit_code"] = 1
        self.bundle.save_report()
        self.assert_blocked(self.bundle.verify())

    def test_a_command_that_never_started_cannot_pass(self):
        self.bundle.native["suite_results"][0]["command_started"] = False
        self.bundle.save_report()
        self.assert_blocked(self.bundle.verify())

    def test_missing_duplicate_and_wrong_suite_records_are_rejected(self):
        original = copy.deepcopy(self.bundle.native["suite_results"])
        variants = {
            "missing": original[:-1],
            "duplicate": original + [copy.deepcopy(original[0])],
            "wrong": [dict(original[0], name="native_UnrelatedTests"), *original[1:]],
        }
        for name, rows in variants.items():
            with self.subTest(case=name):
                self.bundle.native["suite_results"] = rows
                self.bundle.save_report()
                self.assert_blocked(self.bundle.verify())

    def test_duplicate_native_aggregate_is_rejected(self):
        self.bundle.report["checks"].append(copy.deepcopy(self.bundle.native))
        self.bundle.save_report()
        self.assert_blocked(self.bundle.verify())

    def test_command_must_execute_the_requested_candidate_and_suite(self):
        row = self.bundle.native["suite_results"][0]
        original = list(row["command"])
        variants = {
            "other_candidate": [*original[:3], str(self.bundle.candidate.parent / "other"), *original[4:]],
            "other_suite": [*original[:-1], SUITES[1]],
            "extra_argument": [*original, "--skip-build"],
        }
        for name, command_line in variants.items():
            with self.subTest(case=name):
                row["command"] = command_line
                self.bundle.save_report()
                self.assert_blocked(self.bundle.verify())

    def test_live_provider_environment_cannot_enter_source_only_run(self):
        self.bundle.native["suite_results"][0]["environment_overrides"] = {"ARCHI_RECEIPT_LIVE": "1"}
        self.bundle.save_report()
        self.assert_blocked(self.bundle.verify())

    def test_modified_log_is_detected_without_trusting_recorded_digest(self):
        path = Path(self.bundle.native["suite_results"][0]["log"])
        path.write_text(path.read_text() + "Synthetic post-run modification.\n")
        self.assert_blocked(self.bundle.verify())

    def test_changed_contract_cannot_reuse_the_request_pin(self):
        altered = contract()
        altered["objective"] = "Changed after evaluation began."
        save_json(self.bundle.evidence / "contract.json", altered)
        self.assert_blocked(self.bundle.verify())

    def test_modified_request_cannot_choose_its_own_new_pin(self):
        self.bundle.request["request_id"] = "b" * 32
        save_json(self.bundle.evidence / "request.json", self.bundle.request)
        self.assert_blocked(self.bundle.verify())

    def test_changed_candidate_source_blocks_old_evidence(self):
        source = self.bundle.candidate / "desktop/Sources/Synthetic.swift"
        source.write_text(source.read_text() + "let changedAfterRun = true\n")
        self.assert_blocked(self.bundle.verify())

    def test_new_untracked_candidate_source_blocks_old_evidence(self):
        (self.bundle.candidate / "desktop/Sources/Added.swift").write_text("let addedAfterRun = true\n")
        self.assert_blocked(self.bundle.verify())

    def test_deleted_tracked_candidate_source_blocks_old_evidence(self):
        (self.bundle.candidate / "desktop/Sources/Synthetic.swift").unlink()
        self.assert_blocked(self.bundle.verify())

    def test_executable_mode_changes_are_source_changes(self):
        source = self.bundle.candidate / "desktop/Sources/Synthetic.swift"
        source.chmod(0o755)
        self.assert_blocked(self.bundle.verify())

    def test_before_after_source_drift_is_not_hidden_by_restored_current_source(self):
        after = copy.deepcopy(self.bundle.snapshot)
        after["files"][0]["sha256"] = "f" * 64
        after["manifest_sha256"] = hashlib.sha256(canonical(after["files"])).hexdigest()
        save_json(self.bundle.evidence / "source-after.json", after)
        self.assert_blocked(self.bundle.verify())

    def test_raw_source_manifest_cannot_substitute_another_revision(self):
        source = self.bundle.report["archi_source"]
        source["files"][0]["sha256"] = "e" * 64
        source["manifest_sha256"] = hashlib.sha256(canonical(source["files"])).hexdigest()
        self.bundle.save_report()
        self.assert_blocked(self.bundle.verify())

    def test_log_path_cannot_escape_the_evidence_directory(self):
        row = self.bundle.native["suite_results"][0]
        external = self.bundle.evidence.parent / "outside.log"
        external.write_bytes(Path(row["log"]).read_bytes())
        for path in (str(external), str(self.bundle.raw / ".." / ".." / "outside.log")):
            with self.subTest(path=path):
                row["log"] = path
                row["log_sha256"] = digest(external)
                self.bundle.save_report()
                self.assert_blocked(self.bundle.verify())

    def test_log_symlink_cannot_alias_external_evidence(self):
        row = self.bundle.native["suite_results"][0]
        log = Path(row["log"])
        external = self.bundle.evidence.parent / "outside.log"
        external.write_bytes(log.read_bytes())
        log.unlink()
        log.symlink_to(external)
        self.assert_blocked(self.bundle.verify())

    def test_source_symlinks_are_not_silently_followed(self):
        source = self.bundle.candidate / "desktop/Sources/Synthetic.swift"
        outside = self.bundle.candidate.parent / "outside.swift"
        outside.write_bytes(source.read_bytes())
        source.unlink()
        source.symlink_to(outside)
        self.assert_blocked(self.bundle.verify())

    def test_duplicate_json_keys_are_rejected_even_with_fresh_pin(self):
        request_path = self.bundle.evidence / "request.json"
        text = request_path.read_text()
        request_path.write_text(text.replace("{", '{"request_id": "duplicate",', 1))
        self.bundle.request_digest = digest(request_path)
        self.assert_blocked(self.bundle.verify())

    def test_duplicate_keys_in_raw_report_are_not_last_value_wins(self):
        report_path = self.bundle.raw / "acceptance.json"
        text = report_path.read_text()
        report_path.write_text(text.replace("{", '{"host": {},', 1))
        self.assert_blocked(self.bundle.verify())

    def test_boolean_counts_cannot_impersonate_integer_test_counts(self):
        self.bundle.native["suite_results"][0]["xctest"]["failures"] = False
        self.bundle.save_report()
        self.assert_blocked(self.bundle.verify())

    def test_nonfinite_json_numbers_are_rejected(self):
        report_path = self.bundle.raw / "acceptance.json"
        original = report_path.read_text()
        for literal in ("NaN", "Infinity", "1e999"):
            with self.subTest(literal=literal):
                report_path.write_text(original.replace("{", '{"nonfinite": ' + literal + ",", 1))
                self.assert_blocked(self.bundle.verify())

    def test_report_host_cannot_override_request_host(self):
        self.bundle.request["host"] = dict(self.bundle.host, system="Linux", macos="")
        self.bundle.write_request()
        self.assert_blocked(self.bundle.verify())

    def test_linux_host_cannot_present_native_pass_records(self):
        linux = dict(self.bundle.host, system="Linux", macos="")
        self.bundle.request["host"] = linux
        self.bundle.report["host"] = linux
        self.bundle.write_request()
        self.bundle.save_report()
        self.assert_blocked(self.bundle.verify())

    def test_evaluator_script_pin_mismatch_is_rejected(self):
        self.bundle.request["evaluator_files"][EVALUATOR_FILES[0]] = "0" * 64
        self.bundle.write_request()
        self.assert_blocked(self.bundle.verify())

    def test_passing_native_logs_cannot_replace_a_missing_execution_receipt(self):
        (self.bundle.evidence / "execution.json").unlink()
        self.assert_blocked(self.bundle.verify())

    def test_observed_runner_exit_must_agree_with_the_raw_report(self):
        for observed in (0, 1, 99, None):
            with self.subTest(observed_exit=observed):
                self.bundle.execution["exit_code"] = observed
                self.bundle.save_execution()
                self.assert_blocked(self.bundle.verify())

    def test_timeout_and_execution_error_block_otherwise_passing_logs(self):
        original = copy.deepcopy(self.bundle.execution)
        cases = (
            {"timed_out": True},
            {"error": "Synthetic observed execution error"},
            {"error": ""},
        )
        for change in cases:
            with self.subTest(change=change):
                self.bundle.execution = {**original, **change}
                self.bundle.save_execution()
                self.assert_blocked(self.bundle.verify())

    def test_execution_receipt_cannot_change_the_request_or_runner_command(self):
        original = copy.deepcopy(self.bundle.execution)
        cases = (
            {"request_sha256": "0" * 64},
            {"command": [*original["command"][:-1], "1"]},
        )
        for change in cases:
            with self.subTest(change=change):
                self.bundle.execution = {**original, **change}
                self.bundle.save_execution()
                self.assert_blocked(self.bundle.verify())

    def test_execution_receipt_types_do_not_coerce_booleans_and_numbers(self):
        original = copy.deepcopy(self.bundle.execution)
        cases = (
            {"exit_code": False}, {"exit_code": True},
            {"timed_out": 0}, {"timed_out": 1}, {"timed_out": "false"},
            {"elapsed_seconds": False}, {"elapsed_seconds": True},
            {"elapsed_seconds": -0.1}, {"error": False},
        )
        for change in cases:
            with self.subTest(change=change):
                self.bundle.execution = {**original, **change}
                self.bundle.save_execution()
                self.assert_blocked(self.bundle.verify())

    def test_modified_runner_console_cannot_reuse_execution_digest(self):
        console = self.bundle.evidence / "runner-console.log"
        console.write_text(console.read_text() + "Synthetic post-run console mutation.\n")
        self.assert_blocked(self.bundle.verify())


@unittest.skipUnless(platform.system() == "Linux", "This integration case requires the real Linux host.")
class AgentHarnessLinuxCLITests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="archi-harness-real-linux-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.candidate = make_candidate(self.root / "candidate")
        self.source_contract = self.root / "contract-source.json"
        save_json(self.source_contract, contract())
        self.frozen = self.root / "frozen-contract.json"
        self.evidence = self.root / "evidence"

    def cli(self, *arguments: object) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *map(str, arguments)],
            cwd=ROOT, capture_output=True, text=True, timeout=60, check=False,
        )

    def evaluate(self) -> dict:
        freeze = self.cli("freeze", "--contract", self.source_contract, "--output", self.frozen)
        self.assertEqual(freeze.returncode, 0, freeze.stdout + freeze.stderr)
        process = self.cli("evaluate", "--candidate", self.candidate,
                           "--contract", self.frozen, "--contract-sha256", digest(self.frozen),
                           "--output", self.evidence, "--command-timeout", 10)
        self.assertEqual(process.returncode, 2, process.stdout + process.stderr)
        return json.loads((self.evidence / "evaluation.json").read_text())

    def test_freeze_and_evaluate_refuse_to_overwrite_existing_artifacts(self):
        frozen = self.cli("freeze", "--contract", self.source_contract, "--output", self.frozen)
        self.assertEqual(frozen.returncode, 0, frozen.stdout + frozen.stderr)
        before = self.frozen.read_bytes()
        duplicate = self.cli("freeze", "--contract", self.source_contract, "--output", self.frozen)
        self.assertEqual(duplicate.returncode, 1, duplicate.stdout + duplicate.stderr)
        self.assertEqual(self.frozen.read_bytes(), before)
        self.evidence.mkdir()
        sentinel = self.evidence / "previous-run.txt"
        sentinel.write_text("Keep previous evidence intact.\n")
        existing = self.cli("evaluate", "--candidate", self.candidate,
                            "--contract", self.frozen, "--contract-sha256", digest(self.frozen),
                            "--output", self.evidence, "--command-timeout", 10)
        self.assertEqual(existing.returncode, 1, existing.stdout + existing.stderr)
        self.assertEqual(sentinel.read_text(), "Keep previous evidence intact.\n")
        self.assertFalse((self.evidence / "request.json").exists())

    def test_wrong_contract_pin_stops_before_starting_an_evaluation(self):
        frozen = self.cli("freeze", "--contract", self.source_contract, "--output", self.frozen)
        self.assertEqual(frozen.returncode, 0, frozen.stdout + frozen.stderr)
        result = self.cli("evaluate", "--candidate", self.candidate,
                          "--contract", self.frozen, "--contract-sha256", "0" * 64,
                          "--output", self.evidence, "--command-timeout", 10)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertFalse(self.evidence.exists())

    def test_evaluator_executes_its_trusted_runner_not_the_candidate_copy(self):
        sentinel = self.root / "candidate-runner-was-executed.txt"
        candidate_runner = self.candidate / EVALUATOR_FILES[0]
        candidate_runner.write_text(
            "from pathlib import Path\n"
            f"Path({str(sentinel)!r}).write_text('candidate evaluator executed')\n"
            "raise SystemExit(99)\n"
        )
        result = self.evaluate()
        self.assertEqual(result["decision"], "INCOMPLETE", result)
        self.assertFalse(sentinel.exists())
        raw = json.loads((self.evidence / "raw/acceptance.json").read_text())
        self.assertEqual(raw["runner"]["path"], str((ROOT / EVALUATOR_FILES[0]).resolve()))
        self.assertEqual(raw["runner"]["sha256"], digest(ROOT / EVALUATOR_FILES[0]))

    def test_real_linux_evaluate_and_verify_keep_native_execution_incomplete(self):
        result = self.evaluate()
        self.assertEqual(result["integrity"], "PASS", result)
        self.assertEqual(result["source_status"], "SKIPPED", result)
        self.assertEqual(result["decision"], "INCOMPLETE", result)
        self.assertFalse(result["authorizes_commit"])
        self.assertFalse(result["installed_app_qualified"])
        raw = json.loads((self.evidence / "raw/acceptance.json").read_text())
        self.assertEqual(raw["host"]["system"], "Linux")
        native = next(row for row in raw["checks"] if row["name"] == "native_source_tests")
        self.assertEqual(native["status"], "SKIPPED")
        self.assertEqual(native["reason"], "MACOS_REQUIRED")
        self.assertFalse(native["command_started"])
        verified = self.cli("verify", "--candidate", self.candidate, "--evidence", self.evidence,
                            "--request-sha256", digest(self.evidence / "request.json"))
        self.assertEqual(verified.returncode, 2, verified.stdout + verified.stderr)
        self.assertEqual(json.loads(verified.stdout)["decision"], "INCOMPLETE")

    def test_real_cli_rejects_source_mutation_after_evaluation(self):
        self.evaluate()
        source = self.candidate / "desktop/Sources/Synthetic.swift"
        source.write_text(source.read_text() + "let changedAfterEvaluation = true\n")
        verified = self.cli("verify", "--candidate", self.candidate, "--evidence", self.evidence,
                            "--request-sha256", digest(self.evidence / "request.json"))
        self.assertEqual(verified.returncode, 1, verified.stdout + verified.stderr)
        result = json.loads(verified.stdout)
        self.assertEqual(result["decision"], "BLOCKED", result)
        self.assertEqual(result["integrity"], "ERROR", result)
        self.assertFalse(result["authorizes_commit"])

    def test_unicode_source_path_survives_real_runner_manifest_verification(self):
        relative = "desktop/Sources/Caf\u00e9.swift"
        (self.candidate / relative).write_text("// Synthetic Unicode source identity fixture.\n")
        result = self.evaluate()
        self.assertEqual(result["integrity"], "PASS", result)
        self.assertEqual(result["decision"], "INCOMPLETE", result)
        raw = json.loads((self.evidence / "raw/acceptance.json").read_text())
        self.assertIn(relative, [row["path"] for row in raw["archi_source"]["files"]])

    def test_real_verify_cannot_discard_persisted_execution_failure(self):
        result = self.evaluate()
        receipt_path = self.evidence / "execution.json"
        original = json.loads(receipt_path.read_text())
        retained_pin = result["request_sha256"]
        cases = (
            {"exit_code": 99},
            {"timed_out": True, "error": "Synthetic timeout receipt for verifier regression"},
            {"timed_out": 0},
        )
        for change in cases:
            with self.subTest(change=change):
                save_json(receipt_path, {**original, **change})
                verified = self.cli("verify", "--candidate", self.candidate,
                                    "--evidence", self.evidence,
                                    "--request-sha256", retained_pin)
                self.assertEqual(verified.returncode, 1, verified.stdout + verified.stderr)
                self.assertEqual(json.loads(verified.stdout)["decision"], "BLOCKED")
        receipt_path.unlink()
        missing = self.cli("verify", "--candidate", self.candidate,
                           "--evidence", self.evidence, "--request-sha256", retained_pin)
        self.assertEqual(missing.returncode, 1, missing.stdout + missing.stderr)
        self.assertEqual(json.loads(missing.stdout)["decision"], "BLOCKED")


if __name__ == "__main__":
    unittest.main()
