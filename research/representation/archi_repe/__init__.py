"""Opt-in ARCHi representation research, with no model or native-state side effects.

Importing the numerical package requires NumPy only. Optional experimental
backend modules are imported explicitly by callers and never enabled here.
"""

from .numerics import (
    AssayMeasurement,
    ControlProposal,
    CouplingProposal,
    CouplingUncertainty,
    EntropyBounds,
    EntropyMeasurement,
    JointCovariance,
    QuotientCandidate,
    ReaderFit,
    ReferenceMeasurement,
    SteeringResult,
    TransitionEstimate,
    ValidatedCoupling,
    bounded_quotient_candidate,
    bounded_steering,
    couple_effective_delta,
    finite_transition_estimate,
    intelligence_force,
    mean_contrast_reader,
    normalized_entropy,
    previous_reference_cosine_ema,
    propagate_coupling_uncertainty,
    quadratic_potential,
    regularized_control_solve,
    sign_balanced_pca_reader,
    standardized_assay,
    top_k_entropy_bounds,
    validate_coupling,
    validate_joint_covariance,
)

__version__ = "0.1.0"

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
