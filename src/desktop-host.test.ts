import { describe, expect, it, vi } from "vitest";
import {
  connectDesktopHost, createDesktopInteractionScope, createDownloadLeasePool, readDesktopHostBootstrap,
  type DesktopHostEnvironment, type DesktopJourneyProjection, type DesktopJourneyState, type DesktopArenaReadback,
} from "./desktop-host";
import { collectEcho, commitCareAction, commitSession, createCareIntent, createJourney, createPlaySession, revisionForJourney, serializeJourney, journeyOriginSha256 } from "./model";

const sessionId = "8A123456-ABCD-4BCD-8BCD-123456789ABC";
const bootstrap = { version: 1, host: "archi-desktop", sessionId, visible: true };

function fixture(visible = true) {
  const messages: DesktopJourneyProjection[] = [];
  const postMessage = vi.fn((value: DesktopJourneyProjection) => { messages.push(value); });
  const environment: DesktopHostEnvironment = {
    __ARCHI_DESKTOP_BOOTSTRAP__: { ...bootstrap, visible },
    webkit: { messageHandlers: { archiJourneyProjection: { postMessage } } },
    document: { visibilityState: "visible" },
  };
  return { environment, messages, postMessage };
}

function ready(): Extract<DesktopJourneyState, { readiness: "ready" }> {
  const journey = createJourney("host-projection-test", "2026-09-06T12:00:00.000Z");
  return {
    readiness: "ready", storage: "local-browser", mode: "habitat",
    journeyId: journey.id, revision: revisionForJourney(journey), eventCount: journey.events.length,
    originDigest: journeyOriginSha256(journey), practices: [], arena: null,
  };
}

function freshReadback(): DesktopArenaReadback {
  const team = (id: "one" | "two"): DesktopArenaReadback["teams"][number] => ({ id, label: id === "one" ? "Your side" : "Other side", spark: 3,
    roster: [{ id: `${id}-member`, name: "QiMon", role: "hearth", integrity: 36, maximumIntegrity: 36, active: true, exposed: false }] });
  return { teams: [team("one"), team("two")], rounds: [], result: null };
}

