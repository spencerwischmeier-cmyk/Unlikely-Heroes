# Face rig for Vesk's cutscene model (godot/models/vesk_face.glb). Gameplay keeps godot/models/vesk.glb.
# Run with pip bpy:  python build_vesk_face.py <in vesk.glb> <out vesk_face.glb>
# What it adds to the Meshy mesh (all procedural, measured off the painted texture):
#   - the face is subdivided (3 cuts) so the lips, lids and brows have enough vertices to move
#   - a mouth: the triangles across the painted lip line are removed (a slit), with a dark mouth bag,
#     tongue and two rows of teeth behind it
#   - a "jaw" bone (child of head) that opens the lower muzzle, lower teeth and tongue
#   - a real eyeball for his right eye on an "eye.R" bone (the painted eye becomes the socket), a glass
#     dome over the eyepiece lens (catchlights)
#   - shape keys: blink, lids_half, brow_up_L, brow_up_R, brow_down, brow_sad, smile, frown, wide, pucker,
#     press, sneer
import bpy, bmesh, sys, math, numpy as np
from mathutils import Vector, Matrix
sys.path.insert(0, __import__('os').path.dirname(__file__))
_pos = [a for a in sys.argv[1:] if not a.startswith('--')]
IN, OUT = _pos[-2], _pos[-1]

for o in list(bpy.data.objects): bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=IN)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
arm.data.pose_position = 'REST'
me = bpy.data.objects['Mesh_0']

def coords():
    n = len(me.data.vertices); c = np.zeros(n * 3); me.data.vertices.foreach_get('co', c); return c.reshape(-1, 3)
def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0); return t * t * (3 - 2 * t)

# ---------------------------------------------------------------- 1. subdivide the face
co = coords()
sel = (co[:, 1] < -0.12) & (co[:, 2] > 1.25) & (np.abs(co[:, 0]) < 0.17) & (co[:, 2] < 1.56)
bpy.context.view_layer.objects.active = me
def select_faces(mask):
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_mode(type='FACE'); bpy.ops.mesh.select_all(action='DESELECT')
    ebm = bmesh.from_edit_mesh(me.data)
    for f in ebm.faces: f.select_set(all(mask[v.index] for v in f.verts))
    ebm.select_flush_mode(); bmesh.update_edit_mesh(me.data)
select_faces(sel)
bpy.ops.mesh.subdivide(number_cuts=3, smoothness=0.0)
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------- 2. the mouth slit
# painted lip line, measured from the texture (darkest row per x slice)
LIP_X = np.array([-0.09, -0.08, -0.07, -0.06, -0.05, -0.03, -0.01, 0.01, 0.03, 0.05, 0.06, 0.07, 0.08, 0.09])
LIP_Z = np.array([1.374, 1.369, 1.365, 1.359, 1.357, 1.358, 1.360, 1.361, 1.3625, 1.364, 1.363, 1.365, 1.370, 1.375])
MOUTH_HALF = 0.083
def lip_z(x): return np.interp(x, LIP_X, LIP_Z)
co = coords()
front = co[:, 1] < -0.2
bm = bmesh.new(); bm.from_mesh(me.data); bm.verts.ensure_lookup_table()
kill = []
for f in bm.faces:
    vs = [v.co for v in f.verts]
    xs = [v.x for v in vs]
    if max(abs(x) for x in xs) > MOUTH_HALF or min(v.y for v in vs) > -0.22: continue
    above = [v.z > lip_z(v.x) for v in vs]
    if any(above) and not all(above) and all(abs(v.z - lip_z(v.x)) < 0.012 for v in vs): kill.append(f)
bmesh.ops.delete(bm, geom=kill, context='FACES_ONLY')
bm.to_mesh(me.data); bm.free()
print('mouth slit faces removed', len(kill), 'verts', len(me.data.vertices))

# ---------------------------------------------------------------- 3. bones: jaw, eye.R
JAW_PIVOT = Vector((0.0, -0.13, 1.392))
EYE_R_FRONT = Vector((-0.0715, -0.2375, 1.461))
EYE_N = Vector((-0.22, -1.0, 0.04)).normalized()
EYE_RAD = 0.032
EYE_C = EYE_R_FRONT - EYE_N * (EYE_RAD + 0.001)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
head = eb['head']
j = eb.new('jaw'); j.head = JAW_PIVOT; j.tail = JAW_PIVOT + Vector((0, -0.12, -0.02)); j.parent = head; j.roll = 0
e = eb.new('eye.R'); e.head = EYE_C; e.tail = EYE_C + EYE_N * 0.05; e.parent = head; e.roll = 0
bpy.ops.object.mode_set(mode='OBJECT')
arm.data.pose_position = 'REST'

