// Small shared helpers: seeded random, material and mesh shortcuts, canvas textures.
import * as THREE from 'three';

let seed = 1337;
export const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
export const R = (a, b) => a + (b - a) * rnd();
// gameplay randomness (not seeded, so every run plays differently)
export const rand = (a, b) => a + (b - a) * Math.random();

export const V = (x, y, z) => new THREE.Vector3(x, y, z);
export const UP = new THREE.Vector3(0, 1, 0);

export const std = (color, metalness = 0, roughness = 0.5, extra = {}) =>
  new THREE.MeshStandardMaterial({ color, metalness, roughness, ...extra });
export const glow = (color, intensity = 3) =>
  new THREE.MeshStandardMaterial({ color: 0x000000, emissive: color, emissiveIntensity: intensity, roughness: 1 });

export function mesh(geo, mat, cast = true, receive = true) {
  const m = new THREE.Mesh(geo, mat); m.castShadow = cast; m.receiveShadow = receive; return m;
}

// capsule from point a to point b
export function limb(a, b, r, mat) {
  const d = new THREE.Vector3().subVectors(b, a); const len = d.length();
  const m = mesh(new THREE.CapsuleGeometry(r, Math.max(0.001, len), 8, 20), mat);
  m.position.copy(a).add(b).multiplyScalar(0.5);
  m.quaternion.setFromUnitVectors(UP, d.normalize());
  return m;
}

export function canvasTex(w, h, draw, srgb = true) {
  const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); if (srgb) t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return t;
}

export const softDot = canvasTex(128, 128, (g, w) => {
  const gr = g.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2);
  gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(255,255,255,.55)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = gr; g.fillRect(0, 0, w, w);
});

export function glowSprite(color, size, opacity = 1, fog = false) {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: softDot, color, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity, fog }));
  s.scale.setScalar(size); return s;
}

export const damp = (a, b, lambda, dt) => a + (b - a) * (1 - Math.exp(-lambda * dt));
export const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
// shortest signed angle from a to b
export const angleDiff = (a, b) => { let d = (b - a) % (Math.PI * 2); if (d > Math.PI) d -= Math.PI * 2; if (d < -Math.PI) d += Math.PI * 2; return d; };
