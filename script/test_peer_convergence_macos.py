#!/usr/bin/env python3
"""Run bounded peer core and native integration fixtures on a clean Mac checkout.

Exit 0: both selected populations passed. Exit 1: FAIL or ERROR.
Exit 2: prerequisites or selected tests were SKIPPED. No live providers are used.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import time

ANCHOR = "3f5e8d6dad1b80a02ccb19de14b6f1f541cdc281"
CORE_SUITES = {"RepresentationPeerTests": 12, "BoundedConvergenceTests": 4}
NATIVE_SUITES = {"CompanionPeerIntegrationTests": 7}
CORE_FILES = ("RepresentationPeerDomain.swift", "PeerObservationDirectory.swift",
              "PeerWorkSession.swift", "PeerGossipSimulation.swift")
SUITE_SUMMARY = re.compile(
    r"Test Suite '([^']+)' (passed|failed)[^\n]*\n\s*"
    r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?"
)


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def git(root, *args):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True,
                            timeout=30, check=True)
    return result.stdout.decode("utf-8", errors="strict").strip()


def source_snapshot(root, expected_head=None):
    """Validate full tracked-file manifest coverage and capture native inputs."""
    head = git(root, "rev-parse", "HEAD")
    if expected_head is not None and head != expected_head:
        raise ValueError("HEAD differs from the requested immutable revision")
    status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    if status:
        raise ValueError("Checkout is not clean; use a clean isolated checkout")
    tracked = set(git(root, "ls-files", "-z").split("\0")) - {""}
    expected_paths = tracked - {"SOURCE_SHA256SUMS"}
    listed = {}
    for line in (root / "SOURCE_SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match or match[2] in listed:
            raise ValueError("Malformed or duplicate source manifest entry")
        listed[match[2]] = match[1]
    if set(listed) != expected_paths:
        raise ValueError("Source manifest does not cover exactly every tracked file except itself")
    actual = {name: sha256(root / name) for name in sorted(expected_paths)}
    changed = [name for name in actual if actual[name] != listed[name]]
    if changed:
        raise ValueError("Source manifest hash mismatch: " + ", ".join(changed[:5]))
    return {"head": head, "tree": git(root, "rev-parse", "HEAD^{tree}"),
            "worktree_clean": True, "tracked_file_count": len(tracked),
            "manifest_sha256": sha256(root / "SOURCE_SHA256SUMS"),
            "verified_source_sha256": actual,
            "native_input_paths": sorted(name for name in actual if name.startswith("desktop/"))}


def assert_unchanged(before, after):
    for key in ("head", "tree", "manifest_sha256", "verified_source_sha256"):
        if before[key] != after[key]:
            raise ValueError("Source changed during execution: " + key)
    if not after["worktree_clean"]:
        raise ValueError("Checkout became dirty during execution")


def classify_xctest(text, returncode, expected, timed_out=False):
    """Count selected XCTest suites once; ignore aggregate/Swift Testing totals."""
    matches = {}
    for name, state, count, skipped, failures in SUITE_SUMMARY.findall(text):
        name = name.split(".")[-1]
        if name in expected:
            matches.setdefault(name, []).append({"state": state, "executed": int(count),
                "skipped": int(skipped or 0), "failures": int(failures)})
    duplicate = any(len(rows) != 1 for rows in matches.values())
    complete = set(matches) == set(expected) and not duplicate
    observed = {name: rows[0] for name, rows in matches.items() if len(rows) == 1}
    counts_match = complete and all(observed[name]["executed"] == count
                                   for name, count in expected.items())
    if timed_out:
        status, reason = "ERROR", "Stage exceeded its bounded timeout"
    elif duplicate:
        status, reason = "ERROR", "Duplicate required-suite summaries"
    elif any(row["failures"] or row["state"] == "failed" for row in observed.values()):
        status, reason = "FAIL", "Selected XCTest suite reported a failure"
    elif returncode != 0:
        status, reason = "ERROR", "Command failed without a complete passing test result"
    elif not counts_match:
        status, reason = "ERROR", "Missing or unexpected selected-suite test counts"
    elif any(row["skipped"] for row in observed.values()) or re.search(r"Test Case [^\n]+ skipped", text):
        status, reason = "SKIPPED", "Selected execution includes skipped tests"
    else:
        status, reason = "PASS", "Every expected selected test executed and passed"
    return {"status": status, "reason": reason, "expected_suites": expected,
            "observed_suites": observed, "accounting_complete": complete,
            "executed_cases": sum(row["executed"] for row in observed.values()) if complete else None}


def terminate_group(process, grace_seconds=2):
    """Stop descendants even when the immediate Swift parent exits on SIGTERM."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + grace_seconds
    while time.monotonic() < deadline:
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            break
        time.sleep(min(0.05, max(0, deadline - time.monotonic())))
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=5)


