# Chaos kit: the things a city leaves behind when it panics all at once (godot/models/chaos/*.glb).
#   python3 art/chaos_kit.py [--preview]          (pip bpy 5.3, headless)
# Suitcases, a duffel, luggage carts, sawhorse barricades, sandbags, cones, a bent street sign, a toppled market
# stall, a sky tram car, a cable car gondola and a rubble pile. Cartoon proportions, soft rounded edges.
# Game space: Y up, +Z forward, origin on the ground at the prop's footprint centre.
# Placed by godot/scripts/level/layout/chaos.gd and the routes in godot/scripts/level/areas/w_routes.gd.
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blib import *
import bmesh
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', 'godot', 'models', 'chaos'))
os.makedirs(OUT, exist_ok=True)
PREVIEW = '--preview' in sys.argv
PRE = '/tmp/claude-0/chaos_prev'
os.makedirs(PRE, exist_ok=True)

def M(name, c, metal=0.0, rough=0.55):
    return mat('cx_' + name, c, metal, rough)

def done(root, name, cam=(2.2, 1.6, 3.2), look=(0, 0.6, 0)):
    export(os.path.join(OUT, name + '.glb'), root)
    print('%-16s %6d tris' % (name, tri_count(root)))
    if PREVIEW: preview(os.path.join(PRE, name + '.png'), root, cam_from=cam, look=look, size=(500, 500), samples=24)

def box(name, sx, sy, sz, m, root, at, rot=(0, 0, 0), r=0.0):
    return part(name, bm_box(sx, sy, sz), m, root, at=at, rot=rot, rounded=r, smooth=r > 0)

def cyl(name, r1, r2, h, m, root, at, rot=(0, 0, 0), seg=12):
    return part(name, bm_cyl(r1, r2, h, seg), m, root, at=at, rot=rot)

# ------------------------------------------------------------------ luggage
def suitcase(name, col, w=0.55, h=0.75, d=0.26):
    reset(); root = empty(name)
    shell = M(name + '_shell', col, 0.1, 0.4); dark = M('dark', 0x2b2f36, 0.4, 0.5); steel = M('steel', 0xb8c0c8, 0.9, 0.3)
    box('body', w, h, d, shell, root, (0, 0.06 + h / 2, 0), r=0.06)
    for x in (-w * 0.28, w * 0.28): box('rib' + str(x), 0.05, h * 0.96, d + 0.02, shell, root, (x, 0.06 + h / 2, 0), r=0.02)
    box('zip', w + 0.01, 0.025, d + 0.015, dark, root, (0, 0.06 + h * 0.5, 0), r=0.01)
    for x in (-w * 0.33, w * 0.33):
        cyl('wheel' + str(x), 0.05, 0.05, 0.05, dark, root, (x, 0.05, d * 0.32), rot=(0, 0, math.pi / 2), seg=10)
    for x in (-0.12, 0.12): box('rod' + str(x), 0.025, 0.25, 0.025, steel, root, (x, 0.06 + h + 0.12, -d * 0.3))
    box('grip', 0.3, 0.04, 0.05, dark, root, (0, 0.06 + h + 0.25, -d * 0.3), r=0.015)
    box('sticker', 0.16, 0.12, 0.01, M('sticker', 0xf3e6c4), root, (-0.1, 0.06 + h * 0.66, d / 2 + 0.006), rot=(0, 0, 0.2))
    done(root, name, cam=(1.4, 1.1, 1.8), look=(0, 0.45, 0))

def duffel():
    reset(); root = empty('duffel')
    cloth = M('duffel', 0x5c7a3a, 0.0, 0.8); dark = M('dark', 0x2b2f36, 0.4, 0.5)
    bm = bm_capsule(0.22, 0.55, 16, 10)
    bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.pi / 2, 4, 'Z'), verts=bm.verts)
    part('bag', bm, cloth, root, at=(0, 0.22, 0), scale=(1, 0.85, 1))
    part('strap', bm_torus(0.22, 0.025, 20, 6, math.pi), dark, root, at=(0, 0.36, 0), rot=(0, 0, 0))
    for x in (-0.36, 0.36): part('end' + str(x), bm_cyl(0.19, 0.19, 0.03, 16), dark, root, at=(x, 0.22, 0), rot=(0, 0, math.pi / 2), scale=(1, 1, 0.85))
    done(root, 'duffel', cam=(1.3, 1.0, 1.6), look=(0, 0.25, 0))

