"""The Skyharbor art kit: every prop the level places through godot/scripts/kit.gd, built from beveled primitives.

Conventions (match kit.gd):
- Authored in game coordinates: Y up, +Z is the prop's front. Origin at the base center (y = 0 is the floor).
- Every part gets a beveled edge with hardened normals so it catches highlights, then the parts of a prop are
  joined into one mesh per moving piece (few draw calls). Moving pieces become named nodes with their origin at
  the pivot (e.g. wind_turbine/rotor spins about its local Z).
- Material names follow k_<kind>_<rrggbb>. kit.gd swaps each one for a textured Godot material from mats.gd
  (painted metal, brass, rubber, glass, glow, cloth, wood, deck, hazard, ...), so the colors here are the real
  colors and the Blender materials are only a fallback. k_sign_<name> materials carry a decal texture.
- Empties named light_* mark where kit.gd adds a small warm OmniLight3D.

Run: /tmp/claude-0/bpyenv/bin/python art/skyharbor_kit.py [prop names...]   (writes godot/models/kit/<name>.glb)
"""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from blib import reset, mat, glowmat, bm_box, bm_cyl, bm_sphere, bm_torus, G2B
import bpy, bmesh
from mathutils import Matrix, Vector, Euler

OUT = os.path.normpath(os.path.join(HERE, '..', 'godot', 'models', 'kit'))
TEX = os.path.normpath(os.path.join(HERE, '..', 'godot', 'textures'))
os.makedirs(OUT, exist_ok=True)
TAU = math.tau
RX = (math.pi / 2, 0, 0)   # cylinder axis along Z
RZ = (0, 0, math.pi / 2)   # cylinder axis along X

# ---------------- palette ----------------
CREAM, WHITE, TEAL, SKY, NAVY = 0xefe4cc, 0xf1f3f5, 0x2f9e9b, 0x5b8fc0, 0x2b4763
ORANGE, RED, YEL, GREEN, PINK, PURPLE = 0xf0862a, 0xd2473a, 0xf4c232, 0x58a86a, 0xe2457a, 0x6a4ea6
DARK, STEEL, CHROME, BRASS, RUB = 0x3a434e, 0x8c98a5, 0xd6dce2, 0xd9a441, 0x26292e
GLASS, WOOD, TWIG, LEAF, SOIL = 0xa8e4f4, 0xb07a48, 0x7a5233, 0x4fae5c, 0x4a3424
AMBER, CYAN, REDG, GRNG, ORG, GOLDG = 0xffa640, 0x46f0ff, 0xff3c3c, 0x66ff8c, 0xff7a1a, 0xffd24a

PARAMS = {  # kind: (metal, rough)
    'paint': (0.3, 0.42), 'metal': (0.85, 0.38), 'chrome': (1.0, 0.14), 'brass': (0.95, 0.28), 'rubber': (0.0, 0.8),
    'glass': (0.1, 0.05), 'cloth': (0.0, 0.85), 'wood': (0.0, 0.65), 'leaf': (0.0, 0.7), 'soil': (0.0, 1.0),
    'deck': (0.45, 0.5), 'hazard': (0.2, 0.5), 'rust': (0.45, 0.8),
}
_mats = {}


def K(kind, c=0x888888):
    if kind == 'brass' and c == 0x888888: c = BRASS
    if kind == 'hazard': c = YEL
    if kind == 'deck': c = 0xc8d2dc
    name = 'k_%s_%06x' % (kind, c)
    if name in _mats: return _mats[name]
    if kind == 'glow':
        m = glowmat(name, c, 6)
    else:
        metal, rough = PARAMS[kind]
        m = mat(name, c, metal, rough, alpha=0.35 if kind == 'glass' else 1.0)
        if kind == 'glass':
            m.node_tree.nodes['Principled BSDF'].inputs['Alpha'].default_value = 0.35
            if hasattr(m, 'surface_render_method'): m.surface_render_method = 'BLENDED'
    _mats[name] = m
    return m


def SIGN(name):
    key = 'k_sign_' + name
    if key in _mats: return _mats[key]
    m = bpy.data.materials.new(key); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    img = bpy.data.images.load(os.path.join(TEX, 'sign_%s.png' % name))
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = img
    nt.links.new(t.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.45; b.inputs['Metallic'].default_value = 0.1
    _mats[key] = m
    return m


# ---------------- prop builder ----------------
class Prop:
    def __init__(s, name):
        reset(); _mats.clear()
        s.name = name; s.groups = {None: []}; s.piv = {}; s.parent = {}; s.marks = {}; s.n = 0

    def pivot(s, name, at, parent=None):
        s.piv[name] = Vector(at); s.groups[name] = []; s.parent[name] = parent

    def mark(s, name, at): s.marks[name] = Vector(at)

    def add(s, bm, m, at=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), b=0.0, seg=2, grp=None, smooth=True, angle=35, mat3=None):
        R = mat3.to_4x4() if mat3 is not None else Euler(rot, 'ZYX').to_matrix().to_4x4()
        M = Matrix.Translation(Vector(at)) @ R @ Matrix.Diagonal(Vector(scale)).to_4x4()
        bmesh.ops.transform(bm, matrix=G2B @ M, verts=bm.verts)
        s.n += 1
        me = bpy.data.meshes.new('%s_%d' % (s.name, s.n)); bm.to_mesh(me); bm.free()
        for p in me.polygons: p.use_smooth = smooth
        if smooth and hasattr(me, 'set_sharp_from_angle'): me.set_sharp_from_angle(angle=math.radians(angle))
        o = bpy.data.objects.new(me.name, me); bpy.context.scene.collection.objects.link(o)
        me.materials.append(m)
        if b > 0:
            md = o.modifiers.new('bv', 'BEVEL'); md.width = b; md.segments = seg; md.limit_method = 'ANGLE'
            md.angle_limit = math.radians(angle); md.harden_normals = True; md.use_clamp_overlap = True
        s.groups[grp].append(o)
        return o

    def finish(s):
        root = bpy.data.objects.new(s.name, None); bpy.context.scene.collection.objects.link(root)
        made = {}
        for g, objs in s.groups.items():
            if not objs: continue
            for o in bpy.context.scene.objects: o.select_set(False)
            for o in objs: o.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            bpy.ops.object.convert(target='MESH')
            if len(objs) > 1: bpy.ops.object.join()
            o = bpy.context.view_layer.objects.active
            o.name = g or (s.name + '_body'); o.data.name = o.name
            if g:
                pb = G2B @ s.piv[g]; o.data.transform(Matrix.Translation(-pb))
                par = s.parent[g]
                if par and par in made:
                    o.parent = made[par]; o.location = pb - G2B @ s.piv[par]
                else:
                    o.parent = root; o.location = pb
            else:
                o.parent = root
            made[g] = o
        for n, at in s.marks.items():
            e = bpy.data.objects.new(n, None); bpy.context.scene.collection.objects.link(e)
            e.parent = root; e.location = G2B @ at
        for o in bpy.context.scene.objects: o.select_set(False)
        def sel(o):
            o.select_set(True)
            for c in o.children: sel(c)
        sel(root); bpy.context.view_layer.objects.active = root
        path = os.path.join(OUT, s.name + '.glb')
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
                                  export_extras=False, export_cameras=False, export_lights=False)
        dg = bpy.context.evaluated_depsgraph_get(); tris = 0
        for o in bpy.context.scene.objects:
            if o.type == 'MESH':
                me = o.evaluated_get(dg).to_mesh(); me.calc_loop_triangles(); tris += len(me.loop_triangles)
                o.evaluated_get(dg).to_mesh_clear()
        print('PROP %-18s %5d tris' % (s.name, tris))
        TRIS[s.name] = tris


TRIS = {}


# ---------------- primitive shortcuts ----------------
def box(p, size, m, at, rot=(0, 0, 0), b=0.03, seg=2, grp=None, mat3=None):
    return p.add(bm_box(*size), m, at, rot, b=b, seg=seg, grp=grp, mat3=mat3)


def cyl(p, r, h, m, at, rot=(0, 0, 0), r2=None, seg=20, b=0.015, bseg=2, grp=None, mat3=None, cap=True):
    return p.add(bm_cyl(r, r if r2 is None else r2, h, seg, cap), m, at, rot, b=b, seg=bseg, grp=grp, mat3=mat3)


def tor(p, R, r, m, at, rot=(0, 0, 0), seg=28, tube=8, arc=TAU, grp=None, mat3=None):
    return p.add(bm_torus(R, r, seg, tube, arc), m, at, rot, grp=grp, mat3=mat3, angle=80)


def sph(p, r, m, at, scale=(1, 1, 1), seg=16, rings=10, grp=None, rot=(0, 0, 0)):
    return p.add(bm_sphere(r, seg, rings), m, at, rot, scale, grp=grp, angle=80)


def rod(p, a, b_, r, m, seg=8, grp=None, bev=0.0):
    a, b_ = Vector(a), Vector(b_); d = b_ - a
    q = Vector((0, 1, 0)).rotation_difference(d.normalized())
    return p.add(bm_cyl(r, r, d.length, seg, True), m, tuple((a + b_) / 2), mat3=q.to_matrix(), b=bev, grp=grp)


