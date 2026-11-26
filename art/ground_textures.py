"""Tileable ground surfaces for each Skyharbor area (the floor you walk on). Each style gets
   godot/textures/ground/<style>_albedo.png   RGB albedo, A = roughness
   godot/textures/ground/<style>_normal.png   RGB normal map (OpenGL, green up), A = height
plus side.png (the curb / plinth faces) and a small tileable noise texture for the shader's macro variation.
Styles (layer order in the shader): deck, junk, cobble, terracotta, flagstone, planks, tread, concrete.
Pure numpy + Pillow. Run: python3 art/ground_textures.py
"""
import os, math
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'godot', 'textures', 'ground')
os.makedirs(OUT, exist_ok=True)
N = 1024
rng = np.random.default_rng(11)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
U, V = xx / N, yy / N


# ------------------------------------------------------------------ helpers
def noise(scale, n=N, aniso=(1.0, 1.0)):
    """periodic smooth noise in [-1, 1]; scale = feature size in pixels"""
    w = rng.standard_normal((n, n))
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    r = np.real(np.fft.ifft2(np.fft.fft2(w) * np.exp(-(f * scale) ** 2 * 4)))
    r -= r.mean(); r /= (np.abs(r).max() + 1e-9)
    return r.astype(np.float32)


def fbm(base, octaves=5, aniso=(1.0, 1.0)):
    out = np.zeros((N, N), np.float32); amp = 1.0; tot = 0
    for i in range(octaves):
        out += noise(max(base / 2 ** i, 0.6), aniso=aniso) * amp; tot += amp; amp *= 0.5
    return out / tot


def blur(a, r):
    if r <= 0: return a
    k = np.fft.fftfreq(a.shape[0])
    f = np.sqrt(k[:, None] ** 2 + k[None, :] ** 2)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * np.exp(-(f * r) ** 2 * 8))).astype(np.float32)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def voronoi(cells, jitter=0.85, seed=None, stretch=(1.0, 1.0)):
    """tileable Voronoi over the unit square with cells x cells sites.
    returns F1, F2 (in cell units), the id of the nearest site and that site's offset (dx, dy) from the pixel"""
    g = np.random.default_rng(seed)
    pts = (np.arange(cells)[None, :, None] * 0 + 0.5 + (g.random((cells, cells, 2)) - 0.5) * jitter)
    px, py = U * cells, V * cells
    cx, cy = np.floor(px).astype(int), np.floor(py).astype(int)
    f1 = np.full((N, N), 9.0, np.float32); f2 = np.full((N, N), 9.0, np.float32)
    ids = np.zeros((N, N), np.int32); ox = np.zeros((N, N), np.float32); oy = np.zeros((N, N), np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nx, ny = cx + dx, cy + dy
            wx, wy = nx % cells, ny % cells
            sx = nx + pts[wy, wx, 0]; sy = ny + pts[wy, wx, 1]
            ddx = (sx - px) * stretch[0]; ddy = (sy - py) * stretch[1]
            d = np.sqrt(ddx * ddx + ddy * ddy)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            ids = np.where(closer, wy * cells + wx, ids)
            ox = np.where(closer, ddx, ox); oy = np.where(closer, ddy, oy)
            f1 = np.where(closer, d, f1)
    return f1, f2, ids, ox, oy


def per_id(ids, count, seed=0):
    """a random value in [0, 1) per cell id"""
    return np.random.default_rng(seed).random(count + 1).astype(np.float32)[ids]


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def hexc(s):
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def pal(t, cols):
    """pick from a palette by t in [0,1), with smooth blending between neighbours"""
    cols = np.stack([hexc(c) for c in cols])
    i = np.clip((t * len(cols)).astype(int), 0, len(cols) - 1)
    return cols[i]


def save(style, albedo, rough, height, nstrength):
    nrm = normal_from_height(height, nstrength)
    a = np.concatenate([np.clip(albedo, 0, 1), np.clip(rough, 0, 1)[..., None]], -1)
    hn = (height - height.min()) / (np.ptp(height) + 1e-6)
    n = np.concatenate([nrm, hn[..., None]], -1)
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, style + '_albedo.png'), optimize=True)
    Image.fromarray((n * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, style + '_normal.png'), optimize=True)
    print('wrote', style)


