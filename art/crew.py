# Work-Crew Roller and its barricade (Skyharbor enemies).
#   blender --background --python art/crew.py [-- crew_roller crew_barricade] [--preview]
# Writes /tmp/claude-0/art/crew_roller.glb and crew_barricade.glb; copy them to godot/models/.
# Named parts the game animates:
#   crew_roller:    "ball" (rolls), "cap" (hard hat + visor, faces travel), "arm" (the riveter arm, swings)
#   crew_barricade: "lamp" (warning lamp, blinks)
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else 'art')
from blib import *
import bmesh
from mathutils import Vector, Matrix

OUT = '/tmp/claude-0/art'
os.makedirs(OUT, exist_ok=True)

def ico_bm(r, sub):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r); return bm

def orient_bm(bm, dirn):
    q = Vector((0, 1, 0)).rotation_difference(Vector(dirn).normalized())
    bmesh.ops.transform(bm, matrix=q.to_matrix().to_4x4(), verts=bm.verts); return bm

def dome_bm(r, seg=32, rings=10):
    bm = bm_sphere(r, seg, rings * 2)
    for v in list(bm.verts):
        if v.co.y < -1e-4: v.co.y = 0.0
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    return bm

# ======================= WORK-CREW ROLLER =======================
def crew_roller():
    reset()
    core = mat('crew_core', 0x4a5260, 0.8, 0.35)
    plate = mat('crew_plate', 0xe39a1c, 0.6, 0.35)
    stripe = mat('crew_stripe', 0x1e2228, 0.6, 0.45)
    hat = mat('crew_hat', 0xf2c21a, 0.3, 0.3, coat=0.6)
    dark = mat('crew_dark', 0x2c333c, 0.75, 0.4)
    brass = mat('crew_brass', 0xd9a441, 0.9, 0.3)
    eye = glowmat('crew_eye', 0xffb020, 5)
    root = empty('CrewRoller')
    ball = empty('ball', root, at=(0, 0.5, 0))
    C = Vector((0, 0.5, 0))
    part('crew_core', ico_bm(0.42, 2), core, ball, at=tuple(C), smooth=False)
    # orange armour plates with black hazard bands between them
    ico = ico_bm(0.45, 1)
    for i, f in enumerate(ico.faces):
        n = f.normal.copy(); c = f.calc_center_median()
        bm = bm_cyl(0.12, 0.1, 0.05, 6); orient_bm(bm, n)
        part(f'crew_plate_{i}', bm, plate if i % 3 else stripe, ball, at=tuple(C + c.normalized() * 0.42), bevel=0.01, smooth=False)
    ico.free()
    for k, a in enumerate((0.0, math.pi / 2)):
        part(f'crew_band_{k}', bm_torus(0.47, 0.035, 48, 8), brass, ball, at=tuple(C), rot=(0, 0, a) if k else (math.pi / 2, 0, 0))
    # stubby rivet studs instead of spikes: this crew builds, it doesn't stab
    ico = ico_bm(0.45, 0)
    for i, v in enumerate(ico.verts):
        n = v.co.normalized()
        bm = bm_cyl(0.07, 0.05, 0.08, 8); orient_bm(bm, n)
        part(f'crew_stud_{i}', bm, dark, ball, at=tuple(C + n * 0.47), bevel=0.01)
    ico.free()
    # cap: frame around the top half with a hard hat, a visor and the riveter arm
    cap = empty('cap', root, at=(0, 0.5, 0))
    def arc_bm(R, r, arc, seg=24):
        bm = bm_torus(R, r, seg, 10, arc)
        M = Matrix.Rotation(-math.pi / 2, 4, 'Y') @ Matrix.Rotation(math.pi / 2, 4, 'X') @ Matrix.Rotation(-arc / 2, 4, 'Z')
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts); return bm
    part('crew_frame', arc_bm(0.53, 0.06, math.pi * 1.1), dark, cap, at=(0, 0.5, 0))
    part('crew_visor', arc_bm(0.6, 0.04, math.pi * 0.42), eye, cap, at=(0, 0.6, 0.0))
    # hard hat: dome, brim and a ridge
    part('crew_hat', dome_bm(0.36, 32, 8), hat, cap, at=(0, 0.98, -0.02), scale=(1, 0.72, 1.08), smooth=True)
    part('crew_hat_brim', bm_cyl(0.46, 0.46, 0.04, 32), hat, cap, at=(0, 0.98, 0.02), scale=(1, 1, 1.12), bevel=0.012)
    part('crew_hat_ridge', bm_box(0.08, 0.06, 0.7), hat, cap, at=(0, 1.22, -0.02), rounded=0.025)
    part('crew_hat_lamp', bm_cyl(0.07, 0.08, 0.08, 16), dark, cap, at=(0, 1.1, 0.33), rot=(math.pi / 2, 0, 0))
    part('crew_hat_lamp_glass', bm_cyl(0.055, 0.055, 0.02, 16), eye, cap, at=(0, 1.1, 0.38), rot=(math.pi / 2, 0, 0))
    part('crew_neck', bm_cyl(0.16, 0.2, 0.12, 16), dark, cap, at=(0, 0.92, 0), bevel=0.01)
    # riveter arm on the right side (pivot at the shoulder)
    arm = empty('arm', cap, at=(-0.52, 0.72, 0.05), parent_at=(0, 0.5, 0))
    part('crew_shoulder', bm_sphere(0.09, 16, 10), brass, arm, at=(-0.52, 0.72, 0.05))
    part('crew_upper', bm_cyl(0.05, 0.05, 0.32, 12), dark, arm, at=(-0.58, 0.6, 0.18), rot=(1.0, 0, 0), bevel=0.006)
    part('crew_riveter', bm_box(0.12, 0.14, 0.32), plate, arm, at=(-0.6, 0.52, 0.38), rounded=0.03)
    part('crew_riveter_tip', bm_cyl(0.035, 0.025, 0.14, 10), brass, arm, at=(-0.6, 0.52, 0.58), rot=(math.pi / 2, 0, 0))
    empty('crew_muzzle', arm, at=(-0.6, 0.52, 0.66), parent_at=(-0.52, 0.72, 0.05))
    # a plank carried on the back
    part('crew_plank', bm_box(0.9, 0.08, 0.18), plate, cap, at=(0, 0.82, -0.5), rot=(0.35, 0, 0), rounded=0.02)
    part('crew_plank_stripe', bm_box(0.2, 0.085, 0.185), stripe, cap, at=(0.2, 0.82, -0.5), rot=(0.35, 0, 0), rounded=0.02)
    part('crew_plank_stripe2', bm_box(0.2, 0.085, 0.185), stripe, cap, at=(-0.2, 0.82, -0.5), rot=(0.35, 0, 0), rounded=0.02)
    print('crew_roller tris', tri_count(root))
    export(f'{OUT}/crew_roller.glb', root)
    return root

