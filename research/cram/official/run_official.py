#!/usr/bin/env python3
"""Plan or execute one bounded stage against an unchanged, pinned CRAM checkout.

Default is plan-only. --execute requires successful preflight. The harness
records process execution, not a universal scientific correctness claim.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import time

from preflight import inspect, PINNED_COMMIT, project_python

STAGES = {
    'tests': ('.', ['uv', 'run', '--frozen', 'pytest']),
    'prepare-maze': ('.', ['uv', 'run', '--frozen', 'python', 'scripts/prepare_data.py', 'maze-unique']),
    'evaluate-maze': ('.', ['uv', 'run', '--frozen', 'python', 'checkpoints/evaluate.py', '--tasks', 'maze-unique', '--seeds', '0', '1', '2']),
    'prepare-sudoku': ('.', ['uv', 'run', '--frozen', 'python', 'scripts/prepare_data.py', 'sudoku']),
    'evaluate-sudoku-dev': ('.', ['uv', 'run', '--frozen', 'python', 'checkpoints/evaluate.py', '--tasks', 'sudoku-extreme', '--seeds', '0', '1', '2']),
    'train-sudoku': ('experiments', ['uv', 'run', '--frozen', 'python', 'sudoku.py', 'diag']),
    'train-maze': ('experiments', ['uv', 'run', '--frozen', 'python', 'maze_unique.py', 'train', '--kernel', 'free', '--free-init', '0', '--opt', 'sgd', '--momentum', '0.5', '--cosine', '--lr', '1', '--updates', '20', '--l1', '0', '--split', 'train', '--seed', '0', '--out', 'runs/archi-pilot/maze-seed0', '--score']),
}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', required=True, type=Path)
    p.add_argument('--stage', required=True, choices=STAGES)
    p.add_argument('--output-dir', required=True, type=Path)
    p.add_argument('--execute', action='store_true')
    a = p.parse_args()
    repo = a.repo.resolve()
    relative_cwd, documented_argv = STAGES[a.stage]
    interpreter = str(project_python(repo))
    # Use the exact project interpreter inspected by preflight. No implicit install/sync.
    argv = [interpreter, '-m', 'pytest'] if a.stage == 'tests' else [interpreter, *documented_argv[4:]]
    report = {'schema_version': 1, 'stage': a.stage, 'repository': str(repo),
        'pinned_commit': PINNED_COMMIT, 'argv': argv, 'working_directory': str(repo / relative_cwd),
        'official_script_executed': False, 'official_evaluation_attempted': False,
        'official_reproduction_executed': False, 'status': 'SKIPPED',
        'intended_stage_effects': {'downloads': a.stage.startswith('prepare-'),
            'data_preparation': a.stage.startswith('prepare-'), 'model_training': a.stage.startswith('train-'),
            'test_or_evaluation': a.stage == 'tests' or a.stage.startswith('evaluate-')},
        'mode': 'execute' if a.execute else 'dry_run',
        'note': 'Plan-only until --execute. A stage PASS means process success; inspect score records for numerical reproduction.'}
    a.output_dir.mkdir(parents=True, exist_ok=True)
    record = a.output_dir / (a.stage + '.json')
    if record.exists():
        raise SystemExit('Refusing to overwrite an earlier stage record. Choose a fresh output directory.')
    if a.execute:
        check = inspect(repo, a.stage)
        report['preflight'] = check
        if not check['ready_for_stage']:
            report['reason'] = 'Preflight did not establish all required capabilities.'
        else:
            stamp = dt.datetime.now(dt.timezone.utc).isoformat()
            started = time.perf_counter()
            report['started_at_utc'] = stamp
            try:
                with (a.output_dir / (a.stage + '.log')).open('w', encoding='utf-8') as log:
                    run = subprocess.run(argv, cwd=repo / relative_cwd, stdout=log, stderr=subprocess.STDOUT, check=False)
                report.update(official_script_executed=True, official_evaluation_attempted=a.stage.startswith('evaluate-'),
                              official_reproduction_executed=a.stage.startswith('evaluate-') and run.returncode == 0, returncode=run.returncode,
                              status='PASS' if run.returncode == 0 else 'FAIL')
            except OSError as exc:
                report.update(status='ERROR', error=type(exc).__name__ + ': ' + str(exc))
            report['elapsed_seconds'] = time.perf_counter() - started
    record.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))
    return 0 if not a.execute or report['status'] == 'PASS' else 2


if __name__ == '__main__':
    raise SystemExit(main())
