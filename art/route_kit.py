"""The Routes kit: the structure and dressing of the connectors between Skyharbor's areas
(godot/models/routes/<name>.glb).

Built with the Skyharbor kit's Prop builder (art/skyharbor_kit.py): beveled primitives with hardened normals,
joined into one mesh per prop, k_<kind>_<rrggbb> material names. k_stone_* becomes a weathered world-space
stone (sandstone texture, moss in the crevices) in godot/scripts/level/routes/routes_look.gd, everything else
goes through mats.gd like the other kits. Game space: Y up, +Z along the route for the bridge pieces (a bridge
deck runs along Z, its top at y = 0), +Z is the front for the free-standing props.

Three families, one per kind of route:
  - the Scrapline tram viaduct (junkyard -> plaza): stone piers and arches dropping into the clouds, stone
    parapets with iron cresting, double lamp posts, hanging flower boxes, city banners
  - the Lantern Bridge (plaza -> market): lacquered timber railings, a roofed lantern gate, a stone pier with
    timber brackets under the deck
  - the freight routes (gangway, freight approach, lift bridge): yellow guard rails with mesh panels, plate
    girders with pipes and cable trays under the deck, sign gantries, floodlight masts

Run: python3 art/route_kit.py [prop names...]      (pip bpy 5.3 works headless)
"""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import skyharbor_kit as sk
from skyharbor_kit import Prop, K, box, cyl, tor, sph, rod, RX, RZ, TAU
import bmesh
from mathutils import Vector, Matrix, Euler

sk.OUT = os.path.normpath(os.path.join(HERE, '..', 'godot', 'models', 'routes'))
sk.PARAMS['stone'] = (0.0, 0.85)    # k_stone_*: weathered sandstone (routes_look.gd)
os.makedirs(sk.OUT, exist_ok=True)

# ---------------- palette ----------------
STONE, STONE_DK, STONE_LT, STONE_RD = 0xd9c4a4, 0xa8927a, 0xeadcc2, 0xc9a083
IRON, IRON_LT, BRASS = 0x2e3a40, 0x46565e, 0xd9a441
LACQUER, LACQUER_DK, GOLD, ROOF = 0xb8322a, 0x7a2018, 0xe0b04a, 0x2f5a5a
WOOD, WOOD_DK = 0xa8784a, 0x6e4a2e
YELLOW, STEEL, STEEL_DK, PIPE_RED, PIPE_TEAL = 0xf0b528, 0x8a96a2, 0x4a535c, 0xb8453a, 0x2f8f8a
GLASS = 0xf4e0b0
AMBER = 0xffb455
CREAM, TEAL, SAFFRON, PLUM, CRIMSON, SKY = 0xf1e3c6, 0x2f9e9b, 0xf2b33d, 0x7d4e8e, 0xc8453a, 0x5f9fd0
LEAF, LEAF_DK, SOIL = 0x5aa04e, 0x3f8040, 0x4a3424
FLOWERS = [0xe2457a, 0xf4c232, 0xf08a3a, 0xf2f0e8, 0xb05ad0]


def S(c=STONE): return K('stone', c)


