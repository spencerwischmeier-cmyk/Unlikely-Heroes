import sys, math; sys.path.insert(0, '/tmp/claude-0/art')
from blib import *
from mathutils import Vector
reset()

suit = mat('suit_orange', 0xff6a1a, 0, 0.55, sheen=0.6, sheen_tint=0xffc890)
suitDark = mat('suit_navy', 0x262b3d, 0, 0.6, sheen=0.5, sheen_tint=0x6a8cc0)
plate = mat('plate_white', 0xeef2f5, 0.55, 0.25)
skin = mat('skin_teal', 0x58c9b8, 0, 0.45, sheen=0.8, sheen_tint=0xb8fff0, coat=0.15)
fin = mat('fin_violet', 0x6b3fd0, 0, 0.35, coat=0.6)
boot = mat('boot', 0x2c3038, 0.6, 0.38)
glove = mat('glove', 0x3a3f4a, 0.3, 0.55)
brass = mat('brass', 0xd9a441, 0.9, 0.3)
blue = mat('metal_blue', 0x5f8fb0, 0.7, 0.32)
dark = mat('metal_dark', 0x34404c, 0.75, 0.4)
leather = mat('leather', 0x5a3a22, 0.1, 0.6)
eyeW = mat('eye_white', 0xffffff, 0, 0.1, coat=1)
iris = mat('iris', 0xffa21a, 0, 0.2, emit=0x6a3000, strength=0.6, coat=1)
pupilM = mat('pupil', 0x0a0a10, 0, 0.2)
lens = mat('lens', 0x40d0ff, 0.2, 0.05, emit=0x0a4060, strength=0.6, coat=1)
browM = mat('brow', 0x2c5f6a, 0, 0.7)
mouthM = mat('mouth', 0x1c3c3c, 0, 0.6)
noseM = mat('nose', 0x2f6f6a, 0, 0.35)
gunWhite = mat('gun_white', 0xf2f4f6, 0.6, 0.3)
cyan = glowmat('glow_cyan', 0x40f0ff, 7)
cyanSoft = glowmat('glow_cyan_soft', 0x40f6ff, 4)
soleM = glowmat('glow_sole', 0x3ff0ff, 2.5)
wristM = glowmat('glow_wrist', 0x50ff90, 2.5)

root = empty('Hero')
# ---------------- legs ----------------
for s, side in ((1, 'L'), (-1, 'R')):
    hip = empty(f'hip_{side}', root, at=(0.13 * s, 0.66, 0))
    H = Vector(hip['game_at'])
    limb(f'thigh_{side}', H, H + Vector((0.005 * s, -0.28, 0.02)), 0.105, suitDark, hip)
    knee = empty(f'knee_{side}', hip, at=tuple(H + Vector((0, -0.28, 0.02))), parent_at=H)
    K = Vector(knee['game_at'])
    part(f'kneepad_{side}', bm_sphere(0.088, 20, 12), plate, knee, at=tuple(K + Vector((0, 0.0, 0.055))), scale=(1, 0.9, 0.7))
    limb(f'shin_{side}', K, K + Vector((0, -0.25, -0.01)), 0.088, suitDark, knee)
    limb(f'shinplate_{side}', K + Vector((0, -0.08, 0.012)), K + Vector((0, -0.22, 0.0)), 0.098, plate, knee)
    B = K + Vector((0, -0.26, -0.01))
    part(f'boot_{side}', bm_box(0.22, 0.2, 0.36), boot, knee, at=tuple(B + Vector((0, -0.03, 0.05))), rounded=0.06)
    part(f'bootcap_{side}', bm_box(0.2, 0.08, 0.14), plate, knee, at=tuple(B + Vector((0, 0.0, 0.17))), rot=(-0.3, 0, 0), rounded=0.024)
    part(f'cuff_{side}', bm_cyl(0.12, 0.11, 0.1, 24), plate, knee, at=tuple(B + Vector((0, 0.07, 0))), bevel=0.015)
    part(f'sole_{side}', bm_box(0.23, 0.045, 0.37), soleM, knee, at=tuple(B + Vector((0, -0.125, 0.05))), rounded=0.013)

