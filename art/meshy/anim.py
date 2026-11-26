import json,time,urllib.request
def req(u,b=None):
    r=urllib.request.Request(u,data=json.dumps(b).encode() if b else None,headers={'Content-Type':'application/json'})
    return json.loads(urllib.request.urlopen(r).read())
rid=open('rig_B.txt').read().strip()
while True:
    t=req(f'https://api.meshy.ai/openapi/v1/rigging/{rid}')
    if t['status'] in ('SUCCEEDED','FAILED','CANCELED'): break
    time.sleep(5)
print('rig',t['status'],t.get('task_error'))
res=t['result']; urllib.request.urlretrieve(res['rigged_character_glb_url'],'vesk_rigged.glb')
for k in ('walking_glb_url','running_glb_url'):
    if res.get('basic_animations') and res['basic_animations'].get(k): urllib.request.urlretrieve(res['basic_animations'][k],f'basic_{k}.glb')
sets={'set1':[0,14,86,502,644,460,390,477,128,466],'set2':[178,243,659,98,509]}
ids={n:req('https://api.meshy.ai/openapi/v1/animations',{'rig_task_id':rid,'action_ids':a})['result'] for n,a in sets.items()}
for n,i in ids.items():
    while True:
        t=req(f'https://api.meshy.ai/openapi/v1/animations/{i}')
        if t['status'] in ('SUCCEEDED','FAILED','CANCELED'): break
        time.sleep(5)
    print(n,t['status'],t.get('task_error'))
    if t['status']=='SUCCEEDED': urllib.request.urlretrieve(t['result']['animation_glb_url'],f'anim_{n}.glb')
print(req('https://api.meshy.ai/openapi/v1/balance'))