def luggage_cart():
    reset(); root = empty('luggage_cart')
    steel = M('steel', 0xb8c0c8, 0.9, 0.3); red = M('cart_red', 0xc8432f, 0.3, 0.45); dark = M('dark', 0x2b2f36, 0.4, 0.5)
    box('deck', 1.1, 0.06, 1.7, red, root, (0, 0.28, 0), r=0.02)
    for x in (-0.5, 0.5):
        for z in (-0.75, 0.75):
            cyl('caster%s%s' % (x, z), 0.09, 0.09, 0.07, dark, root, (x, 0.09, z), rot=(0, 0, math.pi / 2), seg=12)
            box('fork%s%s' % (x, z), 0.04, 0.12, 0.04, steel, root, (x, 0.2, z))
    for x in (-0.52, 0.52):
        box('upright' + str(x), 0.05, 1.1, 0.05, steel, root, (x, 0.85, -0.8))
        box('side' + str(x), 0.04, 0.04, 1.6, steel, root, (x, 0.55, 0))
    box('handle', 1.1, 0.06, 0.06, red, root, (0, 1.42, -0.8), r=0.02)
    box('back', 1.06, 0.6, 0.03, steel, root, (0, 0.65, -0.82))
    done(root, 'luggage_cart', cam=(2.0, 1.6, 2.4), look=(0, 0.5, 0))

# ------------------------------------------------------------------ barricades
def sawhorse():
    reset(); root = empty('sawhorse')
    wood = M('wood', 0x9a6a3e, 0.0, 0.8); white = M('stripe_w', 0xf2efe6); orange = M('stripe_o', 0xf07a22)
    amber = glowmat('cx_amber', 0xffaa33, 4)
    for x in (-0.8, 0.8):
        for s in (-1, 1):
            box('leg%s%s' % (x, s), 0.07, 1.05, 0.07, wood, root, (x, 0.5, s * 0.16), rot=(s * 0.32, 0, 0))
    board = box('board', 1.9, 0.26, 0.05, white, root, (0, 0.92, 0), r=0.01)
    for i in range(5):
        box('stripe%d' % i, 0.18, 0.27, 0.055, orange, root, (-0.76 + i * 0.38, 0.92, 0), rot=(0, 0, 0.55))
    box('rail_lo', 1.7, 0.08, 0.05, wood, root, (0, 0.42, 0))
    cyl('lamp_base', 0.07, 0.07, 0.06, M('dark', 0x2b2f36, 0.4, 0.5), root, (0.75, 1.08, 0))
    part('lamp', bm_sphere(0.08, 12, 8), amber, root, at=(0.75, 1.16, 0))
    done(root, 'sawhorse', cam=(1.8, 1.5, 2.6), look=(0, 0.6, 0))

def sandbags():
    reset(); root = empty('sandbags')
    sack = M('sack', 0xb79e72, 0.0, 0.9); sack2 = M('sack2', 0xa38a60, 0.0, 0.9)
    i = 0
    for row, (y, n, off) in enumerate([(0.13, 4, 0.0), (0.37, 3, 0.25)]):
        for k in range(n):
            bm = bm_capsule(0.13, 0.32, 12, 8)
            bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.pi / 2, 4, 'Z'), verts=bm.verts)
            part('bag%d' % i, bm, sack if i % 2 else sack2, root, at=(-0.75 + off + k * 0.5, y, 0), scale=(1, 0.75, 1.25),
                 rot=(0, (k % 3 - 1) * 0.08, 0))
            i += 1
    done(root, 'sandbags', cam=(1.6, 1.2, 2.2), look=(0, 0.2, 0))

def cone():
    reset(); root = empty('cone')
    org = M('cone', 0xf26a1b, 0.0, 0.5); white = M('stripe_w', 0xf2efe6); dark = M('dark', 0x2b2f36, 0.4, 0.5)
    box('base', 0.42, 0.05, 0.42, dark, root, (0, 0.025, 0), r=0.02)
    cyl('body', 0.17, 0.035, 0.68, org, root, (0, 0.39, 0), seg=16)
    cyl('band', 0.118, 0.093, 0.12, white, root, (0, 0.42, 0), seg=16)
    done(root, 'cone', cam=(1.0, 0.9, 1.3), look=(0, 0.35, 0))