def decal(p, w, h, m, at, rot=(0, 0, 0), grp=None):
    """A UV-mapped quad facing +Z (before rot) for sign textures."""
    bm = bmesh.new(); uv = bm.loops.layers.uv.new()
    vs = [bm.verts.new((x * w / 2, y * h / 2, 0)) for (x, y) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    f = bm.faces.new(vs)
    for l, c in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))): l[uv].uv = c
    return p.add(bm, m, at, rot, grp=grp, smooth=False)


def ring_xz(n, r, y, start=0.0):
    return [(math.cos(start + TAU * i / n) * r, y, math.sin(start + TAU * i / n) * r) for i in range(n)]


# =====================================================================================================
# props
# =====================================================================================================
def crate(name, s, color, accent):
    p = Prop(name); h = s / 2; fr = 0.13 * s
    dk = K('metal', DARK)
    box(p, (s * 0.92, s * 0.92, s * 0.92), K('paint', color), (0, h, 0), b=0.05 * s, seg=3)
    for x in (-1, 1):
        for z in (-1, 1):
            box(p, (fr, s * 0.98, fr), dk, (x * (h - fr / 2), h, z * (h - fr / 2)), b=0.025 * s)
    for y in (fr / 2, s - fr / 2):
        for (sx, sz, x, z) in ((s * 0.98, fr, 0, h - fr / 2), (s * 0.98, fr, 0, -h + fr / 2), (fr, s * 0.98, h - fr / 2, 0), (fr, s * 0.98, -h + fr / 2, 0)):
            box(p, (sx, fr, sz), dk, (x, y, z), b=0.025 * s)
    for x in (-1, 1):
        for y in (0, 1):
            for z in (-1, 1):
                box(p, (fr * 1.35,) * 3, K('brass'), (x * (h - fr / 2), fr / 2 + y * (s - fr), z * (h - fr / 2)), b=0.03 * s)
    for z in (-1, 1):  # stencil band + light strip front and back
        box(p, (s * 0.55, s * 0.13, 0.03), K('hazard'), (0, s * 0.64, z * s * 0.465), b=0.008, seg=1)
        box(p, (s * 0.3, s * 0.05, 0.03), K('glow', accent), (0, s * 0.42, z * s * 0.465))
    if s > 1.2:  # diagonal brace on the sides of the big one
        for x in (-1, 1):
            box(p, (0.06, s * 1.0, 0.1), dk, (x * s * 0.465, h, 0), rot=(0.785, 0, 0), b=0.02)
    p.finish()


def crate_small(): crate('crate_small', 1.0, ORANGE, AMBER)
def crate_large(): crate('crate_large', 1.6, TEAL, CYAN)


def barrel():
    p = Prop('barrel')
    cyl(p, 0.41, 1.12, K('paint', RED), (0, 0.6, 0), seg=24, b=0.04, bseg=3)
    cyl(p, 0.418, 0.2, K('paint', CREAM), (0, 0.6, 0), seg=24, b=0.01)
    for y in (0.06, 1.14): tor(p, 0.405, 0.035, K('metal', DARK), (0, y, 0), RX)
    for y in (0.33, 0.87): tor(p, 0.42, 0.03, K('metal', DARK), (0, y, 0), RX)
    cyl(p, 0.35, 0.03, K('metal', DARK), (0, 1.165, 0), seg=24)
    cyl(p, 0.06, 0.06, K('brass'), (0.18, 1.19, 0.05), seg=10, b=0.01)
    cyl(p, 0.04, 0.05, K('brass'), (-0.2, 1.185, -0.08), seg=10, b=0.01)
    box(p, (0.24, 0.12, 0.02), K('glow', AMBER), (0, 0.6, 0.42), b=0.0)
    p.finish()


def container(name, color, hanging=False):
    p = Prop(name); dk = K('metal', DARK); pc = K('paint', color)
    y0 = 0.0
    box(p, (4.86, 2.32, 2.26), pc, (0, 1.25, 0), b=0.05)
    nrib = 11 if hanging else 13
    for z in (-1, 1):
        for i in range(nrib):
            x = -2.2 + 4.4 * i / (nrib - 1)
            box(p, (0.16, 2.08, 0.08), pc, (x, 1.25, z * 1.15), b=0.02, seg=1)
    for i in range(4):
        z = -0.8 + 1.6 * i / 3
        box(p, (0.08, 2.08, 0.16), pc, (-2.45, 1.25, z), b=0.02, seg=1)
    for x in (-2.42, 2.42):
        for z in (-1.12, 1.12):
            box(p, (0.17, 2.5, 0.17), dk, (x, 1.25, z), b=0.03)
            for y in (0.09, 2.41): box(p, (0.24, 0.2, 0.24), K('brass'), (x, y, z), b=0.03)
    for y in (0.09, 2.41):
        for z in (-1.12, 1.12): box(p, (4.7, 0.17, 0.17), dk, (0, y, z), b=0.03)
        for x in (-2.42, 2.42): box(p, (0.17, 0.17, 2.1), dk, (x, y, 0), b=0.03)
    # doors on +X with lock bars
    for z in (-0.53, 0.53): box(p, (0.06, 2.1, 1.0), pc, (2.45, 1.25, z), b=0.02)
    for z in (-0.82, -0.25, 0.25, 0.82):
        cyl(p, 0.03, 2.05, K('brass'), (2.51, 1.25, z), seg=8, b=0)
        box(p, (0.06, 0.08, 0.14), dk, (2.53, 1.0, z + 0.06), b=0.01, seg=1)
    # stencil panel and running light on the long sides
    for z in (-1, 1):
        box(p, (1.6, 0.36, 0.04), K('paint', CREAM), (-1.2, 1.75, z * 1.2), b=0.01, seg=1)
        box(p, (1.2, 0.12, 0.05), K('hazard'), (1.3, 0.45, z * 1.2), b=0.01, seg=1)
    if hanging:  # spreader frame, cables and lifting ring
        box(p, (4.4, 0.22, 0.34), K('paint', YEL), (0, 2.86, 0), b=0.04)
        box(p, (4.0, 0.08, 0.36), K('hazard'), (0, 2.86, 0), b=0.01, seg=1)
        for x in (-2.0, 2.0):
            for z in (-1.0, 1.0): rod(p, (x, 2.5, z), (x * 0.95, 2.78, z * 0.15), 0.03, K('rubber', RUB))
            sph(p, 0.08, K('glow', AMBER), (x * 1.08, 2.86, 0), seg=10, rings=6)
            p.mark('light_%d' % (x > 0), (x * 1.08, 2.7, 0))
        for x in (-1.6, 1.6): rod(p, (x, 2.95, 0), (0, 3.25, 0), 0.035, K('rubber', RUB))
        tor(p, 0.14, 0.035, K('brass'), (0, 3.36, 0), seg=16, tube=6)
    p.finish()


def cargo_container(): container('cargo_container', 0xc8452f)
def hanging_container(): container('hanging_container', SKY, True)


def lamp_post():
    p = Prop('lamp_post'); dk = K('metal', DARK)
    cyl(p, 0.28, 0.22, K('brass'), (0, 0.11, 0), seg=8, b=0.03)
    cyl(p, 0.18, 0.3, dk, (0, 0.37, 0), r2=0.12, seg=12, b=0.02)
    cyl(p, 0.07, 3.0, dk, (0, 1.95, 0), r2=0.055, seg=12, b=0)
    for y in (1.0, 2.7): tor(p, 0.075, 0.03, K('brass'), (0, y, 0), RX, seg=14, tube=6)
    cyl(p, 0.17, 0.08, K('brass'), (0, 3.48, 0), seg=12, b=0.02)
    cyl(p, 0.14, 0.38, K('glass', GLASS), (0, 3.71, 0), seg=12, b=0)
    for i in range(4):
        a = TAU * i / 4 + 0.785
        cyl(p, 0.018, 0.4, K('brass'), (math.cos(a) * 0.14, 3.71, math.sin(a) * 0.14), seg=6, b=0)
    sph(p, 0.09, K('glow', AMBER), (0, 3.71, 0), seg=12, rings=8)
    cyl(p, 0.22, 0.2, dk, (0, 4.0, 0), r2=0.05, seg=12, b=0.02)
    sph(p, 0.045, K('brass'), (0, 4.13, 0), seg=10, rings=6)
    # little pennant on an arm
    rod(p, (0.05, 2.45, 0), (0.5, 2.45, 0), 0.02, K('brass'))
    box(p, (0.38, 0.6, 0.02), K('cloth', TEAL), (0.3, 2.13, 0), b=0.008, seg=1)
    box(p, (0.38, 0.06, 0.03), K('cloth', CREAM), (0.3, 1.88, 0), b=0.005, seg=1)
    p.mark('light_0', (0, 3.71, 0))
    p.finish()


def railing_2m():
    p = Prop('railing_2m'); dk = K('metal', DARK)
    cyl(p, 0.045, 2.0, K('brass'), (0, 1.05, 0), RZ, seg=12, b=0)
    cyl(p, 0.03, 2.0, dk, (0, 0.6, 0), RZ, seg=10, b=0)
    box(p, (2.0, 0.02, 0.02), K('glow', CYAN), (0, 0.99, 0.035), b=0)
    box(p, (2.0, 0.2, 0.06), K('paint', WHITE), (0, 0.12, 0), b=0.015)
    for x in (-0.5, 0.0, 0.5):
        cyl(p, 0.025, 0.92, dk, (x, 0.6, 0), seg=8, b=0)
    p.finish()


