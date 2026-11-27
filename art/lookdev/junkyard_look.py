"""Junkyard look target: a high-end Cycles render of Vesk's Junkyard during the panic.

Not used by the game. It shows where the Junkyard could go if the graphics keep getting pushed: real bevels,
layered rust-and-paint materials, volumetric smoke and fire, haze, string lights, depth of field and a
cinematic grade. It reuses the game's own models (Vesk, Dodger, the shack, the half-built skiff, the magnet,
the bots, kit props) and rebuilds the procedural scrap, the scrap towers and the Sorting Works bales.

Run (Blender 5.x):
    blender --background --python art/lookdev/junkyard_look.py -- [shot ...]
Env:
    LOOK_REPO     repo root (default: two folders up from this file)
    LOOK_OUT      output folder (default: <repo>/art/lookdev/out)
    LOOK_SAMPLES  Cycles samples (default 512)
    LOOK_RES      resolution percentage of 2560x1440 (default 100)
    LOOK_GPU      1 to use OptiX/CUDA if present (default 1)
    LOOK_SAVE     1 to also save the .blend next to the stills
Shots: hero (the yard, shack and skiff), works (the Sorting Works bale climb), dock (the skiff under the crane).
"""
import bpy, bmesh, math, os, random, sys
from mathutils import Vector, Euler, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("LOOK_REPO", os.path.abspath(os.path.join(HERE, "..", "..")))
MODELS = os.path.join(REPO, "godot", "models")
OUT = os.environ.get("LOOK_OUT", os.path.join(HERE, "out"))
SAMPLES = int(os.environ.get("LOOK_SAMPLES", "512"))
RES = int(os.environ.get("LOOK_RES", "100"))
GPU = os.environ.get("LOOK_GPU", "1") == "1"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SHOTS = [a for a in argv if not a.startswith("-")] or ["hero", "works", "dock"]

rng = random.Random(4417)
VOLP = "ShaderNodeVolumePrincipled"
D = bpy.data
C = bpy.context


# ------------------------------------------------------------------------------------------------ basics
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = C.scene
    sc.render.engine = "CYCLES"
    cy = sc.cycles
    cy.samples = SAMPLES
    cy.use_adaptive_sampling = True
    cy.adaptive_threshold = 0.01
    cy.use_denoising = True
    cy.max_bounces = 8
    cy.diffuse_bounces = 3
    cy.glossy_bounces = 3
    cy.transmission_bounces = 6
    cy.volume_bounces = 1
    cy.transparent_max_bounces = 8
    cy.volume_step_rate = 2.0
    cy.blur_glossy = 1.0
    cy.sample_clamp_indirect = 8.0
    sc.render.resolution_x = 2560
    sc.render.resolution_y = 1440
    sc.render.resolution_percentage = RES
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_depth = "8"
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Punchy"
    except Exception:
        pass
    sc.view_settings.exposure = 0.0
    if GPU:
        try:
            prefs = C.preferences.addons["cycles"].preferences
            for kind in ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL"):
                try:
                    prefs.compute_device_type = kind
                    prefs.get_devices()
                    devs = [d for d in prefs.devices if d.type == kind]
                    if devs:
                        for d in prefs.devices: d.use = d.type == kind
                        sc.cycles.device = "GPU"
                        print("[look] GPU:", kind, [d.name for d in devs])
                        break
                except Exception:
                    continue
        except Exception as e:
            print("[look] no GPU", e)
    return sc


def link(ob, coll=None):
    (coll or C.scene.collection).objects.link(ob)
    return ob


def mesh_obj(name, bm, mat=None, bevel=0.0, segs=2, smooth=True):
    me = D.meshes.new(name)
    bm.to_mesh(me); bm.free()
    ob = D.objects.new(name, me)
    link(ob)
    if mat: me.materials.append(mat)
    if smooth:
        for p in me.polygons: p.use_smooth = True
    if bevel > 0:
        m = ob.modifiers.new("bevel", "BEVEL")
        m.width = bevel; m.segments = segs; m.limit_method = "ANGLE"; m.harden_normals = False
        m.angle_limit = math.radians(35)
    return ob


def box(name, size, loc, rot=(0, 0, 0), mat=None, bevel=0.03, segs=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = mesh_obj(name, bm, mat, bevel, segs, smooth=False)
    ob.location = loc; ob.rotation_euler = rot
    if bevel > 0:
        ob.data.shade_smooth_by_angle(angle=math.radians(35)) if hasattr(ob.data, "shade_smooth_by_angle") else None
    return ob


def cyl(name, r, h, loc, rot=(0, 0, 0), mat=None, verts=24, bevel=0.02, r2=None, cap=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, segments=verts, radius1=r, radius2=r if r2 is None else r2, depth=h)
    ob = mesh_obj(name, bm, mat, bevel, 2)
    ob.location = loc; ob.rotation_euler = rot
    return ob


def sphere(name, r, loc, mat=None, segs=16, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs * 2, v_segments=segs, radius=r)
    ob = mesh_obj(name, bm, mat)
    ob.location = loc; ob.scale = scale
    return ob


def torus(name, R, r, loc, rot=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=40, minor_segments=14, location=loc, rotation=rot)
    ob = C.active_object; ob.name = name
    if mat: ob.data.materials.append(mat)
    for p in ob.data.polygons: p.use_smooth = True
    return ob


def ground_skinned():
    """Skinned models only know their posed size after evaluation: drop each tagged root so its lowest
    posed vertex sits at its ground_z."""
    C.view_layer.update()
    dg = C.evaluated_depsgraph_get()
    def span(root):
        dg = C.evaluated_depsgraph_get()
        lo, hi = 1e9, -1e9
        for o in root.children_recursive:
            if o.type == "MESH" and not o.hide_render and o.parent and o.parent.type == "ARMATURE":
                ev = o.evaluated_get(dg); me = ev.to_mesh()
                for v in me.vertices:
                    z = (ev.matrix_world @ v.co).z; lo = min(lo, z); hi = max(hi, z)
                ev.to_mesh_clear()
        return lo, hi
    for root in [o for o in D.objects if "ground_z" in o]:
        lo, hi = span(root)
        if lo > 1e8: continue
        if "fit_h" in root and hi > lo:
            root.scale = root.scale * (root["fit_h"] / (hi - lo))
            C.view_layer.update()
            lo, hi = span(root)
        low = lo
        if low < 1e8:
            root.location.z += root["ground_z"] - low
            print("[look] grounded", root.name, round(low, 3), "->", round(root["ground_z"], 2))


def import_glb(rel, height=None, loc=(0, 0, 0), rot_z=0.0, name=None):
    """Import a game model, scale it so its height is `height`, sit it on the ground at loc."""
    before = set(D.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, rel))
    new = [o for o in D.objects if o not in before]
    root = D.objects.new(name or os.path.basename(rel), None)
    link(root)
    for o in new:
        if o.parent is None: o.parent = root
    C.view_layer.update()
    lo = Vector((1e9,) * 3); hi = -lo
    for o in new:
        if o.type == "MESH":
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    s = height / max(hi.z - lo.z, 1e-3) if height else 1.0
    ctr = (lo + hi) / 2
    for o in new:
        if o.parent is root:
            o.location -= Vector((ctr.x, ctr.y, lo.z))
    root.scale = (s, s, s)
    root.location = loc
    root.rotation_euler = (0, 0, rot_z)
    for o in new:
        if o.type == "MESH":
            for p in o.data.polygons: p.use_smooth = True
            for m in o.data.materials:
                if m: upgrade_meshy(m)
    return root, new


# ------------------------------------------------------------------------------------------------ materials
_mcache = {}


def nodes_of(m):
    m.use_nodes = True
    return m.node_tree.nodes, m.node_tree.links


def new_mat(name):
    m = D.materials.new(name)
    nt, ln = nodes_of(m)
    for n in list(nt): nt.remove(n)
    out = nt.new("ShaderNodeOutputMaterial")
    return m, nt, ln, out


def P(nt, **kw):
    b = nt.new("ShaderNodeBsdfPrincipled")
    for k, v in kw.items():
        key = {"base": "Base Color", "metal": "Metallic", "rough": "Roughness", "emit": "Emission Color",
               "estr": "Emission Strength", "coat": "Coat Weight", "coat_rough": "Coat Roughness",
               "trans": "Transmission Weight", "ior": "IOR", "alpha": "Alpha", "spec": "Specular IOR Level",
               "sss": "Subsurface Weight", "sheen": "Sheen Weight"}[k]
        b.inputs[key].default_value = v
    return b


def edge_mask(nt, ln, radius=0.04, power=6.0):
    """1 on worn edges, 0 on flat faces: compares a bevelled normal with the true normal."""
    bev = nt.new("ShaderNodeBevel"); bev.samples = 8; bev.inputs["Radius"].default_value = radius
    geo = nt.new("ShaderNodeNewGeometry")
    dot = nt.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
    ln.new(bev.outputs[0], dot.inputs[0]); ln.new(geo.outputs["Normal"], dot.inputs[1])
    inv = nt.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
    ln.new(dot.outputs["Value"], inv.inputs[1])
    mul = nt.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = power; mul.use_clamp = True
    ln.new(inv.outputs[0], mul.inputs[0])
    # break it up with noise so wear is chipped, not a clean line
    tc = nt.new("ShaderNodeTexCoord")
    nz = nt.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 14.0; nz.inputs["Detail"].default_value = 8.0
    ln.new(tc.outputs["Object"], nz.inputs["Vector"])
    mix = nt.new("ShaderNodeMath"); mix.operation = "MULTIPLY"
    ln.new(mul.outputs[0], mix.inputs[0]); ln.new(nz.outputs["Fac"], mix.inputs[1])
    ramp = nt.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.18; ramp.color_ramp.elements[1].position = 0.32
    ln.new(mix.outputs[0], ramp.inputs[0])
    return bev, ramp.outputs[0]


