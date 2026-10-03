"""Bounded, deterministic synthetic record-pair inputs. No inference or downloads.

Pair inventory means exact lexical tokens (words and punctuation), not a claim
about the model tokenizer. External provenance is a caller declaration; no
validator can establish that a corpus was never inspected or used elsewhere.
"""
from collections import Counter
import hashlib
import json
import re
import unicodedata

SCHEMA = "archi-synthetic-paired-corpus/v1"
VALIDATION = "archi-synthetic-paired-corpus-validation/v1"
SCOPE = "synthetic-record-field-support/prompt-final/v1"
MAX_BYTES = 128 * 1024
TEMPLATE = ("<|im_start|>system\n{{system}}<|im_end|>\n<|im_start|>user\n{{input}}"
            "\n\nReturn exactly one JSON object matching this schema:\n{{schema}}"
            "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def sha(value):
    return hashlib.sha256(value if isinstance(value, bytes) else value.encode()).hexdigest()


def decode(data):
    if len(data) > MAX_BYTES:
        raise ValueError("Corpus exceeds 128 KiB")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON key")
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite JSON")))


def text(value, maximum=96):
    return (isinstance(value, str) and 0 < len(value.encode()) <= maximum
            and value == value.strip() and all(not unicodedata.category(c).startswith("C") for c in value)
            and "<|" not in value)


def exact_keys(value, keys):
    return isinstance(value, dict) and set(value) == set(keys)


def inventory(prompt):
    return Counter(re.findall(r"\w+|[^\w\s]", prompt))


def pair_signature(pairs):
    return encoded(sorted([sorted(rows, key=encoded) for rows in pairs], key=encoded))


def build(value, *, external):
    """Validate declared corpus and derive every prompt, split and support label."""
    if len(encoded(value).encode()) > MAX_BYTES or not exact_keys(value, ["schema", "scope", "syntheticOnly", "groups"]):
        raise ValueError("Invalid corpus shape or bound")
    if value["schema"] != SCHEMA or value["scope"] != SCOPE or value["syntheticOnly"] is not True:
        raise ValueError("Only the declared synthetic record-support scope is accepted")
    groups = value["groups"]
    if not isinstance(groups, list) or len(groups) != 12:
        raise ValueError("Exactly twelve groups are required")
    # Repackaging a disclosed built-in pair must not make it qualification input.
    disclosed = {pair_signature(group["records"]) for group in builtin()["groups"]} if external else set()
    examples, samples, group_ids, prompts, questions = [], [], set(), set(), set()
    splits = Counter()
    response_schema = encoded({"type": "object", "properties": {"answer": {"type": "string"}},
                               "required": ["answer"], "additionalProperties": False})
    for index, group in enumerate(groups):
        keys = ["id", "split", "domain", "layout", "query", "records"] + ([] if external else ["question"])
        if not exact_keys(group, keys):
            raise ValueError("Invalid group shape")
        if (not text(group["id"]) or group["id"] in group_ids or not text(group["domain"])
                or group["split"] not in ("fit", "calibration", "holdout")
                or group["layout"] not in ("assignment", "table", "entry")):
            raise ValueError("Invalid or repeated group identity")
        group_ids.add(group["id"])
        splits[group["split"]] += 1
        query = group["query"]
        if not exact_keys(query, ["id", "field"]) or not all(text(x) for x in query.values()):
            raise ValueError("Invalid exact record-field query")
        question = (f"Which {query['field']} is listed for {query['id']}?" if external else group["question"])
        if not text(question, 240) or question in questions:
            raise ValueError("Questions must be bounded and unique between groups")
        questions.add(question)
        pairs = group["records"]
        if not isinstance(pairs, list) or len(pairs) != 2:
            raise ValueError("Each group requires exactly two record sets")
        system = (f"Read the supplied {group['domain']} records. Answer only the exact record and field asked for. "
                  "Use only those records. If that field is absent for that record, answer NEED_SOURCE. Return one JSON object.")
        pair_prompts, labels = [], []
        for pair_index, rows in enumerate(pairs):
            if (not isinstance(rows, list) or len(rows) != 2
                    or not all(exact_keys(row, ["id", "field", "value"]) and all(text(x) for x in row.values()) for row in rows)
                    or len({row["id"] for row in rows}) != 2 or len({row["field"] for row in rows}) != 2):
                raise ValueError("Each member requires two distinct bounded synthetic records")
            label = 1 if any(row["id"] == query["id"] and row["field"] == query["field"] for row in rows) else -1
            labels.append(label)
            if group["layout"] == "assignment":
                rendered = "\n".join(f"{r['id']}: {r['field']} = {r['value']}" for r in rows)
            elif group["layout"] == "table":
                rendered = "record | field | value\n" + "\n".join(f"{r['id']} | {r['field']} | {r['value']}" for r in rows)
            else:
                rendered = "\n".join(f"Entry [{r['id']}] has {r['field']} '{r['value']}'." for r in rows)
            input_text = encoded({"question": question, "source": rendered})
            prompt = ("<|im_start|>system\n" + system + "<|im_end|>\n<|im_start|>user\n" + input_text
                      + "\n\nReturn exactly one JSON object matching this schema:\n" + response_schema
                      + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
            if len(prompt.encode()) > 16_384 or prompt in prompts:
                raise ValueError("Prompts must be bounded and unique")
            prompts.add(prompt)
            pair_prompts.append(prompt)
            sid = f"record-{index + 1:02d}-{pair_index + 1}"
            samples.append({"sample_id": sid, "input": input_text, "system": system, "response_schema": response_schema,
                            "prompt": prompt, "input_digest": sha(input_text), "system_digest": sha(system),
                            "schema_digest": sha(response_schema), "prompt_digest": sha(prompt)})
            examples.append({"sampleID": sid, "group": group["id"], "split": group["split"], "label": label,
                             "records": rows, "query": query, "promptDigest": sha(prompt)})
        if external and pair_signature(pairs) in disclosed:
            raise ValueError("Disclosed built-in pairs remain development-only")
        if sorted(labels) != [-1, 1] or inventory(pair_prompts[0]) != inventory(pair_prompts[1]):
            raise ValueError("Pairs require opposite derived support labels and exact lexical token inventory")
    if splits != Counter({"fit": 4, "calibration": 4, "holdout": 4}):
        raise ValueError("Freeze exactly four fit, four calibration and four holdout groups")
    return {"schema": "archi-synthetic-record-dataset/v1", "scope": SCOPE, "syntheticOnly": True,
            "examples": examples}, samples


def builtin():
    groups = []
    for index, (split, domain, target, other, field, distractor, value, other_value, question) in enumerate(BUILTIN_GROUPS):
        pairs = []
        for positive in ([True, False] if index % 2 == 0 else [False, True]):
            rows = [{"id": target if positive else other, "field": field, "value": value},
                    {"id": other if positive else target, "field": distractor, "value": other_value}]
            if index % 2:
                rows.reverse()
            pairs.append(rows)
        groups.append({"id": domain, "split": split, "domain": domain,
                       "layout": "assignment" if index < 4 else "table" if index < 8 else "entry",
                       "query": {"id": target, "field": field}, "question": question.format(id=target), "records": pairs})
    return {"schema": SCHEMA, "scope": SCOPE, "syntheticOnly": True, "groups": groups}


BUILTIN_GROUPS = [
        ("fit", "parcel", "PX-41", "PX-87", "destination", "weight", "Harbor", "nine", "Which destination is listed for {id}?"),
        ("fit", "greenhouse", "GH-52", "GH-93", "species", "shelf", "Basil", "upper", "Read the species field for {id}."),
        ("fit", "equipment", "EQ-24", "EQ-68", "voltage", "owner", "twelve", "Mira", "What voltage belongs to {id}?"),
        ("fit", "storage", "BN-35", "BN-79", "contents", "seal", "Ribbon", "blue", "Find the contents recorded under {id}."),
        ("calibration", "train", "TR-16", "TR-82", "platform", "route", "four", "Coastal", "Give the platform entry for {id}."),
        ("calibration", "parts", "PT-27", "PT-64", "material", "batch", "Brass", "winter", "Look up {id} and report its material."),
        ("calibration", "museum", "MU-38", "MU-75", "gallery", "condition", "East", "sealed", "Locate {id}: which gallery does its record name?"),
        ("calibration", "recipe", "RC-49", "RC-86", "temperature", "servings", "medium", "six", "Retrieve the temperature attributed to {id}."),
        ("holdout", "farm", "FM-53", "FM-97", "destination", "crate", "Orchard", "cedar", "Where is {id} scheduled for delivery? Return its destination field."),
        ("holdout", "audio", "AU-62", "AU-18", "instrument", "tempo", "Cello", "slow", "For track {id}, identify the instrument entry."),
        ("holdout", "library", "LB-73", "LB-29", "borrower", "edition", "Nora", "second", "Name the borrower attached to loan {id}."),
        ("holdout", "laboratory", "LA-84", "LA-31", "cabinet", "assay", "West", "salinity", "Consult the storage log: report {id}'s cabinet."),
    ]
