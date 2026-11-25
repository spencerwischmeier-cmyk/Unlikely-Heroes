# Comic panels for the story intro and outro, rendered with Cycles plus Freestyle ink lines.
# Uses the game's own models (public/models/*.glb) and builds the sets and Foreman Grudd from primitives.
#   blender --background --python art/comic.py -- [panel names...]
# Writes 1280x800 JPEGs to public/comic/.
import bpy, bmesh, math, random, sys, os
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blib import reset, gv, mat, glowmat, part, bm_box, bm_cyl, bm_sphere, bm_torus, bm_cone, empty

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
MODELS = os.path.join(ROOT, 'public', 'models')
OUT = os.path.join(ROOT, 'public', 'comic')
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(7)

def imp(name, at=(0, 0, 0), yaw=0.0, scale=1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + '.glb'))
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    for r in roots:
        r.rotation_mode = 'XYZ'  # the glTF importer uses quaternions
        r.location = gv(*at); r.rotation_euler = (0, 0, yaw); r.scale = (scale,) * 3
    return roots[0], {o.name.split('.')[0]: o for o in new}

def look(cam, frm, to, lens=35):
    cam.data.lens = lens
    cam.location = gv(*frm)
    cam.rotation_euler = (gv(*to) - cam.location).to_track_quat('-Z', 'Y').to_euler()

def setup(sky_top=(0.05, 0.2, 0.5), sky_hor=(0.55, 0.75, 0.9), strength=1.0):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = int(os.environ.get('SAMPLES', 40)); sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.render.resolution_x, sc.render.resolution_y = 1280, 800
    sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Punchy'
    sc.render.image_settings.file_format = 'JPEG'; sc.render.image_settings.quality = 86
    # ink lines
    sc.render.use_freestyle = True; sc.render.line_thickness_mode = 'ABSOLUTE'; sc.render.line_thickness = 2.2
    vl = sc.view_layers[0]; vl.use_freestyle = True
    ls = vl.freestyle_settings.linesets[0] if vl.freestyle_settings.linesets else vl.freestyle_settings.linesets.new('L')
    ls.select_by_visibility = True; ls.select_silhouette = True; ls.select_border = True; ls.select_crease = False
    ls.linestyle.color = (0.04, 0.05, 0.08); ls.linestyle.thickness = 2.2
    c = bpy.data.collections.get('noink') or bpy.data.collections.new('noink')
    if c.name not in sc.collection.children: sc.collection.children.link(c)
    ls.select_by_collection = True; ls.collection = c; ls.collection_negation = 'EXCLUSIVE'
    vl.freestyle_settings.crease_angle = math.radians(110)
    # sky: gradient by height
    w = bpy.data.worlds.new('W'); sc.world = w; w.use_nodes = True
    nt = w.node_tree; nt.nodes.clear()
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = nt.nodes.new('ShaderNodeSeparateXYZ'); ramp = nt.nodes.new('ShaderNodeValToRGB')
    bg = nt.nodes.new('ShaderNodeBackground'); out = nt.nodes.new('ShaderNodeOutputWorld')
    nt.links.new(tc.outputs['Generated'], sep.inputs[0]); nt.links.new(sep.outputs['Z'], ramp.inputs[0])
    ramp.color_ramp.elements[0].position = 0.0; ramp.color_ramp.elements[0].color = sky_hor + (1,)
    ramp.color_ramp.elements[1].position = 0.45; ramp.color_ramp.elements[1].color = sky_top + (1,)
    nt.links.new(ramp.outputs[0], bg.inputs[0]); bg.inputs[1].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs[0])
    cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam')); sc.collection.objects.link(cam); sc.camera = cam
    return cam

