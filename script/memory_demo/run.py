#!/usr/bin/env python3
"""Stage the native app, then verify a private session across four launches."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PHASES = ("baseline", "discard", "keep", "stale", "reopen")
SOURCE_A = {"name": "Screenplay A", "digest": hashlib.sha256("INT. ARENA – DAY".encode()).hexdigest()}


def digest(data):
    return hashlib.sha256(data).hexdigest() if data is not None else None


def verify(snapshots, topic, text):
    if set(snapshots) != set(PHASES):
        raise ValueError("Missing checkpoint")
    if snapshots["baseline"] is not None or snapshots["discard"] is not None:
        raise ValueError("A new profile or discarded draft produced a save")
    saved = snapshots["keep"]
    if not saved or snapshots["stale"] != saved or snapshots["reopen"] != saved:
        raise ValueError("Keep must create a record and stale/reopen must preserve its exact bytes")
    def unique_keys(pairs):
        fields = dict(pairs)
        if len(fields) != len(pairs):
            raise ValueError("Duplicate JSON key in native profile")
        return fields
    doc = json.loads(saved, object_pairs_hook=unique_keys)
    if doc.get("schema") != "archi-native-preferences/v5" or type(doc.get("revision")) is not int or doc["revision"] != 1:
        raise ValueError("Unexpected saved schema or revision")
    if not isinstance(doc.get("lessons"), list) or len(doc["lessons"]) != 1:
        raise ValueError("Expected exactly one kept lesson")
    lesson = doc["lessons"][0]
    if (lesson.get("topic"), lesson.get("text"), lesson.get("reason")) != (topic, text, ""):
        raise ValueError("Saved wording differs from the reviewed lesson")
    if type(lesson.get("revision")) is not int or lesson["revision"] != 1:
        raise ValueError("Incorrect lesson revision")
    uuid.UUID(lesson["id"])
    if lesson.get("source") != SOURCE_A:
        raise ValueError("The retained lesson must be bound to the exact Screenplay A copy")
    if any(lesson.get(key) is not None for key in ("origin", "expiresAt")):
        raise ValueError("Unexpected model attribution or expiry")
    for key in ("createdAt", "updatedAt"):
        if type(lesson.get(key)) not in (float, int):
            raise ValueError("Missing native timestamp")
    return {"status": "PASS", "topic": topic, "reviewed_text": text, "saved_lesson": lesson,
            "checkpoints": {name: {"exists": data is not None, "sha256": digest(data)}
                            for name, data in snapshots.items()}}


def snapshot(profile):
    try:
        return profile.read_bytes()
    except FileNotFoundError:
        return None


def checkpoint(out, phase, data):
    # Absence is recorded explicitly so a missing checkpoint cannot pass.
    (out / (phase + ".json")).write_text(json.dumps({"present": data is not None,
                                                      "profile_hex": data.hex() if data is not None else None}))


def load_checkpoints(out):
    result = {}
    for phase in PHASES:
        record = json.loads((out / (phase + ".json")).read_text())
        raw = record["profile_hex"]
        if record["present"] is not (raw is not None):
            raise ValueError("Inconsistent presence marker")
        result[phase] = bytes.fromhex(raw) if raw is not None else None
    return result


def manual(out, app, session, profile, topic, text):
    steps = (
        ("discard", f'Choose “Keep a lesson…”. Enter topic “{topic}” and lesson “{text}”. Click “Do not save”. '
                    'Open Seed Dive → Records and search for “Kept lesson”. Confirm there are no matches.'),
        ("keep", f'Confirm the list is empty. Create the same lesson, “{text}”, under “{topic}”. '
                 'Check “Use only with this exact shared copy”, then click “Keep lesson”. '
                 f'Open Seed Dive → Records, select “{topic}”, and confirm Current and the exact kept text.'),
        ("stale", 'Open another lesson and enter “rejected draft” and “Wrong source”. '
                  'Check “Use only with this exact shared copy”, switch to screenplay B, and click “Keep lesson”. '
                  'Check the source-change message, then click “Do not save”. '
                  f'Open Seed Dive → Records and confirm that “{topic}” is Waiting for shared copy '
                  'and that “rejected draft” is absent.'),
        ("reopen", f'Expand the single kept record. Confirm its text is exactly “{text}”. '
                   f'Open Seed Dive → Records, select “{topic}”, and confirm Current and the same text.'),
    )
    checkpoint(out, "baseline", snapshot(profile))
    for phase, instructions in steps:
        print(f'\n{phase.upper()} — {instructions}\nQuit the demo using ⌘Q to continue.', flush=True)
        subprocess.run(["open", "-n", "-W", str(app), "--args", "--session", session], check=True)
        if input("Did you see and complete the action above? [y/N] ").strip().lower() != "y":
            raise ValueError("Operator did not confirm " + phase)
        checkpoint(out, phase, snapshot(profile))


def ui_test(out, app, session, profile, topic, text):
    with tempfile.TemporaryDirectory(prefix="archi-memory-ui-") as directory:
        project = Path(directory)
        shutil.copy(HERE / "project.yml", project)
        shutil.copy(HERE / "MemoryUITests.swift", project)
        config = dict(app=str(app), session=session, topic=topic, text=text)
        (project / "run.json").write_text(json.dumps(config))
        subprocess.run(["xcodegen", "generate"], cwd=project, check=True)
        common = ["xcodebuild", "-project", "MemoryUITests.xcodeproj", "-scheme", "MemoryUITests",
                  "-destination", "platform=macOS", "-parallel-testing-enabled", "NO",
                  "-derivedDataPath", str(project / "DerivedData"), "-enableCodeCoverage", "NO"]
        subprocess.run(common + ["build-for-testing"], cwd=project, check=True)
        checkpoint(out, "baseline", snapshot(profile))
        for phase in PHASES[1:]:
            method = "test" + phase.title()
            subprocess.run(common + ["test-without-building", "-only-testing:MemoryUITests/MemoryUITests/" + method,
                                     "-resultBundlePath", str(out / (phase + ".xcresult"))], cwd=project, check=True)
            # Xcode can succeed with zero matching tests. Require the individual test to have passed.
            result = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                              "--path", str(out / (phase + ".xcresult"))], text=True)
            summary = json.loads(result)
            if (summary.get("passedTests"), summary.get("failedTests"), summary.get("skippedTests")) != (1, 0, 0):
                raise ValueError("Required UI test did not run and pass: " + method)
            checkpoint(out, phase, snapshot(profile))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ui-test", action="store_true", help="Drive the visible controls with XCUITest")
    parser.add_argument("--output", type=Path, help="New directory for the evidence")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This demo launches an actual macOS app and needs a Mac")
    session = str(uuid.uuid4()).upper()
    profile_dir = Path("/private/tmp/archi-memory-demo-" + session)
    topic, text = "Sol core", "Sol’s core is amber."
    if args.ui_test:
        # Use keyboard-layout-independent input in XCUITest.
        text = "The Sol core is amber."
    else:
        print("Use a fictional example. The report will contain your exact words.")
        topic = input(f"Topic [{topic}]: ").strip() or topic
        text = input(f"Lesson [{text}]: ").strip() or text
    if not 2 <= len(topic) <= 80 or not 1 <= len(text) <= 600:
        parser.error("Choose a 2–80 character topic and a 1–600 character lesson")
    out = args.output.resolve() if args.output else Path.cwd() / ("archi-memory-evidence-" + session)
    out.mkdir(mode=0o700)
    profile_dir.mkdir(mode=0o700)
    profile = profile_dir / "preferences.json"
    report = {"status": "ERROR", "mode": "XCUITest" if args.ui_test else "human-operated",
              "session": session, "macOS": platform.mac_ver()[0], "architecture": platform.machine()}
    print("Evidence:", out, flush=True)
    try:
        app = HERE / "ARCHi Memory Demo.app"
        if app.is_dir():
            build = json.loads((HERE / "build.json").read_text())
            report["source_commit"] = build["source_commit"]
            if digest((app / "Contents/MacOS/ARCHiDesktop").read_bytes()) != build["app_binary_sha256"]:
                raise ValueError("Demo executable does not match the packaged build record")
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        else:
            report["source_commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
            subprocess.run(["bash", str(ROOT / "script/build_and_run.sh"), "--memory-demo"], cwd=ROOT, check=True)
            app = Path(f"/private/tmp/archi-desktop-candidate-{os.getuid()}/ARCHi Memory Demo.app")
        report["app_binary_sha256"] = digest((app / "Contents/MacOS/ARCHiDesktop").read_bytes())
        if args.ui_test:
            ui_test(out, app, session, profile, topic, text)
        else:
            manual(out, app, session, profile, topic, text)
        report.update(verify(load_checkpoints(out), topic, text))
        print("PASS · All four launch checks completed and the independent disk checks matched.")
    except (OSError, ValueError, KeyError, EOFError, subprocess.CalledProcessError) as exc:
        report["error"] = str(exc)
        raise
    finally:
        (out / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        # Only the new private demo session is retired. Evidence includes its saved record.
        shutil.rmtree(profile_dir)


if __name__ == "__main__":
    main()
