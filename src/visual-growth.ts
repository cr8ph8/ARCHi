import type { GrowthStageName } from "./model";

export type GrowthVisualTier =
  | "hatchling"
  | "young-foundation"
  | "adolescent-branch"
  | "mature-canopy"
  | "advanced-radiance";

export interface GrowthVisualProfile {
  readonly tier: GrowthVisualTier;
  readonly silhouette: "round-sprout" | "rising-leaf" | "branching-crown" | "broad-canopy" | "radiant-crest";
  readonly motion:
    | "whole-body-breath"
    | "coordinated-leaf-sway"
    | "counterphase-sway"
    | "grounded-breath"
    | "quiet-current";
  readonly aura: "single-bloom" | "double-orbit" | "threaded-orbit" | "layered-orbit" | "woven-orbit";
  readonly geometry: {
    readonly earAnchorX: number;
    readonly earAnchorY: number;
    readonly earTipY: number;
    readonly earWidth: number;
    readonly earRotation: number;
    readonly headY: number;
    readonly headRadiusX: number;
    readonly headRadiusY: number;
    readonly bodyY: number;
    readonly bodyRadiusX: number;
    readonly bodyRadiusY: number;
    readonly armX: number;
    readonly armY: number;
    readonly armRadiusX: number;
    readonly armRadiusY: number;
    readonly armRotation: number;
    readonly footX: number;
    readonly footY: number;
    readonly footRadiusX: number;
    readonly footRadiusY: number;
    readonly eyeX: number;
  };
  readonly movement: {
    readonly bobRate: number;
    readonly habitatLift: number;
    readonly fieldLift: number;
    readonly earSway: number;
    readonly earSwayRate: number;
    readonly opposingEarPhase: number;
    readonly armSway: number;
    readonly idleLean: number;
    readonly travelLean: number;
    readonly corePulse: number;
  };
  readonly auraGeometry: {
    readonly radius: number;
    readonly baseStrength: number;
    readonly groundRadiusX: number;
    readonly groundRadiusY: number;
    readonly outerGroundRing: boolean;
    readonly orbitRadiusX: number;
    readonly orbitRadiusY: number;
    readonly orbitMotes: number;
    readonly speckCount: number;
  };
  readonly corePearl: typeof CORE_PEARL_VISUAL;
}

export const CORE_PEARL_VISUAL = Object.freeze({
  x: 0,
  y: 29,
  innerRadius: 12,
  glowRadius: 33,
});

const HATCHLING_VISUAL: GrowthVisualProfile = Object.freeze({
  tier: "hatchling",
  silhouette: "round-sprout",
  motion: "whole-body-breath",
  aura: "single-bloom",
  geometry: Object.freeze({
    earAnchorX: 25,
    earAnchorY: -54,
    earTipY: -40,
    earWidth: 25,
    earRotation: 0.42,
    headY: -20,
    headRadiusX: 56,
    headRadiusY: 48,
    bodyY: 29,
    bodyRadiusX: 40,
    bodyRadiusY: 45,
    armX: 40,
    armY: 29,
    armRadiusX: 10,
    armRadiusY: 22,
    armRotation: 0.24,
    footX: 18,
    footY: 69,
    footRadiusX: 16,
    footRadiusY: 10,
    eyeX: 19,
  }),
  movement: Object.freeze({
    bobRate: 0.86,
    habitatLift: 0.68,
    fieldLift: 1.8,
    earSway: 0.018,
    earSwayRate: 0.84,
    opposingEarPhase: 0,
    armSway: 0.018,
    idleLean: 0,
    travelLean: 0,
    corePulse: 0.045,
  }),
  auraGeometry: Object.freeze({
    radius: 104,
    baseStrength: 0.13,
    groundRadiusX: 58,
    groundRadiusY: 15,
    outerGroundRing: false,
    orbitRadiusX: 0,
    orbitRadiusY: 0,
    orbitMotes: 0,
    speckCount: 14,
  }),
  corePearl: CORE_PEARL_VISUAL,
});

const YOUNG_VISUAL: GrowthVisualProfile = Object.freeze({
  tier: "young-foundation",
  silhouette: "rising-leaf",
  motion: "coordinated-leaf-sway",
  aura: "double-orbit",
  geometry: Object.freeze({
    earAnchorX: 28,
    earAnchorY: -64,
    earTipY: -56,
    earWidth: 30,
    earRotation: 0.36,
    headY: -28,
    headRadiusX: 55,
    headRadiusY: 47,
    bodyY: 27,
    bodyRadiusX: 45,
    bodyRadiusY: 57,
    armX: 47,
    armY: 25,
    armRadiusX: 13,
    armRadiusY: 31,
    armRotation: 0.32,
    footX: 22,
    footY: 76,
    footRadiusX: 18,
    footRadiusY: 12,
    eyeX: 20,
  }),
  movement: Object.freeze({
    bobRate: 1,
    habitatLift: 1,
    fieldLift: 2.5,
    earSway: 0.038,
    earSwayRate: 1.04,
    opposingEarPhase: 0.72,
    armSway: 0.03,
    idleLean: 0.012,
    travelLean: 0.055,
    corePulse: 0.06,
  }),
  auraGeometry: Object.freeze({
    radius: 124,
    baseStrength: 0.17,
    groundRadiusX: 68,
    groundRadiusY: 18,
    outerGroundRing: true,
    orbitRadiusX: 78,
    orbitRadiusY: 55,
    orbitMotes: 3,
    speckCount: 24,
  }),
  corePearl: CORE_PEARL_VISUAL,
});

