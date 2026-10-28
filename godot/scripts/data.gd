extends RefCounted
## Справочники игры: танки, режимы, карты и общие константы.
## Характеристики танков заданы в реальных единицах (м, км/ч, °/с, л.с., т, мм)
## и переводятся в единицы карты через UPM.

const UPM := 7.5  # единиц карты в одном метре
const WS := 2200.0  # сторона игровой зоны (~290 м)
const RANGE := 1100.0  # дальность полёта снаряда
const GRAVITY := 9.81 * UPM  # ускорение свободного падения, ед/с²
const SHELL_SCALE := 2.2  # скорость снаряда в игре = м/с × это число (ед/с)
const TIME_LIMIT := 420.0  # 7 минут на бой
const SUP_GOAL := 600.0  # очки для победы в «Превосходстве»
const CAP_RATE := 3.5  # процентов захвата в секунду на танк (до трёх танков)

const ALLY := "6cd04f"
const FOE := "e2563c"
const AMBER := "f0b73a"

# kmh/rev — скорость вперёд/назад; turn/tspd — поворот корпуса/башни, °/с;
# hp — мощность двигателя, л.с.; mass — т; shell — начальная скорость снаряда, м/с;
# caliber/pen — калибр и бронепробиваемость, мм; disp — разброс на 100 м, м; aim — сведение, с;
# armor — [лоб, борт, корма корпуса, лоб, борт, корма башни], мм;
# slope/side_slope — наклон лобового/бортового листа от вертикали, °; elev — склонение и возвышение, °;
# spot — обзор, м; engine — тип двигателя для звука.
const TYPES := {
	"chaffee": {"short": "ЛТ", "name": "M24 Chaffee", "nation": "США", "cls": "Лёгкий танк",
		"hp": 700.0, "dmg": 110.0, "pen": 92.0, "caliber": 75.0, "reload": 2.4, "shell": 619.0,
		"kmh": 56.0, "rev": 20.0, "turn": 46.0, "tspd": 46.0, "power": 220.0, "mass": 18.4,
		"disp": 0.42, "aim": 1.7, "armor": [25, 25, 19, 38, 25, 25], "slope": 60.0, "side_slope": 0.0,
		"elev": [-10.0, 15.0], "spot": 72.0, "engine": "petrol", "len": 5.03, "wid": 2.95, "pref": 320.0},
	"t34": {"short": "СТ", "name": "Т-34-85", "nation": "СССР", "cls": "Средний танк",
		"hp": 980.0, "dmg": 160.0, "pen": 120.0, "caliber": 85.0, "reload": 3.2, "shell": 792.0,
		"kmh": 54.0, "rev": 18.0, "turn": 42.0, "tspd": 38.0, "power": 500.0, "mass": 32.0,
		"disp": 0.46, "aim": 2.1, "armor": [45, 45, 45, 90, 75, 52], "slope": 60.0, "side_slope": 40.0,
		"elev": [-5.0, 22.0], "spot": 64.0, "engine": "diesel", "len": 6.1, "wid": 3.0, "pref": 380.0},
	"pz4": {"short": "СТ", "name": "Pz.Kpfw. IV H", "nation": "Германия", "cls": "Средний танк",
		"hp": 900.0, "dmg": 135.0, "pen": 132.0, "caliber": 75.0, "reload": 2.8, "shell": 790.0,
		"kmh": 42.0, "rev": 16.0, "turn": 40.0, "tspd": 34.0, "power": 300.0, "mass": 25.7,
		"disp": 0.36, "aim": 1.9, "armor": [80, 30, 20, 50, 30, 30], "slope": 12.0, "side_slope": 0.0,
		"elev": [-8.0, 20.0], "spot": 65.0, "engine": "petrol", "len": 5.89, "wid": 2.88, "pref": 430.0},
	"tiger": {"short": "ТТ", "name": "Tiger I", "nation": "Германия", "cls": "Тяжёлый танк",
		"hp": 1500.0, "dmg": 240.0, "pen": 165.0, "caliber": 88.0, "reload": 4.6, "shell": 773.0,
		"kmh": 40.0, "rev": 14.0, "turn": 28.0, "tspd": 22.0, "power": 700.0, "mass": 57.0,
		"disp": 0.32, "aim": 2.4, "armor": [100, 80, 80, 100, 80, 80], "slope": 9.0, "side_slope": 0.0,
		"elev": [-8.0, 15.0], "spot": 62.0, "engine": "petrol", "len": 6.32, "wid": 3.56, "pref": 480.0},
	"is2": {"short": "ТТ", "name": "ИС-2", "nation": "СССР", "cls": "Тяжёлый танк",
		"hp": 1450.0, "dmg": 320.0, "pen": 160.0, "caliber": 122.0, "reload": 6.5, "shell": 781.0,
		"kmh": 37.0, "rev": 14.0, "turn": 30.0, "tspd": 24.0, "power": 520.0, "mass": 46.0,
		"disp": 0.52, "aim": 3.1, "armor": [120, 90, 60, 100, 90, 90], "slope": 60.0, "side_slope": 15.0,
		"elev": [-3.0, 20.0], "spot": 61.0, "engine": "diesel", "len": 6.77, "wid": 3.07, "pref": 420.0},
}

