"""Request-owned activation access for a caller's already-loaded PyTorch model.

This experimental adapter never loads a model, opens a path, or calls a service.
It supports one explicit layer, batch one, CPU/CUDA float32/float64, ordinary
eager execution, and the last token of a [batch, sequence, hidden] tensor. A layer
may return that tensor directly or as item zero of an ordinary tuple. Padding
must leave the last token meaningful. Compiled/scripted, distributed, quantized,
mixed-precision, training, asynchronous/streaming, and arbitrary cache-bearing
custom runtimes are outside this contract.

Identity values are assertions supplied by an owner that checked actual bytes;
matching strings here is data binding, not model authentication. A pre-edit
sample is BEFORE THIS EDIT, not an independent baseline: earlier interventions
in the trajectory can already influence it. Samples never certify correctness
or become native task outcomes. The adapter retains only bounded scalar samples,
not activation tensors. Removing hooks does not undo emitted output.

All calls to a shared model must honor this ownership protocol. The guards reject
another scope or a forward in another thread/context while this scope is active,
including overlapping registered submodules. Direct ``.forward`` calls bypassing
PyTorch's hook machinery, custom background work, monkey-patching, mutations by
other code, and arbitrary user callbacks cannot be made safe by hooks alone.
"""

from __future__ import annotations

import asyncio
from contextvars import ContextVar, Token
from dataclasses import dataclass
from enum import Enum
import inspect
import math
import re
import threading
from typing import Any, Callable, Mapping
from uuid import UUID
import weakref

import torch
from torch import Tensor, nn
from torch.utils.hooks import RemovableHandle


class RepEUnavailable(RuntimeError):
    """The explicitly requested experimental capability cannot be provided."""


class RequestCancelled(RuntimeError):
    """Cooperative cancellation observed at a request or model-call boundary."""


class RequestConflict(RepEUnavailable):
    """The same model or an overlapping submodule already has an owner."""


class Mode(str, Enum):
    OFF = "off"
    SHADOW = "shadow"
    BOUNDED = "bounded"


class TokenRule(str, Enum):
    LAST = "last"


class OutputKind(str, Enum):
    TENSOR = "tensor"
    TUPLE_FIRST = "tuple_first"


@dataclass(frozen=True)
class SHA256Digest:
    value: str

    def __post_init__(self) -> None:
        if not isinstance(self.value, str) or re.fullmatch(r"[0-9a-f]{64}", self.value) is None:
            raise ValueError("A digest must contain exactly 64 lowercase hexadecimal characters")


@dataclass(frozen=True)
class ModelIdentity:
    model_digest: SHA256Digest
    tokenizer_digest: SHA256Digest
    template_digest: SHA256Digest
    backend_revision: str
    precision: str

    def __post_init__(self) -> None:
        for value in (self.model_digest, self.tokenizer_digest, self.template_digest):
            if type(value) is not SHA256Digest:
                raise TypeError("Model identity requires typed SHA256Digest values")
        _label(self.backend_revision, "backend_revision")
        if self.precision not in ("float32", "float64"):
            raise ValueError("Only float32 and float64 model identities are supported")


@dataclass(frozen=True)
class BasisIdentity:
    namespace: str
    model: ModelIdentity
    basis_digest: SHA256Digest
    reader_digest: SHA256Digest
    calibration_digest: SHA256Digest
    layer: str
    token_rule: TokenRule = TokenRule.LAST

    def __post_init__(self) -> None:
        _label(self.namespace, "namespace")
        _label(self.layer, "layer")
        if type(self.model) is not ModelIdentity:
            raise TypeError("Basis identity requires a ModelIdentity")
        for value in (self.basis_digest, self.reader_digest, self.calibration_digest):
            if type(value) is not SHA256Digest:
                raise TypeError("Basis identity requires typed SHA256Digest values")
        if self.token_rule is not TokenRule.LAST:
            raise ValueError("Only the explicit last-token rule is implemented")


