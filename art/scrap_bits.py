# Scrap bits that fly off when a Grudd Works bot breaks apart (godot/models/chars/scrap_bits.glb).
#   /tmp/claude-0/bpyenv/bin/python art/scrap_bits.py [--preview]
# Each bit is its own top-level mesh object centred on its origin: sprocket, sprocket_small, bolt, nut, plate,
# plate_bent, spring, eye_lens. scripts/chars/scrap_burst.gd instances them.
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blib import *
import bmesh
from mathutils import Vector, Matrix

OUT = '/tmp/claude-0/art'
os.makedirs(OUT, exist_ok=True)

def gear_bm(r, teeth, th, hole, tooth_h):
    bm = bmesh.new()
    n = teeth * 4
    outer = []
    for i in range(n):
        a = math.tau * i / n
        k = i % 4
        rr = r + (tooth_h if k in (1, 2) else 0.0)
        outer.append((math.cos(a) * rr, math.sin(a) * rr))
    inner = [(math.cos(math.tau * i / n) * hole, math.sin(math.tau * i / n) * hole) for i in range(n)]
    vt = [[bm.verts.new((x, y, z)) for (x, y) in outer] for z in (-th / 2, th / 2)]
    vi = [[bm.verts.new((x, y, z)) for (x, y) in inner] for z in (-th / 2, th / 2)]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((vt[0][i], vt[0][j], vt[1][j], vt[1][i]))
        bm.faces.new((vi[0][j], vi[0][i], vi[1][i], vi[1][j]))
        bm.faces.new((vt[1][i], vt[1][j], vi[1][j], vi[1][i]))
        bm.faces.new((vt[0][j], vt[0][i], vi[0][i], vi[0][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def bits():
    reset()
    brass = mat('bits_brass', 0xd9a441, 0.9, 0.3)
    steel = mat('bits_steel', 0x9aa4ae, 0.9, 0.35)
    yellow = mat('bits_yellow', 0xe8a81c, 0.4, 0.45)
    dark = mat('bits_dark', 0x2e333b, 0.7, 0.45)
    red = mat('bits_red', 0xb23a2a, 0.4, 0.45)
    lens = glowmat('bits_lens', 0xff3020, 4)
    root = empty('ScrapBits')
    part('sprocket', gear_bm(0.13, 10, 0.04, 0.045, 0.035), brass, root, at=(0, 0, 0), bevel=0.006, smooth=False)
    part('sprocket_small', gear_bm(0.08, 8, 0.035, 0.025, 0.025), steel, root, at=(0.5, 0, 0), bevel=0.005, smooth=False)
    b = bm_cyl(0.06, 0.06, 0.05, 6)
    s = bm_cyl(0.025, 0.025, 0.18, 10); bmesh.ops.translate(s, vec=(0, -0.11, 0), verts=s.verts)
    me = bpy.data.meshes.new('tmp'); s.to_mesh(me); b.from_mesh(me); bpy.data.meshes.remove(me); s.free()
    part('bolt', b, steel, root, at=(1.0, 0, 0), bevel=0.006, smooth=False)
    n = bm_cyl(0.055, 0.055, 0.045, 6)
    part('nut', n, dark, root, at=(1.4, 0, 0), bevel=0.006, smooth=False)
    part('plate', bm_box(0.32, 0.03, 0.22), yellow, root, at=(1.8, 0, 0), rounded=0.012)
    pb = bm_box(0.28, 0.03, 0.2)
    for v in pb.verts:
        if v.co.x > 0: v.co.y += v.co.x * 0.6
    part('plate_bent', pb, red, root, at=(2.3, 0, 0), rounded=0.01)
    sp = bmesh.new()
    turns, R, r, pts = 5, 0.06, 0.012, 80
    prev = None
    rings = []
    for i in range(pts + 1):
        u = i / pts; a = u * turns * math.tau
        c = Vector((math.cos(a) * R, u * 0.22 - 0.11, math.sin(a) * R))
        t = Vector((-math.sin(a), 0.22 / (turns * math.tau * R), math.cos(a))).normalized()
        nrm = Vector((math.cos(a), 0, math.sin(a))); bn = t.cross(nrm)
        rings.append([sp.verts.new(c + (nrm * math.cos(k * math.tau / 6) + bn * math.sin(k * math.tau / 6)) * r) for k in range(6)])
    for i in range(pts):
        for k in range(6):
            sp.faces.new((rings[i][k], rings[i + 1][k], rings[i + 1][(k + 1) % 6], rings[i][(k + 1) % 6]))
    part('spring', sp, steel, root, at=(2.8, 0, 0))
    part('eye_lens', bm_sphere(0.09, 16, 10), lens, root, at=(3.2, 0, 0), scale=(1, 1, 0.5))
    export(f'{OUT}/scrap_bits.glb', root)
    return root

r = bits()
if '--preview' in sys.argv:
    preview(f'{OUT}/scrap_bits.png', r, cam_from=(1.6, 1.4, 2.2), look=(1.6, 0, 0), lens=50, samples=16, size=(800, 400))