# ---------------- shapes ----------------
def prism_zy(profile, x0, x1):
    """Extrude a closed polygon in the ZY plane [(z, y), ...] (counter-clockwise seen from +X) from x0 to x1."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for z, y in profile]
    b = [bm.verts.new((x1, y, z)) for z, y in profile]
    n = len(profile)
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def arch_slab(x0, x1, z0, z1, y_top, y_spring, rise, seg=18):
    """A stone slab between z0 and z1 (top at y_top) with a round-headed arch cut out of its underside:
    built as quads between the arch curve and the top edge, extruded across x0..x1."""
    bm = bmesh.new()
    zc = (z0 + z1) / 2; r = (z1 - z0) / 2
    curve = []
    for i in range(seg + 1):
        t = math.pi * i / seg
        curve.append((zc + r * math.cos(t), y_spring + rise * math.sin(t)))
    # cross-section ring: along the arch (z1 -> z0), up to the top, back along the top
    def ring(x):
        arc = [bm.verts.new((x, y, z)) for z, y in curve]
        top = [bm.verts.new((x, y_top, z)) for z, y in curve]
        return arc, top
    A0, T0 = ring(x0); A1, T1 = ring(x1)
    for i in range(seg):
        # the two faces of the wall
        bm.faces.new((A0[i], T0[i], T0[i + 1], A0[i + 1]))
        bm.faces.new((A1[i + 1], T1[i + 1], T1[i], A1[i]))
        # the intrados (the vault underside) and the top
        bm.faces.new((A0[i + 1], A1[i + 1], A1[i], A0[i]))
        bm.faces.new((T0[i], T1[i], T1[i + 1], T0[i + 1]))
    for k in (0, seg):   # the vertical ends over the piers
        bm.faces.new((A0[k], A1[k], T1[k], T0[k]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def voussoirs(p, x, z0, z1, y_spring, rise, depth, m, n=17, out=0.12, key=None):
    """the ring of arch stones on one face (x), slightly proud of the wall"""
    zc = (z0 + z1) / 2; r = (z1 - z0) / 2
    for i in range(n):
        t = math.pi * (i + 0.5) / n
        z = zc + (r + depth / 2) * math.cos(t); y = y_spring + (rise + depth / 2) * math.sin(t)
        ln = math.pi * r / n * 0.9
        big = key is not None and i == n // 2
        box(p, (0.5 + out, depth * (1.25 if big else 1.0), ln * (1.15 if big else 1.0)), key if big else m, (x, y, z),
            rot=(math.atan2(rise * math.cos(t), -r * math.sin(t)) if False else -(t - math.pi / 2), 0, 0), b=0.03, seg=1)


# ================================================================== the viaduct
def pier():
    """A viaduct pier: a tall stone column across the deck (x -4.6..4.6), 2.4 thick along the route, top at
    y -0.6, tapering and stepping out as it drops 34 m into the clouds; string courses, a buttress on each face,
    a little shrine niche with a lamp, ivy and moss streaks are in the shader."""
    p = Prop('rt_pier'); s, sd, sl = S(STONE), S(STONE_DK), S(STONE_LT)
    top = -0.6
    # the column, in three stages that step out
    stages = [(top, -9.0, 8.6, 2.4), (-9.0, -20.0, 9.2, 2.9), (-20.0, -34.0, 9.8, 3.4)]
    for y0, y1, w, d in stages:
        box(p, (w, y0 - y1, d), s, (0, (y0 + y1) / 2, 0), b=0.08)
        # string course at the top of each stage
        box(p, (w + 0.4, 0.45, d + 0.4), sl, (0, y0 - 0.25, 0), b=0.06)
    # the impost blocks where the arches spring (y -8)
    box(p, (9.0, 0.6, 3.1), sl, (0, -8.0, 0), b=0.06)
    # buttresses on the faces across the route (x = +-), tapering down
    for sx in (-1, 1):
        box(p, (1.0, 25.0, 1.6), sd, (sx * 4.9, -12.5 - 9.0, 0), b=0.08)
        box(p, (1.2, 0.5, 1.9), sl, (sx * 4.95, -9.0, 0), b=0.05)
        # weathering cap
        wedge = box(p, (1.0, 0.8, 1.6), sl, (sx * 4.75, -8.5, 0), rot=(0, 0, sx * 0.5), b=0.05)
    # a rusticated band of big blocks at the base of stage one (both route faces)
    for sz in (-1, 1):
        for k in range(5):
            box(p, (1.5, 0.9, 0.18), sd, (-3.4 + k * 1.7, -12.0, sz * 1.48), b=0.06, seg=1)
            box(p, (1.5, 0.9, 0.18), sd, (-2.55 + k * 1.7, -13.0, sz * 1.48), b=0.06, seg=1)
    # the shrine niche on the outer faces with a lamp in it
    for sx in (-1, 1):
        box(p, (0.5, 1.5, 1.0), K('metal', IRON), (sx * 5.3, -4.2, 0), b=0.04)
        box(p, (0.3, 1.1, 0.7), K('glow', AMBER), (sx * 5.45, -4.2, 0), b=0.0)
        box(p, (0.65, 0.18, 1.2), K('brass'), (sx * 5.33, -3.38, 0), b=0.03)
        p.mark('light_%d' % (0 if sx < 0 else 1), (sx * 5.9, -4.2, 0))
    p.finish()


def arch():
    """One 10 m arch bay between two piers (z -5..5 is pier centre to pier centre; the arch opening spans the
    7.6 m between the piers' faces): a stone slab with a round arch cut out, voussoir rings and a keystone on
    both faces, a cornice band and corbels under the parapet."""
    p = Prop('rt_arch'); s, sd, sl = S(STONE), S(STONE_DK), S(STONE_LT)
    half = 4.3; z0, z1 = -3.8, 3.8; spring = -8.0; rise = 3.8   # crown at -4.2: a stout semicircle-ish arch
    p.add(arch_slab(-half, half, -5.0, 5.0, -0.6, spring, 0.0, seg=2), s)   # placeholder replaced below
    p.groups[None].pop()
    # the wall: solid above the arch, across the whole deck width
    p.add(arch_slab(-half, half, z0, z1, -0.6, spring, rise), s, b=0.0)
    # fill the corners between arch springing and the pier faces (z 3.8..5)
    for sz in (-1, 1):
        box(p, (2 * half, 7.4, 1.25), s, (0, -4.3, sz * 4.38), b=0.0)
    # voussoir rings and keystones on both faces
    for sx in (-1, 1):
        voussoirs(p, sx * (half + 0.02), z0, z1, spring, rise, 0.75, sd, n=15, out=0.1, key=sl)
    # the cornice band along both faces, with corbels under it
    for sx in (-1, 1):
        box(p, (0.55, 0.5, 10.2), sl, (sx * (half + 0.12), -0.85, 0), b=0.06)
        box(p, (0.35, 0.22, 10.2), sd, (sx * (half + 0.05), -1.2, 0), b=0.04)
        for k in range(9):
            box(p, (0.42, 0.42, 0.34), sd, (sx * (half + 0.12), -1.45, -4.4 + k * 1.1), b=0.05, seg=1)
    p.finish()


def parapet():
    """2 m of stone parapet (along X, so it can be laid along any edge): a low wall with coping, iron cresting
    with brass finials on top; 1.05 m tall overall to match the railing collider."""
    p = Prop('rt_parapet'); s, sl = S(STONE), S(STONE_LT); ir = K('metal', IRON)
    box(p, (2.0, 0.62, 0.42), s, (0, 0.31, 0), b=0.04)
    box(p, (2.06, 0.12, 0.52), sl, (0, 0.68, 0), b=0.035)
    # recessed panel on the outer face
    box(p, (1.5, 0.34, 0.04), S(STONE_DK), (0, 0.33, -0.22), b=0.01, seg=1)
    # iron cresting: a top bar and little scrolled pickets
    box(p, (2.0, 0.04, 0.04), ir, (0, 1.02, 0), b=0.0)
    for k in range(8):
        x = -0.875 + k * 0.25
        rod(p, (x, 0.74, 0), (x, 1.02, 0), 0.014, ir)
        tor(p, 0.06, 0.012, ir, (x + 0.125, 0.9, 0), (0, 0, 0), seg=10, tube=4)
    p.finish()


def parapet_post():
    """the pilaster between parapet runs: a taller stone block with a brass ball"""
    p = Prop('rt_parapet_post'); s, sl = S(STONE_LT), S(STONE)
    box(p, (0.62, 1.0, 0.62), sl, (0, 0.5, 0), b=0.05)
    box(p, (0.72, 0.12, 0.72), s, (0, 1.06, 0), b=0.04)
    box(p, (0.5, 0.1, 0.5), s, (0, 1.16, 0), b=0.03)
    sph(p, 0.13, K('brass'), (0, 1.32, 0), seg=12, rings=8)
    p.finish()


def lamp_twin():
    """A double lamp post for the viaduct piers: fluted iron column on a stone block, two scrolled arms with
    glass lanterns, a little city crest."""
    p = Prop('rt_lamp_twin'); ir = K('metal', IRON); br = K('brass')
    box(p, (0.62, 0.5, 0.62), S(STONE_LT), (0, 0.25, 0), b=0.05)
    cyl(p, 0.2, 0.25, ir, (0, 0.62, 0), r2=0.15, seg=12, b=0.02)
    cyl(p, 0.09, 3.6, ir, (0, 2.55, 0), r2=0.07, seg=12, b=0)
    for y in (0.95, 2.2, 4.0): tor(p, 0.1, 0.03, br, (0, y, 0), RX, seg=14, tube=6)
    # crest
    box(p, (0.36, 0.44, 0.05), K('paint', TEAL), (0, 3.2, 0.1), b=0.015, seg=1)
    box(p, (0.2, 0.2, 0.06), br, (0, 3.22, 0.12), b=0.01, seg=1)
    for sx in (-1, 1):
        # scrolled arm
        rod(p, (0, 4.15, 0), (sx * 0.62, 4.15, 0), 0.035, ir)
        tor(p, 0.18, 0.025, ir, (sx * 0.3, 3.95, 0), (0, 0, 0), seg=14, tube=5, arc=math.pi)
        # the lantern hanging from the arm's end
        x = sx * 0.66
        rod(p, (x, 4.15, 0), (x, 3.98, 0), 0.02, ir)
        cyl(p, 0.16, 0.06, ir, (x, 3.94, 0), r2=0.1, seg=8, b=0.01)
        cyl(p, 0.13, 0.42, K('glass', GLASS), (x, 3.68, 0), r2=0.11, seg=8, b=0)
        sph(p, 0.08, K('glow', AMBER), (x, 3.68, 0), seg=10, rings=6)
        for k in range(4):
            a = TAU * k / 4 + 0.78
            rod(p, (x + math.cos(a) * 0.13, 3.9, math.sin(a) * 0.13), (x + math.cos(a) * 0.11, 3.46, math.sin(a) * 0.11), 0.012, br)
        cyl(p, 0.12, 0.06, br, (x, 3.43, 0), seg=8, b=0.01)
        p.mark('light_%d' % (0 if sx < 0 else 1), (x, 3.68, 0))
    cyl(p, 0.16, 0.22, ir, (0, 4.32, 0), r2=0.04, seg=10, b=0.01)
    sph(p, 0.05, br, (0, 4.48, 0), seg=8, rings=6)
    p.finish()


def flower_box(name, cols, seed):
    """a flower box that hangs on the outside of a railing (hooks over the top at y 1.0); flowers spill over"""
    p = Prop(name); rnd = random.Random(seed)
    box(p, (1.3, 0.34, 0.38), K('wood', WOOD_DK), (0, 0.72, -0.34), b=0.03)
    for sx in (-0.5, 0.5):
        rod(p, (sx, 1.04, 0.02), (sx, 1.04, -0.2), 0.015, K('metal', IRON))
        rod(p, (sx, 1.04, -0.2), (sx, 0.82, -0.2), 0.015, K('metal', IRON))
    box(p, (1.22, 0.04, 0.3), K('soil', SOIL), (0, 0.88, -0.34), b=0)
    for k in range(9):
        x = -0.55 + k * 0.137 + rnd.uniform(-0.04, 0.04)
        sph(p, rnd.uniform(0.11, 0.16), K('leaf', LEAF if k % 2 else LEAF_DK), (x, 0.95 + rnd.uniform(0, 0.06), -0.34 + rnd.uniform(-0.06, 0.06)), (1, 0.8, 1), seg=8, rings=6)
    for k in range(16):
        x = rnd.uniform(-0.6, 0.6)
        sph(p, rnd.uniform(0.04, 0.06), K('paint', cols[k % len(cols)]), (x, 1.02 + rnd.uniform(0, 0.12), -0.34 + rnd.uniform(-0.14, 0.12)), seg=6, rings=4)
    # trailing vines down the outside
    for k in range(5):
        x = rnd.uniform(-0.55, 0.55); ln = rnd.uniform(0.4, 0.8)
        for j in range(4):
            sph(p, 0.06 - j * 0.008, K('leaf', LEAF_DK), (x + rnd.uniform(-0.04, 0.04), 0.66 - j * ln / 4, -0.56 - j * 0.02), (1, 1.3, 0.7), seg=6, rings=4)
    p.finish()


def flower_boxes():
    flower_box('rt_flowers_a', [FLOWERS[0], FLOWERS[1], FLOWERS[3]], 3)
    flower_box('rt_flowers_b', [FLOWERS[2], FLOWERS[4], FLOWERS[3]], 7)


def banner(name, c1, c2):
    """a tall pole with a long city banner on two arms"""
    p = Prop(name); ir = K('metal', IRON)
    cyl(p, 0.1, 6.4, ir, (0, 3.2, 0), r2=0.08, seg=10, b=0)
    sph(p, 0.11, K('brass'), (0, 6.5, 0), seg=10, rings=6)
    for y in (6.0, 3.1): rod(p, (0, y, 0), (0.95, y, 0), 0.03, ir)
    # the cloth, with a slight wave (several panels) and a swallowtail hem
    n = 6
    for k in range(n):
        y = 5.95 - (k + 0.5) * 2.8 / n
        box(p, (0.86, 2.8 / n + 0.01, 0.025), K('cloth', c1), (0.5, y, math.sin(k * 1.1) * 0.05), b=0.0, seg=1)
    box(p, (0.6, 0.6, 0.03), K('cloth', c2), (0.5, 5.0, math.sin(2.2) * 0.05 + 0.02), b=0.0, seg=1)
    sph(p, 0.16, K('cloth', CREAM), (0.5, 5.0, math.sin(2.2) * 0.05 + 0.04), (1, 1, 0.15), seg=10, rings=6)
    for sx in (-1, 1):
        box(p, (0.36, 0.3, 0.025), K('cloth', c1), (0.5 + sx * 0.22, 3.05, 0.05), rot=(0, 0, sx * 0.35), b=0, seg=1)
    box(p, (0.9, 0.08, 0.04), K('cloth', c2), (0.5, 5.9, 0.0), b=0, seg=1)
    p.finish()


def banners():
    banner('rt_banner_teal', TEAL, SAFFRON)
    banner('rt_banner_crimson', CRIMSON, CREAM)
    banner('rt_banner_plum', PLUM, SAFFRON)


# ================================================================== the Lantern Bridge
def rail_lacquer():
    """2 m of lacquered timber railing (along X): a top rail with a brass-capped cap rail, a lattice panel"""
    p = Prop('rt_rail_lacquer'); lq, ld, gd = K('paint', LACQUER), K('paint', LACQUER_DK), K('brass')
    box(p, (2.0, 0.09, 0.16), lq, (0, 1.0, 0), b=0.025)
    box(p, (2.0, 0.04, 0.1), gd, (0, 1.06, 0), b=0.012)
    box(p, (2.0, 0.08, 0.1), ld, (0, 0.16, 0), b=0.02)
    box(p, (2.0, 0.05, 0.08), ld, (0, 0.62, 0), b=0.015)
    # a fretwork panel between 0.2 and 0.6: slim uprights, a mid rail, small brass medallions
    for k in range(11):
        x = -0.9 + k * 0.18
        box(p, (0.035, 0.42, 0.045), ld, (x, 0.4, 0), b=0.0, seg=1)
    box(p, (2.0, 0.04, 0.06), ld, (0, 0.4, 0), b=0.01, seg=1)
    for k in range(5):
        cyl(p, 0.06, 0.05, gd, (-0.8 + k * 0.4, 0.4, 0), RX, seg=10, b=0)
    for k in range(5):
        x = -0.8 + k * 0.4
        box(p, (0.05, 0.36, 0.05), lq, (x, 0.81, 0), b=0.01, seg=1)
    p.finish()


def lacquer_post():
    p = Prop('rt_lacquer_post'); lq, gd = K('paint', LACQUER), K('brass')
    box(p, (0.44, 0.22, 0.44), S(STONE), (0, 0.11, 0), b=0.04)
    box(p, (0.22, 1.14, 0.22), lq, (0, 0.78, 0), b=0.03)
    box(p, (0.28, 0.06, 0.28), gd, (0, 1.38, 0), b=0.015)
    cyl(p, 0.1, 0.18, lq, (0, 1.5, 0), r2=0.02, seg=8, b=0)
    sph(p, 0.045, gd, (0, 1.6, 0), seg=8, rings=6)
    p.finish()


def lantern_gate():
    """The lantern gate at each end of the Lantern Bridge: two lacquered columns on stone bases (z +-3.7),
    a double crossbeam with a tiled ridge roof whose ends turn up, a name board in the middle, paper lanterns
    hanging under the beam. Spans along Z (the bridge runs along X through it)."""
    p = Prop('rt_lantern_gate'); lq, ld, gd = K('paint', LACQUER), K('paint', LACQUER_DK), K('brass')
    w = 3.7
    for sz in (-1, 1):
        z = sz * w
        box(p, (0.9, 0.5, 0.9), S(STONE), (0, 0.25, z), b=0.06)
        box(p, (0.7, 0.2, 0.7), S(STONE_LT), (0, 0.58, z), b=0.04)
        cyl(p, 0.24, 5.2, lq, (0, 3.2, z), r2=0.22, seg=14, b=0)
        tor(p, 0.25, 0.04, gd, (0, 1.1, z), RX, seg=14, tube=5)
        tor(p, 0.24, 0.04, gd, (0, 5.1, z), RX, seg=14, tube=5)
        # bracket struts under the beam
        rod(p, (0, 4.6, z), (0, 5.5, z - sz * 1.0), 0.07, ld)
    # the beams
    box(p, (0.42, 0.42, 2 * w + 1.4), lq, (0, 5.55, 0), b=0.05)
    box(p, (0.34, 0.3, 2 * w + 0.4), ld, (0, 4.75, 0), b=0.04)
    for k in range(5): box(p, (0.3, 0.42, 0.18), gd, (0, 5.15, -2.6 + k * 1.3), b=0.02, seg=1)
    # the roof: a ridge of tiles over the top beam, ends curling up
    roof = K('paint', ROOF)
    n = 14; L = 2 * w + 2.6
    for k in range(n):
        u = (k + 0.5) / n; z = -L / 2 + u * L
        lift = 0.55 * (abs(u - 0.5) * 2) ** 3
        for sx in (-1, 1):
            box(p, (0.9, 0.08, L / n + 0.03), roof, (sx * 0.38, 6.05 + lift - 0.18, z), rot=(0, 0, sx * 0.42), b=0.02, seg=1)
        cyl(p, 0.08, L / n + 0.02, roof, (0, 6.2 + lift, z), RX, seg=8, b=0)
    for sz in (-1, 1):
        sph(p, 0.16, gd, (0, 6.85, sz * L / 2), seg=10, rings=6)
    # the name board (text is a Label3D in the game)
    box(p, (0.14, 0.9, 2.6), ld, (0, 5.0, 0), b=0.03)
    box(p, (0.16, 0.78, 2.46), K('paint', 0x1e2a30), (0, 5.0, 0), b=0.02)
    for sx in (-1, 1): box(p, (0.04, 0.84, 2.52), gd, (sx * 0.09, 5.0, 0), b=0.0, seg=1)
    p.mark('sign', (0.1, 5.0, 0))
    # paper lanterns under the beam
    for k, z in enumerate((-2.6, 2.6)):
        rod(p, (0, 4.6, z), (0, 4.2, z), 0.015, ld)
        sph(p, 0.32, K('glow', 0xff8a3a), (0, 3.9, z), (1, 1.2, 1), seg=12, rings=8)
        for y in (4.2, 3.58): cyl(p, 0.16, 0.06, ld, (0, y, z), seg=10, b=0)
        p.mark('light_%d' % k, (0.0, 3.9, z))
    p.finish()


def lantern_pier():
    """Under the Lantern Bridge: a stone pier across the deck (x -3.8..3.8, deck runs along Z) dropping into
    the clouds, with timber knee-braces fanning out to carry the deck stringers."""
    p = Prop('rt_lantern_pier'); s, sl = S(STONE_RD), S(STONE_LT); wd = K('wood', WOOD_DK)
    box(p, (7.2, 22.0, 2.2), s, (0, -0.9 - 11.0, 0), b=0.08)
    box(p, (7.6, 0.45, 2.6), sl, (0, -1.1, 0), b=0.05)
    box(p, (8.0, 0.45, 3.0), sl, (0, -9.0, 0), b=0.05)
    box(p, (8.4, 11.0, 3.4), s, (0, -9.2 - 5.5, 0), b=0.08)
    for sx in (-1, 1):
        box(p, (0.9, 18.0, 1.4), S(STONE), (sx * 3.9, -1.5 - 9.0, 0), b=0.06)
    # the knee braces: three pairs across the deck
    for x in (-2.9, 0.0, 2.9):
        for sz in (-1, 1):
            rod(p, (x, -4.0, sz * 1.1), (x, -0.75, sz * 5.0), 0.16, wd, seg=6)
            box(p, (0.36, 0.36, 0.5), K('metal', IRON), (x, -4.0, sz * 1.15), b=0.03)
    # a lantern on each side of the pier
    for sx in (-1, 1):
        rod(p, (sx * 4.4, -1.6, 0), (sx * 4.9, -1.6, 0), 0.04, K('metal', IRON))
        sph(p, 0.26, K('glow', 0xff8a3a), (sx * 4.95, -2.15, 0), (1, 1.25, 1), seg=10, rings=6)
        p.mark('light_%d' % (0 if sx < 0 else 1), (sx * 5.0, -2.2, 0))
    p.finish()


def timber_bay():
    """6 m of timber deck structure (along Z) under the Lantern Bridge: four stringers, cross joists, a
    lacquered fascia board on each side with brass studs."""
    p = Prop('rt_timber_bay'); wd, wk = K('wood', WOOD), K('wood', WOOD_DK)
    for x in (-3.0, -1.0, 1.0, 3.0):
        box(p, (0.34, 0.6, 6.0), wk, (x, -0.95, 0), b=0.03)
    for k in range(4):
        box(p, (7.6, 0.24, 0.26), wd, (0, -0.72, -2.25 + k * 1.5), b=0.025)
    for sx in (-1, 1):
        box(p, (0.12, 0.5, 6.0), K('paint', LACQUER), (sx * 4.02, -0.55, 0), b=0.02)
        for k in range(6): sph(p, 0.04, K('brass'), (sx * 4.09, -0.55, -2.5 + k), seg=6, rings=4)
    p.finish()


# ================================================================== the freight routes
def rail_freight():
    """2 m of industrial guard rail (along X): yellow pipe rails, a mesh panel, a toe board with hazard stripes"""
    p = Prop('rt_rail_freight'); y = K('paint', YELLOW); dk = K('metal', STEEL_DK)
    cyl(p, 0.045, 2.0, y, (0, 1.02, 0), RZ, seg=10, b=0)
    cyl(p, 0.035, 2.0, y, (0, 0.55, 0), RZ, seg=8, b=0)
    box(p, (2.0, 0.16, 0.03), K('hazard'), (0, 0.08, 0), b=0.005, seg=1)
    # the mesh: a grid of thin wires in a frame
    box(p, (1.9, 0.02, 0.02), dk, (0, 0.95, 0), b=0); box(p, (1.9, 0.02, 0.02), dk, (0, 0.18, 0), b=0)
    for k in range(20):
        x = -0.9 + k * 0.095
        box(p, (0.008, 0.77, 0.008), dk, (x, 0.565, 0), b=0, seg=1)
    for k in range(8):
        box(p, (1.9, 0.008, 0.008), dk, (0, 0.24 + k * 0.095, 0), b=0, seg=1)
    p.finish()


def freight_post():
    p = Prop('rt_freight_post'); y = K('paint', YELLOW)
    box(p, (0.3, 0.04, 0.3), K('metal', STEEL_DK), (0, 0.02, 0), b=0.01)
    cyl(p, 0.06, 1.1, y, (0, 0.57, 0), seg=10, b=0)
    sph(p, 0.065, y, (0, 1.12, 0), seg=10, rings=6)
    for x in (-0.1, 0.1):
        cyl(p, 0.02, 0.03, K('metal', STEEL), (x, 0.045, 0.1), seg=6, b=0)
    p.finish()


def girder_bay():
    """6 m of plate-girder deck structure (along Z) for the freight routes: two deep girders under the deck
    edges with stiffeners and flanges, X bracing between them, a pipe run and a cable tray on brackets,
    red marker lights on the girder ends."""
    p = Prop('rt_girder_bay'); st, sd = K('metal', STEEL), K('metal', STEEL_DK)
    for sx in (-1, 1):
        x = sx * 3.4
        box(p, (0.08, 1.7, 6.0), st, (x, -1.45, 0), b=0.0)
        box(p, (0.55, 0.08, 6.0), sd, (x, -0.62, 0), b=0.01)
        box(p, (0.55, 0.1, 6.0), sd, (x, -2.3, 0), b=0.01)
        for k in range(7):
            z = -3.0 + k
            for side in (-1, 1): box(p, (0.16, 1.6, 0.05), sd, (x + side * 0.1, -1.45, z), b=0, seg=1)
        # rivets along the top flange (just a few bumps)
        for k in range(12): sph(p, 0.03, sd, (x + sx * 0.04, -0.75, -2.75 + k * 0.5), seg=6, rings=4)
    # bottom bracing
    for k in range(2):
        z0, z1 = -3.0 + k * 3.0, k * 3.0
        rod(p, (-3.35, -2.25, z0), (3.35, -2.25, z1), 0.06, sd)
        rod(p, (-3.35, -2.25, z1), (3.35, -2.25, z0), 0.06, sd)
    box(p, (6.8, 0.2, 0.2), sd, (0, -2.25, -3.0), b=0.02)
    # pipes on hangers along the north side, a cable tray on the south
    for k in range(3):
        z = -2.0 + k * 2.0
        rod(p, (2.1, -0.7, z), (2.1, -2.0, z), 0.03, sd)
        box(p, (1.1, 0.06, 0.08), sd, (2.45, -2.0, z), b=0)
        rod(p, (-2.1, -0.7, z), (-2.1, -1.5, z), 0.03, sd)
        box(p, (1.0, 0.05, 0.06), sd, (-2.45, -1.5, z), b=0)
    cyl(p, 0.2, 6.0, K('paint', PIPE_RED), (2.25, -1.78, 0), RX, seg=14, b=0)
    cyl(p, 0.13, 6.0, K('paint', PIPE_TEAL), (2.75, -1.85, 0), RX, seg=12, b=0)
    for z in (-2.95, 2.95):
        tor(p, 0.21, 0.04, sd, (2.25, -1.78, z), (0, 0, 0), seg=14, tube=5)
    box(p, (0.8, 0.12, 6.0), K('metal', 0x5a646e), (-2.45, -1.4, 0), b=0.01)
    for k in range(3):
        box(p, (0.65, 0.1, 0.12), K('rubber'), (-2.45 - 0.1 + k * 0.1, -1.3, 0), rot=(0, 0.02 * k, 0), b=0.0)
    # marker lights at one end of each girder (the game turns some off)
    for sx in (-1, 1):
        sph(p, 0.07, K('glow', 0xff4030), (sx * 3.48, -2.2, 2.9), seg=8, rings=6)
    p.finish()


def sign_gantry():
    """A sign gantry over the freight routes: two lattice posts (x +-4.6), a box-truss beam at 5.4 m, a big
    sign board facing +Z (text is a Label3D), little floodlights over the board, a maintenance walk."""
    p = Prop('rt_sign_gantry'); y = K('paint', YELLOW); sd = K('metal', STEEL_DK)
    for sx in (-1, 1):
        x = sx * 4.6
        box(p, (0.8, 0.3, 0.8), K('metal', STEEL), (x, 0.15, 0), b=0.03)
        for cx in (-0.22, 0.22):
            for cz in (-0.22, 0.22):
                box(p, (0.09, 5.8, 0.09), y, (x + cx, 3.05, cz), b=0.0, seg=1)
        for k in range(8):
            yy = 0.5 + k * 0.7
            for cz in (-0.22, 0.22): rod(p, (x - 0.22, yy, cz), (x + 0.22, yy + 0.7, cz), 0.025, y)
            for cx in (-0.22, 0.22): rod(p, (x + cx, yy, -0.22), (x + cx, yy + 0.7, 0.22), 0.025, y)
    # the beam: a box truss along X
    for cy in (5.3, 6.1):
        for cz in (-0.3, 0.3):
            box(p, (9.8, 0.1, 0.1), y, (0, cy, cz), b=0.0, seg=1)
    for k in range(14):
        x = -4.55 + k * 0.7
        rod(p, (x, 5.3, 0.3), (x + 0.7, 6.1, 0.3), 0.025, y)
        rod(p, (x, 5.3, -0.3), (x + 0.7, 6.1, -0.3), 0.025, y)
    # the walkway grating behind the sign
    box(p, (8.6, 0.05, 0.7), sd, (0, 5.25, -0.75), b=0.0)
    box(p, (8.6, 0.04, 0.04), y, (0, 6.2, -1.05), b=0.0)
    # the sign board
    box(p, (6.6, 1.5, 0.12), K('paint', 0x1f5a4e), (0, 5.7, 0.42), b=0.03)
    box(p, (6.4, 1.3, 0.06), K('paint', 0x247060), (0, 5.7, 0.5), b=0.01, seg=1)
    box(p, (6.66, 0.06, 0.15), K('paint', 0xf1f3f5), (0, 6.42, 0.44), b=0, seg=1)
    box(p, (6.66, 0.06, 0.15), K('paint', 0xf1f3f5), (0, 4.98, 0.44), b=0, seg=1)
    p.mark('sign', (0, 5.7, 0.54))
    for x in (-2.2, 0.0, 2.2):
        rod(p, (x, 6.15, 0.35), (x, 6.6, 0.85), 0.03, sd)
        cyl(p, 0.12, 0.2, sd, (x, 6.6, 0.95), RX, r2=0.16, seg=10, b=0.01)
        box(p, (0.2, 0.06, 0.04), K('glow', 0xfff0c8), (x, 6.55, 1.06), b=0, seg=1)
    p.finish()


def flood_mast():
    """A floodlight mast for the freight routes: a tapered steel pole on a bolted base, a ladder, a head frame
    with three lamps tilted down toward +Z."""
    p = Prop('rt_flood_mast'); y = K('paint', YELLOW); sd = K('metal', STEEL_DK); st = K('metal', STEEL)
    box(p, (0.9, 0.2, 0.9), st, (0, 0.1, 0), b=0.03)
    for cx in (-0.32, 0.32):
        for cz in (-0.32, 0.32): cyl(p, 0.04, 0.12, sd, (cx, 0.26, cz), seg=6, b=0)
    cyl(p, 0.22, 9.0, y, (0, 4.6, 0), r2=0.12, seg=12, b=0)
    for k in range(6): tor(p, 0.2 - k * 0.012, 0.025, sd, (0, 1.2 + k * 1.4, 0), RX, seg=12, tube=4)
    # ladder up the back
    for sx in (-0.18, 0.18): box(p, (0.03, 7.5, 0.03), sd, (sx, 4.6, -0.3), b=0, seg=1)
    for k in range(24): box(p, (0.36, 0.025, 0.025), sd, (0, 1.0 + k * 0.31, -0.3), b=0, seg=1)
    # head frame
    box(p, (2.2, 0.1, 0.1), sd, (0, 9.1, 0.1), b=0.0)
    box(p, (2.2, 0.1, 0.1), sd, (0, 9.7, 0.1), b=0.0)
    for x in (-0.75, 0.0, 0.75):
        rot = (0.6, 0, 0)
        box(p, (0.6, 0.45, 0.32), K('metal', IRON), (x, 9.4, 0.35), rot=rot, b=0.04)
        box(p, (0.5, 0.36, 0.04), K('glow', 0xfff2d8), (x, 9.32, 0.5), rot=rot, b=0, seg=1)
    p.mark('light_0', (0, 9.2, 0.8))
    p.finish()


def cable_pylon():
    """an iron lattice pylon (lattice only, so it can be stretched): four corner legs tapering from 0.84 m to
    0.36 m over 8 m, X bracing in six panels, a stone footing and a cap plate. The game scales it (height to the
    cable, width for the tall ones dropping into the clouds) and puts rt_pylon_head / rt_pylon_arm on top."""
    p = Prop('rt_cable_pylon'); ir = K('metal', IRON_LT); dk = K('metal', IRON)
    h = 8.0; b0, b1 = 0.42, 0.18
    box(p, (1.1, 0.35, 1.1), S(STONE_LT), (0, 0.17, 0), b=0.05)
    for cx in (-1, 1):
        for cz in (-1, 1):
            rod(p, (cx * b0, 0.3, cz * b0), (cx * b1, h, cz * b1), 0.05, ir)
    sq = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for k in range(6):
        y0 = 0.3 + k * (h - 0.3) / 6; y1 = y0 + (h - 0.3) / 6
        w0 = b0 + (b1 - b0) * (y0 / h); w1 = b0 + (b1 - b0) * (y1 / h)
        for side in range(4):
            a = sq[side]; b_ = sq[(side + 1) % 4]
            rod(p, (a[0] * w0, y0, a[1] * w0), (b_[0] * w1, y1, b_[1] * w1), 0.022, ir)
            rod(p, (b_[0] * w0, y0, b_[1] * w0), (a[0] * w1, y1, a[1] * w1), 0.022, ir)
            rod(p, (a[0] * w1, y1, a[1] * w1), (b_[0] * w1, y1, b_[1] * w1), 0.03, dk)
    box(p, (0.5, 0.14, 0.5), dk, (0, h, 0), b=0.02)
    p.finish()


def pylon_head():
    """the unscaled top of a pylon: a teal crown with brass bands, a glass lantern, a brass finial and a little
    pennant (origin at the pylon's cap)"""
    p = Prop('rt_pylon_head'); ir = K('metal', IRON); br = K('brass')
    box(p, (0.62, 0.12, 0.62), K('paint', TEAL), (0, 0.06, 0), b=0.02)
    for cx in (-1, 1):
        for cz in (-1, 1):
            rod(p, (cx * 0.22, 0.1, cz * 0.22), (cx * 0.12, 0.95, cz * 0.12), 0.025, ir)
    cyl(p, 0.2, 0.08, br, (0, 0.14, 0), seg=10, b=0)
    cyl(p, 0.16, 0.5, K('glass', GLASS), (0, 0.48, 0), seg=8, b=0)
    sph(p, 0.1, K('glow', AMBER), (0, 0.48, 0), seg=10, rings=6)
    cyl(p, 0.22, 0.14, K('paint', TEAL), (0, 0.8, 0), r2=0.05, seg=8, b=0.01)
    tor(p, 0.17, 0.02, br, (0, 0.74, 0), RX, seg=12, tube=4)
    rod(p, (0, 0.9, 0), (0, 1.75, 0), 0.02, br)
    sph(p, 0.06, br, (0, 1.78, 0), seg=8, rings=6)
    # a swallow-tail pennant on the finial
    box(p, (0.6, 0.22, 0.015), K('cloth', SAFFRON), (0.32, 1.55, 0), rot=(0, 0, -0.08), b=0, seg=1)
    box(p, (0.2, 0.09, 0.016), K('cloth', CRIMSON), (0.66, 1.6, 0), rot=(0, 0, 0.3), b=0, seg=1)
    box(p, (0.2, 0.09, 0.016), K('cloth', CRIMSON), (0.66, 1.48, 0), rot=(0, 0, -0.4), b=0, seg=1)
    p.mark('light_0', (0, 0.48, 0))
    p.finish()


def pylon_arm():
    """a lattice arm along +X from 0 to 1 m (the game stretches it along X to reach the cable): a top chord, a
    lower chord meeting it at the end, zigzag web, and a cable saddle with a sheave at x 1"""
    p = Prop('rt_pylon_arm'); ir = K('metal', IRON_LT); br = K('brass')
    for z in (-0.12, 0.12):
        rod(p, (0, 0, z), (1.0, 0, z), 0.035, ir)
        rod(p, (0, -0.55, z), (1.0, -0.12, z), 0.03, ir)
        for k in range(6):
            x0 = k / 6; x1 = (k + 1) / 6
            y0 = -0.55 + 0.43 * x0; y1 = -0.55 + 0.43 * x1
            if k % 2 == 0: rod(p, (x0, y0, z), (x1, 0, z), 0.014, ir)
            else: rod(p, (x0, 0, z), (x1, y1, z), 0.014, ir)
    box(p, (0.06, 0.16, 0.34), K('metal', IRON), (1.0, -0.05, 0), b=0)
    cyl(p, 0.14, 0.06, br, (1.0, -0.22, 0), RX, seg=12, b=0)
    p.finish()


def cable_tower():
    """The bullwheel tower at each end of the Skyline Cableway, straddling the station deck (legs at z +-3, the
    cable leaves along +X): teal lattice legs on stone plinths, a cream machine house on a girder, the bullwheel
    turning flat on the +X side with sheaves, brass trim, lanterns on the corners, a board for the line's name."""
    p = Prop('rt_cable_tower'); tl = K('paint', TEAL); br = K('brass'); ir = K('metal', IRON)
    for sz in (-1, 1):
        z = sz * 3.0
        box(p, (0.9, 0.36, 0.9), S(STONE_LT), (0, 0.18, z), b=0.05)
        for cx in (-0.25, 0.25):
            rod(p, (cx, 0.36, z - 0.25), (cx * 0.6, 4.9, z * 0.92 - 0.15), 0.05, tl)
            rod(p, (cx, 0.36, z + 0.25), (cx * 0.6, 4.9, z * 0.92 + 0.15), 0.05, tl)
        for k in range(5):
            y0 = 0.4 + k * 0.9
            rod(p, (-0.22, y0, z - 0.22), (0.2, y0 + 0.9, z + 0.2), 0.02, ir)
            rod(p, (0.22, y0, z - 0.22), (-0.2, y0 + 0.9, z + 0.2), 0.02, ir)
        tor(p, 0.3, 0.035, br, (0, 1.2, z), RX, seg=12, tube=4)
    # cross girder and the machine house
    box(p, (0.6, 0.45, 7.2), ir, (0, 4.95, 0), b=0.03)
    box(p, (0.3, 0.25, 6.2), tl, (0, 3.9, 0), b=0.02)
    box(p, (2.2, 1.5, 2.6), K('paint', CREAM), (-0.3, 5.95, 0), b=0.05)
    for sz in (-1, 1):
        box(p, (0.04, 0.5, 0.5), K('glow', AMBER), (-1.42, 6.0, sz * 0.7), b=0, seg=1)
        box(p, (0.06, 0.62, 0.62), br, (-1.4, 6.0, sz * 0.7), b=0.01, seg=1)
    # roof with a ridge and brass finials
    for sx in (-1, 1):
        box(p, (1.5, 0.1, 3.0), tl, (-0.3 + sx * 0.6, 6.95, 0), rot=(0, 0, -sx * 0.4), b=0.02)
    cyl(p, 0.07, 3.0, br, (-0.3, 7.25, 0), RX, seg=8, b=0)
    for sz in (-1, 1): sph(p, 0.12, br, (-0.3, 7.25, sz * 1.5), seg=10, rings=6)
    # the bullwheel: a big flat wheel with spokes on the +X side
    cyl(p, 0.18, 1.2, ir, (1.1, 5.2, 0), seg=10, b=0)
    tor(p, 1.25, 0.09, ir, (1.1, 5.25, 0), (0, 0, 0), seg=28, tube=6)
    tor(p, 1.12, 0.04, K('paint', CRIMSON), (1.1, 5.25, 0), (0, 0, 0), seg=28, tube=5)
    for k in range(8):
        a = TAU * k / 8
        rod(p, (1.1, 5.25, 0), (1.1 + math.cos(a) * 1.15, 5.25, math.sin(a) * 1.15), 0.03, ir)
    cyl(p, 0.22, 0.2, br, (1.1, 5.85, 0), seg=10, b=0.01)
    # sheave wheels on the cable side
    for sz in (-1, 1):
        cyl(p, 0.22, 0.06, ir, (2.3, 5.0, sz * 1.15), RX, seg=12, b=0)
    # name board (Label3D in the game) hanging under the girder, facing +X and -X
    box(p, (0.14, 0.7, 3.2), K('paint', 0x1e3a3a), (0, 4.35, 0), b=0.03)
    for sx in (-1, 1): box(p, (0.03, 0.62, 3.1), br, (sx * 0.085, 4.35, 0), b=0.0, seg=1)
    p.mark('sign', (0.1, 4.35, 0))
    # corner lanterns
    for sz in (-1, 1):
        rod(p, (0, 5.2, sz * 3.6), (0, 4.6, sz * 3.6), 0.015, ir)
        sph(p, 0.22, K('glow', 0xffb060), (0, 4.4, sz * 3.6), (1, 1.2, 1), seg=10, rings=6)
        p.mark('light_%d' % (0 if sz < 0 else 1), (0, 4.4, sz * 3.6))
    p.finish()


def garden_lamp():
    """a garden-style lamp post for the stations and the barge: a slim teal post on a stone foot, a crook with a
    glass globe, a hanging flower basket"""
    p = Prop('rt_garden_lamp'); tl = K('paint', TEAL); br = K('brass')
    box(p, (0.42, 0.24, 0.42), S(STONE_LT), (0, 0.12, 0), b=0.04)
    cyl(p, 0.09, 3.2, tl, (0, 1.84, 0), r2=0.06, seg=10, b=0)
    for y in (0.5, 1.6): tor(p, 0.09, 0.025, br, (0, y, 0), RX, seg=12, tube=4)
    tor(p, 0.28, 0.035, tl, (0.28, 3.44, 0), (math.pi / 2, 0, 0), seg=14, tube=5, arc=math.pi)
    rod(p, (0.56, 3.44, 0), (0.56, 3.25, 0), 0.02, tl)
    cyl(p, 0.14, 0.08, br, (0.56, 3.22, 0), seg=10, b=0)
    sph(p, 0.2, K('glass', GLASS), (0.56, 2.98, 0), seg=12, rings=8)
    sph(p, 0.1, K('glow', AMBER), (0.56, 2.98, 0), seg=10, rings=6)
    p.mark('light_0', (0.56, 2.98, 0))
    # flower basket on a bracket on the other side
    rod(p, (0, 2.5, 0), (-0.5, 2.5, 0), 0.02, K('metal', IRON))
    rod(p, (-0.5, 2.5, 0), (-0.5, 2.25, 0), 0.012, K('metal', IRON))
    sph(p, 0.2, K('wood', WOOD_DK), (-0.5, 2.05, 0), (1, 0.6, 1), seg=10, rings=6)
    for k in range(7):
        a = TAU * k / 7
        sph(p, 0.09, K('leaf', LEAF if k % 2 else LEAF_DK), (-0.5 + math.cos(a) * 0.15, 2.16, math.sin(a) * 0.15), seg=6, rings=4)
        sph(p, 0.05, K('paint', FLOWERS[k % len(FLOWERS)]), (-0.5 + math.cos(a + 0.4) * 0.14, 2.24, math.sin(a + 0.4) * 0.14), seg=6, rings=4)
    for k in range(4):
        a = TAU * k / 4 + 0.3
        for j in range(3):
            sph(p, 0.045, K('leaf', LEAF_DK), (-0.5 + math.cos(a) * 0.2, 1.95 - j * 0.12, math.sin(a) * 0.2), seg=6, rings=4)
    p.finish()


def pennants():
    """a single cloth pennant hanging from its origin (under a cable), 0.34 wide, 0.5 long; three colours"""
    for name, c in (('rt_pennant_a', SAFFRON), ('rt_pennant_b', TEAL), ('rt_pennant_c', CRIMSON)):
        p = Prop(name)
        bm = bmesh.new()
        v = [bm.verts.new(q) for q in ((-0.17, 0, -0.01), (0.17, 0, -0.01), (0, -0.5, -0.01), (-0.17, 0, 0.01), (0.17, 0, 0.01), (0, -0.5, 0.01))]
        bm.faces.new((v[0], v[2], v[1])); bm.faces.new((v[3], v[4], v[5]))
        for a, b_ in ((0, 1), (1, 2), (2, 0)):
            bm.faces.new((v[a], v[b_], v[b_ + 3], v[a + 3]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        p.add(bm, K('cloth', c), smooth=False)
        box(p, (0.38, 0.03, 0.03), K('cloth', CREAM), (0, -0.01, 0), b=0, seg=1)
        p.finish()


def loft(sections):
    """a closed hull through rings of the same length: [(z, [(x, y), ...]), ...]; caps at both ends"""
    bm = bmesh.new()
    rings = [[bm.verts.new((x, y, z)) for x, y in pts] for z, pts in sections]
    n = len(rings[0])
    for a, b_ in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b_[j], b_[i]))
    bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def barge_hull():
    """The balloon barge's hull under its 8 x 12 deck (deck top y 0, long along Z, bow toward -Z): a rounded
    painted hull with a gold rubbing strake, glowing portholes, a keel fin, two propeller pods at the stern,
    a brass prow with a lamp; mooring bollards on the deck edge."""
    p = Prop('rt_barge_hull'); hull = K('paint', 0x2a5f9e); gd = K('brass'); dk = K('paint', 0x1d3f6a)
    secs = []
    for z in [-7.4, -6.8, -6.0, -4.6, -2.5, 0.0, 2.5, 4.5, 5.6, 6.2]:
        if z < 0: u = abs(z) / 7.4; w = 4.0 * (1 - u ** 3.0); d = 2.6 * (1 - u ** 2.0) + 0.25
        else: u = z / 6.2; w = 4.0 * (1 - u ** 5.0) * 0.98 + 0.02; d = 2.6 * (1 - u ** 3.0) + 0.25
        w = max(w, 0.35)
        ring = [(-w, -0.1), (w, -0.1)]
        ring = []
        for k in range(12):
            a = math.pi * k / 11
            ring.append((math.cos(a) * w, -0.1 - math.sin(a) * d))
        secs.append((z, ring))
    p.add(loft(secs), hull, b=0.0, angle=50)
    # the rubbing strake and a painted band
    box(p, (8.15, 0.22, 11.4), gd, (0, -0.25, -0.4), b=0.05)
    box(p, (7.9, 0.3, 10.6), K('paint', CREAM), (0, -0.55, -0.3), b=0.04)
    # portholes along both sides
    for sx in (-1, 1):
        for k in range(5):
            z = -3.6 + k * 1.8
            cyl(p, 0.2, 0.08, gd, (sx * 3.9, -1.15, z), RZ, seg=12, b=0)
            cyl(p, 0.14, 0.09, K('glow', 0xffc070), (sx * 3.92, -1.15, z), RZ, seg=12, b=0)
    # keel fin and the stern pods with fans
    box(p, (0.18, 1.2, 7.5), dk, (0, -3.0, 0.4), b=0.05)
    for sx in (-1, 1):
        rod(p, (sx * 2.4, -1.4, 4.4), (sx * 4.2, -1.8, 5.2), 0.1, K('metal', IRON))
        cyl(p, 0.45, 1.5, K('paint', CREAM), (sx * 4.5, -1.9, 5.3), RX, r2=0.32, seg=14, b=0.02)
        tor(p, 0.62, 0.06, gd, (sx * 4.5, -1.9, 6.15), RX, seg=18, tube=5)
        for k in range(4):
            a = TAU * k / 4 + 0.4
            box(p, (0.16, 0.55, 0.04), K('metal', STEEL), (sx * 4.5 + math.cos(a) * 0.28, -1.9 + math.sin(a) * 0.28, 6.1), rot=(0, 0, a + math.pi / 2), b=0, seg=1)
        box(p, (0.08, 1.3, 1.4), K('paint', CRIMSON), (sx * 1.6, -0.9, 5.6), rot=(0, sx * 0.1, 0), b=0.02)
    # the prow: a brass beak with a lamp
    rod(p, (0, -0.6, -7.2), (0, 0.2, -8.4), 0.12, gd)
    sph(p, 0.25, K('glow', 0xffb060), (0, 0.3, -8.5), seg=10, rings=6)
    p.mark('light_0', (0, 0.3, -8.8))
    # bollards along the deck edge
    for sx in (-1, 1):
        for z in (-5.0, 5.0):
            cyl(p, 0.14, 0.45, K('metal', IRON), (sx * 3.6, 0.22, z), seg=10, b=0.01)
            cyl(p, 0.2, 0.06, gd, (sx * 3.6, 0.46, z), seg=10, b=0)
    p.finish()


def barge_envelope():
    """The barge's gas envelope, 15 m over the deck (origin at deck centre): a striped spindle, a brass nose
    cone, fins, load bands, a spreader bar with bunting and ropes down to the deck corners"""
    p = Prop('rt_barge_envelope'); cr, cm = K('cloth', CRIMSON), K('cloth', CREAM); gd = K('brass')
    rope = K('cloth', 0x8a6a4a)
    yc = 15.0; L = 13.0; R = 3.4; n = 12
    for k in range(n):
        z0 = -L / 2 + L * k / n; z1 = z0 + L / n
        r0 = R * math.sqrt(max(0.0, 1 - (2 * z0 / L) ** 2)); r1 = R * math.sqrt(max(0.0, 1 - (2 * z1 / L) ** 2))
        cyl(p, max(r0, 0.05), L / n, cr if k % 2 else cm, (0, yc, (z0 + z1) / 2), RX, r2=max(r1, 0.05), seg=20, b=0, cap=False)
    cyl(p, 0.35, 0.5, gd, (0, yc, -L / 2), RX, r2=0.05, seg=12, b=0)
    for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
        box(p, (0.08, 1.6, 1.8), K('paint', SAFFRON), (math.cos(a) * 1.3, yc + math.sin(a) * 1.3, L / 2 - 0.6), rot=(0, 0, a + math.pi / 2), b=0.02)
    for z in (-3.5, 0.0, 3.5):
        tor(p, R * 1.0 * math.sqrt(1 - (2 * z / L) ** 2), 0.05, rope, (0, yc, z), RX, seg=24, tube=4)
    box(p, (0.2, 0.2, 9.0), K('wood', WOOD_DK), (0, yc - R - 0.5, 0), b=0.02)
    for sz in (-1, 1):
        for sx in (-1, 1):
            rod(p, (0, yc - R - 0.5, sz * 4.4), (sx * 3.55, 0.6, sz * 5.6), 0.03, rope, seg=5)
            rod(p, (sx * 1.2, yc - R + 0.3, sz * 2.0), (0, yc - R - 0.5, sz * 3.0), 0.025, rope, seg=5)
    for k in range(12):
        z = -4.2 + k * 0.76
        box(p, (0.02, 0.36, 0.3), K('cloth', [SAFFRON, TEAL, CREAM, PLUM][k % 4]), (0, yc - R - 0.8, z), rot=(0.0, 0, 0), b=0, seg=1)
    p.finish()


def signal_lamp():
    """a dish rail signal: a short post carrying a hooded red-over-green lamp head and a brass number plate"""
    p = Prop('rt_signal_lamp'); ir = K('metal', IRON)
    cyl(p, 0.06, 1.6, ir, (0, 0.8, 0), seg=8, b=0)
    box(p, (0.36, 0.8, 0.22), K('paint', 0x1e2a30), (0, 1.9, 0), b=0.03)
    for y, c in ((2.1, 0xff4030), (1.7, 0x40ff80)):
        cyl(p, 0.11, 0.06, K('glow', c), (0, y, 0.12), RX, seg=10, b=0)
        cyl(p, 0.14, 0.14, ir, (0, y + 0.06, 0.16), RX, seg=10, b=0, cap=False)
    box(p, (0.24, 0.16, 0.03), K('brass'), (0, 1.35, 0.06), b=0.0, seg=1)
    p.mark('light_0', (0, 2.1, 0.3))
    p.finish()


ALL = [pier, arch, parapet, parapet_post, lamp_twin, flower_boxes, banners,
       rail_lacquer, lacquer_post, lantern_gate, lantern_pier, timber_bay,
       rail_freight, freight_post, girder_bay, sign_gantry, flood_mast, cable_pylon,
       pylon_head, pylon_arm, cable_tower, garden_lamp, pennants, barge_hull, barge_envelope, signal_lamp]

if __name__ == '__main__':
    want = [a for a in sys.argv[1:] if not a.startswith('-')]
    for f in ALL:
        if want and f.__name__ not in want: continue
        f()
    print('total tris', sum(sk.TRIS.values()))
