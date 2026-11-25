"""Tileable surface textures for Skyharbor (deck panels, painted metal, brass, hazard stripes, sailcloth,
rubber) plus the sign decals the kit uses. Every surface gets an albedo, a normal map (OpenGL style, green up,
which is what Godot expects) and a roughness map. Pure numpy + Pillow, no Blender needed.
Run: python3 art/skyharbor_textures.py   (writes godot/textures/*.png)
"""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'godot', 'textures')
os.makedirs(OUT, exist_ok=True)
N = 512
rng = np.random.default_rng(7)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)


# ---------- tileable noise (FFT filtered white noise is periodic by construction) ----------
def noise(scale, n=None, aniso=(1.0, 1.0)):
    """Smooth periodic noise in [-1, 1]; `scale` is the feature size in pixels. aniso stretches it (x, y)."""
    n = n or N
    w = rng.standard_normal((n, n))
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    g = np.exp(-(f * scale) ** 2 * 4)
    r = np.real(np.fft.ifft2(np.fft.fft2(w) * g))
    r -= r.mean(); r /= (np.abs(r).max() + 1e-9)
    return r.astype(np.float32)


def fbm(base, octaves=4, aniso=(1.0, 1.0)):
    out = np.zeros((N, N), np.float32); amp = 1.0; tot = 0
    for i in range(octaves):
        out += noise(base / 2 ** i, aniso=aniso) * amp; tot += amp; amp *= 0.5
    return out / tot


def blur(a, r):
    if r <= 0: return a
    k = np.fft.fftfreq(N)
    f = np.sqrt(k[:, None] ** 2 + k[None, :] ** 2)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * np.exp(-(f * r) ** 2 * 8))).astype(np.float32)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save(name, a, mode=None):
    a = np.clip(a, 0, 1)
    if a.ndim == 2: img = Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'L')
    else: img = Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGB')
    img.save(os.path.join(OUT, name + '.png'), optimize=True)
    print('wrote', name)


def rgb(c): return np.array([((c >> 16) & 255) / 255, ((c >> 8) & 255) / 255, (c & 255) / 255], np.float32)


def scratches(count, length=(20, 90), width=1, angle_spread=math.pi):
    """Thin random scratch lines (periodic wrap) as a [0,1] mask."""
    img = Image.new('L', (N * 3, N * 3), 0); d = ImageDraw.Draw(img)
    base_a = rng.uniform(0, math.tau)
    for _ in range(count):
        x, y = rng.uniform(0, N, 2); a = base_a + rng.uniform(-angle_spread, angle_spread) / 2
        L = rng.uniform(*length); v = int(rng.uniform(90, 255))
        for ox in (0, N, 2 * N):
            for oy in (0, N, 2 * N):
                d.line([(x + ox, y + oy), (x + ox + math.cos(a) * L, y + oy + math.sin(a) * L)], fill=v, width=width)
    return np.asarray(img, np.float32)[N:2 * N, N:2 * N] / 255


def rounded_rect_height(x0, y0, x1, y1, bevel, h):
    """Height field of a raised panel with chamfered edges (pixel coords, may wrap)."""
    dx = np.minimum(xx - x0, x1 - xx); dy = np.minimum(yy - y0, y1 - yy)
    d = np.minimum(dx, dy)
    return np.clip(d / bevel, 0, 1) * h * ((dx > 0) & (dy > 0))


def bolt_mask(cx, cy, r):
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    return np.clip(1 - (d / r) ** 2, 0, 1) ** 0.5