def run_stage(name, command, root, output, environment, expected, timeout_seconds=600):
    log = output / (name + ".log")
    started = time.monotonic()
    timed_out = False
    interrupted = False
    code = None
    launch_error = None
    with log.open("w") as stream:
        try:
            process = subprocess.Popen(command, cwd=root, env=environment, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=timeout_seconds)
            except subprocess.TimeoutExpired:
                timed_out = True
                terminate_group(process)
                code = process.returncode
            except KeyboardInterrupt:
                interrupted = True
                terminate_group(process)
                code = process.returncode
            except BaseException:
                terminate_group(process)
                raise
        except OSError as exc:
            launch_error = str(exc)
            stream.write("Process launch failed: " + launch_error + "\n")
    result = classify_xctest(log.read_text(errors="replace"), code, expected, timed_out)
    if interrupted:
        result.update(status="ERROR", reason="Execution interrupted; process group stopped")
    if launch_error is not None:
        result["executed_cases"] = 0
    result.update({"stage": name, "command": command, "cwd": str(root),
                   "returncode": code, "timed_out": timed_out, "interrupted": interrupted,
                   "timeout_seconds": timeout_seconds, "launch_error": launch_error,
                   "elapsed_seconds": round(time.monotonic() - started, 3),
                   "log": log.name, "log_sha256": sha256(log)})
    return result


