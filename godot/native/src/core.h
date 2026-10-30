// Состояние ускоренных расчётов одного боя: рельеф, препятствия, сетка путей, коробки построек.
// Заполняется при загрузке боя, дальше только читается (поэтому маршруты можно искать из потока).
#pragma once

#include "glue.h"

#include <cmath>
#include <cstdint>
#include <vector>

using gd::V2;
using gd::V3;

struct Rect {
	float x, y, w, h;
	bool solid;
	bool has(float px, float py) const { return px >= x && py >= y && px < x + w && py < y + h; }
};

// Коробка постройки (как у физики): центр, полуразмеры, поворот вокруг вертикали.
struct Box {
	float cx, cy, cz, hx, hy, hz, c, s;
};

// Пространственная сетка: клетка → номера предметов (как _hput/_near в battle.gd).
struct Hash {
	float cell = 100.0f;
	int x0 = 0, y0 = 0, nx = 0, ny = 0;
	std::vector<std::vector<int>> cells;
	void build(float lo, float hi, float p_cell);
	void put(float ax, float ay, float bx, float by, int item);
	const std::vector<int> *at(int cx, int cy) const;
	int key(float v, bool y) const { return (int)std::floor(v / cell) - (y ? y0 : x0); }
};

struct Core {
	// рельеф: (n+1)² высот с шагом cell от origin
	std::vector<float> h;
	std::vector<float> cmax;  // наивысшая точка каждой клетки рельефа: луч выше неё клетку пропускает
	int tn = 0;
	float origin = 0.0f, cell = 1.0f;
	float ws = 2860.0f;  // сторона игровой зоны

	std::vector<Rect> obst;
	Hash ohash;
	std::vector<Box> boxes;
	Hash bhash;

	// маска грунта (RGBA8, сторона mask_w): R — дорога, G — гарь воронок
	std::vector<uint8_t> mask;
	int mask_w = 0;
	float tsize = 1.0f;  // сторона рельефа в единицах (маска натянута на него)

	// сетка путей
	float nav_cell = 25.0f;
	int nn = 0;
	std::vector<uint8_t> solid, cover;
	std::vector<float> w_norm, w_safe;

	// грунт под гусеницами (как Battle.ground_at): вид покрытия, база мягкости и сцепления, шум пятен
	int surf = 0;  // 0 — трава и прочее, 1 — песок, 2 — снег, 3 — город
	float soft_base = 0.0f, mu_base = 0.75f, road_mu = 0.9f;
	std::vector<uint8_t> noise;
	int noise_w = 0;

	// разрушаемые деревья и заборы
	struct Prop {
		float x, y, r;
		bool alive, wood;
	};
	std::vector<Prop> props;
	Hash phash;

	// кусты (для засад и укрытий ботов): [x, y, r]
	std::vector<float> bushes;
	Hash bush_hash;

	// неизменные характеристики танков боя (по порядку Battle.tanks)
	struct TankStatic {
		float speed, rev, turn, accel, mass, W, L, press, spring_k, spring_c;
		float casemate, trav, elev0, elev1, shell_v, tspd;
		V3 gun_pos0, tur_pos0;
		float disp, stab, aim, track_z, track_w;
		float armor0, armor1, armor2, slope, side_slope, pen, pref;
	};
	std::vector<TankStatic> ts;
	// следы гусениц: где кончился след левой и правой и пройденный вдоль следа путь
	std::vector<V2> last_mark;
	std::vector<float> mark_v;
	// снимок пакета после последнего шага физики — по нему решают боты (C++-часть этапа 4)
	std::vector<float> snap;

	void build_cmax();
	float patch(float px, float py, bool damp) const;
	V2 ground_at(float px, float py) const;  // (сцепление, мягкость)
	V2 resolve(float &px, float &py, float r) const;  // выталкивание из построек
	bool in_bush(float px, float py) const;
	int trees_near(float px, float py, float r) const;
	float height(float x, float z) const;
	bool terrain_clear(V3 a, V3 b) const;
	V3 normal(float x, float z, float e) const;
	bool blocked_at(float px, float py, float r) const;
	bool straight(V2 a, V2 b, float r) const;
	bool los(V3 a, V3 b) const;
	std::vector<V2> nav_path(V2 from, V2 to, bool safe, float r) const;
};

void register_core(GDExtensionClassLibraryPtr lib);
