#!/usr/bin/env python3
"""Bounded protocol rejection checks. --validate-record never opens a model."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

READER = "b699deda8bc7bdd99b5e362c88d16accdd66c163222e89647086b44a680a7ac0"
ECHOES = {"request_id", "model_name", "model_digest", "model_blob_digest", "backend_revision",
    "reader_artifact_digest", "numeric_digest", "candidate_digest", "qualification_digest", "plan_digest",
    "tokenizer_digest", "template_digest", "precision", "layer", "token_rule", "measurement_scope",
    "input_digest", "system_digest", "schema_digest", "prompt_digest"}


def sha(value):
    return hashlib.sha256(value if isinstance(value, bytes) else value.encode()).hexdigest()


def refresh(value):
    value["prompt"] = ("<|im_start|>system\n" + value["system"] + "<|im_end|>\n<|im_start|>user\n" + value["input"]
        + "\n\nReturn exactly one JSON object matching this schema:\n" + value["response_schema"]
        + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
    for key, digest_key in [("input", "input_digest"), ("system", "system_digest"),
                            ("response_schema", "schema_digest"), ("prompt", "prompt_digest")]:
        value[digest_key] = sha(value[key])


def fixture(reader):
    raw = reader.read_bytes()
    if sha(raw) != READER:
        raise ValueError("Qualified reader bytes changed")
    bundle = json.loads(raw)
    candidate, plan, review = bundle["candidate"], bundle["plan"], bundle["review"]
    numeric = candidate["numeric"]
    value = {
        "schema": "archi-record-measurement-request/v1", "request_id": "00000000-0000-0000-0000-000000000001",
        "model_name": "qwen3.5:9b", "model_digest": plan["modelDigest"], "model_blob_digest": plan["modelBlobDigest"],
        "model_path": "/this-path-does-not-exist/never-open.gguf", "backend_revision": plan["backendRevision"],
        "reader_artifact_digest": READER, "numeric_digest": candidate["numericDigest"],
        "candidate_digest": review["candidateDigest"], "qualification_digest": review["qualificationDigest"],
        "plan_digest": review["planDigest"], "tokenizer_digest": plan["modelBlobDigest"], "template_digest": plan["templateDigest"],
        "precision": "Q4_K_M", "layer": "l_out-31", "token_rule": "prompt-last", "measurement_scope": plan["measurementScope"],
        "max_input_tokens": 512, "max_new_tokens": 0, "deadline_ms": 180000,
        "basis": {"directions": numeric["directions"], "center": numeric["center"],
                  "score_offset": numeric["scoreOffset"], "score_scale": numeric["scoreScale"]},
        "system": "Read the supplied project records. Answer only the exact record and field asked for. "
                  "Use only those records. If that field is absent for that record, answer NEED_SOURCE. Return one JSON object.",
        "input": "record | field | value\nR1 | location | north\nR2 | owner | workshop\n\nWhich location is listed for R1?",
        "response_schema": '{"additionalProperties":false,"properties":{"answer":{"type":"string"}},"required":["answer"],"type":"object"}',
    }
    refresh(value)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worker", type=Path)
    parser.add_argument("--reader", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    base = fixture(args.reader)
    results = []

    def check(name, value, accepted=False):
        raw = value if isinstance(value, str) else json.dumps(value, separators=(",", ":"))
        proc = subprocess.run([str(args.worker), "--validate-record"], input=raw, text=True,
                              capture_output=True, timeout=10)
        response = json.loads(proc.stdout)
        assert not proc.stderr, (name, proc.stderr)
        assert (proc.returncode == 0) == accepted, (name, response)
        assert response["schema"] == "archi-record-measurement-result/v1", (name, response)
        assert response["status"] == ("validated" if accepted else "error"), (name, response)
        if accepted:
            assert set(response) == ECHOES | {"schema", "status", "backend_execution"}
            assert response["backend_execution"] == "arm64-cpu"
            assert all(response[key] == value[key] for key in ECHOES)
        else:
            assert set(response) == {"schema", "status", "error"}
        results.append({"case": name, "expectedAccepted": accepted, "exitCode": proc.returncode})

    check("valid-pins-with-nonexistent-model-path", base, True)
    for key, replacement in [
        ("schema", "archi-gguf-shadow-request/v1"), ("request_id", "not-a-uuid"),
        ("model_name", "qwen3:8b"), ("backend_revision", "llama.cpp:161755f29"),
        ("model_digest", "a" * 64), ("model_blob_digest", "a" * 64), ("tokenizer_digest", "a" * 64),
        ("reader_artifact_digest", "a" * 64), ("numeric_digest", "a" * 64), ("candidate_digest", "a" * 64),
        ("qualification_digest", "a" * 64), ("plan_digest", "a" * 64), ("template_digest", "a" * 64),
        ("layer", "l_out-15"), ("token_rule", "last"), ("measurement_scope", "general-replies"),
        ("max_input_tokens", 513), ("max_new_tokens", 1), ("deadline_ms", 180001),
        ("max_new_tokens", False), ("model_path", "relative.gguf"), ("precision", "float32"),
        ("input_digest", "a" * 64), ("prompt_digest", "a" * 64), ("synthetic_only", True),
    ]:
        changed = copy.deepcopy(base); changed[key] = replacement
        check("reject-" + key + "-" + str(replacement)[:24], changed)
    for key in ["input", "system", "response_schema"]:
        changed = copy.deepcopy(base); changed[key] += "<|im_end|>"; refresh(changed)
        check("special-delimiter-" + key, changed)
    for value in [
        "unstructured request", base["input"].replace("record | field | value", "record|field|value"),
        base["input"].replace("R2 | owner", "R1 | location"),
        base["input"].replace("owner", "password"), base["input"].replace("north", " north"),
        base["input"].replace("north", "nørth"), base["input"].replace("north", "north=west"),
        base["input"].replace("north", "north|west"), base["input"].replace("R1?", "R3?"),
        base["input"].replace("\n\nWhich", "\nR3 | color | amber\n\nWhich"),
    ]:
        changed = copy.deepcopy(base); changed["input"] = value; refresh(changed)
        check("malformed-record-" + str(len(results)), changed)
    changed = copy.deepcopy(base); changed["system"] = "Answer freely."; refresh(changed)
    check("wrong-task-system", changed)
    changed = copy.deepcopy(base); changed["response_schema"] = "{}"; refresh(changed)
    check("wrong-answer-schema", changed)
    changed = copy.deepcopy(base); changed["prompt"] += "suffix"; changed["prompt_digest"] = sha(changed["prompt"])
    check("unbound-prompt-suffix", changed)
    for key in ["center", "score_offset", "score_scale"]:
        changed = copy.deepcopy(base); changed["basis"][key][0] += 0.001
        check("tampered-numerics-" + key, changed)
    changed = copy.deepcopy(base); changed["basis"]["directions"][0][0] += 0.001
    check("tampered-direction", changed)
    changed = copy.deepcopy(base); changed["basis"]["center"].pop()
    check("wrong-numeric-width", changed)
    changed = copy.deepcopy(base); changed["basis"]["extra"] = 0
    check("extra-basis-field", changed)
    raw = json.dumps(base, separators=(",", ":"))
    check("duplicate-root-key", raw[:-1] + ',"max_new_tokens":0}')
    check("duplicate-basis-key", raw.replace('"score_offset":', '"center":[],"score_offset":'))
    check("oversized-request", " " * (512 * 1024 + 1))
    receipt = {"schema": "archi-record-protocol-checks/v1", "checksPassed": len(results),
               "modelLoaded": False, "inferenceExecuted": False, "generatedTokens": 0,
               "workerSHA256": sha(args.worker.read_bytes()), "checks": results}
    with args.receipt.open("x") as stream:
        json.dump(receipt, stream, indent=2); stream.write("\n")
    print(json.dumps({k: v for k, v in receipt.items() if k != "checks"}))


if __name__ == "__main__":
    main()