def runtime_preflight(environment):
    if platform.system() != "Darwin":
        return {"status": "SKIPPED", "reason": "macOS is required; no Swift test cases executed"}
    mac_version = platform.mac_ver()[0]
    if not mac_version or int(mac_version.split(".")[0]) < 14:
        return {"status": "SKIPPED", "reason": "macOS 14 or newer is required"}
    paths = {name: shutil.which(name, path=environment.get("PATH")) for name in ("swift", "xcrun", "git")}
    if not all(paths.values()):
        return {"status": "SKIPPED", "reason": "Missing prerequisite: " +
                ", ".join(name for name, path in paths.items() if path is None)}
    metadata = {"macos_version": mac_version, "executables": paths}
    for key, command in (
        ("swift_version", [paths["swift"], "--version"]),
        ("sdk_path", [paths["xcrun"], "--sdk", "macosx", "--show-sdk-path"]),
        ("sdk_version", [paths["xcrun"], "--sdk", "macosx", "--show-sdk-version"]),
    ):
        try:
            run = subprocess.run(command, env=environment, text=True, capture_output=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as exc:
            return {**metadata, "status": "SKIPPED", "reason": "Toolchain prerequisite failed: " + str(exc)}
        metadata[key] = (run.stdout + run.stderr).strip()
        if run.returncode != 0:
            return {**metadata, "status": "SKIPPED", "reason": "Toolchain prerequisite failed: " + key}
    version = re.search(r"Swift version (\d+)", metadata["swift_version"])
    if not version or int(version[1]) < 6:
        return {**metadata, "status": "SKIPPED", "reason": "Swift 6 or newer is required"}
    return {**metadata, "status": "PASS", "reason": "Mac toolchain prerequisites available"}


def core_package(root, output):
    package = output / "core-package"
    sources = package / "Sources" / "ARCHiDesktop"
    tests = package / "Tests" / "PeerTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for name in CORE_FILES:
        shutil.copy2(root / "desktop/Sources/ARCHiDesktop" / name, sources / name)
    for name in ("RepresentationPeerTests.swift", "BoundedConvergenceTests.swift"):
        shutil.copy2(root / "desktop/Tests/ARCHiDesktopTests" / name, tests / name)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ARCHiPeerConvergenceValidation",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ARCHiDesktop", targets: ["ARCHiDesktop"])],
    targets: [.target(name: "ARCHiDesktop"),
              .testTarget(name: "PeerTests", dependencies: ["ARCHiDesktop"])]
)
''')
    return package


def execute(root, output, expected_head=None, timeout_seconds=600):
    environment = dict(os.environ)
    removed = sorted(name for name in environment if name.startswith("ARCHI_"))
    for name in removed:
        del environment[name]
    report = {"schema": "archi-peer-convergence-macos/v1", "started_at_utc": utc_now(),
              "system": platform.platform(), "removed_environment_variable_names": removed,
              "stages": [], "attempted_stages": [], "executed_cases": 0,
              "scope": "Actual Foundation peer core and native in-process integration fixtures; installed app, UI, live inference and network peers are excluded."}
    try:
        preflight = runtime_preflight(environment)
        report["preflight"] = preflight
        if preflight["status"] != "PASS":
            report.update(status=preflight["status"], reason=preflight["reason"])
            return report
        observed_head = git(root, "rev-parse", "HEAD")
        expected_head = expected_head or observed_head
        report["expected_head"] = expected_head
        git(root, "merge-base", "--is-ancestor", ANCHOR, expected_head)
        report["source_before"] = source_snapshot(root, expected_head)
        shutil.copy2(root / "SOURCE_SHA256SUMS", output / "SOURCE_SHA256SUMS")
        package = core_package(root, output)
        package_files = list(package.rglob("*.swift"))
        report["core_input_sha256"] = {str(path.relative_to(package)): sha256(path) for path in package_files}
        for name in ("module-cache", "swift-cache"):
            (output / name).mkdir()
        environment["CLANG_MODULE_CACHE_PATH"] = str(output / "module-cache")
        environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(output / "module-cache")
        swift = preflight["executables"]["swift"]
        for name, package_path, expected, extra in (
            ("core", package, CORE_SUITES, []),
            ("native-integration", root / "desktop", NATIVE_SUITES,
             ["--filter", "CompanionPeerIntegrationTests"]),
        ):
            command = [swift, "test", "--package-path", str(package_path),
                       "--scratch-path", str(output / (name + "-build")),
                       "--cache-path", str(output / "swift-cache"), "--jobs", "2", *extra]
            print("Running " + name, flush=True)
            report["attempted_stages"].append(name)
            result = run_stage(name, command, root, output, environment, expected, timeout_seconds)
            report["stages"].append(result)
            print(name + ": " + result["status"], flush=True)
            if result["interrupted"]:
                break
        report["source_after"] = source_snapshot(root, expected_head)
        assert_unchanged(report["source_before"], report["source_after"])
        if report["core_input_sha256"] != {str(path.relative_to(package)): sha256(path) for path in package_files}:
            raise ValueError("Copied core input changed during execution")
        statuses = [stage["status"] for stage in report["stages"]]
        report["status"] = next((status for status in ("ERROR", "FAIL", "SKIPPED") if status in statuses), "PASS")
        report["reason"] = "Both selected populations completed" if report["status"] == "PASS" else "See individual stage results"
    except (Exception, KeyboardInterrupt) as exc:
        report.update(status="ERROR", reason=type(exc).__name__ + ": " + str(exc))
    finally:
        if len(report["stages"]) != len(report["attempted_stages"]):
            report["executed_cases"] = None
        elif report["stages"]:
            counts = [stage["executed_cases"] for stage in report["stages"]]
            report["executed_cases"] = sum(counts) if all(count is not None for count in counts) else None
        report["finished_at_utc"] = utc_now()
        (output / "mac-test-results.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="New evidence directory outside the checkout or in an ignored output path")
    parser.add_argument("--expected-head", help="Immutable commit expected at execution time; defaults to HEAD captured before tests")
    parser.add_argument("--timeout-seconds", type=int, default=600, help="Per-stage bound, from 1 through 600 seconds")
    args = parser.parse_args(argv)
    if not 1 <= args.timeout_seconds <= 600:
        parser.error("--timeout-seconds must be between 1 and 600")
    if args.expected_head and not re.fullmatch(r"[0-9a-f]{40}", args.expected_head):
        parser.error("--expected-head must be a full lowercase 40-character commit SHA")
    root = Path(__file__).resolve().parents[1]
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = execute(root, output, args.expected_head, args.timeout_seconds)
    print(json.dumps({"status": report["status"], "reason": report["reason"],
                      "executed_cases": report["executed_cases"], "evidence": str(output)}, indent=2))
    return {"PASS": 0, "SKIPPED": 2}.get(report["status"], 1)


if __name__ == "__main__":
    raise SystemExit(main())
