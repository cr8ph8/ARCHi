#!/usr/bin/env python3
"""Inventory a bounded GGUF v3 header without loading a model or tensor data.

This diagnoses known pinned-loader incompatibilities. An empty blocker list is
not model compatibility, graph equivalence, or reader qualification evidence.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import struct

HEADER_LIMIT = 64 * 1024 * 1024
PRIMITIVES = {0: ("B", 1), 1: ("b", 1), 2: ("H", 2), 3: ("h", 2), 4: ("I", 4),
              5: ("i", 4), 6: ("f", 4), 7: ("?", 1), 10: ("Q", 8), 11: ("q", 8), 12: ("d", 8)}


def inspect(path):
    with path.open("rb") as stream:
        size = path.stat().st_size
        def take(n):
            if n < 0 or stream.tell() + n > min(size, HEADER_LIMIT):
                raise ValueError("GGUF header exceeds file or inspection budget")
            raw = stream.read(n)
            if len(raw) != n:
                raise ValueError("Truncated GGUF header")
            return raw
        def u64():
            return struct.unpack("<Q", take(8))[0]
        def string(keep=True):
            n = u64()
            if keep:
                return take(n).decode("utf-8")
            if stream.tell() + n > min(size, HEADER_LIMIT):
                raise ValueError("GGUF string exceeds inspection budget")
            stream.seek(n, 1)
        def value(kind, keep=True, depth=0):
            if depth > 1:
                raise ValueError("Nested GGUF array")
            if kind in PRIMITIVES:
                fmt, count = PRIMITIVES[kind]
                raw = take(count)
                return struct.unpack("<" + fmt, raw)[0] if keep else None
            if kind == 8:
                return string(keep)
            if kind == 9:
                subtype = struct.unpack("<I", take(4))[0]
                count = u64()
                if count > 1_000_000 or (keep and count > 4096):
                    raise ValueError("GGUF array exceeds inspection budget")
                values = []
                for _ in range(count):
                    item = value(subtype, keep, depth + 1)
                    if keep:
                        values.append(item)
                return values if keep else None
            raise ValueError("Unknown GGUF metadata type")
        magic, version, tensor_count, metadata_count = struct.unpack("<4sIQQ", take(24))
        if magic != b"GGUF" or version != 3 or tensor_count > 4096 or metadata_count > 10000:
            raise ValueError("Unsupported GGUF header")
        metadata = {}
        seen = set()
        for _ in range(metadata_count):
            key = string()
            if key in seen:
                raise ValueError("Duplicate GGUF metadata key")
            seen.add(key)
            kind = struct.unpack("<I", take(4))[0]
            keep = key.startswith(("general.architecture", "general.name", "qwen35."))
            result = value(kind, keep)
            if keep:
                metadata[key] = result
        tensors, seen_tensors = [], set()
        for _ in range(tensor_count):
            name = string()
            dimensions = struct.unpack("<I", take(4))[0]
            if not 1 <= dimensions <= 4 or name in seen_tensors:
                raise ValueError("Invalid or duplicate GGUF tensor")
            seen_tensors.add(name)
            shape = [u64() for _ in range(dimensions)]
            kind, offset = struct.unpack("<IQ", take(12))
            tensors.append({"name": name, "shape": shape, "ggmlType": kind, "offset": offset})
        prefix_counts = dict(Counter(row["name"].split(".")[0] for row in tensors))
        blockers = []
        if metadata.get("general.architecture") == "qwen35":
            sections = metadata.get("qwen35.rope.dimension_sections")
            if sections == [11, 11, 10]:
                blockers.append({"id": "three-mrope-sections", "resolvedBy": "archi-qwen35-mrope-v1"})
            elif not isinstance(sections, list) or len(sections) != 4:
                blockers.append({"id": "unsupported-mrope-sections", "resolvedBy": None})
            legacy_dt = [name for name in seen_tensors if name.endswith(".ssm_dt") and name.startswith("blk.")]
            missing_dt = sorted(name for name in legacy_dt if name + ".bias" not in seen_tensors)
            if missing_dt:
                blockers.append({"id": "legacy-ssm-dt-tensor-name", "count": len(missing_dt),
                                 "example": missing_dt[0], "expected": missing_dt[0] + ".bias", "resolvedBy": None})
            extras = {prefix: prefix_counts[prefix] for prefix in ("v", "mtp") if prefix_counts.get(prefix)}
            if extras:
                blockers.append({"id": "combined-vision-mtp-tensors", "prefixCounts": extras, "resolvedBy": None})
        return {"schema": "archi-gguf-metadata-inventory/v1", "metadata": metadata, "tensors": tensors,
                "tensorCount": tensor_count, "tensorPrefixCounts": prefix_counts, "knownCompatibilityBlockers": blockers,
                "bytesReadThrough": stream.tell(), "modelLoaded": False, "tensorDataRead": False,
                "fullBlobDigestVerified": False, "compatibilityEstablished": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.model)
    with args.output.open("x") as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write("\n")
    print(json.dumps({key: result[key] for key in ("tensorCount", "tensorPrefixCounts", "knownCompatibilityBlockers",
                                                 "modelLoaded", "tensorDataRead", "compatibilityEstablished")}))


if __name__ == "__main__":
    main()
