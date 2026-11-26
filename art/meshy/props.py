import json,time,urllib.request,concurrent.futures as cf,os,sys
B='https://api.meshy.ai/openapi/v2/text-to-3d'
def req(u,b=None):
    for n in range(5):
        try:
            r=urllib.request.Request(u,data=json.dumps(b).encode() if b else None,headers={'Content-Type':'application/json'})
            return json.loads(urllib.request.urlopen(r,timeout=120).read())
        except urllib.error.HTTPError as e:
            if e.code in (429,500,502,503): time.sleep(10*(n+1)); continue
            raise RuntimeError(f'{e.code} {e.read()[:300]}')
STYLE=" Stylized cartoon 3D video game asset in the style of a high-end animated sci-fi action-platformer: chunky appealing shapes, hand-painted worn materials with chipped paint and light rust, warm saturated colors, clean silhouette. Single isolated object, no ground, no background."
P={
 'container': ("Corrugated steel cargo shipping container, off-white paint with chipped edges and rust streaks, chunky corner castings, locking bars on the doors, stenciled numbers.",12000),
 'dock_crane': ("Tall dockside cargo crane on four legs, yellow painted steel lattice, operator cab, long boom with a hanging hook, warning stripes.",20000),
 'airship': ("Small cargo airship: plump cream fabric balloon with brass ribs, wooden gondola hanging below with a cargo crate, two side propellers, fins, little lanterns.",16000),
 'pipes': ("Cluster of industrial pipes and valves with a pressure gauge, brass and teal painted steel, rising from a small metal base, steam vent nozzle on top.",10000),
 'barrels': ("Group of three chunky oil drums, one orange, one teal, one red, dented, with hazard labels.",8000),
 'crates': ("Stack of three wooden cargo crates of different sizes with metal corner brackets and canvas straps, stenciled arrows.",8000),
 'bollard': ("Dockside mooring bollard, dark iron, with thick coiled rope wrapped around it.",5000),
 'floodlight': ("Industrial dock floodlight tower: slim steel pole with a cluster of four round lamps on top and a small junction box.",8000),
 'dock_bot': ("Cute small cargo-loading robot worker, boxy body on tracks, two clamp arms, round single eye, yellow and grey paint, friendly.",12000),
 'island': ("Small floating sky island chunk: grassy top with a few round trees and rocks, jagged earthy rock underside tapering to a point, a little waterfall pouring off the edge.",20000),
 'truss': ("Tall steel truss support tower for a floating pier, criss-cross girders with rivets, painted teal-grey, chunky base plate.",10000),
 'forklift': ("Cartoon forklift truck, orange body, black tires, raised forks holding a pallet, roll cage.",12000),
 'fuel_tanks': ("Two big horizontal fuel tanks on a steel frame with ladders, cream and red stripe paint, valves and a gauge.",12000),
 'cable_spool': ("Large wooden cable spool with thick black cable wound around it.",6000),
 'hazard_barrier': ("Portable yellow and black striped metal barrier with a small amber warning light on top.",5000),
 'rope_bridge': ("Section of a hanging rope bridge: wooden planks tied with thick ropes and two rope handrails, slightly sagging, about four meters long.",8000),
}
only=sys.argv[1:] or list(P)
def run(name):
    if os.path.exists(f'{name}.glb'): return name+' cached'
    text,poly=P[name]
    pid=req(B,{'mode':'preview','prompt':(text+STYLE)[:800],'ai_model':'latest','should_remesh':True,'target_polycount':poly,'topology':'triangle'})['result']
    while True:
        t=req(f'{B}/{pid}')
        if t['status'] in ('SUCCEEDED','FAILED','CANCELED'): break
        time.sleep(8)
    if t['status']!='SUCCEEDED': return f'{name} preview {t["status"]} {t.get("task_error")}'
    rid=req(B,{'mode':'refine','preview_task_id':pid,'enable_pbr':True,'texture_resolution':'2k'})['result']
    while True:
        t=req(f'{B}/{rid}')
        if t['status'] in ('SUCCEEDED','FAILED','CANCELED'): break
        time.sleep(8)
    if t['status']!='SUCCEEDED': return f'{name} refine {t["status"]} {t.get("task_error")}'
    urllib.request.urlretrieve(t['model_urls']['glb'],f'{name}.glb')
    if t.get('thumbnail_url'): urllib.request.urlretrieve(t['thumbnail_url'],f'{name}.png')
    return f'{name} ok'
with cf.ThreadPoolExecutor(8) as ex:
    for f in cf.as_completed([ex.submit(run,n) for n in only]):
        try: print(f.result(),flush=True)
        except Exception as e: print('ERR',e,flush=True)
print(req('https://api.meshy.ai/openapi/v1/balance'))
