// Бой целиком (этап 7): состояние танков и боя живёт здесь, один вызов world_step на шаг логики.
// Повторяет Battle._update и всё, что он звал: таймеры, пожар, полевой ремонт, снаряжение, решения
// и маршруты ботов, управление игрока, выстрел, физику, снаряды и урон, засвет, базы, очки, конец
// боя, награды. Узлы танков (корпус, башня, орудие), параметры шейдеров гусениц, шлейфы пыли,
// дым повреждённых и звук моторов C++ ставит сам через API движка. GDScript получает события
// (эффекты, звуки, надписи, рация) и короткие сводки для интерфейса.
#include "common.h"

#include <cstdio>
#include <cstdlib>

namespace {

// ---------- методы движка (хэши из extension_api.json Godot 4.7) ----------

struct Api {
	gd::MB set_position = nullptr, set_basis = nullptr, set_transform = nullptr, set_global_position = nullptr;
	gd::MB set_visible = nullptr, set_param = nullptr, mm_xf = nullptr, mm_color = nullptr, set_emitting = nullptr;
	gd::MB snd_paused = nullptr, snd_pitch = nullptr, snd_volume = nullptr;
	gd::Name travel_l, travel_r, off_l, off_r, ground_y, emitting;
	bool ok = false;
	void load() {
		if (ok) return;
		set_position = gd::method("Node3D", "set_position", 3460891852);
		set_basis = gd::method("Node3D", "set_basis", 1055510324);
		set_transform = gd::method("Node3D", "set_transform", 2952846383);
		set_global_position = gd::method("Node3D", "set_global_position", 3460891852);
		set_visible = gd::method("Node3D", "set_visible", 2586408642);
		set_param = gd::method("ShaderMaterial", "set_shader_parameter", 3776071444);
		mm_xf = gd::method("MultiMesh", "set_instance_transform", 3616898986);
		mm_color = gd::method("MultiMesh", "set_instance_custom_data", 2878471219);
		// частицы — свои излучатели (scripts/emitter.gd): включаются свойством emitting через Object.set
		set_emitting = gd::method("Object", "set", 3776071444);
		snd_paused = gd::method("AudioStreamPlayer3D", "set_stream_paused", 2586408642);
		snd_pitch = gd::method("AudioStreamPlayer3D", "set_pitch_scale", 373806689);
		snd_volume = gd::method("AudioStreamPlayer3D", "set_volume_db", 373806689);
		travel_l = gd::sname("travel_l");
		travel_r = gd::sname("travel_r");
		off_l = gd::sname("off_l");
		off_r = gd::sname("off_r");
		ground_y = gd::sname("ground_y");
		emitting = gd::sname("emitting");
		ok = set_position && set_basis && set_transform && set_global_position && set_visible && set_param && mm_xf && mm_color &&
			 set_emitting && snd_paused && snd_pitch && snd_volume;
	}
};
Api api;

inline void emit_set(gd::Obj p, bool on) { gd::call_param(api.set_emitting, p, api.emitting, on ? 1.0 : 0.0); }

inline void basis9(const M3 &m, float out[9]) {
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			out[i * 3 + j] = m.m[i][j];
		}
	}
}

// Поворот, переводящий «вверх» в направление d (как Basis(Quaternion(Vector3.UP, d))).
M3 up_to(V3 d) {
	d = v3norm(d);
	M3 r = M3::ident();
	float c = d.y;  // cos угла между UP и d
	if (c > 0.99999f) return r;
	if (c < -0.99999f) return M3::rot(0, PI_F);
	V3 ax = v3norm({ d.z, 0.0f, -d.x });  // UP × d
	float s = std::sqrt(std::max(0.0f, 1.0f - c * c)), t = 1.0f - c;
	float x = ax.x, y = ax.y, z = ax.z;
	r.m[0][0] = t * x * x + c;
	r.m[0][1] = t * x * y - s * z;
	r.m[0][2] = t * x * z + s * y;
	r.m[1][0] = t * x * y + s * z;
	r.m[1][1] = t * y * y + c;
	r.m[1][2] = t * y * z - s * x;
	r.m[2][0] = t * x * z - s * y;
	r.m[2][1] = t * y * z + s * x;
	r.m[2][2] = t * z * z + c;
	return r;
}

inline float linear_to_db(float v) { return 20.0f * std::log10(v); }

// ---------- события для GDScript ----------
enum WorldEv {
	W_SHOT = 20,  // танк, трассер, дуло xyz, направление xyz, калибр, скорость снаряда
	W_DMG,  // танк, кто, урон, вид (0 — снаряд, 2 — таран)
	W_KILL,  // танк, кто, башню сорвало, причина (0 прочее, 1 экипаж выбыл, 2 боеукладка, 3 сгорел экипаж)
	W_WALL,  // танк, сила удара
	W_TREE,  // танк, дерево, куда падает x, z
	W_RAM,  // танк, другой
	W_EXHAUST,  // x, y, z, курс x, z
	W_REPAIRED,  // танк, модуль
	W_CONS,  // танк, что применил
	W_FIRE_OUT,  // танк
	W_SPOTTED,  // танк, направление «по часам» от наблюдаемого
	W_ZONE,  // зона, чья теперь
	W_FINISH,  // итог (1 победа, 2 поражение, 3 ничья), причина
	W_SWAP,  // танк, место, откуда пересел: член экипажа занял место выбывшего
	W_INF_SHOT,  // вид (роль бойца; 5 — пулемёт танка; 6 — граната), откуда xyz, направление xyz, место трассера (−1 — пуля), скорость или дальность, кто
	W_INF_DEAD,  // боец, кто (танк или −1), причина (0 пуля, 1 осколки, 2 гусеницы), x, y, z, команда
	W_STRIKE,  // вид (0 артудар, 1 штурмовик), команда, x, z, через сколько секунд, курс захода x, z
};

enum { IR_RIFLE, IR_SMG, IR_ATR, IR_TUBE, IR_FAUST, IR_CREW, IR_GUN };
enum { IS_STAND, IS_RUN, IS_AIM, IS_KNEEL, IS_PRONE, IS_CRAWL, IS_DEAD_B, IS_DEAD_F, IS_THROW, IS_CROUCH };
const int INF_VIEW = 9;  // на бойца: x, высота, z, курс, поза, фаза, команда, роль + 8 × нация, признаки (1 жив, 2 виден игроку, 4 стрелял только что)

enum { CONS_REPAIR, CONS_MEDKIT, CONS_EXT };
enum { CREW_COMMANDER, CREW_GUNNER, CREW_LOADER, CREW_DRIVER, CREW_RADIO, CREW_N };
const float REPAIR_T[6] = { -1, 10, 8, 8, 12, -1 };  // полевой ремонт: орудие, погон, приборы, боеукладка
const float TRACK_REPAIR = 7.0f, FIRE_TIME = 14.0f;
const float SWAP_TIME = 6.0f;  // за сколько член экипажа пересаживается на место выбывшего
const float BURN_CREW = 3.2f;  // пожар: здоровья экипажа в секунду

const int VIEW = 9;  // на танк: x, z, земля, жив, виден 0, виден 1, прочность, курс корпуса, курс башни
const int DET = 50;  // подробно об игроке и наблюдаемом (поля — Battle._mirror_detail)
const int OUT = 34;  // прицел, счёт, заслуги, итог; дальше по 5 чисел на зону
const int IN = 17;  // ввод: ход, камера, огонь, снаряжение, автопилот, автоприцел, наблюдаемый, …

inline int mstate(float v) { return v > 50.0f ? 2 : (v > 0.0f ? 1 : 0); }

} // namespace

// ---------- состояние танка: модули, экипаж, снаряжение (как Tank.recalc, hit_module, use_cons) ----------

static void recalc(Core::TankDyn &d, bool casemate) {
	int e = mstate(d.mod[MOD_ENGINE]);
	d.immobile = e == 0;
	const float sp[3] = { 0.0f, 0.55f, 1.0f }, ac[3] = { 0.0f, 0.5f, 1.0f }, tu[3] = { 0.0f, 0.7f, 1.0f };
	d.speed_k = sp[e];
	d.accel_k = ac[e];
	d.turn_k = tu[e];
	int g = mstate(d.mod[MOD_GUN]);
	const float dk[3] = { 1.0f, 1.5f, 1.0f }, ak[3] = { 1.0f, 1.35f, 1.0f };
	d.disp_k = dk[g];
	d.aim_k = ak[g];
	const float tk[3] = { 0.0f, 0.5f, 1.0f }, sk[3] = { 0.5f, 0.75f, 1.0f }, rk[3] = { 1.6f, 1.25f, 1.0f };
	d.tspd_k = casemate ? 1.0f : tk[mstate(d.mod[MOD_TURRET])];
	d.spot_k = sk[mstate(d.mod[MOD_OPTICS])];
	d.reload_k = rk[mstate(d.mod[MOD_AMMO])];
	// экипаж: без наводчика (его некому заменить) не стрелять, без мехвода — не ехать
	d.gun_crew = d.crew[CREW_GUNNER] || (!d.crew_has[CREW_GUNNER] && d.crew[CREW_COMMANDER]);
	d.drive_crew = d.crew[CREW_DRIVER];
	if (!d.drive_crew) d.immobile = true;
	if (d.crew_has[CREW_COMMANDER] && !d.crew[CREW_COMMANDER]) {
		d.spot_k *= 0.8f;
		d.reload_k *= 1.08f;
		d.aim_k *= 1.1f;
	}
	if (d.crew_has[CREW_LOADER] && !d.crew[CREW_LOADER]) {
		d.reload_k *= 1.6f;  // заряжает наводчик
	}
	// раненые работают медленнее
	if (d.crew[CREW_GUNNER] && d.crew_hp[CREW_GUNNER] < 50.0f) d.aim_k *= 1.15f;
	if (d.crew[CREW_LOADER] && d.crew_hp[CREW_LOADER] < 50.0f) d.reload_k *= 1.15f;
	if (d.crew[CREW_DRIVER] && d.crew_hp[CREW_DRIVER] < 50.0f) d.accel_k *= 0.85f;
}

// сколько человек живо (с теми, кто пересаживается)
static int crew_left(const Core::TankDyn &d) {
	int n = 0;
	for (int k = 0; k < CREW_N; k++) n += (d.crew[k] || d.swap_t[k] >= 0.0f) ? 1 : 0;
	return n;
}