# ---------------- upper body (pivot at waist) ----------------
up = empty('upper', root, at=(0, 0.72, 0))
torso = sdf_blob('torso', [
    (0, 0.0, 0.0, 0.2, 0.11, 0.13),
    (0, 0.12, 0.0, 0.19, 0.15, 0.14),
    (0, 0.24, 0.0, 0.235, 0.16, 0.15),
    (0.16, 0.32, 0.0, 0.1, 0.1, 0.1), (-0.16, 0.32, 0.0, 0.1, 0.1, 0.1),
], suitDark, up, at=(0, 0.74, 0), k=0.08, center=(0, 0.14, 0))
part('chestplate', bm_box(0.36, 0.25, 0.08), plate, up, at=(0.0, 1.0, 0.14), rot=(-0.12, 0, 0), rounded=0.024)
part('core', bm_cyl(0.05, 0.05, 0.03, 6), cyanSoft, up, at=(0.0, 1.0, 0.185), rot=(math.pi / 2, 0, 0), smooth=False)
part('core_ring', bm_torus(0.055, 0.012, 6, 6), brass, up, at=(0.0, 1.0, 0.18), smooth=True)
part('belt', bm_torus(0.21, 0.035, 40, 10), leather, up, at=(0, 0.79, 0), rot=(math.pi / 2, 0, 0), scale=(1.05, 0.7, 1))
part('buckle', bm_box(0.1, 0.07, 0.03), brass, up, at=(0.03, 0.79, 0.15), bevel=0.01)
part('pouch', bm_box(0.1, 0.11, 0.08), leather, up, at=(-0.21, 0.75, 0.06), rounded=0.024)
part('pouch2', bm_box(0.08, 0.09, 0.07), leather, up, at=(0.22, 0.75, -0.02), rounded=0.021)
shL, shR = Vector((0.27, 1.08, 0.0)), Vector((-0.26, 1.08, 0.02))
for n, sp in (('L', shL), ('R', shR)):
    part(f'shoulderpad_{n}', bm_sphere(0.125, 24, 14), suit, up, at=tuple(sp + Vector((0, 0.03, 0))), scale=(1, 0.75, 1))
    part(f'shoulderrim_{n}', bm_torus(0.105, 0.018, 28, 8), plate, up, at=tuple(sp + Vector((0, 0.0, 0))), rot=(math.pi / 2, 0, 0))
# jetpack
part('pack', bm_box(0.36, 0.38, 0.16), plate, up, at=(0, 0.97, -0.22), rounded=0.048)
part('pack_stripe', bm_box(0.1, 0.36, 0.02), suit, up, at=(0, 0.97, -0.3), rounded=0.006)
for s, n in ((1, 'L'), (-1, 'R')):
    part(f'thruster_{n}', bm_cyl(0.09, 0.07, 0.42, 24), blue, up, at=(0.15 * s, 0.93, -0.3), bevel=0.01)
    part(f'thrusterband_{n}', bm_torus(0.085, 0.012, 24, 6), brass, up, at=(0.15 * s, 1.05, -0.3), rot=(math.pi / 2, 0, 0))
    part(f'nozzle_{n}', bm_cyl(0.06, 0.075, 0.05, 24), cyan, up, at=(0.15 * s, 0.7, -0.3))
    empty(f'jet_{n}', up, at=(0.15 * s, 0.66, -0.3), parent_at=up['game_at'])
    part(f'packfin_{n}', bm_box(0.03, 0.22, 0.12), plate, up, at=(0.24 * s, 1.08, -0.32), rot=(0, 0, 0.35 * s), bevel=0.01)
