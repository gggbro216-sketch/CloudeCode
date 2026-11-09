extends RefCounted
## Справочники игры: танки, режимы, карты и общие константы.
## Характеристики танков заданы в реальных единицах (м, км/ч, °/с, л.с., т, мм)
## и переводятся в единицы карты через UPM.

const UPM := 7.5  # единиц карты в одном метре
const WS := 2860.0  # сторона игровой зоны (~380 м)
const RANGE := 1100.0  # дальность полёта снаряда
const GRAVITY := 9.81 * UPM  # ускорение свободного падения, ед/с²
const SHELL_SCALE := 2.2  # скорость снаряда в игре = м/с × это число (ед/с)
const TIME_LIMIT := 420.0  # 7 минут на бой
const SUP_GOAL := 600.0  # очки для победы в «Превосходстве»
const CAP_RATE := 2.2  # процентов захвата в секунду на танк (до трёх танков): тремя — 15 с
const SPEED_K := 0.8  # в игре танки едут на 20 % медленнее исторической скорости
const SPOT_K := 1.4  # обзор в игре на 40 % больше табличного: поле стало больше, бои дальше

const ALLY := "6cd04f"
const FOE := "e2563c"
const AMBER := "f0b73a"

# kmh/rev — скорость вперёд/назад; turn/tspd — поворот корпуса/башни, °/с;
# hp — мощность двигателя, л.с.; mass — т; shell — начальная скорость снаряда, м/с;
# caliber/pen — калибр и бронепробиваемость, мм; disp — разброс на 100 м, м; aim — сведение, с;
# armor — [лоб, борт, корма корпуса, лоб, борт, корма башни/рубки], мм;
# slope/side_slope — наклон лобового/бортового листа от вертикали, °; tslope — наклон лба башни, °;
# elev — склонение и возвышение, °; traverse — горизонтальная наводка в рубке ±°, только у САУ;
# stab — гиростабилизатор (доля, на которую он снижает разброс в движении);
# spot — обзор, м; engine — тип двигателя для звука.
# tier — уровень (III–VIII): по нему подбор боёв (±1) и цены;
# side — сторона (allies/axis); year — год вступления в бой; pts — боевой вес для подбора команд;
# freq — как часто встречался на фронте (вес при случайном выборе машин в команду);
# variants — модификации по годам: {год: поля, которые меняются}.
const TYPES := {
	"t34_76": {"short": "СТ", "name": "Т-34 обр. 1943", "tag": "Т-34/76", "nation": "СССР", "cls": "Средний танк",
		"tier": 5, "side": "allies", "year": 1942, "pts": 7, "freq": 3.0,
		"hp": 860.0, "dmg": 125.0, "pen": 86.0, "caliber": 76.2, "reload": 2.7, "shell": 662.0,
		"kmh": 54.0, "rev": 18.0, "turn": 44.0, "tspd": 34.0, "power": 500.0, "mass": 30.9,
		"disp": 0.47, "aim": 2.0, "armor": [45, 45, 40, 52, 52, 52], "slope": 60.0, "side_slope": 40.0,
		"elev": [-5.0, 25.0], "spot": 62.0, "engine": "diesel", "len": 5.92, "wid": 3.0, "pref": 330.0},
	"t34": {"short": "СТ", "name": "Т-34-85", "tag": "Т-34-85", "nation": "СССР", "cls": "Средний танк",
		"tier": 6, "side": "allies", "year": 1944, "pts": 8, "freq": 3.0,
		"hp": 980.0, "dmg": 160.0, "pen": 120.0, "caliber": 85.0, "reload": 3.2, "shell": 792.0,
		"kmh": 54.0, "rev": 18.0, "turn": 42.0, "tspd": 38.0, "power": 500.0, "mass": 32.0,
		"disp": 0.46, "aim": 2.1, "armor": [45, 45, 45, 90, 75, 52], "slope": 60.0, "side_slope": 40.0,
		"elev": [-5.0, 22.0], "spot": 64.0, "engine": "diesel", "len": 6.1, "wid": 3.0, "pref": 380.0},
	"kv1": {"short": "ТТ", "name": "КВ-1 обр. 1942", "tag": "КВ-1", "nation": "СССР", "cls": "Тяжёлый танк",
		"tier": 6, "side": "allies", "year": 1941, "pts": 8, "freq": 1.0,
		"hp": 1250.0, "dmg": 125.0, "pen": 86.0, "caliber": 76.2, "reload": 2.9, "shell": 662.0,
		"kmh": 35.0, "rev": 12.0, "turn": 26.0, "tspd": 22.0, "power": 600.0, "mass": 47.0,
		"disp": 0.48, "aim": 2.3, "armor": [75, 75, 60, 95, 90, 75], "slope": 30.0, "side_slope": 0.0,
		"tslope": 20.0, "elev": [-5.0, 25.0], "spot": 58.0, "engine": "diesel", "len": 6.75, "wid": 3.32, "pref": 280.0},
	"is2": {"short": "ТТ", "name": "ИС-2", "tag": "ИС-2", "nation": "СССР", "cls": "Тяжёлый танк",
		"tier": 8, "side": "allies", "year": 1944, "pts": 14, "freq": 1.0,
		"hp": 1450.0, "dmg": 320.0, "pen": 160.0, "caliber": 122.0, "reload": 6.5, "shell": 781.0,
		"kmh": 37.0, "rev": 14.0, "turn": 30.0, "tspd": 24.0, "power": 520.0, "mass": 46.0,
		"disp": 0.52, "aim": 3.1, "armor": [120, 90, 60, 100, 90, 90], "slope": 60.0, "side_slope": 15.0,
		"elev": [-3.0, 20.0], "spot": 61.0, "engine": "diesel", "len": 6.77, "wid": 3.07, "pref": 420.0},
	"sherman": {"short": "СТ", "name": "M4A1 Sherman", "tag": "Sherman", "nation": "США", "cls": "Средний танк",
		"tier": 5, "side": "allies", "year": 1942, "pts": 8, "freq": 2.0,
		"hp": 920.0, "dmg": 120.0, "pen": 92.0, "caliber": 75.0, "reload": 2.6, "shell": 619.0,
		"kmh": 39.0, "rev": 14.0, "turn": 36.0, "tspd": 42.0, "power": 400.0, "mass": 30.3,
		"disp": 0.4, "aim": 1.9, "stab": 0.5, "armor": [51, 38, 38, 76, 51, 51], "slope": 56.0, "side_slope": 0.0,
		"elev": [-10.0, 25.0], "spot": 64.0, "engine": "petrol", "len": 5.84, "wid": 2.62, "pref": 340.0},
	"firefly": {"short": "СТ", "name": "Sherman Firefly VC", "tag": "Firefly", "nation": "Великобритания", "cls": "Средний танк",
		"tier": 6, "side": "allies", "year": 1944, "pts": 9, "freq": 1.0,
		"hp": 930.0, "dmg": 150.0, "pen": 165.0, "caliber": 76.2, "reload": 3.3, "shell": 884.0,
		"kmh": 40.0, "rev": 14.0, "turn": 34.0, "tspd": 38.0, "power": 425.0, "mass": 35.3,
		"disp": 0.36, "aim": 2.2, "armor": [51, 38, 38, 76, 51, 51], "slope": 56.0, "side_slope": 0.0,
		"elev": [-5.0, 20.0], "spot": 64.0, "engine": "petrol", "len": 6.05, "wid": 2.62, "pref": 420.0},
	"cromwell": {"short": "СТ", "name": "Cromwell Mk IV", "tag": "Cromwell", "nation": "Великобритания", "cls": "Крейсерский танк",
		"tier": 5, "side": "allies", "year": 1944, "pts": 7, "freq": 2.0,
		"hp": 880.0, "dmg": 120.0, "pen": 92.0, "caliber": 75.0, "reload": 2.5, "shell": 619.0,
		"kmh": 52.0, "rev": 20.0, "turn": 46.0, "tspd": 40.0, "power": 600.0, "mass": 27.9,
		"disp": 0.4, "aim": 1.9, "armor": [64, 32, 32, 76, 63, 57], "slope": 5.0, "side_slope": 0.0,
		"tslope": 0.0, "elev": [-12.0, 20.0], "spot": 66.0, "engine": "petrol", "len": 6.35, "wid": 2.91, "pref": 330.0},
	"chaffee": {"short": "ЛТ", "name": "M24 Chaffee", "tag": "Chaffee", "nation": "США", "cls": "Лёгкий танк",
		"tier": 5, "side": "allies", "year": 1944, "pts": 5, "freq": 1.0,
		"hp": 700.0, "dmg": 110.0, "pen": 92.0, "caliber": 75.0, "reload": 2.4, "shell": 619.0,
		"kmh": 56.0, "rev": 20.0, "turn": 46.0, "tspd": 46.0, "power": 220.0, "mass": 18.4,
		"disp": 0.42, "aim": 1.7, "armor": [25, 25, 19, 38, 25, 25], "slope": 60.0, "side_slope": 0.0,
		"elev": [-10.0, 15.0], "spot": 72.0, "engine": "petrol", "len": 5.03, "wid": 2.95, "pref": 320.0},
	"a10": {"short": "СТ", "name": "Cruiser Mk. II (A10)", "tag": "A10", "nation": "Великобритания", "cls": "Крейсерский танк",
		"tier": 3, "side": "allies", "year": 1940, "pts": 5, "freq": 1.5,
		"hp": 640.0, "dmg": 70.0, "pen": 64.0, "caliber": 40.0, "reload": 1.8, "shell": 792.0,
		"kmh": 26.0, "rev": 9.0, "turn": 36.0, "tspd": 30.0, "power": 150.0, "mass": 14.3,
		"disp": 0.37, "aim": 1.8, "armor": [30, 30, 14, 30, 30, 30], "slope": 30.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-12.0, 20.0], "spot": 60.0, "engine": "petrol", "len": 5.51, "wid": 2.54, "pref": 300.0},
	"pz3": {"short": "СТ", "name": "Pz.Kpfw. III Ausf. L", "tag": "Pz III L", "nation": "Германия", "cls": "Средний танк",
		"tier": 4, "side": "axis", "year": 1942, "pts": 5, "freq": 2.5,
		"hp": 780.0, "dmg": 90.0, "pen": 82.0, "caliber": 50.0, "reload": 2.2, "shell": 835.0,
		"kmh": 40.0, "rev": 16.0, "turn": 40.0, "tspd": 30.0, "power": 300.0, "mass": 21.5,
		"disp": 0.36, "aim": 1.8, "armor": [70, 30, 50, 57, 30, 30], "slope": 9.0, "side_slope": 0.0,
		"elev": [-10.0, 20.0], "spot": 64.0, "engine": "petrol", "len": 5.52, "wid": 2.95, "pref": 380.0},
	"pz4": {"short": "СТ", "name": "Pz.Kpfw. IV Ausf. G", "tag": "Pz IV G", "nation": "Германия", "cls": "Средний танк",
		"tier": 5, "side": "axis", "year": 1942, "pts": 7, "freq": 2.5,
		"variants": {1944: {"name": "Pz.Kpfw. IV Ausf. H", "tag": "Pz IV H", "mass": 25.7, "kmh": 38.0, "pts": 6},
			1945: {"name": "Pz.Kpfw. IV Ausf. J", "tag": "Pz IV J", "mass": 25.0, "kmh": 38.0, "tspd": 24.0, "pts": 6}},
		"hp": 900.0, "dmg": 120.0, "pen": 132.0, "caliber": 75.0, "reload": 2.8, "shell": 790.0,
		"kmh": 40.0, "rev": 16.0, "turn": 40.0, "tspd": 34.0, "power": 300.0, "mass": 23.5,
		"disp": 0.36, "aim": 1.9, "armor": [80, 30, 20, 50, 30, 30], "slope": 12.0, "side_slope": 0.0,
		"elev": [-8.0, 20.0], "spot": 65.0, "engine": "petrol", "len": 5.89, "wid": 2.88, "pref": 430.0},
	"stug": {"short": "САУ", "name": "StuG III Ausf. G", "tag": "StuG III", "nation": "Германия", "cls": "Штурмовое орудие",
		"tier": 5, "side": "axis", "year": 1942, "pts": 7, "freq": 2.0, "variants": {1944: {"pts": 6}},
		"hp": 850.0, "dmg": 120.0, "pen": 132.0, "caliber": 75.0, "reload": 2.9, "shell": 790.0,
		"kmh": 40.0, "rev": 14.0, "turn": 38.0, "tspd": 14.0, "power": 300.0, "mass": 23.9,
		"disp": 0.34, "aim": 1.9, "armor": [80, 30, 50, 80, 30, 30], "slope": 21.0, "side_slope": 0.0,
		"tslope": 10.0, "traverse": 10.0, "elev": [-6.0, 20.0], "spot": 60.0, "engine": "petrol",
		"len": 5.4, "wid": 2.95, "pref": 420.0},
	"panther": {"short": "СТ", "name": "Pz.Kpfw. V Panther Ausf. D", "tag": "Panther D", "nation": "Германия", "cls": "Средний танк",
		"tier": 7, "side": "axis", "year": 1943, "pts": 9, "freq": 1.2,
		"variants": {1944: {"name": "Pz.Kpfw. V Panther Ausf. A", "tag": "Panther A", "tspd": 26.0, "pts": 8},
			1945: {"name": "Pz.Kpfw. V Panther Ausf. G", "tag": "Panther G", "tspd": 26.0, "pts": 8,
				"armor": [80, 50, 40, 110, 45, 45], "side_slope": 30.0}},
		"hp": 1300.0, "dmg": 135.0, "pen": 185.0, "caliber": 75.0, "reload": 3.4, "shell": 925.0,
		"kmh": 46.0, "rev": 12.0, "turn": 32.0, "tspd": 22.0, "power": 700.0, "mass": 44.8,
		"disp": 0.3, "aim": 2.3, "armor": [80, 40, 40, 100, 45, 45], "slope": 55.0, "side_slope": 40.0,
		"tslope": 12.0, "elev": [-8.0, 18.0], "spot": 66.0, "engine": "petrol", "len": 6.87, "wid": 3.27, "pref": 460.0},
	"tiger2": {"short": "ТТ", "name": "Pz.Kpfw. Tiger Ausf. B", "tag": "Tiger II", "nation": "Германия", "cls": "Тяжёлый танк",
		"tier": 8, "side": "axis", "year": 1944, "pts": 13, "freq": 0.4,
		"hp": 1800.0, "dmg": 240.0, "pen": 230.0, "caliber": 88.0, "reload": 5.0, "shell": 1000.0,
		"kmh": 38.0, "rev": 12.0, "turn": 24.0, "tspd": 18.0, "power": 700.0, "mass": 69.8,
		"disp": 0.28, "aim": 2.5, "armor": [150, 80, 80, 180, 80, 80], "slope": 50.0, "side_slope": 25.0,
		"tslope": 9.0, "elev": [-8.0, 15.0], "spot": 64.0, "engine": "petrol", "len": 7.38, "wid": 3.75, "pref": 500.0},
	"tiger": {"short": "ТТ", "name": "Tiger I", "tag": "Tiger I", "nation": "Германия", "cls": "Тяжёлый танк",
		"tier": 6, "side": "axis", "year": 1942, "pts": 14, "freq": 0.6, "variants": {1944: {"pts": 12}},
		"hp": 1500.0, "dmg": 240.0, "pen": 165.0, "caliber": 88.0, "reload": 4.6, "shell": 773.0,
		"kmh": 40.0, "rev": 14.0, "turn": 28.0, "tspd": 22.0, "power": 700.0, "mass": 57.0,
		"disp": 0.32, "aim": 2.4, "armor": [100, 80, 80, 100, 80, 80], "slope": 9.0, "side_slope": 0.0,
		"elev": [-8.0, 15.0], "spot": 62.0, "engine": "petrol", "len": 6.32, "wid": 3.56, "pref": 480.0},
	"m13_40": {"short": "СТ", "name": "Carro Armato M13/40", "tag": "M13/40", "nation": "Италия", "cls": "Средний танк",
		"tier": 3, "side": "axis", "year": 1940, "pts": 3, "freq": 2.0,
		"hp": 620.0, "dmg": 70.0, "pen": 55.0, "caliber": 47.0, "reload": 2.2, "shell": 630.0,
		"kmh": 32.0, "rev": 10.0, "turn": 38.0, "tspd": 26.0, "power": 125.0, "mass": 14.0,
		"disp": 0.45, "aim": 2.0, "armor": [30, 25, 25, 40, 25, 25], "slope": 20.0, "side_slope": 0.0,
		"tslope": 15.0, "elev": [-10.0, 20.0], "spot": 58.0, "engine": "diesel", "len": 4.92, "wid": 2.2, "pref": 300.0},
	"jagdpanther": {"short": "ПТ", "name": "Jagdpanther", "tag": "Jagdpanther", "nation": "Германия", "cls": "Истребитель танков",
		"tier": 7, "side": "axis", "year": 1944, "pts": 9, "freq": 0.6,
		"hp": 1350.0, "dmg": 240.0, "pen": 230.0, "caliber": 88.0, "reload": 5.2, "shell": 1000.0,
		"kmh": 46.0, "rev": 12.0, "turn": 30.0, "tspd": 14.0, "power": 700.0, "mass": 45.5,
		"disp": 0.29, "aim": 2.3, "armor": [80, 50, 40, 80, 50, 40], "slope": 55.0, "side_slope": 30.0,
		"tslope": 55.0, "traverse": 11.0, "elev": [-8.0, 14.0], "spot": 60.0, "engine": "petrol",
		"len": 6.87, "wid": 3.27, "pref": 520.0},
	"su100": {"short": "ПТ", "name": "СУ-100", "tag": "СУ-100", "nation": "СССР", "cls": "Самоходная установка",
		"tier": 7, "side": "allies", "year": 1944, "pts": 9, "freq": 1.0,
		"hp": 1150.0, "dmg": 250.0, "pen": 175.0, "caliber": 100.0, "reload": 6.0, "shell": 895.0,
		"kmh": 48.0, "rev": 15.0, "turn": 38.0, "tspd": 14.0, "power": 500.0, "mass": 31.6,
		"disp": 0.42, "aim": 2.4, "armor": [75, 45, 40, 75, 45, 40], "slope": 50.0, "side_slope": 20.0,
		"tslope": 50.0, "traverse": 8.0, "elev": [-2.0, 17.0], "spot": 62.0, "engine": "diesel",
		"len": 6.1, "wid": 3.0, "pref": 460.0},
	"pz38t": {"short": "ЛТ", "name": "Pz.Kpfw. 38(t) Ausf. E", "tag": "Pz 38(t)", "nation": "Германия", "cls": "Лёгкий танк",
		"tier": 3, "side": "axis", "year": 1939, "pts": 4, "freq": 1.5,
		"hp": 560.0, "dmg": 50.0, "pen": 64.0, "caliber": 37.0, "reload": 1.6, "shell": 750.0,
		"kmh": 42.0, "rev": 14.0, "turn": 44.0, "tspd": 30.0, "power": 125.0, "mass": 9.85,
		"disp": 0.4, "aim": 1.7, "armor": [50, 30, 22, 50, 30, 22], "slope": 15.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-6.0, 25.0], "spot": 60.0, "engine": "petrol", "len": 4.61, "wid": 2.14, "pref": 300.0},
	"l6_40": {"short": "ЛТ", "name": "Carro Armato L6/40", "tag": "L6/40", "nation": "Италия", "cls": "Лёгкий танк",
		"tier": 3, "side": "axis", "year": 1941, "pts": 3, "freq": 1.5,
		"hp": 480.0, "dmg": 30.0, "pen": 36.0, "caliber": 20.0, "reload": 0.6, "shell": 840.0,
		"kmh": 42.0, "rev": 14.0, "turn": 46.0, "tspd": 36.0, "power": 68.0, "mass": 6.8,
		"disp": 0.42, "aim": 1.4, "armor": [30, 15, 15, 40, 15, 15], "slope": 10.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-12.0, 20.0], "spot": 62.0, "engine": "petrol", "len": 3.82, "wid": 1.86, "pref": 260.0},
	"m15_42": {"short": "СТ", "name": "Carro Armato M15/42", "tag": "M15/42", "nation": "Италия", "cls": "Средний танк",
		"tier": 4, "side": "axis", "year": 1943, "pts": 5, "freq": 1.5,
		"hp": 700.0, "dmg": 75.0, "pen": 63.0, "caliber": 47.0, "reload": 2.0, "shell": 830.0,
		"kmh": 38.0, "rev": 12.0, "turn": 38.0, "tspd": 26.0, "power": 190.0, "mass": 15.5,
		"disp": 0.42, "aim": 1.9, "armor": [42, 25, 25, 45, 25, 25], "slope": 20.0, "side_slope": 0.0,
		"tslope": 15.0, "elev": [-10.0, 20.0], "spot": 60.0, "engine": "petrol", "len": 5.06, "wid": 2.23, "pref": 320.0},
	"hetzer": {"short": "ПТ", "name": "Jagdpanzer 38(t) Hetzer", "tag": "Hetzer", "nation": "Германия", "cls": "Истребитель танков",
		"tier": 4, "side": "axis", "year": 1944, "pts": 6, "freq": 1.2,
		"hp": 720.0, "dmg": 120.0, "pen": 125.0, "caliber": 75.0, "reload": 3.0, "shell": 750.0,
		"kmh": 42.0, "rev": 14.0, "turn": 34.0, "tspd": 12.0, "power": 160.0, "mass": 15.75,
		"disp": 0.36, "aim": 2.0, "armor": [60, 20, 20, 60, 20, 20], "slope": 60.0, "side_slope": 40.0,
		"tslope": 60.0, "traverse": 8.0, "elev": [-6.0, 12.0], "spot": 54.0, "engine": "petrol", "len": 4.87, "wid": 2.63, "pref": 400.0},
	"nashorn": {"short": "ПТ", "name": "Nashorn", "tag": "Nashorn", "nation": "Германия", "cls": "Истребитель танков",
		"tier": 6, "side": "axis", "year": 1943, "pts": 7, "freq": 0.8,
		"hp": 900.0, "dmg": 240.0, "pen": 210.0, "caliber": 88.0, "reload": 5.0, "shell": 1000.0,
		"kmh": 40.0, "rev": 12.0, "turn": 34.0, "tspd": 12.0, "power": 300.0, "mass": 24.0,
		"disp": 0.3, "aim": 2.3, "armor": [30, 20, 10, 10, 10, 10], "slope": 25.0, "side_slope": 0.0,
		"tslope": 30.0, "traverse": 15.0, "elev": [-5.0, 20.0], "spot": 62.0, "engine": "petrol", "len": 6.0, "wid": 2.95, "pref": 560.0},
	"ferdinand": {"short": "ПТ", "name": "Ferdinand", "tag": "Ferdinand", "nation": "Германия", "cls": "Истребитель танков",
		"tier": 8, "side": "axis", "year": 1943, "pts": 13, "freq": 0.4,
		"hp": 1650.0, "dmg": 240.0, "pen": 230.0, "caliber": 88.0, "reload": 5.0, "shell": 1000.0,
		"kmh": 30.0, "rev": 8.0, "turn": 22.0, "tspd": 10.0, "power": 600.0, "mass": 65.0,
		"disp": 0.28, "aim": 2.4, "armor": [200, 80, 80, 200, 80, 80], "slope": 30.0, "side_slope": 0.0,
		"tslope": 30.0, "traverse": 14.0, "elev": [-8.0, 14.0], "spot": 60.0, "engine": "petrol", "len": 7.05, "wid": 3.38, "pref": 560.0},
	"jagdtiger": {"short": "ПТ", "name": "Jagdtiger", "tag": "Jagdtiger", "nation": "Германия", "cls": "Истребитель танков",
		"tier": 8, "side": "axis", "year": 1944, "pts": 17, "freq": 0.3,
		"hp": 2000.0, "dmg": 490.0, "pen": 250.0, "caliber": 128.0, "reload": 9.0, "shell": 920.0,
		"kmh": 34.0, "rev": 10.0, "turn": 20.0, "tspd": 10.0, "power": 700.0, "mass": 71.7,
		"disp": 0.3, "aim": 2.6, "armor": [150, 80, 80, 250, 80, 80], "slope": 50.0, "side_slope": 25.0,
		"tslope": 15.0, "traverse": 10.0, "elev": [-7.0, 15.0], "spot": 62.0, "engine": "petrol", "len": 7.8, "wid": 3.63, "pref": 600.0},
	"stuart": {"short": "ЛТ", "name": "M3 Stuart", "tag": "Stuart", "nation": "США", "cls": "Лёгкий танк",
		"tier": 3, "side": "allies", "year": 1941, "pts": 5, "freq": 2.0,
		"hp": 600.0, "dmg": 55.0, "pen": 53.0, "caliber": 37.0, "reload": 1.5, "shell": 884.0,
		"kmh": 58.0, "rev": 18.0, "turn": 48.0, "tspd": 45.0, "power": 250.0, "mass": 12.7,
		"disp": 0.4, "aim": 1.6, "stab": 0.4, "armor": [38, 25, 25, 38, 25, 25], "slope": 20.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-10.0, 20.0], "spot": 64.0, "engine": "petrol", "len": 4.53, "wid": 2.24, "pref": 300.0},
	"lee": {"short": "СТ", "name": "M3 Lee", "tag": "M3 Lee", "nation": "США", "cls": "Средний танк",
		"tier": 4, "side": "allies", "year": 1941, "pts": 6, "freq": 1.5,
		"hp": 820.0, "dmg": 110.0, "pen": 88.0, "caliber": 75.0, "reload": 2.8, "shell": 619.0,
		"kmh": 39.0, "rev": 13.0, "turn": 34.0, "tspd": 20.0, "power": 340.0, "mass": 27.0,
		"disp": 0.44, "aim": 2.0, "stab": 0.3, "armor": [51, 38, 38, 51, 38, 38], "slope": 30.0, "side_slope": 0.0,
		"tslope": 10.0, "traverse": 15.0, "elev": [-9.0, 20.0], "spot": 62.0, "engine": "petrol", "len": 5.64, "wid": 2.72, "pref": 320.0},
	"churchill": {"short": "ТТ", "name": "Churchill VII", "tag": "Churchill", "nation": "Великобритания", "cls": "Пехотный танк",
		"tier": 6, "side": "allies", "year": 1944, "pts": 9, "freq": 1.0,
		"hp": 1300.0, "dmg": 120.0, "pen": 92.0, "caliber": 75.0, "reload": 2.6, "shell": 619.0,
		"kmh": 21.0, "rev": 8.0, "turn": 26.0, "tspd": 20.0, "power": 350.0, "mass": 40.6,
		"disp": 0.4, "aim": 2.0, "armor": [152, 95, 50, 152, 95, 95], "slope": 10.0, "side_slope": 0.0,
		"tslope": 0.0, "elev": [-12.0, 20.0], "spot": 60.0, "engine": "petrol", "len": 7.44, "wid": 3.25, "pref": 260.0},
	"comet": {"short": "СТ", "name": "Comet I", "tag": "Comet", "nation": "Великобритания", "cls": "Крейсерский танк",
		"tier": 7, "side": "allies", "year": 1945, "pts": 9, "freq": 0.8,
		"hp": 1150.0, "dmg": 150.0, "pen": 160.0, "caliber": 76.2, "reload": 3.0, "shell": 785.0,
		"kmh": 51.0, "rev": 18.0, "turn": 42.0, "tspd": 40.0, "power": 600.0, "mass": 32.7,
		"disp": 0.34, "aim": 2.0, "armor": [76, 43, 32, 102, 64, 57], "slope": 10.0, "side_slope": 0.0,
		"tslope": 5.0, "elev": [-12.0, 20.0], "spot": 66.0, "engine": "petrol", "len": 6.55, "wid": 3.05, "pref": 400.0},
	"kv2": {"short": "ТТ", "name": "КВ-2", "tag": "КВ-2", "nation": "СССР", "cls": "Тяжёлый танк",
		"tier": 7, "side": "allies", "year": 1940, "pts": 11, "freq": 0.6,
		"hp": 1450.0, "dmg": 500.0, "pen": 110.0, "caliber": 152.0, "reload": 14.0, "shell": 436.0,
		"kmh": 26.0, "rev": 8.0, "turn": 22.0, "tspd": 12.0, "power": 600.0, "mass": 52.0,
		"disp": 0.6, "aim": 3.6, "armor": [75, 75, 60, 75, 75, 75], "slope": 30.0, "side_slope": 0.0,
		"tslope": 0.0, "elev": [-3.0, 18.0], "spot": 58.0, "engine": "diesel", "len": 6.79, "wid": 3.32, "pref": 260.0},
	"su85": {"short": "ПТ", "name": "СУ-85", "tag": "СУ-85", "nation": "СССР", "cls": "Самоходная установка",
		"tier": 6, "side": "allies", "year": 1943, "pts": 7, "freq": 1.0,
		"hp": 900.0, "dmg": 160.0, "pen": 120.0, "caliber": 85.0, "reload": 3.2, "shell": 792.0,
		"kmh": 55.0, "rev": 18.0, "turn": 42.0, "tspd": 14.0, "power": 500.0, "mass": 29.6,
		"disp": 0.42, "aim": 2.2, "armor": [45, 45, 45, 60, 45, 45], "slope": 50.0, "side_slope": 20.0,
		"tslope": 50.0, "traverse": 10.0, "elev": [-5.0, 25.0], "spot": 62.0, "engine": "diesel", "len": 6.15, "wid": 3.0, "pref": 420.0},
	"luchs": {"short": "ЛТ", "name": "Pz.Kpfw. II Ausf. L Luchs", "tag": "Luchs", "nation": "Германия", "cls": "Лёгкий танк",
		"tier": 4, "side": "axis", "year": 1943, "pts": 4, "freq": 0.8,
		"hp": 640.0, "dmg": 30.0, "pen": 46.0, "caliber": 20.0, "reload": 0.55, "shell": 900.0,
		"kmh": 60.0, "rev": 18.0, "turn": 50.0, "tspd": 40.0, "power": 180.0, "mass": 11.8,
		"disp": 0.4, "aim": 1.4, "armor": [30, 20, 20, 30, 20, 20], "slope": 10.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-9.0, 18.0], "spot": 72.0, "engine": "petrol", "len": 4.63, "wid": 2.48, "pref": 280.0},
	"tiger_p": {"short": "ТТ", "name": "Panzerkampfwagen VI Tiger (P)", "tag": "Tiger (P)", "nation": "Германия", "cls": "Тяжёлый танк",
		"tier": 7, "side": "axis", "year": 1943, "pts": 14, "freq": 0.3,
		"hp": 1550.0, "dmg": 240.0, "pen": 165.0, "caliber": 88.0, "reload": 4.6, "shell": 773.0,
		"kmh": 35.0, "rev": 10.0, "turn": 26.0, "tspd": 18.0, "power": 620.0, "mass": 59.0,
		"disp": 0.34, "aim": 2.3, "armor": [200, 80, 80, 100, 80, 80], "slope": 30.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-8.0, 15.0], "spot": 62.0, "engine": "petrol", "len": 6.7, "wid": 3.14, "pref": 460.0},
	"pz4f2": {"short": "СТ", "name": "Pz.Kpfw. IV Ausf. F2", "tag": "Pz IV F2", "nation": "Германия", "cls": "Средний танк",
		"tier": 5, "side": "axis", "year": 1942, "pts": 5, "freq": 1.5,
		"hp": 860.0, "dmg": 120.0, "pen": 110.0, "caliber": 75.0, "reload": 2.8, "shell": 740.0,
		"kmh": 40.0, "rev": 12.0, "turn": 38.0, "tspd": 18.0, "power": 300.0, "mass": 23.6,
		"disp": 0.38, "aim": 2.0, "armor": [50, 30, 20, 50, 30, 30], "slope": 10.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-8.0, 20.0], "spot": 64.0, "engine": "petrol", "len": 5.92, "wid": 2.88, "pref": 420.0},
	"p26": {"short": "СТ", "name": "Carro Armato P26/40", "tag": "P26/40", "nation": "Италия", "cls": "Средний танк",
		"tier": 5, "side": "axis", "year": 1943, "pts": 7, "freq": 0.6,
		"hp": 900.0, "dmg": 120.0, "pen": 92.0, "caliber": 75.0, "reload": 2.8, "shell": 700.0,
		"kmh": 40.0, "rev": 13.0, "turn": 32.0, "tspd": 22.0, "power": 330.0, "mass": 26.0,
		"disp": 0.42, "aim": 2.1, "armor": [50, 40, 40, 60, 45, 45], "slope": 45.0, "side_slope": 0.0,
		"tslope": 20.0, "elev": [-10.0, 20.0], "spot": 62.0, "engine": "diesel", "len": 5.8, "wid": 2.8, "pref": 360.0},
	"turan": {"short": "СТ", "name": "40M Turán", "tag": "Turán", "nation": "Венгрия", "cls": "Средний танк",
		"tier": 4, "side": "axis", "year": 1942, "pts": 6, "freq": 1.2,
		"hp": 760.0, "dmg": 110.0, "pen": 70.0, "caliber": 75.0, "reload": 2.6, "shell": 450.0,
		"kmh": 47.0, "rev": 14.0, "turn": 40.0, "tspd": 24.0, "power": 260.0, "mass": 18.2,
		"disp": 0.44, "aim": 2.0, "armor": [50, 25, 25, 50, 25, 25], "slope": 20.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-10.0, 25.0], "spot": 62.0, "engine": "petrol", "len": 5.55, "wid": 2.44, "pref": 320.0},
	"m10": {"short": "ПТ", "name": "3in. GMC M10 Wolverine", "tag": "M10", "nation": "США", "cls": "Истребитель танков",
		"tier": 5, "side": "allies", "year": 1942, "pts": 7, "freq": 1.0,
		"hp": 880.0, "dmg": 140.0, "pen": 115.0, "caliber": 76.2, "reload": 3.2, "shell": 792.0,
		"kmh": 48.0, "rev": 14.0, "turn": 36.0, "tspd": 14.0, "power": 375.0, "mass": 29.6,
		"disp": 0.38, "aim": 2.2, "armor": [57, 25, 19, 57, 25, 25], "slope": 55.0, "side_slope": 38.0,
		"tslope": 45.0, "elev": [-10.0, 19.0], "spot": 62.0, "engine": "diesel", "len": 5.97, "wid": 3.05, "pref": 440.0},
	"easy8": {"short": "СТ", "name": "M4A3E8 Sherman", "tag": "M4A3E8", "nation": "США", "cls": "Средний танк",
		"tier": 6, "side": "allies", "year": 1944, "pts": 8, "freq": 1.5,
		"hp": 1000.0, "dmg": 140.0, "pen": 128.0, "caliber": 76.2, "reload": 3.0, "shell": 810.0,
		"kmh": 48.0, "rev": 16.0, "turn": 40.0, "tspd": 30.0, "power": 500.0, "mass": 33.6,
		"disp": 0.36, "aim": 2.0, "stab": 0.3, "armor": [64, 38, 38, 89, 64, 64], "slope": 47.0, "side_slope": 0.0,
		"tslope": 30.0, "elev": [-10.0, 25.0], "spot": 64.0, "engine": "petrol", "len": 6.0, "wid": 2.99, "pref": 400.0},
	"pershing": {"short": "ТТ", "name": "Heavy Tank M26 Pershing", "tag": "Pershing", "nation": "США", "cls": "Тяжёлый танк",
		"tier": 8, "side": "allies", "year": 1945, "pts": 12, "freq": 0.4,
		"hp": 1600.0, "dmg": 240.0, "pen": 170.0, "caliber": 90.0, "reload": 4.6, "shell": 853.0,
		"kmh": 40.0, "rev": 14.0, "turn": 34.0, "tspd": 24.0, "power": 500.0, "mass": 41.9,
		"disp": 0.34, "aim": 2.2, "armor": [102, 76, 51, 102, 76, 76], "slope": 46.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-10.0, 20.0], "spot": 64.0, "engine": "petrol", "len": 6.33, "wid": 3.51, "pref": 450.0},
	"grant": {"short": "СТ", "name": "Medium Tank M3 Grant", "tag": "Grant", "nation": "Великобритания", "cls": "Средний танк",
		"tier": 4, "side": "allies", "year": 1942, "pts": 6, "freq": 1.2,
		"hp": 840.0, "dmg": 110.0, "pen": 88.0, "caliber": 75.0, "reload": 2.8, "shell": 619.0,
		"kmh": 39.0, "rev": 13.0, "turn": 34.0, "tspd": 20.0, "power": 340.0, "mass": 27.2,
		"disp": 0.44, "aim": 2.0, "stab": 0.3, "armor": [51, 38, 38, 57, 51, 51], "slope": 30.0, "side_slope": 0.0,
		"tslope": 10.0, "traverse": 15.0, "elev": [-9.0, 20.0], "spot": 62.0, "engine": "petrol", "len": 5.64, "wid": 2.72, "pref": 320.0},
	"t70": {"short": "ЛТ", "name": "Т-70М", "tag": "Т-70", "nation": "СССР", "cls": "Лёгкий танк",
		"tier": 3, "side": "allies", "year": 1942, "pts": 4, "freq": 2.0,
		"hp": 560.0, "dmg": 60.0, "pen": 66.0, "caliber": 45.0, "reload": 1.6, "shell": 760.0,
		"kmh": 45.0, "rev": 15.0, "turn": 44.0, "tspd": 24.0, "power": 170.0, "mass": 9.8,
		"disp": 0.42, "aim": 1.7, "armor": [45, 15, 25, 35, 35, 35], "slope": 30.0, "side_slope": 0.0,
		"tslope": 20.0, "elev": [-6.0, 20.0], "spot": 64.0, "engine": "petrol", "len": 4.29, "wid": 2.32, "pref": 280.0},
	"isu152": {"short": "ПТ", "name": "ИСУ-152", "tag": "ИСУ-152", "nation": "СССР", "cls": "Самоходная установка",
		"tier": 8, "side": "allies", "year": 1944, "pts": 10, "freq": 0.6,
		"hp": 1700.0, "dmg": 480.0, "pen": 150.0, "caliber": 152.0, "reload": 11.0, "shell": 600.0,
		"kmh": 35.0, "rev": 12.0, "turn": 28.0, "tspd": 10.0, "power": 520.0, "mass": 46.0,
		"disp": 0.42, "aim": 2.8, "armor": [90, 75, 60, 120, 75, 60], "slope": 30.0, "side_slope": 15.0,
		"tslope": 30.0, "traverse": 6.0, "elev": [-3.0, 20.0], "spot": 58.0, "engine": "diesel", "len": 6.54, "wid": 3.07, "pref": 460.0},
	# ---- 2.4: ещё 21 машина ----
	"bt7": {"short": "ЛТ", "name": "БТ-7", "tag": "БТ-7", "nation": "СССР", "cls": "Лёгкий танк",
		"tier": 3, "side": "allies", "year": 1937, "pts": 4, "freq": 1.0,
		"hp": 520.0, "dmg": 75.0, "pen": 50.0, "caliber": 45.0, "reload": 2.0, "shell": 760.0,
		"kmh": 62.0, "rev": 15.0, "turn": 46.0, "tspd": 40.0, "power": 450.0, "mass": 13.8,
		"disp": 0.42, "aim": 1.8, "armor": [22, 13, 13, 15, 15, 15], "slope": 18.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-6.0, 25.0], "spot": 60.0, "engine": "petrol", "len": 5.66, "wid": 2.29, "pref": 300.0},
	"t34_57": {"short": "СТ", "name": "Т-34-57 (ЗиС-4)", "tag": "Т-34-57", "nation": "СССР", "cls": "Танк-истребитель",
		"tier": 4, "side": "allies", "year": 1941, "pts": 6, "freq": 0.6,
		"hp": 820.0, "dmg": 85.0, "pen": 110.0, "caliber": 57.0, "reload": 2.4, "shell": 990.0,
		"kmh": 54.0, "rev": 12.0, "turn": 40.0, "tspd": 24.0, "power": 500.0, "mass": 28.5,
		"disp": 0.30, "aim": 2.0, "armor": [45, 40, 40, 52, 52, 45], "slope": 60.0, "side_slope": 40.0,
		"tslope": 30.0, "elev": [-5.0, 25.0], "spot": 64.0, "engine": "diesel", "len": 5.92, "wid": 3.0, "pref": 420.0},
	"su122": {"short": "ПТ", "name": "СУ-122", "tag": "СУ-122", "nation": "СССР", "cls": "Самоходная установка",
		"tier": 5, "side": "allies", "year": 1943, "pts": 7, "freq": 1.0,
		"hp": 860.0, "dmg": 280.0, "pen": 90.0, "caliber": 122.0, "reload": 7.5, "shell": 515.0,
		"kmh": 55.0, "rev": 18.0, "turn": 40.0, "tspd": 12.0, "power": 500.0, "mass": 30.9,
		"disp": 0.52, "aim": 2.6, "armor": [45, 45, 40, 45, 45, 40], "slope": 50.0, "side_slope": 20.0,
		"tslope": 50.0, "traverse": 20.0, "elev": [-3.0, 25.0], "spot": 58.0, "engine": "diesel", "len": 6.95, "wid": 3.0, "pref": 300.0},
	"kv85": {"short": "ТТ", "name": "КВ-85", "tag": "КВ-85", "nation": "СССР", "cls": "Тяжёлый танк",
		"tier": 7, "side": "allies", "year": 1943, "pts": 11, "freq": 0.6,
		"hp": 1380.0, "dmg": 160.0, "pen": 120.0, "caliber": 85.0, "reload": 3.6, "shell": 792.0,
		"kmh": 35.0, "rev": 12.0, "turn": 26.0, "tspd": 22.0, "power": 600.0, "mass": 46.0,
		"disp": 0.46, "aim": 2.4, "armor": [75, 60, 60, 100, 100, 100], "slope": 30.0, "side_slope": 0.0,
		"tslope": 20.0, "elev": [-5.0, 25.0], "spot": 60.0, "engine": "diesel", "len": 6.68, "wid": 3.25, "pref": 360.0},
	"su152": {"short": "ПТ", "name": "СУ-152", "tag": "СУ-152", "nation": "СССР", "cls": "Тяжёлая САУ",
		"tier": 7, "side": "allies", "year": 1943, "pts": 11, "freq": 0.6,
		"hp": 1500.0, "dmg": 500.0, "pen": 125.0, "caliber": 152.0, "reload": 11.0, "shell": 600.0,
		"kmh": 33.0, "rev": 12.0, "turn": 26.0, "tspd": 8.0, "power": 600.0, "mass": 45.5,
		"disp": 0.55, "aim": 3.2, "armor": [75, 60, 60, 75, 60, 60], "slope": 30.0, "side_slope": 0.0,
		"tslope": 30.0, "traverse": 12.0, "elev": [-5.0, 18.0], "spot": 56.0, "engine": "diesel", "len": 6.95, "wid": 3.25, "pref": 380.0},
	"pz3j": {"short": "СТ", "name": "Pz.Kpfw. III Ausf. J", "tag": "Pz III J", "nation": "Германия", "cls": "Средний танк",
		"tier": 3, "side": "axis", "year": 1942, "pts": 5, "freq": 2.0,
		"hp": 680.0, "dmg": 80.0, "pen": 60.0, "caliber": 50.0, "reload": 2.3, "shell": 685.0,
		"kmh": 40.0, "rev": 14.0, "turn": 40.0, "tspd": 36.0, "power": 300.0, "mass": 21.5,
		"disp": 0.36, "aim": 1.8, "armor": [50, 30, 50, 50, 30, 30], "slope": 10.0, "side_slope": 0.0,
		"tslope": 15.0, "elev": [-10.0, 20.0], "spot": 60.0, "engine": "petrol", "len": 5.52, "wid": 2.95, "pref": 320.0},
	"pz3n": {"short": "СТ", "name": "Pz.Kpfw. III Ausf. N", "tag": "Pz III N", "nation": "Германия", "cls": "Танк поддержки",
		"tier": 4, "side": "axis", "year": 1942, "pts": 6, "freq": 1.0,
		"hp": 780.0, "dmg": 160.0, "pen": 70.0, "caliber": 75.0, "reload": 3.2, "shell": 450.0,
		"kmh": 40.0, "rev": 14.0, "turn": 40.0, "tspd": 36.0, "power": 300.0, "mass": 23.0,
		"disp": 0.48, "aim": 2.2, "armor": [70, 30, 50, 57, 30, 30], "slope": 10.0, "side_slope": 0.0,
		"tslope": 15.0, "elev": [-10.0, 20.0], "spot": 60.0, "engine": "petrol", "len": 5.52, "wid": 2.95, "pref": 300.0, "he": 60.0},
	"grille": {"short": "ПТ", "name": "15 cm sIG 33 (Sf) Grille Ausf. H", "tag": "Grille", "nation": "Германия", "cls": "Самоходная гаубица",
		"tier": 4, "side": "axis", "year": 1943, "pts": 6, "freq": 1.0,
		"hp": 620.0, "dmg": 300.0, "pen": 80.0, "caliber": 150.0, "reload": 9.0, "shell": 240.0,
		"kmh": 35.0, "rev": 10.0, "turn": 38.0, "tspd": 10.0, "power": 125.0, "mass": 11.5,
		"disp": 0.55, "aim": 2.8, "armor": [25, 15, 10, 15, 10, 10], "slope": 20.0, "side_slope": 0.0,
		"tslope": 20.0, "traverse": 10.0, "elev": [-3.0, 40.0], "spot": 58.0, "engine": "petrol", "len": 4.95, "wid": 2.15, "pref": 300.0, "he": 900.0},
	"brummbar": {"short": "ПТ", "name": "Sturmpanzer IV Brummbär", "tag": "Brummbär", "nation": "Германия", "cls": "Штурмовое орудие",
		"tier": 6, "side": "axis", "year": 1943, "pts": 8, "freq": 0.6,
		"hp": 1050.0, "dmg": 420.0, "pen": 120.0, "caliber": 150.0, "reload": 10.5, "shell": 280.0,
		"kmh": 40.0, "rev": 10.0, "turn": 30.0, "tspd": 10.0, "power": 300.0, "mass": 28.2,
		"disp": 0.6, "aim": 3.2, "armor": [100, 30, 20, 100, 50, 30], "slope": 10.0, "side_slope": 0.0,
		"tslope": 40.0, "traverse": 20.0, "elev": [-8.0, 30.0], "spot": 56.0, "engine": "petrol", "len": 5.93, "wid": 2.88, "pref": 320.0, "he": 900.0},
	"jpz4": {"short": "ПТ", "name": "Panzer IV/70 (V)", "tag": "Pz IV/70", "nation": "Германия", "cls": "Истребитель танков",
		"tier": 6, "side": "axis", "year": 1944, "pts": 9, "freq": 0.8,
		"hp": 1000.0, "dmg": 200.0, "pen": 185.0, "caliber": 75.0, "reload": 4.3, "shell": 925.0,
		"kmh": 35.0, "rev": 10.0, "turn": 30.0, "tspd": 12.0, "power": 300.0, "mass": 25.8,
		"disp": 0.3, "aim": 2.2, "armor": [80, 40, 20, 80, 40, 20], "slope": 45.0, "side_slope": 30.0,
		"tslope": 50.0, "traverse": 20.0, "elev": [-6.0, 15.0], "spot": 58.0, "engine": "petrol", "len": 5.9, "wid": 3.17, "pref": 460.0},
	"m5a1": {"short": "ЛТ", "name": "M5A1 Stuart", "tag": "M5A1", "nation": "США", "cls": "Лёгкий танк",
		"tier": 4, "side": "allies", "year": 1943, "pts": 5, "freq": 1.5,
		"hp": 640.0, "dmg": 60.0, "pen": 60.0, "caliber": 37.0, "reload": 1.6, "shell": 884.0,
		"kmh": 58.0, "rev": 18.0, "turn": 48.0, "tspd": 45.0, "power": 220.0, "mass": 15.4,
		"disp": 0.38, "aim": 1.6, "stab": 0.4, "armor": [29, 29, 25, 51, 32, 32], "slope": 48.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-12.0, 20.0], "spot": 66.0, "engine": "petrol", "len": 4.34, "wid": 2.29, "pref": 300.0},
	"jumbo": {"short": "ТТ", "name": "M4A3E2 Sherman Jumbo", "tag": "Jumbo", "nation": "США", "cls": "Штурмовой танк",
		"tier": 6, "side": "allies", "year": 1944, "pts": 9, "freq": 0.6,
		"hp": 1150.0, "dmg": 120.0, "pen": 92.0, "caliber": 75.0, "reload": 2.7, "shell": 619.0,
		"kmh": 35.0, "rev": 12.0, "turn": 30.0, "tspd": 30.0, "power": 500.0, "mass": 38.0,
		"disp": 0.4, "aim": 2.0, "stab": 0.5, "armor": [102, 76, 38, 152, 152, 152], "slope": 47.0, "side_slope": 0.0,
		"tslope": 0.0, "elev": [-10.0, 25.0], "spot": 62.0, "engine": "petrol", "len": 6.27, "wid": 2.94, "pref": 340.0},
	"m18": {"short": "ПТ", "name": "76mm GMC M18 Hellcat", "tag": "M18", "nation": "США", "cls": "Истребитель танков",
		"tier": 6, "side": "allies", "year": 1944, "pts": 8, "freq": 1.0,
		"hp": 820.0, "dmg": 140.0, "pen": 128.0, "caliber": 76.2, "reload": 3.0, "shell": 792.0,
		"kmh": 72.0, "rev": 18.0, "turn": 50.0, "tspd": 20.0, "power": 400.0, "mass": 17.9,
		"disp": 0.38, "aim": 2.0, "armor": [13, 13, 13, 25, 13, 13], "slope": 38.0, "side_slope": 23.0,
		"tslope": 23.0, "elev": [-10.0, 19.0], "spot": 64.0, "engine": "petrol", "len": 5.44, "wid": 2.87, "pref": 460.0},
	"t28": {"short": "ПТ", "name": "Super Heavy Tank T28 (105mm GMC T95)", "tag": "T28", "nation": "США", "cls": "Истребитель танков",
		"tier": 8, "side": "allies", "year": 1945, "pts": 12, "freq": 0.2,
		"hp": 1500.0, "dmg": 320.0, "pen": 230.0, "caliber": 105.0, "reload": 9.0, "shell": 1128.0,
		"kmh": 13.0, "rev": 5.0, "turn": 18.0, "tspd": 10.0, "power": 500.0, "mass": 86.0,
		"disp": 0.32, "aim": 2.6, "armor": [305, 152, 51, 305, 152, 51], "slope": 0.0, "side_slope": 0.0,
		"tslope": 0.0, "traverse": 10.0, "elev": [-5.0, 19.5], "spot": 60.0, "engine": "petrol", "len": 7.52, "wid": 3.15, "pref": 380.0},
	"tetrarch": {"short": "ЛТ", "name": "Light Tank Mk. VII Tetrarch", "tag": "Tetrarch", "nation": "Великобритания", "cls": "Лёгкий танк",
		"tier": 3, "side": "allies", "year": 1941, "pts": 4, "freq": 0.8,
		"hp": 520.0, "dmg": 70.0, "pen": 64.0, "caliber": 40.0, "reload": 1.8, "shell": 792.0,
		"kmh": 64.0, "rev": 16.0, "turn": 50.0, "tspd": 34.0, "power": 165.0, "mass": 7.6,
		"disp": 0.36, "aim": 1.7, "armor": [16, 14, 10, 16, 14, 14], "slope": 20.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-7.0, 20.0], "spot": 64.0, "engine": "petrol", "len": 4.42, "wid": 2.31, "pref": 240.0},
	"achilles": {"short": "ПТ", "name": "17pdr SP Achilles", "tag": "Achilles", "nation": "Великобритания", "cls": "Истребитель танков",
		"tier": 6, "side": "allies", "year": 1944, "pts": 9, "freq": 0.8,
		"hp": 900.0, "dmg": 150.0, "pen": 165.0, "caliber": 76.2, "reload": 3.4, "shell": 884.0,
		"kmh": 48.0, "rev": 14.0, "turn": 36.0, "tspd": 14.0, "power": 375.0, "mass": 29.6,
		"disp": 0.33, "aim": 2.2, "armor": [57, 25, 19, 57, 25, 25], "slope": 55.0, "side_slope": 38.0,
		"tslope": 45.0, "elev": [-5.0, 20.0], "spot": 62.0, "engine": "diesel", "len": 5.97, "wid": 3.05, "pref": 460.0},
	"challenger": {"short": "СТ", "name": "Cruiser Mk. VIII Challenger", "tag": "Challenger", "nation": "Великобритания", "cls": "Крейсерский танк",
		"tier": 7, "side": "allies", "year": 1944, "pts": 10, "freq": 0.6,
		"hp": 1100.0, "dmg": 150.0, "pen": 170.0, "caliber": 76.2, "reload": 3.5, "shell": 884.0,
		"kmh": 52.0, "rev": 14.0, "turn": 36.0, "tspd": 30.0, "power": 600.0, "mass": 33.0,
		"disp": 0.33, "aim": 2.1, "armor": [64, 32, 25, 102, 40, 40], "slope": 10.0, "side_slope": 0.0,
		"tslope": 0.0, "elev": [-10.0, 20.0], "spot": 64.0, "engine": "petrol", "len": 6.55, "wid": 2.9, "pref": 460.0},
	"sem10525": {"short": "ПТ", "name": "Semovente da 105/25 M43", "tag": "Semovente 105/25", "nation": "Италия", "cls": "Штурмовое орудие",
		"tier": 5, "side": "axis", "year": 1943, "pts": 7, "freq": 0.6,
		"hp": 760.0, "dmg": 280.0, "pen": 85.0, "caliber": 105.0, "reload": 6.5, "shell": 510.0,
		"kmh": 38.0, "rev": 10.0, "turn": 36.0, "tspd": 12.0, "power": 192.0, "mass": 15.8,
		"disp": 0.45, "aim": 2.4, "armor": [75, 25, 25, 75, 45, 25], "slope": 30.0, "side_slope": 0.0,
		"tslope": 30.0, "traverse": 18.0, "elev": [-10.0, 22.0], "spot": 56.0, "engine": "petrol", "len": 5.1, "wid": 2.4, "pref": 320.0, "he": 300.0},
	"l3cc": {"short": "ПТ", "name": "Carro Veloce L3 cc", "tag": "L3 cc", "nation": "Италия", "cls": "Танкетка-истребитель",
		"tier": 3, "side": "axis", "year": 1941, "pts": 3, "freq": 0.6,
		"hp": 380.0, "dmg": 45.0, "pen": 40.0, "caliber": 20.0, "reload": 1.2, "shell": 900.0,
		"kmh": 42.0, "rev": 12.0, "turn": 50.0, "tspd": 20.0, "power": 43.0, "mass": 3.4,
		"disp": 0.30, "aim": 1.6, "armor": [14, 8, 6, 14, 8, 8], "slope": 20.0, "side_slope": 0.0,
		"tslope": 20.0, "traverse": 15.0, "elev": [-8.0, 15.0], "spot": 56.0, "engine": "petrol", "len": 3.17, "wid": 1.4, "pref": 260.0},
	"pz2": {"short": "ЛТ", "name": "Pz.Kpfw. II Ausf. F", "tag": "Pz II", "nation": "Германия", "cls": "Лёгкий танк",
		"tier": 3, "side": "axis", "year": 1941, "pts": 4, "freq": 1.5,
		"hp": 520.0, "dmg": 45.0, "pen": 40.0, "caliber": 20.0, "reload": 0.9, "shell": 780.0,
		"kmh": 40.0, "rev": 12.0, "turn": 46.0, "tspd": 36.0, "power": 140.0, "mass": 9.5,
		"disp": 0.36, "aim": 1.4, "armor": [35, 20, 15, 30, 15, 15], "slope": 20.0, "side_slope": 0.0,
		"tslope": 10.0, "elev": [-9.5, 20.0], "spot": 62.0, "engine": "petrol", "len": 4.81, "wid": 2.28, "pref": 260.0},
	"stug4": {"short": "ПТ", "name": "StuG IV", "tag": "StuG IV", "nation": "Германия", "cls": "Штурмовое орудие",
		"tier": 5, "side": "axis", "year": 1944, "pts": 7, "freq": 0.7,
		"hp": 900.0, "dmg": 135.0, "pen": 112.0, "caliber": 75.0, "reload": 3.4, "shell": 740.0,
		"kmh": 38.0, "rev": 10.0, "turn": 34.0, "tspd": 12.0, "power": 300.0, "mass": 23.0,
		"disp": 0.36, "aim": 2.1, "armor": [80, 30, 20, 80, 30, 30], "slope": 20.0, "side_slope": 0.0,
		"tslope": 10.0, "traverse": 10.0, "elev": [-6.0, 20.0], "spot": 58.0, "engine": "petrol", "len": 6.0, "wid": 2.88, "pref": 330.0},
	"h38": {"short": "ЛТ", "name": "Hotchkiss H38", "tag": "H38", "nation": "Франция", "cls": "Лёгкий танк",
		"tier": 3, "side": "allies", "year": 1938, "pts": 4, "freq": 1.5,
		"hp": 560.0, "dmg": 55.0, "pen": 45.0, "caliber": 37.0, "reload": 1.9, "shell": 705.0,
		"kmh": 36.0, "rev": 10.0, "turn": 38.0, "tspd": 18.0, "power": 120.0, "mass": 12.1,
		"disp": 0.44, "aim": 1.9, "armor": [40, 40, 40, 45, 40, 40], "slope": 30.0, "side_slope": 0.0,
		"tslope": 20.0, "elev": [-10.0, 20.0], "spot": 52.0, "engine": "petrol", "len": 4.22, "wid": 1.95, "pref": 260.0},
	"s35": {"short": "СТ", "name": "SOMUA S35", "tag": "S35", "nation": "Франция", "cls": "Кавалерийский танк",
		"tier": 4, "side": "allies", "year": 1936, "pts": 6, "freq": 1.2,
		"hp": 740.0, "dmg": 75.0, "pen": 52.0, "caliber": 47.0, "reload": 2.3, "shell": 660.0,
		"kmh": 40.0, "rev": 12.0, "turn": 34.0, "tspd": 18.0, "power": 190.0, "mass": 19.5,
		"disp": 0.44, "aim": 2.1, "armor": [47, 40, 25, 56, 46, 46], "slope": 30.0, "side_slope": 0.0,
		"tslope": 20.0, "elev": [-18.0, 20.0], "spot": 56.0, "engine": "petrol", "len": 5.38, "wid": 2.12, "pref": 300.0},
	"b1bis": {"short": "ТТ", "name": "Char B1 bis", "tag": "B1 bis", "nation": "Франция", "cls": "Тяжёлый танк",
		"tier": 5, "side": "allies", "year": 1937, "pts": 7, "freq": 1.0,
		"hp": 1100.0, "dmg": 75.0, "pen": 52.0, "caliber": 47.0, "reload": 2.4, "shell": 660.0,
		"kmh": 28.0, "rev": 10.0, "turn": 24.0, "tspd": 16.0, "power": 307.0, "mass": 31.5,
		"disp": 0.42, "aim": 2.0, "armor": [60, 55, 55, 56, 46, 46], "slope": 20.0, "side_slope": 0.0,
		"tslope": 20.0, "elev": [-18.0, 20.0], "spot": 56.0, "engine": "petrol", "len": 6.37, "wid": 2.46, "pref": 300.0},
	"t26": {"short": "ЛТ", "name": "Т-26 обр. 1939", "tag": "Т-26", "nation": "СССР", "cls": "Лёгкий танк",
		"tier": 3, "side": "allies", "year": 1933, "pts": 4, "freq": 2.5,
		"hp": 520.0, "dmg": 75.0, "pen": 50.0, "caliber": 45.0, "reload": 2.0, "shell": 760.0,
		"kmh": 30.0, "rev": 10.0, "turn": 40.0, "tspd": 24.0, "power": 97.0, "mass": 10.3,
		"disp": 0.44, "aim": 1.9, "armor": [15, 15, 15, 20, 15, 15], "slope": 23.0, "side_slope": 0.0,
		"tslope": 18.0, "elev": [-6.0, 22.0], "spot": 56.0, "engine": "petrol", "len": 4.65, "wid": 2.44, "pref": 280.0},
	"t60": {"short": "ЛТ", "name": "Т-60", "tag": "Т-60", "nation": "СССР", "cls": "Лёгкий танк",
		"tier": 3, "side": "allies", "year": 1941, "pts": 3, "freq": 2.0,
		"hp": 460.0, "dmg": 30.0, "pen": 38.0, "caliber": 20.0, "reload": 0.6, "shell": 815.0,
		"kmh": 44.0, "rev": 12.0, "turn": 46.0, "tspd": 30.0, "power": 70.0, "mass": 5.8,
		"disp": 0.42, "aim": 1.4, "armor": [35, 15, 25, 25, 25, 25], "slope": 60.0, "side_slope": 0.0,
		"tslope": 25.0, "elev": [-7.0, 25.0], "spot": 58.0, "engine": "petrol", "len": 4.1, "wid": 2.3, "pref": 240.0},
	"m4a2": {"short": "СТ", "name": "M4A2(76)W «Эмча»", "tag": "M4A2", "nation": "СССР", "cls": "Средний танк",
		"tier": 6, "side": "allies", "year": 1944, "pts": 8, "freq": 1.2,
		"hp": 980.0, "dmg": 135.0, "pen": 116.0, "caliber": 76.2, "reload": 3.0, "shell": 792.0,
		"kmh": 48.0, "rev": 16.0, "turn": 38.0, "tspd": 30.0, "power": 410.0, "mass": 33.2,
		"disp": 0.38, "aim": 2.0, "stab": 0.3, "armor": [64, 38, 38, 89, 64, 64], "slope": 47.0, "side_slope": 0.0,
		"tslope": 30.0, "elev": [-10.0, 25.0], "spot": 64.0, "engine": "diesel", "len": 5.92, "wid": 2.62, "pref": 400.0},
	"pz3b": {"short": "СТ", "name": "Pz.Kpfw. III Ausf. B", "tag": "Pz III B", "nation": "Германия", "cls": "Средний танк",
		"tier": 3, "side": "axis", "year": 1938, "pts": 4, "freq": 0.8,
		"hp": 600.0, "dmg": 55.0, "pen": 48.0, "caliber": 37.0, "reload": 1.8, "shell": 745.0,
		"kmh": 35.0, "rev": 12.0, "turn": 40.0, "tspd": 24.0, "power": 250.0, "mass": 15.9,
		"disp": 0.38, "aim": 1.8, "armor": [15, 15, 15, 15, 15, 15], "slope": 20.0, "side_slope": 0.0,
		"tslope": 15.0, "elev": [-10.0, 20.0], "spot": 64.0, "engine": "petrol", "len": 5.67, "wid": 2.81, "pref": 320.0},
	"pzj1": {"short": "ПТ", "name": "Panzerjäger I", "tag": "Pz.Jäger I", "nation": "Германия", "cls": "Истребитель танков",
		"tier": 3, "side": "axis", "year": 1940, "pts": 4, "freq": 1.0,
		"hp": 420.0, "dmg": 85.0, "pen": 70.0, "caliber": 47.0, "reload": 2.3, "shell": 775.0,
		"kmh": 40.0, "rev": 12.0, "turn": 42.0, "tspd": 14.0, "power": 100.0, "mass": 6.4,
		"disp": 0.36, "aim": 1.8, "armor": [13, 13, 13, 15, 10, 0], "slope": 25.0, "side_slope": 0.0,
		"tslope": 30.0, "traverse": 17.5, "elev": [-8.0, 12.0], "spot": 60.0, "engine": "petrol", "len": 4.42, "wid": 2.06, "pref": 420.0},
	"hago": {"short": "ЛТ", "name": "Тип 95 «Ха-Го»", "tag": "Ха-Го", "nation": "Япония", "cls": "Лёгкий танк",
		"tier": 3, "side": "axis", "year": 1936, "pts": 4, "freq": 2.0,
		"hp": 500.0, "dmg": 50.0, "pen": 42.0, "caliber": 37.0, "reload": 1.8, "shell": 675.0,
		"kmh": 45.0, "rev": 14.0, "turn": 44.0, "tspd": 26.0, "power": 120.0, "mass": 7.4,
		"disp": 0.44, "aim": 1.8, "armor": [12, 12, 10, 12, 12, 12], "slope": 20.0, "side_slope": 0.0,
		"tslope": 15.0, "elev": [-15.0, 20.0], "spot": 58.0, "engine": "diesel", "len": 4.38, "wid": 2.06, "pref": 260.0},
	"chiha": {"short": "СТ", "name": "Тип 97 «Чи-Ха»", "tag": "Чи-Ха", "nation": "Япония", "cls": "Средний танк",
		"tier": 3, "side": "axis", "year": 1938, "pts": 5, "freq": 1.2,
		"hp": 640.0, "dmg": 95.0, "pen": 32.0, "caliber": 57.0, "reload": 2.4, "shell": 355.0, "he": 250.0,
		"kmh": 38.0, "rev": 12.0, "turn": 36.0, "tspd": 22.0, "power": 170.0, "mass": 15.0,
		"disp": 0.48, "aim": 2.0, "armor": [25, 22, 20, 25, 25, 25], "slope": 20.0, "side_slope": 0.0,
		"tslope": 15.0, "elev": [-15.0, 20.0], "spot": 58.0, "engine": "diesel", "len": 5.52, "wid": 2.33, "pref": 260.0},
}

