"""Ground decals for Skyharbor (RGBA, drawn top-down): oil stains, tyre marks, cracks, manhole and drain covers,
painted lane arrows and stripes, stencil text, chalk doodles and woven rugs. All original.
Run: python3 art/ground_decals.py   (writes godot/textures/ground/decals/*.png)
"""
import os, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'godot', 'textures', 'ground', 'decals')
os.makedirs(OUT, exist_ok=True)
FONT = os.path.join(HERE, '..', 'godot', 'fonts')
random.seed(5)
rng = np.random.default_rng(5)


def font(size):
    for f in os.listdir(FONT):
        if f.lower().startswith('lilita') and f.endswith('.ttf'):
            return ImageFont.truetype(os.path.join(FONT, f), size)
    return ImageFont.load_default()


def noise(n, scale):
    w = rng.standard_normal((n, n))
    k = np.fft.fftfreq(n)
    f = np.sqrt(k[:, None] ** 2 + k[None, :] ** 2)
    r = np.real(np.fft.ifft2(np.fft.fft2(w) * np.exp(-(f * scale) ** 2 * 4)))
    r -= r.min(); return r / (r.max() + 1e-9)


def save(name, img):
    img.save(os.path.join(OUT, name + '.png'), optimize=True)
    print('wrote', name)


def radial(n):
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    return np.hypot(x, y), np.arctan2(y, x)


def wear(img, amount=0.35, scale=6):
    """eat holes into the alpha so paint looks scuffed"""
    a = np.asarray(img).astype(np.float32)
    w, h = img.size
    nz = noise(max(w, h), scale)[:h, :w]
    a[..., 3] *= np.clip((nz - amount) * 4, 0, 1) * 0.6 + 0.4 * (nz > amount * 0.8)
    return Image.fromarray(a.astype(np.uint8), 'RGBA')


def oil(name, seed):
    n = 256
    r, a = radial(n)
    nz = noise(n, 18)
    blob = np.clip((0.75 + 0.35 * (nz - 0.5) * 2 - r) * 5, 0, 1)
    ring = np.clip(1 - np.abs(r - 0.55 - 0.1 * nz) * 12, 0, 1) * 0.3
    al = np.clip(blob * (0.55 + 0.25 * nz) + ring, 0, 0.85)
    col = np.zeros((n, n, 4), np.float32)
    col[..., 0] = 18 + 30 * nz; col[..., 1] = 16 + 22 * nz; col[..., 2] = 22 + 30 * nz
    col[..., 3] = al * 255
    save(name, Image.fromarray(col.astype(np.uint8), 'RGBA'))


