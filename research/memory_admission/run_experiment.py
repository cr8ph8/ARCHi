"""Run paired synthetic candidates and explicit negative controls offline."""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import sqlite3
import statistics
import subprocess
import sys
import tempfile
import time

from .admission import Owner, canonical, digest, evaluate, initial_state, load_policy, proposal
from .fixtures import build_cases


def oracle_truth(case: dict) -> str:
    hidden = case["hidden_entities"]
    if "r1" not in hidden or "r2" not in hidden:
        return "unknown"
    return "same" if hidden["r1"] == hidden["r2"] else "different"


def unsafe_apply_control(owner: Owner, candidate: dict) -> None:
    """INTENTIONALLY UNSAFE comparison writer; only generated test stores.

    This is an experimental ablation, never the current native ARCHi validator.
    It writes the requested alias without admission or commit-time binding.
    """
    connection = sqlite3.connect(owner.path, isolation_level=None)
    try:
        connection.execute("BEGIN IMMEDIATE")
        state = json.loads(connection.execute("SELECT document FROM state WHERE id=1").fetchone()[0])
        state["aliases"][candidate["right_id"]] = candidate["left_id"]
        state["revision"] += 1
        state["commits"].append({"proposal_id": candidate["proposal_id"], "unsafe_control": True})
        connection.execute("UPDATE state SET document=? WHERE id=1", (canonical(state).decode(),))
        connection.execute("COMMIT")
    finally:
        if connection.in_transaction:
            connection.execute("ROLLBACK")
        connection.close()


def replace_fixture_state(owner: Owner, state: dict) -> None:
    """Trusted test setup only, to inject a state change between check and use."""
    with sqlite3.connect(owner.path) as connection:
        connection.execute("UPDATE state SET document=? WHERE id=1", (canonical(state).decode(),))


def _fraction(numerator: int, denominator: int) -> dict:
    return {"numerator": numerator, "denominator": denominator,
            "fraction": numerator / denominator if denominator else None}


def summarize(rows: list[dict]) -> dict:
    result: dict = {"cases": len(rows)}
    for arm in ("proposer_only", "governed"):
        false = [row for row in rows if row["truth"] == "different"]
        eligible_true = [row for row in rows if row["truth"] == "same" and row["eligible"]]
        ineligible_true = [row for row in rows if row["truth"] == "same" and not row["eligible"]]
        unknown = [row for row in rows if row["truth"] == "unknown"]
        result[arm] = {
            "commits": sum(row[arm]["decision"] == "COMMIT" for row in rows),
            "false_merges": _fraction(sum(row[arm]["decision"] == "COMMIT" for row in false), len(false)),
            "eligible_true_accepted": _fraction(sum(row[arm]["decision"] == "COMMIT" for row in eligible_true), len(eligible_true)),
            "ineligible_true_withheld": _fraction(sum(row[arm]["decision"] != "COMMIT" for row in ineligible_true), len(ineligible_true)),
            "unknown_identity_committed": _fraction(sum(row[arm]["decision"] == "COMMIT" for row in unknown), len(unknown)),
            "noncommit_state_mutations": sum(row[arm]["decision"] != "COMMIT" and row[arm]["observed_changed"] for row in rows),
            "transaction_errors": sum(row[arm].get("reason") == "transaction_error" for row in rows),
            "median_elapsed_ms": statistics.median(row[arm]["elapsed_ms"] for row in rows) if rows else None,
        }
    return result


def negative_controls(directory: Path, cases: list[dict]) -> list[dict]:
    """Deliberately faulty paths must create effects the fixture oracle rejects."""
    by_id = {case["case_id"]: case for case in cases}
    controls: list[dict] = []
    for index, mode in enumerate(("accept_all", "trust_supplied_pass", "count_copies_as_origins", "omit_commit_revision_check")):
        case = by_id["many_copies_one_root" if mode == "count_copies_as_origins" else
                     "exact_name" if mode == "omit_commit_revision_check" else "shared_display_name"]
        state = initial_state(case["records"], case["sources"])
        owner = Owner.create(directory / f"control-{index}.sqlite3", state)
        candidate = proposal(state, f"control-{index}")
        good_evidence = evaluate(candidate, state)
        strong = Owner.create(directory / f"strong-{index}.sqlite3", state)
        strong_candidate = copy.deepcopy(candidate)
        strong_evidence = copy.deepcopy(good_evidence)
        faulty_allowed = True
        if mode == "trust_supplied_pass":
            for check in strong_evidence["checks"]:
                check["status"] = "PASS"
            strong_evidence["recommendation"] = "COMMIT"
            faulty_allowed = all(check["status"] == "PASS" for check in strong_evidence["checks"])
        elif mode == "count_copies_as_origins":
            faulty_state = copy.deepcopy(state)
            for source_id, source in faulty_state["sources"].items():
                source["origin"] = source_id
            # Same proposal content is used in paired arms. This separate control
            # intentionally changes the provenance interpretation, then authorizes
            # an effect from that faulty interpretation.
            faulty_candidate = proposal(faulty_state, f"control-{index}")
            faulty_allowed = evaluate(faulty_candidate, faulty_state)["recommendation"] == "COMMIT"
        elif mode == "omit_commit_revision_check":
            changed = copy.deepcopy(state)
            changed["revision"] += 1  # Content-identical ABA/revision fixture.
            replace_fixture_state(owner, changed)
            replace_fixture_state(strong, changed)
            faulty_allowed = good_evidence["recommendation"] == "COMMIT"
        if faulty_allowed:
            unsafe_apply_control(owner, candidate)
        strong_before = strong.snapshot()
        strong_result = strong.commit(strong_candidate, strong_evidence, reviewed_candidate_hash=digest(strong_candidate))
        faulty_after = owner.snapshot()
        strong_after = strong.snapshot()
        wrong_effect = faulty_after["aliases"].get("r2") == "r1"
        expected_reason = {"accept_all": "required_checks_not_passed",
                           "trust_supplied_pass": "evidence_mismatch",
                           "count_copies_as_origins": "required_checks_not_passed",
                           "omit_commit_revision_check": "stale_state"}[mode]
        correct_refusal = (strong_result["decision"] != "COMMIT" and strong_before == strong_after
                           and strong_result["reason"] == expected_reason)
        controls.append({"control": mode, "faulty_effect_observed": wrong_effect,
                         "governed_decision": strong_result["decision"],
                         "governed_reason": strong_result["reason"],
                         "governed_state_unchanged": strong_before == strong_after,
                         "detected": wrong_effect and correct_refusal})
    return controls


