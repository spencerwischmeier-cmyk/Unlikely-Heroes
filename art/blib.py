# Helpers: author models in game coordinates (Y up, +Z forward, three.js Euler XYZ) and store them
# in Blender (Z up) so the glTF export comes out in game coordinates with axis-aligned pivots.
import bpy, bmesh, math
from mathutils import Matrix, Vector, Euler

G2B = Matrix.Rotation(math.radians(90), 4, 'X')  # game (x,y,z) -> blender (x,-z,y)

def reset():
    for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.metaballs, bpy.data.cameras, bpy.data.lights, bpy.data.images, bpy.data.node_groups):
        for d in list(coll): coll.remove(d)

def gv(x, y, z): return G2B @ Vector((x, y, z))

def mat(name, color, metal=0.0, rough=0.5, emit=None, strength=0.0, sheen=0.0, sheen_tint=(1, 1, 1), coat=0.0, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    def srgb(c):
        if isinstance(c, int): c = ((c >> 16) & 255, (c >> 8) & 255, c & 255)
        f = lambda v: (v / 255) ** 2.2 if v > 1 or isinstance(v, int) else v
        return tuple(f(v) for v in c) + (1,)
    b.inputs['Base Color'].default_value = srgb(color)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    if emit is not None:
        b.inputs['Emission Color'].default_value = srgb(emit)
        b.inputs['Emission Strength'].default_value = strength
    if sheen:
        b.inputs['Sheen Weight'].default_value = sheen
        b.inputs['Sheen Tint'].default_value = srgb(sheen_tint)
    if coat:
        b.inputs['Coat Weight'].default_value = coat
        b.inputs['Coat Roughness'].default_value = 0.1
    m.diffuse_color = srgb(color)
    return m

def glowmat(name, color, strength=6):
    return mat(name, 0x000000, 0, 1, emit=color, strength=strength)

# ---------- bmesh primitives, built in game space (Y up) ----------
def _bm_to_mesh(bm, name):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free(); return me

def bm_sphere(r=1, seg=24, rings=16):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.radians(-90), 4, 'X'), verts=bm.verts)  # poles on Y
    return bm

def bm_cyl(r1, r2, h, seg=24, cap=True):
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=h)
    bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.radians(-90), 4, 'X'), verts=bm.verts)  # axis on Y, r1 at bottom
    return bm

def bm_box(sx, sy, sz):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts); return bm

def bm_capsule(r, length, seg=20, rings=12):
    bm = bm_sphere(r, seg, rings)
    for v in bm.verts:
        if v.co.y > 1e-5: v.co.y += length / 2
        elif v.co.y < -1e-5: v.co.y -= length / 2
    return bm

def bm_torus(R, r, seg=32, tube=10, arc=math.tau):
    bm = bmesh.new(); rows = []
    closed = abs(arc - math.tau) < 1e-6
    n = seg if closed else seg + 1
    for i in range(n):
        a = arc * i / seg; row = []
        for j in range(tube):
            b = math.tau * j / tube
            row.append(bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b))))
        rows.append(row)
    for i in range(n if closed else n - 1):
        A, B = rows[i], rows[(i + 1) % n]
        for j in range(tube): bm.faces.new((A[j], B[j], B[(j + 1) % tube], A[(j + 1) % tube]))
    return bm

def bm_cone(r, h, seg=16): return bm_cyl(r, 0.0001, h, seg)

# ---------- objects ----------
def empty(name, parent=None, at=(0, 0, 0), parent_at=(0, 0, 0)):
    e = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(e)
    e.empty_display_size = 0.05
    if parent: e.parent = parent
    e.location = gv(*(Vector(at) - Vector(parent_at)))
    e['game_at'] = list(at)
    return e

def part(name, bm, material, parent=None, at=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), subsurf=0, bevel=0.0, smooth=True, decimate=None, rounded=0.0):
    # bake scale + rotation (three.js XYZ order == blender 'ZYX') into the mesh, keep only translation
    M = Matrix.Diagonal(Vector(scale)).to_4x4()
    M = Euler(rot, 'ZYX').to_matrix().to_4x4() @ M
    bmesh.ops.transform(bm, matrix=G2B @ M, verts=bm.verts)
    me = _bm_to_mesh(bm, name)
    if smooth:
        for p in me.polygons: p.use_smooth = True
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    me.materials.append(material)
    pat = Vector(parent['game_at']) if parent is not None else Vector((0, 0, 0))
    if parent: o.parent = parent
    o.location = gv(*(Vector(at) - pat))
    o['game_at'] = list(at)
    if bevel:
        b = o.modifiers.new('bevel', 'BEVEL'); b.width = bevel; b.segments = 3; b.limit_method = 'ANGLE'
    if rounded:  # like RoundedBoxGeometry: every edge rounded with radius `rounded`
        b = o.modifiers.new('round', 'BEVEL'); b.width = rounded; b.segments = 4; b.limit_method = 'NONE'; b.harden_normals = False
    if subsurf:
        s = o.modifiers.new('subsurf', 'SUBSURF'); s.levels = subsurf; s.render_levels = subsurf
    if decimate:
        d = o.modifiers.new('dec', 'DECIMATE'); d.ratio = decimate
    return o

