import sys, math; sys.path.insert(0, '/tmp/claude-0/art')
from blib import *
import bmesh
from mathutils import Vector

def ico_bm(r, sub):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r); return bm

def orient_bm(bm, dirn):
    q = Vector((0, 1, 0)).rotation_difference(Vector(dirn).normalized())
    bmesh.ops.transform(bm, matrix=q.to_matrix().to_4x4(), verts=bm.verts); return bm

# ======================= DRONE (sidekick) =======================
def drone():
    reset()
    shell = mat('drone_shell', 0xe9edf1, 0.6, 0.22)
    orange = mat('drone_band', 0xff6a1a, 0.3, 0.4)
    dark = mat('drone_dark', 0x34404c, 0.75, 0.4)
    glass = mat('drone_glass', 0x062028, 0.1, 0.05, coat=1)
    pupil = glowmat('drone_pupil', 0x3ff6ff, 2.5)
    ringG = glowmat('drone_glow', 0x40f0ff, 7)
    tip = glowmat('drone_tip', 0xffa030, 5)
    root = empty('Drone')
    # slightly egg-shaped shell with a recessed eye socket
    sdf_blob('drone_body', [(0, 0, 0, 0.26, 0.25, 0.26), (0, -0.04, -0.06, 0.2, 0.2, 0.22)], shell, root, k=0.06, seg=48, rings=32)
    part('drone_band', bm_torus(0.262, 0.03, 48, 12), orange, root)
    part('drone_band2', bm_torus(0.2, 0.018, 40, 8), dark, root, at=(0, 0.17, 0), rot=(math.pi / 2, 0, 0))
    part('drone_eye_ring', bm_torus(0.12, 0.032, 40, 16), dark, root, at=(0, 0, 0.225))
    part('drone_eye_glass', bm_sphere(0.115, 32, 20), glass, root, at=(0, 0, 0.2), scale=(1, 1, 0.5))
    part('drone_pupil', bm_cyl(0.055, 0.055, 0.004, 32), pupil, root, at=(0.0, 0.0, 0.262), rot=(math.pi / 2, 0, 0), smooth=False)
    part('drone_pupil_ring', bm_torus(0.078, 0.007, 32, 6), ringG, root, at=(0, 0, 0.26))
    for s, n in ((-1, 'R'), (1, 'L')):
        part(f'drone_arm_{n}', bm_cyl(0.025, 0.025, 0.22, 10), dark, root, at=(0.32 * s, 0, -0.02), rot=(0, 0, math.pi / 2))
        part(f'drone_pod_{n}', bm_cyl(0.07, 0.095, 0.09, 28), shell, root, at=(0.44 * s, 0, -0.02), bevel=0.012)
        part(f'drone_pod_ring_{n}', bm_torus(0.1, 0.012, 32, 8), ringG, root, at=(0.44 * s, -0.045, -0.02), rot=(math.pi / 2, 0, 0))
        part(f'drone_fin_{n}', bm_box(0.02, 0.12, 0.14), orange, root, at=(0.44 * s, 0.08, -0.07), rot=(0.4, 0, 0), rounded=0.006)
        empty(f'drone_jet_{n}', root, at=(0.44 * s, -0.1, -0.02))
    part('drone_antenna', bm_cyl(0.012, 0.008, 0.2, 8), dark, root, at=(0.06, 0.32, -0.04), rot=(0, 0, -0.25))
    part('drone_antenna_tip', bm_sphere(0.025, 12, 8), tip, root, at=(0.085, 0.42, -0.04))
    empty('drone_eye', root, at=(0, 0, 0.3))
    print('drone tris', tri_count(root))
    export('/tmp/claude-0/art/drone.glb', root)
    return root

