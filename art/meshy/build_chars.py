# Turn the raw Meshy models (art/meshy/chars.py) into game models in godot/models/ and godot/models/chars/.
#   /tmp/claude-0/bpyenv/bin/python art/meshy/build_chars.py -- <name>...
# Every model: transforms applied, scaled to its game size, feet (or centre, for flyers) on the origin, facing +Z
# (glTF), textures shrunk to 1k and stored as PNG.
# Rollers are split into the parts the game animates: "ball" (rolls) and "cap" (the head, turns to face travel).
# The ball is rebuilt from its lower half mirrored upward, so it is a whole sphere that can roll any way.
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector, Matrix

SRC = '/tmp/claude-0/meshy/chars'
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
MODELS = os.path.join(ROOT, 'godot', 'models')

def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def load(name):
    bpy.ops.import_scene.gltf(filepath=f'{SRC}/{name}_raw.glb')
    obs = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in obs:
        o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(obs) > 1: bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    for e in [x for x in bpy.data.objects if x.type != 'MESH']: bpy.data.objects.remove(e)
    return o

def bounds(o):
    vs = np.array([v.co[:] for v in o.data.vertices])
    return vs.min(0), vs.max(0)

def fit(o, height=None, width=None, ground=True, yaw=0.0):
    """Scale to `height` (or `width` = max horizontal size), centre on X/Y, feet on z=0 (or centred)."""
    if yaw: o.data.transform(Matrix.Rotation(yaw, 4, 'Z'))
    lo, hi = bounds(o)
    s = height / (hi[2] - lo[2]) if height else width / max(hi[0] - lo[0], hi[1] - lo[1])
    c = (lo + hi) / 2
    off = Vector((-c[0], -c[1], -lo[2] if ground else -c[2]))
    o.data.transform(Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation(off))
    o.data.update()
    return s

def shrink_textures(size=1024):
    """Scale every texture down to `size` and re-save it as a real PNG (the export must not embed JPEG)."""
    tmp = f'{SRC}/tex'; os.makedirs(tmp, exist_ok=True)
    for k, im in enumerate(bpy.data.images):
        if im.size[0] > size: im.scale(size, size)
        path = f'{tmp}/{k}_{im.name}.png'
        im.filepath_raw = path; im.file_format = 'PNG'; im.save()
        if im.packed_file: im.unpack(method='REMOVE')
        im.filepath = path; im.source = 'FILE'; im.reload()

def mesh_from_faces(src, faces_idx, name, mirror_z=None):
    """New object with the given faces of `src` (optionally plus a copy mirrored across z = mirror_z)."""
    bm = bmesh.new(); bm.from_mesh(src.data)
    keep = set(faces_idx)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context='FACES')
    if mirror_z is not None:
        ret = bmesh.ops.duplicate(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces))
        nv = [g for g in ret['geom'] if isinstance(g, bmesh.types.BMVert)]
        nf = [g for g in ret['geom'] if isinstance(g, bmesh.types.BMFace)]
        for v in nv: v.co.z = 2 * mirror_z - v.co.z
        bmesh.ops.reverse_faces(bm, faces=nf, flip_multires=False)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.clear()
    for m in src.data.materials: me.materials.append(m)
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    return ob

def sphere_fit(pts):
    A = np.c_[2 * pts, np.ones(len(pts))]
    b = (pts ** 2).sum(1)
    x = np.linalg.lstsq(A, b, rcond=None)[0]
    c = x[:3]; r = math.sqrt(x[3] + (c ** 2).sum())
    return c, r

def split_roller(o, name):
    """Split a head-on-a-ball bot into ball + cap. Returns (ball_obj, cap_obj, centre, radius)."""
    vs = np.array([v.co[:] for v in o.data.vertices])
    lo, hi = vs.min(0), vs.max(0)
    low = vs[vs[:, 2] < lo[2] + (hi[2] - lo[2]) * 0.28]
    c, r = sphere_fit(low)
    print(name, 'ball centre', c.round(3), 'r', round(r, 3))
    ball_f, cap_f = [], []
    for f in o.data.polygons:
        p = np.array(f.center[:])
        d = np.linalg.norm(p - c)
        if p[2] < c[2] - 0.01 and d < r * 1.12: ball_f.append(f.index)
        elif p[2] >= c[2] and abs(d - r) < r * 0.05 and p[2] < c[2] + r * 0.55: pass   # upper ball, rebuilt by mirroring
        else: cap_f.append(f.index)
    ball = mesh_from_faces(o, ball_f, f'{name}_ball', mirror_z=c[2])
    cap = mesh_from_faces(o, cap_f, f'{name}_cap')
    bpy.data.objects.remove(o)
    return ball, cap, Vector(c), r

def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(e)
    e.location = loc
    if parent: e.parent = parent
    return e

def reparent(ob, parent):
    """Parent keeping the world position (mesh data moves so the object sits at the parent's origin)."""
    ob.data.transform(Matrix.Translation(-parent.matrix_world.translation))
    ob.parent = parent; ob.location = (0, 0, 0)

def export(path, root=None):
    bpy.context.view_layer.update()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_image_format='AUTO',
                              export_cameras=False, export_lights=False, export_apply=True, export_animations=False)
    print('wrote', path, os.path.getsize(path) // 1024, 'KB')

# ---------------------------------------------------------------- models
def roller(src, out, R_game=0.55, root_name='Roller'):
    clear(); o = load(src)
    o.data.transform(Matrix.Rotation(0, 4, 'Z'))
    lo, hi = bounds(o)
    ball, cap, c, r = split_roller(o, src)
    s = R_game / r
    # ball centre to (0, 0, R_game)
    T = Matrix.Translation(Vector((0, 0, R_game))) @ Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation(-c)
    for ob in (ball, cap): ob.data.transform(T); ob.data.update()
    root = empty(root_name)
    b = empty('ball', root, (0, 0, R_game)); k = empty('cap', root, (0, 0, R_game))
    bpy.context.view_layer.update()
    reparent(ball, b); reparent(cap, k)
    shrink_textures()
    export(out)

def static(src, out, height=None, width=None, ground=True, yaw=0.0, name=None, wrap=None):
    """wrap = (root_name, pivot_name): put the mesh under root/pivot empties (e.g. Hornet/inner)."""
    clear(); o = load(src)
    fit(o, height, width, ground, yaw)
    o.name = name or src
    if wrap:
        r = empty(wrap[0]); p = empty(wrap[1], r); o.parent = p
    shrink_textures()
    export(out)

JOBS = {
    'roller': lambda: roller('roller_head', f'{MODELS}/roller.glb', 0.55, 'Roller'),
    'crew_roller': lambda: roller('crew_head', f'{MODELS}/crew_roller.glb', 0.5, 'CrewRoller'),
    'hornet': lambda: static('hornet', f'{MODELS}/hornet.glb', height=1.6, ground=False, name='hornet_body', wrap=('Hornet', 'inner')),
    'magnet': lambda: static('magnet', f'{MODELS}/chars/crane_magnet.glb', width=2.5, ground=False),
    'crane_cab': lambda: static('crane_cab', f'{MODELS}/chars/crane_cab.glb', width=3.0, yaw=math.pi / 2),
    'crane_base': lambda: static('crane_base', f'{MODELS}/chars/crane_base.glb', width=5.2, yaw=math.pi / 2),
    'barricade': lambda: static('barricade', f'{MODELS}/chars/crew_barricade.glb', width=2.5),
    'gizmart': lambda: static('gizmart', f'{MODELS}/chars/gizmart.glb', height=3.0),
}
if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    for n in args or list(JOBS):
        JOBS[n]()
