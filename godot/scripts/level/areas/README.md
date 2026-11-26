One file per Skyharbor area. See ../areas.gd for the hooks (`build(L)`, `traversal_cases(moves)`).

Build order: the area files (and the area builders in level_skyharbor.gd) build at their ORIGINAL coordinates;
then `layout/spread.gd` moves each area out from the Dock Plaza (Junkyard south, Terrace + Gardens west, Docks
east, Mast north-east, Crane Yard + causeway north). Files whose names start with a "late" prefix run after that,
in final coordinates:

- `w_routes.gd`  the transition routes between areas (tram viaduct + Scrapline Halt + Sorting Works in the
  Junkyard, lantern bridge, freight gangway, freight approach, cableway, balloon line, dish rail)
- `x_chaos.gd`   panic leftovers scattered inside the areas (`layout/scatter.gd` checks each against the geometry)
- `y_ground.gd`  per-area floors and clutter
- `zz_panic.gd`  citizens, air traffic, evacuation, sirens
- `zzz_perf.gd`  draw distances for small pieces

Code that keeps its own world positions written for the old layout converts them with `Spread.at(pos)`.
Flags: `--no-spread`, `--no-chaos`, `--no-cull`, `--layout-map=<png> [--map-box=x0,z0,x1,z1] [--map-px=2]`.
