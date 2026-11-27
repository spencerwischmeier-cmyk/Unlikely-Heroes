extends RefCounted
## Drawing kit for the HUD: glossy panels, round badges, key caps and the icon set.
## Everything is drawn in code so it stays sharp at any screen size. Icons are original shapes
## (shield, sprocket gear, jetpack, flag, weapon emblems...) in the game's cartoon sci-fi style.
##
## Use from any Control's draw callback:  HD.panel(ctrl, rect, accent)  /  HD.icon(ctrl, "sprocket", centre, 20, colour)

const INK := Color(0.02, 0.035, 0.08, 0.96)          # outlines
const PANEL_TOP := Color(0.16, 0.23, 0.38, 0.92)
const PANEL_BOT := Color(0.035, 0.06, 0.13, 0.9)
const SLOT := Color(0.06, 0.09, 0.17, 0.95)            # empty gauge slots

static var _fonts := {}

## Chunky display font (numbers, names, headings).
static func head_font() -> Font:
	return _font("head", "res://fonts/LilitaOne-Regular.ttf", 0)

## Rounded heavy body font (sentences, captions).
static func body_font() -> Font:
	return _font("body", "res://fonts/Nunito.ttf", 850)

static func _font(key: String, path: String, weight: int) -> Font:
	if _fonts.has(key): return _fonts[key]
	var base: Font = null
	if ResourceLoader.exists(path): base = load(path)
	if base == null and FileAccess.file_exists(path):
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) == OK: base = ff
	if base == null:
		var sf := SystemFont.new(); sf.font_names = PackedStringArray(["Segoe UI", "Arial", "sans-serif"]); sf.font_weight = 900
		base = sf
	var f: Font = base
	if weight > 0:
		var fv := FontVariation.new(); fv.base_font = base
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
		f = fv
	_fonts[key] = f
	return f

# ---------------------------------------------------------------- shapes

## Points of a rounded rectangle, clockwise from the top-right corner. `skew` slants it like italics
## (x shifts by (pivot_y - y) * skew), so panels can lean forward.
static func rrect(r: Rect2, rad: float, skew := 0.0, pivot_y := INF, seg := 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var cs := [[Vector2(r.end.x - rad, r.position.y + rad), -PI / 2], [r.end - Vector2(rad, rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI / 2], [r.position + Vector2(rad, rad), PI]]
	for c in cs:
		for i in seg + 1:
			var a: float = c[1] + (PI / 2) * i / seg
			var q: Vector2 = c[0] + Vector2(cos(a), sin(a)) * rad
			if pts.is_empty() or pts[pts.size() - 1].distance_to(q) > 0.01: pts.append(q)
	if pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) <= 0.01: pts.remove_at(pts.size() - 1)
	if skew != 0.0:
		var py := r.get_center().y if pivot_y == INF else pivot_y
		for i in pts.size(): pts[i].x += (py - pts[i].y) * skew
	return pts

static func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate(); q.append(p[0]); return q

static func _fade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

## A glossy HUD panel: drop shadow, ink rim, top-lit gradient body, sheen and an accent edge.
static func panel(ci: CanvasItem, r: Rect2, accent: Color, rad := 14.0, skew := 0.0, alpha := 1.0, top := PANEL_TOP, bot := PANEL_BOT) -> void:
	var py := r.get_center().y
	ci.draw_colored_polygon(rrect(Rect2(r.position + Vector2(2, 5), r.size), rad, skew, py + 5), Color(0, 0, 0, 0.32 * alpha))
	# ink edge, a brushed-metal rim lit from the top left, then a thin ink seam
	var outer := rrect(r.grow(6.0), rad + 6.0, skew, py)
	ci.draw_colored_polygon(outer, _fade(INK, alpha))
	var rim := rrect(r.grow(4.5), rad + 4.5, skew, py)
	ci.draw_polygon(rim, _metal_cols(rim, r.grow(4.5), alpha))
	ci.draw_colored_polygon(rrect(r.grow(1.2), rad + 1.2, skew, py), _fade(INK, alpha))
	var body := rrect(r, rad, skew, py)
	var cols := PackedColorArray()
	for p in body:
		var t := clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)
		cols.append(_fade(top.lerp(bot, t), alpha))
	ci.draw_polygon(body, cols)
	# sheen across the top third
	var sh := Rect2(r.position + Vector2(4, 3), Vector2(r.size.x - 8, r.size.y * 0.36))
	var sheen := rrect(sh, maxf(2.0, rad - 4.0), skew, py)
	var sc := PackedColorArray()
	for p in sheen:
		var t := clampf((p.y - sh.position.y) / sh.size.y, 0.0, 1.0)
		sc.append(Color(1, 1, 1, lerpf(0.16, 0.0, t) * alpha))
	ci.draw_polygon(sheen, sc)
	ci.draw_polyline(_closed(body), _fade(accent, 0.95 * alpha), 2.0, true)
	ci.draw_polyline(_closed(outer), _fade(INK, alpha), 1.5, true)
	# bright accent bar along the bottom edge
	var bw := r.size.x - rad * 2.0
	var by := r.end.y - 2.0
	var bx := r.position.x + rad + (py - by) * skew
	ci.draw_line(Vector2(bx, by), Vector2(bx + bw, by), _fade(accent, alpha), 3.0, true)

