#!/usr/bin/env python3
"""Bounded local ARC-AGI-3 JSONL adapter. No model or provider integration.

Only the published observation/action surface crosses stdout. The network guard
prevents accidental SDK networking; it is not an adversarial code sandbox.
Local environment Python is trusted installed code, never policy input.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager, redirect_stdout
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import logging
import os
from pathlib import Path
import re
import signal
import sys
import uuid

MAX_LINE = 65_536
REQUEST_SECONDS = 10
STARTUP_SECONDS = 45
GAME_ID = re.compile(r"[A-Za-z0-9]{4}-[A-Za-z0-9]{1,64}\Z")
STATES = {"NOT_PLAYED", "NOT_FINISHED", "WIN", "GAME_OVER"}
ERROR_CODES = {"NETWORK_BLOCKED", "SDK_VERSION_MISMATCH", "OFFLINE_INVARIANT_FAILED", "DUPLICATE_GAME_ID", "INVALID_OBSERVATION", "SESSION_ACTIVE", "INVALID_REQUEST", "GAME_UNAVAILABLE", "INVALID_ENVIRONMENT_PATH", "LOCAL_WRAPPER_REQUIRED", "SESSION_FAILED", "NO_ACTIVE_SESSION", "GAME_ID_MISMATCH", "INVALID_COORDINATES", "UNEXPECTED_COORDINATES", "TERMINAL_STATE", "ILLEGAL_ACTION", "BUDGET_EXHAUSTED", "SCORECARD_CLOSE_FAILED", "ENVIRONMENTS_UNAVAILABLE"}


class BridgeError(Exception):
    """Only fixed, authored codes may cross the protocol boundary."""


class Deadline(BaseException):
    # SDK catches Exception internally; a deadline must still escape it.
    pass


class Terminated(BaseException):
    pass


def canonical(value):
    return json.dumps(value, separators=(",", ":"), sort_keys=True, allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def integer(value, low, high):
    return type(value) is int and low <= value <= high


@contextmanager
def deadline(seconds):
    def expired(_signum, _frame):
        raise Deadline()

    old = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old)


def prepare_offline_environment(recordings):
    """Run before importing dotenv or the SDK; never read donor .env files."""
    sys.dont_write_bytecode = True
    # Use an allowlist because provider credentials have no universal name.
    retained = {"HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "SYSTEMROOT", "WINDIR"}
    for key in list(os.environ):
        if key not in retained:
            os.environ.pop(key, None)
    os.environ.update(PYTHON_DOTENV_DISABLED="1", OPERATION_MODE="offline", MPLBACKEND="Agg", MPLCONFIGDIR=str(recordings / "matplotlib"))


def load_sdk(environments, recordings):
    """SDK import is isolated from protocol stdout and credential loading."""
    blocked = []

    def audit(event, _args):
        # Binding a local socket does not send traffic. urllib3 binds ::1:0 at
        # import solely to probe IPv6 support; outbound operations remain blocked.
        if event in {"socket.connect", "socket.sendto", "socket.getaddrinfo", "socket.gethostbyname", "socket.gethostbyaddr"}:
            blocked.append(event)
            raise BridgeError("NETWORK_BLOCKED")

    sys.addaudithook(audit)
    import dotenv
    import dotenv.main
    dotenv.load_dotenv = lambda *_args, **_kwargs: False
    dotenv.main.load_dotenv = dotenv.load_dotenv
    import requests

    def reject_http(*_args, **_kwargs):
        blocked.append("requests.Session.request")
        raise BridgeError("NETWORK_BLOCKED")

    requests.sessions.Session.request = reject_http
    from arc_agi import Arcade, LocalEnvironmentWrapper, OperationMode
    from arcengine import GameAction
    versions = {"python": sys.version.split()[0], "arc-agi": importlib.metadata.version("arc-agi"), "arcengine": importlib.metadata.version("arcengine")}
    if versions["arc-agi"] != "0.9.8" or versions["arcengine"] != "0.9.3":
        raise BridgeError("SDK_VERSION_MISMATCH")
    quiet = logging.Logger("archi.arc3.offline")
    quiet.addHandler(logging.NullHandler())
    quiet.propagate = False
    arcade = Arcade(operation_mode=OperationMode.OFFLINE, environments_dir=str(environments), recordings_dir=str(recordings / "sdk"), logger=quiet)
    if arcade.operation_mode is not OperationMode.OFFLINE or arcade.arc_api_key:
        raise BridgeError("OFFLINE_INVARIANT_FAILED")
    return arcade, GameAction, LocalEnvironmentWrapper, versions, blocked


class Bridge:
    def __init__(self, environments, recordings, sdk):
        self.environments = Path(environments).resolve()
        self.recordings = Path(recordings).resolve()
        self.arcade, self.action_type, self.wrapper_type, self.versions, self.network_attempts = sdk
        self.session = None
        self.env = None
        self.latest = None
        self.receipt_path = None
        self.active = False
        self.failed = False

    def inventory(self):
        entries = {}
        for entry in self.arcade.get_environments():
            if not isinstance(entry.game_id, str) or not GAME_ID.fullmatch(entry.game_id) or not entry.local_dir:
                continue
            local = Path(entry.local_dir).resolve()
            if not local.is_relative_to(self.environments) or not (local / "metadata.json").is_file():
                continue
            if entry.game_id in entries:
                raise BridgeError("DUPLICATE_GAME_ID")
            entries[entry.game_id] = entry
        return entries

    def write_receipt(self):
        if self.session is None:
            return
        self.session["networkAttempts"] = list(self.network_attempts)
        self.session["updatedAt"] = now()
        self.session["receiptDigest"] = digest({k: v for k, v in self.session.items() if k != "receiptDigest"})
        pending = self.receipt_path.with_suffix(".tmp")
        pending.write_text(json.dumps(self.session, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
        pending.replace(self.receipt_path)

    def observation(self, raw, action):
        if raw is None or raw.game_id != self.session["gameID"]:
            raise BridgeError("INVALID_OBSERVATION")
        state = getattr(raw.state, "value", raw.state)
        if state not in STATES or not integer(raw.levels_completed, 0, 10000) or not integer(raw.win_levels, 0, 10000) or raw.levels_completed > raw.win_levels:
            raise BridgeError("INVALID_OBSERVATION")
        allowed = list(raw.available_actions)
        if any(not integer(a, 0, 7) for a in allowed) or len(set(allowed)) != len(allowed):
            raise BridgeError("INVALID_OBSERVATION")
        frames = [layer.tolist() if hasattr(layer, "tolist") else layer for layer in raw.frame]
        if not frames or len(frames) > 1024:
            raise BridgeError("INVALID_OBSERVATION")
        for frame in frames:
            if not isinstance(frame, list) or not 1 <= len(frame) <= 64 or not isinstance(frame[0], list) or not 1 <= len(frame[0]) <= 64:
                raise BridgeError("INVALID_OBSERVATION")
            width = len(frame[0])
            if any(not isinstance(row, list) or len(row) != width or any(not integer(pixel, 0, 15) for pixel in row) for row in frame):
                raise BridgeError("INVALID_OBSERVATION")
        observation = {"gameID": raw.game_id, "state": state, "levelsCompleted": raw.levels_completed, "winLevels": raw.win_levels, "availableActions": allowed, "frame": frames[-1], "frameDigest": digest(frames[-1]), "dispatches": self.session["dispatches"], "budget": self.session["budget"]}
        self.session["observations"].append({"index": len(self.session["observations"]), "observedAt": now(), "action": action, "observation": observation, "allFrames": frames, "allFramesDigest": digest(frames), "provenance": "local-sdk-returned-observation"})
        self.latest = observation
        return observation

    def dispatch(self, action, operation):
        self.session["dispatches"] += 1
        event = {"index": self.session["dispatches"], "action": action, "status": "DISPATCH_ATTEMPT", "at": now()}
        self.session["actions"].append(event)
        self.write_receipt()
        raw = operation()
        result = self.observation(raw, action)
        event["status"] = "ACKNOWLEDGED"
        event["observationDigest"] = result["frameDigest"]
        self.write_receipt()
        return result

    def start(self, request):
        if self.active:
            raise BridgeError("SESSION_ACTIVE")
        game_id, budget = request.get("gameID"), request.get("budget")
        if not isinstance(game_id, str) or not GAME_ID.fullmatch(game_id) or not integer(budget, 1, 64):
            raise BridgeError("INVALID_REQUEST")
        entries = self.inventory()
        if game_id not in entries:
            raise BridgeError("GAME_UNAVAILABLE")
        local = Path(entries[game_id].local_dir).resolve()
        files = {}
        for source in sorted(local.rglob("*")):
            if source.is_file() and "__pycache__" not in source.parts:
                if not source.resolve().is_relative_to(local):
                    raise BridgeError("INVALID_ENVIRONMENT_PATH")
                files[str(source.relative_to(local))] = hashlib.sha256(source.read_bytes()).hexdigest()
        session_dir = self.recordings / ("session-" + str(uuid.uuid4()))
        session_dir.mkdir(parents=True, exist_ok=False)
        self.receipt_path = session_dir / "receipt.json"
        self.session = {"schema": "archi.arc3.offline-session.v1", "sessionID": session_dir.name, "gameID": game_id, "budget": budget, "dispatches": 0, "startedAt": now(), "status": "ACTIVE", "operationMode": "offline", "seed": 0, "sdkVersions": dict(self.versions), "sourceEnvironmentFileDigests": files, "bridgeDigest": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "actions": [], "observations": [], "errors": [], "scorecardClosed": False, "limits": {"requestSeconds": REQUEST_SECONDS, "startupSeconds": STARTUP_SECONDS, "maxRequestBytes": MAX_LINE, "dispatchBudgetIncludesImplicitRESET": True}, "evidenceScope": "LOCAL_PUBLIC_GAME_OBSERVATIONS_ONLY", "limitations": ["No benchmark performance or intelligence claim.", "Local dispatch attempts differ from SDK scorecard action accounting.", "Network guard is not an adversarial sandbox; installed environment source is trusted.", "Only the final visual frame is exposed over the policy protocol; all returned frames are retained here."]}
        self.latest = None
        self.env = None
        self.active = True
        self.write_receipt()
        self.session["scorecardID"] = self.arcade.open_scorecard(tags=["archi", "offline", "bounded-public-game"])

        def make():
            self.env = self.arcade.make(game_id, seed=0, scorecard_id=self.session["scorecardID"], save_recording=True, include_frame_data=True)
            if not isinstance(self.env, self.wrapper_type):
                raise BridgeError("LOCAL_WRAPPER_REQUIRED")
            return self.env.observation_space

        return self.dispatch({"id": 0, "data": {}, "implicit": True}, make)

    def step(self, request):
        if not self.active:
            raise BridgeError("SESSION_FAILED" if self.session and self.session["status"] == "FAILED" else "NO_ACTIVE_SESSION")
        action = request.get("action")
        if not integer(action, 0, 7):
            raise BridgeError("INVALID_REQUEST")
        if "gameID" in request and request["gameID"] != self.session["gameID"]:
            raise BridgeError("GAME_ID_MISMATCH")
        if action == 6:
            if not integer(request.get("x"), 0, 63) or not integer(request.get("y"), 0, 63):
                raise BridgeError("INVALID_COORDINATES")
            payload = {"x": request["x"], "y": request["y"]}
        else:
            if "x" in request or "y" in request:
                raise BridgeError("UNEXPECTED_COORDINATES")
            payload = {}
        if action != 0 and self.latest["state"] in {"WIN", "GAME_OVER"}:
            raise BridgeError("TERMINAL_STATE")
        if action != 0 and action not in self.latest["availableActions"]:
            raise BridgeError("ILLEGAL_ACTION")
        if self.session["dispatches"] >= self.session["budget"]:
            raise BridgeError("BUDGET_EXHAUSTED")
        sdk_action = self.action_type.from_id(action)
        sdk_action.validate_data(payload)
        return self.dispatch({"id": action, "data": payload, "implicit": False}, lambda: self.env.step(sdk_action, data=payload))

    def close(self, reason="CLIENT_CLOSE"):
        if self.session is None or not self.active:
            return
        self.active = False
        self.session["closeReason"] = reason
        self.session["closedAt"] = now()
        try:
            card_id = self.session.get("scorecardID")
            if card_id:
                card = self.arcade.close_scorecard(card_id)
                if card is None:
                    raise BridgeError("SCORECARD_CLOSE_FAILED")
                self.session["localScorecard"] = card.model_dump(mode="json", exclude={"api_key"})
                self.session["scorecardClosed"] = True
            if self.network_attempts:
                raise BridgeError("NETWORK_BLOCKED")
        except (Exception, Deadline):
            self.session["errors"].append("SCORECARD_CLOSE_FAILED")
            self.session["status"] = "FAILED"
            self.failed = True
        if self.session["status"] != "FAILED":
            self.session["status"] = "CLOSED"
        self.env = None
        self.write_receipt()

    def abort(self, code):
        self.failed = True
        if self.session is not None and self.active:
            self.session["status"] = "FAILED"
            self.session["errors"].append(code)
            try:
                with deadline(REQUEST_SECONDS), redirect_stdout(sys.stderr):
                    self.close("FAIL_CLOSED")
            except (Exception, Deadline):
                # The response still reports failure if disk/cleanup is unavailable.
                self.active = False
                self.env = None

    def handle(self, request):
        request_id = request.get("id", "") if isinstance(request, dict) else ""
        if not isinstance(request_id, str) or not 1 <= len(request_id) <= 128 or any(ord(c) < 32 for c in request_id):
            return {"id": "", "ok": False, "error": "INVALID_REQUEST"}
        response = {"id": request_id, "ok": False}
        command = request.get("command")
        keys = {"discover": {"id", "command"}, "start": {"id", "command", "gameID", "budget"}, "step": {"id", "command", "gameID", "action", "x", "y"}, "close": {"id", "command"}}
        if not isinstance(command, str) or command not in keys or set(request) - keys[command]:
            return {**response, "error": "INVALID_REQUEST"}
        before = self.session["dispatches"] if self.session and self.active else 0
        try:
            with deadline(REQUEST_SECONDS), redirect_stdout(sys.stderr):
                if command == "discover":
                    response["games"] = [{"id": key, "title": str(entry.title or key)[:128]} for key, entry in sorted(self.inventory().items())]
                elif command == "start":
                    response["observation"] = self.start(request)
                elif command == "step":
                    response["observation"] = self.step(request)
                else:
                    self.close()
                    if self.session and self.session["status"] == "FAILED":
                        raise BridgeError("SESSION_FAILED")
                if self.network_attempts:
                    raise BridgeError("NETWORK_BLOCKED")
                response["ok"] = True
        except BridgeError as exc:
            code = str(exc) if str(exc) in ERROR_CODES else "SDK_FAILURE"
            response["error"] = code
            # Only validation errors before dispatch preserve the active session.
            if self.active and (self.session["dispatches"] > before or command == "start" and code != "SESSION_ACTIVE" or code == "NETWORK_BLOCKED"):
                self.abort(code)
        except (Exception, Deadline) as exc:
            response["error"] = "REQUEST_TIMEOUT" if isinstance(exc, Deadline) else "SDK_FAILURE"
            self.abort(response["error"])
        if command != "discover" and self.receipt_path:
            response["receiptPath"] = str(self.receipt_path)
            if self.latest:
                response["observation"] = {**self.latest, "dispatches": self.session["dispatches"]}
        return response


def serve(bridge, source, output):
    """One response per input line. EOF finalizes receipts without unsolicited JSON."""
    try:
        while True:
            line = source.readline(MAX_LINE + 1)
            if not line:
                break
            if len(line) > MAX_LINE:
                response = {"id": "", "ok": False, "error": "REQUEST_TOO_LARGE"}
            else:
                try:
                    request = json.loads(line)
                except (ValueError, UnicodeError):
                    response = {"id": "", "ok": False, "error": "INVALID_JSON"}
                else:
                    response = bridge.handle(request)
            output.write(canonical(response) + "\n")
            output.flush()
            if len(line) > MAX_LINE:
                break  # Do not drain an unbounded hostile line or treat its tail as another request.
    except (Terminated, BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        try:
            with deadline(REQUEST_SECONDS), redirect_stdout(sys.stderr):
                bridge.close("INPUT_ENDED")
        except (Exception, Deadline, Terminated):
            bridge.failed = True
    return 1 if bridge.failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environments-dir", required=True, type=Path)
    parser.add_argument("--recordings-dir", required=True, type=Path)
    args = parser.parse_args()
    environments, recordings = args.environments_dir.resolve(), args.recordings_dir.resolve()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda _s, _f: (_ for _ in ()).throw(Terminated()))
    try:
        with deadline(STARTUP_SECONDS), redirect_stdout(sys.stderr):
            if not environments.is_dir():
                raise BridgeError("ENVIRONMENTS_UNAVAILABLE")
            recordings.mkdir(parents=True, exist_ok=True)
            prepare_offline_environment(recordings)
            sdk = load_sdk(environments, recordings)
            bridge = Bridge(environments, recordings, sdk)
    except (Exception, Deadline, Terminated) as exc:
        code = str(exc) if isinstance(exc, BridgeError) and str(exc) in ERROR_CODES else "STARTUP_TIMEOUT" if isinstance(exc, Deadline) else "STARTUP_FAILED"
        print(canonical({"id": "", "ok": False, "error": code}), flush=True)
        return 1
    return serve(bridge, sys.stdin.buffer, sys.stdout)


if __name__ == "__main__":
    raise SystemExit(main())
