import assert from "node:assert/strict";
import test from "node:test";
import {
  hasStaticDeadlock,
  isSolved,
  parseSokoban,
  stepSokoban,
  type SokobanAction,
  type SokobanState,
} from "../src/sokoban.ts";

const simpleRows = [
  "#######",
  "#     #",
  "# @$. #",
  "#     #",
  "#######",
];

test("parsing clones and freezes a valid board, including a null-prototype record", () => {
  const input = { rows: [...simpleRows] };
  const parsed = parseSokoban(input);
  assert.deepEqual(parsed, input);
  assert.notEqual(parsed, input);
  assert.notEqual(parsed.rows, input.rows);
  assert.ok(Object.isFrozen(parsed));
  assert.ok(Object.isFrozen(parsed.rows));
  input.rows[1] = "#######";
  assert.equal(parsed.rows[1], "#     #");
  assert.deepEqual(parseSokoban(parsed), parsed);
  assert.deepEqual(parseSokoban(Object.assign(Object.create(null), { rows: [...simpleRows] })), parsed);
});

test("one push solves the puzzle and solved states are terminal", () => {
  const initial = parseSokoban({ rows: simpleRows });
  assert.equal(isSolved(initial), false);
  const pushed = stepSokoban(initial, "RIGHT");
  assert.equal(pushed.legal, true);
  assert.equal(pushed.solved, true);
  assert.equal(pushed.deadlocked, false);
  assert.equal(pushed.reason, null);
  assert.equal(pushed.state.rows[2], "#  @* #");
  assert.equal(initial.rows[2], "# @$. #");
  assert.ok(Object.isFrozen(pushed));
  const terminal = stepSokoban(pushed.state, "LEFT");
  assert.equal(terminal.legal, false);
  assert.equal(terminal.reason, "already_solved");
  assert.equal(terminal.solved, true);
  assert.deepEqual(terminal.state, pushed.state);
});

test("an initially solved board is recognized without executing a move", () => {
  const state = parseSokoban({ rows: ["####", "#@*#", "####"] });
  assert.equal(isSolved(state), true);
  assert.equal(hasStaticDeadlock(state), false);
  assert.deepEqual(stepSokoban(state, "RIGHT"), {
    state, legal: false, solved: true, deadlocked: false, reason: "already_solved",
  });
});

test("all four directions move one cell on empty floor deterministically", () => {
  const state = parseSokoban({ rows: ["#######", "# $ . #", "#  @  #", "#     #", "#######"] });
  const destinations: Array<[SokobanAction, number, number]> = [
    ["UP", 1, 3], ["DOWN", 3, 3], ["LEFT", 2, 2], ["RIGHT", 2, 4],
  ];
  for (const [action, row, column] of destinations) {
    const first = stepSokoban(state, action);
    const second = stepSokoban(state, action);
    assert.deepEqual(first, second);
    assert.equal(first.legal, true);
    assert.equal(first.state.rows[row]![column], "@");
    assert.equal(first.state.rows[2]![3], " ");
    assert.deepEqual(state.rows, ["#######", "# $ . #", "#  @  #", "#     #", "#######"]);
  }
});

test("walking or pushing into walls is an illegal no-op", () => {
  const state = parseSokoban({ rows: ["#####", "#@$.#", "#####"] });
  for (const action of ["UP", "DOWN", "LEFT"] as const) {
    const blocked = stepSokoban(state, action);
    assert.equal(blocked.legal, false);
    assert.equal(blocked.reason, "blocked_by_wall");
    assert.deepEqual(blocked.state, state);
    assert.equal(blocked.solved, false);
  }
  const wallPush = parseSokoban({ rows: ["######", "# @$##", "#  . #", "######"] });
  const blocked = stepSokoban(wallPush, "RIGHT");
  assert.equal(blocked.legal, false);
  assert.equal(blocked.reason, "blocked_by_wall");
  assert.deepEqual(blocked.state, wallPush);
});

test("a box cannot push another box", () => {
  const state = parseSokoban({ rows: ["######", "# @$$#", "# .. #", "######"] });
  const blocked = stepSokoban(state, "RIGHT");
  assert.equal(blocked.legal, false);
  assert.equal(blocked.reason, "blocked_by_box");
  assert.deepEqual(blocked.state, state);
});

test("moving from a goal restores it and moving a goal box preserves its goal", () => {
  const playerOnGoal = parseSokoban({ rows: ["#######", "# +$* #", "#     #", "#######"] });
  const moved = stepSokoban(playerOnGoal, "DOWN");
  assert.equal(moved.legal, true);
  assert.equal(moved.state.rows[1], "# .$* #");
  assert.equal(moved.state.rows[2], "# @   #");
  assert.deepEqual(parseSokoban(moved.state), moved.state);

  const boxOnGoal = parseSokoban({ rows: ["########", "# @* $.#", "#      #", "########"] });
  const pushed = stepSokoban(boxOnGoal, "RIGHT");
  assert.equal(pushed.legal, true);
  assert.equal(pushed.state.rows[1], "#  +$$.#");
  assert.equal(pushed.solved, false);
  assert.deepEqual(parseSokoban(pushed.state), pushed.state);
});

