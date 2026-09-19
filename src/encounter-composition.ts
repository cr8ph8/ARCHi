export const ENCOUNTER_COMPOSITION_VERSION = "encounter-composition-v1" as const;

export type EncounterViewportClass = "wide" | "standard" | "compact" | "portrait" | "short";
export type EncounterTeamId = "one" | "two";

export interface EncounterPoint {
  readonly x: number;
  readonly y: number;
}

export interface HabitatEncounterComposition {
  readonly schemaVersion: typeof ENCOUNTER_COMPOSITION_VERSION;
  readonly kind: "habitat";
  readonly viewportClass: EncounterViewportClass;
  readonly anchor: EncounterPoint;
  readonly scaleMultiplier: number;
}

export interface ReserveEncounterPlacement extends EncounterPoint {
  readonly slot: number;
  readonly drawScale: number;
  readonly opacity: number;
}

export interface BattleTeamEncounterComposition {
  readonly id: EncounterTeamId;
  readonly active: EncounterPoint & {
    readonly drawScale: number;
    readonly facing: -1 | 1;
  };
  readonly reserves: readonly ReserveEncounterPlacement[];
  readonly ground: EncounterPoint & {
    readonly radiusX: number;
    readonly radiusY: number;
  };
}

export interface BattleEncounterComposition {
  readonly schemaVersion: typeof ENCOUNTER_COMPOSITION_VERSION;
  readonly kind: "battle";
  readonly viewportClass: EncounterViewportClass;
  readonly fieldCenter: EncounterPoint;
  readonly teams: Readonly<Record<EncounterTeamId, BattleTeamEncounterComposition>>;
}

interface CompositionPreset {
  readonly habitatX: number;
  readonly habitatY: number;
  readonly habitatScale: number;
  readonly battleActiveX: number;
  readonly battleY: number;
  readonly activeScale: number;
  readonly reserveScale: number;
  readonly reserveOffsetX: number;
  readonly reserveOffsetY: number;
  readonly groundOffsetY: number;
  readonly groundRadiusX: number;
  readonly groundRadiusY: number;
}

const PRESETS: Readonly<Record<EncounterViewportClass, CompositionPreset>> = Object.freeze({
  wide: Object.freeze({
    habitatX: 0.72,
    habitatY: 0.46,
    habitatScale: 1.12,
    battleActiveX: 0.31,
    battleY: 0.48,
    activeScale: 1.04,
    reserveScale: 0.5,
    reserveOffsetX: 98,
    reserveOffsetY: 72,
    groundOffsetY: 58,
    groundRadiusX: 86,
    groundRadiusY: 19,
  }),
  standard: Object.freeze({
    habitatX: 0.7,
    habitatY: 0.44,
    habitatScale: 1.1,
    battleActiveX: 0.3,
    battleY: 0.48,
    activeScale: 0.94,
    reserveScale: 0.46,
    reserveOffsetX: 82,
    reserveOffsetY: 64,
    groundOffsetY: 54,
    groundRadiusX: 76,
    groundRadiusY: 17,
  }),
  compact: Object.freeze({
    habitatX: 0.5,
    habitatY: 0.36,
    habitatScale: 1.08,
    battleActiveX: 0.29,
    battleY: 0.48,
    activeScale: 0.84,
    reserveScale: 0.44,
    reserveOffsetX: 66,
    reserveOffsetY: 58,
    groundOffsetY: 50,
    groundRadiusX: 66,
    groundRadiusY: 15,
  }),
  portrait: Object.freeze({
    habitatX: 0.5,
    habitatY: 0.36,
    habitatScale: 1.1,
    battleActiveX: 0.29,
    battleY: 0.48,
    activeScale: 0.77,
    reserveScale: 0.46,
    reserveOffsetX: 48,
    // Keep the complete reserve glow above the 390×500 command dock.
    reserveOffsetY: 32,
    groundOffsetY: 48,
    groundRadiusX: 58,
    groundRadiusY: 14,
  }),
  short: Object.freeze({
    habitatX: 0.71,
    habitatY: 0.44,
    habitatScale: 1.05,
    battleActiveX: 0.28,
    battleY: 0.48,
    activeScale: 0.66,
    reserveScale: 0.34,
    reserveOffsetX: 58,
    reserveOffsetY: 42,
    groundOffsetY: 40,
    groundRadiusX: 56,
    groundRadiusY: 12,
  }),
});

