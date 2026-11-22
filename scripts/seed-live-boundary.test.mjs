import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { runInNewContext } from 'node:vm'

// Independent contract checks against the actual offline page's pure projection.
// These checks do not claim browser rendering, WebKit execution or model activity.
const page = readFileSync(
  new URL('../desktop/Sources/ARCHiDesktop/Resources/SeedDive/interior.html', import.meta.url),
  'utf8',
)
const code = page.match(/<script id="seed-live-math">([\s\S]*?)<\/script>/)?.[1]
assert.ok(code, 'the shipped page must contain its telemetry projection')
const { normalizeSeedTelemetry, seedObservedChanges } = runInNewContext(
  code + '\n;({normalizeSeedTelemetry, seedObservedChanges})',
  Object.create(null),
  { timeout: 1000, contextCodeGeneration: { strings: false, wasm: false } },
)
const clone = (value) => JSON.parse(JSON.stringify(value))
const snapshot = () => ({
  schemaVersion: 1,
  origin: 'native',
  contextID: 'test-context-a',
  nodes: [{ id: 'seed', kind: 'companion', status: 'Read-only view' }],
  edges: [],
  telemetry: {
    memory: { keptLessonCount: 0, temporaryRecordCount: 0, graphNodeCount: 1, graphEdgeCount: 0, truncatedCount: 0 },
    harness: { state: 'idle', lanes: [] },
    peer: { progress: 'idle', attemptID: '', candidateReady: false, acceptedReportCount: 0, checks: [] },
    neural: { available: false, reason: 'No activation recorder is connected.' },
  },
})
const lane = (overrides = {}) => ({
  id: 'qwen', provider: 'Local Qwen', requestID: 'request-a', state: 'pending', phase: 'Generating',
  requestStarted: true, modelIdentity: 'Synthetic fixture model', elapsedMilliseconds: null,
  invocations: [], admission: null, ...overrides,
})
function freezeTree(value) {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freezeTree(child)
    Object.freeze(value)
  }
  return value
}

test('missing instrumentation stays unavailable and graph presence never claims a neural recorder', () => {
  for (const input of [undefined, null, {}, { nodes: [{ id: 'a', kind: 'invocation' }] }]) {
    const result = normalizeSeedTelemetry(input)
    assert.equal(result.origin, 'unavailable')
    assert.equal(result.harness.state, 'unavailable')
    assert.equal(result.neural.available, false)
  }
})

test('projection does not mutate its input or retain document, prompt and answer payloads', () => {
  const input = snapshot()
  const secret = 'PRIVATE-CONTENT-MUST-NOT-ENTER-EVENTS'
  input.nodes[0].title = secret
  input.nodes[0].subtitle = secret
  input.nodes[0].details = [{ label: 'Content', value: secret }]
  input.telemetry.harness.prompt = secret
  input.telemetry.harness.lanes = [lane({ prompt: secret, text: secret, tokens: [secret] })]
  input.telemetry.neural.activations = [secret]
  const before = JSON.stringify(input)
  const projected = normalizeSeedTelemetry(freezeTree(input))
  assert.equal(JSON.stringify(input), before)
  assert.equal(JSON.stringify(projected).includes(secret), false)
})

test('initial delivery establishes a baseline rather than inventing past activity', () => {
  const input = snapshot()
  input.telemetry.harness.lanes = [lane({ invocations: [{ id: 'i1', role: 'REASONING', status: 'completed' }] })]
  assert.equal(seedObservedChanges(null, input).length, 0)
  assert.equal(seedObservedChanges(undefined, input).length, 0)
})

test('equivalent snapshots produce no repeated activity', () => {
  const input = snapshot()
  input.telemetry.harness.lanes = [lane()]
  assert.equal(seedObservedChanges(input, clone(input)).length, 0)
})

test('changing context or provenance cannot connect unrelated observations', () => {
  const previous = snapshot()
  for (const change of [
    { contextID: 'another-context' },
    { origin: 'synthetic' },
    { origin: 'unrecognised' },
  ]) {
    const next = { ...clone(previous), ...change }
    next.nodes.push({ id: 'new-record', kind: 'lesson', status: 'Current' })
    assert.equal(seedObservedChanges(previous, next).length, 0)
  }
})

test('withdrawal drops old record content and does not emit an event containing its identity', () => {
  const previous = snapshot()
  previous.nodes.push({ id: 'withdrawn-lesson', kind: 'lesson', status: 'Current', title: 'Old private words' })
  previous.edges.push({ source: 'seed', target: 'withdrawn-lesson', label: 'explicitly kept' })
  const next = snapshot()
  const projected = normalizeSeedTelemetry(next)
  assert.equal(JSON.stringify(projected).includes('withdrawn-lesson'), false)
  const events = seedObservedChanges(previous, next)
  assert.equal(JSON.stringify(events).includes('withdrawn-lesson'), false)
  assert.equal(JSON.stringify(events).includes('Old private words'), false)
})

test('new link events refer only to endpoints actually present in the current bounded projection', () => {
  const previous = snapshot(), next = snapshot()
  next.nodes.push({ id: 'source-a', kind: 'source', status: 'Current' })
  next.edges = [
    { source: 'seed', target: 'source-a', label: 'current shared copy' },
    { source: 'seed', target: 'missing', label: 'must be ignored' },
  ]
  const events = seedObservedChanges(previous, next)
  const links = events.filter(e => e.kind === 'link')
  assert.equal(links.length, 1)
  assert.equal(JSON.stringify(links[0].nodeIDs), JSON.stringify(['seed', 'source-a']))
  const present = new Set(next.nodes.map(n => n.id))
  assert.ok(events.every(e => e.nodeIDs.every(id => present.has(id))))
})

