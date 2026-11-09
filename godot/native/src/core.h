// Состояние ускоренных расчётов одного боя: рельеф, препятствия, сетка путей, коробки построек.
// Заполняется при загрузке боя, дальше только читается (поэтому маршруты можно искать из потока).
#pragma once

#include "glue.h"

#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>

// Веб без потоков (Яндекс Игры: страница без SharedArrayBuffer): маршруты считаются в шаге боя
#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
#define STEEL_NO_THREADS
#endif
#include <thread>
#include <vector>

using gd::V2;
using gd::V3;

// Матрица 3×3 (строки): повороты вокруг Y, Z, X — как Basis(Vector3.UP / BACK / RIGHT, угол)
struct M3 {
	float m[3][3];
	static M3 ident() { return { { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } }; }
	static M3 rot(int axis, float a);
	M3 operator*(const M3 &o) const;
	V3 mul(V3 v) const { return { m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z, m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z, m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z }; }
	V3 tmul(V3 v) const { return { m[0][0] * v.x + m[1][0] * v.y + m[2][0] * v.z, m[0][1] * v.x + m[1][1] * v.y + m[2][1] * v.z, m[0][2] * v.x + m[1][2] * v.y + m[2][2] * v.z }; }
};

struct Rect {
	float x, y, w, h;
	bool solid;
	bool dead = false;  // постройка разрушена: танки проезжают
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

