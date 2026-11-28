extends Node
## The last bot of a fight: when the kill that clears an area lands, time dips into slow motion for a
## moment, the camera gets a solid kick and a low thump plays, so the end of every fight lands as a beat
## instead of just stopping. Not for bosses (they have their own finish). `--no-final-blow` turns it off.

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--no-final-blow"): return
	Game.bot_killed.connect(_on_kill)

func _on_kill(bot: Node, pos: Vector3, _kind: String) -> void:
	var s: Node = Game.story
	if s == null or not s.active or s.index < 0 or s.index >= s.zones.size(): return
	var z: Dictionary = s.zones[s.index]
	if z.get("kind", "") != "": return                 # fights only
	if s.wave < z.get("waves", []).size(): return       # more waves to come
	for b in s.alive:
		if is_instance_valid(b) and b != bot and not b.dead: return
	FX.slow(0.3, 0.5)
	Game.combat_event.emit("final_blow", pos)   # systems/fight_reward.gd pays a style bonus
	FX.shake(0.5)
	FX.ring(pos + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.45), 1.2)
	Snd.play("melee_hit", 2, 0.0, 0.0, 0.6)
	if OS.get_cmdline_user_args().has("--chain-log"): print("[final-blow] at ", pos)