test('a new request on the same provider is distinguished even when invocation labels repeat', () => {
  const previous = snapshot()
  previous.telemetry.harness.lanes = [lane({
    state: 'complete', phase: 'Reply ready',
    invocations: [{ id: 'reasoning', role: 'REASONING', status: 'completed' }],
    admission: { status: 'accepted', stage: 'response' },
  })]
  const next = clone(previous)
  next.telemetry.harness.lanes[0].requestID = 'request-b'
  const events = seedObservedChanges(previous, next)
  assert.ok(events.some(e => e.key.startsWith('lane:') && e.key.includes('request-b')))
  assert.ok(events.some(e => e.key.startsWith('invocation:request-b:')))
  assert.ok(events.some(e => e.key.startsWith('admission:request-b:')))
})

test('cancelled invocation and rejected admission remain distinct from completion and memory retention', () => {
  const previous = snapshot()
  previous.telemetry.harness.lanes = [lane({ invocations: [{ id: 'i1', role: 'REASONING', status: 'dispatched' }] })]
  const next = clone(previous)
  Object.assign(next.telemetry.harness.lanes[0], {
    state: 'cancelled', phase: 'Stopped',
    invocations: [{ id: 'i1', role: 'REASONING', status: 'cancelled' }],
    admission: { status: 'rejected', stage: 'generation' },
  })
  const projection = normalizeSeedTelemetry(next)
  assert.equal(projection.harness.lanes[0].state, 'cancelled')
  assert.equal(projection.harness.lanes[0].admission.status, 'rejected')
  assert.equal(projection.memory.keptLessonCount, 0)
  const events = seedObservedChanges(previous, next)
  assert.ok(events.some(e => e.label.includes('cancelled')))
  assert.ok(events.some(e => e.label.includes('rejected')))
  assert.equal(events.some(e => /memory.*(kept|saved)|committed/i.test(e.label)), false)
})

test('candidate review is observable without inventing an accepted report', () => {
  const previous = snapshot(), next = snapshot()
  next.telemetry.peer = {
    progress: 'candidateReady', attemptID: 'attempt-a', candidateReady: true, acceptedReportCount: 0,
    checks: [{ id: 'source-binding', status: 'PASS' }],
  }
  const result = normalizeSeedTelemetry(next)
  assert.equal(result.peer.candidateReady, true)
  assert.equal(result.peer.acceptedReportCount, 0)
  const events = seedObservedChanges(previous, next)
  assert.ok(events.some(e => e.kind === 'peer'))
  assert.equal(events.some(e => /committed|saved/i.test(e.label)), false)
})

test('synthetic gossip ticks cannot masquerade as native peer-review events', () => {
  const previous = snapshot()
  previous.telemetry.peer.simulation = { origin: 'synthetic', round: 1, workerCount: 4 }
  const next = clone(previous)
  next.telemetry.peer.simulation.round = 2
  const events = seedObservedChanges(previous, next)
  assert.ok(events.every(event => /synthetic|demo|fixture/i.test(event.label)),
    'simulation-only updates must be suppressed or explicitly labelled synthetic')
})

test('no supplied activation values can silently turn schema v1 into a measured neural view', () => {
  const input = snapshot()
  input.telemetry.neural = { available: true, activations: [0.8], weights: [12], neuronCount: 1, reason: 'claimed' }
  const result = normalizeSeedTelemetry(input)
  assert.equal(result.neural.available, false)
  assert.equal('activations' in result.neural, false)
  assert.equal('weights' in result.neural, false)
})

test('normalization and change reporting remain bounded under oversized input', () => {
  const previous = snapshot(), next = snapshot()
  next.nodes = Array.from({ length: 900 }, (_, i) => ({ id: `n${i}`, kind: 'source', status: 'Current' }))
  next.edges = Array.from({ length: 3000 }, (_, i) => ({ source: 'n0', target: `n${i % 400}`, label: `e${i}` }))
  next.telemetry.harness.lanes = Array.from({ length: 20 }, (_, j) => lane({
    id: `lane${j}`, requestID: `request${j}`,
    invocations: Array.from({ length: 100 }, (_, i) => ({ id: `i${i}`, role: 'REASONING', status: 'dispatched' })),
  }))
  next.telemetry.peer.checks = Array.from({ length: 200 }, (_, i) => ({ id: `c${i}`, status: 'PASS' }))
  const result = normalizeSeedTelemetry(next)
  assert.ok(result.nodes.length <= 512)
  assert.ok(result.edges.length <= 2048)
  assert.ok(result.harness.lanes.length <= 4)
  assert.ok(result.harness.lanes.every(l => l.invocations.length <= 32))
  assert.ok(result.peer.checks.length <= 64)
  assert.ok(seedObservedChanges(previous, next).length <= 48)
})

test('invalid numeric counts and unknown outcomes are not displayed as successful measurements', () => {
  const input = snapshot()
  input.telemetry.memory.keptLessonCount = -1
  input.telemetry.memory.graphEdgeCount = Infinity
  input.telemetry.harness.lanes = [lane({ state: 'magic-success', elapsedMilliseconds: -50 })]
  input.telemetry.peer.checks = [{ id: 'check-a', status: 'probably fine' }]
  const result = normalizeSeedTelemetry(input)
  assert.equal(result.memory.keptLessonCount, 0)
  assert.equal(result.memory.graphEdgeCount, 0)
  assert.equal(result.harness.lanes[0].state, 'unavailable')
  assert.equal(result.harness.lanes[0].elapsedMilliseconds, null)
  assert.equal(result.peer.checks[0].status, 'unavailable')
})
