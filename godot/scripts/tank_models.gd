extends RefCounted
## Исторические модели танков по реальным размерам (в метрах, ×UPM в единицы карты).
## Корпус, ходовая и мелкие детали каждого узла сливаются в одну сетку: цвет вершины задаёт
## материал детали (резина, сталь, дерево...), альфа — долю камуфляжной окраски.
## Катки и звёздочки вращаются в вершинном шейдере (UV.x = 1/радиус, UV.y = борт, UV2 = центр).
## Модель смотрит вдоль +X, ось Y — вверх, +Z — правый борт.

const D = preload("res://scripts/data.gd")
const Geo = preload("res://scripts/geo.gd")
const U := D.UPM

# Цвета неокрашенных деталей (альфа 0 — без камуфляжа).
const K := {
	"paint": Color(1, 1, 1, 1), "steel": Color(0.2, 0.2, 0.19, 0), "rubber": Color(0.07, 0.07, 0.065, 0),
	"rust": Color(0.27, 0.17, 0.11, 0), "wood": Color(0.36, 0.27, 0.17, 0), "glass": Color(0.32, 0.36, 0.38, 0),
	"slit": Color(0.03, 0.03, 0.03, 0), "olive": Color(0.25, 0.27, 0.16, 0), "rope": Color(0.3, 0.28, 0.22, 0),
	"white": Color(0.88, 0.88, 0.85, 0),
}

const PAINT_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D camo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grime : filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.03;
uniform vec4 dust_color : source_color = vec4(0.55, 0.5, 0.4, 1.0);
uniform float dust_amount = 0.6;
uniform float ground_y = 0.0;
uniform float tank_h = 20.0;
uniform float burnt = 0.0;
uniform float travel_l = 0.0;
uniform float travel_r = 0.0;
varying vec3 opos;
varying vec3 onrm;
varying float wy;