# ======================= BARRICADE =======================
def crew_barricade():
    reset()
    plank = mat('barr_plank', 0xe39a1c, 0.2, 0.5)
    stripe = mat('barr_stripe', 0x1e2228, 0.3, 0.5)
    steel = mat('barr_steel', 0x7a8590, 0.85, 0.35)
    dark = mat('barr_dark', 0x2c333c, 0.75, 0.4)
    lamp = glowmat('barr_lamp', 0xff6a1a, 6)
    root = empty('CrewBarricade')
    W = 2.4
    # two A-frame legs
    for s in (-1, 1):
        x = s * (W / 2 - 0.15)
        for d in (-1, 1):
            part(f'barr_leg_{s}_{d}', bm_box(0.08, 1.25, 0.08), steel, root, at=(x, 0.6, d * 0.18), rot=(d * 0.28, 0, 0), rounded=0.02)
        part(f'barr_foot_{s}', bm_box(0.12, 0.06, 0.9), dark, root, at=(x, 0.03, 0), rounded=0.02)
        part(f'barr_brace_{s}', bm_box(0.06, 0.06, 0.4), steel, root, at=(x, 0.45, 0), rounded=0.015)
    # striped planks (stripes are separate diagonal blocks laid onto the planks)
    for k, y in enumerate((0.62, 1.05)):
        part(f'barr_plank_{k}', bm_box(W, 0.26, 0.07), plank, root, at=(0, y, 0.2), rounded=0.02)
        part(f'barr_plank_b{k}', bm_box(W, 0.26, 0.07), plank, root, at=(0, y, -0.2), rounded=0.02)
        for i in range(6):
            x = -W / 2 + 0.3 + i * 0.38
            for z in (0.24, -0.24):
                part(f'barr_stripe_{k}_{i}_{z}', bm_box(0.13, 0.3, 0.012), stripe, root, at=(x, y, z), rot=(0, 0, 0.6))
    # bolts and the warning lamp on top
    for s in (-1, 1):
        for y in (0.62, 1.05):
            part(f'barr_bolt_{s}_{y}', bm_cyl(0.03, 0.03, 0.5, 8), steel, root, at=(s * (W / 2 - 0.15), y, 0), rot=(math.pi / 2, 0, 0))
    part('barr_lamp_base', bm_cyl(0.1, 0.12, 0.1, 16), dark, root, at=(W / 2 - 0.15, 1.27, 0), bevel=0.01)
    part('lamp', dome_bm(0.09, 16, 6), lamp, root, at=(W / 2 - 0.15, 1.32, 0))
    print('crew_barricade tris', tri_count(root))
    export(f'{OUT}/crew_barricade.glb', root)
    return root

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
which = [a for a in args if not a.startswith('-')] or ['crew_roller', 'crew_barricade']
for w in which:
    r = globals()[w]()
    if '--preview' in args:
        f, l = ((1.7, 1.5, 2.3), (0, 0.6, 0)) if w == 'crew_roller' else ((2.2, 1.6, 3.2), (0, 0.6, 0))
        preview(f'{OUT}/{w}.png', r, cam_from=f, look=l, lens=50, samples=24, size=(600, 600))