def tyre():
    w, h = 128, 512
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    for x0 in (14, 78):
        for y in range(0, h, 14):
            d.polygon([(x0, y), (x0 + 36, y + 4), (x0 + 36, y + 10), (x0, y + 6)], fill=(25, 22, 20, 150))
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    a = np.asarray(img).astype(np.float32)
    fade = np.clip(np.sin(np.linspace(0, math.pi, h)) * 1.6, 0, 1)[:, None]
    a[..., 3] *= fade * noise(512, 30)[:, :w] * 1.4
    save('tyre', Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA'))


def crack(name):
    n = 512
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    def branch(x, y, ang, length, width):
        if length < 10 or width < 0.6: return
        steps = int(length / 12)
        for _ in range(steps):
            ang += random.uniform(-0.45, 0.45)
            nx, ny = x + math.cos(ang) * 12, y + math.sin(ang) * 12
            d.line([(x, y), (nx, ny)], fill=(30, 26, 22, 220), width=max(1, int(width)))
            x, y = nx, ny
            width *= 0.96
            if random.random() < 0.12: branch(x, y, ang + random.choice([-1, 1]) * random.uniform(0.6, 1.2), length * 0.5, width * 0.7)
    for k in range(3):
        branch(n / 2, n / 2, k * 2.1 + random.uniform(-0.3, 0.3), 260, 5)
    img = img.filter(ImageFilter.GaussianBlur(0.7))
    save(name, img)


def manhole(name, rim, face, pattern):
    n = 256
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.ellipse([6, 6, n - 6, n - 6], fill=rim + (255,))
    d.ellipse([22, 22, n - 22, n - 22], fill=face + (255,))
    c = n / 2
    dark = tuple(max(0, v - 45) for v in face) + (255,)
    light = tuple(min(255, v + 30) for v in face) + (255,)
    if pattern == 'gear':
        for i in range(12):
            a = i * math.tau / 12
            x, y = c + math.cos(a) * 70, c + math.sin(a) * 70
            d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=dark)
        d.ellipse([c - 42, c - 42, c + 42, c + 42], outline=dark, width=8)
        d.ellipse([c - 14, c - 14, c + 14, c + 14], fill=light)
    elif pattern == 'grid':
        lines = Image.new('L', (n, n), 0); ld = ImageDraw.Draw(lines)
        for i in range(-5, 6):
            ld.line([(c + i * 18, 0), (c + i * 18, n)], fill=255, width=6)
        mask = Image.new('L', (n, n), 0); ImageDraw.Draw(mask).ellipse([30, 30, n - 30, n - 30], fill=255)
        from PIL import ImageChops
        img.paste(Image.new('RGBA', (n, n), dark), (0, 0), ImageChops.multiply(lines, mask))
    else:   # radial slots (a drain)
        for i in range(16):
            a = i * math.tau / 16
            d.line([(c + math.cos(a) * 30, c + math.sin(a) * 30), (c + math.cos(a) * 92, c + math.sin(a) * 92)], fill=(20, 20, 22, 255), width=9)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    a = np.asarray(img).astype(np.float32)
    nz = noise(n, 10)
    a[..., :3] *= (0.8 + 0.35 * nz)[..., None]
    save(name, Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA'))


def arrow():
    w, h = 256, 512
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    col = (240, 200, 40, 235)
    d.rectangle([w / 2 - 34, 170, w / 2 + 34, h - 20], fill=col)
    d.polygon([(w / 2, 10), (w - 20, 190), (20, 190)], fill=col)
    save('arrow', wear(img, 0.3, 5))


def stripes():
    w, h = 512, 128
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    for i in range(-2, 12):
        x = i * 56
        d.polygon([(x, h), (x + 28, h), (x + 28 + h, 0), (x + h, 0)], fill=(245, 190, 30, 235))
    for i in range(-2, 12):
        x = i * 56 + 28
        d.polygon([(x, h), (x + 28, h), (x + 28 + h, 0), (x + h, 0)], fill=(30, 30, 34, 225))
    save('stripes', wear(img, 0.28, 4))


def stencil(name, text, color, w=1024, h=256, size=130):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    f = font(size)
    bb = d.textbbox((0, 0), text, font=f)
    d.text(((w - (bb[2] - bb[0])) / 2 - bb[0], (h - (bb[3] - bb[1])) / 2 - bb[1]), text, font=f, fill=color)
    save(name, wear(img, 0.3, 5))


def hopscotch():
    w, h = 256, 768
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    chalk = (250, 246, 236, 210)
    boxes = [(1, 0), (1, 1), (0, 2), (2, 2), (1, 3), (0, 4), (2, 4), (1, 5)]
    s = 84; ox = (w - 3 * s) / 2 + 2
    for bx, by in boxes:
        if by in (2, 4):
            x0 = w / 2 - s if bx == 0 else w / 2
        else:
            x0 = w / 2 - s / 2
        y0 = h - 40 - (by + 1) * s
        d.rectangle([x0, y0, x0 + s, y0 + s], outline=chalk, width=6)
    f = font(56)
    for i, (bx, by) in enumerate(boxes):
        x0 = (w / 2 - s if bx == 0 else w / 2) if by in (2, 4) else w / 2 - s / 2
        y0 = h - 40 - (by + 1) * s
        d.text((x0 + 26, y0 + 12), str(i + 1), font=f, fill=(250, 220, 120, 210))
    d.arc([w / 2 - 60, 10, w / 2 + 60, 110], 180, 360, fill=chalk, width=6)
    save('hopscotch', wear(img, 0.45, 2))


def chalk_bot():
    n = 512
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    c1 = (255, 170, 190, 220); c2 = (150, 220, 255, 220); c3 = (255, 240, 150, 220)
    # a grumpy round bot with a big X over it, drawn by a kid
    d.ellipse([140, 140, 372, 372], outline=c2, width=10)
    d.ellipse([200, 210, 240, 250], fill=c2); d.ellipse([272, 210, 312, 250], fill=c2)
    d.arc([200, 270, 312, 340], 200, 340, fill=c2, width=8)
    d.line([256, 140, 256, 90], fill=c2, width=8); d.ellipse([240, 66, 272, 98], fill=c3)
    d.line([110, 110, 400, 400], fill=c1, width=16); d.line([400, 110, 110, 400], fill=c1, width=16)
    for i in range(7):
        a = i * math.tau / 7
        d.line([(440 + math.cos(a) * 20, 70 + math.sin(a) * 20), (440 + math.cos(a) * 44, 70 + math.sin(a) * 44)], fill=c3, width=6)
    d.ellipse([424, 54, 456, 86], fill=c3)
    save('chalk_bot', wear(img, 0.4, 2))


def rug(name, cols):
    w, h = 384, 256
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.rectangle([12, 8, w - 12, h - 8], fill=cols[0] + (255,))
    d.rectangle([30, 26, w - 30, h - 26], outline=cols[1] + (255,), width=12)
    for i in range(5):
        cx = 70 + i * 61
        d.polygon([(cx, h / 2 - 50), (cx + 26, h / 2), (cx, h / 2 + 50), (cx - 26, h / 2)], fill=cols[2 if i % 2 == 0 else 1] + (255,))
        d.polygon([(cx, h / 2 - 22), (cx + 11, h / 2), (cx, h / 2 + 22), (cx - 11, h / 2)], fill=cols[0] + (255,))
    for x in range(14, w - 12, 8):
        d.line([(x, 0), (x, 8)], fill=cols[3] + (255,), width=3); d.line([(x, h - 8), (x, h)], fill=cols[3] + (255,), width=3)
    a = np.asarray(img).astype(np.float32)
    weave = (np.sin(np.arange(w)[None, :] * 1.6) * np.sin(np.arange(h)[:, None] * 1.6)) * 0.06 + 1
    a[..., :3] *= weave[..., None] * (0.88 + 0.2 * noise(w, 30)[:h, :w])[..., None]
    save(name, Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA'))


def leaves_patch():
    n = 512
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    cols = [(196, 120, 50), (214, 160, 60), (160, 90, 40), (120, 150, 60), (200, 80, 50)]
    for _ in range(90):
        r = random.gauss(0, 1) * 110
        a = random.random() * math.tau
        x, y = n / 2 + math.cos(a) * r, n / 2 + math.sin(a) * r
        s = random.uniform(10, 20); ang = random.random() * math.tau
        pts = [(x + math.cos(ang) * s, y + math.sin(ang) * s), (x + math.cos(ang + 1.9) * s * 0.45, y + math.sin(ang + 1.9) * s * 0.45),
               (x - math.cos(ang) * s, y - math.sin(ang) * s), (x + math.cos(ang - 1.9) * s * 0.45, y + math.sin(ang - 1.9) * s * 0.45)]
        d.polygon(pts, fill=random.choice(cols) + (235,))
    save('leaves', img)


def arena_ring():
    n = 1024
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    c = n / 2; y = (245, 196, 40, 230)
    d.ellipse([20, 20, n - 20, n - 20], outline=y, width=34)
    d.ellipse([150, 150, n - 150, n - 150], outline=(240, 236, 225, 200), width=12)
    for i in range(24):
        a = i * math.tau / 24
        r0, r1 = (n / 2 - 70), (n / 2 - 40)
        d.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * r1, c + math.sin(a) * r1)], fill=y, width=14)
    f = font(120)
    for txt, yy in (('LIFT', c - 140), ('ZONE', c + 10)):
        bb = d.textbbox((0, 0), txt, font=f)
        d.text((c - (bb[2] - bb[0]) / 2 - bb[0], yy), txt, font=f, fill=y)
    save('arena_ring', wear(img, 0.32, 6))