def sun(energy=4.0, rot=(50, 10, 30), color=(1, 0.95, 0.85)):
    s = bpy.data.objects.new('Sun', bpy.data.lights.new('Sun', 'SUN')); bpy.context.scene.collection.objects.link(s)
    s.data.energy = energy; s.data.color = color; s.rotation_euler = tuple(math.radians(a) for a in rot); s.data.angle = math.radians(3)
    return s

def area(at, to, energy=400, size=4, color=(1, 1, 1)):
    l = bpy.data.objects.new('Area', bpy.data.lights.new('Area', 'AREA')); bpy.context.scene.collection.objects.link(l)
    l.data.energy = energy; l.data.size = size; l.data.color = color; l.location = gv(*at)
    l.rotation_euler = (gv(*to) - l.location).to_track_quat('-Z', 'Y').to_euler()
    return l

def point(at, energy=200, color=(1, 0.3, 0.2), radius=0.3):
    l = bpy.data.objects.new('Pt', bpy.data.lights.new('Pt', 'POINT')); bpy.context.scene.collection.objects.link(l)
    l.data.energy = energy; l.data.color = color; l.data.shadow_soft_size = radius; l.location = gv(*at)
    return l

# ---------- set pieces ----------
M = {}
def mats():
    M.update(
        deck=mat('deck', 0x9aa6b4, 0.5, 0.5), dark=mat('dark', 0x34404c, 0.75, 0.4), white=mat('white', 0xdfe8ee, 0.6, 0.3),
        blue=mat('blue', 0x5f8fb0, 0.7, 0.32), teal=mat('teal', 0x3f9fa0, 0.6, 0.35), brass=mat('brass', 0xd9a441, 0.9, 0.3),
        rust=mat('rust', 0x8a4a2a, 0.5, 0.7), orange=mat('orange', 0xff8f1f, 0.35, 0.45), yellow=mat('yellow', 0xf0b21e, 0.45, 0.4),
        rock=mat('rock', 0x6d5a4c, 0.0, 0.9), tire=mat('tire', 0x1d1f24, 0.0, 0.8), red=mat('red', 0x9b1f2a, 0.5, 0.4),
        glowc=glowmat('glowc', 0x40f0ff, 6), gloww=glowmat('gloww', 0xffa030, 6), glowr=glowmat('glowr', 0xff3020, 10),
    )
    M['window'] = tower_mat()

def tower_mat():
    m = bpy.data.materials.new('tower'); m.use_nodes = True; nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (0.16, 0.22, 0.32, 1); b.inputs['Metallic'].default_value = 0.4; b.inputs['Roughness'].default_value = 0.4
    tc = nt.nodes.new('ShaderNodeTexCoord'); br = nt.nodes.new('ShaderNodeTexBrick')
    br.inputs['Scale'].default_value = 0.9; br.inputs['Mortar Size'].default_value = 0.35
    br.inputs['Color1'].default_value = (1.0, 0.78, 0.45, 1); br.inputs['Color2'].default_value = (0.45, 0.85, 1.0, 1); br.inputs['Mortar'].default_value = (0, 0, 0, 1)
    nt.links.new(tc.outputs['Object'], br.inputs['Vector'])
    nt.links.new(br.outputs['Color'], b.inputs['Emission Color']); b.inputs['Emission Strength'].default_value = 1.3
    return m

def island(cx, cz, w, d, top=0.0, depth=6):
    w, d = w + 10, d + 10  # extra deck so its edges stay out of frame
    part('isl_top', bm_box(w, 0.6, d), M['deck'], at=(cx, top - 0.3, cz), smooth=False)  # flat shading: no false ink lines

