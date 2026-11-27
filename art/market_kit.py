"""The Market kit: set dressing for the Market Terrace and the Spice Bazaar (godot/models/market/<name>.glb).

Built with the Skyharbor kit's Prop builder (art/skyharbor_kit.py): beveled primitives with hardened normals,
joined into one mesh per prop, k_<kind>_<rrggbb> material names that godot/scripts/mats.gd swaps for the game's
textured materials (wood grain, woven cloth, brass, painted metal, ...). Game space: Y up, +Z is the prop's
front, origin on the floor at the footprint centre.

Placed by godot/scripts/level/terrace/market_look.gd (the market build-up, a late area file).

Run: python3 art/market_kit.py [prop names...]      (pip bpy 5.3 works headless)
"""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import skyharbor_kit as sk
from skyharbor_kit import Prop, K, box, cyl, tor, sph, rod, RX, RZ, TAU
import bmesh
from mathutils import Vector, Matrix, Euler, noise

sk.OUT = os.path.normpath(os.path.join(HERE, '..', 'godot', 'models', 'market'))
sk.PARAMS['plaster'] = (0.0, 0.9)   # k_plaster_*: weathered plaster (mats.worn in market_look.gd)
os.makedirs(sk.OUT, exist_ok=True)

# ---------------- palette (warm market colours; cloth colours match tkit.gd CLOTH) ----------------
WOOD, WOOD_DK, WOOD_LT, WOOD_GREY = 0xb07a48, 0x7a5233, 0xc89a64, 0x9a8670
SAFFRON, CRIMSON, TEAL, PLUM, CREAM, SKY, GREEN = 0xf2b33d, 0xc8453a, 0x2f9e9b, 0x7d4e8e, 0xf1e3c6, 0x5f9fd0, 0x5c9a4c
CLAY, CLAY_DK, IRON, BRASS = 0xc8724a, 0x9a5236, 0x3a3f46, 0xd9a441
BURLAP = 0xc9a777
ORANGE, LEMON, APPLE, LIME, PLUMF, MELON = 0xf2862a, 0xf2cf3a, 0xd23b2e, 0x8cc04a, 0x6b2e6e, 0x5f9a3a
SPICES = [0xc8321f, 0xf0a020, 0xe8c832, 0x8a5a2a, 0x6a9a34]


