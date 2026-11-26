# Skyharbor citizens (panic pass): concept -> image-to-3d (8k tris) -> rig (1.7 m) -> one animation batch.
#   python3 art/meshy/citizens.py t2i|i23d|rig|anim [name...]      (defaults to all four)
# Outputs land next to chars.py's in /tmp/claude-0/meshy/chars/. build_citizens.py turns them into godot/models/citizens/*.glb.
import sys, concurrent.futures as cf
sys.path.insert(0, __file__.rsplit('/', 1)[0])
import chars as C

STYLE = (" Everyday Skyharbor townsperson, an original alien species. Standing in A-pose, arms out and down, legs apart, empty hands, "
         "full body from head to feet, friendly cartoon proportions with a big expressive head.")
C.P.update({
 'cit_frog': ("A plump, round frog-like alien dockhand with smooth moss-green skin, a wide grin mouth, big round eyes on top of the head, "
              "wearing faded blue work overalls over a striped orange shirt, a knitted red beanie and chunky brown boots." + STYLE, 'a-pose'),
 'cit_bird': ("A tall lanky heron-like alien lady with soft lavender feathers, a short rounded orange beak, long thin legs, a long teal "
              "travel coat with big brass buttons, a yellow knitted scarf and a small round hat with a feather." + STYLE, 'a-pose'),
 'cit_mole': ("A short stout mole-like alien shopkeeper with fuzzy brown fur, a big pink nose, round wire glasses, large round ears, "
              "a cream shirt with rolled sleeves, a mustard yellow apron with pockets and little sandals." + STYLE, 'a-pose'),
 'cit_goat': ("A cheerful goat-like alien tourist with white shaggy fur, small curled horns, a floppy sun hat, a loud coral-pink "
              "flowered short-sleeve shirt, khaki shorts, a camera strap across the chest and sneakers with long socks." + STYLE, 'a-pose'),
})
NAMES = ['cit_frog', 'cit_bird', 'cit_mole', 'cit_goat']
# idle, run fast, run 2, wave for help 1, carry heavy object walk, look around dumbfounded, crouch and step back,
# hop with arms raised, shouting angrily, cautious crouch walk forward
ANIMS = '0,16,14,293,551,333,404,417,51,524'

if __name__ == '__main__':
    cmd, names = sys.argv[1], sys.argv[2:] or NAMES
    fn = {'t2i': C.t2i, 'i23d': lambda n: C.i23d(n + ':8000'), 'rig': lambda n: C.rig(n, 1.7),
          'anim': lambda n: C.anim(n, ANIMS)}[cmd]
    with cf.ThreadPoolExecutor(4) as ex:
        for f in cf.as_completed([ex.submit(fn, n) for n in names]):
            try: f.result()
            except Exception as e: print('ERR', e, flush=True)
    print(C.req(f'{C.A}/v1/balance'))
