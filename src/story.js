// Story mode, Skyharbor: walk into each area to start its fight, clear it to open the next grind rail,
// knock out Grudd's signal relay on the mast, then beat the Crane Bot in the Crane Yard.
import * as THREE from 'three';
import { V, rand } from './util.js';
import { ISLANDS, MAST } from './skyharbor.js';
import { GIZ_LINES } from './gizmart.js';

const pick = a => a[Math.floor(Math.random() * a.length)];
const inRect = (p, r, m = 0) => p.x > r.minX - m && p.x < r.maxX + m && p.z > r.minZ - m && p.z < r.maxZ + m;
const RELAY_HP = 30;

const ZONES = [
  { id: 'dock', name: 'SKYHARBOR DOCKS', rect: ISLANDS.dock, y: 0, delay: 3.5, check: V(0, 0, 64),
    waves: [['roller', 'roller', 'roller']],
    goal: 'Clear the dock',
    intro: [['dodger', 'Bots! On OUR dock! Somebody left the haywire on.'], ['vesk', 'I just wanted one quiet day.']],
    clear: [['dodger', 'Dock clear. The sky steps lead to the Market Terrace. Mind the gaps.'], ['vesk', 'I always mind the gaps.']], next: 'Cross the sky steps to the Market Terrace' },
  { id: 'terrace', name: 'MARKET TERRACE', rect: ISLANDS.terrace, y: 0, delay: 1.4, check: V(2, 0, 13),
    waves: [['roller', 'roller', 'hornet'], ['roller', 'hornet', 'roller', 'roller']],
    goal: 'Clear the Market Terrace',
    intro: [['dodger', 'The market! Usually it smells like noodles. Today it smells like angry bots.']],
    clear: [['dodger', 'See that green pad? Bounce up to the lookout, then grab the swing hooks across.'], ['vesk', 'Swing. Over the sky. Wonderful.']], next: 'Bounce up to the lookout, then swing across' },
  { id: 'cargo', name: 'CARGO YARD', rect: ISLANDS.cargo, y: 0, delay: 1.2, check: V(12, 0, -50), unlock: 0,
    waves: [['roller', 'hornet', 'roller', 'roller'], ['hornet', 'roller', 'hornet', 'roller', 'roller']],
    goal: 'Clear the Cargo Yard',
    intro: [['dodger', 'Cargo Yard. Look, a welcome committee.']],
    clear: [['dodger', 'The signal is stronger up on that tower. Rail is open.'], ['vesk', 'Of course it is up.']], next: 'Ride up to the Signal Mast' },
  { id: 'mast', name: 'SIGNAL MAST', rect: MAST, y: MAST.top, delay: 0.6, check: V(12, MAST.top, -91), unlock: 1, relay: true,
    waves: [['hornet', 'hornet'], ['hornet', 'hornet', 'hornet']],
    goal: 'Destroy the signal relay',
    intro: [['dodger', 'That antenna is beaming the signal! Shoot the big red eye!']],
    clear: [['vesk', 'Relay\'s down. The signal is still coming from somewhere else.'], ['dodger', 'Later problem. The rail goes down to the Fan Gardens.']], next: 'Ride down to the Fan Gardens' },
  { id: 'gardens', name: 'FAN GARDENS', rect: ISLANDS.gardens, y: 0, delay: 1.0, check: V(-22, 0, -96),
    waves: [['hornet', 'roller', 'roller'], ['hornet', 'hornet', 'roller']],
    goal: 'Clear the Fan Gardens',
    intro: [['dodger', 'The Fan Gardens. Very relaxing. Normally.']],
    clear: [['dodger', 'The Crane Yard is past that floating platform. One more swing!'], ['vesk', 'I am getting too old for swinging.']], next: 'Ride the platform and swing to the Crane Yard' },
  { id: 'yard', name: 'CRANE YARD', rect: ISLANDS.yard, y: 0, delay: 4.5, check: V(-58, 0, -118), boss: true,
    goal: 'Defeat the Crane Bot',
    intro: [['dodger', 'Uh, Vesk? That crane is looking at us.'], ['vesk', 'Cranes do not look at people.'], ['dodger', 'This one does!']] },
];
const ZI = id => ZONES.findIndex(z => z.id === id);

