"""Portable learned-energy probe; independently authored, not official CRAM.

This finite 4x4 Sudoku experiment uses NumPy pseudolikelihood training. The
model and sampler receive opaque cell indices and categorical values only.
Sudoku rules appear exclusively in data generation and the separate oracle.
No inference path is differentiated, and no correctness checker is used to
stop learned search. This is not a 9x9 paper reproduction or GPU benchmark.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import time
from pathlib import Path
from typing import Any

import numpy as np

CELL_COUNT = 16
VALUE_COUNT = 4
SEED = 261117309
MODEL_SEED = 8701
SEARCH_SEED = 9019
TRAIN_SIZE = 128
DEV_SIZE = 32
TEST_COUNT = 64
LOW_DATA_SIZE = 4
CONFIG = {
    "steps": 320,
    "learning_rate": 4.0,
    "momentum": 0.5,
    "l1": 0.0005,
    "chains": 4,
    "moves_per_chain": 512,
    "temperature_start_scale": 0.45,
    "temperature_end_scale": 0.08,
    "target_clues": 6,
}


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      allow_nan=False).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def all_solutions() -> list[list[int]]:
    """Enumerate solved boards by row/column/box occupancy (data generation)."""
    board = [0] * 16
    rows, cols, boxes = [0] * 4, [0] * 4, [0] * 4
    answers: list[list[int]] = []

    def visit(position: int) -> None:
        if position == 16:
            answers.append(board.copy())
            return
        row, col = divmod(position, 4)
        box = (row // 2) * 2 + col // 2
        permitted = 15 & ~(rows[row] | cols[col] | boxes[box])
        for digit in range(1, 5):
            bit = 1 << (digit - 1)
            if permitted & bit:
                board[position] = digit
                rows[row] |= bit
                cols[col] |= bit
                boxes[box] |= bit
                visit(position + 1)
                rows[row] ^= bit
                cols[col] ^= bit
                boxes[box] ^= bit
        board[position] = 0

    visit(0)
    if len(answers) != 288:
        raise AssertionError("Expected all 288 valid 4x4 Sudoku solutions")
    return answers


def validate_board(clues: list[int], answer: list[int]) -> dict[str, Any]:
    """Independent set-based validity check; no learned energy is consulted."""
    errors: list[str] = []
    if not isinstance(clues, list) or not isinstance(answer, list) or len(clues) != 16 or len(answer) != 16:
        return {"status": "FAIL", "valid": False, "errors": ["shape"]}
    if any(type(v) is not int or v not in range(5) for v in clues):
        return {"status": "FAIL", "valid": False, "errors": ["clue_domain"]}
    if any(type(v) is not int or v not in range(1, 5) for v in answer):
        return {"status": "FAIL", "valid": False, "errors": ["value_domain"]}
    if any(c and answer[i] != c for i, c in enumerate(clues)):
        errors.append("changed_clue")
    wanted = {1, 2, 3, 4}
    for row in range(4):
        if set(answer[4 * row:4 * row + 4]) != wanted:
            errors.append(f"row_{row}")
    for col in range(4):
        if {answer[4 * row + col] for row in range(4)} != wanted:
            errors.append(f"column_{col}")
    for top in (0, 2):
        for left in (0, 2):
            if {answer[4 * row + col] for row in (top, top + 1)
                    for col in (left, left + 1)} != wanted:
                errors.append(f"box_{top}_{left}")
    return {"status": "FAIL" if errors else "PASS", "valid": not errors,
            "errors": errors}


def exact_solve(clues: list[int], limit: int = 2) -> list[list[int]]:
    """Independent MRV backtracking oracle, with explicit constraints."""
    if len(clues) != 16 or any(type(v) is not int or v not in range(5)
                               for v in clues):
        return []
    board = clues.copy()
    result: list[list[int]] = []
    groups = [list(range(4 * r, 4 * r + 4)) for r in range(4)]
    groups += [[4 * r + c for r in range(4)] for c in range(4)]
    groups += [[4 * r + c for r in (top, top + 1)
                for c in (left, left + 1)]
               for top in (0, 2) for left in (0, 2)]
    for group in groups:
        values = [board[i] for i in group if board[i]]
        if len(values) != len(set(values)):
            return []
    peers = [set().union(*(set(g) for g in groups if i in g)) - {i}
             for i in range(16)]

    def visit() -> None:
        if len(result) >= limit:
            return
        choices = [(i, set(range(1, 5)) - {board[j] for j in peers[i]})
                   for i in range(16) if board[i] == 0]
        if not choices:
            result.append(board.copy())
            return
        cell, candidates = min(choices, key=lambda pair: (len(pair[1]), pair[0]))
        for candidate in sorted(candidates):
            board[cell] = candidate
            visit()
            board[cell] = 0
            if len(result) >= limit:
                return

    visit()
    return result


def make_puzzles(solutions: list[list[int]], seed: int) -> list[dict[str, Any]]:
    """Delete clues while retaining exactly one solution; no learned model."""
    rng = np.random.default_rng(seed)
    result = []
    for row, solution in enumerate(solutions):
        clues = solution.copy()
        for cell in rng.permutation(16):
            if sum(v != 0 for v in clues) <= CONFIG["target_clues"]:
                break
            old = clues[int(cell)]
            clues[int(cell)] = 0
            possible = exact_solve(clues, limit=2)
            if len(possible) != 1:
                clues[int(cell)] = old
        solved = exact_solve(clues, limit=2)
        if solved != [solution]:
            raise AssertionError("Puzzle must uniquely recover its held-out solution")
        result.append({"id": f"puzzle-{row:03d}", "clues": clues,
                       "solution": solution, "clue_count": sum(v != 0 for v in clues)})
    return result


class PairwiseEnergy:
    """Dense categorical pair costs; no spatial Sudoku structure is supplied."""

    def __init__(self, cells: int = CELL_COUNT, values: int = VALUE_COUNT) -> None:
        self.cells, self.values = cells, values
        self.left, self.right = np.triu_indices(cells, 1)
        self.pairs = np.zeros((len(self.left), values, values), dtype=np.float64)
        self.bias = np.zeros((cells, values), dtype=np.float64)
        self.threshold = 0.0

    def full_costs(self) -> np.ndarray:
        costs = np.zeros((self.cells, self.cells, self.values, self.values))
        costs[self.left, self.right] = self.pairs
        costs[self.right, self.left] = self.pairs.transpose(0, 2, 1)
        return costs

    def fields(self, boards: np.ndarray) -> np.ndarray:
        encoded = np.eye(self.values)[boards]
        return self.bias + np.einsum("ijab,njb->nia", self.full_costs(), encoded,
                                     optimize=False)

    def energy(self, board: np.ndarray) -> float:
        return float(self.bias[np.arange(self.cells), board].sum()
                     + self.pairs[np.arange(len(self.left)), board[self.left],
                                  board[self.right]].sum())

    def loss_gradient(self, boards: np.ndarray) -> tuple[float, np.ndarray, np.ndarray]:
        fields = self.fields(boards)
        logits = -fields
        logits -= logits.max(axis=-1, keepdims=True)
        probabilities = np.exp(logits)
        probabilities /= probabilities.sum(axis=-1, keepdims=True)
        selected = probabilities[np.arange(len(boards))[:, None],
                                 np.arange(self.cells), boards]
        loss = float(-np.log(np.maximum(selected, 1e-300)).mean())
        encoded = np.eye(self.values)[boards]
        delta = (encoded - probabilities) / (len(boards) * self.cells)
        directed = np.einsum("nia,njb->ijab", delta, encoded, optimize=False)
        gradient = (directed[self.left, self.right]
                    + directed[self.right, self.left].transpose(0, 2, 1))
        return loss, gradient, delta.sum(axis=0)

    def fit(self, boards: np.ndarray) -> dict[str, Any]:
        start = time.perf_counter()
        velocity_pairs = np.zeros_like(self.pairs)
        velocity_bias = np.zeros_like(self.bias)
        initial = self.loss_gradient(boards)[0]
        for step in range(CONFIG["steps"]):
            _, pair_grad, bias_grad = self.loss_gradient(boards)
            rate = CONFIG["learning_rate"] * 0.5 * (
                1 + math.cos(math.pi * step / CONFIG["steps"]))
            velocity_pairs = CONFIG["momentum"] * velocity_pairs + pair_grad
            velocity_bias = CONFIG["momentum"] * velocity_bias + bias_grad
            self.pairs -= rate * velocity_pairs
            self.bias -= rate * velocity_bias
            # Proximal L1 applies to unique pair parameters and unary biases.
            self.pairs = np.sign(self.pairs) * np.maximum(
                np.abs(self.pairs) - rate * CONFIG["l1"], 0.0)
            self.bias = np.sign(self.bias) * np.maximum(
                np.abs(self.bias) - rate * CONFIG["l1"], 0.0)
        train_energies = [self.energy(board) for board in boards]
        self.threshold = max(train_energies) + 1e-8
        if not np.isfinite(self.pairs).all() or not np.isfinite(self.bias).all():
            raise FloatingPointError("Nonfinite learned parameters")
        final = self.loss_gradient(boards)[0]
        return {"fit_seconds": time.perf_counter() - start,
                "initial_pseudolikelihood": initial,
                "final_pseudolikelihood": final,
                "train_threshold": self.threshold,
                "train_energy_min": min(train_energies),
                "train_energy_max": max(train_energies),
                "trainable_parameters": int(self.pairs.size + self.bias.size),
                "nonzero_parameters": int(np.count_nonzero(self.pairs)
                                          + np.count_nonzero(self.bias))}

    def search(self, clues: list[int], seed: int) -> dict[str, Any]:
        """Search using the learned score only; validator is outside this method."""
        start = time.perf_counter()
        rng = np.random.default_rng(seed)
        given = np.asarray(clues, dtype=np.int64)
        if given.shape != (self.cells,) or ((given < 0) | (given > self.values)).any():
            raise ValueError("Candidate shape/domain mismatch")
        free = np.flatnonzero(given == 0)
        chain_count = CONFIG["chains"]
        states = rng.integers(0, self.values, (chain_count, self.cells))
        states[:, given != 0] = given[given != 0] - 1
        costs = self.full_costs()
        fields = self.fields(states)
        energies = np.array([self.energy(state) for state in states])
        best_index = int(np.argmin(energies))
        best_state, best_energy = states[best_index].copy(), float(energies[best_index])
        scale = float(np.mean(np.abs(self.pairs[self.pairs != 0]))) if np.any(self.pairs) else 1.0
        moves = 0
        reason = "budget_exhausted"
        chosen = best_state

        for sweep in range(CONFIG["moves_per_chain"] + 1):
            stopped = np.flatnonzero(energies <= self.threshold)
            if len(stopped):
                chosen = states[int(stopped[0])].copy()
                reason = "energy_threshold"
                break
            if sweep == CONFIG["moves_per_chain"] or not len(free):
                chosen = best_state.copy()
                break
            fraction = sweep / max(1, CONFIG["moves_per_chain"] - 1)
            temperature = scale * CONFIG["temperature_start_scale"] * (
                CONFIG["temperature_end_scale"] / CONFIG["temperature_start_scale"]
            ) ** fraction
            for chain in range(chain_count):
                regrets = fields[chain, free, states[chain, free]] - fields[chain, free].min(axis=1)
                active = free[regrets > 1e-10]
                cell = int(rng.choice(active if len(active) else free))
                logits = -fields[chain, cell] / max(temperature, 1e-8)
                probabilities = np.exp(logits - logits.max())
                probabilities /= probabilities.sum()
                new = int(rng.choice(self.values, p=probabilities))
                old = int(states[chain, cell])
                if new != old:
                    energies[chain] += fields[chain, cell, new] - fields[chain, cell, old]
                    states[chain, cell] = new
                    fields[chain] += costs[:, cell, :, new] - costs[:, cell, :, old]
                moves += 1
                if energies[chain] < best_energy:
                    best_energy = float(energies[chain])
                    best_state = states[chain].copy()
            # Recompute exactly to prevent cached rounding drift at threshold.
            if sweep % 32 == 31:
                fields = self.fields(states)
                energies = np.array([self.energy(state) for state in states])
        final_energy = self.energy(chosen)
        return {"candidate": (chosen + 1).tolist(), "energy": final_energy,
                "threshold": self.threshold, "termination": reason,
                "moves": moves, "chains": chain_count,
                "search_seed": seed, "inference_seconds": time.perf_counter() - start,
                "threshold_passed": final_energy <= self.threshold}

    def snapshot(self) -> dict[str, Any]:
        return {"cells": self.cells, "values": self.values,
                "left": self.left.tolist(), "right": self.right.tolist(),
                "pairs": self.pairs.tolist(), "bias": self.bias.tolist(),
                "threshold": self.threshold}


def verify_gradient() -> dict[str, Any]:
    """Finite differences on an arbitrary dense model, away from L1 kinks."""
    rng = np.random.default_rng(MODEL_SEED)
    model = PairwiseEnergy(cells=3, values=3)
    model.pairs[:] = rng.normal(0, 0.2, model.pairs.shape)
    model.bias[:] = rng.normal(0, 0.2, model.bias.shape)
    boards = rng.integers(0, 3, size=(7, 3))
    _, pair_gradient, bias_gradient = model.loss_gradient(boards)
    max_error = 0.0
    count = 0
    for params, gradient in ((model.pairs, pair_gradient), (model.bias, bias_gradient)):
        for index in list(np.ndindex(params.shape))[:12]:
            old = params[index]
            params[index] = old + 1e-6
            plus = model.loss_gradient(boards)[0]
            params[index] = old - 1e-6
            minus = model.loss_gradient(boards)[0]
            params[index] = old
            numerical = (plus - minus) / 2e-6
            max_error = max(max_error, abs(numerical - gradient[index]))
            count += 1
    if max_error > 1e-7:
        raise AssertionError(f"Pseudolikelihood gradient failed: {max_error}")
    return {"status": "PASS", "checked_entries": count,
            "maximum_absolute_error": max_error, "tolerance": 1e-7}


def verify_energy_deltas() -> dict[str, Any]:
    """Compare local-field differences with full independent energy recomputation."""
    rng = np.random.default_rng(MODEL_SEED + 1)
    model = PairwiseEnergy()
    model.pairs[:] = rng.normal(size=model.pairs.shape)
    model.bias[:] = rng.normal(size=model.bias.shape)
    largest = 0.0
    for _ in range(32):
        board = rng.integers(0, VALUE_COUNT, size=CELL_COUNT)
        fields = model.fields(board[None, :])[0]
        cell, value = int(rng.integers(CELL_COUNT)), int(rng.integers(VALUE_COUNT))
        changed = board.copy()
        changed[cell] = value
        difference = model.energy(changed) - model.energy(board)
        local_difference = fields[cell, value] - fields[cell, board[cell]]
        largest = max(largest, abs(difference - local_difference))
    if largest > 1e-10:
        raise AssertionError("Local-field deltas disagree with full energy")
    return {"status": "PASS", "checked_changes": 32,
            "maximum_absolute_error": largest, "tolerance": 1e-10}


def frozen_data() -> dict[str, Any]:
    solutions = all_solutions()
    permutation = np.random.default_rng(SEED).permutation(len(solutions))
    shuffled = [solutions[int(i)] for i in permutation]
    train = shuffled[:TRAIN_SIZE]
    dev = shuffled[TRAIN_SIZE:TRAIN_SIZE + DEV_SIZE]
    test = shuffled[TRAIN_SIZE + DEV_SIZE:]
    train_set, dev_set, test_set = map(lambda xs: {tuple(x) for x in xs}, (train, dev, test))
    if train_set & dev_set or train_set & test_set or dev_set & test_set:
        raise AssertionError("Solution splits must not overlap")
    puzzles = make_puzzles(test[:TEST_COUNT], SEED + 1)
    if len({tuple(p["clues"]) for p in puzzles}) != len(puzzles):
        raise AssertionError("Duplicate evaluation inputs")
    return {"train": train, "development": dev, "test": test,
            "evaluation_puzzles": puzzles,
            "split_hashes": {name: digest(rows) for name, rows in
                             (("train", train), ("development", dev), ("test", test))}}


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    valid = sum(row["validation"]["valid"] for row in rows)
    halted = [row for row in rows if row["termination"] == "energy_threshold"]
    seconds = sum(row["inference_seconds"] + row["validation_seconds"] for row in rows)
    return {"puzzles": len(rows), "valid_candidates": valid,
            "invalid_candidates": len(rows) - valid,
            "energy_threshold_stops": len(halted),
            "invalid_energy_threshold_stops": sum(not r["validation"]["valid"] for r in halted),
            "budget_exhaustions": sum(r["termination"] == "budget_exhausted" for r in rows),
            "search_seconds": sum(r["inference_seconds"] for r in rows),
            "validation_seconds": sum(r["validation_seconds"] for r in rows),
            "valid_candidates_per_second_including_validation": valid / seconds if seconds else None,
            "median_inference_seconds": float(np.median([r["inference_seconds"] for r in rows])),
            "p95_inference_seconds": float(np.quantile([r["inference_seconds"] for r in rows], .95)),
            "maximum_inference_seconds": max(r["inference_seconds"] for r in rows),
            "maximum_moves": max(r.get("moves", 0) for r in rows)}


def run_probe(output_dir: Path) -> dict[str, Any]:
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError("Refusing to overwrite previous probe evidence; choose a fresh output directory")
    output_dir.mkdir(parents=True, exist_ok=True)
    start = time.perf_counter()
    gradient_check = verify_gradient()
    delta_check = verify_energy_deltas()
    data = frozen_data()
    protocol = {
        "title": "Independently authored CPU 4x4 learned pairwise-energy probe",
        "official_cram_reproduction": False,
        "status": "FROZEN_PROTOCOL",
        "source_paper": "https://arxiv.org/abs/2611.17309v1",
        "method": "Dense pairwise categorical energy; analytical pseudolikelihood; proximal L1; noisy local search",
        "model_knows_sudoku_geometry": False,
        "search_uses_validity_oracle": False,
        "seeds": {"solution_split": SEED, "puzzle_masks": SEED + 1,
                  "gradient_probe": MODEL_SEED, "search_base": SEARCH_SEED},
        "config": CONFIG, "training_counts": {"normal": TRAIN_SIZE, "low_data": LOW_DATA_SIZE},
        "split_hashes": data["split_hashes"], "test_count": TEST_COUNT,
        "solution_split_sizes": {"train": len(data["train"]), "development": len(data["development"]),
                                 "test": len(data["test"])},
        "oracle": "Independent constraint-aware MRV backtracking; set-based final validator",
        "stopping": "Energy <= max training-solution energy + 1e-8, or fixed move budget",
        "protocol_claim": "Configuration is written before fitting/evaluation in this run; no external preregistration",
        "primary_outcomes": ["independently valid candidate count", "invalid energy-threshold stops",
                             "fit and search wall-clock cost"],
        "quality_target": "Descriptive comparison only; no threshold declaring model quality acceptable",
        "source_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "environment": {"python": platform.python_version(), "numpy": np.__version__,
                        "platform": platform.platform(), "device": "CPU"},
        "limitations": ["Tiny synthetic 4x4 task; no claim about 9x9 Sudoku-Extreme or Maze-Unique",
                        "All examples share one rule family; split is by solved board, not rule or symmetry family",
                        "No GPU timing, electricity measurement, or official CRAM weights",
                        "No user application state or production ARCHi adapter is changed",
                        "CPU timing is implementation-specific and not comparable to the paper's H200 timing"],
    }
    (output_dir / "protocol.json").write_text(json.dumps(protocol, indent=2) + "\n")
    (output_dir / "frozen_inputs.json").write_text(json.dumps(data, indent=2) + "\n")
    all_rows: list[dict[str, Any]] = []
    summaries: dict[str, Any] = {}
    for name, training in (("learned_energy_128", data["train"]),
                           ("learned_energy_4", data["train"][:LOW_DATA_SIZE])):
        model = PairwiseEnergy()
        training_metrics = model.fit(np.asarray(training, dtype=np.int64) - 1)
        snapshot = model.snapshot()
        (output_dir / f"{name}_weights.json").write_text(json.dumps(snapshot) + "\n")
        rows = []
        for number, puzzle in enumerate(data["evaluation_puzzles"]):
            row = {"method": name, "puzzle_id": puzzle["id"], "clues": puzzle["clues"],
                   "expected_unique_solution": puzzle["solution"],
                   "model_sha256": digest(snapshot),
                   **model.search(puzzle["clues"], SEARCH_SEED + number)}
            validate_start = time.perf_counter()
            row["validation"] = validate_board(puzzle["clues"], row["candidate"])
            row["validation_seconds"] = time.perf_counter() - validate_start
            row["exact_match"] = row["candidate"] == puzzle["solution"]
            if row["validation"]["valid"] != row["exact_match"]:
                raise AssertionError("Unique-puzzle oracle and independent validator disagree")
            rows.append(row)
        summaries[name] = {**summarize(rows), "training": training_metrics}
        all_rows.extend(rows)
    exact_rows = []
    for puzzle in data["evaluation_puzzles"]:
        infer_start = time.perf_counter()
        answers = exact_solve(puzzle["clues"], limit=1)
        elapsed = time.perf_counter() - infer_start
        candidate = answers[0] if answers else [0] * 16
        validate_start = time.perf_counter()
        validation = validate_board(puzzle["clues"], candidate)
        validation_seconds = time.perf_counter() - validate_start
        exact_rows.append({"method": "exact_mrv", "puzzle_id": puzzle["id"],
                           "clues": puzzle["clues"], "candidate": candidate,
                           "expected_unique_solution": puzzle["solution"],
                           "termination": "exact_solution" if answers else "unsatisfiable",
                           "validation": validation, "inference_seconds": elapsed,
                           "validation_seconds": validation_seconds,
                           "exact_match": candidate == puzzle["solution"]})
    summaries["exact_mrv"] = summarize(exact_rows)
    all_rows.extend(exact_rows)
    (output_dir / "raw_candidates.jsonl").write_text(
        "".join(json.dumps(row, sort_keys=True, allow_nan=False) + "\n" for row in all_rows))
    result = {"protocol_sha256": digest(protocol), "data_sha256": digest(data),
              "execution_status": "COMPLETED",
              "gradient_check": gradient_check, "energy_delta_check": delta_check,
              "methods": summaries,
              "elapsed_seconds": time.perf_counter() - start,
              "official_cram_reproduction": "NOT_RUN_BY_THIS_CPU_PROBE",
              "native_archi_integration": "UNEXECUTED"}
    (output_dir / "summary.json").write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("energy_probe_results"))
    args = parser.parse_args()
    print(json.dumps(run_probe(args.output), indent=2, allow_nan=False))
