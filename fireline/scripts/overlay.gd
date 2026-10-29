extends Control
## Экранный слой поверх карты: маркеры подразделений, выделение, маршруты, линии огня,
## точки захвата, последние известные позиции противника, заявки артиллерии, зона расстановки.

const UnitT = preload("res://scripts/unit.gd")
const BLUE := Color(0.25, 0.48, 0.9)
const RED := Color(0.85, 0.25, 0.2)
const GREY := Color(0.7, 0.7, 0.7)

var battle
var pings: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func ping(wp: Vector2, col: Color) -> void:
	pings.append({"p": wp, "c": col, "t": 0.0})


func _process(delta: float) -> void:
	for p in pings:
		p.t += delta
	pings = pings.filter(func(p): return p.t < 0.7)


func _side_col(s: int) -> Color:
	if s < 0:
		return GREY
	return BLUE if s == battle.player_side else RED


func _draw() -> void:
	var b = battle
	if b == null or b.map == null:
		return
	var font := get_theme_default_font()
	var z: float = b.zoom
	var vs := size
	var me: int = b.player_side
	# зона расстановки
	if b.phase == "deploy":
		var r: Rect2 = b.map.zones[me]
		var a: Vector2 = b.to_screen(r.position)
		var c: Vector2 = b.to_screen(r.end)
		draw_rect(Rect2(a, c - a), Color(0.4, 1.0, 0.4, 0.10))
		draw_rect(Rect2(a, c - a), Color(0.5, 1.0, 0.5, 0.6), false, 2.0)
	# точки захвата
	for f in b.flags:
		var sp: Vector2 = b.to_screen(f.p)
		var col := _side_col(f.owner)
		var rr: float = 35.0 * z
		draw_arc(sp, rr, 0.0, TAU, 48, Color(col, 0.55), 2.0)
		if absf(f.prog) < 1.0 or f.contested:
			var pc := BLUE if f.prog < 0.0 else RED
			if f.prog != 0.0:
				draw_arc(sp, rr + 4.0, -PI * 0.5, -PI * 0.5 + TAU * absf(f.prog), 48, pc, 4.0)
		draw_line(sp, sp - Vector2(0, 34), Color(0.15, 0.12, 0.1), 3.0)
		draw_rect(Rect2(sp + Vector2(1, -34), Vector2(24, 15)), col)
		draw_string(font, sp + Vector2(1, -22), f.name, HORIZONTAL_ALIGNMENT_CENTER, 24, 13, Color.WHITE)
		if f.contested:
			draw_string(font, sp + Vector2(-30, 14), "бой", HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(1, 0.9, 0.5))
	# заявки артиллерии
	for br in b.barrages:
		if br.side != me and not b.autoplay:
			continue
		var sp: Vector2 = b.to_screen(br.p)
		var rr := (28.0 if br.kind == "he" else 16.0) * z
		var col := Color(1.0, 0.35, 0.25, 0.8) if br.kind == "he" else Color(0.85, 0.85, 0.85, 0.8)
		for i in 16:
			var a0 := TAU * i / 16.0
			draw_arc(sp, rr, a0, a0 + TAU / 32.0, 4, col, 2.0)
		draw_line(sp - Vector2(10, 0), sp + Vector2(10, 0), col, 2.0)
		draw_line(sp - Vector2(0, 10), sp + Vector2(0, 10), col, 2.0)
		if br.delay > 0.0:
			draw_string(font, sp + Vector2(-30, -14), "%d" % int(ceil(br.delay)), HORIZONTAL_ALIGNMENT_CENTER, 60, 16, col)
	# маршруты и линии огня своих подразделений
	for u in b.units:
		if u.side != me or not u.alive:
			continue
		var sel: bool = b.selection.has(u)
		if u.path_i < u.path.size():
			var pts := PackedVector2Array([b.to_screen(u.position)])
			for i in range(u.path_i, u.path.size()):
				pts.append(b.to_screen(u.path[i]))
			var col := Color(0.5, 1.0, 0.5)
			if u.move_mode == UnitT.MV_FAST or u.state == UnitT.ST_ROUT:
				col = Color(1.0, 0.75, 0.3)
			elif u.move_mode == UnitT.MV_BACK:
				col = Color(0.5, 0.85, 1.0)
			col.a = 0.9 if sel else 0.35
			if pts.size() >= 2:
				draw_polyline(pts, col, 2.5 if sel else 1.5)
				draw_circle(pts[pts.size() - 1], 4.0 if sel else 3.0, col)
		if sel:
			if u.forced != null and u.forced.alive and b.is_spotted(me, u.forced):
				draw_line(b.to_screen(u.position), b.to_screen(u.forced.position), Color(1.0, 0.3, 0.25, 0.9), 2.0)
			elif u.target != null and is_instance_valid(u.target) and u.target.alive:
				draw_dashed_line(b.to_screen(u.position), b.to_screen(u.target.position), Color(1.0, 0.4, 0.3, 0.6), 1.5, 8.0)
			if u.area != Vector2.INF:
				var ap: Vector2 = b.to_screen(u.area)
				draw_line(b.to_screen(u.position), ap, Color(1.0, 0.6, 0.2, 0.8), 2.0)
				draw_line(ap - Vector2(8, 8), ap + Vector2(8, 8), Color(1.0, 0.6, 0.2), 3.0)
				draw_line(ap - Vector2(8, -8), ap + Vector2(8, -8), Color(1.0, 0.6, 0.2), 3.0)
			if b.order_mode == "fire" and u.max_range > 0.0:
				draw_arc(b.to_screen(u.position), u.max_range * z, 0.0, TAU, 96, Color(1.0, 0.5, 0.3, 0.35), 1.5)
	# маркеры подразделений
	var small := z < 2.6
	var mw := 32.0 if small else 40.0
	var mh := 15.0 if small else 18.0
	var fs := 11 if small else 13
	for u in b.units:
		if not u.alive:
			continue
		if u.side != me and not (b.autoplay or b.is_spotted(me, u)):
			continue
		var sp: Vector2 = b.to_screen(u.position)
		if sp.x < -60 or sp.y < -60 or sp.x > vs.x + 60 or sp.y > vs.y + 60:
			continue
		var col := _side_col(u.side)
		var sel: bool = b.selection.has(u)
		if sel:
			draw_arc(sp, maxf(u.radius() * z + 4.0, 14.0), 0.0, TAU, 40, Color(0.55, 1.0, 0.55, 0.95), 2.0)
		var top := sp - Vector2(0.0, maxf(u.radius() * z * 0.9, 10.0) + mh * 0.5 + 6.0)
		var r := Rect2(top - Vector2(mw, mh) * 0.5, Vector2(mw, mh))
		draw_rect(r, Color(col, 0.88))
		draw_rect(r, Color.WHITE if sel else Color(0, 0, 0, 0.6), false, 2.0 if sel else 1.0)
		draw_string(font, Vector2(r.position.x, r.end.y - (3.0 if small else 4.0)), u.t.short,
			HORIZONTAL_ALIGNMENT_CENTER, mw, fs, Color.WHITE)
		var st: float = u.strength()
		var bar := Rect2(r.position + Vector2(0, mh + 1), Vector2(mw, 3))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(mw * st, 3)), Color(1.0 - st, 0.3 + st * 0.6, 0.2))
		# подавление
		if u.suppression > 5.0 and not u.is_veh:
			var sb := Rect2(bar.position + Vector2(0, 4), Vector2(mw * u.suppression / 100.0, 2))
			draw_rect(sb, Color(1.0, 0.85, 0.2, 0.9))
		var icon := ""
		var icol := Color(1, 0.9, 0.3)
		if u.state == UnitT.ST_ROUT:
			icon = "<<"
			icol = Color(1, 1, 1)
		elif u.state == UnitT.ST_PINNED:
			icon = "!"
		elif u.immobile:
			icon = "X"
			icol = Color(1, 0.6, 0.4)
		elif u.hold_fire and u.side == me:
			icon = "З"
			icol = Color(0.7, 0.9, 1.0)
		if icon != "":
			draw_string(font, Vector2(r.end.x + 2, r.end.y - 2), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 2, icol)
	# последние известные позиции противника
	for g in b.ghosts.values():
		var sp: Vector2 = b.to_screen(g.p)
		var a: float = clampf(g.t / 25.0, 0.0, 1.0) * 0.6
		var r := Rect2(sp - Vector2(mw, mh) * 0.5 - Vector2(0, 14), Vector2(mw, mh))
		draw_rect(r, Color(RED, a * 0.6))
		draw_rect(r, Color(1, 1, 1, a), false, 1.0)
		draw_string(font, Vector2(r.position.x, r.end.y - 4.0), "?", HORIZONTAL_ALIGNMENT_CENTER, mw, fs, Color(1, 1, 1, a + 0.2))
	# рисуемый пальцем маршрут
	if b.drag_path.size() >= 2:
		var pts := PackedVector2Array()
		for p in b.drag_path:
			pts.append(b.to_screen(p))
		draw_polyline(pts, Color(1, 1, 1, 0.85), 3.0)
	for p in pings:
		var f: float = p.t / 0.7
		var col: Color = p.c
		col.a = 1.0 - f
		draw_arc(b.to_screen(p.p), 8.0 + f * 22.0, 0.0, TAU, 24, col, 3.0)
