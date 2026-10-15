"""Minimal reader for FFDec swf2xml output: character bounds, sprite timelines, matrices."""
import xml.etree.ElementTree as ET, functools

class Mat:
    def __init__(s, a=1, b=0, c=0, d=1, tx=0, ty=0): s.a,s.b,s.c,s.d,s.tx,s.ty = a,b,c,d,tx,ty
    @staticmethod
    def from_xml(m):
        if m is None: return Mat()
        g = lambda k, dv: float(m.get(k, dv))
        return Mat(g('scaleX',1), g('rotateSkew0',0), g('rotateSkew1',0), g('scaleY',1), g('translateX',0), g('translateY',0))
    def apply(s, x, y): return (s.a*x + s.c*y + s.tx, s.b*x + s.d*y + s.ty)
    def __mul__(s, o):  # s after o
        return Mat(s.a*o.a + s.c*o.b, s.b*o.a + s.d*o.b, s.a*o.c + s.c*o.d, s.b*o.c + s.d*o.d,
                   s.a*o.tx + s.c*o.ty + s.tx, s.b*o.tx + s.d*o.ty + s.ty)
    def __repr__(s): return f"Mat(a={s.a:.4f},b={s.b:.4f},c={s.c:.4f},d={s.d:.4f},tx={s.tx/20:.2f}px,ty={s.ty/20:.2f}px)"

def rect_union(r1, r2):
    if r1 is None: return r2
    if r2 is None: return r1
    return (min(r1[0],r2[0]), min(r1[1],r2[1]), max(r1[2],r2[2]), max(r1[3],r2[3]))

def xform_rect(m, r):
    if r is None: return None
    pts = [m.apply(x, y) for x in (r[0], r[2]) for y in (r[1], r[3])]
    return (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))

class Swf:
    def __init__(s, path):
        root = ET.parse(path).getroot()
        s.bounds = {}; s.sprites = {}; s.exports = {}
        for it in root.iter('item'):
            t = it.get('type', '')
            if t.startswith('DefineShape') or t.startswith('DefineMorphShape'):
                b = it.find('shapeBounds'); b = b if b is not None else it.find('startBounds')
                cid = it.get('shapeId') or it.get('characterId')
                if b is not None and cid: s.bounds[int(cid)] = tuple(float(b.get(k)) for k in ('Xmin','Ymin','Xmax','Ymax'))
            elif t in ('DefineEditTextTag',):
                b = it.find('bounds'); s.bounds[int(it.get('characterID'))] = tuple(float(b.get(k)) for k in ('Xmin','Ymin','Xmax','Ymax'))
            elif t in ('DefineTextTag', 'DefineText2Tag'):
                b = it.find('textBounds'); m = Mat.from_xml(it.find('textMatrix'))
                s.bounds[int(it.get('characterID'))] = xform_rect(m, tuple(float(b.get(k)) for k in ('Xmin','Ymin','Xmax','Ymax')))
            elif t == 'DefineButton2Tag' or t == 'DefineButtonTag':
                pass
            elif t == 'DefineSpriteTag':
                s.sprites[int(it.get('spriteId'))] = s._timeline(it.find('subTags'))
            elif t == 'ExportAssetsTag':
                for cid, nm in zip(it.find('tags'), it.find('names')): s.exports[nm.text] = int(cid.text)
        s.main = s._timeline(root.find('tags'))

    def _timeline(s, sub):
        frames = []; dl = {}; labels = {}
        for tg in sub:
            t = tg.get('type')
            if t in ('PlaceObjectTag','PlaceObject2Tag','PlaceObject3Tag'):
                dep = int(tg.get('depth')); cur = dict(dl.get(dep, {}))
                if tg.get('placeFlagHasCharacter') == 'true' or t == 'PlaceObjectTag':
                    if tg.get('placeFlagMove') != 'true': cur = {}
                    cur['id'] = int(tg.get('characterId'))
                m = tg.find('matrix')
                if m is not None: cur['m'] = Mat.from_xml(m)
                elif 'm' not in cur: cur['m'] = Mat()
                if tg.get('name'): cur['name'] = tg.get('name')
                ct = tg.find('colorTransform')
                if ct is not None: cur['ct'] = {k: ct.get(k) for k in ct.keys()}
                dl[dep] = cur
            elif t in ('RemoveObjectTag','RemoveObject2Tag'):
                dl.pop(int(tg.get('depth')), None)
            elif t == 'FrameLabelTag':
                labels[tg.get('name')] = len(frames)
            elif t == 'ShowFrameTag':
                frames.append({d: dict(v) for d, v in sorted(dl.items())})
        return {'frames': frames, 'labels': labels}

    @functools.lru_cache(None)
    def rect(s, cid, frame=None):
        """Bounds in twips. frame=None -> union over all frames (what FFDec uses for sprite PNG export)."""
        if cid in s.bounds: return s.bounds[cid]
        if cid not in s.sprites: return None
        fr = s.sprites[cid]['frames']
        r = None
        for f in (fr if frame is None else [fr[frame]]):
            for o in f.values(): r = rect_union(r, xform_rect(o['m'], s.rect(o['id'])))
        return r