def paint_mat(name, color, rust=0.35, rough=0.42, metal_edges=True, coat=0.25, scale=3.0):
    """Layered painted metal: paint, chipped edges to bare steel, rust blooms and grime in crevices."""
    key = ("paint", name)
    if key in _mcache: return _mcache[key]
    m, nt, ln, out = new_mat(name)
    tc = nt.new("ShaderNodeTexCoord")
    # paint colour with a little hue noise
    nz = nt.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = scale; nz.inputs["Detail"].default_value = 6.0
    ln.new(tc.outputs["Object"], nz.inputs["Vector"])
    paint = nt.new("ShaderNodeMix"); paint.data_type = "RGBA"; paint.blend_type = "OVERLAY"; paint.inputs[0].default_value = 0.25
    paint.inputs[6].default_value = (*color, 1); ln.new(nz.outputs["Color"], paint.inputs[7])
    # rust blooms
    rn = nt.new("ShaderNodeTexNoise"); rn.inputs["Scale"].default_value = scale * 1.6; rn.inputs["Detail"].default_value = 12.0
    rn.inputs["Roughness"].default_value = 0.65
    ln.new(tc.outputs["Object"], rn.inputs["Vector"])
    rr = nt.new("ShaderNodeValToRGB")
    t = 0.62 - rust * 0.25
    rr.color_ramp.elements[0].position = t; rr.color_ramp.elements[1].position = t + 0.06
    ln.new(rn.outputs["Fac"], rr.inputs[0])
    rustc = nt.new("ShaderNodeValToRGB")
    rustc.color_ramp.elements[0].color = (0.16, 0.055, 0.02, 1); rustc.color_ramp.elements[1].color = (0.5, 0.2, 0.07, 1)
    rv = nt.new("ShaderNodeTexVoronoi"); rv.inputs["Scale"].default_value = scale * 9
    ln.new(tc.outputs["Object"], rv.inputs["Vector"]); ln.new(rv.outputs["Distance"], rustc.inputs[0])
    c1 = nt.new("ShaderNodeMix"); c1.data_type = "RGBA"
    ln.new(rr.outputs[0], c1.inputs[0]); ln.new(paint.outputs[2], c1.inputs[6]); ln.new(rustc.outputs[0], c1.inputs[7])
    # chipped edges -> bare steel
    bev, edge = edge_mask(nt, ln)
    c2 = nt.new("ShaderNodeMix"); c2.data_type = "RGBA"; c2.inputs[7].default_value = (0.55, 0.55, 0.56, 1)
    ln.new(edge, c2.inputs[0]); ln.new(c1.outputs[2], c2.inputs[6])
    # grime in crevices (AO)
    ao = nt.new("ShaderNodeAmbientOcclusion"); ao.samples = 8; ao.inputs["Distance"].default_value = 0.35
    g = nt.new("ShaderNodeMix"); g.data_type = "RGBA"; g.blend_type = "MULTIPLY"; g.inputs[0].default_value = 0.85
    ln.new(c2.outputs[2], g.inputs[6])
    aor = nt.new("ShaderNodeValToRGB"); aor.color_ramp.elements[0].color = (0.25, 0.2, 0.16, 1)
    ln.new(ao.outputs["AO"], aor.inputs[0]); ln.new(aor.outputs[0], g.inputs[7])
    b = P(nt, rough=rough, coat=coat, coat_rough=0.3)
    ln.new(g.outputs[2], b.inputs["Base Color"])
    # roughness: paint smooth, rust rough, edges polished
    rm = nt.new("ShaderNodeMix"); rm.data_type = "FLOAT"; rm.inputs[2].default_value = rough; rm.inputs[3].default_value = 0.85
    ln.new(rr.outputs[0], rm.inputs[0])
    rm2 = nt.new("ShaderNodeMix"); rm2.data_type = "FLOAT"; rm2.inputs[3].default_value = 0.28
    ln.new(edge, rm2.inputs[0]); ln.new(rm.outputs[0], rm2.inputs[2])
    ln.new(rm2.outputs[0], b.inputs["Roughness"])
    if metal_edges: ln.new(edge, b.inputs["Metallic"])
    # bump: rust is pitted, edges rounded by the bevel normal
    bump = nt.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25; bump.inputs["Distance"].default_value = 0.01
    hm = nt.new("ShaderNodeMath"); hm.operation = "MULTIPLY"
    ln.new(rv.outputs["Distance"], hm.inputs[0]); ln.new(rr.outputs[0], hm.inputs[1])
    ln.new(hm.outputs[0], bump.inputs["Height"]); ln.new(bev.outputs[0], bump.inputs["Normal"])
    ln.new(bump.outputs[0], b.inputs["Normal"])
    ln.new(ao.outputs["Color"], ao.inputs["Color"]) if False else None
    ln.new(b.outputs[0], out.inputs[0])
    _mcache[key] = m
    return m


def simple_mat(name, color, rough=0.5, metal=0.0, emit=None, estr=0.0, coat=0.0, trans=0.0):
    key = ("simple", name)
    if key in _mcache: return _mcache[key]
    m, nt, ln, out = new_mat(name)
    b = P(nt, base=(*color, 1), rough=rough, metal=metal, coat=coat, trans=trans)
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1); b.inputs["Emission Strength"].default_value = estr
    bev = nt.new("ShaderNodeBevel"); bev.inputs["Radius"].default_value = 0.02
    ln.new(bev.outputs[0], b.inputs["Normal"])
    ln.new(b.outputs[0], out.inputs[0])
    _mcache[key] = m
    return m


def emit_mat(name, color, strength):
    key = ("emit", name)
    if key in _mcache: return _mcache[key]
    m, nt, ln, out = new_mat(name)
    e = nt.new("ShaderNodeEmission"); e.inputs[0].default_value = (*color, 1); e.inputs[1].default_value = strength
    ln.new(e.outputs[0], out.inputs[0])
    _mcache[key] = m
    return m


def bulb_mat():
    key = ("bulb",)
    if key in _mcache: return _mcache[key]
    m, nt, ln, out = new_mat("bulb")
    glass = P(nt, base=(1, 0.85, 0.6, 1), rough=0.05, trans=1.0, ior=1.45)
    e = nt.new("ShaderNodeEmission"); e.inputs[0].default_value = (1.0, 0.62, 0.28, 1); e.inputs[1].default_value = 40
    mix = nt.new("ShaderNodeAddShader")
    ln.new(glass.outputs[0], mix.inputs[0]); ln.new(e.outputs[0], mix.inputs[1]); ln.new(mix.outputs[0], out.inputs[0])
    _mcache[key] = m
    return m


def upgrade_meshy(m):
    """The Meshy models come with baked colour/normal textures. Give them a clearcoat sheen, roughness
    variation, cavity grime and a bevel normal so their hard edges catch light."""
    if m.get("_up"): return
    m["_up"] = 1
    nt, ln = nodes_of(m)
    b = next((n for n in nt if n.type == "BSDF_PRINCIPLED"), None)
    if not b: return
    b.inputs["Coat Weight"].default_value = 0.15
    b.inputs["Coat Roughness"].default_value = 0.35
    b.inputs["Specular IOR Level"].default_value = 0.5
    # cavity grime on the base colour
    src = b.inputs["Base Color"].links[0].from_socket if b.inputs["Base Color"].is_linked else None
    if src is not None:
        ao = nt.new("ShaderNodeAmbientOcclusion"); ao.samples = 8; ao.inputs["Distance"].default_value = 0.25
        aor = nt.new("ShaderNodeValToRGB"); aor.color_ramp.elements[0].color = (0.35, 0.3, 0.26, 1)
        ln.new(ao.outputs["AO"], aor.inputs[0])
        mm = nt.new("ShaderNodeMix"); mm.data_type = "RGBA"; mm.blend_type = "MULTIPLY"; mm.inputs[0].default_value = 0.8
        ln.new(src, mm.inputs[6]); ln.new(aor.outputs[0], mm.inputs[7])
        hsv = nt.new("ShaderNodeHueSaturation"); hsv.inputs["Saturation"].default_value = 1.12; hsv.inputs["Value"].default_value = 1.0
        ln.new(mm.outputs[2], hsv.inputs["Color"])
        ln.new(hsv.outputs[0], b.inputs["Base Color"])
    if not b.inputs["Roughness"].is_linked:
        tc = nt.new("ShaderNodeTexCoord")
        nz = nt.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 6
        ln.new(tc.outputs["Object"], nz.inputs["Vector"])
        mr = nt.new("ShaderNodeMapRange"); mr.inputs[3].default_value = 0.35; mr.inputs[4].default_value = 0.75
        ln.new(nz.outputs["Fac"], mr.inputs[0]); ln.new(mr.outputs[0], b.inputs["Roughness"])


# volumes -------------------------------------------------------------------------------------------
def smoke_mat(name, color=(0.06, 0.055, 0.05), density=1.2, scale=0.35, emit_base=0.0, fire_tint=(1.0, 0.35, 0.08), dims=(1, 1, 1)):
    """A billowing plume in a unit cube (object space -1..1): dense noise, fades at the top and sides,
    with an optional ember glow in the bottom that lights the smoke from inside."""
    m, nt, ln, out = new_mat(name)
    tc = nt.new("ShaderNodeTexCoord")
    nc = nt.new("ShaderNodeVectorMath"); nc.operation = "MULTIPLY"; nc.inputs[1].default_value = dims; ln.new(tc.outputs["Object"], nc.inputs[0])
    sep = nt.new("ShaderNodeSeparateXYZ"); ln.new(tc.outputs["Object"], sep.inputs[0])
    # widen as it rises: radial falloff with radius growing with z
    rz = nt.new("ShaderNodeMapRange"); rz.inputs[1].default_value = -1; rz.inputs[2].default_value = 1
    rz.inputs[3].default_value = 0.35; rz.inputs[4].default_value = 1.0
    ln.new(sep.outputs[2], rz.inputs[0])
    # warp coordinates for billows
    wn = nt.new("ShaderNodeTexNoise"); wn.inputs["Scale"].default_value = scale * 0.7; wn.inputs["Detail"].default_value = 3
    ln.new(nc.outputs[0], wn.inputs["Vector"])
    wv = nt.new("ShaderNodeVectorMath"); wv.operation = "MULTIPLY_ADD"
    wv.inputs[1].default_value = (1.6, 1.6, 2.2); ln.new(wn.outputs["Color"], wv.inputs[0]); ln.new(nc.outputs[0], wv.inputs[2])
    xy = nt.new("ShaderNodeCombineXYZ"); ln.new(sep.outputs[0], xy.inputs[0]); ln.new(sep.outputs[1], xy.inputs[1])
    ln_len = nt.new("ShaderNodeVectorMath"); ln_len.operation = "LENGTH"; ln.new(xy.outputs[0], ln_len.inputs[0])
    rad = nt.new("ShaderNodeMath"); rad.operation = "DIVIDE"; ln.new(ln_len.outputs["Value"], rad.inputs[0]); ln.new(rz.outputs[0], rad.inputs[1])
    fall = nt.new("ShaderNodeMapRange"); fall.inputs[1].default_value = 0.55; fall.inputs[2].default_value = 1.0
    fall.inputs[3].default_value = 1.0; fall.inputs[4].default_value = 0.0
    ln.new(rad.outputs[0], fall.inputs[0])
    topf = nt.new("ShaderNodeMapRange"); topf.inputs[1].default_value = 0.45; topf.inputs[2].default_value = 1.0
    topf.inputs[3].default_value = 1.0; topf.inputs[4].default_value = 0.0
    ln.new(sep.outputs[2], topf.inputs[0])
    botf = nt.new("ShaderNodeMapRange"); botf.inputs[1].default_value = -1.0; botf.inputs[2].default_value = -0.85
    ln.new(sep.outputs[2], botf.inputs[0])
    n = nt.new("ShaderNodeTexNoise"); n.inputs["Scale"].default_value = scale; n.inputs["Detail"].default_value = 10
    n.inputs["Roughness"].default_value = 0.6; n.inputs["Distortion"].default_value = 0.3
    ln.new(wv.outputs[0], n.inputs["Vector"])
    nd = nt.new("ShaderNodeMapRange"); nd.inputs[1].default_value = 0.42; nd.inputs[2].default_value = 0.75
    ln.new(n.outputs["Fac"], nd.inputs[0])
    d = nd.outputs[0]
    for f in (fall, topf, botf):
        mm = nt.new("ShaderNodeMath"); mm.operation = "MULTIPLY"; ln.new(d, mm.inputs[0]); ln.new(f.outputs[0], mm.inputs[1]); d = mm.outputs[0]
    dm = nt.new("ShaderNodeMath"); dm.operation = "MULTIPLY"; dm.inputs[1].default_value = density; ln.new(d, dm.inputs[0])
    v = nt.new(VOLP)
    v.inputs["Color"].default_value = (*color, 1); v.inputs["Anisotropy"].default_value = 0.3
    ln.new(dm.outputs[0], v.inputs["Density"])
    if emit_base > 0:
        eb = nt.new("ShaderNodeMapRange"); eb.inputs[1].default_value = -0.4; eb.inputs[2].default_value = -1.0
        ln.new(sep.outputs[2], eb.inputs[0])
        ee = nt.new("ShaderNodeMath"); ee.operation = "MULTIPLY"; ee.inputs[1].default_value = emit_base
        e2 = nt.new("ShaderNodeMath"); e2.operation = "MULTIPLY"
        ln.new(eb.outputs[0], e2.inputs[0]); ln.new(d, e2.inputs[1]); ln.new(e2.outputs[0], ee.inputs[0])
        v.inputs["Emission Color"].default_value = (*fire_tint, 1)
        ln.new(ee.outputs[0], v.inputs["Emission Strength"])
    ln.new(v.outputs[0], out.inputs["Volume"])
    return m


