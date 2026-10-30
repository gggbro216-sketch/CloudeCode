extends Node3D
## Погода: снегопад вокруг камеры (Сталинград), утренний туман у земли (Нормандия),
## дрожащее марево над раскалённой землёй у горизонта (Эль-Аламейн).
## Всё движется в шейдерах — процессор не тратится; снежинок и облаков немного, марево — только на высокой графике.

const D = preload("res://scripts/data.gd")
const TexLib = preload("res://scripts/textures.gd")

# Снежинки: в вершинах — их места в коробке вокруг начала координат и угол квадрата (UV).
# Коробка «надета» на камеру: снежинка, вылетевшая за край, появляется с другой стороны.
const SNOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec3 box = vec3(170.0, 110.0, 170.0);
uniform float fall = 9.0;
uniform vec2 wind = vec2(4.0, 1.5);
uniform float size = 0.42;
varying float fade;

void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 base = VERTEX;
	vec3 p = base + vec3(wind.x, -fall, wind.y) * TIME;
	// кружение
	p.x += sin(TIME * 1.1 + base.y * 0.7) * 1.2;
	p.z += cos(TIME * 0.9 + base.x * 0.5) * 1.2;
	p = mod(p - cam + box * 0.5, box) - box * 0.5 + cam;
	vec2 corner = UV * 2.0 - 1.0;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float d = length(p - cam);
	p += (right * corner.x + up * corner.y) * size * (1.0 + d * 0.012);
	fade = (1.0 - smoothstep(box.x * 0.32, box.x * 0.5, d)) * smoothstep(5.0, 14.0, d);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	ALBEDO = vec3(0.93, 0.95, 1.0);
	ALPHA = (1.0 - smoothstep(0.25, 1.0, length(c))) * fade * 0.9;
}
"""

# Туман: широкие пологие облака у самой земли. Вблизи камеры тают, чтобы не было видно краёв.
const MIST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D puff : filter_linear_mipmap;
uniform vec3 color : source_color = vec3(0.86, 0.87, 0.86);
uniform float strength = 0.5;
varying float fade;
varying float seed;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sz = length(MODEL_MATRIX[0].xyz);
	seed = INSTANCE_CUSTOM.x;
	center.x += sin(TIME * 0.035 + seed * 6.283) * 28.0;
	center.z += cos(TIME * 0.03 + seed * 4.0) * 18.0;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = normalize(vec3(cam.x - center.x, 0.0, cam.z - center.z));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec2 corner = UV * 2.0 - 1.0;
	vec3 p = center + right * corner.x * sz + vec3(0.0, 1.0, 0.0) * (corner.y + 0.7) * sz * 0.16;
	float d = distance(cam.xz, center.xz);
	fade = smoothstep(sz * 0.35, sz * 1.1, d);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}

void fragment() {
	float a = texture(puff, UV).a;
	ALBEDO = color;
	ALPHA = a * strength * fade * (0.7 + 0.3 * sin(TIME * 0.2 + seed * 9.0));
}
"""

# Марево: стенка-кольцо вокруг камеры у горизонта. Сквозь неё видно то, что дальше, —
# со сдвигом по шуму; ближние танки и дома перекрывают стенку и не дрожат.
const HAZE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform float strength = 0.006;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// дрожит узкая полоса у линии горизонта — там, где взгляд скользит над раскалённой землёй
	vec3 v = normalize(wp - CAMERA_POSITION_WORLD);
	float k = 1.0 - smoothstep(0.012, 0.06, abs(v.y + 0.008));
	vec2 n = texture(noise, vec2(UV.x * 48.0 - TIME * 0.03, v.y * 14.0 + TIME * 0.6)).rg - 0.5;
	vec3 col = texture(screen, SCREEN_UV + n * strength * k).rgb;
	col = mix(col, vec3(0.93, 0.88, 0.78), k * 0.06);
	ALBEDO = col;
	ALPHA = k;
}
"""

var kind := ""
var haze: MeshInstance3D
var battle


func setup(weather: String, b, hq: bool) -> void:
	kind = weather
	battle = b
	match kind:
		"snow":
			_snow(1500 if hq else 700)
		"mist":
			_mist(90 if hq else 40)
		"haze":
			if hq:
				_haze()


func _process(_delta: float) -> void:
	if haze and battle and battle.cam:
		var c: Vector3 = battle.cam.global_position
		haze.global_position = c


func _snow(count: int) -> void:
	var box := Vector3(170.0, 110.0, 170.0)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in count:
		var p := Vector3(rng.randf() * box.x, rng.randf() * box.y, rng.randf() * box.z)
		var b := verts.size()
		for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(p)
			uvs.append(c)
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sh := Shader.new()
	sh.code = SNOW_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("box", box)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# снежинки двигает шейдер — сетка всегда «в кадре»
	mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	add_child(mi)


func _mist(count: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	mm.mesh = q
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var x := rng.randf_range(-200.0, D.WS + 200.0)
		var z := rng.randf_range(-200.0, D.WS + 200.0)
		var sz := rng.randf_range(70.0, 150.0)
		# туман гуще в низинах: облака садятся на рельеф
		var y: float = battle.terra.height(x, z) + rng.randf_range(0.5, 4.0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sz, sz, sz)), Vector3(x, y, z)))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var sh := Shader.new()
	sh.code = MIST_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("puff", TexLib.puff_texture())
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	add_child(mmi)


func _haze() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 560.0
	cyl.bottom_radius = 560.0
	cyl.height = 500.0
	cyl.radial_segments = 32
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.05
	var img := n.get_seamless_image(128, 128, false, false, 0.1, true)
	var n2 := FastNoiseLite.new()
	n2.seed = 9
	n2.frequency = 0.05
	var img2 := n2.get_seamless_image(128, 128, false, false, 0.1, true)
	var rg := Image.create(128, 128, false, Image.FORMAT_RG8)
	for y in 128:
		for x in 128:
			rg.set_pixel(x, y, Color(img.get_pixel(x, y).r, img2.get_pixel(x, y).r, 0))
	var sh := Shader.new()
	sh.code = HAZE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise", ImageTexture.create_from_image(rg))
	m.render_priority = 10
	haze = MeshInstance3D.new()
	haze.mesh = cyl
	haze.material_override = m
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(haze)
