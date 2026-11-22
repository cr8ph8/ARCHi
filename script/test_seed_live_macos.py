#!/usr/bin/env python3
"""Validate the Seed's native projection and bundled WebKit page on a clean Mac.

Reuses the peer runner's bounded execution, strict XCTest accounting, and source
manifest verification. Synthetic fixtures only; never starts a model or peers.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import re

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
    "SeedDiveRenderingTests": 2,
}


def execute(root, output, expected_head, timeout_seconds):
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
        environment["NSUnbufferedIO"] = "YES"
        command = [preflight["executables"]["swift"], "test", "--package-path", str(root / "desktop"),
                   "--scratch-path", str(output / "native-build"),
                   "--cache-path", str(output / "swift-cache"), "--jobs", "2",
                   "--filter", "|".join(EXPECTED_SUITES)]
        print("Running native Seed and peer regression fixtures", flush=True)
        result = run_stage("seed-native", command, root, output, environment,
                           EXPECTED_SUITES, timeout_seconds)
        report["stages"].append(result)
        report["executed_cases"] = result["executed_cases"]
        report["source_after"] = source_snapshot(root, expected_head)
        assert_unchanged(report["source_before"], report["source_after"])
        report.update(status=result["status"], reason=result["reason"])
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
    args = parser.parse_args(argv)
    if not 1 <= args.timeout_seconds <= 600:
        parser.error("--timeout-seconds must be between 1 and 600")
    if args.expected_head and not re.fullmatch(r"[0-9a-f]{40}", args.expected_head):
        parser.error("--expected-head must be a full lowercase commit SHA")
    root = Path(__file__).resolve().parents[1]
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = execute(root, output, args.expected_head, args.timeout_seconds)
    print(json.dumps({key: report.get(key) for key in ("status", "reason", "executed_cases")}, indent=2))
    return {"PASS": 0, "SKIPPED": 2}.get(report["status"], 1)


if __name__ == "__main__":
    raise SystemExit(main())
