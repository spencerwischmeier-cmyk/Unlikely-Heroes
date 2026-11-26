# The Crane Bot's lattice jib (godot/models/chars/crane_boom.glb), in Grudd Works livery to match the Meshy cab.
#   /tmp/claude-0/bpyenv/bin/python art/crane_boom.py [--preview]
# Game space: the jib runs from z=0 (the mount) to z=10 (the tip sheave), chords at x=+-0.35, y=+-0.3,
# the same layout as the old primitive boom in cranebot.gd, so it drops onto the existing "boom" pivot.
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blib import *
from mathutils import Vector
import bmesh

OUT = '/tmp/claude-0/art'
os.makedirs(OUT, exist_ok=True)
L = 10.0

def bar(name, a, b, r, m, parent, seg=6):
    a, b = Vector(a), Vector(b); d = b - a
    bm = bm_cyl(r, r, d.length, seg)
    q = Vector((0, 1, 0)).rotation_difference(d.normalized())
    bmesh.ops.transform(bm, matrix=q.to_matrix().to_4x4(), verts=bm.verts)
    return part(name, bm, m, parent, at=tuple((a + b) / 2))

def boom():
    reset()
    yellow = mat('boom_yellow', 0xd99a22, 0.35, 0.5)
    dark = mat('boom_dark', 0x2e333b, 0.7, 0.45)
    red = mat('boom_red', 0xa8392a, 0.35, 0.5)
    steel = mat('boom_steel', 0x9aa4ae, 0.85, 0.35)
    black = mat('boom_black', 0x16181b, 0.3, 0.6)
    root = empty('CraneBoom')
    # four chords: chunky rounded box sections
    for x in (-0.35, 0.35):
        for y in (-0.3, 0.3):
            part(f'chord_{x}_{y}', bm_box(0.15, 0.15, L + 0.1), yellow, root, at=(x, y, L / 2), rounded=0.03)
    # lacing: zig-zag diagonals on every face, ladder rungs every bay
    n = 10
    for i in range(n):
        z0, z1 = i * L / n + 0.05, (i + 1) * L / n - 0.05
        zm = (z0 + z1) / 2
        for y in (-0.3, 0.3):
            bar(f'lace_h_{i}_{y}', (-0.35, y, z0), (0.35, y, zm), 0.035, dark, root)
            bar(f'lace_h2_{i}_{y}', (0.35, y, zm), (-0.35, y, z1), 0.035, dark, root)
        for x in (-0.35, 0.35):
            bar(f'lace_v_{i}_{x}', (x, -0.3, z0), (x, 0.3, zm), 0.035, dark, root)
            bar(f'lace_v2_{i}_{x}', (x, 0.3, zm), (x, -0.3, z1), 0.035, dark, root)
        # gusset plates at the bay joints
        for x in (-0.35, 0.35):
            for y in (-0.3, 0.3):
                part(f'gusset_{i}_{x}_{y}', bm_box(0.19, 0.19, 0.1), red, root, at=(x, y, z0), rounded=0.02)
    # hazard bands near the tip and the mount
    for k, z in enumerate((0.45, L - 0.7)):
        for j in range(5):
            m = black if j % 2 else yellow
            part(f'band_{k}_{j}', bm_box(0.86, 0.76, 0.1), m, root, at=(0, 0, z + j * 0.1), rounded=0.02)
    # tip: cheek plates and a big sheave the cable runs over
    for x in (-0.33, 0.33):
        part(f'cheek_{x}', bm_box(0.06, 0.8, 0.9), red, root, at=(x, -0.15, L - 0.05), rounded=0.03)
    part('sheave', bm_cyl(0.32, 0.32, 0.18, 32), steel, root, at=(0, -0.3, L), rot=(0, 0, math.pi / 2), bevel=0.02)
    part('sheave_hub', bm_cyl(0.1, 0.1, 0.7, 16), dark, root, at=(0, -0.3, L), rot=(0, 0, math.pi / 2), bevel=0.01)
    # mount: a pin block and two hydraulic lugs
    part('mount', bm_box(0.95, 0.85, 0.5), dark, root, at=(0, 0, 0.1), rounded=0.06)
    part('mount_pin', bm_cyl(0.12, 0.12, 1.1, 16), steel, root, at=(0, 0, 0.1), rot=(0, 0, math.pi / 2), bevel=0.01)
    print('boom tris', tri_count(root))
    export(f'{OUT}/crane_boom.glb', root)
    return root

r = boom()
if '--preview' in sys.argv:
    preview(f'{OUT}/crane_boom.png', r, cam_from=(4, 3, 3), look=(0, 0, 5), lens=35, samples=16, size=(900, 500))
