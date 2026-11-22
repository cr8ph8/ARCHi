"""Bound a test command and clean up its process group on supported hosts.

This is lifecycle cleanup, not a sandbox: a deliberately detached process can
escape a process group. The native harness supports reviewed Mac test code.
"""
from __future__ import annotations

import os
import signal
import subprocess
import threading


def _signal_group(process: subprocess.Popen, signum: int) -> None:
    try:
        if os.name == "posix":
            os.killpg(process.pid, signum)
        elif process.poll() is None:
            process.kill()
    except ProcessLookupError:
        pass


def _cleanup(process: subprocess.Popen, *, immediate: bool = False) -> None:
    if immediate:
        _signal_group(process, signal.SIGKILL)
    else:
        _signal_group(process, signal.SIGTERM)
        try:
            process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass
        # A descendant can outlive an already-exited group leader. Signal the
        # group even if wait() above returned, so that it cannot overlap a suite.
        _signal_group(process, signal.SIGKILL)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        _signal_group(process, signal.SIGKILL)
        process.wait(timeout=5)


def run_bounded(command: list[str], *, cwd, env, stdout,
                stderr=subprocess.STDOUT, timeout: float) -> subprocess.CompletedProcess:
    """Run a command without inherited input and reap its bounded process group.

    The signal handler forwards controller cancellation to the current command
    group. This also lets a nested acceptance runner clean up its Swift group
    when the outer coordinator times out. Deliberately detached processes remain
    outside the guarantee, as do non-POSIX descendant groups.
    """
    process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                               stdout=stdout, stderr=stderr,
                               start_new_session=(os.name == "posix"))
    old_handlers = {}

    def interrupted(signum, _frame):
        # Immediate propagation prevents an outer timeout from killing the
        # middle runner before its inner command group has been stopped.
        _cleanup(process, immediate=True)
        raise SystemExit(128 + signum)

    if os.name == "posix" and threading.current_thread() is threading.main_thread():
        for signum in (signal.SIGTERM, signal.SIGINT):
            old_handlers[signum] = signal.signal(signum, interrupted)
    try:
        try:
            returncode = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            _cleanup(process)
            raise
        # Normally the group has disappeared. Clean up any remaining descendants
        # before source-after snapshots or another suite can start.
        _cleanup(process)
        return subprocess.CompletedProcess(command, returncode)
    except BaseException:
        _cleanup(process, immediate=True)
        raise
    finally:
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)
