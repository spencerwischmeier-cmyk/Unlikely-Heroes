// Character models made in Blender (see art/). Loaded once at startup; the game falls back to the
// basic-shape versions if a model fails to load.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const NAMES = ['hero', 'drone', 'roller', 'hornet', 'wpn_scatter', 'wpn_lobber', 'wpn_seeker'];

export async function loadModels(onProgress) {
  const loader = new GLTFLoader();
  const out = {};
  let done = 0;
  await Promise.all(NAMES.map(async n => {
    try {
      const gltf = await loader.loadAsync(`./models/${n}.glb`);
      gltf.scene.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
      out[n] = gltf.scene;
    } catch (e) { console.warn(`model ${n} failed to load, using basic shapes`, e); }
    onProgress?.(++done / NAMES.length);
  }));
  return out;
}

// Give an instance its own copies of the named materials (so it can flash or glow on its own).
export function ownMaterials(root, names) {
  const map = new Map();
  root.traverse(o => {
    if (!o.isMesh || !names.includes(o.material.name)) return;
    if (!map.has(o.material.name)) map.set(o.material.name, o.material.clone());
    o.material = map.get(o.material.name);
  });
  return map;
}

// Fewer draw calls: under every node, merge the plain child meshes that share a material into one mesh.
export function mergeByMaterial(root) {
  const holders = [];
  root.traverse(o => holders.push(o));
  for (const h of holders) {
    const groups = new Map();
    for (const c of h.children) {
      if (!c.isMesh || c.children.length || c.isSkinnedMesh) continue;
      const key = c.material.uuid;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(c);
    }
    for (const list of groups.values()) {
      if (list.length < 2) continue;
      const geos = list.map(m => {
        m.updateMatrix();
        let g = m.geometry.clone().applyMatrix4(m.matrix);
        if (g.index !== null) g = g.toNonIndexed();
        for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(k)) g.deleteAttribute(k);
        if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
        return g;
      });
      const merged = mergeGeometries(geos, false);
      if (!merged) continue;
      const m = new THREE.Mesh(merged, list[0].material);
      m.name = list[0].name + '_merged'; m.castShadow = m.receiveShadow = true;
      list.forEach(x => h.remove(x));
      h.add(m);
    }
  }
  return root;
}
