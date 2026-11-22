"""Real POSIX lifecycle checks using disposable Python parent/child processes."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


HELPER = Path(__file__).resolve().parents[2] / "script/harness_process.py"
SPEC = importlib.util.spec_from_file_location("archi_process_under_test", HELPER)
PROCESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROCESS)


@unittest.skipUnless(os.name == "posix", "Process-group checks require POSIX.")
class ProcessGroupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="archi-process-fixture-")
        self.root = Path(self.temporary.name)
        self.pid_file = self.root / "child.pid"
        self.marker = self.root / "unwanted-completion.txt"
        self.addCleanup(self.temporary.cleanup)
        self.addCleanup(self.cleanup_child)
        self.child = (
            "from pathlib import Path; import os, time; "
            f"Path({str(self.pid_file)!r}).write_text(str(os.getpid())); "
            "time.sleep(1.2); "
            f"Path({str(self.marker)!r}).write_text('child continued after its command ended')"
        )
        self.parent = (
            "from pathlib import Path\nimport subprocess, sys, time\n"
            f"subprocess.Popen([sys.executable, '-c', {self.child!r}])\n"
            f"ready = Path({str(self.pid_file)!r})\n"
            "while not ready.exists(): time.sleep(0.005)\n"
        )

    def cleanup_child(self):
        if self.pid_file.exists():
            try:
                os.kill(int(self.pid_file.read_text()), signal.SIGKILL)
            except ProcessLookupError:
                pass

    def assert_child_stopped(self):
        self.assertTrue(self.pid_file.exists(), "Fixture must actually start its child")
        time.sleep(1.25)
        self.assertFalse(self.marker.exists(), "A child escaped command lifecycle cleanup")

    def run_fixture(self, code: str, timeout: float):
        with (self.root / "console.log").open("w") as log:
            return PROCESS.run_bounded([sys.executable, "-c", code], cwd=self.root,
                                       env=os.environ.copy(), stdout=log, timeout=timeout)

    def test_timeout_terminates_command_and_descendant(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            self.run_fixture(self.parent + "time.sleep(30)\n", 0.4)
        self.assert_child_stopped()

    def test_completed_parent_cannot_leave_a_background_child(self):
        result = self.run_fixture(self.parent, 5)
        self.assertEqual(result.returncode, 0)
        self.assert_child_stopped()

    def test_outer_timeout_propagates_to_nested_command_group(self):
        inner = self.parent + "time.sleep(30)\n"
        outer = (
            "import importlib.util, os, sys\n"
            f"spec = importlib.util.spec_from_file_location('nested_process', {str(HELPER)!r})\n"
            "module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)\n"
            f"module.run_bounded([sys.executable, '-c', {inner!r}], cwd={str(self.root)!r}, "
            "env=os.environ.copy(), stdout=sys.stdout, timeout=20)\n"
        )
        with self.assertRaises(subprocess.TimeoutExpired):
            self.run_fixture(outer, 0.4)
        self.assert_child_stopped()


if __name__ == "__main__":
    unittest.main()