## Brushed steel shading for rims: bright at the top left, dark at the bottom right, with a soft band.
static func _metal_cols(pts: PackedVector2Array, bounds: Rect2, alpha: float) -> PackedColorArray:
	var cols := PackedColorArray()
	for p in pts:
		var u := clampf(((p.x - bounds.position.x) / maxf(1.0, bounds.size.x) * 0.35 + (p.y - bounds.position.y) / maxf(1.0, bounds.size.y) * 0.65), 0.0, 1.0)
		var c := Color(0.86, 0.9, 0.97).lerp(Color(0.42, 0.47, 0.58), smoothstep(0.0, 0.55, u)).lerp(Color(0.2, 0.23, 0.32), smoothstep(0.55, 1.0, u))
		cols.append(_fade(c, alpha))
	return cols

## A round emblem: shadow, ink rim, accent ring, dark glass centre and a highlight arc.
static func badge(ci: CanvasItem, c: Vector2, r: float, accent: Color, alpha := 1.0) -> void:
	ci.draw_circle(c + Vector2(1.5, 5.5), r + 6.0, Color(0, 0, 0, 0.32 * alpha), true, -1, true)
	ci.draw_circle(c, r + 6.5, _fade(INK, alpha), true, -1, true)
	var ring := PackedVector2Array(_circle_pts(40, r + 5.0, c))
	ci.draw_polygon(ring, _metal_cols(ring, Rect2(c - Vector2(r + 5, r + 5), Vector2(r + 5, r + 5) * 2.0), alpha))
	ci.draw_circle(c, r + 1.5, _fade(INK, alpha), true, -1, true)
	ci.draw_circle(c, r, _fade(accent.darkened(0.25), alpha), true, -1, true)
	ci.draw_circle(c, r * 0.8, _fade(PANEL_BOT, alpha), true, -1, true)
	for i in 5:
		var t := i / 5.0
		ci.draw_circle(c - Vector2(0, r * 0.18 * t), r * 0.8 * (1.0 - t * 0.35), _fade(PANEL_TOP.lerp(accent.darkened(0.55), t * 0.5), 0.35 * alpha), true, -1, true)
	ci.draw_arc(c, r * 0.9, 0, TAU, 48, _fade(accent.lightened(0.2), alpha), r * 0.12, true)
	ci.draw_arc(c, r * 0.9, PI * 1.08, PI * 1.55, 16, Color(1, 1, 1, 0.55 * alpha), r * 0.07, true)

## Text with a thick dark outline. align: 0 left, 1 centre, 2 right of pos.x. pos.y is the baseline.
static func text(ci: CanvasItem, f: Font, pos: Vector2, s: String, size: int, col: Color, align := 0, outline := 6, alpha := 1.0) -> float:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	if outline > 0: ci.draw_string_outline(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, _fade(INK, alpha))
	ci.draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _fade(col, alpha))
	return w

