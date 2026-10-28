extends Node3D
## Танк: параметры, состояние (позиция на плоскости карты) и 3D-модель.
## Модель смотрит вдоль +X; угол a на карте даёт rotation.y = -a.

const D = preload("res://scripts/data.gd")

var T: Dictionary = {}
var type_key := ""
var team := 0
var pos := Vector2.ZERO
var hull := 0.0
var tur := 0.0
var hp := 0.0
var max_hp := 0.0
var rl := 0.0  # до перезарядки, с
var alive := true
var is_player := false
var callsign := ""
var sp := 0.0
var vel := Vector2.ZERO
var lit := 0.0  # засвечен выстрелом/попаданием, с
var vis := [true, true]  # виден ли команде 0 / 1
var recoil := 0.0
var dist_travel := 0.0
var mark := 0.0

# состояние бота
var role := "atk"
var b_av := 0.0
var b_av_dir := 1.0
var b_strafe := 1.0
var b_st := 1.0
var b_goal := Vector2.ZERO
var b_gt := 0.0
var b_zone = null
var b_last := Vector2.ZERO
var b_pt := 1.0

var hull_node := Node3D.new()
var tur_node := Node3D.new()
var bar_node := Node3D.new()
var paint_mat: StandardMaterial3D
var band_mat: StandardMaterial3D
var smoke: CPUParticles3D

# башня, сорванная детонацией боеукладки
var popping := false
var pop_h := 0.0
var pop_vh := 0.0
var pop_off := Vector2.ZERO
var pop_v := Vector2.ZERO
var pop_spin := Vector2.ZERO


func setup(key: String, tm: int, p: Vector2, nm: String, player: bool, shadows: bool) -> void:
	type_key = key
	T = D.TYPES[key]
	team = tm
	pos = p
	b_last = p
	callsign = nm
	is_player = player
	hull = -PI / 2 if team == 0 else PI / 2
	tur = hull
	hp = T.hp
	max_hp = T.hp
	rl = randf_range(0.5, T.reload)
	b_strafe = 1.0 if randf() < 0.5 else -1.0
	b_st = randf_range(1.0, 3.0)
	_build(shadows)
	sync_node()


func turret_y() -> float:
	return float(T.W) * 0.45


func barrel_y() -> float:
	return float(T.W) * 0.6


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _add(mesh: Mesh, m: Material, p: Vector3, parent: Node3D, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(size: Vector3, m: Material, p: Vector3, parent: Node3D, shadows: bool) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add(b, m, p, parent, shadows)


func _cyl(top: float, bottom: float, h: float, seg: int, m: Material, p: Vector3, parent: Node3D, shadows: bool) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return _add(c, m, p, parent, shadows)


func _build(shadows: bool) -> void:
	var L: float = T.L
	var wd: float = T.W
	var th := wd * 0.3
	var ty := turret_y()
	var bw: float = T.bw
	var barrel: float = T.barrel
	paint_mat = _mat(Color(T.paint))
	var dark := _mat(Color("34362c"))
	band_mat = StandardMaterial3D.new()
	band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_mat.albedo_color = Color(D.ALLY if team == 0 else D.FOE)
	add_child(hull_node)
	# гусеницы
	_box(Vector3(L, th, wd * 0.26), dark, Vector3(0, th / 2, wd / 2 - wd * 0.13), hull_node, shadows)
	_box(Vector3(L, th, wd * 0.26), dark, Vector3(0, th / 2, -(wd / 2 - wd * 0.13)), hull_node, shadows)
	# корпус, надгусеничные полки, лобовой лист, моторное отделение
	_box(Vector3(L - 6, ty - th + 1, wd * 0.62), paint_mat, Vector3(-2, th + (ty - th + 1) / 2 - 0.5, 0), hull_node, shadows)
	_box(Vector3(L - 2, 1.2, wd), paint_mat, Vector3(0, th + 0.6, 0), hull_node, shadows)
	var glacis := _box(Vector3(10, 2, wd * 0.62), paint_mat, Vector3(L / 2 - 6, ty - 2.2, 0), hull_node, shadows)
	glacis.rotation.z = -0.5
	_box(Vector3(9, 1.4, wd * 0.5), dark, Vector3(-L / 2 + 7, ty + 0.6, 0), hull_node, false)
	# башня с цветной полосой команды
	tur_node.position.y = ty
	add_child(tur_node)
	var tm := _cyl(wd * 0.3, wd * 0.38, wd * 0.26, 10, paint_mat, Vector3(-2, wd * 0.13, 0), tur_node, shadows)
	tm.scale.x = 1.25
	var band := _cyl(wd * 0.385, wd * 0.385, 1.6, 10, band_mat, Vector3(-2, wd * 0.07, 0), tur_node, false)
	band.scale.x = 1.25
	_cyl(wd * 0.1, wd * 0.1, 1.6, 8, dark, Vector3(-5, wd * 0.27, wd * 0.1), tur_node, false)
	# ствол с дульным тормозом
	bar_node.position = Vector3(0, wd * 0.15, 0)
	tur_node.add_child(bar_node)
	var blen := barrel - wd * 0.3
	var tube := _cyl(bw * 0.38, bw * 0.5, blen, 8, dark, Vector3(wd * 0.3 + blen / 2, 0, 0), bar_node, shadows)
	tube.rotation.z = -PI / 2
	var brake := _cyl(bw * 0.7, bw * 0.7, 5, 8, dark, Vector3(barrel - 2.5, 0, 0), bar_node, false)
	brake.rotation.z = -PI / 2


func sync_node() -> void:
	position = Vector3(pos.x, 0, pos.y)
	var pitch := 0.0
	if alive:
		pitch = clampf(-sp * 0.0004, -0.04, 0.04) + recoil * 0.05
	hull_node.rotation = Vector3(0, -hull, pitch)
	if popping:
		tur_node.position = Vector3(pop_off.x, turret_y() + pop_h, pop_off.y)
	else:
		tur_node.rotation.y = -tur
	bar_node.position.x = -recoil * 3.0


func smoke_on(v: bool) -> void:
	if smoke and smoke.emitting != v:
		smoke.emitting = v


func make_wreck(pop: bool) -> void:
	paint_mat.albedo_color = Color("2b2a26")
	band_mat.albedo_color = Color("33322e")
	bar_node.rotation.z = -0.12
	smoke_on(false)
	if pop:
		popping = true
		pop_vh = randf_range(110.0, 160.0)
		pop_v = Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		pop_spin = Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))


func update_pop(dt: float) -> void:
	if not popping:
		return
	if pop_h > -turret_y() + 2.0 or pop_vh > 0:
		pop_vh -= 320.0 * dt
		pop_h += pop_vh * dt
		pop_off += pop_v * dt
		tur_node.rotation.x += pop_spin.x * dt
		tur_node.rotation.z += pop_spin.y * dt
