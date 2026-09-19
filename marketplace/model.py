"""Closed, data-only recipe contract shared with CompanionItemPackage.swift."""
from __future__ import annotations

import hashlib
import json
import math
import re
from dataclasses import dataclass, field
from typing import Any

MAX_BODY = 16_384
MAX_RECIPE = 4096
RECIPE_SCHEMA = "archi-item-design/v1"


class APIError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


@dataclass
class Response:
    status: int
    value: Any
    headers: dict[str, str] = field(default_factory=dict)


def invalid(message: str) -> None:
    raise APIError(422, "validation_failed", message)


def exact_keys(value: Any, keys: set[str], label: str = "Request") -> dict:
    if type(value) is not dict or set(value) != keys:
        invalid(f"{label} requires only these fields: {', '.join(sorted(keys))}.")
    return value


def json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def parse_json(raw: bytes) -> Any:
    if not raw or len(raw) > MAX_BODY:
        raise APIError(413 if raw else 400, "body_too_large" if raw else "invalid_request",
                       "A JSON body of at most 16,384 bytes is required.")

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("Duplicate JSON field")
            result[key] = value
        return result

    def constant(_):
        raise ValueError("Non-finite JSON number")

    try:
        result = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs, parse_constant=constant)
        # Reject unpaired surrogates and excessive nesting before domain validation.
        def check(value, depth=0):
            if depth > 8:
                raise ValueError("JSON nesting")
            if isinstance(value, str):
                value.encode("utf-8")
            elif isinstance(value, float) and not math.isfinite(value):
                raise ValueError("Non-finite JSON number")
            elif isinstance(value, dict):
                for key, item in value.items():
                    check(key, depth + 1)
                    check(item, depth + 1)
            elif isinstance(value, list):
                for item in value:
                    check(item, depth + 1)
        check(result)
        return result
    except (ValueError, UnicodeError, RecursionError):
        raise APIError(400, "invalid_request", "Use valid UTF-8 JSON with unique keys and bounded nesting.") from None


def text_value(value: Any, maximum: int, label: str, *, required=True) -> str:
    if type(value) is not str:
        invalid(f"{label} must be text.")
    try:
        length = len(value.encode("utf-16-le")) // 2
    except UnicodeError:
        invalid(f"{label} must contain valid Unicode.")
    if length > maximum or (required and not value.strip()):
        invalid(f"{label} must be {'nonempty and ' if required else ''}at most {maximum} UTF-16 units.")
    if any(ord(c) < 0x20 or 0x7F <= ord(c) <= 0x9F or ord(c) in (0x2028, 0x2029) for c in value):
        invalid(f"{label} cannot contain control characters or line separators.")
    return value


def integer(value: Any, minimum: int, maximum: int, label: str) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        invalid(f"{label} must be an integer from {minimum} to {maximum}.")
    return value


def choice(value: Any, allowed: set[str], label: str) -> str:
    if type(value) is not str or value not in allowed:
        invalid(f"{label} has an unsupported value.")
    return value


def validate_recipe(value: Any) -> tuple[dict, str]:
    recipe = exact_keys(value, {"schema", "title", "creator", "summary", "revision", "license",
                                "palette", "crown", "action", "defaultGesture"}, "Recipe")
    choice(recipe["schema"], {RECIPE_SCHEMA}, "Recipe schema")
    for name, maximum in (("title", 24), ("creator", 48), ("summary", 160)):
        text_value(recipe[name], maximum, f"Recipe {name}", required=name != "summary")
    integer(recipe["revision"], 1, 999, "Recipe revision")
    for name, values in (("license", {"MIT", "CC0", "CC-BY-4.0"}),
                         ("palette", {"lilac", "mint", "gold", "rose", "ice"}),
                         ("crown", {"pearl", "star", "leaf"}),
                         ("action", {"decoration", "pointSelection"})):
        choice(recipe[name], values, f"Recipe {name}")
    gesture = exact_keys(recipe["defaultGesture"], {"pace", "sparkle", "hold"}, "Gesture")
    choice(gesture["pace"], {"Quick", "Gentle", "Unhurried"}, "Gesture pace")
    choice(gesture["sparkle"], {"None", "Soft", "Bright"}, "Gesture sparkle")
    choice(gesture["hold"], {"Brief", "Lingering"}, "Gesture hold")
    if len(json_bytes(recipe)) > MAX_RECIPE:
        invalid("Serialized recipe cannot exceed 4,096 bytes.")
    fields = [recipe[name] for name in ("schema", "title", "creator", "summary")]
    fields += [str(recipe["revision"])]
    fields += [recipe[name] for name in ("license", "palette", "crown", "action")]
    fields += [gesture[name] for name in ("pace", "sparkle", "hold")]
    canonical = b"archi-item-design-canonical/v1\n"
    for value in fields:
        raw = value.encode("utf-8")
        canonical += str(len(raw)).encode("ascii") + b":" + raw + b"\n"
    return recipe, hashlib.sha256(canonical).hexdigest()


def validate_provenance(value: Any) -> dict:
    declaration = exact_keys(value, {"declaration", "attribution", "source", "rightsConfirmed"}, "Provenance")
    choice(declaration["declaration"], {"original", "licensed-adaptation"}, "Provenance declaration")
    text_value(declaration["attribution"], 500, "Attribution")
    text_value(declaration["source"], 500, "Source", required=declaration["declaration"] == "licensed-adaptation")
    if declaration["rightsConfirmed"] is not True:
        invalid("Confirm permission to distribute the recipe under its declared license.")
    return declaration


def handle_value(value: Any) -> str:
    if type(value) is not str or not re.fullmatch(r"[a-z][a-z0-9_]{2,31}", value):
        invalid("Handle must use 3–32 lowercase ASCII letters, digits or underscores, starting with a letter.")
    return value


def password_value(value: Any) -> bytes:
    text_value(value, 256, "Password")
    raw = value.encode("utf-8")
    if not 12 <= len(value) <= 128 or len(raw) > 512:
        invalid("Password must contain 12–128 Unicode characters and at most 512 UTF-8 bytes.")
    return raw
