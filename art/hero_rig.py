# Vesk with a skeleton and hand-keyed animations, for the Godot version.
# Builds the same model as hero.py, replaces the rigid legs with one smooth skinned tube per leg,
# skins everything to an armature and keys the animation set (idle, run, jump, fall, land, dash,
# glide, grind, swing, melee). Exports godot/models/vesk.glb.
# Run: python art/hero_rig.py  (pip bpy, headless)
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
src = open(os.path.join(HERE, 'hero.py')).read()
src = src.replace("sys.path.insert(0, '/tmp/claude-0/art')", "")
exec(compile(src[:src.index("print('TRIS'")], 'hero.py', 'exec'))

import bpy, bmesh
from mathutils import Vector, Matrix, Euler
OUT = os.path.join(HERE, '..', 'godot', 'models', 'vesk.glb')
FPS = 30
bpy.context.scene.render.fps = FPS

# ---------------- skeleton (game coordinates: y up, +z forward) ----------------
J = {
    'root': ((0, 0, 0), (0, 0.25, 0), None),
    'pelvis': ((0, 0.70, 0), (0, 0.84, 0), 'root'),
    'spine': ((0, 0.84, 0), (0, 0.98, 0), 'pelvis'),
    'chest': ((0, 0.98, 0), (0, 1.16, 0), 'spine'),
    'neck': ((0, 1.16, 0), (0, 1.28, 0.01), 'chest'),
    'head': ((0.02, 1.28, 0.01), (0.02, 1.62, 0.03), 'neck'),
    'gun': ((0.30, 1.2, 0.32), (0.30, 1.2, 0.62), 'chest'),
}
for s, n in ((1, 'L'), (-1, 'R')):
    hip, knee, ankle, toe = (0.13 * s, 0.66, 0), (0.135 * s, 0.38, 0.02), (0.135 * s, 0.12, 0.01), (0.135 * s, 0.02, 0.2)
    J[f'thigh.{n}'] = (hip, knee, 'pelvis')
    J[f'shin.{n}'] = (knee, ankle, f'thigh.{n}')
    J[f'foot.{n}'] = (ankle, toe, f'shin.{n}')

arm_data = bpy.data.armatures.new('VeskRig')
rig = bpy.data.objects.new('Vesk', arm_data); bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
FWD = gv(0, 0, 1)
for name, (h, t, parent) in J.items():
    eb = arm_data.edit_bones.new(name)
    eb.head = gv(*h); eb.tail = gv(*t)
    axis = (eb.tail - eb.head).normalized()
    eb.align_roll(FWD if abs(axis.dot(FWD)) < 0.9 else gv(0, 1, 0))
    if parent: eb.parent = arm_data.edit_bones[parent]; eb.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------- skin: bake every part into one mesh with bone weights ----------------
def bone_for(o):
    chain = []
    p = o.parent
    while p: chain.append(p.name); p = p.parent
    top = chain[0] if chain else ''
    n = o.name
    if top.startswith('hip_'): return 'thigh.' + top[-1]
    if top.startswith('knee_'):
        return ('foot.' if any(n.startswith(k) for k in ('boot', 'cuff', 'sole')) else 'shin.') + top[-1]
    if top == 'head': return 'head'
    if top == 'gun': return 'gun'
    if top == 'upper':
        if n in ('belt', 'buckle', 'pouch', 'pouch2'): return 'pelvis'
        if n == 'neck': return 'neck'
        if n == 'torso': return '*torso'
        return 'chest'
    return 'chest'

def torso_weights(y):
    # smooth bend through the waist and belly (game y)
    def ramp(a, b): return min(1, max(0, (y - a) / (b - a)))
    w_sp = ramp(0.78, 0.9); w_ch = ramp(0.93, 1.04)
    return {'pelvis': 1 - w_sp, 'spine': w_sp - w_ch, 'chest': w_ch}

dg = bpy.context.evaluated_depsgraph_get()
B2G = G2B.inverted()
pieces = []
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    if o.name.startswith(('thigh_', 'shin_')): continue  # replaced by the skinned leg tubes below
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    me.transform(o.matrix_world)
    pieces.append((me, bone_for(o)))

# one continuous tube per leg from hip to ankle, so knees bend smoothly
suitDarkM = bpy.data.materials['suit_navy']
for s, n in ((1, 'L'), (-1, 'R')):
    hip, knee, ankle = Vector((0.13 * s, 0.70, 0)), Vector((0.135 * s, 0.38, 0.02)), Vector((0.135 * s, 0.13, 0.01))
    bm = bmesh.new(); rings = []
    N, SEG = 28, 16
    pts = []
    for i in range(N + 1):
        u = i / N
        p = hip.lerp(knee, u * 2) if u < 0.5 else knee.lerp(ankle, (u - 0.5) * 2)
        r = 0.112 - 0.024 * u + 0.012 * math.exp(-((u - 0.5) / 0.08) ** 2)  # slightly thicker knee
        if i == 0: r *= 0.9
        pts.append((p, r, u))
    for (p, r, u) in pts:
        ring = [bm.verts.new(gv(p.x + math.cos(a) * r, p.y, p.z + math.sin(a) * r)) for a in [k / SEG * math.tau for k in range(SEG)]]
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(SEG): bm.faces.new((a[k], a[(k + 1) % SEG], b[(k + 1) % SEG], b[k]))
    bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(f'leg_{n}'); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    me.materials.append(suitDarkM)
    pieces.append((me, f'*leg.{n}'))

