extends RefCounted
## Ускоренные на C++ части игры: GDExtension «SteelCore» (папка native/, сборка tools/build_native.sh).
## Если библиотеки нет (другая платформа, редактор без неё) или задано STEEL_NO_NATIVE=1,
## make() вернёт null и всё посчитает GDScript, как раньше.

static var _shared: Object = null


static func available() -> bool:
	return ClassDB.class_exists("SteelCore") and OS.get_environment("STEEL_NO_NATIVE") != "1"


## Свой экземпляр на бой: рельеф, препятствия, сетка путей.
static func make() -> Object:
	return ClassDB.instantiate("SteelCore") if available() else null


## Общий экземпляр для расчётов без состояния: слияние геометрии, текстуры.
static func shared() -> Object:
	if _shared == null and available():
		_shared = make()
	return _shared