# neck + head
part('neck', bm_cyl(0.09, 0.075, 0.12, 16), skin, up, at=(0, 1.17, 0))
part('collar', bm_torus(0.11, 0.035, 30, 10), suitDark, up, at=(0, 1.15, 0), rot=(math.pi / 2, 0, 0))
head = empty('head', up, at=(0.02, 1.43, 0.03), parent_at=up['game_at'])
HP = Vector(head['game_at'])
sdf_blob('skull', [
    (0, 0, 0, 0.29, 0.275, 0.285),
    (0, -0.11, 0.08, 0.21, 0.16, 0.2),
    (0, -0.07, 0.235, 0.125, 0.07, 0.085),
    (0.12, -0.09, 0.15, 0.085, 0.08, 0.08), (-0.12, -0.09, 0.15, 0.085, 0.08, 0.08),
], skin, head, at=tuple(HP), k=0.05)
part('nose', bm_sphere(0.03, 16, 10), noseM, head, at=tuple(HP + Vector((0, -0.045, 0.315))), scale=(1.4, 0.8, 1))
for s, n in ((-1, 'R'), (1, 'L')):
    E = HP + Vector((0.105 * s, 0.035, 0.225)); ry = 0.28 * s
    rotv = lambda v: Vector((v.x * math.cos(ry) + v.z * math.sin(ry), v.y, -v.x * math.sin(ry) + v.z * math.cos(ry)))
    part(f'eye_{n}', bm_sphere(0.075, 32, 20), eyeW, head, at=tuple(E), rot=(0, ry, 0), scale=(1, 1.15, 0.7))
    part(f'iris_{n}', bm_sphere(0.045, 24, 16), iris, head, at=tuple(E + rotv(Vector((0.012 - 0.008 * s, -0.004, 0.044)))), rot=(0, ry, 0), scale=(1, 1.1, 0.45))
    part(f'pupil_{n}', bm_sphere(0.024, 16, 12), pupilM, head, at=tuple(E + rotv(Vector((0.013 - 0.008 * s, -0.004, 0.06)))), rot=(0, ry, 0), scale=(1, 1.15, 0.35))
    part(f'glint_{n}', bm_sphere(0.009, 10, 8), glowmat('glow_white', 0xffffff, 4), head, at=tuple(E + rotv(Vector((0.028 - 0.008 * s, 0.022, 0.066)))))
    lid = bm_sphere(0.082, 32, 16)
    import bmesh as _b
    _b.ops.delete(lid, geom=[v for v in lid.verts if v.co.y < -0.005], context='VERTS')
    part(f'lid_{n}', lid, skin, head, at=tuple(E), rot=(-0.3, ry, 0), scale=(1.06, 1.2, 0.8))
    limb(f'brow_{n}', E + Vector((-0.035 * s, 0.1, 0.045)), E + Vector((0.065 * s, 0.112, 0.0)), 0.019, browM, head)
part('smile', bm_torus(0.06, 0.009, 24, 8, math.pi * 0.75), mouthM, head, at=tuple(HP + Vector((0.02, -0.125, 0.27))), rot=(0.25, 0.1, math.pi + 0.55))
def fin_at(name, base, dirn, r, h, flat=0.5):
    dirn = dirn.normalized()
    bm = bm_cone(r, h, 16)
    bmesh.ops.scale(bm, vec=(flat, 1, 1), verts=bm.verts)
    q = Vector((0, 1, 0)).rotation_difference(dirn)
    bmesh.ops.transform(bm, matrix=q.to_matrix().to_4x4(), verts=bm.verts)
    return part(name, bm, fin, head, at=tuple(base + dirn * h * 0.42), subsurf=1)
import bmesh
for i in range(5):
    phi = 0.15 + i * 0.36
    surf = HP + Vector((0, math.cos(phi), -math.sin(phi))) * 0.27
    fin_at(f'crest_{i}', surf, Vector((0, math.cos(phi + 0.75), -math.sin(phi + 0.75))), 0.07 - i * 0.007, 0.3 - i * 0.035)
for s_, n in ((-1, 'R'), (1, 'L')):
    surf = HP + Vector((0.27 * s_, 0.03, -0.04))
    fin_at(f'ear_{n}', surf, Vector((1.0 * s_, 0.35, -0.45)), 0.06, 0.24, flat=0.45)
part('strap', bm_torus(0.268, 0.02, 48, 8), leather, head, at=tuple(HP + Vector((0, 0.102, -0.062))), rot=(math.pi / 2 - 0.55, 0, 0))
for s, n in ((-1, 'R'), (1, 'L')):
    gp = HP + Vector((0.09 * s, 0.215, 0.16))
    part(f'goggle_{n}', bm_torus(0.06, 0.02, 24, 10), brass, head, at=tuple(gp), rot=(-0.95, 0.25 * s, 0))
    part(f'goggle_lens_{n}', bm_cyl(0.058, 0.058, 0.012, 24), lens, head, at=tuple(gp), rot=(-0.95 + math.pi / 2, 0.25 * s, 0))