# ---------------------------------------------------------------- 4. jaw weights
co = coords()
x, y, z = co[:, 0], co[:, 1], co[:, 2]
lz = lip_z(np.clip(x, -0.09, 0.09)) + np.where(np.abs(x) > 0.09, (np.abs(x) - 0.09) * 0.3, 0)
below = np.where(np.abs(x) < MOUTH_HALF, (z < lz).astype(float), 1.0 - sstep(lz - 0.012, lz + 0.006, z))
w = below * (1 - sstep(0.07, 0.14, np.abs(x))) * sstep(-0.16, -0.25, y) * sstep(1.215, 1.29, z)
w[z > 1.40] = 0.0
jaw_w = w
gi = {g.name: g.index for g in me.vertex_groups}
vg_jaw = me.vertex_groups.new(name='jaw')
for i in np.where(w > 0.001)[0]:
    v = me.data.vertices[int(i)]
    for g in v.groups: g.weight *= (1.0 - w[i])
    vg_jaw.add([int(i)], float(w[i]), 'REPLACE')
print('jaw verts', int((w > 0.001).sum()))

# ---------------------------------------------------------------- 5. eye socket (painted right eye pushed in behind the eyeball)
EA, EB = 0.0255, 0.0158        # eye opening half width / half height
EZC = 1.4605
ex = Vector((1, 0, 0)); ez = Vector((0, 0, 1))
def eye_local(p):
    return ((p[0] - EYE_R_FRONT.x) / EA, (p[2] - EZC) / EB)
co = coords()
basis_co = co.copy()
for i, p in enumerate(co):
    if p[1] > -0.19 or abs(p[0] - EYE_R_FRONT.x) > 0.05 or abs(p[2] - EZC) > 0.04: continue
    u, v = eye_local(p)
    r = math.hypot(u, v)
    if r >= 1.0: continue
    k = float(sstep(1.0, 0.72, r))
    P = Vector(p); d = (P - EYE_C).normalized()
    inner = EYE_C + d * (EYE_RAD - 0.006)
    me.data.vertices[i].co = P.lerp(inner, k)

# ---------------------------------------------------------------- 6. shape keys
co = coords()
me.shape_key_add(name='Basis', from_mix=False)
def key(name, fn):
    kb = me.shape_key_add(name=name, from_mix=False)
    n = 0
    for i, p in enumerate(co):
        d = fn(p)
        if d is not None and (d[0] or d[1] or d[2]):
            kb.data[i].co = Vector(p) + Vector(d); n += 1
    print('key', name, n)
def onsphere(P, extra):
    return EYE_C + (P - EYE_C).normalized() * (EYE_RAD + extra)
def lid(p, close):
    """upper lid band slides down to the `close` line (eye-local units, -1 bottom .. 1 top)"""
    if p[1] > -0.19 or abs(p[0] - EYE_R_FRONT.x) > 0.045 or p[2] < EZC - 0.02 or p[2] > EZC + 0.045: return None
    u, v = eye_local(p)
    if abs(u) >= 1.15: return None
    uu = min(abs(u), 0.999)
    top = math.sqrt(1 - uu * uu)
    band = 1.6
    s = (v - top) / band
    if s < -0.05 or s > 1.0: return None
    s = max(s, 0.0)
    cl = close * math.sqrt(1 - uu * uu)
    nv = cl + s * (top + band - cl)
    side = float(1 - sstep(0.85, 1.15, abs(u)))
    target_plane = Vector((p[0], 0, EZC + nv * EB))
    P = Vector(p)
    moved = Vector((p[0], p[1], EZC + nv * EB))
    sph = onsphere(Vector((p[0], EYE_R_FRONT.y, EZC + nv * EB)), 0.0035)
    sph.x = p[0]
    tgt = sph.lerp(moved, s ** 0.7)
    if tgt.y > moved.y: tgt.y = min(tgt.y, p[1] + 0.0)
    return tuple((tgt - P) * side)
key('blink', lambda p: lid(p, -0.5))
key('lids_half', lambda p: lid(p, 0.35))

BROWS = {'R': Vector((-0.066, -0.268, 1.508)), 'L': Vector((0.082, -0.264, 1.516))}
def brow_w(p, side):
    c = BROWS[side]
    if p[1] > -0.17: return 0.0, 0.0
    dx = (p[0] - c.x) / 0.055; dz = (p[2] - c.z) / 0.03
    r = math.hypot(dx, dz)
    if r >= 1.0: return 0.0, 0.0
    inner = float(np.clip(-(p[0] - c.x) / 0.05 * (1 if side == 'L' else -1), -1, 1))   # +1 toward the nose
    return float(sstep(1.0, 0.35, r)), inner
