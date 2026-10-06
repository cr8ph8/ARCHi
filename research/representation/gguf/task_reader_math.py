"""Bounded group-balanced ridge fitting for supplied prompt-final residuals.

No I/O, model invocation, holdout access, or qualification decision occurs here.
Inputs are raw 4096-wide residuals; the caller owns source identity, task labels,
group independence, split integrity and the acquisition/token/layer protocol.

For each training fold, c = mean(X_raw), X = X_raw - c, K = X X.T,
alpha = strength * trace(K) / n, a = solve(K + alpha I, y), and w = X.T a.
This minimizes ||Xw-y||^2 + alpha ||w||^2. Each group has exactly two rows,
one per label, so every group receives equal weight. Equivalently its data term
is twice the sum over groups of (w.d-1)^2 + (w.(m-c))^2, where d=(x+-x-)/2
and m=(x++x-)/2. No per-group center is subtracted at inference time.

Whole-pair cross-validation uses only FIT rows, recomputing c and alpha inside
every fold. Selection minimizes the total number of held-FIT-row errors;
zero-margin predictions count as errors. Ties prefer the larger strength
(therefore larger alpha for the same training matrix). Fit all FIT rows once
at the chosen strength, then normalize w. Calibration sets only the offset
(min positive score + max negative score)/2 and population standard deviation.
Overlapping or constant calibration scores are returned for caller diagnostics;
they are not repaired, silently reoriented, or declared qualified.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Sequence

import numpy as np
from numpy.typing import ArrayLike, NDArray


ALGORITHM = "group-balanced-ridge/v1"
HIDDEN_WIDTH = 4096
MAXIMUM_FIT_ROWS = 128
MAXIMUM_CALIBRATION_ROWS = 128
RIDGE_STRENGTHS = (0.01, 0.1, 1.0, 10.0)
FloatArray = NDArray[np.float64]


@dataclass(frozen=True)
class RidgeReaderFit:
    direction: FloatArray
    center: FloatArray
    score_offset: float
    score_scale: float
    calibration_scores: FloatArray
    calibration_separation: float
    selected_strength: float
    selected_alpha: float
    # Plain finite JSON-compatible values; contains FIT groups only.
    cv_summary: tuple[dict, ...]


def _finite(value: FloatArray, name: str) -> FloatArray:
    if not np.isfinite(value).all():
        raise ValueError(name + " must contain only finite numbers")
    return value


def _matrix(value: ArrayLike, name: str, maximum: int) -> FloatArray:
    try:
        raw = np.asarray(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(name + " must be a rectangular numeric matrix") from exc
    if (raw.ndim != 2 or raw.shape[1] != HIDDEN_WIDTH
            or not 2 <= raw.shape[0] <= maximum
            or raw.dtype.kind not in "iuf"):
        raise ValueError(name + f" must have 2–{maximum} numeric rows of width {HIDDEN_WIDTH}")
    return _finite(np.array(raw, dtype=np.float64, copy=True), name)


def _labels(value: ArrayLike, count: int, name: str) -> FloatArray:
    raw = np.asarray(value)
    if raw.shape != (count,) or raw.dtype.kind not in "iuf":
        raise ValueError(name + " must be one numeric label per row")
    result = _finite(np.array(raw, dtype=np.float64, copy=True), name)
    if not np.isin(result, (-1.0, 1.0)).all() or set(result.tolist()) != {-1.0, 1.0}:
        raise ValueError(name + " must contain both -1 and +1, and no other labels")
    return result


def _freeze(value: FloatArray) -> FloatArray:
    result = np.array(value, dtype=np.float64, copy=True)
    result.setflags(write=False)
    return result


def _solve(hidden: FloatArray, labels: FloatArray, strength: float) -> tuple[FloatArray, FloatArray, float]:
    try:
        with np.errstate(over="raise", invalid="raise", divide="raise", under="ignore"):
            center = _finite(hidden.mean(axis=0), "fit center")
            design = _finite(hidden - center, "centered fit rows")
            gram = _finite(design @ design.T, "fit Gram matrix")
            energy = float(np.trace(gram) / len(hidden))
            alpha = strength * energy
            if not math.isfinite(alpha) or alpha <= 0:
                raise ValueError("FIT rows have no finite positive centered energy")
            coefficients = np.linalg.solve(gram + alpha * np.eye(len(hidden)), labels)
            weight = _finite(design.T @ coefficients, "ridge direction")
    except (FloatingPointError, np.linalg.LinAlgError) as exc:
        raise ValueError("Ridge fit could not produce finite stable coefficients") from exc
    return weight, center, alpha


def fit_ridge_reader(fit_hidden: ArrayLike, fit_labels: ArrayLike, fit_groups: Sequence[str],
                     calibration_hidden: ArrayLike, calibration_labels: ArrayLike) -> RidgeReaderFit:
    """Fit one unit direction with FIT-only selection, then calibrate its scale.

    FIT has 2–64 groups, each exactly a matched positive/negative pair. The
    returned calibration scale can be zero: its raw diagnostics remain useful,
    but the caller must not divide by that value or admit a standardized reader.
    Calibration input order is retained in calibration_scores. FIT order is
    canonicalized by group and label so caller row order cannot change ties.
    """
    hidden = _matrix(fit_hidden, "FIT residuals", MAXIMUM_FIT_ROWS)
    labels = _labels(fit_labels, len(hidden), "FIT labels")
    if isinstance(fit_groups, (str, bytes)):
        raise ValueError("FIT groups must identify one pair per group")
    groups = list(fit_groups)
    if len(groups) != len(hidden) or any(
        not isinstance(group, str) or not group or len(group.encode("utf-8")) > 128
        or any(ord(character) < 32 or ord(character) == 127 for character in group)
        for group in groups
    ):
        raise ValueError("FIT groups must be bounded nonempty strings, one per row")
    names = sorted(set(groups))
    if len(names) < 2:
        raise ValueError("Grouped cross-validation requires at least two FIT pairs")
    for name in names:
        pair = [index for index, group in enumerate(groups) if group == name]
        if len(pair) != 2 or set(labels[pair].tolist()) != {-1.0, 1.0}:
            raise ValueError("Every FIT group must contain exactly one positive and one negative row")
    order = sorted(range(len(groups)), key=lambda index: (groups[index], labels[index]))
    hidden = hidden[order]
    labels = labels[order]
    groups = [groups[index] for index in order]
    calibration = _matrix(calibration_hidden, "calibration residuals", MAXIMUM_CALIBRATION_ROWS)
    cal_labels = _labels(calibration_labels, len(calibration), "calibration labels")

    summaries = []
    for strength in RIDGE_STRENGTHS:
        folds = []
        mistakes = 0
        for name in names:
            held = np.asarray([group == name for group in groups], dtype=bool)
            weight, center, alpha = _solve(hidden[~held], labels[~held], strength)
            try:
                with np.errstate(over="raise", invalid="raise"):
                    scores = _finite((hidden[held] - center) @ weight, "held FIT scores")
            except FloatingPointError as exc:
                raise ValueError("Held FIT scores overflowed") from exc
            errors = int(np.count_nonzero(labels[held] * scores <= 0))
            mistakes += errors
            folds.append({"heldGroup": name, "trainingGroupCount": len(names) - 1,
                          "heldLabels": [int(x) for x in labels[held]],
                          "heldScores": scores.tolist(), "alpha": alpha, "misclassified": errors})
        summaries.append({"strength": strength, "misclassified": mistakes,
                          "sampleCount": len(hidden), "folds": folds})
    selected = min(summaries, key=lambda item: (item["misclassified"], -item["strength"]))
    strength = selected["strength"]
    weight, center, alpha = _solve(hidden, labels, strength)
    norm = float(np.linalg.norm(weight))
    if not math.isfinite(norm) or norm <= 1e-12:
        raise ValueError("Fitted ridge direction has zero or nonfinite norm")
    direction = _finite(weight / norm, "unit ridge direction")
    try:
        with np.errstate(over="raise", invalid="raise", divide="raise"):
            scores = _finite((calibration - center) @ direction, "calibration scores")
            minimum_positive = float(np.min(scores[cal_labels == 1]))
            maximum_negative = float(np.max(scores[cal_labels == -1]))
            separation = minimum_positive - maximum_negative
            offset = minimum_positive / 2 + maximum_negative / 2
            scale = float(np.std(scores, ddof=0))
    except FloatingPointError as exc:
        raise ValueError("Calibration arithmetic overflowed") from exc
    if not all(math.isfinite(x) for x in (offset, scale, separation)):
        raise ValueError("Calibration diagnostics must be finite")
    return RidgeReaderFit(direction=_freeze(direction), center=_freeze(center),
                          score_offset=offset, score_scale=scale, calibration_scores=_freeze(scores),
                          calibration_separation=separation, selected_strength=strength,
                          selected_alpha=alpha, cv_summary=tuple(summaries))