## A button glyph: a coloured face button for pad letters A/B/X/Y when `pad`, else a keyboard key cap.
static func keycap(ci: CanvasItem, c: Vector2, key: String, pad: bool, alpha := 1.0) -> float:
	var f := head_font()
	if pad and key in ["A", "B", "X", "Y"]:
		var col: Color = {"A": Color(0.35, 0.85, 0.35), "B": Color(0.95, 0.35, 0.3), "X": Color(0.3, 0.6, 1.0), "Y": Color(1.0, 0.8, 0.2)}[key]
		ci.draw_circle(c + Vector2(0, 3), 17, Color(0, 0, 0, 0.35 * alpha), true, -1, true)
		ci.draw_circle(c, 17, _fade(INK, alpha), true, -1, true)
		ci.draw_circle(c, 14.5, _fade(Color(0.12, 0.14, 0.2), alpha), true, -1, true)
		ci.draw_arc(c, 13, 0, TAU, 32, _fade(col, alpha), 2.5, true)
		text(ci, f, c + Vector2(0, 8), key, 22, col, 1, 0, alpha)
		return 36.0
	var w := maxf(34.0, f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 18.0)
	var r := Rect2(c - Vector2(w * 0.5, 16), Vector2(w, 32))
	ci.draw_colored_polygon(rrect(Rect2(r.position + Vector2(0, 4), r.size), 7), Color(0, 0, 0, 0.35 * alpha))
	ci.draw_colored_polygon(rrect(r.grow(2), 9), _fade(INK, alpha))
	ci.draw_colored_polygon(rrect(Rect2(r.position + Vector2(0, 3), r.size - Vector2(0, 3)), 7), _fade(Color(0.62, 0.66, 0.75), alpha))
	ci.draw_colored_polygon(rrect(Rect2(r.position, r.size - Vector2(0, 5)), 7), _fade(Color(0.96, 0.97, 1.0), alpha))
	text(ci, f, c + Vector2(0, 6), key, 20, Color(0.08, 0.1, 0.18), 1, 0, alpha)
	return w

# ---------------------------------------------------------------- icons

## Fill a shape (points in -1..1 icon space) with an ink outline and a soft highlight on its upper half.
static func _shape(ci: CanvasItem, c: Vector2, s: float, pts, fill: Color, alpha: float, rot := 0.0, outline := true) -> void:
	var p := PackedVector2Array()
	for v in pts: p.append(c + (v as Vector2).rotated(rot) * s)
	if outline: ci.draw_polyline(_closed(p), _fade(INK, alpha), maxf(2.5, s * 0.16), true)
	var cols := PackedColorArray()
	for q in p:
		var t := clampf((q.y - (c.y - s)) / (2.0 * s), 0.0, 1.0)
		cols.append(_fade(fill.lightened(0.35).lerp(fill.darkened(0.15), t), alpha))
	ci.draw_polygon(p, cols)

static func _disc(ci: CanvasItem, c: Vector2, r: float, fill: Color, alpha: float, outline := true) -> void:
	if outline: ci.draw_circle(c, r + maxf(1.2, r * 0.18), _fade(INK, alpha), true, -1, true)
	ci.draw_circle(c, r, _fade(fill, alpha), true, -1, true)
	ci.draw_circle(c - Vector2(r * 0.25, r * 0.3), r * 0.45, Color(1, 1, 1, 0.3 * alpha), true, -1, true)

static func _bar(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color, alpha: float) -> void:
	ci.draw_line(a, b, _fade(INK, alpha), w + 3.0, true)
	ci.draw_line(a, b, _fade(col, alpha), w, true)

static func _circle_pts(n: int, r: float, off := Vector2.ZERO, squash := 1.0) -> Array:
	var a := []
	for i in n: a.append(off + Vector2(cos(TAU * i / n), sin(TAU * i / n) * squash) * r)
	return a