# ======================= SCRAP ROLLER =======================
def roller():
    reset()
    core = mat('roller_core', 0x6a5a48, 0.8, 0.35)
    plate = mat('roller_plate', 0x8a7a62, 0.85, 0.3)
    accent = mat('roller_accent', 0x9b1f2a, 0.5, 0.4)
    dark = mat('roller_dark', 0x34404c, 0.75, 0.4)
    eye = glowmat('roller_eye', 0xff2a2a, 5)
    root = empty('Roller')
    ball = empty('ball', root, at=(0, 0.55, 0))
    C = Vector((0, 0.55, 0))
    # armoured core: faceted inner ball plus raised hex plates
    o = part('roller_core', ico_bm(0.47, 2), core, ball, at=tuple(C), smooth=False)
    ico = ico_bm(0.5, 1)
    for i, f in enumerate(ico.faces):
        n = f.normal.copy(); c = f.calc_center_median()
        bm = bm_cyl(0.13, 0.11, 0.06, 6)
        orient_bm(bm, n)
        part(f'roller_plate_{i}', bm, plate, ball, at=tuple(C + c.normalized() * 0.47), bevel=0.01, smooth=False)
    ico.free()
    ico = ico_bm(0.5, 0)
    for i, v in enumerate(ico.verts):
        n = v.co.normalized()
        bm = bm_cone(0.085, 0.3, 8); orient_bm(bm, n)
        part(f'roller_spike_{i}', bm, dark, ball, at=tuple(C + n * 0.6), smooth=False, bevel=0.005)
        bm = bm_cyl(0.11, 0.09, 0.05, 8); orient_bm(bm, n)
        part(f'roller_spike_base_{i}', bm, accent, ball, at=tuple(C + n * 0.48), bevel=0.008)
    ico.free()
    part('roller_band', bm_torus(0.52, 0.045, 48, 10), accent, ball, at=tuple(C))
    # visor cap that always faces travel direction
    cap = empty('cap', root, at=(0, 0.55, 0))
    from mathutils import Matrix
    def arc_bm(R, r, arc, seg=24):
        bm = bm_torus(R, r, seg, 10, arc)
        M = Matrix.Rotation(-math.pi / 2, 4, 'Y') @ Matrix.Rotation(math.pi / 2, 4, 'X') @ Matrix.Rotation(-arc / 2, 4, 'Z')
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts); return bm
    part('roller_visor_frame', arc_bm(0.575, 0.085, math.pi * 0.7), dark, cap, at=(0, 0.6, 0))
    part('roller_visor', arc_bm(0.655, 0.045, math.pi * 0.5), eye, cap, at=(0, 0.6, 0.0))
    empty('roller_eye', cap, at=(0, 0.6, 0.62), parent_at=(0, 0.55, 0))
    print('roller tris', tri_count(root))
    export('/tmp/claude-0/art/roller.glb', root)
    return root

