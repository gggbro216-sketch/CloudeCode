extends RefCounted
## Настройки графики: пресеты и отдельные параметры (хранятся в save.gfx).
##
## Сразу применяются чёткость 3D, лимит кадров, вертикальная синхронизация и сглаживание; тени —
## в ангаре сразу, в бою со следующего боя; остальное (трава, частицы, погода, следы, рельеф текстур,
## дальность прорисовки) — со следующего боя: это задаётся при сборке карты.

## Параметры по порядку показа: ключ, название, пояснение, значения, подписи значений.
const ITEMS := [
	["res", "Чёткость 3D", "Доля разрешения экрана, в которой рисуется 3D (интерфейс всегда чёткий). Главная настройка скорости.",
		[0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0], []],
	["fps", "Лимит кадров", "Не чаще стольких кадров в секунду. 30 — экономия батареи и нагрева.",
		[30, 45, 60, 90, 120, 0], ["30", "45", "60", "90", "120", "ПО ЭКРАНУ"]],
	["vsync", "Вертикальная синхронизация", "Без разрывов картинки; без неё чуть меньше задержка управления.",
		[1, 0], ["ВКЛ", "ВЫКЛ"]],
	["msaa", "Сглаживание", "Сглаживание краёв 3D (MSAA). 4× заметно дороже на телефоне.",
		[0, 1, 2], ["ВЫКЛ", "2×", "4×"]],
	["shadows", "Тени", "Качество теней от солнца (размер карты теней).",
		[0, 1, 2, 3], ["ВЫКЛ", "НИЗКИЕ", "СРЕДНИЕ", "ВЫСОКИЕ"]],
	["shadow_dist", "Дальность теней", "До какого расстояния от камеры видны тени.",
		[20, 30, 40, 55, 70], ["20 м", "30 м", "40 м", "55 м", "70 м"]],
	["obj_shadows", "Тени построек и деревьев", "Отбрасывают ли тень дома, деревья и рельеф (танки — всегда, если тени включены).",
		[0, 1], ["ВЫКЛ", "ВКЛ"]],
	["view", "Дальность прорисовки", "Дальность тумана и прорисовки травы и мелочи.",
		[0.6, 0.75, 0.9, 1.0, 1.15, 1.3], []],
	["grass", "Трава", "Сколько пучков травы на карте.",
		[0, 1, 2, 3], ["ВЫКЛ", "МАЛО", "СРЕДНЕ", "МНОГО"]],
	["particles", "Частицы", "Дым, пыль, огонь, искры и обломки.",
		[0, 1, 2], ["МАЛО", "СРЕДНЕ", "МНОГО"]],
	["weather", "Погода", "Снег, туман и марево на картах, где они есть.",
		[0, 1, 2], ["ВЫКЛ", "СЛАБАЯ", "ПОЛНАЯ"]],
	["decals", "Следы", "Следы гусениц, гарь от разрывов и пробоины на броне.",
		[0, 1, 2], ["ВЫКЛ", "МАЛО", "МНОГО"]],
	["infantry", "Пехота и пушки", "Отделения пехоты и противотанковые пушки в бою.",
		[0, 1, 2], ["ВЫКЛ", "МЕНЬШЕ", "ПОЛНЫЙ СОСТАВ"]],
	["decor", "Окружение", "Камни, трава и мешки с песком на карте.",
		[0, 1, 2], ["ВЫКЛ", "МАЛО", "МНОГО"]],
	["detail", "Рельеф текстур", "Объёмные кирпич, штукатурка и земля (карты нормалей).",
		[0, 1], ["ВЫКЛ", "ВКЛ"]],
	["fps_counter", "Счётчик кадров", "Число кадров в секунду в углу экрана в бою.",
		[0, 1], ["ВЫКЛ", "ВКЛ"]],
]