## Draw icon `kind` centred at c, s = half size in pixels.
static func icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color, alpha := 1.0, rot := 0.0) -> void:
	match kind:
		"hull":   # a shield with a repair cross
			_shape(ci, c, s, [Vector2(-0.82, -0.68), Vector2(0, -0.98), Vector2(0.82, -0.68), Vector2(0.76, 0.08), Vector2(0.45, 0.58), Vector2(0, 0.96), Vector2(-0.45, 0.58), Vector2(-0.76, 0.08)], col, alpha)
			ci.draw_rect(Rect2(c + Vector2(-0.13, -0.5) * s, Vector2(0.26, 0.96) * s), _fade(Color.WHITE, alpha))
			ci.draw_rect(Rect2(c + Vector2(-0.45, -0.15) * s, Vector2(0.9, 0.26) * s), _fade(Color.WHITE, alpha))
		"sprocket":   # an eight-tooth gear
			var p := []
			for i in 8:
				var a := TAU * i / 8.0
				for d in [[-0.24, 0.72], [-0.15, 1.0], [0.15, 1.0], [0.24, 0.72]]:
					p.append(Vector2(cos(a + d[0]), sin(a + d[0])) * d[1])
			_shape(ci, c, s, p, col, alpha, rot)
			ci.draw_circle(c, s * 0.5, _fade(col.darkened(0.25), alpha), true, -1, true)
			ci.draw_circle(c, s * 0.27, _fade(INK, alpha), true, -1, true)
			ci.draw_arc(c, s * 0.6, PI * 1.1, PI * 1.6, 10, Color(1, 1, 1, 0.5 * alpha), s * 0.1, true)
		"washer":   # a lucky washer: flat ring
			_disc(ci, c, s * 0.92, col, alpha)
			ci.draw_arc(c, s * 0.62, 0, TAU, 32, _fade(col.darkened(0.3), alpha), s * 0.08, true)
			ci.draw_circle(c, s * 0.36, _fade(INK, alpha), true, -1, true)
		"page":   # a sheet with a folded corner
			_shape(ci, c, s, [Vector2(-0.7, -0.95), Vector2(0.3, -0.95), Vector2(0.7, -0.55), Vector2(0.7, 0.95), Vector2(-0.7, 0.95)], col, alpha)
			_shape(ci, c, s, [Vector2(0.3, -0.95), Vector2(0.7, -0.55), Vector2(0.3, -0.55)], col.darkened(0.3), alpha, 0.0, false)
			for y in [-0.2, 0.15, 0.5]:
				ci.draw_line(c + Vector2(-0.45, y) * s, c + Vector2(0.45, y) * s, _fade(col.darkened(0.45), alpha), maxf(1.5, s * 0.1), true)
		"gripe":   # an envelope
			_shape(ci, c, s, [Vector2(-0.95, -0.62), Vector2(0.95, -0.62), Vector2(0.95, 0.68), Vector2(-0.95, 0.68)], col, alpha)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.9, -0.55) * s, c + Vector2(0, 0.12) * s, c + Vector2(0.9, -0.55) * s]), _fade(INK, alpha), maxf(2.0, s * 0.12), true)
		"flag":   # objective flag on a pole
			_bar(ci, c + Vector2(-0.6, -0.95) * s, c + Vector2(-0.6, 0.98) * s, maxf(2.0, s * 0.16), Color(0.9, 0.92, 1.0), alpha)
			_shape(ci, c, s, [Vector2(-0.5, -0.92), Vector2(0.1, -0.78), Vector2(0.9, -0.88), Vector2(0.65, -0.45), Vector2(0.9, -0.05), Vector2(0.1, 0.02), Vector2(-0.5, -0.1)], col, alpha)
		"boss":   # an angry bot head with antenna horns
			_bar(ci, c + Vector2(-0.55, -0.55) * s, c + Vector2(-0.8, -0.98) * s, maxf(2.0, s * 0.14), col.lightened(0.2), alpha)
			_bar(ci, c + Vector2(0.55, -0.55) * s, c + Vector2(0.8, -0.98) * s, maxf(2.0, s * 0.14), col.lightened(0.2), alpha)
			_shape(ci, c, s, rrect(Rect2(-0.85, -0.6, 1.7, 1.45), 0.35, 0.0, INF, 4), col, alpha)
			_shape(ci, c, s, [Vector2(-0.62, -0.18), Vector2(-0.12, 0.02), Vector2(-0.18, 0.22), Vector2(-0.62, 0.12)], Color(1, 0.95, 0.5), alpha, 0.0, false)
			_shape(ci, c, s, [Vector2(0.62, -0.18), Vector2(0.12, 0.02), Vector2(0.18, 0.22), Vector2(0.62, 0.12)], Color(1, 0.95, 0.5), alpha, 0.0, false)
			for x in [-0.4, -0.13, 0.13, 0.4]:
				ci.draw_rect(Rect2(c + Vector2(x - 0.09, 0.45) * s, Vector2(0.18, 0.22) * s), _fade(INK, alpha))
		"jet":   # a jetpack: pack body, twin nozzles and flames
			_shape(ci, c, s, [Vector2(-0.52, 0.42), Vector2(-0.32, 1.0), Vector2(-0.12, 0.42)], Color(1, 0.55, 0.12), alpha)
			_shape(ci, c, s, [Vector2(0.12, 0.42), Vector2(0.32, 1.0), Vector2(0.52, 0.42)], Color(1, 0.55, 0.12), alpha)
			_shape(ci, c, s, [Vector2(-0.56, 0.15), Vector2(-0.08, 0.15), Vector2(-0.14, 0.5), Vector2(-0.5, 0.5)], Color(0.45, 0.5, 0.6), alpha)
			_shape(ci, c, s, [Vector2(0.08, 0.15), Vector2(0.56, 0.15), Vector2(0.5, 0.5), Vector2(0.14, 0.5)], Color(0.45, 0.5, 0.6), alpha)
			_shape(ci, c, s, rrect(Rect2(-0.78, -0.95, 1.56, 1.2), 0.32, 0.0, INF, 4), col, alpha)
			ci.draw_line(c + Vector2(0, -0.8) * s, c + Vector2(0, 0.12) * s, _fade(col.darkened(0.45), alpha), maxf(1.5, s * 0.12), true)
		"dash":   # double chevron
			for x in [-0.45, 0.2]:
				_shape(ci, c, s, [Vector2(x - 0.3, -0.75), Vector2(x + 0.05, -0.75), Vector2(x + 0.5, 0), Vector2(x + 0.05, 0.75), Vector2(x - 0.3, 0.75), Vector2(x + 0.15, 0)], col, alpha)
		"ammo":   # a cartridge
			_shape(ci, c, s, [Vector2(-0.32, -0.3), Vector2(-0.2, -0.75), Vector2(0, -0.95), Vector2(0.2, -0.75), Vector2(0.32, -0.3), Vector2(0.32, 0.92), Vector2(-0.32, 0.92)], col, alpha)
			ci.draw_line(c + Vector2(-0.3, -0.2) * s, c + Vector2(0.3, -0.2) * s, _fade(INK, alpha), maxf(1.5, s * 0.12), true)
			ci.draw_line(c + Vector2(-0.3, 0.65) * s, c + Vector2(0.3, 0.65) * s, _fade(INK, alpha), maxf(1.5, s * 0.1), true)
		"heat":   # a flame
			_shape(ci, c, s, [Vector2(0, -1.0), Vector2(0.35, -0.5), Vector2(0.72, 0.05), Vector2(0.62, 0.62), Vector2(0.2, 0.95), Vector2(-0.3, 0.92), Vector2(-0.68, 0.55), Vector2(-0.7, 0.0), Vector2(-0.38, -0.35), Vector2(-0.2, 0.0)], col, alpha)
			_shape(ci, c, s, [Vector2(0.05, -0.2), Vector2(0.35, 0.3), Vector2(0.25, 0.75), Vector2(-0.2, 0.75), Vector2(-0.32, 0.35)], Color(1, 0.95, 0.6), alpha, 0.0, false)
		"bolt":   # Arc Lancer: lightning bolt
			_shape(ci, c, s, [Vector2(0.25, -1.0), Vector2(-0.55, 0.12), Vector2(-0.05, 0.12), Vector2(-0.3, 1.0), Vector2(0.6, -0.2), Vector2(0.1, -0.2), Vector2(0.45, -1.0)], col, alpha)
		"bloom":   # Scatter Bloom: five petals
			for i in 5:
				var a := -PI / 2 + TAU * i / 5.0
				_disc(ci, c + Vector2(cos(a), sin(a)) * s * 0.52, s * 0.4, col, alpha)
			_disc(ci, c, s * 0.34, Color(1, 0.92, 0.45), alpha)
		"lobber":   # Thump Lobber: a round bomb with a lit fuse
			_bar(ci, c + Vector2(0.3, -0.5) * s, c + Vector2(0.62, -0.88) * s, maxf(2.0, s * 0.14), Color(0.85, 0.8, 0.7), alpha)
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				ci.draw_line(c + Vector2(0.72, -0.95) * s, c + (Vector2(0.72, -0.95) + Vector2(cos(a), sin(a)) * 0.28) * s, _fade(Color(1, 0.85, 0.3), alpha), maxf(1.5, s * 0.1), true)
			_disc(ci, c + Vector2(-0.08, 0.18) * s, s * 0.72, col, alpha)
			ci.draw_arc(c + Vector2(-0.08, 0.18) * s, s * 0.72, 0.2, 1.2, 12, _fade(col.darkened(0.4), alpha), s * 0.14, true)
		"hive":   # Seeker Hive: hex cell with three drones
			_shape(ci, c, s, _circle_pts(6, 0.95), col, alpha, PI / 6)
			ci.draw_colored_polygon(PackedVector2Array(_circle_pts(6, 0.6 * s, c).map(func(v): return c + (v - c).rotated(PI / 6))), _fade(col.darkened(0.45), alpha))
			for i in 3:
				var a := -PI / 2 + TAU * i / 3.0
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * s * 0.3, s * 0.17, _fade(Color(1, 1, 0.85), alpha), true, -1, true)
		"up":   # level-up arrow
			_shape(ci, c, s, [Vector2(0, -1.0), Vector2(0.85, -0.1), Vector2(0.35, -0.1), Vector2(0.35, 0.95), Vector2(-0.35, 0.95), Vector2(-0.35, -0.1), Vector2(-0.85, -0.1)], col, alpha)
		"lock":   # padlock
			ci.draw_arc(c + Vector2(0, -0.25) * s, s * 0.42, PI, TAU, 16, _fade(INK, alpha), s * 0.3, true)
			ci.draw_arc(c + Vector2(0, -0.25) * s, s * 0.42, PI, TAU, 16, _fade(col.lightened(0.3), alpha), s * 0.16, true)
			_shape(ci, c, s, rrect(Rect2(-0.7, -0.25, 1.4, 1.15), 0.2, 0.0, INF, 3), col, alpha)
			ci.draw_circle(c + Vector2(0, 0.3) * s, s * 0.14, _fade(INK, alpha), true, -1, true)
		"chat":   # speech bubble
			_shape(ci, c, s, [Vector2(-0.05, 0.4), Vector2(-0.55, 0.95), Vector2(-0.55, 0.4)], col, alpha)
			_shape(ci, c, s, rrect(Rect2(-0.95, -0.8, 1.9, 1.25), 0.4, 0.0, INF, 4), col, alpha)
		"vesk":   # Vesk's portrait: round furry head, ears, muzzle, a grumpy brow and his glowing eyepiece
			var fur := Color(0.66, 0.44, 0.28)
			for sx in [-1.0, 1.0]:
				_disc(ci, c + Vector2(sx * 0.62, -0.62) * s, s * 0.3, fur.darkened(0.1), alpha)
				ci.draw_circle(c + Vector2(sx * 0.62, -0.62) * s, s * 0.15, _fade(Color(0.85, 0.6, 0.5), alpha), true, -1, true)
			_disc(ci, c, s * 0.86, fur, alpha)
			ci.draw_circle(c + Vector2(0, 0.34) * s, s * 0.4, _fade(Color(0.93, 0.8, 0.62), alpha), true, -1, true)
			ci.draw_circle(c + Vector2(0, 0.2) * s, s * 0.13, _fade(INK, alpha), true, -1, true)
			ci.draw_arc(c + Vector2(0, 0.42) * s, s * 0.16, 0.4, PI - 0.4, 8, _fade(INK, alpha), maxf(1.5, s * 0.07), true)
			# left eye + grumpy brow
			ci.draw_circle(c + Vector2(-0.34, -0.14) * s, s * 0.09, _fade(INK, alpha), true, -1, true)
			ci.draw_line(c + Vector2(-0.52, -0.36) * s, c + Vector2(-0.16, -0.26) * s, _fade(INK, alpha), maxf(2.0, s * 0.1), true)
			# eyepiece over the right eye: gunmetal frame, cyan lens, strap
			ci.draw_line(c + Vector2(0.3, -0.18) * s, c + Vector2(0.86, -0.38) * s, _fade(Color(0.25, 0.27, 0.33), alpha), maxf(2.0, s * 0.12), true)
			ci.draw_circle(c + Vector2(0.34, -0.16) * s, s * 0.25, _fade(INK, alpha), true, -1, true)
			ci.draw_circle(c + Vector2(0.34, -0.16) * s, s * 0.2, _fade(Color(0.45, 0.5, 0.58), alpha), true, -1, true)
			ci.draw_circle(c + Vector2(0.34, -0.16) * s, s * 0.13, _fade(Color(0.4, 1.0, 0.95), alpha), true, -1, true)
			ci.draw_circle(c + Vector2(0.3, -0.2) * s, s * 0.05, Color(1, 1, 1, 0.9 * alpha), true, -1, true)
		"play":   # resume: a rounded play triangle
			_shape(ci, c, s, [Vector2(-0.55, -0.85), Vector2(0.9, 0.0), Vector2(-0.55, 0.85)], col, alpha)
		"sliders":   # settings: three slider tracks with knobs at different heights
			for i in 3:
				var x := (-0.55 + i * 0.55) * s
				_bar(ci, c + Vector2(x, -0.85 * s), c + Vector2(x, 0.85 * s), maxf(2.0, s * 0.14), Color(0.8, 0.85, 0.95), alpha)
				_disc(ci, c + Vector2(x, [0.35, -0.45, 0.1][i] * s), s * 0.26, col, alpha)
		"restart":   # checkpoint restart: a circular arrow round a little flag
			ci.draw_arc(c, s * 0.72, -PI * 0.35, PI * 1.45, 24, _fade(INK, alpha), s * 0.36, true)
			ci.draw_arc(c, s * 0.72, -PI * 0.35, PI * 1.45, 24, _fade(col, alpha), s * 0.2, true)
			var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * s * 0.72
			_shape(ci, tip, s, [Vector2(-0.38, -0.12), Vector2(0.2, -0.32), Vector2(0.02, 0.32)], col, alpha)
			ci.draw_circle(c, s * 0.16, _fade(col.lightened(0.4), alpha), true, -1, true)
		"home":   # quit to title: a little house
			_shape(ci, c, s, [Vector2(0, -0.95), Vector2(0.9, -0.1), Vector2(0.65, -0.1), Vector2(0.65, 0.85), Vector2(-0.65, 0.85), Vector2(-0.65, -0.1), Vector2(-0.9, -0.1)], col, alpha)
			ci.draw_rect(Rect2(c + Vector2(-0.2, 0.25) * s, Vector2(0.4, 0.6) * s), _fade(INK, alpha))
		"power":   # quit game: power symbol
			ci.draw_arc(c, s * 0.7, -PI * 0.3, PI * 1.3, 24, _fade(INK, alpha), s * 0.4, true)
			ci.draw_arc(c, s * 0.7, -PI * 0.3, PI * 1.3, 24, _fade(col, alpha), s * 0.22, true)
			_bar(ci, c + Vector2(0, -0.95 * s), c + Vector2(0, -0.1 * s), s * 0.22, col, alpha)
		"xp":   # small star
			icon(ci, "star", c, s, col, alpha)
		_:   # "star"
			var p := []
			for i in 10:
				var a := -PI / 2 + TAU * i / 10.0
				p.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else 0.45))
			_shape(ci, c, s, p, col, alpha, rot)

## The emblem used for each weapon.
static func weapon_icon(id: String) -> String:
	return {"arc_lancer": "bolt", "scatter_bloom": "bloom", "thump_lobber": "lobber", "seeker_hive": "hive"}.get(id, "star")
