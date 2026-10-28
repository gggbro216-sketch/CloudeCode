extends RefCounted
## Справочники игры: танки, режимы, карты и общие константы.

const WS := 2200.0  # сторона карты
const SHELL := 900.0  # скорость снаряда
const RANGE := 950.0  # дальность выстрела
const TIME_LIMIT := 420.0  # 7 минут на бой
const SUP_GOAL := 600.0  # очки для победы в «Превосходстве»
const CAP_RATE := 3.5  # процентов захвата в секунду на танк (до трёх танков)

const ALLY := "6cd04f"
const FOE := "e2563c"
const AMBER := "f0b73a"

# speed в единицах карты в секунду; в ангаре показываем как км/ч (× 0.35)
const TYPES := {
	"light": {"short": "ЛТ", "name": "Ласточка Л-1", "cls": "Лёгкий танк", "hp": 650.0, "speed": 200.0, "turn": 2.6, "tspd": 3.6,
		"dmg": 90.0, "reload": 1.5, "r": 17.0, "L": 40.0, "W": 26.0, "barrel": 32.0, "bw": 4.0, "spot": 520.0, "pref": 300.0, "paint": "6f7c47"},
	"medium": {"short": "СТ", "name": "Барс С-3", "cls": "Средний танк", "hp": 950.0, "speed": 155.0, "turn": 2.0, "tspd": 2.8,
		"dmg": 135.0, "reload": 2.3, "r": 20.0, "L": 46.0, "W": 30.0, "barrel": 38.0, "bw": 5.0, "spot": 470.0, "pref": 380.0, "paint": "5a684b"},
	"heavy": {"short": "ТТ", "name": "Мамонт Т-7", "cls": "Тяжёлый танк", "hp": 1400.0, "speed": 100.0, "turn": 1.4, "tspd": 2.0,
		"dmg": 200.0, "reload": 3.4, "r": 24.0, "L": 54.0, "W": 36.0, "barrel": 46.0, "bw": 7.0, "spot": 420.0, "pref": 450.0, "paint": "55584d"},
}

const MODES := {
	"standard": {"name": "Стандартный бой", "desc": "Уничтожьте врагов или захватите их базу"},
	"encounter": {"name": "Встречный бой", "desc": "Одна нейтральная база в центре карты"},
	"supremacy": {"name": "Превосходство", "desc": "Держите точки A, B, C. Нужно 600 очков"},
}

const MAPS := {
	"meadow": {"name": "Луговая", "desc": "Деревня, поля и рощи", "sky": "a8c4d4", "ground_a": "4c5f30", "ground_b": "75854a",
		"road": "8a7a52", "dust": "8a7a5a", "mini": "3c4c2c"},
	"desert": {"name": "Дюны", "desc": "Скалы и песок", "sky": "e6d2aa", "ground_a": "a08559", "ground_b": "c9b088",
		"road": "a3875a", "dust": "c8aa78", "mini": "a08250"},
	"winter": {"name": "Северск", "desc": "Заснеженный город", "sky": "c4d0da", "ground_a": "c3ced6", "ground_b": "f3f7f9",
		"road": "8d979f", "dust": "e6ebef", "mini": "aab4be"},
}

const NAMES := ["Волк", "Ястреб", "Кобра", "Тигр", "Север", "Орёл", "Гром", "Лис", "Барс", "Шторм", "Сокол", "Беркут"]
