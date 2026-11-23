import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'

export const page = readFileSync(new URL('../../desktop/Sources/ARCHiDesktop/Resources/SeedDive/interior.html', import.meta.url), 'utf8')
const scripts = [...page.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].map(match => match[1]).join('\n')

// This deterministic double exercises the actual shipped controller. Native
// WKWebView tests separately qualify browser layout, accessibility and pixels.
export function harness() {
  const ids = new Map(), canvasCallsByID = new Map()
  const gradient = () => ({ addColorStop() {} })
  function contextFor(id) {
    const calls = canvasCallsByID.get(id) ?? []
    canvasCallsByID.set(id, calls)
    return new Proxy({
      measureText: text => ({ width: String(text).length * 6 }),
      createRadialGradient: gradient, createLinearGradient: gradient,
      // Real Canvas throws IndexSizeError on negative radii. Do not let the
      // lifecycle double hide an animation that dies as small features emerge.
      arc: (_x, _y, radius) => { if (radius < 0) throw new RangeError('Canvas arc radius must be non-negative') },
      ellipse: (_x, _y, radiusX, radiusY) => {
        if (radiusX < 0 || radiusY < 0) throw new RangeError('Canvas ellipse radii must be non-negative')
      },
      setTransform: (...args) => calls.push({ method: 'setTransform', args }),
      clearRect: (...args) => calls.push({ method: 'clearRect', args }),
      fillRect: (...args) => calls.push({ method: 'fillRect', args }),
    }, { get: (o, k) => k in o ? o[k] : () => {} })
  }
  class Element {
    constructor(tag = 'div') {
      this.tagName = tag; this.children = []; this.attributes = {}; this.events = {}; this.ownText = ''
      this.value = ''; this.hidden = false; this.className = ''; this.disabled = false
      this.width = 300; this.height = 150
      this.style = { setProperty() {} }
      this.classList = { toggle: (value, on) => {
        const values = new Set(this.className.split(' '))
        on ? values.add(value) : values.delete(value); this.className = [...values].join(' ')
      } }
    }
    set textContent(value) { this.ownText = String(value); this.children = [] }
    get textContent() { return this.ownText + this.children.map(c => c.textContent).join('') }
    set id(value) { this.elementID = value; ids.set(value, this) }
    get id() { return this.elementID }
    setAttribute(k, v) { this.attributes[k] = v }
    getAttribute(k) { return this.attributes[k] ?? null }
    append(...nodes) { this.children.push(...nodes) }
    replaceChildren(...nodes) { this.ownText = ''; this.children = nodes }
    addEventListener(k, f) { (this.events[k] ??= []).push(f) }
    querySelector(s) {
      for (const child of this.children) {
        if (child.tagName === s) return child
        const match = child.querySelector(s); if (match) return match
      }
      return null
    }
    focus() {}
    setPointerCapture() {}
    getBoundingClientRect() { return { x: 0, y: 0, left: 0, top: 0, width: 900, height: 450 } }
    getContext() { return this.context ??= contextFor(this.elementID) }
  }
  for (const match of page.matchAll(/<([a-z][a-z0-9-]*)\b[^>]*\bid="([^"]+)"[^>]*>/gi)) {
    const e = new Element(match[1]); e.id = match[2]; e.parentElement = new Element()
  }
  const document = {
    hidden: false, events: {}, getElementById: id => ids.get(id), createElement: tag => new Element(tag),
    createTextNode: text => { const e = new Element('text'); e.textContent = text; return e },
    addEventListener(k, f) { (this.events[k] ??= []).push(f) },
  }
  const reduced = { matches: false, events: [], addEventListener(_, f) { this.events.push(f) } }
  let now = 0, nextID = 0
  const timers = new Map(), frames = new Map(), window = { devicePixelRatio: 1 }
  const environment = {
    document, window, location: { search: '' }, URLSearchParams, matchMedia: () => reduced,
    performance: { now: () => now }, ResizeObserver: class { observe() {} },
    requestAnimationFrame: f => { const id = ++nextID; frames.set(id, f); return id },
    cancelAnimationFrame: id => frames.delete(id),
    setTimeout: (f, delay) => { const id = ++nextID; timers.set(id, { f, at: now + delay }); return id },
    clearTimeout: id => timers.delete(id),
  }
  runInNewContext(scripts, environment, { timeout: 1000, contextCodeGeneration: { strings: false, wasm: false } })
  function frame() { const batch = [...frames.values()]; frames.clear(); batch.forEach(f => f(now)) }
  function advance(ms) {
    now += ms
    for (const [id, timer] of [...timers]) if (timer.at <= now) { timers.delete(id); timer.f() }
    frame()
  }
  function walk(ms, interval = 50) {
    for (let elapsed = 0; elapsed < ms;) { const delta = Math.min(interval, ms - elapsed); advance(delta); elapsed += delta }
  }
  return {
    window, document, reduced, ids, timers, frames, canvasCallsByID,
    canvasCalls: canvasCallsByID.get('field'), frame, advance, walk, now: () => now,
    inspect: () => window.seedDive.inspect(), replace: (s, still = false) => window.seedDive.replace(s, still),
    click: id => ids.get(id).onclick(),
    hidden: value => { document.hidden = value; (document.events.visibilitychange ?? []).forEach(f => f()) },
    reduce: value => { reduced.matches = value; reduced.events.forEach(f => f()) },
  }
}

export const node = (id, kind = 'source', title = id) => ({ id, kind, title, status: 'available', subtitle: '', details: [] })
export function snapshot(extra = [], contextID = 'context-1') {
  const nodes = [node('seed', 'companion', 'Core Seed'), ...extra]
  return {
    origin: 'native', schemaVersion: 1, contextID, nodes,
    edges: extra.map(n => ({ source: 'seed', target: n.id, label: 'recorded' })), truncatedCount: 0,
    telemetry: { harness: { state: 'idle', lanes: [] }, memory: { graphNodeCount: nodes.length, graphEdgeCount: extra.length },
      peer: { progress: 'idle', acceptedReportCount: 0, checks: [] }, neural: { available: false } },
  }
}
