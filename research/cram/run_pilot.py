#!/usr/bin/env python3
"""Run bounded CPU research and disposable admission checks, without app access."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import platform
import tempfile
import time

from admission import DisposableGate
from scheduling import canonical, digest, make_tasks, run_scheduling
from test_admission import exercise_admission


def write_json(path: Path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="fresh directory outside the source repository")
    parser.add_argument("--skip-learned-probe", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    source = Path(__file__).resolve().parent
    repository = source.parents[1]
    if output == repository or repository in output.parents:
        parser.error("experimental outputs must be outside the tracked source repository")
    if output.exists() and any(output.iterdir()):
        parser.error("output directory must be fresh; refusing to overwrite prior evidence")
    output.mkdir(parents=True, exist_ok=True)
    protocol = json.loads((source / "protocol.json").read_text())
    expected_fixed = {"scenes_per_case": 6, "slots": 6,
        "unsatisfiable_case_rule": "index mod 4 equals 3",
        "methods": ["exact_enumeration", "coordinate_energy_penalty_10", "coordinate_energy_penalty_0.01"]}
    for field, expected in expected_fixed.items():
        if protocol["scheduling"][field] != expected:
            parser.error(f"unsupported protocol setting: scheduling.{field}")
    for field, limit in (("cases", 100), ("chains", 32), ("maximum_sweeps_per_chain", 256)):
        value = protocol["scheduling"][field]
        if type(value) is not int or not 1 <= value <= limit:
            parser.error(f"invalid bounded protocol setting: scheduling.{field}")
    files = sorted(p for p in source.rglob("*") if p.is_file() and p.suffix in {".py", ".json"} and "__pycache__" not in p.parts)
    source_hashes = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    tasks = make_tasks(seed=protocol["scheduling"]["seed"], count=protocol["scheduling"]["cases"])
    # Freeze complete inputs and executable hashes before evaluating any arm.
    write_json(output / "protocol.json", protocol)
    write_json(output / "source_hashes.json", source_hashes)
    write_json(output / "scheduling_inputs.json", tasks)
    started = time.perf_counter()
    schedule = run_scheduling(tasks, chains=protocol["scheduling"]["chains"],
                              sweeps=protocol["scheduling"]["maximum_sweeps_per_chain"])
    admission_cases = exercise_admission()
    gated = []
    by_id = {t["id"]: t for t in tasks}
    for row in schedule["records"]:
        if row["result"]["assignment"] is None:
            gated.append({"task_id": row["task_id"], "method": row["method"],
                "decision": None, "solver_status": "ABSTAIN", "admission_attempted": False,
                "reason": "reference_unsatisfiable", "state_bytes_changed": False})
            continue
        with tempfile.TemporaryDirectory(prefix="archi-cram-batch-") as temporary:
            gate = DisposableGate(Path(temporary))
            task = by_id[row["task_id"]]
            proposal = gate.propose(task, row["result"]["assignment"])
            evidence = gate.evaluate(task, proposal)
            event = gate.decide(task, proposal, evidence, explicit_commit=True, dry_run=False)
            if event["decision"] == "COMMIT" and row["validator"]["status"] != "PASS":
                raise AssertionError("invalid candidate entered disposable state")
            gated.append({"task_id": row["task_id"], "method": row["method"], **event})
    write_json(output / "scheduling_summary.json", {k:v for k,v in schedule.items() if k != "records"})
    for filename, rows in (("scheduling_candidates.jsonl", schedule["records"]),
                           ("scheduling_admissions.jsonl", gated), ("admission_cases.jsonl", admission_cases)):
        (output / filename).write_text("".join(canonical(row)+"\n" for row in rows), encoding="utf-8")
    learned = {"status": "SKIPPED", "reason": "explicit skip requested"}
    if not args.skip_learned_probe:
        try:
            from energy_probe import run_probe
        except ImportError as exc:
            learned = {"status": "SKIPPED", "reason": str(exc)}
        else:
            learned = run_probe(output / "mini_sudoku")
    from official.preflight import inspect
    preflight = inspect(None)
    write_json(output / "official_preflight.json", preflight)
    summary = {"schema_version": 1,
        "finished_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "runtime": {"python": platform.python_version(), "platform": platform.platform()},
        "source_hashes_digest": digest(source_hashes), "protocol_hash": digest(protocol),
        "integration": "none", "native_owner_adapter": "NOT_IMPLEMENTED", "production_authority": False,
        "official_cram": {"status": "SKIPPED", "executed": False,
            "reason": "This command runs portable research only. Use official/run_official.py on a prepared NVIDIA environment."},
        "scheduling": {k:v for k,v in schedule.items() if k != "records"},
        "admission": {"cases_passed": len(admission_cases), "cases_failed": 0,
            "candidate_decisions": {name: sum(e["decision"] == name for e in gated)
                 for name in ("COMMIT", "REJECT", "DAMP", "ESCALATE")},
            "proposer_abstentions": sum(e.get("solver_status") == "ABSTAIN" for e in gated),
            "invalid_commits": 0, "scope": "disposable_reference_owner"},
        "learned_energy_probe": learned, "elapsed_seconds": time.perf_counter()-started}
    write_json(output / "summary.json", summary)
    evidence_files = sorted(p for p in output.rglob("*") if p.is_file())
    (output / "EVIDENCE_SHA256SUMS").write_text("".join(
        f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(output).as_posix()}\n" for p in evidence_files), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
