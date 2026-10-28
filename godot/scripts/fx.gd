extends Node3D
## Эффекты частиц: вспышки выстрелов, искры, пыль, дым и взрывы.

var soft: GradientTexture2D
var mats := {}
var quads := {}
var ramps := {}
var grow_curve := Curve.new()
var shrink_curve := Curve.new()


func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft = GradientTexture2D.new()
	soft.gradient = g
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	soft.width = 64
	soft.height = 64
	ramps["fire"] = _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.15, 0.9), Color(0.3, 0.1, 0.05, 0)])
	ramps["spark"] = _ramp([Color(1, 0.85, 0.5, 1), Color(1, 0.5, 0.1, 0)])
	ramps["smoke"] = _ramp([Color(0.42, 0.42, 0.4, 0.55), Color(0.3, 0.3, 0.29, 0)])
	ramps["dark"] = _ramp([Color(0.12, 0.12, 0.11, 0.75), Color(0.1, 0.1, 0.1, 0)])
	set_dust(Color(0.55, 0.5, 0.4))
	grow_curve.add_point(Vector2(0, 0.35))
	grow_curve.add_point(Vector2(1, 1))
	shrink_curve.add_point(Vector2(0, 1))
	shrink_curve.add_point(Vector2(1, 0.2))


func set_dust(c: Color) -> void:
	var a := c
	a.a = 0.55
	var b := c
	b.a = 0.0
	ramps["dust"] = _ramp([a, b])


func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	for i in cols.size():
		offs.append(float(i) / (cols.size() - 1))
	g.offsets = offs
	g.colors = PackedColorArray(cols)
	return g


func _quad(size: float, add: bool) -> QuadMesh:
	var key := "%d_%s" % [int(size), add]
	if quads.has(key):
		return quads[key]
	if not mats.has(add):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if add:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = soft
		m.disable_receive_shadows = true
		mats[add] = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mats[add]
	quads[key] = q
	return q


func emit(at: Vector3, amount: int, life: float, ramp: String, vmin: float, vmax: float, dir: Vector3, spread: float,
		grav: float, size: float, add: bool, grow: bool, damp := 0.0, one_shot := true, parent: Node3D = null) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _quad(size, add)
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.lifetime_randomness = 0.4
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, grav, 0)
	p.damping_min = damp
	p.damping_max = damp
	p.color_ramp = ramps[ramp]
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.scale_amount_curve = grow_curve if grow else shrink_curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	if parent:
		parent.add_child(p)
		p.position = at
	else:
		add_child(p)
		p.global_position = at
	p.emitting = true
	if one_shot:
		get_tree().create_timer(life + 0.6, false).timeout.connect(p.queue_free)
	return p


func muzzle(at: Vector3, a: float) -> void:
	var dir := Vector3(cos(a), 0.05, sin(a))
	emit(at, 12, 0.18, "fire", 40, 200, dir, 25, 0, 6, true, false, 4)
	emit(at, 8, 1.1, "smoke", 15, 60, dir, 35, 6, 14, false, true, 2)


func hit_sparks(at: Vector3) -> void:
	emit(at, 16, 0.35, "spark", 60, 170, Vector3.UP, 90, -220, 4, true, false)
	emit(at, 4, 0.8, "smoke", 5, 20, Vector3.UP, 60, 5, 12, false, true, 1)


func impact(at: Vector3) -> void:
	emit(at, 8, 0.4, "spark", 40, 120, Vector3.UP, 80, -200, 3, true, false)
	emit(at, 6, 0.9, "dust", 10, 40, Vector3.UP, 70, 4, 16, false, true, 2)


func shot_dust(at: Vector3) -> void:
	emit(at, 5, 0.8, "dust", 20, 50, Vector3.UP, 85, 0, 24, false, true, 3)


func explosion(at: Vector3) -> void:
	emit(at, 46, 0.9, "fire", 40, 230, Vector3.UP, 180, 20, 14, true, false, 3)
	emit(at, 26, 2.8, "dark", 15, 60, Vector3.UP, 70, 12, 30, false, true, 1.5)


## Постоянный дым и огонь над подбитым танком.
func wreck_fire(at: Vector3) -> void:
	emit(at, 10, 2.6, "dark", 18, 30, Vector3.UP, 15, 4, 20, false, true, 0, false)
	emit(at, 6, 0.6, "fire", 20, 50, Vector3.UP, 20, 0, 7, true, false, 0, false)


## Дымный шлейф повреждённого танка (включается, когда прочности мало).
func damage_smoke(tank: Node3D, y: float) -> CPUParticles3D:
	var p := emit(Vector3(0, y, 0), 14, 1.4, "smoke", 15, 25, Vector3.UP, 15, 4, 14, false, true, 0, false, tank)
	p.emitting = false
	return p
