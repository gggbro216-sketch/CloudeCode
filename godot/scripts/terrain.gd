extends RefCounted
## Рельеф: карта высот (шум, высоты и овраги карты, горы по краю, площадки под постройки и зоны, воронки),
## быстрая выборка высоты и нормали, сетка с коллизией и шейдер земли.

const D = preload("res://scripts/data.gd")

const ORIGIN := -700.0  # рельеф шире игровой зоны: по краям поднимаются горы
const SIZE := 4260.0  # D.WS + 2 × 700
const N := 213  # шаг сетки — 20 единиц
const CELL := SIZE / N

var h := PackedFloat32Array()
var mask: Image  # R — дорога, G — гарь воронок, B — пахота/грязь
var mask_tex: ImageTexture
var ao_tex: ImageTexture  # затенение у подножия построек, остовов, кустов
var noise_img: Image  # шум шейдера земли — по нему же пятна сырого грунта для физики


func height(x: float, z: float) -> float:
	var fx := clampf((x - ORIGIN) / CELL, 0.0, N - 0.001)
	var fz := clampf((z - ORIGIN) / CELL, 0.0, N - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * (N + 1) + ix
	return lerpf(lerpf(h[i], h[i + 1], tx), lerpf(h[i + N + 1], h[i + N + 2], tx), tz)


## Пятна шейдера земли в точке (та же текстура шума): «damp» — сырые низины, «dry» — выгоревшие
## проплешины. 0–1.
func patch(p: Vector2, kind: String) -> float:
	if noise_img == null:
		return 0.0
	var uv := p * 0.0041 + Vector2(0.6, 0.1) if kind == "damp" else p * 0.0023 + Vector2(0.31, 0.77)
	var w := noise_img.get_width()
	var fx := fposmod(uv.x * w - 0.5, float(w))
	var fz := fposmod(uv.y * w - 0.5, float(w))
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := noise_img.get_pixel(ix, iz).r
	var b := noise_img.get_pixel((ix + 1) % w, iz).r
	var c := noise_img.get_pixel(ix, (iz + 1) % w).r
	var d := noise_img.get_pixel((ix + 1) % w, (iz + 1) % w).r
	var v := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)
	return smoothstep(0.6, 0.85, v) if kind == "damp" else smoothstep(0.55, 0.78, v)


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


## Вклад высот и оврагов карты в точке. Каждая — отрезок a–b с радиусом r и высотой h (h < 0 — овраг):
## ровная вершина до core·r, дальше плавный склон.
static func hills_at(p: Vector2, hills: Array) -> float:
	var v := 0.0
	for hl in hills:
		var r: float = hl.r
		var c := Geometry2D.get_closest_point_to_segment(p, hl.a, hl.b)
		var d := p.distance_to(c)
		if d < r:
			var t := clampf((d / r - float(hl.core)) / (1.0 - float(hl.core)), 0.0, 1.0)
			v += float(hl.h) * (1.0 - t * t * (3.0 - 2.0 * t))
	return v