def railing_post():
    p = Prop('railing_post')
    cyl(p, 0.12, 0.05, K('brass'), (0, 0.025, 0), seg=8, b=0.01)
    box(p, (0.16, 1.08, 0.16), K('paint', WHITE), (0, 0.58, 0), b=0.03)
    box(p, (0.17, 0.06, 0.17), K('glow', CYAN), (0, 0.98, 0), b=0)
    cyl(p, 0.11, 0.05, K('brass'), (0, 1.14, 0), seg=8, b=0.01)
    sph(p, 0.09, K('brass'), (0, 1.2, 0), seg=12, rings=8)
    p.finish()


def bench():
    p = Prop('bench'); dk = K('metal', DARK); wd = K('wood', WOOD)
    for x in (-0.85, 0.85):
        box(p, (0.08, 0.42, 0.56), dk, (x, 0.21, 0), b=0.02)
        box(p, (0.07, 0.56, 0.08), dk, (x, 0.68, -0.26), rot=(-0.22, 0, 0), b=0.02)
        cyl(p, 0.035, 0.5, K('brass'), (x * 1.04, 0.62, 0.0), RX, seg=10, b=0.01)
        rod(p, (x * 1.04, 0.45, 0.22), (x * 1.04, 0.6, 0.22), 0.025, K('brass'))
    for z in (-0.18, 0.0, 0.18): box(p, (1.96, 0.05, 0.16), wd, (0, 0.45, z), b=0.015)
    for y in (0.64, 0.82): box(p, (1.96, 0.13, 0.04), wd, (0, y, -0.3 + (y - 0.64) * -0.2), rot=(-0.22, 0, 0), b=0.012)
    p.finish()


def planter():
    p = Prop('planter'); rng = random.Random(3)
    box(p, (1.6, 0.1, 1.6), K('metal', DARK), (0, 0.05, 0), b=0.03)
    box(p, (1.48, 0.72, 1.48), K('paint', TEAL), (0, 0.45, 0), b=0.06, seg=3)
    for i, (sx, sz, x, z) in enumerate(((1.62, 0.12, 0, 0.75), (1.62, 0.12, 0, -0.75), (0.12, 1.62, 0.75, 0), (0.12, 1.62, -0.75, 0))):
        box(p, (sx, 0.08, sz), K('brass'), (x, 0.84, z), b=0.025)
    box(p, (1.38, 0.05, 1.38), K('soil', SOIL), (0, 0.8, 0), b=0)
    for i in range(5):
        a = TAU * i / 5 + rng.uniform(0, 0.4); r = rng.uniform(0.25, 0.45)
        sph(p, rng.uniform(0.28, 0.38), K('leaf', LEAF), (math.cos(a) * r, 1.0 + rng.uniform(0, 0.15), math.sin(a) * r), (1, 0.8, 1), seg=12, rings=8)
    sph(p, 0.36, K('leaf', 0x3f9a50), (0, 1.25, 0), (1, 1.1, 1), seg=12, rings=8)
    for i in range(7):
        a = rng.uniform(0, TAU); r = rng.uniform(0.3, 0.55)
        sph(p, 0.06, K('paint', PINK if i % 2 else YEL), (math.cos(a) * r, rng.uniform(1.1, 1.4), math.sin(a) * r), seg=8, rings=5)
    p.finish()


def bunting(p, x0, x1, y, z, colors, n, size=0.2, tilt=0.0):
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n
        cyl(p, size, 0.02, K('cloth', colors[i % len(colors)]), (x, y - size * 0.5, z), rot=(math.pi / 2 + tilt, 0, -math.pi / 2), seg=3, b=0)


def market_stall():
    p = Prop('market_stall'); dk = K('metal', DARK); wd = K('wood', WOOD); rng = random.Random(5)
    box(p, (3.0, 0.95, 0.8), K('paint', CREAM), (0, 0.475, 0.5), b=0.04)
    box(p, (3.1, 0.08, 0.95), wd, (0, 0.99, 0.5), b=0.02)
    box(p, (3.0, 0.12, 0.05), K('brass'), (0, 0.8, 0.915), b=0.015)
    for i in range(5): box(p, (0.5, 0.6, 0.04), wd, (-1.2 + i * 0.6, 0.45, 0.91), b=0.012)
    for x in (-1.45, 1.45):
        for z in (-0.85, 0.85): cyl(p, 0.06, 2.6, dk, (x, 1.3, z), seg=10, b=0)
    box(p, (2.9, 1.3, 0.05), K('cloth', CREAM), (0, 1.75, -0.85), b=0.01, seg=1)
    box(p, (2.9, 0.06, 0.4), wd, (0, 1.5, -0.65), b=0.01)
    for i in range(6):  # striped roof sloping down to the front
        box(p, (0.52, 0.05, 2.15), K('cloth', RED if i % 2 == 0 else CREAM), (-1.31 + i * 0.524, 2.62, 0.05), rot=(0.18, 0, 0), b=0.012, seg=1)
    cyl(p, 0.05, 3.2, K('brass'), (0, 2.43, 1.12), RZ, seg=10, b=0)
    bunting(p, -1.5, 1.5, 2.4, 1.14, (RED, CREAM, YEL), 9)
    for i in range(7):  # goods on the counter and the shelf
        c = rng.choice((ORANGE, GREEN, YEL, PINK, SKY))
        box(p, (0.25, 0.18, 0.2), K('paint', c), (-1.3 + i * 0.42, 1.12, 0.45 + rng.uniform(-0.1, 0.1)), rot=(0, rng.uniform(-0.3, 0.3), 0), b=0.02)
        sph(p, 0.08, K('paint', rng.choice((RED, ORANGE, GREEN))), (-1.2 + i * 0.4, 1.6, -0.62), seg=10, rings=6)
    rod(p, (0, 2.5, 0.2), (0, 2.2, 0.2), 0.015, dk)
    cyl(p, 0.12, 0.1, K('brass'), (0, 2.15, 0.2), r2=0.06, seg=10, b=0.01)
    sph(p, 0.08, K('glow', AMBER), (0, 2.06, 0.2), seg=10, rings=6)
    p.mark('light_0', (0, 1.95, 0.3))
    p.finish()


def awning():
    p = Prop('awning'); dk = K('metal', DARK)
    cyl(p, 0.06, 3.0, K('brass'), (0, 0.62, -0.7), RZ, seg=12, b=0)
    for i in range(6):
        box(p, (0.5, 0.04, 1.5), K('cloth', TEAL if i % 2 == 0 else CREAM), (-1.25 + i * 0.5, 0.38, 0.0), rot=(0.33, 0, 0), b=0.01, seg=1)
    cyl(p, 0.04, 3.0, K('brass'), (0, 0.15, 0.72), RZ, seg=10, b=0)
    bunting(p, -1.5, 1.5, 0.15, 0.74, (TEAL, CREAM), 8, 0.17)
    for x in (-1.4, 1.4):
        rod(p, (x, 0.1, -0.72), (x, 0.15, 0.7), 0.025, dk)
        box(p, (0.12, 0.2, 0.06), dk, (x, 0.1, -0.73), b=0.015)
    p.finish()


def wind_turbine():
    p = Prop('wind_turbine'); dk = K('metal', DARK); wt = K('paint', WHITE)
    cyl(p, 0.9, 0.35, dk, (0, 0.175, 0), seg=10, b=0.05)
    cyl(p, 0.7, 0.2, K('brass'), (0, 0.45, 0), seg=10, b=0.03)
    cyl(p, 0.4, 6.3, wt, (0, 3.7, 0), r2=0.22, seg=16, b=0)
    for y in (2.0, 4.6):
        r = 0.4 + (0.22 - 0.4) * (y - 0.55) / 6.3
        cyl(p, r + 0.02, 0.28, K('paint', TEAL), (0, y, 0), seg=16, b=0.01)
    box(p, (0.36, 0.7, 0.08), dk, (0, 1.0, 0.38), rot=(-0.03, 0, 0), b=0.02)
    box(p, (0.7, 0.66, 1.35), wt, (0, 6.95, -0.1), b=0.2, seg=3)
    box(p, (0.72, 0.1, 1.2), K('paint', TEAL), (0, 7.12, -0.12), b=0.03)
    box(p, (0.06, 0.8, 0.65), K('paint', TEAL), (0, 7.1, -0.95), b=0.03)
    sph(p, 0.07, K('glow', REDG), (0, 7.33, -0.4), seg=10, rings=6)
    p.pivot('rotor', (0, 6.95, 0.72))
    hub = Vector((0, 6.95, 0.72))
    sph(p, 0.26, K('brass'), tuple(hub), grp='rotor', seg=16, rings=10)
    cyl(p, 0.22, 0.32, K('brass'), tuple(hub + Vector((0, 0, 0.2))), RX, r2=0.03, seg=16, b=0, grp='rotor')
    for i in range(3):
        a = TAU * i / 3 + math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        rod(p, tuple(hub + d * 0.2), tuple(hub + d * 1.5), 0.035, K('brass'), grp='rotor')
        box(p, (0.42, 1.15, 0.03), K('cloth', CREAM), tuple(hub + d * 0.88 + Vector((0, 0, -0.03))), rot=(0, 0.25, a - math.pi / 2), b=0.01, seg=1, grp='rotor')
        box(p, (0.06, 1.15, 0.05), K('cloth', ORANGE), tuple(hub + d * 0.88 + Vector((0, 0, -0.03))) , rot=(0, 0.25, a - math.pi / 2), b=0.0, grp='rotor')
    p.finish()