def sign_bent():
    reset(); root = empty('sign_bent')
    steel = M('steel', 0xb8c0c8, 0.9, 0.3); blue = M('sign_blue', 0x2f6db5, 0.2, 0.45); white = M('stripe_w', 0xf2efe6)
    cyl('post_lo', 0.05, 0.05, 1.3, steel, root, (0, 0.65, 0), seg=10)
    cyl('post_hi', 0.05, 0.05, 1.2, steel, root, (0.32, 1.72, 0), rot=(0, 0, -0.62), seg=10)
    p = box('panel', 1.3, 0.75, 0.05, blue, root, (0.95, 2.05, 0.05), rot=(0.1, 0.25, -0.35), r=0.02)
    box('frame', 1.36, 0.81, 0.04, white, root, (0.95, 2.05, 0.03), rot=(0.1, 0.25, -0.35), r=0.02)
    done(root, 'sign_bent', cam=(2.0, 2.0, 3.2), look=(0.4, 1.3, 0))

# ------------------------------------------------------------------ toppled market stall
def stall_wreck():
    reset(); root = empty('stall_wreck')
    wood = M('wood', 0x9a6a3e, 0.0, 0.8); cloth = M('awning_red', 0xd2483a, 0.0, 0.8); cloth2 = M('awning_cream', 0xf1e2c0, 0.0, 0.8)
    crate = M('crate', 0xb88a52, 0.0, 0.8)
    fruit = [M('fruit_o', 0xf29a2e, 0.0, 0.5), M('fruit_r', 0xd8342c, 0.0, 0.4), M('fruit_g', 0x8fc248, 0.0, 0.5)]
    # counter on its back, legs in the air
    box('counter', 2.2, 0.8, 0.9, wood, root, (0, 0.45, 0), rot=(1.35, 0, 0.06), r=0.03)
    for x in (-1.0, 1.0):
        box('leg' + str(x), 0.08, 1.2, 0.08, wood, root, (x, 0.95, 0.62), rot=(1.2, 0, 0))
    # the awning slumped over the front
    for i in range(6):
        c = cloth if i % 2 == 0 else cloth2
        box('aw%d' % i, 0.42, 0.03, 1.5, c, root, (-1.05 + i * 0.42, 0.45 + 0.08 * math.sin(i), -0.9), rot=(-0.45, 0, 0.04 * (i - 3)))
    box('pole', 0.07, 2.4, 0.07, wood, root, (1.2, 0.35, -0.2), rot=(0, 0.3, 1.45))
    for k, (x, z, ry) in enumerate([(-0.9, -1.5, 0.3), (0.5, -1.7, -0.4), (1.4, -0.9, 0.9)]):
        box('crate%d' % k, 0.5, 0.35, 0.4, crate, root, (x, 0.18, z), rot=(0, ry, 0.0 if k != 1 else 0.6), r=0.02)
    for k in range(14):
        a = k * 2.3
        r = 0.6 + (k % 4) * 0.35
        part('fruit%d' % k, bm_sphere(0.09, 10, 6), fruit[k % 3], root, at=(math.cos(a) * r, 0.09, -1.3 + math.sin(a) * r * 0.6))
    done(root, 'stall_wreck', cam=(3.0, 2.4, -3.4), look=(0, 0.4, -0.6))