def junk(cx, cz, n=30, spread=3.0, h=2.0):
    for i in range(n):
        x = cx + rnd.uniform(-spread, spread); z = cz + rnd.uniform(-spread, spread)
        y = max(0, h * (1 - math.hypot(x - cx, z - cz) / spread)) * rnd.uniform(0.4, 1.0)
        k = rnd.random(); m = rnd.choice([M['rust'], M['dark'], M['blue'], M['brass'], M['white'], M['orange']])
        rot = (rnd.uniform(-1, 1), rnd.uniform(0, 3), rnd.uniform(-1, 1))
        if k < 0.35: part('j', bm_box(rnd.uniform(0.4, 1.2), rnd.uniform(0.3, 0.9), rnd.uniform(0.4, 1.2)), m, at=(x, y, z), rot=rot, rounded=0.03)
        elif k < 0.6: part('j', bm_cyl(rnd.uniform(0.2, 0.45), rnd.uniform(0.2, 0.45), rnd.uniform(0.5, 1.4), 14), m, at=(x, y, z), rot=rot)
        elif k < 0.8: part('j', bm_torus(0.45, 0.18, 20, 10), M['tire'], at=(x, y, z), rot=rot)
        else: part('j', bm_sphere(rnd.uniform(0.25, 0.5), 16, 10), m, at=(x, y, z))

def towers(n=26, r0=45, r1=150, seed=3):
    r = random.Random(seed)
    for i in range(n):
        a = r.uniform(0, math.tau); d = r.uniform(r0, r1)
        x, z = math.sin(a) * d, -math.cos(a) * d
        rad = r.uniform(2.5, 6); top = r.uniform(4, 30)
        part('tw', bm_cyl(rad, rad, top + 60, 20), M['window'], at=(x, top / 2 - 30, z))
        part('tw_cap', bm_sphere(rad * 1.05, 20, 10), M['white'], at=(x, top, z), scale=(1, 0.6, 1))
        part('tw_ring', bm_torus(rad * 1.6, 0.25, 32, 8), M['white'], at=(x, top - 2, z), rot=(math.pi / 2, 0, 0))
        for k in range(3): part('tw_band', bm_cyl(rad * 1.03, rad * 1.03, 0.4, 20), M['gloww'] if (i + k) % 2 else M['glowc'], at=(x, top - 6 - k * 7, z))

def clouds(n=14, seed=5, y=(-25, -8)):
    r = random.Random(seed); cm = mat('cloud', 0xffffff, 0, 1, emit=0xffffff, strength=0.35)
    for i in range(n):
        x, z = r.uniform(-90, 90), r.uniform(-120, 10)
        for k in range(5): noink(part('cl', bm_sphere(r.uniform(4, 9), 16, 10), cm, at=(x + r.uniform(-8, 8), r.uniform(*y), z + r.uniform(-5, 5)), scale=(1.6, 0.7, 1)))

# objects that get no ink lines (soft things like clouds and smoke)
def noink(o):
    c = bpy.data.collections.get('noink')
    if not c: c = bpy.data.collections.new('noink'); bpy.context.scene.collection.children.link(c)
    for u in list(o.users_collection): u.objects.unlink(o)
    c.objects.link(o); return o

# glowing see-through hologram: bright at the edges, faint in the middle, with scanlines
def holo_mat(name, color, strength=6.0):
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    lw = nt.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = 0.35
    tc = nt.nodes.new('ShaderNodeTexCoord'); wv = nt.nodes.new('ShaderNodeTexWave'); wv.inputs['Scale'].default_value = 18; wv.wave_profile = 'SAW'; wv.bands_direction = 'Z'
    nt.links.new(tc.outputs['Object'], wv.inputs['Vector'])
    mul = nt.nodes.new('ShaderNodeMath'); mul.operation = 'MULTIPLY_ADD'; mul.inputs[1].default_value = 0.35; mul.inputs[2].default_value = 0.65
    nt.links.new(wv.outputs['Fac'], mul.inputs[0])
    add = nt.nodes.new('ShaderNodeMath'); add.operation = 'ADD'; add.inputs[1].default_value = 0.25
    nt.links.new(lw.outputs['Facing'], add.inputs[0])
    fac = nt.nodes.new('ShaderNodeMath'); fac.operation = 'MULTIPLY'; fac.use_clamp = True
    soft = nt.nodes.new('ShaderNodeMath'); soft.operation = 'MULTIPLY'; soft.inputs[1].default_value = 0.7
    nt.links.new(add.outputs[0], fac.inputs[0]); nt.links.new(mul.outputs[0], fac.inputs[1])
    em = nt.nodes.new('ShaderNodeEmission'); em.inputs[0].default_value = color + (1,); em.inputs[1].default_value = strength
    tr = nt.nodes.new('ShaderNodeBsdfTransparent'); mix = nt.nodes.new('ShaderNodeMixShader'); out = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(fac.outputs[0], soft.inputs[0]); nt.links.new(soft.outputs[0], mix.inputs[0]); nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2]); nt.links.new(mix.outputs[0], out.inputs[0])
    return m

