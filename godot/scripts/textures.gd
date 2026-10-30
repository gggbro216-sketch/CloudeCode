extends RefCounted
## Текстуры окружения: детальные (кирпич, штукатурка, черепица, бетон, доски, камень, сланец,
## ржавый металл, гарь, мешковина, битый кирпич, листва, грунт, фасады, ящики) запечены заранее
## скриптом tools/make_textures.py вместе с картами нормалей; здесь — общий шейдер построек
## (мировая трипланарная проекция с рельефом, копоть у земли, снег на верхних гранях)
## и мелкие процедурные текстуры: шум, клубы дыма, травинки.

static var _cache := {}

const WORLD_SHADER := """
shader_type spatial;
render_mode diffuse_lambert;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ntex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 scale = vec3(0.05);
uniform vec4 tint : source_color = vec4(1.0);
uniform float snow = 0.0;
uniform float grime = 0.35;
uniform float roughness = 0.92;
uniform float bump = 1.0;
varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// нормаль из карты, сжатой в два канала: z восстанавливается
vec3 _tn(vec2 rg) {
	vec2 xy = (rg * 2.0 - 1.0) * bump;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
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
#ifdef BUMP
	// рельеф кладки по трём проекциям (смешивание «whiteout»), под снегом — гладко
	vec3 tx = _tn(texture(ntex, p.zy).xy);
	vec3 ty = _tn(texture(ntex, p.xz).xy);
	vec3 tz = _tn(texture(ntex, p.xy).xy);
	tx = vec3(tx.xy + wn.zy, abs(tx.z) * wn.x);
	ty = vec3(ty.xy + wn.xz, abs(ty.z) * wn.y);
	tz = vec3(tz.xy + wn.xy, abs(tz.z) * wn.z);
	vec3 bn = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(mix(bn, wn, s)), 0.0)).xyz);
#endif
}
"""

static var bump := true  # рельеф по картам нормалей (выключается в экономном режиме графики)


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


## Запечённая текстура окружения и её карта нормалей (kind + "_n").
static func get_tex(kind: String) -> Texture2D:
	if not _cache.has(kind):
		_cache[kind] = load("res://assets/textures/%s.png" % kind)
	return _cache[kind]


## Материал построек: текстура в мировой проекции; scale — сколько текстур на единицу карты.
static func world_mat(kind: String, scale: Vector3, snow := 0.0, grime := 0.35, tint := Color.WHITE) -> ShaderMaterial:
	var key := "world_shader_b" if bump else "world_shader"
	if not _cache.has(key):
		var sh := Shader.new()
		sh.code = WORLD_SHADER.replace("render_mode diffuse_lambert;", "render_mode diffuse_lambert;\n#define BUMP") if bump else WORLD_SHADER
		_cache[key] = sh
	var m := ShaderMaterial.new()
	m.shader = _cache[key]
	m.set_shader_parameter("tex", get_tex(kind))
	if bump:
		m.set_shader_parameter("ntex", get_tex(kind + "_n"))
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
		var base := Color("566038") if not dry else Color("9c8a56")
		base = base.lightened(rng.randf_range(-0.1, 0.2))
		for i in int(h):
			var t := float(i) / h
			var x := x0 + lean * t * t
			var ww := w * (1.0 - t)
			for dx in range(int(-ww - 1), int(ww + 2)):
				var px := int(x) + dx
				var py := S - 1 - i
				if px >= 0 and px < S and absf(dx) <= ww:
					# к кончикам травинки выгорают в солому
					img.set_pixel(px, py, base.lerp(Color("a69a62"), t * t * 0.5).darkened((1.0 - t) * 0.3))
	var t := _finish(img)
	_cache[key] = t
	return t
