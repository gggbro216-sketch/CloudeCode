extends Node2D
## Следы боя на земле: воронки, гарь под остовами и павшие бойцы. Перерисовывается только при изменении.

const MapT = preload("res://scripts/map.gd")

var craters: Array = []
var bodies: Array = []
var scorch: Array = []
var dirty := false


func crater(p: Vector2, r: float) -> void:
	if craters.size() > 400:
		craters.pop_front()
	craters.append([p, r, randf() * TAU])
	dirty = true


func body(p: Vector2, ang: float, col: Color) -> void:
	if bodies.size() > 500:
		bodies.pop_front()
	bodies.append([p, ang, col])
	dirty = true


func burn_mark(p: Vector2, r: float) -> void:
	scorch.append([p, r])
	dirty = true


func _process(_dt: float) -> void:
	if dirty:
		dirty = false
		queue_redraw()


func _draw() -> void:
	for s in scorch:
		MapT.blob(self, s[0], s[1] * 1.6, Color(0.08, 0.07, 0.05, 0.35), 10, s[1])
		MapT.blob(self, s[0], s[1], Color(0.06, 0.05, 0.04, 0.5), 9, s[1] * 2.0)
	for c in craters:
		var p: Vector2 = c[0]
		var r: float = c[1]
		MapT.blob(self, p, r * 1.5, Color(0.30, 0.25, 0.18, 0.45), 9, c[2])
		MapT.blob(self, p, r, Color(0.13, 0.11, 0.08, 0.8), 8, c[2] + 1.0)
		MapT.blob(self, p + Vector2(r * 0.15, r * 0.2), r * 0.6, Color(0.08, 0.07, 0.05, 0.8), 7, c[2] + 2.0)
	for b in bodies:
		draw_set_transform(b[0], b[1])
		var col: Color = b[2]
		draw_rect(Rect2(-0.9, -0.3, 1.6, 0.6), col.darkened(0.35))
		draw_circle(Vector2(0.75, 0.0), 0.28, col.darkened(0.5))
		draw_set_transform(Vector2.ZERO, 0.0)