# ---------- Прогресс: исследование, покупка, модули ----------

const ROMAN := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
# Танки, которые есть у игрока с самого начала (по одному-два на нацию).
## Ключи машин, заменённых в 2.4, → замена (перенос сохранений).
const RENAMED := {"crusader": "a10", "matilda": "grant", "su76": "t34_57", "marder3": "grille", "m36": "t28",
	"valentine": "tetrarch", "sem7518": "sem10525", "sem9053": "l3cc", "toldi": "pz2", "zrinyi": "stug4"}
## Разворот на месте вокруг центра (планетарные и двухпоточные механизмы поворота: «Тигры», «Пантеры»,
## британский Merritt-Brown, гидростатика Naeder у B1 bis). У остальных (бортовые фрикционы и тормоза,
## управляемый дифференциал) танк без хода поворачивается вокруг заторможенной гусеницы.
const NEUTRAL_STEER := ["tiger", "tiger2", "tiger_p", "panther", "jagdpanther", "jagdtiger", "ferdinand",
	"churchill", "cromwell", "comet", "challenger", "b1bis"]
const STARTERS := ["t34_76", "a10", "pz3", "m13_40", "stuart", "l6_40", "pz38t", "t70", "bt7", "pz3j", "tetrarch", "pz2",
	"h38", "hago"]
