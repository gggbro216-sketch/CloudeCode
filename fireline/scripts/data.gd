extends RefCounted
## Справочник игры: стороны, оружие, подразделения, сценарии и автонабор армии.
## Расстояния в метрах (1 единица карты = 1 м), скорости в м/с, время в секундах.

const FACTIONS := {
	"us": {"name": "США", "paint": Color(0.40, 0.42, 0.26), "cloth": Color(0.47, 0.45, 0.30),
		"helmet": Color(0.33, 0.36, 0.22)},
	"su": {"name": "СССР", "paint": Color(0.27, 0.34, 0.20), "cloth": Color(0.52, 0.50, 0.33),
		"helmet": Color(0.30, 0.38, 0.22)},
	"de": {"name": "Германия", "paint": Color(0.62, 0.55, 0.36), "cloth": Color(0.42, 0.45, 0.40),
		"helmet": Color(0.33, 0.36, 0.33)},
}

# kind: sa — стрелковое (мгновенно, трассер), he — фугас (граната), mortar — навесной огонь,
# rocket — РПГ (кумулятив), ap — бронебойное ружьё, gun — пушка (бронебойный по технике, фугас по пехоте).
# acc0/acc1 — вероятность попадания вблизи и на предельной дальности, sup — подавление за выстрел,
# pen0/pen1 — бронепробитие (мм) на 0 и 1000 м, he_r — радиус разлёта, he_k — шанс поражения в центре.
const W := {
	"rifle": {"name": "Винтовка", "kind": "sa", "range": 380.0, "reload": 2.8, "acc0": 0.30, "acc1": 0.03,
		"sup": 4.0, "burst": 1, "snd": "rifle"},
	"garand": {"name": "M1 Garand", "kind": "sa", "range": 380.0, "reload": 1.9, "acc0": 0.30, "acc1": 0.03,
		"sup": 4.5, "burst": 1, "snd": "rifle"},
	"smg": {"name": "Пистолет-пулемёт", "kind": "sa", "range": 140.0, "reload": 1.5, "acc0": 0.42, "acc1": 0.03,
		"sup": 5.0, "burst": 3, "snd": "smg"},
	"lmg": {"name": "Ручной пулемёт", "kind": "sa", "range": 480.0, "reload": 1.7, "acc0": 0.24, "acc1": 0.03,
		"sup": 7.0, "burst": 4, "snd": "mg"},
	"hmg": {"name": "Станковый пулемёт", "kind": "sa", "range": 650.0, "reload": 1.1, "acc0": 0.22, "acc1": 0.03,
		"sup": 9.0, "burst": 6, "snd": "mg"},
	"mg42": {"name": "MG 42", "kind": "sa", "range": 650.0, "reload": 0.9, "acc0": 0.22, "acc1": 0.03,
		"sup": 10.0, "burst": 7, "snd": "mg42"},
	"mg50": {"name": "Пулемёт .50", "kind": "sa", "range": 700.0, "reload": 1.2, "acc0": 0.22, "acc1": 0.04,
		"sup": 11.0, "burst": 5, "pen": 18.0, "snd": "mg"},
	"sniper": {"name": "Снайперская винтовка", "kind": "sa", "range": 700.0, "reload": 6.5, "acc0": 0.85,
		"acc1": 0.40, "sup": 16.0, "burst": 1, "snd": "rifle"},
	"grenade": {"name": "Гранаты", "kind": "he", "range": 32.0, "reload": 16.0, "acc0": 0.9, "acc1": 0.5,
		"he_r": 5.0, "he_k": 0.55, "sup": 28.0, "vel": 16.0, "snd": "nade"},
	"bazooka": {"name": "Базука", "kind": "rocket", "range": 150.0, "reload": 8.0, "acc0": 0.8, "acc1": 0.25,
		"pen0": 100.0, "pen1": 100.0, "he_r": 3.0, "he_k": 0.4, "sup": 18.0, "vel": 85.0, "snd": "rocket"},
	"pschreck": {"name": "Панцершрек", "kind": "rocket", "range": 180.0, "reload": 8.5, "acc0": 0.8, "acc1": 0.25,
		"pen0": 160.0, "pen1": 160.0, "he_r": 3.5, "he_k": 0.45, "sup": 20.0, "vel": 105.0, "snd": "rocket"},
	"ptrd": {"name": "ПТРД", "kind": "ap", "range": 400.0, "reload": 4.5, "acc0": 0.75, "acc1": 0.2,
		"pen0": 40.0, "pen1": 20.0, "sup": 8.0, "vel": 1000.0, "snd": "rifle"},
	"mort60": {"name": "60-мм миномёт", "kind": "mortar", "min": 60.0, "range": 700.0, "reload": 4.5,
		"acc0": 0.04, "acc1": 0.07, "he_r": 7.0, "he_k": 0.45, "sup": 30.0, "vel": 110.0, "snd": "mortar"},
	"mort8": {"name": "81/82-мм миномёт", "kind": "mortar", "min": 80.0, "range": 900.0, "reload": 5.5,
		"acc0": 0.04, "acc1": 0.07, "he_r": 9.5, "he_k": 0.55, "sup": 40.0, "vel": 120.0, "snd": "mortar"},
	# пушки
	"37mm": {"name": "37-мм M6", "kind": "gun", "range": 700.0, "reload": 3.0, "acc0": 0.92, "acc1": 0.35,
		"pen0": 64.0, "pen1": 40.0, "he_r": 3.0, "he_k": 0.35, "sup": 18.0, "vel": 800.0, "snd": "gun_s"},
	"45mm": {"name": "45-мм 20-К", "kind": "gun", "range": 700.0, "reload": 3.4, "acc0": 0.9, "acc1": 0.33,
		"pen0": 58.0, "pen1": 38.0, "he_r": 3.0, "he_k": 0.35, "sup": 18.0, "vel": 760.0, "snd": "gun_s"},
	"57mm": {"name": "57-мм M1", "kind": "gun", "range": 900.0, "reload": 4.0, "acc0": 0.92, "acc1": 0.35,
		"pen0": 115.0, "pen1": 80.0, "he_r": 3.5, "he_k": 0.35, "sup": 20.0, "vel": 850.0, "snd": "gun_s"},
	"75us": {"name": "75-мм M3", "kind": "gun", "range": 1000.0, "reload": 5.0, "acc0": 0.9, "acc1": 0.3,
		"pen0": 92.0, "pen1": 70.0, "he_r": 7.0, "he_k": 0.55, "sup": 35.0, "vel": 620.0, "snd": "gun_75"},
	"76us": {"name": "76-мм M1", "kind": "gun", "range": 1000.0, "reload": 5.5, "acc0": 0.92, "acc1": 0.35,
		"pen0": 128.0, "pen1": 100.0, "he_r": 6.0, "he_k": 0.5, "sup": 32.0, "vel": 790.0, "snd": "gun_75"},
	"3in": {"name": "3-дюйм. M7", "kind": "gun", "range": 1000.0, "reload": 6.0, "acc0": 0.92, "acc1": 0.35,
		"pen0": 128.0, "pen1": 100.0, "he_r": 6.5, "he_k": 0.5, "sup": 32.0, "vel": 790.0, "snd": "gun_75"},
	"76su": {"name": "76-мм Ф-34", "kind": "gun", "range": 1000.0, "reload": 5.0, "acc0": 0.88, "acc1": 0.28,
		"pen0": 86.0, "pen1": 65.0, "he_r": 7.0, "he_k": 0.55, "sup": 35.0, "vel": 660.0, "snd": "gun_75"},
	"zis3": {"name": "76-мм ЗиС-3", "kind": "gun", "range": 1000.0, "reload": 4.5, "acc0": 0.9, "acc1": 0.3,
		"pen0": 86.0, "pen1": 65.0, "he_r": 7.0, "he_k": 0.55, "sup": 35.0, "vel": 680.0, "snd": "gun_75"},
	"85su": {"name": "85-мм ЗиС-С-53", "kind": "gun", "range": 1000.0, "reload": 6.0, "acc0": 0.9, "acc1": 0.33,
		"pen0": 135.0, "pen1": 102.0, "he_r": 7.5, "he_k": 0.55, "sup": 36.0, "vel": 790.0, "snd": "gun_88"},
	"122": {"name": "122-мм Д-25Т", "kind": "gun", "range": 1000.0, "reload": 17.0, "acc0": 0.86, "acc1": 0.28,
		"pen0": 175.0, "pen1": 145.0, "he_r": 12.0, "he_k": 0.75, "sup": 60.0, "vel": 780.0, "snd": "gun_122"},
	"75L48": {"name": "75-мм KwK 40", "kind": "gun", "range": 1000.0, "reload": 5.0, "acc0": 0.92, "acc1": 0.35,
		"pen0": 135.0, "pen1": 105.0, "he_r": 7.0, "he_k": 0.55, "sup": 35.0, "vel": 750.0, "snd": "gun_75"},
	"75L70": {"name": "75-мм KwK 42", "kind": "gun", "range": 1000.0, "reload": 6.0, "acc0": 0.94, "acc1": 0.42,
		"pen0": 185.0, "pen1": 150.0, "he_r": 6.0, "he_k": 0.5, "sup": 32.0, "vel": 935.0, "snd": "gun_88"},
	"88L56": {"name": "88-мм KwK 36", "kind": "gun", "range": 1000.0, "reload": 7.0, "acc0": 0.94, "acc1": 0.42,
		"pen0": 165.0, "pen1": 135.0, "he_r": 8.5, "he_k": 0.62, "sup": 42.0, "vel": 810.0, "snd": "gun_88"},
	"pak40": {"name": "75-мм PaK 40", "kind": "gun", "range": 1000.0, "reload": 4.8, "acc0": 0.92, "acc1": 0.35,
		"pen0": 135.0, "pen1": 105.0, "he_r": 6.0, "he_k": 0.5, "sup": 30.0, "vel": 790.0, "snd": "gun_75"},
	# поддержка вне карты
	"art105": {"name": "105-мм гаубицы", "kind": "he", "range": 9999.0, "he_r": 14.0, "he_k": 0.75,
		"he_pen": 30.0, "sup": 70.0, "snd": "explosion"},
	"smoke": {"name": "Дымовые снаряды", "kind": "smoke", "range": 9999.0, "snd": "pop"},
}