static bool crew_wounded(const Core::TankDyn &d) {
	for (int k = 0; k < CREW_N; k++) {
		if (d.crew[k] && d.crew_hp[k] < 100.0f) return true;
	}
	return false;
}

// «Состояние» танка 0–1 (вместо прочности): здоровье экипажа и модули. По нему ИИ решает, отходить
// ли, а урон по танку — разница состояний (так считаются заслуги и серебро).
static float condition(const Core::TankDyn &d) {
	float ch = 0.0f, cn = 0.0f;
	for (int k = 0; k < CREW_N; k++) {
		if (!d.crew_has[k]) continue;
		cn += 1.0f;
		ch += (d.crew[k] ? d.crew_hp[k] : (d.swap_t[k] >= 0.0f ? d.swap_hp[k] : 0.0f)) / 100.0f;
	}
	float mh = 0.0f;
	for (float m : d.mod) mh += clampf(m, 0.0f, 100.0f) / 100.0f;
	return 0.78f * ch / std::max(cn, 1.0f) + 0.22f * mh / 6.0f;
}

static bool cons_needed(const Core::TankDyn &d, int c) {
	switch (c) {
		case CONS_REPAIR:
			if (d.track_broken > 0.0f) return true;
			for (float m : d.mod) {
				if (mstate(m) < 2) return true;
			}
			return false;
		case CONS_MEDKIT:
			return crew_wounded(d);
		default:
			return d.fire > 0.0f;
	}
}

namespace {

struct Step {
	Core *c;
	float dt;
	EvOut ev;
	std::vector<float> &P() { return c->snap; }
	float *T(int i) { return &c->snap[(size_t)i * PHYS]; }
	int n() const { return (int)c->td.size(); }
	float randf() { return c->randf(); }
	float rnd(float a, float b) { return a + (b - a) * c->randf(); }
	float randn() {  // нормальное (Бокс — Мюллер)
		float u1 = std::max(1e-7f, c->randf()), u2 = c->randf();
		return std::sqrt(-2.0f * std::log(u1)) * std::cos(2.0f * PI_F * u2);
	}
	int team(int i) { return i < 0 ? -1 : (int)T(i)[P_TEAM]; }
	V2 pos(int i) { return { T(i)[P_X], T(i)[P_Y] }; }
	V3 center(int i) { return { T(i)[P_X], T(i)[P_GROUND] + c->ts[i].hh * 0.6f, T(i)[P_Y] }; }
	V3 top(int i) { return { T(i)[P_X], T(i)[P_GROUND] + c->ai[i].height - 2.0f, T(i)[P_Y] }; }
	bool in_zone(int i, const Core::Zone &z) {
		float dx = T(i)[P_X] - z.x, dy = T(i)[P_Y] - z.y;
		return dx * dx + dy * dy < z.r * z.r;
	}

	// снаряжение (как Tank.use_cons)
	bool use_cons(int i, int k) {
		Core::TankDyn &d = c->td[i];
		if (k < 0 || k > 2 || !d.cons_has[k] || d.cons_cd[k] > 0.0f || !d.alive) return false;
		if (k == CONS_REPAIR) {
			bool any = d.track_broken > 0.0f;
			for (float &m : d.mod) {
				if (m < 100.0f) {
					any = true;
					m = m <= 0.0f ? 30.0f : 100.0f;
				}
			}
			if (!any) return false;
			d.track_broken = 0.0f;
			for (float &f : d.fix) f = -1.0f;
		} else if (k == CONS_MEDKIT) {
			// аптечка лечит раненых (выбывших не поднимает)
			if (!crew_wounded(d)) return false;
			for (int m = 0; m < CREW_N; m++) {
				if (d.crew[m]) d.crew_hp[m] = 100.0f;
			}
		} else {
			if (d.fire <= 0.0f) return false;
			d.fire = 0.0f;
		}
		d.cons_cd[k] = c->w.cons_cd[k];
		d.cons_used[k] = true;
		recalc(d, c->ds[i].casemate);
		d.hp = std::max(1.0f, condition(d) * d.max_hp);
		ev.add({ (float)W_CONS, (float)i, (float)k });
		return true;
	}

	// бот применяет снаряжение не сразу: через 1–3 с после беды (Battle._bot_cons)
	void bot_cons(int i) {
		Core::TankDyn &d = c->td[i];
		d.cons_acc += dt;
		if (d.cons_acc < 0.25f) return;
		float acc = d.cons_acc;
		d.cons_acc = 0.0f;
		for (int k = 0; k < 3; k++) {
			if (!d.cons_has[k]) continue;
			bool need = d.cons_cd[k] <= 0.0f && cons_needed(d, k);
			if (need && k == CONS_REPAIR) {
				need = d.track_broken > 0.0f || mstate(d.mod[MOD_ENGINE]) == 0 || mstate(d.mod[MOD_GUN]) == 0;
			} else if (need && k == CONS_MEDKIT) {
				need = false;
				for (int m = 0; m < CREW_N; m++) need = need || (d.crew[m] && d.crew_hp[m] < 55.0f);
			}
			if (!need) {
				d.cons_t[k] = -1.0f;
				continue;
			}
			if (d.cons_t[k] < 0.0f) d.cons_t[k] = k == CONS_EXT ? rnd(0.6f, 1.5f) : rnd(1.0f, 3.0f);
			d.cons_t[k] -= acc;
			if (d.cons_t[k] <= 0.0f) {
				d.cons_t[k] = -1.0f;
				use_cons(i, k);
			}
		}
	}

	// заслуги за урон: amount — сколько «состояния» танка (в единицах прежней прочности) снято;
	// tag: 0 — снаряд, 1 — пожар, 2 — таран
	void credit(int i, float amount, int by, int tag) {
		Core::TankDyn &d = c->td[i];
		if (!(amount > 0.0f)) return;
		Core::World &w = c->w;
		float real = amount;
		T(i)[P_HIT_T] = c->clock;
		if (by >= 0 && by != i) {
			c->td[by].dmg_dealt += real;
			if (team(by) == 0 && team(i) == 1) d.lit = std::max(d.lit, 2.0f);
			if (by == w.player) {
				w.dmg_done += real;
			} else if (team(by) == 0 && team(i) == 1 && (size_t)i < w.spotter.size() && w.spotter[i] == w.player) {
				w.spot_dmg += real;
			}
		}
		if (tag != 1) {
			for (Core::Zone &z : c->zones) {
				int tm = team(i);
				if (in_zone(i, z) && z.prog[tm] > 0.0f) {
					if (by == w.player && z.side == 0) w.def_pts += std::min(z.prog[tm], 40.0f);
					z.prog[tm] = std::max(0.0f, z.prog[tm] - 40.0f);
				}
			}
			ev.add({ (float)W_DMG, (float)i, (float)by, amount, (float)tag });
		}
	}

	// после удара: новое «состояние», заслуги стрелку; меньше двух человек — танк выбыл
	void update(int i, int by, int tag, int why = 1) {
		Core::TankDyn &d = c->td[i];
		if (!d.alive) return;
		float now = condition(d) * d.max_hp;
		float amount = d.hp - now;
		d.hp = std::max(now, 1.0f);
		if (amount > 0.0f) credit(i, amount, by, tag);
		if (crew_left(d) < 2) destroy(i, by, why);
	}

	// уничтожен: остаток «состояния» — в заслуги стрелку
	void destroy(int i, int by, int why) {
		Core::TankDyn &d = c->td[i];
		if (!d.alive) return;
		credit(i, d.hp, by, 0);
		kill(i, by, why);
	}

	// ранение члена экипажа; выбыл — на его место пересядет кто сможет
	void crew_hit(int i, int k, float dmg, int by) {
		Core::TankDyn &d = c->td[i];
		if (!d.alive || k < 0 || k >= CREW_N || !d.crew[k] || !(dmg > 0.0f)) return;
		d.crew_hp[k] -= dmg;
		if (d.crew_hp[k] > 0.0f) {
			recalc(d, c->ds[i].casemate);
			return;
		}
		d.crew_hp[k] = 0.0f;
		d.crew[k] = false;
		try_swap(d);
		recalc(d, c->ds[i].casemate);
		(void)by;
	}

	// подмена: место наводчика и мехвода важнее, их занимают радист или заряжающий, место заряжающего — радист
	static void try_swap(Core::TankDyn &d) {
		static const int need[3] = { CREW_GUNNER, CREW_DRIVER, CREW_LOADER };
		for (int slot : need) {
			if (!d.crew_has[slot] || d.crew[slot] || d.swap_t[slot] >= 0.0f) continue;
			int donor = -1;
			if (d.crew_has[CREW_RADIO] && d.crew[CREW_RADIO]) {
				donor = CREW_RADIO;
			} else if (slot != CREW_LOADER && d.crew_has[CREW_LOADER] && d.crew[CREW_LOADER]) {
				donor = CREW_LOADER;
			}
			if (donor < 0) continue;
			d.swap_hp[slot] = d.crew_hp[donor];
			d.swap_t[slot] = SWAP_TIME;
			d.crew[donor] = false;
			d.crew_hp[donor] = 0.0f;
		}
	}

	// таран: удар достаётся экипажу и двигателю (в долях прежней прочности)
	void ram_hit(int i, float amount, int by) {
		Core::TankDyn &d = c->td[i];
		if (!d.alive || !(amount > 0.0f)) return;
		float frac = amount / std::max(d.max_hp, 1.0f);
		for (int k = 0; k < CREW_N; k++) {
			if (d.crew[k]) d.crew_hp[k] = std::max(1.0f, d.crew_hp[k] - frac * 80.0f * rnd(0.6f, 1.2f));
		}
		int was, now;
		hit_module(i, MOD_ENGINE, frac * 60.0f, was, now);
		recalc(d, c->ds[i].casemate);
		update(i, by, 2);
	}