mesh = bpy.data.meshes.new('VeskBody')
obj = bpy.data.objects.new('VeskBody', mesh); bpy.context.scene.collection.objects.link(obj)
bm = bmesh.new()
mats = []
weights = []  # per vertex dict
for me, bone in pieces:
    off = len(bm.verts)
    slot = {}
    for i, m in enumerate(me.materials):
        if m not in mats: mats.append(m)
        slot[i] = mats.index(m)
    vmap = []
    for v in me.vertices:
        nv = bm.verts.new(v.co); vmap.append(nv)
        g = B2G @ v.co
        if bone == '*torso': w = torso_weights(g.y)
        elif bone.startswith('*leg.'):
            side = bone[-1]; y = g.y
            t = min(1, max(0, (0.44 - y) / 0.12))  # blend thigh -> shin around the knee (y 0.38)
            w = {f'thigh.{side}': 1 - t, f'shin.{side}': t}
            if y > 0.64: h = min(1, (y - 0.64) / 0.08) * 0.5; w = {f'thigh.{side}': 1 - h, 'pelvis': h}
        else: w = {bone: 1.0}
        weights.append(w)
    bm.verts.ensure_lookup_table()
    for p in me.polygons:
        try:
            f = bm.faces.new([vmap[i] for i in p.vertices]); f.material_index = slot.get(p.material_index, 0); f.smooth = p.use_smooth
        except ValueError: pass
bm.to_mesh(mesh); bm.free()
for m in mats: mesh.materials.append(m)
for name in J: obj.vertex_groups.new(name=name)
for i, w in enumerate(weights):
    for b, x in w.items():
        if x > 1e-4: obj.vertex_groups[b].add([i], x, 'REPLACE')
obj.parent = rig
mod = obj.modifiers.new('rig', 'ARMATURE'); mod.object = rig

# drop the original parts
for o in [o for o in bpy.data.objects if o not in (rig, obj)]: bpy.data.objects.remove(o, do_unlink=True)

# ---------------- animation ----------------
bpy.context.view_layer.objects.active = rig
for pb in rig.pose.bones: pb.rotation_mode = 'XYZ'
rig.animation_data_create()

def key(action, frame, pose):
    """pose: {bone: (rx, ry, rz) or ((rx, ry, rz), (lx, ly, lz))}; +rx swings a bone forward (legs) / leans forward (spine)"""
    for pb in rig.pose.bones:
        val = pose.get(pb.name, (0, 0, 0))
        rot, loc = (val if isinstance(val[0], (tuple, list)) else (val, (0, 0, 0)))
        pb.rotation_euler = Euler(rot, 'XYZ'); pb.location = Vector(loc)
        pb.keyframe_insert('rotation_euler', frame=frame, group=pb.name)
        pb.keyframe_insert('location', frame=frame, group=pb.name)

def make(name, frames, fn, loop=True):
    act = bpy.data.actions.new(name); act.use_fake_user = True
    rig.animation_data.action = act
    n = frames
    for f in range(0, n + 1):
        u = f / n
        key(act, f, fn(u))
    if loop:
        for fc in getattr(act, 'fcurves', []):
            for kp in fc.keyframe_points: kp.interpolation = 'LINEAR'
    # stash on the NLA so the exporter writes every action
    tr = rig.animation_data.nla_tracks.new(); tr.name = name
    tr.strips.new(name, 0, act)
    rig.animation_data.action = None
    return act

S = math.sin; C = math.cos; T = math.tau
def leg(side, swing, knee, foot=0.0):
    return {f'thigh.{side}': (swing, 0, 0), f'shin.{side}': (-knee, 0, 0), f'foot.{side}': (foot, 0, 0)}

def idle(u):
    b = S(u * T)
    p = {'pelvis': ((0, 0, 0), (0, 0.004 * b, 0)), 'spine': (0.03 + 0.015 * b, 0, 0), 'chest': (0.02 * b, 0.03 * S(u * T * 0.5 + 1), 0),
         'neck': (-0.02 * b, 0, 0), 'head': (0.03 * S(u * T + 0.6), 0.08 * S(u * T * 0.5), 0.02 * S(u * T * 0.5))}
    p.update(leg('L', 0.05, 0.1, 0.05)); p.update(leg('R', -0.03, 0.08, 0.02))
    return p

