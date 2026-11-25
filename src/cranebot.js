// Crane Bot: Foreman Grudd's heavy lifter and the Skyharbor mini-boss. A tracked crane with a magnet on a boom.
//   Magnet slam  the magnet tracks you, a red ring marks where it will land, then it drops
//   Rivet spray  a fan of hot rivets from the cab
//   Work crew    (second half) drops Scrap Rollers from the magnet
// The cab is the target. Shoot it.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { V, std, glow, mesh, glowSprite, rand, clamp, angleDiff } from './util.js';

export const BOSS_HP = 200;

export function createCraneBot(scene, fx) {
  const root = new THREE.Group(); root.visible = false; scene.add(root);
  const yellow = std(0xf0b21e, 0.45, 0.4), dark = std(0x2b3038, 0.8, 0.4), steel = std(0xb8c2cc, 0.85, 0.3), red = std(0x9b1f2a, 0.5, 0.4);
  const flashMats = [yellow, red];
  // tracked base
  for (const s of [-1, 1]) {
    const tr = mesh(new RoundedBoxGeometry(0.95, 1.1, 5, 3, 0.4), dark); tr.position.set(1.6 * s, 0.55, 0); root.add(tr);
    for (let i = -2; i <= 2; i++) { const wheel = mesh(new THREE.CylinderGeometry(0.38, 0.38, 1.0, 14), steel); wheel.rotation.z = Math.PI / 2; wheel.position.set(1.6 * s, 0.5, i * 0.95); root.add(wheel); }
  }
  const chassis = mesh(new RoundedBoxGeometry(2.6, 0.8, 4.2, 3, 0.15), yellow); chassis.position.y = 1.2; root.add(chassis);
  const stripe = mesh(new THREE.BoxGeometry(2.62, 0.18, 0.1), red); stripe.position.set(0, 1.2, 2.12); root.add(stripe);
  // turntable with the cab, counterweight and boom
  const turn = new THREE.Group(); turn.position.y = 1.6; root.add(turn);
  { const tt = mesh(new THREE.CylinderGeometry(1.5, 1.6, 0.35, 24), dark); tt.position.y = 0.1; turn.add(tt); }
  const cab = mesh(new RoundedBoxGeometry(2.4, 2.1, 2.3, 4, 0.3), yellow); cab.position.set(0, 1.35, 0.2); turn.add(cab);
  const eyeMat = glow(0xff2a2a, 6);
  const eye = mesh(new RoundedBoxGeometry(1.8, 0.42, 0.12, 2, 0.08), eyeMat, false, false); eye.position.set(0, 1.65, 1.37); turn.add(eye);
  const eyeGlow = glowSprite(0xff3030, 3.2, 0.7, true); eyeGlow.position.set(0, 1.65, 1.5); turn.add(eyeGlow);
  const grill = mesh(new RoundedBoxGeometry(1.4, 0.4, 0.1, 2, 0.05), dark); grill.position.set(0, 0.95, 1.37); turn.add(grill);
  for (const s of [-1, 1]) { const horn = mesh(new THREE.ConeGeometry(0.16, 0.6, 8), red); horn.position.set(0.95 * s, 2.55, 0.5); horn.rotation.z = -0.4 * s; turn.add(horn); }
  const weight = mesh(new RoundedBoxGeometry(2.6, 1.4, 1.2, 3, 0.2), dark); weight.position.set(0, 1.0, -1.7); turn.add(weight);
  const wstripe = mesh(new THREE.BoxGeometry(2.62, 0.2, 1.22), yellow); wstripe.position.set(0, 1.2, -1.7); turn.add(wstripe);
  // boom: a lattice arm that pivots at the top of the cab
  const boom = new THREE.Group(); boom.position.set(0, 2.5, 0.8); turn.add(boom);
  const BOOM = 10;
  for (const [x, y] of [[-0.35, -0.3], [0.35, -0.3], [-0.35, 0.3], [0.35, 0.3]]) { const bar = mesh(new THREE.BoxGeometry(0.12, 0.12, BOOM), yellow); bar.position.set(x, y, BOOM / 2); boom.add(bar); }
  for (let i = 0; i < 10; i++) {
    const z = 0.5 + i * 0.95;
    for (const [x, y, rz] of [[0, -0.3, 0], [0, 0.3, 0]]) { const c = mesh(new THREE.BoxGeometry(0.75, 0.06, 0.06), yellow); c.position.set(x, y, z); c.rotation.z = rz; boom.add(c); }
    for (const x of [-0.35, 0.35]) { const d = mesh(new THREE.BoxGeometry(0.06, 0.7, 0.06), yellow); d.position.set(x, 0, z + 0.45); d.rotation.x = 0.55; boom.add(d); }
  }
  const tip = new THREE.Object3D(); tip.position.set(0, -0.3, BOOM); boom.add(tip);
  const pulley = mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.3, 14), dark); pulley.rotation.z = Math.PI / 2; tip.add(pulley);
  // magnet and cable (in world space, under the tip)
  const magnet = new THREE.Group(); scene.add(magnet); magnet.visible = false;
  magnet.add(mesh(new THREE.CylinderGeometry(1.15, 1.25, 0.5, 24), dark));
  const magGlowMat = glow(0xff4030, 3);
  const magRing = mesh(new THREE.TorusGeometry(1.0, 0.08, 8, 32), magGlowMat, false, false); magRing.rotation.x = Math.PI / 2; magRing.position.y = -0.27; magnet.add(magRing);
  { const st = mesh(new THREE.CylinderGeometry(0.25, 0.25, 0.5, 10), steel); st.position.y = 0.45; magnet.add(st); }
  const cable = mesh(new THREE.CylinderGeometry(0.035, 0.035, 1, 6), dark, false, false); scene.add(cable); cable.visible = false;
  // warning ring on the floor
  const warnMat = new THREE.MeshBasicMaterial({ color: 0xff3020, transparent: true, opacity: 0.7, depthWrite: false, toneMapped: false });
  const warn = new THREE.Mesh(new THREE.RingGeometry(1.9, 2.3, 40), warnMat); warn.rotation.x = -Math.PI / 2; warn.visible = false; scene.add(warn);
  const warnFill = new THREE.Mesh(new THREE.CircleGeometry(2.3, 40), new THREE.MeshBasicMaterial({ color: 0xff3020, transparent: true, opacity: 0.18, depthWrite: false, toneMapped: false })); warnFill.rotation.x = -Math.PI / 2; warn.add(warnFill); warnFill.rotation.x = 0; warnFill.position.z = 0.001;
  root.traverse(o => { if (o.isMesh) o.castShadow = true; });

  const target = { type: 'boss', boss: true, name: 'CRANE BOT', pos: V(0, 0, 0), radius: 1.7, hp: BOSS_HP, maxHp: BOSS_HP, dead: true };
  const collider = { min: V(0, 0, 0), max: V(0, 0, 0) };
  const s = { t: 0, state: 'off', stT: 0, flash: 0, yaw: 0, turnYaw: 0, pitch: 0.45, mag: V(0, 6, 0), lock: V(0, 0, 0), sprays: 0, area: null, crewOut: 0, deathT: 0, lastAttack: '' };
  const tipW = V(0, 0, 0), heroFlat = V(0, 0, 0);

  function spawn(pos, area) {
    Object.assign(s, { t: 0, state: 'intro', stT: 2.2, flash: 0, yaw: Math.PI, turnYaw: 0, pitch: 0.6, sprays: 0, area, crewOut: 0, lastAttack: '' });
    root.position.copy(pos).setY(14); root.visible = magnet.visible = cable.visible = true;
    target.hp = BOSS_HP; target.dead = false;
    eyeMat.color.setHex(0xff2a2a);
  }
  function hide() { root.visible = magnet.visible = cable.visible = warn.visible = false; target.dead = true; s.state = 'off'; collider.min.set(0, -99, 0); collider.max.set(0, -99, 0); }
  hide();

  function damage(amount) {
    if (target.dead || s.state === 'intro' || s.state === 'dying') return false;
    const wasAngry = target.hp < BOSS_HP * 0.5;
    target.hp -= amount; s.flash = 1;
    if (!wasAngry && target.hp < BOSS_HP * 0.5 && target.hp > 0) s.halfHit = true;
    if (target.hp <= 0) { target.hp = 0; s.state = 'dying'; s.stT = 2.4; warn.visible = false; return true; }
    return false;
  }

  // ctx: { heroPos, alive, hurtHero(n, from), fireShot(from, to), spawnRoller(x, z), sound(name, pos), shake(n), onDead(pos) }
  function update(dt, ctx) {
    if (s.state === 'off') return;
    if (s.halfHit) { s.halfHit = false; ctx.onHalf?.(target.pos.clone()); }
    s.t += dt; s.stT -= dt;
    s.flash = Math.max(0, s.flash - dt * 7);
    flashMats.forEach(m => { m.emissive.setRGB(s.flash, s.flash * 0.9, s.flash * 0.8); m.emissiveIntensity = 1.5; });
    const angry = target.hp < BOSS_HP * 0.5;
    const speed = angry ? 1.35 : 1;
    heroFlat.set(ctx.heroPos.x, 0, ctx.heroPos.z);
    const toHero = heroFlat.clone().sub(root.position.clone().setY(0)); const hd = toHero.length();

    if (s.state === 'intro') {
      root.position.y = Math.max(0, root.position.y - dt * 16);
      if (root.position.y === 0 && !s.landed) { s.landed = true; fx.explosion(root.position.clone().add(V(0, 0.3, 0)), 1.2); ctx.shake(1.2); ctx.sound('explosion', root.position); }
      if (s.stT <= 0) { s.state = 'idle'; s.stT = 0.8; s.landed = false; }
    } else if (s.state === 'dying') {
      if (Math.random() < dt * 14) { const p = target.pos.clone().add(V(rand(-1.8, 1.8), rand(-1.5, 1.5), rand(-1.8, 1.8))); fx.explosion(p, rand(0.4, 0.8)); ctx.sound('explosion', p); }
      root.rotation.z = Math.sin(s.t * 30) * 0.03;
      s.pitch = Math.max(-0.1, s.pitch - dt * 0.4);
      if (s.stT <= 0) {
        fx.explosion(target.pos.clone(), 2.2); fx.explosion(root.position.clone().add(V(0, 1, 0)), 2); ctx.shake(2);
        const at = target.pos.clone(); hide(); ctx.onDead(at);
        return;
      }
    } else {
      // drive: keep about 9 m from the hero, inside the yard
      if (s.state === 'idle' || s.state === 'spray') {
        const want = hd > 11 ? 1 : hd < 7 ? -1 : 0;
        if (want) {
          const dir = toHero.clone().normalize().multiplyScalar(want * 1.6 * speed * dt);
          root.position.add(dir);
          s.yaw += angleDiff(s.yaw, Math.atan2(toHero.x, toHero.z) + (want < 0 ? Math.PI : 0)) * (1 - Math.exp(-1.5 * dt));
        }
      }
      if (s.area) { root.position.x = clamp(root.position.x, s.area.minX + 3, s.area.maxX - 3); root.position.z = clamp(root.position.z, s.area.minZ + 3, s.area.maxZ - 3); }
      // turntable faces the hero (or the slam point)
      const aim = s.state === 'slam' && s.stT < 0.4 ? s.lock : heroFlat;
      const wantTurn = Math.atan2(aim.x - root.position.x, aim.z - root.position.z);
      s.turnYaw += angleDiff(s.turnYaw, wantTurn) * (1 - Math.exp(-(s.state === 'slam' ? 3.5 : 2.5) * speed * dt));

      if (s.state === 'idle' && s.stT <= 0) {
        const opts = ['slam', 'spray']; if (angry && s.crewOut < 3) opts.push('crew');
        let next = opts[Math.floor(Math.random() * opts.length)];
        if (next === s.lastAttack && Math.random() < 0.6) next = opts[(opts.indexOf(next) + 1) % opts.length];
        s.lastAttack = next; s.state = next;
        if (next === 'slam') { s.stT = 1.85 / speed; warn.visible = true; ctx.sound('enemyCharge', target.pos); }
        if (next === 'spray') { s.stT = 0.8; s.sprays = angry ? 2 : 1; }
        if (next === 'crew') { s.stT = 1.2; }
      }
      // the magnet hangs from the boom tip; how far the boom reaches depends on its pitch
      const flatReach = Math.hypot(ctx.heroPos.x - root.position.x, ctx.heroPos.z - root.position.z);
      if (s.state === 'slam') {
        if (s.stT > 0.4) {
          s.lock.copy(heroFlat);
          // the boom can't reach closer than about 5.3 m, or further than 11 m
          const off = s.lock.clone().sub(root.position).setY(0), l = off.length(), minR = 0.8 + BOOM * Math.cos(1.1);
          if (l < minR) s.lock.copy(root.position).setY(0).addScaledVector(l > 0.01 ? off.divideScalar(l) : V(Math.sin(s.turnYaw), 0, Math.cos(s.turnYaw)), minR);
        }
        const reach = clamp(Math.hypot(s.lock.x - root.position.x, s.lock.z - root.position.z), 4, 10.5);
        s.pitch += (Math.min(1.1, Math.acos(clamp((reach - 0.8) / BOOM, -1, 1))) - s.pitch) * (1 - Math.exp(-6 * dt));
        warn.position.set(s.lock.x, 0.04, s.lock.z);
        warnMat.opacity = s.stT > 0.4 ? 0.5 + Math.sin(s.t * 20) * 0.2 : 0.95;
        warn.scale.setScalar(s.stT > 0.4 ? 1 : 1 + (0.4 - s.stT) * 0.3);
        if (s.stT <= 0) {
          s.state = 'drop'; s.stT = 0.18;
        }
      } else if (s.state === 'spray') {
        s.pitch += (0.9 - s.pitch) * (1 - Math.exp(-3 * dt));
        if (s.stT <= 0 && ctx.alive) {
          const from = target.pos.clone().add(V(Math.sin(s.turnYaw) * 1.4, -0.1, Math.cos(s.turnYaw) * 1.4));
          const to = ctx.heroPos.clone().add(V(0, 0.9, 0));
          const base = Math.atan2(to.x - from.x, to.z - from.z), n = angry ? 7 : 5, spread = angry ? 1.0 : 0.8;
          const dist = Math.hypot(to.x - from.x, to.z - from.z);
          for (let i = 0; i < n; i++) {
            const a = base + (i / (n - 1) - 0.5) * spread;
            ctx.fireShot(from, V(from.x + Math.sin(a) * dist, to.y, from.z + Math.cos(a) * dist));
          }
          ctx.sound('enemyShot', from);
          s.sprays--; s.stT = 0.55;
          if (s.sprays <= 0) { s.state = 'idle'; s.stT = rand(1.4, 2.0) / speed; }
        }
      } else if (s.state === 'crew') {
        s.pitch += (0.5 - s.pitch) * (1 - Math.exp(-3 * dt));
        if (s.stT <= 0) {
          for (let i = 0; i < 2; i++) {
            const a = rand(0, Math.PI * 2), r = rand(4, 7);
            let x = ctx.heroPos.x + Math.sin(a) * r, z = ctx.heroPos.z + Math.cos(a) * r;
            if (s.area) { x = clamp(x, s.area.minX + 1.5, s.area.maxX - 1.5); z = clamp(z, s.area.minZ + 1.5, s.area.maxZ - 1.5); }
            ctx.spawnRoller(x, z); s.crewOut++;
          }
          s.state = 'idle'; s.stT = 1.2 / speed;
        }
      } else if (s.state === 'idle') {
        s.pitch += (0.55 - s.pitch) * (1 - Math.exp(-2 * dt));
      }
    }

    // pose
    root.rotation.y = s.yaw;
    turn.rotation.y = s.turnYaw - s.yaw;
    boom.rotation.x = -s.pitch;
    root.updateMatrixWorld(true);
    tip.getWorldPosition(tipW);
    // magnet: hangs at 6 m, drops in a slam, sits for a moment, then rises
    let magY;
    if (s.state === 'drop') {
      magY = Math.max(0.3, s.mag.y - dt * 60);
      if (magY <= 0.3) {
        const hx = s.mag.x, hz = s.mag.z; // where the magnet actually came down
        fx.explosion(V(hx, 0.3, hz), 1.1); fx.ring(V(hx, 0.06, hz), 0xff5030); ctx.shake(1.3); ctx.sound('explosion', V(hx, 0, hz));
        if (ctx.alive && Math.hypot(ctx.heroPos.x - hx, ctx.heroPos.z - hz) < 2.2 && ctx.heroPos.y < 1.4) ctx.hurtHero(2, V(hx, 0, hz));
        s.state = 'hold'; s.stT = 0.8 / speed; warn.visible = false;
      }
    } else if (s.state === 'hold') { magY = 0.3; if (s.stT <= 0) { s.state = 'idle'; s.stT = rand(1.3, 1.9) / speed; } }
    else magY = s.mag.y + (Math.min(tipW.y - 1.5, 6) - s.mag.y) * (1 - Math.exp(-3 * dt));
    s.mag.set(tipW.x, magY, tipW.z);
    magnet.position.copy(s.mag);
    magGlowMat.emissiveIntensity = s.state === 'slam' || s.state === 'drop' ? 8 : 3;
    const top = tipW.clone(), bot = s.mag.clone().add(V(0, 0.6, 0));
    cable.position.copy(top).add(bot).multiplyScalar(0.5); cable.scale.set(1, Math.max(0.05, top.distanceTo(bot)), 1);
    // weak point = the cab
    cab.getWorldPosition(target.pos);
    eyeMat.emissiveIntensity = (angry ? 10 : 6) + Math.sin(s.t * (angry ? 14 : 5)) * 3;
    eyeGlow.scale.setScalar(angry ? 4 : 3.2);
    if (angry) eyeMat.color.setHex(0xff5a1a);
    // solid body so you can't walk through it
    collider.min.set(root.position.x - 2.1, 0, root.position.z - 2.1); collider.max.set(root.position.x + 2.1, root.position.y + 1.6, root.position.z + 2.1);
  }

  return {
    target, collider, spawn, hide, damage, update,
    get active() { return s.state !== 'off'; },
    get dying() { return s.state === 'dying'; },
    get state() { return s.state; },
    crewDown() { s.crewOut = Math.max(0, s.crewOut - 1); },
  };
}