vec3 tri3(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 0.0001);
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void vertex() {
	// катки и звёздочки крутятся вокруг своих осей, пропорционально пройденному гусеницей пути
	if (UV.x > 0.0) {
		float travel = UV.y > 0.0 ? travel_r : travel_l;
		float a = -travel * UV.x;
		float cs = cos(a);
		float sn = sin(a);
		vec2 p = VERTEX.xy - UV2;
		VERTEX.xy = UV2 + vec2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
		NORMAL.xy = vec2(NORMAL.x * cs - NORMAL.y * sn, NORMAL.x * sn + NORMAL.y * cs);
	}
	opos = VERTEX;
	onrm = NORMAL;
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 camo_c = tri3(camo, opos * tex_scale, onrm);
	float g = tri3(grime, opos * tex_scale * 2.7, onrm).r;
	vec3 c = mix(COLOR.rgb, camo_c, COLOR.a);
	// потёки и выцветание
	c *= 0.84 + 0.3 * g;
	// грязь и пыль снизу корпуса, на гусеничных полках
	float h = clamp((wy - ground_y) / tank_h, 0.0, 1.0);
	float dirt = smoothstep(0.5, 0.06, h + (g - 0.5) * 0.3) * dust_amount;
	dirt += smoothstep(0.7, 1.0, onrm.y) * 0.18 * dust_amount;
	c = mix(c, dust_color.rgb * (0.78 + 0.35 * g), clamp(dirt, 0.0, 0.85));
	// обгоревший корпус
	c = mix(c, vec3(0.06, 0.055, 0.05) * (0.5 + g), burnt);
	ALBEDO = c;
	ROUGHNESS = mix(0.68, 0.95, clamp(dirt + burnt, 0.0, 1.0)) - (1.0 - COLOR.a) * 0.15;
	SPECULAR = 0.3;
}
"""

# Размеры в метрах. hull — боковой профиль корпуса (x от кормы -L/2 до носа +L/2, y вверх).
# th — высота верхней ветви гусеницы; tw — ширина гусеницы; up_w — ширина верхнего корпуса;
# wheels — x катков; wr — радиус катка; spr/idl — звёздочка и ленивец [x, y, r];
# rollers — x поддерживающих роликов; tur_x — центр погона; tpoly — башня сверху; tur_h — высота.
# Необязательные ключи: shelf — надгусеничные полки (по умолчанию есть); hatch — люк заряжающего
# на крыше; cupola: [] — без командирской башенки; bogies — тележки блокированной подвески;
# em_turret — опознавательный знак на башне, а не на корпусе; skirts — год, с которого ставились бортовые экраны (skirt_y — высота их середины); casemate — неподвижная рубка вместо башни
# (tpoly — её контур, орудие качается в лобовом листе).
const SPECS := {
	"t34_76": {
		"L": 5.92, "W": 3.0, "tw": 0.5, "th": 0.92, "up_w": 3.0, "camo": "green", "emblem": "ussr",
		"hull": [[-2.96, 0.62], [-2.68, 1.44], [1.5, 1.5], [2.96, 0.76], [2.8, 0.42], [-2.76, 0.42]],
		"wheels": [1.8, 0.85, -0.12, -1.08, -2.02], "wr": 0.415, "wheel": "spoked",
		"spr": [-2.66, 0.6, 0.36], "idl": [2.54, 0.58, 0.33], "rollers": [],
		"tur_x": 0.85, "tpoly": ["hex", 0.9, 1.22, 0.92], "tur_h": 0.72, "tur_top": 0.78, "smooth": false,
		"mant": "f34", "gun_len": 2.15, "gun_r": [0.075, 0.058], "brake": "none",
		"cupola": [], "hatch": false},
	"t34": {
		"L": 6.1, "W": 3.0, "tw": 0.5, "th": 0.92, "up_w": 3.0, "camo": "green", "emblem": "ussr",
		"hull": [[-3.05, 0.62], [-2.76, 1.44], [1.6, 1.5], [3.05, 0.76], [2.88, 0.42], [-2.85, 0.42]],
		"wheels": [1.85, 0.88, -0.14, -1.12, -2.08], "wr": 0.415, "wheel": "spoked",
		"spr": [-2.74, 0.6, 0.36], "idl": [2.62, 0.58, 0.33], "rollers": [],
		"tur_x": 0.42, "tpoly": ["oval", 1.02, 1.6, 1.08], "tur_h": 0.86, "tur_top": 0.8, "smooth": true,
		"mant": "cast", "gun_len": 4.3, "gun_r": [0.085, 0.064], "brake": "none",
		"cupola": [-0.85, -0.46, 0.3, 0.3]},
	"kv1": {
		"L": 6.75, "W": 3.32, "tw": 0.7, "th": 0.9, "up_w": 2.72, "camo": "green", "emblem": "ussr",
		"hull": [[-3.3, 0.5], [-3.37, 1.2], [-3.05, 1.78], [2.75, 1.78], [3.3, 1.08], [3.37, 0.98], [3.05, 0.42], [-3.0, 0.42]],
		"wheels": [2.38, 1.43, 0.48, -0.47, -1.42, -2.37], "wr": 0.3, "wheel": "single",
		"spr": [-3.05, 0.66, 0.37], "idl": [3.02, 0.62, 0.34], "rollers": [1.9, 0.0, -1.9],
		"tur_x": 0.4, "tpoly": ["oval", 1.05, 1.38, 1.06], "tur_h": 0.9, "tur_top": 0.8, "smooth": true,
		"mant": "kv", "gun_len": 2.2, "gun_r": [0.075, 0.058], "brake": "none",
		"cupola": [], "hatch": false},
	"is2": {
		"L": 6.77, "W": 3.07, "tw": 0.65, "th": 0.86, "up_w": 3.07, "camo": "green", "emblem": "ussr",
		"hull": [[-3.38, 0.6], [-3.2, 1.56], [1.75, 1.62], [3.38, 0.84], [3.12, 0.44], [-3.05, 0.44]],
		"wheels": [2.42, 1.48, 0.54, -0.4, -1.34, -2.28], "wr": 0.28, "wheel": "double",
		"spr": [-3.02, 0.7, 0.34], "idl": [3.02, 0.64, 0.3], "rollers": [1.55, -0.1, -1.75],
		"tur_x": 0.55, "tpoly": ["oval", 1.12, 1.55, 1.2], "tur_h": 0.96, "tur_top": 0.74, "smooth": true,
		"mant": "cast_big", "gun_len": 4.95, "gun_r": [0.11, 0.085], "brake": "double_big",
		"cupola": [-0.78, -0.48, 0.3, 0.32]},
	"sherman": {
		"L": 5.84, "W": 2.62, "tw": 0.42, "th": 0.98, "up_w": 2.62, "camo": "olive", "emblem": "usa",
		"hull": [[-2.92, 0.62], [-2.92, 1.88], [1.45, 1.9], [2.35, 1.2], [2.68, 1.1], [2.92, 0.85], [2.86, 0.52], [2.5, 0.4], [-2.7, 0.55]],
		"wheels": [1.86, 1.26, 0.3, -0.3, -1.26, -1.86], "wr": 0.254, "wheel": "vvss", "bogies": [1.56, 0.0, -1.56],
		"spr": [2.6, 0.8, 0.31], "idl": [-2.62, 0.5, 0.29], "rollers": [1.4, -0.16, -1.72],
		"tur_x": -0.15, "tpoly": ["oval", 0.95, 1.28, 0.88], "tur_h": 0.74, "tur_top": 0.87, "smooth": true,
		"mant": "rotor", "gun_len": 2.3, "gun_r": [0.068, 0.054], "brake": "none",
		"cupola": [], "hatch": false, "shelf": false},
	"firefly": {
		"L": 6.05, "W": 2.62, "tw": 0.42, "th": 0.98, "up_w": 2.62, "camo": "british", "emblem": "usa",
		"hull": [[-3.02, 0.62], [-3.02, 1.88], [1.52, 1.9], [2.44, 1.2], [2.78, 1.1], [3.02, 0.85], [2.96, 0.52], [2.6, 0.4], [-2.8, 0.55]],
		"wheels": [2.0, 1.4, 0.3, -0.3, -1.4, -2.0], "wr": 0.254, "wheel": "vvss", "bogies": [1.7, 0.0, -1.7],
		"spr": [2.7, 0.8, 0.31], "idl": [-2.72, 0.5, 0.29], "rollers": [1.54, -0.16, -1.86],
		"tur_x": -0.15, "tpoly": ["oval", 0.95, 1.28, 0.88], "tur_h": 0.74, "tur_top": 0.87, "smooth": true,
		"mant": "rotor", "gun_len": 3.55, "gun_r": [0.085, 0.06], "brake": "double",
		"cupola": [], "hatch": false, "shelf": false},
	"cromwell": {
		"L": 6.35, "W": 2.91, "tw": 0.36, "th": 1.0, "up_w": 2.7, "camo": "british", "emblem": "usa",
		"hull": [[-3.17, 0.58], [-3.17, 1.52], [2.78, 1.56], [3.12, 1.46], [3.17, 0.98], [3.0, 0.5], [-2.95, 0.5]],
		"wheels": [2.3, 1.2, 0.1, -1.0, -2.1], "wr": 0.41, "wheel": "double",
		"spr": [-2.88, 0.74, 0.36], "idl": [2.86, 0.66, 0.34], "rollers": [],
		"tur_x": 0.35, "tpoly": ["cromwell", 0.92, 0.98, 0.9], "tur_h": 0.72, "tur_top": 0.94, "smooth": false,
		"mant": "box", "gun_len": 2.3, "gun_r": [0.068, 0.054], "brake": "none",
		"cupola": [-0.32, -0.42, 0.3, 0.14], "shelf": false, "em_turret": true},
	"chaffee": {
		"L": 5.03, "W": 2.95, "tw": 0.41, "th": 0.88, "up_w": 2.95, "camo": "olive", "emblem": "usa",
		"hull": [[-2.52, 0.62], [-2.52, 1.58], [0.62, 1.64], [2.52, 0.86], [2.4, 0.5], [-2.32, 0.5]],
		"wheels": [1.62, 0.86, 0.1, -0.66, -1.42], "wr": 0.32, "wheel": "double",
		"spr": [2.2, 0.76, 0.33], "idl": [-2.24, 0.7, 0.3], "rollers": [1.25, -0.05, -1.05],
		"tur_x": 0.32, "tpoly": ["oval", 0.92, 1.08, 0.95], "tur_h": 0.74, "tur_top": 0.8, "smooth": true,
		"mant": "rounded", "gun_len": 2.95, "gun_r": [0.07, 0.056], "brake": "none",
		"cupola": [-0.38, -0.45, 0.26, 0.26]},
	"crusader": {
		"L": 5.97, "W": 2.77, "tw": 0.3, "th": 0.98, "up_w": 2.6, "camo": "desert", "emblem": "uk",
		"hull": [[-2.98, 0.55], [-2.98, 1.36], [1.15, 1.42], [2.65, 1.12], [2.98, 0.92], [2.9, 0.52], [2.6, 0.42], [-2.75, 0.45]],
		"wheels": [2.1, 1.05, 0.0, -1.05, -2.1], "wr": 0.4, "wheel": "double",
		"spr": [-2.72, 0.72, 0.34], "idl": [2.7, 0.62, 0.32], "rollers": [],
		"tur_x": 0.35, "tpoly": ["crusader", 0.9, 1.05, 0.86], "tur_h": 0.6, "tur_top": 0.74, "smooth": false,
		"mant": "6pdr", "gun_len": 2.35, "gun_r": [0.052, 0.04], "brake": "none",
		"cupola": [], "hatch": false, "shelf": false},
	"pz3": {
		"L": 5.52, "W": 2.95, "tw": 0.4, "th": 0.85, "up_w": 2.9, "camo": "german", "emblem": "germany",
		"hull": [[-2.76, 0.55], [-2.78, 1.62], [1.58, 1.64], [1.62, 1.36], [2.5, 1.2], [2.76, 0.92], [2.66, 0.55], [2.36, 0.42], [-2.5, 0.45]],
		"wheels": [1.64, 1.02, 0.3, -0.32, -1.04, -1.66], "wr": 0.26, "wheel": "double",
		"spr": [2.46, 0.72, 0.33], "idl": [-2.52, 0.62, 0.3], "rollers": [1.35, 0.0, -1.3],
		"tur_x": -0.1, "tpoly": ["pz", 0.85, 1.12, 0.86], "tur_h": 0.74, "tur_top": 0.86, "smooth": false,
		"mant": "box_spaced", "gun_len": 2.85, "gun_r": [0.058, 0.045], "brake": "none",
		"cupola": [-0.86, 0.0, 0.3, 0.28], "hatch": false, "skirts": 1943, "skirt_y": 0.83},
	"pz4": {
		"L": 5.89, "W": 2.88, "tw": 0.4, "th": 0.82, "up_w": 2.88, "camo": "german", "emblem": "germany",
		"hull": [[-2.95, 0.5], [-2.95, 1.55], [1.38, 1.6], [1.42, 1.22], [2.42, 1.14], [2.95, 1.0], [2.95, 0.6], [2.7, 0.4], [-2.75, 0.4]],
		"wheels": [1.98, 1.6, 0.84, 0.46, -0.3, -0.68, -1.44, -1.82], "wr": 0.235, "wheel": "double",
		"spr": [2.56, 0.64, 0.34], "idl": [-2.7, 0.56, 0.3], "rollers": [1.6, 0.4, -0.75, -1.9],
		"tur_x": 0.05, "tpoly": ["pz4", 1.0, 1.0, 1.0], "tur_h": 0.82, "tur_top": 0.86, "smooth": false,
		"mant": "box", "gun_len": 3.75, "gun_r": [0.075, 0.06], "brake": "ball",
		"cupola": [-0.98, 0.0, 0.33, 0.3], "skirts": 1943},
	"stug": {
		"L": 5.4, "W": 2.95, "tw": 0.4, "th": 0.85, "up_w": 2.9, "camo": "german", "emblem": "germany",
		"hull": [[-2.7, 0.55], [-2.75, 1.38], [1.8, 1.4], [2.48, 1.2], [2.7, 0.92], [2.62, 0.55], [2.32, 0.42], [-2.45, 0.45]],
		"wheels": [1.64, 1.02, 0.3, -0.32, -1.04, -1.66], "wr": 0.26, "wheel": "double",
		"spr": [2.42, 0.72, 0.33], "idl": [-2.47, 0.62, 0.3], "rollers": [1.35, 0.0, -1.3],
		"tur_x": 0.12, "tpoly": ["stug", 1.1, 1.36, 1.32], "tur_h": 0.66, "tur_top": 0.9, "smooth": false,
		"mant": "saukopf", "gun_len": 2.34, "gun_r": [0.08, 0.06], "brake": "double",
		"cupola": [-0.62, -0.7, 0.28, 0.18], "hatch": false, "skirts": 1943, "skirt_y": 0.83, "casemate": true},
	"panther": {
		"L": 6.87, "W": 3.27, "tw": 0.66, "th": 1.02, "up_w": 3.2, "camo": "german", "emblem": "germany",
		"hull": [[-3.1, 0.52], [-3.32, 1.88], [2.12, 1.88], [3.43, 1.0], [2.98, 0.45], [-2.95, 0.45]],
		"wheels": [2.2, 1.58, 0.96, 0.34, -0.28, -0.9, -1.52, -2.14], "wr": 0.43, "wheel": "interleaved",
		"spr": [2.96, 0.9, 0.42], "idl": [-2.98, 0.84, 0.34], "rollers": [],
		"tur_x": 0.55, "tpoly": ["panther", 1.0, 1.4, 0.95], "tur_h": 0.88, "tur_top": 0.68, "smooth": false,
		"mant": "bell", "gun_len": 3.3, "gun_r": [0.08, 0.055], "brake": "double",
		"cupola": [-0.78, -0.48, 0.33, 0.3], "hatch": false, "skirts": 1944, "skirt_y": 0.86},
	"tiger2": {
		"L": 7.38, "W": 3.75, "tw": 0.8, "th": 1.08, "up_w": 3.62, "camo": "german44", "emblem": "germany",
		"hull": [[-3.55, 0.52], [-3.69, 1.98], [2.6, 2.0], [3.69, 1.18], [3.25, 0.48], [-3.3, 0.48]],
		"wheels": [2.65, 1.97, 1.29, 0.61, -0.07, -0.75, -1.43, -2.11, -2.79], "wr": 0.4, "wheel": "interleaved",
		"spr": [3.32, 0.95, 0.44], "idl": [-3.38, 0.9, 0.38], "rollers": [],
		"tur_x": -0.1, "tpoly": ["panther", 1.15, 1.95, 1.12], "tur_h": 0.95, "tur_top": 0.74, "smooth": false,
		"mant": "saukopf_big", "gun_len": 5.15, "gun_r": [0.1, 0.07], "brake": "double",
		"cupola": [-0.95, -0.56, 0.37, 0.3], "skirts": 1944, "skirt_y": 0.92},
	"tiger": {
		"L": 6.32, "W": 3.56, "tw": 0.725, "th": 0.98, "up_w": 3.42, "camo": "german", "emblem": "germany",
		"hull": [[-3.16, 0.52], [-3.16, 1.76], [2.36, 1.86], [2.36, 1.24], [3.16, 1.12], [3.16, 0.62], [2.92, 0.46], [-2.92, 0.46]],
		"wheels": [2.12, 1.5, 0.88, 0.26, -0.36, -0.98, -1.6, -2.22], "wr": 0.4, "wheel": "interleaved",
		"spr": [2.86, 0.86, 0.42], "idl": [-2.94, 0.84, 0.33], "rollers": [],
		"tur_x": 0.25, "tpoly": ["horseshoe", 0.95, 1.25, 1.12], "tur_h": 0.94, "tur_top": 0.98, "smooth": false,
		"mant": "plate", "gun_len": 4.75, "gun_r": [0.1, 0.075], "brake": "double",
		"cupola": [-0.72, -0.56, 0.37, 0.3]},
}

static var _cache := {}


# ---------- Текстуры ----------

## Камуфляж: однотонный 4БО (СССР), оливковый (США, Великобритания), тёмно-жёлтый с полосами
## (Германия, 1943), «засадный» (1944–1945), «Африканский корпус», пустынный британский,
## зимняя побелка поверх зелёной или серой краски.
static func camo_texture(kind: String) -> ImageTexture:
	var key := "camo_" + kind
	if _cache.has(key):
		return _cache[key]
	var S := 256
	var n1 := FastNoiseLite.new()
	n1.seed = 11
	n1.frequency = 0.011
	n1.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = 37
	n2.frequency = 0.015
	n2.fractal_octaves = 3
	var n3 := FastNoiseLite.new()
	n3.seed = 5
	n3.frequency = 0.25
	var a := n1.get_seamless_image(S, S)
	var b := n2.get_seamless_image(S, S)
	var g := n3.get_seamless_image(S, S)
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var bases := {"olive": "464a2f", "german": "a8956a", "desert": "c4b38a", "german44": "ad9a68", "dak": "9c8358",
		"british": "4f4b34", "grey_winter": "4b5155", "whitewash": "3f4c2b"}
	var base := Color(bases.get(kind, "3f4c2b"))
	for y in S:
		for x in S:
			var va := a.get_pixel(x, y).r
			var vb := b.get_pixel(x, y).r
			var vg := g.get_pixel(x, y).r
			var c := base
			if kind == "german":
				# извилистые полосы оливкового и красно-коричневого, нанесённые пульверизатором
				var s1 := smoothstep(0.075, 0.035, absf(va - 0.5))
				var s2 := smoothstep(0.06, 0.025, absf(vb - 0.44))
				c = c.lerp(Color("4f5935"), s1 * 0.9)
				c = c.lerp(Color("5e3b26"), s2 * 0.85)
			elif kind == "desert":
				# британская пустынная окраска: светлый камень с резкими тёмно-оливковыми пятнами
				c = c.lerp(Color("5c5a40"), smoothstep(0.6, 0.63, va) * 0.9)
				c = c.darkened((vb - 0.5) * 0.12)
			elif kind == "german44":
				# «засадный» камуфляж 1944 г.: крупные пятна оливкового и красно-коричневого
				# по тёмно-жёлтому, на тёмных пятнах — мелкие светлые крапины
				var s1 := smoothstep(0.56, 0.6, va)
				var s2 := smoothstep(0.58, 0.62, vb) * (1.0 - s1)
				c = c.lerp(Color("47522f"), s1 * 0.95)
				c = c.lerp(Color("6a3a24"), s2 * 0.9)
				var dots := smoothstep(0.78, 0.82, vg) * maxf(s1, s2)
				c = c.lerp(Color("b8a470"), dots * 0.9)
			elif kind == "dak":
				# «Африканский корпус»: жёлто-коричневый с серо-зелёными пятнами
				c = c.lerp(Color("6b6a52"), smoothstep(0.62, 0.66, vb) * 0.85)
				c = c.darkened((va - 0.5) * 0.15)
			elif kind == "grey_winter" or kind == "whitewash":
				# зимняя побелка поверх заводской краски: мелом кистью, стёрта местами до металла
				var wash := smoothstep(0.36, 0.52, va * 0.75 + vg * 0.25)
				c = c.darkened((vb - 0.5) * 0.15)
				c = c.lerp(Color("dcdfdc").darkened((vg - 0.5) * 0.12), wash * 0.92)
			else:
				c = c.darkened((va - 0.5) * 0.22)
				c = c.lightened(clampf((vb - 0.7) * 0.6, 0.0, 0.12))
			c = c.lightened((vg - 0.5) * 0.08)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func grime_texture() -> ImageTexture:
	if _cache.has("grime"):
		return _cache["grime"]
	var n := FastNoiseLite.new()
	n.seed = 21
	n.frequency = 0.04
	n.fractal_octaves = 4
	var img := n.get_seamless_image(256, 256)
	# вертикальные потёки
	var out := Image.create(256, 256, false, Image.FORMAT_L8)
	for x in 256:
		var streak := 0.0
		for y in 256:
			var v := img.get_pixel(x, y).r
			streak = maxf(streak * 0.97, v - 0.55)
			out.set_pixel(x, y, Color(clampf(v - streak * 0.8, 0, 1), 0, 0))
	out.generate_mipmaps()
	var t := ImageTexture.create_from_image(out)
	_cache["grime"] = t
	return t


## Траки: звенья с грунтозацепами, проушинами и блестящими от трения гребнями.
static func track_texture() -> ImageTexture:
	if _cache.has("track"):
		return _cache["track"]
	var img := Image.create(64, 32, false, Image.FORMAT_RGB8)
	img.fill(Color("1f1f1c"))
	for x0 in [0, 32]:
		img.fill_rect(Rect2i(x0 + 1, 1, 30, 30), Color("34332e"))
		img.fill_rect(Rect2i(x0 + 4, 2, 6, 28), Color("4d4b43"))
		img.fill_rect(Rect2i(x0 + 5, 2, 2, 28), Color("77736a"))
		img.fill_rect(Rect2i(x0 + 18, 2, 6, 28), Color("4d4b43"))
		img.fill_rect(Rect2i(x0 + 19, 2, 2, 28), Color("77736a"))
		img.fill_rect(Rect2i(x0 + 12, 13, 4, 6), Color("5d5a50"))
		img.fill_rect(Rect2i(x0 + 29, 0, 3, 32), Color("141412"))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["track"] = t
	return t


## Опознавательный знак: красная звезда, белая звезда в круге, балочный крест
## или британская опознавательная полоса.
static func emblem_texture(kind: String) -> ImageTexture:
	var key := "em_" + kind
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if kind == "uk":
		# опознавательная полоса бело-красно-белая, как на британских танках в Африке
		img.fill_rect(Rect2i(28, 38, 24, 52), Color("ece8dc"))
		img.fill_rect(Rect2i(52, 38, 24, 52), Color("a8231b"))
		img.fill_rect(Rect2i(76, 38, 24, 52), Color("ece8dc"))
	elif kind == "germany":
		img.fill_rect(Rect2i(46, 6, 36, 116), Color("ece8dc"))
		img.fill_rect(Rect2i(6, 46, 116, 36), Color("ece8dc"))
		img.fill_rect(Rect2i(53, 13, 22, 102), Color("141414"))
		img.fill_rect(Rect2i(13, 53, 102, 22), Color("141414"))
	else:
		var star := PackedVector2Array()
		for i in 10:
			var r := 60.0 if i % 2 == 0 else 24.0
			var ang := -PI / 2 + TAU * i / 10.0
			star.append(Vector2(64, 67) + Vector2(cos(ang), sin(ang)) * r)
		var col := Color("a8231b") if kind == "ussr" else Color("e8e6dd")
		for y in 128:
			for x in 128:
				var p := Vector2(x + 0.5, y + 0.5)
				if Geometry2D.is_point_in_polygon(p, star):
					img.set_pixel(x, y, col)
				elif kind == "usa":
					var d := (p - Vector2(64, 67)).length()
					if d > 59.0 and d < 64.0:
						img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func _blob() -> GradientTexture2D:
	if _cache.has("blob"):
		return _cache["blob"]
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.65))
	g.set_color(1, Color(0, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	_cache["blob"] = t
	return t


static func paint_material(camo: String) -> ShaderMaterial:
	if not _cache.has("shader"):
		var sh := Shader.new()
		sh.code = PAINT_SHADER
		_cache["shader"] = sh
	var m := ShaderMaterial.new()
	m.shader = _cache["shader"]
	m.set_shader_parameter("camo", camo_texture(camo))
	m.set_shader_parameter("grime", grime_texture())
	return m


# ---------- Построение ----------

## Преобразование: позиция и масштаб в метрах → единицы карты.
static func T3(pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scale * U), pos * U)


class Builder:
	var g := Geo.Group.new()
	var m: Material

	func _init(mat: Material) -> void:
		m = mat
		g.extra = true

	func put(mesh: Mesh, xf: Transform3D, kind := "paint", flat := false) -> void:
		g.add(mesh, xf, m, flat, K[kind], Vector2.ZERO, Vector2.ZERO)

	## Вращающаяся деталь ходовой: центр (x, y) в метрах, радиус, борт.
	func wheel(mesh: Mesh, xf: Transform3D, kind: String, cx: float, cy: float, r: float, side: float) -> void:
		g.add(mesh, xf, m, false, K[kind], Vector2(cx, cy) * U, Vector2(1.0 / (r * U), side))


static func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(p[0], p[1]))
	return out


static func _clip(poly: PackedVector2Array, y0: float, y1: float) -> PackedVector2Array:
	var band := PackedVector2Array([Vector2(-99, y0), Vector2(99, y0), Vector2(99, y1), Vector2(-99, y1)])
	var res := Geometry2D.intersect_polygons(poly, band)
	return res[0] if res.size() > 0 else PackedVector2Array()


static func _turret_poly(spec: Array) -> PackedVector2Array:
	var kind: String = spec[0]
	var f: float = spec[1]
	var b: float = spec[2]
	var hw: float = spec[3]
	match kind:
		"horseshoe":
			var pts := PackedVector2Array([Vector2(f * 0.82, hw)])
			for i in 15:
				var a := PI / 2 + PI * i / 14.0
				pts.append(Vector2(cos(a) * b, sin(a) * hw))
			pts.append(Vector2(f * 0.82, -hw))
			pts.append(Vector2(f, -hw * 0.72))
			pts.append(Vector2(f, hw * 0.72))
			return pts
		"pz4":
			return _pts([[0.88, 0.5], [0.3, 0.86], [-1.18, 0.8], [-1.3, 0.0], [-1.18, -0.8], [0.3, -0.86], [0.88, -0.5]])
		"pz":
			# граненая башня Pz III: лоб с маской, скошенные скулы, корма углом
			return _pts([[f, hw * 0.58], [f * 0.34, hw], [-b * 0.9, hw * 0.93], [-b, 0.0], [-b * 0.9, -hw * 0.93], [f * 0.34, -hw], [f, -hw * 0.58]])
		"crusader":
			# низкая многогранная башня «Крусейдера»
			return _pts([[f, hw * 0.45], [f * 0.6, hw * 0.85], [-b * 0.3, hw], [-b * 0.85, hw * 0.8], [-b, hw * 0.45],
				[-b, -hw * 0.45], [-b * 0.85, -hw * 0.8], [-b * 0.3, -hw], [f * 0.6, -hw * 0.85], [f, -hw * 0.45]])
		"cromwell":
			# коробчатая башня «Кромвеля» с навесными бортовыми листами
			return _pts([[f, hw * 0.82], [f * 0.85, hw], [-b, hw], [-b, -hw], [f * 0.85, -hw], [f, -hw * 0.82]])
		"hex":
			# «гайка» Т-34 обр. 1943: вытянутый шестигранник
			return _pts([[f, hw * 0.5], [f * 0.45, hw], [-b * 0.72, hw], [-b, hw * 0.55], [-b, -hw * 0.55],
				[-b * 0.72, -hw], [f * 0.45, -hw], [f, -hw * 0.5]])
		"panther":
			# башня «Пантеры» сужается ко лбу
			return _pts([[f, hw * 0.66], [-b * 0.86, hw], [-b, hw * 0.84], [-b, -hw * 0.84], [-b * 0.86, -hw], [f, -hw * 0.66]])
		"stug":
			# рубка StuG III со скошенными скулами и бортовыми нишами
			return _pts([[f, hw * 0.62], [f * 0.72, hw], [-b, hw], [-b, -hw], [f * 0.72, -hw], [f, -hw * 0.62]])
	return Geo.oval(f, b, hw, 22)


static func _cyl_x(r1: float, r2: float, l: float, seg := 12) -> Array:
	# цилиндр вдоль оси X (ствол, бочка): сетка и поворот
	return [Geo.cyl(r1, r2, l, seg), Vector3(0, 0, -PI / 2)]


## Строит модель в root. year — год сражения (от него зависят, например, бортовые экраны).
## Возвращает узлы корпуса, башни (у САУ — качающейся установки орудия), орудия, материалы
## и размеры в единицах карты. sup — узел и габариты верхней части для попаданий: башня
## или неподвижная рубка.
static func build(root: Node3D, key: String, shadows: bool, year := 1944, paint_cfg := {}) -> Dictionary:
	var S: Dictionary = SPECS[key]
	var TT := D.spec(key, year)
	var emblem: String = paint_cfg.get("emblem", S.emblem)
	var L: float = S.L
	var W: float = S.W
	var tw: float = S.tw
	var th: float = S.th
	var skirts: bool = S.has("skirts") and year >= int(S.skirts)
	var paint := paint_material(paint_cfg.get("camo", S.camo))
	var hull := Node3D.new()
	root.add_child(hull)
	var hb := Builder.new(paint)

	# --- корпус: низ между гусеницами, верх над гусеницами с наклоном бортов
	var prof := _pts(S.hull)
	var roof := 0.0
	for p in prof:
		roof = maxf(roof, p.y)
	var lower := _clip(prof, -1.0, th + 0.02)
	var upper := _clip(prof, th - 0.04, 9.0)
	var side_k := tan(deg_to_rad(float(TT.side_slope)))
	var up_w: float = S.up_w
	if not lower.is_empty():
		hb.put(Geo.loft(lower, 0.0, W - tw * 2.0 + 0.04, 9.0, W - tw * 2.0 + 0.04), T3(Vector3.ZERO), "paint", true)
	if not upper.is_empty():
		hb.put(Geo.loft(upper, th, up_w, roof, up_w - 2.0 * (roof - th) * side_k), T3(Vector3.ZERO), "paint", true)

	# --- ходовая
	var wr: float = S.wr
	var tz := W / 2 - tw / 2
	var belt_pts := PackedVector2Array()
	var spr: Array = S.spr
	var idl: Array = S.idl
	for s: float in [1.0, -1.0]:
		var z := s * tz
		# катки
		for i in S.wheels.size():
			var x: float = S.wheels[i]
			var cy := wr + 0.04
			match S.wheel:
				"interleaved":
					var zo := s * (tw * 0.22 if i % 2 == 0 else -tw * 0.22)
					_wheel_disc(hb, x, cy, z + zo, wr, tw * 0.3, s, false)
				"spoked":
					_wheel_spoked(hb, x, cy, z, wr, tw * 0.8, s)
				"single":
					_wheel_disc(hb, x, cy, z, wr, tw * 0.72, s, false)
				"vvss":
					_wheel_disc(hb, x, cy, z, wr, tw * 0.5, s, true)
				_:
					_wheel_disc(hb, x, cy, z + s * tw * 0.22, wr, tw * 0.3, s, true)
					_wheel_disc(hb, x, cy, z - s * tw * 0.22, wr, tw * 0.3, s, true)
			if s > 0:
				for k in 10:
					var a := TAU * k / 10.0
					belt_pts.append(Vector2(x + cos(a) * (wr + 0.02), cy + sin(a) * (wr + 0.02)))
		# тележки блокированной подвески: корпус с пружиной, рычаги, ролик сверху
		for bx: float in S.get("bogies", []):
			var by := wr + 0.04
			hb.put(Geo.box(Vector3(0.5, 0.42, tw * 0.3)), T3(Vector3(bx, by + 0.2, z)), "paint", true)
			hb.put(Geo.box(Vector3(0.34, 0.2, tw * 0.36)), T3(Vector3(bx, by + 0.42, z)), "paint", true)
			hb.put(Geo.cyl(0.07, 0.07, 0.3, 8), T3(Vector3(bx, by + 0.15, z)), "steel")
			for d: float in [-1.0, 1.0]:
				hb.put(Geo.box(Vector3(0.36, 0.09, tw * 0.62)), T3(Vector3(bx + d * 0.17, by + 0.04, z), Vector3(0, 0, d * 0.35)), "steel", true)
		# звёздочка (с зубьями) и ленивец
		_sprocket(hb, spr[0], spr[1], z, spr[2], tw * 0.7, s)
		_wheel_disc(hb, idl[0], idl[1], z, idl[2], tw * 0.6, s, false)
		for x in S.rollers:
			var ry := th - 0.12
			hb.wheel(Geo.cyl(0.11, 0.11, tw * 0.5, 10), T3(Vector3(x, ry, z), Vector3(PI / 2, 0, 0)), "rubber", x, ry, 0.11, s)
			if s > 0:
				belt_pts.append(Vector2(x, ry + 0.12))
		# надгусеничная полка
		if S.get("shelf", true):
			hb.put(Geo.box(Vector3(L * 0.97, 0.03, tw + 0.08)), T3(Vector3(0, th + 0.05, s * (tz + 0.02))), "paint", true)
	for a in [spr, idl]:
		for k in 12:
			var ang := TAU * k / 12.0
			belt_pts.append(Vector2(a[0] + cos(ang) * (a[2] + 0.03), a[1] + sin(ang) * (a[2] + 0.03)))
	var outline := Geometry2D.convex_hull(belt_pts)
	if outline.size() > 1 and outline[0] == outline[outline.size() - 1]:
		outline.remove_at(outline.size() - 1)
	var scaled := PackedVector2Array()
	for p in outline:
		scaled.append(p * U)
	var trk_l := _track_mat()
	var trk_r := _track_mat()
	var tg := Geo.Group.new()
	tg.add(Geo.belt(scaled, tw * U, 0.09 * U, 0.24 * U), Transform3D(Basis.IDENTITY, Vector3(0, 0, tz * U)), trk_r)
	tg.add(Geo.belt(scaled, tw * U, 0.09 * U, 0.24 * U), Transform3D(Basis.IDENTITY, Vector3(0, 0, -tz * U)), trk_l)
	tg.commit(hull, shadows)

	# --- детали корпуса
	_hull_details(hb, key, S, roof, skirts, year)
	hb.g.commit(hull, shadows)

	# опознавательные знаки на бортах корпуса (Германия, США): на экранах, если они есть,
	# иначе на борту, повторяя его наклон
	var em_turret: bool = emblem == "ussr" or S.get("em_turret", false)
	if not em_turret:
		var ey := th + (roof - th) * 0.5
		var ez := up_w / 2 - (ey - th) * side_k + 0.02
		var tilt := atan(side_k)
		if skirts:
			ey = S.get("skirt_y", 1.0)
			ez = W / 2 + 0.24
			tilt = 0.0
		_emblems(hull, emblem, Vector3(-L * 0.08, ey, ez), 0.7, tilt)

	# пятно тени под танком
	var blob := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(L * 1.25, W * 1.35) * U
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_texture = _blob()
	bm.disable_receive_shadows = true
	blob.mesh = bq
	blob.material_override = bm
	blob.rotation = Vector3(-PI / 2, 0, 0)
	blob.position.y = 0.05 * U
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hull.add_child(blob)

	# --- башня или рубка
	var casemate: bool = S.get("casemate", false)
	var tpoly := _turret_poly(S.tpoly)
	var tur_h: float = S.tur_h
	var front: float = S.tpoly[1]
	var hw: float = S.tpoly[3]
	var gun_y := tur_h * (0.42 if casemate else 0.46)
	var top := Node3D.new()  # верх: вращается (башня) или неподвижен (рубка)
	top.position = Vector3(float(S.tur_x), roof - 0.02, 0) * U
	hull.add_child(top)
	var tb := Builder.new(paint)
	tb.put(Geo.frustum(tpoly, tur_h, S.tur_top, 0.0, S.smooth), T3(Vector3.ZERO), "paint", not S.smooth)
	_turret_details(tb, key, S, front, tur_h, skirts, year)
	if paint_cfg.get("band", false) and not S.get("casemate", false):
		# Берлин, 1945: белая полоса вокруг башни и белый крест на крыше — опознавание с воздуха
		var yb := tur_h * 0.5
		var k0 := 1.0 + (float(S.tur_top) - 1.0) * yb / tur_h
		var k1 := 1.0 + (float(S.tur_top) - 1.0) * (yb + 0.13) / tur_h
		var band := PackedVector2Array()
		for p in tpoly:
			band.append(p * k0 * 1.012)
		tb.put(Geo.frustum(band, 0.13, k1 / k0, 0.0, S.smooth), T3(Vector3(0, yb, 0)), "white", not S.smooth)
		var rw := hw * float(S.tur_top) * 0.75
		tb.put(Geo.box(Vector3(rw * 2.0, 0.02, 0.16)), T3(Vector3(-0.15, tur_h + 0.012, 0)), "white", true)
		tb.put(Geo.box(Vector3(0.16, 0.02, rw * 2.0)), T3(Vector3(-0.15, tur_h + 0.012, 0)), "white", true)
	var tur := top
	var trunnion := Vector3(front * 0.9, gun_y, 0)
	if casemate:
		# рубка на корпусе, а маска с орудием качается в амбразуре лобового листа
		tb.g.commit(top, shadows)
		tur = Node3D.new()
		tur.position = top.position + Vector3(front * float(S.tur_top) * 0.98, gun_y, 0) * U
		hull.add_child(tur)
		var mb := Builder.new(paint)
		_mantlet(mb, S, 0.0, 0.0)
		mb.g.commit(tur, shadows)
		trunnion = Vector3(0.05, 0, 0)
	else:
		_mantlet(tb, S, front, gun_y)
		tb.g.commit(top, shadows)
	if em_turret:
		var tilt := atan2(hw * (1.0 - float(S.tur_top)), tur_h)
		_emblems(top, emblem, Vector3(-0.2, tur_h * 0.5, hw * (1.0 + float(S.tur_top)) / 2.0 + 0.06), 0.55, tilt)

	# --- орудие на оси возвышения
	var gun := Node3D.new()
	gun.position = trunnion * U
	tur.add_child(gun)
	var gb := Builder.new(paint)
	var glen: float = S.gun_len
	var gr: Array = S.gun_r
	var c := _cyl_x(gr[1], gr[0], glen, 14)
	gb.put(c[0], T3(Vector3(glen / 2, 0, 0), c[1]), "paint")
	match S.brake:
		"double", "double_big":
			var big := 1.25 if S.brake == "double_big" else 1.0
			var r: float = float(gr[1]) * 1.9 * big
			var bl := 0.5 * big
			var cb := _cyl_x(r, r, bl, 14)
			gb.put(cb[0], T3(Vector3(glen + bl / 2 - 0.05, 0, 0), cb[1]), "paint")
			gb.put(Geo.box(Vector3(0.1, r * 1.6, r * 2.9)), T3(Vector3(glen + 0.06, 0, 0)), "paint", true)
			gb.put(Geo.box(Vector3(0.1, r * 1.6, r * 2.9)), T3(Vector3(glen + bl - 0.1, 0, 0)), "paint", true)
			gb.put(Geo.box(Vector3(bl * 0.7, r * 1.0, r * 2.95)), T3(Vector3(glen + bl / 2, 0, 0)), "slit", true)
		"ball":
			gb.put(Geo.sphere(14, 8), T3(Vector3(glen + 0.12, 0, 0), Vector3.ZERO, Vector3(0.42, float(gr[1]) * 3.2, float(gr[1]) * 3.2)), "paint")
			gb.put(Geo.box(Vector3(0.16, float(gr[1]) * 2.2, float(gr[1]) * 3.4)), T3(Vector3(glen + 0.12, 0, 0)), "slit", true)
		_:
			var cm := _cyl_x(float(gr[1]) * 1.25, float(gr[1]) * 1.25, 0.18, 14)
			gb.put(cm[0], T3(Vector3(glen - 0.09, 0, 0), cm[1]), "paint")
	# дульный срез
	var hole := _cyl_x(float(gr[1]) * 0.55, float(gr[1]) * 0.55, 0.02, 10)
	var tip := glen + (0.5 if S.brake.begins_with("double") else 0.0)
	gb.put(hole[0], T3(Vector3(tip + 0.005, 0, 0), hole[1]), "slit")
	gb.g.commit(gun, shadows)

	var back: float = S.tpoly[2]
	return {"hull": hull, "tur": tur, "gun": gun, "barrel": tip * U, "paint": paint, "tracks": [trk_l, trk_r],
		"hh": roof * U, "tur_h": tur_h * U, "tz": hw * U, "tur_f": front * U,
		"tur_b": back * U, "height": (roof + tur_h + 0.3) * U, "th": th * U,
		"sup": top, "sup_min": Vector3(-back, 0, -hw) * U, "sup_max": Vector3(front, tur_h, hw) * U}


static func _track_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = track_texture()
	m.roughness = 0.75
	m.metallic = 0.45
	return m


## Каток со сплошным диском: резиновый бандаж, окрашенный диск, ступица и болты.
static func _wheel_disc(b: Builder, x: float, y: float, z: float, r: float, w: float, s: float, rubber: bool) -> void:
	var rot := Vector3(PI / 2, 0, 0)
	b.wheel(Geo.cyl(r, r, w, 18), T3(Vector3(x, y, z), rot), "rubber" if rubber else "paint", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.82, r * 0.86, w * 1.08, 18), T3(Vector3(x, y, z), rot), "paint", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.3, r * 0.34, w * 1.25, 12), T3(Vector3(x, y, z), rot), "steel", x, y, r, s)
	for k in 6:
		var a := TAU * k / 6.0
		var bx := x + cos(a) * r * 0.5
		var by := y + sin(a) * r * 0.5
		b.wheel(Geo.cyl(r * 0.06, r * 0.06, w * 1.16, 6), T3(Vector3(bx, by, z), rot), "steel", x, y, r, s)


## Каток Т-34: большой, с резиновым бандажом и облегчающими отверстиями-спицами.
static func _wheel_spoked(b: Builder, x: float, y: float, z: float, r: float, w: float, s: float) -> void:
	var rot := Vector3(PI / 2, 0, 0)
	b.wheel(Geo.cyl(r, r, w, 22), T3(Vector3(x, y, z), rot), "rubber", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.84, r * 0.84, w * 1.06, 22), T3(Vector3(x, y, z), rot), "paint", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.26, r * 0.3, w * 1.2, 12), T3(Vector3(x, y, z), rot), "steel", x, y, r, s)
	for k in 8:
		var a := TAU * k / 8.0
		b.wheel(Geo.cyl(r * 0.13, r * 0.13, w * 1.12, 8), T3(Vector3(x + cos(a) * r * 0.56, y + sin(a) * r * 0.56, z), rot), "slit", x, y, r, s)


## Ведущая звёздочка с зубьями.
static func _sprocket(b: Builder, x: float, y: float, z: float, r: float, w: float, s: float) -> void:
	var rot := Vector3(PI / 2, 0, 0)
	b.wheel(Geo.cyl(r * 0.85, r * 0.85, w, 16), T3(Vector3(x, y, z), rot), "paint", x, y, r, s)
	b.wheel(Geo.cyl(r * 0.35, r * 0.4, w * 1.3, 10), T3(Vector3(x, y, z), rot), "steel", x, y, r, s)
	for k in 12:
		var a := TAU * k / 12.0
		var tp := Vector3(x + cos(a) * r * 0.92, y + sin(a) * r * 0.92, z)
		b.wheel(Geo.box(Vector3(0.09, 0.07, w * 0.9)), T3(tp, Vector3(0, 0, a)), "steel", x, y, r, s)


## Точка на линии профиля между двумя вершинами (для деталей на наклонных листах).
static func _on_edge(prof: Array, i: int, t: float) -> Array:
	var a := Vector2(prof[i][0], prof[i][1])
	var b := Vector2(prof[i + 1][0], prof[i + 1][1])
	var p := a.lerp(b, t)
	return [p, atan2(b.y - a.y, b.x - a.x)]


static func _hull_details(b: Builder, key: String, S: Dictionary, roof: float, skirts: bool, year: int) -> void:
	var L: float = S.L
	var W: float = S.W
	var up_w: float = S.up_w
	var th: float = S.th
	var prof: Array = S.hull
	var side_k := tan(deg_to_rad(float(D.spec(key, year).side_slope)))
	match key:
		"t34", "t34_76":
			# люк механика-водителя и шаровая установка пулемёта на лобовом листе
			var e := _on_edge(prof, 2, 0.45)
			var p: Vector2 = e[0]
			b.put(Geo.box(Vector3(0.5, 0.08, 0.6)), T3(Vector3(p.x, p.y + 0.03, -0.55), Vector3(0, 0, e[1])), "paint", true)
			b.put(Geo.box(Vector3(0.12, 0.03, 0.3)), T3(Vector3(p.x + 0.1, p.y + 0.06, -0.55), Vector3(0, 0, e[1])), "slit", true)
			var e2 := _on_edge(prof, 2, 0.5)
			var p2: Vector2 = e2[0]
			b.put(Geo.sphere(12, 8), T3(Vector3(p2.x, p2.y, 0.62), Vector3.ZERO, Vector3(0.32, 0.32, 0.32)), "paint")
			var mg := _cyl_x(0.025, 0.025, 0.4, 6)
			b.put(mg[0], T3(Vector3(p2.x + 0.25, p2.y - 0.1, 0.62), mg[1] + Vector3(0, 0, -0.3)), "steel")
			# фара, буксирные крюки
			b.put(Geo.cyl(0.09, 0.09, 0.14, 10), T3(Vector3(2.55, 1.0, -1.15), Vector3(0, 0, -PI / 2)), "glass")
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(0.18, 0.1, 0.08)), T3(Vector3(3.08, 0.55, s * 0.9)), "steel", true)
			# бочки с топливом на корме и выхлопные трубы
			for s: float in [1.0, -1.0]:
				var drum := _cyl_x(0.3, 0.3, 0.95, 14)
				b.put(drum[0], T3(Vector3(-2.15, 1.38, s * 1.22), drum[1]), "paint")
				b.put(Geo.box(Vector3(0.04, 0.68, 0.04)), T3(Vector3(-1.75, 1.38, s * 1.22)), "steel", true)
				b.put(Geo.box(Vector3(0.04, 0.68, 0.04)), T3(Vector3(-2.55, 1.38, s * 1.22)), "steel", true)
				var ex := _cyl_x(0.09, 0.09, 0.3, 8)
				b.put(ex[0], T3(Vector3(-3.05, 0.95, s * 0.55), ex[1]), "rust")
			# запасные траки на лобовом листе
			for k in 3:
				var ek := _on_edge(prof, 2, 0.72 + k * 0.08)
				var pk: Vector2 = ek[0]
				b.put(Geo.box(Vector3(0.2, 0.05, 0.5)), T3(Vector3(pk.x, pk.y + 0.03, 0.55), Vector3(0, 0, ek[1])), "steel", true)
			# решётки моторного отделения
			b.put(Geo.box(Vector3(1.1, 0.04, 1.2)), T3(Vector3(-1.9, 1.47, 0)), "slit", true)
			for k in 6:
				b.put(Geo.box(Vector3(1.1, 0.05, 0.06)), T3(Vector3(-1.9, 1.49, -0.5 + k * 0.2)), "paint", true)
		"tiger":
			# смотровой прибор механика и курсовой пулемёт на вертикальном лобовом листе
			b.put(Geo.box(Vector3(0.14, 0.18, 0.55)), T3(Vector3(2.4, 1.6, -0.75)), "paint", true)
			b.put(Geo.box(Vector3(0.05, 0.05, 0.4)), T3(Vector3(2.48, 1.6, -0.75)), "slit", true)
			b.put(Geo.sphere(12, 8), T3(Vector3(2.38, 1.55, 0.78), Vector3.ZERO, Vector3(0.3, 0.3, 0.3)), "paint")
			var mg := _cyl_x(0.025, 0.025, 0.35, 6)
			b.put(mg[0], T3(Vector3(2.6, 1.55, 0.78), mg[1]), "steel")
			# фары «Бош», передние крылья, буксирные тросы вдоль бортов
			for s: float in [1.0, -1.0]:
				b.put(Geo.cyl(0.1, 0.12, 0.2, 10), T3(Vector3(2.3, 1.95, s * 1.45), Vector3(0, 0, -PI / 2)), "paint")
				b.put(Geo.box(Vector3(0.55, 0.03, 0.72)), T3(Vector3(3.3, 1.07, s * (1.78 - 0.36)), Vector3(0, 0, -0.25)), "paint", true)
				var rope := _cyl_x(0.03, 0.03, 4.2, 6)
				b.put(rope[0], T3(Vector3(-0.3, 1.45, s * 1.73), rope[1]), "rope")
				# выхлопные трубы с кожухами
				b.put(Geo.cyl(0.08, 0.08, 0.75, 10), T3(Vector3(-3.25, 1.75, s * 0.45)), "rust")
				b.put(Geo.cyl(0.13, 0.13, 0.5, 10), T3(Vector3(-3.25, 1.62, s * 0.45)), "paint")
				# воздухозаборники на корме
				b.put(Geo.cyl(0.32, 0.32, 0.06, 14), T3(Vector3(-2.2, 1.78, s * 0.9)), "paint")
			# решётки моторного отделения и инструмент
			b.put(Geo.box(Vector3(1.2, 0.04, 1.0)), T3(Vector3(-2.2, 1.79, 0)), "slit", true)
			b.put(Geo.box(Vector3(1.6, 0.06, 0.12)), T3(Vector3(-0.5, 1.88, 1.4)), "wood", true)
			b.put(Geo.box(Vector3(1.2, 0.06, 0.1)), T3(Vector3(-0.4, 1.88, -1.45)), "wood", true)
		"is2":
			var e := _on_edge(prof, 2, 0.4)
			var p: Vector2 = e[0]
			b.put(Geo.box(Vector3(0.45, 0.1, 0.55)), T3(Vector3(p.x, p.y + 0.04, 0), Vector3(0, 0, e[1])), "paint", true)
			b.put(Geo.box(Vector3(0.1, 0.03, 0.3)), T3(Vector3(p.x + 0.1, p.y + 0.08, 0), Vector3(0, 0, e[1])), "slit", true)
			b.put(Geo.cyl(0.09, 0.09, 0.14, 10), T3(Vector3(2.8, 1.2, -1.15), Vector3(0, 0, -PI / 2)), "glass")
			for s: float in [1.0, -1.0]:
				# наружные топливные баки на кормовых полках
				b.put(Geo.box(Vector3(1.15, 0.45, 0.42)), T3(Vector3(-1.9, th_top(S) + 0.25, s * (up_w / 2 - 0.22))), "paint", true)
				b.put(Geo.box(Vector3(1.0, 0.47, 0.06)), T3(Vector3(-1.9, th_top(S) + 0.25, s * (up_w / 2 - 0.05))), "steel", true)
				var ex := _cyl_x(0.1, 0.1, 0.3, 8)
				b.put(ex[0], T3(Vector3(-3.3, 1.1, s * 0.6), ex[1]), "rust")
				var rope := _cyl_x(0.03, 0.03, 3.6, 6)
				b.put(rope[0], T3(Vector3(0.2, 1.52, s * 1.5), rope[1]), "rope")
			for k in 3:
				var ek := _on_edge(prof, 2, 0.62 + k * 0.1)
				var pk: Vector2 = ek[0]
				b.put(Geo.box(Vector3(0.18, 0.05, 0.6)), T3(Vector3(pk.x, pk.y + 0.03, 0.9), Vector3(0, 0, ek[1])), "steel", true)
			b.put(Geo.box(Vector3(1.4, 0.04, 1.4)), T3(Vector3(-2.2, 1.6, 0)), "slit", true)
			for k in 7:
				b.put(Geo.box(Vector3(1.4, 0.05, 0.07)), T3(Vector3(-2.2, 1.62, -0.6 + k * 0.2)), "paint", true)
		"pz4":
			# смотровой прибор механика, курсовой пулемёт
			b.put(Geo.box(Vector3(0.12, 0.16, 0.42)), T3(Vector3(1.42, 1.45, -0.62)), "paint", true)
			b.put(Geo.box(Vector3(0.04, 0.04, 0.32)), T3(Vector3(1.48, 1.45, -0.62)), "slit", true)
			b.put(Geo.sphere(12, 8), T3(Vector3(1.42, 1.4, 0.55), Vector3.ZERO, Vector3(0.26, 0.26, 0.26)), "paint")
			# запасные катки на лобовом листе и траки на носу
			for s: float in [1.0, -1.0]:
				b.put(Geo.cyl(0.235, 0.235, 0.1, 16), T3(Vector3(2.62, 1.12, s * 0.8), Vector3(0, 0, -0.25)), "rubber")
				b.put(Geo.cyl(0.19, 0.19, 0.12, 16), T3(Vector3(2.63, 1.13, s * 0.8), Vector3(0, 0, -0.25)), "paint")
				b.put(Geo.cyl(0.07, 0.07, 0.6, 8), T3(Vector3(-3.0, 0.95, s * 0.5), Vector3(0, 0, PI / 2)), "rust")
			for k in 5:
				b.put(Geo.box(Vector3(0.05, 0.13, 0.36)), T3(Vector3(2.98, 0.68 + k * 0.08, -0.6 + (k % 2) * 0.05)), "steel", true)
				b.put(Geo.box(Vector3(0.05, 0.13, 0.36)), T3(Vector3(2.98, 0.68 + k * 0.08, 0.6 - (k % 2) * 0.05)), "steel", true)
			# бортовые экраны «шюрцен» на кронштейнах (с весны 1943 г.)
			if skirts:
				_skirts(b, W, -2.15, 5, 0.98, 1.48)
			b.put(Geo.box(Vector3(1.0, 0.04, 1.1)), T3(Vector3(-2.2, 1.57, 0)), "slit", true)
		"chaffee":
			for s: float in [1.0, -1.0]:
				b.put(Geo.cyl(0.08, 0.08, 0.12, 10), T3(Vector3(2.3, 1.02, s * 1.1), Vector3(0, 0, -PI / 2 - 0.5)), "glass")
				b.put(Geo.box(Vector3(0.9, 0.35, 0.3)), T3(Vector3(-1.3, 1.08, s * (W / 2 - 0.15))), "paint", true)
				var muf := _cyl_x(0.11, 0.11, 0.6, 10)
				b.put(muf[0], T3(Vector3(-2.65, 0.95, s * 0.6), muf[1] + Vector3(PI / 2, 0, 0)), "rust")
			var e := _on_edge(prof, 2, 0.3)
			var p: Vector2 = e[0]
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(0.5, 0.06, 0.5)), T3(Vector3(p.x, p.y + 0.03, s * 0.55), Vector3(0, 0, e[1])), "paint", true)
			# большие решётки моторного отделения
			b.put(Geo.box(Vector3(1.6, 0.04, 1.6)), T3(Vector3(-1.6, 1.6, 0)), "slit", true)
			for k in 9:
				b.put(Geo.box(Vector3(1.6, 0.05, 0.06)), T3(Vector3(-1.6, 1.62, -0.75 + k * 0.19)), "paint", true)

		"kv1":
			# смотровой прибор механика-водителя и курсовой пулемёт на верхнем лобовом листе
			var e := _on_edge(prof, 3, 0.35)
			var p: Vector2 = e[0]
			b.put(Geo.box(Vector3(0.3, 0.12, 0.5)), T3(Vector3(p.x, p.y + 0.04, -0.45), Vector3(0, 0, e[1])), "paint", true)
			b.put(Geo.box(Vector3(0.05, 0.04, 0.3)), T3(Vector3(p.x + 0.07, p.y + 0.1, -0.45), Vector3(0, 0, e[1])), "slit", true)
			var e2 := _on_edge(prof, 3, 0.5)
			var p2: Vector2 = e2[0]
			b.put(Geo.sphere(12, 8), T3(Vector3(p2.x, p2.y, 0.55), Vector3.ZERO, Vector3(0.3, 0.3, 0.3)), "paint")
			var mg := _cyl_x(0.025, 0.025, 0.4, 6)
			b.put(mg[0], T3(Vector3(p2.x + 0.25, p2.y - 0.08, 0.55), mg[1] + Vector3(0, 0, -0.3)), "steel")
			b.put(Geo.cyl(0.1, 0.1, 0.15, 10), T3(Vector3(2.95, 1.6, -1.0), Vector3(0, 0, -PI / 2)), "glass")
			for s: float in [1.0, -1.0]:
				# буксирные крюки спереди и сзади
				b.put(Geo.box(Vector3(0.18, 0.1, 0.1)), T3(Vector3(3.42, 0.7, s * 0.95)), "steel", true)
				b.put(Geo.box(Vector3(0.18, 0.1, 0.1)), T3(Vector3(-3.42, 0.7, s * 0.95)), "steel", true)
				# ящики ЗИП на надгусеничных полках
				b.put(Geo.box(Vector3(1.0, 0.36, 0.38)), T3(Vector3(0.9, th + 0.25, s * (up_w / 2 + 0.2))), "paint", true)
				b.put(Geo.box(Vector3(0.7, 0.3, 0.38)), T3(Vector3(-1.6, th + 0.22, s * (up_w / 2 + 0.2))), "paint", true)
				# выхлопные трубы на кормовом листе
				var ex := _cyl_x(0.09, 0.09, 0.35, 8)
				b.put(ex[0], T3(Vector3(-3.3, 1.45, s * 0.55), ex[1] + Vector3(0, 0, 0.5)), "rust")
				# буксирный трос вдоль борта
				var rope := _cyl_x(0.03, 0.03, 3.4, 6)
				b.put(rope[0], T3(Vector3(-0.4, 1.45, s * (up_w / 2 + 0.03)), rope[1]), "rope")
			# запасные траки на нижнем лобовом листе
			for k in 3:
				var ek := _on_edge(prof, 5, 0.25 + k * 0.22)
				var pk: Vector2 = ek[0]
				b.put(Geo.box(Vector3(0.06, 0.16, 0.6)), T3(Vector3(pk.x + 0.03, pk.y, 0.75), Vector3(0, 0, ek[1] + PI / 2)), "steel", true)
			# жалюзи моторного отделения
			b.put(Geo.box(Vector3(1.4, 0.04, 1.3)), T3(Vector3(-2.1, 1.79, 0)), "slit", true)
			for k in 7:
				b.put(Geo.box(Vector3(1.4, 0.05, 0.07)), T3(Vector3(-2.1, 1.81, -0.57 + k * 0.19)), "paint", true)
		"sherman", "firefly":
			var fx := 0.1 if key == "firefly" else 0.0
			for s: float in [1.0, -1.0]:
				# люки механика и помощника на крыше перед башней, перископы
				if key == "sherman" or s < 0:
					b.put(Geo.box(Vector3(0.5, 0.05, 0.48)), T3(Vector3(1.1 + fx, 1.92, s * 0.52)), "paint", true)
					b.put(Geo.box(Vector3(0.1, 0.1, 0.16)), T3(Vector3(1.28 + fx, 1.98, s * 0.52)), "paint", true)
				# фары с защитными решётками у верхних углов лобового листа
				var e := _on_edge(prof, 2, 0.62)
				var p: Vector2 = e[0]
				b.put(Geo.cyl(0.07, 0.08, 0.12, 10), T3(Vector3(p.x + 0.04, p.y + 0.1, s * 1.0), Vector3(0, 0, -PI / 2 - 0.3)), "glass")
				b.put(Geo.box(Vector3(0.04, 0.22, 0.24)), T3(Vector3(p.x + 0.15, p.y + 0.12, s * 1.0)), "steel", true)
				# буксирные проушины
				b.put(Geo.box(Vector3(0.14, 0.12, 0.08)), T3(Vector3(2.95 + fx, 0.66, s * 0.72)), "steel", true)
				# воздухоочистители на кормовом листе
				b.put(Geo.cyl(0.13, 0.13, 0.5, 12), T3(Vector3(-3.04 - fx, 1.35, s * 0.82)), "paint")
				b.put(Geo.cyl(0.14, 0.14, 0.06, 12), T3(Vector3(-3.04 - fx, 1.62, s * 0.82)), "steel")
			# шаровая установка курсового пулемёта справа (у «Файрфлая» снята ради боекомплекта)
			if key == "sherman":
				var e2 := _on_edge(prof, 2, 0.4)
				var p2: Vector2 = e2[0]
				b.put(Geo.sphere(12, 8), T3(Vector3(p2.x, p2.y, 0.5), Vector3.ZERO, Vector3(0.24, 0.24, 0.24)), "paint")
				var mg := _cyl_x(0.025, 0.025, 0.35, 6)
				b.put(mg[0], T3(Vector3(p2.x + 0.2, p2.y - 0.08, 0.5), mg[1] + Vector3(0, 0, -0.45)), "steel")
			else:
				var e2 := _on_edge(prof, 2, 0.4)
				var p2: Vector2 = e2[0]
				b.put(Geo.box(Vector3(0.22, 0.04, 0.3)), T3(Vector3(p2.x, p2.y + 0.02, 0.5), Vector3(0, 0, e2[1])), "paint", true)
			# литой картер трансмиссии: болты по фланцу
			for k in 13:
				b.put(Geo.cyl(0.03, 0.03, 0.03, 6), T3(Vector3(2.68 + fx, 1.11, -1.1 + k * 0.183), Vector3(0, 0, -0.3)), "steel")
			# решётки моторного отделения, лопата и топор
			b.put(Geo.box(Vector3(1.0, 0.04, 1.4)), T3(Vector3(-2.2 - fx, 1.9, 0)), "slit", true)
			for k in 8:
				b.put(Geo.box(Vector3(1.0, 0.05, 0.07)), T3(Vector3(-2.2 - fx, 1.92, -0.63 + k * 0.18)), "paint", true)
			b.put(Geo.box(Vector3(1.2, 0.05, 0.1)), T3(Vector3(-0.95, 1.92, 1.05)), "wood", true)
			b.put(Geo.box(Vector3(0.9, 0.05, 0.1)), T3(Vector3(-1.05, 1.92, -1.05)), "wood", true)
			b.put(Geo.box(Vector3(0.22, 0.04, 0.2)), T3(Vector3(-0.3, 1.92, 1.05)), "steel", true)
			# отражатель выхлопа под кормой
			b.put(Geo.box(Vector3(0.08, 0.36, 1.6)), T3(Vector3(-2.98 - fx, 0.95, 0), Vector3(0, 0, 0.4)), "paint", true)
		"panther":
			# смотровой лючок механика и откидная крышка пулемёта на лобовом листе
			var e := _on_edge(prof, 2, 0.22)
			var p: Vector2 = e[0]
			b.put(Geo.box(Vector3(0.2, 0.07, 0.46)), T3(Vector3(p.x, p.y + 0.03, -0.62), Vector3(0, 0, e[1])), "paint", true)
			b.put(Geo.box(Vector3(0.06, 0.04, 0.3)), T3(Vector3(p.x + 0.02, p.y + 0.07, -0.62), Vector3(0, 0, e[1])), "slit", true)
			if year >= 1944:
				# у Ausf. A и G — шаровая установка вместо «почтового ящика»
				b.put(Geo.sphere(12, 8), T3(Vector3(p.x, p.y, 0.62), Vector3.ZERO, Vector3(0.28, 0.28, 0.28)), "paint")
				var mg := _cyl_x(0.025, 0.025, 0.35, 6)
				b.put(mg[0], T3(Vector3(p.x + 0.22, p.y - 0.1, 0.62), mg[1] + Vector3(0, 0, -0.55)), "steel")
			else:
				b.put(Geo.box(Vector3(0.18, 0.06, 0.26)), T3(Vector3(p.x, p.y + 0.03, 0.62), Vector3(0, 0, e[1])), "paint", true)
				b.put(Geo.box(Vector3(0.05, 0.03, 0.16)), T3(Vector3(p.x + 0.02, p.y + 0.06, 0.62), Vector3(0, 0, e[1])), "slit", true)
			if skirts:
				_skirts(b, W, -2.85, 6, 0.95, th + 0.05, 0.42)
			# фара «Бош»
			b.put(Geo.cyl(0.1, 0.12, 0.2, 10), T3(Vector3(p.x - 0.1, p.y + 0.22, -1.05), Vector3(0, 0, -PI / 2)), "paint")
			for s: float in [1.0, -1.0]:
				# буксирные серьги
				b.put(Geo.box(Vector3(0.2, 0.22, 0.08)), T3(Vector3(3.3, 0.82, s * 1.1)), "steel", true)
				# выхлопные трубы с кожухами на кормовом листе
				b.put(Geo.cyl(0.085, 0.085, 0.85, 10), T3(Vector3(-3.36, 1.62, s * 0.48)), "rust")
				b.put(Geo.cyl(0.13, 0.13, 0.5, 10), T3(Vector3(-3.33, 1.42, s * 0.48)), "paint")
				# решётки вентиляторов на моторной палубе
				b.put(Geo.cyl(0.28, 0.28, 0.04, 16), T3(Vector3(-2.55, 1.89, s * 0.52)), "slit")
				for k in 4:
					b.put(Geo.box(Vector3(0.54, 0.04, 0.05)), T3(Vector3(-2.55, 1.91, s * 0.52 - 0.18 + k * 0.12)), "steel", true)
				b.put(Geo.box(Vector3(0.75, 0.04, 0.5)), T3(Vector3(-1.7, 1.89, s * 0.55)), "slit", true)
				# буксирный трос вдоль наклонного борта
				var rope := _cyl_x(0.03, 0.03, 4.6, 6)
				b.put(rope[0], T3(Vector3(-0.4, th + 0.22, s * (up_w / 2 - 0.22 * side_k + 0.04)), rope[1]), "rope")
			# домкрат и ящик ЗИП на корме
			b.put(Geo.cyl(0.09, 0.09, 0.6, 10), T3(Vector3(-3.4, 1.0, -0.95), Vector3(PI / 2, 0, 0)), "steel")
			b.put(Geo.box(Vector3(0.25, 0.3, 0.7)), T3(Vector3(-3.32, 1.05, 0.95)), "paint", true)
			b.put(Geo.cyl(0.012, 0.012, 2.0, 4), T3(Vector3(-2.9, 2.88, -0.9)), "steel")
		"pz3":
			# смотровой прибор механика и шаровая установка пулемёта в лобовом листе рубки
			b.put(Geo.box(Vector3(0.1, 0.12, 0.34)), T3(Vector3(1.64, 1.52, -0.55)), "paint", true)
			b.put(Geo.box(Vector3(0.03, 0.03, 0.24)), T3(Vector3(1.7, 1.52, -0.55)), "slit", true)
			b.put(Geo.sphere(12, 8), T3(Vector3(1.62, 1.5, 0.55), Vector3.ZERO, Vector3(0.26, 0.26, 0.26)), "paint")
			var mg := _cyl_x(0.022, 0.022, 0.3, 6)
			b.put(mg[0], T3(Vector3(1.8, 1.5, 0.55), mg[1]), "steel")
			# люки доступа к тормозам и запасные траки на носу
			var e := _on_edge(prof, 3, 0.5)
			var p: Vector2 = e[0]
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(0.42, 0.05, 0.62)), T3(Vector3(p.x, p.y + 0.03, s * 0.5), Vector3(0, 0, e[1])), "paint", true)
				b.put(Geo.box(Vector3(0.16, 0.12, 0.08)), T3(Vector3(2.78, 0.7, s * 0.85)), "steel", true)
				b.put(Geo.box(Vector3(0.16, 0.12, 0.08)), T3(Vector3(-2.82, 0.7, s * 0.85)), "steel", true)
			var ek := _on_edge(prof, 4, 0.5)
			var pk: Vector2 = ek[0]
			for z: float in [-0.75, -0.38, 0.0, 0.38, 0.75]:
				b.put(Geo.box(Vector3(0.05, 0.13, 0.34)), T3(Vector3(pk.x + 0.03, pk.y, z), Vector3(0, 0, ek[1] + PI / 2)), "steel", true)
			# фара «Нотек», глушитель поперёк кормы, антенна
			b.put(Geo.box(Vector3(0.14, 0.1, 0.12)), T3(Vector3(2.4, th + 0.12, -1.25)), "paint", true)
			b.put(Geo.cyl(0.16, 0.16, 1.5, 12), T3(Vector3(-2.94, 1.0, 0), Vector3(PI / 2, 0, 0)), "rust")
			b.put(Geo.cyl(0.012, 0.012, 2.0, 4), T3(Vector3(-2.4, 2.62, 1.15)), "steel")
			# решётки и люки моторного отделения, инструмент на полках
			b.put(Geo.box(Vector3(0.9, 0.04, 1.6)), T3(Vector3(-2.15, 1.63, 0)), "slit", true)
			for k in 8:
				b.put(Geo.box(Vector3(0.9, 0.05, 0.07)), T3(Vector3(-2.15, 1.65, -0.7 + k * 0.2)), "paint", true)
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(0.6, 0.05, 0.55)), T3(Vector3(-1.35, 1.64, s * 0.45)), "paint", true)
			b.put(Geo.box(Vector3(1.4, 0.06, 0.12)), T3(Vector3(-0.6, th + 0.1, 1.3)), "wood", true)
			b.put(Geo.box(Vector3(0.8, 0.1, 0.14)), T3(Vector3(-1.7, th + 0.1, -1.3)), "steel", true)
			if skirts:
				_skirts(b, W, -2.1, 5, 0.94, 1.3)
		"crusader":
			# выступающая рубка механика-водителя справа
			var e := _on_edge(prof, 2, 0.32)
			var p: Vector2 = e[0]
			b.put(Geo.box(Vector3(0.62, 0.28, 0.64)), T3(Vector3(p.x - 0.05, p.y + 0.12, 0.6)), "paint", true)
			b.put(Geo.box(Vector3(0.04, 0.05, 0.38)), T3(Vector3(p.x + 0.27, p.y + 0.18, 0.6)), "slit", true)
			b.put(Geo.box(Vector3(0.3, 0.04, 0.4)), T3(Vector3(p.x - 0.1, p.y + 0.28, 0.6)), "paint", true)
			for s: float in [1.0, -1.0]:
				# фары и буксирные серьги
				b.put(Geo.cyl(0.08, 0.09, 0.14, 10), T3(Vector3(2.75, 1.12, s * 1.05), Vector3(0, 0, -PI / 2)), "glass")
				b.put(Geo.box(Vector3(0.16, 0.14, 0.08)), T3(Vector3(3.0, 0.62, s * 0.8)), "steel", true)
				# песочные экраны над гусеницами
				b.put(Geo.box(Vector3(L * 0.92, 0.32, 0.03)), T3(Vector3(-0.05, th - 0.08, s * (W / 2 + 0.02))), "paint", true)
				# выхлопная труба вдоль кормы
				var ex := _cyl_x(0.07, 0.07, 0.5, 8)
				b.put(ex[0], T3(Vector3(-3.05, 1.12, s * 0.75), ex[1]), "rust")
			# большие жалюзи моторного отделения и канистры на корме
			b.put(Geo.box(Vector3(2.0, 0.04, 1.8)), T3(Vector3(-1.75, 1.41, 0)), "slit", true)
			for k in 10:
				b.put(Geo.box(Vector3(2.0, 0.05, 0.07)), T3(Vector3(-1.75, 1.43, -0.81 + k * 0.18)), "paint", true)
			for k in 4:
				b.put(Geo.box(Vector3(0.14, 0.34, 0.24)), T3(Vector3(-3.07, 0.95, -0.4 + k * 0.27)), "olive", true)
			b.put(Geo.box(Vector3(1.4, 0.06, 0.12)), T3(Vector3(-0.4, 1.44, -1.15)), "wood", true)
		"cromwell":
			# лобовой лист: смотровой лючок механика справа, курсовой «Беза» слева
			b.put(Geo.box(Vector3(0.08, 0.16, 0.42)), T3(Vector3(3.17, 1.3, 0.62)), "paint", true)
			b.put(Geo.box(Vector3(0.03, 0.04, 0.3)), T3(Vector3(3.22, 1.32, 0.62)), "slit", true)
			b.put(Geo.sphere(12, 8), T3(Vector3(3.15, 1.25, -0.6), Vector3.ZERO, Vector3(0.24, 0.24, 0.24)), "paint")
			var mg := _cyl_x(0.022, 0.022, 0.3, 6)
			b.put(mg[0], T3(Vector3(3.32, 1.25, -0.6), mg[1]), "steel")
			for s: float in [1.0, -1.0]:
				# фары, буксирные серьги, выносные бортовые листы над подвеской
				b.put(Geo.cyl(0.08, 0.09, 0.14, 10), T3(Vector3(3.2, 1.5, s * 1.1), Vector3(0, 0, -PI / 2)), "glass")
				b.put(Geo.box(Vector3(0.16, 0.14, 0.08)), T3(Vector3(3.12, 0.62, s * 0.85)), "steel", true)
				b.put(Geo.box(Vector3(L * 0.93, 0.42, 0.03)), T3(Vector3(-0.05, th - 0.1, s * (W / 2 + 0.02))), "paint", true)
				# ящики ЗИП на крыльях
				b.put(Geo.box(Vector3(0.9, 0.3, 0.2)), T3(Vector3(-1.9, th + 0.25, s * (W / 2 - 0.08))), "paint", true)
			# жалюзи моторного отделения и выхлоп «рыбий хвост» на корме
			b.put(Geo.box(Vector3(2.2, 0.04, 1.9)), T3(Vector3(-1.9, 1.54, 0)), "slit", true)
			for k in 11:
				b.put(Geo.box(Vector3(2.2, 0.05, 0.07)), T3(Vector3(-1.9, 1.56, -0.86 + k * 0.172)), "paint", true)
			b.put(Geo.box(Vector3(0.22, 0.3, 1.4)), T3(Vector3(-3.27, 1.25, 0)), "paint", true)
			b.put(Geo.box(Vector3(0.05, 0.12, 1.3)), T3(Vector3(-3.39, 1.2, 0)), "rust", true)
		"tiger2":
			# перископ механика, шаровая установка пулемёта на лобовом листе
			var e := _on_edge(prof, 2, 0.12)
			var p: Vector2 = e[0]
			b.put(Geo.box(Vector3(0.16, 0.12, 0.3)), T3(Vector3(p.x - 0.1, p.y + 0.06, -0.7)), "paint", true)
			var e2 := _on_edge(prof, 2, 0.32)
			var p2: Vector2 = e2[0]
			b.put(Geo.sphere(12, 8), T3(Vector3(p2.x, p2.y, 0.7), Vector3.ZERO, Vector3(0.3, 0.3, 0.3)), "paint")
			var mg := _cyl_x(0.025, 0.025, 0.35, 6)
			b.put(mg[0], T3(Vector3(p2.x + 0.22, p2.y - 0.1, 0.7), mg[1] + Vector3(0, 0, -0.5)), "steel")
			b.put(Geo.cyl(0.1, 0.12, 0.2, 10), T3(Vector3(p.x, p.y + 0.18, -1.2), Vector3(0, 0, -PI / 2)), "paint")
			for s: float in [1.0, -1.0]:
				# буксирные серьги, выхлопные трубы, вентиляторы, тросы вдоль наклонных бортов
				b.put(Geo.box(Vector3(0.24, 0.26, 0.1)), T3(Vector3(3.55, 0.95, s * 1.2)), "steel", true)
				b.put(Geo.cyl(0.09, 0.09, 0.9, 10), T3(Vector3(-3.72, 1.72, s * 0.5)), "rust")
				b.put(Geo.cyl(0.14, 0.14, 0.55, 10), T3(Vector3(-3.68, 1.52, s * 0.5)), "paint")
				b.put(Geo.cyl(0.3, 0.3, 0.04, 16), T3(Vector3(-2.8, 2.01, s * 0.6)), "slit")
				for k in 4:
					b.put(Geo.box(Vector3(0.58, 0.04, 0.05)), T3(Vector3(-2.8, 2.03, s * 0.6 - 0.2 + k * 0.13)), "steel", true)
				b.put(Geo.box(Vector3(0.8, 0.04, 0.55)), T3(Vector3(-1.85, 2.01, s * 0.6)), "slit", true)
				var rope := _cyl_x(0.03, 0.03, 5.0, 6)
				b.put(rope[0], T3(Vector3(-0.3, th + 0.3, s * (up_w / 2 - 0.3 * side_k + 0.04)), rope[1]), "rope")
			b.put(Geo.cyl(0.012, 0.012, 2.0, 4), T3(Vector3(-3.0, 3.0, 1.0)), "steel")
			if skirts:
				_skirts(b, W, -3.1, 7, 0.95, th + 0.05, 0.42)
		"stug":
			# люки доступа к тормозам на верхнем лобовом листе
			var e := _on_edge(prof, 2, 0.5)
			var p: Vector2 = e[0]
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(0.4, 0.05, 0.6)), T3(Vector3(p.x, p.y + 0.03, s * 0.5), Vector3(0, 0, e[1])), "paint", true)
				b.put(Geo.box(Vector3(0.16, 0.12, 0.08)), T3(Vector3(2.72, 0.7, s * 0.85)), "steel", true)
				b.put(Geo.box(Vector3(0.16, 0.12, 0.08)), T3(Vector3(-2.78, 0.7, s * 0.85)), "steel", true)
			# фара «Нотек» на левой полке, запасные траки на носу
			b.put(Geo.box(Vector3(0.14, 0.1, 0.12)), T3(Vector3(2.4, th + 0.12, -1.25)), "paint", true)
			b.put(Geo.box(Vector3(0.02, 0.04, 0.08)), T3(Vector3(2.48, th + 0.12, -1.25)), "glass", true)
			for k in 2:
				var ek := _on_edge(prof, 3, 0.3 + k * 0.4)
				var pk: Vector2 = ek[0]
				for z: float in [-0.75, -0.38, 0.38, 0.75]:
					b.put(Geo.box(Vector3(0.05, 0.13, 0.34)), T3(Vector3(pk.x + 0.03, pk.y, z), Vector3(0, 0, ek[1] + PI / 2)), "steel", true)
			# глушитель поперёк кормы
			b.put(Geo.cyl(0.16, 0.16, 1.5, 12), T3(Vector3(-2.9, 1.0, 0), Vector3(PI / 2, 0, 0)), "rust")
			# решётки и люки моторного отделения
			b.put(Geo.box(Vector3(0.9, 0.04, 1.6)), T3(Vector3(-2.15, 1.41, 0)), "slit", true)
			for k in 8:
				b.put(Geo.box(Vector3(0.9, 0.05, 0.07)), T3(Vector3(-2.15, 1.43, -0.7 + k * 0.2)), "paint", true)
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(0.6, 0.05, 0.55)), T3(Vector3(-1.38, 1.42, s * 0.45)), "paint", true)
			# инструмент и домкрат на полках
			b.put(Geo.box(Vector3(1.4, 0.06, 0.12)), T3(Vector3(-0.6, th + 0.1, 1.3)), "wood", true)
			b.put(Geo.box(Vector3(0.8, 0.1, 0.14)), T3(Vector3(-1.7, th + 0.1, -1.3)), "steel", true)
			if skirts:
				_skirts(b, W, -2.1, 5, 0.94, 1.3)


## Бортовые экраны: count листов высотой h шагом step от x0, поручень на высоте rail_y.
static func _skirts(b: Builder, W: float, x0: float, count: int, step: float, rail_y: float, h := 0.95) -> void:
	for s: float in [1.0, -1.0]:
		var rail := _cyl_x(0.025, 0.025, step * count, 6)
		b.put(rail[0], T3(Vector3(x0 + step * (count - 1) / 2.0, rail_y, s * (W / 2 + 0.16)), rail[1]), "steel")
		for k in count:
			var px := x0 + k * step
			b.put(Geo.box(Vector3(step - 0.04, h, 0.03)), T3(Vector3(px, rail_y - h / 2, s * (W / 2 + 0.18)), Vector3(0.03 * s, 0, 0.01 * (k - 2))), "paint", true)

static func th_top(S: Dictionary) -> float:
	return float(S.th) + 0.06


## Маска орудия: front — лоб башни (у рубки 0 — ось качания), gy — высота оси орудия.
static func _mantlet(b: Builder, S: Dictionary, front: float, gy: float) -> void:
	match S.mant:
		"cast":
			b.put(Geo.sphere(16, 10), T3(Vector3(front * 0.9, gy, 0), Vector3.ZERO, Vector3(0.5, 0.6, 0.95)), "paint")
			b.put(Geo.box(Vector3(0.4, 0.5, 0.82)), T3(Vector3(front * 0.82, gy, 0)), "paint")
		"cast_big":
			b.put(Geo.sphere(16, 10), T3(Vector3(front * 0.92, gy, 0), Vector3.ZERO, Vector3(0.62, 0.66, 1.15)), "paint")
			b.put(Geo.box(Vector3(0.5, 0.58, 1.0)), T3(Vector3(front * 0.82, gy, 0)), "paint")
		"plate":
			b.put(Geo.box(Vector3(0.26, 0.78, 1.55)), T3(Vector3(front + 0.12, gy, 0)), "paint", true)
			b.put(Geo.cyl(0.18, 0.18, 0.4, 12), T3(Vector3(front + 0.4, gy, 0), Vector3(0, 0, -PI / 2)), "paint")
			# смотровой прибор и спаренный пулемёт в маске
			b.put(Geo.box(Vector3(0.06, 0.06, 0.08)), T3(Vector3(front + 0.26, gy + 0.13, -0.35)), "slit", true)
			b.put(Geo.box(Vector3(0.06, 0.06, 0.08)), T3(Vector3(front + 0.26, gy - 0.06, 0.38)), "slit", true)
		"box":
			b.put(Geo.box(Vector3(0.3, 0.48, 0.62)), T3(Vector3(front + 0.1, gy, 0)), "paint", true)
			b.put(Geo.cyl(0.13, 0.15, 0.35, 12), T3(Vector3(front + 0.35, gy, 0), Vector3(0, 0, -PI / 2)), "paint")
		"rounded":
			b.put(Geo.sphere(16, 10), T3(Vector3(front * 0.92, gy, 0), Vector3.ZERO, Vector3(0.4, 0.5, 0.8)), "paint")
		"box_spaced":
			# маска Pz III L с навесным 20-мм экраном
			b.put(Geo.box(Vector3(0.24, 0.44, 0.66)), T3(Vector3(front + 0.06, gy, 0)), "paint", true)
			b.put(Geo.box(Vector3(0.04, 0.42, 0.72)), T3(Vector3(front + 0.26, gy, 0)), "paint", true)
			b.put(Geo.cyl(0.1, 0.12, 0.28, 12), T3(Vector3(front + 0.38, gy, 0), Vector3(0, 0, -PI / 2)), "paint")
			b.put(Geo.box(Vector3(0.04, 0.05, 0.05)), T3(Vector3(front + 0.29, gy + 0.02, 0.22)), "slit", true)
		"6pdr":
			# плоская маска 6-фунтовки с прорезями прицела и пулемёта «Беза»
			b.put(Geo.box(Vector3(0.14, 0.34, 0.62)), T3(Vector3(front + 0.02, gy, 0)), "paint", true)
			b.put(Geo.cyl(0.08, 0.1, 0.3, 12), T3(Vector3(front + 0.22, gy, 0), Vector3(0, 0, -PI / 2)), "paint")
			b.put(Geo.box(Vector3(0.04, 0.05, 0.05)), T3(Vector3(front + 0.1, gy + 0.03, -0.2)), "slit", true)
			b.put(Geo.cyl(0.025, 0.025, 0.25, 6), T3(Vector3(front + 0.2, gy - 0.02, 0.2), Vector3(0, 0, -PI / 2)), "steel")
		"f34":
			# литая бронировка пушки Ф-34: короб с округлым лбом и муфта ствола
			b.put(Geo.box(Vector3(0.42, 0.42, 0.56)), T3(Vector3(front + 0.06, gy, 0)), "paint", true)
			b.put(Geo.cyl(0.21, 0.21, 0.56, 14), T3(Vector3(front + 0.26, gy, 0), Vector3(PI / 2, 0, 0)), "paint")
			b.put(Geo.cyl(0.11, 0.13, 0.32, 12), T3(Vector3(front + 0.5, gy, 0), Vector3(0, 0, -PI / 2)), "paint")
			b.put(Geo.box(Vector3(0.04, 0.05, 0.05)), T3(Vector3(front + 0.45, gy + 0.02, 0.2)), "slit", true)
		"kv":
			# маска ЗиС-5: скошенный короб и толстая муфта
			b.put(Geo.box(Vector3(0.36, 0.5, 0.7)), T3(Vector3(front + 0.04, gy, 0)), "paint", true)
			b.put(Geo.box(Vector3(0.22, 0.36, 0.5)), T3(Vector3(front + 0.28, gy, 0)), "paint", true)
			b.put(Geo.cyl(0.12, 0.14, 0.36, 12), T3(Vector3(front + 0.5, gy, 0), Vector3(0, 0, -PI / 2)), "paint")
			b.put(Geo.box(Vector3(0.04, 0.05, 0.05)), T3(Vector3(front + 0.4, gy + 0.04, 0.2)), "slit", true)
		"rotor":
			# установка M34: узкий ротор с прицелом и спаренным пулемётом
			b.put(Geo.box(Vector3(0.16, 0.42, 0.74)), T3(Vector3(front + 0.02, gy, 0)), "paint", true)
			b.put(Geo.cyl(0.19, 0.19, 0.66, 16), T3(Vector3(front + 0.1, gy, 0), Vector3(PI / 2, 0, 0)), "paint")
			b.put(Geo.cyl(0.1, 0.11, 0.3, 12), T3(Vector3(front + 0.4, gy, 0), Vector3(0, 0, -PI / 2)), "paint")
			b.put(Geo.box(Vector3(0.05, 0.05, 0.05)), T3(Vector3(front + 0.33, gy, 0.22)), "slit", true)
			b.put(Geo.box(Vector3(0.05, 0.05, 0.05)), T3(Vector3(front + 0.33, gy + 0.05, -0.24)), "slit", true)
		"bell":
			# литая скруглённая маска «Пантеры» и прорези бинокулярного прицела
			b.put(Geo.cyl(0.38, 0.38, 0.96, 18), T3(Vector3(front - 0.02, gy, 0), Vector3(PI / 2, 0, 0)), "paint")
			b.put(Geo.cyl(0.13, 0.15, 0.42, 12), T3(Vector3(front + 0.5, gy, 0), Vector3(0, 0, -PI / 2)), "paint")
			for z: float in [-0.3, -0.38]:
				b.put(Geo.box(Vector3(0.05, 0.05, 0.04)), T3(Vector3(front + 0.35, gy + 0.12, z)), "slit", true)
			b.put(Geo.box(Vector3(0.05, 0.05, 0.05)), T3(Vector3(front + 0.35, gy + 0.05, 0.3)), "slit", true)
		"saukopf_big":
			# литая маска «свиное рыло» башни «Хеншель»
			b.put(Geo.sphere(16, 10), T3(Vector3(front + 0.04, gy, 0), Vector3.ZERO, Vector3(0.6, 0.56, 0.66)), "paint")
			b.put(Geo.cyl(0.15, 0.3, 0.5, 14), T3(Vector3(front + 0.4, gy, 0), Vector3(0, 0, -PI / 2)), "paint")
			b.put(Geo.box(Vector3(0.05, 0.05, 0.05)), T3(Vector3(front + 0.3, gy + 0.1, 0.3)), "slit", true)
		"saukopf":
			# литая маска «свиное рыло» на штурмовом орудии
			b.put(Geo.sphere(16, 10), T3(Vector3(front + 0.06, gy, 0), Vector3.ZERO, Vector3(0.56, 0.44, 0.52)), "paint")
			b.put(Geo.cyl(0.12, 0.24, 0.42, 14), T3(Vector3(front + 0.36, gy, 0), Vector3(0, 0, -PI / 2)), "paint")


static func _turret_details(b: Builder, key: String, S: Dictionary, front: float, h: float, skirts: bool, year: int) -> void:
	var hw: float = S.tpoly[3]
	var back: float = S.tpoly[2]
	var top: float = S.tur_top
	# командирская башенка со смотровыми щелями и открытым люком
	var cp: Array = S.cupola
	var cx := 0.0
	var cz := 0.0
	var ch := 0.0
	if not cp.is_empty():
		cx = cp[0]
		cz = cp[1]
		var cr: float = cp[2]
		ch = cp[3]
		b.put(Geo.cyl(cr, cr * 1.05, ch, 16), T3(Vector3(cx, h * top + ch / 2 - 0.02, cz)), "paint")
		b.put(Geo.cyl(cr * 1.01, cr * 1.01, 0.05, 16), T3(Vector3(cx, h * top + ch * 0.55, cz)), "slit")
		b.put(Geo.cyl(cr * 0.88, cr * 0.92, 0.07, 16), T3(Vector3(cx, h * top + ch + 0.01, cz)), "paint")
		b.put(Geo.box(Vector3(0.1, 0.05, 0.04)), T3(Vector3(cx + cr * 0.4, h * top + ch + 0.06, cz)), "steel", true)
	# люк заряжающего
	if S.get("hatch", true):
		b.put(Geo.box(Vector3(0.5, 0.05, 0.45)), T3(Vector3(-0.1, h * top + 0.02, -cz * 0.9 if cz != 0.0 else 0.4)), "paint", true)
	match key:
		"t34":
			for s: float in [1.0, -1.0]:
				# поручни и перископы
				var rail := _cyl_x(0.02, 0.02, 1.1, 6)
				b.put(rail[0], T3(Vector3(-0.35, h * 0.7, s * (hw * 0.93 + 0.04)), rail[1]), "steel")
				b.put(Geo.box(Vector3(0.12, 0.1, 0.1)), T3(Vector3(0.25, h * top + 0.05, s * 0.45)), "paint", true)
			# грибки вентиляторов
			for z: float in [-0.25, 0.25]:
				b.put(Geo.sphere(12, 6), T3(Vector3(-1.05, h * top, z), Vector3.ZERO, Vector3(0.32, 0.18, 0.32)), "paint")
		"tiger":
			for s: float in [1.0, -1.0]:
				# дымовые мортирки по три на борт
				for k in 3:
					b.put(Geo.cyl(0.05, 0.05, 0.22, 8), T3(Vector3(front * 0.55 - k * 0.12, h * 0.78, s * (hw + 0.05)), Vector3(s * 0.7, 0, 0)), "paint")
				# запасные траки на бортах башни
				for k in 3:
					b.put(Geo.box(Vector3(0.16, 0.36, 0.035)), T3(Vector3(-0.25 - k * 0.2, h * 0.42, s * (hw + 0.02))), "steel", true)
			# ящик «Роммеля» на корме башни
			b.put(Geo.box(Vector3(0.5, 0.45, 1.2)), T3(Vector3(-back - 0.18, h * 0.5, 0)), "paint", true)
		"is2":
			# ДШК на командирской башенке, кормовой пулемёт, поручни
			var dshk := _cyl_x(0.03, 0.03, 1.4, 6)
			b.put(dshk[0], T3(Vector3(cx + 0.6, h * top + ch + 0.35, cz), dshk[1] + Vector3(0, 0, 0.1)), "steel")
			b.put(Geo.box(Vector3(0.2, 0.18, 0.12)), T3(Vector3(cx, h * top + ch + 0.25, cz)), "steel", true)
			b.put(Geo.sphere(12, 8), T3(Vector3(-back * 0.98, h * 0.48, 0), Vector3.ZERO, Vector3(0.28, 0.28, 0.28)), "paint")
			for s: float in [1.0, -1.0]:
				var rail := _cyl_x(0.02, 0.02, 1.3, 6)
				b.put(rail[0], T3(Vector3(-0.3, h * 0.72, s * (hw * 0.86 + 0.05)), rail[1]), "steel")
		"pz4":
			# экраны вокруг башни (с весны 1943 г.)
			for s: float in [1.0, -1.0]:
				if skirts:
					b.put(Geo.box(Vector3(1.55, 0.66, 0.03)), T3(Vector3(-0.35, h * 0.5, s * (hw + 0.24)), Vector3(0, 0, 0)), "paint", true)
					b.put(Geo.box(Vector3(0.12, 0.04, 0.24)), T3(Vector3(-0.35, h * 0.75, s * (hw + 0.12))), "steel", true)
				# бортовые люки башни
				b.put(Geo.box(Vector3(0.45, 0.4, 0.05)), T3(Vector3(-0.1, h * 0.45, s * 0.84)), "paint", true)
			if skirts:
				b.put(Geo.box(Vector3(0.03, 0.66, 1.9)), T3(Vector3(-1.52, h * 0.5, 0)), "paint", true)
		"t34_76":
			# два круглых люка, перископы, поручни, лючки для стрельбы из личного оружия
			for s: float in [1.0, -1.0]:
				b.put(Geo.cyl(0.26, 0.27, 0.06, 16), T3(Vector3(-0.42, h * top + 0.03, s * 0.36)), "paint")
				b.put(Geo.box(Vector3(0.06, 0.04, 0.12)), T3(Vector3(-0.2, h * top + 0.07, s * 0.36)), "steel", true)
				b.put(Geo.box(Vector3(0.12, 0.1, 0.1)), T3(Vector3(0.22, h * top + 0.05, s * 0.36)), "paint", true)
				var rail := _cyl_x(0.02, 0.02, 0.9, 6)
				b.put(rail[0], T3(Vector3(-0.3, h * 0.62, s * (_side_at(hw, top, 0.62) + 0.05)), rail[1]), "steel")
				b.put(Geo.cyl(0.05, 0.05, 0.05, 8), T3(Vector3(-0.7, h * 0.45, s * _side_at(hw, top, 0.45)), Vector3(PI / 2, 0, 0)), "steel")
			b.put(Geo.sphere(12, 6), T3(Vector3(0.42, h * top, 0), Vector3.ZERO, Vector3(0.28, 0.14, 0.28)), "paint")
		"kv1":
			# пулемёт ДТ в корме башни, большой люк, перископы, смотровые щели, антенна
			b.put(Geo.sphere(12, 8), T3(Vector3(-back * _side_at(1.0, top, 0.45), h * 0.45, 0), Vector3.ZERO, Vector3(0.26, 0.26, 0.26)), "paint")
			var dt := _cyl_x(0.02, 0.02, 0.3, 6)
			b.put(dt[0], T3(Vector3(-back * _side_at(1.0, top, 0.45) - 0.14, h * 0.45, 0), dt[1]), "steel")
			b.put(Geo.cyl(0.36, 0.38, 0.06, 18), T3(Vector3(-0.25, h * top + 0.03, 0)), "paint")
			b.put(Geo.box(Vector3(0.06, 0.05, 0.4)), T3(Vector3(-0.25, h * top + 0.08, 0)), "steel", true)
			b.put(Geo.box(Vector3(0.14, 0.14, 0.1)), T3(Vector3(0.3, h * top + 0.07, -0.42)), "paint", true)
			b.put(Geo.box(Vector3(0.1, 0.1, 0.08)), T3(Vector3(0.15, h * top + 0.05, 0.48)), "paint", true)
			for s: float in [1.0, -1.0]:
				var rail := _cyl_x(0.02, 0.02, 1.1, 6)
				b.put(rail[0], T3(Vector3(-0.3, h * 0.66, s * (_side_at(hw, top, 0.66) + 0.04)), rail[1]), "steel")
				b.put(Geo.box(Vector3(0.18, 0.04, 0.04)), T3(Vector3(0.25, h * 0.68, s * _side_at(hw * 0.97, top, 0.68))), "slit", true)
			b.put(Geo.cyl(0.012, 0.012, 1.8, 4), T3(Vector3(-0.75, h * top + 0.9, 0.55)), "steel")
		"sherman", "firefly":
			if key == "firefly":
				# короб радиостанции на корме башни: место внутри заняла казённая часть 17-фунтовки
				b.put(Geo.box(Vector3(0.5, 0.42, 0.9)), T3(Vector3(-back * _side_at(1.0, top, 0.45) - 0.18, h * 0.45, 0)), "paint", true)
			# раздвижной люк командира, «Браунинг» калибра .50 на турели, перископы, антенна
			b.put(Geo.cyl(0.3, 0.32, 0.07, 16), T3(Vector3(-0.35, h * top + 0.03, 0.36)), "paint")
			b.put(Geo.box(Vector3(0.04, 0.05, 0.56)), T3(Vector3(-0.35, h * top + 0.08, 0.36)), "steel", true)
			var m2 := _cyl_x(0.03, 0.03, 1.5, 6)
			b.put(m2[0], T3(Vector3(-0.15, h * top + 0.45, 0.36), m2[1] + Vector3(0, 0, 0.06)), "steel")
			b.put(Geo.box(Vector3(0.3, 0.15, 0.12)), T3(Vector3(-0.55, h * top + 0.42, 0.36)), "steel", true)
			b.put(Geo.cyl(0.03, 0.03, 0.38, 6), T3(Vector3(-0.55, h * top + 0.2, 0.36)), "steel")
			for z: float in [-0.4, 0.12]:
				b.put(Geo.box(Vector3(0.12, 0.1, 0.1)), T3(Vector3(0.35, h * top + 0.05, z)), "paint", true)
			var px := -0.5
			var pz := hw * sqrt(1.0 - pow(px / back, 2.0)) * _side_at(1.0, top, 0.5)
			b.put(Geo.cyl(0.08, 0.08, 0.05, 10), T3(Vector3(px, h * 0.5, -pz), Vector3(PI / 2, 0, 0)), "steel")
			b.put(Geo.cyl(0.012, 0.012, 2.2, 4), T3(Vector3(-0.95, h * top + 1.1, -0.3)), "steel")
		"panther":
			# дымовые мортирки по три на борт (только Ausf. D), лючки, люк в корме башни, вентилятор
			for s: float in [1.0, -1.0]:
				for k in (3 if year < 1944 else 0):
					var x := front * 0.15 - k * 0.15
					var sw := lerpf(hw * 0.66, hw, clampf((front - x) / (front + back * 0.86), 0.0, 1.0))
					b.put(Geo.cyl(0.045, 0.045, 0.2, 8), T3(Vector3(x, h * 0.8, s * (_side_at(sw, top, 0.8) + 0.05)), Vector3(s * 0.7, 0, 0)), "paint")
				var sw2 := lerpf(hw * 0.66, hw, clampf((front + 0.7) / (front + back * 0.86), 0.0, 1.0))
				b.put(Geo.cyl(0.06, 0.06, 0.05, 8), T3(Vector3(-0.7, h * 0.45, s * _side_at(sw2, top, 0.45)), Vector3(PI / 2, 0, 0)), "steel")
			b.put(Geo.cyl(0.3, 0.3, 0.06, 16), T3(Vector3(-back * _side_at(1.0, top, 0.48) - 0.02, h * 0.48, 0), Vector3(0, 0, PI / 2)), "paint")
			b.put(Geo.cyl(0.12, 0.12, 0.05, 10), T3(Vector3(0.3, h * top + 0.02, 0.1)), "paint")
		"stug":
			# смотровой прибор механика в лобовом листе рубки, ниша прицела, щит пулемёта
			b.put(Geo.box(Vector3(0.08, 0.12, 0.38)), T3(Vector3(front * _side_at(1.0, top, 0.62) + 0.02, h * 0.62, -0.62)), "paint", true)
			b.put(Geo.box(Vector3(0.03, 0.03, 0.28)), T3(Vector3(front * _side_at(1.0, top, 0.62) + 0.06, h * 0.62, -0.62)), "slit", true)
			b.put(Geo.box(Vector3(0.3, 0.12, 0.22)), T3(Vector3(front * 0.55, h * top + 0.05, -0.3)), "paint", true)
			b.put(Geo.box(Vector3(0.04, 0.32, 0.5)), T3(Vector3(0.05, h * top + 0.17, 0.5)), "paint", true)
			var mg := _cyl_x(0.02, 0.02, 0.8, 6)
			b.put(mg[0], T3(Vector3(0.35, h * top + 0.25, 0.5), mg[1]), "steel")
			b.put(Geo.box(Vector3(0.55, 0.05, 0.45)), T3(Vector3(-0.5, h * top + 0.02, 0.5)), "paint", true)
			# стереотруба командира и антенна
			for s: float in [1.0, -1.0]:
				b.put(Geo.cyl(0.02, 0.02, 0.4, 6), T3(Vector3(cx + 0.1, h * top + ch + 0.2, cz + s * 0.07)), "steel")
			b.put(Geo.cyl(0.012, 0.012, 2.0, 4), T3(Vector3(-back * 0.8, h * top + 1.0, 0.85)), "steel")
			# ящик ЗИП на корме рубки
			b.put(Geo.box(Vector3(0.22, 0.3, 0.9)), T3(Vector3(-back * _side_at(1.0, top, 0.45) - 0.1, h * 0.45, 0)), "paint", true)
		"pz3":
			for s: float in [1.0, -1.0]:
				# бортовые люки и смотровые щели
				b.put(Geo.box(Vector3(0.42, 0.4, 0.05)), T3(Vector3(-0.15, h * 0.45, s * _side_at(hw * 0.97, top, 0.45))), "paint", true)
				b.put(Geo.box(Vector3(0.16, 0.03, 0.04)), T3(Vector3(0.25, h * 0.62, s * _side_at(hw * 0.99, top, 0.62))), "slit", true)
				if skirts:
					b.put(Geo.box(Vector3(1.4, 0.6, 0.03)), T3(Vector3(-0.35, h * 0.5, s * (hw + 0.22))), "paint", true)
					b.put(Geo.box(Vector3(0.12, 0.04, 0.22)), T3(Vector3(-0.35, h * 0.75, s * (hw + 0.11))), "steel", true)
			# ящик «Роммеля» на корме башни
			b.put(Geo.box(Vector3(0.42, 0.4, 1.1)), T3(Vector3(-back * 0.92 - 0.12, h * 0.5, 0)), "paint", true)
		"crusader":
			# два люка, перископы, бомбомёт, ящик на корме, антенна
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(0.45, 0.04, 0.36)), T3(Vector3(-0.35, h * top + 0.02, s * 0.25)), "paint", true)
				b.put(Geo.box(Vector3(0.1, 0.1, 0.1)), T3(Vector3(0.12, h * top + 0.05, s * 0.3)), "paint", true)
			b.put(Geo.cyl(0.05, 0.05, 0.35, 8), T3(Vector3(0.05, h * 0.75, _side_at(hw, top, 0.75) + 0.08), Vector3(0.6, 0, 0)), "steel")
			b.put(Geo.box(Vector3(0.3, 0.32, 1.0)), T3(Vector3(-back * _side_at(1.0, top, 0.45) - 0.12, h * 0.45, 0)), "paint", true)
			b.put(Geo.cyl(0.012, 0.012, 2.4, 4), T3(Vector3(-0.7, h * top + 1.2, -0.4)), "steel")
		"cromwell":
			# навесные бортовые листы на болтах, бомбомёт, ящик на корме, антенны
			for s: float in [1.0, -1.0]:
				b.put(Geo.box(Vector3(1.3, h * 0.8, 0.03)), T3(Vector3(-0.1, h * 0.45, s * (hw + 0.02))), "paint", true)
				for k in 4:
					for j in 2:
						b.put(Geo.cyl(0.025, 0.025, 0.02, 6), T3(Vector3(-0.65 + k * 0.36, h * (0.2 + j * 0.5), s * (hw + 0.04)), Vector3(PI / 2, 0, 0)), "steel")
			b.put(Geo.cyl(0.05, 0.05, 0.3, 8), T3(Vector3(0.3, h * 0.85, hw + 0.08), Vector3(0.6, 0, 0)), "steel")
			b.put(Geo.box(Vector3(0.3, 0.42, 1.5)), T3(Vector3(-back - 0.15, h * 0.5, 0)), "paint", true)
			b.put(Geo.box(Vector3(0.5, 0.04, 0.42)), T3(Vector3(-0.3, h * top + 0.02, 0.42)), "paint", true)
			for z: float in [-0.75, 0.75]:
				b.put(Geo.cyl(0.012, 0.012, 2.2, 4), T3(Vector3(-back + 0.15, h * top + 1.1, z)), "steel")
		"tiger2":
			# запасные траки на бортах башни, люк в корме, пистолетные лючки, крышка вентилятора
			for s: float in [1.0, -1.0]:
				for k in 4:
					var x := -0.35 - k * 0.24
					var sw := lerpf(hw * 0.66, hw, clampf((front - x) / (front + back * 0.86), 0.0, 1.0))
					b.put(Geo.box(Vector3(0.18, 0.4, 0.04)), T3(Vector3(x, h * 0.5, s * (_side_at(sw, top, 0.5) + 0.03)), Vector3(s * 0.36, 0, 0)), "steel", true)
			b.put(Geo.cyl(0.32, 0.32, 0.06, 16), T3(Vector3(-back * _side_at(1.0, top, 0.5) - 0.02, h * 0.5, 0), Vector3(0, 0, PI / 2)), "paint")
			b.put(Geo.cyl(0.14, 0.14, 0.05, 10), T3(Vector3(0.2, h * top + 0.02, 0.15)), "paint")
			b.put(Geo.box(Vector3(0.5, 0.05, 0.45)), T3(Vector3(-0.3, h * top + 0.02, 0.5)), "paint", true)
		"chaffee":
			# крупнокалиберный пулемёт на турели в корме крыши
			var m2 := _cyl_x(0.03, 0.03, 1.5, 6)
			b.put(m2[0], T3(Vector3(-0.55, h * top + 0.55, 0.35), m2[1] + Vector3(0, 0, 0.08)), "steel")
			b.put(Geo.box(Vector3(0.28, 0.15, 0.12)), T3(Vector3(-0.85, h * top + 0.48, 0.35)), "steel", true)
			b.put(Geo.cyl(0.03, 0.03, 0.45, 6), T3(Vector3(-0.85, h * top + 0.22, 0.35)), "steel")
			b.put(Geo.box(Vector3(0.12, 0.1, 0.12)), T3(Vector3(0.3, h * top + 0.05, 0.4)), "paint", true)


## Насколько сужается башня к высоте yf (доля высоты): для деталей на наклонных бортах.
static func _side_at(w: float, top: float, yf: float) -> float:
	return w * (1.0 + (top - 1.0) * yf)


static func _emblems(parent: Node3D, kind: String, pos: Vector3, size: float, tilt: float) -> void:
	var em := StandardMaterial3D.new()
	em.albedo_texture = emblem_texture(kind)
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	em.roughness = 0.8
	var g := Geo.Group.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size) * U
	for s: float in [1.0, -1.0]:
		var bs := Basis(Vector3.RIGHT, -tilt) if s > 0 else Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -tilt)
		g.add(q, Transform3D(bs, Vector3(pos.x, pos.y, s * pos.z) * U), em)
	g.commit(parent, false)