@dataclass(frozen=True)
class RequestBinding:
    request_id: UUID
    input_digest: SHA256Digest
    system_digest: SHA256Digest
    schema_digest: SHA256Digest

    def __post_init__(self) -> None:
        if type(self.request_id) is not UUID:
            raise TypeError("request_id must be a UUID")
        for value in (self.input_digest, self.system_digest, self.schema_digest):
            if type(value) is not SHA256Digest:
                raise TypeError("Request binding requires typed SHA256Digest values")


@dataclass(frozen=True)
class LayerAssayBasis:
    """Frozen metadata and caller-supplied tensors, snapshotted when entering.

    ``directions`` has shape [hidden, readers], with unit-norm columns. ``center``
    has shape [hidden]. ``score_offset`` and positive ``score_scale`` have shape
    [readers]. Coordinates are sigmoid((raw - offset) / scale), not probabilities.
    Caller tensors must not be mutated concurrently with context entry.
    """

    identity: BasisIdentity
    names: tuple[str, ...]
    directions: Tensor
    center: Tensor
    score_offset: Tensor
    score_scale: Tensor
    output_kind: OutputKind = OutputKind.TENSOR


@dataclass(frozen=True)
class SteeringBudget:
    """Explicit numerical experiment settings; no validated safety threshold."""

    coefficients: tuple[float, ...]
    coefficient_cap: float
    relative_norm_cap: float

    def __post_init__(self) -> None:
        if type(self.coefficients) is not tuple or not self.coefficients:
            raise ValueError("coefficients must be a nonempty immutable tuple")
        for value in self.coefficients:
            _finite_number(value, "coefficient")
        _finite_number(self.coefficient_cap, "coefficient_cap")
        _finite_number(self.relative_norm_cap, "relative_norm_cap")
        if self.coefficient_cap < 0 or not 0 <= self.relative_norm_cap <= 1:
            raise ValueError("coefficient_cap must be nonnegative and relative_norm_cap in [0, 1]")


@dataclass(frozen=True)
class ScalarSample:
    """No activation tensor is retained. token_index is a layer-call ordinal.

    With use_cache=False, each call can recompute the complete prefix. The ordinal
    is not asserted to be a tokenizer position or a unique emitted answer token;
    token_position records the selected position within this forward's sequence.
    """

    token_index: int
    token_position: int
    phase: str
    raw_scores: tuple[float, ...]
    normalized_scores: tuple[float, ...]
    coordinates: tuple[float, ...]
    hidden_norm: float
    edit_norm: float
    independent_baseline: bool = False


@dataclass(frozen=True)
class SamplePair:
    before: ScalarSample
    after: ScalarSample


@dataclass(frozen=True)
class RequestReport:
    binding: RequestBinding
    model: ModelIdentity
    basis: BasisIdentity | None
    mode: Mode
    names: tuple[str, ...]
    samples: tuple[SamplePair, ...]
    observed_layer_calls: int
    dropped_sample_pairs: int
    outcome: str
    cleanup_errors: tuple[str, ...] = ()
    warning: str = (
        "Pre-current-edit samples may reflect earlier layer/token interventions. "
        "They are not independent unsteered baselines. Coordinates are operational "
        "assays, not calibrated probabilities or verified task outcomes."
    )


@dataclass(frozen=True)
class GenerationResult:
    output: str | Tensor
    report: RequestReport


def _label(value: str, name: str) -> None:
    if not isinstance(value, str) or not value.strip() or len(value) > 512:
        raise ValueError(f"{name} must be a nonempty string of at most 512 characters")


def _finite_number(value: float, name: str) -> None:
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value):
        raise ValueError(f"{name} must be a finite number")


