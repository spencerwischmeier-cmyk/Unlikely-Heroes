// Shrinks the textures inside every .glb under a folder, in place (run on a COPY of godot/, see build.sh).
// Characters keep sharper textures than props: they fill the screen in cutscenes and up close.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { textureCompress, weld, simplify } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
import fs from 'fs';
import path from 'path';

const root = process.argv[2];
const BIG = Number(process.env.GLB_TEX_BIG || 1024);    // characters
const SMALL = Number(process.env.GLB_TEX_SMALL || 512);  // everything else
const isChar = p => /(^|\/)(vesk|hornet|roller|crew_roller|drone)\.glb$/.test(p) || p.includes('/chars/') || p.includes('/citizens/');

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const files = [];
(function walk(d) { for (const f of fs.readdirSync(d)) { const p = path.join(d, f); if (fs.statSync(p).isDirectory()) walk(p); else if (p.endsWith('.glb')) files.push(p); } })(root);
let before = 0, after = 0, simplified = 0;
const TRI_LIMIT = Number(process.env.GLB_TRI_LIMIT || 8000);
await MeshoptSimplifier.ready;
for (const p of files) {
  const s0 = fs.statSync(p).size; before += s0;
  const doc = await io.read(p);
  const root_ = doc.getRoot();
  let tris = 0;
  for (const m of root_.listMeshes()) for (const pr of m.listPrimitives()) { const i = pr.getIndices(); tris += (i ? i.getCount() : pr.getAttribute('POSITION').getCount()) / 3; }
  const steps = [];
  if (root_.listTextures().length) steps.push(textureCompress({ encoder: sharp, resize: isChar(p) ? [BIG, BIG] : [SMALL, SMALL], quality: 88 }));
  // heavy static props: half the triangles (animated / skinned models are left alone)
  if (tris > TRI_LIMIT && !isChar(p) && root_.listSkins().length === 0 && root_.listAnimations().length === 0) {
    steps.push(weld(), simplify({ simplifier: MeshoptSimplifier, ratio: TRI_LIMIT / tris > 0.5 ? TRI_LIMIT / tris : 0.5, error: Number(process.env.GLB_SIMPLIFY_ERROR || 0.01) }));
    simplified++;
  }
  if (steps.length) { await doc.transform(...steps); await io.write(p, doc); }
  after += fs.statSync(p).size;
}
console.log(`[glb] ${files.length} files, ${(before / 1e6).toFixed(1)} MB -> ${(after / 1e6).toFixed(1)} MB, ${simplified} heavy props simplified`);