def fire_mat(name, strength=28.0, scale=2.4, dims=(1, 1, 1)):
    """Flames in a unit cube: a tapering tongue of noise, hottest at the base, blackbody coloured."""
    m, nt, ln, out = new_mat(name)
    tc = nt.new("ShaderNodeTexCoord")
    nc = nt.new("ShaderNodeVectorMath"); nc.operation = "MULTIPLY"; nc.inputs[1].default_value = dims; ln.new(tc.outputs["Object"], nc.inputs[0])
    sep = nt.new("ShaderNodeSeparateXYZ"); ln.new(tc.outputs["Object"], sep.inputs[0])
    h = nt.new("ShaderNodeMapRange"); h.inputs[1].default_value = -1; h.inputs[2].default_value = 1
    ln.new(sep.outputs[2], h.inputs[0])  # 0 bottom .. 1 top
    wn = nt.new("ShaderNodeTexNoise"); wn.inputs["Scale"].default_value = scale * 0.8; wn.inputs["Detail"].default_value = 2
    ln.new(nc.outputs[0], wn.inputs["Vector"])
    wv = nt.new("ShaderNodeVectorMath"); wv.operation = "MULTIPLY_ADD"; wv.inputs[1].default_value = (0.9, 0.9, 0.7)
    ln.new(wn.outputs["Color"], wv.inputs[0]); ln.new(nc.outputs[0], wv.inputs[2])
    stretch = nt.new("ShaderNodeVectorMath"); stretch.operation = "MULTIPLY"; stretch.inputs[1].default_value = (1, 1, 0.5)
    ln.new(wv.outputs[0], stretch.inputs[0])
    n = nt.new("ShaderNodeTexNoise"); n.inputs["Scale"].default_value = scale; n.inputs["Detail"].default_value = 8
    ln.new(stretch.outputs[0], n.inputs["Vector"])
    xy = nt.new("ShaderNodeCombineXYZ"); ln.new(sep.outputs[0], xy.inputs[0]); ln.new(sep.outputs[1], xy.inputs[1])
    rl = nt.new("ShaderNodeVectorMath"); rl.operation = "LENGTH"; ln.new(xy.outputs[0], rl.inputs[0])
    # allowed radius shrinks with height (tongue shape)
    ar = nt.new("ShaderNodeMapRange"); ar.inputs[3].default_value = 0.95; ar.inputs[4].default_value = 0.05
    ln.new(h.outputs[0], ar.inputs[0])
    rr = nt.new("ShaderNodeMath"); rr.operation = "DIVIDE"; ln.new(rl.outputs["Value"], rr.inputs[0]); ln.new(ar.outputs[0], rr.inputs[1])
    sh = nt.new("ShaderNodeMapRange"); sh.inputs[1].default_value = 0.4; sh.inputs[2].default_value = 1.0
    sh.inputs[3].default_value = 1.0; sh.inputs[4].default_value = 0.0
    ln.new(rr.outputs[0], sh.inputs[0])
    nn = nt.new("ShaderNodeMath"); nn.operation = "MULTIPLY"; ln.new(n.outputs["Fac"], nn.inputs[0]); ln.new(sh.outputs[0], nn.inputs[1])
    dd = nt.new("ShaderNodeMapRange"); dd.inputs[1].default_value = 0.46; dd.inputs[2].default_value = 0.68
    ln.new(nn.outputs[0], dd.inputs[0])
    temp = nt.new("ShaderNodeMapRange"); temp.inputs[3].default_value = 2600; temp.inputs[4].default_value = 1100
    ln.new(h.outputs[0], temp.inputs[0])
    bb = nt.new("ShaderNodeBlackbody"); ln.new(temp.outputs[0], bb.inputs[0])
    es = nt.new("ShaderNodeMath"); es.operation = "MULTIPLY"; es.inputs[1].default_value = strength
    ln.new(dd.outputs[0], es.inputs[0])
    v = nt.new(VOLP); v.inputs["Density"].default_value = 0.0
    ln.new(bb.outputs[0], v.inputs["Emission Color"]); ln.new(es.outputs[0], v.inputs["Emission Strength"])
    dm = nt.new("ShaderNodeMath"); dm.operation = "MULTIPLY"; dm.inputs[1].default_value = 0.6
    ln.new(dd.outputs[0], dm.inputs[0]); ln.new(dm.outputs[0], v.inputs["Density"])
    v.inputs["Color"].default_value = (0.05, 0.03, 0.02, 1)
    ln.new(v.outputs[0], out.inputs["Volume"])
    return m


def vol_cube(name, mat, loc, size, rot_z=0.0):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=2.0)
    ob = mesh_obj(name, bm, mat, smooth=False)
    ob.location = loc; ob.scale = size; ob.rotation_euler = (0, 0, rot_z)
    ob.visible_shadow = True
    return ob


def point(name, loc, color, power, radius=0.3):
    l = D.lights.new(name, "POINT"); l.color = color; l.energy = power; l.shadow_soft_size = radius
    ob = D.objects.new(name, l); ob.location = loc; link(ob)
    return ob


def area(name, loc, rot, color, power, size=2.0):
    l = D.lights.new(name, "AREA"); l.color = color; l.energy = power; l.size = size
    ob = D.objects.new(name, l); ob.location = loc; ob.rotation_euler = rot; link(ob)
    return ob


def fire(loc, w=1.2, h=2.2, smoke_h=14.0, smoke_w=None, power=4500, lean=(0.0, 0.0)):
    fm = fire_mat("fire_%d" % len(D.materials), strength=30, dims=(w, w, h))
    vol_cube("fire", fm, Vector(loc) + Vector((0, 0, h * 0.9)), (w, w, h))
    sw = smoke_w or w * 3.2
    sm = smoke_mat("smoke_%d" % len(D.materials), density=0.9, emit_base=0.8, dims=(sw, sw, smoke_h))
    ob = vol_cube("smoke", sm, Vector(loc) + Vector((lean[0] * smoke_h * 0.5, lean[1] * smoke_h * 0.5, h + smoke_h * 0.92)), (sw, sw, smoke_h))
    ob.rotation_euler = (lean[1] * -0.6, lean[0] * 0.6, rng.random() * 6)
    point("fire_light", Vector(loc) + Vector((0, 0, h * 0.7)), (1.0, 0.45, 0.14), power, 0.8)
    # embers drifting up
    em = emit_mat("ember", (1.0, 0.45, 0.1), 60)
    for i in range(int(18 * w)):
        p = Vector(loc) + Vector((rng.uniform(-w, w) * 1.5, rng.uniform(-w, w) * 1.5, rng.uniform(h * 0.6, h * 4.0)))
        s = sphere("ember", rng.uniform(0.012, 0.03), p, em, segs=4)
        s.visible_shadow = False


# ------------------------------------------------------------------------------------------------ world
def world(sun_elev=9.0, sun_rot=-28.0, strength=0.9, haze=0.012):
    sc = C.scene
    w = D.worlds.new("sky"); sc.world = w
    nt, ln = nodes_of(w)
    for n in list(nt): nt.remove(n)
    out = nt.new("ShaderNodeOutputWorld")
    sky = nt.new("ShaderNodeTexSky")
    try:
        sky.sky_type = "NISHITA"
    except Exception:
        pass
    try:
        sky.sun_elevation = math.radians(sun_elev); sky.sun_rotation = math.radians(sun_rot)
        sky.sun_disc = False
        sky.altitude = 1200; sky.air_density = 1.4; sky.ozone_density = 1.2
        sky.aerosol_density = 3.0
    except Exception:
        pass
    bg = nt.new("ShaderNodeBackground"); bg.inputs[1].default_value = strength
    # warm the sky a touch toward the fires
    hsv = nt.new("ShaderNodeHueSaturation"); hsv.inputs["Saturation"].default_value = 1.15
    ln.new(sky.outputs[0], hsv.inputs["Color"]); ln.new(hsv.outputs[0], bg.inputs[0])
    ln.new(bg.outputs[0], out.inputs["Surface"])
    if haze > 0:
        # aerial haze in a big box (a world volume would swallow the sky)
        hm, hnt, hln, hout = new_mat("haze")
        pv = hnt.new(VOLP)
        pv.inputs["Density"].default_value = haze
        pv.inputs["Color"].default_value = (0.95, 0.8, 0.66, 1)
        pv.inputs["Anisotropy"].default_value = 0.6
        hln.new(pv.outputs[0], hout.inputs["Volume"])
        hb = vol_cube("haze", hm, (0, 60, 60), (260, 260, 62))
        hb.visible_shadow = False
    # sun
    l = D.lights.new("sun", "SUN"); l.energy = 6.0; l.angle = math.radians(1.2)
    l.color = (1.0, 0.6, 0.34)
    ob = D.objects.new("sun", l); link(ob)
    # sun_rot: azimuth of the sun measured from +Y (straight ahead of the cameras) toward +X
    az = math.radians(sun_rot); el = math.radians(sun_elev)
    to_sun = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
    ob.rotation_euler = (-to_sun).to_track_quat("-Z", "Y").to_euler()
    try:
        sky.sun_rotation = math.atan2(to_sun.y, to_sun.x) + math.pi / 2
    except Exception:
        pass
    return ob


