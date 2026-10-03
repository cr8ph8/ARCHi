/** A visit-only portrait choice. It grants no form, memory, or combat state. */
export const LIMINAL_LIGHT_STYLE = "liminal-light-flow/v12";
export const PORTRAIT_CHOICES = ["presence", "seed", "ball", "beast"] as const;
export type PortraitChoice = (typeof PORTRAIT_CHOICES)[number];
export type LiminalPortraitChoice = Exclude<PortraitChoice, "presence">;

export function isPortraitChoice(value: unknown): value is PortraitChoice {
  return typeof value === "string" && (PORTRAIT_CHOICES as readonly string[]).includes(value);
}

/** Native ownership always wins, including while its own image is loading. */
export function visibleLiminalPortrait(choice: PortraitChoice, nativeOwned: boolean, sourceAvailable = true): LiminalPortraitChoice | null {
  return nativeOwned || !sourceAvailable || choice === "presence" ? null : choice;
}

export function liminalPortraitLight(seconds: number, quiet: boolean): { scale: number; haloAlpha: number } {
  const phase = quiet || !Number.isFinite(seconds) ? 0 : Math.sin(seconds * Math.PI / 2);
  return { scale: quiet ? 1 : 1 + phase * 0.006, haloAlpha: quiet ? 0.12 : 0.145 + phase * 0.025 };
}

export function portraitLabel(choice: LiminalPortraitChoice): string {
  return `Liminal · ${choice === "seed" ? "Seed" : choice === "ball" ? "Ball" : "Beast"}`;
}