def grime(base_scale=180, amt=0.25):
    return 1.0 - amt * sstep(-0.1, 0.6, fbm(base_scale))


# ------------------------------------------------------------------ deck (the old plates, kept as layer 0)
def deck():
    src = os.path.join(HERE, '..', 'godot', 'textures')
    a = np.asarray(Image.open(os.path.join(src, 'deck_albedo.png')).convert('RGB').resize((N, N), Image.LANCZOS), np.float32) / 255
    r = np.asarray(Image.open(os.path.join(src, 'deck_rough.png')).convert('L').resize((N, N), Image.LANCZOS), np.float32) / 255
    nm = np.asarray(Image.open(os.path.join(src, 'deck_normal.png')).convert('RGB').resize((N, N), Image.LANCZOS), np.float32) / 255
    h = a.mean(-1)
    out = np.concatenate([a, r[..., None]], -1)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'deck_albedo.png'), optimize=True)
    n = np.concatenate([nm, h[..., None]], -1)
    Image.fromarray((n * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'deck_normal.png'), optimize=True)
    print('wrote deck')


# ------------------------------------------------------------------ junkyard: packed earth, gravel, patched scrap plates
def junk():
    # earth
    e = fbm(90)
    col = hexc('8a6446') * (0.85 + 0.25 * e[..., None])
    col = col * (1 - 0.18 * sstep(0.2, 0.7, fbm(260))[..., None]) + hexc('6d5a3e') * 0.18 * sstep(0.2, 0.7, fbm(260))[..., None]
    h = e * 0.15 + fbm(8) * 0.08
    # gravel: many small voronoi pebbles
    f1, f2, ids, _, _ = voronoi(40, seed=3)
    keep = (per_id(ids, 40 * 40, 4) < 0.35) * sstep(-0.2, 0.3, fbm(150))
    peb = sstep(0.4, 0.2, f1) * keep
    pc = pal(per_id(ids, 40 * 40, 5), ['6e6862', '857c70', '5a5450', '93866f', '6d5a48'])
    col = col * (1 - peb[..., None]) + pc * (0.75 + 0.35 * peb[..., None]) * peb[..., None]
    h += peb * 0.35
    # tyre ruts
    rut = sstep(0.06, 0.0, np.abs(((V * 2 + 0.15 * noise(300)) % 1.0) - 0.5) - 0.12)
    col *= (1 - 0.12 * rut[..., None]); h -= rut * 0.1
    # patched scrap plates (axis aligned rects, wrapping)
    g = np.random.default_rng(21)
    plate = np.zeros((N, N), np.float32); pcol = np.zeros((N, N, 3), np.float32); edge = np.zeros((N, N), np.float32)
    riv = np.zeros((N, N), np.float32)
    pcols = ['7e8a90', '9a5a3a', '5f7f8a', 'a27b3c', '6c7a5c', '8c8f94']
    for k in range(6):
        w, d = g.integers(170, 340), g.integers(120, 280)
        x0, y0 = g.integers(0, N), g.integers(0, N)
        lx = (xx - x0) % N; ly = (yy - y0) % N
        inside = (lx < w) & (ly < d)
        ex = np.minimum(lx, w - lx); ey = np.minimum(ly, d - ly)
        border = np.minimum(ex, ey)
        m = inside.astype(np.float32)
        plate = np.maximum(plate, m)
        c = hexc(pcols[k % len(pcols)])
        pcol = np.where(inside[..., None], c, pcol)
        edge = np.where(inside, np.clip(border / 10.0, 0, 1), edge)
        # rivets along the border
        rx = ((lx - 12) % 40); ry = ((ly - 12) % 40)
        rv = inside & (((np.abs(ex - 12) < 6) & (ry < 1e9)) | ((np.abs(ey - 12) < 6))) & (np.hypot(np.where(np.abs(ex - 12) < 6, ex - 12, (rx - 20)), np.where(np.abs(ey - 12) < 6, ey - 12, (ry - 20))) < 5)
        riv = np.maximum(riv, rv.astype(np.float32))
    rust = sstep(0.0, 0.5, fbm(60) + 0.25 * noise(12))
    pcol = pcol * (1 - 0.65 * rust[..., None]) + hexc('8b4423') * 0.65 * rust[..., None] * (0.8 + 0.3 * noise(4)[..., None])
    pcol *= (0.75 + 0.25 * edge[..., None])
    col = col * (1 - plate[..., None]) + pcol * plate[..., None]
    col = col * (1 - 0.15 * riv[..., None]) + hexc('c8c2b8') * 0.15 * riv[..., None]
    h = h * (1 - plate) + (0.55 + 0.1 * edge + 0.15 * riv - 0.05 * rust) * plate
    # dirt drifts over the plates
    drift = sstep(0.25, 0.65, fbm(120)) * plate
    col = col * (1 - 0.5 * drift[..., None]) + hexc('7a5a40') * 0.5 * drift[..., None]
    col *= grime(200, 0.2)[..., None]
    rough = 0.92 - plate * (0.35 - 0.3 * rust) - peb * 0.1
    save('junk', col, rough, h, 6.0)