_ACTIVE_OWNER: ContextVar[object | None] = ContextVar("archi_repe_owner", default=None)
_REGISTRY_LOCK = threading.Lock()
_OWNERS: dict[int, tuple[weakref.ReferenceType[nn.Module], object]] = {}
_CACHE_ARGUMENTS = frozenset(("past_key_values", "past_key_value", "past", "mems", "cache"))
_CAPTURE_ARGUMENTS = frozenset(("output_hidden_states", "output_attentions"))
_DTYPES = {"float32": torch.float32, "float64": torch.float64}


def _current_task() -> object | None:
    try:
        return asyncio.current_task()
    except RuntimeError:
        return None


class TorchRequestScope:
    """Single-use synchronous owner of hooks and scalar samples for one request.

    Model/module lookup is confined to the supplied object. No global hook is
    installed. Shared module graphs are reserved atomically and competing scopes
    fail immediately. All forward calls must stay on the entering thread and
    context, using normal module invocation. Training flags and owned hooks are
    restored on exit (including BaseException); weights and buffers are never
    intentionally mutated by this adapter. Arbitrary callback mutation of model
    weights/buffers or custom runtime caches is unsupported and cannot be rolled
    back by this context manager.

    For standard generation use ``generate_in_scope``. Direct scope users must
    pass use_cache=False if the model exposes a cache switch. Cooperative
    cancellation is checked before/after root forwards and at the assay layer;
    this cannot interrupt an already running native kernel.
    """

    def __init__(
        self,
        *,
        model: nn.Module,
        model_identity: ModelIdentity,
        binding: RequestBinding,
        mode: Mode = Mode.OFF,
        basis: LayerAssayBasis | None = None,
        expected_basis: BasisIdentity | None = None,
        steering: SteeringBudget | None = None,
        experimental_steering_enabled: bool = False,
        max_sample_pairs: int = 64,
        cancelled: Callable[[], bool] | None = None,
        require_explicit_cache_disable: bool = False,
    ) -> None:
        if not isinstance(model, nn.Module):
            raise TypeError("model must be an already-loaded torch.nn.Module")
        if type(model_identity) is not ModelIdentity or type(binding) is not RequestBinding:
            raise TypeError("model_identity and binding must use their typed contracts")
        if type(mode) is not Mode:
            raise TypeError("mode must be an explicit Mode enum")
        if type(max_sample_pairs) is not int or not 0 <= max_sample_pairs <= 2048:
            raise ValueError("max_sample_pairs must be an integer from 0 through 2048")
        if type(experimental_steering_enabled) is not bool or type(require_explicit_cache_disable) is not bool:
            raise TypeError("feature switches must be bool")
        if cancelled is not None and not callable(cancelled):
            raise TypeError("cancelled must be a callable or None")
        if mode is Mode.OFF:
            if basis is not None or expected_basis is not None or steering is not None:
                raise ValueError("OFF mode does not accept basis or steering settings")
        else:
            if type(basis) is not LayerAssayBasis or type(expected_basis) is not BasisIdentity:
                raise RepEUnavailable("An assay requires a basis and an explicit expected identity")
            if basis.identity != expected_basis or basis.identity.model != model_identity:
                raise RepEUnavailable("Exact model/basis identity mismatch")
        if mode is Mode.BOUNDED:
            if not experimental_steering_enabled or type(steering) is not SteeringBudget:
                raise RepEUnavailable("Bounded steering requires explicit opt-in and an explicit budget")
        elif steering is not None:
            raise ValueError("Steering settings require BOUNDED mode")
        self.model = model
        self.model_identity = model_identity
        self.binding = binding
        self.mode = mode
        self.basis = basis
        self.steering = steering
        self.max_sample_pairs = max_sample_pairs
        self.cancelled = cancelled
        self.require_explicit_cache_disable = require_explicit_cache_disable
        self._owner = object()
        self._thread_id: int | None = None
        self._task: object | None = None
        self._context_token: Token | None = None
        self._modules: tuple[nn.Module, ...] = ()
        self._training: tuple[bool, ...] = ()
        self._handles: list[RemovableHandle] = []
        self._samples: list[SamplePair] = []
        self._calls = 0
        self._dropped = 0
        self._state = "created"
        self._inference: Any = None
        self._forward_signature: inspect.Signature | None = None
        self._layer: nn.Module | None = None
        self._directions: Tensor | None = None
        self._center: Tensor | None = None
        self._offset: Tensor | None = None
        self._scale: Tensor | None = None
        self._coefficients: Tensor | None = None
        self._device: torch.device | None = None
        self._failure: str | None = None
        self._cleanup_errors: tuple[str, ...] = ()

    def __enter__(self) -> TorchRequestScope:
        if self._state != "created":
            raise RequestConflict("Request scopes are single use")
        self._state = "entering"
        try:
            self.check_cancelled()
            if isinstance(self.model, torch.jit.ScriptModule) or hasattr(self.model, "_orig_mod"):
                raise RepEUnavailable("Compiled/scripted models are not supported")
            self._modules = tuple(self.model.modules())
            self._reserve()
            self._thread_id = threading.get_ident()
            self._task = _current_task()
            self._context_token = _ACTIVE_OWNER.set(self._owner)
            self._training = tuple(module.training for module in self._modules)
            self._validate_model()
            if self.basis is not None:
                self._prepare_basis()
            self._forward_signature = inspect.signature(self.model.forward)
            # Set only standard flags, avoiding arbitrary custom train() side effects.
            for module in self._modules:
                module.training = False
            self._inference = torch.inference_mode()
            self._inference.__enter__()
            self._handles.append(self.model.register_forward_pre_hook(self._before_model, with_kwargs=True, prepend=True))
            self._handles.append(self.model.register_forward_hook(self._after_model, always_call=True))
            if self._layer is not None:
                self._handles.append(self._layer.register_forward_hook(self._on_layer))
            self._state = "active"
            return self
        except BaseException as error:
            self._state = "failed"
            self._annotate_cleanup(error, self._cleanup())
            raise

    def __exit__(self, exc_type: Any, exc_value: Any, traceback: Any) -> bool:
        try:
            if exc_type is None:
                if self._failure == "cancelled":
                    raise RequestCancelled("The request previously observed cancellation")
                if self._failure is not None:
                    raise RepEUnavailable("A failed request cannot return successful output")
                self.check_cancelled()
                if self.mode is not Mode.OFF and self._calls == 0:
                    raise RepEUnavailable("The request never visited its exact assay layer")
                self._state = "completed"
            else:
                self._state = "cancelled" if isinstance(exc_value, RequestCancelled) else "failed"
        except BaseException as error:
            self._state = "cancelled" if isinstance(error, RequestCancelled) else "failed"
            self._annotate_cleanup(error, self._cleanup())
            raise
        cleanup_errors = self._cleanup()
        if cleanup_errors:
            self._state = "failed"
            if exc_value is not None:
                self._annotate_cleanup(exc_value, cleanup_errors)
            else:
                raise RepEUnavailable("Request cleanup failed; inspect report().cleanup_errors") from cleanup_errors[0]
        return False

    def check_cancelled(self) -> None:
        if self.cancelled is not None and self.cancelled():
            self._failure = "cancelled"
            raise RequestCancelled("Experimental request was cancelled")

    def report(self) -> RequestReport:
        """Snapshot bounded scalar diagnostics, including failed request status."""
        return RequestReport(
            self.binding, self.model_identity, self.basis.identity if self.basis else None,
            self.mode, self.basis.names if self.basis else (), tuple(self._samples),
            self._calls, self._dropped, self._state, self._cleanup_errors,
        )

    def _reserve(self) -> None:
        with _REGISTRY_LOCK:
            for module in self._modules:
                entry = _OWNERS.get(id(module))
                if entry is not None and entry[0]() is module:
                    raise RequestConflict("The model or a shared submodule has an active request")
            for module in self._modules:
                _OWNERS[id(module)] = (weakref.ref(module), self._owner)

    def _assert_owner(self) -> None:
        if self._failure is not None:
            raise RepEUnavailable("This request previously failed and cannot continue")
        if _ACTIVE_OWNER.get() is not self._owner or threading.get_ident() != self._thread_id or _current_task() is not self._task:
            raise RequestConflict("Forward execution crossed the request's thread/context boundary")
        if self._state != "active":
            raise RequestConflict("Forward execution outside the active request scope")

    def _validate_model(self) -> None:
        # Existing hooks may transform an apparent SHADOW trajectory. Refuse them
        # rather than claiming an unsteered measurement. Do not remove their state.
        for module in self._modules:
            if module._forward_hooks or module._forward_pre_hooks:
                raise RepEUnavailable("Pre-existing model/submodule forward hooks are unsupported")
        module_runtime = nn.modules.module
        if getattr(module_runtime, "_global_forward_hooks", {}) or getattr(module_runtime, "_global_forward_pre_hooks", {}):
            raise RepEUnavailable("Global PyTorch forward hooks are unsupported")
        expected_dtype = _DTYPES[self.model_identity.precision]
        devices: set[torch.device] = set()
        for tensor in (*self.model.parameters(), *self.model.buffers()):
            if tensor.device.type not in ("cpu", "cuda") or tensor.is_quantized:
                raise RepEUnavailable("Only unquantized CPU/CUDA tensors are supported")
            if tensor.is_floating_point() and tensor.dtype != expected_dtype:
                raise RepEUnavailable("Model precision does not match the supplied identity")
            if tensor.is_complex():
                raise RepEUnavailable("Complex model tensors are unsupported")
            devices.add(tensor.device)
        if len(devices) > 1:
            raise RepEUnavailable("A request requires a single-device model")
        self._device = next(iter(devices), None)

    def _prepare_basis(self) -> None:
        assert self.basis is not None
        basis = self.basis
        if type(basis.output_kind) is not OutputKind:
            raise TypeError("output_kind must be an explicit OutputKind enum")
        if type(basis.names) is not tuple or not 1 <= len(basis.names) <= 32:
            raise ValueError("Basis must name 1 through 32 readers in an immutable tuple")
        for name in basis.names:
            _label(name, "reader name")
        if len(set(basis.names)) != len(basis.names):
            raise ValueError("Reader names must be unique")
        try:
            self._layer = self.model.get_submodule(basis.identity.layer)
        except (AttributeError, KeyError) as error:
            raise RepEUnavailable("The exact requested layer is unavailable") from error
        if self._layer is self.model:
            raise RepEUnavailable("Select an explicit internal layer, not the root module")
        snapshots: list[Tensor] = []
        for tensor in (basis.directions, basis.center, basis.score_offset, basis.score_scale):
            if not isinstance(tensor, Tensor) or tensor.dtype not in (torch.float32, torch.float64):
                raise ValueError("Basis arrays must be float32/float64 torch tensors")
            if tensor.device.type not in ("cpu", "cuda") or tensor.layout != torch.strided:
                raise ValueError("Basis arrays require dense CPU/CUDA tensors")
            copied = tensor.detach().to(device=self._device or tensor.device, dtype=torch.float64).clone()
            if not bool(torch.isfinite(copied).all()):
                raise ValueError("Basis contains nonfinite values")
            snapshots.append(copied)
        self._directions, self._center, self._offset, self._scale = snapshots
        directions, center, offset, scale = snapshots
        if directions.ndim != 2 or directions.shape[0] < 1 or directions.shape[1] != len(basis.names):
            raise ValueError("Directions must have shape [hidden, named_readers]")
        if center.shape != (directions.shape[0],) or offset.shape != (len(basis.names),) or scale.shape != offset.shape:
            raise ValueError("Basis center/normalization shapes do not match the directions")
        if not bool((scale > 0).all()):
            raise ValueError("Normalization scales must be positive")
        norms = torch.linalg.vector_norm(directions, dim=0)
        if not bool(torch.isfinite(norms).all()) or not bool(torch.allclose(norms, torch.ones_like(norms), atol=1e-6, rtol=1e-6)):
            raise ValueError("Steering/reader direction columns must have unit norm")
        if len({tensor.device for tensor in snapshots}) != 1:
            raise ValueError("Basis tensors must be on one device")
        if self.steering is not None:
            if len(self.steering.coefficients) != len(basis.names):
                raise ValueError("One steering coefficient is required per direction")
            self._coefficients = torch.tensor(self.steering.coefficients, dtype=torch.float64, device=directions.device).clamp(
                -self.steering.coefficient_cap, self.steering.coefficient_cap,
            )

    def _before_model(self, module: nn.Module, args: tuple[Any, ...], kwargs: dict[str, Any]) -> None:
        self._assert_owner()
        try:
            self.check_cancelled()
            assert self._forward_signature is not None
            bound = self._forward_signature.bind_partial(*args, **kwargs)
            arguments = dict(bound.arguments)
            for name, parameter in self._forward_signature.parameters.items():
                if parameter.kind is inspect.Parameter.VAR_KEYWORD:
                    arguments.update(arguments.pop(name, {}))
            for name in _CACHE_ARGUMENTS:
                if arguments.get(name) is not None:
                    raise RepEUnavailable("Cross-call KV/cache inputs are unsupported")
            if "use_cache" in arguments and arguments["use_cache"] is not False:
                raise RepEUnavailable("use_cache must be explicitly False")
            exposes_cache = "use_cache" in self._forward_signature.parameters or hasattr(getattr(module, "config", None), "use_cache")
            if (self.require_explicit_cache_disable or exposes_cache) and arguments.get("use_cache") is not False:
                raise RepEUnavailable("Generation must disable caching on every model forward")
            for name in _CAPTURE_ARGUMENTS:
                if arguments.get(name) not in (None, False):
                    raise RepEUnavailable("Hidden-state/attention capture is outside the scalar-only contract")
            for name in ("input_ids", "inputs_embeds", "attention_mask"):
                value = arguments.get(name)
                if isinstance(value, Tensor) and (value.ndim < 2 or value.shape[0] != 1):
                    raise RepEUnavailable("Only batch-one inputs are supported")
        except BaseException:
            self._failure = self._failure or "failed"
            raise

    def _after_model(self, module: nn.Module, args: tuple[Any, ...], output: Any) -> None:
        # An always-call hook sees None when forward throws. Preserve that original
        # error while preventing a callback from swallowing it and claiming success.
        if output is None:
            if _ACTIVE_OWNER.get() is self._owner and threading.get_ident() == self._thread_id and _current_task() is self._task:
                self._failure = self._failure or "failed"
            return
        self._assert_owner()
        self.check_cancelled()

    def _on_layer(self, module: nn.Module, args: tuple[Any, ...], output: Any) -> Any:
        self._assert_owner()
        try:
            self.check_cancelled()
            return self._process_layer(output)
        except BaseException:
            self._failure = self._failure or "failed"
            raise

    def _process_layer(self, output: Any) -> Any:
        assert self.basis is not None and self._directions is not None
        if self.basis.output_kind is OutputKind.TENSOR:
            activation = output
        elif type(output) is tuple and output:
            activation = output[0]
        else:
            raise RepEUnavailable("Layer output does not match the explicit tensor/tuple contract")
        if not isinstance(activation, Tensor) or activation.layout != torch.strided:
            raise RepEUnavailable("Layer activation must be a dense tensor")
        if activation.ndim != 3 or activation.shape[0] != 1 or activation.shape[1] < 1 or activation.shape[2] != self._directions.shape[0]:
            raise RepEUnavailable("Expected [1, nonempty_sequence, basis_hidden_size] activation")
        if activation.dtype != _DTYPES[self.model_identity.precision] or activation.device != self._directions.device:
            raise RepEUnavailable("Activation precision/device does not match the model-bound basis")
        if not bool(torch.isfinite(activation).all()):
            raise RepEUnavailable("Layer activation contains nonfinite values")
        hidden = activation[0, -1, :].detach()
        hidden64 = hidden.to(dtype=torch.float64)
        hidden_norm = float(torch.linalg.vector_norm(hidden64).item())
        if not math.isfinite(hidden_norm):
            raise RepEUnavailable("Hidden norm is not finite")
        self._calls += 1
        index, position = self._calls - 1, activation.shape[1] - 1
        candidate, edit_norm = hidden, 0.0
        if self.mode is Mode.BOUNDED:
            candidate, edit_norm = self._bounded_edit(hidden, hidden64, hidden_norm)
        if len(self._samples) < self.max_sample_pairs:
            before = self._sample(hidden64, index, position, "pre_current_edit", hidden_norm, 0.0)
            after64 = candidate.to(dtype=torch.float64)
            after_norm = float(torch.linalg.vector_norm(after64).item())
            after = self._sample(after64, index, position, "post_current_edit", after_norm, edit_norm)
            self._samples.append(SamplePair(before, after))
        else:
            self._dropped += 1
        self.check_cancelled()
        if edit_norm == 0:
            return output
        changed = activation.clone()
        changed[0, -1, :] = candidate
        return changed if self.basis.output_kind is OutputKind.TENSOR else (changed, *output[1:])

    def _bounded_edit(self, hidden: Tensor, hidden64: Tensor, hidden_norm: float) -> tuple[Tensor, float]:
        assert self.steering is not None and self._directions is not None and self._coefficients is not None
        if hidden_norm == 0 or self.steering.relative_norm_cap == 0:
            return hidden, 0.0
        # The cap is applied to the TOTAL edit after coefficient clipping.
        delta = self._directions @ self._coefficients
        delta_norm = float(torch.linalg.vector_norm(delta).item())
        if not math.isfinite(delta_norm):
            raise RepEUnavailable("Combined steering edit is not finite")
        if delta_norm == 0:
            return hidden, 0.0
        cap = self.steering.relative_norm_cap * hidden_norm
        delta = delta * min(1.0, cap / delta_norm)
        # Enforce the cap on the actual cast/add result, including float rounding.
        for _ in range(64):
            candidate = (hidden64 + delta).to(dtype=hidden.dtype)
            if bool(torch.isfinite(candidate).all()):
                actual = float(torch.linalg.vector_norm(candidate.to(torch.float64) - hidden64).item())
                if math.isfinite(actual) and actual <= cap:
                    return candidate, actual
            delta = delta * 0.5
        return hidden, 0.0

    def _sample(self, hidden: Tensor, index: int, position: int, phase: str, norm: float, edit_norm: float) -> ScalarSample:
        assert self._directions is not None and self._center is not None and self._offset is not None and self._scale is not None
        raw = self._directions.T @ (hidden - self._center)
        normalized = (raw - self._offset) / self._scale
        if not math.isfinite(norm) or not bool(torch.isfinite(raw).all()) or not bool(torch.isfinite(normalized).all()):
            raise RepEUnavailable("Readout produced nonfinite scalars")
        return ScalarSample(
            index, position, phase, tuple(raw.tolist()), tuple(normalized.tolist()),
            tuple(torch.sigmoid(normalized).tolist()), norm, edit_norm,
        )

    def _cleanup(self) -> tuple[BaseException, ...]:
        # Remove only handles owned by this request, preserving unrelated hooks.
        errors: list[BaseException] = []
        failed_handles: list[RemovableHandle] = []
        for handle in reversed(self._handles):
            try:
                handle.remove()
            except BaseException as error:
                errors.append(error)
                failed_handles.append(handle)
        self._handles = failed_handles
        if self._inference is not None:
            try:
                self._inference.__exit__(None, None, None)
            except BaseException as error:
                errors.append(error)
            self._inference = None
        for module, training in zip(self._modules, self._training):
            try:
                module.training = training
            except BaseException as error:
                errors.append(error)
        if self._context_token is not None:
            try:
                _ACTIVE_OWNER.reset(self._context_token)
            except BaseException as error:
                errors.append(error)
            self._context_token = None
        with _REGISTRY_LOCK:
            for module in self._modules:
                entry = _OWNERS.get(id(module))
                if entry is not None and entry[1] is self._owner:
                    del _OWNERS[id(module)]
        self._directions = self._center = self._offset = self._scale = self._coefficients = None
        self._layer = None
        self._modules = ()
        self._training = ()
        self._task = None
        self._cleanup_errors = tuple(f"{type(error).__name__}: {error}" for error in errors)
        return tuple(errors)

    @staticmethod
    def _annotate_cleanup(error: BaseException, cleanup_errors: tuple[BaseException, ...]) -> None:
        if cleanup_errors and hasattr(error, "add_note"):
            error.add_note("RepE cleanup errors: " + "; ".join(f"{type(item).__name__}: {item}" for item in cleanup_errors))