def brows(fn, sides=('L', 'R')):
    def f(p):
        tot = Vector((0, 0, 0))
        for s in sides:
            w, inner = brow_w(p, s)
            if w > 0: tot += Vector(fn(w, inner, s))
        return tuple(tot) if tot.length > 0 else None
    return f
key('brow_up_L', brows(lambda w, i, s: (0, -0.003 * w, 0.019 * w), ('L',)))
key('brow_up_R', brows(lambda w, i, s: (0, -0.003 * w, 0.019 * w), ('R',)))
key('brow_down', brows(lambda w, i, s: ((0.004 if s == 'R' else -0.004) * w * max(i, 0), -0.004 * w, -0.016 * w * (0.45 + 0.8 * max(i, 0)))))
key('brow_sad', brows(lambda w, i, s: (0, -0.002 * w, 0.016 * w * i)))

def mouth_w(p, reach=0.022):
    if p[1] > -0.2 or abs(p[0]) > 0.12: return 0.0
    d = abs(p[2] - float(lip_z(np.clip(p[0], -0.09, 0.09))))
    return float(sstep(reach, 0.0, d)) * float(1 - sstep(0.105, 0.125, abs(p[0])))
def corner(p):
    return float(sstep(0.025, 0.08, abs(p[0])))
sgn = lambda p: 1.0 if p[0] > 0 else -1.0
key('smile', lambda p: (sgn(p) * 0.008 * mouth_w(p, 0.045) * corner(p), 0.008 * mouth_w(p, 0.045) * corner(p), 0.02 * mouth_w(p, 0.045) * corner(p) ** 1.3))
key('frown', lambda p: (sgn(p) * 0.001 * mouth_w(p, 0.03) * corner(p), 0.0, -0.014 * mouth_w(p, 0.035) * corner(p) ** 1.5))
key('wide', lambda p: (sgn(p) * 0.009 * mouth_w(p) * corner(p), 0.004 * mouth_w(p) * corner(p), 0.0))
key('pucker', lambda p: (-p[0] * 0.28 * mouth_w(p, 0.02), -0.008 * mouth_w(p, 0.02) * (1 - corner(p) * 0.5), 0.0))
def press(p):
    w = mouth_w(p, 0.008)
    if w <= 0: return None
    up = p[2] > float(lip_z(np.clip(p[0], -0.09, 0.09)))
    return (0, -0.0015 * w, (-0.0016 if up else 0.0016) * w)
key('press', press)
def sneer(p):
    if p[1] > -0.2 or abs(p[0]) > 0.09: return None
    lzz = float(lip_z(np.clip(p[0], -0.09, 0.09)))
    if p[2] < lzz or p[2] > 1.43: return None
    w = float(sstep(0.04, 0.0, p[2] - lzz)) * float(1 - sstep(0.04, 0.085, abs(p[0])))
    return (0, -0.001 * w, 0.006 * w)
key('sneer', sneer)

# ---------------------------------------------------------------- 7. mouth bag, teeth, tongue, eyeball, lens glass
def skinned(obj, groups):
    obj.parent = arm
    mod = obj.modifiers.new('Armature', 'ARMATURE'); mod.object = arm
    for gname, fn in groups:
        vg = obj.vertex_groups.new(name=gname)
        for v in obj.data.vertices:
            ww = fn(v.co)
            if ww > 0: vg.add([v.index], ww, 'REPLACE')
def mat(name, col, rough=0.6, emit=None, metal=0.0, alpha=None):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*col, 1); b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if alpha is not None:
        b.inputs['Alpha'].default_value = alpha
        try: m.surface_render_method = 'BLENDED'
        except Exception: pass
        m.blend_method = 'BLEND' if hasattr(m, 'blend_method') else None
    return m
def add_obj(name, mesh):
    o = bpy.data.objects.new(name, mesh); bpy.context.scene.collection.objects.link(o); return o

