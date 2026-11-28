extends RefCounted
## The routes' look pass (late file: final coordinates; runs right after w_routes and before the chaos scatter
## and the floors, so those see the new props). Brings the connectors between the key areas up to the market and
## gardens: the tram viaduct, the lantern bridge, the freight gangway, the freight approach and lift bridge, the
## cableway, the balloon barge and the dish rail (scripts/level/routes/routes_look.gd).
##   --no-routes-look     keep the routes as they were (for before/after shots)
##   --no-routes-sky      skip only the sky routes pass (cableway towers, barge hull and envelope, dish rail
##                        pylons, the viaduct's cable pylons, their moods)
##   --routes-shots=<p>   visit the routes, save <p>_<spot>.png with the fps, then quit
##                        (--routes-only=a,b to pick spots, --routes-fast for slow software renders)

const Look := preload("res://scripts/level/routes/routes_look.gd")
const Shots := preload("res://scripts/level/routes/routes_shots.gd")
const S := preload("res://scripts/level/layout/spread.gd")

static func build(L) -> void:
	if not S.on(): return
	if Look.on(): Look.build(L)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--routes-shots="):
			var s: Node = Shots.new(); s.prefix = a.substr(15); s.name = "RoutesShots"
			L.add_child(s)
