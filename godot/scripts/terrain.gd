extends RefCounted
## Рельеф: карта высот (холмы, горы по краю, площадки под постройки и зоны, воронки),
## быстрая выборка высоты и нормали, сетка с коллизией и шейдер земли.

const D = preload("res://scripts/data.gd")

const ORIGIN := -700.0  # рельеф шире игровой зоны: по краям поднимаются горы
const SIZE := 3600.0
const N := 180
const CELL := SIZE / N

var h := PackedFloat32Array()
var mask: Image  # R — дорога, G — гарь воронок, B — пахота/грязь
var mask_tex: ImageTexture


func height(x: float, z: float) -> float:
	var fx := clampf((x - ORIGIN) / CELL, 0.0, N - 0.001)
	var fz := clampf((z - ORIGIN) / CELL, 0.0, N - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * (N + 1) + ix
	return lerpf(lerpf(h[i], h[i + 1], tx), lerpf(h[i + N + 1], h[i + N + 2], tx), tz)


func normal(x: float, z: float, e := 6.0) -> Vector3:
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


func _vx(i: int) -> float:
	return ORIGIN + (i % (N + 1)) * CELL


func _vz(i: int) -> float:
	return ORIGIN + (i / (N + 1)) * CELL


## Окно индексов вершин, покрывающее прямоугольник мира.
func _window(r: Rect2) -> Array:
	var x0 := clampi(int((r.position.x - ORIGIN) / CELL), 0, N)
	var x1 := clampi(int((r.end.x - ORIGIN) / CELL) + 1, 0, N)
	var z0 := clampi(int((r.position.y - ORIGIN) / CELL), 0, N)
	var z1 := clampi(int((r.end.y - ORIGIN) / CELL) + 1, 0, N)
	return [x0, x1, z0, z1]


func generate(map_key: String, zones: Array, obst: Array, craters: Array, roads: Array) -> void:
	var M: Dictionary = D.MAPS[map_key]
	var relief: float = M.relief
	var ws := D.WS
	var big := FastNoiseLite.new()
	big.seed = randi()
	big.frequency = 0.0028
	big.fractal_octaves = 3
	var small := FastNoiseLite.new()
	small.seed = randi()
	small.frequency = 0.02
	var ridge := FastNoiseLite.new()
	ridge.seed = randi()
	ridge.frequency = 0.0016
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	h.resize((N + 1) * (N + 1))
	for i in h.size():
		var x := _vx(i)
		var z := _vz(i)
		var v := big.get_noise_2d(x, z) * relief + small.get_noise_2d(x, z) * relief * 0.08
		if map_key == "alamein":
			v = absf(big.get_noise_2d(x, z)) * relief * 1.3 - relief * 0.3 + small.get_noise_2d(x, z) * 1.5
		# горы за краем игровой зоны
		var out := maxf(maxf(-x, x - ws), maxf(-z, z - ws))
		if out > -150.0:
			var k := smoothstep(-150.0, 450.0, out)
			v += k * (90.0 + (ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 140.0)
		# сглаживаем зоны старта
		if z < 420.0 or z > ws - 420.0:
			var dz := minf(absf(z - 260.0), absf(z - (ws - 260.0)))
			v = lerpf(v, v * 0.25, 1.0 - smoothstep(60.0, 220.0, dz))
		h[i] = v
	# ровные площадки под зонами захвата
	for z in zones:
		var zp: Vector2 = z.pos
		var zr: float = float(z.r) + 110.0
		var target := height(zp.x, zp.y) * 0.4
		var w := _window(Rect2(zp - Vector2(zr, zr), Vector2(zr, zr) * 2))
		for iz in range(w[2], w[3] + 1):
			for ix in range(w[0], w[1] + 1):
				var i := iz * (N + 1) + ix
				var d := Vector2(_vx(i), _vz(i)).distance_to(zp)
				h[i] = lerpf(h[i], target, 1.0 - smoothstep(float(z.r) * 0.9, zr, d))
	# фундаменты построек
	for o in obst:
		var r: Rect2 = o.r
		var c := r.get_center()
		var target := (height(r.position.x, r.position.y) + height(r.end.x, r.end.y) + height(r.position.x, r.end.y) + height(r.end.x, r.position.y)) / 4.0
		var g := r.grow(40.0)
		var w := _window(g)
		for iz in range(w[2], w[3] + 1):
			for ix in range(w[0], w[1] + 1):
				var i := iz * (N + 1) + ix
				var p := Vector2(_vx(i), _vz(i))
				var dx := maxf(0.0, maxf(r.position.x - p.x, p.x - r.end.x))
				var dz := maxf(0.0, maxf(r.position.y - p.y, p.y - r.end.y))
				var k := 1.0 - smoothstep(8.0, 40.0, Vector2(dx, dz).length())
				h[i] = lerpf(h[i], target, k)
		o.base = target
	# воронки
	for cr in craters:
		var cp: Vector2 = Vector2(cr.x, cr.y)
		var rad: float = cr.z
		var w := _window(Rect2(cp - Vector2(rad, rad) * 1.4, Vector2(rad, rad) * 2.8))
		for iz in range(w[2], w[3] + 1):
			for ix in range(w[0], w[1] + 1):
				var i := iz * (N + 1) + ix
				var d := Vector2(_vx(i), _vz(i)).distance_to(cp) / rad
				if d < 1.0:
					h[i] -= rad * 0.22 * (1.0 - d * d)
				elif d < 1.35:
					h[i] += rad * 0.06 * sin((d - 1.0) / 0.35 * PI)
	_paint_mask(map_key, craters, roads)


func _brush(r: int, c: Color) -> Image:
	var s := r * 2 + 1
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - r, y - r).length() / float(r)
			var col := c
			col.a = c.a * (1.0 - smoothstep(0.55, 1.0, d))
			img.set_pixel(x, y, col)
	return img


## Маска для шейдера земли: дороги, пахота, гарь воронок.
func _paint_mask(map_key: String, craters: Array, roads: Array) -> void:
	var S := 1024
	var k := S / SIZE
	mask = Image.create(S, S, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0, 0, 0, 1))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if map_key == "prokhorovka":
		# поля с бороздами
		for f in 14:
			var fx := int((rng.randf() * D.WS - ORIGIN) * k)
			var fz := int((rng.randf() * D.WS - ORIGIN) * k)
			var fw := int((150 + rng.randf() * 260) * k)
			var fh := int((150 + rng.randf() * 260) * k)
			for s in range(0, fw, 3):
				mask.fill_rect(Rect2i(fx + s, fz, 1, fh), Color(0, 0, 0.55, 1))
	var brushes := {}
	for road in roads:
		var w: float = road.w
		var br := maxi(2, int(w * 0.5 * k))
		if not brushes.has(br):
			brushes[br] = _brush(br, Color(1, 0, 0, 0.9))
		var pts: PackedVector2Array = road.pts
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var steps := maxi(1, int(a.distance_to(b) * k / (br * 0.5)))
			for s in steps + 1:
				var p := a.lerp(b, float(s) / steps)
				var px := int((p.x - ORIGIN) * k) - br
				var pz := int((p.y - ORIGIN) * k) - br
				mask.blend_rect(brushes[br], Rect2i(0, 0, br * 2 + 1, br * 2 + 1), Vector2i(px, pz))
	for cr in craters:
		var br := maxi(2, int(float(cr.z) * 1.5 * k))
		var key := "c%d" % br
		if not brushes.has(key):
			brushes[key] = _brush(br, Color(0, 1, 0, 0.85))
		mask.blend_rect(brushes[key], Rect2i(0, 0, br * 2 + 1, br * 2 + 1), Vector2i(int((cr.x - ORIGIN) * k) - br, int((cr.y - ORIGIN) * k) - br))
	mask.generate_mipmaps()
	mask_tex = ImageTexture.create_from_image(mask)