def ground(size=220, center=(0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=200, y_segments=200, size=size / 2)
    ob = mesh_obj("ground", bm, smooth=True)
    ob.location = (center[0], center[1], 0)
    # gentle lumps so the yard isn't a table top
    tex = D.textures.new("lumps", "CLOUDS"); tex.noise_scale = 9.0
    dm = ob.modifiers.new("lumps", "DISPLACE"); dm.texture = tex; dm.strength = 0.35; dm.mid_level = 0.5
    m, nt, ln, out = new_mat("yard_ground")
    tc = nt.new("ShaderNodeTexCoord")
    # dirt: two browns plus darker damp patches
    n1 = nt.new("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = 0.35; n1.inputs["Detail"].default_value = 12
    ln.new(tc.outputs["Object"], n1.inputs["Vector"])
    dr = nt.new("ShaderNodeValToRGB")
    dr.color_ramp.elements[0].color = (0.09, 0.05, 0.03, 1); dr.color_ramp.elements[1].color = (0.32, 0.2, 0.11, 1)
    dr.color_ramp.elements[0].position = 0.35; dr.color_ramp.elements[1].position = 0.65
    ln.new(n1.outputs["Fac"], dr.inputs[0])
    # gravel speckle
    v1 = nt.new("ShaderNodeTexVoronoi"); v1.inputs["Scale"].default_value = 60
    ln.new(tc.outputs["Object"], v1.inputs["Vector"])
    gs = nt.new("ShaderNodeMix"); gs.data_type = "RGBA"; gs.blend_type = "MULTIPLY"; gs.inputs[0].default_value = 0.35
    ln.new(dr.outputs[0], gs.inputs[6]); ln.new(v1.outputs["Color"], gs.inputs[7])
    # scrap floor plates: voronoi cells with F1 distance -> a few cells become steel plates
    sc_m = nt.new("ShaderNodeMapping"); sc_m.inputs["Scale"].default_value = (0.18, 0.18, 0.18)
    ln.new(tc.outputs["Object"], sc_m.inputs["Vector"])
    vp = nt.new("ShaderNodeTexVoronoi"); vp.voronoi_dimensions = "2D"; vp.feature = "F1"; vp.distance = "CHEBYCHEV"
    vp.inputs["Scale"].default_value = 1.0; vp.inputs["Randomness"].default_value = 0.6
    ln.new(sc_m.outputs[0], vp.inputs["Vector"])
    sepc = nt.new("ShaderNodeSeparateColor"); ln.new(vp.outputs["Color"], sepc.inputs[0])
    pick = nt.new("ShaderNodeMath"); pick.operation = "GREATER_THAN"; pick.inputs[1].default_value = 0.72
    ln.new(sepc.outputs[0], pick.inputs[0])
    inner = nt.new("ShaderNodeMath"); inner.operation = "LESS_THAN"; inner.inputs[1].default_value = 0.42
    ln.new(vp.outputs["Distance"], inner.inputs[0])
    plate = nt.new("ShaderNodeMath"); plate.operation = "MULTIPLY"; ln.new(pick.outputs[0], plate.inputs[0]); ln.new(inner.outputs[0], plate.inputs[1])
    pc = nt.new("ShaderNodeValToRGB")
    pc.color_ramp.elements[0].color = (0.22, 0.2, 0.19, 1); pc.color_ramp.elements[1].color = (0.42, 0.2, 0.09, 1)
    pn = nt.new("ShaderNodeTexNoise"); pn.inputs["Scale"].default_value = 3; pn.inputs["Detail"].default_value = 10
    ln.new(tc.outputs["Object"], pn.inputs["Vector"]); ln.new(pn.outputs["Fac"], pc.inputs[0])
    col = nt.new("ShaderNodeMix"); col.data_type = "RGBA"
    ln.new(plate.outputs[0], col.inputs[0]); ln.new(gs.outputs[2], col.inputs[6]); ln.new(pc.outputs[0], col.inputs[7])
    # oil puddles: glossy and dark
    on = nt.new("ShaderNodeTexNoise"); on.inputs["Scale"].default_value = 0.5; on.inputs["Detail"].default_value = 4
    ln.new(tc.outputs["Object"], on.inputs["Vector"])
    oil = nt.new("ShaderNodeMapRange"); oil.inputs[1].default_value = 0.63; oil.inputs[2].default_value = 0.66
    ln.new(on.outputs["Fac"], oil.inputs[0])
    col2 = nt.new("ShaderNodeMix"); col2.data_type = "RGBA"; col2.inputs[7].default_value = (0.02, 0.018, 0.016, 1)
    ln.new(oil.outputs[0], col2.inputs[0]); ln.new(col.outputs[2], col2.inputs[6])
    b = P(nt)
    ln.new(col2.outputs[2], b.inputs["Base Color"])
    rough = nt.new("ShaderNodeMix"); rough.data_type = "FLOAT"; rough.inputs[2].default_value = 0.92; rough.inputs[3].default_value = 0.06
    ln.new(oil.outputs[0], rough.inputs[0])
    r2 = nt.new("ShaderNodeMix"); r2.data_type = "FLOAT"; r2.inputs[3].default_value = 0.45
    ln.new(plate.outputs[0], r2.inputs[0]); ln.new(rough.outputs[0], r2.inputs[2])
    ln.new(r2.outputs[0], b.inputs["Roughness"])
    ln.new(plate.outputs[0], b.inputs["Metallic"])
    bump = nt.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.6; bump.inputs["Distance"].default_value = 0.03
    hh = nt.new("ShaderNodeMath"); hh.operation = "ADD"
    ln.new(v1.outputs["Distance"], hh.inputs[0]); ln.new(plate.outputs[0], hh.inputs[1])
    hz = nt.new("ShaderNodeMath"); hz.operation = "MULTIPLY"; ln.new(hh.outputs[0], hz.inputs[0]); hz.inputs[1].default_value = 1.0
    nooil = nt.new("ShaderNodeMath"); nooil.operation = "SUBTRACT"; nooil.inputs[0].default_value = 1.0
    ln.new(oil.outputs[0], nooil.inputs[1]); ln.new(nooil.outputs[0], hz.inputs[1])
    ln.new(hz.outputs[0], bump.inputs["Height"]); ln.new(bump.outputs[0], b.inputs["Normal"])
    ln.new(b.outputs[0], out.inputs[0])
    ob.data.materials.append(m)
    return ob


# ------------------------------------------------------------------------------------------------ scrap kit
PALETTE = [(0.62, 0.3, 0.14), (0.86, 0.42, 0.12), (0.16, 0.5, 0.52), (0.86, 0.8, 0.64), (0.3, 0.32, 0.36),
           (0.72, 0.16, 0.1), (0.92, 0.66, 0.12), (0.26, 0.4, 0.62)]
PNAMES = ["rust", "orange", "teal", "cream", "gun", "red", "yellow", "blue"]


def pmat(i=None):
    i = rng.randrange(len(PALETTE)) if i is None else i
    return paint_mat("paint_" + PNAMES[i], PALETTE[i], rust=0.25 + 0.5 * (PNAMES[i] == "rust"))


def rubber():
    return simple_mat("rubber", (0.025, 0.025, 0.028), rough=0.75)


def steel():
    return paint_mat("steel", (0.36, 0.37, 0.4), rust=0.2, rough=0.32)


def scrap_piece(loc, s=1.0, kind=None):
    kind = kind or rng.choice(["plate", "plate", "box", "drum", "tire", "pipe", "gear", "beam", "panel"])
    rot = (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0, 6.28))
    if kind == "plate":
        return box("plate", (rng.uniform(0.8, 2.0) * s, rng.uniform(0.6, 1.4) * s, 0.06 * s), loc, rot, pmat(), 0.015)
    if kind == "panel":
        o = box("panel", (rng.uniform(1.0, 1.8) * s, 0.08 * s, rng.uniform(0.8, 1.3) * s), loc, rot, pmat(), 0.02)
        return o
    if kind == "box":
        return box("box", tuple(rng.uniform(0.4, 1.1) * s for _ in range(3)), loc, rot, pmat(), 0.04)
    if kind == "drum":
        o = cyl("drum", 0.32 * s, 0.9 * s, loc, rot, pmat(), 28, 0.02)
        for z in (-0.25, 0.25):
            torus("hoop", 0.33 * s, 0.018 * s, Vector(loc), rot, steel()).matrix_parent_inverse = Matrix()
        return o
    if kind == "tire":
        return torus("tire", 0.42 * s, 0.15 * s, loc, rot, rubber())
    if kind == "pipe":
        return cyl("pipe", 0.12 * s, rng.uniform(1.5, 3.0) * s, loc, (rng.uniform(1.2, 1.9), rot[1], rot[2]), pmat(), 16, 0.01)
    if kind == "gear":
        return gear(loc, 0.45 * s, rot)
    if kind == "beam":
        return ibeam(loc, rng.uniform(1.8, 3.5) * s, rot, 0.16 * s)


def gear(loc, r, rot, teeth=12, mat=None):
    bm = bmesh.new()
    pts = []
    for i in range(teeth * 4):
        a = i / (teeth * 4) * math.tau
        rr = r * (1.0 if (i % 4) in (1, 2) else 0.82)
        pts.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, 0)))
    f = bm.faces.new(pts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    vs = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, r * 0.25), verts=vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = mesh_obj("gear", bm, mat or paint_mat("paint_yellow", PALETTE[6]), 0.01, 2, smooth=False)
    ob.location = loc; ob.rotation_euler = rot
    return ob


def ibeam(loc, length, rot, h=0.2, mat=None):
    bm = bmesh.new()
    t = h * 0.12
    for (sx, sy, sz, oz) in ((h, length, t, h / 2 - t / 2), (h, length, t, -h / 2 + t / 2), (t, length, h, 0)):
        r = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=r["verts"])
        bmesh.ops.translate(bm, vec=(0, 0, oz), verts=r["verts"])
    ob = mesh_obj("ibeam", bm, mat or pmat(0), 0.008, 1, smooth=False)
    ob.location = loc; ob.rotation_euler = rot
    return ob