func generate(map_key: String, zones: Array, obst: Array, craters: Array, roads: Array, ao_points := [], hills := []) -> void:
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
		if not hills.is_empty() and x > -300.0 and z > -300.0 and x < ws + 300.0 and z < ws + 300.0:
			v += hills_at(Vector2(x, z), hills)
		# горы за краем игровой зоны
		var out := maxf(maxf(-x, x - ws), maxf(-z, z - ws))
		if out > -150.0:
			var k := smoothstep(-150.0, 450.0, out)
			v += k * (90.0 + (ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 140.0) * float(M.get("edge", 1.0))
		# сглаживаем зоны старта; переход к холмам длинный, чтобы на краю не вырос уступ,
		# на который не въедет слабосильная машина
		if z < 660.0 or z > ws - 660.0:
			var dz := minf(absf(z - 260.0), absf(z - (ws - 260.0)))
			v = lerpf(v, v * 0.25, 1.0 - smoothstep(60.0, 400.0, dz))
		h[i] = v
	# ровные площадки под зонами захвата; зона на высоте — площадка на её вершине
	for z in zones:
		var zp: Vector2 = z.pos
		var zr: float = float(z.r) + 110.0
		var on_hill := hills_at(zp, hills)
		var target := (height(zp.x, zp.y) - on_hill) * 0.4 + on_hill
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
	_paint_ao(obst, ao_points)


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
	if map_key == "prokhorovka" or map_key == "normandy":
		# поля с бороздами
		for f in 24:
			var fx := int((rng.randf() * D.WS - ORIGIN) * k)
			var fz := int((rng.randf() * D.WS - ORIGIN) * k)
			var fw := int((150 + rng.randf() * 260) * k)
			var fh := int((150 + rng.randf() * 260) * k)
			for s in range(0, fw, 3):
				mask.fill_rect(Rect2i(fx + s, fz, 1, fh), Color(0, 0, 0.55, 1))
	if map_key == "berlin":
		# пыль и битый кирпич в кварталах и на пустырях
		var dust := _brush(int(60 * k), Color(0, 0, 0.8, 0.7))
		for f in 100:
			var px := int((rng.randf() * D.WS - ORIGIN) * k)
			var pz := int((rng.randf() * D.WS - ORIGIN) * k)
			mask.blend_rect(dust, Rect2i(0, 0, dust.get_width(), dust.get_height()), Vector2i(px, pz))
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


## Карта затенения: тёмные ореолы у оснований построек и под кустами (вместо SSAO,
## которого нет в мобильном рендере).
func _paint_ao(obst: Array, points: Array) -> void:
	var S := 512
	var k := S / SIZE
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var brushes := {}
	var stamp := func(x: float, z: float, r: float, strength: float) -> void:
		var br := maxi(2, int(r * k))
		var key := "%d_%d" % [br, int(strength * 10)]
		if not brushes.has(key):
			brushes[key] = _brush(br, Color(0, 0, 0, strength))
		img.blend_rect(brushes[key], Rect2i(0, 0, br * 2 + 1, br * 2 + 1), Vector2i(int((x - ORIGIN) * k) - br, int((z - ORIGIN) * k) - br))
	for o in obst:
		var r: Rect2 = o.r
		var strength := 0.45 if o.solid else 0.25
		var step := 9.0
		var x := r.position.x
		while x <= r.end.x:
			stamp.call(x, r.position.y, 12.0, strength)
			stamp.call(x, r.end.y, 12.0, strength)
			x += step
		var z := r.position.y
		while z <= r.end.y:
			stamp.call(r.position.x, z, 12.0, strength)
			stamp.call(r.end.x, z, 12.0, strength)
			z += step
	for p in points:
		stamp.call(p.x, p.y, p.z, 0.35)
	img.generate_mipmaps()
	ao_tex = ImageTexture.create_from_image(img)


## Детальная текстура грунта (яркость и рельеф) для мелкого масштаба под гусеницами:
## трава, рябь песка, снежные заструги, брусчатка (запечены tools/make_textures.py).
static func _detail(surf: String) -> Array:
	return [load("res://assets/textures/ground_%s.png" % surf), load("res://assets/textures/ground_%s_n.png" % surf)]


const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform sampler2D mask_tex : filter_linear_mipmap;
uniform sampler2D ao_tex : filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 c_g1 : source_color;
uniform vec3 c_g2 : source_color;
uniform vec3 c_rock : source_color;
uniform vec3 c_road : source_color;
uniform vec3 c_dirt : source_color;
uniform vec3 c_scorch : source_color;
uniform float origin;
uniform float size;
uniform float snow = 0.0;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
}