	void kill(int i, int by, int why = 0) {
		Core::TankDyn &d = c->td[i];
		Core::World &w = c->w;
		d.alive = false;
		d.hp = 0.0f;
		d.fire = 0.0f;
		float *t = T(i);
		t[P_ALIVE] = 0.0f;
		t[P_GUN_PITCH] = c->ts[i].elev0;  // орудие остова опущено
		t[P_SP] = 0.0f;
		t[P_VX] = 0.0f;
		t[P_VY] = 0.0f;
		bool pop = randf() < 0.45f && !c->ds[i].casemate;
		if (pop) {
			d.popping = true;
			if ((size_t)i < c->top_gone.size()) c->top_gone[i] = 1;
		}
		if (by == w.player) w.kills++;
		if (c->mode == 2 && by >= 0) w.score[team(by)] += 25.0f;
		if (d.smoke && d.smoke_on == 1) {
			emit_set(d.smoke, false);
			d.smoke_on = 0;
		}
		for (int k = 0; k < 2; k++) {
			gd::Obj p = k == 0 ? d.dust : d.mud;
			if (p) emit_set(p, false);
		}
		d.dust_on = d.mud_on = 0;
		ev.add({ (float)W_KILL, (float)i, (float)by, pop ? 1.0f : 0.0f, (float)why });
		if (std::getenv("STEEL_DEBUG_KILL")) {
			std::fprintf(stderr, "KILL tank=%d by=%d why=%d pens=%d hits=%d crew_left=%d he=%.0f\n", i, by, why, d.pens_taken, d.hits_taken, crew_left(d),
				by >= 0 ? c->td[by].he : -1.0f);
		}
	}

	void start_fire(int i, int by) {
		Core::TankDyn &d = c->td[i];
		if (d.fire > 0.0f) return;
		c->w.stat[6]++;
		d.fire = FIRE_TIME;
		d.fire_by = by;
	}

	// урон модулю (как Tank.hit_module): [было, стало]
	void hit_module(int i, int m, float amount, int &was, int &now) {
		Core::TankDyn &d = c->td[i];
		was = mstate(d.mod[m]);
		d.mod[m] = std::max(0.0f, d.mod[m] - amount);
		now = mstate(d.mod[m]);
		if (now == 0 && was > 0 && REPAIR_T[m] > 0.0f) d.fix[m] = REPAIR_T[m];
		if (now != was) recalc(d, c->ds[i].casemate);
	}

	// выстрел (как Battle.shoot)
	void shoot(int i) {
		Core::TankDyn &d = c->td[i];
		const Core::TankStatic &TS = c->ts[i];
		const Core::DmgStatic &DS = c->ds[i];
		float *t = T(i);
		V3 dir;
		V3 p = muzzle_at(c, i, dir);
		V3 u = v3norm({ -dir.z, 0.0f, dir.x });  // dir × UP
		V3 v = v3norm({ u.y * dir.z - u.z * dir.y, u.z * dir.x - u.x * dir.z, u.x * dir.y - u.y * dir.x });
		float spread = std::tan(t[P_DISP]);
		float gx = randn() * 0.45f, gy = randn() * 0.45f;
		float gl = std::sqrt(gx * gx + gy * gy);
		if (gl > 1.0f) {
			gx /= gl;
			gy /= gl;
		}
		gx *= spread;
		gy *= spread;
		dir = v3norm(v3add(dir, v3add(v3mul(u, gx), v3mul(v, gy))));
		// снаряд: у игрока — выбранный, у бота — по цели
		if (!d.player && d.am_n > 1) d.am_cur = ammo_bot_pick(c, i);
		Core::TankDyn::Ammo am;
		am.pen = DS.pen;
		am.dmg = d.dmg;
		am.he = d.he;
		if (d.am_n > 0) {
			Core::TankDyn::Ammo &cur = d.am[d.am_cur];
			am = cur;
			cur.used++;
			if (cur.left > 0 && --cur.left == 0) d.am_cur = 0;  // кончились — дальше основным
		}
		float sv = TS.shell_v * clampf(am.vel_k, 0.3f, 2.0f);
		V3 vel = v3mul(dir, sv);
		int slot = c->w.shell_slot;
		c->w.shell_slot = (slot + 1) % 64;
		if (c->shells.size() < 512) {
			Core::Shell s;
			s.pos = p;
			s.vel = vel;
			s.dmg = am.dmg;
			s.he = am.he;
			s.pen = am.pen;
			s.kind = am.kind;
			s.cal = DS.cal;
			s.dist = 0.0f;
			s.rico = 0;
			s.owner = i;
			s.slot = slot;
			c->shells.push_back(s);
		}
		d.rl_max = d.reload * d.reload_k * (d.player ? 1.0f : 1.15f);
		d.rl = d.rl_max;
		d.shots++;
		d.recoil = 1.0f;
		t[P_DISP] += 0.035f;
		// отдача раскачивает корпус: сильнее у крупного калибра и лёгкой машины
		float kick = DS.cal / 85.0f * 30.0f / std::max(TS.mass, 1.0f);
		float rel = ang_diff(t[P_TUR], t[P_HULL]);
		t[P_BODY_PV] += std::cos(rel) * 0.4f * kick;
		t[P_BODY_RV] += -std::sin(rel) * 0.4f * kick;
		t[P_VX] -= std::cos(t[P_TUR]) * kick * 2.0f;
		t[P_VY] -= std::sin(t[P_TUR]) * kick * 2.0f;
		// вспышку выстрела видят враги поблизости
		for (int o = 0; o < n(); o++) {
			if (c->td[o].alive && team(o) != team(i)) {
				float dx = T(o)[P_X] - t[P_X], dy = T(o)[P_Y] - t[P_Y];
				if (dx * dx + dy * dy < 800.0f * 800.0f) {
					d.lit = std::max(d.lit, 2.0f);
					break;
				}
			}
		}
		if (i == c->w.player) c->w.shots++;
		ev.add({ (float)W_SHOT, (float)i, (float)slot, p.x, p.y, p.z, dir.x, dir.y, dir.z, DS.cal, sv });
	}

	// маршрут боту (как Battle._set_route): в фоновый поток C++ или сразу (прогоны без кадров)
	void set_route(int i, V2 to, bool safe) {
		Core::TankDyn &d = c->td[i];
		Core::Bot &b = c->bots[i];
		if (d.path_wait) return;
		if (!b.path.empty() && dist2(d.path_to, to) < 50.0f && safe == d.path_safe && c->clock < d.path_t) return;
		float r = c->ts[i].W * 0.62f;
		if (c->w.sync_routes) {
			apply_route(i, c->nav_path(pos(i), to, safe, r), to, safe);
			return;
		}
		d.path_wait = true;
		{
			std::lock_guard<std::mutex> lk(c->nav_mx);
			c->nav_jobs.push_back({ i, pos(i), to, safe, r });
		}
		c->nav_cv.notify_one();
	}

	void apply_route(int i, std::vector<V2> path, V2 to, bool safe) {
		Core::TankDyn &d = c->td[i];
		Core::Bot &b = c->bots[i];
		b.path = std::move(path);
		b.pi = 0;
		d.path_to = to;
		d.path_safe = safe;
		d.path_t = c->clock + rnd(5.0f, 8.0f);
		d.path_wait = false;
	}

	void take_routes() {
#ifdef STEEL_NO_THREADS
		// веб без потоков: заявки считаются тут же, по несколько за шаг (A* ~0,2–0,5 мс)
		for (int k = 0; k < 3 && !c->nav_jobs.empty(); k++) {
			Core::RouteJob job = c->nav_jobs.front();
			c->nav_jobs.pop_front();
			c->nav_done.push_back({ job.bot, job.to, job.safe, c->nav_path(job.from, job.to, job.safe, job.r) });
		}
#endif
		std::vector<Core::RouteDone> done;
		{
			std::lock_guard<std::mutex> lk(c->nav_mx);
			done.swap(c->nav_done);
		}
		for (Core::RouteDone &r : done) {
			if (r.bot >= 0 && r.bot < n()) apply_route(r.bot, std::move(r.path), r.to, r.safe);
		}
	}

	// засвет (как Battle._update_spotting_native)
	void spotting() {
		const int K = 16;
		int N = n();
		std::vector<float> f((size_t)N * K, 0.0f);
		for (int i = 0; i < N; i++) {
			float *k = &f[(size_t)i * K];
			const Core::TankDyn &d = c->td[i];
			k[0] = (float)team(i);
			k[1] = d.alive ? 1.0f : 0.0f;
			if (!d.alive) continue;
			V3 tp = top(i), cen = center(i);
			k[2] = d.lit;
			k[3] = T(i)[P_X];
			k[4] = T(i)[P_Y];
			k[5] = tp.x;
			k[6] = tp.y + 2.0f;
			k[7] = tp.z;
			k[8] = tp.x;
			k[9] = tp.y;
			k[10] = tp.z;
			k[11] = cen.x;
			k[12] = cen.y;
			k[13] = cen.z;
			k[14] = d.spot * d.spot_k;
			k[15] = (c->in_bush(T(i)[P_X], T(i)[P_Y]) || c->trees_near(T(i)[P_X], T(i)[P_Y], 26.0f) >= 2) ? 1.0f : 0.0f;
		}
		std::vector<int32_t> res = spot_run(c, f, 110.0f, c->clock);
		Core::World &w = c->w;
		for (int e = 0; e < N; e++) {
			if (!c->td[e].alive) continue;
			int s = res[(size_t)e * 2];
			if (team(e) == 0) continue;
			if (s >= 0 && w.spotter[e] < 0) {
				w.spotter[e] = s;
				if (s == w.player) w.spotted_n++;
			}
			bool seen = T(e)[P_VIS0] != 0.0f;
			if (seen && !w.reported[e] && c->clock > 3.0f) {
				w.reported[e] = 1;
				int wt = w.watch >= 0 ? w.watch : w.player;
				float d = ang_diff(std::atan2(T(e)[P_Y] - T(wt)[P_Y], T(e)[P_X] - T(wt)[P_X]), T(wt)[P_HULL]);
				int h = ((int)std::lround(d / (PI_F / 6.0f)) % 12 + 12) % 12;
				ev.add({ (float)W_SPOTTED, (float)e, (float)(h == 0 ? 12 : h) });
			}
		}
	}

	void finish(int result, int reason) {
		Core::World &w = c->w;
		if (w.over) return;
		w.over = true;
		w.result = result;
		w.reason = reason;
		ev.add({ (float)W_FINISH, (float)result, (float)reason });
	}

	int alive_count(int tm) {
		int k = 0;
		for (int i = 0; i < n(); i++) k += (c->td[i].alive && team(i) == tm) ? 1 : 0;
		return k;
	}

