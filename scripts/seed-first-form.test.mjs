import assert from 'node:assert/strict'
import test from 'node:test'
import { harness, node, snapshot } from './helpers/seed-page-harness.mjs'

const form = h => h.inspect().form
function frozen(value) {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) frozen(child)
    Object.freeze(value)
  }
  return value
}
function openNative() {
  const h = harness(), input = frozen(snapshot([node('source-a')]))
  h.replace(input); h.advance(600); h.click('viewForm'); h.frame()
  return { h, input }
}
function start(h) { h.click('formStart'); h.walk(1200) }

test('first-form preview starts idle and does not claim an automatic identity transition', () => {
  const h = harness()
  assert.equal(form(h).visible, false)
  assert.equal(form(h).selected, 'seed')
  assert.equal(form(h).playing, false)
  h.click('viewForm'); h.walk(30000)
  assert.equal(form(h).visible, true)
  assert.equal(form(h).stage, 'seed')
  assert.equal(form(h).progress, 0)
  assert.equal(form(h).playing, false)
  assert.equal(form(h).scheduled, false)
  assert.equal(h.inspect().origin, 'unavailable')
  assert.equal(h.inspect().eventCount, 0)
})

test('growth reaches its option in order, but only an explicit choice previews Sol', () => {
  const { h, input } = openNative(), before = JSON.stringify(input)
  h.click('formStart')
  const stages = ['seed']; let previous = 0
  for (let elapsed = 0; elapsed < 15000; elapsed += 50) {
    h.advance(50)
    const current = form(h)
    assert.ok(current.progress >= previous && current.progress <= 1, 'progress must stay bounded and monotonic')
    previous = current.progress
    if (stages.at(-1) !== current.stage) stages.push(current.stage)
  }
  assert.deepEqual(stages, ['seed', 'gathering', 'shaping', 'ready'])
  assert.equal(form(h).progress, 1)
  assert.equal(form(h).playing, false)
  assert.equal(form(h).scheduled, false)
  assert.equal(form(h).selected, 'seed', 'finishing an animation must not select or adopt a form')
  h.click('formChooseSol'); h.walk(2000)
  assert.equal(form(h).selected, 'sol-raindrop')
  assert.equal(form(h).scheduled, false, 'the chosen pose must settle without an idle animation loop')
  assert.equal(JSON.stringify(input), before, 'the authoritative input remains unchanged')
  assert.equal(h.ids.get('counts').textContent, '2 records / 1 link')
  assert.equal(h.inspect().origin, 'native')
  assert.equal(h.inspect().eventCount, 0)
  assert.equal(h.inspect().pulseCount, 0)
})

test('pause freezes elapsed growth; resume continues and reset invalidates pending frames', () => {
  const { h } = openNative(); start(h)
  assert.ok(form(h).progress > 0 && form(h).progress < 1)
  h.click('formPause'); const held = form(h).progress
  h.walk(60000)
  assert.equal(form(h).paused, true)
  assert.equal(form(h).progress, held)
  assert.equal(form(h).scheduled, false)
  h.click('formPause'); h.walk(500)
  assert.ok(form(h).progress > held)
  const stale = [...h.frames.values()]
  h.click('formReset'); stale.forEach(callback => callback(h.now())); h.walk(2000)
  assert.equal(form(h).stage, 'seed')
  assert.equal(form(h).progress, 0)
  assert.equal(form(h).selected, 'seed')
  assert.equal(form(h).playing, false)
  assert.equal(form(h).scheduled, false)
})

test('hiding the page freezes the preview and returning requires explicit resume', () => {
  const { h } = openNative(); start(h)
  const held = form(h).progress
  h.hidden(true); h.walk(30000)
  assert.equal(form(h).progress, held)
  assert.equal(form(h).paused, true)
  assert.equal(form(h).scheduled, false)
  h.hidden(false); h.walk(3000)
  assert.equal(form(h).progress, held)
  assert.equal(form(h).paused, true)
  assert.equal(form(h).scheduled, false)
  h.click('formPause'); h.walk(500)
  assert.ok(form(h).progress > held)
})