# mouth bag: an ellipsoid shell inside the muzzle, top half on head, bottom half on the jaw
bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * 0.07, v.co.y * 0.06 - 0.285, v.co.z * 0.032 + 1.356))
bmesh.ops.reverse_faces(bm, faces=bm.faces)   # seen from inside
mb = bpy.data.meshes.new('MouthBag'); bm.to_mesh(mb); bm.free()
bag = add_obj('MouthBag', mb); mb.materials.append(mat('mouth_in', (0.09, 0.025, 0.03), 0.8))
skinned(bag, [('head', lambda c: 1.0 if c.z >= 1.357 else 0.0), ('jaw', lambda c: 1.0 if c.z < 1.357 else 0.0)])
# tongue
bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1.0)
for v in bm.verts: v.co = Vector((v.co.x * 0.042, v.co.y * 0.045 - 0.29, v.co.z * 0.012 + 1.338))
tm = bpy.data.meshes.new('Tongue'); bm.to_mesh(tm); bm.free()
tg = add_obj('Tongue', tm); tm.materials.append(mat('tongue', (0.55, 0.2, 0.22), 0.45))
skinned(tg, [('jaw', lambda c: 1.0)])
# teeth: a row of rounded little blocks along the lip arc, just behind the lips
def teeth(name, zc, h, upper):
    bm = bmesh.new()
    n = 8
    for k in range(n):
        xx = -0.042 + 0.084 * (k + 0.5) / n
        yy = float(np.interp(abs(xx), [0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06], [-0.357, -0.357, -0.352, -0.349, -0.344, -0.336, -0.328])) + 0.012 + 2.0 * abs(xx) ** 2
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r['verts']:
            v.co = Vector((v.co.x * 0.009 + xx, v.co.y * 0.006 + yy, v.co.z * h + zc))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.0018, segments=2, affect='EDGES')
    m = bpy.data.meshes.new(name); bm.to_mesh(m); bm.free()
    o = add_obj(name, m); m.materials.append(mat('teeth', (0.92, 0.88, 0.76), 0.3))
    skinned(o, [('head' if upper else 'jaw', lambda c: 1.0)])
teeth('TeethTop', 1.3655, 0.009, True)
teeth('TeethBot', 1.3505, 0.008, False)
# eyeball (sphere around +Y local, aimed down EYE_N); UVs from the sphere let Godot paint the iris
bm = bmesh.new(); bm.loops.layers.uv.new('UVMap'); bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=24, radius=EYE_RAD, calc_uvs=True)
rot = (-EYE_N).to_track_quat('Z', 'Y').to_matrix().to_4x4()   # local +Z = pupil direction
bmesh.ops.transform(bm, matrix=Matrix.Translation(EYE_C) @ (-EYE_N).to_track_quat('-Z', 'Y').to_matrix().to_4x4() @ Matrix.Rotation(0, 4, 'X'), verts=bm.verts)
em = bpy.data.meshes.new('EyeR'); bm.to_mesh(em); bm.free()
eye = add_obj('EyeR', em)
em_mat = mat('eye_r', (1, 1, 1), 0.08)
em_mat.node_tree.nodes['Principled BSDF'].inputs['Coat Weight'].default_value = 1.0
img = bpy.data.images.new('vesk_eye', 256, 256)
H = W = 256
vv = (np.arange(H) + 0.5) / H
lat = np.abs(vv - 0.5) * 2 * 90.0          # 90 deg at both poles (iris painted on both so UV orientation can't hide it)
ang = 90.0 - lat                           # degrees away from the pole
col = np.zeros((H, 3))
scl = np.array([0.93, 0.9, 0.84]); iris_o = np.array([0.55, 0.27, 0.07]); iris_i = np.array([0.95, 0.62, 0.22])
for k in range(H):
    a = ang[k]
    if a < 9.5: c = np.array([0.02, 0.015, 0.01])
    elif a < 23.0:
        t = (a - 9.5) / 13.5; c = iris_i * (1 - t) + iris_o * t
    elif a < 25.5: c = np.array([0.12, 0.06, 0.03])
    else:
        t = min(1.0, (a - 25.5) / 50.0); c = scl * (1 - 0.12 * t) + np.array([0.06, 0.0, 0.0]) * t
    col[k] = c