	// базы и очки (как Battle._zones_update)
	void zones_update() {
		Core::World &w = c->w;
		for (size_t zi = 0; zi < c->zones.size(); zi++) {
			Core::Zone &z = c->zones[zi];
			z.n[0] = z.n[1] = 0;
			for (int i = 0; i < n(); i++) {
				if (c->td[i].alive && in_zone(i, z)) z.n[team(i)]++;
			}
			for (int side = 0; side < 2; side++) {
				int other = 1 - side;
				if (z.side != side && z.n[side] > 0 && z.n[other] == 0 && ((c->cap_mask >> side) & 1)) {
					z.prog[side] = std::min(100.0f, z.prog[side] + dt * w.cap_rate * std::min(3, z.n[side]));
					if (side == 0 && w.player >= 0 && c->td[w.player].alive && in_zone(w.player, z)) w.cap_pts += dt * w.cap_rate;
				} else if (z.n[side] == 0) {
					z.prog[side] = std::max(0.0f, z.prog[side] - dt * 3.0f);
				}
				if (z.prog[side] >= 100.0f) {
					if (c->mode == 2) {
						z.side = side;
						z.prog[0] = z.prog[1] = 0.0f;
						ev.add({ (float)W_ZONE, (float)zi, (float)side });
					} else if (!w.over) {
						if (c->mode == 1) {
							finish(side == 0 ? 1 : 2, side == 0 ? 3 : 4);
						} else {
							finish(side == 0 ? 1 : 2, side == 0 ? 5 : 6);
						}
					}
				}
			}
		}
		if (c->mode == 2) {
			for (Core::Zone &z : c->zones) {
				if (z.side >= 0) w.score[z.side] += dt * 2.0f;
			}
			if (!w.over) {
				if (w.score[0] >= w.sup_goal) {
					finish(1, 7);
				} else if (w.score[1] >= w.sup_goal) {
					finish(2, 8);
				}
			}
		}
	}

	// попадания снарядов: разбор в resolve_hit, состояние меняется здесь, события — дальше в GDScript
	void shells() {
		Core::World &w = c->w;
		V3 cam = cam_pos;
		EvOut se;
		shells_run(c, dt, cam, w.player, se);
		for (size_t q = 0; q + EV_N <= se.v.size(); q += EV_N) {
			float *e = &se.v[q];
			int kind = (int)e[0];
			if (kind == EV_HIT) {
				int k = (int)e[1], i = (int)e[2];
				if (k < 0 || (size_t)k >= c->shells.size() || i < 0 || i >= n()) continue;
				Core::TankDyn &d = c->td[i];
				float st[13];
				st[0] = d.alive ? 1.0f : 0.0f;
				st[1] = d.fire > 0.0f ? 1.0f : 0.0f;
				for (int m = 0; m < 6; m++) st[2 + m] = d.mod[m];
				for (int m = 0; m < CREW_N; m++) st[8 + m] = !d.crew_has[m] ? -1.0f : (d.crew[m] ? d.crew_hp[m] : 0.0f);
				EvOut he;
				resolve_hit(c, c->shells[k], st, he);
				c->shells[k].hit_tank = -1;
				for (size_t h = 0; h + EV_N <= he.v.size(); h += EV_N) apply_hit(&he.v[h]);
				continue;
			}
			if (kind == EV_MISS) w.stat[3]++;
			forward(e);
		}
		inf_shell_blasts();
	}

	V3 cam_pos = { 0, 0, 0 };

#include "infantry.inc"

	void forward(const float *e) {
		size_t k = ev.v.size();
		ev.v.resize(k + EV_N);
		memcpy(&ev.v[k], e, EV_N * sizeof(float));
	}

	void apply_hit(float *e) {
		Core::World &w = c->w;
		int kind = (int)e[0];
		switch (kind) {
			case EV_KICK: {
				int i = (int)e[1];
				T(i)[P_BODY_PV] += e[2];
				T(i)[P_BODY_RV] += e[3];
				return;  // GDScript толчок не нужен
			}
			case EV_RICO: {
				int i = (int)e[2];
				c->td[i].hits_taken++;
				w.stat[2]++;
				if (i == w.player) w.blocked += e[11];
				break;
			}
			case EV_NOPEN: {
				int i = (int)e[2], by = (int)e[3];
				c->td[i].hits_taken++;
				w.stat[1]++;
				if (i == w.player) w.blocked += e[11];
				if (team(by) == 0 && team(i) == 1) c->td[i].lit = std::max(c->td[i].lit, 2.0f);
				T(i)[P_HIT_T] = c->clock;
				break;
			}
			case EV_PEN: {
				int i = (int)e[2], by = (int)e[3];
				c->td[i].hits_taken++;
				c->td[i].pens_taken++;
				w.stat[0]++;
				if (by == w.player) w.hits++;
				break;
			}
			case EV_TRACK: {
				int i = (int)e[1];
				Core::TankDyn &d = c->td[i];
				e[6] = d.track_broken <= 0.0f ? 1.0f : 0.0f;  // гусеница слетела только что
				if (d.track_broken <= 0.0f) w.stat[5]++;
				d.track_broken = TRACK_REPAIR;
				T(i)[P_VX] *= 0.3f;
				T(i)[P_VY] *= 0.3f;
				break;
			}
			case EV_MODULE: {
				int i = (int)e[1], m = (int)e[3];
				int was, now;
				hit_module(i, m, e[4], was, now);
				e[5] = (float)was;
				e[6] = (float)now;
				if (now != was && e[7] == 0.0f && m == MOD_ENGINE && now == 0) {
					T(i)[P_VX] *= 0.4f;
					T(i)[P_VY] *= 0.4f;
				}
				forward(e);
				update(i, (int)e[2], 0);
				return;
			}
			case EV_CREW: {
				// ранение: e[4] — урон; в e[5] для GDScript — выбыл ли (1) или ранен (0)
				int i = (int)e[1], by = (int)e[2], k = (int)e[3];
				Core::TankDyn &d = c->td[i];
				if (k < 0 || k >= CREW_N || !d.crew[k] || !d.alive) return;
				crew_hit(i, k, e[4], by);
				e[5] = d.crew[k] ? 0.0f : 1.0f;
				forward(e);
				update(i, by, 0);
				return;
			}
			case EV_FIRE:
				start_fire((int)e[1], (int)e[2]);
				break;
			case EV_PEN_DMG: {
				// прочности нет: пробитие уничтожает танк только подрывом боеукладки (или экипаж уже выбыл)
				int i = (int)e[1], by = (int)e[2];
				Core::TankDyn &d = c->td[i];
				bool was_alive = d.alive;
				forward(e);
				if (e[4] != 0.0f && d.alive) {
					w.stat[7]++;
					destroy(i, by, 2);
				} else {
					update(i, by, 0);
				}
				(void)was_alive;
				return;
			}
			default:
				break;
		}
		forward(e);
	}

	// узлы танка по позе (как Tank.sync_node); у неподвижного остова — только если он сдвинулся
	void sync(int i) {
		Core::TankDyn &d = c->td[i];
		if (!api.ok || !d.root) return;
		float *t = T(i);
		if (!d.alive && !d.popping) {
			float key[4] = { t[P_X], t[P_Y], t[P_PITCH] + t[P_ROLL] * 3.0f + t[P_BODY_P] * 5.0f + t[P_BODY_R] * 7.0f, t[P_GROUND] };
			bool same = true;
			for (int k = 0; k < 4; k++) same = same && std::fabs(key[k] - d.key[k]) < 1e-4f;
			if (same) return;
			memcpy(d.key, key, sizeof(key));
		}
		gd::call_v3(api.set_position, d.root, { t[P_X], t[P_GROUND], t[P_Y] });
		float b[9];
		basis9(M3::rot(1, -t[P_HULL]) * M3::rot(2, t[P_PITCH] + t[P_BODY_P]) * M3::rot(0, t[P_ROLL] + t[P_BODY_R]), b);
		gd::call_basis(api.set_basis, d.hull_n, b);
		if (!d.popping) {
			basis9(M3::rot(1, -(t[P_TUR] - t[P_HULL])), b);
			gd::call_basis(api.set_basis, d.tur_n, b);
		}
		const V3 &gp = c->ts[i].gun_pos0;
		basis9(M3::rot(2, t[P_GUN_PITCH]), b);
		gd::call_xf(api.set_transform, d.gun_n, b, { gp.x - d.recoil * 0.35f * c->upm, gp.y, gp.z });
		// высота грунта для пыли на корпусе: три материала — три перезаливки буфера; шлём при сдвиге больше 0,8 (~10 см)
		if (std::fabs(t[P_GROUND] - d.gy_set) > 0.8f) {
			d.gy_set = t[P_GROUND];
			for (gd::Obj m : d.paint) gd::call_param(api.set_param, m, api.ground_y, t[P_GROUND]);
		}
		if (!d.alive) travel(i, t[P_TRAVEL_L], t[P_TRAVEL_R]);
	}

	void travel(int i, float l, float r) {
		Core::TankDyn &d = c->td[i];
		gd::call_param(api.set_param, d.paint[0], api.travel_l, l);
		gd::call_param(api.set_param, d.paint[0], api.travel_r, r);
		float link = 0.24f * c->upm;
		gd::call_param(api.set_param, d.track_mat, api.off_l, -std::fmod(l / link, 1.0f));
		gd::call_param(api.set_param, d.track_mat, api.off_r, -std::fmod(r / link, 1.0f));
	}

	void fx_on(gd::Obj p, int8_t &state, bool on, V3 at) {
		if (!p) return;
		if (on) gd::call_v3(api.set_global_position, p, at);
		if ((state != 0) != on) {
			emit_set(p, on);
			state = on ? 1 : 0;
		}
	}