def vent_stack():
    p = Prop('vent_stack'); dk = K('metal', DARK)
    box(p, (1.2, 0.3, 1.2), dk, (0, 0.15, 0), b=0.05)
    cyl(p, 0.42, 2.4, K('metal', STEEL), (0, 1.5, 0), seg=18, b=0)
    for y in (0.7, 1.9): tor(p, 0.43, 0.035, K('brass'), (0, y, 0), RX)
    cyl(p, 0.47, 0.32, dk, (0, 2.82, 0), r2=0.52, seg=18, b=0.03)
    box(p, (0.36, 0.5, 0.06), K('hazard'), (0, 1.3, 0.42), b=0.01, seg=1)
    p.pivot('fan', (0, 2.9, 0))
    cyl(p, 0.08, 0.1, K('brass'), (0, 2.92, 0), seg=10, grp='fan')
    for i in range(5):
        a = TAU * i / 5
        box(p, (0.38, 0.03, 0.14), K('metal', STEEL), (math.cos(a) * 0.24, 2.92, math.sin(a) * 0.24), rot=(0.5, -a, 0), b=0, grp='fan')
    sph(p, 0.05, K('glow', AMBER), (0.5, 2.75, 0.2), seg=8, rings=5)
    p.finish()


def antenna():
    p = Prop('antenna'); dk = K('metal', DARK)
    box(p, (0.6, 0.2, 0.6), dk, (0, 0.1, 0), b=0.04)
    legs = [(math.cos(a) * 0.24, math.sin(a) * 0.24) for a in (0, TAU / 3, 2 * TAU / 3)]
    for (x, z) in legs: rod(p, (x, 0.2, z), (x * 0.25, 4.4, z * 0.25), 0.025, K('metal', STEEL))
    for y in (1.0, 1.9, 2.8, 3.6):
        k = 1 - (y - 0.2) / 4.2 * 0.75
        tor(p, 0.24 * k * 0.5 + 0.02, 0.015, K('brass'), (0, y, 0), RX, seg=12, tube=5)
    for i in range(3):
        y = 1.0 + i * 0.9
        a, b_ = legs[i], legs[(i + 1) % 3]
        ka, kb = 1 - (y - 0.2) / 4.2 * 0.75, 1 - (y + 0.9 - 0.2) / 4.2 * 0.75
        rod(p, (a[0] * ka, y, a[1] * ka), (b_[0] * kb, y + 0.9, b_[1] * kb), 0.012, K('metal', STEEL), seg=5)
    cyl(p, 0.02, 0.7, K('chrome', CHROME), (0, 4.75, 0), seg=8, b=0)
    for y, w in ((4.2, 0.5), (4.55, 0.34)):
        cyl(p, 0.015, w, K('brass'), (0, y, 0), RZ, seg=6, b=0)
    sph(p, 0.07, K('glow', REDG), (0, 5.1, 0), seg=10, rings=6)
    cyl(p, 0.16, 0.06, K('paint', WHITE), (0.12, 3.95, 0.1), (1.1, 0, -0.3), r2=0.06, seg=14, b=0.01)
    p.finish()


def flange(p, at, rot):
    cyl(p, 0.28, 0.1, K('brass'), at, rot, seg=18, b=0.02)


def pipe_straight():
    p = Prop('pipe_straight'); dk = K('metal', DARK)
    cyl(p, 0.2, 1.84, K('paint', TEAL), (0, 0.3, 0), RX, seg=18, b=0)
    for z in (-0.95, 0.95):
        flange(p, (0, 0.3, z), RX)
        for i in range(6):
            a = TAU * i / 6
            cyl(p, 0.025, 0.14, dk, (math.cos(a) * 0.24, 0.3 + math.sin(a) * 0.24, z), RX, seg=6, b=0)
    for z in (-0.5, 0.5):
        box(p, (0.5, 0.12, 0.16), dk, (0, 0.06, z), b=0.02)
        box(p, (0.1, 0.2, 0.12), dk, (0, 0.14, z), b=0.02)
    cyl(p, 0.04, 0.18, dk, (0, 0.55, 0.3), seg=8, b=0)
    tor(p, 0.12, 0.022, K('paint', RED), (0, 0.64, 0.3), RX, seg=16, tube=6)
    box(p, (0.24, 0.02, 0.03), K('paint', RED), (0, 0.64, 0.3), b=0)
    box(p, (0.03, 0.02, 0.24), K('paint', RED), (0, 0.64, 0.3), b=0)
    tor(p, 0.205, 0.02, K('hazard'), (0, 0.3, -0.55), seg=20, tube=5)
    p.finish()


def pipe_corner():
    # 90 degree elbow. Ends: (0.3, 0.3, -0.3) facing -Z and (-0.3, 0.3, 0.3) facing -X.
    p = Prop('pipe_corner'); dk = K('metal', DARK)
    tor(p, 0.6, 0.2, K('paint', TEAL), (-0.3, 0.3, -0.3), (math.pi / 2, 0, 0), seg=12, tube=18, arc=math.pi / 2)
    flange(p, (0.3, 0.3, -0.3), RX)
    flange(p, (-0.3, 0.3, 0.3), RZ)
    box(p, (0.4, 0.12, 0.4), dk, (0.1, 0.06, 0.1), rot=(0, 0.785, 0), b=0.02)
    box(p, (0.12, 0.14, 0.12), dk, (0.1, 0.16, 0.1), b=0.02)
    p.finish()


def sign_board():
    p = Prop('sign_board'); dk = K('metal', DARK)
    for x in (-0.85, 0.85):
        box(p, (0.3, 0.12, 0.3), dk, (x, 0.06, 0), b=0.03)
        cyl(p, 0.06, 2.1, dk, (x, 1.1, 0), seg=10, b=0)
    box(p, (1.96, 1.04, 0.12), K('brass'), (0, 1.62, 0), b=0.035, seg=3)
    box(p, (1.84, 0.92, 0.13), K('paint', NAVY), (0, 1.62, 0), b=0.01, seg=1)
    decal(p, 1.8, 0.9, SIGN('dock'), (0, 1.62, 0.067))
    for x in (-0.55, 0.55):
        rod(p, (x, 2.14, 0.0), (x, 2.2, 0.25), 0.015, dk)
        cyl(p, 0.09, 0.08, dk, (x, 2.18, 0.28), (0.6, 0, 0), r2=0.04, seg=10, b=0)
        sph(p, 0.045, K('glow', AMBER), (x, 2.14, 0.3), seg=8, rings=5)
    p.finish()


def flag_pole():
    p = Prop('flag_pole')
    cyl(p, 0.25, 0.2, K('brass'), (0, 0.1, 0), seg=8, b=0.03)
    cyl(p, 0.05, 4.8, K('chrome', CHROME), (0, 2.5, 0), r2=0.035, seg=10, b=0)
    sph(p, 0.09, K('brass'), (0, 4.97, 0), seg=12, rings=8)
    p.pivot('flag', (0, 4.6, 0))
    box(p, (1.4, 0.8, 0.03), K('cloth', ORANGE), (0.74, 4.2, 0), b=0.01, seg=1, grp='flag')
    cyl(p, 0.22, 0.035, K('cloth', CREAM), (0.74, 4.2, 0), RX, seg=16, b=0, grp='flag')
    cyl(p, 0.11, 0.04, K('cloth', ORANGE), (0.8, 4.2, 0), RX, seg=12, b=0, grp='flag')
    box(p, (1.4, 0.08, 0.035), K('cloth', NAVY), (0.74, 3.86, 0), b=0, grp='flag')
    p.finish()


def dish_assembly(p, center, R, tilt, grp, glow_grp=None, depth=0.25):
    ax = Vector((0, math.cos(tilt), math.sin(tilt)))
    c = Vector(center)
    cyl(p, R * 0.18, depth, K('paint', CREAM), tuple(c + ax * depth / 2), (tilt, 0, 0), r2=R, seg=28, b=0.03, grp=grp)
    cyl(p, R * 0.93, 0.03, K('paint', 0xb9c4cf), tuple(c + ax * (depth + 0.005)), (tilt, 0, 0), seg=28, b=0, grp=grp)
    tor(p, R, 0.045 * max(R, 0.6), K('glow', ORG) if glow_grp else K('brass'), tuple(c + ax * depth), (tilt + math.pi / 2, 0, 0), seg=32, tube=6, grp=glow_grp or grp)
    feed = c + ax * (depth + R * 0.85)
    for i in range(3):
        a = TAU * i / 3
        side = Vector((math.cos(a), 0, math.sin(a)))
        side = (side - ax * side.dot(ax)).normalized()
        rod(p, tuple(c + ax * depth + side * R * 0.9), tuple(feed), 0.015 * max(R, 1), K('metal', DARK), grp=grp)
    sph(p, 0.05 * max(R, 1) + 0.02, K('glow', ORG), tuple(feed), seg=10, rings=6, grp=glow_grp or grp)
    return feed


