# Review what ARCHi remembers

On a Mac with the macOS 14+ SDK, Swift 6 and Python 3, run this from a checkout of the demo branch.

```sh
python3 script/memory_demo/run.py
```

Pick a fictional topic and lesson, or accept the defaults. Keep Terminal visible next to the demo. The launcher stages a separately identified app, opens a fresh profile and walks you through four launches. Quit using ⌘Q after each action. The demo uses ARCHi’s ordinary lesson card, editor, admission checks and native preference storage.

| Launch | Your action | Independent disk evidence |
| --- | --- | --- |
| 1 | Enter the lesson and click **Do not save**. | The profile file is absent. |
| 2 | See the empty list, re-enter the lesson and click **Keep lesson**. | A new profile contains exactly one lesson with your wording. |
| 3 | Start another lesson, bind it to the exact shared copy, switch to screenplay B inside the editor, then try **Keep lesson**. Read the rejection and click **Do not save**. | The saved file matches the previous launch byte for byte. |
| 4 | Open the kept lesson and read it back. | The file still matches the successful Keep. |

The launcher prints an evidence directory containing a JSON result, the saved record and five checkpoints. The result identifies human-operated or XCUITest mode. The teaching session is disposable. The record and any words you entered remain in your evidence folder. The two synthetic screenplays exist only inside the demo. The source-switch button exercises the existing source-binding check while a review sheet is open.

For unattended UI testing on a logged-in Mac with Xcode and XcodeGen, run `python3 script/memory_demo/run.py --ui-test`. XCUITest works in a separate process and checks the rejection message and the exact wording on the final screen. The Python checker reads the captured profile bytes without using the app’s decoder. The automated run retains the Xcode result bundle.
