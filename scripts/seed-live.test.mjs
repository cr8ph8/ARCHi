import assert from 'node:assert/strict'
import test from 'node:test'
import { harness, node, snapshot } from './helpers/seed-page-harness.mjs'

test('native baseline is silent; an observed graph change pulses once and settles',()=>{
  const h=harness();h.replace(snapshot());h.advance(600)
  assert.equal(h.inspect().origin,'native');assert.equal(h.inspect().eventCount,0);assert.equal(h.inspect().pulseCount,0);assert.equal(h.inspect().scheduled,false)
  const changed=snapshot([node('source-1')]);h.replace(changed);h.frame()
  assert.ok(h.inspect().pulseCount>0);const count=h.inspect().eventCount
  h.advance(900);h.replace(structuredClone(changed));assert.equal(h.inspect().eventCount,count)
  h.advance(1000);assert.equal(h.inspect().pulseCount,0);assert.equal(h.inspect().scheduled,false)
  assert.equal(h.ids.get('mode').textContent,'Local snapshot')
})
test('pause suppresses motion without delaying native replacement or replaying it on resume',()=>{
  const h=harness();h.replace(snapshot());h.click('motionToggle');h.replace(snapshot([node('fresh')]));h.frame()
  assert.equal(h.ids.get('counts').textContent,'2 records / 1 link');assert.equal(h.inspect().pulseCount,0);assert.ok(h.inspect().eventCount>0)
  h.click('motionToggle');h.advance(2000);assert.equal(h.inspect().pulseCount,0);assert.equal(h.inspect().scheduled,false)
})
test('hidden and reduced-motion views consume updates without deferred motion',()=>{
  const h=harness();h.replace(snapshot());h.hidden(true);h.replace(snapshot([node('while-hidden')]))
  assert.equal(h.inspect().pulseCount,0);assert.equal(h.inspect().scheduled,false)
  h.hidden(false);h.advance(600);assert.equal(h.inspect().pulseCount,0)
  h.reduce(true);h.replace(snapshot([node('while-hidden'),node('reduced')]));h.frame()
  assert.equal(h.inspect().reducedMotion,true);assert.equal(h.inspect().pulseCount,0)
  h.reduce(false);h.replace(snapshot([node('still')]),true);h.frame();assert.equal(h.inspect().reducedMotion,true);assert.equal(h.inspect().pulseCount,0)
})
test('withdrawn nodes and relationships clear old transient history and hidden record text',()=>{
  const h=harness();h.replace(snapshot());const changed=snapshot([node('private','source','REMOVABLE_TEXT')]);h.replace(changed);h.click('listTab')
  assert.match(h.ids.get('rows').textContent,/REMOVABLE_TEXT/)
  h.click('harnessView');h.replace(snapshot());h.frame()
  assert.doesNotMatch([...h.ids.values()].map(e=>e.textContent).join(' '),/REMOVABLE_TEXT/)
  assert.equal(h.inspect().eventCount,0);assert.equal(h.inspect().pulseCount,0)
  h.click('memoryView');h.click('mapTab');h.replace(changed);assert.ok(h.inspect().eventCount>0)
  h.replace({...changed,edges:[]});h.frame();assert.equal(h.inspect().eventCount,0);assert.equal(h.inspect().pulseCount,0)
})
test('a hidden authoritative replacement immediately clears all backing pixels before visibility returns',()=>{
  const h=harness();h.window.devicePixelRatio=2
  h.replace(snapshot([node('withdrawn')]));h.advance(600)
  assert.equal(h.ids.get('field').width,1800);assert.equal(h.ids.get('field').height,900)
  h.hidden(true);h.canvasCalls.length=0
  h.replace(snapshot([], 'replacement-context'))
  const clearIndex=h.canvasCalls.findIndex(call=>call.method==='clearRect')
  assert.ok(clearIndex>=0,'replacement must clear pixels before any visibility callback')
  assert.deepEqual(h.canvasCalls[clearIndex-1],{method:'setTransform',args:[1,0,0,1,0,0]})
  assert.deepEqual(h.canvasCalls[clearIndex],{method:'clearRect',args:[0,0,1800,900]})
  assert.equal(h.canvasCalls.some(call=>call.method==='fillRect'),false,'a hidden replacement must not repaint the preceding snapshot')
  assert.equal(h.inspect().pulseCount,0);assert.equal(h.inspect().eventCount,0);assert.equal(h.inspect().scheduled,false)
})
test('neural view reports missing recorder and context replacement clears observations',()=>{
  const h=harness();h.replace(snapshot());h.replace(snapshot([node('new')]));h.click('neuralView')
  assert.equal(h.ids.get('field').hidden,true);assert.match(h.ids.get('neural').textContent,/not connected/)
  h.replace(snapshot([], 'different-context'));assert.equal(h.inspect().eventCount,0);assert.equal(h.inspect().pulseCount,0)
})
test('synthetic replay is explicit, pausable, and cannot return after native takeover',()=>{
  const h=harness();assert.equal(h.inspect().origin,'unavailable');assert.equal(h.inspect().playing,false)
  h.click('demoStart');assert.equal(h.inspect().origin,'synthetic');assert.equal(h.inspect().playing,true)
  h.advance(1700);assert.equal(h.inspect().demoStep,1)
  h.click('motionToggle');const step=h.inspect().demoStep;h.advance(4000);assert.equal(h.inspect().demoStep,step)
  h.click('motionToggle');const stale=[...h.timers.values()].map(t=>t.f)
  h.replace(snapshot());assert.equal(h.inspect().nativeLocked,true);assert.equal(h.inspect().playing,false)
  stale.forEach(f=>f());h.click('replay');h.click('demoStart');h.advance(4000)
  assert.equal(h.inspect().origin,'native');assert.equal(h.inspect().eventCount,0);assert.equal(h.ids.get('demoCaption').hidden,true)
})
test('reduced motion still permits pausing semantic replay progression',()=>{
  const h=harness();h.reduce(true);h.click('demoStart')
  assert.equal(h.inspect().reducedMotion,true);assert.equal(h.ids.get('motionToggle').disabled,false)
  assert.equal(h.ids.get('motionToggle').textContent,'Pause replay')
  h.advance(1700);const step=h.inspect().demoStep;h.click('motionToggle');h.advance(4000)
  assert.equal(h.inspect().demoStep,step);assert.equal(h.inspect().paused,true);assert.equal(h.inspect().pulseCount,0)
  assert.equal(h.ids.get('motionToggle').textContent,'Resume replay');assert.match(h.ids.get('motionState').textContent,/Replay paused/)
  h.click('motionToggle');h.advance(1700);assert.ok(h.inspect().demoStep>step);assert.equal(h.inspect().pulseCount,0)
  h.replace(snapshot());assert.equal(h.ids.get('motionToggle').disabled,true)
  assert.equal(h.ids.get('motionToggle').textContent,'Reduced motion')
})
