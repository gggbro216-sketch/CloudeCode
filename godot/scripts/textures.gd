extends RefCounted
## Процедурные текстуры окружения (кирпич, штукатурка, черепица, бетон, доски, песчаник,
## ржавый металл, мешковина, гарь, оконные проёмы, нормандский камень, сланец, листва изгородей,
## земляные валы, берлинские фасады) и общий шейдер построек:
## мировая трипланарная проекция, копоть у земли и снег на верхних гранях.

static var _cache := {}

const WORLD_SHADER := """
shader_type spatial;
render_mode diffuse_lambert;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 scale = vec3(0.05);
uniform vec4 tint : source_color = vec4(1.0);
uniform float snow = 0.0;
uniform float grime = 0.35;
uniform float roughness = 0.92;
varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wn), vec3(5.0));
	w /= (w.x + w.y + w.z + 0.0001);
	vec3 p = wpos * scale;
	vec3 c = texture(tex, p.zy).rgb * w.x + texture(tex, p.xz).rgb * w.y + texture(tex, p.xy).rgb * w.z;
	c *= tint.rgb;
	float n = texture(noise, wpos.xz * 0.013 + wpos.y * 0.01).r;
	// копоть и потёки пятнами
	c *= 1.0 - grime * smoothstep(0.35, 0.8, n) * 0.6;
	// снег на верхних гранях и выступах
	float s = snow * smoothstep(0.55, 0.85, wn.y + (n - 0.5) * 0.3);
	c = mix(c, vec3(0.93, 0.95, 0.97), s);
	ALBEDO = c;
	ROUGHNESS = mix(roughness, 0.6, s);
}
"""


static func _noise(seed: int, freq: float, octaves := 3) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