# ------------------------------------------------------------------ plaza: chunky rounded cobbles in warm stone
def cobble():
    f1, f2, ids, ox, oy = voronoi(18, jitter=0.7, seed=31, stretch=(1.0, 1.25))
    n = 18 * 18
    gap = f2 - f1
    stone = sstep(0.05, 0.2, gap)              # 0 in the joints
    dome = np.sqrt(np.clip(1 - (f1 / 0.75) ** 2, 0, 1))
    t = per_id(ids, n, 32)
    base = pal(t, ['d9c3a0', 'c9ad8a', 'e2d2b4', 'b99a7e', 'd4b49a', 'c8b7a0', 'a98d73'])
    base = base * (0.88 + 0.12 * per_id(ids, n, 33)[..., None])
    speck = noise(3) * 0.5 + noise(1.2) * 0.5
    base = base * (0.93 + 0.08 * speck[..., None]) * (0.82 + 0.18 * dome[..., None])
    # worn polished tops
    base = base * (1 + 0.06 * sstep(0.5, 0.9, dome)[..., None])
    mortar = hexc('6f6656') * (0.9 + 0.2 * noise(6)[..., None])
    moss = sstep(0.0, 0.5, fbm(150)) * (1 - stone)
    mortar = mortar * (1 - moss[..., None]) + hexc('5d7a37') * moss[..., None]
    col = base * stone[..., None] + mortar * (1 - stone[..., None])
    # a few cracked stones
    crk = (per_id(ids, n, 34) < 0.08) & (np.abs(noise(40) * 1.0 + ox * 0.6) < 0.012)
    col *= (1 - 0.35 * crk[..., None])
    col *= grime(220, 0.18)[..., None]
    h = stone * (0.45 + 0.5 * dome) + speck * 0.03 - crk * 0.1
    rough = 0.55 + 0.35 * (1 - stone) - 0.12 * dome * stone
    save('cobble', col, rough, h, 9.0)


