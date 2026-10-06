#!/usr/bin/env python3
"""Focused offline bridge contracts. Fake SDK only; no donor source imports."""

from contextlib import redirect_stdout
from enum import IntEnum
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch

BRIDGE_PATH = Path(__file__).resolve().parents[1] / "desktop/Sources/ARCHiDesktop/Resources/ARC3Bridge/archi_arc3_bridge.py"
spec = importlib.util.spec_from_file_location("archi_arc3_bridge", BRIDGE_PATH)
bridge_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge_module)


class FakeAction(IntEnum):
    RESET = 0
    ACTION1 = 1
    ACTION2 = 2
    ACTION3 = 3
    ACTION4 = 4
    ACTION5 = 5
    ACTION6 = 6
    ACTION7 = 7

    @classmethod
    def from_id(cls, action_id):
        return cls(action_id)

    def validate_data(self, data):
        if self == FakeAction.ACTION6:
            assert set(data) == {"x", "y"}
        else:
            assert data == {}


def frame(allowed=(1, 6), state="NOT_FINISHED", frames=None):
    return SimpleNamespace(game_id="ls20-9607627b", state=SimpleNamespace(value=state), levels_completed=0, win_levels=7, available_actions=list(allowed), frame=frames or [[[0, 1], [2, 3]], [[3, 2], [1, 0]]])


class FakeWrapper:
    def __init__(self, arcade):
        self.arcade = arcade
        self.observation_space = frame()

    def step(self, action, data):
        self.arcade.calls.append((int(action), dict(data)))
        if self.arcade.noisy:
            print("incidental SDK output")
        if self.arcade.error:
            raise self.arcade.error
        self.observation_space = self.arcade.next_frame
        return self.observation_space


class FakeCard:
    def model_dump(self, **kwargs):
        assert "api_key" in kwargs["exclude"]
        return {"total_actions": 1, "score": 0.0}