# ---------------- blaster ----------------
GP = Vector((0.30, 1.2, 0.32))  # shouldered on the left, so it shows over the hero's shoulder
gun = empty('gun', up, at=tuple(GP), parent_at=up['game_at'])
part('gun_body', bm_box(0.17, 0.17, 0.42), gunWhite, gun, at=tuple(GP), rounded=0.051)
part('gun_top', bm_box(0.1, 0.06, 0.3), suit, gun, at=tuple(GP + Vector((0, 0.1, 0.02))), bevel=0.012)
part('gun_sight', bm_box(0.04, 0.05, 0.08), dark, gun, at=tuple(GP + Vector((0, 0.15, -0.04))), bevel=0.008)
part('gun_barrel', bm_cyl(0.055, 0.045, 0.42, 20), dark, gun, at=tuple(GP + Vector((0, 0.02, 0.38))), rot=(math.pi / 2, 0, 0))
for i in range(4):
    part(f'gun_coil_{i}', bm_torus(0.07, 0.016, 24, 10), cyan, gun, at=tuple(GP + Vector((0, 0.02, 0.24 + i * 0.075))))
for s in (-1, 1):
    part(f'gun_prong_{s}', bm_box(0.04, 0.04, 0.18), brass, gun, at=tuple(GP + Vector((0.075 * s, 0.02, 0.6))), rot=(0, -0.15 * s, 0), bevel=0.008)
part('gun_tank', bm_cyl(0.05, 0.05, 0.2, 16), cyanSoft, gun, at=tuple(GP + Vector((0, -0.06, -0.08))), rot=(math.pi / 2, 0, 0))
part('gun_grip', bm_box(0.08, 0.18, 0.09), dark, gun, at=tuple(GP + Vector((0, -0.14, -0.1))), rot=(0.3, 0, 0), rounded=0.024)
part('gun_stock', bm_box(0.1, 0.12, 0.2), suit, gun, at=tuple(GP + Vector((0, -0.02, -0.28))), rounded=0.03)
empty('muzzle', gun, at=tuple(GP + Vector((0, 0.02, 0.72))), parent_at=GP)

# ---------------- arms + gloves ----------------
handGrip = GP + Vector((0, -0.13, -0.08)); handFore = GP + Vector((-0.03, -0.08, 0.12))
elbL, elbR = Vector((0.44, 0.92, 0.1)), Vector((0.0, 0.92, 0.26))
limb('upperarm_L', shL, elbL, 0.075, suit, up); limb('forearm_L', elbL, handGrip, 0.066, suit, up)
limb('upperarm_R', shR, elbR, 0.075, suit, up); limb('forearm_R', elbR, handFore, 0.066, suit, up)
for n, e, h in (('L', elbL, handGrip), ('R', elbR, handFore)):
    limb(f'gauntlet_{n}', e.lerp(h, 0.5), e.lerp(h, 0.88), 0.085, glove, up)
    d = (h - e).normalized()
    sdf_blob(f'hand_{n}', [(0, 0, 0, 0.08, 0.07, 0.09), (0.045 * (1 if n == 'L' else -1), 0.035, 0.03, 0.035, 0.035, 0.05)], glove, up, at=tuple(h), k=0.03, seg=32, rings=24)
part('wrist_screen', bm_box(0.07, 0.035, 0.09), wristM, up, at=tuple(elbR.lerp(handFore, 0.72) + Vector((0, 0.07, 0))), bevel=0.008)

print('TRIS', tri_count(root))
export('/tmp/claude-0/art/hero.glb', root)
if '--preview' in sys.argv:
    preview('/tmp/claude-0/art/hero_front.png', root, cam_from=(1.6, 1.3, 2.6), look=(0.05, 0.95, 0), lens=50)
    preview('/tmp/claude-0/art/hero_face.png', root, cam_from=(0.5, 1.5, 1.2), look=(0.02, 1.4, 0.05), lens=60)
