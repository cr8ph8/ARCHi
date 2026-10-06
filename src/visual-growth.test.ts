import { describe, expect, it } from "vitest";
import type { GrowthStageName } from "./model";
import { protoVisualRigForView } from "./proto-visual-rig";
import { CORE_PEARL_VISUAL, visualProfileForStage } from "./visual-growth";

const STAGES = ["Hatchling", "Young", "Adolescent", "Mature", "Advanced"] as const satisfies readonly GrowthStageName[];

describe("ARCHi Field visual growth", () => {
  it("maps every admitted Journey stage to its own frozen presentation recipe", () => {
    const profiles = STAGES.map(visualProfileForStage);
    expect(profiles.map((profile) => profile.tier)).toEqual([
      "hatchling", "young-foundation", "adolescent-branch", "mature-canopy", "advanced-radiance",
    ]);
    expect(new Set(profiles).size).toBe(STAGES.length);
    expect(new Set(profiles.map((profile) => profile.silhouette)).size).toBe(STAGES.length);
    expect(new Set(profiles.map((profile) => profile.motion)).size).toBe(STAGES.length);
    expect(new Set(profiles.map((profile) => profile.aura)).size).toBe(STAGES.length);
    for (const profile of profiles) {
      expect(Object.isFrozen(profile)).toBe(true);
      expect(Object.isFrozen(profile.geometry)).toBe(true);
      expect(Object.isFrozen(profile.movement)).toBe(true);
      expect(Object.isFrozen(profile.auraGeometry)).toBe(true);
    }
  });

  it("changes actual rig proportions at each step without moving the Core Pearl", () => {
    const rigs = STAGES.map((stage) => protoVisualRigForView("front", visualProfileForStage(stage)));
    const totalHeight = (index: number): number => {
      const profile = visualProfileForStage(STAGES[index]);
      const earTop = profile.geometry.earAnchorY + profile.geometry.earTipY;
      const footBottom = profile.geometry.footY + profile.geometry.footRadiusY;
      return footBottom - earTop;
    };
    expect(STAGES.map((_, index) => totalHeight(index))).toEqual([173, 208, 231, 251, 275]);
    expect(rigs.map((rig) => rig.body.radiusY)).toEqual([45, 57, 62, 70, 77]);
    expect(rigs.map((rig) => rig.head.radiusX)).toEqual([56, 55, 56, 59, 61]);
    expect(rigs.map((rig) => rig.appendages.find((appendage) => appendage.id === "arm-right")?.x))
      .toEqual([40, 47, 52, 58, 64]);
    for (const rig of rigs) {
      expect(rig.core.visual).toBe(CORE_PEARL_VISUAL);
      expect(rig.core.visual).toEqual({ x: 0, y: 29, innerRadius: 12, glowRadius: 33 });
    }
  });

  it("adds bounded stage-specific orbit and body detail while keeping Hatchling quiet", () => {
    const profiles = STAGES.map(visualProfileForStage);
    expect(profiles.map((profile) => profile.auraGeometry.outerGroundRing))
      .toEqual([false, true, true, true, true]);
    expect(profiles.map((profile) => profile.auraGeometry.orbitMotes)).toEqual([0, 3, 5, 7, 9]);
    expect(profiles.map((profile) => profile.auraGeometry.speckCount)).toEqual([14, 24, 31, 40, 52]);
    expect(profiles.map((profile) => profile.auraGeometry.radius)).toEqual([104, 124, 138, 154, 176]);
    expect(profiles.map((profile) => profile.movement.opposingEarPhase))
      .toEqual([0, 0.72, 1.1, 1.4, 1.8]);
    for (const profile of profiles) {
      expect(profile.auraGeometry.orbitMotes).toBeLessThanOrEqual(9);
      expect(profile.auraGeometry.speckCount).toBeLessThanOrEqual(52);
    }
  });

  it("projects the same staged recipe into side and rear views", () => {
    for (const stage of STAGES) {
      const profile = visualProfileForStage(stage);
      const side = protoVisualRigForView("side", profile);
      const back = protoVisualRigForView("back", profile);
      expect(side.body.radiusY).toBe(profile.geometry.bodyRadiusY);
      expect(back.body.radiusY).toBe(profile.geometry.bodyRadiusY);
      expect(side.core.visual).toBe(CORE_PEARL_VISUAL);
      expect(back.core.visual).toBe(CORE_PEARL_VISUAL);
      expect(back.face.visible).toBe(false);
    }
  });
});