def skid():
    n = 768
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    for k, (r, w) in enumerate([(300, 26), (250, 26), (180, 20), (140, 20)]):
        a0 = random.uniform(150, 200); a1 = a0 + random.uniform(80, 140)
        d.arc([n / 2 - r, n / 2 - r, n / 2 + r, n / 2 + r], a0, a1, fill=(22, 20, 18, 170), width=w)
    img = img.filter(ImageFilter.GaussianBlur(2.0))
    save('skid', wear(img, 0.3, 10))


if __name__ == '__main__':
    arena_ring(); skid(); stencil('bay_text', 'BAY 7', (240, 236, 225, 230), 1024, 384, 300)
    oil('oil1', 1); oil('oil2', 2); tyre(); crack('crack')
    manhole('manhole_brass', (150, 118, 60), (120, 100, 70), 'gear')
    manhole('manhole_steel', (90, 94, 100), (70, 74, 80), 'grid')
    manhole('drain', (120, 116, 108), (96, 92, 86), 'drain')
    arrow(); stripes()
    stencil('pier_text', 'MIND THE GAP', (245, 240, 225, 230))
    stencil('yard_text', 'KEEP CLEAR', (245, 200, 40, 235))
    stencil('mast_text', 'NO LOITERING', (245, 240, 225, 220))
    hopscotch(); chalk_bot()
    rug('rug_a', [(170, 50, 40), (235, 190, 90), (40, 110, 120), (240, 230, 210)])
    rug('rug_b', [(40, 80, 130), (230, 160, 70), (200, 70, 60), (240, 230, 210)])
    leaves_patch()