function checkedDimension(value: number, label: string): number {
  if (!Number.isFinite(value) || value <= 0) throw new Error(`${label} must be a positive finite number.`);
  return value;
}

function checkedRosterSize(value: number, teamId: EncounterTeamId): number {
  if (!Number.isInteger(value) || value < 1 || value > 3) {
    throw new Error(`Team ${teamId} roster size must be an integer from 1 to 3.`);
  }
  return value;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}

export function encounterViewportClass(width: number, height: number): EncounterViewportClass {
  checkedDimension(width, "Viewport width");
  checkedDimension(height, "Viewport height");
  if (height <= 520 && width > height) return "short";
  if (width <= 520) return "portrait";
  if (width <= 800) return "compact";
  if (width >= 1180 && height >= 680) return "wide";
  return "standard";
}

export function habitatEncounterComposition(width: number, height: number): HabitatEncounterComposition {
  const safeWidth = checkedDimension(width, "Viewport width");
  const safeHeight = checkedDimension(height, "Viewport height");
  const viewportClass = encounterViewportClass(safeWidth, safeHeight);
  const preset = PRESETS[viewportClass];
  return Object.freeze({
    schemaVersion: ENCOUNTER_COMPOSITION_VERSION,
    kind: "habitat",
    viewportClass,
    anchor: Object.freeze({ x: safeWidth * preset.habitatX, y: safeHeight * preset.habitatY }),
    scaleMultiplier: preset.habitatScale,
  });
}

function teamComposition(
  id: EncounterTeamId,
  rosterSize: number,
  width: number,
  height: number,
  preset: CompositionPreset,
): BattleTeamEncounterComposition {
  const direction = id === "one" ? -1 : 1;
  const activeX = width * (id === "one" ? preset.battleActiveX : 1 - preset.battleActiveX);
  const activeY = height * preset.battleY;
  const reserves = Array.from({ length: rosterSize - 1 }, (_, index) => {
    const verticalDirection = index === 0 ? 1 : -0.72;
    return Object.freeze({
      slot: index + 1,
      x: clamp(
        activeX + direction * (preset.reserveOffsetX + index * preset.reserveOffsetX * 0.16),
        preset.groundRadiusX * 0.55,
        width - preset.groundRadiusX * 0.55,
      ),
      y: clamp(
        activeY + preset.reserveOffsetY * verticalDirection,
        preset.groundOffsetY * 1.35,
        height - preset.groundOffsetY * 1.15,
      ),
      drawScale: preset.reserveScale * (index === 0 ? 1 : 0.92),
      opacity: index === 0 ? 0.72 : 0.58,
    });
  });
  return Object.freeze({
    id,
    active: Object.freeze({
      x: activeX,
      y: activeY,
      drawScale: preset.activeScale,
      facing: (id === "one" ? 1 : -1) as -1 | 1,
    }),
    reserves: Object.freeze(reserves),
    ground: Object.freeze({
      x: activeX,
      y: activeY + preset.groundOffsetY,
      radiusX: preset.groundRadiusX,
      radiusY: preset.groundRadiusY,
    }),
  });
}

export function battleEncounterComposition(
  width: number,
  height: number,
  rosterSizes: Readonly<Record<EncounterTeamId, number>>,
): BattleEncounterComposition {
  const safeWidth = checkedDimension(width, "Viewport width");
  const safeHeight = checkedDimension(height, "Viewport height");
  const oneSize = checkedRosterSize(rosterSizes.one, "one");
  const twoSize = checkedRosterSize(rosterSizes.two, "two");
  const viewportClass = encounterViewportClass(safeWidth, safeHeight);
  const preset = PRESETS[viewportClass];
  return Object.freeze({
    schemaVersion: ENCOUNTER_COMPOSITION_VERSION,
    kind: "battle",
    viewportClass,
    fieldCenter: Object.freeze({ x: safeWidth / 2, y: safeHeight * preset.battleY }),
    teams: Object.freeze({
      one: teamComposition("one", oneSize, safeWidth, safeHeight, preset),
      two: teamComposition("two", twoSize, safeWidth, safeHeight, preset),
    }),
  });
}