def limb(name, a, b, r, material, parent=None, seg=16):
    a, b = Vector(a), Vector(b); d = b - a
    bm = bm_capsule(r, d.length, seg, 10)
    q = Vector((0, 1, 0)).rotation_difference(d.normalized())
    bmesh.ops.transform(bm, matrix=q.to_matrix().to_4x4(), verts=bm.verts)
    return part(name, bm, material, parent, at=tuple((a + b) / 2))

def blob(name, balls, material, parent=None, at=(0, 0, 0), res=0.02, threshold=0.6, decimate=None):
    """Organic shape from metaballs given in game space relative to `at`: [(x,y,z,radius,(sx,sy,sz)), ...]"""
    mb = bpy.data.metaballs.new(name + '_mb'); mb.resolution = res; mb.render_resolution = res; mb.threshold = threshold
    for (x, y, z, r, *s) in balls:
        el = mb.elements.new(); el.co = gv(x, y, z); el.radius = r / 0.575  # visible radius = 0.575 * influence radius
        if s:
            sx, sy, sz = s[0]; el.type = 'ELLIPSOID'; el.size_x, el.size_y, el.size_z = sx, sz, sy
    tmp = bpy.data.objects.new(name + '_tmp', mb); bpy.context.scene.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get(); dg.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp, do_unlink=True)
    me.name = name
    for p in me.polygons: p.use_smooth = True
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    me.materials.clear(); me.materials.append(material)
    pat = Vector(parent['game_at']) if parent is not None else Vector((0, 0, 0))
    if parent: o.parent = parent
    o.location = gv(*(Vector(at) - pat)); o['game_at'] = list(at)
    if decimate:
        d = o.modifiers.new('dec', 'DECIMATE'); d.ratio = decimate
    return o

def export(path, root):
    for o in bpy.data.objects: o.select_set(False)
    def sel(o):
        o.select_set(True)
        for c in o.children: sel(c)
    sel(root)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
                              export_extras=False, export_cameras=False, export_lights=False, export_draco_mesh_compression_enable=False)

def tri_count(root):
    dg = bpy.context.evaluated_depsgraph_get(); n = 0
    def walk(o):
        nonlocal n
        if o.type in ('MESH',):
            me = o.evaluated_get(dg).to_mesh(); me.calc_loop_triangles(); n += len(me.loop_triangles); o.evaluated_get(dg).to_mesh_clear()
        for c in o.children: walk(c)
    walk(root); return n

def preview(path, root, cam_from=(2.2, 1.6, 3.2), look=(0, 0.9, 0), size=(900, 900), lens=50, samples=48):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = samples; sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = size; sc.render.film_transparent = False
    sc.view_settings.view_transform = 'AgX'
    w = bpy.data.worlds.get('W') or bpy.data.worlds.new('W'); sc.world = w; w.use_nodes = True
    bg = w.node_tree.nodes['Background']; bg.inputs[0].default_value = (0.35, 0.55, 0.75, 1); bg.inputs[1].default_value = 0.9
    cam = bpy.data.objects.get('PrevCam')
    if not cam:
        cam = bpy.data.objects.new('PrevCam', bpy.data.cameras.new('PrevCam')); sc.collection.objects.link(cam)
        sun = bpy.data.objects.new('PrevSun', bpy.data.lights.new('PrevSun', 'SUN')); sc.collection.objects.link(sun)
        sun.data.energy = 4; sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
        fl = bpy.data.objects.new('PrevFill', bpy.data.lights.new('PrevFill', 'AREA')); sc.collection.objects.link(fl)
        fl.data.energy = 300; fl.data.size = 3; fl.location = gv(-3, 2.5, 3)
        floor = bpy.data.objects.new('PrevFloor', bpy.data.meshes.new('PrevFloor')); sc.collection.objects.link(floor)
        bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6); bm.to_mesh(floor.data); bm.free()
        floor.data.materials.append(mat('PrevFloorMat', 0x8e9aa6, 0.6, 0.4))
    cam.data.lens = lens
    cam.location = gv(*cam_from)
    d = gv(*look) - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)

def sdf_blob(name, ells, material, parent=None, at=(0, 0, 0), k=0.035, seg=64, rings=48, center=(0, 0, 0)):
    """Smooth union of ellipsoids [(x,y,z, rx,ry,rz)] (game space, relative to `at`), meshed by projecting a sphere
    from `center` onto the surface. Shapes must be star-shaped around `center`."""
    import math
    def sd(p):
        d = None
        for (x, y, z, rx, ry, rz) in ells:
            q = Vector(((p.x - x) / rx, (p.y - y) / ry, (p.z - z) / rz))
            v = (q.length - 1.0) * min(rx, ry, rz)
            if d is None: d = v
            else:
                h = max(k - abs(d - v), 0.0) / k
                d = min(d, v) - h * h * k * 0.25
        return d
    C = Vector(center)
    bm = bm_sphere(1.0, seg, rings)
    for v in bm.verts:
        dirn = v.co.normalized()
        lo, hi = 0.0, 2.0
        for _ in range(40):
            mid = (lo + hi) / 2
            if sd(C + dirn * mid) < 0: lo = mid
            else: hi = mid
        v.co = C + dirn * lo
    return part(name, bm, material, parent, at=at)
