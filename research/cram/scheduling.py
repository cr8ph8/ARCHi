"""Synthetic production scheduling probe; this is not the official CRAM model.

The energy search and the direct requirements validator are separate code paths.
An exact enumerator is the reference for feasibility and the best valid cost.
All fixtures are fictional; no production booking or project data is accessed.
"""
from __future__ import annotations

import hashlib
import itertools
import json
import random
import re
import time
from typing import Any


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def validate_task(task: Any) -> dict:
    """Closed, bounded context schema for this synthetic one-slot experiment."""
    def bad(reason):
        return {"status": "ERROR", "reasons": ["invalid_context:" + reason]}
    def identifier(value):
        return type(value) is str and re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value) is not None
    if type(task) is not dict or set(task) != {"id", "revision", "slots", "scenes", "precedence", "synthetic", "duration_slots"}:
        return bad("fields")
    if not identifier(task["id"]) or type(task["revision"]) is not int or task["revision"] < 1:
        return bad("identity_revision")
    if type(task["slots"]) is not int or not 1 <= task["slots"] <= 12:
        return bad("slot_count")
    if type(task["duration_slots"]) is not int or task["duration_slots"] != 1 or task["synthetic"] is not True:
        return bad("unsupported_duration_or_real_context")
    if type(task["scenes"]) is not list or not 1 <= len(task["scenes"]) <= 8:
        return bad("scenes")
    ids = set()
    for scene in task["scenes"]:
        if type(scene) is not dict or set(scene) != {"id", "actors", "location", "allowed_slots", "priority"}:
            return bad("scene_fields")
        if not identifier(scene["id"]) or scene["id"] in ids or not identifier(scene["location"]):
            return bad("scene_identity")
        ids.add(scene["id"])
        actors = scene["actors"]
        if type(actors) is not list or not 1 <= len(actors) <= 8 or not all(identifier(a) for a in actors) or len(actors) != len(set(actors)):
            return bad("actors")
        allowed = scene["allowed_slots"]
        if type(allowed) is not list or not allowed or not all(type(s) is int and 0 <= s < task["slots"] for s in allowed) or len(allowed) != len(set(allowed)):
            return bad("allowed_slots")
        if type(scene["priority"]) is not int or not 1 <= scene["priority"] <= 100:
            return bad("priority")
    if type(task["precedence"]) is not list or len(task["precedence"]) > 56:
        return bad("precedence")
    seen = set()
    for pair in task["precedence"]:
        if type(pair) is not list or len(pair) != 2 or not all(type(x) is str and x in ids for x in pair) or pair[0] == pair[1]:
            return bad("precedence_reference")
        if tuple(pair) in seen:
            return bad("duplicate_precedence")
        seen.add(tuple(pair))
    return {"status": "PASS", "reasons": []}


def make_tasks(seed: int = 20261115, count: int = 24) -> list[dict]:
    rng = random.Random(seed)
    tasks = []
    for n in range(count):
        witness = rng.sample(range(6), 6)
        scenes = []
        for i in range(6):
            scenes.append({"id": f"scene-{i}",
                "actors": sorted(rng.sample(["actor-a", "actor-b", "actor-c"], rng.randint(1, 2))),
                "location": rng.choice(["studio", "courtyard"]),
                "allowed_slots": sorted({witness[i], *rng.sample(range(6), 2)}),
                "priority": rng.randint(1, 4)})
        order = sorted(range(6), key=lambda i: witness[i])
        task = {"id": f"synthetic-{n:03d}", "revision": 1, "slots": 6,
            "scenes": scenes, "precedence": [[f"scene-{order[0]}", f"scene-{order[-1]}"]],
            "synthetic": True, "duration_slots": 1}
        if n % 4 == 3:
            # Deliberately unsatisfiable: two scenes require one actor at one time.
            task["scenes"][0]["actors"] = ["actor-a"]
            task["scenes"][1]["actors"] = ["actor-a"]
            task["scenes"][0]["allowed_slots"] = [0]
            task["scenes"][1]["allowed_slots"] = [0]
        tasks.append(task)
    return tasks


def validate_schedule(task: dict, assignment: Any) -> dict:
    """Direct domain checks. Never reads model energy, confidence, or self-report."""
    context = validate_task(task)
    if context["status"] != "PASS":
        return context
    if type(assignment) is not dict:
        return {"status": "FAIL", "reasons": ["assignment_not_object"]}
    expected = {s["id"] for s in task["scenes"]}
    if set(assignment) != expected:
        return {"status": "FAIL", "reasons": ["scene_set_mismatch"]}
    reasons = []
    occupied: dict[tuple, str] = {}
    for scene in task["scenes"]:
        sid = scene["id"]
        slot = assignment[sid]
        if type(slot) is not int or slot not in scene["allowed_slots"]:
            reasons.append(f"availability:{sid}")
            continue
        resources = [("actor", a) for a in scene["actors"]] + [("location", scene["location"])]
        for kind, resource in resources:
            key = (kind, resource, slot)
            if key in occupied:
                reasons.append(f"overlap:{kind}:{resource}:{occupied[key]}:{sid}")
            occupied[key] = sid
    for before, after in task["precedence"]:
        a, b = assignment[before], assignment[after]
        if type(a) is not int or type(b) is not int or a >= b:
            reasons.append(f"precedence:{before}:{after}")
    return {"status": "FAIL" if reasons else "PASS", "reasons": reasons}


def cost(task: dict, assignment: dict) -> float:
    denom = max(1, task["slots"] - 1) * sum(s["priority"] for s in task["scenes"])
    return sum(s["priority"] * assignment[s["id"]] for s in task["scenes"]) / denom