static func _finish(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func noise_texture() -> ImageTexture:
	if not _cache.has("noise"):
		var img := _noise(31, 0.03, 4).get_seamless_image(256, 256)
		_cache["noise"] = _finish(img)
	return _cache["noise"]


static func get_tex(kind: String) -> ImageTexture:
	if _cache.has(kind):
		return _cache[kind]
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var nz := _noise(kind.hash() & 0xffff, 0.05, 4).get_seamless_image(S, S)
	var fine := _noise((kind.hash() >> 8) & 0xffff, 0.3, 2).get_seamless_image(S, S)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	match kind:
		"brick":
			# кирпичная кладка: ряды 16 px, кирпичи 32 px со смещением, светлые швы
			var tints := {}
			for y in S:
				for x in S:
					var row := y / 16
					var off := 16 if row % 2 == 1 else 0
					var col := (x + off) / 32
					var key := row * 64 + col
					if not tints.has(key):
						tints[key] = rng.randf_range(-0.12, 0.12)
					var mortar := (y % 16) < 2 or ((x + off) % 32) < 2
					var c := Color("8a5038").lightened(tints[key])
					if mortar:
						c = Color("9c9384")
					c = c.darkened((fine.get_pixel(x, y).r - 0.5) * 0.3 + (nz.get_pixel(x, y).r - 0.5) * 0.25)
					img.set_pixel(x, y, c)
		"plaster":
			# побелка с пятнами сырости и отвалившимися кусками, под которыми кирпич
			var brick := get_tex("brick").get_image()
			if brick.is_compressed():
				brick.decompress()
			brick.clear_mipmaps()
			for y in S:
				for x in S:
					var v := nz.get_pixel(x, y).r
					var c := Color("d2c8ae").darkened((v - 0.4) * 0.3 + (fine.get_pixel(x, y).r - 0.5) * 0.1)
					if v > 0.8:
						c = brick.get_pixel(x, y)
					elif v > 0.77:
						c = c.darkened(0.2)
					img.set_pixel(x, y, c)
		"roof":
			# черепица: ряды с тенью под нижней кромкой
			for y in S:
				for x in S:
					var ry := float(y % 20) / 20.0
					var tile := (x + (10 if (y / 20) % 2 == 1 else 0)) % 20
					var c := Color("7a4430").lightened(0.15 - ry * 0.3).darkened(0.1 if tile < 2 else 0.0)
					c = c.darkened((nz.get_pixel(x, y).r - 0.5) * 0.35 + (fine.get_pixel(x, y).r - 0.5) * 0.12)
					img.set_pixel(x, y, c)
		"concrete":
			for y in S:
				for x in S:
					var c := Color("8a877e").darkened((nz.get_pixel(x, y).r - 0.5) * 0.35 + (fine.get_pixel(x, y).r - 0.5) * 0.2)
					img.set_pixel(x, y, c)
			# трещины: случайные блуждания
			for k in 6:
				var p := Vector2(rng.randf() * S, rng.randf() * S)
				var a := rng.randf() * TAU
				for i in 90:
					a += rng.randf_range(-0.5, 0.5)
					p += Vector2.from_angle(a)
					img.set_pixel(posmod(int(p.x), S), posmod(int(p.y), S), Color("3a3833"))
			# опалубка: горизонтальные швы
			for y in range(0, S, 64):
				for x in S:
					img.set_pixel(x, y, Color("6a675f"))
		"wood":
			for y in S:
				for x in S:
					var plank := x / 32
					var grain := sin((y * 0.08 + nz.get_pixel(x, y).r * 6.0 + plank * 3.0)) * 0.5 + 0.5
					var c := Color("6a5038").lightened((plank % 3) * 0.05).darkened(grain * 0.2 + (fine.get_pixel(x, y).r - 0.5) * 0.15)
					if x % 32 < 2:
						c = Color("2e241a")
					img.set_pixel(x, y, c)
		"sandstone":
			for y in S:
				for x in S:
					var strata := sin(y * 0.18 + nz.get_pixel(x, y).r * 5.0) * 0.5 + 0.5
					var c := Color("b08c62").darkened(strata * 0.2 + (fine.get_pixel(x, y).r - 0.5) * 0.25)
					img.set_pixel(x, y, c)
		"granite":
			for y in S:
				for x in S:
					var c := Color("85857d").darkened((nz.get_pixel(x, y).r - 0.5) * 0.4 + (fine.get_pixel(x, y).r - 0.5) * 0.35)
					img.set_pixel(x, y, c)
		"rust":
			for y in S:
				for x in S:
					var v := nz.get_pixel(x, y).r
					var c := Color("4a3a30").lerp(Color("7a4426"), smoothstep(0.35, 0.7, v)).darkened((fine.get_pixel(x, y).r - 0.5) * 0.4)
					img.set_pixel(x, y, c)
		"charred":
			for y in S:
				for x in S:
					var v := nz.get_pixel(x, y).r
					var c := Color("1e1c1a").lerp(Color("4a4540"), pow(fine.get_pixel(x, y).r, 3.0) * 0.6 + v * 0.2)
					img.set_pixel(x, y, c)
		"sandbag":
			for y in S:
				for x in S:
					var weave := 0.5 + 0.25 * sin(x * 1.6) * sin(y * 1.6)
					var c := Color("a08a62").darkened((weave - 0.5) * 0.2 + (nz.get_pixel(x, y).r - 0.5) * 0.35)
					img.set_pixel(x, y, c)
		"rubble":
			for y in S:
				for x in S:
					var v := fine.get_pixel(x, y).r
					var c := Color("7d766c") if v > 0.45 else Color("7a5040")
					c = c.darkened((nz.get_pixel(x, y).r - 0.5) * 0.4 + (v - 0.5) * 0.3)
					img.set_pixel(x, y, c)
		"stone":
			# нормандская кладка из известняка: неровные ряды светлых блоков, тёмный раствор
			img.fill(Color("8a8273"))
			var y0 := 0
			while y0 < S:
				var rh := rng.randi_range(20, 30)
				if y0 + rh > S - 12:
					rh = S - y0
				var x0 := -rng.randi_range(0, 30)
				while x0 < S:
					var bw := rng.randi_range(26, 58)
					var c := Color("cbc1a6").darkened(rng.randf_range(-0.08, 0.16)).lerp(Color("b9a988"), rng.randf() * 0.4)
					for y in range(y0 + 2, mini(y0 + rh, S)):
						for x in range(maxi(x0 + 2, 0), mini(x0 + bw, S)):
							img.set_pixel(x, y, c.darkened((fine.get_pixel(x, y).r - 0.5) * 0.25 + (nz.get_pixel(x, y).r - 0.5) * 0.2))
					x0 += bw
				y0 += rh
		"slate":
			# сланцевая кровля: мелкие серо-синие плитки внахлёст
			for y in S:
				for x in S:
					var ry := float(y % 14) / 14.0
					var tile := (x + (8 if (y / 14) % 2 == 1 else 0)) % 16
					var c := Color("525a60").lightened(0.12 - ry * 0.22).darkened(0.12 if tile < 1 else 0.0)
					c = c.darkened((nz.get_pixel(x, y).r - 0.5) * 0.3 + (fine.get_pixel(x, y).r - 0.5) * 0.15)
					img.set_pixel(x, y, c)
		"leaves":
			# листва живой изгороди: тёмная зелень с бликами и тенями
			for y in S:
				for x in S:
					var v := fine.get_pixel(x, y).r
					var c := Color("33502a").lerp(Color("5c7a36"), smoothstep(0.55, 0.8, v)).darkened(smoothstep(0.45, 0.2, v) * 0.35)
					c = c.darkened((nz.get_pixel(x, y).r - 0.5) * 0.3)
					img.set_pixel(x, y, c)
		"earth":
			# земляной вал: суглинок с камешками
			for y in S:
				for x in S:
					var v := fine.get_pixel(x, y).r
					var c := Color("6a5840").darkened((nz.get_pixel(x, y).r - 0.5) * 0.35 + (v - 0.5) * 0.3)
					if v > 0.82:
						c = Color("8d8572")
					img.set_pixel(x, y, c)
		"facade":
			# берлинский доходный дом: серо-охристая штукатурка, высокие окна с наличниками,
			# карнизы между этажами, выбоины от пуль и осколков
			for y in S:
				for x in S:
					var c := Color("989488").darkened((nz.get_pixel(x, y).r - 0.5) * 0.3 + (fine.get_pixel(x, y).r - 0.5) * 0.12)
					img.set_pixel(x, y, c)
			for fy in [0, 128]:
				img.fill_rect(Rect2i(0, fy + 118, S, 6), Color("8b8170"))
				img.fill_rect(Rect2i(0, fy + 116, S, 2), Color("c2b8a4"))
				for wx in [20, 84, 148, 212]:
					img.fill_rect(Rect2i(wx - 5, fy + 10, 34, 6), Color("bfb5a0"))
					img.fill_rect(Rect2i(wx - 3, fy + 16, 30, 82), Color("7f7564"))
					img.fill_rect(Rect2i(wx, fy + 18, 24, 78), Color("141310"))
					img.fill_rect(Rect2i(wx + 11, fy + 18, 2, 78), Color("3a3329"))
					img.fill_rect(Rect2i(wx - 5, fy + 96, 34, 5), Color("bdb39e"))
			for k in 160:
				var p := Vector2i(rng.randi_range(0, S - 4), rng.randi_range(0, S - 4))
				var r := rng.randi_range(1, 3)
				img.fill_rect(Rect2i(p.x, p.y, r, r), Color("5d5547"))
			# копоть над выгоревшими окнами
			for p in [Vector2i(84, 146), Vector2i(212, 146)]:
				for y in 46:
					for x in 30:
						var c := img.get_pixel(p.x + x, p.y - 46 + y)
						img.set_pixel(p.x + x, p.y - 46 + y, c.darkened(float(y) / 46.0 * 0.65))
		"windows":
			img.fill(Color("8a8378"))
			var plaster := get_tex("plaster").get_image()
			if plaster.is_compressed():
				plaster.decompress()
			plaster.clear_mipmaps()
			img.blit_rect(plaster, Rect2i(0, 0, S, S), Vector2i.ZERO)
			for p in [Vector2i(36, 48), Vector2i(148, 48), Vector2i(36, 176), Vector2i(148, 176)]:
				img.fill_rect(Rect2i(p.x - 4, p.y - 4, 76, 72), Color("6d665c"))
				img.fill_rect(Rect2i(p.x, p.y, 68, 64), Color("15140f"))
				img.fill_rect(Rect2i(p.x + 32, p.y, 4, 64), Color("3a3329"))
				img.fill_rect(Rect2i(p.x - 6, p.y + 64, 80, 6), Color("a49c8c"))
			# копоть над окнами (пожары)
			for p in [Vector2i(36, 48), Vector2i(148, 176)]:
				for y in 40:
					for x in 68:
						var c := img.get_pixel(p.x + x, p.y - 40 + y)
						img.set_pixel(p.x + x, p.y - 40 + y, c.darkened(float(y) / 40.0 * 0.6 * (0.6 + 0.4 * fine.get_pixel(x, y).r)))
	var t := _finish(img)
	_cache[kind] = t
	return t


## Материал построек: текстура в мировой проекции; scale — сколько текстур на единицу карты.
static func world_mat(kind: String, scale: Vector3, snow := 0.0, grime := 0.35, tint := Color.WHITE) -> ShaderMaterial:
	if not _cache.has("world_shader"):
		var sh := Shader.new()
		sh.code = WORLD_SHADER
		_cache["world_shader"] = sh
	var m := ShaderMaterial.new()
	m.shader = _cache["world_shader"]
	m.set_shader_parameter("tex", get_tex(kind))
	m.set_shader_parameter("noise", noise_texture())
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("snow", snow)
	m.set_shader_parameter("grime", grime)
	m.set_shader_parameter("tint", tint)
	return m


## Мягкий клуб дыма: радиальный спад, изрезанный шумом (для частиц).
static func puff_texture() -> ImageTexture:
	if _cache.has("puff"):
		return _cache["puff"]
	var S := 128
	var n := _noise(5, 0.06, 4).get_image(S, S)
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var d := Vector2(x - S / 2, y - S / 2).length() / (S / 2.0)
			var v := n.get_pixel(x, y).r
			var a := clampf((1.0 - d) * 1.6 - (1.0 - v) * 0.7, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	var t := _finish(img)
	_cache["puff"] = t
	return t


## Травинки для пучков травы (с прозрачностью).
static func grass_texture(dry: bool) -> ImageTexture:
	var key := "grass_dry" if dry else "grass"
	if _cache.has(key):
		return _cache[key]
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for b in 26:
		var x0 := rng.randf_range(8, S - 8)
		var lean := rng.randf_range(-22, 22)
		var h := rng.randf_range(S * 0.45, S * 0.98)
		var w := rng.randf_range(2.0, 4.5)
		var base := Color("4f6a2a") if not dry else Color("9c8a56")
		base = base.lightened(rng.randf_range(-0.1, 0.2))
		for i in int(h):
			var t := float(i) / h
			var x := x0 + lean * t * t
			var ww := w * (1.0 - t)
			for dx in range(int(-ww - 1), int(ww + 2)):
				var px := int(x) + dx
				var py := S - 1 - i
				if px >= 0 and px < S and absf(dx) <= ww:
					img.set_pixel(px, py, base.lightened(t * 0.25).darkened((1.0 - t) * 0.25))
	var t := _finish(img)
	_cache[key] = t
	return t
