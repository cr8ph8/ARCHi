"""CI preference cleanup contracts; all defaults operations use an in-memory double."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPTS = Path(__file__).resolve().parents[2] / "script"
PEER_SPEC = importlib.util.spec_from_file_location(
    "peer_runner_for_seed_tests", SCRIPTS / "test_peer_convergence_macos.py")
peer_runner = importlib.util.module_from_spec(PEER_SPEC)
PEER_SPEC.loader.exec_module(peer_runner)
SPEC = importlib.util.spec_from_file_location(
    "seed_mac_runner", SCRIPTS / "test_seed_live_macos.py")
runner = importlib.util.module_from_spec(SPEC)
# unittest discovery may already have loaded the similarly named test module.
# Bind the dependency to its actual production script only during this import.
with mock.patch.dict(sys.modules, {"test_peer_convergence_macos": peer_runner}):
    SPEC.loader.exec_module(runner)


FIRST = ("com.apple.universalaccess", "reduceMotion")
SECOND = ("com.apple.Accessibility", "ReduceMotionEnabled")
HOSTED = {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"}


def command(operation, key, value=None):
    result = ["/usr/bin/defaults", operation, *key]
    if operation == "write":
        result += ["-bool", str(value).lower()]
    return result


class DefaultsDouble:
    """Models only the two declared keys; any broader command fails the test."""
    def __init__(self, state, fail_once=None, failure=None, apply_before_failure=False):
        self.state = dict(state)
        self.calls = []
        self.fail_once = fail_once
        self.failure = failure
        self.apply_before_failure = apply_before_failure

    def __call__(self, args, **kwargs):
        args = list(args)
        self.calls.append(args)
        if args[0] != "/usr/bin/defaults" or tuple(args[2:4]) not in (FIRST, SECOND):
            raise AssertionError("Only the two declared preference keys may be touched")
        if kwargs.get("timeout") != 15 or not kwargs.get("capture_output") or not kwargs.get("text"):
            raise AssertionError("Preference operations must remain bounded and captured")
        if kwargs.get("shell"):
            raise AssertionError("Preference operations must not use a shell")
        operation, key = args[1], tuple(args[2:4])
        expected_length = 6 if operation == "write" else 4
        if len(args) != expected_length or operation not in ("read", "write", "delete"):
            raise AssertionError("No whole-domain or additional defaults command is allowed")
        if operation == "write" and (args[4] != "-bool" or args[5] not in ("true", "false")):
            raise AssertionError("Only boolean writes are allowed")
        failing = args == self.fail_once
        if failing:
            self.fail_once = None
        if not failing or self.apply_before_failure:
            if operation == "write":
                self.state[key] = args[5] == "true"
            elif operation == "delete":
                self.state.pop(key, None)
        if failing:
            if isinstance(self.failure, BaseException):
                raise self.failure
            return subprocess.CompletedProcess(args, self.failure or 1, stdout="", stderr="Operation denied")
        if operation == "read":
            if key not in self.state:
                return subprocess.CompletedProcess(args, 1, stdout="", stderr="The domain/default pair does not exist")
            value = self.state[key]
            text = "1" if value is True else "0" if value is False else str(value)
            return subprocess.CompletedProcess(args, 0, stdout=text + "\n", stderr="")
        return subprocess.CompletedProcess(args, 0, stdout="", stderr="")


class SeedMacRunnerTests(unittest.TestCase):
    def report(self, output):
        return json.loads((output / "ci-motion-preferences.json").read_text())

    def test_disabled_configuration_never_reads_or_writes_local_preferences(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "run") as process:
            output = Path(directory)
            with runner.ci_motion_preferences(output, False, {}):
                pass
            process.assert_not_called()
            self.assertFalse((output / "ci-motion-preferences.json").exists())

    def test_non_hosted_and_partially_claimed_ci_environments_are_rejected_before_any_call(self):
        environments = [{}, {"GITHUB_ACTIONS": "true"},
                        {"RUNNER_ENVIRONMENT": "github-hosted"},
                        {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "self-hosted"},
                        {"GITHUB_ACTIONS": "false", "RUNNER_ENVIRONMENT": "github-hosted"}]
        for environment in environments:
            with self.subTest(environment=environment), tempfile.TemporaryDirectory() as directory, \
                 mock.patch.object(runner.subprocess, "run") as process:
                with self.assertRaisesRegex(ValueError, "GitHub-hosted"):
                    with runner.ci_motion_preferences(Path(directory), True, environment):
                        self.fail("The guarded body must not run")
                process.assert_not_called()
                self.assertFalse((Path(directory) / "ci-motion-preferences.json").exists())

    def test_only_needed_booleans_change_and_original_values_are_restored(self):
        original = {FIRST: True, SECOND: False}
        defaults = DefaultsDouble(original)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "run", side_effect=defaults):
            output = Path(directory)
            with runner.ci_motion_preferences(output, True, HOSTED):
                self.assertEqual(defaults.state, {FIRST: False, SECOND: False})
            self.assertEqual(defaults.state, original)
            self.assertEqual(defaults.calls, [command("read", FIRST), command("read", SECOND),
                command("write", FIRST, False), command("write", FIRST, True)])
            result = self.report(output)
            self.assertEqual(result["configuration"], "requested")
            self.assertEqual(len(result["restoration"]), 1)
            self.assertTrue(result["restoration"][0]["success"])

    def test_body_error_restores_every_changed_key_before_propagating(self):
        original = {FIRST: True, SECOND: True}
        defaults = DefaultsDouble(original)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "run", side_effect=defaults):
            output = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "synthetic inner failure"):
                with runner.ci_motion_preferences(output, True, HOSTED):
                    self.assertEqual(defaults.state, {FIRST: False, SECOND: False})
                    raise RuntimeError("synthetic inner failure")
            self.assertEqual(defaults.state, original)
            self.assertEqual(defaults.calls[-2:], [command("write", SECOND, True), command("write", FIRST, True)])
            self.assertTrue(all(row["success"] for row in self.report(output)["restoration"]))

    def test_originally_missing_key_is_deleted_instead_of_retaining_a_new_false_value(self):
        original = {FIRST: False}
        defaults = DefaultsDouble(original)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "run", side_effect=defaults):
            output = Path(directory)
            with runner.ci_motion_preferences(output, True, HOSTED):
                self.assertEqual(defaults.state, {FIRST: False, SECOND: False})
            self.assertEqual(defaults.state, original)
            self.assertEqual(defaults.calls[-1], command("delete", SECOND))
            result = self.report(output)
            self.assertIsNone(result["preferences"][1]["before"])
            self.assertTrue(result["restoration"][0]["success"])

    def test_reduced_variant_enables_real_keys_then_restores_false_and_missing_values(self):
        original = {FIRST: False}
        defaults = DefaultsDouble(original)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "run", side_effect=defaults):
            output = Path(directory)
            normal_evidence = output / "ci-motion-preferences.json"
            normal_evidence.write_text("earlier variant evidence\n")
            with runner.ci_motion_preferences(output, True, HOSTED, reduced=True):
                self.assertEqual(defaults.state, {FIRST: True, SECOND: True})
            self.assertEqual(defaults.state, original)
            self.assertEqual(defaults.calls[-2:], [command("delete", SECOND), command("write", FIRST, False)])
            result = json.loads((output / "ci-reduced-motion-preferences.json").read_text())
            self.assertTrue(all(row["requested"] is True for row in result["preferences"]))
            self.assertTrue(all(row["success"] for row in result["restoration"]))
            self.assertEqual(normal_evidence.read_text(), "earlier variant evidence\n")

    def test_denied_write_stops_without_elevated_retry_and_restores_prior_changes(self):
        original = {FIRST: True, SECOND: True}
        denied = command("write", SECOND, False)
        defaults = DefaultsDouble(original, fail_once=denied, failure=1)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "run", side_effect=defaults):
            output = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "denied.*no elevated retry"):
                with runner.ci_motion_preferences(output, True, HOSTED):
                    self.fail("A denied setup cannot enter the test body")
            self.assertEqual(defaults.state, original)
            self.assertEqual(defaults.calls.count(denied), 1)
            self.assertTrue(all(row["success"] for row in self.report(output)["restoration"]))

    def test_write_that_applies_then_times_out_is_still_restored(self):
        original = {FIRST: True, SECOND: False}
        attempted = command("write", FIRST, False)
        defaults = DefaultsDouble(original, fail_once=attempted,
            failure=subprocess.TimeoutExpired(attempted, 15), apply_before_failure=True)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "run", side_effect=defaults):
            output = Path(directory)
            with self.assertRaises(subprocess.TimeoutExpired):
                with runner.ci_motion_preferences(output, True, HOSTED):
                    self.fail("Uncertain setup cannot enter the test body")
            self.assertEqual(defaults.state, original)
            self.assertEqual(defaults.calls[-1], command("write", FIRST, True))
            self.assertTrue(self.report(output)["restoration"][0]["success"])

    def test_unknown_preference_value_aborts_before_mutating_any_key(self):
        original = {FIRST: True, SECOND: "not-a-boolean"}
        defaults = DefaultsDouble(original)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "run", side_effect=defaults):
            output = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "Cannot safely read"):
                with runner.ci_motion_preferences(output, True, HOSTED):
                    self.fail("An unreadable preference must not be overwritten")
            self.assertEqual(defaults.state, original)
            self.assertTrue(all(args[1] == "read" for args in defaults.calls))
            self.assertEqual(self.report(output)["restoration"], [])

    def test_restoration_failure_is_reported_and_other_keys_are_still_restored(self):
        original = {FIRST: True, SECOND: True}
        defaults = DefaultsDouble(original, fail_once=command("write", SECOND, True), failure=1)
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "run", side_effect=defaults):
            output = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "Could not restore CI motion preference"):
                with runner.ci_motion_preferences(output, True, HOSTED):
                    pass
            self.assertTrue(defaults.state[FIRST])
            self.assertFalse(defaults.state[SECOND])
            rows = self.report(output)["restoration"]
            self.assertEqual([row["success"] for row in rows], [False, True])
            self.assertEqual(rows[0]["key"], SECOND[1])


if __name__ == "__main__":
    unittest.main()