const MODES := {
	"standard": {"name": "Стандартный бой", "desc": "Уничтожьте врагов или захватите их базу"},
	"encounter": {"name": "Встречный бой", "desc": "Одна нейтральная база в центре карты"},
	"supremacy": {"name": "Превосходство", "desc": "Держите точки A, B, C. Нужно 600 очков"},
}

# Цвета земли для шейдера: трава/песок/снег (две тени), скала, дорога, грязь, гарь.
# grip — сопротивление грунта (1 — дорога), surf — материал поверхности для текстур.
const MAPS := {
	"prokhorovka": {"name": "Прохоровка", "desc": "Холмистые поля и деревня, лето 1943", "surf": "grass",
		"sky_top": "5f86b0", "sky_hor": "c4d0d2", "fog": "b9c4c4", "sun": "fff0d4", "sun_e": 1.05, "amb": 0.42,
		"g1": "4a5e2e", "g2": "75834a", "rock": "6f6a5c", "road": "7d6c4b", "dirt": "57472f", "scorch": "26221d",
		"dust": "8a7a5a", "mini": "3c4c2c", "relief": 26.0, "grip": 0.85},
	"alamein": {"name": "Эль-Аламейн", "desc": "Барханы и скалы Северной Африки, 1942", "surf": "sand",
		"sky_top": "7aa0c4", "sky_hor": "ddd3bd", "fog": "d6ccb6", "sun": "fff0d0", "sun_e": 1.1, "amb": 0.45,
		"g1": "a39072", "g2": "c2b08e", "rock": "8f7556", "road": "9c8766", "dirt": "8e7350", "scorch": "3a3028",
		"dust": "c8aa78", "mini": "a08250", "relief": 30.0, "grip": 0.74},
	"stalingrad": {"name": "Сталинград", "desc": "Руины зимнего города, 1942", "surf": "snow",
		"sky_top": "8a97a4", "sky_hor": "c6cbd0", "fog": "bcc2c7", "sun": "e8eef5", "sun_e": 0.75, "amb": 0.55,
		"g1": "c9d1d8", "g2": "eef2f5", "rock": "7d8186", "road": "75797d", "dirt": "5d5650", "scorch": "2a2826",
		"dust": "e6ebef", "mini": "9aa4ae", "relief": 7.0, "grip": 0.78},
}

const NAMES := ["Волк", "Ястреб", "Кобра", "Тигр", "Север", "Орёл", "Гром", "Лис", "Барс", "Шторм", "Сокол", "Беркут"]


## Производные величины в единицах карты.
static func derived(T: Dictionary) -> Dictionary:
	return {
		"speed": float(T.kmh) / 3.6 * UPM,
		"rev_speed": float(T.rev) / 3.6 * UPM,
		"turn": deg_to_rad(T.turn),
		"tspd": deg_to_rad(T.tspd),
		"shell_v": float(T.shell) * SHELL_SCALE,
		"disp": float(T.disp) / 100.0,  # рад: разброс в метрах на 100 м
		"spot": float(T.spot) * UPM,
		"slope": deg_to_rad(T.slope),
		"side_slope": deg_to_rad(T.side_slope),
		"elev": [deg_to_rad(T.elev[0]), deg_to_rad(T.elev[1])],
		"L": float(T.len) * UPM,
		"W": float(T.wid) * UPM,
		"accel": 2.4 * float(T.power) / float(T.mass),  # тяговооружённость → разгон, ед/с²
	}
