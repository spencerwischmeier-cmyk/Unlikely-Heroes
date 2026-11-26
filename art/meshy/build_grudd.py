# Foreman Grudd for the cutscenes: godot/models/chars/grudd.glb (4 m tall, rigged, with clips).
#   /tmp/claude-0/bpyenv/bin/python art/meshy/build_grudd.py
# Source: chars.py t2i/i23d/rig "grudd2" and one animation batch (action ids 0,311,308,409,26,119,315,403,181,25).
# Clips: idle, talk, talk_big, wag, stomp, walk (in place), hip, cheer, defeat, agree.
# Extra nodes: "stack_top" (smoke comes out here) and "mouth" (the loudspeaker), both on the Head bone.
import bpy, os, sys
import numpy as np
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_chars import shrink_textures, MODELS, SRC

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f'{SRC}/grudd2_rigged.glb')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
body = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == arm or (o.type == 'MESH' and o.find_armature() == arm)]
base_actions = set(bpy.data.actions)
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=f'{SRC}/grudd2_anim.glb')
for o in set(bpy.data.objects) - before: bpy.data.objects.remove(o)
for a in base_actions:
    if a.name in bpy.data.actions: bpy.data.actions.remove(a)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Icosphere')]: bpy.data.objects.remove(o)
A = bpy.data.actions

def all_fcurves(act):
    if hasattr(act, 'fcurves') and len(act.fcurves): return list(act.fcurves)
    out = []
    for layer in getattr(act, 'layers', []):
        for strip in layer.strips:
            for cb in strip.channelbags: out += list(cb.fcurves)
    return out

def flatten_hips(act, axes=(0, 2)):
    for fc in all_fcurves(act):
        if fc.data_path == 'pose.bones["Hips"].location' and fc.array_index in axes:
            v0 = fc.keyframe_points[0].co[1] if len(fc.keyframe_points) else 0
            for k in fc.keyframe_points: k.co[1] = v0; k.handle_left[1] = v0; k.handle_right[1] = v0

names = {'Idle': 'idle', 'Stand_Talking_Angry': 'talk', 'Talk_Passionately': 'talk_big', 'Finger_Wag_No': 'wag',
         'Angry_Stomp': 'stomp', 'Slow_Orc_Walk': 'walk', 'Hand_on_Hip_Gesture': 'hip', 'Victory_Fist_Pump': 'cheer',
         'Electrocuted_Fall': 'defeat', 'Agree_Gesture': 'agree'}
for a in list(A):
    if a.name in names: a.name = names[a.name]
    elif a.name not in names.values(): A.remove(a)
flatten_hips(A['walk'])
for a in A: a.use_fake_user = True
print('clips', sorted((a.name, tuple(round(x) for x in a.frame_range)) for a in A))

# the concept's modelled smoke puff is cut off the stack (the game draws real smoke at "stack_top")
import bmesh
mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
bpy.context.view_layer.update()
mw = mesh.matrix_world
bm = bmesh.new(); bm.from_mesh(mesh.data)
cut = [v for v in bm.verts if (mw @ v.co).z > 3.6]
print('smoke verts cut', len(cut))
bmesh.ops.delete(bm, geom=cut, context='VERTS'); bm.to_mesh(mesh.data); bm.free(); mesh.data.update()

# marker nodes on the Head bone: the smokestack top (highest point) and the loudspeaker mouth (front-most point near head height)
mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
bpy.context.view_layer.update()
vs = np.array([(mesh.matrix_world @ v.co)[:] for v in mesh.data.vertices])
top = vs[vs[:, 2].argmax()]
zmax = vs[:, 2].max()
head = vs[(vs[:, 2] > 3.0) & (vs[:, 2] < 3.35) & (np.abs(vs[:, 0]) < 0.4)]
mouth = head[head[:, 1].argmin()]
print('stack top', top.round(2), 'mouth', mouth.round(2))
for nm, p in (('stack_top', top), ('mouth', mouth)):
    e = bpy.data.objects.new(nm, None); bpy.context.scene.collection.objects.link(e)
    e.parent = arm; e.parent_type = 'BONE'; e.parent_bone = 'Head'
    bpy.context.view_layer.update()
    e.matrix_world = e.matrix_world.__class__.Translation(Vector(p))
arm.name = 'Grudd'
arm.animation_data_create(); arm.animation_data.action = None
shrink_textures()
out = f'{MODELS}/chars/grudd.glb'
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_anim_single_armature=True, export_cameras=False, export_lights=False)
print('wrote', out, os.path.getsize(out) // 1024, 'KB')