	// шлейф за кормой и выхлоп (как Battle._trail и выхлоп в _phys_native)
	void trail(int i, int watch) {
		Core::TankDyn &d = c->td[i];
		float *t = T(i);
		float fx = std::cos(t[P_HULL]), fy = std::sin(t[P_HULL]);
		bool vis = team(i) == 0 || t[P_VIS0] != 0.0f;
		float dwx = t[P_X] - T(watch)[P_X], dwy = t[P_Y] - T(watch)[P_Y];
		float dw = std::sqrt(dwx * dwx + dwy * dwy);
		if (d.dust) {
			bool on = (std::fabs(t[P_SP]) > 10.0f || t[P_SLIP] > 0.3f) && vis && dw < 1100.0f;
			if (on || d.dust_on || d.mud_on) {
				float sg = signf(t[P_SP] + 0.01f);
				V3 at = { t[P_X] - fx * c->ts[i].L * 0.45f * sg, t[P_GROUND] + 1.2f, t[P_Y] - fy * c->ts[i].L * 0.45f * sg };
				bool muddy = d.mud && t[P_SOFT] > 0.42f;
				fx_on(d.dust, d.dust_on, on && !muddy, at);
				if (d.mud) {
					fx_on(d.mud, d.mud_on, on && muddy, at);
					float b[9];
					basis9(up_to({ -fx * sg, 1.4f, -fy * sg }), b);
					gd::call_basis(api.set_basis, d.mud, b);
				}
			}
		}
		// выхлоп при резком разгоне
		if (t[P_THROTTLE] > 0.6f && t[P_SP] < t[P_VMAX] * 0.5f && randf() < dt * 6.0f && vis && dw < 700.0f) {
			float ex = t[P_X] - fx * c->ts[i].L * 0.45f, ey = t[P_Y] - fy * c->ts[i].L * 0.45f;
			ev.add({ (float)W_EXHAUST, ex, t[P_GROUND] + c->ts[i].hh + 1.0f, ey, fx, fy });
		}
	}
};

} // namespace

// ---------- поток маршрутов ----------

void Core::nav_start() {
#ifdef STEEL_NO_THREADS
	return;  // заявки разбирает take_routes
#endif
	if (nav_thread.joinable()) return;
	nav_quit = false;
	nav_thread = std::thread([this]() {
		for (;;) {
			RouteJob job;
			{
				std::unique_lock<std::mutex> lk(nav_mx);
				nav_cv.wait(lk, [this] { return nav_quit || !nav_jobs.empty(); });
				if (nav_quit) return;
				job = nav_jobs.front();
				nav_jobs.pop_front();
			}
			std::vector<V2> p = nav_path(job.from, job.to, job.safe, job.r);
			std::lock_guard<std::mutex> lk(nav_mx);
			nav_done.push_back({ job.bot, job.to, job.safe, std::move(p) });
		}
	});
}

void Core::nav_stop() {
	if (!nav_thread.joinable()) return;
	{
		std::lock_guard<std::mutex> lk(nav_mx);
		nav_quit = true;
	}
	nav_cv.notify_all();
	nav_thread.join();
}

// ---------- методы для GDScript ----------

// Начало боя: (пакет физики PHYS×n, на танк 11 чисел [обзор, перезарядка, урон, скорость, скорость башни,
// ширина, прочность, игрок, есть ремкомплект, аптечка, огнетушитель], [скорость захвата, очки победы,
// перезарядка снаряжения ×3], MultiMesh следов гусениц, сколько в нём следов)
METHOD(world_init) {
	SELF;
	if (!need(a, 5, e)) return;
	std::vector<float> P = f32(a, 0), st = f32(a, 1), k = f32(a, 2);
	int n = (int)(P.size() / PHYS);
	if (n <= 0 || (int)self->ts.size() < n || (int)self->ds.size() < n || (int)self->ai.size() < n || (int)st.size() < n * 13) {
		ret_bool(r, false);
		return;
	}
	api.load();
	self->inf.clear();
	self->isq.clear();
	self->mg_t.clear();
	self->inf_kills = 0;
	self->snap = P;
	self->td.assign(n, Core::TankDyn());
	for (int i = 0; i < n; i++) {
		Core::TankDyn &d = self->td[i];
		const float *q = &st[(size_t)i * 13];
		d.spot = q[0];
		d.reload = q[1];
		d.dmg = q[2];
		d.speed = q[3];
		d.tspd = q[4];
		d.W = q[5];
		d.max_hp = d.hp = q[6];
		d.player = q[7] != 0.0f;
		for (int c = 0; c < 3; c++) d.cons_has[c] = q[8 + c] != 0.0f;
		// экипаж: 5 — все места, 4 — без радиста, 3 — командир, наводчик, мехвод, 2 — командир (он же наводчик) и мехвод
		int nc = (int)clampf(q[11], 2.0f, 5.0f);
		const bool has[4][5] = { { 1, 0, 0, 1, 0 }, { 1, 1, 0, 1, 0 }, { 1, 1, 1, 1, 0 }, { 1, 1, 1, 1, 1 } };
		for (int k = 0; k < CREW_N; k++) {
			d.crew_has[k] = has[nc - 2][k];
			d.crew[k] = d.crew_has[k];
			d.crew_hp[k] = d.crew_has[k] ? 100.0f : 0.0f;
			d.swap_t[k] = -1.0f;
		}
		d.he = std::max(0.0f, q[12]);
		d.alive = P[(size_t)i * PHYS + P_ALIVE] != 0.0f;
		d.rl = P[(size_t)i * PHYS + P_RL];
		d.rl_max = d.reload;
		recalc(d, self->ds[i].casemate);
		if (d.player) self->w.player = i;
	}
	Core::World &w = self->w;
	w.on = true;
	w.over = false;
	w.watch = w.player;
	if (k.size() >= 5) {
		w.cap_rate = k[0];
		w.sup_goal = k[1];
		for (int c = 0; c < 3; c++) w.cons_cd[c] = k[2 + c];
	}
	w.trk_mm = gd::object(a, 3);
	w.trk_n = std::max(1, (int)a.integer(4));
	w.spotter.assign(n, -1);
	w.reported.assign(n, 0);
	self->nav_start();
	ret_bool(r, api.ok);
}

// Узлы танка: (номер, корень, корпус, башня, орудие, материалы ×3, материал гусениц, пыль, грязь, дым,
// звук мотора, гусениц, башни) — любой может быть null.
METHOD(world_nodes) {
	SELF;
	if (!need(a, 15, e)) return;
	int i = (int)a.integer(0);
	if (i < 0 || i >= (int)self->td.size()) return;
	Core::TankDyn &d = self->td[i];
	d.root = gd::object(a, 1);
	d.hull_n = gd::object(a, 2);
	d.tur_n = gd::object(a, 3);
	d.gun_n = gd::object(a, 4);
	for (int k = 0; k < 3; k++) d.paint[k] = gd::object(a, 5 + k);
	d.track_mat = gd::object(a, 8);
	d.dust = gd::object(a, 9);
	d.mud = gd::object(a, 10);
	d.smoke = gd::object(a, 11);
	for (int k = 0; k < 3; k++) d.snd[k] = gd::object(a, 12 + k);
}