def dish_small():
    p = Prop('dish_small'); dk = K('metal', DARK)
    box(p, (0.6, 0.2, 0.6), dk, (0, 0.1, 0), b=0.04)
    cyl(p, 0.08, 0.6, dk, (0, 0.5, 0), seg=10, b=0)
    p.pivot('dish', (0, 0.85, 0))
    box(p, (0.28, 0.12, 0.2), K('brass'), (0, 0.85, 0), b=0.03, grp='dish')
    dish_assembly(p, (0, 0.88, 0.05), 0.55, 0.6, 'dish')
    p.finish()


def generator():
    p = Prop('generator'); dk = K('metal', DARK)
    box(p, (1.9, 0.2, 1.3), dk, (0, 0.1, 0), b=0.04)
    for x in (-0.8, 0.8):
        for z in (-0.5, 0.5): cyl(p, 0.09, 0.08, K('rubber', RUB), (x, 0.0, z), seg=10, b=0)
    box(p, (1.6, 1.1, 1.2), K('paint', YEL), (0, 0.75, 0), b=0.12, seg=3)
    box(p, (1.62, 0.12, 1.22), K('hazard'), (0, 0.38, 0), b=0.02, seg=1)
    for i in range(6): box(p, (0.1, 0.05, 1.0), dk, (-0.83, 0.55 + i * 0.1, 0), b=0.01, seg=1)
    box(p, (0.7, 0.42, 0.06), dk, (0.25, 0.9, 0.6), b=0.02)
    for i, c in enumerate((GRNG, AMBER, REDG)):
        cyl(p, 0.04, 0.04, K('glow', c), (0.05 + i * 0.12, 0.8, 0.64), RX, seg=10, b=0)
    tor(p, 0.11, 0.02, K('brass'), (0.4, 0.98, 0.635), seg=16, tube=6)
    cyl(p, 0.1, 0.02, K('glass', GLASS), (0.4, 0.98, 0.635), RX, seg=16, b=0)
    box(p, (0.012, 0.08, 0.01), K('paint', RED), (0.41, 1.0, 0.65), rot=(0, 0, -0.6), b=0)
    cyl(p, 0.07, 0.7, K('brass'), (0.55, 1.55, -0.3), seg=12, b=0)
    cyl(p, 0.1, 0.1, dk, (0.55, 1.93, -0.3), r2=0.08, seg=12, b=0.01)
    tor(p, 0.25, 0.03, K('metal', CHROME), (-0.2, 1.3, 0), (0, math.pi / 2, 0), seg=16, tube=6, arc=math.pi)
    tor(p, 0.22, 0.05, K('rubber', RUB), (0.95, 0.6, 0.2), (0, math.pi / 2, 0), seg=16, tube=6)
    p.finish()


def scrap_bits(p, rng, n, spread, top):
    paints = (RED, TEAL, YEL, SKY, CREAM, ORANGE, NAVY)
    for i in range(n):
        a = rng.uniform(0, TAU); r = rng.uniform(0.1, 1.0) ** 0.7 * spread
        x, z = math.cos(a) * r, math.sin(a) * r
        y = top * math.sqrt(max(0.0, 1 - (r / (spread * 1.1)) ** 2)) + rng.uniform(-0.02, 0.12)
        rot = (rng.uniform(-0.8, 0.8), rng.uniform(0, TAU), rng.uniform(-0.8, 0.8))
        k = i % 6
        if k == 0: tor(p, 0.3, 0.12, K('rubber', RUB), (x, y, z), rot, seg=14, tube=6)
        elif k in (1, 4): box(p, (rng.uniform(0.35, 0.8), rng.uniform(0.25, 0.55), rng.uniform(0.35, 0.7)), K('paint', rng.choice(paints)), (x, y, z), rot, b=0.03)
        elif k == 2: cyl(p, rng.uniform(0.06, 0.14), rng.uniform(0.6, 1.2), K('metal', STEEL), (x, y, z), rot, seg=10, b=0)
        elif k == 3: box(p, (rng.uniform(0.6, 1.0), 0.05, rng.uniform(0.4, 0.7)), K('metal', rng.choice((DARK, STEEL))), (x, y, z), rot, b=0.01, seg=1)
        else: cyl(p, 0.2, 0.08, K('brass'), (x, y, z), rot, seg=12, b=0.01)


def mound(p, scale, at, color, seed, seg=18, rings=10):
    bm = bm_sphere(1.0, seg, rings); r = random.Random(seed)
    ph = [r.uniform(0, TAU) for _ in range(6)]
    for v in bm.verts:
        x, y, z = v.co
        f = 1 + 0.13 * math.sin(3 * x + ph[0]) * math.sin(3 * z + ph[1]) + 0.08 * math.sin(6 * x + 4 * y + ph[2]) + 0.06 * math.sin(7 * z - 5 * y + ph[3])
        v.co *= f
        if v.co.y < -0.1: v.co.y = -0.1
    p.add(bm, K('rust', color), at, (0, r.uniform(0, TAU), 0), scale, angle=60)


def junk_pile():
    p = Prop('junk_pile'); rng = random.Random(11)
    mound(p, (1.45, 0.95, 1.35), (0, 0, 0), 0x5e5048, 1)
    scrap_bits(p, rng, 22, 1.3, 1.0)
    p.finish()


def scrap_heap():
    p = Prop('scrap_heap'); rng = random.Random(21)
    mound(p, (2.4, 1.7, 2.3), (0, 0, 0), 0x5e5048, 2, 20, 12)
    mound(p, (1.4, 1.2, 1.3), (0.9, 0, -0.6), 0x5f6670, 3)
    scrap_bits(p, rng, 34, 2.2, 1.7)
    # an old bot head left in the heap, one dim eye still on
    sph(p, 0.45, K('paint', CREAM), (-0.9, 1.35, 0.9), (1, 0.9, 1), rot=(0.3, 0.5, 0.2), seg=16, rings=10)
    cyl(p, 0.12, 0.08, K('glow', AMBER), (-0.75, 1.42, 1.3), (1.3, 0.4, 0), seg=12, b=0)
    tor(p, 0.13, 0.025, K('metal', DARK), (-0.75, 1.42, 1.31), (-0.27, 0.4, 0), seg=14, tube=5)
    rod(p, (-0.95, 1.7, 0.85), (-1.1, 2.15, 0.8), 0.02, K('metal', STEEL))
    sph(p, 0.05, K('paint', RED), (-1.1, 2.17, 0.8), seg=8, rings=5)
    p.finish()


def workbench():
    p = Prop('workbench'); dk = K('metal', DARK); wd = K('wood', WOOD)
    box(p, (2.2, 0.1, 0.9), wd, (0, 0.91, 0), b=0.025)
    for x in (-1.0, 1.0):
        for z in (-0.36, 0.36): box(p, (0.08, 0.86, 0.08), dk, (x, 0.43, z), b=0.015)
    box(p, (2.04, 0.05, 0.76), K('metal', STEEL), (0, 0.25, 0), b=0.015)
    box(p, (2.1, 0.06, 0.05), K('hazard'), (0, 0.83, 0.43), b=0.01, seg=1)
    # vise
    box(p, (0.22, 0.14, 0.25), K('brass'), (0.85, 1.03, 0.32), b=0.03)
    box(p, (0.22, 0.12, 0.06), K('brass'), (0.85, 1.03, 0.5), b=0.02)
    cyl(p, 0.015, 0.3, K('metal', CHROME), (0.85, 1.03, 0.55), RZ, seg=6, b=0)
    # toolbox
    box(p, (0.55, 0.24, 0.26), K('paint', RED), (-0.65, 1.08, -0.15), b=0.03)
    tor(p, 0.09, 0.015, K('metal', CHROME), (-0.65, 1.2, -0.15), seg=12, tube=5, arc=math.pi)
    # wrench on the bench
    rod(p, (-0.1, 0.975, 0.2), (0.35, 0.975, 0.05), 0.022, K('metal', CHROME))
    tor(p, 0.05, 0.018, K('metal', CHROME), (0.4, 0.975, 0.03), RX, seg=12, tube=5)
    cyl(p, 0.09, 0.03, K('brass'), (0.15, 0.97, -0.25), seg=12, b=0.008)
    # desk lamp
    cyl(p, 0.09, 0.03, dk, (0.2, 0.975, -0.32), seg=12, b=0.008)
    rod(p, (0.2, 0.98, -0.32), (0.3, 1.4, -0.25), 0.015, dk)
    rod(p, (0.3, 1.4, -0.25), (0.48, 1.42, -0.05), 0.015, dk)
    cyl(p, 0.1, 0.14, K('paint', TEAL), (0.5, 1.36, -0.02), (0.4, 0, 0), r2=0.04, seg=12, b=0.01)
    sph(p, 0.04, K('glow', AMBER), (0.52, 1.3, 0.0), seg=8, rings=5)
    p.finish()


