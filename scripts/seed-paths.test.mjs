import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { runInNewContext } from 'node:vm'

// Exercise the actual functions shipped in the offline, single-file renderer.
const page = readFileSync(
  new URL('../desktop/Sources/ARCHiDesktop/Resources/SeedDive/interior.html', import.meta.url),
  'utf8',
)
const code = page.match(/<script id="seed-path-math">([\s\S]*?)<\/script>/)[1]
const { seedPathTree, pathFromSeed } = runInNewContext(code + '\n;({seedPathTree, pathFromSeed})')
const nodes = ['s', 'a', 'b', 'c'].map((id) => ({ id, kind: id === 's' ? 'companion' : 'source' }))
const edge = (source, target, label = 'recorded') => ({ source, target, label })

test('only recorded forward links form a route, and the origin is zero hops', () => {
  const tree = seedPathTree(nodes, [edge('a', 's'), edge('s', 's'), edge('s', 'b')])
  assert.equal(pathFromSeed(tree, 's').length, 0)
  assert.equal(pathFromSeed(tree, 'a'), null)
  assert.equal(pathFromSeed(tree, 'b').length, 1)
  assert.equal(pathFromSeed(tree, 'c'), null)
})
test('invalid endpoints and missing or ambiguous origin yield no invented route', () => {
  const edges = [edge('s', 'missing'), edge('missing', 'a')]
  assert.equal(seedPathTree(nodes, edges).size, 1)
  assert.equal(seedPathTree(nodes.slice(1), edges).size, 0)
  assert.equal(seedPathTree([...nodes, { id: 's2', kind: 'companion' }], edges).size, 0)
})
test('parallel links keep an actual label and replacement discards withdrawn paths', () => {
  const edges = [
    edge('s', 'a', 'prepared for'),
    edge('s', 'a', 'dispatched to'),
    edge('a', 'b', 'answer outcome'),
  ]
  const trail = pathFromSeed(seedPathTree(nodes, edges), 'b')
  assert.equal(trail[0], edges[0])
  assert.equal(trail[1], edges[2])
  assert.equal(pathFromSeed(seedPathTree(nodes, edges.slice(0, 2)), 'b'), null)
})
test('distances and path witnesses agree with an independent all-pairs solver on all 4,096 simple directed graphs of four nodes', () => {
  const choices = []
  for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) if (i !== j) choices.push([i, j])
  for (let mask = 0; mask < 2 ** choices.length; mask++) {
    const dist = Array.from({ length: 4 }, (_, i) => nodes.map((_, j) => (i === j ? 0 : Infinity)))
    const edges = []
    choices.forEach(([i, j], index) => {
      if (!(mask & (1 << index))) return
      edges.push(edge(nodes[i].id, nodes[j].id))
      dist[i][j] = 1
    })
    // Floyd–Warshall uses all possible intermediate vertices, independently of queue order.
    for (let k = 0; k < 4; k++)
      for (let i = 0; i < 4; i++)
        for (let j = 0; j < 4; j++) dist[i][j] = Math.min(dist[i][j], dist[i][k] + dist[k][j])
    const tree = seedPathTree(nodes, edges)
    nodes.forEach(({ id }, j) => {
      const trail = pathFromSeed(tree, id)
      assert.equal(trail?.length ?? Infinity, dist[0][j])
      if (!trail) return
      let last = 's'
      for (const step of trail) {
        assert.ok(edges.includes(step))
        assert.equal(step.source, last)
        last = step.target
      }
      assert.equal(last, id)
    })
  }
})