# ======================= deck panels =======================
def deck():
    # 1024 px tile of 4x4 plates (mats.gd maps one plate to ~1.8 m). Plates are plain, diamond tread, split in
    # four, or vented, picked at random so the repeat is hard to spot.
    global N, xx, yy
    N0 = N; N = 1024
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    h = np.zeros((N, N), np.float32)
    alb = np.ones((N, N), np.float32) * 0.86
    S = N // 4; gap = 5
    kinds = ['plain'] * 7 + ['tread'] * 3 + ['quad'] * 4 + ['vent'] * 2
    rng.shuffle(kinds)
    for i in range(4):
        for j in range(4):
            x0, y0 = i * S + gap, j * S + gap; x1, y1 = (i + 1) * S - gap, (j + 1) * S - gap
            k = kinds[i * 4 + j]
            plate = rounded_rect_height(x0, y0, x1, y1, 6, 1.0)
            h += plate
            inside = plate > 0
            tone = rng.uniform(-0.05, 0.04)
            alb[inside] += tone
            if k == 'tread':
                u = (xx - x0) / 22; v = (yy - y0) / 22
                a = np.abs(((u + v) % 1) - 0.5) < 0.12
                b = np.abs(((u - v) % 1) - 0.5) < 0.12
                cell = ((np.floor(u) + np.floor(v)) % 2 == 0)
                m = np.where(cell, a, b) & (rounded_rect_height(x0 + 14, y0 + 14, x1 - 14, y1 - 14, 3, 1) > 0.5)
                h += m * 0.35
                alb += m * 0.03
            elif k == 'quad':
                mx, my = (x0 + x1) / 2, (y0 + y1) / 2
                groove = (np.abs(xx - mx) < 2) | (np.abs(yy - my) < 2)
                h -= groove * inside * 0.6
                alb -= groove * inside * 0.18
            elif k == 'vent':
                for s in range(6):
                    sy = y0 + 40 + s * 30
                    slot = rounded_rect_height(x0 + 50, sy, x1 - 50, sy + 12, 4, 1.0)
                    h -= slot * 1.1
                    alb -= (slot > 0.3) * 0.3
            # corner bolts
            for (bx, by) in ((x0 + 14, y0 + 14), (x1 - 14, y0 + 14), (x0 + 14, y1 - 14), (x1 - 14, y1 - 14)):
                b = bolt_mask(bx, by, 6)
                h += b * 0.5
                alb += (b > 0) * 0.05
    # seams between plates are dark
    seam = h < 0.05
    alb[seam] = 0.42
    # grime gathers in seams and along plate edges, plus soft blotches and scuffs
    cav = np.clip(blur(h, 3) - h, 0, 1)
    grime = np.clip(fbm(140) * 0.5 + 0.5, 0, 1)
    alb *= 1 - 0.12 * grime
    alb -= np.clip(1.0 - blur((h > 0.2).astype(np.float32), 4), 0, 1) * 0.12
    sc = scratches(500, (10, 60))
    alb += sc * 0.08
    alb += fbm(6, 2) * 0.025
    h += fbm(3, 2) * 0.02 - sc * 0.05
    rough = 0.52 + grime * 0.18 - sc * 0.2 + fbm(30, 2) * 0.05
    rough[seam] = 0.85
    a3 = np.stack([alb * 0.97, alb * 0.99, alb * 1.02], -1)
    save('deck_albedo', a3); save('deck_normal', normal_from_height(h, 2.2)); save('deck_rough', rough)
    N = N0; yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)


# ======================= painted metal (tintable, near white) =======================
def paint():
    blot = fbm(120)
    speck = fbm(4, 2)
    sc = scratches(220, (6, 40))
    chips = np.clip((fbm(18, 3) - 0.55) * 8, 0, 1)  # small paint chips showing bare metal
    alb = 0.93 + blot * 0.04 + speck * 0.015
    alb = alb * (1 - chips * 0.45) + sc * 0.05
    h = speck * 0.04 + blur(noise(10), 1) * 0.03 - chips * 0.25 - sc * 0.15
    rough = 0.4 + blot * 0.06 + chips * 0.25 - sc * 0.15
    # faint panel seam every half tile so big flat faces read as plates
    seam = ((np.abs(yy - N / 2) < 1.5) | (yy < 1.5)).astype(np.float32)
    rivets = np.zeros_like(h)
    for k in range(16):
        for row in (8, N / 2 + 8):
            rivets = np.maximum(rivets, bolt_mask(k * 32 + 16, row, 3.2))
    h += rivets * 0.4 - seam * 0.5
    alb = alb - seam * 0.25 + (rivets > 0) * 0.02
    a3 = np.stack([alb, alb, alb], -1)
    save('paint_albedo', a3); save('paint_normal', normal_from_height(h, 2.0)); save('paint_rough', rough)


