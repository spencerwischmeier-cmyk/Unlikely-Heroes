extends Node
## Debug: `-- --layout-map=out.png [--map-box=x0,z0,x1,z1] [--map-px=2]` writes a top-down map of the level
## (walkable heights from downward rays, rails red, hooks yellow, bounce pads green, movers blue, checkpoints
## white, island names) and quits. Used to plan the layout and the transitions between areas.

var frames := 0

func _physics_process(_dt: float) -> void:
	frames += 1
	if frames < 3: return
	set_physics_process(false)
	var L: Node3D = get_parent()
	var out := "map.png"; var box := Rect2(-170, -200, 380, 420); var px := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--layout-map="): out = a.substr(13)
		if a.begins_with("--map-box="):
			var v := a.substr(10).split_floats(","); box = Rect2(v[0], v[1], v[2] - v[0], v[3] - v[1])
		if a.begins_with("--map-px="): px = 1.0 / a.substr(9).to_float()
	var W := int(box.size.x / px); var H := int(box.size.y / px)
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.08, 0.1, 0.16))
	var space := L.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	for j in H:
		for i in W:
			var x := box.position.x + (i + 0.5) * px; var z := box.position.y + (j + 0.5) * px
			q.from = Vector3(x, 60, z); q.to = Vector3(x, -12, z)
			var hit := space.intersect_ray(q)
			if hit.is_empty(): continue
			var y: float = hit.position.y
			var u := clampf((y + 4.0) / 30.0, 0.0, 1.0)
			var c := Color(0.25, 0.4, 0.3).lerp(Color(0.95, 0.9, 0.7), u)
			if hit.normal.y < 0.6: c = c.darkened(0.45)
			img.set_pixel(i, j, c)
	var to_px := func(p: Vector3) -> Vector2i: return Vector2i(int((p.x - box.position.x) / px), int((p.z - box.position.y) / px))
	var dot := func(p: Vector3, col: Color, r: int) -> void:
		var c: Vector2i = to_px.call(p)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q2 := c + Vector2i(dx, dy)
				if q2.x >= 0 and q2.y >= 0 and q2.x < W and q2.y < H: img.set_pixel(q2.x, q2.y, col)
	for rr in L.rails:
		var cv: Curve3D = rr.curve
		var Ln := cv.get_baked_length(); var s := 0.0
		while s < Ln:
			dot.call((rr.path as Node3D).to_global(cv.sample_baked(s)), Color(1, 0.2, 0.2) if not rr.locked else Color(1, 0.5, 0.6), 0); s += px * 0.5
	for h in L.hooks: dot.call((h as Node3D).global_position, Color(1, 0.9, 0.1), 2)
	for b in L.bouncers: dot.call(b.pos, Color(0.2, 1, 0.3), 2)
	for m in L.movers:
		var par: Node3D = (m.body as Node3D).get_parent()
		dot.call(par.to_global(m.a), Color(0.3, 0.5, 1), 2); dot.call(par.to_global(m.b), Color(0.3, 0.5, 1), 2)
	for c in L.checkpoints: dot.call(c.pos, Color(1, 1, 1), 1)
	# grid every 20 m
	for gx in range(int(ceil(box.position.x / 20.0)) * 20, int(box.end.x), 20):
		var ix := int((gx - box.position.x) / px)
		for j in range(0, H, 3): img.set_pixel(ix, j, Color(0.4, 0.4, 0.5) if gx != 0 else Color(0.8, 0.5, 0.8))
	for gz in range(int(ceil(box.position.y / 20.0)) * 20, int(box.end.y), 20):
		var jz := int((gz - box.position.y) / px)
		for i in range(0, W, 3): img.set_pixel(i, jz, Color(0.4, 0.4, 0.5) if gz != 0 else Color(0.8, 0.5, 0.8))
	img.save_png(out)
	var info := {}
	for k in L.islands: info[k] = [L.islands[k], L.heights[k]]
	print("[map] saved ", out, " box ", box, " px ", px)
	for k in info: print("[map] island ", k, " ", info[k][0], " y=", info[k][1])
	for i in L.rails.size():
		var cv: Curve3D = L.rails[i].curve
		var pth: Node3D = L.rails[i].path; print("[map] rail ", i, " len=%.1f" % cv.get_baked_length(), " ", pth.to_global(cv.get_point_position(0)), " -> ", pth.to_global(cv.get_point_position(cv.point_count - 1)))
	get_tree().quit()
