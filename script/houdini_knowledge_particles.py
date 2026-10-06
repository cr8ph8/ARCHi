"""Read-only ARCHi map adapter. Run in a *new* Python SOP, never over Liminal.

Add a file-path parameter named archi_map. In the Python SOP:
  import sys; sys.path.insert(0, '/path/to/ARCHi/script')
  import houdini_knowledge_particles as adapter
  adapter.cook(hou.pwd())

No hou import or scene mutation occurs when validating the JSON from plain Python.
"""
import json
import math
from pathlib import Path

SCHEMA = 'archi-knowledge-particles/v1'


def load_map(path):
    with Path(path).open('rb') as stream:
        raw = stream.read(512_001)
    if len(raw) > 512_000:
        raise ValueError('Particle map exceeds 512 KB')
    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key] = value
        return result
    value = json.loads(raw, object_pairs_hook=unique_keys)
    if not isinstance(value, dict) or set(value) != {'schema', 'scope', 'omittedCount', 'nodes', 'edges'} or value['schema'] != SCHEMA:
        raise ValueError('Unsupported particle map schema')
    if type(value['omittedCount']) is not int or value['omittedCount'] < 0:
        raise ValueError('Invalid omitted count')
    if not isinstance(value['scope'], str) or len(value['scope']) > 512:
        raise ValueError('Invalid scope')
    nodes, edges = value['nodes'], value['edges']
    if not isinstance(nodes, list) or len(nodes) > 220 or not isinstance(edges, list) or len(edges) > 500:
        raise ValueError('Particle map exceeds graph bounds')
    def text(s):
        return isinstance(s, str) and 0 < len(s.encode('utf-8')) <= 512 and all(ord(c) >= 32 for c in s)
    ids = set()
    kinds = {'companion','source','knowledge','lesson','request','invocation','answer','context','omission','evaluation','accounting'}
    for node in nodes:
        if not isinstance(node, dict) or set(node) != {'nodeID','kind','orb','constellation'} or not text(node['nodeID']) or node['nodeID'] in ids or not isinstance(node['kind'], str) or node['kind'] not in kinds:
            raise ValueError('Invalid or duplicate node identity')
        ids.add(node['nodeID'])
        for pose in ['orb', 'constellation']:
            point = node[pose]
            if not isinstance(point, dict) or set(point) != {'x','y'} or not all(type(v) in (int,float) and math.isfinite(v) and abs(v) <= 1 for v in point.values()):
                raise ValueError('Invalid particle coordinate')
    edge_ids = set()
    for edge in edges:
        if not isinstance(edge, dict) or set(edge) != {'id','source','target','relationship'} or not all(text(v) for v in edge.values()) or edge['id'] in edge_ids or edge['source'] not in ids or edge['target'] not in ids:
            raise ValueError('Invalid or unbound relationship')
        edge_ids.add(edge['id'])
    return value


def cook(node):
    import hou
    try:
        payload = load_map(node.evalParm('archi_map'))
    except (OSError, ValueError, TypeError, KeyError) as error:
        raise hou.NodeError(str(error)) from error
    geo = node.geometry()
    if len(geo.points()) or len(geo.prims()):
        raise hou.NodeError('Use a new unconnected Python SOP. Existing geometry was preserved.')
    for name in ['archi_node_id', 'archi_kind']:
        geo.addAttrib(hou.attribType.Point, name, '')
    for name in ['orbP', 'constellationP']:
        geo.addAttrib(hou.attribType.Point, name, (0.0, 0.0, 0.0))
    geo.addAttrib(hou.attribType.Point, 'pscale', 0.014)
    geo.addAttrib(hou.attribType.Prim, 'archi_edge_id', '')
    geo.addAttrib(hou.attribType.Prim, 'archi_relationship', '')
    geo.addAttrib(hou.attribType.Global, 'archi_schema', SCHEMA)
    geo.addAttrib(hou.attribType.Global, 'archi_omitted_count', payload['omittedCount'])
    points = {}
    for item in payload['nodes']:
        point = geo.createPoint()
        point.setAttribValue('archi_node_id', item['nodeID'])
        point.setAttribValue('archi_kind', item['kind'])
        for name, pose in [('orbP','orb'),('constellationP','constellation')]:
            p = item[pose]
            point.setAttribValue(name, (p['x'], -p['y'], 0.0))
        p = item['constellation']; point.setPosition((p['x'], -p['y'], 0.0))
        points[item['nodeID']] = point
    for item in payload['edges']:
        line = geo.createPolygon(is_closed=False)
        line.addVertex(points[item['source']]); line.addVertex(points[item['target']])
        line.setAttribValue('archi_edge_id', item['id'])
        line.setAttribValue('archi_relationship', item['relationship'])


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Validate an ARCHi particle map without Houdini or a model call.')
    parser.add_argument('map')
    payload = load_map(parser.parse_args().map)
    print(json.dumps({'schema': SCHEMA, 'nodes': len(payload['nodes']), 'edges': len(payload['edges']),
                      'omittedCount': payload['omittedCount'], 'houdiniCooked': False}))
