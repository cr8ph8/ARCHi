"""Local numerical proposals for QI-ARCHI-REPE-2026-09-25-R1.

These functions operate on caller-supplied NumPy-compatible real arrays. They do
not extract model activations, establish a model/basis identity, measure general
intelligence, verify outcomes, or apply state to an ARCHi owner. All arrays are
copied into float64; returned arrays are read-only snapshots. Non-finite inputs,
invalid dimensions, and non-finite arithmetic fail with ``ValueError``.

An unavailable measurement has ``available=False`` and an explicit reason.
Numerical tolerances below handle arithmetic and degeneracy, not experimental
acceptance thresholds. Calibration, model qualification, and independent outcome
review belong to the caller. No model files or trained directions are shipped.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Literal

import numpy as np
from numpy.typing import ArrayLike, NDArray

FloatArray = NDArray[np.float64]


def _array(value: ArrayLike, name: str, ndim: int) -> FloatArray:
    raw = np.asarray(value)
    if not np.issubdtype(raw.dtype, np.number) or np.iscomplexobj(raw):
        raise ValueError(f"{name} must contain real numeric values")
    with np.errstate(over="ignore", invalid="ignore"):
        result = np.array(raw, dtype=np.float64, copy=True)
    if result.ndim != ndim or any(size == 0 for size in result.shape):
        raise ValueError(f"{name} must be a nonempty {ndim}-dimensional array")
    return _finite(result, name)


def _finite(value: FloatArray, name: str) -> FloatArray:
    if not np.all(np.isfinite(value)):
        raise ValueError(f"{name} contains non-finite values or overflowed")
    return value


def _scalar(value: float, name: str, *, minimum: float | None = None) -> float:
    if isinstance(value, (bool, np.bool_, str, bytes)) or np.iscomplexobj(value) or np.ndim(value) != 0:
        raise ValueError(f"{name} must be a finite real scalar")
    try:
        result = float(value)
    except (TypeError, ValueError, OverflowError) as exc:
        raise ValueError(f"{name} must be a finite real scalar") from exc
    if not math.isfinite(result) or (minimum is not None and result < minimum):
        raise ValueError(f"{name} must be finite and >= {minimum}")
    return result


def _positive(value: float, name: str) -> float:
    result = _scalar(value, name, minimum=0.0)
    if result == 0:
        raise ValueError(f"{name} must be positive")
    return result


def _snapshot(value: FloatArray) -> FloatArray:
    result = np.array(value, dtype=np.float64, copy=True)
    result.setflags(write=False)
    return result


def _same_shape(left: FloatArray, right: FloatArray, names: str) -> None:
    if left.shape != right.shape:
        raise ValueError(f"{names} must have matching shapes")


def _norm_parts(value: FloatArray) -> tuple[float, float]:
    """Represent a Euclidean norm as peak * scaled_norm without squaring peaks."""
    peak = float(np.max(np.abs(value)))
    if peak == 0:
        return 0.0, 0.0
    scaled = value / peak
    return peak, float(np.sqrt(np.sum(scaled * scaled)))


def _unit(value: FloatArray, epsilon: float) -> FloatArray | None:
    peak, length = _norm_parts(value)
    if peak == 0 or peak <= epsilon / length:
        return None
    return (value / peak) / length


def _cap_norm(value: FloatArray, limit: float) -> tuple[FloatArray, float]:
    peak, length = _norm_parts(value)
    if peak == 0 or peak <= limit / length:
        return value.copy(), 1.0
    scale = (limit / peak) / length
    return value * scale, scale


def _matmul(left: FloatArray, right: FloatArray, name: str) -> FloatArray:
    with np.errstate(over="ignore", invalid="ignore"):
        result = left @ right
    return _finite(np.asarray(result), name)


def _symmetric(value: ArrayLike, name: str) -> FloatArray:
    matrix = _array(value, name, 2)
    if matrix.shape[0] != matrix.shape[1]:
        raise ValueError(f"{name} must be square")
    if not np.allclose(matrix, matrix.T, rtol=1e-10, atol=1e-12):
        raise ValueError(f"{name} must be symmetric")
    # Only average already symmetric-within-roundoff input; do not repair a model.
    return matrix * 0.5 + matrix.T * 0.5


def _positive_definite(value: ArrayLike, name: str) -> tuple[FloatArray, FloatArray]:
    matrix = _symmetric(value, name)
    try:
        factor = np.linalg.cholesky(matrix)
    except np.linalg.LinAlgError as exc:
        raise ValueError(f"{name} must be positive definite") from exc
    return matrix, _finite(factor, f"{name} Cholesky factor")


def _psd_minimum(matrix: FloatArray, name: str, tolerance: float) -> tuple[float, float]:
    try:
        eigenvalues = np.linalg.eigvalsh(matrix)
    except np.linalg.LinAlgError as exc:
        raise ValueError(f"could not characterize {name}") from exc
    _finite(eigenvalues, f"{name} eigenvalues")
    allowed = tolerance * max(1.0, float(np.max(np.abs(eigenvalues))))
    if not math.isfinite(allowed):
        raise ValueError(f"{name} PSD tolerance overflowed")
    minimum = float(eigenvalues[0])
    if minimum < -allowed:
        raise ValueError(f"{name} must be positive semidefinite; minimum eigenvalue={minimum}")
    return minimum, allowed


@dataclass(frozen=True)
class ReaderFit:
    available: bool
    direction: FloatArray | None
    reason: str | None
    method: str
    sample_count: int
    hidden_width: int
    explained_variance_ratio: float | None = None
    orientation_margin: float | None = None


def _contrasts(positive: ArrayLike, negative: ArrayLike) -> FloatArray:
    plus = _array(positive, "positive", 2)
    minus = _array(negative, "negative", 2)
    _same_shape(plus, minus, "positive and negative examples [samples, hidden]")
    with np.errstate(over="ignore", invalid="ignore"):
        return _finite(plus - minus, "matched contrasts")


def sign_balanced_pca_reader(
    positive: ArrayLike, negative: ArrayLike, *, epsilon: float = 1e-12
) -> ReaderFit:
    """Fit the first component of [D; -D], where D=positive-negative [N,H].

    Positive and negative arguments provide fit-set contrast labels. The first
    component is oriented toward their mean difference. Zero energy or an
    ambiguous mean sign is unavailable. A degenerate leading eigenspace is not
    resolved semantically; component stability must be characterized separately.
    Only the supplied fit examples are used; group splitting is caller-owned.
    """
    epsilon = _scalar(epsilon, "epsilon", minimum=0.0)
    differences = _contrasts(positive, negative)
    samples, width = differences.shape
    peak = float(np.max(np.abs(differences)))
    if peak == 0:
        return ReaderFit(False, None, "zero_contrast", "sign_balanced_pca", samples, width)
    # Scaling preserves the component and avoids overflow in the SVD.
    scaled = differences / peak
    balanced = np.concatenate((scaled, -scaled), axis=0)
    try:
        _, singular_values, right = np.linalg.svd(balanced, full_matrices=False)
    except np.linalg.LinAlgError as exc:
        raise ValueError("sign-balanced PCA did not converge") from exc
    _finite(singular_values, "PCA singular values")
    direction = _finite(right[0], "PCA direction")
    if singular_values[0] == 0:
        return ReaderFit(False, None, "zero_contrast", "sign_balanced_pca", samples, width)
    scaled_mean = np.mean(scaled, axis=0)
    orientation = float(_matmul(scaled_mean, direction, "PCA orientation"))
    ratio = float(1.0 / np.sum((singular_values / singular_values[0]) ** 2))
    # Epsilon is relative to the maximum absolute contrast for this sign check.
    if abs(orientation) <= epsilon:
        return ReaderFit(False, None, "ambiguous_label_orientation", "sign_balanced_pca",
                         samples, width, ratio, abs(orientation))
    if orientation < 0:
        direction = -direction
    return ReaderFit(True, _snapshot(direction), None, "sign_balanced_pca",
                     samples, width, ratio, abs(orientation))


def mean_contrast_reader(
    positive: ArrayLike, negative: ArrayLike, *, epsilon: float = 1e-12
) -> ReaderFit:
    """Normalize the mean matched difference [N,H]; zero mean is unavailable.

    ``epsilon`` is an absolute norm threshold in activation units. No reference
    center or assay normalization is learned implicitly from these fit examples.
    """
    epsilon = _scalar(epsilon, "epsilon", minimum=0.0)
    differences = _contrasts(positive, negative)
    samples, width = differences.shape
    peak = float(np.max(np.abs(differences)))
    mean = np.zeros(width) if peak == 0 else np.mean(differences / peak, axis=0) * peak
    direction = _unit(mean, epsilon)
    if direction is None:
        return ReaderFit(False, None, "zero_mean_contrast", "mean_contrast", samples, width)
    return ReaderFit(True, _snapshot(direction), None, "mean_contrast", samples, width)


@dataclass(frozen=True)
class AssayMeasurement:
    available: bool
    raw_score: float | None
    standardized_score: float | None
    bounded_score: float | None
    out_of_reference: bool | None
    reason: str | None


def standardized_assay(
    hidden: ArrayLike,
    direction: ArrayLike,
    reference_center: ArrayLike,
    *,
    score_mean: float,
    score_scale: float,
    score_range: tuple[float, float] | None = None,
    epsilon: float = 1e-12,
) -> AssayMeasurement:
    """Read one H-vector against a caller-frozen unit direction and reference.

    Computes s=v@(h-center), z=(s-score_mean)/score_scale, then sigmoid(z).
    The bounded result is an experimental coordinate, not a probability. A raw
    score-range flag is a limited reference check, not a distribution-shift test.
    Zero direction or reference scale is unavailable; non-unit directions fail.
    """
    hidden = _array(hidden, "hidden", 1)
    direction = _array(direction, "direction", 1)
    center = _array(reference_center, "reference_center", 1)
    _same_shape(hidden, direction, "hidden and direction")
    _same_shape(hidden, center, "hidden and reference_center")
    epsilon = _scalar(epsilon, "epsilon", minimum=0.0)
    mean = _scalar(score_mean, "score_mean")
    scale = _scalar(score_scale, "score_scale", minimum=0.0)
    limits = None
    if score_range is not None:
        if len(score_range) != 2:
            raise ValueError("score_range must contain lower and upper bounds")
        lower, upper = (_scalar(value, "score_range bound") for value in score_range)
        if lower > upper:
            raise ValueError("score_range lower bound must not exceed upper bound")
        limits = (lower, upper)
    unit = _unit(direction, epsilon)
    if unit is None:
        return AssayMeasurement(False, None, None, None, None, "zero_direction")
    if not np.allclose(direction, unit, rtol=1e-8, atol=1e-10):
        raise ValueError("direction must have unit Euclidean norm")
    if scale <= epsilon:
        return AssayMeasurement(False, None, None, None, None, "zero_reference_scale")
    with np.errstate(over="ignore", invalid="ignore"):
        centered = _finite(hidden - center, "centered hidden vector")
    score = float(_matmul(direction, centered, "assay score"))
    standardized = _scalar((score - mean) / scale, "standardized assay score")
    if standardized >= 0:
        bounded = 1.0 / (1.0 + math.exp(-standardized))
    else:
        exponential = math.exp(standardized)
        bounded = exponential / (1.0 + exponential)
    outside = None if limits is None else not limits[0] <= score <= limits[1]
    return AssayMeasurement(True, score, standardized, bounded, outside, None)


@dataclass(frozen=True)
class EntropyMeasurement:
    nats: float
    normalized: float
    support_size: int


def _probabilities(values: ArrayLike) -> FloatArray:
    probabilities = _array(values, "probabilities", 1)
    if np.any(probabilities < 0) or np.any(probabilities > 1):
        raise ValueError("probabilities must be between zero and one")
    return probabilities


def _entropy(probabilities: FloatArray) -> float:
    positive = probabilities[probabilities > 0]
    return float(-np.sum(positive * np.log(positive)))


def normalized_entropy(
    probabilities: ArrayLike, *, normalization_tolerance: float = 1e-8
) -> EntropyMeasurement:
    """Entropy of the supplied complete K-entry distribution, K >= 2.

    Supply every vocabulary entry, including zeros. This function cannot detect
    a caller passing a renormalized truncated distribution as if it were full.
    It checks the sum without renormalizing the input.
    """
    probabilities = _probabilities(probabilities)
    tolerance = _scalar(normalization_tolerance, "normalization_tolerance", minimum=0.0)
    if len(probabilities) < 2:
        raise ValueError("full support must have at least two entries")
    if abs(float(np.sum(probabilities)) - 1.0) > tolerance:
        raise ValueError("complete probabilities must sum to one")
    nats = _entropy(probabilities)
    normalized = float(np.clip(nats / math.log(len(probabilities)), 0.0, 1.0))
    return EntropyMeasurement(nats, normalized, len(probabilities))


@dataclass(frozen=True)
class EntropyBounds:
    lower_nats: float
    upper_nats: float
    lower_normalized: float
    upper_normalized: float
    observed_mass: float
    missing_mass: float
    support_size: int
    reported_count: int


def top_k_entropy_bounds(
    probabilities: ArrayLike,
    support_size: int,
    *,
    probabilities_are_full_distribution_mass: bool,
    normalization_tolerance: float = 1e-8,
) -> EntropyBounds:
    """Bound full entropy from exact original probabilities for k of K entries.

    The explicit mass declaration must be True. Renormalized top-k probabilities
    are ineligible; their original missing mass cannot be recovered here. Bounds
    concentrate or uniformly distribute the tail and do not exploit top-k rank.
    A full K-entry input must sum to one within the declared numerical tolerance.
    """
    if probabilities_are_full_distribution_mass is not True:
        raise ValueError("entropy bounds require original full-distribution probability mass")
    if isinstance(support_size, (bool, np.bool_)) or not isinstance(support_size, (int, np.integer)):
        raise ValueError("support_size must be an integer >= 2")
    if support_size < 2:
        raise ValueError("support_size must be at least two")
    probabilities = _probabilities(probabilities)
    tolerance = _scalar(normalization_tolerance, "normalization_tolerance", minimum=0.0)
    count = len(probabilities)
    if count > support_size:
        raise ValueError("reported entries cannot exceed full support")
    observed = float(np.sum(probabilities))
    if observed > 1.0 + tolerance:
        raise ValueError("reported original probability mass exceeds one")
    missing = max(0.0, 1.0 - observed)
    tail_count = support_size - count
    if tail_count == 0 and missing > tolerance:
        raise ValueError("full-support probabilities must sum to one")
    if tail_count == 0:
        missing = 0.0
    tail_entropy = 0.0 if missing == 0 else -missing * math.log(missing)
    lower = _entropy(probabilities) + tail_entropy
    upper = lower if tail_count <= 1 else lower + missing * math.log(tail_count)
    denominator = math.log(support_size)
    return EntropyBounds(lower, upper,
                         float(np.clip(lower / denominator, 0.0, 1.0)),
                         float(np.clip(upper / denominator, 0.0, 1.0)),
                         observed, missing, int(support_size), count)


@dataclass(frozen=True)
class ReferenceMeasurement:
    available: bool
    cosine: float | None
    previous_reference: FloatArray | None
    next_reference: FloatArray
    reason: str | None


def previous_reference_cosine_ema(
    hidden: ArrayLike,
    previous_reference: ArrayLike | None,
    *,
    ema_weight: float,
    epsilon: float = 1e-12,
) -> ReferenceMeasurement:
    """Measure against the previous H-vector, then propose its next EMA value.

    next=(1-weight)*previous+weight*hidden. Missing reference initializes to a
    copy of hidden and returns unavailable. Zero-norm cosine is unavailable but
    an EMA candidate is still returned. Neither input is mutated or persisted.
    """
    hidden = _array(hidden, "hidden", 1)
    weight = _scalar(ema_weight, "ema_weight", minimum=0.0)
    if weight > 1:
        raise ValueError("ema_weight must be <= 1")
    epsilon = _scalar(epsilon, "epsilon", minimum=0.0)
    if previous_reference is None:
        return ReferenceMeasurement(False, None, None, _snapshot(hidden), "missing_previous_reference")
    previous = _array(previous_reference, "previous_reference", 1)
    _same_shape(hidden, previous, "hidden and previous_reference")
    current_unit, previous_unit = _unit(hidden, epsilon), _unit(previous, epsilon)
    cosine = None
    if current_unit is not None and previous_unit is not None:
        cosine = float(np.clip(_matmul(current_unit, previous_unit, "cosine"), -1.0, 1.0))
    with np.errstate(over="ignore", invalid="ignore"):
        next_reference = _finite((1.0 - weight) * previous + weight * hidden, "EMA candidate")
    return ReferenceMeasurement(cosine is not None, cosine, _snapshot(previous),
                                _snapshot(next_reference), None if cosine is not None else "zero_norm")


@dataclass(frozen=True)
class TransitionEstimate:
    available: bool
    value: float | None
    clipped: bool
    reason: str | None


def finite_transition_estimate(
    consistency: float | None,
    normalized_expansion: float | None,
    *,
    max_magnitude: float,
    expansion_epsilon: float = 1e-12,
) -> TransitionEstimate:
    """Experimental clipped cosine/entropy ratio; not an asymptotic limit."""
    bound = _positive(max_magnitude, "max_magnitude")
    epsilon = _scalar(expansion_epsilon, "expansion_epsilon", minimum=0.0)
    if consistency is None or normalized_expansion is None:
        return TransitionEstimate(False, None, False, "missing_observable")
    omega = _scalar(consistency, "consistency")
    phi = _scalar(normalized_expansion, "normalized_expansion", minimum=0.0)
    if abs(omega) > 1 or phi > 1:
        raise ValueError("consistency must lie in [-1,1] and normalized_expansion in [0,1]")
    if phi <= epsilon:
        return TransitionEstimate(False, None, False, "expansion_below_threshold")
    clipped = abs(omega) > bound * phi
    value = math.copysign(bound, omega) if clipped else omega / phi
    return TransitionEstimate(True, value, clipped, None)


def _potential(q: FloatArray, target: FloatArray, factor: FloatArray) -> float:
    with np.errstate(over="ignore", invalid="ignore"):
        displacement = _finite(q - target, "potential displacement")
    transformed = _matmul(factor.T, displacement, "potential transform")
    with np.errstate(over="ignore", invalid="ignore"):
        value = float(np.sum((transformed * 0.5) * transformed))
    return _scalar(value, "quadratic potential", minimum=0.0)


def quadratic_potential(q: ArrayLike, target: ArrayLike, potential_matrix: ArrayLike) -> float:
    """Evaluate V(q)=0.5*(q-target)^T P (q-target), requiring symmetric P>0."""
    q = _array(q, "q", 1)
    target = _array(target, "target", 1)
    _same_shape(q, target, "q and target")
    matrix, factor = _positive_definite(potential_matrix, "potential_matrix")
    if matrix.shape != (len(q), len(q)):
        raise ValueError("potential_matrix must have shape [n,n]")
    return _potential(q, target, factor)


@dataclass(frozen=True)
class QuotientCandidate:
    previous: FloatArray
    candidate: FloatArray
    requested_delta: FloatArray
    capped_delta: FloatArray
    effective_delta: FloatArray
    accepted: bool
    status: Literal["ACCEPTED_CANDIDATE", "DAMPED_CANDIDATE", "REJECTED_UNCHANGED"]
    norm_scale: float
    backtracks: int
    potential_previous: float
    potential_candidate: float


def bounded_quotient_candidate(
    q: ArrayLike,
    innovation: ArrayLike,
    learning_matrix: ArrayLike,
    error: ArrayLike,
    *,
    learning_rate: float,
    delta_max: float,
    target: ArrayLike,
    potential_matrix: ArrayLike,
    allowed_increase: float = 0.0,
    max_backtracks: int = 24,
) -> QuotientCandidate:
    """Propose clip(q + 2**(-b)*cap(eta*(L@I-E)), 0, 1), never apply it.

    Shapes: q,E,target=[n], I=[m], L=[n,m], P=[n,n]. q must already be in
    [0,1]. The fixed target and positive-definite P are copied once. Every full
    finite candidate is checked against V(previous)+allowed_increase, including
    coordinate clipping. The effective norm is rechecked after arithmetic.
    Counts b=0 through max_backtracks (an integer in 0...64) are attempted. If
    none pass, return the unchanged rejected candidate. Only effective_delta
    (candidate-previous) is eligible for downstream experimental coupling.
    """
    q = _array(q, "q", 1)
    innovation = _array(innovation, "innovation", 1)
    learning = _array(learning_matrix, "learning_matrix", 2)
    error = _array(error, "error", 1)
    target = _array(target, "target", 1)
    _same_shape(q, error, "q and error")
    _same_shape(q, target, "q and target")
    if learning.shape != (len(q), len(innovation)):
        raise ValueError("learning_matrix must have shape [len(q),len(innovation)]")
    if np.any(q < 0) or np.any(q > 1):
        raise ValueError("previous q must lie in [0,1]")
    eta = _scalar(learning_rate, "learning_rate", minimum=0.0)
    cap = _scalar(delta_max, "delta_max", minimum=0.0)
    increase = _scalar(allowed_increase, "allowed_increase", minimum=0.0)
    if isinstance(max_backtracks, (bool, np.bool_)) or not isinstance(max_backtracks, (int, np.integer)) or not 0 <= max_backtracks <= 64:
        raise ValueError("max_backtracks must be an integer between zero and 64")
    matrix, factor = _positive_definite(potential_matrix, "potential_matrix")
    if matrix.shape != (len(q), len(q)):
        raise ValueError("potential_matrix must have shape [n,n]")
    before = _potential(q, target, factor)
    ceiling = _scalar(before + increase, "potential acceptance ceiling", minimum=0.0)
    learned = _matmul(learning, innovation, "learning increment")
    with np.errstate(over="ignore", invalid="ignore"):
        requested = _finite(eta * (learned - error), "requested quotient delta")
    capped, scale = _cap_norm(requested, cap)
    for count in range(int(max_backtracks) + 1):
        step = math.ldexp(1.0, -count)
        candidate = np.clip(q + step * capped, 0.0, 1.0)
        effective = candidate - q
        _, effective_scale = _cap_norm(effective, cap)
        if effective_scale < 1.0:
            continue
        try:
            after = _potential(candidate, target, factor)
        except ValueError:
            # A candidate whose potential overflows cannot pass the full-step
            # check; a smaller candidate may still be representable.
            continue
        if after <= ceiling:
            status = "DAMPED_CANDIDATE" if count > 0 or scale < 1 else "ACCEPTED_CANDIDATE"
            return QuotientCandidate(_snapshot(q), _snapshot(candidate), _snapshot(requested),
                                     _snapshot(capped), _snapshot(effective), True, status,
                                     scale, count, before, after)
    return QuotientCandidate(_snapshot(q), _snapshot(q), _snapshot(requested),
                             _snapshot(capped), _snapshot(np.zeros_like(q)), False,
                             "REJECTED_UNCHANGED", scale, int(max_backtracks), before, before)


def intelligence_force(
    q: ArrayLike,
    target: ArrayLike,
    potential_matrix: ArrayLike,
    metric_matrix: ArrayLike,
    *,
    gain: float,
) -> FloatArray:
    """Return the continuous vector field -gain*solve(G,P@(q-target)).

    This is not a finite accepted update. Both matrices must be symmetric
    positive definite. Use a complete candidate check for any finite step.
    """
    q = _array(q, "q", 1)
    target = _array(target, "target", 1)
    _same_shape(q, target, "q and target")
    potential, _ = _positive_definite(potential_matrix, "potential_matrix")
    metric, _ = _positive_definite(metric_matrix, "metric_matrix")
    if potential.shape != (len(q), len(q)) or metric.shape != potential.shape:
        raise ValueError("potential_matrix and metric_matrix must have shape [n,n]")
    gain = _scalar(gain, "gain", minimum=0.0)
    with np.errstate(over="ignore", invalid="ignore"):
        displacement = _finite(q - target, "force displacement")
    gradient = _matmul(potential, displacement, "potential gradient")
    try:
        with np.errstate(over="ignore", invalid="ignore"):
            force = _finite(-gain * np.linalg.solve(metric, gradient), "intelligence force")
    except np.linalg.LinAlgError as exc:
        raise ValueError("metric solve failed") from exc
    return _snapshot(force)


@dataclass(frozen=True)
class ValidatedCoupling:
    matrix: FloatArray
    spectral_norm: float
    spectral_norm_bound: float


def validate_coupling(matrix: ArrayLike, *, spectral_norm_bound: float) -> ValidatedCoupling:
    """Check rectangular M[source,destination] against its declared operator bound.

    Unknown or over-bound matrices fail; nothing is silently rescaled. Zero
    matrices and a zero declared bound support disabled experimental coupling.
    """
    matrix = _array(matrix, "coupling_matrix", 2)
    bound = _scalar(spectral_norm_bound, "spectral_norm_bound", minimum=0.0)
    try:
        singular = np.linalg.svd(matrix, compute_uv=False)
    except np.linalg.LinAlgError as exc:
        raise ValueError("coupling singular-value calculation failed") from exc
    _finite(singular, "coupling singular values")
    norm = float(singular[0])
    if norm > bound:
        raise ValueError(f"coupling spectral norm {norm} exceeds declared bound {bound}")
    return ValidatedCoupling(_snapshot(matrix), norm, bound)


@dataclass(frozen=True)
class CouplingProposal:
    effective_delta: FloatArray
    destination_delta: FloatArray
    spectral_norm: float


def couple_effective_delta(
    effective_delta: ArrayLike, matrix: ArrayLike, *, spectral_norm_bound: float
) -> CouplingProposal:
    """Return delta_z=M.T@effective_delta, with M=[source,destination].

    The caller must supply the actual accepted candidate-minus-previous delta.
    This function cannot prove a supplied array came from that computation.
    """
    delta = _array(effective_delta, "effective_delta", 1)
    coupling = validate_coupling(matrix, spectral_norm_bound=spectral_norm_bound)
    if coupling.matrix.shape[0] != len(delta):
        raise ValueError("coupling source width must match effective_delta")
    destination = _matmul(coupling.matrix.T, delta, "coupled effective delta")
    return CouplingProposal(_snapshot(delta), _snapshot(destination), coupling.spectral_norm)


@dataclass(frozen=True)
class JointCovariance:
    joint: FloatArray
    delta_covariance: FloatArray
    joint_minimum_eigenvalue: float
    joint_absolute_tolerance: float
    delta_minimum_eigenvalue: float


def validate_joint_covariance(
    next_covariance: ArrayLike,
    previous_covariance: ArrayLike,
    cross_covariance: ArrayLike,
    *,
    psd_tolerance: float = 1e-10,
) -> JointCovariance:
    """Validate Cov([q_next,q_previous])=[[S_next,C],[C.T,S_previous]].

    All inputs have shape [n,n]; C=Cov(q_next,q_previous) need not be symmetric.
    PSD tolerance is relative to max(1, spectral radius). Tiny negative values
    within that numerical tolerance are reported, never projected away. Passing
    marginal covariance checks alone does not establish a valid joint model.
    """
    next_covariance = _symmetric(next_covariance, "next_covariance")
    previous = _symmetric(previous_covariance, "previous_covariance")
    cross = _array(cross_covariance, "cross_covariance", 2)
    _same_shape(next_covariance, previous, "next and previous covariance")
    _same_shape(next_covariance, cross, "marginal and cross covariance")
    tolerance = _scalar(psd_tolerance, "psd_tolerance", minimum=0.0)
    joint = np.block([[next_covariance, cross], [cross.T, previous]])
    minimum, absolute_tolerance = _psd_minimum(joint, "joint covariance", tolerance)
    with np.errstate(over="ignore", invalid="ignore"):
        delta = _finite(next_covariance + previous - cross - cross.T, "delta covariance")
    delta = delta * 0.5 + delta.T * 0.5
    delta_minimum, _ = _psd_minimum(delta, "delta covariance", tolerance)
    return JointCovariance(_snapshot(joint), _snapshot(delta), minimum, absolute_tolerance,
                           delta_minimum)


@dataclass(frozen=True)
class CouplingUncertainty:
    delta_covariance: FloatArray
    destination_covariance: FloatArray
    joint_minimum_eigenvalue: float
    destination_minimum_eigenvalue: float
    spectral_norm: float


def propagate_coupling_uncertainty(
    next_covariance: ArrayLike,
    previous_covariance: ArrayLike,
    cross_covariance: ArrayLike,
    matrix: ArrayLike,
    *,
    spectral_norm_bound: float,
    psd_tolerance: float = 1e-10,
) -> CouplingUncertainty:
    """Propagate a validated joint covariance through fixed M as M.T@S_delta@M.

    Excludes uncertainty in M, changed bases, and nonlinear clipping. Covariances
    must describe the actual accepted states; use full-pipeline uncertainty
    estimation when those assumptions do not hold.
    """
    tolerance = _scalar(psd_tolerance, "psd_tolerance", minimum=0.0)
    covariance = validate_joint_covariance(next_covariance, previous_covariance,
                                           cross_covariance, psd_tolerance=tolerance)
    coupling = validate_coupling(matrix, spectral_norm_bound=spectral_norm_bound)
    if coupling.matrix.shape[0] != covariance.delta_covariance.shape[0]:
        raise ValueError("coupling source width must match covariance dimension")
    left = _matmul(coupling.matrix.T, covariance.delta_covariance, "covariance left product")
    destination = _matmul(left, coupling.matrix, "destination covariance")
    destination = destination * 0.5 + destination.T * 0.5
    minimum, _ = _psd_minimum(destination, "destination covariance", tolerance)
    return CouplingUncertainty(covariance.delta_covariance, _snapshot(destination),
                               covariance.joint_minimum_eigenvalue, minimum,
                               coupling.spectral_norm)


@dataclass(frozen=True)
class SteeringResult:
    hidden: FloatArray
    residual: FloatArray
    requested_coefficients: FloatArray
    clipped_coefficients: FloatArray
    scale: float
    backtracks: int


def bounded_steering(
    hidden: ArrayLike,
    directions: ArrayLike,
    coefficients: ArrayLike,
    *,
    coefficient_cap: float,
    relative_cap: float,
) -> SteeringResult:
    """Add a combined bounded residual to one hidden H-vector.

    directions=[H,C] must have unit columns; coefficients=[C]. Clip every
    coefficient, combine all directions, then cap the total residual norm at
    relative_cap*norm(hidden), with relative_cap in [0,1]. Recheck the actual
    edited-minus-hidden residual after addition and halve up to 64 times if
    rounding exceeds the budget; fall back to zero edit when necessary. Zero
    hidden norm or a zero combined residual produces zero edit. ``scale`` is the
    request multiplier; ``residual`` is the effective edit after arithmetic.
    Caps are caller-selected experiment settings, not safety thresholds. The
    result belongs to this experimental computation only.
    """
    hidden = _array(hidden, "hidden", 1)
    directions = _array(directions, "directions", 2)
    coefficients = _array(coefficients, "coefficients", 1)
    if directions.shape != (len(hidden), len(coefficients)):
        raise ValueError("directions must have shape [hidden width, coefficient count]")
    cap = _scalar(coefficient_cap, "coefficient_cap", minimum=0.0)
    relative = _scalar(relative_cap, "relative_cap", minimum=0.0)
    if relative > 1:
        raise ValueError("relative_cap must be <= 1")
    for column in directions.T:
        unit = _unit(column, 0.0)
        if unit is None or not np.allclose(column, unit, rtol=1e-8, atol=1e-10):
            raise ValueError("every steering direction must have unit Euclidean norm")
    clipped = np.clip(coefficients, -cap, cap)
    combined = _matmul(directions, clipped, "combined steering residual")
    hidden_peak, hidden_length = _norm_parts(hidden)
    edit_peak, edit_length = _norm_parts(combined)
    backtracks = 0
    if hidden_peak == 0 or relative == 0:
        scale = 0.0
    elif edit_peak == 0:
        scale = 1.0
    else:
        # Compute the cap ratio in log-space so large finite norms do not overflow.
        log_ratio = (math.log(relative) + math.log(hidden_peak) + math.log(hidden_length)
                     - math.log(edit_peak) - math.log(edit_length))
        scale = 1.0 if log_ratio >= 0 else math.exp(log_ratio)
    edited = hidden.copy()
    residual = np.zeros_like(hidden)
    if hidden_peak != 0 and relative != 0 and edit_peak != 0:
        for backtracks in range(65):
            with np.errstate(over="ignore", invalid="ignore"):
                proposal = hidden + combined * scale
                effective = proposal - hidden
            if np.all(np.isfinite(proposal)) and np.all(np.isfinite(effective)):
                effective_peak, effective_length = _norm_parts(effective)
                ratio = (effective_peak / hidden_peak) * (effective_length / hidden_length)
                if effective_peak == 0 or ratio <= relative:
                    edited, residual = proposal, effective
                    break
            if backtracks == 64:
                scale = 0.0
            else:
                scale *= 0.5
    return SteeringResult(_snapshot(edited), _snapshot(residual), _snapshot(coefficients),
                          _snapshot(clipped), scale, backtracks)


@dataclass(frozen=True)
class ControlProposal:
    coefficients: FloatArray
    desired_change: FloatArray
    predicted_change: FloatArray
    remaining_error: FloatArray
    regularization: float


def regularized_control_solve(
    outcome_sensitivity: ArrayLike,
    current_outcome: ArrayLike,
    target_outcome: ArrayLike,
    *,
    regularization: float,
) -> ControlProposal:
    """Solve the ridge proposal (J.T@J+lambda*I)^-1@J.T@(target-current).

    J=[outcomes,controls]; current and target=[outcomes]; lambda>0. An SVD
    evaluates the same ridge solution without squaring J's condition number.
    No J is learned here and causal identification is not implied. Returned
    coefficients are unbounded proposals; apply bounded_steering before use.
    """
    sensitivity = _array(outcome_sensitivity, "outcome_sensitivity", 2)
    current = _array(current_outcome, "current_outcome", 1)
    target = _array(target_outcome, "target_outcome", 1)
    _same_shape(current, target, "current and target outcomes")
    if sensitivity.shape[0] != len(current):
        raise ValueError("outcome_sensitivity rows must match outcome count")
    ridge = _positive(regularization, "regularization")
    with np.errstate(over="ignore", invalid="ignore"):
        desired = _finite(target - current, "desired outcome change")
    try:
        left, singular, right = np.linalg.svd(sensitivity, full_matrices=False)
    except np.linalg.LinAlgError as exc:
        raise ValueError("control sensitivity SVD did not converge") from exc
    _finite(singular, "control singular values")
    root = math.sqrt(ridge)
    factors = np.empty_like(singular)
    small = singular <= root
    ratio = singular[small] / root
    factors[small] = ratio / (root * (1.0 + ratio * ratio))
    large = singular[~small]
    factors[~small] = (1.0 / large) / (1.0 + (root / large) ** 2)
    projection = _matmul(left.T, desired, "control target projection")
    with np.errstate(over="ignore", invalid="ignore"):
        weighted = _finite(factors * projection, "regularized control components")
    coefficients = _matmul(right.T, weighted, "control coefficients")
    predicted = _matmul(sensitivity, coefficients, "predicted outcome change")
    with np.errstate(over="ignore", invalid="ignore"):
        remaining = _finite(desired - predicted, "remaining predicted error")
    return ControlProposal(_snapshot(coefficients), _snapshot(desired), _snapshot(predicted),
                            _snapshot(remaining), ridge)


__all__ = [
    "AssayMeasurement", "ControlProposal", "CouplingProposal", "CouplingUncertainty",
    "EntropyBounds", "EntropyMeasurement", "JointCovariance", "QuotientCandidate",
    "ReaderFit", "ReferenceMeasurement", "SteeringResult", "TransitionEstimate",
    "ValidatedCoupling", "bounded_quotient_candidate", "bounded_steering",
    "couple_effective_delta", "finite_transition_estimate", "intelligence_force",
    "mean_contrast_reader", "normalized_entropy", "previous_reference_cosine_ema",
    "propagate_coupling_uncertainty", "quadratic_potential", "regularized_control_solve",
    "sign_balanced_pca_reader", "standardized_assay", "top_k_entropy_bounds",
    "validate_coupling", "validate_joint_covariance",
]