def pile(center, radius, height, n):
    c = Vector(center)
    for i in range(n):
        a = rng.uniform(0, math.tau); d = math.sqrt(rng.random()) * radius
        z = (1 - d / radius) * height * rng.uniform(0.6, 1.0)
        scrap_piece(c + Vector((math.cos(a) * d, math.sin(a) * d, z)), rng.uniform(0.6, 1.2))
    # a core mound so it reads as a heap, not floating bits
    m = paint_mat("pile_core", (0.2, 0.13, 0.08), rust=0.9, rough=0.9)
    s = sphere("pile_core", 1.0, c, m, 12, (radius * 0.95, radius * 0.95, height * 0.75))
    tex = D.textures.new("pile_tex", "VORONOI"); tex.noise_scale = 0.4
    dm = s.modifiers.new("lumps", "DISPLACE"); dm.texture = tex; dm.strength = 0.5


def scrap_tower(base, h, w=2.2, lean=0.05):
    """A tall wobbly column of compressed scrap: stacked bales, drums, car shells, crowned by junk."""
    z = 0.0
    p = Vector(base)
    lx, ly = rng.uniform(-lean, lean), rng.uniform(-lean, lean)
    while z < h:
        k = rng.random()
        off = Vector((lx * z, ly * z, 0))
        if k < 0.45:
            bh = rng.uniform(0.9, 1.4)
            bale(p + off + Vector((0, 0, z + bh / 2)), (w * rng.uniform(0.85, 1.1), w * rng.uniform(0.85, 1.1), bh), rng.uniform(-0.15, 0.15))
            z += bh
        elif k < 0.7:
            for j in range(rng.randint(2, 3)):
                q = p + off + Vector((rng.uniform(-w / 3, w / 3), rng.uniform(-w / 3, w / 3), z + 0.45))
                cyl("drum", 0.33, 0.92, q, (0, 0, rng.uniform(0, 6)), pmat(), 28, 0.02)
            z += 0.92
        else:
            bh = rng.uniform(0.5, 0.9)
            box("slab", (w * 1.25, w * rng.uniform(0.9, 1.2), bh), p + off + Vector((0, 0, z + bh / 2)),
                (rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06), rng.uniform(0, 3)), pmat(), 0.05)
            z += bh
    for i in range(rng.randint(4, 7)):
        scrap_piece(p + Vector((lx * z, ly * z, z)) + Vector((rng.uniform(-w / 2, w / 2), rng.uniform(-w / 2, w / 2), rng.uniform(0, 0.6))), rng.uniform(0.6, 1.0))


_bale_mats = []


def bale_mat(tint):
    """Crushed-scrap bale: a crumpled patchwork of painted sheet metal with strapping."""
    m, nt, ln, out = new_mat("bale_%d" % len(_bale_mats))
    _bale_mats.append(m)
    tc = nt.new("ShaderNodeTexCoord")
    v = nt.new("ShaderNodeTexVoronoi"); v.inputs["Scale"].default_value = 2.8; v.inputs["Randomness"].default_value = 1.0
    wn = nt.new("ShaderNodeTexNoise"); wn.inputs["Scale"].default_value = 2.0; wn.inputs["Detail"].default_value = 4
    ln.new(tc.outputs["Object"], wn.inputs["Vector"])
    lay = nt.new("ShaderNodeVectorMath"); lay.operation = "MULTIPLY"; lay.inputs[1].default_value = (0.7, 0.7, 2.6)
    ln.new(tc.outputs["Object"], lay.inputs[0])
    wv = nt.new("ShaderNodeVectorMath"); wv.operation = "MULTIPLY_ADD"; wv.inputs[1].default_value = (0.4, 0.4, 0.25)
    ln.new(wn.outputs["Color"], wv.inputs[0]); ln.new(lay.outputs[0], wv.inputs[2])
    ln.new(wv.outputs[0], v.inputs["Vector"])
    # each cell picks a paint from a ramp
    cr = nt.new("ShaderNodeValToRGB"); cr.color_ramp.interpolation = "CONSTANT"
    cols = [tint, (0.4, 0.17, 0.07), (0.2, 0.28, 0.28), (0.6, 0.55, 0.46), (0.25, 0.25, 0.28), (0.36, 0.3, 0.22), tint, (0.3, 0.3, 0.32)]
    els = cr.color_ramp.elements
    while len(els) < len(cols): els.new(0.5)
    for i, c in enumerate(cols):
        els[i].position = i / len(cols); els[i].color = (*c, 1)
    sepc = nt.new("ShaderNodeSeparateColor"); ln.new(v.outputs["Color"], sepc.inputs[0]); ln.new(sepc.outputs[0], cr.inputs[0])
    # crease lines between crumpled sheets
    v2 = nt.new("ShaderNodeTexVoronoi"); v2.feature = "DISTANCE_TO_EDGE"; v2.inputs["Scale"].default_value = 2.8; v2.inputs["Randomness"].default_value = 1.0
    ln.new(wv.outputs[0], v2.inputs["Vector"])
    crease = nt.new("ShaderNodeMapRange"); crease.inputs[1].default_value = 0.0; crease.inputs[2].default_value = 0.1
    ln.new(v2.outputs["Distance"], crease.inputs[0])
    dark = nt.new("ShaderNodeMix"); dark.data_type = "RGBA"; dark.blend_type = "MULTIPLY"
    ln.new(crease.outputs[0], dark.inputs[0]) if False else None
    inv = nt.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0; ln.new(crease.outputs[0], inv.inputs[1])
    ln.new(inv.outputs[0], dark.inputs[0]); ln.new(cr.outputs[0], dark.inputs[6]); dark.inputs[7].default_value = (0.05, 0.03, 0.02, 1)
    # rust over everything
    rn = nt.new("ShaderNodeTexNoise"); rn.inputs["Scale"].default_value = 5; rn.inputs["Detail"].default_value = 12
    ln.new(tc.outputs["Object"], rn.inputs["Vector"])
    rr = nt.new("ShaderNodeMapRange"); rr.inputs[1].default_value = 0.55; rr.inputs[2].default_value = 0.68
    ln.new(rn.outputs["Fac"], rr.inputs[0])
    rc = nt.new("ShaderNodeMix"); rc.data_type = "RGBA"; rc.inputs[7].default_value = (0.3, 0.11, 0.04, 1)
    ln.new(rr.outputs[0], rc.inputs[0]); ln.new(dark.outputs[2], rc.inputs[6])
    b = P(nt, rough=0.5, metal=0.6)
    ln.new(rc.outputs[2], b.inputs["Base Color"])
    rough = nt.new("ShaderNodeMapRange"); rough.inputs[3].default_value = 0.35; rough.inputs[4].default_value = 0.9
    ln.new(rr.outputs[0], rough.inputs[0]); ln.new(rough.outputs[0], b.inputs["Roughness"])
    bump = nt.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 1.0; bump.inputs["Distance"].default_value = 0.12
    ln.new(v2.outputs["Distance"], bump.inputs["Height"])
    bev = nt.new("ShaderNodeBevel"); bev.inputs["Radius"].default_value = 0.05
    ln.new(bev.outputs[0], bump.inputs["Normal"])
    ln.new(bump.outputs[0], b.inputs["Normal"])
    ln.new(b.outputs[0], out.inputs[0])
    return m


BALE_TINTS = [(0.62, 0.42, 0.3), (0.5, 0.55, 0.6), (0.72, 0.6, 0.38), (0.45, 0.5, 0.42)]


def bale(loc, size, rz=0.0):
    if len(_bale_mats) < 6:
        m = bale_mat(rng.choice(BALE_TINTS))
    else:
        m = rng.choice(_bale_mats)
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=6, use_grid_fill=True)
    for v in bm.verts:  # crumple
        v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.035
    ob = mesh_obj("bale", bm, m, 0.0, smooth=False)
    ob.location = loc; ob.rotation_euler = (rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02), rz)
    # steel straps
    st = steel()
    for f in (-0.28, 0.28):
        s = box("strap", (size[0] + 0.03, 0.06, size[2] + 0.03), Vector(loc), ob.rotation_euler, st, 0.005, 1)
        s.location = ob.matrix_world @ Vector((0, f * size[1], 0)) if False else Vector(loc) + Matrix.Rotation(rz, 3, "Z") @ Vector((0, f * size[1], 0))
    return ob


def catenary(a, b, sag, n):
    a = Vector(a); b = Vector(b)
    return [a.lerp(b, t) - Vector((0, 0, sag * 4 * t * (1 - t))) for t in (i / (n - 1) for i in range(n))]


def wire(pts, r=0.008, mat=None):
    cu = D.curves.new("wire", "CURVE"); cu.dimensions = "3D"; cu.bevel_depth = r; cu.bevel_resolution = 2
    sp = cu.splines.new("POLY"); sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts): sp.points[i].co = (*p, 1)
    ob = D.objects.new("wire", cu); link(ob)
    cu.materials.append(mat or simple_mat("wire", (0.03, 0.03, 0.03), 0.6))
    return ob


def string_lights(a, b, sag=0.6, n=14, light_every=3):
    pts = catenary(a, b, sag, n * 3)
    wire(pts)
    bm_ = bulb_mat()
    for i in range(1, n):
        p = pts[i * 3] - Vector((0, 0, 0.07))
        sphere("bulb", 0.055, p, bm_, 8, (1, 1, 1.25))
        if i % light_every == 0:
            point("bulb_l", p - Vector((0, 0, 0.05)), (1.0, 0.65, 0.35), 18, 0.05)


# ------------------------------------------------------------------------------------------------ set pieces
def shack(loc, rot_z):
    root, objs = import_glb("junkyard/shack.glb", 5.4, loc, rot_z, "shack")
    # warm interior glow behind the windows, and a porch lamp
    f = Matrix.Rotation(rot_z, 3, "Z")
    point("shack_in", Vector(loc) + f @ Vector((0, 0, 1.6)), (1.0, 0.62, 0.3), 900, 0.6)
    point("shack_in2", Vector(loc) + f @ Vector((1.5, 0.5, 3.2)), (1.0, 0.6, 0.28), 350, 0.4)
    return root