# Дерево исследования: какие машины открывает опыт, набранный на танке.
const TREE := {
	"t70": ["t34_76", "kv1", "t34_57"], "bt7": ["t34_76", "t34_57", "t26"], "t34_57": ["su122"], "su122": ["su85", "su152"],
	"t34_76": ["t34", "su85", "kv1", "m4a2"], "t34": ["su100"], "su85": ["su100"], "kv1": ["kv2", "is2", "kv85"], "kv85": ["is2"],
	"su100": ["isu152"], "kv2": ["isu152"], "su152": ["isu152"],
	"stuart": ["lee", "grant", "m5a1"], "m5a1": ["chaffee", "m18"], "lee": ["sherman", "m10"], "grant": ["churchill"],
	"tetrarch": ["grant", "a10"], "m10": ["easy8", "m18", "achilles"], "m18": ["t28"],
	"sherman": ["firefly", "easy8", "jumbo", "m4a2"], "easy8": ["pershing"], "achilles": ["challenger"],
	"a10": ["cromwell", "sherman", "chaffee"], "cromwell": ["firefly", "churchill", "comet", "challenger"], "challenger": ["comet"],
	"l6_40": ["m15_42", "l3cc"], "m13_40": ["m15_42", "pz3", "sem10525"], "m15_42": ["p26"],
	"pz3j": ["pz3", "pz3n", "grille"], "pz3n": ["pz4", "brummbar"], "pz3": ["pz4", "stug", "pz4f2"],
	"grille": ["nashorn", "stug"], "pz4": ["tiger", "panther", "brummbar"], "pz4f2": ["tiger"],
	"stug": ["jagdpanther", "jpz4"], "jpz4": ["jagdpanther"], "tiger": ["tiger2", "tiger_p"], "tiger_p": ["ferdinand"],
	"jagdpanther": ["jagdtiger"],
	"pz38t": ["hetzer", "luchs", "turan", "pzj1"], "pz2": ["turan", "pz3b"], "turan": ["pz4f2", "stug4"], "luchs": ["pz4f2"],
	"hetzer": ["stug", "nashorn"], "nashorn": ["jagdpanther"],
	"h38": ["s35"], "s35": ["b1bis"], "t26": ["t34_76", "t60"], "t60": ["t70"], "pz3b": ["pz3j"], "pzj1": ["hetzer"], "hago": ["chiha"],
}
const RESEARCH_XP := {3: 400, 4: 800, 5: 2500, 6: 5000, 7: 9000, 8: 15000}  # опыт на исследование танка
const PRICE := {3: 8000, 4: 15000, 5: 45000, 6: 90000, 7: 180000, 8: 320000}  # серебро
const START_SILVER := 60000
const FREE_XP_SHARE := 0.05  # доля опыта за бой, которая идёт в свободный
const SLOTS := ["gun", "turret", "engine", "susp"]
const SLOT_NAMES := {"gun": "Орудие", "turret": "Башня", "engine": "Двигатель", "susp": "Ходовая"}
const SLOT_XP := {"gun": 0.4, "turret": 0.3, "engine": 0.25, "susp": 0.15}  # доля опыта на исследование уровня
const SLOT_PRICE := {"gun": 0.2, "turret": 0.15, "engine": 0.12, "susp": 0.08}  # доля цены танка