	// Точная коллизия построек для снарядов, прицела и видимости — треугольники той же геометрии, что
	// видна на экране (MapGen: дома, крыши, руины, скалы, остовы, мешки...). Объекты разбиты на куски
	// со своей коробкой, куски разложены по сетке. Пусто — старые коробки boxes.
	struct WObj {
		float lo[3], hi[3];
		int t0, t1;  // треугольники [t0, t1) в wtri
		int obj = -1;  // номер постройки (obst); разрушенная — луч сквозь
	};
	std::vector<float> wtri;  // 9 чисел на треугольник: вершина A, рёбра E1 = B − A, E2 = C − A; E1 × E2 — наружу
	std::vector<WObj> wobj;
	Hash whash;
	// tri — треугольники подряд по объектам, objs — [начало, конец, номер постройки] каждого объекта
	void mesh_build(const std::vector<float> &tri, const std::vector<int> &objs);
	// Отрезок [a, a + d] против точной коллизии: доля пути до ближайшего попадания (2 — мимо); any — первое попавшееся;
	// obj — номер постройки, в которую попал луч
	float mesh_t(V3 a, V3 d, bool any, int *obj = nullptr) const;
	// разрушаемость: прочность постройки (< 0 — неразрушима), рушится ли тараном, разрушена ли
	std::vector<float> obj_hp;
	std::vector<uint8_t> obj_soft, obj_dead;
	bool obj_damage(int obj, float dmg);  // true — от этого удара постройка рухнула
	void obj_destroy(int obj);
	V3 obj_center(int obj) const;

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
		float neutral;  // 1 — разворот на месте вокруг центра (планетарный механизм), 0 — вокруг заторможенной гусеницы
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
		float release_t = 0.0f;  // резерв волны: до этого времени стоит на месте
	};
	std::vector<BotAi> ai;
	bool ai_on = false;
	int mode = 0;  // 0 стандартный, 1 встречный, 2 превосходство
	// миссия кампании: каким командам можно брать базы (бит команды), кто побеждает по времени
	// (1 победа, 2 поражение, 3 ничья; −1 — как в обычном бою), какая команда обороняется
	int cap_mask = 3, timeout_result = -1;
	bool hold_team[2] = { false, false };
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

	// ---- снаряды и урон (этап 6): полёт, попадания в рельеф, постройки и танки, броня, модули, экипаж ----
	struct DmgStatic {
		float armor[6];  // корпус: лоб, борт, корма; башня (рубка): лоб, борт, корма
		float tslope, slope, side_slope, L, W, hull_y0, hh, th, cal, pen, mass;
		V3 up_min, up_max, up_pos, gp;  // коробка башни; где она на корпусе; орудие в её осях
		bool casemate;
	};
	std::vector<DmgStatic> ds;
	float upm = 7.5f;
	struct LayoutItem {
		bool crew, top;  // член экипажа (иначе модуль); в башне (рубке)
		int idx;  // номер в Tank.CREW или Tank.MODS
		V3 c, h;
		float r;  // > 0 — шар (экипаж)
	};
	std::vector<std::vector<LayoutItem>> layout;
	std::vector<uint8_t> top_gone;  // башню сорвало взрывом: её коробки больше нет
	struct Shell {
		V3 pos, vel;
		float dmg, pen, cal, dist;
		float he = 0.0f;  // ВВ в снаряде, г (0 — сплошная болванка)
		int kind = 0;  // AM_*: основной, подкалиберный, фугасный, кумулятивный, дымовой
		int owner, rico, slot;
		bool whiz = false, dead = false;
		// попадание в танк на этом шаге (разбирает shell_hit)
		int hit_tank = -1, hit_part = 0;
		V3 hit_pos, hit_n, hit_v;
	};
	std::vector<Shell> shells;
	// дымовые завесы: шар, до какого времени снарядов (shell_clock) стоит; закрывают прямую видимость
	struct Smoke {
		V3 p;
		float r, until;
	};
	std::vector<Smoke> smokes;
	float shell_clock = 0.0f;
	bool smoke_blocks(V3 a, V3 b) const;
	struct TankHit {
		int tank = -1, part = 0;  // part: 0 корпус, 1 башня (рубка)
		float t = 2.0f;
		V3 n_local = { 0, 0, 0 };
	};
	void part_xf(int i, int part, M3 &basis, V3 &origin) const;
	bool segment_hit(V3 a, V3 b, float &t, bool &ground, int *obj = nullptr) const;
	float boxes_t(V3 a, V3 d) const;
	bool tanks_hit(V3 a, V3 b, int exclude, TankHit &out) const;
	// ---- бой целиком (этап 7): всё состояние танков и боя живёт здесь, GDScript только показывает ----
	struct TankDyn {
		float hp = 1, max_hp = 1, rl = 0, rl_max = 1, lit = 0, recoil = 0, fire = 0, track_broken = 0, dmg_dealt = 0;
		int fire_by = -1, shots = 0, hits_taken = 0, pens_taken = 0;
		float mod[6] = { 100, 100, 100, 100, 100, 100 };
		float fix[6] = { -1, -1, -1, -1, -1, -1 };  // до полевого ремонта уничтоженного модуля; < 0 — не чинится
		// экипаж: 0 командир, 1 наводчик, 2 заряжающий, 3 мехвод, 4 радист; место есть / жив / здоровье
		bool crew_has[5] = { true, true, true, true, false };
		bool crew[5] = { true, true, true, true, false };
		float crew_hp[5] = { 100, 100, 100, 100, 0 };
		float swap_t[5] = { -1, -1, -1, -1, -1 };  // подмена: через сколько займёт место (< 0 — нет)
		float swap_hp[5] = { 0, 0, 0, 0, 0 };  // здоровье того, кто пересаживается
		float he = 0;  // ВВ снаряда, г
		// боекомплект: виды снарядов этого орудия (первый — основной, без счёта)
		struct Ammo {
			int kind = 0, left = -1, used = 0;  // left < 0 — без счёта
			float pen = 0, dmg = 0, he = 0, vel_k = 1;
		};
		Ammo am[5];
		int am_n = 0, am_cur = 0;
		bool gun_crew = true, drive_crew = true;  // есть кому стрелять / вести
		bool alive = true, player = false, immobile = false, popping = false;
		float speed_k = 1, accel_k = 1, turn_k = 1, tspd_k = 1, reload_k = 1, aim_k = 1, disp_k = 1, spot_k = 1;
		bool cons_has[3] = { false, false, false }, cons_used[3] = { false, false, false };
		float cons_cd[3] = { 0, 0, 0 }, cons_t[3] = { -1, -1, -1 };  // перезарядка; бот: через сколько применит
		float cons_acc = 0, think_t = 0;
		// маршрут
		bool path_wait = false, path_safe = false;
		V2 path_to = { -1e6f, -1e6f };
		float path_t = 0;
		// постоянное
		float spot = 500, reload = 3, dmg = 100, speed = 50, tspd = 1, W = 20;
		// узлы сцены и что им уже отдано
		gd::Obj root = nullptr, hull_n = nullptr, tur_n = nullptr, gun_n = nullptr, paint[3] = { nullptr, nullptr, nullptr };
		gd::Obj track_mat = nullptr, dust = nullptr, mud = nullptr, smoke = nullptr, snd[3] = { nullptr, nullptr, nullptr };
		float travel_prev[2] = { 0, 0 }, gy_set = -1e9f, eng_pitch = 1;
		float travel_sent[2] = { -1e9f, -1e9f };  // ход гусениц, уже отданный шейдерам
		uint8_t travel_tick = 0;
		float key[4] = { 1e30f, 0, 0, 0 };  // остов: что нарисовано (не менялось — не трогаем)
		int8_t shown = -1, smoke_on = -1, dust_on = 0, mud_on = 0, snd_paused[3] = { -1, -1, -1 };
	};
	std::vector<TankDyn> td;
	struct World {
		bool on = false, over = false, sync_routes = false;
		int player = -1, watch = -1, result = 0, reason = -1, shell_slot = 0, trk_i = 0, trk_n = 4000, speed = 1;
		float spot_t = 0, squad_t = 0, cap_rate = 2.2f, sup_goal = 600, score[2] = { 0, 0 };
		float cons_cd[3] = { 90, 90, 60 };
		// заслуги игрока: урон, по засвету, заблокировано, захват, защита; убито, попаданий, выстрелов, засвечено
		float dmg_done = 0, spot_dmg = 0, blocked = 0, cap_pts = 0, def_pts = 0;
		int kills = 0, hits = 0, shots = 0, spotted_n = 0;
		int stat[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };  // пробитий, непробитий, рикошетов, промахов, таранов, гусениц, пожаров, боеукладок
		std::vector<int> spotter;
		std::vector<uint8_t> reported;
		gd::Obj trk_mm = nullptr;
		// для HUD: прицел игрока
		float gun_point[3] = { 0, 0, 0 }, aim_point[3] = { 0, 0, 0 };
		int pen_hint = -1;
		bool gun_limited = false;
	} w;
	// поиск маршрутов в своём потоке: заявки от ботов, готовые пути забирает шаг боя
	struct RouteJob {
		int bot;
		V2 from, to;
		bool safe;
		float r;
	};
	struct RouteDone {
		int bot;
		V2 to;
		bool safe;
		std::vector<V2> path;
	};
	std::thread nav_thread;
	std::mutex nav_mx;
	std::condition_variable nav_cv;
	std::deque<RouteJob> nav_jobs;
	std::vector<RouteDone> nav_done;
	bool nav_quit = false;
	void nav_start();
	void nav_stop();
	~Core() { nav_stop(); }
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
	V2 resolve(float &px, float &py, float r, int *hit = nullptr) const;  // выталкивание из построек; hit — в какую упёрся
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