# ---------------- shapes ----------------
def lathe(profile, seg=16, cap_top=True, cap_bot=True):
    """A surface of revolution about Y from [(r, y), ...] (bottom to top)."""
    bm = bmesh.new(); rings = []
    for r, y in profile:
        rings.append([bm.verts.new((math.cos(TAU * i / seg) * r, y, math.sin(TAU * i / seg) * r)) for i in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap_bot and profile[0][0] > 1e-4: bm.faces.new(list(reversed(rings[0])))
    if cap_top and profile[-1][0] > 1e-4: bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def lumpy(bm, amp, freq, seed=0.0, flat_bottom=None):
    for v in bm.verts:
        n = noise.noise(Vector((v.co.x * freq + seed, v.co.y * freq, v.co.z * freq - seed)))
        v.co += v.co.normalized() * n * amp if v.co.length > 1e-5 else Vector()
        if flat_bottom is not None and v.co.y < flat_bottom: v.co.y = flat_bottom
    return bm


def cloth_grid(w, d, nx, nz, sag, scallop=0.0, droop_front=0.0):
    """A cloth sheet in XZ (centre origin) that sags in the middle; optional scalloped hem along +Z."""
    bm = bmesh.new(); vs = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            u, v = i / nx, j / nz
            x, z = (u - 0.5) * w, (v - 0.5) * d
            y = -sag * math.sin(u * math.pi) * math.sin(v * math.pi) - droop_front * v * v
            if scallop and j == nz: z += scallop * abs(math.sin(u * math.pi * 6))
            row.append(bm.verts.new((x, y, z)))
        vs.append(row)
    for j in range(nz):
        for i in range(nx):
            bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.y < 0: f.normal_flip()
    return bm


def fruit(p, at, r, c, seg=10):
    sph(p, r, K('paint', c), at, seg=seg, rings=6)


def fruit_fill(p, rnd, cx, cz, w, d, y, r, cols, n):
    for k in range(n):
        x = cx + (rnd.random() - 0.5) * (w - r * 2)
        z = cz + (rnd.random() - 0.5) * (d - r * 2)
        fruit(p, (x, y + rnd.random() * r * 0.8, z), r * (0.85 + rnd.random() * 0.3), cols[k % len(cols)], seg=8)


# ================================================================== goods
def slat_crate(p, at=(0, 0, 0), yaw=0.0, w=0.62, h=0.42, d=0.44, c=WOOD, fill=None, rnd=None, tilt=(0, 0)):
    """An open slatted produce crate; fill = list of fruit colours."""
    ox, oy, oz = at
    R = Euler((tilt[0], yaw, tilt[1]), 'XYZ').to_matrix()
    def P(x, y, z): return tuple(Vector((ox, oy, oz)) + R @ Vector((x, y, z)))
    m = K('wood', c); mdk = K('wood', WOOD_DK)
    box(p, (w, 0.03, d), m, P(0, 0.03, 0), mat3=R, b=0.008)
    for y in (0.1, 0.24, 0.37):
        if y > h: continue
        for s in (-1, 1):
            box(p, (w, 0.09, 0.022), m, P(0, y, s * (d / 2 - 0.011)), mat3=R, b=0.006)
            box(p, (0.022, 0.09, d), m, P(s * (w / 2 - 0.011), y, 0), mat3=R, b=0.006)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(p, (0.045, h, 0.045), mdk, P(sx * (w / 2 - 0.02), h / 2, sz * (d / 2 - 0.02)), mat3=R, b=0.008)
    if fill and rnd:
        r = 0.065
        for k in range(14):
            x = (rnd.random() - 0.5) * (w - 0.14); z = (rnd.random() - 0.5) * (d - 0.14)
            sph(p, r * (0.85 + rnd.random() * 0.3), K('paint', fill[k % len(fill)]), P(x, h - 0.04 + rnd.random() * 0.05, z), seg=8, rings=5)


def crate_fruit():
    p = Prop('mk_crate_fruit'); rnd = random.Random(3)
    slat_crate(p, (0, 0, 0), 0.0, fill=[ORANGE, ORANGE, LEMON], rnd=rnd)
    p.finish()


def crate_stack():
    """three crates stacked, the top one half full of apples"""
    p = Prop('mk_crate_stack'); rnd = random.Random(5)
    slat_crate(p, (-0.33, 0, 0), 0.05, fill=[LIME, APPLE], rnd=rnd)
    slat_crate(p, (0.34, 0, 0.02), -0.08, fill=[ORANGE], rnd=rnd)
    slat_crate(p, (0.02, 0.43, 0.0), 0.12, c=WOOD_LT, fill=[APPLE, APPLE, LEMON], rnd=rnd)
    p.finish()


def crate_spill():
    """a crate on its side with fruit rolled out across the floor"""
    p = Prop('mk_crate_spill'); rnd = random.Random(9)
    slat_crate(p, (0, 0.22, 0), 0.3, tilt=(math.pi / 2 - 0.05, 0))
    for k in range(18):
        a = -0.6 + rnd.random() * 1.6; r = 0.35 + rnd.random() * 1.3
        fruit(p, (math.sin(a) * r * 0.9, 0.06, 0.25 + math.cos(a) * r), 0.06 + rnd.random() * 0.015, [ORANGE, LEMON, APPLE][k % 3], seg=8)
    p.finish()


def barrel():
    p = Prop('mk_barrel')
    prof = [(0.27, 0.0), (0.31, 0.2), (0.33, 0.42), (0.31, 0.64), (0.27, 0.84)]
    p.add(lathe(prof, 18), K('wood', WOOD), b=0.0, angle=50)
    for y, r in ((0.08, 0.29), (0.25, 0.322), (0.59, 0.322), (0.76, 0.29)):
        tor(p, r, 0.012, K('metal', IRON), (0, y, 0), seg=24, tube=5)
    cyl(p, 0.265, 0.025, K('wood', WOOD_DK), (0, 0.83, 0), seg=18, b=0.006)
    for i in range(18):   # stave grooves
        a = TAU * i / 18
        box(p, (0.006, 0.8, 0.012), K('wood', WOOD_DK), (math.cos(a) * 0.318, 0.42, math.sin(a) * 0.318), rot=(0, -a, 0), b=0)
    p.finish()


def barrels_open():
    """two barrels, one open and full of pickled somethings, a scoop leaning on it"""
    p = Prop('mk_barrels')
    prof = [(0.27, 0.0), (0.31, 0.2), (0.33, 0.42), (0.31, 0.64), (0.27, 0.84)]
    for x, ry in ((-0.36, 0.0), (0.36, 0.5)):
        p.add(lathe([(r, y) for r, y in prof], 18, cap_top=(x > 0)), K('wood', WOOD), at=(x, 0, 0), b=0.0, angle=50)
        for y, r in ((0.08, 0.29), (0.25, 0.322), (0.59, 0.322), (0.76, 0.29)):
            tor(p, r, 0.012, K('metal', IRON), (x, y, 0), seg=24, tube=5)
    cyl(p, 0.255, 0.04, K('soil', 0x6a8a2a), (-0.36, 0.76, 0), seg=18, b=0)
    for k in range(8):
        a = k * 2.1
        sph(p, 0.05, K('paint', 0x7aa03a), (-0.36 + math.cos(a) * 0.14, 0.79, math.sin(a) * 0.14), scale=(1, 0.7, 1.6), seg=8, rings=5)
    cyl(p, 0.265, 0.025, K('wood', WOOD_DK), (0.36, 0.83, 0), seg=18, b=0.006)
    rod(p, (-0.62, 0.0, 0.18), (-0.5, 0.9, 0.08), 0.018, K('wood', WOOD_DK))
    cyl(p, 0.07, 0.08, K('metal', 0x9aa4ae), (-0.62, 0.06, 0.2), rot=(0.3, 0, 0), seg=12, b=0.005)
    p.finish()


def sack(p, at, h=0.62, r=0.24, c=BURLAP, seed=0.0, open_=None, lean=0.0):
    prof = [(r * 0.75, 0.0), (r, 0.08), (r * 1.08, h * 0.35), (r * 1.02, h * 0.7), (r * 0.7, h * 0.88), (r * 0.32, h * 0.95)]
    if open_ is not None:
        prof = [(r * 0.75, 0.0), (r, 0.08), (r * 1.08, h * 0.4), (r * 1.06, h * 0.72), (r * 1.14, h * 0.8)]
    bm = lumpy(lathe(prof, 14, cap_top=open_ is None), r * 0.12, 3.2, seed, flat_bottom=0.0)
    p.add(bm, K('cloth', c), at=at, rot=(lean, seed, 0), angle=60)
    if open_ is None:
        cyl(p, r * 0.34, 0.08, K('cloth', c), (at[0], at[1] + h * 0.98, at[2]), r2=r * 0.5, seg=10, b=0)
        tor(p, r * 0.33, 0.018, K('cloth', 0x8a6a42), (at[0], at[1] + h * 0.94, at[2]), seg=14, tube=5)
    else:
        mound = lumpy(lathe([(r * 1.05, 0.0), (r * 0.8, 0.07), (r * 0.4, 0.12), (0.001, 0.14)], 14, cap_bot=False), 0.012, 9, seed)
        p.add(mound, K('soil', open_), at=(at[0], at[1] + h * 0.74, at[2]), angle=70)
        tor(p, r * 1.12, 0.035, K('cloth', c), (at[0], at[1] + h * 0.8, at[2]), seg=16, tube=6)


def sacks():
    p = Prop('mk_sacks')
    sack(p, (-0.3, 0, 0), seed=0.3)
    sack(p, (0.28, 0, 0.05), h=0.55, seed=1.7, open_=SPICES[0])
    sack(p, (0.0, 0, -0.42), h=0.5, r=0.26, seed=2.9, open_=SPICES[1])
    sack(p, (-0.05, 0.08, 0.42), h=0.5, r=0.22, seed=4.2, lean=-1.35)
    p.finish()


def spice_sacks():
    """a row of open spice sacks with scoops, the classic bazaar front"""
    p = Prop('mk_spice_sacks')
    for i in range(5):
        x = -1.0 + i * 0.5
        sack(p, (x, 0, (i % 2) * 0.12), h=0.5 + (i % 3) * 0.05, r=0.21, seed=i * 1.3, open_=SPICES[i % len(SPICES)])
        if i % 2 == 0:
            rod(p, (x + 0.05, 0.5, (i % 2) * 0.12), (x + 0.16, 0.75, (i % 2) * 0.12 + 0.05), 0.012, K('brass'))
    box(p, (2.6, 0.08, 0.7), K('wood', WOOD_DK), (0, -0.02, 0.05), b=0.01)
    p.finish()


def jars():
    """a cluster of clay jars and an amphora"""
    p = Prop('mk_jars')
    amph = [(0.08, 0.0), (0.17, 0.08), (0.24, 0.3), (0.22, 0.5), (0.12, 0.66), (0.08, 0.72), (0.11, 0.78)]
    p.add(lathe(amph, 16, cap_top=False), K('paint', CLAY), at=(0, 0, 0), angle=50)
    for s in (-1, 1): tor(p, 0.08, 0.016, K('paint', CLAY), (s * 0.15, 0.6, 0), rot=(math.pi / 2, 0, 0), seg=12, tube=5, arc=math.pi)
    jar = [(0.1, 0.0), (0.18, 0.1), (0.2, 0.25), (0.14, 0.38), (0.12, 0.42), (0.14, 0.45)]
    p.add(lathe(jar, 14, cap_top=False), K('paint', CLAY_DK), at=(0.38, 0, 0.12), angle=50)
    p.add(lathe([(r * 0.7, y * 0.7) for r, y in jar], 14), K('paint', 0x2f7f86), at=(0.2, 0, 0.36), angle=50)
    p.add(lathe([(r * 0.8, y * 0.8) for r, y in jar], 14, cap_top=False), K('paint', CLAY), at=(-0.32, 0, 0.25), angle=50)
    for x, z in ((0.38, 0.12), (-0.32, 0.25)): tor(p, 0.13 if x > 0 else 0.11, 0.012, K('paint', CREAM), (x, 0.2 if x > 0 else 0.16, z), seg=16, tube=4)
    p.finish()


def basket(p, at, r=0.26, h=0.22, fill=None, rnd=None):
    m = K('wood', 0xc79a5a); m2 = K('wood', 0x9a6e3a)
    for i in range(5):
        tor(p, r * (0.85 + 0.15 * i / 4), 0.022, m if i % 2 else m2, (at[0], at[1] + 0.03 + i * h / 5, at[2]), seg=20, tube=5)
    cyl(p, r * 0.84, 0.03, m2, (at[0], at[1] + 0.015, at[2]), seg=16, b=0)
    tor(p, r * 0.6, 0.016, m2, (at[0], at[1] + h, at[2]), rot=(math.pi / 2, 0, 0), seg=16, tube=4, arc=math.pi)
    if fill and rnd:
        for k in range(9):
            a = rnd.random() * TAU; rr = rnd.random() * r * 0.6
            fruit(p, (at[0] + math.cos(a) * rr, at[1] + h - 0.02 + rnd.random() * 0.04, at[2] + math.sin(a) * rr), 0.06, fill[k % len(fill)], seg=8)


def baskets():
    p = Prop('mk_baskets'); rnd = random.Random(11)
    basket(p, (-0.3, 0, 0), fill=[APPLE, LEMON], rnd=rnd)
    basket(p, (0.3, 0, 0.1), r=0.22, fill=[PLUMF, LIME], rnd=rnd)
    basket(p, (0.0, 0, -0.38), r=0.3, h=0.18, fill=[ORANGE], rnd=rnd)
    p.finish()


def rug_rolls():
    """rolled carpets standing in a rack and lying in a pile"""
    p = Prop('mk_rug_rolls')
    cols = [CRIMSON, TEAL, SAFFRON, PLUM, SKY, CREAM]
    for i in range(5):
        x = -0.8 + i * 0.38
        cyl(p, 0.13, 1.7 + (i % 3) * 0.2, K('cloth', cols[i]), (x, 0.9 + (i % 3) * 0.1, -0.1), rot=(0.0, 0, 0.1 * (i - 2)), seg=12, b=0.01)
        tor(p, 0.13, 0.018, K('cloth', cols[(i + 2) % 6]), (x, 1.2, -0.1), seg=12, tube=4)
    for s in (-1, 1): box(p, (0.08, 1.3, 0.08), K('wood', WOOD_DK), (s * 1.05, 0.65, -0.3), b=0.01)
    box(p, (2.2, 0.08, 0.08), K('wood', WOOD_DK), (0, 1.25, -0.3), b=0.01)
    for i in range(3):
        cyl(p, 0.14, 1.9, K('cloth', cols[(i + 3) % 6]), (-0.2 + i * 0.12, 0.14 + i * 0.26 if i < 2 else 0.38, 0.45 + (i % 2) * 0.28), rot=(0, 0.3 * i, math.pi / 2), seg=12, b=0.01)
    p.finish()


# ================================================================== furniture and fittings
def trestle(p, at=(0, 0, 0), w=1.8, d=0.8, h=0.82, c=WOOD):
    x0, y0, z0 = at
    box(p, (w, 0.06, d), K('wood', c), (x0, y0 + h, z0), b=0.012)
    for s in (-1, 1):
        for t in (-1, 1):
            rod(p, (x0 + s * (w / 2 - 0.2), y0, z0 + t * (d / 2 - 0.05)), (x0 + s * (w / 2 - 0.25), y0 + h - 0.03, z0), 0.03, K('wood', WOOD_DK))
        box(p, (0.05, 0.05, d - 0.1), K('wood', WOOD_DK), (x0 + s * (w / 2 - 0.25), y0 + h - 0.06, z0), b=0.005)


def produce_table():
    """a trestle table piled with crates, baskets and loose produce, a striped cloth over the front"""
    p = Prop('mk_produce_table'); rnd = random.Random(21)
    trestle(p, (0, 0, 0), 2.0, 0.9)
    p.add(cloth_grid(2.06, 0.5, 12, 3, 0.0, 0.03), K('cloth', CREAM), at=(0, 0.6, 0.45), rot=(-math.pi / 2 + 0.05, 0, 0))
    for i in range(6): box(p, (0.12, 0.5, 0.004), K('cloth', CRIMSON), (-0.85 + i * 0.34, 0.62, 0.465), b=0)
    slat_crate(p, (-0.6, 0.85, -0.05), 0.1, fill=[APPLE, APPLE, LEMON], rnd=rnd, h=0.3)
    slat_crate(p, (0.05, 0.85, 0.0), -0.05, fill=[ORANGE], rnd=rnd, h=0.3)
    basket(p, (0.65, 0.85, 0.05), r=0.24, fill=[LIME, PLUMF], rnd=rnd)
    for k in range(10): fruit(p, (-0.9 + k * 0.18, 0.92, 0.32), 0.07, [MELON, LEMON, APPLE][k % 3])
    slat_crate(p, (0.55, 0, 0.1), 0.2, fill=[ORANGE, LEMON], rnd=rnd)
    sack(p, (-0.55, 0, 0.05), h=0.5, r=0.2, seed=5.1)
    p.finish()


def spice_shelf():
    """a tall open shelf rack of spice jars, pots and bundles (stands against a wall or a stall back)"""
    p = Prop('mk_spice_shelf'); rnd = random.Random(31)
    w, h, d = 1.6, 2.1, 0.45
    for s in (-1, 1): box(p, (0.06, h, d), K('wood', WOOD_DK), (s * w / 2, h / 2, 0), b=0.01)
    box(p, (w, h, 0.03), K('wood', WOOD), (0, h / 2, -d / 2), b=0.005)
    for i, y in enumerate((0.05, 0.6, 1.15, 1.7, h)):
        box(p, (w, 0.04, d), K('wood', WOOD_DK), (0, y, 0), b=0.006)
        if y >= h: continue
        n = 5
        for k in range(n):
            x = -w / 2 + 0.18 + k * (w - 0.36) / (n - 1)
            kind = (k + i) % 3
            if kind == 0:
                p.add(lathe([(0.08, 0), (0.1, 0.04), (0.1, 0.22), (0.07, 0.26), (0.075, 0.3)], 12), K('glass', 0xd8f0e8), at=(x, y + 0.02, 0.02), angle=60)
                cyl(p, 0.085, 0.14, K('soil', SPICES[(k + i) % 5]), (x, y + 0.1, 0.02), seg=12, b=0)
            elif kind == 1:
                p.add(lathe([(0.1, 0), (0.14, 0.08), (0.13, 0.2), (0.08, 0.28), (0.09, 0.31)], 12, cap_top=False), K('paint', [CLAY, 0x2f7f86, CLAY_DK][k % 3]), at=(x, y + 0.02, 0.02), angle=50)
            else:
                for b in range(3):
                    cyl(p, 0.05, 0.12, K('paint', [0xc84030, 0xe8a030, 0xd8c050][b]), (x - 0.08 + b * 0.08, y + 0.08, 0.06), rot=(0, 0, 0), seg=8, b=0.004)
    # chilli and garlic strings hanging from the top
    for s in (-1, 1):
        for k in range(7):
            sph(p, 0.04, K('paint', 0xc8321f if s < 0 else 0xf2ead8), (s * (w / 2 - 0.12), h - 0.15 - k * 0.11, d / 2 + 0.04), scale=(1, 1.6 if s < 0 else 1, 1), seg=8, rings=5)
    p.finish()


def canopy_stall(name, c1, c2, goods):
    """an open market stall: timber frame, a sagging striped canopy with a scalloped hem, a counter of goods,
    strings of chillies and garlic and a hanging lamp. 3 m wide, counter along +Z."""
    p = Prop(name); rnd = random.Random(hash(name) & 0xffff)
    W, D = 3.0, 2.2
    for sx in (-1, 1):
        for sz in (-1, 1):
            hh = 2.75 if sz > 0 else 3.05
            box(p, (0.11, hh, 0.11), K('wood', WOOD_DK), (sx * W / 2, hh / 2, sz * D / 2), b=0.015)
            box(p, (0.2, 0.1, 0.2), K('wood', WOOD_DK), (sx * W / 2, 0.05, sz * D / 2), b=0.015)
        box(p, (0.09, 0.09, D + 0.2), K('wood', WOOD), (sx * W / 2, 2.8, 0), rot=(0.12, 0, 0), b=0.01)
    for sz in (-1, 1): box(p, (W + 0.2, 0.09, 0.09), K('wood', WOOD), (0, 2.68 if sz > 0 else 2.98, sz * D / 2), b=0.01)
    # canopy: stripes of two colours, sagging between the beams and sloping to the front, scalloped front hem
    nst = 6
    for i in range(nst):
        sw = W / nst
        x = -W / 2 + sw * (i + 0.5)
        bm = cloth_grid(sw + 0.01, D + 0.5, 3, 8, 0.08, 0.0)
        p.add(bm, K('cloth', c1 if i % 2 == 0 else c2), at=(x, 2.96, 0.1), rot=(0.13, 0, 0))
    for i in range(nst * 2):
        x = -W / 2 + W / (nst * 2) * (i + 0.5)
        bm = bmesh.new()
        vs = [bm.verts.new(v) for v in ((-0.13, 0, 0), (0.13, 0, 0), (0.1, -0.2, 0), (0.0, -0.28, 0), (-0.1, -0.2, 0))]
        bm.faces.new(vs)
        p.add(bm, K('cloth', c2 if i % 2 == 0 else c1), at=(x, 2.66, D / 2 + 0.38), rot=(0.1, 0, 0), smooth=False)
    # counter with goods
    box(p, (W - 0.2, 0.9, 0.7), K('wood', WOOD), (0, 0.45, D / 2 - 0.4), b=0.02)
    box(p, (W, 0.07, 0.86), K('wood', WOOD_DK), (0, 0.93, D / 2 - 0.38), b=0.012)
    for i in range(5): box(p, (0.03, 0.8, 0.02), K('wood', WOOD_DK), (-1.2 + i * 0.6, 0.45, D / 2 - 0.04), b=0)
    if goods == 'fruit':
        slat_crate(p, (-0.9, 0.97, -0.0 + D / 2 - 0.4), 0.1, fill=[ORANGE, LEMON], rnd=rnd, h=0.28)
        slat_crate(p, (0.0, 0.97, D / 2 - 0.4), -0.05, fill=[APPLE, APPLE, LIME], rnd=rnd, h=0.28)
        basket(p, (0.9, 0.97, D / 2 - 0.4), r=0.25, fill=[PLUMF, LEMON], rnd=rnd)
    elif goods == 'spice':
        for k in range(5):
            x = -1.15 + k * 0.575
            cyl(p, 0.2, 0.08, K('paint', CLAY), (x, 1.0, D / 2 - 0.4), seg=14, b=0.01)
            p.add(lumpy(lathe([(0.19, 0), (0.13, 0.07), (0.06, 0.12), (0.001, 0.14)], 12, cap_bot=False), 0.01, 10, k), K('soil', SPICES[k]), at=(x, 1.04, D / 2 - 0.4), angle=70)
    elif goods == 'pots':
        for k in range(4):
            x = -1.1 + k * 0.73
            p.add(lathe([(0.1, 0), (0.17, 0.1), (0.18, 0.24), (0.1, 0.36), (0.12, 0.4)], 14, cap_top=False), K('paint', [CLAY, 0x2f7f86, CLAY_DK, CREAM][k]), at=(x, 0.97, D / 2 - 0.4), angle=50)
    elif goods == 'cloth':
        for k in range(6):
            cyl(p, 0.11, 0.6, K('cloth', [CRIMSON, TEAL, SAFFRON, PLUM, SKY, CREAM][k]), (-1.1 + k * 0.44, 1.08, D / 2 - 0.4), rot=(math.pi / 2, 0, 0), seg=10, b=0.01)
    # back shelf
    box(p, (W - 0.2, 0.05, 0.4), K('wood', WOOD_DK), (0, 1.5, -D / 2 + 0.25), b=0.008)
    for k in range(6):
        x = -1.2 + k * 0.48
        p.add(lathe([(0.07, 0), (0.1, 0.06), (0.1, 0.2), (0.06, 0.26)], 10), K('paint', [CLAY, 0x2f7f86, CREAM][k % 3]), at=(x, 1.53, -D / 2 + 0.25), angle=50)
    # strings of chillies and garlic under the front beam
    for k, x in enumerate((-1.1, -0.35, 0.4, 1.15)):
        red = k % 2 == 0
        for j in range(6):
            sph(p, 0.038, K('paint', 0xc8321f if red else 0xf2ead8), (x + 0.02 * math.sin(j), 2.55 - j * 0.1, D / 2), scale=(1, 1.7 if red else 1, 1), seg=8, rings=5)
    # a hanging lamp
    rod(p, (0, 2.7, D / 2 - 0.5), (0, 2.35, D / 2 - 0.5), 0.01, K('metal', IRON))
    cyl(p, 0.1, 0.2, K('brass'), (0, 2.25, D / 2 - 0.5), r2=0.06, seg=10, b=0.005)
    sph(p, 0.08, K('glow', 0xffa640), (0, 2.12, D / 2 - 0.5), seg=10, rings=6)
    p.mark('light_0', (0, 2.0, D / 2 - 0.5))
    # sacks and a crate round the front
    sack(p, (-1.6, 0, D / 2 + 0.35), h=0.52, r=0.2, seed=1.1, open_=SPICES[rnd.randrange(5)])
    slat_crate(p, (1.65, 0, D / 2 + 0.2), 0.3, fill=[ORANGE, APPLE], rnd=rnd)
    p.finish()


def canopy_stalls():
    canopy_stall('mk_stall_fruit', CRIMSON, CREAM, 'fruit')
    canopy_stall('mk_stall_spice', SAFFRON, CRIMSON, 'spice')
    canopy_stall('mk_stall_pots', TEAL, CREAM, 'pots')
    canopy_stall('mk_stall_cloth', PLUM, SAFFRON, 'cloth')


def canopy_collapsed():
    """a stall whose frame gave way in the stampede: canopy slumped over the counter, goods everywhere"""
    p = Prop('mk_stall_collapsed'); rnd = random.Random(77)
    W, D = 3.0, 2.2
    box(p, (W - 0.2, 0.9, 0.7), K('wood', WOOD), (0, 0.45, 0.7), b=0.02)
    for sx in (-1, 1):
        box(p, (0.11, 3.05, 0.11), K('wood', WOOD_DK), (sx * W / 2, 1.52, -D / 2), b=0.015)
    box(p, (0.11, 2.75, 0.11), K('wood', WOOD_DK), (-W / 2, 1.0, D / 2 + 0.6), rot=(1.15, 0, 0.1), b=0.015)
    box(p, (0.11, 2.75, 0.11), K('wood', WOOD_DK), (W / 2 + 0.3, 0.12, D / 2 + 0.2), rot=(0.1, 0.4, math.pi / 2), b=0.015)
    for i in range(6):
        bm = cloth_grid(0.51, D + 0.6, 3, 10, -0.0, 0.0, droop_front=2.0)
        lumpy(bm, 0.06, 2.0, i)
        p.add(bm, K('cloth', CRIMSON if i % 2 == 0 else CREAM), at=(-1.25 + i * 0.5, 3.0, -0.6), rot=(0.25, 0, 0.05 * (i - 3)))
    for k in range(22):
        a = rnd.random() * math.pi - math.pi / 2; r = 0.6 + rnd.random() * 1.6
        fruit(p, (math.sin(a) * r * 1.3, 0.065, 1.4 + math.cos(a) * r * 0.7), 0.065, [ORANGE, APPLE, LEMON, LIME][k % 4], seg=8)
    slat_crate(p, (-1.3, 0.22, 1.5), 0.6, tilt=(math.pi / 2, 0))
    slat_crate(p, (1.0, 0, 1.7), -0.4)
    sack(p, (0.2, 0.1, 1.8), h=0.5, r=0.21, seed=3.3, lean=1.4)
    p.finish()


def blade_sign(name, c):
    """a hanging shop sign on a wall bracket (the lettering is a Label3D in the game); faces +X and -X"""
    p = Prop(name)
    rod(p, (0, 2.6, 0), (0, 2.6, 1.1), 0.025, K('metal', IRON))
    rod(p, (0, 2.2, 0), (0, 2.6, 0.7), 0.02, K('metal', IRON))
    tor(p, 0.1, 0.012, K('metal', IRON), (0, 2.6, 1.15), rot=(0, math.pi / 2, 0), seg=12, tube=4)
    for z in (0.35, 0.95): rod(p, (0, 2.58, z), (0, 2.42, z), 0.008, K('metal', IRON))
    box(p, (0.07, 0.62, 0.9), K('wood', c), (0, 2.1, 0.65), b=0.02)
    box(p, (0.09, 0.66, 0.06), K('brass'), (0, 2.1, 0.2), b=0.01)
    box(p, (0.09, 0.66, 0.06), K('brass'), (0, 2.1, 1.1), b=0.01)
    box(p, (0.1, 0.1, 0.1), K('metal', IRON), (0, 2.6, -0.02), b=0.01)
    p.finish()


def blade_signs():
    blade_sign('mk_sign_teal', 0x2f7f86)
    blade_sign('mk_sign_red', 0x9a3a2e)


def parasol(name, c1, c2):
    """a big market umbrella on a weighted base (tip it over in the game for the panic look)"""
    p = Prop(name)
    n = 8; R = 1.5; top = 2.55
    cyl(p, 0.035, top + 0.1, K('wood', WOOD_DK), (0, (top + 0.1) / 2, 0), seg=10, b=0.004)
    cyl(p, 0.3, 0.12, K('paint', 0x4a4f56), (0, 0.06, 0), r2=0.2, seg=16, b=0.02)
    for i in range(n):
        a0, a1 = TAU * i / n, TAU * (i + 1) / n
        bm = bmesh.new()
        tip = bm.verts.new((0, top + 0.05, 0))
        ring = []
        for k in range(5):
            a = a0 + (a1 - a0) * k / 4
            rr = R * (1.0 - 0.06 * math.sin(math.pi * k / 4))
            ring.append(bm.verts.new((math.cos(a) * rr, top - 0.55 + 0.05 * math.sin(math.pi * k / 4), math.sin(a) * rr)))
        mid = [bm.verts.new((math.cos(a0 + (a1 - a0) * k / 4) * R * 0.55, top - 0.18, math.sin(a0 + (a1 - a0) * k / 4) * R * 0.55)) for k in range(5)]
        for k in range(4):
            bm.faces.new((mid[k], mid[k + 1], ring[k + 1], ring[k]))
            bm.faces.new((tip, mid[k + 1], mid[k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        for f in bm.faces:
            if f.normal.y < 0: f.normal_flip()
        p.add(bm, K('cloth', c1 if i % 2 == 0 else c2), angle=40)
        rod(p, (0, top - 0.6, 0), (math.cos(a0) * R * 0.98, top - 0.53, math.sin(a0) * R * 0.98), 0.012, K('wood', WOOD_DK))
        # hem flap
        flap = bmesh.new()
        vs = [flap.verts.new(v) for v in ((math.cos(a0) * R, top - 0.55, math.sin(a0) * R), (math.cos(a1) * R, top - 0.55, math.sin(a1) * R),
                                          (math.cos(a1) * R * 1.01, top - 0.72, math.sin(a1) * R * 1.01), (math.cos((a0 + a1) / 2) * R * 1.0, top - 0.78, math.sin((a0 + a1) / 2) * R * 1.0),
                                          (math.cos(a0) * R * 1.01, top - 0.72, math.sin(a0) * R * 1.01))]
        flap.faces.new(vs)
        p.add(flap, K('cloth', c2 if i % 2 == 0 else c1), smooth=False)
    sph(p, 0.06, K('brass'), (0, top + 0.1, 0), seg=10, rings=6)
    p.finish()


def parasols():
    parasol('mk_parasol_red', CRIMSON, CREAM)
    parasol('mk_parasol_teal', TEAL, SAFFRON)


def stools():
    """two stools and a little low table, one stool knocked over"""
    p = Prop('mk_stools')
    def stool(at, rot=(0, 0, 0)):
        R = Euler(rot, 'XYZ').to_matrix(); o = Vector(at)
        cyl(p, 0.2, 0.05, K('wood', WOOD), tuple(o + R @ Vector((0, 0.45, 0))), mat3=R, seg=14, b=0.01)
        for k in range(3):
            a = TAU * k / 3
            rod(p, tuple(o + R @ Vector((math.cos(a) * 0.17, 0.0, math.sin(a) * 0.17))), tuple(o + R @ Vector((math.cos(a) * 0.1, 0.43, math.sin(a) * 0.1))), 0.02, K('wood', WOOD_DK))
        cyl(p, 0.19, 0.04, K('cloth', CRIMSON), tuple(o + R @ Vector((0, 0.49, 0))), mat3=R, seg=14, b=0.012)
    stool((-0.55, 0, 0))
    stool((0.5, 0.2, 0.3), rot=(0, 0.5, math.pi / 2))
    cyl(p, 0.35, 0.04, K('wood', WOOD_DK), (0, 0.5, -0.4), seg=16, b=0.01)
    cyl(p, 0.04, 0.48, K('brass'), (0, 0.25, -0.4), seg=8, b=0)
    cyl(p, 0.2, 0.03, K('brass'), (0, 0.015, -0.4), seg=12, b=0)
    sph(p, 0.11, K('paint', TEAL), (0.05, 0.6, -0.4), scale=(1, 0.85, 1), seg=12, rings=8)
    cyl(p, 0.04, 0.04, K('paint', CREAM), (-0.15, 0.54, -0.3), seg=8, b=0)
    cyl(p, 0.04, 0.04, K('paint', CREAM), (0.35, 0.02, 0.2), rot=(math.pi / 2, 0, 0.3), seg=8, b=0)   # a dropped cup
    p.finish()


def lamp_post():
    """a wrought-iron market lamp post with two hanging lanterns"""
    p = Prop('mk_lamp_post'); ir = K('metal', 0x2e3238)
    cyl(p, 0.2, 0.3, ir, (0, 0.15, 0), r2=0.12, seg=12, b=0.01)
    cyl(p, 0.06, 3.6, ir, (0, 1.95, 0), r2=0.045, seg=10, b=0.004)
    for y in (0.4, 1.0, 3.3): tor(p, 0.07, 0.015, K('brass'), (0, y, 0), seg=14, tube=4)
    for s in (-1, 1):
        rod(p, (0, 3.5, 0), (s * 0.6, 3.5, 0), 0.025, ir)
        tor(p, 0.18, 0.015, ir, (s * 0.3, 3.32, 0), rot=(math.pi / 2, 0, 0), seg=12, tube=4, arc=math.pi / 2)
        rod(p, (s * 0.6, 3.5, 0), (s * 0.6, 3.3, 0), 0.01, ir)
        cyl(p, 0.14, 0.06, K('brass'), (s * 0.6, 3.27, 0), r2=0.06, seg=8, b=0)
        cyl(p, 0.11, 0.32, K('glow', 0xffa640), (s * 0.6, 3.07, 0), seg=8, b=0)
        for k in range(4):
            a = TAU * k / 4 + math.pi / 4
            rod(p, (s * 0.6 + math.cos(a) * 0.12, 3.24, math.sin(a) * 0.12), (s * 0.6 + math.cos(a) * 0.1, 2.9, math.sin(a) * 0.1), 0.01, K('brass'))
        cyl(p, 0.13, 0.05, K('brass'), (s * 0.6, 2.89, 0), seg=8, b=0)
        p.mark('light_%d' % (s + 1), (s * 0.6, 3.05, 0))
    sph(p, 0.07, K('brass'), (0, 3.78, 0), seg=10, rings=6)
    p.finish()


# ================================================================== vehicles
def wheel(p, at, r=0.42, w=0.06, spokes=8, axis_x=True, tilt=0.0):
    rot = (0, 0, math.pi / 2) if axis_x else (math.pi / 2, 0, 0)
    tor(p, r, w * 0.7, K('wood', WOOD_DK), at, rot=(0, tilt, math.pi / 2) if axis_x else (math.pi / 2, tilt, 0), seg=24, tube=6)
    tor(p, r + w * 0.55, w * 0.3, K('metal', IRON), at, rot=(0, tilt, math.pi / 2) if axis_x else (math.pi / 2, tilt, 0), seg=24, tube=4)
    cyl(p, 0.07, w * 2.2, K('metal', IRON), at, rot=rot, seg=10, b=0.005)
    for k in range(spokes):
        a = TAU * k / spokes
        d = Vector((0, math.cos(a), math.sin(a))) if axis_x else Vector((math.cos(a), math.sin(a), 0))
        o = Vector(at)
        rod(p, tuple(o + d * 0.06), tuple(o + d * (r - 0.02)), 0.018, K('wood', WOOD))


def handcart(name, tipped=False):
    """a two-wheeled market barrow loaded with crates and sacks; tipped=True: on its nose with the load spilled"""
    p = Prop(name); rnd = random.Random(41)
    if not tipped:
        bed_y = 0.62
        box(p, (1.1, 0.06, 1.7), K('wood', WOOD), (0, bed_y, 0), b=0.01)
        for s in (-1, 1):
            box(p, (0.04, 0.28, 1.7), K('wood', WOOD_LT), (s * 0.55, bed_y + 0.16, 0), b=0.006)
            for z in (-0.7, 0.0, 0.7): box(p, (0.06, 0.34, 0.06), K('wood', WOOD_DK), (s * 0.56, bed_y + 0.12, z), b=0.006)
            rod(p, (s * 0.45, bed_y - 0.02, -0.85), (s * 0.4, 0.75, -1.85), 0.035, K('wood', WOOD_DK))
            wheel(p, (s * 0.68, 0.48, 0.15), r=0.46)
            rod(p, (s * 0.45, bed_y - 0.03, -0.75), (s * 0.45, 0.0, -0.8), 0.03, K('wood', WOOD_DK))
        box(p, (1.1, 0.28, 0.04), K('wood', WOOD_LT), (0, bed_y + 0.16, 0.85), b=0.006)
        slat_crate(p, (-0.25, bed_y + 0.03, 0.4), 0.1, fill=[ORANGE, LEMON], rnd=rnd)
        slat_crate(p, (0.25, bed_y + 0.03, 0.35), -0.1, fill=[APPLE], rnd=rnd)
        slat_crate(p, (0.0, bed_y + 0.46, 0.4), 0.3, fill=[LIME, APPLE], rnd=rnd)
        sack(p, (-0.22, bed_y + 0.03, -0.35), h=0.55, r=0.22, seed=2.0)
        sack(p, (0.25, bed_y + 0.03, -0.4), h=0.5, r=0.2, seed=6.0, open_=SPICES[1])
    else:
        R = Euler((0.0, 0.0, 0.0), 'XYZ').to_matrix()
        # the cart is pitched forward onto its front board, handles in the air
        pitch = 0.75
        Rm = Euler((pitch, 0, 0), 'XYZ').to_matrix()
        o = Vector((0, 0.0, 0))
        def P(v): return tuple(o + Rm @ Vector(v))
        bed_y = 0.62
        box(p, (1.1, 0.06, 1.7), K('wood', WOOD), P((0, bed_y, 0)), mat3=Rm, b=0.01)
        for s in (-1, 1):
            box(p, (0.04, 0.28, 1.7), K('wood', WOOD_LT), P((s * 0.55, bed_y + 0.16, 0)), mat3=Rm, b=0.006)
            rod(p, P((s * 0.45, bed_y - 0.02, -0.85)), P((s * 0.4, 0.75, -1.85)), 0.035, K('wood', WOOD_DK))
            wheel(p, P((s * 0.68, 0.48, 0.15)), r=0.46)
        box(p, (1.1, 0.28, 0.04), K('wood', WOOD_LT), P((0, bed_y + 0.16, 0.85)), mat3=Rm, b=0.006)
        slat_crate(p, (-0.5, 0.0, 1.5), 0.7)
        slat_crate(p, (0.45, 0.22, 1.25), -0.3, tilt=(math.pi / 2, 0))
        sack(p, (0.1, 0.1, 1.95), h=0.55, r=0.22, seed=2.0, lean=1.45)
        for k in range(20):
            a = rnd.random() * math.pi - math.pi / 2; r = 0.4 + rnd.random() * 1.4
            fruit(p, (math.sin(a) * r, 0.065, 1.6 + math.cos(a) * r * 0.8), 0.065, [ORANGE, LEMON, APPLE, LIME][k % 4], seg=8)
    p.finish()


def handcarts():
    handcart('mk_handcart')
    handcart('mk_handcart_tipped', True)


def cargo_trike():
    """a three-wheeled delivery trike with a canvas-topped cargo box (painted, a bit battered)"""
    p = Prop('mk_cargo_trike')
    paint = K('paint', 0x2f8f8c); paint2 = K('paint', CREAM); dk = K('metal', 0x2e3238); rub = K('rubber', 0x26292e)
    # cargo box over the two rear wheels (rear is -Z)
    box(p, (1.3, 0.9, 1.2), paint, (0, 1.05, -0.55), b=0.04)
    box(p, (1.34, 0.12, 1.24), paint2, (0, 1.5, -0.55), b=0.03)
    box(p, (1.32, 0.08, 1.22), paint2, (0, 0.62, -0.55), b=0.02)
    p.add(cloth_grid(1.4, 1.3, 6, 6, -0.18), K('cloth', SAFFRON), at=(0, 1.58, -0.55))
    for s in (-1, 1):
        box(p, (0.02, 0.5, 0.7), K('paint', SAFFRON), (s * 0.66, 1.05, -0.55), b=0.005)   # side panels
        for k in range(3): rod(p, (s * 0.66, 1.62, -1.05 + k * 0.5), (s * 0.66, 1.5, -1.05 + k * 0.5), 0.01, K('wood', 0x8a6a42))
        # rear wheels
        cyl(p, 0.3, 0.14, rub, (s * 0.62, 0.3, -0.55), rot=RZ, seg=20, b=0.03)
        cyl(p, 0.17, 0.16, K('metal', 0xb8c0c8), (s * 0.62, 0.3, -0.55), rot=RZ, seg=14, b=0.01)
        box(p, (0.18, 0.08, 0.7), paint, (s * 0.62, 0.66, -0.55), rot=(0, 0, 0), b=0.03)   # mudguards
    rod(p, (-0.62, 0.3, -0.55), (0.62, 0.3, -0.55), 0.035, dk)
    # frame forward to the front wheel
    rod(p, (0, 0.62, 0.0), (0, 0.55, 0.85), 0.05, paint)
    rod(p, (0, 0.55, 0.85), (0, 1.15, 1.05), 0.045, paint)
    rod(p, (0, 0.8, 0.3), (0, 1.0, 0.3), 0.04, dk)
    box(p, (0.28, 0.08, 0.36), K('cloth', 0x4a3424), (0, 1.03, 0.28), b=0.03)   # saddle
    rod(p, (0, 1.15, 1.05), (0, 0.32, 1.3), 0.03, dk)   # fork
    cyl(p, 0.32, 0.12, rub, (0, 0.32, 1.3), rot=RZ, seg=20, b=0.03)
    cyl(p, 0.18, 0.14, K('metal', 0xb8c0c8), (0, 0.32, 1.3), rot=RZ, seg=14, b=0.01)
    box(p, (0.16, 0.06, 0.5), paint, (0, 0.68, 1.28), rot=(0.25, 0, 0), b=0.025)
    rod(p, (-0.32, 1.22, 1.0), (0.32, 1.22, 1.0), 0.022, K('metal', 0xd6dce2))
    for s in (-1, 1): cyl(p, 0.03, 0.12, rub, (s * 0.36, 1.22, 1.0), rot=RZ, seg=8, b=0.005)
    cyl(p, 0.08, 0.06, K('glow', 0xfff0c0), (0, 1.05, 1.12), rot=RX, seg=12, b=0.005)
    cyl(p, 0.1, 0.06, K('metal', 0xd6dce2), (0, 1.05, 1.09), rot=RX, seg=12, b=0.01)
    # pedals and a horn
    for s in (-1, 1): box(p, (0.12, 0.03, 0.06), dk, (s * 0.14, 0.5, 0.45), b=0.005)
    cyl(p, 0.05, 0.12, K('brass'), (0.25, 1.28, 1.0), r2=0.02, rot=RX, seg=10, b=0)
    # goods tumbling out of the back
    rnd = random.Random(61)
    slat_crate(p, (0.1, 0, -1.6), 0.4, fill=[ORANGE, APPLE], rnd=rnd)
    for k in range(8): fruit(p, (-0.5 + rnd.random() * 1.2, 0.06, -1.3 - rnd.random() * 1.0), 0.06, [ORANGE, APPLE][k % 2], seg=8)
    p.finish()


def hover_float():
    """a market float-cart: a flat-bed hover barrow (antigrav pods) that dropped to the deck when the bots
    went haywire; a stack of melons and a striped sunshade"""
    p = Prop('mk_hover_barrow'); rnd = random.Random(71)
    paint = K('paint', 0xd2a03a); dk = K('metal', 0x3a3f46)
    box(p, (1.4, 0.18, 2.2), paint, (0, 0.42, 0), b=0.06, seg=3)
    box(p, (1.46, 0.08, 2.26), dk, (0, 0.32, 0), b=0.03)
    for sx in (-1, 1):
        for sz in (-1, 1):
            cyl(p, 0.2, 0.22, dk, (sx * 0.5, 0.17, sz * 0.8), seg=14, b=0.03)
            cyl(p, 0.14, 0.03, K('glow', 0x46f0ff) if (sx + sz) != 0 else K('metal', 0x222428), (sx * 0.5, 0.05, sz * 0.8), seg=14, b=0)
    for s in (-1, 1):
        rod(p, (s * 0.7, 0.55, -1.1), (s * 0.7, 1.05, -1.2), 0.03, K('metal', 0xd6dce2))
    rod(p, (-0.7, 1.05, -1.2), (0.7, 1.05, -1.2), 0.03, K('metal', 0xd6dce2))
    for s in (-1, 1): box(p, (0.04, 0.22, 2.1), K('wood', WOOD_LT), (s * 0.68, 0.62, 0.05), b=0.01)
    # melons
    for k in range(9):
        x = -0.4 + (k % 3) * 0.4; z = -0.5 + (k // 3) * 0.45
        sph(p, 0.2, K('paint', MELON), (x, 0.7, z), scale=(1, 0.9, 1.2), seg=14, rings=8)
    for k in range(3): sph(p, 0.19, K('paint', 0x4f8a32), (-0.2 + k * 0.4, 1.0, -0.25 + (k % 2) * 0.4), scale=(1, 0.9, 1.2), seg=14, rings=8)
    # sunshade on a pole
    rod(p, (0.6, 0.5, 0.95), (0.6, 2.2, 0.95), 0.025, K('metal', 0xd6dce2))
    p.add(cloth_grid(1.3, 1.1, 6, 5, -0.12), K('cloth', CRIMSON), at=(0.25, 2.2, 0.6), rot=(0.1, 0, 0.12))
    p.finish()


# ================================================================== big pieces
def awning_wall(name, c1, c2):
    """a striped wall awning 3 m wide that juts 1.3 m out from a wall (wall plane at z=0, faces +Z), mounted at 2.6 m"""
    p = Prop(name)
    n = 6
    for i in range(n):
        bm = cloth_grid(0.505, 1.4, 2, 6, 0.04)
        p.add(bm, K('cloth', c1 if i % 2 == 0 else c2), at=(-1.25 + i * 0.5, 2.9, 0.7), rot=(0.42, 0, 0))
    for i in range(n * 2):
        x = -1.5 + 0.125 + i * 0.25
        bm = bmesh.new()
        vs = [bm.verts.new(v) for v in ((-0.125, 0, 0), (0.125, 0, 0), (0.09, -0.16, 0), (0.0, -0.22, 0), (-0.09, -0.16, 0))]
        bm.faces.new(vs)
        p.add(bm, K('cloth', c2 if i % 2 == 0 else c1), at=(x, 2.62, 1.34), smooth=False)
    for s in (-1, 1):
        rod(p, (s * 1.5, 3.2, 0.0), (s * 1.5, 2.62, 1.32), 0.02, K('metal', IRON))
        rod(p, (s * 1.5, 2.3, 0.0), (s * 1.5, 2.62, 1.32), 0.015, K('metal', IRON))
    rod(p, (-1.5, 2.62, 1.32), (1.5, 2.62, 1.32), 0.02, K('metal', IRON))
    box(p, (3.1, 0.12, 0.1), K('wood', WOOD_DK), (0, 3.2, 0.03), b=0.015)
    p.finish()


def awnings():
    awning_wall('mk_awning_saffron', SAFFRON, CREAM)
    awning_wall('mk_awning_teal', TEAL, CREAM)
    awning_wall('mk_awning_crimson', CRIMSON, SAFFRON)


def tarp_pile():
    """goods heaped under a tied-down tarp, a corner blown loose"""
    p = Prop('mk_tarp_pile'); rnd = random.Random(91)
    for k, (x, z, s) in enumerate(((-0.45, 0, 0.7), (0.4, 0.1, 0.65), (0.0, -0.1, 0.55))):
        box(p, (s, s * 0.8, s), K('wood', WOOD), (x, s * 0.4 + (0.55 if k == 2 else 0), z), rot=(0, 0.2 * k, 0), b=0.02)
    bm = bmesh.new(); nx, nz = 14, 10; vs = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            u, v = i / nx, j / nz
            x, z = (u - 0.5) * 2.2, (v - 0.5) * 1.7
            dome = max(0.0, 1.0 - (abs(x) / 1.05) ** 2.4 - (abs(z) / 0.8) ** 2.4)
            y = 0.04 + 1.15 * dome ** 0.45 + 0.04 * noise.noise(Vector((x * 3, z * 3, 0.5)))
            if u > 0.82 and v < 0.25: y += (u - 0.82) * 2.0 * (0.25 - v) * 6   # loose corner lifting in the wind
            row.append(bm.verts.new((x, y, z)))
        vs.append(row)
    for j in range(nz):
        for i in range(nx): bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.y < 0: f.normal_flip()
    p.add(bm, K('cloth', 0x5f7f8a), angle=60)
    for z in (-0.4, 0.4): rod(p, (-1.1, 0.05, z), (1.1, 0.05, z * 0.9), 0.012, K('wood', 0x8a6a42))
    p.finish()


def crate_wall():
    """a wall of stacked wooden shipping crates (2.4 x 1.8 x 1.0), stencilled, one fallen off the top"""
    p = Prop('mk_crate_wall'); rnd = random.Random(101)
    for row, y in enumerate((0.0, 0.62, 1.24)):
        n = 3 if row < 2 else 2
        for k in range(n):
            x = -0.8 + k * 0.8 + (0.4 if row == 2 else 0) + (rnd.random() - 0.5) * 0.05
            s = 0.62
            c = [WOOD, WOOD_LT, 0xa8865a][(k + row) % 3]
            box(p, (0.78, s, 0.9), K('wood', c), (x, y + s / 2, (rnd.random() - 0.5) * 0.08), rot=(0, (rnd.random() - 0.5) * 0.08, 0), b=0.025)
            for e in (-1, 1): box(p, (0.82, 0.07, 0.94), K('wood', WOOD_DK), (x, y + s / 2 + e * 0.22, 0), b=0.01)
            box(p, (0.3, 0.22, 0.005), K('paint', [CRIMSON, 0x2f6a8a, 0x3a3f46][(k + row) % 3]), (x, y + s / 2, 0.47), b=0)
    box(p, (0.78, 0.62, 0.9), K('wood', WOOD_LT), (1.6, 0.4, 0.5), rot=(0.4, 0.5, 0.3), b=0.025)
    p.finish()


# ================================================================== shop-houses
def shophouse(name, W, floors, wall, trim, shutter, sign_c, lit=(), balcony=1, arch=False, roof='tank', seed=1):
    """A narrow market shop-house: an open shopfront on the ground floor (counter, shelves, a sign board over
    it), plastered upper floors with shuttered windows, a balcony with flower pots, a cornice and a rooftop
    clutter silhouette. Front face at z = 0 facing +Z, the building runs back to z = -D. Origin front-centre."""
    p = Prop(name); rnd = random.Random(seed)
    D = 4.6; FH = 3.1; H = FH * floors
    pl = K('plaster', wall); tr = K('plaster', trim); wd = K('wood', WOOD_DK); ir = K('metal', 0x2e3238)
    # shell (back and sides solid, front built up from pieces)
    box(p, (W, H - FH, D - 0.3), pl, (0, FH + (H - FH) / 2, -D / 2 - 0.15), b=0.04)
    box(p, (W, FH, D - 1.5), pl, (0, FH / 2, -1.5 - (D - 1.5) / 2), b=0.04)
    for s in (-1, 1): box(p, (0.12, FH, 1.5), pl, (s * (W / 2 - 0.06), FH / 2, -0.75), b=0.02)
    box(p, (W - 0.2, 0.12, 1.5), K('plaster', 0x5a4636), (0, FH - 0.06, -0.75), b=0)
    box(p, (W + 0.12, 0.35, D), K('plaster', 0xa89580), (0, 0.175, -D / 2), b=0.03)            # stone plinth
    # ground floor shopfront: corner piers, a lintel, a dark recess with shelves and a counter
    for s in (-1, 1): box(p, (0.5, FH, 0.4), tr, (s * (W / 2 - 0.25), FH / 2, -0.2), b=0.04)
    box(p, (W, 0.55, 0.42), tr, (0, FH - 0.27, -0.2), b=0.04)
    box(p, (W - 1.0, FH - 0.55, 0.1), K('plaster', 0x4a3a30), (0, (FH - 0.55) / 2, -1.45), b=0)   # back of the shop
    box(p, (W - 1.0, 0.1, 1.3), K('wood', 0x6a4a32), (0, 0.05, -0.8), b=0)
    for y in (0.9, 1.5, 2.1):
        box(p, (W - 1.1, 0.05, 0.35), wd, (0, y, -1.25), b=0.005)
        for k in range(int(W - 1.4) * 2):
            x = -(W - 1.4) / 2 + 0.25 + k * 0.5
            c = [CLAY, 0x2f7f86, CREAM, CLAY_DK, SAFFRON][(k + int(y * 3)) % 5]
            p.add(sk.bm_cyl(0.08, 0.06, 0.22 + 0.06 * (k % 2), 8), K('paint', c), at=(x, y + 0.14, -1.25), b=0.0)
    box(p, (W - 1.0, 0.95, 0.5), K('wood', WOOD), (0, 0.475, -0.35), b=0.02)                     # counter
    box(p, (W - 0.9, 0.06, 0.62), wd, (0, 0.97, -0.33), b=0.01)
    box(p, (W - 1.2, 0.9, 0.02), K('plaster', 0x4a3a30), (0, 0.45, -1.42), b=0)
    # sign board over the shopfront (lettering added in the game)
    box(p, (W - 1.3, 0.62, 0.1), K('wood', sign_c), (0, FH + 0.1, 0.05), b=0.02)
    box(p, (W - 1.1, 0.08, 0.14), K('brass'), (0, FH + 0.45, 0.05), b=0.01)
    box(p, (W - 1.1, 0.08, 0.14), K('brass'), (0, FH - 0.25, 0.05), b=0.01)
    p.mark('sign', (0, FH + 0.1, 0.12))
    # upper floors
    nwin = 2 if W < 5.8 else 3
    for f in range(1, floors):
        y0 = f * FH
        box(p, (W + 0.14, 0.16, 0.2), tr, (0, y0 + 0.08, 0.02), b=0.02)                           # floor band
        for k in range(nwin):
            x = -W / 2 + W * (k + 0.5) / nwin
            ww, wh = 0.95, 1.55
            wy = y0 + 1.55
            glass = K('glow', 0xffb060) if (f, k) in lit else K('glass', 0x2a3a48)
            box(p, (ww, wh, 0.05), glass, (x, wy, 0.02), b=0)
            if arch: cyl(p, ww / 2, 0.05, glass, (x, wy + wh / 2, 0.02), rot=RX, seg=16, b=0)
            for s in (-1, 1): box(p, (0.1, wh + 0.1, 0.14), tr, (x + s * (ww / 2 + 0.05), wy, 0.06), b=0.015)
            box(p, (ww + 0.3, 0.1, 0.24), tr, (x, wy - wh / 2 - 0.05, 0.1), b=0.015)               # sill
            if arch: tor(p, ww / 2 + 0.05, 0.06, tr, (x, wy + wh / 2, 0.06), rot=(math.pi / 2, 0, 0), seg=16, tube=6, arc=math.pi)
            else: box(p, (ww + 0.3, 0.12, 0.18), tr, (x, wy + wh / 2 + 0.06, 0.08), b=0.015)
            box(p, (0.04, wh, 0.03), wd, (x, wy, 0.06), b=0)
            # shutters swung open (one half-closed now and then)
            for s in (-1, 1):
                ang = 1.25 if rnd.random() > 0.25 else 0.45
                cx = x + s * (ww / 2 + 0.1)
                R = Euler((0, -s * ang, 0), 'XYZ').to_matrix()
                c = Vector((cx, wy, 0.12)) + R @ Vector((s * ww / 4, 0, 0))
                box(p, (ww / 2, wh, 0.04), K('wood', shutter), tuple(c), mat3=R, b=0.008)
                for j in range(5):
                    cj = Vector((cx, wy - wh / 2 + 0.2 + j * 0.28, 0.12)) + R @ Vector((s * ww / 4, 0, 0.025))
                    box(p, (ww / 2 - 0.08, 0.03, 0.02), K('wood', WOOD_DK), tuple(cj), mat3=R, b=0)
            if rnd.random() < 0.6 and not (f == balcony):
                box(p, (ww + 0.1, 0.22, 0.26), K('wood', WOOD), (x, wy - wh / 2 + 0.06, 0.32), b=0.015)
                for j in range(4):
                    sph(p, 0.11, K('leaf', [0x4fae5c, 0x3e8e4a][j % 2]), (x - 0.36 + j * 0.24, wy - wh / 2 + 0.26, 0.32), seg=8, rings=5)
                    if j % 2 == 0: sph(p, 0.06, K('leaf', [0xe2457a, 0xf4c232, 0xffffff][rnd.randrange(3)]), (x - 0.36 + j * 0.24, wy - wh / 2 + 0.33, 0.4), seg=8, rings=5)
        if f == balcony:
            by = y0 + 0.2
            box(p, (W - 0.6, 0.16, 1.0), tr, (0, by, 0.5), b=0.03)
            for s in (-1, 1): box(p, (0.14, 0.34, 0.9), tr, (s * (W / 2 - 0.6), by - 0.25, 0.45), rot=(0, 0, 0), b=0.02)
            rod(p, (-(W - 0.7) / 2, by + 0.95, 0.98), ((W - 0.7) / 2, by + 0.95, 0.98), 0.025, ir)
            for s in (-1, 1): rod(p, (s * (W - 0.7) / 2, by + 0.95, 0.98), (s * (W - 0.7) / 2, by + 0.95, 0.05), 0.025, ir)
            n = int((W - 0.7) / 0.14)
            for j in range(n + 1):
                x = -(W - 0.7) / 2 + j * (W - 0.7) / n
                rod(p, (x, by + 0.08, 0.98), (x, by + 0.95, 0.98), 0.01, ir)
            for j in range(3):
                x = -W / 2 + 1.0 + j * (W - 2.0) / 2
                p.add(lathe([(0.12, 0), (0.17, 0.25), (0.18, 0.3)], 12, cap_top=False), K('paint', CLAY), at=(x, by + 0.08, 0.65), angle=50)
                sph(p, 0.22, K('leaf', 0x4fae5c), (x, by + 0.45, 0.65), seg=10, rings=6)
                sph(p, 0.08, K('leaf', 0xe2457a), (x + 0.1, by + 0.6, 0.75), seg=8, rings=5)
    # cornice, parapet with tile coping
    box(p, (W + 0.3, 0.22, 0.4), tr, (0, H + 0.1, 0.05), b=0.03)
    box(p, (W + 0.1, 0.6, 0.2), pl, (0, H + 0.5, -0.05), b=0.03)
    for k in range(int(W / 0.3)):
        cyl(p, 0.09, 0.28, K('paint', 0xb0583a), (-W / 2 + 0.15 + k * 0.3, H + 0.84, -0.05), rot=RX, seg=8, b=0, cap=True)
    for s in (-1, 1): box(p, (0.2, 0.6, D), pl, (s * (W / 2 - 0.05), H + 0.5, -D / 2), b=0.02)
    # rooftop clutter for the silhouette
    if roof == 'tank':
        cyl(p, 0.65, 1.2, K('metal', 0x8c98a5), (W * 0.2, H + 1.0, -2.6), seg=16, b=0.03)
        for s in (-1, 1):
            for t in (-1, 1): rod(p, (W * 0.2 + s * 0.45, H, -2.6 + t * 0.45), (W * 0.2 + s * 0.45, H + 0.4, -2.6 + t * 0.45), 0.04, ir)
        cyl(p, 0.68, 0.1, K('paint', 0xb0583a), (W * 0.2, H + 1.62, -2.6), r2=0.1, seg=16, b=0.01)
    elif roof == 'pergola':
        for s in (-1, 1):
            for t in (0, 1): box(p, (0.1, 2.0, 0.1), K('wood', WOOD), (s * (W / 2 - 0.4), H + 1.0, -0.8 - t * 2.6), b=0.01)
        for k in range(7): box(p, (W - 0.6, 0.08, 0.08), K('wood', WOOD), (0, H + 2.0, -0.6 - k * 0.5), b=0.005)
        for k in range(6):
            sph(p, 0.35, K('leaf', [0x4fae5c, 0x58a86a, 0x3e8e4a][k % 3]), (-W / 2 + 0.6 + (k % 3) * (W - 1.2) / 2, H + 2.1, -0.8 - (k // 3) * 2.2), scale=(1.4, 0.6, 1.2), seg=10, rings=6)
    else:
        box(p, (1.6, 1.4, 1.6), pl, (-W * 0.2, H + 0.7, -2.8), b=0.03)
        box(p, (1.8, 0.12, 1.8), K('paint', 0xb0583a), (-W * 0.2, H + 1.45, -2.8), b=0.02)
        rod(p, (-W * 0.2 + 0.5, H + 1.5, -2.8), (-W * 0.2 + 0.5, H + 3.2, -2.8), 0.025, ir)
        cyl(p, 0.35, 0.08, K('metal', 0xd6dce2), (-W * 0.2 + 0.5, H + 3.2, -2.6), r2=0.05, rot=(0.6, 0, 0), seg=14, b=0)
    # a drainpipe and a lantern on a bracket by the door
    rod(p, (W / 2 - 0.08, 0.3, 0.12), (W / 2 - 0.08, H + 0.2, 0.12), 0.05, K('metal', 0x6a7078))
    rod(p, (-W / 2 + 0.25, 2.3, 0.2), (-W / 2 + 0.25, 2.3, 0.55), 0.02, ir)
    cyl(p, 0.1, 0.28, K('glow', 0xffa640), (-W / 2 + 0.25, 2.05, 0.55), seg=8, b=0)
    cyl(p, 0.13, 0.05, K('brass'), (-W / 2 + 0.25, 2.21, 0.55), seg=8, b=0)
    p.mark('light_0', (-W / 2 + 0.25, 2.05, 0.75))
    p.finish()


def shophouses():
    shophouse('mk_house_a', 5.4, 2, 0xe8b56a, 0xf3e6cf, 0x2f7f86, 0x2f5f6a, lit={(1, 0)}, roof='tank', seed=1)
    shophouse('mk_house_b', 5.0, 3, 0xd98a6a, 0xf1e3c6, 0x7d4e8e, 0x7a3a2e, lit={(1, 1), (2, 0)}, balcony=2, roof='pergola', seed=2)
    shophouse('mk_house_c', 6.2, 2, 0xe9dcc0, 0xc8724a, 0x2f9e9b, 0x5a3a6a, lit={(1, 2)}, arch=True, roof='hut', seed=3)
    shophouse('mk_house_d', 5.2, 3, 0xa9cdb8, 0xf3e6cf, 0xc8453a, 0x6a3a20, lit={(2, 1)}, balcony=1, arch=True, roof='tank', seed=4)


ALL = [crate_fruit, crate_stack, crate_spill, barrel, barrels_open, sacks, spice_sacks, jars, baskets, rug_rolls,
       produce_table, spice_shelf, canopy_stalls, canopy_collapsed, blade_signs, parasols, stools, lamp_post,
       handcarts, cargo_trike, hover_float, awnings, tarp_pile, crate_wall, shophouses]

if __name__ == '__main__':
    want = [a for a in sys.argv[1:] if not a.startswith('-')]
    for f in ALL:
        if want and f.__name__ not in want: continue
        f()
    print('TRIS', sk.TRIS)
