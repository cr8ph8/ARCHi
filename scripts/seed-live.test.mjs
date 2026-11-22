import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { runInNewContext } from 'node:vm'

const page = readFileSync(new URL('../desktop/Sources/ARCHiDesktop/Resources/SeedDive/interior.html', import.meta.url), 'utf8')
const scripts = [...page.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].map(match => match[1]).join('\n')

// A deterministic DOM/canvas double tests controller lifecycle and data fences.
// Native WKWebView tests separately cover the real browser and rendering.
function harness() {
  class Element {
    constructor(tag='div') {
      this.tagName=tag;this.children=[];this.attributes={};this.events={};this.ownText='';this.value='';this.hidden=false;this.className='';this.disabled=false
      this.style={setProperty(){}}
      this.classList={toggle:(value,on)=>{const values=new Set(this.className.split(' '));on?values.add(value):values.delete(value);this.className=[...values].join(' ')}}
    }
    set textContent(value){this.ownText=String(value);this.children=[]}
    get textContent(){return this.ownText+this.children.map(c=>c.textContent).join('')}
    set id(value){this.elementID=value;ids.set(value,this)}
    get id(){return this.elementID}
    setAttribute(k,v){this.attributes[k]=v}
    append(...nodes){this.children.push(...nodes)}
    replaceChildren(...nodes){this.ownText='';this.children=nodes}
    addEventListener(k,f){(this.events[k]??=[]).push(f)}
    querySelector(s){for(const child of this.children){if(child.tagName===s)return child;const match=child.querySelector(s);if(match)return match}return null}
    focus(){}
    setPointerCapture(){}
    getBoundingClientRect(){return {x:0,y:0,left:0,top:0,width:900,height:450}}
  }
  const ids=new Map([...page.matchAll(/\bid="([^"]+)"/g)].map(m=>[m[1],new Element(m[1]==='field'?'canvas':'div')]))
  const context=new Proxy({measureText:text=>({width:String(text).length*6}),createRadialGradient:()=>({addColorStop(){}})}, {get:(o,k)=>k in o?o[k]:()=>{}})
  ids.get('field').getContext=()=>context
  ids.get('field').parentElement=new Element()
  const document={hidden:false,events:{},getElementById:id=>ids.get(id),createElement:tag=>new Element(tag),createTextNode:text=>{const e=new Element('text');e.textContent=text;return e},addEventListener(k,f){(this.events[k]??=[]).push(f)}}
  const reduced={matches:false,events:[],addEventListener(_,f){this.events.push(f)}}
  let now=0,nextID=0
  const timers=new Map(),frames=new Map(),window={devicePixelRatio:1}
  const environment={document,window,location:{search:''},URLSearchParams,matchMedia:()=>reduced,performance:{now:()=>now},ResizeObserver:class{observe(){}},
    requestAnimationFrame:f=>{const id=++nextID;frames.set(id,f);return id},cancelAnimationFrame:id=>frames.delete(id),
    setTimeout:(f,delay)=>{const id=++nextID;timers.set(id,{f,at:now+delay});return id},clearTimeout:id=>timers.delete(id)}
  runInNewContext(scripts,environment)
  function frame(){const batch=[...frames.values()];frames.clear();batch.forEach(f=>f(now))}
  function advance(ms){now+=ms;for(const [id,timer] of [...timers])if(timer.at<=now){timers.delete(id);timer.f()}frame()}
  return {window,document,reduced,ids,timers,frame,advance,inspect:()=>window.seedDive.inspect(),replace:(s,still=false)=>window.seedDive.replace(s,still),
    click:id=>ids.get(id).onclick(),hidden:value=>{document.hidden=value;document.events.visibilitychange.forEach(f=>f())},
    reduce:value=>{reduced.matches=value;reduced.events.forEach(f=>f())}}
}
const node=(id,kind='source',title=id)=>({id,kind,title,status:'available',subtitle:'',details:[]})
function snapshot(extra=[],contextID='context-1') {
  const nodes=[node('seed','companion','Core Seed'),...extra]
  return {origin:'native',schemaVersion:1,contextID,nodes,edges:extra.map(n=>({source:'seed',target:n.id,label:'recorded'})),truncatedCount:0,
    telemetry:{harness:{state:'idle',lanes:[]},memory:{graphNodeCount:nodes.length,graphEdgeCount:extra.length},peer:{progress:'idle',acceptedReportCount:0,checks:[]},neural:{available:false}}}
}

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