def exact_reference(task: dict) -> dict:
    if validate_task(task)["status"] != "PASS":
        raise ValueError("invalid scheduling context")
    start = time.perf_counter()
    best = None
    best_cost = float("inf")
    considered = 0
    ids = [s["id"] for s in task["scenes"]]
    for values in itertools.product(*(s["allowed_slots"] for s in task["scenes"])):
        considered += 1
        candidate = dict(zip(ids, values))
        if validate_schedule(task, candidate)["status"] != "PASS":
            continue
        score = cost(task, candidate)
        if score < best_cost:
            best, best_cost = candidate, score
    return {"assignment": best, "valid": best is not None,
        "cost": best_cost if best is not None else None,
        "status": "OPTIMAL" if best is not None else "UNSAT",
        "considered": considered, "elapsed_seconds": time.perf_counter() - start}


def compile_energy(task: dict, penalty: float):
    """Compile pair costs independently from validate_schedule's resource checks."""
    if validate_task(task)["status"] != "PASS":
        raise ValueError("invalid scheduling context")
    scenes = task["scenes"]
    ids = {s["id"]: i for i, s in enumerate(scenes)}
    pairs = []
    for i, left in enumerate(scenes):
        for j in range(i + 1, len(scenes)):
            right = scenes[j]
            clashes = len(set(left["actors"]).intersection(right["actors"]))
            clashes += int(left["location"] == right["location"])
            if clashes:
                pairs.append((i, j, clashes))
    edges = [(ids[a], ids[b]) for a, b in task["precedence"]]
    weights = [s["priority"] / (max(1, task["slots"] - 1) * sum(t["priority"] for t in scenes)) for s in scenes]

    def energy(values):
        violation = sum(k for i, j, k in pairs if values[i] == values[j])
        violation += sum(values[i] >= values[j] for i, j in edges)
        violation += sum(values[i] not in scenes[i]["allowed_slots"] for i in range(len(scenes)))
        return sum(w * v for w, v in zip(weights, values)) + penalty * violation
    return energy


def search_energy(task: dict, *, seed: int, penalty: float, chains: int = 8, sweeps: int = 32) -> dict:
    """Bounded coordinate descent; termination does not consult the validator."""
    start = time.perf_counter()
    rng = random.Random(seed)
    energy = compile_energy(task, penalty)
    best, best_e = None, float("inf")
    moves, evaluations = 0, 0
    chain_stops = []
    best_origin = None
    for chain in range(chains):
        values = [rng.choice(s["allowed_slots"]) for s in task["scenes"]]
        chain_stop = "budget_exhausted"
        for sweep in range(sweeps):
            changed = False
            cells = list(range(len(values)))
            rng.shuffle(cells)
            for i in cells:
                old = values[i]
                candidates = []
                for value in task["scenes"][i]["allowed_slots"]:
                    values[i] = value
                    candidates.append((energy(values), value))
                    evaluations += 1
                score, chosen = min(candidates)
                values[i] = chosen
                changed |= chosen != old
                moves += 1
                if score < best_e:
                    best_e, best = score, values.copy()
                    best_origin = {"chain": chain, "sweep": sweep, "cell": i}
            if not changed:
                chain_stop = "coordinate_fixed_point"
                break
        chain_stops.append(chain_stop)
    return {"assignment": dict(zip((s["id"] for s in task["scenes"]), best)),
        "energy": best_e, "stopping_reason": "all_chains_completed", "moves": moves,
        "chain_stopping_reasons": chain_stops, "returned_candidate_origin": best_origin,
        "energy_evaluations": evaluations, "seed": seed, "penalty": penalty,
        "elapsed_seconds": time.perf_counter() - start}


def run_scheduling(tasks: list[dict], *, chains: int = 8, sweeps: int = 32) -> dict:
    rows = []
    summary = {name: {"cases": 0, "valid": 0, "invalid": 0, "elapsed_seconds": 0.0,
                      "valid_on_feasible": 0, "optimal_on_feasible": 0}
        for name in ("exact_reference", "energy_penalty_10", "energy_penalty_0_01")}
    feasible = 0
    for i, task in enumerate(tasks):
        oracle = exact_reference(task)
        feasible += int(oracle["valid"])
        candidates = {"exact_reference": oracle,
            "energy_penalty_10": search_energy(task, seed=1000+i, penalty=10.0, chains=chains, sweeps=sweeps),
            "energy_penalty_0_01": search_energy(task, seed=1000+i, penalty=0.01, chains=chains, sweeps=sweeps)}
        for name, result in candidates.items():
            validation = validate_schedule(task, result["assignment"])
            valid = validation["status"] == "PASS"
            entry = summary[name]
            entry["cases"] += 1
            entry["valid"] += int(valid)
            entry["invalid"] += int(not valid and result["assignment"] is not None)
            entry["elapsed_seconds"] += result["elapsed_seconds"]
            entry["valid_on_feasible"] += int(valid and oracle["valid"])
            optimal = valid and abs(cost(task, result["assignment"])-oracle["cost"]) < 1e-12
            entry["optimal_on_feasible"] += int(optimal)
            rows.append({"task_id": task["id"], "task_hash": digest(task), "method": name,
                "result": result, "validator": validation, "reference_feasible": oracle["valid"],
                "optimal": optimal})
    return {"kind": "synthetic_scheduling_hand_set_energy_probe", "official_cram": False,
        "integration": "none", "feasible_tasks": feasible, "unsatisfiable_tasks": len(tasks)-feasible,
        "task_manifest_hash": digest(tasks), "summary": summary, "records": rows}
