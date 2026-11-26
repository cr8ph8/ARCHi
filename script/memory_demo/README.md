# Review kept lessons in Seed Dive

On a Mac with the macOS 14+ SDK, Swift 6 and Python 3, run this from a checkout of the demo branch.

```sh
python3 script/memory_demo/run.py
```

Pick a fictional topic and lesson, or accept the defaults. Keep Terminal visible next to the demo. The launcher stages a separately identified app, opens a fresh profile and walks you through four launches. Use **Open Seed Dive → Records** to inspect the local snapshot after each action. Quit using ⌘Q, then confirm the outcome in Terminal. The demo uses ARCHi’s ordinary lesson card, editor, admission checks and native preference storage.

| Launch | Your action and Seed check | Independent disk evidence |
| --- | --- | --- |
| 1 | Enter the lesson, click **Do not save**, and confirm Seed has no kept lesson. | The profile file is absent. |
| 2 | Re-enter the lesson, bind it to the exact shared copy, and click **Keep lesson**. See the exact text and Current status in Seed. | A new profile contains exactly one lesson with your wording and the Screenplay A SHA-256. |
| 3 | Start another lesson, bind it to the exact shared copy, switch to screenplay B inside the editor, then try **Keep lesson**. Read the rejection and click **Do not save**. Seed shows the prior lesson as Waiting for shared copy and omits the rejected draft. | The saved file matches the previous launch byte for byte. |
| 4 | Open the kept lesson and read it back in the native card and Seed. The demo starts with screenplay A again, so Seed shows Current. | The file still matches the successful Keep. |

The launcher prints an evidence directory containing a JSON result, the saved record and five checkpoints. The result identifies human-operated or XCUITest mode. The teaching session is disposable. The record and any words you entered remain in your evidence folder. The two synthetic screenplays exist only inside the demo. The source-switch button exercises the existing source-binding check while a review sheet is open.

For unattended UI testing on a logged-in Mac with Xcode and XcodeGen, run `python3 script/memory_demo/run.py --ui-test`. XCUITest works in a separate process and checks the rejection message, the Seed projection after each action, and the exact saved wording after relaunch. The Python checker reads the captured profile bytes without using the app’s decoder. The automated run retains an Xcode result bundle for each launch.

The passing Mac workflow also packages the tested Apple Silicon app alongside the independent Python reader. Extract the package to a writable folder and open **Start.command** on a Mac with Python 3 installed. It uses the included app and writes a new evidence folder on each run. The package is an ad-hoc-signed development build.