// Шаг боя: (dt, ввод IN чисел) → [события, вид VIEW×n, игрок DET, наблюдаемый DET, итог OUT + 5×зон]
METHOD(world_step) {
	SELF;
	if (!need(a, 2, e)) return;
	Core::World &w = self->w;
	float dt = (float)a.num(0);
	std::vector<float> in = f32(a, 1);
	in.resize(IN, 0.0f);
	Step S{ self, dt };
	int n = (int)self->td.size();
	if (!w.on || n == 0 || !(dt > 0.0f && dt < 1.0f)) {
		ret_f32(r, nullptr, 0);
		return;
	}
	self->clock += dt;
	int pl = w.player;
	bool autopilot = in[10] != 0.0f;
	w.watch = (int)clampf(in[14], 0.0f, (float)(n - 1));
	w.sync_routes = in[15] != 0.0f;
	w.speed = (int)in[16];
	S.cam_pos = { in[2], in[3], in[4] };
	S.take_routes();
	for (int i = 0; i < n; i++) {
		Core::TankDyn &d = self->td[i];
		d.travel_prev[0] = S.T(i)[P_TRAVEL_L];
		d.travel_prev[1] = S.T(i)[P_TRAVEL_R];
	}
	// засвет — 4 раза в секунду
	w.spot_t -= dt;
	if (w.spot_t <= 0.0f) {
		S.spotting();
		w.spot_t = 0.25f;
	}
	w.squad_t -= dt;
	if (w.squad_t <= 0.0f) {
		self->squads_update(autopilot);
		w.squad_t = 1.0f;
	}
	float lead[4] = { 0, 0, 0, 0 };
	// танки: таймеры, пожар, ремонт, управление
	for (int i = 0; i < n; i++) {
		Core::TankDyn &d = self->td[i];
		float *t = S.T(i);
		t[P_CMD] = 0.0f;
		t[P_AIM] = 0.0f;
		t[P_DISP_CMD] = 0.0f;
		t[P_BOT] = 0.0f;
		if (!d.alive) continue;
		d.rl = std::max(0.0f, d.rl - dt);
		d.lit = std::max(0.0f, d.lit - dt);
		d.recoil = std::max(0.0f, d.recoil - dt * 3.0f);
		d.track_broken = std::max(0.0f, d.track_broken - dt);
		for (int k = 0; k < 3; k++) d.cons_cd[k] = std::max(0.0f, d.cons_cd[k] - dt);
		// полевой ремонт уничтоженных модулей
		bool fixed = false;
		for (int m = 0; m < 6; m++) {
			if (d.fix[m] < 0.0f) continue;
			d.fix[m] -= dt;
			if (d.fix[m] <= 0.0f) {
				d.fix[m] = -1.0f;
				d.mod[m] = 30.0f;
				fixed = true;
				S.ev.add({ (float)W_REPAIRED, (float)i, (float)m });
			}
		}
		if (fixed) recalc(d, self->ds[i].casemate);
		// подмена членов экипажа
		for (int k = 0; k < CREW_N; k++) {
			if (d.swap_t[k] < 0.0f) continue;
			d.swap_t[k] -= dt;
			if (d.swap_t[k] <= 0.0f) {
				d.swap_t[k] = -1.0f;
				d.crew[k] = true;
				d.crew_hp[k] = std::max(1.0f, d.swap_hp[k]);
				recalc(d, self->ds[i].casemate);
				S.ev.add({ (float)W_SWAP, (float)i, (float)k });
			}
		}
		// пожар жжёт экипаж и двигатель; не потушен — экипаж сгорит
		if (d.fire > 0.0f) {
			d.fire -= dt;
			int by = d.fire_by >= 0 ? d.fire_by : i;
			for (int k = 0; k < CREW_N; k++) {
				if (d.crew[k]) {
					d.crew_hp[k] -= BURN_CREW * dt * S.rnd(0.6f, 1.4f);
					if (d.crew_hp[k] <= 0.0f) S.crew_hit(i, k, 1.0f, by);
				}
			}
			d.mod[MOD_ENGINE] = std::max(0.0f, d.mod[MOD_ENGINE] - 1.5f * dt);
			S.update(i, by, 1, 3);
			if (d.fire <= 0.0f && d.alive) S.ev.add({ (float)W_FIRE_OUT, (float)i });
			if (!d.alive) continue;
		}
		if (w.over) {
			t[P_CMD] = 1.0f;
			t[P_THR] = 0.0f;
			t[P_STEER] = 0.0f;
			continue;
		}
		if (i == pl && !autopilot) {
			// игрок: ход с мёртвой зоной, САУ доворачивает корпус за прицелом
			float sy = in[1], sx = in[0];
			float thr = std::fabs(sy) > 0.2f ? -sy : 0.0f;
			float steer = std::fabs(sx) > 0.15f ? sx : 0.0f;
			float aim[7];
			V3 o = { in[2], in[3], in[4] }, dir = { in[5], in[6], in[7] };
			V3 far = v3add(o, v3mul(dir, 1800.0f));
			V3 gdir;
			V3 mz = muzzle_at(self, i, gdir);
			float avk = self->td[i].am_n > 0 ? self->td[i].am[self->td[i].am_cur].vel_k : 1.0f;
			aim_run(self, o, far, mz, v3mul(gdir, self->ts[i].shell_v * clampf(avk, 0.3f, 2.0f)), i, aim);
			if (self->ds[i].casemate && steer == 0.0f) {
				float off = ang_diff(std::atan2(aim[2] - t[P_Y], aim[0] - t[P_X]), t[P_HULL]);
				if (std::fabs(off) > self->ts[i].trav * 0.9f) {
					bool rev = t[P_SP] < -1.0f || thr < -0.05f;
					steer = clampf(off / 0.25f, -1.0f, 1.0f) * (rev ? -1.0f : 1.0f);
				}
			}
			t[P_CMD] = 1.0f;
			t[P_THR] = thr;
			t[P_STEER] = steer;
			t[P_AIM] = 1.0f;
			t[P_AX] = aim[0];
			t[P_AY] = aim[1];
			t[P_AZ] = aim[2];
			t[P_DISP_CMD] = 1.0f;
			for (int k = 0; k < 3; k++) {
				w.aim_point[k] = aim[k];
				w.gun_point[k] = aim[3 + k];
			}
			w.pen_hint = (int)aim[6];
			// автоприцел: ближайший видимый враг в конусе 0,3 рад около взгляда, упреждение
			if (in[11] != 0.0f && in[12] == 0.0f) {
				int best = -1;
				float bd = 900.0f;
				for (int o2 = 0; o2 < n; o2++) {
					if (!self->td[o2].alive || S.team(o2) == S.team(i) || S.T(o2)[S.team(i) == 0 ? P_VIS0 : P_VIS1] == 0.0f) continue;
					float dx = S.T(o2)[P_X] - t[P_X], dy = S.T(o2)[P_Y] - t[P_Y];
					float dd = std::sqrt(dx * dx + dy * dy);
					if (std::fabs(ang_diff(std::atan2(dy, dx), in[13])) > 0.3f) continue;
					if (dd < bd) {
						bd = dd;
						best = o2;
					}
				}
				if (best >= 0 && self->los(S.top(i), S.center(best))) {
					float *g = S.T(best);
					float tf = bd / std::max(self->ts[i].shell_v, 1.0f) * 0.9f;
					lead[0] = g[P_X] + g[P_VX] * tf;
					lead[1] = g[P_GROUND] + self->ts[best].hh * 0.7f;
					lead[2] = g[P_Y] + g[P_VY] * tf;
					lead[3] = 1.0f;
				}
			}
			// огонь и снаряжение
			if (in[8] != 0.0f && d.rl <= 0.0f && mstate(d.mod[MOD_GUN]) > 0 && d.gun_crew) S.shoot(i);
			if (in[9] >= 0.0f) S.use_cons(i, (int)in[9]);
		} else {
			// бот (и игрок на автопилоте): снаряжение, решения, ход и огонь — в физике
			S.bot_cons(i);
			d.think_t -= dt;
			if (d.think_t <= 0.0f) {
				int en = 1 - S.team(i);
				float dx = t[P_X] - S.T(w.watch)[P_X], dy = t[P_Y] - S.T(w.watch)[P_Y];
				bool calm = self->ai[i].tg < 0 && t[en == 0 ? P_VIS0 : P_VIS1] == 0.0f && dx * dx + dy * dy > 1200.0f * 1200.0f;
				d.think_t = calm ? S.rnd(0.5f, 0.6f) : S.rnd(0.18f, 0.24f);
				V2 to = { 0, 0 };
				bool safe = false;
				if (self->think(i, to, safe)) S.set_route(i, to, safe);
			}
			t[P_BOT] = 1.0f;
			int tg = self->ai[i].tg;
			t[P_RL] = d.rl;
			t[P_CAN_FIRE] = tg >= 0 && tg < n && self->td[tg].alive && mstate(d.mod[MOD_GUN]) > 0 && d.gun_crew ? 1.0f : 0.0f;
		}
		// дым подбитого — только у видимых и не слишком далёких
		float dx = t[P_X] - S.T(w.watch)[P_X], dy = t[P_Y] - S.T(w.watch)[P_Y];
		bool smoke = d.hp < d.max_hp * 0.35f && (S.team(i) == 0 || t[P_VIS0] != 0.0f) && dx * dx + dy * dy < 1400.0f * 1400.0f;
		if (d.smoke && (d.smoke_on != 0) != smoke && api.ok) {
			emit_set(d.smoke, smoke);
			d.smoke_on = smoke ? 1 : 0;
		}
	}
	// состояние для физики
	for (int i = 0; i < n; i++) {
		Core::TankDyn &d = self->td[i];
		float *t = S.T(i);
		t[P_SPEED_K] = d.speed_k;
		t[P_TURN_K] = d.turn_k;
		t[P_ACCEL_K] = d.accel_k;
		t[P_TRACK_BROKEN] = d.track_broken;
		t[P_IMMOBILE] = d.immobile ? 1.0f : 0.0f;
		t[P_ALIVE] = d.alive ? 1.0f : 0.0f;
		t[P_TSPD_K] = d.tspd_k;
		t[P_DISP_K] = d.disp_k;
		t[P_AIM_K] = d.aim_k;
		t[P_HP] = d.hp / std::max(d.max_hp, 1.0f);
		float dx = t[P_X] - S.T(w.watch)[P_X], dy = t[P_Y] - S.T(w.watch)[P_Y];
		t[P_SHOWN] = (S.team(i) == 0 || t[P_VIS0] != 0.0f) && dx * dx + dy * dy < 750.0f * 750.0f ? 1.0f : 0.0f;
		t[P_TG] = (float)self->ai[i].tg;
		if (w.over) t[P_BOT] = 0.0f;
	}
	// физика всех танков (боты решают ход и огонь внутри)
	std::vector<float> pev, marks;
	physics_run(self, dt, self->clock, self->snap, pev, marks);
	for (int i = 0; i < n; i++) {
		float *t = S.T(i);
		if (t[P_BOT] != 0.0f) {
			if (t[P_STUCK] != 0.0f) self->td[i].path_t = 0.0f;  // застрял: новый маршрут
			if (t[P_FIRE] != 0.0f && self->td[i].alive && self->td[i].gun_crew) S.shoot(i);
		}
	}
	for (size_t q = 0; q + 4 < pev.size(); q += 5) {
		int kind = (int)pev[q], i = (int)pev[q + 1], j = (int)pev[q + 2];
		if (kind == 6) {
			V3 oc = self->obj_center(j);
			S.ev.add({ (float)EV_DESTROY, (float)j, oc.x, oc.y, oc.z });
		} else if (kind == 1) {
			S.ev.add({ (float)W_WALL, (float)i, pev[q + 3] });
		} else if (kind == 2) {
			S.ev.add({ (float)W_TREE, (float)i, (float)j, pev[q + 3], pev[q + 4] });
		} else if (kind == 3 && j >= 0 && j < n) {
			// таран: урон обоим по массам
			float closing = pev[q + 3];
			float ma = self->ts[i].mass, mb = self->ts[j].mass;
			w.stat[4]++;
			float en = closing * closing * 0.006f;
			S.ram_hit(j, std::round(en * ma / (ma + mb) * 2.0f), i);
			S.ram_hit(i, std::round(en * mb / (ma + mb) * 0.8f), j);
			S.ev.add({ (float)W_RAM, (float)i, (float)j });
		}
	}
	// следы гусениц — сразу в MultiMesh
	if (api.ok && w.trk_mm) {
		for (size_t q = 0; q + 15 < marks.size(); q += 16) {
			const float *m = &marks[q];
			float b[9] = { m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8] };
			gd::call_int_xf(api.mm_xf, w.trk_mm, w.trk_i, b, { m[9], m[10], m[11] });
			gd::call_int_color(api.mm_color, w.trk_mm, w.trk_i, &m[12]);
			w.trk_i = (w.trk_i + 1) % w.trk_n;
		}
	}
	for (int i = 0; i < n; i++) {
		if (self->td[i].alive && S.T(i)[P_CMD] != 0.0f) S.trail(i, w.watch);
		S.sync(i);
	}
	// прицел игрока после хода: упёрлось ли орудие
	if (pl >= 0 && self->td[pl].alive) {
		float *t = S.T(pl);
		const Core::TankStatic &T = self->ts[pl];
		w.gun_limited = std::fabs(t[P_GUN_TARGET] - T.elev0) < 0.0005f || std::fabs(t[P_GUN_TARGET] - T.elev1) < 0.0005f;
		if (self->ds[pl].casemate) {
			float off = ang_diff(std::atan2(w.aim_point[2] - t[P_Y], w.aim_point[0] - t[P_X]), t[P_HULL]);
			w.gun_limited = w.gun_limited || std::fabs(off) > T.trav + 0.01f;
		}
	}
	// пехота, затем снаряды
	S.inf_step();
	S.shells();
	S.zones_update();
	if (!w.over) {
		int al = S.alive_count(0), en = S.alive_count(1);
		if (en == 0) {
			S.finish(1, 0);
		} else if (al == 0) {
			S.finish(2, 1);
		} else if (self->clock >= self->time_limit) {
			if (self->timeout_result > 0) {
				// миссия: по времени — оборона выстояла (9) или атака не успела (10)
				S.finish(self->timeout_result, self->timeout_result == 1 ? 9 : (self->timeout_result == 2 ? 10 : 2));
			} else if (self->mode == 2) {
				S.finish(w.score[0] > w.score[1] ? 1 : (w.score[0] < w.score[1] ? 2 : 3), 2);
			} else {
				S.finish(3, 2);
			}
		}
	}
	// ответ
	std::vector<float> view((size_t)n * VIEW);
	for (int i = 0; i < n; i++) {
		float *v = &view[(size_t)i * VIEW], *t = S.T(i);
		v[0] = t[P_X];
		v[1] = t[P_Y];
		v[2] = t[P_GROUND];
		v[3] = self->td[i].alive ? 1.0f : 0.0f;
		v[4] = t[P_VIS0];
		v[5] = t[P_VIS1];
		v[6] = self->td[i].hp;
		v[7] = t[P_HULL];
		v[8] = t[P_TUR];
	}
	auto detail = [&](int i, std::vector<float> &o) {
		o.assign(DET, 0.0f);
		if (i < 0 || i >= n) return;
		const Core::TankDyn &d = self->td[i];
		float *t = S.T(i);
		float f[DET] = { d.rl, d.rl_max, t[P_DISP], d.track_broken, d.fire, t[P_SP], t[P_GUN_PITCH], t[P_GUN_TARGET], t[P_PITCH], t[P_ROLL],
			t[P_TUR_RATE], d.immobile ? 1.0f : 0.0f };
		for (int m = 0; m < 6; m++) {
			f[12 + m] = d.mod[m];
			f[18 + m] = d.fix[m];
		}
		for (int k = 0; k < 4; k++) f[24 + k] = d.crew[k] ? 1.0f : 0.0f;
		// экипаж подробно: здоровье (−1 — места нет, −2 — пересаживается), есть кому стрелять и вести
		for (int k = 0; k < CREW_N; k++) f[43 + k] = !d.crew_has[k] ? -1.0f : (d.swap_t[k] >= 0.0f ? -2.0f : (d.crew[k] ? d.crew_hp[k] : 0.0f));
		f[48] = d.gun_crew ? 1.0f : 0.0f;
		f[49] = d.drive_crew ? 1.0f : 0.0f;
		for (int k = 0; k < 3; k++) {
			f[28 + k] = d.cons_cd[k];
			f[31 + k] = d.cons_used[k] ? 1.0f : 0.0f;
		}
		f[34] = t[P_THROTTLE];
		f[35] = t[P_YAW];
		f[36] = t[P_VX];
		f[37] = t[P_VY];
		f[38] = d.lit;
		f[39] = d.recoil;
		f[40] = (float)d.hits_taken;
		f[41] = (float)d.shots;
		f[42] = d.dmg_dealt;
		o.assign(f, f + DET);
	};
	std::vector<float> dp, dw;
	detail(pl, dp);
	detail(w.watch, dw);
	std::vector<float> out(OUT + self->zones.size() * 5, 0.0f);
	for (int k = 0; k < 3; k++) {
		out[k] = w.gun_point[k];
		out[5 + k] = w.aim_point[k];
		out[8 + k] = lead[k];
	}
	out[3] = (float)w.pen_hint;
	out[4] = w.gun_limited ? 1.0f : 0.0f;
	out[11] = lead[3];
	out[12] = w.score[0];
	out[13] = w.score[1];
	out[14] = w.dmg_done;
	out[15] = (float)w.kills;
	out[16] = (float)w.hits;
	out[17] = (float)w.shots;
	out[18] = w.spot_dmg;
	out[19] = w.blocked;
	out[20] = w.cap_pts;
	out[21] = w.def_pts;
	out[22] = (float)w.spotted_n;
	for (int k = 0; k < 8; k++) out[23 + k] = (float)w.stat[k];
	out[31] = w.over ? 1.0f : 0.0f;
	out[32] = (float)w.result;
	out[33] = (float)w.reason;
	for (size_t z = 0; z < self->zones.size(); z++) {
		const Core::Zone &Z = self->zones[z];
		float *o = &out[OUT + z * 5];
		o[0] = (float)Z.side;
		o[1] = Z.prog[0];
		o[2] = Z.prog[1];
		o[3] = (float)Z.n[0];
		o[4] = (float)Z.n[1];
	}
	ArrayOut res(5);
	ret_f32(res.at(0), S.ev.v.data(), (int64_t)S.ev.v.size());
	ret_f32(res.at(1), view.data(), (int64_t)view.size());
	ret_f32(res.at(2), dp.data(), (int64_t)dp.size());
	ret_f32(res.at(3), dw.data(), (int64_t)dw.size());
	ret_f32(res.at(4), out.data(), (int64_t)out.size());
	res.to_variant(r);
}