def markdown_report(report: dict) -> str:
    contract, overall = report["cohorts"]["contract"], report["overall"]
    def rate(item: dict) -> str:
        return f"{item['numerator']}/{item['denominator']}" if item["denominator"] else "not applicable"
    lines = ["# ARCHi memory-admission experiment", "", f"Run: {report['run_utc']}", "",
             "Synthetic, portable reference experiment. No native app or live model executed.", "",
             "## Observed outcomes", "", "| Measure | Proposer-only control | Governed reference owner |",
             "| --- | ---: | ---: |"]
    for title, group, metric in [
        ("False merges, contract cohort", contract, "false_merges"),
        ("Eligible true merges admitted", contract, "eligible_true_accepted"),
        ("True but ineligible merges withheld", contract, "ineligible_true_withheld"),
        ("Unknown identities committed", contract, "unknown_identity_committed"),
        ("False merges, all cases including false-source challenges", overall, "false_merges"),
    ]:
        lines.append(f"| {title} | {rate(group['proposer_only'][metric])} | {rate(group['governed'][metric])} |")
    lines += ["", "Two intentionally false-consistent source cases are included in the overall denominator. "
              "They satisfy visible evidence requirements while referring to different hidden entities. "
              "Their admission demonstrates that source consistency does not prove semantic truth.", "",
              f"Fixture matrix and faulty controls: **{report['fixture_matrix_verdict']}**. Transaction/replay/process tests are a separate suite; this report does not certify the entire contract.",
              "", "## Faulty controls", "", "| Deliberate fault | Detected | Governed outcome |",
              "| --- | --- | --- |"]
    for control in report["negative_controls"]:
        lines.append(f"| {control['control']} | {control['detected']} | {control['governed_decision']} |")
    lines += ["", "## Case decisions", "", "| Case | Cohort | Oracle truth | Governed decision |",
              "| --- | --- | --- | --- |"]
    for row in report["cases"]:
        lines.append(f"| {row['case_id']} | {row['cohort']} | {row['truth']} | {row['governed']['decision']} |")
    lines += ["", "## Measurement limits", "",
              "- The proposer is a fixed synthetic candidate generator; its natural model error rate is not measured.",
              "- Fixture oracle labels are excluded from the candidate and owner state.",
              "- Source origins are trusted inputs. The contract cohort includes detectable disagreements; false-consistent claims are explicit assumption challenges.",
              "- Traces and hashes provide consistency under trusted-code assumptions, not authenticated execution.",
              "- Timings are descriptive single-run CPU/SQLite measurements; no performance or population-risk claim is made.",
              "- Native Swift, installed Mac behavior, live Ollama, and real memory identity remain NOT RUN / NOT ESTABLISHED.",
              "- This run is not a quantum algorithm or a reproduction of either quantum paper.", ""]
    return "\n".join(lines)