describe("read-only desktop Journey host", () => {
  it("delivers the current native body without changing Journey metadata", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    bridge.publish(ready());
    const before = JSON.stringify(messages);
    const message = { version: 1, host: "archi-desktop", sessionId, sequence: 1,
      id: "Companion:origin", label: "Companion", png: "data:image/png;base64,iVBORw0KGgoAAAA=", reduceMotion: false };
    expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance(message)).toBe(true);
    const changed = vi.fn(); bridge.onAppearanceChange(changed);
    expect(changed.mock.calls[0][0].id).toBe("Companion:origin");
    expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance({...message, sequence: 2, id: "Guide light:origin", label: "Guide light"})).toBe(true);
    expect(changed.mock.calls[1][0].id).toBe("Guide light:origin");
    expect(JSON.stringify(messages)).toBe(before);
    expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance(message)).toBe(false);
    expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance({...message, sequence: 3, sessionId: "another-session"})).toBe(false);
    const api = environment.__ARCHI_DESKTOP_HOST__!; bridge.dispose();
    expect(api.setAppearance({...message, sequence: 3})).toBe(false);
  });

  it("accepts local PNG appearance only, never a URL or a save payload", () => {
    const { environment } = fixture(); connectDesktopHost(environment);
    const message = { version: 1, host: "archi-desktop", sessionId, sequence: 1,
      id: "Companion:origin", label: "Companion", png: "data:image/png;base64,iVBORw0KGgoAAAA=", reduceMotion: false };
    for (const invalid of [
      {...message, png: "https://example.com/body.png"},
      {...message, png: "data:image/svg+xml,<svg/>"},
      {...message, png: "data:image/png;base64," + "a".repeat(2_000_000)},
      {...message, journey: {}}, {...message, reduceMotion: "true"}, {...message, sequence: 0},
    ]) expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance(invalid)).toBe(false);
    expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance(message)).toBe(true);
  });
  it("accepts a compact Liminal structure identity and rejects concatenated oversized identities", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    bridge.publish(ready());
    const before = JSON.stringify(messages);
    const message = { version: 1, host: "archi-desktop", sessionId, sequence: 1,
      id: "liminal-" + "a".repeat(64), label: "Liminal · Beast Form", png: "data:image/png;base64,iVBORw0KGgoAAAA=", reduceMotion: true };
    const changed = vi.fn(); bridge.onAppearanceChange(changed);
    expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance({ ...message,
      id: "liminal-v008-" + "a".repeat(64) + "-structure-" + "b".repeat(64) })).toBe(false);
    expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance(message)).toBe(true);
    expect(changed).toHaveBeenLastCalledWith(expect.objectContaining({ id: message.id }));
    expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance({ ...message, sequence: 2, id: "b".repeat(100) })).toBe(true);
    expect(environment.__ARCHI_DESKTOP_HOST__!.setAppearance({ ...message, sequence: 3, id: "c".repeat(101) })).toBe(false);
    expect(changed).toHaveBeenCalledTimes(2);
    expect(JSON.stringify(messages)).toBe(before);
  });
  it("requires both exact native bootstrap and its callable WK transport", () => {
    expect(readDesktopHostBootstrap({})).toBeNull();
    expect(readDesktopHostBootstrap({ __ARCHI_DESKTOP_BOOTSTRAP__: bootstrap })).toBeNull();
    const { environment } = fixture();
    expect(readDesktopHostBootstrap(environment)).toEqual(bootstrap);
    delete environment.__ARCHI_DESKTOP_BOOTSTRAP__;
    expect(readDesktopHostBootstrap(environment)).toBeNull();
  });

  it.each([
    { ...bootstrap, version: 2 }, { ...bootstrap, host: "browser" },
    { ...bootstrap, sessionId: "not-a-session" }, { ...bootstrap, visible: "true" },
    { ...bootstrap, visibility: true }, null, [],
  ])("rejects malformed or expanded bootstrap %j", (raw) => {
    const { environment, messages } = fixture();
    environment.__ARCHI_DESKTOP_BOOTSTRAP__ = raw;
    expect(connectDesktopHost(environment)).toBeNull();
    expect(environment.__ARCHI_DESKTOP_HOST__).toBeUndefined();
    expect(messages).toHaveLength(0);
  });

  it("fails closed when bootstrap or transport access throws", () => {
    const environment: DesktopHostEnvironment = {};
    Object.defineProperty(environment, "__ARCHI_DESKTOP_BOOTSTRAP__", { get() { throw new Error("unavailable"); } });
    expect(connectDesktopHost(environment)).toBeNull();
  });

  it("starts with loading and null identity, then reports the real Journey projection", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    expect(messages[0]).toEqual({
      ...bootstrap, version: 4, sequence: 1, kind: "journey-projection", readiness: "loading", storage: "unknown",
      mode: "habitat", journeyId: null, revision: null, eventCount: null, originDigest: null, practices: [], arena: null,
    });
    expect(bridge.publish(ready())).toBe(true);
    expect(messages[1]).toEqual({ ...bootstrap, version: 4, sequence: 2, kind: "journey-projection", ...ready() });
    expect(Object.isFrozen(messages[1])).toBe(true);
    expect(bridge.publish(ready())).toBe(false);
    expect(messages).toHaveLength(2);
  });

  it("selects metadata instead of serializing events or the source object", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    const privateFields = { ...ready(), events: ["private history"], document: "private source", seed: "private seed" };
    bridge.publish(privateFields);
    const sent = JSON.stringify(messages.at(-1));
    expect(sent).not.toMatch(/private|events|document|seed/);
    expect(Object.keys(messages.at(-1)!)).toEqual([
      "version", "host", "sessionId", "sequence", "kind", "readiness", "storage", "mode", "journeyId", "revision", "eventCount", "visible", "originDigest", "practices", "arena",
    ]);
  });

  it("copies accepted metadata and emits only changed fields with increasing sequence", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    const state = ready();
    bridge.publish(state);
    state.mode = "battle";
    environment.__ARCHI_DESKTOP_HOST__!.setVisibility({ ...bootstrap, sequence: 1, visible: false });
    expect(messages.at(-1)?.mode).toBe("habitat");
    bridge.publish(state);
    expect(messages.at(-1)).toMatchObject({ sequence: 4, mode: "battle", visible: false });
  });

  it("rejects invalid identity/count/state and a readiness rewind", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    for (const invalid of [
      { ...ready(), journeyId: "raw document" }, { ...ready(), eventCount: -1 },
      { ...ready(), eventCount: 2.4 }, { ...ready(), revision: "x".repeat(161) },
      { ...ready(), mode: "reset" }, { ...ready(), storage: "cloud" },
    ]) expect(bridge.publish(invalid as DesktopJourneyState)).toBe(false);
    expect(messages).toHaveLength(1);
    bridge.publish(ready());
    expect(bridge.publish({ readiness: "loading", storage: "unknown", mode: "habitat", journeyId: null, revision: null, eventCount: null, originDigest: null, practices: [], arena: null })).toBe(false);
  });

  it("allows only a current-session versioned visibility operation", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    const visible = vi.fn();
    bridge.onVisibilityChange(visible);
    visible.mockClear();
    const api = environment.__ARCHI_DESKTOP_HOST__!;
    for (const invalid of [
      { ...bootstrap, sequence: 1, version: 2, visible: false },
      { ...bootstrap, sequence: 1, sessionId: "8A123456-ABCD-4BCD-8BCD-123456789ABD", visible: false },
      { ...bootstrap, sequence: 1, host: "wrong", visible: false },
      { ...bootstrap, sequence: 0, visible: false },
      { ...bootstrap, sequence: 1.1, visible: false },
      { ...bootstrap, sequence: 1, visible: false, command: "reset" },
      { ...bootstrap, sequence: 1, visible: "false" }, null,
    ]) expect(api.setVisibility(invalid)).toBe(false);
    expect(bridge.visible).toBe(true);
    expect(visible).not.toHaveBeenCalled();
    expect(messages).toHaveLength(1);
    expect(Object.keys(api).sort()).toEqual(["performArenaAction", "setAppearance", "setVisibility"]);
  });

  it("ignores duplicate and out-of-order visibility updates, including old hides after resume", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    const visible = vi.fn();
    bridge.onVisibilityChange(visible);
    const api = environment.__ARCHI_DESKTOP_HOST__!;
    expect(api.setVisibility({ ...bootstrap, sequence: 3, visible: false })).toBe(true);
    expect(api.setVisibility({ ...bootstrap, sequence: 3, visible: true })).toBe(false);
    expect(api.setVisibility({ ...bootstrap, sequence: 2, visible: true })).toBe(false);
    expect(api.setVisibility({ ...bootstrap, sequence: 4, visible: true })).toBe(true);
    expect(api.setVisibility({ ...bootstrap, sequence: 3, visible: false })).toBe(false);
    expect(visible.mock.calls).toEqual([[true], [false], [true]]);
    expect(messages.map((message) => message.sequence)).toEqual([1, 2, 3]);
  });

  it("delivers initial hidden state and resumes only when host AND document are visible", () => {
    const { environment } = fixture(false);
    const bridge = connectDesktopHost(environment)!;
    const visible = vi.fn();
    bridge.onVisibilityChange(visible);
    bridge.setDocumentVisibility(false);
    environment.__ARCHI_DESKTOP_HOST__!.setVisibility({ ...bootstrap, sequence: 1 });
    expect(bridge.visible).toBe(false);
    bridge.setDocumentVisibility(true);
    expect(bridge.visible).toBe(true);
    expect(visible.mock.calls).toEqual([[false], [true]]);
  });

  it("reports actual revision changes without owning or mutating the Journey", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    let journey = createJourney("local-authority", "2026-09-06T12:00:00.000Z");
    const before = JSON.stringify(journey);
    bridge.publish({ ...ready(), journeyId: journey.id, revision: revisionForJourney(journey), eventCount: 0 });
    environment.__ARCHI_DESKTOP_HOST__!.setVisibility({ ...bootstrap, sequence: 1, visible: false });
    expect(JSON.stringify(journey)).toBe(before);
    journey = commitCareAction(journey, createCareIntent(journey, "greet"), "2026-09-06T12:01:00.000Z");
    bridge.publish({ ...ready(), journeyId: journey.id, revision: revisionForJourney(journey), eventCount: journey.events.length });
    expect(messages.at(-1)).toMatchObject({ eventCount: 1, revision: revisionForJourney(journey), visible: false });
  });

  it("a dead native transport does not throw into game state and a later send can retry", () => {
    const { environment, postMessage } = fixture();
    postMessage.mockImplementationOnce(() => { throw new Error("host closed"); });
    const bridge = connectDesktopHost(environment)!;
    expect(() => bridge.publish(ready())).not.toThrow();
    expect(postMessage).toHaveBeenCalledTimes(2);
  });

  it("retires a bridge without deleting a replacement's API", () => {
    const { environment } = fixture();
    const old = connectDesktopHost(environment)!;
    const oldAPI = environment.__ARCHI_DESKTOP_HOST__!;
    const next = connectDesktopHost(environment)!;
    old.dispose();
    expect(environment.__ARCHI_DESKTOP_HOST__).not.toBe(oldAPI);
    expect(oldAPI.setVisibility({ ...bootstrap, sequence: 1, visible: false })).toBe(false);
    expect(old.publish(ready())).toBe(false);
    expect(next.visible).toBe(true);
    next.dispose();
    expect(environment.__ARCHI_DESKTOP_HOST__).toBeUndefined();
  });
});

