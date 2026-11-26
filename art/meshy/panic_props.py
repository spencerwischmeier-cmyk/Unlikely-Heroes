# Panic pass props (Meshy text-to-3d, same recipe as props.py): the evacuation shuttle and the sky car.
#   cd /tmp/claude-0/meshy/panic && python3 <repo>/art/meshy/panic_props.py [name...]
# The raw glbs are shrunk into godot/models/panic/ with art/meshy/shrink.py (1k textures).
import sys, os
sys.argv = [sys.argv[0]] + (sys.argv[1:] or ['shuttle', 'skycar'])
STYLE = (" Stylized cartoon 3D video game asset in the style of a high-end animated sci-fi action-platformer: chunky appealing shapes, "
         "hand-painted worn materials with chipped paint and light rust, warm saturated colors, clean silhouette. Single isolated object, "
         "no ground, no background.")
P = {
 'shuttle': ("Chunky retro passenger space shuttle bus for evacuating a sky city: rounded cream and teal hull like a flying tour bus, "
             "a row of round porthole windows along the side, a big side hatch door, stubby swept wings, two large glowing rocket "
             "thrusters at the back, small landing legs, a red stripe and a lit sign box on the roof.", 16000),
 'skycar': ("Small cute retro flying hover car for one or two people: rounded bubble glass canopy, chunky curvy body in bright red paint "
            "with chrome trim, two round hover thruster pods underneath, little tail fins, round headlights, no wheels.", 7000),
}
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'props.py')).read().split("only=sys.argv")[0].split("P={")[0]
     + "only=sys.argv[1:] or list(P)\n" + open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'props.py')).read().split("only=sys.argv[1:] or list(P)\n")[1])