# Подразделения. cat: inf — стрелки, team — расчёт поддержки, gun — буксируемое орудие, veh — машина.
# men: [[оружие, число бойцов], ...]; у машин armor = [лоб, борт, корма] (мм, с учётом наклона).
const U := {
	# ----- США -----
	"us_rifle": {"f": "us", "name": "Стрелковое отделение", "short": "СТР", "cat": "inf", "cost": 60,
		"men": [["garand", 8], ["smg", 1], ["lmg", 1]], "nade": true, "speed": 1.7, "spot": 300.0},
	"us_mg": {"f": "us", "name": "Пулемёт M1919", "short": "ПУЛ", "cat": "team", "cost": 45,
		"men": [["hmg", 1], ["rifle", 3]], "speed": 1.5, "spot": 320.0},
	"us_bazooka": {"f": "us", "name": "Расчёт базуки", "short": "ПТР", "cat": "team", "cost": 40,
		"men": [["bazooka", 1], ["garand", 1]], "speed": 1.7, "spot": 280.0, "stealth": 0.85},
	"us_sniper": {"f": "us", "name": "Снайпер", "short": "СНП", "cat": "team", "cost": 40,
		"men": [["sniper", 1], ["garand", 1]], "speed": 1.7, "spot": 450.0, "stealth": 0.55},
	"us_mortar": {"f": "us", "name": "60-мм миномёт", "short": "МИН", "cat": "team", "cost": 50,
		"men": [["mort60", 1], ["rifle", 2]], "speed": 1.4, "spot": 260.0},
	"us_atgun": {"f": "us", "name": "57-мм пушка M1", "short": "ПТО", "cat": "gun", "cost": 75,
		"men": [["crew", 5]], "gun": "57mm", "speed": 0.7, "spot": 300.0, "stealth": 0.75},
	"us_ht": {"f": "us", "name": "Бронетранспортёр M3", "short": "БТР", "cat": "veh", "cost": 70,
		"armor": [13.0, 7.0, 7.0], "open": true, "turret": false, "gun": "", "mg": ["mg50", "hmg"], "crew": 3,
		"speed": 9.0, "turn": 45.0, "tturn": 0.0, "len": 6.2, "wid": 2.2, "spot": 260.0, "kind": "ht"},
	"us_stuart": {"f": "us", "name": "Лёгкий танк M5 «Стюарт»", "short": "ЛТ", "cat": "veh", "cost": 100,
		"armor": [64.0, 28.0, 25.0], "turret": true, "gun": "37mm", "mg": ["hmg", "hmg"], "crew": 4,
		"speed": 9.5, "turn": 50.0, "tturn": 40.0, "len": 4.8, "wid": 2.3, "spot": 250.0, "kind": "tank"},
	"us_sherman": {"f": "us", "name": "Средний танк M4 «Шерман»", "short": "СТ", "cat": "veh", "cost": 145,
		"armor": [90.0, 38.0, 38.0], "turret": true, "gun": "75us", "mg": ["hmg", "hmg"], "crew": 5,
		"speed": 7.0, "turn": 35.0, "tturn": 28.0, "len": 5.9, "wid": 2.6, "spot": 250.0, "kind": "tank", "stab": true},
	"us_sherman76": {"f": "us", "name": "M4A1(76)W «Шерман»", "short": "СТ76", "cat": "veh", "cost": 175,
		"armor": [95.0, 38.0, 38.0], "turret": true, "gun": "76us", "mg": ["hmg", "hmg"], "crew": 5,
		"speed": 7.0, "turn": 35.0, "tturn": 26.0, "len": 6.2, "wid": 2.6, "spot": 250.0, "kind": "tank", "stab": true},
	"us_m10": {"f": "us", "name": "САУ M10 «Росомаха»", "short": "ИСТ", "cat": "veh", "cost": 150,
		"armor": [70.0, 25.0, 20.0], "open": true, "turret": true, "gun": "3in", "mg": ["mg50"], "crew": 5,
		"speed": 7.5, "turn": 35.0, "tturn": 12.0, "len": 6.8, "wid": 3.0, "spot": 280.0, "kind": "tank"},
	# ----- СССР -----
	"su_rifle": {"f": "su", "name": "Стрелковое отделение", "short": "СТР", "cat": "inf", "cost": 55,
		"men": [["rifle", 6], ["smg", 3], ["lmg", 1]], "nade": true, "speed": 1.7, "spot": 300.0},
	"su_mg": {"f": "su", "name": "Пулемёт «Максим»", "short": "ПУЛ", "cat": "team", "cost": 45,
		"men": [["hmg", 1], ["rifle", 3]], "speed": 1.3, "spot": 320.0},
	"su_ptrd": {"f": "su", "name": "Расчёт ПТРД", "short": "ПТР", "cat": "team", "cost": 35,
		"men": [["ptrd", 1], ["rifle", 1]], "speed": 1.6, "spot": 300.0, "stealth": 0.85},
	"su_sniper": {"f": "su", "name": "Снайпер", "short": "СНП", "cat": "team", "cost": 40,
		"men": [["sniper", 1], ["rifle", 1]], "speed": 1.7, "spot": 450.0, "stealth": 0.55},
	"su_mortar": {"f": "su", "name": "82-мм миномёт", "short": "МИН", "cat": "team", "cost": 55,
		"men": [["mort8", 1], ["rifle", 3]], "speed": 1.3, "spot": 260.0},
	"su_atgun": {"f": "su", "name": "76-мм пушка ЗиС-3", "short": "ПТО", "cat": "gun", "cost": 75,
		"men": [["crew", 5]], "gun": "zis3", "speed": 0.7, "spot": 300.0, "stealth": 0.75},
	"su_t70": {"f": "su", "name": "Лёгкий танк Т-70", "short": "ЛТ", "cat": "veh", "cost": 85,
		"armor": [55.0, 15.0, 15.0], "turret": true, "gun": "45mm", "mg": ["lmg"], "crew": 2,
		"speed": 9.0, "turn": 50.0, "tturn": 40.0, "len": 4.3, "wid": 2.3, "spot": 230.0, "kind": "tank"},
	"su_t34": {"f": "su", "name": "Средний танк Т-34", "short": "СТ", "cat": "veh", "cost": 140,
		"armor": [90.0, 45.0, 40.0], "turret": true, "gun": "76su", "mg": ["lmg", "lmg"], "crew": 4,
		"speed": 8.5, "turn": 38.0, "tturn": 25.0, "len": 6.0, "wid": 3.0, "spot": 230.0, "kind": "tank"},
	"su_t3485": {"f": "su", "name": "Т-34-85", "short": "СТ85", "cat": "veh", "cost": 180,
		"armor": [90.0, 45.0, 40.0], "turret": true, "gun": "85su", "mg": ["lmg", "lmg"], "crew": 5,
		"speed": 8.0, "turn": 36.0, "tturn": 24.0, "len": 6.1, "wid": 3.0, "spot": 250.0, "kind": "tank"},
	"su_su76": {"f": "su", "name": "САУ СУ-76М", "short": "САУ", "cat": "veh", "cost": 105,
		"armor": [35.0, 15.0, 15.0], "open": true, "turret": false, "gun": "zis3", "mg": [], "crew": 4,
		"speed": 8.5, "turn": 45.0, "tturn": 0.0, "len": 5.0, "wid": 2.7, "spot": 260.0, "kind": "td"},
	"su_is2": {"f": "su", "name": "Тяжёлый танк ИС-2", "short": "ТТ", "cat": "veh", "cost": 240,
		"armor": [160.0, 90.0, 60.0], "turret": true, "gun": "122", "mg": ["lmg", "lmg"], "crew": 4,
		"speed": 6.0, "turn": 28.0, "tturn": 18.0, "len": 6.8, "wid": 3.1, "spot": 230.0, "kind": "tank"},
	# ----- Германия -----
	"de_rifle": {"f": "de", "name": "Отделение гренадеров", "short": "СТР", "cat": "inf", "cost": 60,
		"men": [["rifle", 7], ["smg", 1], ["mg42", 1]], "nade": true, "speed": 1.7, "spot": 300.0},
	"de_mg": {"f": "de", "name": "Пулемёт MG 42", "short": "ПУЛ", "cat": "team", "cost": 50,
		"men": [["mg42", 1], ["rifle", 3]], "speed": 1.5, "spot": 330.0},
	"de_schreck": {"f": "de", "name": "Расчёт панцершрека", "short": "ПТР", "cat": "team", "cost": 45,
		"men": [["pschreck", 1], ["rifle", 1]], "speed": 1.6, "spot": 280.0, "stealth": 0.85},
	"de_sniper": {"f": "de", "name": "Снайпер", "short": "СНП", "cat": "team", "cost": 40,
		"men": [["sniper", 1], ["rifle", 1]], "speed": 1.7, "spot": 450.0, "stealth": 0.55},
	"de_mortar": {"f": "de", "name": "81-мм миномёт", "short": "МИН", "cat": "team", "cost": 55,
		"men": [["mort8", 1], ["rifle", 3]], "speed": 1.3, "spot": 260.0},
	"de_atgun": {"f": "de", "name": "75-мм пушка PaK 40", "short": "ПТО", "cat": "gun", "cost": 90,
		"men": [["crew", 5]], "gun": "pak40", "speed": 0.6, "spot": 300.0, "stealth": 0.75},
	"de_ht": {"f": "de", "name": "Бронетранспортёр Sd.Kfz. 251", "short": "БТР", "cat": "veh", "cost": 65,
		"armor": [14.0, 8.0, 8.0], "open": true, "turret": false, "gun": "", "mg": ["mg42"], "crew": 3,
		"speed": 8.5, "turn": 45.0, "tturn": 0.0, "len": 5.8, "wid": 2.1, "spot": 260.0, "kind": "ht"},
	"de_pz4": {"f": "de", "name": "Средний танк Pz.Kpfw. IV", "short": "СТ", "cat": "veh", "cost": 160,
		"armor": [80.0, 30.0, 20.0], "turret": true, "gun": "75L48", "mg": ["mg42", "mg42"], "crew": 5,
		"speed": 6.5, "turn": 35.0, "tturn": 16.0, "len": 5.9, "wid": 2.9, "spot": 260.0, "kind": "tank"},
	"de_stug": {"f": "de", "name": "Штурмовое орудие StuG III", "short": "САУ", "cat": "veh", "cost": 140,
		"armor": [80.0, 30.0, 30.0], "turret": false, "gun": "75L48", "mg": ["mg42"], "crew": 4,
		"speed": 6.5, "turn": 35.0, "tturn": 0.0, "len": 6.8, "wid": 2.95, "spot": 240.0, "kind": "td", "low": true},
	"de_panther": {"f": "de", "name": "Средний танк «Пантера»", "short": "ПНТ", "cat": "veh", "cost": 235,
		"armor": [140.0, 45.0, 40.0], "turret": true, "gun": "75L70", "mg": ["mg42", "mg42"], "crew": 5,
		"speed": 7.0, "turn": 30.0, "tturn": 22.0, "len": 6.9, "wid": 3.4, "spot": 260.0, "kind": "tank"},
	"de_tiger": {"f": "de", "name": "Тяжёлый танк «Тигр»", "short": "ТТ", "cat": "veh", "cost": 260,
		"armor": [110.0, 80.0, 80.0], "turret": true, "gun": "88L56", "mg": ["mg42", "mg42"], "crew": 5,
		"speed": 5.5, "turn": 26.0, "tturn": 14.0, "len": 6.3, "wid": 3.6, "spot": 260.0, "kind": "tank"},
}