# Модули: [стоковый, исследуемый, что меняется при стоковом]. Характеристики в TYPES — с исследованными
# модулями; стоковая ходовая поворачивает корпус на 12 % медленнее.
const MODULES := {
	"m13_40": {"engine": ["SPA 8T", "SPA 15T", {"power": 105.0}], "susp": ["M13/40", "M14/41"]},
	"pz3": {"gun": ["5 cm KwK 38 L/42", "5 cm KwK 39 L/60", {"dmg": 75.0, "pen": 60.0, "shell": 685.0, "reload": 2.0}],
		"engine": ["Maybach HL 120 TR", "Maybach HL 120 TRM", {"power": 265.0}],
		"susp": ["Pz.Kpfw. III Ausf. H", "Pz.Kpfw. III Ausf. L"]},
	"a10": {"gun": ["QF 2-pdr Mk. IX (сплошной)", "QF 2-pdr Mk. IX (APCBC)", {"pen": 52.0, "shell": 760.0}],
		"engine": ["AEC A179", "AEC A179 форсированный", {"power": 135.0}],
		"susp": ["A10 Mk. I", "A10 Mk. IA"]},
	"chaffee": {"engine": ["Cadillac 44T4", "2× Cadillac 44T24", {"power": 190.0}], "susp": ["T24", "M24"]},
	"t34_76": {"gun": ["76 мм Л-11", "76 мм Ф-34", {"dmg": 110.0, "pen": 66.0, "shell": 612.0, "reload": 2.6}],
		"turret": ["Башня обр. 1941", "Башня обр. 1943", {"tspd": 30.0, "armor": [45, 45, 40, 45, 45, 45], "hp": 820.0}],
		"engine": ["В-2", "В-2-34", {"power": 450.0}], "susp": ["Т-34 обр. 1941", "Т-34 обр. 1943"]},
	"pz4": {"gun": ["7,5 cm KwK 40 L/43", "7,5 cm KwK 40 L/48", {"pen": 112.0, "shell": 740.0, "disp": 0.38}],
		"engine": ["Maybach HL 120 TR", "Maybach HL 120 TRM", {"power": 265.0}],
		"susp": ["Pz.Kpfw. IV Ausf. F", "Pz.Kpfw. IV Ausf. H"]},
	"stug": {"gun": ["7,5 cm StuK 40 L/43", "7,5 cm StuK 40 L/48", {"pen": 112.0, "shell": 740.0, "disp": 0.36}],
		"engine": ["Maybach HL 120 TR", "Maybach HL 120 TRM", {"power": 265.0}],
		"susp": ["StuG III Ausf. F", "StuG III Ausf. G"]},
	"sherman": {"engine": ["Continental R975 C1", "Continental R975 C4", {"power": 350.0}], "susp": ["VVSS", "VVSS усиленная"]},
	"cromwell": {"gun": ["QF 6-pdr Mk. V", "QF 75 mm Mk. V", {"dmg": 95.0, "pen": 95.0, "caliber": 57.0, "shell": 853.0, "reload": 2.1}],
		"engine": ["Nuffield Liberty Mk. V", "Rolls-Royce Meteor", {"power": 410.0}], "susp": ["Centaur", "Cromwell"]},
	"t34": {"gun": ["85 мм Д-5Т", "85 мм ЗИС-С-53", {"pen": 112.0, "reload": 3.4, "aim": 2.3}],
		"engine": ["В-2-34", "В-2-34М", {"power": 470.0}], "susp": ["Т-34-85 обр. 1943", "Т-34-85 обр. 1944"]},
	"kv1": {"gun": ["76 мм Ф-32", "76 мм ЗИС-5", {"dmg": 110.0, "pen": 66.0, "shell": 613.0, "reload": 2.8}],
		"engine": ["В-2К", "В-2К форсированный", {"power": 500.0}], "susp": ["КВ-1 обр. 1941", "КВ-1 обр. 1942"]},
	"firefly": {"engine": ["Chrysler A57 ранний", "Chrysler A57 Multibank", {"power": 370.0}], "susp": ["VVSS", "VVSS усиленная"]},
	"tiger": {"engine": ["Maybach HL 210 P45", "Maybach HL 230 P45", {"power": 650.0}], "susp": ["Tiger I ранний", "Tiger I поздний"]},
	"panther": {"engine": ["Maybach HL 210 P30", "Maybach HL 230 P30", {"power": 650.0}], "susp": ["Panther ранняя", "Panther поздняя"]},
	"jagdpanther": {"engine": ["Maybach HL 210 P30", "Maybach HL 230 P30", {"power": 650.0}], "susp": ["Jagdpanther G1", "Jagdpanther G2"]},
	"su100": {"gun": ["85 мм Д-5С", "100 мм Д-10С", {"dmg": 160.0, "pen": 120.0, "caliber": 85.0, "shell": 792.0, "reload": 3.2, "disp": 0.44}],
		"engine": ["В-2-34", "В-2-34М", {"power": 470.0}], "susp": ["СУ-85", "СУ-100"]},
	"is2": {"gun": ["85 мм Д-5Т", "122 мм Д-25Т", {"dmg": 160.0, "pen": 120.0, "caliber": 85.0, "shell": 792.0, "reload": 3.3, "disp": 0.46, "aim": 2.3}],
		"engine": ["В-2К", "В-2-ИС", {"power": 480.0}], "susp": ["ИС-1", "ИС-2"]},
	"pz38t": {"gun": ["3,7 cm KwK 34(t)", "3,7 cm KwK 38(t)", {"pen": 50.0, "shell": 675.0}],
		"engine": ["Praga TNHPS/II", "Praga EPA/2", {"power": 110.0}], "susp": ["Pz.Kpfw. 38(t) Ausf. A", "Pz.Kpfw. 38(t) Ausf. E"]},
	"l6_40": {"engine": ["SPA 18 VT", "SPA 18 VT форсированный", {"power": 60.0}], "susp": ["L6/40 ранний", "L6/40"]},
	"m15_42": {"engine": ["SPA 15T", "SPA 15TBM", {"power": 145.0}], "susp": ["M14/41", "M15/42"]},
	"hetzer": {"gun": ["7,5 cm StuK 40 L/43", "7,5 cm PaK 39 L/48", {"pen": 105.0, "shell": 700.0}],
		"engine": ["Praga AC/2", "Praga AC/2800", {"power": 145.0}], "susp": ["Jagdpanzer 38(t) ранний", "Jagdpanzer 38(t)"]},
	"nashorn": {"engine": ["Maybach HL 120 TRM ранний", "Maybach HL 120 TRM", {"power": 265.0}], "susp": ["Hornisse", "Nashorn"]},
	"ferdinand": {"engine": ["2× Maybach HL 120 TRM ранние", "2× Maybach HL 120 TRM", {"power": 530.0}], "susp": ["Ferdinand", "Elefant"]},
	"jagdtiger": {"gun": ["8,8 cm PaK 43/3 L/71", "12,8 cm PaK 44 L/55", {"dmg": 240.0, "pen": 230.0, "caliber": 88.0, "shell": 1000.0, "reload": 5.0, "disp": 0.28}],
		"engine": ["Maybach HL 230 P30 ранний", "Maybach HL 230 P30", {"power": 650.0}], "susp": ["Jagdtiger (Henschel)", "Jagdtiger (Porsche)"]},
	"stuart": {"gun": ["37 мм M5", "37 мм M6", {"pen": 48.0, "shell": 820.0}],
		"engine": ["Continental W-670-8", "Continental W-670-9A", {"power": 220.0}], "susp": ["M3 ранний", "M3"]},
	"lee": {"gun": ["75 мм M2", "75 мм M3", {"pen": 75.0, "shell": 588.0}],
		"engine": ["Wright R975 EC2", "Wright R975 C1", {"power": 300.0}], "susp": ["M3 Lee ранний", "M3 Lee"]},
	"churchill": {"gun": ["QF 6-pdr Mk. V", "QF 75 mm Mk. V", {"dmg": 95.0, "pen": 95.0, "caliber": 57.0, "shell": 853.0, "reload": 2.1}],
		"engine": ["Bedford Twin-Six ранний", "Bedford Twin-Six", {"power": 325.0}], "susp": ["Churchill III", "Churchill VII"]},
	"comet": {"engine": ["Rolls-Royce Meteor Mk. III ранний", "Rolls-Royce Meteor Mk. III", {"power": 550.0}], "susp": ["Comet I ранний", "Comet I"]},
	"kv2": {"gun": ["122 мм У-11", "152 мм М-10", {"dmg": 320.0, "pen": 120.0, "caliber": 122.0, "shell": 515.0, "reload": 8.0, "disp": 0.52, "aim": 3.0}],
		"engine": ["В-2К", "В-2К форсированный", {"power": 500.0}], "susp": ["КВ-2 обр. 1940", "КВ-2 обр. 1941"]},
	"su85": {"engine": ["В-2-34", "В-2-34М", {"power": 470.0}], "susp": ["СУ-85", "СУ-85М"]},
	"luchs": {"gun": ["2 cm KwK 30", "2 cm KwK 38", {"pen": 40.0, "reload": 0.7}],
		"engine": ["Maybach HL 62 TR", "Maybach HL 66 P", {"power": 140.0}], "susp": ["VK 13.01", "Pz.Kpfw. II Ausf. L"]},
	"tiger_p": {"engine": ["2× Porsche Typ 101/1", "2× Porsche Typ 101/3", {"power": 540.0}], "susp": ["VK 45.01 (P)", "Tiger (P)"]},
	"pz4f2": {"gun": ["7,5 cm KwK 37 L/24", "7,5 cm KwK 40 L/43", {"dmg": 110.0, "pen": 60.0, "shell": 450.0, "disp": 0.48}],
		"engine": ["Maybach HL 120 TRM ранний", "Maybach HL 120 TRM", {"power": 265.0}], "susp": ["Pz.Kpfw. IV Ausf. F1", "Pz.Kpfw. IV Ausf. F2"]},
	"p26": {"gun": ["Cannone da 75/18", "Cannone da 75/34", {"pen": 60.0, "shell": 450.0, "disp": 0.48}],
		"engine": ["SPA 342 ранний", "SPA 342", {"power": 290.0}], "susp": ["P40 опытная", "P26/40"]},
	"turan": {"gun": ["40 мм 41.M", "75 мм 41.M", {"dmg": 70.0, "pen": 64.0, "caliber": 40.0, "shell": 800.0, "reload": 1.9, "disp": 0.4}],
		"turret": ["Башня 40M", "Башня 41M", {"tspd": 20.0, "hp": 720.0}],
		"engine": ["Manfréd Weiss V-8H ранний", "Manfréd Weiss V-8H", {"power": 230.0}], "susp": ["40M Turán I", "41M Turán II"]},
	"m10": {"engine": ["GM 6046 ранний", "GM 6046", {"power": 330.0}], "susp": ["VVSS", "VVSS усиленная"]},
	"easy8": {"gun": ["76 мм M1A1", "76 мм M1A2", {"disp": 0.38, "aim": 2.2}],
		"engine": ["Ford GAA ранний", "Ford GAA", {"power": 450.0}], "susp": ["HVSS ранняя", "HVSS"]},
	"pershing": {"engine": ["Ford GAF ранний", "Ford GAF", {"power": 450.0}], "susp": ["T26E3", "M26"]},
	"grant": {"gun": ["75 мм M2", "75 мм M3", {"pen": 75.0, "shell": 588.0}],
		"engine": ["Wright R975 EC2", "Wright R975 C1", {"power": 300.0}], "susp": ["Grant I ранний", "Grant I"]},
	"t70": {"engine": ["2× ГАЗ-202", "2× ГАЗ-203", {"power": 140.0}], "susp": ["Т-70", "Т-70М"]},
	"isu152": {"gun": ["122 мм А-19С", "152 мм МЛ-20С", {"dmg": 320.0, "pen": 160.0, "caliber": 122.0, "shell": 800.0, "reload": 8.0, "disp": 0.4}],
		"engine": ["В-2-ИС", "В-2-ИС форсированный", {"power": 480.0}], "susp": ["ИСУ-152 ранняя", "ИСУ-152"]},
	"tiger2": {"turret": ["Башня «Порше»", "Башня «Хеншель»", {"armor": [150, 80, 80, 100, 80, 80], "tslope": 25.0, "hp": 1720.0, "tspd": 16.0}],
		"engine": ["Maybach HL 230 P30 ранний", "Maybach HL 230 P30", {"power": 650.0}], "susp": ["Tiger II ранний", "Tiger II"]},
	"h38": {"gun": ["37 мм SA18", "37 мм SA38", {"pen": 32.0, "shell": 600.0, "dmg": 45.0}],
		"engine": ["Hotchkiss 6 цил.", "Hotchkiss 6 цил. форсированный", {"power": 75.0, "kmh": 28.0}], "susp": ["H35", "H38"]},
	"s35": {"engine": ["SOMUA V8 ранний", "SOMUA V8", {"power": 170.0}], "susp": ["S35 ранняя", "S35"]},
	"b1bis": {"engine": ["Renault 6 цил. 272 л. с.", "Renault 6 цил. 307 л. с.", {"power": 272.0}], "susp": ["B1", "B1 bis"]},
	"t26": {"gun": ["45 мм 20-К обр. 1932", "45 мм 20-К обр. 1938", {"pen": 43.0, "shell": 760.0}],
		"engine": ["ГАЗ Т-26 ранний", "ГАЗ Т-26", {"power": 90.0}], "susp": ["Т-26 обр. 1933", "Т-26 обр. 1939"]},
	"t60": {"engine": ["ГАЗ-202", "ГАЗ-203", {"power": 70.0}], "susp": ["Т-60 ранний", "Т-60"]},
	"m4a2": {"gun": ["75 мм M3", "76 мм M1A1", {"dmg": 120.0, "pen": 92.0, "caliber": 75.0, "shell": 619.0, "reload": 2.6}],
		"engine": ["GM 6046 ранний", "GM 6046", {"power": 375.0}], "susp": ["VVSS", "HVSS"]},
	"pz3b": {"engine": ["Maybach HL 108 TR", "Maybach HL 108 TR форсированный", {"power": 230.0}], "susp": ["Ausf. A", "Ausf. B"]},
	"pzj1": {"engine": ["Maybach NL 38 TR ранний", "Maybach NL 38 TR", {"power": 90.0}], "susp": ["Pz.Kpfw. I Ausf. B ранняя", "Pz.Kpfw. I Ausf. B"]},
	"hago": {"engine": ["Mitsubishi A6120VDe ранний", "Mitsubishi A6120VDe", {"power": 110.0}], "susp": ["Тип 95 ранний", "Тип 95"]},
	"chiha": {"gun": ["57 мм тип 97", "47 мм тип 1", {"dmg": 70.0, "pen": 55.0, "caliber": 47.0, "shell": 810.0, "reload": 2.0, "he": 0.0}],
		"engine": ["Mitsubishi SA12200VD ранний", "Mitsubishi SA12200VD", {"power": 150.0}], "susp": ["Тип 97", "Тип 97 «Синхото»"]},
}

