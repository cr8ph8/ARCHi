"""Scalar-only adapter to ARCHi's native representation receipt, schema v1.

No model loading, tensor persistence, native state writes, or automatic learning.
Identity digests are caller-owned bindings; the model loader must verify actual
artifact bytes before supplying a report. This envelope is not a signature.
"""
from __future__ import annotations

import hashlib
import json
import math
import unicodedata
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .torch_adapter import RequestReport


def encode_native_assay(report: RequestReport, answer_text: str, *, reader_name: str) -> bytes:
    """Bind one named reader to the exact UTF-8 answer returned to LocalRoleClient.

    Use the same input/instruction/schema bytes captured by the native request
    owner. A tokenizer output must be decoded first; hashing token IDs would not
    match the native answer digest. Samples are layer-call ordinals, not episodes.
    """
    from .torch_adapter import RequestReport, Mode

    if type(report) is not RequestReport or report.outcome != "completed":
        raise ValueError("only a completed request report may become an assay")
    if report.mode not in (Mode.SHADOW, Mode.BOUNDED) or report.basis is None:
        raise ValueError("an explicitly selected representation mode and basis are required")
    if not isinstance(answer_text, str) or len(answer_text.encode("utf-8")) > 1_048_576:
        raise ValueError("answer must be bounded UTF-8 text")
    if reader_name not in report.names or len(set(report.names)) != len(report.names):
        raise ValueError("choose one exact, unique reader name")
    basis, model = report.basis, report.model
    if basis.model != model:
        raise ValueError("basis and model identities disagree")
    for value in (basis.namespace, basis.layer, model.backend_revision, reader_name):
        if not value or len(value.encode("utf-8")) > 160 or any(unicodedata.category(c) in ("Cc", "Cf") for c in value):
            raise ValueError("native labels must be bounded and contain no controls")
    if not 1 <= len(report.samples) <= 4096:
        raise ValueError("native assay requires 1 through 4096 recorded samples")
    index = report.names.index(reader_name)
    samples = []
    previous = -1
    for pair in report.samples:
        if (pair.before.phase != "pre_current_edit" or pair.after.phase != "post_current_edit"
                or pair.before.token_index != pair.after.token_index
                or pair.before.token_position != pair.after.token_position):
            raise ValueError("sample pair phases and locations do not match")
        sample = pair.before if report.mode is Mode.SHADOW else pair.after
        if not 0 <= sample.token_index < 32768 or sample.token_index <= previous:
            raise ValueError("sample ordinals must increase within the native limit")
        if len(sample.raw_scores) != len(report.names) or len(sample.coordinates) != len(report.names):
            raise ValueError("sample reader dimensions do not match")
        raw, coordinate = sample.raw_scores[index], sample.coordinates[index]
        if not math.isfinite(raw) or not math.isfinite(coordinate) or not 0 <= coordinate <= 1:
            raise ValueError("sample scalars are invalid")
        samples.append({"tokenIndex": sample.token_index, "rawScore": raw, "coordinate": coordinate})
        previous = sample.token_index
    envelope = {
        "schemaVersion": "archi-representation-assay/v1",
        "requestID": str(report.binding.request_id),
        "inputDigest": report.binding.input_digest.value,
        "systemDigest": report.binding.system_digest.value,
        "schemaDigest": report.binding.schema_digest.value,
        "outputDigest": hashlib.sha256(answer_text.encode("utf-8")).hexdigest(),
        "basis": {
            "namespace": basis.namespace, "modelDigest": model.model_digest.value,
            "tokenizerDigest": model.tokenizer_digest.value, "templateDigest": model.template_digest.value,
            "backendRevision": model.backend_revision, "precision": model.precision,
            "layer": basis.layer, "tokenRule": "last", "readerName": reader_name,
            "basisDigest": basis.basis_digest.value, "readerDigest": basis.reader_digest.value,
            "calibrationDigest": basis.calibration_digest.value,
        },
        "mode": report.mode.value,
        # This is relative to this adapter's request, not an independent matched
        # baseline. Before-current-edit measurements in bounded mode are affected.
        "phase": "unsteered" if report.mode is Mode.SHADOW else "intervened",
        "samples": samples,
    }
    return json.dumps(envelope, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