// Каждый кадр: видимость танков, ход гусениц между шагами, звук моторов (как часть Battle._sync).
// (доля шага, камера xyz, наблюдаемый в прицеле (-1 — нет), пауза)
METHOD(world_frame) {
	SELF;
	if (!need(a, 4, e)) return;
	Core::World &w = self->w;
	if (!w.on || !api.ok) return;
	float frac = (float)a.num(0);
	V3 cam = a.v3(1);
	int hide = (int)a.integer(2);
	bool paused = a.boolean(3);
	int n = (int)self->td.size();
	Step S{ self, 0.0f };
	for (int i = 0; i < n; i++) {
		Core::TankDyn &d = self->td[i];
		float *t = S.T(i);
		bool vis = (!d.alive || S.team(i) == 0 || t[P_VIS0] != 0.0f) && i != hide;
		if (d.root && d.shown != (vis ? 1 : 0)) {
			gd::call_bool(api.set_visible, d.root, vis);
			d.shown = vis ? 1 : 0;
		}
		if (!d.alive) continue;
		// звук: далёкие моторы стоят и не нагружают микшер
		V3 c = S.center(i);
		float dx = c.x - cam.x, dy = c.y - cam.y, dz = c.z - cam.z;
		// ход гусениц и катков — параметры материалов: каждая смена перезаливает буфер материала в драйвер.
		// Стоящим не шлём, ближним — каждый кадр, дальше 700 — каждый 4-й, дальше 1300 — не шлём (не видно)
		if (vis) {
			float dd = dx * dx + dy * dy + dz * dz;
			float tl = d.travel_prev[0] + (t[P_TRAVEL_L] - d.travel_prev[0]) * frac;
			float tr = d.travel_prev[1] + (t[P_TRAVEL_R] - d.travel_prev[1]) * frac;
			bool moved = std::fabs(tl - d.travel_sent[0]) > 1e-3f || std::fabs(tr - d.travel_sent[1]) > 1e-3f;
			bool due = dd < 700.0f * 700.0f || (dd < 1300.0f * 1300.0f && (d.travel_tick++ & 3) == 0);
			if (moved && due) {
				S.travel(i, tl, tr);
				d.travel_sent[0] = tl;
				d.travel_sent[1] = tr;
			}
		}
		bool far = dx * dx + dy * dy + dz * dz > 1300.0f * 1300.0f;
		for (int k = 0; k < 3; k++) {
			bool pz = far || paused;
			if (k == 1 && !far) {
				float tv0 = clampf(std::max(std::fabs(t[P_SP]), std::fabs(t[P_YAW]) * d.W * 0.5f) / std::max(d.speed, 1.0f), 0.0f, 1.0f);
				pz = paused || tv0 < 0.02f;
			}
			if (d.snd[k] && d.snd_paused[k] != (pz ? 1 : 0)) {
				gd::call_bool(api.snd_paused, d.snd[k], pz);
				d.snd_paused[k] = pz ? 1 : 0;
			}
		}
		if (far) continue;
		float v = clampf(std::fabs(t[P_SP]) / std::max(d.speed, 1.0f), 0.0f, 1.0f);
		float load = clampf(std::fabs(t[P_THROTTLE]), 0.0f, 1.0f);
		float x4 = w.speed > 1 ? 10.0f : 0.0f;
		if (d.snd[0]) {
			float rpm = 0.75f + v * 0.75f + load * 0.35f + std::fabs(t[P_YAW]) * 0.15f;
			d.eng_pitch += (rpm - d.eng_pitch) * 0.1f;
			gd::call_double(api.snd_pitch, d.snd[0], d.eng_pitch);
			gd::call_double(api.snd_volume, d.snd[0], (d.player ? -2.0f : -6.0f) + load * 4.0f - x4);
		}
		if (d.snd[1]) {
			float tv = clampf(std::max(std::fabs(t[P_SP]), std::fabs(t[P_YAW]) * d.W * 0.5f) / std::max(d.speed, 1.0f), 0.0f, 1.0f);
			gd::call_double(api.snd_pitch, d.snd[1], 0.6f + tv * 0.9f);
			gd::call_double(api.snd_volume, d.snd[1], linear_to_db(std::max(tv, 0.001f)) - 2.0f - x4);
		}
		if (d.snd[2]) {
			float tr = clampf(t[P_TUR_RATE] / std::max(d.tspd, 0.01f), 0.0f, 1.0f);
			gd::call_double(api.snd_volume, d.snd[2], linear_to_db(std::max(tr, 0.001f)) - 6.0f);
			gd::call_double(api.snd_pitch, d.snd[2], 0.8f + tr * 0.4f);
		}
	}
}

// Звуки танка смолкли (подбит): больше не трогаем.
METHOD(world_silence) {
	SELF;
	if (!need(a, 1, e)) return;
	int i = (int)a.integer(0);
	if (i < 0 || i >= (int)self->td.size()) return;
	for (gd::Obj &s : self->td[i].snd) s = nullptr;
}