test('leaving the First form tab freezes growth without catch-up on return', () => {
  const { h } = openNative(); start(h)
  const held = form(h).progress
  h.click('harnessView'); h.walk(10000)
  assert.equal(form(h).visible, false)
  assert.equal(form(h).progress, held)
  assert.equal(form(h).paused, true)
  assert.equal(form(h).scheduled, false)
  h.click('viewForm'); h.walk(3000)
  assert.equal(form(h).progress, held)
  assert.equal(form(h).paused, true)
  h.click('formPause'); h.walk(500)
  assert.ok(form(h).progress > held)
})

test('reduced motion and native quiet presentation expose a complete static choice', () => {
  for (const quiet of [false, true]) {
    const h = harness()
    if (!quiet) h.reduce(true)
    h.replace(snapshot(), quiet); h.click('viewForm'); h.click('formStart'); h.walk(1000)
    assert.equal(form(h).reducedMotion, true)
    assert.equal(form(h).stage, 'ready')
    assert.equal(form(h).progress, 1)
    assert.equal(form(h).selected, 'seed')
    assert.equal(form(h).playing, false)
    assert.equal(form(h).scheduled, false)
    assert.equal(h.ids.get('formChooseSol').disabled, false)
    h.click('formChooseSol'); h.walk(2000)
    assert.equal(form(h).selected, 'sol-raindrop')
    assert.equal(form(h).scheduled, false)
    h.click('formReset'); assert.equal(form(h).selected, 'seed')
    assert.equal(form(h).stage, 'seed')
  }
})

test('enabling reduced motion during growth stops the loop and keeps direct preview usable', () => {
  const { h } = openNative(); start(h)
  h.reduce(true); h.walk(2000)
  assert.equal(form(h).reducedMotion, true)
  assert.equal(form(h).scheduled, false)
  const held = form(h).progress; h.walk(10000)
  assert.equal(form(h).progress, held)
  h.click('formChooseSol'); h.walk(1000)
  assert.equal(form(h).selected, 'sol-raindrop')
  assert.equal(form(h).scheduled, false)
})

test('same-context data refresh preserves the local choice; new context clears it', () => {
  const { h } = openNative()
  h.click('formChooseSol'); h.frame()
  h.replace(frozen(snapshot([node('source-a'), node('source-b')]))); h.frame()
  assert.equal(form(h).selected, 'sol-raindrop')
  assert.equal(form(h).contextID, 'context-1')
  assert.equal(h.ids.get('counts').textContent, '3 records / 2 links')
  h.replace(frozen(snapshot([], 'context-2'))); h.walk(2000)
  assert.equal(form(h).contextID, 'context-2')
  assert.equal(form(h).selected, 'seed')
  assert.equal(form(h).stage, 'seed')
  assert.equal(form(h).progress, 0)
  assert.equal(form(h).playing, false)
  assert.equal(form(h).scheduled, false)
})

test('old growth callbacks cannot restore a withdrawn context', () => {
  const { h } = openNative(); start(h)
  const stale = [...h.frames.values()]
  assert.ok(stale.length > 0)
  h.replace(frozen(snapshot([], 'replacement-context')))
  stale.forEach(callback => callback(h.now())); h.walk(2000)
  assert.equal(form(h).contextID, 'replacement-context')
  assert.equal(form(h).stage, 'seed')
  assert.equal(form(h).progress, 0)
  assert.equal(form(h).playing, false)
  assert.equal(form(h).scheduled, false)
})

test('standalone and synthetic previews retain their provenance and native arrival resets the option', () => {
  const h = harness()
  h.click('viewForm'); h.click('formChooseSol')
  assert.equal(h.inspect().origin, 'unavailable')
  assert.equal(form(h).selected, 'sol-raindrop')
  h.click('demoStart'); h.click('viewForm'); h.click('formChooseSol'); h.advance(1700)
  assert.equal(h.inspect().origin, 'synthetic')
  assert.equal(h.ids.get('mode').textContent, 'Synthetic replay')
  assert.equal(form(h).selected, 'sol-raindrop')
  h.replace(frozen(snapshot())); h.walk(2000)
  assert.equal(h.inspect().origin, 'native')
  assert.equal(h.inspect().nativeLocked, true)
  assert.equal(h.inspect().playing, false)
  assert.equal(form(h).selected, 'seed')
  assert.equal(form(h).stage, 'seed')
  assert.equal(form(h).scheduled, false)
  h.click('replay'); h.click('demoStart'); h.walk(2000)
  assert.equal(h.inspect().origin, 'native')
  assert.equal(form(h).selected, 'seed')
})