# ---------- Foreman Grudd (as a red hologram) ----------
def grudd(at=(0, 0, 0), s=1.0, holo=True):
    if holo:
        body = holo_mat('holo', (1.0, 0.08, 0.02), 3.0)
        eye = glowmat('grudd_eye', 0xffd040, 25)
    else:
        body = mat('grudd_body', 0x4a4f58, 0.8, 0.4); eye = glowmat('grudd_eye', 0xffb020, 14)
    x, y, z = at
    P = lambda name, bm, m, dx, dy, dz, **kw: part(name, bm, m, at=(x + dx * s, y + dy * s, z + dz * s), **kw)
    # torso and shoulders
    P('g_torso', bm_box(5.2 * s, 3.4 * s, 3 * s), body, 0, 1.7, 0, rounded=0.3 * s)
    for sx in (-1, 1):
        P('g_shoulder', bm_box(2.2 * s, 2.0 * s, 2.6 * s), body, 3.4 * sx, 3.0, 0, rounded=0.3 * s)
        P('g_stack', bm_cyl(0.45 * s, 0.55 * s, 2.6 * s, 16), body, 3.6 * sx, 5.2, -0.4)
        P('g_stackrim', bm_torus(0.5 * s, 0.1 * s, 20, 8), body, 3.6 * sx, 6.5, -0.4, rot=(math.pi / 2, 0, 0))
    # head: a boxy furnace with a hard-hat dome, one wide visor and a grill jaw
    P('g_head', bm_box(3.6 * s, 2.6 * s, 2.8 * s), body, 0, 4.9, 0.3, rounded=0.35 * s)
    P('g_hat', bm_sphere(2.0 * s, 32, 16), body, 0, 6.15, 0.3, scale=(1.05, 0.55, 0.95))
    P('g_brim', bm_cyl(2.5 * s, 2.5 * s, 0.18 * s, 32), body, 0, 6.1, 0.5)
    P('g_visor', bm_box(2.9 * s, 0.55 * s, 0.2 * s), eye, 0, 5.35, 1.72, rounded=0.1 * s)
    for i in range(6): P('g_grill', bm_box(0.18 * s, 0.9 * s, 0.25 * s), body, -1.1 + i * 0.44, 4.2, 1.7)
    for sx in (-1, 1): P('g_bolt', bm_sphere(0.2 * s, 12, 8), body, 1.5 * sx, 4.2, 1.6)
    for sx in (-1, 1): P('g_vent', bm_cyl(0.5 * s, 0.5 * s, 0.3 * s, 16), body, 1.95 * sx, 4.9, 0.6, rot=(0, 0, math.pi / 2))
    P('g_gear', bm_torus(0.8 * s, 0.22 * s, 12, 6), eye, 0, 2.2, 1.55)
    P('g_gearhub', bm_sphere(0.35 * s, 12, 8), eye, 0, 2.2, 1.55)
    P('g_hatstripe', bm_box(0.5 * s, 0.25 * s, 3.8 * s), eye, 0, 6.85, 0.3)
    # arms with clamp hands
    for sx in (-1, 1):
        P('g_arm', bm_cyl(0.6 * s, 0.5 * s, 3.2 * s, 16), body, 3.9 * sx, 0.6, 0.3)
        P('g_hand', bm_box(1.4 * s, 1.0 * s, 1.4 * s), body, 3.9 * sx, -1.3, 0.5, rounded=0.2 * s)

