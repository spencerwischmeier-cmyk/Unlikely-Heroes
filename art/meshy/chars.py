# Characters and enemies from Meshy (sprint/characters).
#   python3 art/meshy/chars.py t2i <name>...     concept image(s) -> /tmp/claude-0/meshy/chars/<name>.png
#   python3 art/meshy/chars.py i23d <name>...    image-to-3d from the concept -> <name>_raw.glb
#   python3 art/meshy/chars.py rig <name>        rigging (humanoids only) -> <name>_rigged.glb
#   python3 art/meshy/chars.py anim <name> id,id,...  animation batch -> <name>_anim.glb
# Grudd Works livery used in the prompts: mustard yellow + charcoal grey, brick-red trim, a white gear stencil.
import json, sys, time, os, base64, urllib.request, urllib.error
OUT = '/tmp/claude-0/meshy/chars'
os.makedirs(OUT, exist_ok=True)
A = 'https://api.meshy.ai/openapi'

def req(u, b=None):
    for n in range(6):
        try:
            r = urllib.request.Request(u, data=json.dumps(b).encode() if b else None, headers={'Content-Type': 'application/json'})
            return json.loads(urllib.request.urlopen(r, timeout=120).read())
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503): time.sleep(10 * (n + 1)); continue
            raise RuntimeError(f'{e.code} {e.read()[:400]}')
        except Exception:
            time.sleep(5 * (n + 1))
    raise RuntimeError('network')

def wait(u):
    while True:
        t = req(u)
        if t['status'] in ('SUCCEEDED', 'FAILED', 'CANCELED'): return t
        time.sleep(8)

BASE = ("Character concept for a stylized 3D cartoon sci-fi action-platformer video game, high-end animated feature film quality, "
        "chunky appealing rounded shapes, hand-painted worn materials with chipped paint, warm golden-hour lighting, "
        "clean plain light grey background, whole object fully visible, three-quarter front view. Original design. ")
LIV = " Company livery: mustard yellow and charcoal grey painted steel with brick-red trim, rivets, hazard stripes and a small white gear stencil. "
P = {
 'grudd': ("Foreman Grudd: a towering, top-heavy factory foreman robot with a huge barrel chest, short stubby legs and long thick arms "
           "ending in big three-fingered hands. A tall smokestack chimney on top of his head like a top hat. His face is a big brass "
           "loudspeaker horn for a mouth under two small glowing orange eyes and a heavy frowning brow plate. A giant clipboard hangs from "
           "his belt. Pompous, bossy middle-manager attitude. Standing in A-pose, arms out and down, legs apart." + LIV, 'a-pose'),
 'grudd2': ("Foreman Grudd: a towering, top-heavy giant factory foreman robot with a huge round barrel chest, short stubby legs and long thick "
            "arms ending in big three-fingered hands. A big boxy head with a heavy angry brow plate over two glowing orange eyes, and a wide brass "
            "loudspeaker grille for a mouth in the middle of his face. A short factory smokestack chimney sticks out of the top of his head, "
            "puffing a little smoke. A giant clipboard hangs from his belt. Pompous, bossy middle-manager attitude. Standing in A-pose, arms out "
            "and down, legs apart." + LIV, 'a-pose'),
 'gizmart': ("Gizmart: a cheerful vending-machine robot shopkeeper. Tall rounded vending machine body with a glass front window showing "
             "shelves of colorful gadget capsules and spare parts, a large blank dark rectangular screen for a face at the top, two stubby "
             "mechanical arms with big white cartoon gloves, a coin slot and a pickup tray, small chunky wheels, a red and white striped "
             "awning on top with a little antenna. Teal and cream paint with gold trim and a starburst sale sticker. Over-the-top friendly salesman.", None),
 'hornet': ("Tin Hornet: a flying wasp-like robot drone made of riveted tin. Chunky rounded armored head with a single wide glowing red "
            "visor eye, a round striped abdomen ending in a riveter-gun stinger, two pairs of stiff metal wings, two small thruster pods, "
            "tiny dangling legs. Mischievous and menacing but cute. Flying pose." + LIV, None),
 'crane_cab': ("Crane Bot cab: the angry face cab of a heavy construction crane robot boss, a big chunky boxy operator cab on a round "
               "turret ring, front of the cab is an angry face: one wide glowing red visor eye slit under a heavy brow, a riveted grille jaw "
               "with a rivet-gun port, two exhaust stacks on the back, a counterweight block at the back, warning lamps on the roof." + LIV, None),
 'crane_base': ("Crane Bot chassis: a wide low tracked vehicle base for a construction crane robot, two big chunky caterpillar tracks with "
                "road wheels, a flat round turret mount plate on top, mud flaps, hazard-striped bumpers front and back, no cab on top." + LIV, None),
 'magnet': ("A heavy round crane electromagnet: thick disc with a ribbed top, a big shackle loop on top, glowing red coil rim around the "
            "bottom edge, hazard stripes, dents." + LIV, None),
 'roller_head': ("Scrap Roller head: a dome-shaped robot head unit that sits on top of a ball, wide helmet with a single big round glowing "
                 "red eye lens in front, two small horns, a rim around the base, little exhaust pipes on the back." + LIV, None),
 'barricade': ("Work-crew road barricade: a sturdy portable construction roadblock, two thick horizontal planks painted with bold "
               "diagonal hazard stripes, mounted on chunky A-frame steel legs with flat feet, big bolts, a small round amber warning "
               "lamp on top of one end, front view, wide and low, no text." + LIV, None),
 'crew_head': ("Work-crew robot head: a dome-shaped robot head unit that sits on top of a rolling ball, wearing a chunky yellow hard hat "
               "with a lamp, one big round glowing amber eye lens with a grumpy brow, a rim around the base, a small radio antenna." + LIV, None),
}