def skiff(loc, rot_z):
    root, objs = import_glb("junkyard/hull.glb", 4.2, Vector(loc) + Vector((0, 0, 1.2)), rot_z, "hull")
    f = Matrix.Rotation(rot_z, 3, "Z")
    # trestles
    for along in (-2.8, 0.0, 2.8):
        for side in (-1.0, 1.0):
            p = Vector(loc) + f @ Vector((along, side * 0.9, 0.65))
            box("trestle", (0.18, 0.18, 1.3), p, (side * 0.25, 0, rot_z), paint_mat("paint_yellow", PALETTE[6]), 0.02)
        box("trestle_top", (0.35, 2.2, 0.16), Vector(loc) + f @ Vector((along, 0, 1.3)), (0, 0, rot_z), steel(), 0.02)
    # scaffold along one side
    sm = paint_mat("scaffold", (0.75, 0.75, 0.72), rust=0.15, rough=0.35)
    for i in range(5):
        for side in (0, 1):
            p = Vector(loc) + f @ Vector((-4.4 + i * 2.2, -2.4 - side * 1.1, 2.0))
            cyl("pole", 0.045, 4.0, p, (0, 0, 0), sm, 10, 0.0)
        box("deck", (2.2, 1.3, 0.06), Vector(loc) + f @ Vector((-3.3 + i * 2.2, -2.95, 2.45)), (0, 0, rot_z), plank_mat(), 0.01) if i < 4 else None
    for z in (1.0, 2.45, 3.9):
        for side in (0, 1):
            a = Vector(loc) + f @ Vector((-4.4, -2.4 - side * 1.1, z)); b = Vector(loc) + f @ Vector((4.4, -2.4 - side * 1.1, z))
            mid = (a + b) / 2
            cyl("rail", 0.035, 8.8, mid, (0, math.pi / 2, rot_z), sm, 8, 0.0)
    # a tarp thrown over the nose, welding sparks on the side, work lamp
    spark = emit_mat("spark", (1.0, 0.75, 0.4), 120)
    weld = Vector(loc) + f @ Vector((1.2, -1.05, 1.9))
    point("weld", weld + f @ Vector((0, -0.15, 0)), (0.6, 0.8, 1.0), 260, 0.03)
    sphere("weld_core", 0.05, weld, emit_mat("weld_core", (0.7, 0.85, 1.0), 400), 6)
    for i in range(70):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1.6, -0.2), rng.uniform(-1.4, 0.6))).normalized() * rng.uniform(0.1, 1.4)
        a = weld + f @ d
        cyl("spark", 0.006, rng.uniform(0.05, 0.16), a, (rng.uniform(0, 3), rng.uniform(0, 3), 0), spark, 4, 0.0).visible_shadow = False
    return root


def plank_mat():
    key = ("plank",)
    if key in _mcache: return _mcache[key]
    m, nt, ln, out = new_mat("plank")
    tc = nt.new("ShaderNodeTexCoord")
    w = nt.new("ShaderNodeTexWave"); w.inputs["Scale"].default_value = 2.5; w.inputs["Distortion"].default_value = 6; w.inputs["Detail"].default_value = 4
    ln.new(tc.outputs["Object"], w.inputs["Vector"])
    r = nt.new("ShaderNodeValToRGB"); r.color_ramp.elements[0].color = (0.18, 0.1, 0.05, 1); r.color_ramp.elements[1].color = (0.5, 0.33, 0.19, 1)
    ln.new(w.outputs["Fac"], r.inputs[0])
    b = P(nt, rough=0.75)
    ln.new(r.outputs[0], b.inputs["Base Color"])
    bev = nt.new("ShaderNodeBevel"); bev.inputs["Radius"].default_value = 0.015; ln.new(bev.outputs[0], b.inputs["Normal"])
    ln.new(b.outputs[0], out.inputs[0])
    _mcache[key] = m
    return m


def magnet_crane(base, top_h=11.0, jib=9.0, jib_rot=0.6, car=True):
    """A lattice magnet crane over the yard, still swinging a sky-car it grabbed when the bots went haywire."""
    yel = paint_mat("paint_yellow", PALETTE[6])
    b = Vector(base)
    # lattice mast
    for cx in (-0.6, 0.6):
        for cy in (-0.6, 0.6):
            cyl("mast", 0.07, top_h, b + Vector((cx, cy, top_h / 2)), (0, 0, 0), yel, 8, 0.0)
    for i in range(int(top_h / 1.2)):
        z = 0.6 + i * 1.2
        for (p, r) in (((0, -0.6), (0, 0, 0)), ((0, 0.6), (0, 0, 0)), ((-0.6, 0), (0, 0, math.pi / 2)), ((0.6, 0), (0, 0, math.pi / 2))):
            cyl("brace", 0.035, 1.7, b + Vector((p[0], p[1], z)), (math.radians(45 if i % 2 else -45), 0, r[2]), yel, 6, 0.0)
    cab, _ = import_glb("chars/crane_cab.glb", 3.0, b + Vector((0, 0, top_h)), jib_rot + math.pi / 2, "cab")
    f = Matrix.Rotation(jib_rot, 3, "Z")
    tip = b + Vector((0, 0, top_h + 2.2)) + f @ Vector((jib, 0, 0))
    mid = (b + Vector((0, 0, top_h + 2.2)) + tip) / 2
    box("jib", (jib + 2.5, 0.7, 0.7), mid, (0, 0, jib_rot), yel, 0.04)
    box("counter", (2.0, 1.4, 1.2), b + Vector((0, 0, top_h + 2.2)) - f @ Vector((2.2, 0, 0)), (0, 0, jib_rot), steel(), 0.05)
    # cable and magnet swinging off-plumb
    swing = Vector((0.9, -0.5, 0))
    mag_at = tip + Vector((0, 0, -6.0)) + swing
    wire([tip, mag_at + Vector((0, 0, 1.0))], 0.03, steel())
    mag, _ = import_glb("chars/crane_magnet.glb", 1.6, mag_at, 0.3, "magnet")
    mag.rotation_euler = (0.12, -0.08, 0.3)
    if car:
        sc, _ = import_glb("panic/skycar.glb", 1.8, mag_at + Vector((0, 0, -1.75)), 1.2, "skycar")
        sc.rotation_euler = (0.25, 0.18, 1.2)
    return tip


def conveyor(a, b, w=1.4):
    a = Vector(a); b = Vector(b); d = b - a; L = d.length; rz = math.atan2(d.y, d.x)
    mid = (a + b) / 2
    belt = simple_mat("belt", (0.04, 0.04, 0.045), 0.65)
    box("belt", (L, w, 0.12), mid, (0, 0, rz), belt, 0.03)
    f = Matrix.Rotation(rz, 3, "Z")
    for s in (-1, 1):
        box("belt_side", (L, 0.1, 0.4), mid + f @ Vector((0, s * (w / 2 + 0.05), 0.05)), (0, 0, rz), paint_mat("paint_orange", PALETTE[1]), 0.02)
    n = int(L / 2.2)
    for i in range(n + 1):
        p = a + d * (i / n)
        for s in (-1, 1):
            box("leg", (0.12, 0.12, p.z), Vector((p.x, p.y, p.z / 2)) + f @ Vector((0, s * w / 2, 0)), (0, 0, rz), steel(), 0.01)
    # junk riding along it
    for i in range(int(L / 0.8)):
        p = a + d * rng.random() + Vector((0, 0, 0.18))
        scrap_piece(p, 0.45, rng.choice(["box", "plate", "gear", "drum"]))


def crusher(loc, rot_z):
    f = Matrix.Rotation(rot_z, 3, "Z"); L_ = Vector(loc)
    body = paint_mat("crusher", (0.2, 0.42, 0.45), rust=0.4)
    haz = hazard_mat()
    box("crusher_body", (3.4, 3.0, 3.2), L_ + Vector((0, 0, 1.6)), (0, 0, rot_z), body, 0.08, 3)
    box("crusher_hopper", (3.0, 2.6, 1.0), L_ + Vector((0, 0, 3.7)), (0, 0, rot_z), steel(), 0.04)
    box("crusher_stripe", (3.45, 3.05, 0.35), L_ + Vector((0, 0, 0.9)), (0, 0, rot_z), haz, 0.02)
    for s in (-1, 1):
        cyl("piston", 0.22, 2.6, L_ + f @ Vector((s * 1.85, 0, 2.2)), (0, 0, 0), steel(), 18, 0.01)
    sphere("warn", 0.16, L_ + Vector((0, 0, 4.4)), emit_mat("warn_red", (1, 0.15, 0.08), 80), 8)
    point("warn_l", L_ + Vector((0, 0, 4.7)), (1, 0.15, 0.08), 120, 0.1)


def hazard_mat():
    key = ("hazard",)
    if key in _mcache: return _mcache[key]
    m, nt, ln, out = new_mat("hazard")
    tc = nt.new("ShaderNodeTexCoord")
    mp = nt.new("ShaderNodeMapping"); mp.inputs["Rotation"].default_value = (0, 0, 0.785)
    ln.new(tc.outputs["Object"], mp.inputs["Vector"])
    w = nt.new("ShaderNodeTexWave"); w.wave_profile = "SAW"; w.inputs["Scale"].default_value = 2.5
    ln.new(mp.outputs[0], w.inputs["Vector"])
    r = nt.new("ShaderNodeValToRGB"); r.color_ramp.interpolation = "CONSTANT"
    r.color_ramp.elements[0].color = (0.02, 0.02, 0.02, 1); r.color_ramp.elements[1].position = 0.5; r.color_ramp.elements[1].color = (0.9, 0.62, 0.05, 1)
    ln.new(w.outputs["Fac"], r.inputs[0])
    b = P(nt, rough=0.45); ln.new(r.outputs[0], b.inputs["Base Color"]); ln.new(b.outputs[0], out.inputs[0])
    _mcache[key] = m
    return m


def gantry(a, b, h=3.6):
    a = Vector(a); b = Vector(b); d = b - a; L = d.length; rz = math.atan2(d.y, d.x); f = Matrix.Rotation(rz, 3, "Z")
    mid = (a + b) / 2 + Vector((0, 0, h))
    box("gantry_deck", (L, 1.8, 0.12), mid, (0, 0, rz), grate_mat(), 0.01)
    rail = paint_mat("paint_yellow", PALETTE[6])
    for s in (-1, 1):
        cyl("rail", 0.035, L, mid + f @ Vector((0, s * 0.9, 1.0)), (0, math.pi / 2, rz), rail, 8, 0.0)
        cyl("rail2", 0.025, L, mid + f @ Vector((0, s * 0.9, 0.5)), (0, math.pi / 2, rz), rail, 8, 0.0)
    n = int(L / 2.0)
    for i in range(n + 1):
        p = a + d * (i / n)
        for s in (-1, 1):
            cyl("post", 0.03, 1.0, Vector((p.x, p.y, h + 0.5)) + f @ Vector((0, s * 0.9, 0)), (0, 0, 0), rail, 8, 0.0)
        if i % 2 == 0:
            for s in (-1, 1):
                box("leg", (0.2, 0.2, h), Vector((p.x, p.y, h / 2)) + f @ Vector((0, s * 0.8, 0)), (0, 0, rz), steel(), 0.02)