class FakeArcade:
    def __init__(self, local):
        self.entries = [SimpleNamespace(game_id="ls20-9607627b", title="LS20", local_dir=str(local))]
        self.calls = []
        self.closed = []
        self.next_frame = frame()
        self.error = None
        self.make_error = None
        self.close_error = None
        self.noisy = False

    def get_environments(self):
        return self.entries

    def open_scorecard(self, **kwargs):
        return "local-card"

    def make(self, game_id, **kwargs):
        self.calls.append((0, {}))
        assert kwargs["save_recording"] and kwargs["include_frame_data"]
        if self.make_error:
            raise self.make_error
        return FakeWrapper(self)

    def close_scorecard(self, card_id):
        self.closed.append(card_id)
        if self.close_error:
            raise self.close_error
        return FakeCard()


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.environments = self.root / "environments"
        self.local = self.environments / "ls20" / "9607627b"
        self.local.mkdir(parents=True)
        (self.local / "metadata.json").write_text('{"game_id":"ls20-9607627b"}')
        (self.local / "ls20.py").write_text("# Unexecuted fixture source\n")
        self.arcade = FakeArcade(self.local)
        self.bridge = bridge_module.Bridge(self.environments, self.root / "recordings", (self.arcade, FakeAction, FakeWrapper, {"arc-agi": "fake", "arcengine": "fake"}, []))
        self.sequence = 0

    def request(self, command, **kwargs):
        self.sequence += 1
        return self.bridge.handle({"id": str(self.sequence), "command": command, **kwargs})

    def start(self, budget=3):
        result = self.request("start", gameID="ls20-9607627b", budget=budget)
        self.assertTrue(result["ok"], result)
        return result

    def receipt(self):
        return json.loads(self.bridge.receipt_path.read_text())

    def test_discovery_uses_local_metadata_without_dispatch_or_source_disclosure(self):
        result = self.request("discover")
        self.assertEqual(result["games"], [{"id": "ls20-9607627b", "title": "LS20"}])
        self.assertEqual(self.arcade.calls, [])
        self.assertNotIn("Unexecuted", json.dumps(result))
        self.assertFalse((self.root / "recordings").exists())

    def test_last_frame_digest_and_all_frames_receipt_provenance(self):
        result = self.start()
        observation = result["observation"]
        expected = [[3, 2], [1, 0]]
        self.assertEqual(observation["frame"], expected)
        self.assertEqual(observation["frameDigest"], hashlib.sha256(json.dumps(expected, separators=(",", ":")).encode()).hexdigest())
        self.assertEqual(observation["dispatches"], 1)
        receipt = self.receipt()
        self.assertEqual(len(receipt["observations"][0]["allFrames"]), 2)
        self.assertEqual(set(receipt["sourceEnvironmentFileDigests"]), {"metadata.json", "ls20.py"})
        self.assertEqual(receipt["receiptDigest"], bridge_module.digest({k: v for k, v in receipt.items() if k != "receiptDigest"}))

    def test_budget_counts_implicit_reset_and_rejects_third_dispatch(self):
        self.start(2)
        self.assertTrue(self.request("step", action=1)["ok"])
        self.assertEqual(self.request("step", action=1)["error"], "BUDGET_EXHAUSTED")
        self.assertEqual(self.arcade.calls, [(0, {}), (1, {})])
        self.assertEqual(self.receipt()["dispatches"], 2)

    def test_one_dispatch_budget_leaves_initial_observation_only(self):
        self.start(1)
        self.assertEqual(self.request("step", action=0)["error"], "BUDGET_EXHAUSTED")
        self.assertEqual(len(self.arcade.calls), 1)

    def test_strict_budget_versioned_identity_and_unknown_fields(self):
        for budget in (True, False, 0, 65, 1.0, "2", None):
            self.assertEqual(self.request("start", gameID="ls20-9607627b", budget=budget)["error"], "INVALID_REQUEST")
        self.assertEqual(self.request("start", gameID="ls20", budget=2)["error"], "INVALID_REQUEST")
        self.assertEqual(self.request("discover", api_key="secret")["error"], "INVALID_REQUEST")
        self.assertEqual(self.arcade.calls, [])

    def test_new_start_rejected_while_active(self):
        self.start()
        self.assertEqual(self.request("start", gameID="ls20-9607627b", budget=4)["error"], "SESSION_ACTIVE")
        self.assertTrue(self.bridge.active)
        self.assertEqual(len(self.arcade.calls), 1)

    def test_legality_uses_latest_observation_and_reset_is_explicit(self):
        self.start(4)
        self.assertEqual(self.request("step", action=2)["error"], "ILLEGAL_ACTION")
        self.arcade.next_frame = frame(allowed=(2,))
        self.assertTrue(self.request("step", action=1)["ok"])
        self.assertEqual(self.request("step", action=1)["error"], "ILLEGAL_ACTION")
        self.assertTrue(self.request("step", action=0)["ok"])
        self.assertEqual([call[0] for call in self.arcade.calls], [0, 1, 0])

    def test_coordinate_orientation_bounds_and_strict_action_types(self):
        self.start(3)
        for coords in ({"x": 64, "y": 0}, {"x": -1, "y": 0}, {"x": True, "y": 0}, {"x": 0}, {"x": 0, "y": 1.0}):
            self.assertEqual(self.request("step", action=6, **coords)["error"], "INVALID_COORDINATES")
        for action in (True, "1", 1.0, -1, 8):
            self.assertEqual(self.request("step", action=action)["error"], "INVALID_REQUEST")
        self.assertEqual(self.request("step", action=1, x=3, y=5)["error"], "UNEXPECTED_COORDINATES")
        self.assertTrue(self.request("step", action=6, x=3, y=51)["ok"])
        self.assertEqual(self.arcade.calls[-1], (6, {"x": 3, "y": 51}))

    def test_action_resolution_uses_sdk_from_id_api(self):
        self.start(2)
        self.bridge.action_type = SimpleNamespace(from_id=FakeAction.from_id)
        self.assertTrue(self.request("step", action=1)["ok"])
        self.assertEqual(self.arcade.calls[-1], (1, {}))

    def test_terminal_nonreset_rejected_but_explicit_reset_permitted(self):
        self.start(4)
        self.arcade.next_frame = frame(state="GAME_OVER")
        self.assertTrue(self.request("step", action=1)["ok"])
        self.assertEqual(self.request("step", action=1)["error"], "TERMINAL_STATE")
        self.assertTrue(self.request("step", action=0)["ok"])

    def test_failure_consumes_attempt_closes_and_never_retries_or_leaks(self):
        self.start()
        self.arcade.error = RuntimeError("PRIVATE_API_KEY=DO_NOT_LEAK")
        result = self.request("step", action=1)
        self.assertEqual(result["error"], "SDK_FAILURE")
        self.assertNotIn("DO_NOT_LEAK", json.dumps(result))
        self.assertFalse(self.bridge.active)
        self.assertEqual(self.receipt()["dispatches"], 2)
        self.assertEqual(self.receipt()["status"], "FAILED")
        self.assertEqual(self.arcade.closed, ["local-card"])
        self.assertEqual(self.request("step", action=1)["error"], "SESSION_FAILED")
        self.assertEqual(len(self.arcade.calls), 2)

    def test_make_failure_counts_reset_attempt_and_finalizes_card(self):
        self.arcade.make_error = RuntimeError("private")
        result = self.request("start", gameID="ls20-9607627b", budget=3)
        self.assertFalse(result["ok"])
        self.assertEqual(self.receipt()["dispatches"], 1)
        self.assertTrue(self.receipt()["scorecardClosed"])

    def test_invalid_observation_fails_closed(self):
        self.start()
        self.arcade.next_frame = frame(frames=[[[16]]])
        result = self.request("step", action=1)
        self.assertEqual(result["error"], "INVALID_OBSERVATION")
        self.assertFalse(self.bridge.active)
        self.assertEqual(self.receipt()["dispatches"], 2)

    def test_deadline_bypasses_sdk_exception_catch_and_fails_closed(self):
        self.start()
        self.arcade.error = bridge_module.Deadline()
        self.assertEqual(self.request("step", action=1)["error"], "REQUEST_TIMEOUT")
        self.assertFalse(self.bridge.active)
        self.assertEqual(self.receipt()["status"], "FAILED")

    def test_close_persists_local_scorecard_and_is_idempotent(self):
        self.start()
        self.assertTrue(self.request("close")["ok"])
        self.assertTrue(self.request("close")["ok"])
        self.assertEqual(self.arcade.closed, ["local-card"])
        self.assertEqual(self.receipt()["status"], "CLOSED")
        self.assertEqual(self.receipt()["localScorecard"]["total_actions"], 1)

    def test_close_failure_is_never_success(self):
        self.start()
        self.arcade.close_error = RuntimeError("private")
        self.assertEqual(self.request("close")["error"], "SESSION_FAILED")
        self.assertEqual(self.receipt()["status"], "FAILED")

    def test_eof_finalizes_card_without_unsolicited_response(self):
        source = io.BytesIO(b'{"id":"s","command":"start","gameID":"ls20-9607627b","budget":2}\n')
        output = io.StringIO()
        self.assertEqual(bridge_module.serve(self.bridge, source, output), 0)
        self.assertEqual(len(output.getvalue().splitlines()), 1)
        self.assertEqual(self.receipt()["closeReason"], "INPUT_ENDED")
        self.assertTrue(self.receipt()["scorecardClosed"])

    def test_malformed_json_schema_and_line_bound(self):
        source = io.BytesIO(b'[]\n{broken}\n' + b'x' * (bridge_module.MAX_LINE + 1) + b'\n')
        output = io.StringIO()
        bridge_module.serve(self.bridge, source, output)
        responses = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([r["error"] for r in responses], ["INVALID_REQUEST", "INVALID_JSON", "REQUEST_TOO_LARGE"])
        self.assertEqual(self.arcade.calls, [])

    def test_incidental_sdk_print_is_not_protocol_stdout(self):
        self.start()
        self.arcade.noisy = True
        stdout = io.StringIO()
        with redirect_stdout(stdout), patch("sys.stderr", new=io.StringIO()) as stderr:
            self.assertTrue(self.request("step", action=1)["ok"])
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("incidental", stderr.getvalue())

    def test_credentials_removed_before_sdk_load(self):
        values = {"ARC_API_KEY": "private", "OPENAI_API_KEY": "private", "CUSTOM_AUTH_TOKEN": "private", "AWS_SECRET_ACCESS_KEY": "private", "AWS_ACCESS_KEY_ID": "private", "AUTHORIZATION": "private", "UNRECOGNIZED_PROVIDER_LOGIN": "private", "OPERATION_MODE": "competition", "PYTHONPATH": "/unsafe"}
        with patch.dict(os.environ, values, clear=True):
            bridge_module.prepare_offline_environment(self.root)
            self.assertFalse(any(key in os.environ for key in values if key not in {"OPERATION_MODE"}))
            self.assertEqual(os.environ["OPERATION_MODE"], "offline")
            self.assertEqual(os.environ["PYTHON_DOTENV_DISABLED"], "1")

    def test_sdk_loader_disables_dotenv_and_blocks_http_and_socket_egress(self):
        dotenv = ModuleType("dotenv")
        dotenv.main = ModuleType("dotenv.main")
        forbidden_loader = lambda *_a, **_k: self.fail("dotenv loader executed")
        dotenv.load_dotenv = forbidden_loader
        dotenv.main.load_dotenv = forbidden_loader
        requests = ModuleType("requests")
        requests.sessions = SimpleNamespace(Session=type("Session", (), {"request": forbidden_loader}))
        arc = ModuleType("arc_agi")
        mode = SimpleNamespace(OFFLINE=object())

        def construct(**kwargs):
            self.assertFalse(dotenv.load_dotenv())
            self.assertFalse(dotenv.main.load_dotenv())
            self.assertIs(kwargs["operation_mode"], mode.OFFLINE)
            return SimpleNamespace(operation_mode=mode.OFFLINE, arc_api_key="")

        arc.Arcade, arc.LocalEnvironmentWrapper, arc.OperationMode = construct, FakeWrapper, mode
        engine = ModuleType("arcengine")
        engine.GameAction = FakeAction
        hooks = []
        modules = {"dotenv": dotenv, "dotenv.main": dotenv.main, "requests": requests, "arc_agi": arc, "arcengine": engine}
        with patch.dict("sys.modules", modules), patch("sys.addaudithook", hooks.append), patch.object(bridge_module.importlib.metadata, "version", side_effect=lambda key: {"arc-agi": "0.9.8", "arcengine": "0.9.3"}[key]):
            sdk = bridge_module.load_sdk(self.environments, self.root)
        self.assertEqual(len(hooks), 1)
        hooks[0]("socket.bind", ())  # Local-only urllib3 IPv6 probe.
        for event in ("socket.connect", "socket.sendto", "socket.getaddrinfo"):
            with self.assertRaisesRegex(bridge_module.BridgeError, "NETWORK_BLOCKED"):
                hooks[0](event, ())
        with self.assertRaisesRegex(bridge_module.BridgeError, "NETWORK_BLOCKED"):
            requests.sessions.Session().request("GET", "https://invalid.example")
        self.assertEqual(len(sdk[-1]), 4)


if __name__ == "__main__":
    unittest.main()