const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D mask_tex : filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 c_g1 : source_color;
uniform vec3 c_g2 : source_color;
uniform vec3 c_rock : source_color;
uniform vec3 c_road : source_color;
uniform vec3 c_dirt : source_color;
uniform vec3 c_scorch : source_color;
uniform float origin;
uniform float size;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
}

void fragment() {
	vec4 m = texture(mask_tex, (wpos.xz - vec2(origin)) / size);
	float n_big = texture(noise_tex, wpos.xz * 0.0011).r;
	float n_mid = texture(noise_tex, wpos.xz * 0.009).r;
	float n_fine = texture(noise_tex, wpos.xz * 0.07).r;
	vec3 c = mix(c_g1, c_g2, smoothstep(0.3, 0.75, n_big * 0.6 + n_mid * 0.4));
	c *= 0.86 + 0.28 * n_fine;
	float slope = 1.0 - wnrm.y;
	c = mix(c, c_rock * (0.8 + 0.4 * n_mid), smoothstep(0.18, 0.38, slope + (n_mid - 0.5) * 0.12));
	c = mix(c, c_dirt * (0.8 + 0.4 * n_fine), m.b * 0.85);
	c = mix(c, c_road * (0.78 + 0.44 * n_fine), smoothstep(0.15, 0.7, m.r));
	c = mix(c, c_scorch * (0.75 + 0.5 * n_fine), smoothstep(0.1, 0.8, m.g) * 0.9);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
"""


## Сетка рельефа с шейдером и коллизия (только в пределах игровой зоны и рядом).
func build(parent: Node3D, map_key: String, shadows: bool) -> void:
	var M: Dictionary = D.MAPS[map_key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(h.size())
	norms.resize(h.size())
	for i in h.size():
		var x := _vx(i)
		var z := _vz(i)
		verts[i] = Vector3(x, h[i], z)
		norms[i] = normal(x, z, CELL)
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var lo := int((-150.0 - ORIGIN) / CELL)
	var hi := int((D.WS + 150.0 - ORIGIN) / CELL)
	for iz in N:
		for ix in N:
			var a := iz * (N + 1) + ix
			var b := a + 1
			var c := a + N + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
			if ix >= lo and ix <= hi and iz >= lo and iz <= hi:
				faces.append_array([verts[a], verts[b], verts[c], verts[b], verts[d], verts[c]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var nimg := noise.get_seamless_image(256, 256)
	nimg.generate_mipmaps()
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("mask_tex", mask_tex)
	mat.set_shader_parameter("noise_tex", ImageTexture.create_from_image(nimg))
	for k in ["g1", "g2", "rock", "road", "dirt", "scorch"]:
		mat.set_shader_parameter("c_" + k, Color(M[k]))
	mat.set_shader_parameter("origin", ORIGIN)
	mat.set_shader_parameter("size", SIZE)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	# коллизия для лучей (снаряды, видимость, камера)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