describe("native interaction lifetime", () => {
  it.each(["care", "keep"] as const)("retires queued %s even if the lock ignores abort and grants after hide then resume", async (operation) => {
    let visible = true;
    const scope = createDesktopInteractionScope(() => visible);
    const lease = scope.begin()!;
    let journey = createJourney("queued-native-work", "2026-09-06T12:00:00.000Z");
    const original = serializeJourney(journey);
    let saved = original;
    let session = createPlaySession(journey);
    for (const echo of session.echoes.slice(0,3)) session = collectEcho(session, echo.id);
    const intent = createCareIntent(journey, "greet");
    let release!: () => void;
    const lock = new Promise<void>((resolve) => { release = resolve; });
    const committed = vi.fn();
    const pending = lock.then(() => {
      if (!lease.isCurrent()) return;
      journey = operation === "care" ? commitCareAction(journey, intent, "2026-09-06T12:01:00.000Z") : commitSession(journey, session, "hold");
      saved = serializeJourney(journey);
      committed();
    }).finally(() => lease.finish());
    visible = false; scope.invalidate(); visible = true;
    expect(lease.signal.aborted).toBe(true);
    release(); await pending;
    expect(committed).not.toHaveBeenCalled();
    expect(saved).toBe(original);
    expect(serializeJourney(journey)).toBe(original);
    const next = scope.begin()!;
    expect(next.isCurrent()).toBe(true);
    next.finish();
  });

  it("does not start a field from an old Explore continuation after hide then resume", async () => {
    let visible = true;
    const scope = createDesktopInteractionScope(() => visible);
    const lease = scope.begin()!;
    const beginPlay = vi.fn();
    let finishLock!: () => void;
    const lock = new Promise<void>((resolve) => { finishLock = resolve; });
    const pending = (async () => {
      await lock;
      lease.finish();
      if (lease.isCurrent()) beginPlay();
    })();
    visible = false; scope.invalidate(); visible = true;
    finishLock(); await pending;
    expect(beginPlay).not.toHaveBeenCalled();
  });

  it("blocks late picker entry while hidden and a File.text completion from a retired visible lifetime", () => {
    let visible = true;
    const scope = createDesktopInteractionScope(() => visible);
    const fileReadIsCurrent = scope.capture()!;
    visible = false; scope.invalidate();
    expect(scope.capture()).toBeNull();
    expect(scope.begin()).toBeNull();
    visible = true;
    expect(fileReadIsCurrent()).toBe(false);
    expect(scope.capture()!()).toBe(true);
  });

  it("ordinary care changes the projection revision without a mode or Continuity change, including session-only storage", () => {
    const { environment, messages } = fixture();
    const bridge = connectDesktopHost(environment)!;
    let journey = createJourney("care-projection", "2026-09-06T12:00:00.000Z");
    const publish = (storage: "local-browser" | "session-only") => bridge.publish({
      readiness: "ready", storage, mode: "habitat", journeyId: journey.id, revision: revisionForJourney(journey), eventCount: journey.events.length,
    originDigest: journeyOriginSha256(journey), practices: [], arena: null,
    });
    publish("local-browser");
    for (const [index,action] of (["greet","tend","rest"] as const).entries()) {
      journey = commitCareAction(journey,createCareIntent(journey,action),`2026-09-06T12:0${index+1}:00.000Z`);
      publish(index === 2 ? "session-only" : "local-browser");
      expect(messages.at(-1)).toMatchObject({ mode: "habitat", revision: revisionForJourney(journey), eventCount: index+1 });
    }
    expect(messages.at(-1)?.storage).toBe("session-only");
    expect(messages).toHaveLength(5);
  });
});

