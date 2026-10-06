import { describe, expect, it } from "vitest";
import { isPortraitChoice, liminalPortraitLight, visibleLiminalPortrait } from "./liminal-portrait";

describe("visit-only Liminal portraits", () => {
  it("lets the native renderer retain ownership for every optional portrait", () => {
    for (const choice of ["presence", "seed", "ball", "beast"] as const) {
      expect(visibleLiminalPortrait(choice, true)).toBeNull();
    }
    expect(visibleLiminalPortrait("presence", false)).toBeNull();
    expect(visibleLiminalPortrait("beast", false)).toBe("beast");
  });
  it("accepts only known presentation endpoints", () => {
    for (const value of [null, {}, "true-form", "../beast", "SEED", ""]) expect(isPortraitChoice(value)).toBe(false);
    for (const value of ["presence", "seed", "ball", "beast"]) expect(isPortraitChoice(value)).toBe(true);
  });
  it("keeps the presence fallback when optional portrait source is unavailable", () => {
    for (const choice of ["seed", "ball", "beast"] as const) {
      expect(visibleLiminalPortrait(choice, false, false)).toBeNull();
      expect(visibleLiminalPortrait(choice, false, true)).toBe(choice);
      expect(visibleLiminalPortrait(choice, true, true)).toBeNull();
      expect(visibleLiminalPortrait(choice, true, false)).toBeNull();
    }
  });
  it("bounds the four-second light cycle and keeps quiet frames stable", () => {
    for (let tick = -400; tick <= 400; tick++) {
      const seconds = tick / 31;
      const light = liminalPortraitLight(seconds, false);
      expect(light.scale).toBeGreaterThanOrEqual(0.994);
      expect(light.scale).toBeLessThanOrEqual(1.006);
      expect(light.haloAlpha).toBeGreaterThanOrEqual(0.12);
      expect(light.haloAlpha).toBeLessThanOrEqual(0.17);
      expect(liminalPortraitLight(seconds + 4, false).scale).toBeCloseTo(light.scale, 12);
      expect(liminalPortraitLight(seconds, true)).toEqual({ scale: 1, haloAlpha: 0.12 });
    }
    expect(liminalPortraitLight(Number.NaN, false).scale).toBe(1);
  });
});
