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
		"tier": 5, "side": "allies", "year": 1942, "pts": 8, "freq": 3.0,
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
		"tier": 8, "side": "allies", "year": 1944, "pts": 15, "freq": 1.0,
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
	"crusader": {"short": "СТ", "name": "Crusader Mk III", "tag": "Crusader", "nation": "Великобритания", "cls": "Крейсерский танк",
		"tier": 4, "side": "allies", "year": 1942, "pts": 7, "freq": 2.0,
		"hp": 760.0, "dmg": 95.0, "pen": 95.0, "caliber": 57.0, "reload": 2.2, "shell": 853.0,
		"kmh": 44.0, "rev": 16.0, "turn": 44.0, "tspd": 36.0, "power": 340.0, "mass": 20.1,
		"disp": 0.38, "aim": 1.8, "armor": [51, 28, 28, 51, 32, 23], "slope": 25.0, "side_slope": 0.0,
		"tslope": 30.0, "elev": [-12.0, 20.0], "spot": 66.0, "engine": "petrol", "len": 5.97, "wid": 2.77, "pref": 330.0},
	"pz3": {"short": "СТ", "name": "Pz.Kpfw. III Ausf. L", "tag": "Pz III L", "nation": "Германия", "cls": "Средний танк",
		"tier": 4, "side": "axis", "year": 1942, "pts": 4, "freq": 2.5,
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
		"tier": 5, "side": "axis", "year": 1942, "pts": 6, "freq": 2.0, "variants": {1944: {"pts": 5}},
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
		"tier": 3, "side": "axis", "year": 1940, "pts": 4, "freq": 2.0,
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
}

# ---------- Прогресс: исследование, покупка, модули ----------