describe("bounded Journey download URL retention", () => {
  it("keeps URLs alive for a delayed save, then revokes them at expiry", () => {
    vi.useFakeTimers();
    const revoke = vi.fn();
    const pool = createDownloadLeasePool({ revoke, later: (fn,ms) => setTimeout(fn,ms) as unknown as number, cancel: clearTimeout });
    pool.retain("blob:one");
    vi.advanceTimersByTime(60_000);
    expect(revoke).not.toHaveBeenCalled();
    vi.advanceTimersByTime(240_000);
    expect(revoke).toHaveBeenCalledExactlyOnceWith("blob:one");
    expect(vi.getTimerCount()).toBe(0);
    vi.useRealTimers();
  });

  it("bounds outstanding blobs and releases all retained URLs on unload", () => {
    vi.useFakeTimers();
    const revoke = vi.fn();
    const pool = createDownloadLeasePool({ revoke, later: (fn,ms) => setTimeout(fn,ms) as unknown as number, cancel: clearTimeout });
    for (let i=0; i<10; i++) pool.retain(`blob:${i}`);
    expect(revoke.mock.calls).toEqual([["blob:0"],["blob:1"]]);
    expect(vi.getTimerCount()).toBe(8);
    pool.dispose();
    expect(revoke).toHaveBeenCalledTimes(10);
    expect(vi.getTimerCount()).toBe(0);
    pool.dispose();
    expect(revoke).toHaveBeenCalledTimes(10);
    vi.useRealTimers();
  });
});