# ======================= RIVET HORNET =======================
def hornet():
    reset()
    shell = mat('hornet_shell', 0x2d333d, 0.85, 0.32)
    accent = mat('hornet_accent', 0x9b1f2a, 0.5, 0.4)
    dark = mat('hornet_dark', 0x1c2027, 0.8, 0.4)
    brass = mat('hornet_brass', 0xd9a441, 0.9, 0.3)
    wingM = mat('hornet_wing', 0x3a4250, 0.85, 0.28)
    eye = glowmat('hornet_eye', 0xff2a2a, 6)
    thr = glowmat('hornet_thruster', 0xff7030, 5)
    root = empty('Hornet')
    inner = empty('inner', root)
    # body: armoured head + abdomen
    sdf_blob('hornet_body', [(0, 0, 0.05, 0.6, 0.45, 0.62), (0, 0.05, -0.55, 0.38, 0.34, 0.5)], shell, inner, k=0.15, seg=56, rings=40, center=(0, 0, -0.1))
    sdf_blob('hornet_jaw', [(0, -0.2, 0.25, 0.42, 0.22, 0.42), (0.18, -0.28, 0.45, 0.1, 0.08, 0.16), (-0.18, -0.28, 0.45, 0.1, 0.08, 0.16)], accent, inner, k=0.1, seg=40, rings=28, center=(0, -0.2, 0.25))
    for i in range(3):
        part(f'hornet_stripe_{i}', bm_torus(0.36 - i * 0.04, 0.03, 40, 8), accent, inner, at=(0, 0.05, -0.38 - i * 0.18), scale=(1.05, 0.95, 1))
    part('hornet_visor_frame', bm_box(0.62, 0.16, 0.12), dark, inner, at=(0, 0.06, 0.6), rounded=0.04)
    part('hornet_eye', bm_box(0.52, 0.08, 0.06), eye, inner, at=(0, 0.06, 0.66), rounded=0.03)
    empty('hornet_eye_point', inner, at=(0, 0.06, 0.72))
    for s, n in ((-1, 'R'), (1, 'L')):
        part(f'hornet_wing_{n}', bm_box(1.15, 0.05, 0.5), wingM, inner, at=(0.85 * s, 0.05, -0.15), rot=(0, 0.25 * s, 0.3 * s), rounded=0.02)
        part(f'hornet_wing_edge_{n}', bm_box(1.0, 0.03, 0.06), accent, inner, at=(0.86 * s, 0.07, 0.1), rot=(0, 0.25 * s, 0.3 * s), rounded=0.012)
        part(f'hornet_gun_{n}', bm_cyl(0.065, 0.055, 0.7, 12), dark, inner, at=(0.55 * s, -0.2, 0.4), rot=(math.pi / 2, 0, 0), bevel=0.008)
        part(f'hornet_gun_ring_{n}', bm_torus(0.07, 0.015, 16, 6), brass, inner, at=(0.55 * s, -0.2, 0.62))
        part(f'hornet_pod_{n}', bm_cyl(0.1, 0.13, 0.25, 16), dark, inner, at=(0.85 * s, -0.12, -0.2), bevel=0.01)
        part(f'hornet_nozzle_{n}', bm_cyl(0.085, 0.085, 0.03, 16), thr, inner, at=(0.85 * s, -0.25, -0.2))
        empty(f'hornet_jet_{n}', inner, at=(0.85 * s, -0.3, -0.2))
    for i in range(5):
        a = (i / 4 - 0.5) * 1.6
        bm = bm_cone(0.06, 0.38, 8); orient_bm(bm, (math.sin(a) * 0.5, 1, -0.45))
        part(f'hornet_spike_{i}', bm, accent, inner, at=(math.sin(a) * 0.38, 0.5, -0.05 + math.cos(a) * -0.1), bevel=0.004)
    bm = bm_cone(0.08, 0.45, 10); orient_bm(bm, (0, -0.25, -1))
    part('hornet_stinger', bm, dark, inner, at=(0, -0.02, -1.15), bevel=0.004)
    print('hornet tris', tri_count(root))
    export('/tmp/claude-0/art/hornet.glb', root)
    return root

which = [a for a in sys.argv[1:] if not a.startswith('-')] or ['drone', 'roller', 'hornet']
for w in which:
    if w.startswith('-'): continue
    r = globals()[w]()
    if '--preview' in sys.argv:
        cams = {'drone': ((0.9, 0.5, 1.1), (0, 0, 0), 55), 'roller': ((1.6, 1.4, 2.2), (0, 0.55, 0), 50), 'hornet': ((2.4, 1.5, 3.2), (0, 0, -0.2), 45)}
        f, l, lens = cams[w]
        if w != 'roller':  # lift flyers off the floor for the preview
            r.location = gv(0, 1.2, 0); l = (l[0], l[1] + 1.2, l[2]); f = (f[0], f[1] + 1.2, f[2])
        preview(f'/tmp/claude-0/art/{w}.png', r, cam_from=f, look=l, lens=lens, samples=32, size=(700, 700))