def t2i(name):
    prompt, pose = P[name]
    body = {'ai_model': 'nano-banana-2', 'prompt': (BASE + prompt)[:1500]}
    if pose: body['pose_mode'] = pose
    i = req(f'{A}/v1/text-to-image', body)['result']
    t = wait(f'{A}/v1/text-to-image/{i}')
    print(name, t['status'], t.get('task_error'), flush=True)
    if t['status'] == 'SUCCEEDED':
        urllib.request.urlretrieve(t['image_urls'][0], f'{OUT}/{name}.png')

def i23d(name, poly=30000):
    if ':' in name: name, poly = name.split(':'); poly = int(poly)
    data = base64.b64encode(open(f'{OUT}/{name}.png', 'rb').read()).decode()
    body = {'image_url': 'data:image/png;base64,' + data, 'ai_model': 'latest', 'enable_pbr': True, 'should_texture': True,
            'should_remesh': True, 'target_polycount': poly, 'topology': 'triangle'}
    if name.startswith('grudd'): body['pose_mode'] = 'a-pose'
    i = req(f'{A}/v1/image-to-3d', body)['result']
    open(f'{OUT}/{name}_i23d.txt', 'w').write(i)
    t = wait(f'{A}/v1/image-to-3d/{i}')
    print(name, 'i23d', t['status'], t.get('task_error'), t.get('consumed_credits'), flush=True)
    if t['status'] == 'SUCCEEDED':
        urllib.request.urlretrieve(t['model_urls']['glb'], f'{OUT}/{name}_raw.glb')
        if t.get('thumbnail_url'): urllib.request.urlretrieve(t['thumbnail_url'], f'{OUT}/{name}_thumb.png')

def rig(name, h=4.0):
    i = open(f'{OUT}/{name}_i23d.txt').read().strip()
    r = req(f'{A}/v1/rigging', {'input_task_id': i, 'height_meters': h})['result']
    open(f'{OUT}/{name}_rig.txt', 'w').write(r)
    t = wait(f'{A}/v1/rigging/{r}')
    print(name, 'rig', t['status'], t.get('task_error'), flush=True)
    if t['status'] == 'SUCCEEDED':
        res = t['result']; urllib.request.urlretrieve(res['rigged_character_glb_url'], f'{OUT}/{name}_rigged.glb')
        for k, v in (res.get('basic_animations') or {}).items():
            if v and k.endswith('glb_url'): urllib.request.urlretrieve(v, f'{OUT}/{name}_{k}.glb')

def anim(name, ids, tag='anim'):
    r = open(f'{OUT}/{name}_rig.txt').read().strip()
    i = req(f'{A}/v1/animations', {'rig_task_id': r, 'action_ids': [int(x) for x in ids.split(',')]})['result']
    t = wait(f'{A}/v1/animations/{i}')
    print(name, 'anim', t['status'], t.get('task_error'), flush=True)
    if t['status'] == 'SUCCEEDED': urllib.request.urlretrieve(t['result']['animation_glb_url'], f'{OUT}/{name}_{tag}.glb')

if __name__ == '__main__':
    import concurrent.futures as cf
    cmd, names = sys.argv[1], sys.argv[2:]
    if cmd == 'anim': anim(names[0], names[1], names[2] if len(names) > 2 else 'anim')
    else:
        fn = {'t2i': t2i, 'i23d': i23d, 'rig': rig}[cmd]
        with cf.ThreadPoolExecutor(8) as ex:
            for f in cf.as_completed([ex.submit(fn, n) for n in names]):
                try: f.result()
                except Exception as e: print('ERR', e, flush=True)
    print(req(f'{A}/v1/balance'))