describe("native Arena intent admission", () => {
  const arenaRevision = "a".repeat(64);
  const commandId = "12345678-abcd-4abc-8abc-123456789abc";
  function arenaState(): Extract<DesktopJourneyState, { readiness: "ready" }> {
    return { ...ready(), arena: { battleId: null, revision: arenaRevision, phase: "entry", round: 0,
      summary: "Choose a partner practice", actions: [{ id: "start", label: "Start practice", detail: "No model call" }], whatIf: null, readback: null } };
  }
  function command(overrides: Record<string, unknown> = {}) {
    return { version: 1, host: "archi-desktop", sessionId, commandId, expectedRevision: arenaRevision,
      actionId: "start", visibilitySequence: 0, ...overrides };
  }
  it("admits one visible, legal, current-revision intent and publishes the reducer readback", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    bridge.publish(arenaState());
    const handler = vi.fn((id, revision) => {
      expect([id, revision]).toEqual(["start", arenaRevision]);
      bridge.publish({ ...arenaState(), mode: "battle", arena: { battleId: "12345678-abcd-4abc-8abc-123456789abc",
        revision: "b".repeat(64), phase: "planning", round: 1, summary: "Round one", actions: [], whatIf: null, readback: freshReadback() } });
      return true;
    });
    bridge.onArenaAction(handler);
    const api = environment.__ARCHI_DESKTOP_HOST__!;
    expect(api.performArenaAction(command())).toBe(true);
    expect(messages.at(-1)).toMatchObject({ version: 4, mode: "battle", arena: { phase: "planning", round: 1 } });
    expect(api.performArenaAction(command())).toBe(false);
    expect(handler).toHaveBeenCalledTimes(1);
  });
  it("rejects unknown operations, stale revisions, sessions and expanded commands without invoking the handler", () => {
    const { environment } = fixture(); const bridge = connectDesktopHost(environment)!;
    bridge.publish(arenaState()); const handler = vi.fn(() => true); bridge.onArenaAction(handler);
    const api = environment.__ARCHI_DESKTOP_HOST__!;
    for (const invalid of [
      command({ version: 2 }), command({ host: "other" }), command({ sessionId: commandId }),
      command({ expectedRevision: "b".repeat(64) }), command({ actionId: "reset" }), command({ commandId: "bad" }),
      command({ visibilitySequence: -1 }), command({ visibilitySequence: 0.1 }), command({ extra: "keep" }),
      command({ visibilitySequence: undefined }), null,
    ]) expect(api.performArenaAction(invalid)).toBe(false);
    expect(handler).not.toHaveBeenCalled();
    expect(api.performArenaAction(command())).toBe(true);
    expect(api.performArenaAction(command({ commandId: commandId.toUpperCase() }))).toBe(false);
  });
  it("rejects an unused command from an earlier visibility epoch even when the Arena revision is unchanged", () => {
    const { environment } = fixture(); const bridge = connectDesktopHost(environment)!;
    bridge.publish(arenaState()); const handler = vi.fn(() => true); bridge.onArenaAction(handler);
    const api = environment.__ARCHI_DESKTOP_HOST__!;
    expect(api.setVisibility({ ...bootstrap, sequence: 1, visible: false })).toBe(true);
    expect(api.performArenaAction(command())).toBe(false);
    expect(api.setVisibility({ ...bootstrap, sequence: 2, visible: true })).toBe(true);
    expect(api.performArenaAction(command())).toBe(false);
    expect(api.performArenaAction(command({ visibilitySequence: 2 }))).toBe(true);
    expect(handler).toHaveBeenCalledTimes(1);
  });
  it("does not permit hidden, disposed, loading or unavailable actions", () => {
    const { environment } = fixture(); const bridge = connectDesktopHost(environment)!;
    const handler = vi.fn(() => true); bridge.onArenaAction(handler);
    const api = environment.__ARCHI_DESKTOP_HOST__!;
    expect(api.performArenaAction(command())).toBe(false);
    bridge.publish(arenaState()); bridge.setDocumentVisibility(false);
    expect(api.performArenaAction(command())).toBe(false);
    bridge.setDocumentVisibility(true);
    bridge.publish({ ...arenaState(), arena: { ...arenaState().arena!, actions: [] } });
    expect(api.performArenaAction(command())).toBe(false);
    bridge.publish(arenaState()); bridge.dispose();
    expect(api.performArenaAction(command())).toBe(false);
    expect(handler).not.toHaveBeenCalled();
  });
  it("consumes a command even if its reducer handler rejects or throws", () => {
    const { environment } = fixture(); const bridge = connectDesktopHost(environment)!;
    bridge.publish(arenaState()); const handler = vi.fn(() => { throw new Error("stale live state"); });
    bridge.onArenaAction(handler); const api = environment.__ARCHI_DESKTOP_HOST__!;
    expect(api.performArenaAction(command())).toBe(false);
    expect(api.performArenaAction(command())).toBe(false);
    expect(handler).toHaveBeenCalledTimes(1);
  });
  it("owns a detached copy of action state so caller mutation cannot silently grant another action", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    const candidate = arenaState(); bridge.publish(candidate);
    const handler = vi.fn(() => true); bridge.onArenaAction(handler);
    candidate.arena!.actions[0].id = "keep";
    expect(environment.__ARCHI_DESKTOP_HOST__!.performArenaAction(command({ actionId: "keep" }))).toBe(false);
    expect(messages.at(-1)?.arena?.actions[0].id).toBe("start");
    expect(environment.__ARCHI_DESKTOP_HOST__!.performArenaAction(command())).toBe(true);
  });
  it("requires bounded closed projection shapes and internally consistent entry and active rounds", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    const initialCount = messages.length; const a = arenaState().arena!;
    for (const invalid of [
      { ...arenaState(), originDigest: null },
      { ...arenaState(), arena: { ...a, battleId: commandId } },
      { ...arenaState(), arena: { ...a, round: 1 } },
      { ...arenaState(), arena: { ...a, phase: "planning" } },
      { ...arenaState(), arena: { ...a, summary: "🦋".repeat(126) } },
      { ...arenaState(), arena: { ...a, actions: [{ id: "start", label: "🦋".repeat(31), detail: "" }] } },
      { ...arenaState(), arena: { ...a, actions: [{ id: "start", label: "start", detail: "x".repeat(301) }] } },
      { ...arenaState(), arena: { ...a, actions: [a.actions[0], a.actions[0]] } },
      { ...arenaState(), arena: { ...a, actions: new Array(1) } },
      { ...arenaState(), arena: { ...a, privateMove: "guard" } },
      { ...arenaState(), practices: [null] },
    ]) expect(bridge.publish(invalid as DesktopJourneyState)).toBe(false);
    expect(messages).toHaveLength(initialCount);
    const getter = { ...a.actions[0] }; Object.defineProperty(getter, "id", { get() { throw new Error("getter"); } });
    expect(bridge.publish({ ...arenaState(), arena: { ...a, actions: [getter] } })).toBe(false);
  });
  it("bounds saved summaries to the current Journey origin and removes caller data from the wire", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    const summary = { originDigest: ready().originDigest!, eventId: `event-1-${"c".repeat(64)}`, battleId: commandId,
      rulesVersion: 1 as const, rounds: 4, outcome: "won" as const, replayDigest: "d".repeat(64), committedAt: "2026-09-06T12:00:00.000Z" };
    expect(bridge.publish({ ...arenaState(), practices: [summary] })).toBe(true);
    summary.outcome = "lost" as "won";
    expect(messages.at(-1)?.practices[0].outcome).toBe("won");
    for (const item of [ { ...summary, originDigest: "f".repeat(64) }, { ...summary, rounds: 21 },
      { ...summary, replayDigest: "D".repeat(64) }, { ...summary, eventId: "claimed" },
      { ...summary, committedAt: "yesterday" }, { ...summary, rawTranscript: "private" } ]) {
      expect(bridge.publish({ ...arenaState(), practices: [item] })).toBe(false);
    }
    expect(bridge.publish({ ...arenaState(), practices: [summary, summary] })).toBe(false);
    expect(bridge.publish({ ...arenaState(), practices: Array.from({ length: 9 }, (_, i) => ({ ...summary, eventId: `event-${i + 1}-${"c".repeat(64)}` })) })).toBe(false);
  });
});

