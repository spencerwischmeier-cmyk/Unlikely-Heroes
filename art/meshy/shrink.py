import bpy, sys, glob, os
out='/home/user/unlikely-heroes/godot/models/docks/'
for f in sorted(glob.glob('/tmp/claude-0/meshy/props/*.glb')):
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    for im in list(bpy.data.images): bpy.data.images.remove(im)
    for me in list(bpy.data.meshes): bpy.data.meshes.remove(me)
    bpy.ops.import_scene.gltf(filepath=f)
    for im in bpy.data.images:
        if im.size[0] > 1024: im.scale(1024, 1024)
    name=os.path.basename(f)
    bpy.ops.export_scene.gltf(filepath=out+name, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=88, use_selection=False)
    print('done', name, os.path.getsize(out+name)//1024, 'KB')
