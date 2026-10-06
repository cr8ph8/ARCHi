"""Immutable, local Stack R2 record adapters; no store, model, or mutation port.

These records describe evidence and proposed work. Validation checks bindings and
declared boundaries, never truth, permission, scientific validity, or a commit.
See docs/research/2026-09-25-stack-and-representation/local-stack-build.md.
"""

from __future__ import annotations

from dataclasses import dataclass, fields, is_dataclass
from datetime import datetime
from enum import Enum
from hashlib import sha256
import json
import math
import re
from typing import ClassVar


class ContractError(ValueError):
    """A supplied record violates an explicit local contract."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def _text(value: str, name: str) -> None:
    _require(isinstance(value, str) and bool(value.strip()), f"{name} is required")


def _digest(value: str) -> None:
    _require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None,
             "expected a lowercase SHA-256 digest")


def _items(value: tuple, item_type: type, name: str, *, nonempty: bool = False) -> None:
    _require(isinstance(value, tuple), f"{name} must be an immutable tuple")
    _require(all(isinstance(item, item_type) for item in value), f"invalid {name} item")
    _require(not nonempty or bool(value), f"{name} must not be empty")


def _instant(value: datetime) -> None:
    _require(isinstance(value, datetime) and value.utcoffset() is not None,
             "timestamps must include a timezone")


def _finite(value: float, name: str) -> None:
    _require(isinstance(value, (int, float)) and not isinstance(value, bool)
             and math.isfinite(value), f"{name} must be finite")


class OperatingLoop(str, Enum):
    INFERENCE = "inference"
    TASK = "task"
    DEVELOPMENT = "development"
    RESEARCH = "research"


@dataclass(frozen=True)
class LoopContract:
    loop: OperatingLoop
    operating_unit: str
    may_adapt: tuple[str, ...]
    progress_requires: str

    def __post_init__(self) -> None:
        _require(isinstance(self.loop, OperatingLoop), "invalid operating loop")
        _text(self.operating_unit, "operating unit")
        _items(self.may_adapt, str, "adaptable surfaces", nonempty=True)
        _text(self.progress_requires, "progress requirements")


LOOP_CONTRACTS = (
    LoopContract(OperatingLoop.INFERENCE, "token or model step k",
                 ("temporary activations", "decoding", "bounded experimental controls"),
                 "independent task outcomes; a latent meter cannot qualify progress"),
    LoopContract(OperatingLoop.TASK, "reviewed episode t",
                 ("strategy", "retrieval", "search order", "bounded plans", "repair"),
                 "source-bound review or domain/environment evidence"),
    LoopContract(OperatingLoop.DEVELOPMENT, "explicit developmental transition",
                 ("memory", "skills", "relationships", "form", "other declared channels"),
                 "channel evidence, consent, dependencies, and existing owner checks"),
    LoopContract(OperatingLoop.RESEARCH, "experiment or release r",
                 ("harnesses", "adapters", "learned operators", "candidate policies"),
                 "held-out evaluation, complete cost accounting, and authorized release"),
)


class RecordFamily(str, Enum):
    TASK = "task"
    MEASUREMENT = "measurement"
    CANDIDATE = "candidate"
    OUTCOME = "outcome"
    DEVELOPMENT = "development"


class EpistemicType(str, Enum):
    OBSERVED_EVENT = "observed_event"
    SOURCE_REPORTED_CLAIM = "source_reported_claim"
    MATHEMATICAL_DERIVATION = "mathematical_derivation"
    HYPOTHESIS = "hypothesis"
    SIMULATION = "simulation"
    FICTIONAL_CANON = "fictional_canon"
    DOMAIN_VERIFIED_ASSERTION = "domain_verified_assertion"


class DevelopmentChannel(str, Enum):
    HOMEOSTASIS = "homeostasis"
    MEMORY = "memory"
    RELATIONSHIP = "relationship"
    COMPETENCE = "competence"
    MORPHOGENESIS = "morphogenesis"
    STORY = "story"
    ECOLOGY = "ecology"
    GOVERNANCE = "governance"
    PERCEPTION = "perception"


@dataclass(frozen=True)
class Scope:
    user_id: str
    domain: str
    world_id: str

    def __post_init__(self) -> None:
        for name in ("user_id", "domain", "world_id"):
            _text(getattr(self, name), name)


@dataclass(frozen=True)
class Freshness:
    observed_at: datetime
    expires_at: datetime

    def __post_init__(self) -> None:
        _instant(self.observed_at)
        _instant(self.expires_at)
        _require(self.expires_at > self.observed_at, "expiry must follow observation")

    def require_current(self, now: datetime) -> None:
        _instant(now)
        _require(self.observed_at <= now < self.expires_at, "record is future-dated or expired")


@dataclass(frozen=True)
class SourceBinding:
    source_id: str
    revision: str
    sha256: str

    def __post_init__(self) -> None:
        _text(self.source_id, "source_id")
        _text(self.revision, "source revision")
        _digest(self.sha256)


@dataclass(frozen=True)
class TaskBinding:
    task_id: str
    request_sha256: str
    sources: tuple[SourceBinding, ...]
    state_revision: str
    policy_revision: str

    def __post_init__(self) -> None:
        for name in ("task_id", "state_revision", "policy_revision"):
            _text(getattr(self, name), name)
        _digest(self.request_sha256)
        _items(self.sources, SourceBinding, "sources")
        _require(len({s.source_id for s in self.sources}) == len(self.sources),
                 "a source may have only one bound revision in a task")


@dataclass(frozen=True)
class RecordRef:
    family: RecordFamily
    record_id: str
    revision: str
    sha256: str

    def __post_init__(self) -> None:
        _require(isinstance(self.family, RecordFamily), "invalid record family")
        _text(self.record_id, "record_id")
        _text(self.revision, "record revision")
        _digest(self.sha256)


@dataclass(frozen=True)
class RecordHeader:
    record_id: str
    revision: str
    scope: Scope
    loop: OperatingLoop
    loop_run_id: str
    loop_index: int
    freshness: Freshness

    def __post_init__(self) -> None:
        for name in ("record_id", "revision", "loop_run_id"):
            _text(getattr(self, name), name)
        _require(isinstance(self.scope, Scope), "invalid scope")
        _require(isinstance(self.loop, OperatingLoop), "invalid operating loop")
        _require(type(self.loop_index) is int and self.loop_index >= 0, "invalid loop index")
        _require(isinstance(self.freshness, Freshness), "invalid freshness")


@dataclass(frozen=True)
class EvidenceStatement:
    epistemic_type: EpistemicType
    claim: str
    evidence_establishes: str
    evidence: tuple[SourceBinding, ...]

    def __post_init__(self) -> None:
        _require(isinstance(self.epistemic_type, EpistemicType), "invalid epistemic type")
        _text(self.claim, "claim")
        _text(self.evidence_establishes, "what the evidence establishes")
        _items(self.evidence, SourceBinding, "evidence", nonempty=True)


def _canonical(value: object) -> object:
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, datetime):
        return value.isoformat()
    if is_dataclass(value):
        return {f.name: _canonical(getattr(value, f.name)) for f in fields(value)}
    if isinstance(value, tuple):
        return [_canonical(item) for item in value]
    return value


@dataclass(frozen=True)
class StackRecord:
    header: RecordHeader
    binding: TaskBinding
    FAMILY: ClassVar[RecordFamily]

    def __post_init__(self) -> None:
        _require(isinstance(self.header, RecordHeader), "invalid record header")
        _require(isinstance(self.binding, TaskBinding), "invalid task binding")

    @property
    def reference(self) -> RecordRef:
        """Content binding only; this digest is neither a signature nor authority."""
        payload = {"schema": "archi-stack-adapter/1", "family": self.FAMILY.value,
                   "record": _canonical(self)}
        raw = json.dumps(payload, sort_keys=True, separators=(",", ":"),
                         ensure_ascii=False, allow_nan=False).encode("utf-8")
        return RecordRef(self.FAMILY, self.header.record_id, self.header.revision,
                         sha256(raw).hexdigest())


@dataclass(frozen=True)
class ResourceAmount:
    resource: str
    unit: str
    amount: float | None

    def __post_init__(self) -> None:
        _text(self.resource, "resource")
        _text(self.unit, "resource unit")
        if self.amount is not None:
            _finite(self.amount, "resource amount")
            _require(self.amount >= 0, "resource amount must be nonnegative")


@dataclass(frozen=True)
class TaskRecord(StackRecord):
    """TaskSnapshot adapter; resource unknowns remain None, never inferred zero."""

    FAMILY: ClassVar[RecordFamily] = RecordFamily.TASK
    goal: str
    constraints: tuple[str, ...]
    budget: tuple[ResourceAmount, ...]

    def __post_init__(self) -> None:
        super().__post_init__()
        _text(self.goal, "goal")
        _items(self.constraints, str, "constraints")
        _items(self.budget, ResourceAmount, "budget")


@dataclass(frozen=True)
class CoordinateDefinition:
    name: str
    definition: str
    unit: str
    minimum: float
    maximum: float

    def __post_init__(self) -> None:
        for name in ("name", "definition", "unit"):
            _text(getattr(self, name), name)
        _finite(self.minimum, "coordinate minimum")
        _finite(self.maximum, "coordinate maximum")
        _require(self.minimum < self.maximum, "invalid coordinate range")


@dataclass(frozen=True)
class Coordinate(CoordinateDefinition):
    value: float | None
    uncertainty: float | None

    def __post_init__(self) -> None:
        super().__post_init__()
        if self.value is not None:
            _finite(self.value, "coordinate value")
            _require(self.minimum <= self.value <= self.maximum, "coordinate out of range")
        if self.uncertainty is not None:
            _finite(self.uncertainty, "uncertainty")
            _require(self.uncertainty >= 0, "uncertainty must be nonnegative")


class MeasurementKind(str, Enum):
    OBSERVATION = "observation"
    NATIVE_PRESSURE = "native_pressure"
    LATENT_ASSAY = "latent_assay"


# These are identities, not sixteen interchangeable numeric quotient coordinates.
CANONICAL_STATE_FIELDS = (
    "G", "N", "D", "K", "R", "M", "F", "Π", "L", "T", "C", "W", "X", "P", "B", "Y",
)


class QuotientSpace(str, Enum):
    ARCHIVED_CONTROLLER = "archived_18_coordinate_controller"
    NATIVE_PRESSURES = "native_five_pressures"
    LATENT_ASSAY = "experimental_latent_assay"


@dataclass(frozen=True)
class QuotientSchema:
    namespace: str
    schema_revision: str
    space: QuotientSpace
    coordinates: tuple[CoordinateDefinition, ...]
    basis_revision: str
    model_binding: SourceBinding | None
    reference_population: str

    def __post_init__(self) -> None:
        for name in ("namespace", "schema_revision", "basis_revision", "reference_population"):
            _text(getattr(self, name), name)
        _require(isinstance(self.space, QuotientSpace), "invalid quotient space")
        _items(self.coordinates, CoordinateDefinition, "schema coordinates", nonempty=True)
        _require(all(type(c) is CoordinateDefinition for c in self.coordinates),
                 "schemas contain definitions, not sampled coordinates")
        _require(len({c.name for c in self.coordinates}) == len(self.coordinates), "duplicate schema coordinate")
        _require(self.model_binding is None or isinstance(self.model_binding, SourceBinding),
                 "invalid model binding")
        if self.space is QuotientSpace.ARCHIVED_CONTROLLER:
            _require(len(self.coordinates) == 18, "archived controller has 18 declared coordinates")
        elif self.space is QuotientSpace.NATIVE_PRESSURES:
            _require(tuple(c.name for c in self.coordinates) ==
                     ("support", "coveragePressure", "verifierPressure", "alternativeCoverage", "resourceRemaining"),
                     "native pressure identity/order must be preserved")
        else:
            _require(self.model_binding is not None, "latent schemas require a model identity")


@dataclass(frozen=True)
class QuotientSchemaRegistry:
    """A caller-owned tuple of declared schemas, with no store or implicit migration."""

    schemas: tuple[QuotientSchema, ...]

    def __post_init__(self) -> None:
        _items(self.schemas, QuotientSchema, "quotient schemas")
        _require(len({(s.namespace, s.schema_revision) for s in self.schemas}) == len(self.schemas),
                 "duplicate namespace/schema revision")
        for schema in self.schemas:
            _require(all(s.space is schema.space for s in self.schemas if s.namespace == schema.namespace),
                     "a namespace must not change quotient space")

    def resolve(self, namespace: str, schema_revision: str) -> QuotientSchema:
        for schema in self.schemas:
            if (schema.namespace, schema.schema_revision) == (namespace, schema_revision):
                return schema
        raise ContractError("unknown quotient namespace/schema revision")


@dataclass(frozen=True)
class MeasurementRecord(StackRecord):
    """ObservationEnvelope/RepresentationAssay metadata, never a positive outcome."""

    FAMILY: ClassVar[RecordFamily] = RecordFamily.MEASUREMENT
    kind: MeasurementKind
    namespace: str
    schema_revision: str
    basis_revision: str
    reference_population: str
    uncertainty_method: str
    coordinates: tuple[Coordinate, ...]
    statement: EvidenceStatement
    model_binding: SourceBinding | None
    layer_token_rule: str | None
    intervention_phase: str | None
    input_links: tuple[RecordRef, ...] = ()

    def __post_init__(self) -> None:
        super().__post_init__()
        _require(isinstance(self.kind, MeasurementKind), "invalid measurement kind")
        for name in ("namespace", "schema_revision", "basis_revision", "reference_population", "uncertainty_method"):
            _text(getattr(self, name), name)
        _items(self.coordinates, Coordinate, "coordinates")
        _require(len({c.name for c in self.coordinates}) == len(self.coordinates),
                 "coordinate names must be unique")
        _require(isinstance(self.statement, EvidenceStatement), "invalid evidence statement")
        _require(self.model_binding is None or isinstance(self.model_binding, SourceBinding),
                 "invalid measurement model binding")
        for name in ("layer_token_rule", "intervention_phase"):
            if getattr(self, name) is not None:
                _text(getattr(self, name), name)
        _items(self.input_links, RecordRef, "measurement input links")
        if self.kind is MeasurementKind.LATENT_ASSAY:
            _require(isinstance(self.model_binding, SourceBinding), "latent assay needs a pinned model")
            _text(self.layer_token_rule, "layer/token rule")
            _text(self.intervention_phase, "intervention phase")
            _require(bool(self.coordinates), "latent assay requires declared coordinates")


def validate_measurement_schema(measurement: MeasurementRecord, registry: QuotientSchemaRegistry) -> None:
    """Check units, definitions, ranges and exact basis/model identity without coercion."""
    schema = registry.resolve(measurement.namespace, measurement.schema_revision)
    definitions = tuple(CoordinateDefinition(c.name, c.definition, c.unit, c.minimum, c.maximum)
                        for c in measurement.coordinates)
    _require(definitions == schema.coordinates, "measurement coordinate schema mismatch")
    _require((measurement.basis_revision, measurement.model_binding, measurement.reference_population)
             == (schema.basis_revision, schema.model_binding, schema.reference_population),
             "measurement basis/model/reference population changed")
    if schema.space is QuotientSpace.NATIVE_PRESSURES:
        _require(measurement.kind is MeasurementKind.NATIVE_PRESSURE, "native namespace is not a latent assay")
    if schema.space is QuotientSpace.LATENT_ASSAY:
        _require(measurement.kind is MeasurementKind.LATENT_ASSAY, "latent namespace cannot become native state")
    if schema.space is QuotientSpace.ARCHIVED_CONTROLLER:
        _require(measurement.kind is MeasurementKind.OBSERVATION,
                 "archived controller cannot be relabeled as a native pressure or latent assay")


@dataclass(frozen=True)
class ProposedEffect:
    owner_id: str
    expected_owner_revision: str
    operation: str
    payload_sha256: str

    def __post_init__(self) -> None:
        for name in ("owner_id", "expected_owner_revision", "operation"):
            _text(getattr(self, name), name)
        _digest(self.payload_sha256)


@dataclass(frozen=True)
class CandidateRecord(StackRecord):
    """CandidateTransition manifest; it has no apply/commit operation."""

    FAMILY: ClassVar[RecordFamily] = RecordFamily.CANDIDATE
    proposer_id: str
    effects: tuple[ProposedEffect, ...]
    dependencies: tuple[RecordRef, ...]

    def __post_init__(self) -> None:
        super().__post_init__()
        _text(self.proposer_id, "proposer_id")
        _items(self.effects, ProposedEffect, "effects", nonempty=True)
        _items(self.dependencies, RecordRef, "dependencies")
        _require(len(set(self.dependencies)) == len(self.dependencies), "duplicate candidate dependency")
        _require(len({(e.owner_id, e.operation) for e in self.effects}) == len(self.effects),
                 "duplicate owner/operation effects")


class CheckMethod(str, Enum):
    DOMAIN_CHECK = "domain_check"
    HUMAN_REVIEW = "human_review"
    SOURCE_COMPARISON = "source_comparison"
    MODEL_JUDGE = "model_judge"
    LATENT_READOUT = "latent_readout"


@dataclass(frozen=True)
class VerificationReceipt:
    candidate: RecordRef
    binding: TaskBinding
    execution_id: str
    answer_sha256: str
    verifier_id: str
    verifier_revision: str
    checked_property: str
    method: CheckMethod
    passed: bool | None
    evidence: tuple[SourceBinding, ...]
    freshness: Freshness

    def __post_init__(self) -> None:
        _require(isinstance(self.candidate, RecordRef)
                 and self.candidate.family is RecordFamily.CANDIDATE, "check requires a candidate")
        _require(isinstance(self.binding, TaskBinding), "invalid check binding")
        _digest(self.answer_sha256)
        for name in ("execution_id", "verifier_id", "verifier_revision", "checked_property"):
            _text(getattr(self, name), name)
        _require(isinstance(self.method, CheckMethod), "invalid check method")
        _require(self.passed is None or type(self.passed) is bool, "invalid check result")
        _items(self.evidence, SourceBinding, "check evidence", nonempty=True)
        _require(isinstance(self.freshness, Freshness), "invalid check freshness")


class ReviewResult(str, Enum):
    SUCCESS = "success"
    CORRECTION = "correction"
    FAILURE = "failure"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class OutcomeRecord(StackRecord):
    """Exact execution/review adapter; withdrawal is explicit, not a second count."""

    FAMILY: ClassVar[RecordFamily] = RecordFamily.OUTCOME
    candidate: RecordRef
    execution_id: str
    answer_sha256: str
    review_result: ReviewResult
    statement: EvidenceStatement
    review: VerificationReceipt | None
    withdrawn_by: SourceBinding | None
    replaces: RecordRef | None

    def __post_init__(self) -> None:
        super().__post_init__()
        _require(isinstance(self.candidate, RecordRef)
                 and self.candidate.family is RecordFamily.CANDIDATE, "outcome needs a candidate")
        _text(self.execution_id, "execution_id")
        _digest(self.answer_sha256)
        _require(isinstance(self.review_result, ReviewResult), "invalid review result")
        _require(isinstance(self.statement, EvidenceStatement), "invalid outcome statement")
        _require(self.withdrawn_by is None or isinstance(self.withdrawn_by, SourceBinding),
                 "invalid withdrawal link")
        _require(self.replaces is None or (isinstance(self.replaces, RecordRef)
                 and self.replaces.family is RecordFamily.OUTCOME), "invalid replacement link")
        if self.review is None:
            _require(self.review_result is ReviewResult.UNKNOWN, "unreviewed execution stays unknown")
        else:
            _require(isinstance(self.review, VerificationReceipt), "invalid review receipt")
            _require((self.review.candidate, self.review.binding, self.review.execution_id,
                      self.review.answer_sha256)
                     == (self.candidate, self.binding, self.execution_id, self.answer_sha256),
                     "review does not bind this exact execution")
            if self.review_result is not ReviewResult.UNKNOWN:
                _require(self.review.method not in (CheckMethod.LATENT_READOUT, CheckMethod.MODEL_JUDGE),
                         "latent scores/model judges alone cannot qualify a reviewed outcome")
                _require(self.review.passed is not None, "unknown check remains unrated")
                _require(self.review.passed == (self.review_result is not ReviewResult.FAILURE),
                         "review result conflicts with the checked property")


@dataclass(frozen=True)
class DevelopmentRecord(StackRecord):
    """DevelopmentProposal adapter; existing channel owners retain admission."""

    FAMILY: ClassVar[RecordFamily] = RecordFamily.DEVELOPMENT
    channel: DevelopmentChannel
    transition_schema: str
    cadence: str
    owner_id: str
    accepted_evidence_types: tuple[EpistemicType, ...]
    epistemic_type: EpistemicType
    evidence: tuple[RecordRef, ...]
    dependencies: tuple[RecordRef, ...]
    coupled_candidate: RecordRef
    consent: SourceBinding
    revocation_policy: SourceBinding
    lineage: tuple[SourceBinding, ...]

    def __post_init__(self) -> None:
        super().__post_init__()
        _require(self.header.loop is OperatingLoop.DEVELOPMENT, "development requires its own loop")
        _require(isinstance(self.channel, DevelopmentChannel), "invalid development channel")
        for name in ("transition_schema", "cadence", "owner_id"):
            _text(getattr(self, name), name)
        _items(self.accepted_evidence_types, EpistemicType, "accepted evidence types", nonempty=True)
        _require(isinstance(self.epistemic_type, EpistemicType), "invalid developmental epistemic type")
        _items(self.evidence, RecordRef, "development evidence", nonempty=True)
        _require(len(set(self.evidence)) == len(self.evidence), "duplicate developmental evidence")
        _require(all(ref.family is RecordFamily.OUTCOME for ref in self.evidence),
                 "development requires reviewed outcomes, not latent measurements")
        _items(self.dependencies, RecordRef, "development dependencies")
        _require(isinstance(self.coupled_candidate, RecordRef)
                 and self.coupled_candidate.family is RecordFamily.CANDIDATE,
                 "development needs a complete coupled candidate")
        _require(isinstance(self.consent, SourceBinding), "consent binding is required")
        _require(isinstance(self.revocation_policy, SourceBinding), "revocation binding is required")
        _items(self.lineage, SourceBinding, "development lineage", nonempty=True)


def validate_bound_record(record: StackRecord, task: TaskRecord, *, now: datetime,
                          current_binding: TaskBinding,
                          invalidated: frozenset[RecordRef]) -> None:
    """Compare supplied current owner context; this function does not fetch it."""
    _require(isinstance(invalidated, frozenset), "invalidated references must be a frozenset")
    task.header.freshness.require_current(now)
    record.header.freshness.require_current(now)
    _require(record.header.scope == task.header.scope, "cross-user/domain/world route")
    _require(record.binding == task.binding == current_binding, "stale task/source/policy binding")
    _require(record.reference not in invalidated and task.reference not in invalidated,
             "record or task was invalidated")


def validate_candidate(candidate: CandidateRecord, task: TaskRecord, *, now: datetime,
                       current_binding: TaskBinding, current_owners: tuple[SourceBinding, ...],
                       required_effects: tuple[ProposedEffect, ...],
                       dependencies: tuple[StackRecord, ...],
                       invalidated: frozenset[RecordRef]) -> None:
    """Check an exact caller-supplied complete effect manifest and owner revisions."""
    validate_bound_record(candidate, task, now=now, current_binding=current_binding,
                          invalidated=invalidated)
    _items(current_owners, SourceBinding, "current owner bindings")
    _items(required_effects, ProposedEffect, "required effects", nonempty=True)
    _items(dependencies, StackRecord, "dependency records")
    _require(candidate.effects == required_effects, "candidate effects are incomplete, reordered, or changed")
    _require(len({o.source_id for o in current_owners}) == len(current_owners), "duplicate owner identity")
    for effect in candidate.effects:
        _require(any(o.source_id == effect.owner_id and o.revision == effect.expected_owner_revision
                     for o in current_owners), "missing or stale destination owner revision")
    _require({r.reference for r in dependencies} == set(candidate.dependencies), "dependency binding mismatch")
    for dependency in dependencies:
        validate_bound_record(dependency, task, now=now, current_binding=current_binding,
                              invalidated=invalidated)


def validate_outcome(outcome: OutcomeRecord, candidate: CandidateRecord, task: TaskRecord, *,
                     now: datetime, current_binding: TaskBinding,
                     expected_execution_id: str, expected_answer_sha256: str,
                     invalidated: frozenset[RecordRef]) -> None:
    """Validate attribution only. This neither counts nor promotes an outcome."""
    for record in (outcome, candidate):
        validate_bound_record(record, task, now=now, current_binding=current_binding,
                              invalidated=invalidated)
    _require(outcome.candidate == candidate.reference, "outcome binds a different candidate")
    _require((outcome.execution_id, outcome.answer_sha256)
             == (expected_execution_id, expected_answer_sha256), "execution binding mismatch")
    _require(outcome.withdrawn_by is None, "withdrawn outcome is not retained evidence")
    if outcome.review is not None:
        outcome.review.freshness.require_current(now)
        _require(outcome.review.verifier_id != candidate.proposer_id,
                 "a proposer cannot qualify its own outcome")


def validate_development(development: DevelopmentRecord, task: TaskRecord, *, now: datetime,
                         current_binding: TaskBinding, candidate: CandidateRecord,
                         outcomes: tuple[OutcomeRecord, ...],
                         outcome_candidates: tuple[CandidateRecord, ...],
                         dependencies: tuple[StackRecord, ...],
                         current_consent: SourceBinding, current_revocation_policy: SourceBinding,
                         invalidated: frozenset[RecordRef]) -> None:
    """Validate proposal references; owner consent/evidence policy still decides admission."""
    for record in (development, candidate):
        validate_bound_record(record, task, now=now, current_binding=current_binding,
                              invalidated=invalidated)
    _items(outcomes, OutcomeRecord, "development outcomes", nonempty=True)
    _items(outcome_candidates, CandidateRecord, "reviewed outcome candidates", nonempty=True)
    _items(dependencies, StackRecord, "development dependencies")
    _require(development.coupled_candidate == candidate.reference, "coupled candidate mismatch")
    _require(any(e.owner_id == development.owner_id for e in candidate.effects), "missing channel owner effect")
    _require((development.consent, development.revocation_policy)
             == (current_consent, current_revocation_policy), "stale consent or revocation policy")
    _require({o.reference for o in outcomes} == set(development.evidence), "development evidence mismatch")
    _require(len({(o.binding.task_id, o.execution_id) for o in outcomes}) == len(outcomes),
             "one execution cannot become multiple developmental evidence events")
    _require({d.reference for d in dependencies} == set(development.dependencies), "development dependency mismatch")
    # Retained experience may originate in older tasks. Preserve its original
    # request binding and require its exact reviewed candidate, scope and freshness.
    _require({c.reference for c in outcome_candidates} == {o.candidate for o in outcomes},
             "missing or unrelated historical outcome candidate")
    for record in (*outcomes, *outcome_candidates, *dependencies):
        record.header.freshness.require_current(now)
        _require(record.header.scope == development.header.scope, "cross-scope developmental evidence")
        _require(record.reference not in invalidated, "invalidated developmental evidence")
    for outcome in outcomes:
        _require(outcome.withdrawn_by is None and outcome.review_result in
                 (ReviewResult.SUCCESS, ReviewResult.CORRECTION), "unqualified developmental evidence")
        _require(outcome.review is not None, "developmental evidence requires a review")
        outcome.review.freshness.require_current(now)
        original_candidate = next(c for c in outcome_candidates if c.reference == outcome.candidate)
        _require(outcome.binding == original_candidate.binding, "historical task binding mismatch")
        _require(outcome.review.verifier_id != original_candidate.proposer_id,
                 "self-reviewed history cannot award development")
        _require(outcome.statement.epistemic_type in development.accepted_evidence_types,
                 "evidence type is not admitted by this channel schema")
        _require(outcome.statement.epistemic_type == development.epistemic_type,
                 "development cannot relabel fictional, simulated, or inferred evidence")


class RouteOperation(str, Enum):
    MEASURE_TASK = "measure_task"
    PROPOSE_FROM_TASK = "propose_from_task"
    INFORM_PROPOSAL = "inform_proposal"
    REVIEW_EXECUTION = "review_execution"
    OBSERVE_FEEDBACK = "observe_feedback"
    SUPPORT_DEVELOPMENT = "support_development"
    COMPILE_DEVELOPMENT = "compile_development"


_DIRECTIONS = (
    (RecordFamily.TASK, RecordFamily.MEASUREMENT, RouteOperation.MEASURE_TASK),
    (RecordFamily.TASK, RecordFamily.CANDIDATE, RouteOperation.PROPOSE_FROM_TASK),
    (RecordFamily.MEASUREMENT, RecordFamily.CANDIDATE, RouteOperation.INFORM_PROPOSAL),
    (RecordFamily.CANDIDATE, RecordFamily.OUTCOME, RouteOperation.REVIEW_EXECUTION),
    (RecordFamily.OUTCOME, RecordFamily.MEASUREMENT, RouteOperation.OBSERVE_FEEDBACK),
    (RecordFamily.OUTCOME, RecordFamily.DEVELOPMENT, RouteOperation.SUPPORT_DEVELOPMENT),
    (RecordFamily.DEVELOPMENT, RecordFamily.CANDIDATE, RouteOperation.COMPILE_DEVELOPMENT),
)


@dataclass(frozen=True)
class DirectedEdge:
    source: RecordRef
    destination: RecordRef
    operation: RouteOperation
    scope: Scope
    provenance: SourceBinding
    destination_owner: str
    admission_requirement: str

    def __post_init__(self) -> None:
        _require(isinstance(self.source, RecordRef) and isinstance(self.destination, RecordRef),
                 "invalid edge endpoints")
        _require(isinstance(self.operation, RouteOperation), "invalid route operation")
        _require((self.source.family, self.destination.family, self.operation) in _DIRECTIONS,
                 "route direction/operation has no declared contract")
        _require(isinstance(self.scope, Scope) and isinstance(self.provenance, SourceBinding),
                 "edge needs scope and provenance")
        _text(self.destination_owner, "destination owner")
        _text(self.admission_requirement, "admission requirement")


def validate_edge(edge: DirectedEdge, source: StackRecord, destination: StackRecord, *,
                  now: datetime, invalidated: frozenset[RecordRef]) -> None:
    """Only explicit one-way information routes; no inverse or durable write is inferred."""
    _require((edge.source, edge.destination) == (source.reference, destination.reference),
             "edge does not bind supplied endpoints")
    _require(edge.scope == source.header.scope == destination.header.scope, "edge scope mismatch")
    # Historical outcome support is a distinct declared route; every other route
    # is within the exact current request. It never rewrites the older binding.
    if edge.operation is not RouteOperation.SUPPORT_DEVELOPMENT:
        _require(source.binding == destination.binding, "edge crosses task/source/policy binding")
    for record in (source, destination):
        record.header.freshness.require_current(now)
        _require(record.reference not in invalidated, "edge endpoint invalidated")
    if edge.operation is RouteOperation.REVIEW_EXECUTION:
        _require(isinstance(destination, OutcomeRecord) and destination.candidate == source.reference,
                 "outcome does not reference the source candidate")
    if edge.operation is RouteOperation.INFORM_PROPOSAL:
        _require(isinstance(destination, CandidateRecord) and source.reference in destination.dependencies,
                 "proposal does not reference the informing measurement")
    if edge.operation is RouteOperation.OBSERVE_FEEDBACK:
        _require(isinstance(destination, MeasurementRecord) and source.reference in destination.input_links,
                 "feedback observation does not reference the original outcome")
    if edge.operation is RouteOperation.SUPPORT_DEVELOPMENT:
        _require(isinstance(destination, DevelopmentRecord) and source.reference in destination.evidence,
                 "development does not reference the source outcome")
    if edge.operation is RouteOperation.COMPILE_DEVELOPMENT:
        _require(isinstance(source, DevelopmentRecord) and source.coupled_candidate == destination.reference,
                 "development does not reference the complete candidate")


@dataclass(frozen=True)
class ExperimentRelease:
    """Research-loop manifest, not an installer or an automatic promotion decision."""

    release_id: str
    source: SourceBinding
    configuration: SourceBinding
    data: SourceBinding
    model: SourceBinding
    evaluator: SourceBinding
    held_out_manifest: SourceBinding
    evaluation_report: SourceBinding | None
    costs: tuple[ResourceAmount, ...]
    approval: SourceBinding | None
    proposer_id: str
    evaluator_owner_id: str
    release_owner_id: str

    def __post_init__(self) -> None:
        for name in ("release_id", "proposer_id", "evaluator_owner_id", "release_owner_id"):
            _text(getattr(self, name), name)
        for name in ("source", "configuration", "data", "model", "evaluator", "held_out_manifest"):
            _require(isinstance(getattr(self, name), SourceBinding), f"{name} pin is required")
        for name in ("evaluation_report", "approval"):
            _require(getattr(self, name) is None or isinstance(getattr(self, name), SourceBinding),
                     f"invalid {name}")
        _items(self.costs, ResourceAmount, "release costs")

    def require_complete_manifest(self, *, required_cost_units: tuple[tuple[str, str], ...]) -> None:
        """Structural prerequisite only; a complete manifest does not authorize release."""
        _require(self.evaluation_report is not None and self.approval is not None,
                 "evaluation report and release approval are missing")
        _require(self.proposer_id not in (self.evaluator_owner_id, self.release_owner_id),
                 "proposer cannot own evaluation or release approval")
        _require(isinstance(required_cost_units, tuple) and bool(required_cost_units),
                 "required cost units must be declared")
        _require(len({(c.resource, c.unit) for c in self.costs}) == len(self.costs),
                 "duplicate release cost units")
        for resource, unit in required_cost_units:
            _require(any(c.resource == resource and c.unit == unit and c.amount is not None
                         for c in self.costs), "mandatory cost is missing or unknown")