describe("native Arena What if projection", () => {
  function whatIf() {
    return {
      choices: [{ id: "pulse", label: "Pulse", detail: "Use Spark." }, { id: "guard", label: "Guard", detail: "Recover Spark." }],
      firstId: "pulse", secondId: "guard",
      cases: [{ opponentId: "guard", opponentLabel: "Guard", first: "Your Pulse meets their shield.", second: "Both recover Spark." }],
    };
  }
  function state(): Extract<DesktopJourneyState, { readiness: "ready" }> {
    return { ...ready(), mode: "battle", arena: { battleId: "12345678-abcd-4abc-8abc-123456789abc", revision: "a".repeat(64),
      phase: "planning", round: 1, summary: "Compare two choices.",
      actions: [{ id: "what-if:close", label: "Close comparison", detail: "Return to moves." }], whatIf: whatIf(), readback: freshReadback() } };
  }
  it("emits v4 comparisons through the existing v1 revision-bound action API", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    expect(bridge.publish(state())).toBe(true);
    expect(messages.at(-1)).toMatchObject({ version: 4, arena: { whatIf: whatIf() } });
    const handler = vi.fn(() => true); bridge.onArenaAction(handler);
    expect(environment.__ARCHI_DESKTOP_HOST__!.performArenaAction({ version: 1, host: "archi-desktop", sessionId,
      commandId: "12345678-abcd-4abc-8abc-123456789abc", expectedRevision: "a".repeat(64), actionId: "what-if:close", visibilitySequence: 0 })).toBe(true);
    expect(handler).toHaveBeenCalledWith("what-if:close", "a".repeat(64));
  });
  it("requires nullable whatIf in v4 even when comparisons are closed", () => {
    const { environment } = fixture(); const bridge = connectDesktopHost(environment)!;
    const candidate = state(); candidate.arena!.whatIf = null;
    expect(bridge.publish(candidate)).toBe(true);
    const missing = { ...candidate.arena } as Record<string, unknown>; delete missing.whatIf;
    expect(bridge.publish({ ...candidate, arena: missing } as unknown as DesktopJourneyState)).toBe(false);
  });
  it("rejects malformed, nonfinite, expanded and inconsistent comparison content", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    const good = whatIf();
    for (const invalid of [
      {}, [], "preview", { ...good, extra: true }, { ...good, firstId: "missing" }, { ...good, firstId: "guard" },
      { ...good, secondId: Infinity }, { ...good, choices: good.choices.slice(0, 1) },
      { ...good, choices: Array.from({ length: 8 }, (_, i) => ({ ...good.choices[0], id: String(i) })) },
      { ...good, choices: [good.choices[0], good.choices[0]] }, { ...good, choices: new Array(2) },
      { ...good, choices: [{ ...good.choices[0], detail: "x".repeat(301) }, good.choices[1]] },
      { ...good, choices: [{ ...good.choices[0], label: "🦋".repeat(31) }, good.choices[1]] },
      { ...good, choices: [{ ...good.choices[0], id: "x".repeat(161) }, good.choices[1]] },
      { ...good, cases: [] }, { ...good, cases: new Array(1) },
      { ...good, cases: Array.from({ length: 8 }, (_, i) => ({ ...good.cases[0], opponentId: String(i) })) },
      { ...good, cases: [good.cases[0], good.cases[0]] },
      ...["opponentId", "opponentLabel", "first", "second"].flatMap((key) => [
        { ...good, cases: [{ ...good.cases[0], [key]: "" }] }, { ...good, cases: [{ ...good.cases[0], [key]: NaN }] },
      ]),
      { ...good, cases: [{ ...good.cases[0], first: "🦋".repeat(176) }] },
      { ...good, cases: [{ ...good.cases[0], second: "x".repeat(701) }] },
      { ...good, cases: [{ ...good.cases[0], opponentId: "x".repeat(161) }] },
      { ...good, cases: [{ ...good.cases[0], opponentLabel: "x".repeat(121) }] },
      { ...good, cases: [{ ...good.cases[0], hiddenCommand: "guard" }] },
    ]) expect(bridge.publish({ ...state(), arena: { ...state().arena!, whatIf: invalid } } as DesktopJourneyState)).toBe(false);
    expect(messages).toHaveLength(1);
  });
  it("rejects accessor, symbolic and non-plain nested values without reading a getter", () => {
    const { environment } = fixture(); const bridge = connectDesktopHost(environment)!;
    const getter = vi.fn(() => "guard"); const expanded = whatIf();
    Object.defineProperty(expanded.cases[0], "opponentId", { get: getter });
    const candidates = [expanded, Object.assign(whatIf(), { [Symbol("private")]: true }), Object.assign(Object.create({ private: true }), whatIf())];
    for (const candidate of candidates) expect(bridge.publish({ ...state(), arena: { ...state().arena!, whatIf: candidate } })).toBe(false);
    expect(getter).not.toHaveBeenCalled();
  });
  it("admits comparisons only for active planning in the Arena", () => {
    const { environment } = fixture(); const bridge = connectDesktopHost(environment)!;
    for (const override of [{ phase: "sealed" }, { phase: "finished" }, { phase: "entry", battleId: null, round: 0 },
      { battleId: null }, { round: 0 }, { round: Infinity }, { round: NaN }]) {
      expect(bridge.publish({ ...state(), arena: { ...state().arena!, ...override } } as DesktopJourneyState)).toBe(false);
    }
    expect(bridge.publish({ ...state(), mode: "field" })).toBe(false);
  });
  it("detaches all nested comparison data on both input and output", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    const candidate = state(); expect(bridge.publish(candidate)).toBe(true);
    candidate.arena!.whatIf!.choices[0].label = "Changed input";
    candidate.arena!.whatIf!.cases[0].first = "Changed input outcome";
    const sent = messages.at(-1)!;
    expect(sent.arena?.whatIf).toEqual(whatIf());
    sent.arena!.whatIf!.choices[1].label = "Changed output";
    sent.arena!.whatIf!.cases[0].second = "Changed output outcome";
    bridge.setDocumentVisibility(false);
    expect(messages.at(-1)?.arena?.whatIf).toEqual(whatIf());
  });
  it("keeps the prior state and actions when a individually bounded payload exceeds the total byte budget", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    const prior = state(); expect(bridge.publish(prior)).toBe(true);
    const huge = state();
    huge.arena!.actions = Array.from({ length: 32 }, (_, i) => ({ id: String(i).padEnd(160, "x"), label: "l".repeat(120), detail: "d".repeat(300) }));
    huge.arena!.whatIf = { choices: Array.from({ length: 7 }, (_, i) => ({ id: String(i).padEnd(160, "x"), label: "l".repeat(120), detail: "d".repeat(300) })),
      firstId: "0".padEnd(160, "x"), secondId: "1".padEnd(160, "x"),
      cases: Array.from({ length: 7 }, (_, i) => ({ opponentId: String(i).padEnd(160, "x"), opponentLabel: "l".repeat(120), first: "a".repeat(700), second: "b".repeat(700) })) };
    expect(bridge.publish(huge)).toBe(false);
    expect(messages).toHaveLength(2);
    bridge.setDocumentVisibility(false);
    expect(messages.at(-1)?.arena).toEqual(prior.arena);
  });
});