const PRESETS := {
	"low": {"res": 0.6, "fps": 30, "vsync": 1, "msaa": 0, "shadows": 0, "shadow_dist": 30, "obj_shadows": 0, "view": 0.75,
		"infantry": 1, "decor": 0, "grass": 0, "particles": 0, "weather": 1, "decals": 1, "detail": 0},
	"medium": {"res": 0.75, "fps": 60, "vsync": 1, "msaa": 0, "shadows": 1, "shadow_dist": 30, "obj_shadows": 0, "view": 0.9,
		"infantry": 2, "decor": 1, "grass": 1, "particles": 1, "weather": 1, "decals": 1, "detail": 0},
	"high": {"res": 0.85, "fps": 60, "vsync": 1, "msaa": 1, "shadows": 2, "shadow_dist": 40, "obj_shadows": 1, "view": 1.0,
		"infantry": 2, "decor": 2, "grass": 3, "particles": 2, "weather": 2, "decals": 2, "detail": 1},
	"ultra": {"res": 1.0, "fps": 0, "vsync": 1, "msaa": 2, "shadows": 3, "shadow_dist": 55, "obj_shadows": 1, "view": 1.15,
		"infantry": 2, "decor": 2, "grass": 3, "particles": 2, "weather": 2, "decals": 2, "detail": 1},
}
const PRESET_ORDER := ["low", "medium", "high", "ultra"]
const PRESET_NAMES := {"low": "НИЗКАЯ", "medium": "СРЕДНЯЯ", "high": "ВЫСОКАЯ", "ultra": "УЛЬТРА", "custom": "СВОЯ"}


## Настройки из сохранения: недостающее — из пресета (старые сохранения: hq, res, eco).
static func normalize(save: Dictionary) -> Dictionary:
	var g = save.get("gfx")
	if not (g is Dictionary):
		var base := "high" if save.get("hq", true) else "medium"
		g = PRESETS[base].duplicate()
		g.preset = base
		if save.has("res"):
			g.res = float(save.res)
		if save.get("eco", false):
			g.fps = 30
			g.preset = "custom"
		g.fps_counter = 0
	var out: Dictionary = {}
	var base_p: Dictionary = PRESETS.get(String(g.get("preset", "high")), PRESETS.high)
	for it in ITEMS:
		var k: String = it[0]
		var vals: Array = it[3]
		var v = g.get(k, base_p.get(k, vals[0]))
		out[k] = _nearest(vals, v)
	out.preset = String(g.get("preset", "custom"))
	if out.preset != "custom" and not _matches(out, out.preset):
		out.preset = "custom"
	return out


static func _nearest(vals: Array, v) -> Variant:
	var best = vals[0]
	var bd := INF
	for x in vals:
		var d := absf(float(x) - float(v))
		if d < bd:
			bd = d
			best = x
	return best


static func _matches(g: Dictionary, preset: String) -> bool:
	if not PRESETS.has(preset):
		return false
	var p: Dictionary = PRESETS[preset]
	for k in p:
		if absf(float(g.get(k, -1)) - float(p[k])) > 0.001:
			return false
	return true


## Применить пресет (счётчик кадров не трогаем — это не про качество).
static func apply_preset(g: Dictionary, preset: String) -> void:
	for k in PRESETS[preset]:
		g[k] = PRESETS[preset][k]
	g.preset = preset


## Шаг значения вперёд/назад; после ручной правки пресет — «своя», если не совпал с каким-то.
static func step(g: Dictionary, key: String, dir: int) -> void:
	for it in ITEMS:
		if it[0] != key:
			continue
		var vals: Array = it[3]
		var i := vals.find(_nearest(vals, g[key]))
		i = clampi(i + dir, 0, vals.size() - 1)
		g[key] = vals[i]
	g.preset = "custom"
	for p in PRESET_ORDER:
		if _matches(g, p):
			g.preset = p


static func label(key: String, v) -> String:
	for it in ITEMS:
		if it[0] != key:
			continue
		var vals: Array = it[3]
		var names: Array = it[4]
		if names.is_empty():
			return "%d %%" % roundi(float(v) * 100.0)
		var i := vals.find(_nearest(vals, v))
		return names[maxi(0, i)]
	return str(v)


## Размер карты теней по уровню.
static func shadow_size(level: int) -> int:
	return [1024, 1024, 2048, 4096][clampi(level, 0, 3)]


## Сразу: чёткость, кадры, синхронизация, сглаживание (вызывается из Main).
static func apply_now(vp: Viewport, g: Dictionary) -> void:
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(g.res)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(g.msaa), 0, 2)]
	Engine.max_fps = int(g.fps)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if int(g.vsync) != 0 else DisplayServer.VSYNC_DISABLED)
	RenderingServer.directional_shadow_atlas_set_size(shadow_size(int(g.shadows)), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][clampi(int(g.shadows), 0, 3)])


## Солнце по настройкам: тени, их дальность.
static func setup_sun(sun: DirectionalLight3D, g: Dictionary, upm: float) -> void:
	sun.shadow_enabled = int(g.shadows) > 0
	sun.directional_shadow_max_distance = float(g.shadow_dist) * upm
