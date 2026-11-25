"""The three extra blasters: Scatter Bloom, Thump Lobber and Seeker Hive.

Each is built around the same hand positions as the Arc Lancer (rear grip at (0,-0.13,-0.08), front hand at
(-0.03,-0.08,0.12), relative to the gun pivot), so the hero holds them all the same way. Coordinates are
gun-local: +Z is the firing direction. Each gets a 'muzzle_<id>' empty where shots come out.
Run: python weapons.py [--preview]
"""
import sys, math; sys.path.insert(0, '/tmp/claude-0/art')
from blib import *
from mathutils import Vector

OUT = '/tmp/claude-0/art/'
rx = (math.pi / 2, 0, 0)  # cylinders along +Z


def common():
    return dict(
        dark=mat('w_dark', 0x34404c, 0.75, 0.4),
        grip=mat('w_grip', 0x2a2f38, 0.3, 0.6),
        brass=mat('w_brass', 0xd9a441, 0.9, 0.3),
        white=mat('w_white', 0xf2f4f6, 0.6, 0.3),
    )


def grip_and_stock(c, root, stock_mat):
    part('grip', bm_box(0.08, 0.18, 0.09), c['grip'], root, at=(0, -0.14, -0.1), rot=(0.3, 0, 0), rounded=0.024)
    part('stock', bm_box(0.1, 0.12, 0.2), stock_mat, root, at=(0, -0.02, -0.28), rounded=0.03)
    part('trigger_guard', bm_torus(0.045, 0.01, 16, 6, math.pi), c['dark'], root, at=(0, -0.1, -0.03), rot=(0, math.pi / 2, 0))


def scatter():
    reset(); c = common()
    pink = mat('w_scatter_shell', 0xe2457a, 0.25, 0.4, coat=0.4)
    petal = mat('w_scatter_petal', 0xffb0cc, 0.1, 0.35, coat=0.5)
    glowP = glowmat('w_scatter_glow', 0xff6ab0, 6)
    root = empty('wpn_scatter')
    # chunky body with a fat drum
    part('body', bm_box(0.19, 0.18, 0.4), pink, root, at=(0, 0, 0.0), rounded=0.06)
    part('drum', bm_cyl(0.11, 0.11, 0.2, 24), c['white'], root, at=(0, -0.02, 0.2), rot=rx, rounded=0.02)
    for i in range(6):
        a = i / 6 * math.tau
        part(f'shell_{i}', bm_cyl(0.028, 0.028, 0.05, 12), glowP, root, at=(math.cos(a) * 0.075, -0.02 + math.sin(a) * 0.075, 0.31), rot=rx)
    # short wide barrel flaring into a flower-shaped muzzle
    part('barrel', bm_cyl(0.06, 0.08, 0.26, 24), c['dark'], root, at=(0, 0.0, 0.42), rot=rx)
    part('bell', bm_cyl(0.075, 0.13, 0.08, 24, cap=False), c['brass'], root, at=(0, 0.0, 0.58), rot=rx, bevel=0.006)
    for i in range(6):
        a = i / 6 * math.tau + math.pi / 6
        d = Vector((math.cos(a), math.sin(a), 0))
        bm = bm_sphere(1, 16, 10)
        p = part(f'petal_{i}', bm, petal, root, at=tuple(Vector((0, 0.0, 0.6)) + d * 0.14), scale=(0.07, 0.035, 0.05),
                 rot=(0, 0, a))
    part('bell_glow', bm_torus(0.07, 0.012, 24, 8), glowP, root, at=(0, 0, 0.615))
    part('rail', bm_box(0.05, 0.04, 0.34), c['brass'], root, at=(0, 0.11, 0.05), bevel=0.008)
    part('sight', bm_box(0.03, 0.05, 0.05), c['dark'], root, at=(0, 0.14, -0.06), bevel=0.006)
    grip_and_stock(c, root, pink)
    empty('muzzle_scatter', root, at=(0, 0.0, 0.66))
    return root