def grate_mat():
    key = ("grate",)
    if key in _mcache: return _mcache[key]
    m, nt, ln, out = new_mat("grate")
    tc = nt.new("ShaderNodeTexCoord")
    ck = nt.new("ShaderNodeTexChecker"); ck.inputs["Scale"].default_value = 18
    ln.new(tc.outputs["Object"], ck.inputs["Vector"])
    b = P(nt, base=(0.22, 0.22, 0.24, 1), metal=0.85, rough=0.45)
    bump = nt.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.5
    ln.new(ck.outputs["Fac"], bump.inputs["Height"]); ln.new(bump.outputs[0], b.inputs["Normal"])
    ln.new(b.outputs[0], out.inputs[0])
    _mcache[key] = m
    return m


def domes(center, radius, n, seed=2):
    """Skyharbor's white domed towers on the horizon (the game's skyline language)."""
    r = random.Random(seed)
    white = simple_mat("dome_white", (0.86, 0.84, 0.8), 0.35, coat=0.3)
    gold = simple_mat("dome_gold", (0.9, 0.62, 0.25), 0.25, metal=1.0)
    glass = simple_mat("dome_glass", (0.7, 0.85, 0.95), 0.05, trans=0.8)
    win = emit_mat("dome_win", (1.0, 0.75, 0.45), 6)
    for i in range(n):
        a = math.radians(r.uniform(-75, 75)) + math.pi / 2
        d = radius * r.uniform(0.8, 1.3)
        p = Vector(center) + Vector((math.cos(a) * d, math.sin(a) * d, r.uniform(-14, -4)))
        h = r.uniform(18, 46); rad = r.uniform(4, 9)
        cyl("tower", rad, h, p + Vector((0, 0, h / 2)), (0, 0, 0), white, 48, 0.1)
        sphere("dome", rad * 1.05, p + Vector((0, 0, h)), glass if r.random() < 0.4 else white, 24, (1, 1, 0.85))
        for k in range(r.randint(1, 3)):
            torus("ring", rad * 1.35, rad * 0.07, p + Vector((0, 0, h * r.uniform(0.45, 0.95))), (0, 0, 0), gold)
        for k in range(r.randint(3, 8)):
            aa = r.uniform(0, 6.28); zz = r.uniform(4, h - 2)
            box("win", (0.6, 0.6, 1.0), p + Vector((math.cos(aa) * rad, math.sin(aa) * rad, zz)), (0, 0, aa), win, 0.0)


def floating_rocks(center, n, seed=5):
    r = random.Random(seed)
    rock = paint_mat("rock", (0.36, 0.27, 0.22), rust=0.0, rough=0.9, metal_edges=False, coat=0.0)
    grass = simple_mat("grass", (0.18, 0.32, 0.12), 0.8)
    for i in range(n):
        p = Vector(center) + Vector((r.uniform(-90, 90), r.uniform(-20, 30), r.uniform(-6, 30)))
        s = r.uniform(3, 10)
        bpy.ops.mesh.primitive_cone_add(vertices=9, radius1=s, depth=s * 1.8, location=p, rotation=(math.pi, 0, r.uniform(0, 6)))
        o = C.active_object; o.data.materials.append(rock)
        tex = D.textures.new("rk", "VORONOI")
        sub = o.modifiers.new("s", "SUBSURF"); sub.levels = 2; sub.render_levels = 2
        dm = o.modifiers.new("d", "DISPLACE"); dm.texture = tex; dm.strength = s * 0.25
        cyl("rock_top", s * 1.02, 0.4, p + Vector((0, 0, s * 0.9)), (0, 0, 0), grass, 9, 0.1)


def clouds(center, n, seed=9):
    """Soft cumulus banks behind the skyline (low density volumes so they glow in the sun)."""
    r = random.Random(seed)
    for i in range(n):
        sz = (r.uniform(25, 50), r.uniform(15, 25), r.uniform(8, 14))
        m = smoke_mat("cloud_%d" % i, color=(0.95, 0.9, 0.85), density=0.05, scale=0.06, dims=sz)
        p = Vector(center) + Vector((r.uniform(-160, 160), r.uniform(-10, 40), r.uniform(-25, 15)))
        vol_cube("cloud", m, p, sz, r.uniform(0, 1))


def hornet_swarm(pts):
    for p, rz in pts:
        h, _ = import_glb("hornet.glb", 1.3, p, rz, "hornet")
        h.rotation_euler = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rz)
        point("hornet_eye", Vector(p) + Vector((0, 0, 0.6)), (1.0, 0.2, 0.1), 25, 0.05)


def laser(a, b, color=(1.0, 0.25, 0.1), r=0.035, strength=80):
    a = Vector(a); b = Vector(b); d = b - a
    o = cyl("bolt", r, d.length, (a + b) / 2, (0, 0, 0), emit_mat("bolt_%s" % str(color), color, strength), 8, 0.0)
    o.rotation_mode = "QUATERNION"; o.rotation_quaternion = d.to_track_quat("Z", "Y")
    o.visible_shadow = False
    return o


def pose(arm_root, action, frame):
    arm = next((o for o in arm_root.children_recursive if o.type == "ARMATURE"), None)
    act = D.actions.get(action)
    if not arm or not act: return
    ad = arm.animation_data or arm.animation_data_create()
    for t in list(ad.nla_tracks): ad.nla_tracks.remove(t)
    ad.action = act
    try:
        if act.slots: ad.action_slot = act.slots[0]
    except Exception:
        pass
    C.scene.frame_set(frame)


def vesk(loc, rz, action="run_shoot", frame=6, h=1.6, lift=0.0):
    root, objs = import_glb("vesk.glb", None, loc, rz, "Vesk")
    pose(root, action, frame)
    C.view_layer.update()
    # scale to height after posing
    lo, hi = 1e9, -1e9
    for o in objs:
        if o.type == "MESH":
            for c in o.bound_box:
                z = (o.matrix_world @ Vector(c)).z; lo = min(lo, z); hi = max(hi, z)
    s = h / max(hi - lo, 1e-3)
    root.scale = (s, s, s)
    root["ground_z"] = loc[2] + lift
    root["fit_h"] = h
    # fur gets sheen and soft subsurface
    for o in objs:
        if o.type == "MESH":
            for m in o.data.materials:
                if not m: continue
                b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if b:
                    b.inputs["Sheen Weight"].default_value = 0.6; b.inputs["Sheen Roughness"].default_value = 0.4
                    b.inputs["Subsurface Weight"].default_value = 0.08
                    b.inputs["Coat Weight"].default_value = 0.0
    # blaster muzzle flash light
    return root


def dodger(loc, rz):
    root, objs = import_glb("chars/dodger_body.glb", 0.55, loc, rz, "Dodger")
    f = Matrix.Rotation(rz, 3, "Z")
    eye = Vector(loc) + Vector((0, 0, 0.28)) + f @ Vector((0, -0.3, 0))
    sphere("dodger_eye", 0.11, eye, emit_mat("dodger_eye", (0.3, 0.85, 1.0), 6), 12)
    point("dodger_glow", eye + f @ Vector((0, -0.2, 0)), (0.35, 0.9, 1.0), 30, 0.1)
    point("dodger_jet", Vector(loc) - Vector((0, 0, 0.15)), (0.35, 0.9, 1.0), 20, 0.1)
    return root


# ------------------------------------------------------------------------------------------------ the set
def build_set():
    world(sun_elev=4.0, sun_rot=-55.0, strength=0.5, haze=float(os.environ.get("LOOK_HAZE", "0.0007")))
    ground(260, (0, 30))
    # home yard: Vesk's shack facing the camera with its porch, string lights and clutter
    shack((0, 10, 0), 0.0)
    porch = None  # the shack model already has its own porch
    for x in (-5.6, 5.6):
        cyl("light_pole", 0.09, 4.6, (x, 3.2, 2.3), (0, 0, 0), plank_mat(), 10, 0.01)
    string_lights((-5.6, 3.2, 4.5), (5.6, 3.2, 4.5), 0.7, 18)
    string_lights((-5.6, 3.2, 4.5), (-1.0, 9.0, 5.6), 0.5, 10)
    string_lights((5.6, 3.2, 4.5), (2.0, 9.0, 5.6), 0.5, 10)
    wb, _ = import_glb("kit/workbench.glb", 1.0, (4.8, 1.0, 0), math.pi * 0.9, "workbench")
    import_glb("kit/barrel.glb", 1.0, (6.6, 2.0, 0), 0.4, "barrel")
    import_glb("kit/barrel.glb", 1.0, (7.3, 2.7, 0), 1.4, "barrel")
    import_glb("kit/generator.glb", 1.4, (-6.6, 1.8, 0), 0.9, "generator")
    import_glb("kit/water_tower.glb", 8.0, (-9.5, 13.5, 0), 0.3, "water_tower")
    import_glb("kit/wind_turbine.glb", 9.5, (8.5, 15.5, 0), -0.4, "turbine")
    import_glb("kit/scrap_heap.glb", 3.5, (-8.0, 7.0, 0), 0.8, "heap")
    import_glb("kit/junk_pile.glb", 2.2, (9.0, 7.0, 0), 2.0, "junk_pile")
    # litter: small scrap and bolts across the yard floor
    for i in range(260):
        p = Vector((rng.uniform(-18, 18), rng.uniform(-12, 22), 0.06))
        if abs(p.x) < 4.5 and 6 < p.y < 13: continue
        scrap_piece(p, rng.uniform(0.18, 0.4), rng.choice(["plate", "plate", "box", "gear", "pipe", "tire"]))
    # Scrap Heap (west): towers and piles
    for (x, y, h) in ((-15, 6, 7.5), (-19, 12, 11.0), (-13, 16, 5.0), (-23, 4, 9.0), (-26, 18, 13.0), (-17, 24, 8.0)):
        scrap_tower((x, y, 0), h, rng.uniform(1.8, 2.6))
    for (x, y, r_, h) in ((-12, 1, 3.0, 1.6), (-20, 9, 4.0, 2.6), (-24, 14, 3.5, 2.0), (-10, 19, 3.0, 1.8)):
        pile((x, y, 0), r_, h, 45)
    # Hull Dock (east): the half-built skiff on trestles under the magnet crane
    skiff((15.5, 9.0, 0), math.pi * 0.62)
    magnet_crane((22, 18, 0), 11.0, 10.0, math.radians(200))
    for (x, y, h) in ((24, 4, 8.0), (27, 12, 10.0), (20, 26, 7.0)):
        scrap_tower((x, y, 0), h, 2.2)
    pile((19, 1.5, 0), 2.5, 1.2, 30)
    # Sorting Works (north-west, behind the heap): bale steps, conveyor, crusher, gantry
    W = Vector((-14, 34, 0))
    for (dx, dy, n) in ((0, 0, 1), (2.4, 0, 2), (4.8, 0, 3), (4.8, 2.4, 3), (7.2, 2.4, 2), (-2.4, 3, 1), (9.6, 0, 4), (9.6, 2.4, 4)):
        for k in range(n):
            bale(W + Vector((dx, dy, 0.6 + k * 1.2)), (2.3, 2.3, 1.2), rng.uniform(-0.06, 0.06))
    gantry(W + Vector((-4, 6.5, 0)), W + Vector((16, 6.5, 0)), 4.8)
    conveyor(W + Vector((-10, -3, 2.0)), W + Vector((-3.0, -3, 2.6)))
    crusher(W + Vector((-1.2, -3, 0)), 0.0)
    magnet_crane(W + Vector((14, 10, 0)), 13.0, 9.0, math.radians(215), car=True)
    # Skyharbor beyond: domes, floating rocks, cloud banks
    domes((0, 20, 0), 120, 14)
    floating_rocks((0, 300, 10), 7)
    clouds((0, 230, 0), 8)
    # the panic: fires, smoke columns, bots in the sky
    fire((-12.5, 1.0, 1.4), 1.0, 1.8, 16, lean=(0.25, 0.1))
    fire((-20, 9, 2.4), 1.4, 2.4, 22, lean=(0.3, 0.1))
    fire((19, 1.5, 1.0), 0.9, 1.5, 14, lean=(0.25, 0.05))
    fire((27, 12, 10.0), 1.2, 2.0, 22, lean=(0.3, 0.0))
    fire((-26, 18, 13.0), 1.3, 2.2, 26, lean=(0.35, 0.05))
    fire((-14, 30, 0.2), 1.6, 2.6, 24, lean=(0.3, 0.0))
    # far smoke columns over the city
    for p in ((-60, 110, -2), (45, 95, -4), (90, 140, -6)):
        vol_cube("far_smoke", smoke_mat("far_smoke", (0.08, 0.075, 0.07), density=0.3, scale=0.08, emit_base=0.3, dims=(12, 12, 40)), Vector(p) + Vector((0, 0, 30)), (12, 12, 40))
        point("far_fire", Vector(p) + Vector((0, 0, 1)), (1.0, 0.4, 0.12), 60000, 3)


