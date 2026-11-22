"""Runner accounting and process-boundary checks; these are not Swift tests."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[2] / "script/test_peer_convergence_macos.py"
SPEC = importlib.util.spec_from_file_location("peer_mac_runner", SOURCE)
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def summary(name, count, failures=0, skipped=0):
    state = "failed" if failures else "passed"
    skip_text = f"{skipped} tests skipped and " if skipped else ""
    return (f"Test Suite '{name}' {state} at 2026-11-22 12:00:00.\n"
            f"\t Executed {count} tests, with {skip_text}{failures} failures (0 unexpected) in 0.1 seconds\n")


class PeerMacRunnerTests(unittest.TestCase):
    def test_selected_core_and_native_counts_do_not_sum_aggregate_or_swift_testing(self):
        core = summary("RepresentationPeerTests", 12) + summary("BoundedConvergenceTests", 4)
        core += summary("All tests", 16) + "Test run with 0 tests passed after 0.001 seconds.\n"
        native = summary("CompanionPeerIntegrationTests", 7) + summary("Selected tests", 7)
        a = runner.classify_xctest(core, 0, runner.CORE_SUITES)
        b = runner.classify_xctest(native, 0, runner.NATIVE_SUITES)
        self.assertEqual((a["status"], b["status"]), ("PASS", "PASS"))
        self.assertEqual(a["executed_cases"] + b["executed_cases"], 23)

    def test_zero_exit_missing_suite_or_zero_cases_is_error(self):
        for log in ("", summary("All tests", 16), summary("RepresentationPeerTests", 12),
                    summary("RepresentationPeerTests", 0) + summary("BoundedConvergenceTests", 4)):
            with self.subTest(log=log):
                self.assertEqual(runner.classify_xctest(log, 0, runner.CORE_SUITES)["status"], "ERROR")

    def test_failed_suite_cannot_be_green_even_with_zero_exit(self):
        log = summary("RepresentationPeerTests", 12, failures=1) + summary("BoundedConvergenceTests", 4)
        self.assertEqual(runner.classify_xctest(log, 0, runner.CORE_SUITES)["status"], "FAIL")

    def test_nonzero_command_after_passing_summaries_is_error(self):
        log = summary("CompanionPeerIntegrationTests", 7)
        self.assertEqual(runner.classify_xctest(log, 1, runner.NATIVE_SUITES)["status"], "ERROR")

    def test_skipped_cases_remain_skipped(self):
        log = summary("CompanionPeerIntegrationTests", 7, skipped=1)
        self.assertEqual(runner.classify_xctest(log, 0, runner.NATIVE_SUITES)["status"], "SKIPPED")

    def test_duplicate_required_suite_is_error_instead_of_last_result_wins(self):
        log = summary("CompanionPeerIntegrationTests", 7) * 2
        result = runner.classify_xctest(log, 0, runner.NATIVE_SUITES)
        self.assertEqual(result["status"], "ERROR")
        self.assertIsNone(result["executed_cases"])

    def test_linux_preflight_is_structured_skip_with_no_swift_calls(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.platform, "system", return_value="Linux"), \
             mock.patch.object(runner.platform, "platform", return_value="Linux-test-fixture"), \
             mock.patch.object(runner.subprocess, "run") as process:
            output = Path(directory)
            result = runner.execute(SOURCE.parents[1], output)
            self.assertEqual(result["status"], "SKIPPED")
            self.assertEqual(result["executed_cases"], 0)
            self.assertEqual(result["stages"], [])
            self.assertEqual(json.loads((output / "mac-test-results.json").read_text())["status"], "SKIPPED")
            process.assert_not_called()

    def test_changed_head_source_or_dirty_worktree_blocks_attribution(self):
        before = {"head": "a" * 40, "tree": "b" * 40, "manifest_sha256": "c" * 64,
                  "verified_source_sha256": {"source.swift": "d" * 64}, "worktree_clean": True}
        for key, value in (("head", "e" * 40), ("tree", "f" * 40),
                           ("manifest_sha256", "0" * 64),
                           ("verified_source_sha256", {"source.swift": "1" * 64}),
                           ("worktree_clean", False)):
            with self.subTest(key=key):
                after = copy.deepcopy(before)
                after[key] = value
                with self.assertRaises(ValueError):
                    runner.assert_unchanged(before, after)

    def test_manifest_requires_exact_coverage_and_valid_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "a.swift").write_text("original\n")
            digest = runner.sha256(root / "a.swift")
            manifest = root / "SOURCE_SHA256SUMS"
            outputs = {("rev-parse", "HEAD"): "a" * 40,
                       ("status", "--porcelain=v1", "--untracked-files=all"): "",
                       ("ls-files", "-z"): "a.swift\0SOURCE_SHA256SUMS\0",
                       ("rev-parse", "HEAD^{tree}"): "b" * 40}
            with mock.patch.object(runner, "git", side_effect=lambda root, *args: outputs[args]):
                manifest.write_text(f"{digest}  a.swift\n")
                self.assertEqual(runner.source_snapshot(root)["tracked_file_count"], 2)
                for bad in ("", f"{digest}  a.swift\n{digest}  a.swift\n", f"{'0' * 64}  a.swift\n"):
                    manifest.write_text(bad)
                    with self.assertRaises(ValueError):
                        runner.source_snapshot(root)

    def test_interrupted_stage_is_preserved_as_error_with_unknown_count(self):
        process = mock.Mock()
        process.wait.side_effect = KeyboardInterrupt
        process.returncode = -2
        with tempfile.TemporaryDirectory() as directory, \
             mock.patch.object(runner.subprocess, "Popen", return_value=process), \
             mock.patch.object(runner, "terminate_group") as cleanup:
            output = Path(directory)
            result = runner.run_stage("interrupted", ["synthetic-process"], output,
                                      output, {}, {"RequiredSuite": 1})
            self.assertEqual(result["status"], "ERROR")
            self.assertTrue(result["interrupted"])
            self.assertIsNone(result["executed_cases"])
            cleanup.assert_called_once_with(process)

    @unittest.skipUnless(os.name == "posix", "Process-group cleanup requires POSIX")
    def test_timeout_stops_child_that_ignores_term_and_stabilizes_log(self):
        # The isolated child writes repeatedly and ignores TERM. It must receive
        # group KILL even if its parent exits immediately after group TERM.
        child = "import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN)\nwhile True: print('child-alive',flush=True); time.sleep(.03)"
        parent = ("import subprocess,sys,time\n"
                  "p=subprocess.Popen([sys.executable,'-u','-c'," + repr(child) + "])\n"
                  "print('child-pid='+str(p.pid),flush=True)\n"
                  "time.sleep(20)\n")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = runner.run_stage("timeout", [sys.executable, "-u", "-c", parent],
                output, output, dict(os.environ), {"Unused": 1}, timeout_seconds=0.3)
            self.assertTrue(result["timed_out"])
            self.assertEqual(result["status"], "ERROR")
            log = output / "timeout.log"
            self.assertIn("child-alive", log.read_text())
            digest = runner.sha256(log)
            time.sleep(0.15)
            self.assertEqual(runner.sha256(log), digest)
            self.assertEqual(result["log_sha256"], digest)


if __name__ == "__main__":
    unittest.main()