describe("native Arena v4 resolved readback", () => {
  function state(readback: unknown = freshReadback()): DesktopJourneyState {
    return { ...ready(), mode: "battle", arena: { battleId: "12345678-abcd-4abc-8abc-123456789abc",
      revision: "a".repeat(64), phase: "planning", round: 1, summary: "Choose a move.",
      actions: [], whatIf: null, readback } } as DesktopJourneyState;
  }
  it("requires the new field and binds result/history presence to the actual displayed phase and round", () => {
    const { environment } = fixture(); const bridge = connectDesktopHost(environment)!;
    const candidate = state(); expect(bridge.publish(candidate)).toBe(true);
    const missing = { ...candidate.arena } as Record<string, unknown>; delete missing.readback;
    expect(bridge.publish({ ...candidate, arena: missing } as unknown as DesktopJourneyState)).toBe(false);
    expect(bridge.publish(state(null))).toBe(false);
    expect(bridge.publish({ ...candidate, arena: { ...candidate.arena!, phase: "entry", round: 0, battleId: null } })).toBe(false);
    expect(bridge.publish({ ...candidate, arena: { ...candidate.arena!, phase: "finished" } })).toBe(false);
    expect(bridge.publish({ ...candidate, arena: { ...candidate.arena!, round: 2 } })).toBe(false);
    expect(bridge.publish({ ...candidate, arena: { ...candidate.arena!, phase: "sealed" } })).toBe(true);
  });
  it("rejects malformed team resources, member flags, repeated identities and expanded records", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    const view = freshReadback(); const team = view.teams[0]; const member = team.roster[0];
    const invalidMembers = [
      { ...member, id: "" }, { ...member, id: "x".repeat(161) }, { ...member, name: "蝶".repeat(41) },
      { ...member, role: "unknown" }, { ...member, role: null }, { ...member, integrity: -1 },
      { ...member, integrity: 37 }, { ...member, integrity: 1.5 }, { ...member, integrity: NaN },
      { ...member, integrity: Infinity }, { ...member, maximumIntegrity: 0 }, { ...member, maximumIntegrity: 35 },
      { ...member, active: "true" }, { ...member, exposed: 1 }, { ...member, integrity: 0 },
      { ...member, pendingCommand: "pulse" },
    ];
    const invalidTeams = [
      { ...team, id: "two" }, { ...team, label: "" }, { ...team, label: "x".repeat(121) },
      { ...team, spark: -1 }, { ...team, spark: 4 }, { ...team, spark: 0.5 },
      { ...team, roster: [] }, { ...team, roster: new Array(1) }, { ...team, roster: [member, member] },
      { ...team, roster: Array.from({ length: 4 }, (_, index) => ({ ...member, id: String(index), maximumIntegrity: 9, integrity: 9, active: false })) },
      { ...team, roster: [0, 1].map((index) => ({ ...member, id: String(index), integrity: 18, maximumIntegrity: 18 })) },
      { ...team, sealed: "guard" }, ...invalidMembers.map((entry) => ({ ...team, roster: [entry] })),
    ];
    for (const entry of invalidTeams) expect(bridge.publish(state({ ...view, teams: [entry, view.teams[1]] }))).toBe(false);
    for (const entry of [null, {}, [], { ...view, teams: new Array(2) }, { ...view, teams: [team] },
      { ...view, teams: [view.teams[1], team] }, { ...view, extra: true },
      { ...view, teams: [team, { ...view.teams[1], roster: [{ ...view.teams[1].roster[0], id: member.id }] }] }]) {
      expect(bridge.publish(state(entry))).toBe(false);
    }
    expect(messages).toHaveLength(1);
  });
  it("rejects nested getters and sparse histories without evaluating an accessor", () => {
    const { environment } = fixture(); const bridge = connectDesktopHost(environment)!;
    const getter = vi.fn(() => 36); const view = freshReadback();
    Object.defineProperty(view.teams[0].roster[0], "integrity", { get: getter });
    expect(bridge.publish(state(view))).toBe(false); expect(getter).not.toHaveBeenCalled();
    for (const rounds of [new Array(1), [{ round: 0, summary: "wrong" }], [{ round: 2, summary: "gap" }],
      [{ round: 1, summary: "" }], [{ round: 1, summary: "蝶".repeat(167) }], [{ round: 1, summary: "ok", hiddenMove: "pulse" }],
      Array.from({ length: 21 }, (_, index) => ({ round: index + 1, summary: "ok" }))]) {
      const candidate = state({ ...freshReadback(), rounds }); candidate.arena!.round = 2;
      expect(bridge.publish(candidate)).toBe(false);
    }
  });
  it("validates terminal outcomes and preserves all copies across later caller and transport mutation", () => {
    const { environment, messages } = fixture(); const bridge = connectDesktopHost(environment)!;
    const result = { winner: "one", reason: "eliminated", retention: "unsaved", message: "Keep this result." };
    const view = { ...freshReadback(), rounds: [{ round: 1, summary: "Side 1 wins." }], result };
    const candidate = state(view); candidate.arena!.phase = "finished";
    for (const entry of [{ ...result, winner: "three" }, { ...result, reason: "timeout" }, { ...result, retention: "cloud" },
      { ...result, message: "" }, { ...result, message: "x".repeat(301) }, { ...result, savedFile: "private" }]) {
      expect(bridge.publish({ ...candidate, arena: { ...candidate.arena!, readback: { ...view, result: entry } } } as DesktopJourneyState)).toBe(false);
    }
    expect(bridge.publish(state(view))).toBe(false);
    expect(bridge.publish(candidate)).toBe(true);
    const pristine = JSON.parse(JSON.stringify(messages.at(-1)?.arena?.readback));
    view.teams[0].roster[0].integrity = 5; view.rounds[0].summary = "Changed input"; result.retention = "saved";
    expect(messages.at(-1)?.arena?.readback).toEqual(pristine);
    const sent = messages.at(-1)!.arena!.readback!;
    sent.teams[1].roster[0].name = "Changed output"; sent.rounds[0].summary = "Changed output"; sent.result!.message = "Changed output";
    bridge.setDocumentVisibility(false);
    expect(messages.at(-1)?.arena?.readback).toEqual(pristine);
  });
});