export function createStory(d) {
  // d: { player, enemies, rails, dodger, hud, sfx, fx, boss, gizmarts, relay, extraTargets, spawnIn(rect, minDist), openShop, hurtHero, onComplete, dropNuts, shake }
  const relayT = { type: 'relay', name: 'SIGNAL RELAY', pos: d.relay.pos.clone(), radius: 0.9, hp: RELAY_HP, maxHp: RELAY_HP, dead: false };
  const S = { zone: -1, phase: 'idle', t: 0, waveI: 0, waveT: 0, checkpoint: V(0, 0, 35), goal: 'Explore the docks', time: 0, active: false, done: false, hornetT: 0, rodeOnce: false, deaths: 0 };
  const zoneState = ZONES.map(() => ({ started: false, cleared: false }));

  function reset() {
    Object.assign(S, { zone: -1, phase: 'idle', t: 0, waveI: 0, waveT: 0, checkpoint: d.start.pos.clone(), goal: 'Look around the docks', time: 0, active: true, done: false, hornetT: 0, rodeOnce: false, deaths: 0 });
    zoneState.forEach(z => Object.assign(z, { started: false, cleared: false }));
    d.rails.rails.forEach((r, i) => d.rails.setLocked(i, true));
    relayT.hp = RELAY_HP; relayT.dead = false; d.relay.group.visible = true;
    d.extraTargets.length = 0; d.extraTargets.push(relayT);
    d.boss.hide(); d.hud.boss(null);
    S.introT = 1.2; S.endT = -1; queue.length = 0;
  }

  const queue = []; // bots waiting to drop in (sim time, so pausing holds them)
  const alive = () => queue.length +  d.enemies.list.filter(e => !e.dead && e.tag === 'story').length;

  function spawnWave(z, list) {
    list.forEach((type, i) => queue.push({ type, z, t: i * 0.38 }));
  }

  function clearZone(zi) {
    const z = ZONES[zi]; zoneState[zi].cleared = true; S.phase = 'idle';
    d.sfx.waveClear();
    d.hud.banner('AREA CLEAR', z.name, '#7dff9a');
    if (z.unlock !== undefined) d.rails.setLocked(z.unlock, false);
    z.clear?.forEach(([who, line]) => d.dodger.story(who, line));
    S.goal = z.next || S.goal;
    d.heal(2);
  }

  function damageRelay(amount) {
    if (relayT.dead) return false;
    relayT.hp -= amount;
    d.relay.eyeMat.emissiveIntensity = 20;
    if (relayT.hp <= 0) {
      relayT.dead = true; d.relay.group.visible = false;
      d.fx.explosion(relayT.pos.clone(), 1.8); d.fx.explosion(relayT.pos.clone().add(V(0, -3, 0)), 1.2); d.shake(1.5);
      d.sfx.explosion(1, 1.4);
      d.dodger.story('dodger', 'Relay scrapped! Ten out of ten! Okay, nine.');
      d.dropNuts(relayT.pos.clone().add(V(0, -4, 0)), 12);
      return true;
    }
    return false;
  }

  function startZone(zi) {
    const z = ZONES[zi]; zoneState[zi].started = true;
    S.zone = zi; S.phase = 'intro'; S.t = z.delay; S.waveI = 0;
    S.checkpoint.copy(z.check);
    S.goal = z.goal;
    d.hud.banner(z.name, z.goal, z.boss ? '#ff6040' : '#ffd040');
    z.intro?.forEach(([who, line]) => d.dodger.story(who, line));
    if (z.boss) d.music?.boss?.(true);
  }

  function update(dt) {
    if (!S.active) return;
    const p = d.player;
    S.time += dt;
    for (let i = queue.length - 1; i >= 0; i--) {
      const q = queue[i]; q.t -= dt; if (q.t > 0) continue;
      const [x, zz] = d.spawnIn(q.z.rect, 6);
      d.enemies.spawn(q.type, x, zz, { zone: q.type === 'roller' ? q.z.rect : null, tag: 'story' });
      d.sfx.spawn(0.8); queue.splice(i, 1);
    }
    if (S.endT > 0) { S.endT -= dt; if (S.endT <= 0) { S.done = true; S.active = false; d.onComplete(); return; } }
    if (S.introT > 0) { S.introT -= dt; if (S.introT <= 0) { d.dodger.story('dodger', 'The signal is coming from somewhere in Skyharbor. Also, Gizmart is open.'); d.dodger.story('vesk', 'We are not shopping.'); d.dodger.story('dodger', 'We are a little bit shopping.'); } }
    // walk into an area to start it
    for (let i = 0; i < ZONES.length; i++) {
      const z = ZONES[i];
      if (zoneState[i].started || !p.grounded || d.rails.riding) continue;
      if (inRect(p.pos, z.rect, -0.5) && Math.abs(p.pos.y - z.y) < 1.2) { startZone(i); break; }
    }
        const zi = S.zone, z = ZONES[zi];
    if (z && !zoneState[zi].cleared) {
      S.t -= dt;
      if (z.boss) {
        if (S.phase === 'intro' && S.t <= 0) {
          d.boss.spawn(d.bossPos, z.rect); S.phase = 'boss';
          d.extraTargets.push(d.boss.target);
          d.hud.banner('CRANE BOT', 'Foreman Grudd\'s heavy lifter. Shoot the cab!', '#ff6040');
          d.sfx.waveStart();
        }
        if (S.phase === 'boss') d.hud.boss(d.boss.target.name, d.boss.target.hp / d.boss.target.maxHp);
      } else if (S.phase === 'intro' && S.t <= 0) {
        S.phase = 'fight'; spawnWave(z, z.waves[0]); S.waveI = 1; S.waveT = 2;
        d.sfx.waveStart(); d.dodger.line('spawn');
      } else if (S.phase === 'fight') {
        S.waveT -= dt;
        if (S.waveT <= 0 && alive() === 0) {
          if (S.waveI < z.waves.length) { spawnWave(z, z.waves[S.waveI++]); S.waveT = 2; d.dodger.line('taunt'); }
          else if (z.relay && !relayT.dead) {
            // the relay keeps calling hornets until it's destroyed
            S.hornetT -= dt;
            if (S.hornetT <= 0) { spawnWave(z, ['hornet', 'hornet']); S.hornetT = 9; S.waveT = 2; }
          } else clearZone(zi);
        }
      }
    }
    if (S.zone === ZI('mast') && !relayT.dead) d.hud.boss(relayT.name, relayT.hp / relayT.maxHp);
    else if (S.zone === ZI('mast')) d.hud.boss(null);
    // Gizmart
    for (const g of d.gizmarts) if (g.update(dt, p.pos, p.grounded)) { g.talk(); d.dodger.say(pick(GIZ_LINES.hello), 1, 'giz'); d.openShop(g); }
    // touching a checkpoint pad on the way between areas
    if (p.grounded) for (const c of d.checkpoints) if (Math.hypot(p.pos.x - c.pos.x, p.pos.z - c.pos.z) < c.r && Math.abs(p.pos.y - c.pos.y) < 0.6) S.checkpoint.copy(c.pos);
    // fell off: back to the last checkpoint
    if (p.pos.y < -14) {
      S.deaths++;
      p.pos.copy(S.checkpoint); p.vel.set(0, 0, 0); d.rails.detach(); d.onFall?.();
      d.hurtHero(1, null, true);
      d.dodger.line('fall', 1); d.sfx.hurt();
    }
  }

  function bossDead(at) {
    d.dropNuts(at, 30);
    d.hud.boss(null);
    d.music?.boss?.(false);
    zoneState[ZI('yard')].cleared = true; S.goal = 'Skyharbor is safe. For now.';
    d.sfx.waveClear(); d.hud.banner('CRANE BOT SCRAPPED', '', '#ffd040');
    d.dodger.kill({ boss: true });
    d.dodger.story('vesk', 'That\'s one big piece of junk for the pile.');
    d.dodger.story('dodger', 'Wait. Its radio is still on. Something is talking...');
    S.endT = 5.2;
  }

  return {
    reset, update, damageRelay, bossDead, relayTarget: relayT,
    get goal() { return S.goal; }, get time() { return S.time; }, get deaths() { return S.deaths; }, get active() { return S.active; },
    stop() { S.active = false; },
    get zone() { return S.zone; }, get checkpoint() { return S.checkpoint; },
  };
}
