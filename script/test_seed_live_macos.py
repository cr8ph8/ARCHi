#!/usr/bin/env python3
"""Validate the Seed's native projection and bundled WebKit page on a clean Mac.

Reuses the peer runner's bounded execution, strict XCTest accounting, and source
manifest verification. Synthetic fixtures only; never starts a model or peers.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import platform
import re
import subprocess

from test_peer_convergence_macos import (
    assert_unchanged, git, run_stage, runtime_preflight, source_snapshot, utc_now,
)


EXPECTED_SUITES = {
    "RepresentationPeerTests": 12,
    "BoundedConvergenceTests": 4,
    "CompanionPeerIntegrationTests": 7,
    "CompanionGraphTests": 11,
    "SeedDiveTests": 1,
    "SeedTelemetryTests": 8,
    "SeedDiveRenderingTests": 4,
}


@contextmanager
def ci_motion_preferences(output, enabled, environment, reduced=False):
    """Control real OS preferences only in a disposable GitHub-hosted account.

    Production and local test runs never enter this path. WebKit and AppKit must
    still report their actual preference; no browser API or visibility is mocked.
    Save/restore only the two relevant booleans, not whole preference domains.
    """
    if not enabled:
        yield
        return
    if environment.get("GITHUB_ACTIONS") != "true" or environment.get("RUNNER_ENVIRONMENT") != "github-hosted":
        raise ValueError("CI motion configuration is restricted to a disposable GitHub-hosted runner")
    keys = [("com.apple.universalaccess", "reduceMotion"),
            ("com.apple.Accessibility", "ReduceMotionEnabled")]
    records = []
    changed = []
    evidence_path = output / ("ci-reduced-motion-preferences.json" if reduced else "ci-motion-preferences.json")
    result = {"scope": "Disposable CI account only; real OS preferences with restoration",
              "preferences": records, "restoration": []}
    try:
        for domain, key in keys:
            read = subprocess.run(["/usr/bin/defaults", "read", domain, key],
                                  text=True, capture_output=True, timeout=15)
            if read.returncode == 0 and read.stdout.strip().lower() in ("0", "1", "true", "false"):
                value = read.stdout.strip().lower() in ("1", "true")
            elif read.returncode != 0 and "does not exist" in read.stderr.lower():
                value = None
            else:
                raise RuntimeError("Cannot safely read motion preference: " + domain + "/" + key)
            records.append({"domain": domain, "key": key, "before": value, "requested": reduced})
        for record in records:
            if record["before"] is reduced:
                continue
            command = ["/usr/bin/defaults", "write", record["domain"], record["key"], "-bool", str(reduced).lower()]
            # A process can apply its write before timing out. Restore every
            # attempted mutation even when completion cannot be confirmed.
            changed.append(record)
            write = subprocess.run(command, text=True, capture_output=True, timeout=15)
            if write.returncode != 0:
                raise RuntimeError("Motion preference write was denied; no elevated retry: " + record["domain"])
        result["configuration"] = "requested"
        evidence_path.write_text(json.dumps(result, indent=2) + "\n")
        yield
    finally:
        errors = []
        for record in reversed(changed):
            command = ["/usr/bin/defaults"]
            if record["before"] is None:
                command += ["delete", record["domain"], record["key"]]
            else:
                command += ["write", record["domain"], record["key"], "-bool", str(record["before"]).lower()]
            try:
                restored = subprocess.run(command, text=True, capture_output=True, timeout=15)
                success = restored.returncode == 0
            except (OSError, subprocess.TimeoutExpired):
                success = False
            result["restoration"].append({"domain": record["domain"], "key": record["key"], "success": success})
            if not success:
                errors.append(record["domain"] + "/" + record["key"])
        evidence_path.write_text(json.dumps(result, indent=2) + "\n")
        if errors:
            raise RuntimeError("Could not restore CI motion preference: " + ", ".join(errors))


def execute(root, output, expected_head, timeout_seconds, configure_ci_motion=False):
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith("ARCHI_")}
    report = {
        "schema": "archi-seed-live-macos/v1",
        "started_at_utc": utc_now(),
        "system": platform.platform(),
        "expected_head": expected_head,
        "scope": "Native read-only Seed projection, bundled WebKit lifecycle/rendering, and in-process peer regression fixtures. No live models, external peers, installed profile, or measured neural activations.",
        "stages": [],
        "executed_cases": 0,
    }
    try:
        preflight = runtime_preflight(environment)
        report["preflight"] = preflight
        if preflight["status"] != "PASS":
            report.update(status=preflight["status"], reason=preflight["reason"])
            return report
        if any(count < 1 for count in EXPECTED_SUITES.values()):
            raise ValueError("Every required suite must have a positive reviewed test count")
        expected_head = expected_head or git(root, "rev-parse", "HEAD")
        report["expected_head"] = expected_head
        report["source_before"] = source_snapshot(root, expected_head)
        for name in ("module-cache", "swift-cache", "rendered"):
            (output / name).mkdir()
        environment["CLANG_MODULE_CACHE_PATH"] = str(output / "module-cache")
        environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(output / "module-cache")
        environment["SEED_CAPTURE_OUTPUT"] = str(output / "rendered")
        environment["SEED_EXPECT_REDUCED_MOTION"] = "0"
        environment["NSUnbufferedIO"] = "YES"
        command = [preflight["executables"]["swift"], "test", "--package-path", str(root / "desktop"),
                   "--scratch-path", str(output / "native-build"),
                   "--cache-path", str(output / "swift-cache"), "--jobs", "2",
                   "--filter", "|".join(EXPECTED_SUITES)]
        print("Running native Seed and peer regression fixtures", flush=True)
        with ci_motion_preferences(output, configure_ci_motion, environment):
            result = run_stage("seed-native", command, root, output, environment,
                               EXPECTED_SUITES, timeout_seconds)
            # Keep actual case accounting even if preference restoration fails.
            report["stages"].append(result)
            report["executed_cases"] = result["executed_cases"]
        if configure_ci_motion and result["status"] == "PASS":
            # Repeat only the concrete accessibility regressions, with the real
            # OS preference enabled. Reuse the built native test binary.
            reduced_environment = dict(environment)
            reduced_environment.pop("SEED_CAPTURE_OUTPUT", None)
            reduced_environment["SEED_EXPECT_REDUCED_MOTION"] = "1"
            reduced_command = command[:-2] + ["--skip-build", "--filter",
                "SeedDiveRenderingTests/testStandaloneReplayPausesAndNativeArrivalPermanentlyFencesIt|"
                "SeedDiveRenderingTests/testFirstFormReducedMotionKeepsPreviewSelectable"]
            print("Running actual reduced-motion replay and first-form regressions", flush=True)
            with ci_motion_preferences(output, True, reduced_environment, reduced=True):
                reduced_result = run_stage("seed-reduced-motion", reduced_command, root, output,
                    reduced_environment, {"SeedDiveRenderingTests": 2}, min(timeout_seconds, 90))
                report["stages"].append(reduced_result)
                counts = [stage["executed_cases"] for stage in report["stages"]]
                report["executed_cases"] = sum(counts) if all(count is not None for count in counts) else None
        report["source_after"] = source_snapshot(root, expected_head)
        assert_unchanged(report["source_before"], report["source_after"])
        statuses = [stage["status"] for stage in report["stages"]]
        status = next((value for value in ("ERROR", "FAIL", "SKIPPED") if value in statuses), "PASS")
        report.update(status=status, reason="All required native populations passed" if status == "PASS" else "See individual stage results")
    except (Exception, KeyboardInterrupt) as exc:
        report.update(status="ERROR", reason=type(exc).__name__ + ": " + str(exc))
    finally:
        report["finished_at_utc"] = utc_now()
        (output / "seed-test-results.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="New evidence directory outside the checkout")
    parser.add_argument("--expected-head", help="Immutable source revision")
    parser.add_argument("--timeout-seconds", type=int, default=600)
    parser.add_argument("--configure-ci-motion", action="store_true",
                        help="Temporarily configure real motion preferences on a disposable GitHub-hosted runner only")
    args = parser.parse_args(argv)
    if not 1 <= args.timeout_seconds <= 600:
        parser.error("--timeout-seconds must be between 1 and 600")
    if args.expected_head and not re.fullmatch(r"[0-9a-f]{40}", args.expected_head):
        parser.error("--expected-head must be a full lowercase commit SHA")
    root = Path(__file__).resolve().parents[1]
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = execute(root, output, args.expected_head, args.timeout_seconds, args.configure_ci_motion)
    print(json.dumps({key: report.get(key) for key in ("status", "reason", "executed_cases")}, indent=2))
    return {"PASS": 0, "SKIPPED": 2}.get(report["status"], 1)


if __name__ == "__main__":
    raise SystemExit(main())