def camera(name, loc, target, lens=32, fstop=2.8, focus=None):
    cd = D.cameras.new(name); cd.lens = lens; cd.sensor_width = 36
    cd.dof.use_dof = True; cd.dof.aperture_fstop = fstop
    ob = D.objects.new(name, cd); link(ob)
    ob.location = loc
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cd.dof.focus_distance = focus or d.length
    return ob


def compositor():
    sc = C.scene
    if os.environ.get("LOOK_COMP", "1") != "1": return
    try: sc.render.compositor_device = "GPU" if GPU else "CPU"
    except Exception: pass
    try:
        sc.use_nodes = True
        nt = sc.node_tree
    except Exception:
        nt = None
    if nt is None:
        try:
            ng = D.node_groups.new("look_comp", "CompositorNodeTree")
            sc.compositing_node_group = ng
            nt = ng
            gi = nt.nodes.new("NodeGroupInput") if False else None
        except Exception as e:
            print("[look] no compositor", e); return
    for n in list(nt.nodes): nt.nodes.remove(n)
    rl = nt.nodes.new("CompositorNodeRLayers")
    try:
        out = nt.nodes.new("CompositorNodeComposite")
        out_in = out.inputs[0]
    except Exception:
        nt.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        out = nt.nodes.new("NodeGroupOutput"); out_in = out.inputs[0]
    cur = rl.outputs["Image"]
    try:
        gl = nt.nodes.new("CompositorNodeGlare")
        for attr, val in (("glare_type", "FOG_GLOW"), ("quality", "HIGH"), ("threshold", 1.2), ("size", 8), ("mix", -0.75)):
            try: setattr(gl, attr, val)
            except Exception: pass
        for k, val in (("Type", "Fog Glow"), ("Threshold", 1.2), ("Strength", 0.35), ("Size", 0.6)):
            if k in gl.inputs:
                try: gl.inputs[k].default_value = val
                except Exception: pass
        nt.links.new(cur, gl.inputs[0]); cur = gl.outputs[0]
    except Exception as e:
        print("[look] glare", e)
    try:
        ld = nt.nodes.new("CompositorNodeLensdist")
        for k, val in (("Distortion", -0.012), ("Dispersion", 0.012), ("Distort", -0.012), ("Dispersion", 0.012)):
            if k in ld.inputs: ld.inputs[k].default_value = val
        nt.links.new(cur, ld.inputs[0]); cur = ld.outputs[0]
    except Exception as e:
        print("[look] lens", e)
    nt.links.new(cur, out_in)


SHOT_CAMS = {
    # the yard: Vesk mid-run blasting a hornet, Dodger at his shoulder, the shack and skiff behind, smoke rising
    "hero": dict(loc=(-3.8, -9.8, 0.8), target=(3.6, 6, 3.4), lens=26, fstop=2.8, focus=5.0),
    # the Sorting Works: low angle up the bale steps to the gantry, crusher light and fire
    "works": dict(loc=(-9.0, 26.8, 1.5), target=(-10.6, 35.0, 4.0), lens=24, fstop=3.2, focus=6.4),
    # the Hull Dock: the skiff on its trestles, welding sparks, crane swinging the car overhead
    "dock": dict(loc=(8.0, -2.4, 1.2), target=(15.0, 9.0, 3.6), lens=26, fstop=3.5, focus=6.3),
}


def build_actors(shot):
    if shot == "hero":
        # Vesk mid-run, blasting a hornet off to the right; Dodger at his shoulder
        vesk((-3.3, -5.7, 0), math.radians(58), "run_shoot", 8, 1.6)
        dodger((-2.1, -4.7, 2.15), math.radians(25))
        laser((-2.55, -6.15, 1.0), (6.0, -9.0, 3.0), (0.25, 0.85, 1.0), 0.012, 14)
        sphere("muzzle_flash", 0.045, (-2.5, -6.2, 1.0), emit_mat("muzzle_fx", (0.4, 0.9, 1.0), 40), 8, (1.6, 1, 1))
        point("muzzle", (-2.45, -6.3, 1.05), (0.3, 0.9, 1.0), 150, 0.05)
        hornet_swarm([((2.8, -1.0, 4.6), 4.2), ((-1.5, 1.5, 3.2), 3.0), ((-4.5, 6.0, 7.5), 3.6), ((10.5, 4.0, 9.0), 2.2),
                      ((1.0, 18, 12.0), 3.0), ((14, 20, 14), 2.0), ((18.5, 6.0, 6.0), 4.0)])
        import_glb("roller.glb", 1.2, (6.5, -1.0, 0), math.radians(140), "roller")
        import_glb("roller.glb", 1.2, (-7.5, 4.0, 0), math.radians(30), "roller")
        laser((10.5, 4.0, 9.0), (8.0, 1.5, 6.6), (1.0, 0.25, 0.08), 0.012, 14)
        laser((-4.5, 6.0, 7.5), (-5.2, 3.0, 5.0), (1.0, 0.25, 0.08), 0.012, 14)
        # foreground: burning debris low in frame, soft in the depth of field
        fire((1.2, -6.2, 0.05), 0.4, 0.7, 6, lean=(0.2, 0.1))
        for i in range(6): scrap_piece(Vector((1.2 + rng.uniform(-0.6, 0.6), -6.2 + rng.uniform(-0.6, 0.6), 0.1)), 0.35, rng.choice(["plate", "box", "tire"]))
        for (rel, p, rz) in (("citizens/cit_goat.glb", (3.2, 1.8, 0), 0.4), ("citizens/cit_frog.glb", (-3.8, 2.5, 0), -0.5),
                             ("citizens/cit_bird.glb", (11.0, 3.5, 0), 0.9)):
            if os.path.exists(os.path.join(MODELS, rel)):
                c_ = import_glb(rel, 1.3, p, rz, os.path.basename(rel))[0]; c_["ground_z"] = 0.0; c_["fit_h"] = 1.25
    elif shot == "works":
        # Vesk leaping up the bale steps of the Sorting Works, hornets buzzing the gantry, the crusher burning
        vesk((-10.4, 33.0, 2.4), math.radians(-120), "jump", 6, 1.6, lift=0.8)
        dodger((-8.4, 32.0, 4.1), math.radians(-60))
        hornet_swarm([((-6.0, 37.0, 7.5), 2.0), ((-12.0, 40.0, 9.5), 3.5), ((-3.0, 33.0, 5.5), 1.2)])
        laser((-6.0, 37.0, 7.5), (-9.6, 33.4, 3.6), (1.0, 0.25, 0.08), 0.012, 14)
        import_glb("roller.glb", 1.2, (-9.2, 38.4, 4.9), math.radians(200), "roller")
        fire((-15.5, 31.0, 4.0), 0.9, 1.4, 14, lean=(0.3, 0.0))
    elif shot == "dock":
        # Vesk wrenching a Scrap Roller off the skiff's trestles while the crane swings overhead
        vesk((11.3, 3.1, 0), math.radians(49), "melee", 7, 1.6)
        dodger((10.2, 3.4, 2.1), math.radians(20))
        import_glb("roller.glb", 1.2, (12.7, 2.0, 0), math.radians(-130), "roller")
        hornet_swarm([((16.0, 6.0, 6.5), 2.6), ((10.0, 12.0, 8.0), 3.4)])
        laser((16.0, 6.0, 6.5), (11.8, 3.4, 1.2), (1.0, 0.25, 0.08), 0.012, 14)


def main():
    os.makedirs(OUT, exist_ok=True)
    for shot in SHOTS:
        global rng
        rng = random.Random(4417)
        _mcache.clear(); del _bale_mats[:]
        sc = reset()
        build_set()
        build_actors(shot)
        ground_skinned()
        compositor()
        cam = camera("cam_" + shot, **SHOT_CAMS[shot])
        sc.camera = cam
        if os.environ.get("LOOK_SAVE") == "1":
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "junkyard_%s.blend" % shot))
        if os.environ.get("LOOK_DEBUG") == "1":
            dg = C.evaluated_depsgraph_get()
            for o in D.objects:
                if o.type == "MESH" and o.parent and o.parent.type == "ARMATURE":
                    ev = o.evaluated_get(dg); me = ev.to_mesh()
                    zs = [(ev.matrix_world @ v.co).z for v in me.vertices]
                    print("[look] skinned", o.name, o.parent.name, round(min(zs), 2), round(max(zs), 2), "frame", sc.frame_current)
                    ev.to_mesh_clear()
            continue
        sc.render.filepath = os.path.join(OUT, "junkyard_%s.png" % shot)
        print("[look] rendering", shot, sc.render.resolution_x * RES // 100, "x", sc.render.resolution_y * RES // 100, SAMPLES, "spp")
        bpy.ops.render.render(write_still=True)
        print("[look] wrote", sc.render.filepath)


main()