def run(output: Path) -> dict:
    output = output.resolve()
    repository = Path(__file__).resolve().parents[2]
    if output == repository or repository in output.parents:
        raise ValueError("Put generated evidence outside the source checkout")
    output.mkdir(parents=True, exist_ok=False)
    policy = load_policy()
    cases = build_cases()
    fixture_hash = digest(cases)
    freeze = {"frozen_utc": datetime.now(timezone.utc).isoformat(), "contract_hash": digest(policy),
              "fixtures_hash": fixture_hash, "cases": len(cases)}
    (output / "protocol-freeze.json").write_bytes(canonical(freeze) + b"\n")
    rows = []
    with tempfile.TemporaryDirectory(prefix="archi-memory-admission-") as temporary:
        directory = Path(temporary)
        for index, case in enumerate(cases):
            truth = oracle_truth(case)
            if truth != case["truth"]:
                raise ValueError("Fixture oracle disagrees with its declared truth")
            state = initial_state(case["records"], case["sources"])
            if "oracle-only:" in canonical(state).decode():
                raise ValueError("Hidden fixture oracle leaked into visible state")
            candidate = proposal(state, f"p-{index:04d}", policy=policy)
            if any(key in candidate for key in ("truth", "eligible", "expected_decision", "hidden_entities", "case_id")):
                raise ValueError("Scoring metadata leaked into proposal")
            baseline = Owner.create(directory / f"baseline-{index}.sqlite3", state, policy)
            governed = Owner.create(directory / f"governed-{index}.sqlite3", state, policy)
            started = time.perf_counter_ns()
            unsafe_apply_control(baseline, candidate)
            baseline_elapsed = (time.perf_counter_ns() - started) / 1_000_000
            baseline_after = baseline.snapshot()
            started = time.perf_counter_ns()
            evidence = evaluate(candidate, state, policy)
            result = governed.commit(candidate, evidence, reviewed_candidate_hash=digest(candidate))
            governed_elapsed = (time.perf_counter_ns() - started) / 1_000_000
            governed_after = governed.snapshot()
            baseline_result = {"decision": "COMMIT", "elapsed_ms": baseline_elapsed,
                               "observed_changed": baseline_after != state}
            result.update({"elapsed_ms": governed_elapsed, "observed_changed": governed_after != state})
            # Independently read the effect instead of trusting returned status.
            effect = governed_after["aliases"].get("r2") == "r1"
            if effect != (result["decision"] == "COMMIT"):
                raise AssertionError("Reported commit and persisted effect disagree")
            rows.append({"case_id": case["case_id"], "category": case["category"],
                         "cohort": case["cohort"], "truth": truth, "eligible": case["eligible"],
                         "expected_decision": case["expected_decision"], "description": case["description"],
                         "candidate_hash": digest(candidate), "proposer_only_candidate_hash": digest(candidate),
                         "governed_candidate_hash": digest(candidate), "candidate": candidate,
                         "evidence": evidence, "proposer_only": baseline_result, "governed": result,
                         "state_before": state, "state_after": governed_after})
        controls = negative_controls(directory, cases)
    cohort_summaries = {name: summarize([row for row in rows if row["cohort"] == name])
                        for name in ("contract", "assumption_challenge")}
    mismatches = [row["case_id"] for row in rows if row["governed"]["decision"] != row["expected_decision"]]
    execution_errors = [row["case_id"] for row in rows if row["governed"].get("reason") == "transaction_error"]
    contract_stats = cohort_summaries["contract"]["governed"]
    passed = (not mismatches and not execution_errors and all(control["detected"] for control in controls)
              and contract_stats["false_merges"]["numerator"] == 0
              and contract_stats["eligible_true_accepted"]["fraction"] == 1.0
              and contract_stats["noncommit_state_mutations"] == 0)
    try:
        source_commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repository, text=True).strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=repository, text=True).strip())
    except (OSError, subprocess.CalledProcessError):
        source_commit, dirty = None, None
    local_files = sorted(path for path in Path(__file__).resolve().parent.iterdir()
                         if path.suffix in {".py", ".json"})
    import hashlib
    report = {"schema": "archi-memory-admission-report/v1", "run_utc": datetime.now(timezone.utc).isoformat(),
              "fixture_matrix_verdict": "PASS" if passed else "FAIL", "decision_mismatches": mismatches,
              "execution_errors": execution_errors,
              "verdict_scope": "24 fixed identity fixtures and four deliberately faulty controls only",
              "behavioral_suite": "SEPARATE_TEST_SUITE_NOT_RUN_BY_THIS_COMMAND",
              "platform": platform.platform(), "python": sys.version, "sqlite": sqlite3.sqlite_version,
              "source_commit": source_commit, "source_worktree_dirty": dirty,
              "source_hashes": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in local_files},
              "protocol": freeze, "qualification": policy["qualification"], "overall": summarize(rows),
              "cohorts": cohort_summaries, "negative_controls": controls, "cases": rows,
              "model_calls": 0, "live_proposer_error_rate": None,
              "limits": ["Synthetic reference owner only", "No native adapter", "No population-risk estimate",
                         "False-consistent source challenges remain included in overall false-merge totals"]}
    (output / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (output / "report.md").write_text(markdown_report(report), encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="New output directory outside the source checkout")
    args = parser.parse_args()
    report = run(args.output)
    print(json.dumps({"fixture_matrix_verdict": report["fixture_matrix_verdict"], "cases": len(report["cases"]),
                      "overall_false_merges": report["overall"]["governed"]["false_merges"],
                      "contract_false_merges": report["cohorts"]["contract"]["governed"]["false_merges"],
                      "negative_controls_detected": sum(c["detected"] for c in report["negative_controls"]),
                      "output": str(args.output.resolve())}, indent=2))
    return 0 if report["fixture_matrix_verdict"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