# ------------------------------------------------------------------ terrace: terracotta tiles with glazed accents
def terracotta():
    k = 6                                       # 6 x 6 tiles per texture
    tx = U * k; ty = V * k
    ix, iy = np.floor(tx).astype(int), np.floor(ty).astype(int)
    fx, fy = tx - ix, ty - iy
    tid = (iy % k) * k + (ix % k)
    edge = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy))
    grout = sstep(0.018, 0.04, edge)
    bevel = sstep(0.02, 0.09, edge)
    t = per_id(tid, k * k, 41)
    base = pal(t, ['c4693f', 'b75a35', 'cf7a4c', 'b0603f', 'd08452', 'a9512f'])
    base = base * (0.9 + 0.15 * noise(30)[..., None]) * (0.92 + 0.08 * noise(3)[..., None])
    # glazed accent tiles: a teal and cream quatrefoil
    acc = per_id(tid, k * k, 42) < 0.14
    cx, cy = fx - 0.5, fy - 0.5
    r = np.hypot(cx, cy); a = np.arctan2(cy, cx)
    petal = sstep(0.02, 0.0, r - (0.28 + 0.1 * np.cos(a * 4)))
    ring = sstep(0.025, 0.0, np.abs(r - 0.41))
    glaze = np.where(petal[..., None] > 0.5, hexc('e9dcc0'), hexc('2f8f8a'))
    glaze = glaze * (1 - ring[..., None]) + hexc('e9dcc0') * ring[..., None]
    base = np.where(acc[..., None], glaze * (0.92 + 0.08 * noise(20)[..., None]), base)
    # chipped corners
    chip = (per_id(tid, k * k, 43) < 0.3) & (np.hypot(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy)) < 0.08 + 0.04 * noise(6))
    base = np.where(chip[..., None], hexc('8e5a3c'), base)
    groutc = hexc('d8c7a8') * (0.85 + 0.2 * noise(8)[..., None])
    col = base * grout[..., None] + groutc * (1 - grout[..., None])
    col *= (0.86 + 0.14 * bevel[..., None])
    col *= grime(240, 0.15)[..., None]
    h = grout * (0.5 + 0.3 * bevel) - chip * 0.25 + noise(4) * 0.02
    rough = np.where(acc, 0.22, 0.7) * grout + 0.85 * (1 - grout)
    save('terracotta', col, rough, h, 7.0)


# ------------------------------------------------------------------ gardens: irregular flagstones with grassy joints
def flagstone():
    f1, f2, ids, ox, oy = voronoi(7, jitter=0.9, seed=51)
    n = 49
    gap = f2 - f1
    stone = sstep(0.03, 0.08, gap)
    t = per_id(ids, n, 52)
    base = pal(t, ['cfc6b0', 'bdb39b', 'd9d0bb', 'b0a690', 'c7bba0'])
    base = base * (0.9 + 0.12 * fbm(40)[..., None]) * (0.94 + 0.06 * noise(2)[..., None])
    lich = sstep(0.35, 0.6, fbm(60)) * stone
    base = base * (1 - 0.35 * lich[..., None]) + hexc('a7b26a') * 0.35 * lich[..., None]
    grass = hexc('5f8f3a') * (0.8 + 0.35 * noise(2.5)[..., None])
    col = base * stone[..., None] + grass * (1 - stone[..., None])
    col *= grime(200, 0.12)[..., None]
    h = stone * (0.5 + 0.1 * fbm(20)) + (1 - stone) * 0.2 * noise(1.5)
    rough = 0.72 * stone + 0.9 * (1 - stone)
    save('flagstone', col, rough, h, 8.0)


