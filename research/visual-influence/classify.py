"""Classify bounded Python source structurally. Never execute model code.

Only direct calls reachable from the requested top-level entry function are
followed. Dynamic dispatch, imports, decorators and unresolved calls are unknown.
This detects a syntactic strategy, not program correctness or causal influence.
"""

import ast
import json
import re
import sys

MAX_CODE_BYTES = 16384
SAFE_BUILTINS = {"len", "range", "enumerate", "min", "max", "abs", "int", "bool"}
SAFE_METHODS = {"append", "pop", "extend", "insert"}


def classify(code, entry):
    if not isinstance(code, str) or not isinstance(entry, str):
        return {"strategy": "unknown", "reason": "invalid_input"}
    if len(code.encode("utf-8")) > MAX_CODE_BYTES:
        return {"strategy": "unknown", "reason": "oversized"}
    fenced = re.fullmatch(r"\s*```(?:python)?\s*\n(.*?)\n```\s*", code, re.S)
    if fenced:
        code = fenced.group(1)
    try:
        tree = ast.parse(code)
    except (SyntaxError, ValueError, RecursionError):
        return {"strategy": "unknown", "reason": "syntax_error"}
    if any(isinstance(node, (ast.Import, ast.ImportFrom, ast.ClassDef,
                             ast.AsyncFunctionDef, ast.Lambda)) for node in ast.walk(tree)):
        return {"strategy": "unknown", "reason": "unsupported_construct"}
    if any(not isinstance(node, ast.FunctionDef) and not (
            isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant)
            and isinstance(node.value.value, str)) for node in tree.body):
        return {"strategy": "unknown", "reason": "top_level_execution"}
    functions = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]
    names = [node.name for node in functions]
    if len(names) != len(set(names)) or any(node.decorator_list for node in functions):
        return {"strategy": "unknown", "reason": "ambiguous_functions"}
    for function in functions:
        for value in [*function.args.defaults, *function.args.kw_defaults]:
            if value is not None:
                try:
                    ast.literal_eval(value)
                except (ValueError, TypeError, RecursionError):
                    return {"strategy": "unknown", "reason": "dynamic_default"}
        annotations = [function.returns, *[node.annotation for node in ast.walk(function.args) if isinstance(node, ast.arg)]]
        if any(isinstance(node, ast.Call) for value in annotations if value is not None for node in ast.walk(value)):
            return {"strategy": "unknown", "reason": "dynamic_annotation"}
    by_name = {node.name: node for node in functions}
    if entry not in {node.name for node in tree.body if isinstance(node, ast.FunctionDef)}:
        return {"strategy": "unknown", "reason": "missing_entry"}

    # Exclude nested function bodies from the enclosing function's own body walk.
    # They become reachable only when a direct call to them is encountered.
    def own_nodes(function):
        pending = list(function.body)
        while pending:
            node = pending.pop()
            yield node
            if not isinstance(node, ast.FunctionDef):
                pending.extend(ast.iter_child_nodes(node))

    graph, loops, uncertain = {}, {}, {}
    for name, function in by_name.items():
        graph[name], loops[name], uncertain[name] = set(), False, False
        for node in own_nodes(function):
            if isinstance(node, (ast.For, ast.While, ast.comprehension)):
                loops[name] = True
            if isinstance(node, ast.Call):
                target = node.func
                if isinstance(target, ast.Name) and target.id in by_name:
                    graph[name].add(target.id)
                elif isinstance(target, ast.Name) and target.id in SAFE_BUILTINS:
                    pass
                elif isinstance(target, ast.Attribute) and target.attr in SAFE_METHODS:
                    pass
                else:
                    uncertain[name] = True

    seen, active = set(), set()
    recursive = False

    def walk(name):
        nonlocal recursive
        if name in active:
            recursive = True
            return
        if name in seen:
            return
        seen.add(name)
        active.add(name)
        for target in graph[name]:
            walk(target)
        active.remove(name)

    walk(entry)
    if any(uncertain[name] for name in seen):
        return {"strategy": "unknown", "reason": "unresolved_call"}
    if recursive:
        return {"strategy": "recursive", "reason": "reachable_call_cycle"}
    if any(loops[name] for name in seen):
        return {"strategy": "iterative", "reason": "reachable_loop_without_call_cycle"}
    return {"strategy": "unknown", "reason": "no_recognized_strategy"}


if __name__ == "__main__":
    raw = sys.stdin.buffer.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024:
        raise SystemExit("Classifier input exceeds 4 MiB")
    payload = json.loads(raw)
    if not isinstance(payload, list) or len(payload) > 200:
        raise SystemExit("Classifier requires at most 200 records per batch")
    print(json.dumps([classify(item.get("code"), item.get("entry")) for item in payload]))
