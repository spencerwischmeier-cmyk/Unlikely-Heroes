import bpy, sys, math
from mathutils import Vector, Matrix
M='/tmp/claude-0/meshy/'
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
for a in list(bpy.data.actions): bpy.data.actions.remove(a)
bpy.ops.import_scene.gltf(filepath=M+'vesk_rigged.glb')
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
keep_objs=set(bpy.data.objects)
base_actions=set(bpy.data.actions)
for f in ('anim_set1.glb','anim_set2.glb'):
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=M+f)
    for o in set(bpy.data.objects)-before: bpy.data.objects.remove(o)
for a in base_actions:
    if a.name in bpy.data.actions: bpy.data.actions.remove(a)
print('actions', [a.name for a in bpy.data.actions])
A=bpy.data.actions
def strip_root(act, keep_y=True):
    # remove horizontal root motion from the hips (glTF Y-up was converted: Blender Z up; hips location is in armature space)
    for fc in list(act.fcurves) if hasattr(act,'fcurves') else []:
        pass
def all_fcurves(act):
    out=[]
    if hasattr(act,'fcurves') and len(act.fcurves): return list(act.fcurves)
    for layer in getattr(act,'layers',[]):
        for strip in layer.strips:
            for cb in strip.channelbags: out+=list(cb.fcurves)
    return out
def flatten_hips(act, axes=(0,2)):
    for fc in all_fcurves(act):
        if fc.data_path=='pose.bones["mixamorig:Hips"].location' and fc.array_index in axes:
            # bone-local: hips Y is usually up; zero the two horizontal axes to their first value
            v0=fc.keyframe_points[0].co[1] if len(fc.keyframe_points) else 0
            for k in fc.keyframe_points:
                k.co[1]=v0; k.handle_left[1]=v0; k.handle_right[1]=v0
def dup_range(src, name, f0, f1):
    a=src.copy(); a.name=name
    for fc in all_fcurves(a):
        for i in reversed(range(len(fc.keyframe_points))):
            c=fc.keyframe_points[i].co[0]
            if c<f0-0.01 or c>f1+0.01: fc.keyframe_points.remove(fc.keyframe_points[i], fast=True)
        for k in fc.keyframe_points: k.co[0]-=f0; k.handle_left[0]-=f0; k.handle_right[0]-=f0
    return a
names={'Idle_3':'idle','run_fast_3_inplace':'run','Regular_Jump':'jump_full','Fall1':'fall','Lean_Forward_Sprint':'dash',
 'Jump_with_Arms_Open':'glide_full','Stand_on_Pole_and_Balance':'grind','Rope_Hang_Idle':'swing','Heavy_Hammer_Swing':'melee',
 'Hit_Reaction':'hurt','Run_and_Shoot':'run_shoot','Idle':'idle_alt','Basic_Jump':'jump_basic','Run_02':'run_alt','Lean_Forward_Sprint_inplace':'dash_inplace'}
for old,new in names.items():
    if old in A: A[old].name=new
for n in ('jump_full','glide_full','jump_basic','run_alt','dash'): 
    if n in A: flatten_hips(A[n])
for n in ('jump_full','glide_full'): flatten_hips(A[n],(1,))
# hip channel layout check
for fc in all_fcurves(A['jump_full']):
    if 'Hips' in fc.data_path and fc.data_path.endswith('location'):
        ys=[k.co[1] for k in fc.keyframe_points]; print('hips loc', fc.array_index, round(min(ys),2), round(max(ys),2))
jf=A['jump_full']; r=jf.frame_range; print('jump range', r)
dup_range(jf,'jump', r[0]+8, r[0]+22)
dup_range(A['jump_basic'],'land', A['jump_basic'].frame_range[1]-26, A['jump_basic'].frame_range[1]-8)
gf=A['glide_full']; g=gf.frame_range; dup_range(gf,'glide', g[0]+30, g[0]+50)
for n in ('jump_full','glide_full','jump_basic','idle_alt'):
    if n in A: A.remove(A[n])
for a in A: a.use_fake_user=True
print('final', sorted((a.name, tuple(round(x) for x in a.frame_range)) for a in A))
# gun bone in the right hand
bpy.context.view_layer.objects.active=arm
bpy.ops.object.mode_set(mode='EDIT')
eb=arm.data.edit_bones
hand=eb['mixamorig:RightHand']; mid=eb.get('mixamorig:RightHandMiddle1')
g=eb.new('gun'); g.parent=hand
p=(hand.head+ (mid.head if mid else hand.tail))*0.5
g.head=p; g.tail=p+(hand.tail-hand.head).normalized()*0.12; g.roll=hand.roll
g.use_deform=False
bpy.ops.object.mode_set(mode='OBJECT')
arm.name='Vesk'
REN={'Hips':'pelvis','Spine':'spine0','Spine1':'spine','Spine2':'chest','Neck':'neck','Head':'head',
 'LeftUpLeg':'thigh.L','LeftLeg':'shin.L','LeftFoot':'foot.L','RightUpLeg':'thigh.R','RightLeg':'shin.R','RightFoot':'foot.R'}
for a in A:
    for fc in all_fcurves(a):
        for o,n in REN.items():
            key='pose.bones["mixamorig:%s"]' % o
            if fc.data_path.startswith(key): fc.data_path=fc.data_path.replace(key,'pose.bones["%s"]' % n); break
for o,n in REN.items():
    b=arm.data.bones.get('mixamorig:'+o)
    if b: b.name=n
# re-check paths after Blender's own rename pass
bad=[fc.data_path for a in A for fc in all_fcurves(a) if any(fc.data_path.startswith('pose.bones["mixamorig:%s"]' % o) for o in REN)]
print('stale paths', len(bad))
mesh=[o for o in bpy.data.objects if o.type=='MESH'][0]
import mathutils
ws=[mesh.matrix_world @ v.co for v in mesh.data.vertices]
print('bounds z', min(v.z for v in ws), max(v.z for v in ws), 'y', min(v.y for v in ws), max(v.y for v in ws), 'x', min(v.x for v in ws), max(v.x for v in ws))

arm.animation_data_create(); arm.animation_data.action=None
bpy.ops.export_scene.gltf(filepath='/tmp/claude-0/meshy/build/vesk_new.glb', export_format='GLB', export_animation_mode='ACTIONS', export_force_sampling=True, export_anim_single_armature=True)
print('exported')