def porch_chair():
    p = Prop('porch_chair'); wd = K('wood', WOOD)
    for x in (-0.33, 0.33):
        tor(p, 1.2, 0.03, wd, (x, 1.23, 0), (0, math.pi / 2, -math.pi / 2 - 0.33), seg=10, tube=6, arc=0.66)
        for z in (-0.2, 0.22): rod(p, (x, 0.02 + abs(z) * 0.0, z), (x, 0.45, z), 0.025, wd, seg=6)
        rod(p, (x, 0.45, -0.27), (x, 1.0, -0.42), 0.03, wd, seg=6)
        box(p, (0.07, 0.04, 0.48), K('brass'), (x * 1.08, 0.68, -0.02), b=0.012)
        rod(p, (x * 1.08, 0.45, 0.2), (x * 1.08, 0.66, 0.2), 0.018, wd, seg=6)
    box(p, (0.66, 0.05, 0.56), wd, (0, 0.45, 0), b=0.015)
    box(p, (0.58, 0.1, 0.5), K('cloth', RED), (0, 0.52, 0.02), b=0.04, seg=3)
    for y in (0.62, 0.78, 0.94):
        box(p, (0.66, 0.08, 0.03), wd, (0, y, -0.29 - (y - 0.45) * 0.27), rot=(-0.27, 0, 0), b=0.01)
    p.finish()


def gull_nest():
    p = Prop('gull_nest'); rng = random.Random(9)
    for i in range(36):
        a = TAU * i / 36 + rng.uniform(-0.1, 0.1); R = rng.uniform(0.38, 0.5); y = rng.uniform(0.06, 0.36)
        c = Vector((math.cos(a) * R, y, math.sin(a) * R)); t = Vector((-math.sin(a), rng.uniform(-0.25, 0.25), math.cos(a)))
        L = rng.uniform(0.35, 0.6)
        rod(p, tuple(c - t * L / 2), tuple(c + t * L / 2), rng.uniform(0.018, 0.03), K('wood', rng.choice((TWIG, 0x8f6a45, 0x5e4026))), seg=5)
    sph(p, 0.42, K('cloth', 0xd8ccb0), (0, 0.12, 0), (1, 0.32, 1), seg=14, rings=8)
    for (x, z, r) in ((-0.08, 0.05, 0.0), (0.1, -0.04, 0.6), (0.02, 0.14, 1.2)):
        sph(p, 0.065, K('paint', 0xeee6d0), (x, 0.24, z), (1, 1.3, 1), rot=(1.3, r, 0), seg=10, rings=7)
    box(p, (0.03, 0.01, 0.22), K('cloth', WHITE), (0.3, 0.38, 0.1), rot=(0.3, 0.6, 0.2), b=0)
    p.finish()


def bank_vault_door():
    p = Prop('bank_vault_door'); dk = K('metal', DARK)
    box(p, (3.0, 3.0, 0.36), K('metal', STEEL), (0, 1.5, -0.12), b=0.06, seg=3)
    for (sx, sy, x, y) in ((3.04, 0.14, 0, 0.07), (3.04, 0.14, 0, 2.93), (0.14, 3.0, -1.45, 1.5), (0.14, 3.0, 1.45, 1.5)):
        box(p, (sx, sy, 0.4), K('brass'), (x, y, -0.12), b=0.03)
    tor(p, 1.2, 0.07, K('brass'), (0, 1.42, 0.07), seg=32, tube=6)
    decal(p, 0.62, 0.31, SIGN('vault'), (0, 2.8, 0.065))
    for y in (0.8, 2.0): cyl(p, 0.09, 0.36, dk, (-1.18, y + 0.0, 0.18), seg=12, b=0.02)
    p.pivot('door', (-1.18, 1.42, 0.18))
    cyl(p, 1.12, 0.26, K('metal', CHROME), (0, 1.42, 0.2), RX, seg=32, b=0.05, grp='door')
    tor(p, 0.95, 0.04, K('brass'), (0, 1.42, 0.33), seg=32, tube=6, grp='door')
    for i in range(12):
        a = TAU * i / 12
        cyl(p, 0.05, 0.06, K('brass'), (math.cos(a) * 1.02, 1.42 + math.sin(a) * 1.02, 0.34), RX, seg=8, b=0, grp='door')
    cyl(p, 0.24, 0.12, K('brass'), (0, 1.42, 0.38), RX, seg=20, b=0.02, grp='door')
    p.pivot('wheel', (0, 1.42, 0.5), parent='door')
    tor(p, 0.48, 0.05, K('brass'), (0, 1.42, 0.55), seg=24, tube=6, grp='wheel')
    for i in range(4):
        a = TAU * i / 4 + 0.785
        rod(p, (0, 1.42, 0.5), (math.cos(a) * 0.48, 1.42 + math.sin(a) * 0.48, 0.55), 0.03, K('brass'), grp='wheel')
        sph(p, 0.06, K('rubber', RUB), (math.cos(a) * 0.56, 1.42 + math.sin(a) * 0.56, 0.56), seg=10, rings=6, grp='wheel')
    p.pivot('lock_light', (1.2, 2.6, 0.08))
    cyl(p, 0.09, 0.06, K('glow', REDG), (1.2, 2.6, 0.08), RX, seg=14, b=0, grp='lock_light')
    p.finish()


def turbine_switch():
    p = Prop('turbine_switch'); dk = K('metal', DARK)
    box(p, (0.8, 0.08, 0.6), dk, (0, 0.04, 0), b=0.02)
    box(p, (0.6, 0.86, 0.44), K('paint', NAVY), (0, 0.5, 0), b=0.06, seg=3)
    box(p, (0.62, 0.1, 0.46), K('hazard'), (0, 0.18, 0), b=0.02, seg=1)
    box(p, (0.68, 0.12, 0.5), dk, (0, 0.96, 0.02), rot=(0.35, 0, 0), b=0.03)
    box(p, (0.36, 0.02, 0.18), K('glow', CYAN), (-0.1, 1.03, 0.08), rot=(0.35, 0, 0), b=0)
    p.pivot('lever', (0.2, 1.0, 0.02))
    cyl(p, 0.06, 0.12, K('brass'), (0.2, 1.0, 0.02), RZ, seg=12, b=0.01, grp='lever')
    rod(p, (0.2, 1.0, 0.02), (0.2, 1.32, -0.12), 0.025, K('metal', CHROME), grp='lever')
    sph(p, 0.07, K('paint', RED), (0.2, 1.35, -0.13), seg=12, rings=8, grp='lever')
    p.pivot('status_light', (-0.22, 0.75, 0.23))
    cyl(p, 0.05, 0.04, K('glow', REDG), (-0.22, 0.75, 0.23), RX, seg=12, b=0, grp='status_light')
    p.finish()


def chimney():
    p = Prop('chimney'); dk = K('metal', DARK)
    box(p, (1.0, 0.8, 1.0), K('paint', CREAM), (0, 0.4, 0), b=0.06, seg=3)
    box(p, (1.04, 0.1, 1.04), K('brass'), (0, 0.78, 0), b=0.025)
    cyl(p, 0.3, 2.0, dk, (0, 1.8, 0), seg=16, b=0)
    for y in (1.3, 2.3): tor(p, 0.31, 0.03, K('brass'), (0, y, 0), RX, seg=18, tube=6)
    cyl(p, 0.34, 0.08, K('brass'), (0, 2.8, 0), seg=16, b=0.01)
    cyl(p, 0.26, 0.01, K('glow', ORG), (0, 2.82, 0), seg=14, b=0)
    for i in range(3):
        a = TAU * i / 3
        rod(p, (math.cos(a) * 0.3, 2.84, math.sin(a) * 0.3), (math.cos(a) * 0.3, 2.95, math.sin(a) * 0.3), 0.02, dk, seg=5)
    cyl(p, 0.45, 0.18, dk, (0, 3.03, 0), r2=0.08, seg=16, b=0.02)
    p.finish()


def water_tower():
    p = Prop('water_tower'); dk = K('metal', DARK)
    feet = [(x, z) for x in (-1.2, 1.2) for z in (-1.2, 1.2)]
    for (x, z) in feet:
        box(p, (0.36, 0.14, 0.36), dk, (x, 0.07, z), b=0.03)
        rod(p, (x, 0.1, z), (x * 0.78, 3.35, z * 0.78), 0.08, dk, seg=10)
    sides = ((feet[0], feet[1]), (feet[2], feet[3]), (feet[0], feet[2]), (feet[1], feet[3]))
    for (a, b_) in sides:
        rod(p, (a[0] * 0.97, 0.5, a[1] * 0.97), (b_[0] * 0.82, 3.0, b_[1] * 0.82), 0.03, K('metal', STEEL), seg=6)
        rod(p, (b_[0] * 0.97, 0.5, b_[1] * 0.97), (a[0] * 0.82, 3.0, a[1] * 0.82), 0.03, K('metal', STEEL), seg=6)
    cyl(p, 1.45, 0.1, dk, (0, 3.35, 0), seg=28, b=0.02)
    tor(p, 1.45, 0.04, K('brass'), (0, 3.85, 0), RX, seg=32, tube=6)
    for i in range(10):
        a = TAU * i / 10
        cyl(p, 0.02, 0.45, K('brass'), (math.cos(a) * 1.45, 3.62, math.sin(a) * 1.45), seg=5, b=0)
    cyl(p, 1.2, 2.0, K('paint', TEAL), (0, 4.45, 0), seg=28, b=0.06, bseg=3)
    for y in (3.75, 5.15): tor(p, 1.21, 0.04, K('brass'), (0, y, 0), RX, seg=32, tube=6)
    cyl(p, 1.36, 0.8, K('paint', RED), (0, 5.85, 0), r2=0.12, seg=28, b=0.03)
    sph(p, 0.12, K('brass'), (0, 6.3, 0), seg=12, rings=8)
    cyl(p, 0.45, 0.04, K('paint', CREAM), (0, 4.5, 1.19), RX, seg=24, b=0)
    cyl(p, 0.28, 0.05, K('paint', ORANGE), (0, 4.5, 1.2), RX, seg=20, b=0)
    for x in (-0.22, 0.22): rod(p, (x, 0.0, 1.35), (x, 3.35, 1.35), 0.025, K('metal', STEEL), seg=6)
    for i in range(10): rod(p, (-0.22, 0.25 + i * 0.32, 1.35), (0.22, 0.25 + i * 0.32, 1.35), 0.018, K('metal', STEEL), seg=5)
    p.finish()