# ======================= brass =======================
def brass():
    brush = noise(60, aniso=(0.04, 1.0)) * 0.5 + noise(10, aniso=(0.05, 1.0)) * 0.5  # streaks along x
    patina = np.clip(fbm(90) * 1.4, 0, 1)
    base = rgb(0xe0a84a); dark = rgb(0x8a5a22); green = rgb(0x6f8f6a)
    t = (brush * 0.5 + 0.5)[..., None]
    alb = base * (0.88 + 0.14 * t) * (1 - patina[..., None] * 0.35) + dark * patina[..., None] * 0.2
    pg = np.clip((fbm(40, 3) - 0.45) * 4, 0, 1)[..., None] * 0.25
    alb = alb * (1 - pg) + green * pg
    sc = scratches(120, (10, 60), angle_spread=0.3)
    alb += sc[..., None] * 0.08
    h = brush * 0.06 - sc * 0.1
    rough = 0.24 + patina * 0.25 + pg[..., 0] * 1.2 - sc * 0.08 + (brush * 0.5 + 0.5) * 0.06
    save('brass_albedo', alb); save('brass_normal', normal_from_height(h, 2.0)); save('brass_rough', rough)


# ======================= hazard stripes =======================
def hazard():
    period = 128
    s = ((xx + yy) % period) < period / 2
    yel = rgb(0xffc21c); blk = rgb(0x1d1e22)
    wear = np.clip((fbm(26, 4) - 0.35) * 5, 0, 1)
    edge = np.abs(((xx + yy) % (period / 2)) - period / 4) / (period / 4)  # 1 at stripe borders
    alb = np.where(s[..., None], yel, blk).astype(np.float32)
    alb *= (0.92 + fbm(80)[..., None] * 0.08)
    bare = np.clip(wear * (0.4 + edge * 0.8) - 0.4, 0, 1)[..., None]
    metal = rgb(0x6e737a) * (0.9 + fbm(5, 2)[..., None] * 0.1)
    alb = alb * (1 - bare) + metal * bare
    sc = scratches(140, (8, 50))
    alb += sc[..., None] * 0.12
    h = -bare[..., 0] * 0.4 - sc * 0.1 + fbm(4, 2) * 0.02
    rough = 0.48 + bare[..., 0] * -0.12 + fbm(60) * 0.06 + (~s) * 0.06
    save('hazard_albedo', alb); save('hazard_normal', normal_from_height(h, 2.5)); save('hazard_rough', rough)


# ======================= sailcloth (tintable) =======================
def cloth():
    t = 8.0
    wu = np.sin(xx / t * math.pi) ; wv = np.sin(yy / t * math.pi)
    over = (np.floor(xx / t) + np.floor(yy / t)) % 2
    hw = np.where(over > 0, np.abs(wu) * 0.6 + 0.4 * np.abs(np.cos(yy / t * math.pi)), np.abs(wv) * 0.6 + 0.4 * np.abs(np.cos(xx / t * math.pi)))
    h = hw * 0.5 + fbm(60) * 0.3
    alb = 0.9 + hw * 0.06 + fbm(100) * 0.04 + noise(2) * 0.02
    # a doubled seam band every half tile like stitched sail panels
    seam = (np.abs((yy % (N / 2)) - 6) < 4)
    stitch = seam & ((xx % 10) < 5) & (np.abs((yy % (N / 2)) - 6) < 1.2)
    h += seam * 0.4
    alb -= stitch * 0.25
    rough = 0.82 + fbm(40) * 0.06
    a3 = np.stack([alb, alb * 0.99, alb * 0.96], -1)
    save('cloth_albedo', a3); save('cloth_normal', normal_from_height(h, 1.6)); save('cloth_rough', rough)


# ======================= rubber / grip =======================
def rubber():
    h = fbm(3, 2) * 0.3 + fbm(50) * 0.2
    knurl = (np.abs(((xx + yy) / 16) % 1 - 0.5) < 0.08) | (np.abs(((xx - yy) / 16) % 1 - 0.5) < 0.08)
    h -= knurl * 0.3
    alb = 0.9 + fbm(70) * 0.06 - knurl * 0.06
    rough = 0.75 + fbm(40) * 0.08
    save('rubber_albedo', np.stack([alb] * 3, -1)); save('rubber_normal', normal_from_height(h, 1.5)); save('rubber_rough', rough)


