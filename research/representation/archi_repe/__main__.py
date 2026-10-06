"""Explicit, bounded local JSON calculations; no model, tests or app mutations."""
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np

from . import numerics


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON field")
        result[key] = value
    return result


def _plain(value):
    if dataclasses.is_dataclass(value):
        return {f.name: _plain(getattr(value, f.name)) for f in dataclasses.fields(value)}
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, dict):
        return {k: _plain(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_plain(v) for v in value]
    return value


def _bounded(value, depth=0):
    if depth > 6:
        raise ValueError("input nesting exceeds the local calculation limit")
    if isinstance(value, dict):
        if len(value) > 32:
            raise ValueError("too many input fields")
        for v in value.values():
            _bounded(v, depth + 1)
    elif isinstance(value, list):
        if len(value) > 128:
            raise ValueError("CLI vectors and matrix axes are limited to 128 coordinates")
        for v in value:
            _bounded(v, depth + 1)
    elif isinstance(value, (float, int)) and not isinstance(value, bool):
        if not math.isfinite(value):
            raise ValueError("input values must be finite")
    elif value is not None and not isinstance(value, (str, bool)):
        raise ValueError("unsupported JSON value")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="JSON object with operation and arguments; writes a result to stdout")
    args = parser.parse_args()
    try:
        with args.input.open("rb") as stream:
            data = stream.read(262_145)
        if len(data) > 262_144:
            raise ValueError("input exceeds 256 KiB")
        request = json.loads(data, object_pairs_hook=_object,
                             parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))
        _bounded(request)
        if not isinstance(request, dict) or set(request) != {"operation", "arguments"} or not isinstance(request["arguments"], dict):
            raise ValueError("expected operation and arguments fields")
        operations = {
            "quotient_candidate": numerics.bounded_quotient_candidate,
            "couple_effective_delta": numerics.couple_effective_delta,
            "coupling_uncertainty": numerics.propagate_coupling_uncertainty,
            "normalized_entropy": numerics.normalized_entropy,
            "entropy_bounds": numerics.top_k_entropy_bounds,
            "bounded_steering_vector": numerics.bounded_steering,
            "regularized_control": numerics.regularized_control_solve,
        }
        operation = request["operation"]
        if not isinstance(operation, str) or operation not in operations:
            raise ValueError("unsupported local operation")
        result = operations[operation](**request["arguments"])
        print(json.dumps({"schemaVersion": "archi-local-calculation/v1", "operation": operation,
                          "inputDigest": hashlib.sha256(data).hexdigest(), "result": _plain(result),
                          "authority": "numerical proposal only; no native state changed"}, allow_nan=False))
        return 0
    except (OSError, ValueError, TypeError, OverflowError, RecursionError) as error:
        print(json.dumps({"status": "unavailable", "reason": str(error)[:400]}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