const ROSTER := {
	"us": ["us_rifle", "us_mg", "us_bazooka", "us_sniper", "us_mortar", "us_atgun", "us_ht", "us_stuart",
		"us_sherman", "us_sherman76", "us_m10"],
	"su": ["su_rifle", "su_mg", "su_ptrd", "su_sniper", "su_mortar", "su_atgun", "su_t70", "su_su76", "su_t34",
		"su_t3485", "su_is2"],
	"de": ["de_rifle", "de_mg", "de_schreck", "de_sniper", "de_mortar", "de_atgun", "de_ht", "de_pz4", "de_stug",
		"de_panther", "de_tiger"],
}

# mode — роль игрока: meeting (встречный бой), attack (игрок наступает), defend (игрок обороняется).
const SCENARIOS := [
	{"id": "village", "name": "Перекрёсток", "map": "village", "mode": "meeting", "budget": 900, "enemy": 1.0,
		"time": 900.0, "desc": "Деревня на скрещении двух дорог. Обе стороны выходят к селу одновременно — займите три ключевые точки раньше противника."},
	{"id": "forest", "name": "Лесная опушка", "map": "forest", "mode": "attack", "budget": 950, "enemy": 0.8,
		"time": 1000.0, "desc": "Противник закрепился в лесу и на хуторе. Наступайте, подавите пулемёты и выбейте его с позиций."},
	{"id": "river", "name": "Мост", "map": "river", "mode": "defend", "budget": 800, "enemy": 1.35,
		"time": 900.0, "desc": "Ваш отряд удерживает переправу. Противник превосходит числом — продержитесь до конца отведённого времени."},
	{"id": "bocage", "name": "Живые изгороди", "map": "bocage", "mode": "meeting", "budget": 1000, "enemy": 1.0,
		"time": 1000.0, "desc": "Поля, разделённые густыми изгородями. Видимость короткая, бой будет вестись почти в упор."},
	{"id": "steppe", "name": "Танковое поле", "map": "steppe", "mode": "meeting", "budget": 1400, "enemy": 1.0,
		"time": 900.0, "armor": true, "desc": "Открытая местность, редкие рощи и балки. Решать исход будут танки и противотанковые пушки."},
]


