import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

// Disposable authored data only. This test never discovers or opens a real profile.
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = process.env.PLAYTEST_OUTPUT_DIR || join(tmpdir(), "archi-memory-influence-playtest");
const checks = [];
let server, browser, page;
const check = (name, value) => { assert.ok(value, name); checks.push(name); };
const at = (minute) => new Date(Date.UTC(2026, 0, 1, 0, minute)).toISOString();

try {
  await mkdir(output, { recursive: true });
  server = await createServer({ root, server: { host: "127.0.0.1", port: 0, strictPort: false, hmr: false }, appType: "spa" });
  await server.listen();
  const address = server.httpServer.address();
  assert.ok(address && typeof address !== "string");
  const origin = `http://127.0.0.1:${address.port}`;
  const model = await server.ssrLoadModule("/src/model.ts");
  const rosterOwner = await server.ssrLoadModule("/src/qimon-roster.ts");
  const battleOwner = await server.ssrLoadModule("/src/battle-engine.ts");
  const original = model.createJourney("memory-playtest-synthetic", at(0));
  let roster = rosterOwner.createQiMonRoster(original, at(0));
  let session = model.createPlaySession(original);
  for (const echo of session.echoes.slice(0, 3)) session = model.collectEcho(session, echo.id);
  const journey = model.commitSession(original, session, session.proposals[0], at(1));
  roster = rosterOwner.discoverQiMon(journey, roster, journey.events.at(-1).eventId,
    rosterOwner.revisionForQiMonRoster(roster), model.revisionForJourney(journey), at(2));
  roster = rosterOwner.inviteQiMon(journey, roster, rosterOwner.projectQiMonRoster(journey, roster).offers[0].id,
    rosterOwner.revisionForQiMonRoster(roster), model.revisionForJourney(journey), at(3));
  const seed = { "archi.journey.v3": model.serializeJourney(journey),
    "archi.qimon.roster.v1": rosterOwner.serializeQiMonRoster(roster, journey, at(4)) };
  const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  browser = await chromium.launch({ headless: true,
    ...(executablePath ? { executablePath } : { channel: "chrome" }) });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, reducedMotion: "reduce" });
  await context.addInitScript((storage) => {
    for (const [key, value] of Object.entries(storage)) if (localStorage.getItem(key) === null) localStorage.setItem(key, value);
  }, seed);
  page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.setDefaultTimeout(15_000);
  const ready = async () => {
    await page.waitForSelector("html.archi-ready");
    await page.waitForFunction(() => typeof window.render_game_to_text === "function");
  };
  const stored = () => page.evaluate(() => JSON.parse(localStorage.getItem("archi.qimon.roster.v1")));
  const readback = () => page.evaluate(() => JSON.parse(window.render_game_to_text()));
  const openEditor = async () => {
    await page.locator("#roster-entry").click();
    const editor = page.locator(".qimon-memory-editor").first();
    await editor.locator("summary").click();
    return editor;
  };
  const assess = async (polarity) => {
    const editor = await openEditor();
    await editor.getByLabel("Move being considered · rules v1 practice").selectOption("guard");
    await editor.getByLabel("Directional influence").selectOption(polarity);
    const oldCount = (await stored()).authority.events.length;
    await editor.getByRole("button", { name: "Keep this assessment", exact: true }).click();
    await page.waitForFunction((count) => JSON.parse(localStorage.getItem("archi.qimon.roster.v1")).authority.events.length === count + 1, oldCount);
  };
  const startPractice = async () => {
    await page.locator("#qimon-members").getByRole("button", { name: "Train solo", exact: true }).click();
    await page.locator("#battle-start").click();
    await page.locator("#battle-memory-guidance").waitFor({ state: "visible" });
  };
  await page.goto(origin);
  await ready();
  const editor = await openEditor();
  await editor.getByLabel("Move being considered · rules v1 practice").selectOption("guard");
  await editor.getByLabel("Directional influence").selectOption("1");
  await editor.getByLabel("Magnitude · 0 to 1").fill("");
  await editor.getByRole("button", { name: "Keep this assessment", exact: true }).click();
  check("empty numeric control cannot become a zero assessment", (await stored()).authority.events.length === roster.events.length);
  await editor.getByLabel("Magnitude · 0 to 1").fill("1");
  await editor.getByRole("button", { name: "Keep this assessment", exact: true }).click();
  await page.waitForFunction(() => JSON.parse(localStorage.getItem("archi.qimon.roster.v1")).archiveVersion === 2);
  const positive = await stored();
  check("explicit UI edit migrates existing roster and persists attraction", positive.authority.events.at(-1).action.polarity === 1);
  check("original event history survives migration", JSON.stringify(positive.authority.events.slice(0, roster.events.length)) === JSON.stringify(roster.events));
  check("memory assessment leaves Journey source bytes intact", await page.evaluate((expected) => localStorage.getItem("archi.journey.v3") === expected, seed["archi.journey.v3"]));
  await page.reload(); await ready();
  const reloaded = await openEditor();
  await reloaded.getByLabel("Move being considered · rules v1 practice").selectOption("guard");
  check("saved attraction reloads into the real editor", await reloaded.getByLabel("Directional influence").inputValue() === "1");
  await reloaded.scrollIntoViewIfNeeded();
  await page.screenshot({ path: join(output, "memory-editor-desktop.png") });
  await startPractice();
  const before = await readback();
  const positiveHeading = await page.locator("#battle-memory-guidance > strong").textContent();
  check("attraction affects the real practice recommendation", positiveHeading.includes("Guard"));
  await page.locator("#battle-memory-guidance").getByText("Inspect move influences", { exact: true }).click();
  check("retrieval is exposed for inspection", (await page.locator("#battle-memory-guidance").textContent()).includes("retrieval 1.000"));
  await page.locator("#battle-memory-guidance").getByRole("button", { name: "Use suggestion", exact: true }).click();
  check("Use suggestion fills a lawful selected move", await page.locator("#battle-one-action").inputValue() === "guard");
  const after = await readback();
  check("using a suggestion neither seals nor plays a move", after.battle.revision === before.battle.revision
    && after.battle.round === before.battle.round && after.battle.sealedCommands.one === false);
  await page.screenshot({ path: join(output, "memory-practice-attraction.png") });

  await page.reload(); await ready(); await assess("-1"); await startPractice();
  const negativeHeading = await page.locator("#battle-memory-guidance > strong").textContent();
  check("detraction reverses the candidate recommendation", !negativeHeading.includes("Guard"));
  await page.locator("#battle-memory-guidance").getByText("Inspect move influences", { exact: true }).click();
  const guardLine = (await page.locator("#battle-memory-guidance li").allTextContents()).find((line) => line.startsWith("Guard:"));
  check("polarity reversal leaves retrieval unchanged", guardLine?.includes("retrieval 1.000"));
  const negative = await stored();
  check("polarity reversal remains source bound", negative.authority.events.at(-1).action.sourceEventSha256 === positive.authority.events.at(-1).action.sourceEventSha256);

  await page.reload(); await ready(); await assess("unassessed"); await startPractice();
  const unassessed = await stored();
  check("unassess persists a reversible withdrawal of directional guidance", unassessed.authority.events.at(-1).action.polarity === null);
  const baseline = battleOwner.choosePracticeCommand((await readback()).battle, "one");
  await page.locator("#battle-memory-guidance").getByRole("button", { name: "Use suggestion", exact: true }).click();
  check("unassessed guidance returns to the existing public-state policy", await page.locator("#battle-one-action").inputValue() === baseline.action);
  await page.evaluate(() => {
    const key = "archi.journey.v3", oldValue = localStorage.getItem(key);
    localStorage.removeItem(key);
    window.dispatchEvent(new StorageEvent("storage", { key, oldValue, newValue: null, storageArea: localStorage }));
  });
  check("withdrawn source authority removes the displayed recommendation", await page.locator("#battle-memory-guidance").isHidden());
  // Reload seeds the deliberately removed synthetic source; the saved assessment stays unassessed.
  await page.reload(); await ready(); await page.setViewportSize({ width: 390, height: 844 });
  const narrow = await openEditor(); await narrow.scrollIntoViewIfNeeded();
  const bounds = await narrow.boundingBox();
  check("memory editor fits a narrow viewport", bounds && bounds.x >= 0 && bounds.x + bounds.width <= 391);
  await page.screenshot({ path: join(output, "memory-editor-narrow.png") });
  check("page completes without JavaScript errors", errors.length === 0);
  const report = { status: "passed", checks: checks.length, names: checks,
    scope: "Retained QiMon web practice only; disposable authored data; no First Signal or native app installation", output };
  await writeFile(join(output, "results.json"), JSON.stringify(report, null, 2) + "\n");
  process.stdout.write(JSON.stringify(report) + "\n");
} catch (error) {
  if (page) await page.screenshot({ path: join(output, "failure.png") }).catch(() => {});
  const report = { status: "failed", checksPassed: checks, error: error instanceof Error ? error.stack : String(error), output };
  await writeFile(join(output, "results.json"), JSON.stringify(report, null, 2) + "\n").catch(() => {});
  process.stderr.write(JSON.stringify(report) + "\n");
  process.exitCode = 1;
} finally {
  await browser?.close();
  await server?.close();
}
