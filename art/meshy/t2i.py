import json, sys, time, urllib.request
API='https://api.meshy.ai/openapi/v1/text-to-image'
def req(url, body=None):
    r=urllib.request.Request(url, data=json.dumps(body).encode() if body else None, headers={'Content-Type':'application/json'})
    return json.loads(urllib.request.urlopen(r, timeout=120).read())
base=("Full-body character concept for a stylized 3D cartoon sci-fi action-platformer video game, high-end animated film quality, "
 "clean neutral light grey background, character standing in A-pose facing the camera. ")
V={
 'a': "Vesk: a stocky, broad-shouldered older alien mechanic, grizzled and grumpy, about 60 in human terms. Rounded wide head with a heavy brow, short bristly grey whiskers on a short muzzle, tired half-lidded amber eyes, one round brass cybernetic eyepiece over his left eye. Slight hunch. Wears scuffed armored work plates in faded burnt orange and gunmetal over patched navy overalls, an oversized left mechanical gauntlet with built-in tools, heavy magnetic work boots, a salvaged two-nozzle jetpack, small brass trim details. Original design.",
 'b': "Vesk: a short, barrel-chested veteran alien engineer with blue-grey leathery skin, a wide frowning mouth, a bushy grey moustache, and droopy long ears tucked under a battered leather and steel work cap with flip-up welding goggles. Wears heavy chunky armored combat-mechanic suit with big shoulder pauldrons, faded burnt orange and gunmetal plates, brass rivets, an oversized right tool gauntlet, thick boots, salvaged jetpack. Grumpy expression. Original design.",
 'c': "Vesk: a sturdy middle-aged reptilian alien mechanic with olive-green scaly skin, a broad jaw with a few grey bristles, a scar across the snout, small horns swept back, and a monocle-style cyber eye lens. Wears a heavy armored work suit like a rugged mech pilot: thick padded collar, layered gunmetal armor plates with chipped burnt orange paint, brass gear emblem on the chest, huge tool gauntlet, magnetic boots, compact jetpack. Dry, unimpressed expression. Original design.",
 'd': "Vesk: a burly old furry alien mechanic with dusty brown-and-grey fur, a big round nose, thick grey eyebrows and sideburns, small rounded ears, tired eyes with crow's feet, and a cybernetic eyepiece. Wears a rugged armored mechanic exosuit: dented gunmetal chest plate, faded burnt orange shoulder armor, worn leather tool belt with wrenches, an oversized hydraulic gauntlet, heavy boots, salvaged jetpack with patched pipes. Grumpy but kind. Original design.",
}
ids={}
for k,p in V.items():
    ids[k]=req(API,{'ai_model':'nano-banana-2','prompt':base+p,'pose_mode':'a-pose'})['result']
print(ids)
pending=dict(ids)
while pending:
    time.sleep(6)
    for k,i in list(pending.items()):
        t=req(f'{API}/{i}')
        if t['status'] in ('SUCCEEDED','FAILED','CANCELED'):
            print(k,t['status'],t.get('task_error'))
            if t['status']=='SUCCEEDED':
                urllib.request.urlretrieve(t['image_urls'][0], f'/tmp/claude-0/meshy/vesk_{k}.png')
            del pending[k]
json.dump(ids,open('/tmp/claude-0/meshy/vesk_t2i_ids.json','w'))