# ---------- panels ----------
def p_intro1(cam):
    setup(sky_top=(0.18, 0.08, 0.32), sky_hor=(1.0, 0.55, 0.3), strength=1.2); mats()
    sun(3.5, (75, 0, -60), (1, 0.75, 0.5)); area((-4, 4, 6), (0, 1, 0), 500, 5, (0.7, 0.85, 1))
    island(0, 0, 18, 14); junk(-4.5, -3, 46, 3.2, 2.6); junk(4.5, -4, 30, 2.6, 1.8); junk(-6, 3, 14, 1.6, 0.9)
    part('shack', bm_box(3.5, 2.6, 2.6), M['blue'], at=(5.2, 1.3, 1.5), rounded=0.08)
    part('roof', bm_box(4, 0.2, 3), M['rust'], at=(5.2, 2.7, 1.5), rot=(0, 0, 0.1))
    part('sign', bm_box(2.4, 0.6, 0.1), M['orange'], at=(5.2, 2.0, 2.85))
    part('crate', bm_box(1.0, 0.8, 1.0), M['teal'], at=(-1.9, 0.4, -0.4), rounded=0.08)
    part('toolbox', bm_box(0.8, 0.35, 0.4), M['red'], at=(1.0, 0.18, 0.9), rounded=0.05)
    imp('hero', at=(-0.4, 0, 0.6), yaw=0.35)
    imp('drone', at=(1.6, 2.1, 0.8), yaw=-0.8)
    towers(30, 40, 140); clouds(12)
    look(cam, (1.8, 1.6, 5.8), (0.0, 1.3, 0.0), 32)

def p_intro2(cam):
    setup(sky_top=(0.12, 0.02, 0.04), sky_hor=(0.8, 0.25, 0.12), strength=1.0); mats()
    sun(2.0, (35, 0, 150), (1, 0.4, 0.3)); area((0, 6, 6), (0, 0, 0), 300, 8, (1, 0.6, 0.5))
    point((0, 1.5, 2), 300, (1, 0.2, 0.1), 1)
    island(0, 0, 20, 16); junk(0, -4, 60, 4.5, 3.0)
    for (x, z, yaw) in [(-2.8, 1.6, 0.3), (0.2, 2.4, 0), (2.9, 1.2, -0.4), (-0.9, -0.2, 0.1), (1.6, -0.6, -0.2)]:
        imp('roller', at=(x, 0, z), yaw=yaw)
    imp('hornet', at=(-3.4, 3.4, 0.0), yaw=0.5); imp('hornet', at=(3.6, 3.9, -0.6), yaw=-0.5)
    towers(24, 40, 140); clouds(8)
    look(cam, (0.0, 0.7, 8.2), (0.0, 1.6, 0.0), 28)

