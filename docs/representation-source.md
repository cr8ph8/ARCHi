# Optional representation source

The native app includes measurement contracts and an optional request-scoped GGUF client. Authored Python and C++ implementation sources are under `research/representation`; this directory is a code module, not a copy of the private research corpus.

The Python package provides numerical quotient proposals, bounded coupling and uncertainty propagation, representation summaries, scoped PyTorch hooks, native envelopes and reference Stack records. `pyproject.toml` declares NumPy and optional PyTorch dependencies. These calculations do not independently mutate the companion, rewrite weights or authorize an action. The native five-pressure strategy state and the archived 18-coordinate controller remain different representations.

The GGUF worker and build recipe pin llama.cpp revision `161755f29e415e2c33efe906e91843c068efd664`. Source URLs and expected checksums are recorded in `gguf/upstream-provenance.json`; the upstream llama.cpp and nlohmann JSON license texts accompany the recipe. No upstream compiled libraries, model weights or reader artifact are included in this source checkpoint.

`gguf/build.py` builds an arm64 macOS CPU observation worker using a supplied CMake executable. Downloading the pinned source archive requires its explicit `--fetch` flag; bootstrapping CMake separately requires `--bootstrap-cmake`. The recipe builds under the checkout's ignored output directory. `script/package_representation_runtime.py` copies only a locally built runtime whose manifest and member hashes match the declared contract.

The native route is optional and defaults off. Qwen availability does not imply that a model-specific reader is calibrated. The last local reader attempt did not qualify; this checkpoint includes no passing reader and makes no claim of improved answer quality. Ordinary Ollama generation exposes output rather than internal activations.

`gguf/calibrate.py` contains a separate explicit prepare/acquire/fit workflow. Running it is research work, not part of compilation or normal chat. `gguf/protocol_checks.py` can check the built worker's bounded protocol without loading model weights. Neither a protocol pass nor successful extraction alone establishes scientific validity, useful model steering or permission to change persistent state.