# Снаряжение: многоразовое в бою, с перезарядкой; серебро списывается, если использовали
# (price — для V уровня, на других — пропорционально уровню).
const CONSUMABLES := {
	"repair": {"name": "Ремкомплект", "desc": "Чинит гусеницу и модули (уничтоженные — до «повреждён», двигатель тоже)",
		"cd": 90.0, "price": 1500},
	"medkit": {"name": "Аптечка", "desc": "Возвращает в строй раненый экипаж", "cd": 90.0, "price": 1500},
	"ext": {"name": "Огнетушитель", "desc": "Тушит пожар", "cd": 60.0, "price": 1000},
}
const REPAIR_FULL := {3: 1500, 4: 2400, 5: 3600, 6: 5200, 7: 7200, 8: 9600}  # ремонт уничтоженного танка

const SIDES := {
	"allies": {"name": "Союзники", "full": "Антигитлеровская коалиция"},
	"axis": {"name": "Ось", "full": "Страны Оси"},
}
const TEAM_BUDGET := 44  # боевой вес команды: пять-семь машин (средний танк — 7–8)
const TEAM_MAX := 7

const MODES := {
	"standard": {"name": "Стандартный бой", "desc": "Уничтожьте врагов или захватите их базу"},
	"encounter": {"name": "Встречный бой", "desc": "Одна нейтральная база в центре карты"},
	"supremacy": {"name": "Превосходство", "desc": "Держите точки A, B, C. Нужно 600 очков"},
}

