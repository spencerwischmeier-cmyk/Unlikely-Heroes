extends CanvasLayer
## Running out of hull: the world slows, the screen fades to black, Vesk is patched up at the last
## checkpoint and it fades back in (instead of snapping him there mid-hit). Bots hold still meanwhile.

var fade: ColorRect
var busy := false

func _ready() -> void:
	layer = 90
	fade = ColorRect.new(); fade.color = Color(0.02, 0.03, 0.06, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT); fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	Game.player_downed.connect(_downed)

func _downed() -> void:
	if busy: return
	busy = true
	Snd.bark("dodger", "fall", 0.0)
	Engine.time_scale = 0.3
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(fade, "color:a", 1.0, 0.6).set_ease(Tween.EASE_IN)
	await tw.finished
	Game.input_locked = true
	Engine.time_scale = 1.0
	if Game.combat: Game.combat.revive()
	await get_tree().create_timer(0.4, false, false, true).timeout
	Game.input_locked = false
	var tw2 := create_tween().set_ignore_time_scale(true)
	tw2.tween_property(fade, "color:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	await tw2.finished
	busy = false