const ROMAN := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
# Танки, которые есть у игрока с самого начала (по одному-два на нацию).
const STARTERS := ["t34_76", "crusader", "pz3", "m13_40"]
# Дерево исследования: какие машины открывает опыт, набранный на танке.
const TREE := {
	"t34_76": ["t34", "kv1"], "t34": ["su100"], "kv1": ["is2"],
	"crusader": ["cromwell", "sherman", "chaffee"], "cromwell": ["firefly"], "sherman": ["firefly"],
	"m13_40": ["pz3"], "pz3": ["pz4", "stug"], "pz4": ["tiger", "panther"], "stug": ["jagdpanther"], "tiger": ["tiger2"],
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
	"crusader": {"gun": ["QF 2-pdr Mk. IX", "QF 6-pdr Mk. III", {"dmg": 70.0, "pen": 64.0, "caliber": 40.0, "shell": 792.0, "reload": 1.8}],
		"engine": ["Nuffield Liberty Mk. II", "Nuffield Liberty Mk. III", {"power": 310.0}],
		"susp": ["Crusader Mk. I", "Crusader Mk. III"]},
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
	"tiger2": {"turret": ["Башня «Порше»", "Башня «Хеншель»", {"armor": [150, 80, 80, 100, 80, 80], "tslope": 25.0, "hp": 1720.0, "tspd": 16.0}],
		"engine": ["Maybach HL 230 P30 ранний", "Maybach HL 230 P30", {"power": 650.0}], "susp": ["Tiger II ранний", "Tiger II"]},
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
# Цвета земли для шейдера: трава/песок/снег (две тени), скала, дорога, грязь, гарь.
# grip — сопротивление грунта (1 — дорога), surf — материал поверхности для текстур.
# edge — высота холмов за краем поля (1 — горы); cover — облачность; fog — начало и конец дымки; sun — наклон и азимут солнца, °.
# weather — погода: mist — утренний туман у земли, snow — снегопад, haze — марево над раскалённой землёй.
const MAPS := {
	"prokhorovka": {"name": "Прохоровка", "desc": "Холмистые поля и деревня", "surf": "grass",
		"date": "12 июля 1943", "year": 1943, "allies": "СССР", "axis": "Германия", "allies_g": "СССР", "axis_g": "Германии",
		"nations": {"allies": ["СССР"], "axis": ["Германия"]}, "season": "summer",
		"roster": {"allies": ["t34_76", "kv1"], "axis": ["pz3", "pz4", "stug", "panther", "tiger"]},
		"brief": "Курская битва. Утром 12 июля 1943 года 5-я гвардейская танковая армия Ротмистрова контратаковала 2-й танковый корпус СС у станции Прохоровка. Сотни машин сошлись на узком поле между рекой Псёл и железной дорогой, бой шёл на коротких дистанциях: «тридцатьчетвёрки» старались подойти вплотную к «Тиграм», чьи 88-мм пушки били на километр.",
		"sky_top": "6c829b", "sky_hor": "c6c8bf", "fog": "b6b7ab", "sun": "fff0d8", "sun_e": 1.15, "amb": 0.42,
		"cover": 0.5, "fog_near": 520.0, "fog_far": 1900.0, "sun_rot": [-36.0, -42.0],
		"g1": "545c38", "g2": "8b8657", "rock": "78705e", "road": "7a6a4c", "dirt": "6a5a3a", "scorch": "26221d",
		"dust": "8a7c5c", "mini": "4a5236", "relief": 26.0, "grip": 0.85, "edge": 0.4},
	"alamein": {"name": "Эль-Аламейн", "desc": "Барханы и скалы Северной Африки", "surf": "sand",
		"date": "октябрь 1942", "year": 1942, "allies": "Великобритания", "axis": "Германия и Италия", "allies_g": "Великобритании",
		"axis_g": "Германии и Италии", "nations": {"allies": ["Великобритания"], "axis": ["Германия", "Италия"]}, "season": "desert",
		"roster": {"allies": ["sherman", "crusader"], "axis": ["pz3", "pz4", "m13_40"]},
		"brief": "Египет, октябрь–ноябрь 1942 года. 8-я британская армия Монтгомери прорывает оборону германо-итальянской танковой армии «Африка» Роммеля. Впервые в бой массово идут американские «Шерманы», полученные по ленд-лизу. После Эль-Аламейна войска Оси навсегда уходят из Египта.",
		"sky_top": "7aa0c4", "sky_hor": "ddd3bd", "fog": "d6ccb6", "sun": "fff0d0", "sun_e": 1.1, "amb": 0.45,
		"cover": 0.22, "fog_near": 520.0, "fog_far": 1900.0, "sun_rot": [-36.0, -42.0],
		"g1": "a39072", "g2": "c2b08e", "rock": "8f7556", "road": "9c8766", "dirt": "8e7350", "scorch": "3a3028",
		"dust": "c8aa78", "mini": "a08250", "relief": 30.0, "grip": 0.74, "weather": "haze"},
	"stalingrad": {"name": "Сталинград", "desc": "Руины зимнего города", "surf": "snow",
		"date": "зима 1942–1943", "year": 1942, "allies": "СССР", "axis": "Германия", "allies_g": "СССР", "axis_g": "Германии",
		"nations": {"allies": ["СССР"], "axis": ["Германия"]}, "season": "winter",
		"roster": {"allies": ["t34_76", "kv1"], "axis": ["pz3", "pz4", "stug"]},
		"brief": "Сталинград, зима 1942–1943 года. Бои идут за каждый дом разрушенного города. 19 ноября Красная армия начала операцию «Уран» и окружила 6-ю армию Паулюса; 2 февраля 1943 года её остатки капитулировали. Улицы завалены обломками, из-за угла можно получить снаряд в борт.",
		"sky_top": "8a97a4", "sky_hor": "c6cbd0", "fog": "bcc2c7", "sun": "e8eef5", "sun_e": 0.75, "amb": 0.55,
		"cover": 0.88, "fog_near": 300.0, "fog_far": 1300.0, "sun_rot": [-48.0, 20.0],
		"g1": "c9d1d8", "g2": "eef2f5", "rock": "7d8186", "road": "75797d", "dirt": "5d5650", "scorch": "2a2826",
		"dust": "e6ebef", "mini": "9aa4ae", "relief": 7.0, "grip": 0.78, "edge": 0.55, "weather": "snow"},
	"normandy": {"name": "Нормандия", "desc": "Бокаж: поля за земляными валами с живыми изгородями", "surf": "grass",
		"date": "июль 1944, утро", "year": 1944, "allies": "США и Великобритания", "axis": "Германия",
		"allies_g": "США и Великобритании", "axis_g": "Германии",
		"nations": {"allies": ["США", "Великобритания"], "axis": ["Германия"]}, "season": "summer",
		"roster": {"allies": ["sherman", "firefly", "cromwell"], "axis": ["pz4", "stug", "panther", "tiger", "tiger2", "jagdpanther"]},
		"brief": "Франция, лето 1944 года. После высадки 6 июня союзники пробиваются вглубь Нормандии через бокаж — поля, разделённые земляными валами с живыми изгородями. Вал не пробить снарядом и не переехать, изгородь прячет засаду, а бой идёт на сотне метров. Британцы ставят 17-фунтовую пушку на «Шерман» — «Файрфлай» — единственный союзный танк, берущий «Пантеру» в лоб.",
		"sky_top": "7488a0", "sky_hor": "d3d2c8", "fog": "c9c8bf", "sun": "ffe0b8", "sun_e": 1.0, "amb": 0.5,
		"cover": 0.48, "fog_near": 260.0, "fog_far": 1350.0, "sun_rot": [-17.0, -100.0],
		"g1": "434f30", "g2": "687250", "rock": "77756a", "road": "766850", "dirt": "54452f", "scorch": "24211c",
		"dust": "857a5c", "mini": "3f4a30", "relief": 16.0, "grip": 0.84, "edge": 0.35, "weather": "mist"},
	"berlin": {"name": "Берлин", "desc": "Штурм столицы Рейха: проспекты, руины, Рейхстаг", "surf": "urban",
		"date": "апрель 1945", "year": 1945, "allies": "СССР", "axis": "Германия", "allies_g": "СССР", "axis_g": "Германии",
		"nations": {"allies": ["СССР"], "axis": ["Германия"]}, "season": "late",
		"roster": {"allies": ["t34", "is2", "su100"], "axis": ["pz4", "stug", "panther", "tiger2", "jagdpanther"]},
		"brief": "Берлин, апрель 1945 года. 1-й Белорусский и 1-й Украинский фронты штурмуют столицу Рейха. Советские танки идут по улицам с белыми полосами на башнях и крестами на крышах — опознавательным знаком операции. Город обороняют последние «Пантеры», штурмовые орудия и «Королевские тигры» 503-го батальона. 2 мая гарнизон Берлина капитулировал.",
		"sky_top": "75787b", "sky_hor": "b3a896", "fog": "a49b8c", "sun": "f4dfc4", "sun_e": 0.85, "amb": 0.5,
		"cover": 0.72, "fog_near": 320.0, "fog_far": 1400.0, "sun_rot": [-30.0, 28.0],
		"g1": "5c554a", "g2": "726a5c", "rock": "6c6862", "road": "57554f", "dirt": "4c4238", "scorch": "201d1a",
		"dust": "8c8272", "mini": "5a5650", "relief": 5.0, "grip": 0.88, "edge": 0.3},
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
}
const LANG := {"СССР": "ru", "Германия": "de", "США": "en", "Великобритания": "en", "Италия": "it"}

# Переговоры по рации своей стороны: на её языке, для немецкого и английского — с переводом.
# {h} — направление «по часам» от корпуса игрока, {clock} — оно же по-русски («2 часа»), {cs} — позывной.
const RADIO := {
	"start": {
		"ru": [["Всем! Задача ясна — вперёд!", ""], ["Я «{cs}». Выдвигаемся, держать строй!", ""]],
		"de": [["Panzer marsch!", "Танки, вперёд!"], ["Hier {cs}. Vorwärts, Abstand halten!", "Говорит {cs}. Вперёд, держать дистанцию!"]],
		"en": [["All stations, advance!", "Всем, вперёд!"], ["{cs} here. Move out, keep spread!", "Говорит {cs}. Выдвигаемся, не кучковаться!"]],
		"it": [["Carri, avanti!", "Танки, вперёд!"], ["Qui {cs}. Avanti, mantenere le distanze!", "Говорит {cs}. Вперёд, держать дистанцию!"]]},
	"spot": {
		"ru": [["Танк противника на {clock}!", ""], ["Вижу противника на {clock}!", ""]],
		"de": [["Feindpanzer auf {h} Uhr!", "Вражеский танк на {clock}!"], ["Achtung, Feind auf {h} Uhr!", "Внимание, противник на {clock}!"]],
		"en": [["Enemy tank, {h} o'clock!", "Вражеский танк на {clock}!"], ["Contact, {h} o'clock!", "Контакт на {clock}!"]],
		"it": [["Carro nemico a ore {h}!", "Вражеский танк на {clock}!"], ["Attenzione, nemico a ore {h}!", "Внимание, противник на {clock}!"]]},
	"spot_tiger": {
		"ru": [["Осторожно, «Тигр» на {clock}!", ""]],
		"de": [["Feindpanzer auf {h} Uhr!", "Вражеский танк на {clock}!"]],
		"en": [["Tiger! Tiger at {h} o'clock!", "«Тигр»! «Тигр» на {clock}!"]],
		"it": [["Carro nemico a ore {h}!", "Вражеский танк на {clock}!"]]},
	"ally_down": {
		"ru": [["«{cs}» подбит!", ""], ["Потеряли «{cs}»!", ""]],
		"de": [["{cs} ist ausgefallen!", "{cs} подбит!"], ["{cs} brennt!", "{cs} горит!"]],
		"en": [["{cs} is hit, they're bailing out!", "{cs} подбит, экипаж покидает машину!"], ["We've lost {cs}!", "Потеряли {cs}!"]],
		"it": [["{cs} è stato colpito!", "{cs} подбит!"], ["{cs} brucia!", "{cs} горит!"]]},
	"enemy_down": {
		"ru": [["Готов! Есть один!", ""], ["Горит, гад!", ""]],
		"de": [["Abschuss!", "Подбит!"], ["Volltreffer, er brennt!", "Прямое попадание, горит!"]],
		"en": [["Got him!", "Есть, подбил!"], ["Scratch one!", "Минус один!"]],
		"it": [["Colpito, brucia!", "Попал, горит!"], ["Centrato!", "Прямое попадание!"]]},
	"our_base": {
		"ru": [["Противник на нашей базе! Все назад!", ""]],
		"de": [["Feind in unserer Stellung! Zurück!", "Противник на нашей позиции! Назад!"]],
		"en": [["They're taking our base! Fall back!", "Захватывают нашу базу! Назад!"]],
		"it": [["Il nemico è nella nostra posizione! Indietro!", "Противник на нашей позиции! Назад!"]]},
	"their_base": {
		"ru": [["Захватываем базу, прикройте!", ""]],
		"de": [["Wir nehmen die Stellung, Feuerschutz!", "Занимаем позицию, прикройте огнём!"]],
		"en": [["Capturing the base, cover us!", "Захватываем базу, прикройте!"]],
		"it": [["Occupiamo la posizione, copriteci!", "Занимаем позицию, прикройте!"]]},
	"last": {
		"ru": [["Нас осталось мало — держаться!", ""]],
		"de": [["Wir sind nur noch wenige — haltet aus!", "Нас осталось мало — держитесь!"]],
		"en": [["We're nearly done for — hold on!", "Нас почти не осталось — держитесь!"]],
		"it": [["Siamo rimasti in pochi — resistete!", "Нас осталось мало — держитесь!"]]},
}


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
static func match_teams(mine: Array, theirs: Array, first: String, rng: RandomNumberGenerator, year: int, tier := 5) -> Array:
	# у лёгких машин семь танков не набирают полного веса: бюджет — по более лёгкой стороне
	var budget := mini(TEAM_BUDGET + maxi(0, tier - 6) * 9, int(minf(_mean_pts(mine, year), _mean_pts(theirs, year)) * TEAM_MAX))
	var a_list: Array = []
	var b_list: Array = []
	for i in 40:
		a_list.append(compose(mine, first, budget, rng, year))
		b_list.append(compose(theirs, "", budget, rng, year))
	var pairs: Array = []
	var best: Array = [a_list[0], b_list[0]]
	var best_d := 1 << 20
	for a in a_list:
		if a.size() < 3:
			continue
		for b in b_list:
			if b.size() < 3:
				continue
			var d := absi(team_pts(a, year) - team_pts(b, year))
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
## Великобритания — пустынная с бело-красно-белой полосой или оливковая с белой звездой союзников.
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
				return {"camo": "grey_winter", "emblem": "germany"}
			if season == "desert":
				return {"camo": "dak", "emblem": "germany"}
			return {"camo": "german44" if year >= 1944 else "german", "emblem": "germany"}
		"Великобритания":
			if season == "desert":
				return {"camo": "desert", "emblem": "uk"}
			return {"camo": "british", "emblem": "usa"}
		"Италия":
			return {"camo": "italy", "emblem": "italy"}
	return {"camo": "olive", "emblem": "usa"}
