"""High-detail scrap pieces for the Junkyard clutter (junk_kit.gd MultiMeshes) and the Sorting Works bales.

Each piece replaces one of junk_kit.gd's unit primitives and keeps its size and centre, so every existing
pile, litter scatter and tower picks it up without layout changes:
    plate 1 x 0.07 x 1, beam 0.18 x 0.18 x 1 (along Z), block 1 x 1 x 1, pipe r0.5 h1, drum r0.36 h0.95,
    tire torus 0.24..0.48, gear r0.5 h0.12, nut hex r0.5 h0.5   (Godot units, Y up, centred)
plus `bale` (1 x 1 x 1 crushed-scrap cube with steel straps, two material slots).

The pieces are bevelled and dented. Edge wear and cavity are baked per vertex into the second UV channel
(UV2.x = convex edge, UV2.y = cavity), which shaders/scrap.gdshader turns into chipped paint, bare metal edges,
rust and grime. The bale also gets a baked crushed-metal texture set (textures/junkyard/bale_*.png).

Run: blender --background --python art/scrap_hd.py   (or python3 with the bpy module)
"""
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
OUT_GLB = os.path.join(REPO, "godot", "models", "junkyard", "scrap_hd.glb")
TEX_DIR = os.path.join(REPO, "godot", "textures", "junkyard")
rng = random.Random(77)
D = bpy.data


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def obj_from_bm(name, bm):
    me = D.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = D.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    return ob


def apply_mods(ob):
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects: o.select_set(False)
    ob.select_set(True)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def bevel(ob, width, segs=2, angle=40):
    m = ob.modifiers.new("bev", "BEVEL"); m.width = width; m.segments = segs
    m.limit_method = "ANGLE"; m.angle_limit = math.radians(angle); m.harden_normals = True
    try: ob.data.use_auto_smooth = True
    except Exception: pass
    return m


def dent(ob, strength, scale=0.6, seed=0):
    t = D.textures.new("dent%d" % seed, "CLOUDS"); t.noise_scale = scale; t.noise_depth = 2
    m = ob.modifiers.new("dent", "DISPLACE"); m.texture = t; m.strength = strength; m.mid_level = 0.5
    m.texture_coords = "OBJECT" if False else "LOCAL"


def subdiv_simple(ob, levels=1):
    m = ob.modifiers.new("sub", "SUBSURF"); m.subdivision_type = "SIMPLE"; m.levels = levels; m.render_levels = levels


def join(objs, name):
    for o in bpy.context.selected_objects: o.select_set(False)
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active; ob.name = name; ob.data.name = name
    return ob


def cube(size, loc=(0, 0, 0)):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return obj_from_bm("c", bm)


def cylinder(r, h, segs, loc=(0, 0, 0), r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=h)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    return obj_from_bm("cy", bm)


def torus(R, r, maj=24, minr=10, loc=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=maj, minor_segments=minr, location=loc)
    return bpy.context.active_object


def shade(ob, angle=35):
    for p in ob.data.polygons: p.use_smooth = True
    try:
        ob.data.shade_smooth_by_angle(angle=math.radians(angle))
    except Exception:
        try:
            bpy.context.view_layer.objects.active = ob
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
        except Exception:
            pass


# ------------------------------------------------------------------------------------------------ pieces
def make_plate():
    ob = cube((1.0, 1.0, 0.07))
    subdiv_simple(ob, 2)
    apply_mods(ob)
    # bend one corner up and ripple the sheet
    for v in ob.data.vertices:
        x, y = v.co.x, v.co.y
        lift = max(0.0, x + y - 0.45) ** 2 * 0.28
        v.co.z += lift + 0.012 * math.sin(x * 9.0 + y * 5.0)
    bevel(ob, 0.012, 2, 30)
    apply_mods(ob)
    rivets = []
    for i in range(10):
        t = (i + 0.5) / 10
        for (x, y) in ((-0.45, -0.5 + t), (0.45 - t * 0.9, -0.45)):
            r = cylinder(0.018, 0.02, 6, (x, y, 0.045)); rivets.append(r)
    return join([ob] + rivets, "scrap_plate")


def make_beam():
    h = 0.18; t = 0.028; L = 1.0
    parts = [cube((h, L, t), (0, 0, h / 2 - t / 2)), cube((h, L, t), (0, 0, -h / 2 + t / 2)), cube((t * 0.8, L, h - 2 * t), (0, 0, 0))]
    ob = join(parts, "scrap_beam")
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(ob.data); bm.free()
    bevel(ob, 0.006, 2, 40); apply_mods(ob)
    # bolt plates near the ends
    bolts = []
    for y in (-0.44, 0.44):
        for z in (-0.04, 0.04):
            bolts.append(cylinder(0.012, 0.03, 6, (0.02, y, z)))
            bolts[-1].rotation_euler = (0, math.pi / 2, 0)
    for b in bolts:
        bpy.context.view_layer.objects.active = b; b.select_set(True)
        bpy.ops.object.transform_apply(rotation=True)
        b.select_set(False)
    ob = join([ob] + bolts, "scrap_beam")
    return ob