def run(u):
    a = u * T
    p = {}
    for side, off in (('L', 0.0), ('R', math.pi)):
        ph = a + off
        sw = S(ph)                                      # +: leg forward
        kn = 0.25 + max(0.0, -C(ph)) * 1.45 + max(0.0, S(ph)) * 0.25   # tuck as the leg swings through
        ft = -0.35 * max(0.0, -S(ph)) + 0.25 * max(0.0, S(ph + 0.6))
        p.update(leg(side, sw * 0.95, kn, ft))
    bob = abs(S(a)) * 0.05
    p['pelvis'] = ((0, 0.18 * S(a), 0.05 * C(a)), (0, -bob, 0))
    p['spine'] = (0.16, -0.12 * S(a), 0)
    p['chest'] = (0.06 + 0.03 * abs(C(a)), -0.08 * S(a), 0.03 * C(a))
    p['neck'] = (-0.12, 0.1 * S(a), 0)
    p['head'] = (-0.05 + 0.04 * abs(S(a)), 0.06 * S(a), 0)
    return p

def jump(u):
    k = min(1, u * 2.5)
    p = leg('L', -0.9 * k, 1.5 * k, 0.3 * k); p.update(leg('R', 0.35 * k, 0.5 * k, -0.4 * k))
    p['spine'] = (-0.08 * k, 0, 0); p['chest'] = (-0.06 * k, 0, 0); p['head'] = (0.08 * k, 0, 0)
    return p

def fall(u):
    w = S(u * T)
    p = leg('L', -0.35 + 0.08 * w, 0.55, 0.2); p.update(leg('R', 0.15 - 0.08 * w, 0.35, 0.1))
    p['spine'] = (0.05, 0, 0.03 * w); p['chest'] = (0.04, 0.05 * w, 0); p['head'] = (-0.05, 0, 0)
    return p

def land(u):
    k = S(min(1, u) * math.pi) * (1 - u * 0.3)
    p = leg('L', -0.55 * k, 1.1 * k, 0.55 * k); p.update(leg('R', -0.5 * k, 1.05 * k, 0.5 * k))
    p['pelvis'] = ((0, 0, 0), (0, -0.16 * k, 0)); p['spine'] = (0.25 * k, 0, 0); p['chest'] = (0.12 * k, 0, 0); p['head'] = (-0.25 * k, 0, 0)
    return p

def dash(u):
    p = leg('L', 0.45, 1.3, 0.4); p.update(leg('R', -0.6, 0.4, -0.2))
    p['spine'] = (0.35, 0, 0); p['chest'] = (0.15, 0, 0); p['head'] = (-0.35, 0, 0)
    return p

def glide(u):
    w = S(u * T)
    p = leg('L', -0.15 + 0.06 * w, 0.4, 0.2); p.update(leg('R', 0.1 - 0.06 * w, 0.3, 0.2))
    p['spine'] = (0.12, 0, 0.04 * w); p['chest'] = (0.05, 0, 0); p['head'] = (-0.1, 0, 0)
    return p

def grind(u):
    w = S(u * T)
    p = {'pelvis': ((0, 0.9, 0.05 * w), (0, -0.12, 0)), 'spine': (0.2, -0.6, 0.05 * w), 'chest': (0.05, -0.25, 0), 'head': (-0.1, -0.05, 0)}
    p.update(leg('L', -0.5, 0.9, 0.4)); p.update(leg('R', 0.35, 0.8, 0.3))
    return p

def swing(u):
    w = S(u * T)
    p = leg('L', -1.0 + 0.1 * w, 1.6, 0.5); p.update(leg('R', -0.7 - 0.1 * w, 1.3, 0.4))
    p['spine'] = (-0.25, 0, 0); p['chest'] = (-0.2, 0, 0); p['head'] = (0.2, 0, 0)
    return p

def melee(u):
    # wind up right, whip across to the left, settle
    if u < 0.25: k = u / 0.25; tw = -0.9 * k
    elif u < 0.55: k = (u - 0.25) / 0.3; tw = -0.9 + 2.1 * (1 - (1 - k) ** 3)
    else: k = (u - 0.55) / 0.45; tw = 1.2 * (1 - k)
    p = {'spine': (0.1, tw * 0.45, 0), 'chest': (0.08, tw * 0.6, -0.1 * tw), 'head': (0, -tw * 0.4, 0), 'pelvis': ((0, tw * 0.25, 0), (0, -0.04, 0))}
    p.update(leg('L', 0.35, 0.45, 0.1)); p.update(leg('R', -0.3, 0.3, 0))
    return p

make('idle', 60, idle)
make('run', 20, run)
make('jump', 10, jump, False)
make('fall', 20, fall)
make('land', 10, land, False)
make('dash', 10, dash)
make('glide', 30, glide)
make('grind', 40, grind)
make('swing', 20, swing)
make('melee', 12, melee, False)

# ---------------- export ----------------
for o in bpy.data.objects: o.select_set(o in (rig, obj))
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True, export_apply=False,
                          export_animations=True, export_animation_mode='NLA_TRACKS', export_force_sampling=True,
                          export_cameras=False, export_lights=False, export_extras=False)
print('exported', OUT, len(mesh.vertices), 'verts')