# date/year — когда шло сражение; allies/axis — кто воевал (_g — в родительном падеже); nations — страны
# сторон (по ним окраска и позывные); roster — какие машины участвовали (в исторических составах
# в бой идут только они); season — для окраски: winter, desert, summer, late; brief — текст брифинга.
# winter — снег на крышах и побелка машин.
# Цвета земли для шейдера: трава/песок/снег (две тени), скала, дорога, грязь, гарь.
# grip — сопротивление грунта (1 — дорога), surf — материал поверхности для текстур.
# edge — высота холмов за краем поля (1 — горы); cover — облачность; fog — начало и конец дымки; sun — наклон и азимут солнца, °.
# weather — погода: mist — утренний туман у земли, snow — снегопад, haze — марево над раскалённой землёй.
const MAPS := {
	"prokhorovka": {"name": "Прохоровка", "desc": "Холмистые поля и деревня", "surf": "grass",
		"date": "12 июля 1943", "year": 1943, "allies": "СССР", "axis": "Германия", "allies_g": "СССР", "axis_g": "Германии",
		"nations": {"allies": ["СССР"], "axis": ["Германия", "Венгрия"]}, "season": "summer",
		"roster": {"allies": ["t34_76", "kv1", "t70", "t34_57", "su122", "su152", "kv85"], "axis": ["pz3", "pz4", "stug", "panther", "tiger", "nashorn", "ferdinand", "tiger_p", "turan", "pz3j", "pz3n", "grille", "brummbar", "pz2", "stug4"]},
		"brief": "Курская битва. Утром 12 июля 1943 года 5-я гвардейская танковая армия Ротмистрова контратаковала 2-й танковый корпус СС у станции Прохоровка. Сотни машин сошлись на узком поле между рекой Псёл и железной дорогой, бой шёл на коротких дистанциях: «тридцатьчетвёрки» старались подойти вплотную к «Тиграм», чьи 88-мм пушки били на километр.",
		"sky_top": "6c829b", "sky_hor": "c6c8bf", "fog": "b6b7ab", "sun": "fff0d8", "sun_e": 1.15, "amb": 0.42,
		"cover": 0.5, "fog_near": 520.0, "fog_far": 1900.0, "sun_rot": [-36.0, -42.0],
		"g1": "545c38", "g2": "8b8657", "rock": "78705e", "road": "7a6a4c", "dirt": "6a5a3a", "scorch": "26221d",
		"dust": "8a7c5c", "mini": "4a5236", "relief": 26.0, "grip": 0.85, "edge": 0.4},
	"alamein": {"name": "Эль-Аламейн", "desc": "Барханы и скалы Северной Африки", "surf": "sand",
		"date": "октябрь 1942", "year": 1942, "allies": "Великобритания", "axis": "Германия и Италия", "allies_g": "Великобритании",
		"axis_g": "Германии и Италии", "nations": {"allies": ["Великобритания"], "axis": ["Германия", "Италия"]}, "season": "desert",
		"roster": {"allies": ["sherman", "a10", "stuart", "lee", "grant", "tetrarch"], "axis": ["pz3", "pz4", "m13_40", "l6_40", "m15_42", "pz4f2", "p26", "pz3j", "pz3n", "grille", "sem10525", "l3cc"]},
		"brief": "Египет, октябрь–ноябрь 1942 года. 8-я британская армия Монтгомери прорывает оборону германо-итальянской танковой армии «Африка» Роммеля. Впервые в бой массово идут американские «Шерманы», полученные по ленд-лизу. После Эль-Аламейна войска Оси навсегда уходят из Египта.",
		"sky_top": "7aa0c4", "sky_hor": "ddd3bd", "fog": "d6ccb6", "sun": "fff0d0", "sun_e": 1.1, "amb": 0.45,
		"cover": 0.22, "fog_near": 520.0, "fog_far": 1900.0, "sun_rot": [-36.0, -42.0],
		"g1": "a39072", "g2": "c2b08e", "rock": "8f7556", "road": "9c8766", "dirt": "8e7350", "scorch": "3a3028",
		"dust": "c8aa78", "mini": "a08250", "relief": 30.0, "grip": 0.74, "weather": "haze"},
	"stalingrad": {"name": "Сталинград", "desc": "Руины зимнего города", "surf": "snow",
		"date": "зима 1942–1943", "year": 1942, "allies": "СССР", "axis": "Германия", "allies_g": "СССР", "axis_g": "Германии",
		"nations": {"allies": ["СССР"], "axis": ["Германия"]}, "season": "winter", "winter": true,
		"roster": {"allies": ["t34_76", "kv1", "kv2", "t70", "bt7", "t60"], "axis": ["pz3", "pz4", "stug", "pz38t", "pz3j", "pz3n", "grille"]},
		"brief": "Сталинград, зима 1942–1943 года. Бои идут за каждый дом разрушенного города. 19 ноября Красная армия начала операцию «Уран» и окружила 6-ю армию Паулюса; 2 февраля 1943 года её остатки капитулировали. Улицы завалены обломками, из-за угла можно получить снаряд в борт.",
		"sky_top": "8a97a4", "sky_hor": "c6cbd0", "fog": "bcc2c7", "sun": "e8eef5", "sun_e": 0.75, "amb": 0.55,
		"cover": 0.88, "fog_near": 300.0, "fog_far": 1300.0, "sun_rot": [-48.0, 20.0],
		"g1": "c9d1d8", "g2": "eef2f5", "rock": "7d8186", "road": "75797d", "dirt": "5d5650", "scorch": "2a2826",
		"dust": "e6ebef", "mini": "9aa4ae", "relief": 7.0, "grip": 0.78, "edge": 0.55, "weather": "snow",
		# на открытых улицах длинные 75-мм Pz IV и StuG бьют Т-34 и КВ раньше, чем те подходят:
		# без поправки Ось выигрывала здесь 16 боёв из 29, с 0,95 — 12 из 30
		"handicap": {"axis": 0.97}},
	"normandy": {"name": "Нормандия", "desc": "Бокаж: поля за земляными валами с живыми изгородями", "surf": "grass",
		"date": "июль 1944, утро", "year": 1944, "allies": "США и Великобритания", "axis": "Германия",
		"allies_g": "США и Великобритании", "axis_g": "Германии",
		"nations": {"allies": ["США", "Великобритания"], "axis": ["Германия"]}, "season": "summer",
		"roster": {"allies": ["sherman", "firefly", "cromwell", "churchill", "stuart", "m10", "m5a1", "achilles", "challenger"], "axis": ["pz4", "stug", "panther", "tiger", "tiger2", "jagdpanther", "luchs", "grille", "brummbar", "jpz4"]},
		"brief": "Франция, лето 1944 года. После высадки 6 июня союзники пробиваются вглубь Нормандии через бокаж — поля, разделённые земляными валами с живыми изгородями. Вал не пробить снарядом и не переехать, изгородь прячет засаду, а бой идёт на сотне метров. Британцы ставят 17-фунтовую пушку на «Шерман» — «Файрфлай» — единственный союзный танк, берущий «Пантеру» в лоб.",
		"sky_top": "7488a0", "sky_hor": "d3d2c8", "fog": "c9c8bf", "sun": "ffe0b8", "sun_e": 1.0, "amb": 0.5,
		"cover": 0.48, "fog_near": 260.0, "fog_far": 1350.0, "sun_rot": [-17.0, -100.0],
		"g1": "434f30", "g2": "687250", "rock": "77756a", "road": "766850", "dirt": "54452f", "scorch": "24211c",
		"dust": "857a5c", "mini": "3f4a30", "relief": 16.0, "grip": 0.84, "edge": 0.35, "weather": "mist"},
	"berlin": {"name": "Берлин", "desc": "Штурм столицы Рейха: проспекты, руины, Рейхстаг", "surf": "urban",
		"date": "апрель 1945", "year": 1945, "allies": "СССР", "axis": "Германия", "allies_g": "СССР", "axis_g": "Германии",
		"nations": {"allies": ["СССР"], "axis": ["Германия"]}, "season": "late",
		"roster": {"allies": ["t34", "is2", "su100", "su85", "isu152", "t34_57", "su122", "m4a2"], "axis": ["pz4", "stug", "panther", "tiger2", "jagdpanther", "hetzer", "jagdtiger", "ferdinand", "jpz4", "grille", "brummbar"]},
		"brief": "Берлин, апрель 1945 года. 1-й Белорусский и 1-й Украинский фронты штурмуют столицу Рейха. Советские танки идут по улицам с белыми полосами на башнях и крестами на крышах — опознавательным знаком операции. Город обороняют последние «Пантеры», штурмовые орудия и «Королевские тигры» 503-го батальона. 2 мая гарнизон Берлина капитулировал.",
		"sky_top": "75787b", "sky_hor": "b3a896", "fog": "a49b8c", "sun": "f4dfc4", "sun_e": 0.85, "amb": 0.5,
		"cover": 0.72, "fog_near": 320.0, "fog_far": 1400.0, "sun_rot": [-30.0, 28.0],
		"g1": "5c554a", "g2": "726a5c", "rock": "6c6862", "road": "57554f", "dirt": "4c4238", "scorch": "201d1a",
		"dust": "8c8272", "mini": "5a5650", "relief": 5.0, "grip": 0.88, "edge": 0.3},
	"ardennes": {"name": "Арденны", "desc": "Заснеженные еловые леса, гребень и бельгийская деревня", "surf": "snow",
		"date": "декабрь 1944", "year": 1944, "allies": "США", "axis": "Германия", "allies_g": "США", "axis_g": "Германии",
		"nations": {"allies": ["США"], "axis": ["Германия"]}, "season": "winter", "winter": true,
		"roster": {"allies": ["sherman", "firefly", "stuart", "easy8", "pershing", "m10", "chaffee", "m5a1", "jumbo", "m18", "t28"], "axis": ["pz4", "stug", "panther", "tiger2", "jagdpanther", "hetzer", "luchs", "jpz4", "brummbar"]},
		"brief": "Бельгия, декабрь 1944 года. 16 декабря три германские армии внезапно ударили по растянутому фронту американцев в заснеженных Арденнах, рассчитывая прорваться к Антверпену. Низкие облака прижали к земле авиацию союзников. Окружённая в Бастони 101-я воздушно-десантная дивизия на предложение сдаться ответила одним словом: «Nuts!» — а 26 декабря к городу пробились танки 4-й бронетанковой дивизии Паттона. Бои идут на лесных опушках, у деревень и на перекрёстках дорог.",
		"sky_top": "8b96a2", "sky_hor": "c8cdd2", "fog": "c0c6cb", "sun": "e6ecf3", "sun_e": 0.7, "amb": 0.58,
		"cover": 0.82, "fog_near": 280.0, "fog_far": 1350.0, "sun_rot": [-24.0, 150.0],
		"g1": "cdd5dc", "g2": "eef2f5", "rock": "6c7076", "road": "8b8681", "dirt": "5a4e44", "scorch": "2a2826",
		"dust": "e6ebef", "mini": "a4adb5", "relief": 18.0, "grip": 0.8, "edge": 0.75, "weather": "snow"},
	"france": {"name": "Франция", "desc": "Гряда над Мёзом, городок и сады", "surf": "grass",
		"date": "май 1940", "year": 1940, "allies": "Франция и Великобритания", "axis": "Германия",
		"allies_g": "Франции и Великобритании", "axis_g": "Германии",
		"nations": {"allies": ["Франция", "Великобритания"], "axis": ["Германия"]}, "season": "summer",
		"roster": {"allies": ["h38", "s35", "b1bis", "a10"], "axis": ["pz2", "pz38t", "pz3b", "pzj1"]},
		"brief": "Франция, май 1940 года. Германские танковые дивизии прошли через Арденны, которые французское командование считало непроходимыми для танков, и 13 мая форсировали Мёз у Седана. У деревни Стонн несколько дней шли встречные бои: тяжёлый Char B1 bis «Эр» капитана Бийота за один бой подбил тринадцать немецких танков, а 37-мм снаряды его броню не брали. Но французские танки были раздроблены по пехотным частям и многие воевали без радио, а немцы — собранными в кулак дивизиями.",
		"sky_top": "6f8fb0", "sky_hor": "cfd4c8", "fog": "bfc4b6", "sun": "fff3dc", "sun_e": 1.1, "amb": 0.45,
		"cover": 0.4, "fog_near": 520.0, "fog_far": 1900.0, "sun_rot": [-40.0, -30.0],
		"g1": "4d6236", "g2": "7f8a52", "rock": "7a7466", "road": "857a62", "dirt": "6a5b40", "scorch": "26221d",
		"dust": "8f8566", "mini": "48582f", "relief": 22.0, "grip": 0.86, "edge": 0.45},
	"moscow": {"name": "Подмосковье", "desc": "Заснеженная деревня, ельник и противотанковый рубеж", "surf": "snow",
		"date": "декабрь 1941", "year": 1941, "allies": "СССР", "axis": "Германия", "allies_g": "СССР", "axis_g": "Германии",
		"nations": {"allies": ["СССР"], "axis": ["Германия"]}, "season": "winter", "winter": true,
		"roster": {"allies": ["t34_76", "kv1", "t26", "t60", "bt7", "t34_57"], "axis": ["pz3j", "pz38t", "pz2", "stug", "pzj1", "pz3b"]},
		"brief": "Битва за Москву, декабрь 1941 года. Немецкое наступление «Тайфун» выдохлось в нескольких десятках километров от столицы: морозы до −30 °C, бездорожье, сожжённые деревни. 5–6 декабря Красная армия перешла в контрнаступление. На Волоколамском шоссе дралась 1-я гвардейская танковая бригада Катукова: из засад за избами и ельниками «тридцатьчетвёрки» и КВ выбивали германские танки, а лёгкие Т-60 и Т-26 шли в бой вместе с пехотой.",
		"sky_top": "8b96a2", "sky_hor": "c8cdd2", "fog": "c0c6cb", "sun": "e6ecf3", "sun_e": 0.7, "amb": 0.58,
		"cover": 0.8, "fog_near": 300.0, "fog_far": 1400.0, "sun_rot": [-18.0, 160.0],
		"g1": "cdd5dc", "g2": "eef2f5", "rock": "6c7076", "road": "8b8681", "dirt": "5a4e44", "scorch": "2a2826",
		"dust": "e6ebef", "mini": "a4adb5", "relief": 16.0, "grip": 0.78, "edge": 0.6, "weather": "snow"},
	"khalkhin": {"name": "Халхин-Гол", "desc": "Степь, барханы и высота Баин-Цаган", "surf": "grass",
		"date": "август 1939", "year": 1939, "allies": "СССР", "axis": "Япония", "allies_g": "СССР", "axis_g": "Японии",
		"nations": {"allies": ["СССР"], "axis": ["Япония"]}, "season": "summer",
		"roster": {"allies": ["bt7", "t26"], "axis": ["hago", "chiha"]},
		"brief": "Монголия, лето 1939 года. Японская Квантунская армия перешла реку Халхин-Гол. В начале июля у горы Баин-Цаган Жуков бросил в бой танковую бригаду с ходу, без пехоты: БТ понесли большие потери, но японцев отбросили за реку. 20 августа советско-монгольские войска ударили по флангам и за десять дней окружили и разгромили японскую группировку. Это поражение во многом удержало Японию от войны с СССР в 1941 году.",
		"sky_top": "6f97c2", "sky_hor": "d6d3c0", "fog": "cfcab4", "sun": "fff0d0", "sun_e": 1.15, "amb": 0.44,
		"cover": 0.3, "fog_near": 560.0, "fog_far": 2000.0, "sun_rot": [-38.0, -50.0],
		"g1": "8a8358", "g2": "a89f6c", "rock": "8a7a5e", "road": "9c8a68", "dirt": "86704e", "scorch": "302a22",
		"dust": "b8a478", "mini": "8a8052", "relief": 28.0, "grip": 0.82, "edge": 0.35, "weather": "haze"},
}