def make_block():
    ob = cube((1, 1, 1))
    bm = bmesh.new(); bm.from_mesh(ob.data)
    # inset panels with a recessed face on each side
    res = bmesh.ops.inset_individual(bm, faces=bm.faces[:], thickness=0.08, depth=-0.025)
    bm.to_mesh(ob.data); bm.free()
    bevel(ob, 0.025, 2, 40); apply_mods(ob)
    subdiv_simple(ob, 1); apply_mods(ob)
    dent(ob, 0.03, 0.5, 3); apply_mods(ob)
    # corner brackets
    br = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            br.append(cube((0.1, 0.1, 1.02), (sx * 0.48, sy * 0.48, 0)))
    for b in br:
        bevel(b, 0.01, 1); apply_mods(b)
    return join([ob] + br, "scrap_block")


def make_pipe():
    body = cylinder(0.42, 1.0, 20)
    bm = bmesh.new(); bm.from_mesh(body.data)
    caps = [f for f in bm.faces if abs(f.normal.z) > 0.9]
    bmesh.ops.inset_individual(bm, faces=caps, thickness=0.08, depth=-0.3)   # hollow ends
    bm.to_mesh(body.data); bm.free()
    bevel(body, 0.01, 2, 40); apply_mods(body)
    fl = []
    for z in (-0.46, 0.46):
        f = cylinder(0.5, 0.08, 20, (0, 0, z)); bevel(f, 0.012, 2); apply_mods(f); fl.append(f)
        for i in range(8):
            a = i / 8 * math.tau
            fl.append(cylinder(0.025, 0.11, 6, (math.cos(a) * 0.46, math.sin(a) * 0.46, z)))
    return join([body] + fl, "scrap_pipe")


def make_drum():
    r = 0.36; h = 0.95
    body = cylinder(r * 0.985, h * 0.96, 28)
    bm = bmesh.new(); bm.from_mesh(body.data)
    top = [f for f in bm.faces if f.normal.z > 0.9]
    bmesh.ops.inset_individual(bm, faces=top, thickness=0.03, depth=-0.025)
    bm.to_mesh(body.data); bm.free()
    subdiv_simple(body, 1); apply_mods(body)
    dent(body, 0.025, 0.35, 5); apply_mods(body)
    parts = [body]
    for z in (-h / 2 + 0.01, h / 2 - 0.01):
        parts.append(torus(r, 0.016, 32, 6, (0, 0, z)))
    for z in (-h / 6, h / 6):
        parts.append(torus(r * 0.995, 0.012, 32, 6, (0, 0, z)))
    parts.append(cylinder(0.04, 0.03, 10, (0.17, 0.0, h / 2 - 0.02)))
    parts.append(cylinder(0.025, 0.03, 8, (-0.2, 0.06, h / 2 - 0.02)))
    return join(parts, "scrap_drum")


def make_tire():
    R = 0.36; r = 0.12
    ob = torus(R, r, 36, 12)
    ob.scale = (1, 1, 1.25); bpy.ops.object.transform_apply(scale=True)
    # tread blocks on the outer band
    bm = bmesh.new(); bm.from_mesh(ob.data)
    outer = [f for f in bm.faces if Vector((f.calc_center_median().x, f.calc_center_median().y, 0)).length > R + r * 0.75]
    sel = [f for i, f in enumerate(outer) if i % 2 == 0]
    bmesh.ops.inset_individual(bm, faces=sel, thickness=0.006, depth=0.012)
    bm.to_mesh(ob.data); bm.free()
    hub = cylinder(0.2, 0.12, 16)
    bm = bmesh.new(); bm.from_mesh(hub.data)
    caps = [f for f in bm.faces if abs(f.normal.z) > 0.9]
    bmesh.ops.inset_individual(bm, faces=caps, thickness=0.05, depth=-0.03)
    bm.to_mesh(hub.data); bm.free()
    bevel(hub, 0.01, 2); apply_mods(hub)
    hub.data.materials.append(D.materials.get("tire_hub") or D.materials.new("tire_hub"))
    ob.data.materials.append(D.materials.get("tire_rubber") or D.materials.new("tire_rubber"))
    return join([ob, hub], "scrap_tire")


def make_gear():
    bm = bmesh.new()
    teeth = 14; ro = 0.5; ri = 0.41
    pts = []
    for i in range(teeth * 4):
        a = i / (teeth * 4) * math.tau
        rr = ro if (i % 4) in (1, 2) else ri
        pts.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, -0.06)))
    f = bm.faces.new(pts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    vs = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, 0.12), verts=vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm("g", bm)
    bevel(ob, 0.008, 2, 30); apply_mods(ob)
    hub = cylinder(0.14, 0.18, 16); bevel(hub, 0.012, 2); apply_mods(hub)
    holes = [cylinder(0.06, 0.13, 10, (math.cos(a) * 0.26, math.sin(a) * 0.26, 0)) for a in (0, 2.094, 4.189)]
    for hh in holes:
        bevel(hh, 0.006, 1); apply_mods(hh)
    return join([ob, hub] + holes, "scrap_gear")


