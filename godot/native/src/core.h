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
	// номер клетки, ограниченный сеткой (-1…n): цикл по клеткам не выйдет за неё даже при огромных
	// или нечисловых координатах (на ARM перевод такого числа в int даёт не то же, что на x86)
	int key(float v, bool y) const {
		double k = std::floor((double)v / cell) - (y ? y0 : x0);
		int n = y ? ny : nx;
		if (!(k >= -1.0)) return -1;
		if (k > n) return n;
		return (int)k;
	}
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
		float hh, th, armored;
	};
	// покадровое управление ботом (Battle._bot без решений): строфа, объезд, «застрял», маршрут
	struct Bot {
		float st = 1.0f, strafe = 1.0f, av = 0.0f, av_dir = 1.0f, pt = 1.0f;
		V2 last = { -1e6f, -1e6f };
		int pi = 0;
		std::vector<V2> path;
	};
	std::vector<Bot> bots;

	// ---- решения ботов (этап 5): Battle._think/_plan/_squads_update/_lane_power, память о врагах ----
	struct BotAi {
		int cls = 1, lane = 1, act = 0, spot_kind = 0, tg = -1, zone = -1;  // cls: 0 ЛТ, 1 СТ, 2 ТТ, 3 ПТ; lane: 0 высота, 1 центр, 2 застройка
		bool def = false, player = false, has_spot = false, has_peek = false, hold = false, adv = true, los = false;
		V2 off = { 0, 0 }, spot = { 0, 0 }, peek = { 0, 0 }, goal = { 0, 0 };
		float side = 1.0f, back_t = 0.0f, spot_t = 0.0f, pts = 5.0f, max_hp = 1.0f, dmg = 100.0f, reload = 3.0f, height = 20.0f, barrel = 30.0f;
	};
	std::vector<BotAi> ai;
	bool ai_on = false;
	int mode = 0;  // 0 стандартный, 1 встречный, 2 превосходство
	float time_limit = 420.0f, clock = 0.0f;
	float lane_x[3] = { 0, 0, 0 };
	struct Squad {
		int stage = 0, n0 = 0;
		float t = 0.0f;
	};
	Squad squads[2][3];
	struct Zone {
		float x, y, r;
		int side;
		float prog[2];
		int n[2];
	};
	std::vector<Zone> zones;
	struct Intel {
		V2 pos;
		float t = -1e9f;
		bool has = false;
	};
	std::vector<Intel> intel[2];  // команда → по танку: где и когда видели
	uint32_t rng = 0x9e3779b9u;
	float randf() {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return (rng >> 8) / 16777216.0f;
	}
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
	// решения ботов (по снимку snap)
	int choose(int i) const;
	bool foe_guess(V2 bp, int team, V2 &out) const;
	bool foe_near(int i, float r) const;
	bool covered(V2 p) const;
	bool cover_near(V2 p, float r, V2 &out) const;
	bool bush_near(V2 p, float r, int bi, V2 &out) const;
	bool ally_near(V2 p, int team, float r, int bi) const;
	bool find_spot(int i, V3 eye, bool hull, V2 &out);
	V2 stage_point(int team, int lane, int stage) const;
	int max_stage() const { return mode == 0 ? 6 : 4; }
	int alive_count(int team) const;
	int lane_of(float x) const;
	V2 lane_power(int team, int lane, bool autopilot) const;
	V2 plan(int i);
	bool think(int i, V2 &route_to, bool &route_safe);
	void squads_update(bool autopilot);
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
