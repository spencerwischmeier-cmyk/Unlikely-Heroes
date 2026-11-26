# Skyharbor citizens for the panic pass: godot/models/citizens/<name>.glb (rigged, ~1.6-1.9 m, facing +Z, 512 px textures).
#   /tmp/claude-0/bpyenv/bin/python art/meshy/build_citizens.py [name...]
# Source: citizens.py (t2i -> i23d 8k tris -> rig 1.7 m -> one animation batch, ids in citizens.py ANIMS).
# Clips: idle, run, run2, wave, carry, look, cower, hop, shout, sneak (all in place: the hips' travel is removed).
import bpy, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_chars import shrink_textures, MODELS, SRC

NAMES = ['cit_frog', 'cit_bird', 'cit_mole', 'cit_goat']
HEIGHT = {'cit_frog': 1.55, 'cit_bird': 1.95, 'cit_mole': 1.35, 'cit_goat': 1.75}
CLIPS = {'Idle': 'idle', 'RunFast': 'run', 'Run_02': 'run2', 'Wave_for_Help_1': 'wave', 'Carry_Heavy_Object_Walk': 'carry',
         'Look_Around_Dumbfounded': 'look', 'Crouch_and_Step_Back': 'cower', 'Hop_with_Arms_Raised': 'hop',
         'Shouting_Angrily': 'shout', 'Cautious_Crouch_Walk_Forward': 'sneak'}

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

def build(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=f'{SRC}/{name}_rigged.glb')
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    base = set(bpy.data.actions)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f'{SRC}/{name}_anim.glb')
    for o in set(bpy.data.objects) - before: bpy.data.objects.remove(o)
    for a in base:
        if a.name in bpy.data.actions: bpy.data.actions.remove(a)
    A = bpy.data.actions
    print(name, 'actions', [a.name for a in A])
    for a in list(A):
        key = next((k for k in CLIPS if a.name.startswith(k) or a.name.split('|')[-1].startswith(k)), None)
        if key and CLIPS[key] not in [x.name for x in A]: a.name = CLIPS[key]
        else: A.remove(a)
    for a in A:
        flatten_hips(a); a.use_fake_user = True
    print(name, 'clips', sorted((a.name, tuple(round(x) for x in a.frame_range)) for a in A))
    # scale the whole rig to the character's height (the rig is 1.7 m)
    s = HEIGHT[name] / 1.7
    arm.scale = (arm.scale[0] * s, arm.scale[1] * s, arm.scale[2] * s)
    bpy.context.view_layer.objects.active = arm
    arm.name = name
    arm.animation_data_create(); arm.animation_data.action = None
    print(name, 'bones', [b.name for b in arm.data.bones][:60])
    shrink_textures(512)
    os.makedirs(f'{MODELS}/citizens', exist_ok=True)
    out = f'{MODELS}/citizens/{name}.glb'
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='ACTIONS', export_force_sampling=True,
                              export_anim_single_armature=True, export_cameras=False, export_lights=False)
    print('wrote', out, os.path.getsize(out) // 1024, 'KB')

for n in [a for a in sys.argv[1:] if not a.startswith('-')] or NAMES: build(n)