# Позывные по странам (не меньше 2 × TEAM_MAX). У британцев и американцев — фонетический алфавит
# своих армий тех лет с номером машины.
const CALLSIGNS := {
	"СССР": ["Волк", "Ястреб", "Кобра", "Берёза", "Север", "Орёл", "Гром", "Лис", "Барс", "Шторм", "Сокол", "Беркут",
		"Медведь", "Рысь", "Ворон", "Стрела", "Молот", "Кремень", "Буран", "Дозор"],
	"Германия": ["Adler", "Falke", "Wolf", "Bär", "Luchs", "Puma", "Fuchs", "Greif", "Sperber", "Kondor", "Habicht",
		"Marder", "Dachs", "Iltis", "Uhu", "Hirsch", "Wiesel", "Otter", "Biber", "Keiler"],
	"США": ["Able 1", "Able 2", "Baker 1", "Baker 2", "Charlie 1", "Charlie 2", "Dog 1", "Dog 2", "Easy 1", "Easy 2",
		"Fox 1", "Fox 2", "George 1", "George 2", "How 1", "How 2", "Item 1", "Item 2", "King 1", "King 2"],
	"Великобритания": ["Ack 1", "Ack 2", "Beer 1", "Beer 2", "Charlie 1", "Charlie 2", "Don 1", "Don 2", "Edward 1",
		"Edward 2", "Freddie 1", "Freddie 2", "George 1", "George 2", "Harry 1", "Harry 2", "Johnnie 1", "Johnnie 2",
		"King 1", "King 2"],
	"Италия": ["Leone", "Aquila", "Lupo", "Falco", "Orso", "Volpe", "Grifo", "Toro", "Saetta", "Fulmine", "Tuono",
		"Ardito", "Folgore", "Ariete", "Centauro", "Vipera", "Sparviero", "Cinghiale", "Nibbio", "Gufo"],
	"Франция": ["Lion 1", "Lion 2", "Aigle 1", "Aigle 2", "Loup 1", "Loup 2", "Tigre 1", "Tigre 2", "Ours 1", "Ours 2",
		"Faucon 1", "Faucon 2", "Renard 1", "Renard 2", "Cerf 1", "Cerf 2", "Sanglier 1", "Sanglier 2", "Vautour 1", "Vautour 2"],
	"Япония": ["Taka", "Washi", "Tora", "Ōkami", "Kuma", "Hayabusa", "Kitsune", "Inazuma", "Arashi", "Kaze", "Kumo",
		"Yari", "Katana", "Raijin", "Fūjin", "Sakura", "Matsu", "Take", "Ume", "Kiri"],
	"Венгрия": ["Sas", "Holló", "Farkas", "Medve", "Sólyom", "Turul", "Párduc", "Hiúz", "Bika", "Vihar", "Villám",
		"Rigó", "Bagoly", "Kánya", "Héja", "Ölyv", "Darázs", "Csuka", "Róka", "Szarvas"],
}
const LANG := {"СССР": "ru", "Германия": "de", "США": "en", "Великобритания": "en", "Италия": "it", "Венгрия": "hu",
	"Франция": "fr", "Япония": "ja"}

# Переговоры по рации своей стороны: на её языке, для немецкого и английского — с переводом.
# {h} — направление «по часам» от корпуса игрока, {clock} — оно же по-русски («2 часа»), {cs} — позывной.
const RADIO := {
	"start": {
		"ru": [["Всем! Задача ясна — вперёд!", ""], ["Я «{cs}». Выдвигаемся, держать строй!", ""]],
		"de": [["Panzer marsch!", "Танки, вперёд!"], ["Hier {cs}. Vorwärts, Abstand halten!", "Говорит {cs}. Вперёд, держать дистанцию!"]],
		"en": [["All stations, advance!", "Всем, вперёд!"], ["{cs} here. Move out, keep spread!", "Говорит {cs}. Выдвигаемся, не кучковаться!"]],
		"it": [["Carri, avanti!", "Танки, вперёд!"], ["Qui {cs}. Avanti, mantenere le distanze!", "Говорит {cs}. Вперёд, держать дистанцию!"]],
		"fr": [["Chars, en avant !", "Танки, вперёд!"], ["Ici {cs}. En avant, gardez vos distances !", "Говорит {cs}. Вперёд, держать дистанцию!"]],
		"ja": [["Sensha, zenshin!", "Танки, вперёд!"], ["Kochira {cs}. Zenshin, kankaku o tamote!", "Говорит {cs}. Вперёд, держать дистанцию!"]],
		"hu": [["Harckocsik, előre!", "Танки, вперёд!"], ["Itt {cs}. Előre, tartsátok a távolságot!", "Говорит {cs}. Вперёд, держать дистанцию!"]]},
	"spot": {
		"ru": [["Танк противника на {clock}!", ""], ["Вижу противника на {clock}!", ""]],
		"de": [["Feindpanzer auf {h} Uhr!", "Вражеский танк на {clock}!"], ["Achtung, Feind auf {h} Uhr!", "Внимание, противник на {clock}!"]],
		"en": [["Enemy tank, {h} o'clock!", "Вражеский танк на {clock}!"], ["Contact, {h} o'clock!", "Контакт на {clock}!"]],
		"it": [["Carro nemico a ore {h}!", "Вражеский танк на {clock}!"], ["Attenzione, nemico a ore {h}!", "Внимание, противник на {clock}!"]],
		"fr": [["Char ennemi à {h} heures !", "Вражеский танк на {clock}!"], ["Attention, ennemi à {h} heures !", "Внимание, противник на {clock}!"]],
		"ja": [["Teki sensha, {h}-ji no hōkō!", "Вражеский танк на {clock}!"], ["Chūi, teki {h}-ji!", "Внимание, противник на {clock}!"]],
		"hu": [["Ellenséges harckocsi {h} óránál!", "Вражеский танк на {clock}!"], ["Figyelem, ellenség {h} óránál!", "Внимание, противник на {clock}!"]]},
	"spot_tiger": {
		"ru": [["Осторожно, «Тигр» на {clock}!", ""]],
		"de": [["Feindpanzer auf {h} Uhr!", "Вражеский танк на {clock}!"]],
		"en": [["Tiger! Tiger at {h} o'clock!", "«Тигр»! «Тигр» на {clock}!"]],
		"it": [["Carro nemico a ore {h}!", "Вражеский танк на {clock}!"]],
		"fr": [["Char ennemi à {h} heures !", "Вражеский танк на {clock}!"]],
		"ja": [["Teki sensha, {h}-ji no hōkō!", "Вражеский танк на {clock}!"]],
		"hu": [["Ellenséges harckocsi {h} óránál!", "Вражеский танк на {clock}!"]]},
	"ally_down": {
		"ru": [["«{cs}» подбит!", ""], ["Потеряли «{cs}»!", ""]],
		"de": [["{cs} ist ausgefallen!", "{cs} подбит!"], ["{cs} brennt!", "{cs} горит!"]],
		"en": [["{cs} is hit, they're bailing out!", "{cs} подбит, экипаж покидает машину!"], ["We've lost {cs}!", "Потеряли {cs}!"]],
		"it": [["{cs} è stato colpito!", "{cs} подбит!"], ["{cs} brucia!", "{cs} горит!"]],
		"fr": [["{cs} est touché !", "{cs} подбит!"], ["{cs} brûle !", "{cs} горит!"]],
		"ja": [["{cs}, hidan!", "{cs} подбит!"], ["{cs} ga moete iru!", "{cs} горит!"]],
		"hu": [["{cs} találatot kapott!", "{cs} подбит!"], ["{cs} ég!", "{cs} горит!"]]},
	"enemy_down": {
		"ru": [["Готов! Есть один!", ""], ["Горит, гад!", ""]],
		"de": [["Abschuss!", "Подбит!"], ["Volltreffer, er brennt!", "Прямое попадание, горит!"]],
		"en": [["Got him!", "Есть, подбил!"], ["Scratch one!", "Минус один!"]],
		"it": [["Colpito, brucia!", "Попал, горит!"], ["Centrato!", "Прямое попадание!"]],
		"fr": [["Touché, il brûle !", "Попал, горит!"], ["En plein dedans !", "Прямое попадание!"]],
		"ja": [["Meichū, moete iru!", "Попал, горит!"], ["Chokugeki!", "Прямое попадание!"]],
		"hu": [["Kilőve!", "Подбит!"], ["Telitalálat, ég!", "Прямое попадание, горит!"]]},
	"our_base": {
		"ru": [["Противник на нашей базе! Все назад!", ""]],
		"de": [["Feind in unserer Stellung! Zurück!", "Противник на нашей позиции! Назад!"]],
		"en": [["They're taking our base! Fall back!", "Захватывают нашу базу! Назад!"]],
		"it": [["Il nemico è nella nostra posizione! Indietro!", "Противник на нашей позиции! Назад!"]],
		"fr": [["L'ennemi est sur notre position ! Repli !", "Противник на нашей позиции! Назад!"]],
		"ja": [["Teki ga jinchi ni iru! Kōtai!", "Противник на нашей позиции! Назад!"]],
		"hu": [["Az ellenség az állásunkban! Vissza!", "Противник на нашей позиции! Назад!"]]},
	"their_base": {
		"ru": [["Захватываем базу, прикройте!", ""]],
		"de": [["Wir nehmen die Stellung, Feuerschutz!", "Занимаем позицию, прикройте огнём!"]],
		"en": [["Capturing the base, cover us!", "Захватываем базу, прикройте!"]],
		"it": [["Occupiamo la posizione, copriteci!", "Занимаем позицию, прикройте!"]],
		"fr": [["Nous prenons la position, couvrez-nous !", "Занимаем позицию, прикройте!"]],
		"ja": [["Jinchi o senryō suru, engo seyo!", "Занимаем позицию, прикройте!"]],
		"hu": [["Elfoglaljuk az állást, fedezzetek!", "Занимаем позицию, прикройте!"]]},
	"last": {
		"ru": [["Нас осталось мало — держаться!", ""]],
		"de": [["Wir sind nur noch wenige — haltet aus!", "Нас осталось мало — держитесь!"]],
		"en": [["We're nearly done for — hold on!", "Нас почти не осталось — держитесь!"]],
		"it": [["Siamo rimasti in pochi — resistete!", "Нас осталось мало — держитесь!"]],
		"fr": [["Nous ne sommes plus que quelques-uns — tenez bon !", "Нас осталось мало — держитесь!"]],
		"ja": [["Nokori wazuka da — fumitodomare!", "Нас осталось мало — держитесь!"]],
		"hu": [["Kevesen maradtunk — kitartás!", "Нас осталось мало — держитесь!"]]},
}


## Экипаж (человек): 5 — командир, наводчик, заряжающий, мехвод, радист; 4 — без радиста; 3 — командир,
## наводчик, мехвод; 2 — командир (он же наводчик и заряжающий) и мехвод.
const CREW_N := {"t34_76": 4, "t34": 5, "kv1": 5, "is2": 4, "sherman": 5, "firefly": 4, "cromwell": 5, "chaffee": 5,
	"a10": 5, "pz3": 5, "pz4": 5, "stug": 4, "panther": 5, "tiger2": 5, "tiger": 5, "m13_40": 4, "jagdpanther": 5,
	"su100": 4, "pz38t": 4, "l6_40": 2, "m15_42": 4, "hetzer": 4, "nashorn": 5, "ferdinand": 5, "jagdtiger": 5, "stuart": 4,
	"lee": 5, "churchill": 5, "comet": 5, "kv2": 5, "su85": 4, "luchs": 4, "tiger_p": 5, "pz4f2": 5, "p26": 4, "turan": 5,
	"m10": 5, "easy8": 5, "pershing": 5, "grant": 5, "t70": 2, "isu152": 5,
	"bt7": 3, "t34_57": 4, "su122": 5, "kv85": 4, "su152": 5, "pz3j": 5, "pz3n": 5, "grille": 4, "brummbar": 5, "jpz4": 4,
	"m5a1": 4, "jumbo": 5, "m18": 5, "t28": 4, "tetrarch": 3, "achilles": 5, "challenger": 5, "sem10525": 3, "l3cc": 2,
	"pz2": 3, "stug4": 4, "h38": 2, "s35": 3, "b1bis": 4, "t26": 3, "t60": 2, "m4a2": 5, "pz3b": 5, "pzj1": 3,
	"hago": 3, "chiha": 4}


