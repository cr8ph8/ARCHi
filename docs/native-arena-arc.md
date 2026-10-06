# ARCHi Trials in Arena

Open **Arena → ARCHi Trials** in the native ARCHi app. ARCHi Trials is the product experience for our pattern reasoning and world exploration. The Arena hosts the existing grid solver, ARC3 environment controls and saved results alongside **Companion practice**. Switching activities is navigation only: it does not start a puzzle, discover games, call a model, launch Unity or save preferences.

## Pattern Trials

1. Choose **Pattern Trials**. Use **Import ARC task…** for one standard train/test JSON file, or **Load sample** for the labeled synthetic rotation task.
2. Choose **Solve locally**. The bounded symbolic solver uses the training examples and test inputs. Supplied test answers remain with the independent checker.
3. Review the prediction, exact-check result and work counts. Use **Trial records**, **View run in Usage** or **View in Activity map** to inspect retained evidence.
4. **Try Qwen** opens separate proposal controls. Only **Ask Qwen for a rule** starts a local model request. Browsing, loading and symbolic solving do not use model tokens.

An imported file does not establish its official provenance. A task without expected answers produces unscored predictions, not a passing benchmark. The sample is synthetic. There is no automatic benchmark sweep or public leaderboard submission.

## World Trials

1. Choose **World Trials → Find installed worlds**. This explicitly starts the existing offline discovery process; the page alone does not.
2. If needed, use **Choose world runtime…** to select a local runtime containing `.venv/bin/python` and `environment_files`. The bridge checks its pinned SDK versions (`arc-agi` 0.9.8 and `arcengine` 0.9.3).
3. Select an installed environment and a budget from 1–64 dispatches, then choose **Start trial**. The initial reset consumes one dispatch.
4. Choose a manual action, or **Explore up to 8 actions** for the existing local planning policy. It replans from observations and stops earlier when appropriate. No language model is called by this policy.
5. Use **Stop & keep record** and **Show trial record** to inspect the episode. **Session usage** uses the same accounting owner as Chat and Reasoning.

An episode remains active between actions. Stop it before starting a grid solve, replay or Qwen proposal; both Arena and Reasoning display this constraint while keeping Stop accessible. Switching tabs or visiting Chat does not discard the episode. Returning to ARCHi Trials resumes the existing session view. In Companion practice, **Your trial is still open** links back to ongoing work.

## Branding and source attribution

The public experience is **ARCHi Trials**, with **Pattern Trials**, **World Trials** and **Trial records**. **Sources & trial records** and **Environment source & limits** retain ARC/ARC3 attribution. Existing game names, version IDs, receipt schemas and `/arc3` commands remain compatible. Rebranding does not claim that ARCHi authored the imported ARC datasets, the ARC3 SDK or existing game assets. ARCHi-authored worlds can be added separately with their own source and version records.

## One system, distinct activities

`CompanionStore.arcCapabilities` and `.arc3` own execution and evidence. Arena and Reasoning are views of these same instances. `ArenaActivity` is transient navigation and does not enter the saved profile. Home/menu **Play Arena** explicitly selects Companion practice before opening Unity.

ARC tests run in native ARCHi and the installed offline ARC3 runtime. Unity companion combat remains its own play activity. ARC3 actions do not control Unity, and local test outcomes do not grant companion growth, Marketplace rewards, official ARC Prize scores or demonstrated Hampton-wide efficacy. No online test server, remote contest or multiplayer ARC protocol is introduced by this integration.

Sources: [Arena view](../desktop/Sources/ARCHiDesktop/UnityWorkspace.swift), [entry](../desktop/Sources/ARCHiDesktop/ArenaEntry.swift), [shared grid workspace](../desktop/Sources/ARCHiDesktop/ARCCapabilitiesWorkspace.swift), [ARC3 session](../desktop/Sources/ARCHiDesktop/ARC3SessionStore.swift).

## Native runtime setup

The SDK is a separate local dependency. If an older checkout uses an incompatible Python architecture, preserve it and run the [setup helper](../script/setup_arc3_runtime.py) with a native macOS Python 3.12+:

```sh
/absolute/path/to/native/python3 script/setup_arc3_runtime.py \
  --source-environments /absolute/path/to/existing/environment_files
```

These are placeholders for existing paths. The helper explicitly downloads the two pinned SDK packages and dependencies as binary wheels from PyPI, verifies imports, copies the named game folder and records its hashes and installed package versions. It runs no games, refuses an existing destination and never repairs by deleting a checkout. Review a failed partial destination before choosing another path with `--destination`.

The default destination is `~/Library/Application Support/ARCHi/ARC3Runtime-<architecture>-v1`. On next launch, ARCHi prefers that location only after setup writes its final receipt and Python/game folders exist. Otherwise it retains `~/ARC-AGI-3-Agents`. Custom destinations can be selected in **Choose world runtime…** for that app visit. The virtual environment retains a dependency on the chosen base Python installation; keep that interpreter available. This helper supplies neither new game licensing rights nor a public game service.