test("a push into a non-goal wall corner is flagged without rejecting the legal move", () => {
  const state = parseSokoban({ rows: ["#######", "# @ $ #", "#   . #", "#######"] });
  assert.equal(hasStaticDeadlock(state), false);
  const approached = stepSokoban(state, "RIGHT");
  const pushed = stepSokoban(approached.state, "RIGHT");
  assert.equal(pushed.legal, true);
  assert.equal(pushed.deadlocked, true);
  assert.equal(pushed.solved, false);
  assert.equal(pushed.state.rows[1], "#   @$#");
  // Reporting a corner trap does not prevent unrelated legal player movement.
  assert.equal(stepSokoban(pushed.state, "LEFT").legal, true);
});

test("static deadlock detection is deliberately incomplete", () => {
  const wallTrap = parseSokoban({ rows: ["#######", "# $   #", "#  @. #", "#     #", "#######"] });
  // This box cannot leave the top wall to reach its lower goal, but is not in a corner.
  assert.equal(isSolved(wallTrap), false);
  assert.equal(hasStaticDeadlock(wallTrap), false);
  const corner = parseSokoban({ rows: ["#####", "#$@.#", "#   #", "#####"] });
  assert.equal(hasStaticDeadlock(corner), true);
});

test("size, character, boundary and occupancy constraints are enforced", () => {
  const invalidBoards: unknown[] = [
    null, undefined, [], {}, { rows: "board" }, { rows: [] },
    { rows: ["###", "#@*"] },
    { rows: ["##", "@*", "##"] },
    { rows: ["#####", "#@$.#", "####"] },
    { rows: ["#####", "#@x.#", "#####"] },
    { rows: ["#####", "#@$.#", "## ##"] },
    { rows: ["#####", "#@$.#", "# @ #", "#####"] },
    { rows: ["#####", "# $.#", "#####"] },
    { rows: ["#####", "#@ .#", "#####"] },
    { rows: ["#####", "#@$$#", "# . #", "#####"] },
    { rows: ["############", "#@$$$$$....#", "# .        #", "############"] },
    { rows: ["#############", "#@$.        #", "#############"] },
    { rows: ["#####", "#@$.#", ...Array.from({ length: 11 }, () => "#####")] },
  ];
  for (const input of invalidBoards) assert.throws(() => parseSokoban(input), TypeError);
  const largest = { rows: ["############", "#@$.       #", ...Array.from({ length: 9 }, () => "#          #"), "############"] };
  assert.equal(parseSokoban(largest).rows.length, 12);
});

test("state and row arrays reject undeclared own keys and symbols", () => {
  assert.throws(() => parseSokoban({ rows: simpleRows, other: true }), TypeError);
  assert.throws(() => parseSokoban({ rows: simpleRows, [Symbol("secret")]: true }), TypeError);
  for (const key of ["extra", "01", "-1", Symbol("secret")]) {
    const rows = [...simpleRows];
    Object.defineProperty(rows, key, { value: true });
    assert.throws(() => parseSokoban({ rows }), TypeError);
  }
  const sparse: Array<string | undefined> = [...simpleRows];
  delete sparse[1];
  assert.throws(() => parseSokoban({ rows: sparse }), TypeError);
});

test("accessors, proxies and custom prototypes are rejected without executing getters or traps", () => {
  let calls = 0;
  const accessorState = Object.defineProperty({}, "rows", { get() { calls += 1; return simpleRows; } });
  assert.throws(() => parseSokoban(accessorState), TypeError);
  const accessorRows = [...simpleRows];
  Object.defineProperty(accessorRows, "1", { get() { calls += 1; return simpleRows[1]; } });
  assert.throws(() => parseSokoban({ rows: accessorRows }), TypeError);
  const proxyState = new Proxy({ rows: simpleRows }, { getPrototypeOf() { calls += 1; return Object.prototype; } });
  assert.throws(() => parseSokoban(proxyState), TypeError);
  const proxyRows = new Proxy([...simpleRows], { getPrototypeOf() { calls += 1; return Array.prototype; } });
  assert.throws(() => parseSokoban({ rows: proxyRows }), TypeError);
  assert.equal(calls, 0);
  const inherited = Object.create({ rows: simpleRows });
  assert.throws(() => parseSokoban(inherited), TypeError);
  class CustomRows extends Array<string> {}
  assert.throws(() => parseSokoban({ rows: CustomRows.from(simpleRows) }), TypeError);
  class CustomState { rows = simpleRows; }
  assert.throws(() => parseSokoban(new CustomState()), TypeError);
});

test("every public operation validates states and rejects non-enumerated actions", () => {
  const malformed = { rows: simpleRows, unexpected: true } as SokobanState;
  assert.throws(() => isSolved(malformed), TypeError);
  assert.throws(() => hasStaticDeadlock(malformed), TypeError);
  assert.throws(() => stepSokoban(malformed, "UP"), TypeError);
  const valid = parseSokoban({ rows: simpleRows });
  for (const action of ["up", "JUMP", "", null, {}, "toString"]) {
    assert.throws(() => stepSokoban(valid, action as SokobanAction), TypeError);
  }
});
