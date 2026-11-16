"""Guard against false PASS evidence in the native acceptance runner."""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[2] / "script/accept_relationship_admission.py"
SPEC = importlib.util.spec_from_file_location("relationship_acceptance", SCRIPT)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class EvidenceClassificationTests(unittest.TestCase):
    def test_zero_exit_and_no_tests_are_not_pass(self):
        self.assertEqual(RUNNER.classify_node("", 0)["status"], "ERROR")
        self.assertEqual(RUNNER.classify_node("# tests 0\n# pass 0\n# fail 0\n", 0)["status"], "ERROR")
        self.assertEqual(RUNNER.classify_swift("Build complete!", 0)["status"], "ERROR")
        self.assertEqual(RUNNER.classify_swift("Test run with 0 tests passed after 0.0 seconds.", 0)["status"], "ERROR")

    def test_node_run_keeps_skips_and_failures_distinct(self):
        complete = "# tests 3\n# pass 3\n# fail 0\n# cancelled 0\n# skipped 0\n# todo 0\n"
        self.assertEqual(RUNNER.classify_node(complete, 0)["status"], "PASS")
        skipped = complete.replace("# pass 3", "# pass 2").replace("# skipped 0", "# skipped 1")
        self.assertEqual(RUNNER.classify_node(skipped, 0)["status"], "SKIPPED")
        failed = complete.replace("# pass 3", "# pass 2").replace("# fail 0", "# fail 1")
        self.assertEqual(RUNNER.classify_node(failed, 1)["status"], "FAIL")
        self.assertEqual(RUNNER.classify_node("Cannot import package", 1)["status"], "ERROR")

    def test_swift_framework_counts_remain_separate(self):
        log = "Executed 2 tests, with 0 failures (0 unexpected) in 0.1 seconds\nExecuted 7 tests, with 0 failures (0 unexpected) in 0.2 seconds\nTest run with 4 tests in 2 suites passed after 0.3 seconds.\n"
        result = RUNNER.classify_swift(log, 0)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["xctest"]["executed"], 7)
        self.assertEqual(result["swift_testing"]["reported_tests"], 4)
        self.assertNotIn("total", result)

    def test_swift_skips_do_not_become_pass(self):
        xctest = "Executed 7 tests, with 2 tests skipped and 0 failures (0 unexpected) in 0.2 seconds\n"
        self.assertEqual(RUNNER.classify_swift(xctest, 0)["status"], "SKIPPED")
        testing = '↷ Test localProvider() skipped: "Provider unavailable"\n✔ Test run with 4 tests passed after 0.2 seconds.\n'
        self.assertEqual(RUNNER.classify_swift(testing, 0)["status"], "SKIPPED")

    def test_swift_failures_and_infrastructure_errors_are_distinct(self):
        self.assertEqual(RUNNER.classify_swift("Executed 3 tests, with 1 failure (0 unexpected)", 1)["status"], "FAIL")
        self.assertEqual(RUNNER.classify_swift("Test run with 4 tests failed after 0.2 seconds.", 1)["status"], "FAIL")
        self.assertEqual(RUNNER.classify_swift("error: linker command failed", 1)["status"], "ERROR")

    def test_each_selected_suite_must_be_observed_exactly(self):
        summary = "Executed 3 tests, with 0 failures (0 unexpected) in 0.1 seconds\n"
        other = "Test Suite 'OtherHamptonSessionContextTests' passed at 2026-11-16\n" + summary
        result = RUNNER.classify_swift(other, 0, expected_suite="HamptonSessionContextTests")
        self.assertEqual(result["status"], "ERROR")
        self.assertEqual(result["reason"], "EXPECTED_SUITE_NOT_OBSERVED")
        exact = "Test Suite 'HamptonSessionContextTests' passed at 2026-11-16\n" + summary
        self.assertEqual(RUNNER.classify_swift(exact, 0, expected_suite="HamptonSessionContextTests")["status"], "PASS")
        swift_testing = "✔ Suite WorkingCopyStoreTests passed after 0.1 seconds.\n✔ Test run with 5 tests passed after 0.1 seconds.\n"
        self.assertEqual(RUNNER.classify_swift(swift_testing, 0, expected_suite="WorkingCopyStoreTests")["status"], "PASS")
        self.assertEqual(RUNNER.classify_swift(swift_testing, 0, expected_suite="HamptonProposalValidationTests")["status"], "ERROR")

    def test_live_receipt_rejects_nonobject_and_malformed_checks(self):
        good = {"result": "passed", "receiptAccountingPassed": True,
                "currentInstructionFollowed": True, "externalCalls": 0,
                "checks": {"localOnly": True}}
        malformed = [[], None, "passed", {**good, "checks": []}, {**good, "checks": {}},
                     {**good, "checks": {"localOnly": 1}}, {**good, "externalCalls": False}]
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "receipt.json"
            for payload in malformed:
                with self.subTest(payload=payload):
                    receipt.write_text(json.dumps(payload))
                    self.assertEqual(RUNNER.validate_live_receipt(receipt)["status"], "ERROR")
            receipt.write_text(json.dumps(good))
            self.assertEqual(RUNNER.validate_live_receipt(receipt)["status"], "PASS")
            receipt.write_text(json.dumps({**good, "checks": {"localOnly": False}}))
            self.assertEqual(RUNNER.validate_live_receipt(receipt)["status"], "FAIL")

    def test_malformed_receipt_still_saves_acceptance_report(self):
        # Exercise the complete runner with simulated native command outputs;
        # this unit test is not native execution or live-model evidence.
        for payload in [[], {"checks": []}]:
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "evidence"

                def fake_command(name, command, cwd, destination, timeout, overrides=None):
                    log = destination / (name + ".log")
                    if name == "swift_version":
                        text = "Apple Swift version 6.0 (fixture)\n"
                    else:
                        suite = command[-1]
                        text = f"Test Suite '{suite}' passed at fixture-time\nExecuted 1 test, with 0 failures (0 unexpected) in 0.1 seconds\n"
                    log.write_text(text)
                    if name == "native_live_receipt":
                        live = Path(overrides["ARCHI_RECEIPT_LIVE_OUTPUT"])
                        live.mkdir()
                        (live / "assistant-receipt-live.json").write_text(json.dumps(payload))
                    return {"name": name, "command": command, "command_started": True,
                            "log": str(log), "exit_code": 0}

                with mock.patch.object(RUNNER.sys, "argv", [str(SCRIPT), "--output", str(output), "--live-receipt"]), \
                     mock.patch.object(RUNNER.platform, "system", return_value="Darwin"), \
                     mock.patch.object(RUNNER.platform, "mac_ver", return_value=("14.0", ("", "", ""), "arm64")), \
                     mock.patch.object(RUNNER.shutil, "which", return_value="/fixture/swift"), \
                     mock.patch.object(RUNNER, "source_record", return_value={"fixture": True}), \
                     mock.patch.object(RUNNER, "run_command", side_effect=fake_command), \
                     contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(RUNNER.main(), 1)
                report = json.loads((output / "acceptance.json").read_text())
                live = next(row for row in report["checks"] if row["name"] == "native_live_receipt")
                self.assertEqual(live["status"], "ERROR")
                self.assertEqual(live["reason"], "LIVE_RECEIPT_EVIDENCE_UNAVAILABLE")
                self.assertEqual(report["exit_code"], 1)


if __name__ == "__main__":
    unittest.main()
