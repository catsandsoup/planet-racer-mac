"""Bake the Planet Racer asset pack from FFDec exports.

Inputs:  --xml   FFDec swf2xml dump of planetracer.swf
         --z4    FFDec sprite/shape export at -zoom 4
         --z8    FFDec sprite export at -zoom 8 (chassis colour sprites 155/171/188)
         --z4w   FFDec export of shape 193 + sprite 195 at -zoom 4 (wheel parts)
         --sounds FFDec sound export folder
Output:  <out>/sprites/**.png + <out>/sprites/manifest.json, <out>/sounds/*.mp3

Every baked image is stored at SCALE pixels per game unit (the original 550x400 stage
used 1 unit = 1 pixel). manifest.json gives each image's top-left corner ("origin") in
its parent's local game units, so a mod can swap a PNG for a bigger/better one and only
needs to edit the manifest entry if the registration point moves.
"""
import argparse, json, math, os, shutil, sys
sys.path.insert(0, os.path.dirname(__file__))
from swfxml import Swf, Mat, xform_rect
from PIL import Image

SCALE = 4  # output pixels per game unit

ap = argparse.ArgumentParser()
for k in ('xml', 'z4', 'z8', 'z4w', 'sounds', 'fonts', 'images', 'out'):
    ap.add_argument('--' + k, required=True)
ap.add_argument('--faces', help='export of the rival face sprites 438,448,457,465,469,440 at -zoom 4 (default: --z4)')
ap.add_argument('--only', choices=['faces'], help='bake just this group (merged into an existing manifest)')
A = ap.parse_args()
swf = Swf(A.xml)
OUT = os.path.join(A.out, 'sprites')
manifest = {'scale': SCALE, 'images': {}}
if A.only and os.path.exists(os.path.join(OUT, 'manifest.json')):
    with open(os.path.join(OUT, 'manifest.json')) as f: manifest = json.load(f)


def sprite_png(root, cid, frame):
    import glob
    d = glob.glob(os.path.join(root, 'sprites', f'DefineSprite_{cid}*')) or glob.glob(os.path.join(root, f'DefineSprite_{cid}*'))
    return os.path.join(d[0], f'{frame}.png')


def bake(name, src_png, src_zoom, src_rect, m=Mat(), tint_white=False):
    """Place src (exported with top-left at src_rect, in twips) through matrix m (twips->parent twips)."""
    img = Image.open(src_png).convert('RGBA')
    r = xform_rect(m, src_rect)
    w_units = (r[2] - r[0]) / 20.0
    h_units = (r[3] - r[1]) / 20.0
    # FFDec rounds image sizes up; keep the real sub-pixel aspect from the source image
    sx = abs(m.a) * SCALE / src_zoom
    sy = abs(m.d) * SCALE / src_zoom
    size = (max(1, round(img.width * sx)), max(1, round(img.height * sy)))
    img = img.resize(size, Image.LANCZOS)
    if m.a < 0: img = img.transpose(Image.FLIP_LEFT_RIGHT)
    if m.d < 0: img = img.transpose(Image.FLIP_TOP_BOTTOM)
    if tint_white:  # Flash Color.setRGB(): replace RGB, keep alpha -> store white, tint at runtime
        a = img.getchannel('A'); img = Image.new('RGBA', img.size, (255, 255, 255, 255)); img.putalpha(a)
    path = os.path.join(OUT, name + '.png')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    manifest['images'][name] = {'file': name + '.png', 'origin': [round(r[0] / 20.0, 3), round(r[1] / 20.0, 3)],
                                'size': [round(size[0] / SCALE, 3), round(size[1] / SCALE, 3)]}


def place(sprite, frame_idx, name):
    for o in swf.sprites[sprite]['frames'][frame_idx].values():
        if o.get('name') == name: return o
    raise KeyError((sprite, name))


def bake_faces():
    """Rival portraits (mcOpponentPanel.face, sprite 470): frame = face type 1..5, its 'faceframes' child
    picks the expression, plus the King's crown. Origins are in the face clip's own units."""
    root = A.faces or A.z4
    face = swf.sprites[470]
    for n, fr in enumerate(face['frames'], start=1):
        o = fr[1]
        cid = o['id']
        for f in range(1, len(swf.sprites[cid]['frames']) + 1):
            bake(f'faces/face{n}_{f}', sprite_png(root, cid, f), 4, swf.rect(cid), o['m'])
    crown = face['frames'][0][23]
    bake('faces/crown', sprite_png(root, crown['id'], 1), 4, swf.rect(crown['id']), crown['m'])


if A.only == 'faces':
    bake_faces()
    with open(os.path.join(OUT, 'manifest.json'), 'w') as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print('baked faces ->', OUT)
    sys.exit(0)


