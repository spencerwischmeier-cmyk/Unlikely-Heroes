# Render glb files side by side for a quick look (Cycles CPU, low samples).
#   bpy-python art/meshy/sheet.py out.png file1.glb file2.glb ... [--size 1200x500] [--yaw 30]
import bpy, sys, math
from mathutils import Vector
args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
size = (1200, 500); yaw = 30.0; samples = 16
if '--size' in args:
    i = args.index('--size'); size = tuple(int(v) for v in args[i + 1].split('x')); del args[i:i + 2]
if '--yaw' in args:
    i = args.index('--yaw'); yaw = float(args[i + 1]); del args[i:i + 2]
spin = '--spinball' in args
if spin: args.remove('--spinball')
out, files = args[0], args[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
x = 0.0
for f in files:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    if spin:
        for o in new:
            if o.name.startswith('ball'): o.rotation_mode = 'XYZ'; o.rotation_euler = (1.4, 0.6, 0)
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in new if o.type == 'MESH' for c in o.bound_box]
    if not pts: continue
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    h = hi.z - lo.z; s = 1.0 / max(h, hi.x - lo.x, hi.y - lo.y)
    piv = bpy.data.objects.new('piv', None); sc.collection.objects.link(piv)
    for r in roots: r.parent = piv; r.matrix_parent_inverse = piv.matrix_world.inverted()
    piv.location = (-(lo.x + hi.x) / 2 * s + x, -(lo.y + hi.y) / 2 * s, -lo.z * s)
    piv.scale = (s, s, s)
    piv.rotation_euler = (0, 0, 0)
    print(f, 'size', tuple(round(v, 2) for v in (hi - lo)))
    x += 1.25
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam)
cx = (x - 1.25) / 2
a = math.radians(yaw)
d = max(2.2, x * 1.05)
cam.location = (cx + math.sin(a) * d * 0.3, -d, 0.9 + d * 0.18)
cam.data.lens = 50
dirn = Vector((cx, 0, 0.45)) - cam.location
cam.rotation_euler = dirn.to_track_quat('-Z', 'Y').to_euler()
sc.camera = cam
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 3.5; sun.data.color = (1, 0.88, 0.72); sun.rotation_euler = (math.radians(55), math.radians(15), math.radians(-35))
fill = bpy.data.objects.new('fill', bpy.data.lights.new('fill', 'SUN')); sc.collection.objects.link(fill)
fill.data.energy = 1.2; fill.data.color = (0.6, 0.75, 1); fill.rotation_euler = (math.radians(60), 0, math.radians(150))
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs[0].default_value = (0.55, 0.62, 0.7, 1); w.node_tree.nodes['Background'].inputs[1].default_value = 0.6
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = samples; sc.cycles.use_denoising = True
sc.render.resolution_x, sc.render.resolution_y = size
sc.view_settings.view_transform = 'AgX'
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