def generate_in_scope(
    *,
    scope: TorchRequestScope,
    generate: Callable[[nn.Module, Mapping[str, Any]], str | Tensor],
    generation_kwargs: Mapping[str, Any],
) -> GenerationResult:
    """Run a synchronous caller-provided generation function with fresh state.

    Example callback shape: ``lambda model, kwargs: model.generate(**kwargs)``.
    The owner must provide ``use_cache=False``; this helper enforces that switch
    again at each root forward and rejects incoming cache, multi-beam/sequence
    generation, activation capture, lazy/async results, and cache-bearing output.
    Output is text or batch-one integer token IDs. No model loader is provided.
    A callback must complete all model work before returning and obey the passed
    options; arbitrary model-internal persistent custom caches are unsupported.
    """
    if type(scope) is not TorchRequestScope or scope._state != "created":
        raise ValueError("generate_in_scope requires a fresh TorchRequestScope")
    if not callable(generate):
        raise TypeError("generate must be a synchronous callable")
    kwargs = dict(generation_kwargs)
    if kwargs.get("use_cache") is not False:
        raise RepEUnavailable("The provider must explicitly request use_cache=False")
    for name in _CACHE_ARGUMENTS:
        if kwargs.get(name) is not None:
            raise RepEUnavailable("Incoming cache state is not accepted")
    for name in (*_CAPTURE_ARGUMENTS, "return_dict_in_generate"):
        if kwargs.get(name) not in (None, False):
            raise RepEUnavailable("Generation may return only text or token IDs")
        kwargs[name] = False
    for name in ("num_beams", "num_beam_groups", "num_return_sequences"):
        if kwargs.get(name, 1) != 1:
            raise RepEUnavailable("Only one generation sequence/beam is supported")
        kwargs[name] = 1
    for name in ("assistant_model", "streamer", "synced_gpus"):
        if kwargs.get(name) not in (None, False):
            raise RepEUnavailable("Assisted, streamed, or distributed generation is unsupported")
    scope.require_explicit_cache_disable = True
    with scope:
        scope.check_cancelled()
        output = generate(scope.model, kwargs)
        scope.check_cancelled()
        if isinstance(output, Tensor):
            if output.ndim != 2 or output.shape[0] != 1 or output.dtype not in (torch.int32, torch.int64):
                raise RepEUnavailable("Generation must return batch-one integer token IDs")
            output = output.detach().clone()
        elif not isinstance(output, str):
            # In particular, generators/coroutines cannot escape hook lifetime.
            if inspect.iscoroutine(output):
                output.close()
            raise RepEUnavailable("Generation must finish synchronously and return text or token IDs")
        if scope.mode is not Mode.OFF and scope._calls == 0:
            raise RepEUnavailable("Generation never visited the exact requested assay layer")
    return GenerationResult(output, scope.report())