def make_nut():
    ob = cylinder(0.5, 0.5, 6)
    bm = bmesh.new(); bm.from_mesh(ob.data)
    caps = [f for f in bm.faces if abs(f.normal.z) > 0.9]
    bmesh.ops.inset_individual(bm, faces=caps, thickness=0.22, depth=-0.12)
    bm.to_mesh(ob.data); bm.free()
    bevel(ob, 0.05, 2, 40); apply_mods(ob)
    return ob


def make_bale():
    """A cube of crushed scrap: crumpled skin, layered creases, two steel straps."""
    ob = cube((1, 1, 1))
    subdiv_simple(ob, 4); apply_mods(ob)
    r = random.Random(9)
    for v in ob.data.vertices:
        n = v.co.normalized()
        # crumple and layered creases
        k = 0.025 * math.sin(v.co.z * 31.0 + math.sin(v.co.x * 7.0) * 2.0) + r.uniform(-0.012, 0.012)
        v.co += Vector((v.co.x, v.co.y, 0)).normalized() * k if abs(v.co.z) < 0.49 else Vector((0, 0, k * 0.5))
    bevel(ob, 0.03, 2, 50); apply_mods(ob)
    ob.data.materials.append(D.materials.get("bale_skin") or D.materials.new("bale_skin"))
    straps = []
    for y in (-0.28, 0.28):
        s = cube((1.035, 0.07, 1.035), (0, y, 0))
        bm = bmesh.new(); bm.from_mesh(s.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.normal.y) > 0.9], context="FACES")
        bm.to_mesh(s.data); bm.free()
        sol = s.modifiers.new("sol", "SOLIDIFY"); sol.thickness = 0.012
        apply_mods(s)
        s.data.materials.append(D.materials.get("bale_strap") or D.materials.new("bale_strap"))
        straps.append(s)
    return join([ob] + straps, "scrap_bale")


# ------------------------------------------------------------------------------------------------ bake edge/cavity to UV2
def bake_uv2(ob):
    """UV2.x = convex edge wear, UV2.y = cavity. Per vertex, from the dihedral angles of the edges around it."""
    me = ob.data
    bm = bmesh.new(); bm.from_mesh(me)
    bm.normal_update()
    edge = {}
    cav = {}
    for v in bm.verts:
        e_sum = 0.0; c_sum = 0.0
        for e in v.link_edges:
            if len(e.link_faces) != 2:
                e_sum = max(e_sum, 0.6); continue
            a = e.calc_face_angle_signed(0.0)   # >0 convex, <0 concave
            if a > 0: e_sum = max(e_sum, min(1.0, max(0.0, a - math.radians(20)) / math.radians(30)))
            else: c_sum = max(c_sum, min(1.0, max(0.0, -a - math.radians(15)) / math.radians(30)))
        edge[v.index] = e_sum; cav[v.index] = c_sum
    # blur once over neighbours so it spreads a touch
    e2 = {}; c2 = {}
    for v in bm.verts:
        nb = [e.other_vert(v) for e in v.link_edges]
        e2[v.index] = 0.6 * edge[v.index] + 0.4 * (sum(edge[n.index] for n in nb) / max(1, len(nb)))
        c2[v.index] = 0.6 * cav[v.index] + 0.4 * (sum(cav[n.index] for n in nb) / max(1, len(nb)))
    bm.free()
    while len(me.uv_layers) < 1:
        me.uv_layers.new(name="UVMap")
    if not me.uv_layers[0].data or True:
        # simple box projection for UV1 (used for the bale texture)
        uv = me.uv_layers[0]
        for poly in me.polygons:
            n = poly.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                u, v = [(co.y, co.z), (co.x, co.z), (co.x, co.y)][ax]
                uv.data[li].uv = (u + 0.5, v + 0.5)
    uv2 = me.uv_layers.new(name="Wear")
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            uv2.data[li].uv = (e2[vi], c2[vi])


def main():
    reset()
    makers = [make_plate, make_beam, make_block, make_pipe, make_drum, make_tire, make_gear, make_nut, make_bale]
    objs = []
    for mk in makers:
        ob = mk()
        if ob.name != "scrap_" + mk.__name__[5:]:
            ob.name = "scrap_" + mk.__name__[5:]
        ob.data.name = ob.name
        bpy.context.view_layer.objects.active = ob
        for o in bpy.context.selected_objects: o.select_set(False)
        ob.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        if not ob.data.materials:
            ob.data.materials.append(D.materials.get("scrap") or D.materials.new("scrap"))
        bake_uv2(ob)
        shade(ob)
        # Godot: plate/block/etc. sit centred on the origin like the primitives they replace
        objs.append(ob)
        print("[scrap_hd]", ob.name, len(ob.data.polygons), "faces", tuple(round(x, 3) for x in ob.dimensions))
    # space them out (positions don't matter: Godot takes the meshes by name)
    for i, ob in enumerate(objs):
        ob.location.x = i * 2.0
    for o in objs: o.select_set(True)
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True,
                              export_texcoords=True, export_normals=True, export_materials="PLACEHOLDER",
                              export_attributes=False, export_yup=True)
    print("[scrap_hd] wrote", OUT_GLB)


if __name__ == "__main__" or True:
    main()