def gantry():
    p = Prop('gantry'); dk = K('metal', DARK)
    for x in (-3.6, 3.6):
        box(p, (0.9, 0.2, 1.5), dk, (x, 0.1, 0), b=0.04)
        for z in (-0.5, 0.5): box(p, (0.26, 5.4, 0.26), K('paint', YEL), (x, 2.9, z), b=0.04)
        for i in range(5):
            y = 0.5 + i * 1.0
            rod(p, (x, y, -0.45), (x, y + 0.95, 0.45) if i % 2 == 0 else (x, y + 0.95, -0.45), 0.04, dk, seg=6)
            if i % 2: rod(p, (x, y + 0.95, -0.45), (x, y + 0.95, 0.45), 0.04, dk, seg=6)
    box(p, (8.0, 0.7, 1.3), K('paint', YEL), (0, 5.75, 0), b=0.08, seg=3)
    for z in (-1, 1): box(p, (7.2, 0.22, 0.03), K('hazard'), (0, 5.75, z * 0.66), b=0.0)
    box(p, (8.0, 0.08, 0.5), dk, (0, 5.36, 0), b=0.02)
    for x in (-3.8, 3.8):
        sph(p, 0.12, K('glow', AMBER), (x, 6.18, 0), seg=10, rings=6)
        cyl(p, 0.14, 0.06, dk, (x, 6.12, 0), seg=10, b=0.01)
        p.mark('light_%d' % (x > 0), (x, 6.3, 0))
    p.pivot('trolley', (0, 5.32, 0))
    box(p, (0.8, 0.36, 0.7), dk, (0, 5.12, 0), b=0.05, grp='trolley')
    for x in (-0.25, 0.25):
        for z in (-0.25, 0.25): cyl(p, 0.08, 0.06, K('brass'), (x, 5.3, z), RX, seg=10, b=0, grp='trolley')
    rod(p, (0, 4.95, 0), (0, 3.9, 0), 0.025, K('rubber', RUB), grp='trolley')
    box(p, (0.3, 0.2, 0.16), K('paint', YEL), (0, 3.85, 0), b=0.03, grp='trolley')
    tor(p, 0.16, 0.05, K('metal', CHROME), (0, 3.58, 0), (0, math.pi / 2, math.pi * 0.85), seg=14, tube=6, arc=math.pi * 1.4, grp='trolley')
    p.finish()


# ---------------- hero landmark pieces ----------------
def signal_mast_top():
    p = Prop('signal_mast_top'); dk = K('metal', DARK)
    cyl(p, 0.95, 0.4, dk, (0, 0.2, 0), r2=1.05, seg=20, b=0.04)
    for i in range(8):
        a = TAU * i / 8
        box(p, (0.12, 0.5, 0.75), dk, (math.cos(a) * 1.3, 0.4, math.sin(a) * 1.3), rot=(0, -a + math.pi / 2, 0), b=0.02)
    cyl(p, 2.0, 0.26, K('deck'), (0, 0.6, 0), seg=32, b=0.04)
    tor(p, 2.0, 0.08, K('brass'), (0, 0.6, 0), RX, seg=32, tube=6)
    tor(p, 2.04, 0.025, K('glow', CYAN), (0, 0.46, 0), RX, seg=32, tube=4)
    # railing ring with a gap facing +Z for landing
    gap = 1.0
    tor(p, 1.85, 0.045, K('brass'), (0, 1.62, 0), (math.pi / 2, 0, math.pi / 2 + gap / 2), seg=32, tube=6, arc=TAU - gap)
    tor(p, 1.85, 0.03, dk, (0, 1.15, 0), (math.pi / 2, 0, math.pi / 2 + gap / 2), seg=28, tube=4, arc=TAU - gap)
    for i in range(11):
        a = math.pi / 2 + gap / 2 + (TAU - gap) * i / 10
        cyl(p, 0.04, 0.95, dk, (math.cos(a) * 1.85, 1.2, math.sin(a) * 1.85), seg=8, b=0)
    # central pedestal and the relay dish (pivot 'dish' yaws, 'dish_glow' pulses orange with the broadcast)
    cyl(p, 0.42, 0.3, K('brass'), (0, 0.88, 0), seg=16, b=0.03)
    cyl(p, 0.32, 1.5, dk, (0, 1.75, 0), r2=0.26, seg=16, b=0)
    for y in (1.3, 2.1): tor(p, 0.3, 0.035, K('brass'), (0, y, 0), RX, seg=18, tube=6)
    box(p, (0.3, 0.4, 0.05), K('glow', ORG), (0, 1.7, 0.29), b=0)
    p.pivot('dish', (0, 2.55, 0))
    p.pivot('dish_glow', (0, 2.55, 0), parent='dish')
    cyl(p, 0.36, 0.2, K('brass'), (0, 2.55, 0), seg=18, b=0.03, grp='dish')
    for x in (-0.38, 0.38): box(p, (0.1, 0.6, 0.3), K('brass'), (x, 2.85, 0), b=0.03, grp='dish')
    cyl(p, 0.07, 0.86, dk, (0, 3.05, 0), RZ, seg=10, b=0, grp='dish')
    dish_assembly(p, (0, 3.0, 0.1), 1.45, 0.45, 'dish', 'dish_glow', depth=0.45)
    p.mark('light_0', (0, 3.6, 1.0))
    p.finish()


def crane_yard_gate():
    p = Prop('crane_yard_gate'); dk = K('metal', DARK)
    for x in (-3.3, 3.3):
        box(p, (1.4, 6.0, 1.4), K('paint', 0x4a5563), (x, 3.0, 0), b=0.1, seg=3)
        for y in (0.45, 4.2): box(p, (1.46, 0.5, 1.46), K('hazard'), (x, y, 0), b=0.04, seg=1)
        box(p, (1.6, 0.25, 1.6), K('brass'), (x, 6.0, 0), b=0.05)
        sph(p, 0.2, K('glow', AMBER), (x, 6.25, 0), seg=12, rings=8)
        p.mark('light_%d' % (x > 0), (x, 6.6, 0))
        for z in (-0.71, 0.71):
            for y in (1.5, 2.5, 3.5): cyl(p, 0.06, 0.05, K('brass'), (x + 0.45, y, z), RX, seg=8, b=0)
    box(p, (5.4, 1.0, 0.8), K('paint', YEL), (0, 5.2, 0), b=0.08, seg=3)
    decal(p, 4.4, 0.55, SIGN('crane'), (0, 5.2, 0.405))
    decal(p, 4.4, 0.55, SIGN('crane'), (0, 5.2, -0.405), rot=(0, math.pi, 0))
    box(p, (5.2, 0.1, 0.3), dk, (0, 4.66, 0), b=0.02)
    p.pivot('lock_light', (0, 4.55, 0.0))
    sph(p, 0.14, K('glow', REDG), (0, 4.5, 0), seg=12, rings=8, grp='lock_light')
    for side, x0 in (('door_L', -1.3), ('door_R', 1.3)):
        p.pivot(side, (x0, 0, 0))
        box(p, (2.56, 0.16, 0.2), K('paint', YEL), (x0, 0.18, 0), b=0.03, grp=side)
        box(p, (2.56, 0.16, 0.2), K('paint', YEL), (x0, 4.35, 0), b=0.03, grp=side)
        for dx in (-1.2, 1.2): box(p, (0.16, 4.3, 0.2), K('paint', YEL), (x0 + dx, 2.26, 0), b=0.03, grp=side)
        for i in range(7):
            cyl(p, 0.035, 4.1, dk, (x0 - 0.9 + i * 0.3, 2.26, 0), seg=8, b=0, grp=side)
        rod(p, (x0 - 1.15, 0.3, 0.06), (x0 + 1.15, 4.2, 0.06), 0.05, K('paint', YEL), grp=side)
        box(p, (2.3, 0.35, 0.06), K('hazard'), (x0, 2.3, 0.1), b=0.0, grp=side)
    p.finish()