# ======================= wood planks (tintable warm) =======================
def wood():
    grain = noise(40, aniso=(0.03, 1.0)) * 0.6 + noise(6, aniso=(0.08, 1.0)) * 0.4  # long grain along x
    rings = np.sin((yy + noise(90) * 40) / 7.0) * 0.5 + 0.5
    plank = (yy % 128)
    gap = (plank < 3).astype(np.float32)
    tone = np.zeros_like(yy)
    for k in range(4): tone[(yy >= k * 128) & (yy < (k + 1) * 128)] = rng.uniform(-0.08, 0.08)
    v = 0.78 + grain * 0.12 + rings * 0.06 + tone
    v = v * (1 - gap * 0.6)
    knots = np.zeros_like(v)
    for _ in range(5):
        cx, cy = rng.uniform(0, N, 2)
        d = np.sqrt(((xx - cx + N / 2) % N - N / 2) ** 2 / 3 + ((yy - cy + N / 2) % N - N / 2) ** 2)
        knots = np.maximum(knots, np.clip(1 - d / 10, 0, 1))
    v -= knots * 0.25
    base = rgb(0xb07a48)
    alb = base * v[..., None]
    h = grain * 0.15 + rings * 0.05 - gap * 0.8 - knots * 0.1
    rough = 0.62 + grain * 0.08 + gap * 0.2
    save('wood_albedo', alb); save('wood_normal', normal_from_height(h, 2.0)); save('wood_rough', rough)


# ======================= sign decals (UV mapped on the kit's sign faces) =======================
def font(sz):
    for p in ('/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf', '/usr/share/fonts/opentype/inter/Inter-Bold.otf',
              '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'):
        if os.path.exists(p): return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def sign(name, w, h, bg, fg, lines, accent=None, arrow=False):
    img = Image.new('RGB', (w, h), bg); d = ImageDraw.Draw(img)
    pad = int(h * 0.07)
    d.rounded_rectangle([pad // 2, pad // 2, w - pad // 2, h - pad // 2], radius=pad, outline=accent or fg, width=max(4, pad // 3))
    n = len(lines); y = h / 2 - (n - 1) * h * 0.18
    for i, (txt, rel) in enumerate(lines):
        sz = int(h * rel); f = font(sz); tw = d.textlength(txt, font=f)
        avail = w * 0.86 - (h * 0.5 if arrow else 0)
        while tw > avail and sz > 8:
            sz -= 2; f = font(sz); tw = d.textlength(txt, font=f)
        d.text(((w - tw) / 2 - (h * 0.12 if arrow else 0), y - sz * 0.62), txt, font=f, fill=fg)
        y += h * 0.36
    if arrow:
        ax = w - h * 0.42; ay = h / 2; s = h * 0.18
        d.polygon([(ax - s, ay - s), (ax + s * 0.6, ay), (ax - s, ay + s)], fill=accent or fg)
    img = img.filter(ImageFilter.SMOOTH)
    img.save(os.path.join(OUT, name + '.png')); print('wrote', name)


def decals():
    sign('sign_dock', 1024, 512, (30, 54, 74), (246, 240, 222), [('DOCK PLAZA', 0.22), ('CARGO  -  TERRACE  -  MAST', 0.09)], accent=(255, 176, 52), arrow=True)
    sign('sign_gizmart', 1024, 256, (255, 196, 40), (40, 30, 60), [('GIZMART', 0.62)], accent=(232, 62, 92))
    sign('sign_crane', 2048, 256, (40, 44, 52), (255, 196, 40), [('CRANE YARD', 0.46), ('AUTHORIZED BOTS ONLY', 0.17)], accent=(255, 196, 40))
    sign('sign_junk', 1024, 256, (140, 70, 40), (250, 236, 200), [("VESK'S SALVAGE", 0.4), ('no refunds, no regrets', 0.16)], accent=(250, 236, 200))
    sign('sign_vault', 512, 256, (36, 40, 48), (220, 180, 90), [('SKYHARBOR', 0.22), ('SAVINGS & LOAN', 0.15)], accent=(220, 180, 90))


if __name__ == '__main__':
    deck(); paint(); brass(); hazard(); cloth(); rubber(); wood(); decals()