# ------------------------------------------------------------------ docks: weathered boardwalk planks (run along x)
def planks():
    rows = 8
    py = V * rows
    row = np.floor(py).astype(int)
    fy = py - row
    g = np.random.default_rng(61)
    offs = g.random(rows)
    lens = g.integers(2, 4, rows)            # planks per texture width in each row
    px = (U + offs[row % rows]) * lens[row % rows]
    pid = np.floor(px).astype(int)
    fx = px - pid
    uid = row * 8 + (pid % 8)
    gapy = sstep(0.025, 0.06, np.minimum(fy, 1 - fy))
    gapx = sstep(0.004, 0.012, np.minimum(fx, 1 - fx) / lens[row % rows])
    board = gapy * gapx
    t = per_id(uid, rows * 8, 62)
    base = pal(t, ['a8774c', '9c6b44', 'b58658', '8e8070', 'a59a8a', '946240', 'bf9466'])
    grain = noise(60, aniso=(0.05, 1.0)) * 0.6 + noise(14, aniso=(0.08, 1.0)) * 0.4
    knot = np.zeros((N, N), np.float32)
    for k in range(6):
        kx, ky = g.random() * N, g.random() * N
        d = np.hypot(((xx - kx + N / 2) % N - N / 2) * 0.5, (yy - ky + N / 2) % N - N / 2)
        knot = np.maximum(knot, sstep(18, 4, d))
    base = base * (0.86 + 0.18 * grain[..., None]) * (1 - 0.35 * knot[..., None])
    # bleached, sea-greyed boards and a few with old paint
    grey = sstep(0.2, 0.6, fbm(250)) * 0.5
    base = base * (1 - grey[..., None]) + base.mean(-1, keepdims=True) * np.array([0.98, 1.0, 1.04]) * 1.05 * grey[..., None]
    painted = per_id(uid, rows * 8, 63) < 0.08
    pc = np.where(per_id(uid, rows * 8, 64)[..., None] < 0.5, hexc('3f8fb0'), hexc('d4a83a'))
    chips = sstep(-0.35, -0.15, noise(25) + 0.15 * noise(3))
    base = np.where(painted[..., None], base * (1 - chips[..., None]) + pc * chips[..., None], base)
    # nail heads at plank ends
    near_end = np.minimum(fx, 1 - fx) * (N / lens[row % rows]) < 22
    nail = near_end & ((np.abs(fy - 0.3) < 0.04) | (np.abs(fy - 0.7) < 0.04)) & (np.minimum(fx, 1 - fx) * (N / lens[row % rows]) > 8)
    nd = nail.astype(np.float32)
    base = base * (1 - 0.5 * nd[..., None]) + hexc('4a4a4a') * 0.5 * nd[..., None]
    gapc = hexc('2a1e16')
    col = base * board[..., None] + gapc * (1 - board[..., None])
    col *= grime(220, 0.15)[..., None]
    h = board * (0.6 + 0.08 * grain - 0.1 * knot) - (1 - board) * 0.2 + nd * 0.05
    rough = 0.78 * board + 0.95 * (1 - board) - painted * 0.2
    save('planks', col, rough, h, 6.0)


# ------------------------------------------------------------------ mast: diamond tread plate panels
def tread():
    k = 2
    fx, fy = (U * k) % 1, (V * k) % 1
    pid = (np.floor(V * k) * k + np.floor(U * k)).astype(int)
    seam = sstep(0.006, 0.014, np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy)))
    # diamond lugs alternating direction
    d = 26
    gx, gy = xx / d, yy / d
    cxp, cyp = np.floor(gx), np.floor(gy)
    lx, ly = gx - cxp - 0.5, gy - cyp - 0.5
    flip = ((cxp + cyp) % 2) == 0
    ax, ay = np.where(flip, lx + ly, lx - ly), np.where(flip, lx - ly, lx + ly)
    lug = sstep(0.06, 0.0, np.abs(ax) * 0.35 + np.abs(ay) * 1.0 - 0.32)
    base = hexc('7f8f9e') * (0.88 + 0.12 * fbm(120)[..., None])
    base = base * (0.95 + 0.1 * per_id(pid, k * k, 71)[..., None])
    worn = sstep(0.2, 0.7, fbm(160))
    lugc = base * (1.0 + 0.25 * lug[..., None] * (0.5 + worn[..., None]))
    col = lugc
    # rust tears from the seams, paint on edges
    rs = sstep(0.4, 0.8, fbm(40) + 0.6 * (1 - seam)) * 0.6
    col = col * (1 - rs[..., None]) + hexc('8a5530') * rs[..., None]
    # bolts in the panel corners
    cdx = np.minimum(fx, 1 - fx) * N / k; cdy = np.minimum(fy, 1 - fy) * N / k
    bolt = sstep(8, 5, np.hypot(cdx - 22, cdy - 22))
    col = col * (1 - 0.3 * bolt[..., None]) + hexc('c9ccd0') * 0.3 * bolt[..., None]
    col = col * seam[..., None] + hexc('2c3036') * (1 - seam[..., None])
    col *= grime(220, 0.15)[..., None]
    h = 0.4 * seam + lug * 0.35 + bolt * 0.3
    rough = 0.45 - lug * 0.15 * worn + rs * 0.4 + (1 - seam) * 0.3
    save('tread', col, rough, h, 7.0)