// Опыт и серебро за бой (как Battle.rewards): (уровень, ремонт уничтоженного, цены снаряжения ×3,
// доля свободного опыта) → [строки: вид, опыт, серебро]*, множитель, за уровень, опыт, свободный,
// серебро до вычетов, ремонт, снаряжение, итого серебро — последние 8 чисел.
METHOD(world_rewards) {
	SELF;
	if (!need(a, 3, e)) return;
	Core::World &w = self->w;
	int tier = (int)a.integer(0);
	float repair_full = (float)a.num(1);
	std::vector<float> prices = f32(a, 2);
	prices.resize(4, 0.0f);
	float free_share = a.n > 3 ? (float)a.num(3) : 0.05f;
	int pl = w.player;
	bool alive = pl >= 0 && self->td[pl].alive;
	float lines[8][2] = {
		{ w.dmg_done * 0.5f, w.dmg_done * 8.0f },
		{ w.spot_dmg * 0.25f, w.spot_dmg * 4.0f },
		{ w.blocked * 0.1f, w.blocked * 1.5f },
		{ w.kills * 40.0f, w.kills * 900.0f },
		{ w.spotted_n * 15.0f, w.spotted_n * 300.0f },
		{ w.cap_pts, w.cap_pts * 30.0f },
		{ w.def_pts * 1.5f, w.def_pts * 30.0f },
		{ 20.0f + (alive ? 30.0f : 0.0f), 1000.0f + tier * 400.0f },
	};
	std::vector<float> out;
	double xp = 0.0, silver = 0.0;
	for (int k = 0; k < 8; k++) {
		xp += lines[k][0];
		silver += lines[k][1];
		if (lines[k][0] >= 1.0f || lines[k][1] >= 1.0f) {
			out.push_back((float)k);
			out.push_back(std::round(lines[k][0]));
			out.push_back(std::round(lines[k][1]));
		}
	}
	float mult = w.result == 1 ? 1.5f : (w.result == 3 ? 1.1f : 1.0f);
	float tk_mult = 1.0f + std::max(0, tier - 4) * 0.2f;
	xp = std::round(xp * mult * tk_mult);
	silver = std::round(silver * mult * tk_mult);
	float hp_k = pl >= 0 ? clampf(self->td[pl].hp / std::max(self->td[pl].max_hp, 1.0f), 0.0f, 1.0f) : 0.0f;
	float repair = std::round((1.0f - hp_k) * repair_full);
	float cons_cost = 0.0f;
	if (pl >= 0) {
		for (int k = 0; k < 3; k++) cons_cost += self->td[pl].cons_used[k] ? prices[k] : 0.0f;
	}
	float tail[8] = { mult, tk_mult, (float)xp, std::round((float)xp * free_share), (float)silver, repair, cons_cost, (float)silver - repair - cons_cost };
	out.insert(out.end(), tail, tail + 8);
	ret_f32(r, out.data(), (int64_t)out.size());
}


// Боекомплект танка i: по 6 чисел на вид — вид (AM_*), пробитие, урон, ВВ г, скорость ×, сколько (-1 — без счёта).
METHOD(ammo_set) {
	SELF;
	if (!need(a, 2, e)) return;
	int i = (int)a.integer(0);
	if (i < 0 || (size_t)i >= self->td.size()) return;
	std::vector<float> f = f32(a, 1);
	Core::TankDyn &d = self->td[i];
	d.am_n = 0;
	d.am_cur = 0;
	for (size_t k = 0; k + 6 <= f.size() && d.am_n < 5; k += 6) {
		Core::TankDyn::Ammo &m = d.am[d.am_n++];
		m.kind = (int)clampf(f[k], 0.0f, 4.0f);
		m.pen = std::max(0.0f, f[k + 1]);
		m.dmg = std::max(0.0f, f[k + 2]);
		m.he = std::max(0.0f, f[k + 3]);
		m.vel_k = clampf(f[k + 4], 0.3f, 2.0f);
		m.left = (int)f[k + 5];
		m.used = 0;
	}
}

// Игрок выбрал снаряд k: если орудие уже заряжено другим — перезарядка заново (как в War Thunder).
METHOD(ammo_pick) {
	SELF;
	if (!need(a, 2, e)) return;
	int i = (int)a.integer(0), k = (int)a.integer(1);
	if (i < 0 || (size_t)i >= self->td.size()) return;
	Core::TankDyn &d = self->td[i];
	if (k < 0 || k >= d.am_n || k == d.am_cur || d.am[k].left == 0) return;
	d.am_cur = k;
	if (d.rl <= 0.0f && d.alive) {
		d.rl_max = d.reload * d.reload_k;
		d.rl = d.rl_max;
	}
}

// Боекомплект танка i для интерфейса: текущий, затем по виду — вид, осталось, выпущено.
METHOD(ammo_state) {
	SELF;
	if (!need(a, 1, e)) return;
	int i = (int)a.integer(0);
	std::vector<float> o;
	if (i >= 0 && (size_t)i < self->td.size()) {
		const Core::TankDyn &d = self->td[i];
		o.push_back((float)d.am_cur);
		for (int k = 0; k < d.am_n; k++) {
			o.push_back((float)d.am[k].kind);
			o.push_back((float)d.am[k].left);
			o.push_back((float)d.am[k].used);
		}
	}
	ret_f32(r, o.data(), (int64_t)o.size());
}

// Пехота: отделения строками по 16 чисел — команда, направление, x, z, держит рубеж, нация, стрелков,
// автоматчиков, ПТ-ружей, гранатомётов, «фаустов», пробитие ружья, гранатомёта, «фауста», калибр гранатомёта, запас.
METHOD(inf_init) {
	SELF;
	if (!need(a, 1, e)) return;
	std::vector<float> f = f32(a, 0);
	self->inf.clear();
	self->isq.clear();
	self->mg_t.clear();
	self->inf_kills = 0;
	self->inf_t = 0.0f;
	for (size_t q = 0; q + 16 <= f.size(); q += 16) {
		const float *p = &f[q];
		Core::InfSquad s;
		s.team = p[0] != 0.0f ? 1 : 0;
		s.lane = (int)clampf(p[1], 0.0f, 2.0f);
		s.ax = p[2];
		s.ay = p[3];
		s.hold = p[4] != 0.0f;
		s.nat = (int)p[5];
		s.hx = 0.0f;
		s.hy = s.team == 0 ? -1.0f : 1.0f;
		s.side = (self->isq.size() % 2 == 0 ? 1.0f : -1.0f) * (90.0f + 30.0f * (float)(self->isq.size() % 3));
		s.atr_pen = p[11];
		s.tube_pen = p[12];
		s.faust_pen = p[13];
		s.tube_cal = p[14];
		int cnt[5];
		int total = 0;
		for (int k = 0; k < 5; k++) {
			cnt[k] = (int)clampf(p[6 + k], 0.0f, 12.0f);
			total += cnt[k];
		}
		int qi = (int)self->isq.size();
		if (p[15] != 0.0f && self->inf.size() < 400) {
			// ПТ-пушка: одна на «отделение», встаёт в ближайшие кусты или за укрытие
			Core::Soldier o;
			o.team = s.team;
			o.squad = qi;
			o.role = IR_GUN;
			o.ammo = 3;
			o.x = s.ax;
			o.y = s.ay;
			V2 out;
			if (self->bush_near({ s.ax, s.ay }, 130.0f, -1, out) || self->cover_near({ s.ax, s.ay }, 130.0f, out)) {
				o.x = out.x;
				o.y = out.y;
			}
			self->resolve(o.x, o.y, 8.0f);
			o.gh = self->height(o.x, o.y);
			o.yaw = std::atan2(s.hy, s.hx);
			o.think_t = self->randf() * 0.6f;
			o.rl = 2.0f + self->randf() * 2.0f;
			self->inf.push_back(o);
			s.hold = true;
			s.alive = 1;
			s.nat = (int)p[5] + 64 * (int)clampf(p[13], 0.0f, 3.0f);
			self->isq.push_back(s);
			continue;
		}
		if (total <= 0 || self->inf.size() + (size_t)total > 400) continue;
		int j = 0;
		for (int role = 0; role < 5; role++) {
			for (int m = 0; m < cnt[role]; m++, j++) {
				Core::Soldier o;
				o.team = s.team;
				o.squad = qi;
				o.role = role;
				o.ammo = role == IR_TUBE ? 5 : (role == IR_FAUST ? 2 : 0);
				float lat = ((float)j - (float)(total - 1) * 0.5f) * 15.0f;
				o.ox = lat + (self->randf() - 0.5f) * 6.0f;
				o.oy = -std::fabs(lat) * 0.35f + (self->randf() - 0.5f) * 8.0f;
				o.x = s.ax + (-s.hy) * o.ox + s.hx * o.oy;
				o.y = s.ay + s.hx * o.ox + s.hy * o.oy;
				self->resolve(o.x, o.y, 2.5f);
				o.gh = self->height(o.x, o.y);
				o.yaw = std::atan2(s.hy, s.hx);
				o.think_t = self->randf() * 0.6f;
				o.rl = self->randf() * 2.0f;
				o.anim = self->randf();
				o.state = s.hold ? IS_CROUCH : IS_STAND;
				self->inf.push_back(o);
			}
		}
		s.alive = total;
		self->isq.push_back(s);
	}
	ret_int(r, (int64_t)self->inf.size());
}

METHOD(inf_view) {
	SELF;
	std::vector<float> o(self->inf.size() * INF_VIEW + 1);
	for (size_t k = 0; k < self->inf.size(); k++) {
		const Core::Soldier &s = self->inf[k];
		float *v = &o[k * INF_VIEW];
		v[0] = s.x;
		v[1] = s.gh;
		v[2] = s.y;
		v[3] = s.yaw;
		v[4] = (float)s.state;
		v[5] = s.role == IR_GUN ? (float)s.ammo : (s.alive ? s.anim : s.dead_t);
		v[6] = (float)s.team;
		int nat = (s.squad >= 0 && (size_t)s.squad < self->isq.size()) ? self->isq[s.squad].nat : 0;
		v[7] = (float)(s.role + 8 * nat);
		v[8] = (float)((s.alive ? 1 : 0) | ((s.team == 0 || s.seen[0] > 0.0f) ? 2 : 0) | (s.fired_t < 0.15f ? 4 : 0) | (s.sup > 0.45f ? 8 : 0));
	}
	o[self->inf.size() * INF_VIEW] = (float)self->inf_kills;
	ret_f32(r, o.data(), (int64_t)o.size());
}

void register_battle(GDExtensionClassLibraryPtr lib, const char *cls) {
	static const MethodDef defs[] = {
		{ "ammo_set", ammo_set },
		{ "ammo_pick", ammo_pick },
		{ "ammo_state", ammo_state },
		{ "inf_init", inf_init },
		{ "inf_view", inf_view },
		{ "world_init", world_init },
		{ "world_nodes", world_nodes },
		{ "world_step", world_step },
		{ "world_frame", world_frame },
		{ "world_silence", world_silence },
		{ "world_rewards", world_rewards },
	};
	register_list(lib, cls, defs, sizeof(defs) / sizeof(defs[0]));
}