def junkyard_porch():
    p = Prop('junkyard_porch'); dk = K('metal', DARK); wd = K('wood', WOOD)
    box(p, (6.0, 0.36, 3.4), K('paint', 0x6b5a4a), (0, 0.18, 0), b=0.04)
    for i in range(8): box(p, (6.0, 0.08, 0.41), wd, (0, 0.405, -1.49 + i * 0.425), b=0.015)
    for x in (-2.85, 0, 2.85): box(p, (0.14, 0.3, 3.4), dk, (x, 0.2, 0), b=0.02)
    for i, (z, y) in enumerate(((1.95, 0.25), (2.3, 0.1))):
        box(p, (1.6, 0.08, 0.36), wd, (0, y + 0.04, z), b=0.015)
        box(p, (1.6, y, 0.34), K('paint', 0x6b5a4a), (0, y / 2, z), b=0.02)
    for x in (-2.85, 2.85):
        for z in (-1.55, 1.55): box(p, (0.18, 2.95, 0.18), wd, (x, 1.92, z), b=0.03)
    # corrugated roof, sloping down to the front
    box(p, (6.4, 0.1, 4.0), K('paint', RED), (0, 3.45, 0.05), rot=(0.1, 0, 0), b=0.03)
    for i in range(14):
        x = -3.0 + i * 6.0 / 13
        cyl(p, 0.035, 4.0, K('paint', RED), (x, 3.51, 0.05), (math.pi / 2 + 0.1, 0, 0), seg=6, b=0)
    cyl(p, 0.07, 6.4, K('brass'), (0, 3.2, 2.02), RZ, seg=10, b=0)
    # back wall with door, porthole and the shop sign
    box(p, (6.0, 2.95, 0.22), K('paint', TEAL), (0, 1.92, -1.62), b=0.04)
    box(p, (1.1, 2.1, 0.08), wd, (1.3, 1.5, -1.48), b=0.02)
    sph(p, 0.05, K('brass'), (0.88, 1.45, -1.42), seg=8, rings=5)
    tor(p, 0.42, 0.06, K('brass'), (-1.4, 2.0, -1.5), seg=24, tube=6)
    cyl(p, 0.4, 0.03, K('glow', AMBER), (-1.4, 2.0, -1.55), RX, seg=20, b=0)
    cyl(p, 0.4, 0.02, K('glass', GLASS), (-1.4, 2.0, -1.5), RX, seg=20, b=0)
    decal(p, 2.4, 0.6, SIGN('junk'), (0, 3.02, -1.505))
    # side railings
    for x in (-2.85, 2.85):
        rod(p, (x, 1.35, -1.5), (x, 1.35, 1.5), 0.04, K('brass'))
        for z in (-0.75, 0.0, 0.75): rod(p, (x, 0.45, z), (x, 1.35, z), 0.025, dk)
    for x in (-2.0, 2.0): rod(p, (x * 1.42, 1.35, 1.55), (x * 0.6, 1.35, 1.55), 0.04, K('brass'))
    # hanging lamp
    rod(p, (0, 3.4, 0.5), (0, 2.85, 0.5), 0.015, dk)
    cyl(p, 0.22, 0.2, K('paint', TEAL), (0, 2.78, 0.5), r2=0.06, seg=14, b=0.01)
    sph(p, 0.08, K('glow', AMBER), (0, 2.68, 0.5), seg=10, rings=6)
    p.mark('light_0', (0, 2.5, 0.5))
    # side table with a coffee mug
    cyl(p, 0.3, 0.05, wd, (-1.9, 0.98, -0.8), seg=16, b=0.01)
    cyl(p, 0.04, 0.5, dk, (-1.9, 0.7, -0.8), seg=8, b=0)
    cyl(p, 0.06, 0.12, K('paint', CREAM), (-1.85, 1.07, -0.78), seg=12, b=0.01)
    tor(p, 0.04, 0.012, K('paint', CREAM), (-1.78, 1.07, -0.78), seg=10, tube=5)
    p.finish()


def gizmart_kiosk():
    p = Prop('gizmart_kiosk'); dk = K('metal', DARK)
    box(p, (2.1, 0.16, 1.3), dk, (0, 0.08, 0), b=0.04)
    box(p, (2.0, 2.6, 1.2), K('paint', PURPLE), (0, 1.42, 0), b=0.16, seg=3)
    box(p, (2.04, 0.12, 1.24), K('brass'), (0, 2.66, 0), b=0.04)
    box(p, (2.0, 0.55, 0.12), K('brass'), (0, 2.42, 0.56), b=0.04)
    decal(p, 1.86, 0.465, SIGN('gizmart'), (0, 2.42, 0.625))
    # the face: two round eyes and a light-up grin (separate nodes so code can blink or flash them)
    p.pivot('eyes', (0, 2.0, 0.6))
    for x in (-0.36, 0.36):
        tor(p, 0.16, 0.035, K('metal', DARK), (x, 2.02, 0.61), seg=20, tube=6)
        cyl(p, 0.14, 0.04, K('glow', CYAN), (x, 2.02, 0.6), RX, seg=20, b=0, grp='eyes')
    p.pivot('grin', (0, 1.7, 0.6))
    tor(p, 0.46, 0.065, K('glow', GOLDG), (0, 2.12, 0.61), (0, 0, math.pi + 0.5), seg=24, tube=6, arc=math.pi - 1.0, grp='grin')
    for a in (math.pi + 0.5, TAU - 0.5): sph(p, 0.075, K('glow', GOLDG), (math.cos(a) * 0.46, 2.12 + math.sin(a) * 0.46, 0.62), seg=8, rings=5, grp='grin')
    # goods window
    box(p, (1.36, 0.92, 0.04), K('metal', DARK), (-0.2, 0.95, 0.55), b=0.0)
    for y in (0.72, 1.05):
        box(p, (1.3, 0.03, 0.12), K('metal', CHROME), (-0.2, y, 0.6), b=0)
        for i in range(5):
            c = (ORANGE, GREEN, PINK, SKY, YEL)[(i + int(y * 10)) % 5]
            box(p, (0.16, 0.18, 0.08), K('paint', c), (-0.72 + i * 0.26, y + 0.11, 0.6), b=0.02)
    box(p, (1.4, 0.96, 0.03), K('glass', GLASS), (-0.2, 0.95, 0.66), b=0.0)
    for (sx, sy, x, y) in ((1.46, 0.06, -0.2, 1.45), (1.46, 0.06, -0.2, 0.45), (0.06, 1.0, -0.92, 0.95), (0.06, 1.0, 0.52, 0.95)):
        box(p, (sx, sy, 0.08), K('brass'), (x, y, 0.64), b=0.015)
    # coin slot, buttons, dispenser tray
    box(p, (0.28, 0.5, 0.06), dk, (0.78, 1.15, 0.6), b=0.02)
    box(p, (0.1, 0.02, 0.03), K('glow', GOLDG), (0.78, 1.32, 0.63), b=0)
    for i in range(3): cyl(p, 0.035, 0.03, K('glow', (REDG, GRNG, CYAN)[i]), (0.78, 1.18 - i * 0.1, 0.63), RX, seg=10, b=0)
    box(p, (0.9, 0.22, 0.14), dk, (0, 0.32, 0.6), b=0.04)
    box(p, (0.7, 0.1, 0.06), K('glow', 0x8a5cff), (0, 0.35, 0.66), b=0)
    for x in (-1.0, 1.0):  # side speaker grilles
        for i in range(4): box(p, (0.03, 0.04, 0.6), dk, (x * 1.0, 1.6 + i * 0.1, 0), b=0)
    rod(p, (0.7, 2.72, -0.3), (0.7, 3.05, -0.3), 0.02, K('metal', CHROME))
    sph(p, 0.07, K('glow', GOLDG), (0.7, 3.08, -0.3), seg=10, rings=6)
    p.mark('light_0', (0, 1.8, 1.2))
    p.finish()


def sky_island_rim():
    # Deck edge segment, 4 m along X, +Z faces out over the sky. The walkable top is at y = 1.2, so place it
    # at y = deck_top - 1.2 on the deck edge. Segments tile every 4 m.
    p = Prop('sky_island_rim'); dk = K('metal', DARK)
    box(p, (4.0, 0.5, 1.0), K('paint', WHITE), (0, 0.92, 0), b=0.04)
    box(p, (4.0, 0.72, 0.62), K('paint', 0xc9d3dd), (0, 0.36, -0.19), b=0.04)
    box(p, (4.0, 0.08, 0.6), K('paint', 0xc9d3dd), (0, 0.5, 0.18), rot=(-0.9, 0, 0), b=0.02)
    box(p, (4.0, 0.06, 0.82), K('deck'), (0, 1.17, -0.07), b=0.01, seg=1)
    box(p, (4.0, 0.25, 0.18), K('brass'), (0, 1.3, 0.41), b=0.05, seg=3)
    box(p, (3.96, 0.045, 0.04), K('glow', CYAN), (0, 0.72, 0.51), b=0)
    for x in (-1.0, 1.0):
        box(p, (0.24, 0.62, 0.14), dk, (x, 0.95, 0.52), b=0.03)
        for y in (0.8, 1.1): cyl(p, 0.035, 0.05, K('brass'), (x, y, 0.6), RX, seg=8, b=0)
    box(p, (0.6, 0.12, 0.05), K('hazard'), (0, 1.0, 0.505), b=0.0)
    p.finish()


ALL = [crate_small, crate_large, barrel, cargo_container, hanging_container, lamp_post, railing_2m, railing_post, bench,
       planter, market_stall, awning, wind_turbine, vent_stack, antenna, pipe_straight, pipe_corner, sign_board,
       flag_pole, dish_small, generator, junk_pile, scrap_heap, workbench, porch_chair, gull_nest, bank_vault_door,
       turbine_switch, chimney, water_tower, gantry, signal_mast_top, crane_yard_gate, junkyard_porch, gizmart_kiosk,
       sky_island_rim]

if __name__ == '__main__':
    want = [a for a in sys.argv[1:] if not a.startswith('-')]
    for f in ALL:
        if want and f.__name__ not in want: continue
        f()
    print('TRIS', TRIS)
