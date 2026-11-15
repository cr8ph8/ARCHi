#!/usr/bin/env python3
"""Read-only preflight for the pinned official CRAM pilot; stdlib only.

This checks an environment, not model correctness. No installs or network calls.
An optional JSON output is a local evidence artifact. SKIPPED is not PASS.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

PINNED_COMMIT = '62bbe830c7d6f87f2ba18f30a28039258b986454'
STAGE_NAMES = ('tests', 'prepare-maze', 'evaluate-maze', 'prepare-sudoku', 'evaluate-sudoku-dev', 'train-sudoku', 'train-maze')
GPU_STAGES = {'tests', 'evaluate-maze', 'evaluate-sudoku-dev', 'train-sudoku', 'train-maze'}
RUNTIME_PROBE = '''
import importlib.util, json, platform, sys
result = dict(executable=sys.executable, python_version=platform.python_version(), python_info=list(sys.version_info[:3]))
result['modules'] = {name: bool(importlib.util.find_spec(name)) for name in ('numpy','tyro','huggingface_hub','pytest','triton','torch')}
if result['modules']['torch']:
    try:
        import torch
        result['torch'] = dict(version=torch.__version__,cuda_build=torch.version.cuda,cuda_available=torch.cuda.is_available(),device_count=torch.cuda.device_count())
    except Exception as exc:
        result['torch_error'] = type(exc).__name__ + ': ' + str(exc)
print(json.dumps(result))
'''


def command(argv: list[str], cwd: Path | None = None) -> dict:
    try:
        run = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=30, check=False)
        return {'returncode': run.returncode, 'stdout': run.stdout.strip(), 'stderr': run.stderr.strip()}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {'returncode': None, 'error': type(exc).__name__ + ': ' + str(exc)}


def memory_bytes() -> int | None:
    try:
        return os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES')
    except (AttributeError, OSError, ValueError):
        return None


def project_python(repo: Path | None) -> Path:
    return (repo / '.venv' / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')) if repo else Path(sys.executable)


def inspect(repo: Path | None = None, stage: str = 'evaluate-maze') -> dict:
    if stage not in STAGE_NAMES:
        raise ValueError('Unknown stage: ' + stage)
    checks = []
    def add(name: str, status: str, details: object) -> None:
        checks.append({'check': name, 'status': status, 'details': details})

    interpreter = project_python(repo)
    add('project_interpreter', 'PASS' if repo and interpreter.is_file() else 'SKIPPED',
        {'path': str(interpreter), 'note': 'Probe and execution use the upstream checkout virtual environment, even if this script is called by system Python.'})
    runtime = command([str(interpreter), '-c', RUNTIME_PROBE])
    details = {}
    if runtime['returncode'] == 0:
        try:
            details = json.loads(runtime['stdout'])
            add('runtime_probe', 'PASS', details)
        except (ValueError, KeyError) as exc:
            add('runtime_probe', 'ERROR', {'error': str(exc), 'process': runtime})
    else:
        add('runtime_probe', 'ERROR', runtime)
    version_status = ('PASS' if tuple(details['python_info']) >= (3, 12) else 'FAIL') if 'python_info' in details else 'SKIPPED'
    add('python_at_least_3_12', version_status, details.get('python_version'))
    add('linux_reference_environment', 'PASS' if platform.system() == 'Linux' else 'ABSTAIN',
        {'platform': platform.platform(), 'note': 'The pinned project selects the CUDA 12.8 index only on Linux; native Windows is unverified.'})
    add('git_available', 'PASS' if shutil.which('git') else 'SKIPPED', shutil.which('git'))
    add('uv_available', 'PASS' if shutil.which('uv') else 'SKIPPED', shutil.which('uv'))
    smi = shutil.which('nvidia-smi')
    if smi:
        observed = command([smi, '--query-gpu=name,driver_version,memory.total', '--format=csv,noheader'])
        add('nvidia_driver_observed', 'PASS' if observed['returncode'] == 0 else 'ERROR', observed)
    else:
        add('nvidia_driver_observed', 'SKIPPED', 'nvidia-smi unavailable; no GPU was demonstrated')

    if 'torch' in details:
        td = details['torch']
        add('torch_2_11_0', 'PASS' if td['version'].split('+')[0] == '2.11.0' else 'FAIL', td)
        add('torch_cuda_available', 'PASS' if td['cuda_available'] else 'FAIL', td['cuda_available'])
        add('cuda_12_8_reference_build', 'PASS' if td['cuda_build'] == '12.8' else 'ABSTAIN', td['cuda_build'])
    else:
        if 'torch_error' in details:
            add('torch_import', 'ERROR', details['torch_error'])
        add('torch_2_11_0', 'SKIPPED', 'torch is not installed in this Python environment')
        add('torch_cuda_available', 'SKIPPED', 'torch unavailable')
    modules = details.get('modules', {})
    for name in ('numpy', 'tyro', 'huggingface_hub', 'pytest', 'triton'):
        add(name + '_available', 'PASS' if modules.get(name) else 'SKIPPED',
            'Module discoverability in the project interpreter; execution is tested only by the requested stage.')
    ram = memory_bytes()
    add('sudoku_preparation_memory', 'PASS' if ram is not None and ram >= 32 * 1024**3 else 'ABSTAIN',
        {'total_memory_bytes': ram, 'reference_note': 'Official Sudoku preparation uses about 32 GB RAM; currently free memory also matters.'})
    add('disk_observation', 'PASS', {'free_bytes': shutil.disk_usage(Path.cwd()).free,
        'reference_note': 'Official Sudoku data output is about 2 GB, excluding environment, cache, logs and other tasks.'})
    if repo:
        head = command(['git', 'rev-parse', 'HEAD'], repo)
        add('official_commit', 'PASS' if head.get('stdout') == PINNED_COMMIT else 'FAIL', head)
        dirty = command(['git', 'status', '--porcelain', '--untracked-files=no'], repo)
        add('official_tracked_sources_clean', 'PASS' if dirty['returncode'] == 0 and not dirty['stdout'] else 'FAIL', dirty)
    else:
        add('official_commit', 'SKIPPED', 'No full checkout supplied; selected source snapshot is not a checkout')

    required = {'project_interpreter', 'runtime_probe', 'python_at_least_3_12', 'linux_reference_environment', 'git_available',
                'numpy_available', 'tyro_available', 'official_commit', 'official_tracked_sources_clean'}
    if stage in GPU_STAGES:
        required.update({'torch_2_11_0', 'torch_cuda_available', 'cuda_12_8_reference_build', 'triton_available'})
    if stage.startswith('prepare-'):
        required.add('huggingface_hub_available')
    if stage == 'prepare-sudoku':
        required.add('sudoku_preparation_memory')
    if stage == 'tests':
        required.add('pytest_available')
    by_name = {c['check']: c['status'] for c in checks}
    ready = all(by_name.get(name) == 'PASS' for name in required)
    return {'schema_version': 1, 'created_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
        'evidence_type': 'environment_preflight', 'pinned_official_commit': PINNED_COMMIT,
        'official_reproduction_status': 'SKIPPED', 'official_reproduction_executed': False,
        'stage': stage, 'environment_python': str(interpreter),
        'required_checks': sorted(required), 'ready_for_stage': ready,
        'ready_for_official_gpu_stage': ready and stage in GPU_STAGES, 'checks': checks}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--stage', choices=STAGE_NAMES, default='evaluate-maze')
    parser.add_argument('--require-ready', action='store_true')
    args = parser.parse_args()
    report = inspect(args.repo.resolve() if args.repo else None, args.stage)
    text = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    print(text, end='')
    return 2 if args.require_ready and not report['ready_for_stage'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
