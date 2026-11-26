# The Work-Crew Roller's riveter arm (godot/models/chars/crew_riveter.glb), pivot at the shoulder (origin).
#   /tmp/claude-0/bpyenv/bin/python art/crew_riveter.py
# enemy_crew_roller.gd hangs it on the head as "arm" and fires from the "crew_muzzle" node.
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blib import *

OUT = '/tmp/claude-0/art'
os.makedirs(OUT, exist_ok=True)
reset()
yellow = mat('riv_yellow', 0xd99a22, 0.35, 0.5)
dark = mat('riv_dark', 0x2e333b, 0.7, 0.45)
red = mat('riv_red', 0xa8392a, 0.35, 0.5)
brass = mat('riv_brass', 0xd9a441, 0.9, 0.3)
black = mat('riv_black', 0x16181b, 0.3, 0.6)
root = empty('CrewRiveter')
part('shoulder', bm_sphere(0.1, 20, 12), brass, root)
part('shoulder_cap', bm_cyl(0.11, 0.11, 0.06, 20), dark, root, at=(-0.04, 0, 0), rot=(0, 0, math.pi / 2), bevel=0.01)
part('upper', bm_cyl(0.05, 0.05, 0.3, 12), dark, root, at=(-0.05, -0.08, 0.15), rot=(1.1, 0, 0), bevel=0.006)
part('piston', bm_cyl(0.025, 0.025, 0.3, 10), brass, root, at=(-0.0, -0.03, 0.17), rot=(1.1, 0, 0))
# riveter gun body: rounded block with a hazard band, a rivet hopper and a nozzle
part('body', bm_box(0.17, 0.19, 0.34), yellow, root, at=(-0.08, -0.15, 0.37), rounded=0.04)
for j in range(4):
    part(f'band_{j}', bm_box(0.175, 0.195, 0.04), black if j % 2 else yellow, root, at=(-0.08, -0.15, 0.24 + j * 0.04), rounded=0.012)
part('trim', bm_box(0.18, 0.03, 0.35), red, root, at=(-0.08, -0.04, 0.37), rounded=0.01)
part('hopper', bm_cyl(0.05, 0.06, 0.12, 12), dark, root, at=(-0.08, -0.0, 0.42), bevel=0.008)
part('hopper_cap', bm_cyl(0.055, 0.055, 0.02, 12), brass, root, at=(-0.08, 0.065, 0.42))
part('nozzle_ring', bm_cyl(0.07, 0.07, 0.05, 16), dark, root, at=(-0.08, -0.15, 0.55), rot=(math.pi / 2, 0, 0), bevel=0.01)
part('nozzle', bm_cyl(0.035, 0.045, 0.16, 12), brass, root, at=(-0.08, -0.15, 0.62), rot=(math.pi / 2, 0, 0), bevel=0.005)
empty('crew_muzzle', root, at=(-0.08, -0.15, 0.71))
print('riveter tris', tri_count(root))
export(f'{OUT}/crew_riveter.glb', root)
