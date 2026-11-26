# Shrink the panic props (panic_props.py) into godot/models/panic/ with 1k JPEG textures.
#   /tmp/claude-0/bpyenv/bin/python art/meshy/shrink_panic.py
import bpy, glob, os
out = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'godot', 'models', 'panic')) + '/'
os.makedirs(out, exist_ok=True)
for f in sorted(glob.glob('/tmp/claude-0/meshy/panic/*.glb')):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=f)
    for im in bpy.data.images:
        if im.size[0] > 1024: im.scale(1024, 1024)
    name = os.path.basename(f)
    print('meshes', name, [(o.name, len(o.data.polygons), [m.name for m in o.data.materials]) for o in bpy.data.objects if o.type == 'MESH'])
    bpy.ops.export_scene.gltf(filepath=out + name, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=88, use_selection=False)
    print('done', name, os.path.getsize(out + name) // 1024, 'KB')