static func w(id: String) -> Dictionary:
	return W[id]


static func pen_at(wid: String, d: float) -> float:
	var x: Dictionary = W[wid]
	return lerpf(x.get("pen0", 0.0), x.get("pen1", 0.0), clampf(d / 1000.0, 0.0, 1.0))


static func faction_units(f: String) -> Array:
	return ROSTER[f]


## Состав по умолчанию: пехота — костяк, к ней поддержка и бронетехника.
static func auto_army(f: String, budget: int, armor_heavy := false) -> Array:
	var r: Array = ROSTER[f]
	var rifle: String = r[0]
	var order: Array
	if armor_heavy:
		order = [r[8], r[0], r[5], r[9], r[7], r[1], r[8], r[2], r[0], r[10], r[8], r[5], r[3], r[0], r[7], r[9]]
	else:
		order = [r[0], r[0], r[1], r[8], r[2], r[0], r[4], r[5], r[7], r[3], r[0], r[1], r[9], r[6], r[0], r[2],
			r[10], r[0], r[8], r[1]]
	var out: Array = []
	var left := budget
	for id in order:
		var c: int = U[id].cost
		if c <= left:
			out.append(id)
			left -= c
	while left >= U[rifle].cost:
		out.append(rifle)
		left -= U[rifle].cost
	return out


static func army_cost(ids: Array) -> int:
	var s := 0
	for id in ids:
		s += int(U[id].cost)
	return s


static func enemy_of(f: String) -> String:
	if f == "de":
		return "su" if randf() < 0.5 else "us"
	return "de"
