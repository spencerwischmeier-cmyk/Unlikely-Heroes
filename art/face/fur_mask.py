# Fur mask for Vesk's shell fur (godot/textures/vesk_fur_mask.png): white where the Meshy texture is fur
# (rough, non-metal, grey-brown, not the pink muzzle/ears), black on armour, straps and skin.
#   python3 fur_mask.py <albedo vesk_Image_0.jpg> <metal-rough vesk_Image_1.png> <out.png>
import sys, numpy as np
from PIL import Image, ImageFilter
a = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(np.float32) / 255
m = np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(np.float32) / 255
mx, mn, lum = a.max(2), a.min(2), a.mean(2)
sat = (mx - mn) / np.maximum(mx, 1e-3)
rough, metal = m[..., 1], m[..., 2]
skin = (a[..., 0] > a[..., 2] + 0.08) & (lum > 0.5)
fur = (metal < 0.3) & (rough > 0.55) & (sat < 0.28) & (lum > 0.18) & (lum < 0.72) & ~skin
f = Image.fromarray((fur * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.GaussianBlur(2))
f.resize((1024, 1024), Image.LANCZOS).save(sys.argv[3], optimize=True)
print('fur coverage', round(float(fur.mean()), 3))