# ------------------------------------------------------------------ the sky tram
def tram_car():
    reset(); root = empty('tram_car')
    paint = M('tram_teal', 0x2f9c95, 0.2, 0.4); cream = M('tram_cream', 0xf2e4c4, 0.1, 0.45)
    dark = M('dark', 0x2b2f36, 0.4, 0.5); glass = M('glass', 0x9fd7ea, 0.2, 0.08); steel = M('steel', 0xb8c0c8, 0.9, 0.3)
    red = M('cart_red', 0xc8432f, 0.3, 0.45)
    L, W, H = 8.0, 2.6, 2.7
    box('lower', W, 1.1, L, paint, root, (0, 0.95, 0), r=0.18)
    box('upper', W - 0.05, 1.4, L - 0.3, cream, root, (0, 2.2, 0), r=0.25)
    box('roof', W - 0.3, 0.25, L - 0.9, paint, root, (0, 2.98, 0), r=0.1)
    box('stripe', W + 0.02, 0.12, L - 0.2, red, root, (0, 1.5, 0), r=0.04)
    for side in (-1, 1):
        for i in range(5):
            box('win%d%d' % (side, i), 0.04, 0.85, 1.05, glass, root, (side * (W / 2 - 0.01), 2.25, -2.8 + i * 1.4), r=0.03)
    for z in (-1, 1):
        box('front%d' % z, 2.0, 0.9, 0.04, glass, root, (0, 2.3, z * (L / 2 - 0.13)), r=0.05)
        part('lamp%d' % z, bm_sphere(0.16, 12, 8), glowmat('cx_tramlamp', 0xffe2a0, 3), root, at=(0.75, 1.15, z * (L / 2 + 0.05)))
        part('lamp2%d' % z, bm_sphere(0.16, 12, 8), glowmat('cx_tramlamp', 0xffe2a0, 3), root, at=(-0.75, 1.15, z * (L / 2 + 0.05)))
    for z in (-2.8, 2.8):
        box('bogie' + str(z), W - 0.4, 0.35, 1.8, dark, root, (0, 0.28, z), r=0.06)
        for x in (-0.8, 0.8):
            for dz in (-0.55, 0.55):
                cyl('wh%s%s%s' % (z, x, dz), 0.26, 0.26, 0.12, steel, root, (x, 0.26, z + dz), rot=(0, 0, math.pi / 2))
    # pantograph to the overhead cable
    box('panto_base', 0.9, 0.12, 0.9, dark, root, (0, 3.15, 0))
    for s in (-1, 1): box('panto%d' % s, 0.06, 1.2, 0.06, steel, root, (0, 3.6, s * 0.25), rot=(s * 0.6, 0, 0))
    box('panto_bar', 1.3, 0.06, 0.1, steel, root, (0, 4.05, 0))
    done(root, 'tram_car', cam=(7.5, 4.5, 8.0), look=(0, 1.4, 0))

def gondola():
    reset(); root = empty('gondola')
    paint = M('gondola_yellow', 0xf0b429, 0.2, 0.4); dark = M('dark', 0x2b2f36, 0.4, 0.5); glass = M('glass', 0x9fd7ea, 0.2, 0.08)
    steel = M('steel', 0xb8c0c8, 0.9, 0.3)
    box('cabin', 2.2, 1.9, 2.6, paint, root, (0, 0.95, 0), r=0.3)
    box('roof', 1.8, 0.25, 2.2, dark, root, (0, 2.0, 0), r=0.08)
    for s in (-1, 1):
        box('win_s%d' % s, 0.04, 0.8, 2.0, glass, root, (s * 1.1, 1.25, 0), r=0.04)
        box('win_f%d' % s, 1.7, 0.8, 0.04, glass, root, (0, 1.25, s * 1.3), r=0.04)
    box('arm', 0.16, 2.2, 0.16, steel, root, (0, 3.2, 0))
    box('trolley', 0.5, 0.35, 1.4, dark, root, (0, 4.35, 0), r=0.05)
    for z in (-0.45, 0.45): cyl('wheel' + str(z), 0.18, 0.18, 0.1, steel, root, (0, 4.6, z), rot=(0, 0, math.pi / 2))
    done(root, 'gondola', cam=(4.0, 3.0, 5.0), look=(0, 1.8, 0))

def rubble():
    reset(); root = empty('rubble')
    stone = M('rubble', 0xb9ab95, 0.0, 0.9); stone2 = M('rubble2', 0x8f8676, 0.0, 0.9); steel = M('steel_rust', 0x8a5a3c, 0.6, 0.6)
    import random
    rnd = random.Random(7)
    for i in range(11):
        a = rnd.random() * math.tau; r = rnd.random() * 1.1
        s = 0.25 + rnd.random() * 0.45
        box('chunk%d' % i, s * 1.3, s * 0.7, s, stone if i % 2 else stone2, root, (math.cos(a) * r, s * 0.3, math.sin(a) * r),
            rot=(rnd.uniform(-0.4, 0.4), rnd.uniform(0, 3), rnd.uniform(-0.4, 0.4)), r=0.05)
    for i in range(3):
        box('rebar%d' % i, 0.05, 0.05, 1.6, steel, root, (rnd.uniform(-0.5, 0.5), 0.35, rnd.uniform(-0.5, 0.5)),
            rot=(rnd.uniform(-0.5, 0.5), rnd.uniform(0, 3), 0))
    done(root, 'rubble', cam=(2.4, 1.8, 2.8), look=(0, 0.3, 0))

suitcase('suitcase_teal', 0x2f9c95)
suitcase('suitcase_coral', 0xe2604a)
suitcase('suitcase_mustard', 0xe0a832, w=0.48, h=0.62)
duffel()
luggage_cart()
sawhorse()
sandbags()
cone()
sign_bent()
stall_wreck()
tram_car()
gondola()
rubble()
