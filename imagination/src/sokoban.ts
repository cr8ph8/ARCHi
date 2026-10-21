import { isProxy } from "node:util/types";

/** A bounded, synthetic board. No state outside this value is read or written. */
export interface SokobanState {
  readonly rows: readonly string[];
}

export type SokobanAction = "UP" | "DOWN" | "LEFT" | "RIGHT";

export interface SokobanStep {
  readonly state: SokobanState;
  readonly legal: boolean;
  readonly solved: boolean;
  /** Only non-goal boxes in wall corners are detected; false is not a solvability proof. */
  readonly deadlocked: boolean;
  readonly reason: string | null;
}

function invalid(message: string): never {
  throw new TypeError(`Invalid Sokoban state: ${message}`);
}

function canonicalState(rows: readonly string[]): SokobanState {
  return Object.freeze({ rows: Object.freeze([...rows]) });
}

/**
 * Parse data without reading accessors. Reject proxies, custom prototypes, sparse
 * arrays, symbols and undeclared own properties before inspecting their values.
 * Rows use ordinary Sokoban notation: # wall, . goal, $ box, @ player,
 * * box on goal, + player on goal, and a space for empty floor.
 */
export function parseSokoban(input: unknown): SokobanState {
  if (input === null || typeof input !== "object" || isProxy(input)) {
    invalid("expected a plain object");
  }
  const prototype = Object.getPrototypeOf(input);
  if (prototype !== Object.prototype && prototype !== null) {
    invalid("expected a plain object");
  }
  const keys = Reflect.ownKeys(input);
  if (keys.length !== 1 || keys[0] !== "rows") {
    invalid("only the rows property is allowed");
  }
  const rowsDescriptor = Object.getOwnPropertyDescriptor(input, "rows");
  if (!rowsDescriptor || !Object.hasOwn(rowsDescriptor, "value")) {
    invalid("rows must be a data property");
  }
  const candidate: unknown = rowsDescriptor.value;
  if (!Array.isArray(candidate) || isProxy(candidate) || Object.getPrototypeOf(candidate) !== Array.prototype) {
    invalid("rows must be an ordinary dense array");
  }

  // An array's length is a data descriptor. Read it through the descriptor so
  // no user-supplied property getter participates in parsing.
  const lengthDescriptor = Object.getOwnPropertyDescriptor(candidate, "length");
  const height: unknown = lengthDescriptor?.value;
  if (typeof height !== "number" || !Number.isInteger(height) || height < 3 || height > 12) {
    invalid("expected 3 to 12 rows");
  }
  const rowKeys = Reflect.ownKeys(candidate);
  if (rowKeys.length !== height + 1 || rowKeys.some((key) => typeof key !== "string")) {
    invalid("rows must have only dense indices and length");
  }
  const allowedKeys = new Set(["length", ...Array.from({ length: height }, (_, index) => String(index))]);
  if (rowKeys.some((key) => !allowedKeys.has(key as string))) {
    invalid("rows must have only dense indices and length");
  }

  const rows: string[] = [];
  let width = 0;
  let players = 0;
  let boxes = 0;
  let goals = 0;
  for (let rowIndex = 0; rowIndex < height; rowIndex += 1) {
    const descriptor = Object.getOwnPropertyDescriptor(candidate, String(rowIndex));
    if (!descriptor || !Object.hasOwn(descriptor, "value") || typeof descriptor.value !== "string") {
      invalid("every row must be an own string data property");
    }
    const row: string = descriptor.value;
    if (rowIndex === 0) width = row.length;
    if (width < 3 || width > 12 || row.length !== width) {
      invalid("expected rectangular rows with 3 to 12 columns");
    }
    if (!/^[# .$@*+]+$/.test(row)) {
      invalid("unrecognized board character");
    }
    for (let column = 0; column < width; column += 1) {
      const cell = row[column];
      if ((rowIndex === 0 || rowIndex === height - 1 || column === 0 || column === width - 1) && cell !== "#") {
        invalid("the boundary must contain only walls");
      }
      if (cell === "@" || cell === "+") players += 1;
      if (cell === "$" || cell === "*") boxes += 1;
      if (cell === "." || cell === "*" || cell === "+") goals += 1;
    }
    rows.push(row);
  }
  if (players !== 1) invalid("expected exactly one player");
  if (boxes < 1 || boxes > 4) invalid("expected 1 to 4 boxes");
  if (goals !== boxes) invalid("the box and goal counts must match");
  return canonicalState(rows);
}

function solvedUnchecked(state: SokobanState): boolean {
  return state.rows.every((row) => !row.includes("$"));
}

function deadlockedUnchecked(state: SokobanState): boolean {
  for (let row = 1; row < state.rows.length - 1; row += 1) {
    const cells = state.rows[row]!;
    for (let column = 1; column < cells.length - 1; column += 1) {
      if (cells[column] !== "$") continue;
      const verticalWall = state.rows[row - 1]?.[column] === "#" || state.rows[row + 1]?.[column] === "#";
      const horizontalWall = cells[column - 1] === "#" || cells[column + 1] === "#";
      if (verticalWall && horizontalWall) return true;
    }
  }
  return false;
}

/** True iff every box occupies a goal on a valid board, including initial boards. */
export function isSolved(state: SokobanState): boolean {
  return solvedUnchecked(parseSokoban(state));
}

/**
 * Detect only a box outside a goal with a wall on one vertical and one horizontal
 * side. This deliberately does not detect wall traps, box groups or all deadlocks.
 */
export function hasStaticDeadlock(state: SokobanState): boolean {
  return deadlockedUnchecked(parseSokoban(state));
}

function result(state: SokobanState, legal: boolean, reason: string | null): SokobanStep {
  return Object.freeze({
    state,
    legal,
    solved: solvedUnchecked(state),
    deadlocked: deadlockedUnchecked(state),
    reason,
  });
}

function offset(action: SokobanAction): readonly [number, number] {
  switch (action) {
    case "UP": return [-1, 0];
    case "DOWN": return [1, 0];
    case "LEFT": return [0, -1];
    case "RIGHT": return [0, 1];
    default: throw new TypeError("Invalid Sokoban action: expected UP, DOWN, LEFT or RIGHT");
  }
}

/**
 * Execute one deterministic move against a validated copy. Blocked moves leave
 * the board value unchanged and are illegal; solved boards are terminal.
 * A detected corner deadlock is reported but does not disable otherwise legal
 * movement. No pull, multi-box push, reset, rendering or runtime commit is provided.
 */
export function stepSokoban(state: SokobanState, action: SokobanAction): SokobanStep {
  const current = parseSokoban(state);
  const [rowOffset, columnOffset] = offset(action);
  if (solvedUnchecked(current)) return result(current, false, "already_solved");

  let playerRow = 0;
  let playerColumn = 0;
  for (let row = 1; row < current.rows.length - 1; row += 1) {
    const column = current.rows[row]!.search(/[@+]/);
    if (column !== -1) {
      playerRow = row;
      playerColumn = column;
      break;
    }
  }
  const nextRow = playerRow + rowOffset;
  const nextColumn = playerColumn + columnOffset;
  const nextCell = current.rows[nextRow]?.[nextColumn];
  if (nextCell === undefined || nextCell === "#") return result(current, false, "blocked_by_wall");

  const pushing = nextCell === "$" || nextCell === "*";
  const boxRow = nextRow + rowOffset;
  const boxColumn = nextColumn + columnOffset;
  const boxDestination = current.rows[boxRow]?.[boxColumn];
  if (pushing && (boxDestination === undefined || boxDestination === "#")) {
    return result(current, false, "blocked_by_wall");
  }
  if (pushing && (boxDestination === "$" || boxDestination === "*")) {
    return result(current, false, "blocked_by_box");
  }

  const cells = current.rows.map((row) => [...row]);
  cells[playerRow]![playerColumn] = current.rows[playerRow]![playerColumn] === "+" ? "." : " ";
  cells[nextRow]![nextColumn] = nextCell === "." || nextCell === "*" ? "+" : "@";
  if (pushing) cells[boxRow]![boxColumn] = boxDestination === "." ? "*" : "$";
  return result(canonicalState(cells.map((row) => row.join(""))), true, null);
}
