extends RefCounted
## The market build-up (late file: final coordinates; runs before w_routes, so the routes' chaos, the scatter
## and the floors all see the new props). Fills the Market Terrace and the Spice Bazaar: shop-houses, stalls,
## goods, abandoned vehicles and the panic (scripts/level/terrace/market_look.gd).
##   --no-market          keep the market as it was (for before/after shots)
##   --market-shots=<p>   visit a few market viewpoints, save <p>_<spot>.png with the fps, then quit
##                        (--market-only=a,b to pick spots, --market-fast for slow software renders)

const Look := preload("res://scripts/level/terrace/market_look.gd")
const Shots := preload("res://scripts/level/terrace/market_shots.gd")

static func build(L) -> void:
	if not L.islands.has("bazaar"): return
	var args := OS.get_cmdline_user_args()
	if Look.on(): Look.build(L)
	for a in args:
		if a.begins_with("--market-shots="):
			var s: Node = Shots.new(); s.prefix = a.substr(15); s.name = "MarketShots"
			L.add_child(s)