def p_intro3(cam):
    setup(sky_top=(0.03, 0.15, 0.4), sky_hor=(0.45, 0.7, 0.9)); mats()
    sun(3.5, (55, 0, 30)); area((-2, 2, 3), (0.6, 1.5, 0), 120, 2, (0.6, 0.95, 1))
    island(0, 0, 18, 14); junk(-3, -4, 30, 3, 2)
    imp('drone', at=(0.35, 1.55, 0.4), yaw=0.25, scale=1.0)
    imp('hero', at=(-1.4, 0, -2.2), yaw=0.3)
    # holographic map of the signal spreading from planet to planet
    holo = bpy.data.materials.new('mapholo'); holo.use_nodes = True; nt = holo.node_tree; nt.nodes.clear()
    em = nt.nodes.new('ShaderNodeEmission'); em.inputs[0].default_value = (0.2, 0.9, 1, 1); em.inputs[1].default_value = 4
    tr = nt.nodes.new('ShaderNodeBsdfTransparent'); mx = nt.nodes.new('ShaderNodeMixShader'); mx.inputs[0].default_value = 0.6
    o = nt.nodes.new('ShaderNodeOutputMaterial'); nt.links.new(tr.outputs[0], mx.inputs[1]); nt.links.new(em.outputs[0], mx.inputs[2]); nt.links.new(mx.outputs[0], o.inputs[0])
    pm = holo_mat('mapholo2', (0.2, 0.9, 1.0), 5)
    for (x, y, r) in [(-0.55, 2.05, 0.07), (-0.25, 2.25, 0.05), (-0.75, 2.3, 0.06), (-0.4, 1.9, 0.04)]:
        part('planet', bm_sphere(r, 20, 12), pm, at=(x, y, 0.2))
        part('pulse', bm_torus(r * 1.9, 0.006, 32, 6), glowmat('pulse', 0xff3020, 8), at=(x, y, 0.2), rot=(0.3, 0, 0))
    towers(28, 40, 140); clouds(10)
    look(cam, (0.5, 1.75, 2.6), (-0.25, 1.75, 0.2), 32)

def p_intro4(cam):
    setup(sky_top=(0.03, 0.18, 0.5), sky_hor=(0.6, 0.8, 0.95), strength=1.1); mats()
    sun(4.5, (40, 0, -30)); area((3, 1, 3), (0, 1.2, 0), 300, 3, (1, 0.8, 0.6))
    island(0, 0, 12, 10)
    imp('hero', at=(0, 0, 0), yaw=0.5)
    imp('drone', at=(-0.9, 2.2, -0.3), yaw=0.6)
    towers(40, 25, 160); clouds(14)
    look(cam, (0.9, 0.45, 2.3), (-0.05, 1.35, 0), 22)

def p_outro1(cam):
    setup(sky_top=(0.1, 0.12, 0.35), sky_hor=(1.0, 0.6, 0.35)); mats()
    sun(3.0, (60, 0, -120), (1, 0.8, 0.6)); point((0.5, 1.2, -2.5), 400, (1, 0.45, 0.1), 1.5)
    island(0, 0, 20, 18)
    # the wrecked crane bot: tipped cab, broken boom, scattered tracks
    part('cab', bm_box(2.4, 2.1, 2.3), M['yellow'], at=(0.6, 1.0, -3), rot=(0.3, 0.6, 0.5), rounded=0.25)
    part('visor', bm_box(1.8, 0.4, 0.12), mat('deadeye', 0x221111, 0.3, 0.5), at=(0.9, 1.3, -1.9), rot=(0.3, 0.6, 0.5))
    part('chassis', bm_box(2.6, 0.8, 4.2), M['yellow'], at=(-2.2, 0.4, -4.2), rot=(0, 0.9, 0.15), rounded=0.12)
    for i in range(6): part('lat', bm_box(0.14, 0.14, 4), M['yellow'], at=(2.5 + i * 0.25, 0.4 + i * 0.05, -4.5 + (i % 2) * 0.5), rot=(0.1, 1.1 + i * 0.05, 0.2))
    part('magnet', bm_cyl(1.15, 1.25, 0.5, 24), M['dark'], at=(-3.6, 0.25, -1.2), rot=(0.2, 0, 0.4))
    for i in range(14): part('tread', bm_box(0.5, 0.15, 0.3), M['dark'], at=(rnd.uniform(-4, 4), 0.08, rnd.uniform(-5, 1)), rot=(0, rnd.uniform(0, 3), 0))
    smoke = mat('smoke', 0x555a60, 0, 1)
    for i in range(10): noink(part('smk', bm_sphere(rnd.uniform(0.4, 0.9), 14, 8), smoke, at=(0.6 + rnd.uniform(-0.6, 0.6), 2.5 + i * 0.45, -3.4 - i * 0.2)))
    imp('hero', at=(-1.3, 0, 2.2), yaw=0.45)
    imp('drone', at=(0.9, 2.0, 2.3), yaw=0.2)
    towers(24, 40, 140); clouds(8)
    look(cam, (-0.3, 1.9, 6.4), (-0.2, 1.3, -1.6), 30)