void fragment() {
	vec2 muv = (wpos.xz - vec2(origin)) / size;
	vec4 m = texture(mask_tex, muv);
	float ao = texture(ao_tex, muv).r;
	float n_big = texture(noise_tex, wpos.xz * 0.0011).r;
	float n_mid = texture(noise_tex, wpos.xz * 0.009).r;
	float d1 = texture(detail_tex, wpos.xz * 0.11).r;
	float d2 = texture(detail_tex, wpos.xz * 0.023).r;
	vec3 c = mix(c_g1, c_g2, smoothstep(0.3, 0.75, n_big * 0.6 + n_mid * 0.4));
	// выгоревшие проплешины и тёмные сырые низины
	float dry = smoothstep(0.55, 0.78, texture(noise_tex, wpos.xz * 0.0023 + vec2(0.31, 0.77)).r);
	c = mix(c, c_g2 * vec3(1.1, 1.03, 0.8), dry * 0.45 * (1.0 - snow));
	float damp = smoothstep(0.6, 0.85, texture(noise_tex, wpos.xz * 0.0041 + vec2(0.6, 0.1)).r);
	c = mix(c, c_g1 * 0.82, damp * 0.35);
	c *= 0.68 + 0.55 * d1 * (0.6 + 0.4 * d2);
	float slope = 1.0 - wnrm.y;
	float rock = smoothstep(0.18, 0.38, slope + (n_mid - 0.5) * 0.12);
	c = mix(c, c_rock * (0.75 + 0.5 * d2), rock);
	c = mix(c, c_dirt * (0.7 + 0.5 * d1), m.b * 0.85);
	// дорога: колеи вдоль и утоптанная середина
	float road = smoothstep(0.15, 0.7, m.r);
	c = mix(c, c_road * (0.72 + 0.5 * d1), road);
	c = mix(c, c_scorch * (0.7 + 0.6 * d1), smoothstep(0.1, 0.8, m.g) * 0.9);
	c *= mix(0.55, 1.0, ao);
	// дальние холмы за краем поля: голая земля и камень, выцветшие в дымке
	float hi = smoothstep(35.0, 170.0, wpos.y);
	vec3 bare = mix(c_rock, c_g2, 0.35) * (0.8 + 0.3 * n_mid);
	c = mix(c, mix(bare, vec3(dot(bare, vec3(0.333))), 0.35), hi * 0.75 * (1.0 - snow));
	ALBEDO = c;
	// мелкий рельеф грунта в мировых осях (у сетки рельефа нет касательных)
	vec3 tn = vec3(texture(detail_nrm, wpos.xz * 0.11).xy * 2.0 - 1.0, 0.0);
	tn.xy *= mix(1.0, 0.4, road) * (1.0 - rock * 0.5);
	tn.z = sqrt(max(0.0, 1.0 - dot(tn.xy, tn.xy)));
	vec3 wn = normalize(wnrm);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(tn.x + wn.x, abs(tn.z) * wn.y, tn.y + wn.z)), 0.0)).xyz);
	ROUGHNESS = mix(1.0, 0.55, snow * (1.0 - road));
	SPECULAR = snow * 0.4;
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
	var lo := int((-150.0 - ORIGIN) / CELL)
	var hi := int((D.WS + 150.0 - ORIGIN) / CELL)
	for iz in N:
		for ix in N:
			var a := iz * (N + 1) + ix
			var b := a + 1
			var c := a + N + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
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
	noise_img = nimg.duplicate()
	nimg.generate_mipmaps()
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("mask_tex", mask_tex)
	mat.set_shader_parameter("noise_tex", ImageTexture.create_from_image(nimg))
	mat.set_shader_parameter("ao_tex", ao_tex)
	var det := _detail(M.surf)
	mat.set_shader_parameter("detail_tex", det[0])
	mat.set_shader_parameter("detail_nrm", det[1])
	mat.set_shader_parameter("snow", 1.0 if M.surf == "snow" else 0.0)
	for k in ["g1", "g2", "rock", "road", "dirt", "scorch"]:
		mat.set_shader_parameter("c_" + k, Color(M[k]))
	mat.set_shader_parameter("origin", ORIGIN)
	mat.set_shader_parameter("size", SIZE)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	# коллизия для лучей (снаряды, видимость, камера): сетка высот — луч идёт по клеткам,
	# это в разы дешевле, чем по дереву из треугольников; масштаб общий, поэтому высоты делим на шаг
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var n := hi - lo + 1
	var data := PackedFloat32Array()
	data.resize(n * n)
	for iz in n:
		for ix in n:
			data[iz * n + ix] = h[(lo + iz) * (N + 1) + lo + ix] / CELL
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var mid := ORIGIN + (lo + hi) * 0.5 * CELL
	cs.transform = Transform3D(Basis.from_scale(Vector3(CELL, CELL, CELL)), Vector3(mid, 0.0, mid))
	body.add_child(cs)
	parent.add_child(body)