static func crew_n(key: String) -> int:
	if TYPES.has(key) and TYPES[key].has("crew"):
		return int(TYPES[key].crew)
	return int(CREW_N.get(key, 4))


## Виды снарядов (как AmmoKind в native/src/common.h): основной бронебойный, подкалиберный, фугасный,
## кумулятивный, дымовой. short — подпись на кнопке, price — серебро за выстрел (× уровень танка).
const AMMO := [
	{"name": "Бронебойный", "short": "ББ", "price": 0},
	{"name": "Подкалиберный", "short": "ПК", "price": 12},
	{"name": "Осколочно-фугасный", "short": "ОФ", "price": 0},
	{"name": "Кумулятивный", "short": "КС", "price": 8},
	{"name": "Дымовой", "short": "ДЫМ", "price": 5},
]
## Подкалиберные: с какого года и во сколько раз пробитие больше основного (PzGr 40, БР-240П/350П, HVAP, APDS).
const APCR := {"Германия": [1940, 1.35, 20.0, 88.0], "СССР": [1942, 1.3, 45.0, 85.0], "США": [1944, 1.45, 76.0, 90.0],
	"Великобритания": [1944, 1.3, 57.0, 77.0]}


## Боекомплект орудия в бою года year: [{kind, name, short, pen, dmg, he, vel_k, left}], первый — основной (без счёта).
## Подкалиберные — где и когда они были; кумулятивные — у короткоствольных пушек и гаубиц от 75 мм с 1942 года
## (кроме советских 152 мм); фугасные — у всех от 37 мм; дымовые — от 75 мм.
static func ammo_types(T: Dictionary, year: int) -> Array:
	var cal: float = T.caliber
	var pen: float = T.pen
	var dmg: float = T.dmg
	var v: float = T.get("shell", 700.0)
	var nation := String(T.get("nation", ""))
	var he := shell_he(T)
	var out: Array = [{"kind": 0, "name": "Бронебойный" + (" (каморный)" if he > 0.0 else ""), "short": "БР" if he > 0.0 else "ББ",
		"pen": pen, "dmg": dmg, "he": he, "vel_k": 1.0, "left": -1}]
	var cr: Array = APCR.get(nation, [])
	if not cr.is_empty() and year >= int(cr[0]) and cal >= float(cr[2]) and cal <= float(cr[3]) and v >= 600.0:
		out.append({"kind": 1, "name": "Подкалиберный", "short": "ПК", "pen": roundf(pen * float(cr[1])), "dmg": roundf(dmg * 0.55),
			"he": 0.0, "vel_k": 1.2, "left": 6})
	if cal >= 37.0:
		var he_g := 0.0015 * cal * cal * cal  # ВВ фугасного снаряда, г (75 мм ~630, 152 мм ~5300)
		out.append({"kind": 2, "name": "Осколочно-фугасный", "short": "ОФ", "pen": roundf(0.14 * cal + 0.004 * he_g), "dmg": dmg,
			"he": he_g, "vel_k": 0.92, "left": 15})
	if year >= 1942 and cal >= 75.0 and v <= 520.0 and not (nation == "СССР" and cal > 130.0):
		out.append({"kind": 3, "name": "Кумулятивный", "short": "КС", "pen": roundf(40.0 + cal * 0.8), "dmg": roundf(dmg * 0.9),
			"he": 0.0, "vel_k": 1.0, "left": 8})
	if cal >= 75.0:
		out.append({"kind": 4, "name": "Дымовой", "short": "ДЫМ", "pen": 0.0, "dmg": 0.0, "he": 0.0, "vel_k": 0.92, "left": 3})
	return out


## Масса ВВ в бронебойном снаряде, г (в тротиловом эквиваленте, упрощённо по стране и калибру):
## каморные снаряды СССР, Германии, США рвутся за бронёй; британские и малокалиберные — сплошные болванки.
## Орудие сменили модулем — калибр другой, и снаряд тоже.
static func shell_he(T: Dictionary) -> float:
	if T.has("he"):
		return float(T.he)
	var cal: float = T.caliber
	match String(T.get("nation", "")):
		"СССР":
			if cal <= 25.0: return 0.0
			if cal <= 57.0: return 20.0  # 45 мм БР-240
			if cal <= 77.0: return 150.0  # 76 мм БР-350А
			if cal <= 86.0: return 48.0  # 85 мм БР-365
			if cal <= 101.0: return 65.0  # 100 мм БР-412
			if cal <= 123.0: return 156.0  # 122 мм БР-471
			return 480.0  # 152 мм БР-540
		"Германия":
			if cal <= 25.0: return 0.0
			if cal <= 38.0: return 13.0  # 3,7 см PzGr
			if cal <= 51.0: return 17.0  # 5 см PzGr 39
			if cal <= 76.0: return 29.0  # 7,5 см PzGr 39
			if cal <= 89.0: return 109.0  # 8,8 см PzGr 39
			return 300.0  # 12,8 см PzGr 43
		"США":
			if cal <= 38.0: return 0.0  # 37 мм M51 — сплошной
			if cal <= 77.0: return 64.0  # 75/76 мм M61/M62
			return 137.0  # 90 мм M82
		"Великобритания":
			# 2-, 6-, 17-фунтовые и 77 мм — сплошные болванки; 75 мм — американский M61
			return 64.0 if absf(cal - 75.0) < 0.6 else 0.0
		"Италия":
			if cal <= 25.0: return 0.0
			if cal <= 48.0: return 31.0  # 47 мм EP
			return 48.0  # 75 мм EP
		"Венгрия":
			return 30.0 if cal >= 70.0 else 0.0
		"Франция":
			# 47 мм APX и SA35 — каморный снаряд со слабым зарядом, 37 мм — сплошной
			return 15.0 if cal >= 45.0 else 0.0
		"Япония":
			if cal <= 38.0: return 10.0  # 37 мм тип 94
			if cal <= 48.0: return 20.0  # 47 мм тип 1
			return 250.0  # 57 мм тип 97 — осколочно-фугасный
	return 0.0


## Производные величины в единицах карты.
static func derived(T: Dictionary) -> Dictionary:
	return {
		"speed": float(T.kmh) / 3.6 * UPM * SPEED_K,
		"rev_speed": float(T.rev) / 3.6 * UPM * SPEED_K,
		"turn": deg_to_rad(T.turn),
		"tspd": deg_to_rad(T.tspd),
		"shell_v": float(T.shell) * SHELL_SCALE,
		"disp": float(T.disp) / 100.0,  # рад: разброс в метрах на 100 м
		"spot": float(T.spot) * UPM * SPOT_K,
		"slope": deg_to_rad(T.slope),
		"tslope": deg_to_rad(T.get("tslope", 14.0)),
		"trav": deg_to_rad(T.get("traverse", 180.0)),
		"casemate": T.has("traverse"),
		# лоб, который средние пушки не берут: такой танк держат лбом к противнику
		"armored": float(T.armor[0]) / cos(deg_to_rad(T.slope)) >= 100.0,
		"stab": float(T.get("stab", 0.0)),
		"side_slope": deg_to_rad(T.side_slope),
		"elev": [deg_to_rad(T.elev[0]), deg_to_rad(T.elev[1])],
		"L": float(T.len) * UPM,
		"W": float(T.wid) * UPM,
		"accel": 2.4 * float(T.power) / float(T.mass),  # тяговооружённость → разгон, ед/с²
	}


## Противоположная сторона.
static func foe_side(side: String) -> String:
	return "axis" if side == "allies" else "allies"


## Машины стороны, которые могут выйти на карту: по историческому составу или все.
static func roster(map_key: String, side: String, history: bool) -> Array:
	if history:
		return MAPS[map_key].roster[side]
	var out: Array = []
	for k in TYPES:
		if TYPES[k].side == side:
			out.append(k)
	return out


## Карты, на которых воевал танк.
static func maps_for(key: String, history: bool) -> Array:
	var out: Array = []
	for m in MAPS:
		if not history or MAPS[m].roster[TYPES[key].side].has(key):
			out.append(m)
	return out


## Подбор команды: машины из состава случайно (чаще — массовые), пока хватает боевого веса.
## first — танк, который точно будет в команде (игрок).
static func compose(pool: Array, first: String, budget: int, rng: RandomNumberGenerator, year: int) -> Array:
	var team: Array = [first] if first != "" else []
	var sum := team_pts(team, year)
	while team.size() < TEAM_MAX:
		var fit: Array = []
		var wsum := 0.0
		for k in pool:
			if sum + pts(k, year) <= budget:
				fit.append(k)
				wsum += float(TYPES[k].freq)
		if fit.is_empty():
			break
		var r := rng.randf() * wsum
		var pick: String = fit[-1]
		for k in fit:
			r -= float(TYPES[k].freq)
			if r <= 0.0:
				pick = k
				break
		team.append(pick)
		sum += pts(pick, year)
	return team


## Две команды равного боевого веса: много случайных составов каждой стороны,
## из них — случайная пара с одинаковой суммой (иначе ближайшая).
## tier — уровень боя: на VII–VIII вес команды больше, чтобы тяжёлых машин было не по три.
## k_mine, k_theirs — поправка карты (handicap): вес команды стороны относительно другой.
static func match_teams(mine: Array, theirs: Array, first: String, rng: RandomNumberGenerator, year: int, tier := 5,
		k_mine := 1.0, k_theirs := 1.0) -> Array:
	# у лёгких машин семь танков не набирают полного веса: бюджет — по более лёгкой стороне
	var budget := mini(TEAM_BUDGET + maxi(0, tier - 6) * 9, int(minf(_mean_pts(mine, year), _mean_pts(theirs, year)) * TEAM_MAX))
	var a_list: Array = []
	var b_list: Array = []
	for i in 40:
		a_list.append(compose(mine, first, int(budget * k_mine), rng, year))
		b_list.append(compose(theirs, "", int(budget * k_theirs), rng, year))
	var pairs: Array = []
	var best: Array = [a_list[0], b_list[0]]
	var best_d := 1 << 20
	for a in a_list:
		if a.size() < 3:
			continue
		for b in b_list:
			if b.size() < 3:
				continue
			var d := absi(roundi(team_pts(a, year) / k_mine) - roundi(team_pts(b, year) / k_theirs))
			if d == 0:
				pairs.append([a, b])
			elif d < best_d:
				best_d = d
				best = [a, b]
	if not pairs.is_empty():
		return pairs[rng.randi() % pairs.size()]
	return best


static func _mean_pts(pool: Array, year: int) -> float:
	if pool.is_empty():
		return 7.0
	var s := 0.0
	for k in pool:
		s += pts(k, year)
	return s / pool.size()


## Машины стороны для боя: из состава карты уровнем не дальше ±1 от танка игрока
## (если таких нет — диапазон шире).
static func pool(map_key: String, side: String, history: bool, tier: int) -> Array:
	var all := roster(map_key, side, history)
	for spread in [1, 2, 3]:
		var out: Array = []
		for k in all:
			if absi(int(TYPES[k].tier) - tier) <= spread:
				out.append(k)
		if not out.is_empty():
			return out
	return all


static func team_pts(team: Array, year: int) -> int:
	var s := 0
	for k in team:
		s += pts(k, year)
	return s


## Боевой вес машины в модификации данного года: к 1944-му немецкие средние танки
## встречают более сильных противников, и их вес ниже.
static func pts(key: String, year: int) -> int:
	var p: int = TYPES[key].pts
	var vars: Dictionary = TYPES[key].get("variants", {})
	var best := 0
	for y in vars:
		if int(y) <= year and int(y) > best and vars[y].has("pts"):
			best = int(y)
			p = vars[y].pts
	return p


## Характеристики танка в модификации данного года (Pz IV G → H → J, Panther D → A → G)
## с установленными модулями: top — {слот: true, если стоит исследованный}; нет слота — исследованный.
static func spec(key: String, year: int, top := {}) -> Dictionary:
	var T: Dictionary = TYPES[key].duplicate(true)
	var best := 0
	var vars: Dictionary = T.get("variants", {})
	for y in vars:
		if int(y) <= year and int(y) > best:
			best = int(y)
	if best > 0:
		T.merge(vars[best], true)
	var mods: Dictionary = MODULES.get(key, {})
	for slot in mods:
		if top.get(slot, true):
			continue
		if slot == "susp":
			T.turn = float(T.turn) * 0.88
		if mods[slot].size() > 2:
			T.merge((mods[slot][2] as Dictionary).duplicate(true), true)
	return T


## Модули машины бота: чаще исследованные, иногда стоковые.
static func random_mods(key: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for slot in MODULES.get(key, {}):
		out[slot] = rng.randf() < 0.65
	return out


## Цена снаряжения для танка данного уровня.
static func cons_price(name: String, tier: int) -> int:
	return roundi(float(CONSUMABLES[name].price) * tier / 5.0 / 100.0) * 100


static func tier(key: String) -> int:
	return int(TYPES[key].tier)


## Опыт на исследование и цена танка.
static func research_xp(key: String) -> int:
	return RESEARCH_XP[tier(key)]


static func price(key: String) -> int:
	return PRICE[tier(key)]


## Опыт и серебро за исследованный модуль.
static func module_xp(key: String, slot: String) -> int:
	return roundi(RESEARCH_XP[tier(key)] * float(SLOT_XP[slot]) / 10.0) * 10


static func module_price(key: String, slot: String) -> int:
	return roundi(PRICE[tier(key)] * float(SLOT_PRICE[slot]) / 100.0) * 100


## Из каких танков исследуется этот.
static func parents(key: String) -> Array:
	var out: Array = []
	for k in TREE:
		if (TREE[k] as Array).has(key):
			out.append(k)
	return out


## Чья армия ведёт танк на этой карте. В исторических составах — страна, воевавшая здесь
## (британский «Шерман» под Эль-Аламейном), иначе — страна-производитель.
static func operator(key: String, map_key: String, history: bool) -> String:
	var nat: String = TYPES[key].nation
	if not MAPS.has(map_key):
		return nat
	var list: Array = MAPS[map_key].nations[TYPES[key].side]
	if history and not list.has(nat):
		return list[0]
	return nat


## Окраска и опознавательные знаки по стране и сезону:
## СССР — 4БО, зимой побелка, в Берлине белые полосы на башне и крест на крыше;
## Германия — серая с побелкой (1942, зима), «Африканский корпус», тёмно-жёлтая с полосами (1943),
## трёхцветный «засадный» камуфляж (1944–1945); США — оливковая со звездой;
## Великобритания — пустынная с бело-красно-белой полосой или оливковая с белой звездой союзников;
## зимой 1944-го немцы и американцы — с побелкой поверх своей окраски.
static func paint(key: String, map_key: String, history: bool) -> Dictionary:
	var nat := operator(key, map_key, history)
	var season: String = MAPS[map_key].season if MAPS.has(map_key) else "summer"
	var year: int = MAPS[map_key].year if MAPS.has(map_key) else int(TYPES[key].year)
	match nat:
		"СССР":
			if season == "winter":
				return {"camo": "whitewash", "emblem": "ussr"}
			return {"camo": "green", "emblem": "ussr", "band": season == "late"}
		"Германия":
			if season == "winter":
				# в 1942-м — побелка по серой краске, в 1944-м — по «засадному» камуфляжу
				return {"camo": "wash44" if year >= 1944 else "grey_winter", "emblem": "germany"}
			if season == "desert":
				return {"camo": "dak", "emblem": "germany"}
			# до 1943 г. танки красили в тёмно-серый «панцерграу», потом — в тёмно-жёлтый
			if year < 1943:
				return {"camo": "panzergrey", "emblem": "germany"}
			return {"camo": "german44" if year >= 1944 else "german", "emblem": "germany"}
		"Великобритания":
			if season == "desert":
				return {"camo": "desert", "emblem": "uk"}
			return {"camo": "british", "emblem": "usa"}
		"Италия":
			return {"camo": "italy", "emblem": "italy"}
		"Венгрия":
			# трёхцветный венгерский камуфляж, белый крест на чёрном квадрате
			return {"camo": "hungary", "emblem": "hungary"}
		"Франция":
			# трёхцветный камуфляж 1940 г. с тёмной обводкой пятен, кокарда
			return {"camo": "france", "emblem": "france"}
		"Япония":
			# трёхцветный камуфляж императорской армии, жёлтая звезда
			return {"camo": "japan", "emblem": "japan"}
	# американцы в Арденнах белили танки известью и простынями — местами
	return {"camo": "olive_wash" if season == "winter" else "olive", "emblem": "usa"}
