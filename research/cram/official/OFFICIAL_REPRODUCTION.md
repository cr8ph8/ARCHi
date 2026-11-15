# Official CRAM reproduction handoff

## Status

The official GPU benchmark is **SKIPPED in the ChatGPT executor**. The executor has Python 3.12, NumPy and roughly 9.7 GiB host RAM; it has no demonstrated NVIDIA GPU, PyTorch, or Triton. This is an environment observation, not a failed CRAM result. No H200 or RTX 4090 timing has been measured here.

`provenance.json` records the immutable upstream commit and verified Git blob SHA and SHA-256 of eight inspected upstream files. Upstream source is not vendored here. The commands below obtain the unchanged full checkout, including its Apache 2.0 license.

## Pinned upstream

- Repository: https://github.com/Prefrontal-AI/CRAM
- Commit: `62bbe830c7d6f87f2ba18f30a28039258b986454`
- Commit date: 2026-11-13
- Paper: https://arxiv.org/abs/2611.17309v1
- Reproduction instructions: https://github.com/Prefrontal-AI/CRAM/blob/62bbe830c7d6f87f2ba18f30a28039258b986454/REPRODUCING.md
- Environment definition: https://github.com/Prefrontal-AI/CRAM/blob/62bbe830c7d6f87f2ba18f30a28039258b986454/pyproject.toml

The pinned project requires Python >=3.12 and PyTorch 2.11.0. On Linux its package configuration selects the CUDA 12.8 PyTorch index. Sudoku search uses Triton. Native Windows execution is unverified. For the user's Windows RTX 4090 machine, a Linux/WSL2 environment is the proposed route; WSL2 GPU visibility, driver compatibility and Triton kernel execution still need to be observed. The reported Windows machine's 128 GB RAM exceeds the documented approximately 32 GB preparation requirement, but available RAM inside WSL must also be checked.

## Prepare an isolated checkout on the GPU machine

Start in the ARCHi repository root in a Linux shell with `git`, `uv` and an NVIDIA GPU exposed. The checkout and evidence go into a sibling directory outside tracked ARCHi source. Choose a fresh sibling directory if this one already exists.

```sh
CRAM_PILOT_ROOT="$(pwd)/research/cram/official"
CRAM_WORK_ROOT="$(dirname "$(pwd)")/archi-cram-work"
CRAM_ROOT="$CRAM_WORK_ROOT/CRAM-official"
CRAM_EVIDENCE_ROOT="$CRAM_WORK_ROOT/gpu-run-001"
mkdir -p "$CRAM_WORK_ROOT"
git clone https://github.com/Prefrontal-AI/CRAM.git "$CRAM_ROOT"
git -C "$CRAM_ROOT" checkout --detach 62bbe830c7d6f87f2ba18f30a28039258b986454
uv sync --project "$CRAM_ROOT" --frozen
```

`uv sync --frozen` retains the upstream lockfile. Do not silently upgrade dependencies or remove version pins when setup fails; record the actual failure. The official `AGENTS.md` requests a project-local environment and GPU execution for fits, searches and tests.

Inspect that exact virtual environment:

```sh
python3 "$CRAM_PILOT_ROOT/preflight.py" --repo "$CRAM_ROOT" --output "$CRAM_EVIDENCE_ROOT/preflight.json" --require-ready
```

The preflight probes the checkout's `.venv/bin/python` (or `.venv/Scripts/python.exe`) explicitly, even if invoked with system `python3`. The runner executes that same interpreter. A ready preflight establishes the checked prerequisites for attempting the selected stage, not model correctness or operating-system permissions. It does not install software or call the network.

## Bounded execution stages

The wrapper plans a stage unless `--execute` is supplied. It refuses execution if the stage-specific preflight lacks a required PASS, the upstream commit differs, or tracked source is modified. Preparation needs the data-loading dependencies, and Sudoku preparation additionally checks host memory; it does not require CUDA. Training, tests and evaluation require the reference CUDA/Triton environment. After setup the wrapper calls the observed project interpreter directly and does not run an implicit dependency synchronization.

It writes one stage record and a log into a fresh output directory. Existing stage records are not overwritten. The tracked-source check excludes untracked and ignored files, so expected generated data and run files do not block later stages; modifications to tracked source still block execution. This is a reproducibility check, not a filesystem security sandbox. Dependency discoverability does not establish kernel execution or every read/write permission. The stage's actual process result records those failures.

```sh
python3 "$CRAM_PILOT_ROOT/run_official.py" --repo "$CRAM_ROOT" --stage tests --output-dir "$CRAM_EVIDENCE_ROOT" --execute
python3 "$CRAM_PILOT_ROOT/run_official.py" --repo "$CRAM_ROOT" --stage prepare-maze --output-dir "$CRAM_EVIDENCE_ROOT" --execute
python3 "$CRAM_PILOT_ROOT/run_official.py" --repo "$CRAM_ROOT" --stage evaluate-maze --output-dir "$CRAM_EVIDENCE_ROOT" --execute
```

These call the documented upstream tests, Maze-Unique preparation, and checkpoint evaluator for seeds 0, 1 and 2. The upstream expectation is 1,000/1,000 Maze-Unique test mazes for each seed. A stage PASS means its process exited successfully; inspect the log for the upstream score comparison. `official_reproduction_executed` becomes true only for an evaluation stage that actually exits 0; failed evaluations are separately recorded as attempted. Preparation, tests and training cannot set that flag. A differing score is evidence to investigate, not a reason to replace it with the recorded expectation.

For the Sudoku phase, first check available RAM. Upstream preparation uses about 32 GB and writes about 2 GB of data, excluding environment and cache storage. Then execute `prepare-sudoku`, followed by `evaluate-sudoku-dev` using the same wrapper. The default Sudoku evaluator runs 10,000 **development** puzzles. Keep this label in reports.

The full Sudoku test has 412,786 puzzles and is documented at about 1.5 H200 GPU-hours per seed. It is deliberately absent from the default wrapper stages. Freeze settings and budgets before that expensive test. Do not call the development evaluation a full benchmark reproduction.

Optional `train-sudoku` and `train-maze` stages use the authors' training commands. Upstream warns that Sudoku CUDA random relabelings can differ across GPU types; identical model hashes on an H200 are not an appropriate requirement for a different GPU. Record weights, seed, device and measured scores.

## Evidence boundaries

1. `official_preflight.json` in the portable run output: executed environment check in the ChatGPT executor.
2. `provenance.json`: verified source retrieval; no benchmark execution and no vendored snapshot.
3. `preflight.json` in the GPU output directory: future GPU environment observation.
4. `gpu-run-*/`: actual upstream execution records, when run.
5. Any separate NumPy/CPU demonstration: original pilot implementation, never an official CRAM reproduction.

Record all cold-start, fit-only, search-only and end-to-end timings separately. Count incorrect stops, budget exhaustion and valid completions independently. A candidate energy or stopping threshold cannot authorize an ARCHi COMMIT. Preserve an independent task validator and the existing authority, revision and scope checks.

## What is still unverified

- WSL2/native Windows compatibility on the user's machine.
- The RTX 4090's observed driver, CUDA and Triton behavior.
- Official checkpoint accuracy and training behavior in that environment.
- End-to-end runtime and memory cost on the RTX 4090.
- Any production ARCHi adapter or durable application state integration.

The accompanying runner and preflight are newly authored integration scaffolding. They are outside the upstream snapshot and do not change the upstream solver.