def lobber():
    reset(); c = common()
    green = mat('w_lobber_shell', 0x3f9f5a, 0.35, 0.45)
    olive = mat('w_lobber_band', 0xc6d64a, 0.2, 0.45)
    glowG = glowmat('w_lobber_glow', 0x9dff5a, 6)
    root = empty('wpn_lobber')
    part('body', bm_box(0.17, 0.17, 0.36), green, root, at=(0, 0, -0.02), rounded=0.05)
    # revolving drum of glowing bombs on the side
    part('drum', bm_cyl(0.13, 0.13, 0.14, 32), c['white'], root, at=(0.0, -0.01, 0.2), rot=rx, rounded=0.02)
    part('drum_band', bm_torus(0.13, 0.02, 32, 8), olive, root, at=(0, -0.01, 0.2))
    for i in range(5):
        a = i / 5 * math.tau + 0.3
        part(f'bomb_{i}', bm_sphere(0.035, 14, 10), glowG, root, at=(math.cos(a) * 0.085, -0.01 + math.sin(a) * 0.085, 0.275))
    # stubby wide barrel tipped slightly up, with a reinforced lip
    part('barrel', bm_cyl(0.075, 0.075, 0.3, 28), c['dark'], root, at=(0, 0.02, 0.42), rot=rx)
    part('lip', bm_torus(0.078, 0.022, 28, 8), olive, root, at=(0, 0.02, 0.57))
    part('lip_glow', bm_cyl(0.06, 0.06, 0.01, 24), glowG, root, at=(0, 0.02, 0.565), rot=rx)
    part('top_handle', bm_torus(0.07, 0.016, 20, 8, math.pi), c['dark'], root, at=(0, 0.1, 0.05), rot=(0, math.pi / 2, 0))
    part('vent_L', bm_box(0.02, 0.08, 0.14), olive, root, at=(0.095, 0.02, -0.04), bevel=0.006)
    part('vent_R', bm_box(0.02, 0.08, 0.14), olive, root, at=(-0.095, 0.02, -0.04), bevel=0.006)
    grip_and_stock(c, root, green)
    empty('muzzle_lobber', root, at=(0, 0.02, 0.6))
    return root


def seeker():
    reset(); c = common()
    amber = mat('w_seeker_shell', 0xffb21a, 0.35, 0.4, coat=0.3)
    navy = mat('w_seeker_pod', 0x2b3550, 0.5, 0.4)
    glowY = glowmat('w_seeker_glow', 0xffd040, 6)
    root = empty('wpn_seeker')
    part('body', bm_box(0.16, 0.16, 0.34), amber, root, at=(0, 0, -0.02), rounded=0.05)
    # hexagonal launcher pod with a honeycomb of tubes on the front
    pod = bm_cyl(0.17, 0.17, 0.3, 6)
    part('pod', pod, navy, root, at=(0, 0.05, 0.3), rot=(math.pi / 2, 0, math.pi / 6), bevel=0.012)
    part('pod_ring', bm_cyl(0.18, 0.18, 0.04, 6), amber, root, at=(0, 0.05, 0.43), rot=(math.pi / 2, 0, math.pi / 6), bevel=0.008)
    cells = [(0, 0)] + [(math.cos(i / 6 * math.tau) * 0.095, math.sin(i / 6 * math.tau) * 0.095) for i in range(6)]
    for i, (x, y) in enumerate(cells):
        part(f'tube_{i}', bm_cyl(0.034, 0.034, 0.05, 6), c['dark'], root, at=(x, 0.05 + y, 0.455), rot=(math.pi / 2, 0, math.pi / 6))
        part(f'tip_{i}', bm_cone(0.026, 0.05, 10), glowY, root, at=(x, 0.05 + y, 0.46), rot=rx)
    # little tracking dish on top
    part('mast', bm_cyl(0.012, 0.012, 0.1, 8), c['dark'], root, at=(0.0, 0.25, 0.22))
    part('dish', bm_sphere(0.06, 16, 8), c['white'], root, at=(0.0, 0.3, 0.24), scale=(1, 0.35, 1), rot=(-0.6, 0, 0))
    part('dish_glow', bm_sphere(0.015, 10, 6), glowY, root, at=(0.0, 0.31, 0.27))
    grip_and_stock(c, root, amber)
    empty('muzzle_seeker', root, at=(0, 0.05, 0.5))
    return root


if __name__ == '__main__':
    want = [a for a in sys.argv[1:] if not a.startswith('--')] or ['scatter', 'lobber', 'seeker']
    for name in want:
        root = {'scatter': scatter, 'lobber': lobber, 'seeker': seeker}[name]()
        print(name, 'TRIS', tri_count(root))
        export(OUT + f'wpn_{name}.glb', root)
        if '--preview' in sys.argv:
            root.location = gv(0, 0.5, 0)
            preview(OUT + f'wpn_{name}.png', root, cam_from=(1.0, 0.85, 0.9), look=(0, 0.5, 0.15), lens=50, size=(600, 600), samples=32)