# ------------------------------------------------------------------ crane yard: cast concrete slabs
def concrete():
    k = 2
    fx, fy = (U * k) % 1, (V * k) % 1
    pid = (np.floor(V * k) * k + np.floor(U * k)).astype(int)
    joint = sstep(0.004, 0.01, np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy)))
    base = hexc('b2aca2') * (0.9 + 0.1 * per_id(pid, k * k, 81)[..., None])
    base = base * (0.88 + 0.14 * fbm(140)[..., None])
    agg = sstep(0.55, 0.8, noise(1.6)) * 0.5 - sstep(0.55, 0.85, -noise(1.4)) * 0.3
    base = base * (1 + 0.15 * agg[..., None])
    # trowel swirls
    base *= (1 + 0.03 * noise(70, aniso=(1.0, 0.2)))[..., None]
    # cracks: thin lines of a warped Voronoi
    f1, f2, _, _, _ = voronoi(5, seed=82)
    wn = noise(30) * 0.04
    crack = sstep(0.015, 0.0, (f2 - f1) + wn) * sstep(0.2, 0.55, fbm(200))
    col = base * (1 - 0.55 * crack[..., None])
    stain = sstep(0.3, 0.8, fbm(90)) * 0.35
    col = col * (1 - stain[..., None]) + col * hexc('8a7e6c') * stain[..., None]
    col = col * joint[..., None] + hexc('4a4640') * (1 - joint[..., None])
    col *= grime(260, 0.15)[..., None]
    h = 0.5 * joint + agg * 0.04 - crack * 0.2
    rough = 0.85 - stain * 0.2
    save('concrete', col, rough, h, 6.0)


# ------------------------------------------------------------------ side faces (curbs, plinths): rough stone blocks
def side():
    rows = 4
    py = V * rows
    row = np.floor(py).astype(int)
    fy = py - row
    px = U * 3 + (row % 2) * 0.5
    pid = np.floor(px).astype(int)
    fx = px - pid
    j = sstep(0.01, 0.035, np.minimum(fy, 1 - fy)) * sstep(0.006, 0.02, np.minimum(fx, 1 - fx))
    uid = row * 8 + pid % 8
    base = pal(per_id(uid, 64, 91), ['bdb5a6', 'a99f90', 'c8bfae', 'b2a796'])
    base = base * (0.85 + 0.2 * fbm(50)[..., None])
    col = base * j[..., None] + hexc('5a5249') * (1 - j[..., None])
    h = j * (0.5 + 0.15 * fbm(20))
    save('side', col, np.full((N, N), 0.85, np.float32), h, 6.0)


# ------------------------------------------------------------------ macro noise (R: big blotches, G: medium, B: fine, A: streaks)
def macro():
    n = 512
    def nz(s, a=(1, 1)):
        w = rng.standard_normal((n, n))
        fy = np.fft.fftfreq(n)[:, None] * a[1]; fx = np.fft.fftfreq(n)[None, :] * a[0]
        f = np.sqrt(fx * fx + fy * fy)
        r = np.real(np.fft.ifft2(np.fft.fft2(w) * np.exp(-(f * s) ** 2 * 4)))
        r -= r.min(); return r / (r.max() + 1e-9)
    def fb(s):
        o = nz(s) * 0.55 + nz(s / 2) * 0.27 + nz(s / 4) * 0.13 + nz(s / 8) * 0.05
        o -= o.min(); return o / o.max()
    out = np.stack([fb(120), fb(40), fb(10), nz(30, (0.15, 1.0))], -1)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'macro.png'), optimize=True)
    print('wrote macro')


if __name__ == '__main__':
    deck(); junk(); cobble(); terracotta(); flagstone(); planks(); tread(); concrete(); side(); macro()