// These are presentation recipes for the Journey's already-admitted stages.
// They do not grant a form, change a saved Journey, or introduce a new Pearl.
const ADOLESCENT_VISUAL: GrowthVisualProfile = Object.freeze({
  tier: "adolescent-branch",
  silhouette: "branching-crown",
  motion: "counterphase-sway",
  aura: "threaded-orbit",
  geometry: Object.freeze({
    earAnchorX: 33, earAnchorY: -69, earTipY: -67, earWidth: 32, earRotation: 0.31,
    headY: -34, headRadiusX: 56, headRadiusY: 47,
    bodyY: 25, bodyRadiusX: 49, bodyRadiusY: 62,
    armX: 52, armY: 23, armRadiusX: 14, armRadiusY: 34, armRotation: 0.37,
    footX: 24, footY: 82, footRadiusX: 19, footRadiusY: 13,
    eyeX: 21,
  }),
  movement: Object.freeze({
    bobRate: 1.1, habitatLift: 1.06, fieldLift: 2.4,
    earSway: 0.046, earSwayRate: 1.1, opposingEarPhase: 1.1,
    armSway: 0.038, idleLean: 0.017, travelLean: 0.065, corePulse: 0.06,
  }),
  auraGeometry: Object.freeze({
    radius: 138, baseStrength: 0.19, groundRadiusX: 75, groundRadiusY: 19,
    outerGroundRing: true, orbitRadiusX: 89, orbitRadiusY: 65,
    orbitMotes: 5, speckCount: 31,
  }),
  corePearl: CORE_PEARL_VISUAL,
});

const MATURE_VISUAL: GrowthVisualProfile = Object.freeze({
  tier: "mature-canopy",
  silhouette: "broad-canopy",
  motion: "grounded-breath",
  aura: "layered-orbit",
  geometry: Object.freeze({
    earAnchorX: 36, earAnchorY: -73, earTipY: -76, earWidth: 35, earRotation: 0.27,
    headY: -37, headRadiusX: 59, headRadiusY: 49,
    bodyY: 23, bodyRadiusX: 54, bodyRadiusY: 70,
    armX: 58, armY: 20, armRadiusX: 16, armRadiusY: 37, armRotation: 0.41,
    footX: 27, footY: 88, footRadiusX: 21, footRadiusY: 14,
    eyeX: 23,
  }),
  movement: Object.freeze({
    bobRate: 0.92, habitatLift: 0.9, fieldLift: 2,
    earSway: 0.033, earSwayRate: 0.86, opposingEarPhase: 1.4,
    armSway: 0.035, idleLean: 0.009, travelLean: 0.058, corePulse: 0.055,
  }),
  auraGeometry: Object.freeze({
    radius: 154, baseStrength: 0.21, groundRadiusX: 83, groundRadiusY: 22,
    outerGroundRing: true, orbitRadiusX: 105, orbitRadiusY: 75,
    orbitMotes: 7, speckCount: 40,
  }),
  corePearl: CORE_PEARL_VISUAL,
});

const ADVANCED_VISUAL: GrowthVisualProfile = Object.freeze({
  tier: "advanced-radiance",
  silhouette: "radiant-crest",
  motion: "quiet-current",
  aura: "woven-orbit",
  geometry: Object.freeze({
    earAnchorX: 40, earAnchorY: -78, earTipY: -87, earWidth: 39, earRotation: 0.22,
    headY: -40, headRadiusX: 61, headRadiusY: 51,
    bodyY: 21, bodyRadiusX: 60, bodyRadiusY: 77,
    armX: 64, armY: 16, armRadiusX: 18, armRadiusY: 40, armRotation: 0.45,
    footX: 30, footY: 95, footRadiusX: 23, footRadiusY: 15,
    eyeX: 24,
  }),
  movement: Object.freeze({
    bobRate: 0.82, habitatLift: 0.75, fieldLift: 1.7,
    earSway: 0.04, earSwayRate: 0.74, opposingEarPhase: 1.8,
    armSway: 0.04, idleLean: 0.008, travelLean: 0.05, corePulse: 0.05,
  }),
  auraGeometry: Object.freeze({
    radius: 176, baseStrength: 0.24, groundRadiusX: 93, groundRadiusY: 24,
    outerGroundRing: true, orbitRadiusX: 121, orbitRadiusY: 84,
    orbitMotes: 9, speckCount: 52,
  }),
  corePearl: CORE_PEARL_VISUAL,
});

export function visualProfileForStage(stageName: GrowthStageName): GrowthVisualProfile {
  switch (stageName) {
    case "Hatchling":
      return HATCHLING_VISUAL;
    case "Young":
      return YOUNG_VISUAL;
    case "Adolescent":
      return ADOLESCENT_VISUAL;
    case "Mature":
      return MATURE_VISUAL;
    case "Advanced":
      return ADVANCED_VISUAL;
  }
  const unhandledStage: never = stageName;
  throw new Error(`Unhandled ARCHi growth stage: ${String(unhandledStage)}`);
}
