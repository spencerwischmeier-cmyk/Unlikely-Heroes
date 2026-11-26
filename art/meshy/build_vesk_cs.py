# Cutscene acting clips for Vesk, as an animation-only GLB (godot/models/vesk_cs_anims.glb).
# vesk.glb itself is untouched: scripts/cutscene/vesk_actor.gd copies these clips into Vesk's
# AnimationPlayer at runtime (same armature "Vesk", same bone names, so the track paths match).
# Clips: two Meshy animation batches on the Vesk rig (rig_B.txt), library action ids
#   batch 0: 33 Chair Sit Idle M, 343 Sit and Drink, 53 Sit to Stand M, 364 Sit Arms Crossed,
#            313 Talk Hands Open, 314 Talk Right Hand Open, 311 Stand Talking Angry, 317 Shrug, 316 Headache Relief
#   batch 1: 36 Confused Scratch, 290 Wave One Hand, 29 Call Gesture, 47 Listening Gesture, 26 Angry Stomp,
#            342 Stand and Drink, 25 Agree Gesture, 333 Look Around Dumbfounded
# Run: /tmp/claude-0/bpyenv/bin/python build_vesk_cs.py <vesk_rigged.glb> <out.glb> <anim_batch.glb>...
import bpy, sys
args = sys.argv[1:]
RIG, OUT, ANIMS = args[0], args[1], args[2:]
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
for a in list(bpy.data.actions): bpy.data.actions.remove(a)
bpy.ops.import_scene.gltf(filepath=RIG)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
base_actions = set(bpy.data.actions)
for f in ANIMS:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    for o in set(bpy.data.objects) - before: bpy.data.objects.remove(o)
for a in base_actions:
    if a.name in bpy.data.actions: bpy.data.actions.remove(a)
A = bpy.data.actions
NAMES = [('chair_sit_idle', 'cs_sit'), ('sit_and_drink', 'cs_sit_drink'), ('sit_to_stand', 'cs_sit_stand'),
         ('arms_crossed', 'cs_sit_arms'), ('hands_open', 'cs_talk'), ('right_hand_open', 'cs_talk2'),
         ('talking_angry', 'cs_talk_angry'), ('shrug', 'cs_shrug'), ('headache', 'cs_facepalm'),
         ('confused_scratch', 'cs_scratch'), ('wave_one_hand', 'cs_wave'), ('call_gesture', 'cs_beckon'),
         ('listening', 'cs_listen'), ('angry_stomp', 'cs_stomp'), ('stand_and_drink', 'cs_drink'),
         ('agree', 'cs_nod'), ('dumbfounded', 'cs_look_around')]
for a in list(A):
    low = a.name.lower()
    for k, n in NAMES:
        if k in low: a.name = n; break
    else:
        A.remove(a)
def all_fcurves(act):
    if hasattr(act, 'fcurves') and len(act.fcurves): return list(act.fcurves)
    out = []
    for layer in getattr(act, 'layers', []):
        for strip in layer.strips:
            for cb in strip.channelbags: out += list(cb.fcurves)
    return out
def flatten_hips(act, axes=(0, 2)):
    for fc in all_fcurves(act):
        if fc.data_path == 'pose.bones["mixamorig:Hips"].location' and fc.array_index in axes and len(fc.keyframe_points):
            v0 = fc.keyframe_points[0].co[1]
            for k in fc.keyframe_points: k.co[1] = v0; k.handle_left[1] = v0; k.handle_right[1] = v0
# standing gestures must not drift away from their mark (sitting ones keep their hip motion)
for a in A:
    if not a.name.startswith('cs_sit'): flatten_hips(a)
for a in A: a.use_fake_user = True
REN = {'Hips': 'pelvis', 'Spine': 'spine0', 'Spine1': 'spine', 'Spine2': 'chest', 'Neck': 'neck', 'Head': 'head',
       'LeftUpLeg': 'thigh.L', 'LeftLeg': 'shin.L', 'LeftFoot': 'foot.L', 'RightUpLeg': 'thigh.R', 'RightLeg': 'shin.R', 'RightFoot': 'foot.R'}
for a in A:
    for fc in all_fcurves(a):
        for o, n in REN.items():
            key = 'pose.bones["mixamorig:%s"]' % o
            if fc.data_path.startswith(key): fc.data_path = fc.data_path.replace(key, 'pose.bones["%s"]' % n); break
for o, n in REN.items():
    b = arm.data.bones.get('mixamorig:' + o)
    if b: b.name = n
arm.name = 'Vesk'
# animation only: drop the meshes
for o in list(bpy.data.objects):
    if o.type == 'MESH': bpy.data.objects.remove(o)
print('final', sorted((a.name, tuple(round(x) for x in a.frame_range)) for a in A))
arm.animation_data_create(); arm.animation_data.action = None
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animation_mode='ACTIONS', export_force_sampling=True,
                          export_anim_single_armature=True, export_skins=True)
print('exported', OUT)