def p_outro2(cam):
    setup(sky_top=(0.02, 0.02, 0.05), sky_hor=(0.15, 0.04, 0.05), strength=0.6); mats()
    sun(0.6, (60, 0, 30), (0.6, 0.6, 1)); point((0, 1.0, 0), 800, (1, 0.25, 0.1), 2)
    island(0, 0, 20, 18)
    part('radio', bm_box(0.8, 0.5, 0.5), M['yellow'], at=(0, 0.25, 1.0), rounded=0.06)
    part('proj', bm_cone(1.4, 2.4, 24), holo_mat('projbeam', (1.0, 0.25, 0.05), 1.5), at=(0, 1.7, 0.6), rot=(math.pi, 0, 0))
    grudd(at=(0, 2.6, -0.5), s=0.62)
    imp('hero', at=(-2.2, 0, 4.4), yaw=math.pi - 0.5); imp('drone', at=(2.0, 1.9, 4.6), yaw=math.pi + 0.5)
    look(cam, (0.0, 1.6, 10.5), (0.0, 3.4, 0), 30)

def p_outro3(cam):
    setup(sky_top=(0.08, 0.05, 0.25), sky_hor=(1.0, 0.5, 0.35), strength=1.2); mats()
    sun(3.0, (82, 0, 180), (1, 0.7, 0.5)); area((0, 3, 4), (0, 1, 0), 250, 4, (0.7, 0.8, 1))
    island(0, 0, 10, 8)
    imp('hero', at=(-1.5, 0, 1.6), yaw=math.pi + 0.35)
    imp('drone', at=(0.9, 2.0, 1.4), yaw=math.pi - 0.3)
    # a distant planet with the signal beam rising from it
    part('planet', bm_sphere(24, 48, 24), mat('planet', 0x5a3a8a, 0, 0.8, emit=0x2a1040, strength=0.3), at=(-30, 18, -150))
    part('ring', bm_torus(40, 1.2, 96, 8), mat('pring', 0xd9b0ff, 0, 0.6, emit=0x8040c0, strength=0.6), at=(-30, 18, -150), rot=(1.2, 0.3, 0))
    part('beam', bm_cyl(0.8, 0.8, 120, 12), glowmat('sbeam', 0xff3020, 6), at=(-24, 60, -140))
    towers(20, 40, 140, seed=9); clouds(12)
    look(cam, (0.3, 1.4, 5.4), (-2.0, 3.6, -20), 30)

PANELS = {'intro1': p_intro1, 'intro2': p_intro2, 'intro3': p_intro3, 'intro4': p_intro4, 'outro1': p_outro1, 'outro2': p_outro2, 'outro3': p_outro3}

if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    for name in (args or list(PANELS)):
        reset()
        for w in list(bpy.data.worlds): bpy.data.worlds.remove(w)
        for c in list(bpy.data.collections): bpy.data.collections.remove(c)
        sc = bpy.context.scene
        cam = None
        # each panel calls setup(), which makes the camera; look() places it
        def run():
            fn = PANELS[name]
            fn(_Cam())
        class _Cam:
            def __getattr__(self, k): return getattr(bpy.context.scene.camera, k)
            def __setattr__(self, k, v): setattr(bpy.context.scene.camera, k, v)
        run()
        sc.render.filepath = os.path.join(OUT, name + '.jpg')
        bpy.ops.render.render(write_still=True)
        print('rendered', name)