# ---- car bodies: mcChassis (190, player, faces right) and mcOppChassis (191, faces left)
COLOR_SPRITES = {1: 155, 2: 171, 3: 188}
for side, root_id in (('player', 190), ('opponent', 191)):
    m_type = place(root_id, 0, 'chassisType')['m']
    m_exh = place(root_id, 0, 'exhaust')['m']
    m_ab = place(root_id, 0, 'afterburner')['m']
    for t, csprite in COLOR_SPRITES.items():
        child = swf.sprites[189]['frames'][t - 1][1]
        m = m_type * child['m']
        rect = swf.rect(csprite)
        for c in range(1, len(swf.sprites[csprite]['frames']) + 1):
            bake(f'car/{side}/body_t{t}_c{c}', sprite_png(A.z8, csprite, c), 8, rect, m)
        bake(f'car/{side}/exhaust_t{t}', sprite_png(A.z4, 141, t), 4, swf.rect(141), m_exh)
    for k in range(1, 6):
        bake(f'car/{side}/flame_{k}', sprite_png(A.z4, 137, k), 4, swf.rect(137), m_ab)
manifest['kingmobileColor'] = swf.sprites[188]['labels']['kingmobile'] + 1

# ---- wheel (203): under-ring, colour mask (tinted per chassis colour), over-ring, tire tread (rotates)
w = {o.get('name') or f'd{d}': o for d, o in swf.sprites[203]['frames'][0].items()}
ring = os.path.join(A.z4w, 'shapes', '193.png')
bake('wheel/under', ring, 4, swf.rect(193), swf.sprites[203]['frames'][0][1]['m'])
bake('wheel/color', sprite_png(A.z4w, 195, 1), 4, swf.rect(195), w['wheelColor']['m'], tint_white=True)
bake('wheel/over', ring, 4, swf.rect(193), swf.sprites[203]['frames'][0][4]['m'])
for t in range(1, 4):
    bake(f'wheel/tire_{t}', sprite_png(A.z4, 202, t), 4, swf.rect(202), w['tire']['m'])
manifest['wheelArtRadius'] = 35  # original code scales wheels by radius/35

# ---- scenery
bake('scene/sky', sprite_png(A.z4, 316, 1), 4, swf.rect(316))
for k in (1, 2, 3):
    bake(f'scene/star_{k}', sprite_png(A.z4, 554, k), 4, swf.rect(554))
for k in range(1, 5):
    bake(f'scene/surface_tile_{k}', sprite_png(A.z4, 559, k), 4, swf.rect(559), tint_white=True)  # tinted with planet lineColor
bake('scene/start_finish', sprite_png(A.z4, 547, 1), 4, swf.rect(547))
for label, idx in swf.sprites[331]['labels'].items():
    bake(f'scene/buildings_{label}', sprite_png(A.z4, 331, idx + 1), 4, swf.rect(331))

bake_faces()

with open(os.path.join(OUT, 'manifest.json'), 'w') as f:
    json.dump(manifest, f, indent=1, sort_keys=True)

# ---- sounds: keep the linkage names the game code uses
snd_out = os.path.join(A.out, 'sounds'); os.makedirs(snd_out, exist_ok=True)
for fn in os.listdir(A.sounds):
    base, ext = os.path.splitext(fn)
    if '_' in base and ext == '.mp3':
        shutil.copy(os.path.join(A.sounds, fn), os.path.join(snd_out, base.split('_', 1)[1] + ext))
# ---- fonts: the game's own lettering (Bitsumishi for UI, Impact for numbers)
font_out = os.path.join(A.out, 'fonts'); os.makedirs(font_out, exist_ok=True)
for src, dst in (('208_Bitsumishi.ttf', 'ui.ttf'), ('86_Impact.ttf', 'numbers.ttf')):
    shutil.copy(os.path.join(A.fonts, src), os.path.join(font_out, dst))
# ---- original menu bitmaps (backdrop, planet globes, part pictures); the FOG ad art is left out
ui_out = os.path.join(A.out, 'ui'); os.makedirs(ui_out, exist_ok=True)
UI = {'570.jpg': 'backdrop.png', '572.png': 'planet_orange.png', '575.png': 'planet_purple.png',
      '578.png': 'planet_red.png', '581.png': 'planet_violet.png', '584.png': 'planet_grey.png',
      '680.png': 'engine_1.png', '682.png': 'engine_2.png', '684.png': 'engine_3.png',
      '687.png': 'afterburner_1.png', '689.png': 'afterburner_2.png', '691.png': 'afterburner_3.png',
      '284.png': 'driver.png'}
for src, dst in UI.items():  # always PNG: raylib's default build has no JPEG decoder
    Image.open(os.path.join(A.images, src)).convert('RGBA').save(os.path.join(ui_out, dst))
print('baked', len(manifest['images']), 'images ->', OUT)