px = np.ones((H, W, 4)); px[:, :, :3] = col[:, None, :]
img.pixels[:] = px.ravel().tolist(); img.pack()
tex = em_mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = img
em_mat.node_tree.links.new(tex.outputs['Color'], em_mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
em.materials.append(em_mat)
skinned(eye, [('eye.R', lambda c: 1.0)])
# store the pupil direction in local terms for the shader: vertex colour R = dot(normal, EYE_N)
cl = em.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
for v in em.vertices:
    n = (v.co - EYE_C).normalized()
    d = n.dot(EYE_N)
    side = n.dot(Vector((1, 0, 0)).cross(EYE_N).normalized()) if False else 0.0
    cl.data[v.index].color = (d * 0.5 + 0.5, 0, 0, 1)
# glass dome over the eyepiece lens
LENS_C = Vector((0.0885, -0.262, 1.4615)); LENS_N = Vector((0.25, -1.0, 0.0)).normalized()
bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=0.03)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 0.0215], context='VERTS')
for v in bm.verts: v.co.z -= 0.0215
bmesh.ops.transform(bm, matrix=Matrix.Translation(LENS_C) @ LENS_N.to_track_quat('Z', 'Y').to_matrix().to_4x4(), verts=bm.verts)
lm = bpy.data.meshes.new('LensGlass'); bm.to_mesh(lm); bm.free()
lens = add_obj('LensGlass', lm); lm.materials.append(mat('lens_glass', (0.6, 0.75, 0.7), 0.05, alpha=0.18))
skinned(lens, [('head', lambda c: 1.0)])
for o in (bag, tg, eye, lens): 
    for p in o.data.polygons: p.use_smooth = True
for o in bpy.data.objects:
    if o.type == 'MESH' and o.name.startswith('Teeth'):
        for p in o.data.polygons: p.use_smooth = True

# ---------------------------------------------------------------- 8. split the face off so only it carries morph targets
# (custom normals first, so the cut line shades the same on both sides)
me.data.normals_split_custom_set_from_vertices([v.normal[:] for v in me.data.vertices])
co = coords()
box = (co[:, 1] < -0.09) & (co[:, 2] > 1.19) & (np.abs(co[:, 0]) < 0.2)
moved = np.zeros(len(co), bool)
for kb in me.data.shape_keys.key_blocks[1:]:
    kc = np.zeros(len(co) * 3); kb.data.foreach_get('co', kc)
    moved |= np.linalg.norm(kc.reshape(-1, 3) - co, axis=1) > 1e-7
moved |= jaw_w > 0.001
print('moved verts', int(moved.sum()), 'outside box', int((moved & ~box).sum()))
bpy.context.view_layer.objects.active = me
for o in bpy.context.selected_objects: o.select_set(False)
me.select_set(True)
select_faces(box)
bpy.ops.mesh.separate(type='SELECTED'); bpy.ops.object.mode_set(mode='OBJECT')
face = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Mesh_0') and o != me][0]
face.name = 'VeskFace'; face.data.name = 'VeskFace'
me.shape_key_clear()
print('body verts', len(me.data.vertices), 'face verts', len(face.data.vertices))

# mouth parts follow the lips exactly: copy each vertex's weights from the nearest face vertex on its side
from mathutils.kdtree import KDTree
fco = np.zeros(len(face.data.vertices) * 3); face.data.vertices.foreach_get('co', fco); fco = fco.reshape(-1, 3)
fgn = {g.index: g.name for g in face.vertex_groups}
fw = [[(fgn[g.group], g.weight) for g in v.groups if g.weight > 0.001] for v in face.data.vertices]
flz = lip_z(np.clip(fco[:, 0], -0.09, 0.09))
trees = {}
for side in (True, False):
    kd = KDTree(len(fco)); cnt = 0
    for i, p in enumerate(fco):
        if p[1] < -0.22 and abs(p[0]) < 0.09 and ((p[2] > flz[i]) == side): kd.insert(p, i); cnt += 1
    kd.balance(); trees[side] = kd
def copy_weights(obj, upper_fn):
    for vg in list(obj.vertex_groups): obj.vertex_groups.remove(vg)
    groups = {}
    for v in obj.data.vertices:
        wc = obj.matrix_world @ v.co
        _, i, _ = trees[upper_fn(wc)].find(wc)
        for gname, ww in fw[i]:
            if gname not in groups: groups[gname] = obj.vertex_groups.new(name=gname)
            groups[gname].add([v.index], ww, 'REPLACE')
copy_weights(bag, lambda c: c.z >= 1.357)
copy_weights(tg, lambda c: False)
copy_weights(bpy.data.objects['TeethTop'], lambda c: True)
copy_weights(bpy.data.objects['TeethBot'], lambda c: False)

ico = bpy.data.objects.get('Icosphere')
if ico: bpy.data.objects.remove(ico)
arm.data.pose_position = 'POSE'
arm.animation_data_create(); arm.animation_data.action = None
if '--no-export' not in sys.argv:
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animation_mode='ACTIONS', export_force_sampling=True,
                              export_anim_single_armature=True, export_skins=True, export_morph=True, export_morph_normal=False,
                              export_image_format='AUTO')
    print('exported', OUT)
bpy.ops.wm.save_as_mainfile(filepath='/tmp/w/vesk_face.blend')
