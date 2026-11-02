// Процедурные модели танков (как TankModels.build в GDScript): корпус по профилю с наклонными бортами,
// ходовая (катки всех видов, тележки, звёздочка, ленивец, поддерживающие ролики, полки), гусеничные
// ленты по выпуклой оболочке, башня или рубка, маска, орудие с дульным тормозом и детали 42 танков
// (люки, приборы, пулемёты, фары, баки, тросы, решётки, экраны, ящики). Числа — как в GDScript: скаляры —
// double, векторы — float, многоугольники режет Clipper2 самого движка, триангуляция — как у движка.
#include "geom.h"

namespace {

const double PI_D = 3.141592653589793;
const double TAU_D = 6.283185307179586;

double U = 7.5;  // D.UPM: единиц карты в метре (задаёт GDScript при вызове)

inline V3 Vector3(double x, double y, double z) { return { (float)x, (float)y, (float)z }; }
inline V3 operator+(V3 a, V3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 mulf(V3 a, double k) {
	float f = (float)k;
	return { a.x * f, a.y * f, a.z * f };
}
inline double lerpd(double a, double b, double t) { return a + (b - a) * t; }
inline double clampd(double v, double a, double b) { return v < a ? a : (v > b ? b : v); }

// Преобразование: позиция и масштаб в метрах → единицы карты (TankModels.T3)
inline Xf T3(V3 pos, V3 rot = { 0, 0, 0 }, V3 scale = { 1, 1, 1 }) { return { basis_euler(rot) * basis_scale(mulf(scale, U)), mulf(pos, U) }; }

inline Prim box(V3 s) { return prim_box(s); }
inline Prim cyl(double top, double bottom, double h, int seg = 10) { return prim_cyl((float)top, (float)bottom, (float)h, seg, 1); }
inline Prim sph(int radial = 7, int rings = 4) { return prim_sphere(0.5f, 1.0f, radial, rings); }

struct CX {
	Prim p0;
	V3 p1;
};
// цилиндр вдоль оси X (ствол, бочка): сетка и поворот
inline CX cyl_x(double r1, double r2, double l, int seg = 12) { return { cyl(r1, r2, l, seg), Vector3(0, 0, -PI_D / 2) }; }

// Цвета неокрашенных деталей (альфа 0 — без камуфляжа), TankModels.K
enum Kind { K_PAINT, K_STEEL, K_RUBBER, K_RUST, K_WOOD, K_GLASS, K_SLIT, K_OLIVE, K_ROPE, K_WHITE };
const float KC[10][4] = { { 1, 1, 1, 1 }, { 0.2f, 0.2f, 0.19f, 0 }, { 0.07f, 0.07f, 0.065f, 0 }, { 0.27f, 0.17f, 0.11f, 0 },
	{ 0.36f, 0.27f, 0.17f, 0 }, { 0.32f, 0.36f, 0.38f, 0 }, { 0.03f, 0.03f, 0.03f, 0 }, { 0.25f, 0.27f, 0.16f, 0 },
	{ 0.3f, 0.28f, 0.22f, 0 }, { 0.88f, 0.88f, 0.85f, 0 } };

// Сборщик части (TankModels.Builder): один материал, цвет детали в цвете вершины, UV2 — центр катка
struct TB {
	Group g;
	TB() { g.extra = true; }
	void put(const Prim &p, const Xf &x, int kind = K_PAINT, bool flat = false) {
		static const V2 zero = { 0, 0 };
		g.add(p, x, 0, flat, KC[kind], zero, &zero);
	}
	// вращающаяся деталь ходовой: центр (x, y) в метрах, радиус, борт
	void wheel(const Prim &p, const Xf &x, int kind, double cx, double cy, double r, double side) {
		float u = (float)U;
		V2 uv2 = { (float)cx * u, (float)cy * u };
		V2 over = { (float)(1.0 / (r * U)), (float)side };
		g.add(p, x, 0, false, KC[kind], uv2, &over);
	}
};

// Танки с особыми деталями (TankModels._hull_details / _turret_details)
enum Key {
	KEY_NONE = -1, KEY_T34, KEY_T34_76, KEY_TIGER, KEY_IS2, KEY_PZ4, KEY_CHAFFEE, KEY_KV1, KEY_SHERMAN, KEY_FIREFLY,
	KEY_PANTHER, KEY_PZ3, KEY_CRUSADER, KEY_CROMWELL, KEY_TIGER2, KEY_STUG
};
enum Wheel { W_INTERLEAVED, W_SPOKED, W_SINGLE, W_VVSS, W_DOUBLE };
enum TPoly { TP_HORSESHOE, TP_PZ4, TP_PZ, TP_CRUSADER, TP_CROMWELL, TP_HEX, TP_PANTHER, TP_STUG, TP_OVAL };
enum Mant {
	MANT_NONE = -1, MANT_CAST, MANT_CAST_BIG, MANT_PLATE, MANT_BOX, MANT_ROUNDED, MANT_BOX_SPACED, MANT_6PDR, MANT_F34,
	MANT_KV, MANT_ROTOR, MANT_BELL, MANT_SAUKOPF_BIG, MANT_SAUKOPF
};
enum Brake { BR_DOUBLE, BR_DOUBLE_BIG, BR_BALL, BR_NONE };

// Спецификация танка (TankModels.SPECS[key] и год), из PackedFloat64Array GDScript
struct Spec {
	int key = KEY_NONE, wheel = W_DOUBLE, tpk = TP_OVAL, mant = MANT_NONE, brake = BR_NONE;
	double L = 0, W = 0, tw = 0, th = 0, up_w = 0, wr = 0, tur_x = 0, tur_h = 0, tur_top = 1;
	bool smooth = false;
	double gun_len = 0, gun_r0 = 0, gun_r1 = 0, tp_f = 0, tp_b = 0, tp_hw = 0;
	bool skirts = false;
	double skirt_y = 1.0;
	bool shelf = true, hatch = true, casemate = false;
	double side_slope = 0;
	bool band = false;
	int year = 1944;
	std::vector<V2> hull;  // профиль (Vector2 из пар double)
	std::vector<double> wheels, spr, idl, rollers, bogies, cupola;
};
const int HEAD = 30;

bool read_spec(const std::vector<double> &f, Spec &S) {
	if (f.size() < (size_t)HEAD) return false;
	S.key = (int)f[0];
	S.wheel = (int)f[1];
	S.tpk = (int)f[2];
	S.mant = (int)f[3];
	S.brake = (int)f[4];
	S.L = f[5];
	S.W = f[6];
	S.tw = f[7];
	S.th = f[8];
	S.up_w = f[9];
	S.wr = f[10];
	S.tur_x = f[11];
	S.tur_h = f[12];
	S.tur_top = f[13];
	S.smooth = f[14] != 0.0;
	S.gun_len = f[15];
	S.gun_r0 = f[16];
	S.gun_r1 = f[17];
	S.tp_f = f[18];
	S.tp_b = f[19];
	S.tp_hw = f[20];
	S.skirts = f[21] != 0.0;
	S.skirt_y = f[22];
	S.shelf = f[23] != 0.0;
	S.hatch = f[24] != 0.0;
	S.casemate = f[25] != 0.0;
	S.side_slope = f[26];
	S.band = f[27] != 0.0;
	S.year = (int)f[28];
	U = f[29];
	size_t q = HEAD;
	auto list = [&](std::vector<double> &out) {
		if (q >= f.size()) return false;
		size_t n = (size_t)f[q++];
		if (q + n > f.size()) return false;
		out.assign(f.begin() + (long)q, f.begin() + (long)(q + n));
		q += n;
		return true;
	};
	std::vector<double> hp;
	if (!list(hp)) return false;
	for (size_t i = 0; i + 1 < hp.size(); i += 2) S.hull.push_back({ (float)hp[i], (float)hp[i + 1] });
	return list(S.wheels) && list(S.spr) && list(S.idl) && list(S.rollers) && list(S.bogies) && list(S.cupola) && S.spr.size() == 3 &&
			S.idl.size() == 3;
}

const Spec *SP = nullptr;  // текущая спецификация (для th_top)
inline double th_top() { return SP->th + 0.06; }

// Точка на линии профиля между двумя вершинами (для деталей на наклонных листах): [точка, угол]
struct Edge {
	V2 p0;
	double p1;
};
Edge on_edge(const std::vector<V2> &prof, int i, double t) {
	Edge e = { { 0, 0 }, 0.0 };
	if (i + 1 >= (int)prof.size()) return e;
	V2 a = prof[i], b = prof[i + 1];
	float w = (float)t;
	e.p0 = { a.x + (b.x - a.x) * w, a.y + (b.y - a.y) * w };
	e.p1 = std::atan2((double)b.y - a.y, (double)b.x - a.x);
	return e;
}

// Насколько сужается башня к высоте yf (доля высоты): для деталей на наклонных бортах
inline double side_at(double w, double top, double yf) { return w * (1.0 + (top - 1.0) * yf); }

// Бортовые экраны: count листов высотой h шагом step от x0, поручень на высоте rail_y
void skirts_(TB &b, double W, double x0, int count, double step, double rail_y, double h = 0.95) {
	for (double s : { 1.0, -1.0 }) {
		auto rail = cyl_x(0.025, 0.025, step * count, 6);
		b.put(rail.p0, T3(Vector3(x0 + step * (count - 1) / 2.0, rail_y, s * (W / 2 + 0.16)), rail.p1), K_STEEL);
		for (int k = 0; k < count; k++) {
			auto px = x0 + k * step;
			b.put(box(Vector3(step - 0.04, h, 0.03)), T3(Vector3(px, rail_y - h / 2, s * (W / 2 + 0.18)), Vector3(0.03 * s, 0, 0.01 * (k - 2))), K_PAINT, true);
		}
	}
}

// Каток со сплошным диском: резиновый бандаж, окрашенный диск, ступица и болты
void wheel_disc(TB &b, double x, double y, double z, double r, double w, double s, bool rubber) {
	V3 rot = Vector3(PI_D / 2, 0, 0);
	b.wheel(cyl(r, r, w, 18), T3(Vector3(x, y, z), rot), rubber ? K_RUBBER : K_PAINT, x, y, r, s);
	b.wheel(cyl(r * 0.82, r * 0.86, w * 1.08, 18), T3(Vector3(x, y, z), rot), K_PAINT, x, y, r, s);
	b.wheel(cyl(r * 0.3, r * 0.34, w * 1.25, 12), T3(Vector3(x, y, z), rot), K_STEEL, x, y, r, s);
	for (int k = 0; k < 6; k++) {
		double a = TAU_D * k / 6.0;
		double bx = x + std::cos(a) * r * 0.5;
		double by = y + std::sin(a) * r * 0.5;
		b.wheel(cyl(r * 0.06, r * 0.06, w * 1.16, 6), T3(Vector3(bx, by, z), rot), K_STEEL, x, y, r, s);
	}
}

// Каток Т-34: большой, с резиновым бандажом и облегчающими отверстиями-спицами
void wheel_spoked(TB &b, double x, double y, double z, double r, double w, double s) {
	V3 rot = Vector3(PI_D / 2, 0, 0);
	b.wheel(cyl(r, r, w, 22), T3(Vector3(x, y, z), rot), K_RUBBER, x, y, r, s);
	b.wheel(cyl(r * 0.84, r * 0.84, w * 1.06, 22), T3(Vector3(x, y, z), rot), K_PAINT, x, y, r, s);
	b.wheel(cyl(r * 0.26, r * 0.3, w * 1.2, 12), T3(Vector3(x, y, z), rot), K_STEEL, x, y, r, s);
	for (int k = 0; k < 8; k++) {
		double a = TAU_D * k / 8.0;
		b.wheel(cyl(r * 0.13, r * 0.13, w * 1.12, 8), T3(Vector3(x + std::cos(a) * r * 0.56, y + std::sin(a) * r * 0.56, z), rot), K_SLIT, x, y, r, s);
	}
}

// Ведущая звёздочка с зубьями
void sprocket(TB &b, double x, double y, double z, double r, double w, double s) {
	V3 rot = Vector3(PI_D / 2, 0, 0);
	b.wheel(cyl(r * 0.85, r * 0.85, w, 16), T3(Vector3(x, y, z), rot), K_PAINT, x, y, r, s);
	b.wheel(cyl(r * 0.35, r * 0.4, w * 1.3, 10), T3(Vector3(x, y, z), rot), K_STEEL, x, y, r, s);
	for (int k = 0; k < 12; k++) {
		double a = TAU_D * k / 12.0;
		V3 tp = Vector3(x + std::cos(a) * r * 0.92, y + std::sin(a) * r * 0.92, z);
		b.wheel(box(Vector3(0.09, 0.07, w * 0.9)), T3(tp, Vector3(0, 0, a)), K_STEEL, x, y, r, s);
	}
}

std::vector<V2> pts(std::initializer_list<double> v) {
	std::vector<V2> out;
	const double *p = v.begin();
	for (size_t i = 0; i + 1 < v.size(); i += 2) out.push_back({ (float)p[i], (float)p[i + 1] });
	return out;
}

// Вид башни сверху (TankModels._turret_poly)
std::vector<V2> turret_poly(int kind, double f, double b, double hw) {
	switch (kind) {
		case TP_HORSESHOE: {
			std::vector<V2> out = { { (float)(f * 0.82), (float)hw } };
			for (int i = 0; i < 15; i++) {
				double a = PI_D / 2 + PI_D * i / 14.0;
				out.push_back({ (float)(std::cos(a) * b), (float)(std::sin(a) * hw) });
			}
			out.push_back({ (float)(f * 0.82), (float)-hw });
			out.push_back({ (float)f, (float)(-hw * 0.72) });
			out.push_back({ (float)f, (float)(hw * 0.72) });
			return out;
		}
		case TP_PZ4:
			return pts({ 0.88, 0.5, 0.3, 0.86, -1.18, 0.8, -1.3, 0.0, -1.18, -0.8, 0.3, -0.86, 0.88, -0.5 });
		case TP_PZ:
			return pts({ f, hw * 0.58, f * 0.34, hw, -b * 0.9, hw * 0.93, -b, 0.0, -b * 0.9, -hw * 0.93, f * 0.34, -hw, f, -hw * 0.58 });
		case TP_CRUSADER:
			return pts({ f, hw * 0.45, f * 0.6, hw * 0.85, -b * 0.3, hw, -b * 0.85, hw * 0.8, -b, hw * 0.45,
				-b, -hw * 0.45, -b * 0.85, -hw * 0.8, -b * 0.3, -hw, f * 0.6, -hw * 0.85, f, -hw * 0.45 });
		case TP_CROMWELL:
			return pts({ f, hw * 0.82, f * 0.85, hw, -b, hw, -b, -hw, f * 0.85, -hw, f, -hw * 0.82 });
		case TP_HEX:
			return pts({ f, hw * 0.5, f * 0.45, hw, -b * 0.72, hw, -b, hw * 0.55, -b, -hw * 0.55,
				-b * 0.72, -hw, f * 0.45, -hw, f, -hw * 0.5 });
		case TP_PANTHER:
			return pts({ f, hw * 0.66, -b * 0.86, hw, -b, hw * 0.84, -b, -hw * 0.84, -b * 0.86, -hw, f, -hw * 0.66 });
		case TP_STUG:
			return pts({ f, hw * 0.62, f * 0.72, hw, -b, hw, -b, -hw, f * 0.72, -hw, f, -hw * 0.62 });
		default:
			return geo_oval(f, b, hw, 22);
	}
}

// Гусеничные ленты по контуру (в единицах карты): одна сетка на обе, материал один
Group tracks(const std::vector<V2> &outline, double tw, double tz) {
	Group tg;
	Prim belt = geo_belt(outline, tw, 0.09 * U, 0.24 * U);
	tg.add(belt, { M3::ident(), Vector3(0, 0, tz) }, 0);
	tg.add(belt, { M3::ident(), Vector3(0, 0, -tz) }, 0);
	return tg;
}

void hull_details(TB &b, const Spec &S, double roof, bool skirts, int year) {
	(void)roof;
	int key = S.key;
	double L = S.L, W = S.W, up_w = S.up_w, th = S.th;
	(void)L;
	const std::vector<V2> &prof = S.hull;
	double side_k = std::tan(S.side_slope * (PI_D / 180.0));
	(void)side_k;
	// match key
	{
		if (key == KEY_T34 || key == KEY_T34_76) {
			// люк механика-водителя и шаровая установка пулемёта на лобовом листе
			auto e = on_edge(prof, 2, 0.45);
			auto p = e.p0;
			b.put(box(Vector3(0.5, 0.08, 0.6)), T3(Vector3(p.x, p.y + 0.03, -0.55), Vector3(0, 0, e.p1)), K_PAINT, true);
			b.put(box(Vector3(0.12, 0.03, 0.3)), T3(Vector3(p.x + 0.1, p.y + 0.06, -0.55), Vector3(0, 0, e.p1)), K_SLIT, true);
			auto e2 = on_edge(prof, 2, 0.5);
			auto p2 = e2.p0;
			b.put(sph(12, 8), T3(Vector3(p2.x, p2.y, 0.62), Vector3(0, 0, 0), Vector3(0.32, 0.32, 0.32)), K_PAINT);
			auto mg = cyl_x(0.025, 0.025, 0.4, 6);
			b.put(mg.p0, T3(Vector3(p2.x + 0.25, p2.y - 0.1, 0.62), mg.p1 + Vector3(0, 0, -0.3)), K_STEEL);
			// фара, буксирные крюки
			b.put(cyl(0.09, 0.09, 0.14, 10), T3(Vector3(2.55, 1.0, -1.15), Vector3(0, 0, -PI_D / 2)), K_GLASS);
			for (double s : { 1.0, -1.0 }) {
				b.put(box(Vector3(0.18, 0.1, 0.08)), T3(Vector3(3.08, 0.55, s * 0.9)), K_STEEL, true);
			}
			// бочки с топливом на корме и выхлопные трубы
			for (double s : { 1.0, -1.0 }) {
				auto drum = cyl_x(0.3, 0.3, 0.95, 14);
				b.put(drum.p0, T3(Vector3(-2.15, 1.38, s * 1.22), drum.p1), K_PAINT);
				b.put(box(Vector3(0.04, 0.68, 0.04)), T3(Vector3(-1.75, 1.38, s * 1.22)), K_STEEL, true);
				b.put(box(Vector3(0.04, 0.68, 0.04)), T3(Vector3(-2.55, 1.38, s * 1.22)), K_STEEL, true);
				auto ex = cyl_x(0.09, 0.09, 0.3, 8);
				b.put(ex.p0, T3(Vector3(-3.05, 0.95, s * 0.55), ex.p1), K_RUST);
			}
			// запасные траки на лобовом листе
			for (int k = 0; k < 3; k++) {
				auto ek = on_edge(prof, 2, 0.72 + k * 0.08);
				auto pk = ek.p0;
				b.put(box(Vector3(0.2, 0.05, 0.5)), T3(Vector3(pk.x, pk.y + 0.03, 0.55), Vector3(0, 0, ek.p1)), K_STEEL, true);
			}
			// решётки моторного отделения
			b.put(box(Vector3(1.1, 0.04, 1.2)), T3(Vector3(-1.9, 1.47, 0)), K_SLIT, true);
			for (int k = 0; k < 6; k++) {
				b.put(box(Vector3(1.1, 0.05, 0.06)), T3(Vector3(-1.9, 1.49, -0.5 + k * 0.2)), K_PAINT, true);
			}
		}
		else if (key == KEY_TIGER) {
			// смотровой прибор механика и курсовой пулемёт на вертикальном лобовом листе
			b.put(box(Vector3(0.14, 0.18, 0.55)), T3(Vector3(2.4, 1.6, -0.75)), K_PAINT, true);
			b.put(box(Vector3(0.05, 0.05, 0.4)), T3(Vector3(2.48, 1.6, -0.75)), K_SLIT, true);
			b.put(sph(12, 8), T3(Vector3(2.38, 1.55, 0.78), Vector3(0, 0, 0), Vector3(0.3, 0.3, 0.3)), K_PAINT);
			auto mg = cyl_x(0.025, 0.025, 0.35, 6);
			b.put(mg.p0, T3(Vector3(2.6, 1.55, 0.78), mg.p1), K_STEEL);
			// фары «Бош», передние крылья, буксирные тросы вдоль бортов
			for (double s : { 1.0, -1.0 }) {
				b.put(cyl(0.1, 0.12, 0.2, 10), T3(Vector3(2.3, 1.95, s * 1.45), Vector3(0, 0, -PI_D / 2)), K_PAINT);
				b.put(box(Vector3(0.55, 0.03, 0.72)), T3(Vector3(3.3, 1.07, s * (1.78 - 0.36)), Vector3(0, 0, -0.25)), K_PAINT, true);
				auto rope = cyl_x(0.03, 0.03, 4.2, 6);
				b.put(rope.p0, T3(Vector3(-0.3, 1.45, s * 1.73), rope.p1), K_ROPE);
				// выхлопные трубы с кожухами
				b.put(cyl(0.08, 0.08, 0.75, 10), T3(Vector3(-3.25, 1.75, s * 0.45)), K_RUST);
				b.put(cyl(0.13, 0.13, 0.5, 10), T3(Vector3(-3.25, 1.62, s * 0.45)), K_PAINT);
				// воздухозаборники на корме
				b.put(cyl(0.32, 0.32, 0.06, 14), T3(Vector3(-2.2, 1.78, s * 0.9)), K_PAINT);
			}
			// решётки моторного отделения и инструмент
			b.put(box(Vector3(1.2, 0.04, 1.0)), T3(Vector3(-2.2, 1.79, 0)), K_SLIT, true);
			b.put(box(Vector3(1.6, 0.06, 0.12)), T3(Vector3(-0.5, 1.88, 1.4)), K_WOOD, true);
			b.put(box(Vector3(1.2, 0.06, 0.1)), T3(Vector3(-0.4, 1.88, -1.45)), K_WOOD, true);
		}
		else if (key == KEY_IS2) {
			auto e = on_edge(prof, 2, 0.4);
			auto p = e.p0;
			b.put(box(Vector3(0.45, 0.1, 0.55)), T3(Vector3(p.x, p.y + 0.04, 0), Vector3(0, 0, e.p1)), K_PAINT, true);
			b.put(box(Vector3(0.1, 0.03, 0.3)), T3(Vector3(p.x + 0.1, p.y + 0.08, 0), Vector3(0, 0, e.p1)), K_SLIT, true);
			b.put(cyl(0.09, 0.09, 0.14, 10), T3(Vector3(2.8, 1.2, -1.15), Vector3(0, 0, -PI_D / 2)), K_GLASS);
			for (double s : { 1.0, -1.0 }) {
				// наружные топливные баки на кормовых полках
				b.put(box(Vector3(1.15, 0.45, 0.42)), T3(Vector3(-1.9, th_top() + 0.25, s * (up_w / 2 - 0.22))), K_PAINT, true);
				b.put(box(Vector3(1.0, 0.47, 0.06)), T3(Vector3(-1.9, th_top() + 0.25, s * (up_w / 2 - 0.05))), K_STEEL, true);
				auto ex = cyl_x(0.1, 0.1, 0.3, 8);
				b.put(ex.p0, T3(Vector3(-3.3, 1.1, s * 0.6), ex.p1), K_RUST);
				auto rope = cyl_x(0.03, 0.03, 3.6, 6);
				b.put(rope.p0, T3(Vector3(0.2, 1.52, s * 1.5), rope.p1), K_ROPE);
			}
			for (int k = 0; k < 3; k++) {
				auto ek = on_edge(prof, 2, 0.62 + k * 0.1);
				auto pk = ek.p0;
				b.put(box(Vector3(0.18, 0.05, 0.6)), T3(Vector3(pk.x, pk.y + 0.03, 0.9), Vector3(0, 0, ek.p1)), K_STEEL, true);
			}
			b.put(box(Vector3(1.4, 0.04, 1.4)), T3(Vector3(-2.2, 1.6, 0)), K_SLIT, true);
			for (int k = 0; k < 7; k++) {
				b.put(box(Vector3(1.4, 0.05, 0.07)), T3(Vector3(-2.2, 1.62, -0.6 + k * 0.2)), K_PAINT, true);
			}
		}
		else if (key == KEY_PZ4) {
			// смотровой прибор механика, курсовой пулемёт
			b.put(box(Vector3(0.12, 0.16, 0.42)), T3(Vector3(1.42, 1.45, -0.62)), K_PAINT, true);
			b.put(box(Vector3(0.04, 0.04, 0.32)), T3(Vector3(1.48, 1.45, -0.62)), K_SLIT, true);
			b.put(sph(12, 8), T3(Vector3(1.42, 1.4, 0.55), Vector3(0, 0, 0), Vector3(0.26, 0.26, 0.26)), K_PAINT);
			// запасные катки на лобовом листе и траки на носу
			for (double s : { 1.0, -1.0 }) {
				b.put(cyl(0.235, 0.235, 0.1, 16), T3(Vector3(2.62, 1.12, s * 0.8), Vector3(0, 0, -0.25)), K_RUBBER);
				b.put(cyl(0.19, 0.19, 0.12, 16), T3(Vector3(2.63, 1.13, s * 0.8), Vector3(0, 0, -0.25)), K_PAINT);
				b.put(cyl(0.07, 0.07, 0.6, 8), T3(Vector3(-3.0, 0.95, s * 0.5), Vector3(0, 0, PI_D / 2)), K_RUST);
			}
			for (int k = 0; k < 5; k++) {
				b.put(box(Vector3(0.05, 0.13, 0.36)), T3(Vector3(2.98, 0.68 + k * 0.08, -0.6 + (k % 2) * 0.05)), K_STEEL, true);
				b.put(box(Vector3(0.05, 0.13, 0.36)), T3(Vector3(2.98, 0.68 + k * 0.08, 0.6 - (k % 2) * 0.05)), K_STEEL, true);
			}
			// бортовые экраны «шюрцен» на кронштейнах (с весны 1943 г.)
			if (skirts) {
				skirts_(b, W, -2.15, 5, 0.98, 1.48);
			}
			b.put(box(Vector3(1.0, 0.04, 1.1)), T3(Vector3(-2.2, 1.57, 0)), K_SLIT, true);
		}
		else if (key == KEY_CHAFFEE) {
			for (double s : { 1.0, -1.0 }) {
				b.put(cyl(0.08, 0.08, 0.12, 10), T3(Vector3(2.3, 1.02, s * 1.1), Vector3(0, 0, -PI_D / 2 - 0.5)), K_GLASS);
				b.put(box(Vector3(0.9, 0.35, 0.3)), T3(Vector3(-1.3, 1.08, s * (W / 2 - 0.15))), K_PAINT, true);
				auto muf = cyl_x(0.11, 0.11, 0.6, 10);
				b.put(muf.p0, T3(Vector3(-2.65, 0.95, s * 0.6), muf.p1 + Vector3(PI_D / 2, 0, 0)), K_RUST);
			}
			auto e = on_edge(prof, 2, 0.3);
			auto p = e.p0;
			for (double s : { 1.0, -1.0 }) {
				b.put(box(Vector3(0.5, 0.06, 0.5)), T3(Vector3(p.x, p.y + 0.03, s * 0.55), Vector3(0, 0, e.p1)), K_PAINT, true);
			}
			// большие решётки моторного отделения
			b.put(box(Vector3(1.6, 0.04, 1.6)), T3(Vector3(-1.6, 1.6, 0)), K_SLIT, true);
			for (int k = 0; k < 9; k++) {
				b.put(box(Vector3(1.6, 0.05, 0.06)), T3(Vector3(-1.6, 1.62, -0.75 + k * 0.19)), K_PAINT, true);
			}
		}
		else if (key == KEY_KV1) {
			// смотровой прибор механика-водителя и курсовой пулемёт на верхнем лобовом листе
			auto e = on_edge(prof, 3, 0.35);
			auto p = e.p0;
			b.put(box(Vector3(0.3, 0.12, 0.5)), T3(Vector3(p.x, p.y + 0.04, -0.45), Vector3(0, 0, e.p1)), K_PAINT, true);
			b.put(box(Vector3(0.05, 0.04, 0.3)), T3(Vector3(p.x + 0.07, p.y + 0.1, -0.45), Vector3(0, 0, e.p1)), K_SLIT, true);
			auto e2 = on_edge(prof, 3, 0.5);
			auto p2 = e2.p0;
			b.put(sph(12, 8), T3(Vector3(p2.x, p2.y, 0.55), Vector3(0, 0, 0), Vector3(0.3, 0.3, 0.3)), K_PAINT);
			auto mg = cyl_x(0.025, 0.025, 0.4, 6);
			b.put(mg.p0, T3(Vector3(p2.x + 0.25, p2.y - 0.08, 0.55), mg.p1 + Vector3(0, 0, -0.3)), K_STEEL);
			b.put(cyl(0.1, 0.1, 0.15, 10), T3(Vector3(2.95, 1.6, -1.0), Vector3(0, 0, -PI_D / 2)), K_GLASS);
			for (double s : { 1.0, -1.0 }) {
				// буксирные крюки спереди и сзади
				b.put(box(Vector3(0.18, 0.1, 0.1)), T3(Vector3(3.42, 0.7, s * 0.95)), K_STEEL, true);
				b.put(box(Vector3(0.18, 0.1, 0.1)), T3(Vector3(-3.42, 0.7, s * 0.95)), K_STEEL, true);
				// ящики ЗИП на надгусеничных полках
				b.put(box(Vector3(1.0, 0.36, 0.38)), T3(Vector3(0.9, th + 0.25, s * (up_w / 2 + 0.2))), K_PAINT, true);
				b.put(box(Vector3(0.7, 0.3, 0.38)), T3(Vector3(-1.6, th + 0.22, s * (up_w / 2 + 0.2))), K_PAINT, true);
				// выхлопные трубы на кормовом листе
				auto ex = cyl_x(0.09, 0.09, 0.35, 8);
				b.put(ex.p0, T3(Vector3(-3.3, 1.45, s * 0.55), ex.p1 + Vector3(0, 0, 0.5)), K_RUST);
				// буксирный трос вдоль борта
				auto rope = cyl_x(0.03, 0.03, 3.4, 6);
				b.put(rope.p0, T3(Vector3(-0.4, 1.45, s * (up_w / 2 + 0.03)), rope.p1), K_ROPE);
			}
			// запасные траки на нижнем лобовом листе
			for (int k = 0; k < 3; k++) {
				auto ek = on_edge(prof, 5, 0.25 + k * 0.22);
				auto pk = ek.p0;
				b.put(box(Vector3(0.06, 0.16, 0.6)), T3(Vector3(pk.x + 0.03, pk.y, 0.75), Vector3(0, 0, ek.p1 + PI_D / 2)), K_STEEL, true);
			}
			// жалюзи моторного отделения
			b.put(box(Vector3(1.4, 0.04, 1.3)), T3(Vector3(-2.1, 1.79, 0)), K_SLIT, true);
			for (int k = 0; k < 7; k++) {
				b.put(box(Vector3(1.4, 0.05, 0.07)), T3(Vector3(-2.1, 1.81, -0.57 + k * 0.19)), K_PAINT, true);
			}
		}
		else if (key == KEY_SHERMAN || key == KEY_FIREFLY) {
			auto fx = key == KEY_FIREFLY ? 0.1 : 0.0;
			for (double s : { 1.0, -1.0 }) {
				// люки механика и помощника на крыше перед башней, перископы
				if (key == KEY_SHERMAN || s < 0) {
					b.put(box(Vector3(0.5, 0.05, 0.48)), T3(Vector3(1.1 + fx, 1.92, s * 0.52)), K_PAINT, true);
					b.put(box(Vector3(0.1, 0.1, 0.16)), T3(Vector3(1.28 + fx, 1.98, s * 0.52)), K_PAINT, true);
				}
				// фары с защитными решётками у верхних углов лобового листа
				auto e = on_edge(prof, 2, 0.62);
				auto p = e.p0;
				b.put(cyl(0.07, 0.08, 0.12, 10), T3(Vector3(p.x + 0.04, p.y + 0.1, s * 1.0), Vector3(0, 0, -PI_D / 2 - 0.3)), K_GLASS);
				b.put(box(Vector3(0.04, 0.22, 0.24)), T3(Vector3(p.x + 0.15, p.y + 0.12, s * 1.0)), K_STEEL, true);
				// буксирные проушины
				b.put(box(Vector3(0.14, 0.12, 0.08)), T3(Vector3(2.95 + fx, 0.66, s * 0.72)), K_STEEL, true);
				// воздухоочистители на кормовом листе
				b.put(cyl(0.13, 0.13, 0.5, 12), T3(Vector3(-3.04 - fx, 1.35, s * 0.82)), K_PAINT);
				b.put(cyl(0.14, 0.14, 0.06, 12), T3(Vector3(-3.04 - fx, 1.62, s * 0.82)), K_STEEL);
			}
			// шаровая установка курсового пулемёта справа (у «Файрфлая» снята ради боекомплекта)
			if (key == KEY_SHERMAN) {
				auto e2 = on_edge(prof, 2, 0.4);
				auto p2 = e2.p0;
				b.put(sph(12, 8), T3(Vector3(p2.x, p2.y, 0.5), Vector3(0, 0, 0), Vector3(0.24, 0.24, 0.24)), K_PAINT);
				auto mg = cyl_x(0.025, 0.025, 0.35, 6);
				b.put(mg.p0, T3(Vector3(p2.x + 0.2, p2.y - 0.08, 0.5), mg.p1 + Vector3(0, 0, -0.45)), K_STEEL);
			}
			else {
				auto e2 = on_edge(prof, 2, 0.4);
				auto p2 = e2.p0;
				b.put(box(Vector3(0.22, 0.04, 0.3)), T3(Vector3(p2.x, p2.y + 0.02, 0.5), Vector3(0, 0, e2.p1)), K_PAINT, true);
			}
			// литой картер трансмиссии: болты по фланцу
			for (int k = 0; k < 13; k++) {
				b.put(cyl(0.03, 0.03, 0.03, 6), T3(Vector3(2.68 + fx, 1.11, -1.1 + k * 0.183), Vector3(0, 0, -0.3)), K_STEEL);
			}
			// решётки моторного отделения, лопата и топор
			b.put(box(Vector3(1.0, 0.04, 1.4)), T3(Vector3(-2.2 - fx, 1.9, 0)), K_SLIT, true);
			for (int k = 0; k < 8; k++) {
				b.put(box(Vector3(1.0, 0.05, 0.07)), T3(Vector3(-2.2 - fx, 1.92, -0.63 + k * 0.18)), K_PAINT, true);
			}
			b.put(box(Vector3(1.2, 0.05, 0.1)), T3(Vector3(-0.95, 1.92, 1.05)), K_WOOD, true);
			b.put(box(Vector3(0.9, 0.05, 0.1)), T3(Vector3(-1.05, 1.92, -1.05)), K_WOOD, true);
			b.put(box(Vector3(0.22, 0.04, 0.2)), T3(Vector3(-0.3, 1.92, 1.05)), K_STEEL, true);
			// отражатель выхлопа под кормой
			b.put(box(Vector3(0.08, 0.36, 1.6)), T3(Vector3(-2.98 - fx, 0.95, 0), Vector3(0, 0, 0.4)), K_PAINT, true);
		}
		else if (key == KEY_PANTHER) {
			// смотровой лючок механика и откидная крышка пулемёта на лобовом листе
			auto e = on_edge(prof, 2, 0.22);
			auto p = e.p0;
			b.put(box(Vector3(0.2, 0.07, 0.46)), T3(Vector3(p.x, p.y + 0.03, -0.62), Vector3(0, 0, e.p1)), K_PAINT, true);
			b.put(box(Vector3(0.06, 0.04, 0.3)), T3(Vector3(p.x + 0.02, p.y + 0.07, -0.62), Vector3(0, 0, e.p1)), K_SLIT, true);
			if (year >= 1944) {
				// у Ausf. A и G — шаровая установка вместо «почтового ящика»
				b.put(sph(12, 8), T3(Vector3(p.x, p.y, 0.62), Vector3(0, 0, 0), Vector3(0.28, 0.28, 0.28)), K_PAINT);
				auto mg = cyl_x(0.025, 0.025, 0.35, 6);
				b.put(mg.p0, T3(Vector3(p.x + 0.22, p.y - 0.1, 0.62), mg.p1 + Vector3(0, 0, -0.55)), K_STEEL);
			}
			else {
				b.put(box(Vector3(0.18, 0.06, 0.26)), T3(Vector3(p.x, p.y + 0.03, 0.62), Vector3(0, 0, e.p1)), K_PAINT, true);
				b.put(box(Vector3(0.05, 0.03, 0.16)), T3(Vector3(p.x + 0.02, p.y + 0.06, 0.62), Vector3(0, 0, e.p1)), K_SLIT, true);
			}
			if (skirts) {
				skirts_(b, W, -2.85, 6, 0.95, th + 0.05, 0.42);
			}
			// фара «Бош»
			b.put(cyl(0.1, 0.12, 0.2, 10), T3(Vector3(p.x - 0.1, p.y + 0.22, -1.05), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			for (double s : { 1.0, -1.0 }) {
				// буксирные серьги
				b.put(box(Vector3(0.2, 0.22, 0.08)), T3(Vector3(3.3, 0.82, s * 1.1)), K_STEEL, true);
				// выхлопные трубы с кожухами на кормовом листе
				b.put(cyl(0.085, 0.085, 0.85, 10), T3(Vector3(-3.36, 1.62, s * 0.48)), K_RUST);
				b.put(cyl(0.13, 0.13, 0.5, 10), T3(Vector3(-3.33, 1.42, s * 0.48)), K_PAINT);
				// решётки вентиляторов на моторной палубе
				b.put(cyl(0.28, 0.28, 0.04, 16), T3(Vector3(-2.55, 1.89, s * 0.52)), K_SLIT);
				for (int k = 0; k < 4; k++) {
					b.put(box(Vector3(0.54, 0.04, 0.05)), T3(Vector3(-2.55, 1.91, s * 0.52 - 0.18 + k * 0.12)), K_STEEL, true);
				}
				b.put(box(Vector3(0.75, 0.04, 0.5)), T3(Vector3(-1.7, 1.89, s * 0.55)), K_SLIT, true);
				// буксирный трос вдоль наклонного борта
				auto rope = cyl_x(0.03, 0.03, 4.6, 6);
				b.put(rope.p0, T3(Vector3(-0.4, th + 0.22, s * (up_w / 2 - 0.22 * side_k + 0.04)), rope.p1), K_ROPE);
			}
			// домкрат и ящик ЗИП на корме
			b.put(cyl(0.09, 0.09, 0.6, 10), T3(Vector3(-3.4, 1.0, -0.95), Vector3(PI_D / 2, 0, 0)), K_STEEL);
			b.put(box(Vector3(0.25, 0.3, 0.7)), T3(Vector3(-3.32, 1.05, 0.95)), K_PAINT, true);
			b.put(cyl(0.012, 0.012, 2.0, 4), T3(Vector3(-2.9, 2.88, -0.9)), K_STEEL);
		}
		else if (key == KEY_PZ3) {
			// смотровой прибор механика и шаровая установка пулемёта в лобовом листе рубки
			b.put(box(Vector3(0.1, 0.12, 0.34)), T3(Vector3(1.64, 1.52, -0.55)), K_PAINT, true);
			b.put(box(Vector3(0.03, 0.03, 0.24)), T3(Vector3(1.7, 1.52, -0.55)), K_SLIT, true);
			b.put(sph(12, 8), T3(Vector3(1.62, 1.5, 0.55), Vector3(0, 0, 0), Vector3(0.26, 0.26, 0.26)), K_PAINT);
			auto mg = cyl_x(0.022, 0.022, 0.3, 6);
			b.put(mg.p0, T3(Vector3(1.8, 1.5, 0.55), mg.p1), K_STEEL);
			// люки доступа к тормозам и запасные траки на носу
			auto e = on_edge(prof, 3, 0.5);
			auto p = e.p0;
			for (double s : { 1.0, -1.0 }) {
				b.put(box(Vector3(0.42, 0.05, 0.62)), T3(Vector3(p.x, p.y + 0.03, s * 0.5), Vector3(0, 0, e.p1)), K_PAINT, true);
				b.put(box(Vector3(0.16, 0.12, 0.08)), T3(Vector3(2.78, 0.7, s * 0.85)), K_STEEL, true);
				b.put(box(Vector3(0.16, 0.12, 0.08)), T3(Vector3(-2.82, 0.7, s * 0.85)), K_STEEL, true);
			}
			auto ek = on_edge(prof, 4, 0.5);
			auto pk = ek.p0;
			for (double z : { -0.75, -0.38, 0.0, 0.38, 0.75 }) {
				b.put(box(Vector3(0.05, 0.13, 0.34)), T3(Vector3(pk.x + 0.03, pk.y, z), Vector3(0, 0, ek.p1 + PI_D / 2)), K_STEEL, true);
			}
			// фара «Нотек», глушитель поперёк кормы, антенна
			b.put(box(Vector3(0.14, 0.1, 0.12)), T3(Vector3(2.4, th + 0.12, -1.25)), K_PAINT, true);
			b.put(cyl(0.16, 0.16, 1.5, 12), T3(Vector3(-2.94, 1.0, 0), Vector3(PI_D / 2, 0, 0)), K_RUST);
			b.put(cyl(0.012, 0.012, 2.0, 4), T3(Vector3(-2.4, 2.62, 1.15)), K_STEEL);
			// решётки и люки моторного отделения, инструмент на полках
			b.put(box(Vector3(0.9, 0.04, 1.6)), T3(Vector3(-2.15, 1.63, 0)), K_SLIT, true);
			for (int k = 0; k < 8; k++) {
				b.put(box(Vector3(0.9, 0.05, 0.07)), T3(Vector3(-2.15, 1.65, -0.7 + k * 0.2)), K_PAINT, true);
			}
			for (double s : { 1.0, -1.0 }) {
				b.put(box(Vector3(0.6, 0.05, 0.55)), T3(Vector3(-1.35, 1.64, s * 0.45)), K_PAINT, true);
			}
			b.put(box(Vector3(1.4, 0.06, 0.12)), T3(Vector3(-0.6, th + 0.1, 1.3)), K_WOOD, true);
			b.put(box(Vector3(0.8, 0.1, 0.14)), T3(Vector3(-1.7, th + 0.1, -1.3)), K_STEEL, true);
			if (skirts) {
				skirts_(b, W, -2.1, 5, 0.94, 1.3);
			}
		}
		else if (key == KEY_CRUSADER) {
			// выступающая рубка механика-водителя справа
			auto e = on_edge(prof, 2, 0.32);
			auto p = e.p0;
			b.put(box(Vector3(0.62, 0.28, 0.64)), T3(Vector3(p.x - 0.05, p.y + 0.12, 0.6)), K_PAINT, true);
			b.put(box(Vector3(0.04, 0.05, 0.38)), T3(Vector3(p.x + 0.27, p.y + 0.18, 0.6)), K_SLIT, true);
			b.put(box(Vector3(0.3, 0.04, 0.4)), T3(Vector3(p.x - 0.1, p.y + 0.28, 0.6)), K_PAINT, true);
			for (double s : { 1.0, -1.0 }) {
				// фары и буксирные серьги
				b.put(cyl(0.08, 0.09, 0.14, 10), T3(Vector3(2.75, 1.12, s * 1.05), Vector3(0, 0, -PI_D / 2)), K_GLASS);
				b.put(box(Vector3(0.16, 0.14, 0.08)), T3(Vector3(3.0, 0.62, s * 0.8)), K_STEEL, true);
				// песочные экраны над гусеницами
				b.put(box(Vector3(L * 0.92, 0.32, 0.03)), T3(Vector3(-0.05, th - 0.08, s * (W / 2 + 0.02))), K_PAINT, true);
				// выхлопная труба вдоль кормы
				auto ex = cyl_x(0.07, 0.07, 0.5, 8);
				b.put(ex.p0, T3(Vector3(-3.05, 1.12, s * 0.75), ex.p1), K_RUST);
			}
			// большие жалюзи моторного отделения и канистры на корме
			b.put(box(Vector3(2.0, 0.04, 1.8)), T3(Vector3(-1.75, 1.41, 0)), K_SLIT, true);
			for (int k = 0; k < 10; k++) {
				b.put(box(Vector3(2.0, 0.05, 0.07)), T3(Vector3(-1.75, 1.43, -0.81 + k * 0.18)), K_PAINT, true);
			}
			for (int k = 0; k < 4; k++) {
				b.put(box(Vector3(0.14, 0.34, 0.24)), T3(Vector3(-3.07, 0.95, -0.4 + k * 0.27)), K_OLIVE, true);
			}
			b.put(box(Vector3(1.4, 0.06, 0.12)), T3(Vector3(-0.4, 1.44, -1.15)), K_WOOD, true);
		}
		else if (key == KEY_CROMWELL) {
			// лобовой лист: смотровой лючок механика справа, курсовой «Беза» слева
			b.put(box(Vector3(0.08, 0.16, 0.42)), T3(Vector3(3.17, 1.3, 0.62)), K_PAINT, true);
			b.put(box(Vector3(0.03, 0.04, 0.3)), T3(Vector3(3.22, 1.32, 0.62)), K_SLIT, true);
			b.put(sph(12, 8), T3(Vector3(3.15, 1.25, -0.6), Vector3(0, 0, 0), Vector3(0.24, 0.24, 0.24)), K_PAINT);
			auto mg = cyl_x(0.022, 0.022, 0.3, 6);
			b.put(mg.p0, T3(Vector3(3.32, 1.25, -0.6), mg.p1), K_STEEL);
			for (double s : { 1.0, -1.0 }) {
				// фары, буксирные серьги, выносные бортовые листы над подвеской
				b.put(cyl(0.08, 0.09, 0.14, 10), T3(Vector3(3.2, 1.5, s * 1.1), Vector3(0, 0, -PI_D / 2)), K_GLASS);
				b.put(box(Vector3(0.16, 0.14, 0.08)), T3(Vector3(3.12, 0.62, s * 0.85)), K_STEEL, true);
				b.put(box(Vector3(L * 0.93, 0.42, 0.03)), T3(Vector3(-0.05, th - 0.1, s * (W / 2 + 0.02))), K_PAINT, true);
				// ящики ЗИП на крыльях
				b.put(box(Vector3(0.9, 0.3, 0.2)), T3(Vector3(-1.9, th + 0.25, s * (W / 2 - 0.08))), K_PAINT, true);
			}
			// жалюзи моторного отделения и выхлоп «рыбий хвост» на корме
			b.put(box(Vector3(2.2, 0.04, 1.9)), T3(Vector3(-1.9, 1.54, 0)), K_SLIT, true);
			for (int k = 0; k < 11; k++) {
				b.put(box(Vector3(2.2, 0.05, 0.07)), T3(Vector3(-1.9, 1.56, -0.86 + k * 0.172)), K_PAINT, true);
			}
			b.put(box(Vector3(0.22, 0.3, 1.4)), T3(Vector3(-3.27, 1.25, 0)), K_PAINT, true);
			b.put(box(Vector3(0.05, 0.12, 1.3)), T3(Vector3(-3.39, 1.2, 0)), K_RUST, true);
		}
		else if (key == KEY_TIGER2) {
			// перископ механика, шаровая установка пулемёта на лобовом листе
			auto e = on_edge(prof, 2, 0.12);
			auto p = e.p0;
			b.put(box(Vector3(0.16, 0.12, 0.3)), T3(Vector3(p.x - 0.1, p.y + 0.06, -0.7)), K_PAINT, true);
			auto e2 = on_edge(prof, 2, 0.32);
			auto p2 = e2.p0;
			b.put(sph(12, 8), T3(Vector3(p2.x, p2.y, 0.7), Vector3(0, 0, 0), Vector3(0.3, 0.3, 0.3)), K_PAINT);
			auto mg = cyl_x(0.025, 0.025, 0.35, 6);
			b.put(mg.p0, T3(Vector3(p2.x + 0.22, p2.y - 0.1, 0.7), mg.p1 + Vector3(0, 0, -0.5)), K_STEEL);
			b.put(cyl(0.1, 0.12, 0.2, 10), T3(Vector3(p.x, p.y + 0.18, -1.2), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			for (double s : { 1.0, -1.0 }) {
				// буксирные серьги, выхлопные трубы, вентиляторы, тросы вдоль наклонных бортов
				b.put(box(Vector3(0.24, 0.26, 0.1)), T3(Vector3(3.55, 0.95, s * 1.2)), K_STEEL, true);
				b.put(cyl(0.09, 0.09, 0.9, 10), T3(Vector3(-3.72, 1.72, s * 0.5)), K_RUST);
				b.put(cyl(0.14, 0.14, 0.55, 10), T3(Vector3(-3.68, 1.52, s * 0.5)), K_PAINT);
				b.put(cyl(0.3, 0.3, 0.04, 16), T3(Vector3(-2.8, 2.01, s * 0.6)), K_SLIT);
				for (int k = 0; k < 4; k++) {
					b.put(box(Vector3(0.58, 0.04, 0.05)), T3(Vector3(-2.8, 2.03, s * 0.6 - 0.2 + k * 0.13)), K_STEEL, true);
				}
				b.put(box(Vector3(0.8, 0.04, 0.55)), T3(Vector3(-1.85, 2.01, s * 0.6)), K_SLIT, true);
				auto rope = cyl_x(0.03, 0.03, 5.0, 6);
				b.put(rope.p0, T3(Vector3(-0.3, th + 0.3, s * (up_w / 2 - 0.3 * side_k + 0.04)), rope.p1), K_ROPE);
			}
			b.put(cyl(0.012, 0.012, 2.0, 4), T3(Vector3(-3.0, 3.0, 1.0)), K_STEEL);
			if (skirts) {
				skirts_(b, W, -3.1, 7, 0.95, th + 0.05, 0.42);
			}
		}
		else if (key == KEY_STUG) {
			// люки доступа к тормозам на верхнем лобовом листе
			auto e = on_edge(prof, 2, 0.5);
			auto p = e.p0;
			for (double s : { 1.0, -1.0 }) {
				b.put(box(Vector3(0.4, 0.05, 0.6)), T3(Vector3(p.x, p.y + 0.03, s * 0.5), Vector3(0, 0, e.p1)), K_PAINT, true);
				b.put(box(Vector3(0.16, 0.12, 0.08)), T3(Vector3(2.72, 0.7, s * 0.85)), K_STEEL, true);
				b.put(box(Vector3(0.16, 0.12, 0.08)), T3(Vector3(-2.78, 0.7, s * 0.85)), K_STEEL, true);
			}
			// фара «Нотек» на левой полке, запасные траки на носу
			b.put(box(Vector3(0.14, 0.1, 0.12)), T3(Vector3(2.4, th + 0.12, -1.25)), K_PAINT, true);
			b.put(box(Vector3(0.02, 0.04, 0.08)), T3(Vector3(2.48, th + 0.12, -1.25)), K_GLASS, true);
			for (int k = 0; k < 2; k++) {
				auto ek = on_edge(prof, 3, 0.3 + k * 0.4);
				auto pk = ek.p0;
				for (double z : { -0.75, -0.38, 0.38, 0.75 }) {
					b.put(box(Vector3(0.05, 0.13, 0.34)), T3(Vector3(pk.x + 0.03, pk.y, z), Vector3(0, 0, ek.p1 + PI_D / 2)), K_STEEL, true);
				}
			}
			// глушитель поперёк кормы
			b.put(cyl(0.16, 0.16, 1.5, 12), T3(Vector3(-2.9, 1.0, 0), Vector3(PI_D / 2, 0, 0)), K_RUST);
			// решётки и люки моторного отделения
			b.put(box(Vector3(0.9, 0.04, 1.6)), T3(Vector3(-2.15, 1.41, 0)), K_SLIT, true);
			for (int k = 0; k < 8; k++) {
				b.put(box(Vector3(0.9, 0.05, 0.07)), T3(Vector3(-2.15, 1.43, -0.7 + k * 0.2)), K_PAINT, true);
			}
			for (double s : { 1.0, -1.0 }) {
				b.put(box(Vector3(0.6, 0.05, 0.55)), T3(Vector3(-1.38, 1.42, s * 0.45)), K_PAINT, true);
			}
			// инструмент и домкрат на полках
			b.put(box(Vector3(1.4, 0.06, 0.12)), T3(Vector3(-0.6, th + 0.1, 1.3)), K_WOOD, true);
			b.put(box(Vector3(0.8, 0.1, 0.14)), T3(Vector3(-1.7, th + 0.1, -1.3)), K_STEEL, true);
			if (skirts) {
				skirts_(b, W, -2.1, 5, 0.94, 1.3);
			}
		}
	}
}

// Маска орудия: front — лоб башни (у рубки 0 — ось качания), gy — высота оси орудия
void mantlet(TB &b, const Spec &S, double front, double gy) {
	// match S.mant
	{
		if (S.mant == MANT_CAST) {
			b.put(sph(16, 10), T3(Vector3(front * 0.9, gy, 0), Vector3(0, 0, 0), Vector3(0.5, 0.6, 0.95)), K_PAINT);
			b.put(box(Vector3(0.4, 0.5, 0.82)), T3(Vector3(front * 0.82, gy, 0)), K_PAINT);
		}
		else if (S.mant == MANT_CAST_BIG) {
			b.put(sph(16, 10), T3(Vector3(front * 0.92, gy, 0), Vector3(0, 0, 0), Vector3(0.62, 0.66, 1.15)), K_PAINT);
			b.put(box(Vector3(0.5, 0.58, 1.0)), T3(Vector3(front * 0.82, gy, 0)), K_PAINT);
		}
		else if (S.mant == MANT_PLATE) {
			b.put(box(Vector3(0.26, 0.78, 1.55)), T3(Vector3(front + 0.12, gy, 0)), K_PAINT, true);
			b.put(cyl(0.18, 0.18, 0.4, 12), T3(Vector3(front + 0.4, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			// смотровой прибор и спаренный пулемёт в маске
			b.put(box(Vector3(0.06, 0.06, 0.08)), T3(Vector3(front + 0.26, gy + 0.13, -0.35)), K_SLIT, true);
			b.put(box(Vector3(0.06, 0.06, 0.08)), T3(Vector3(front + 0.26, gy - 0.06, 0.38)), K_SLIT, true);
		}
		else if (S.mant == MANT_BOX) {
			b.put(box(Vector3(0.3, 0.48, 0.62)), T3(Vector3(front + 0.1, gy, 0)), K_PAINT, true);
			b.put(cyl(0.13, 0.15, 0.35, 12), T3(Vector3(front + 0.35, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
		}
		else if (S.mant == MANT_ROUNDED) {
			b.put(sph(16, 10), T3(Vector3(front * 0.92, gy, 0), Vector3(0, 0, 0), Vector3(0.4, 0.5, 0.8)), K_PAINT);
		}
		else if (S.mant == MANT_BOX_SPACED) {
			// маска Pz III L с навесным 20-мм экраном
			b.put(box(Vector3(0.24, 0.44, 0.66)), T3(Vector3(front + 0.06, gy, 0)), K_PAINT, true);
			b.put(box(Vector3(0.04, 0.42, 0.72)), T3(Vector3(front + 0.26, gy, 0)), K_PAINT, true);
			b.put(cyl(0.1, 0.12, 0.28, 12), T3(Vector3(front + 0.38, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			b.put(box(Vector3(0.04, 0.05, 0.05)), T3(Vector3(front + 0.29, gy + 0.02, 0.22)), K_SLIT, true);
		}
		else if (S.mant == MANT_6PDR) {
			// плоская маска 6-фунтовки с прорезями прицела и пулемёта «Беза»
			b.put(box(Vector3(0.14, 0.34, 0.62)), T3(Vector3(front + 0.02, gy, 0)), K_PAINT, true);
			b.put(cyl(0.08, 0.1, 0.3, 12), T3(Vector3(front + 0.22, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			b.put(box(Vector3(0.04, 0.05, 0.05)), T3(Vector3(front + 0.1, gy + 0.03, -0.2)), K_SLIT, true);
			b.put(cyl(0.025, 0.025, 0.25, 6), T3(Vector3(front + 0.2, gy - 0.02, 0.2), Vector3(0, 0, -PI_D / 2)), K_STEEL);
		}
		else if (S.mant == MANT_F34) {
			// литая бронировка пушки Ф-34: короб с округлым лбом и муфта ствола
			b.put(box(Vector3(0.42, 0.42, 0.56)), T3(Vector3(front + 0.06, gy, 0)), K_PAINT, true);
			b.put(cyl(0.21, 0.21, 0.56, 14), T3(Vector3(front + 0.26, gy, 0), Vector3(PI_D / 2, 0, 0)), K_PAINT);
			b.put(cyl(0.11, 0.13, 0.32, 12), T3(Vector3(front + 0.5, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			b.put(box(Vector3(0.04, 0.05, 0.05)), T3(Vector3(front + 0.45, gy + 0.02, 0.2)), K_SLIT, true);
		}
		else if (S.mant == MANT_KV) {
			// маска ЗиС-5: скошенный короб и толстая муфта
			b.put(box(Vector3(0.36, 0.5, 0.7)), T3(Vector3(front + 0.04, gy, 0)), K_PAINT, true);
			b.put(box(Vector3(0.22, 0.36, 0.5)), T3(Vector3(front + 0.28, gy, 0)), K_PAINT, true);
			b.put(cyl(0.12, 0.14, 0.36, 12), T3(Vector3(front + 0.5, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			b.put(box(Vector3(0.04, 0.05, 0.05)), T3(Vector3(front + 0.4, gy + 0.04, 0.2)), K_SLIT, true);
		}
		else if (S.mant == MANT_ROTOR) {
			// установка M34: узкий ротор с прицелом и спаренным пулемётом
			b.put(box(Vector3(0.16, 0.42, 0.74)), T3(Vector3(front + 0.02, gy, 0)), K_PAINT, true);
			b.put(cyl(0.19, 0.19, 0.66, 16), T3(Vector3(front + 0.1, gy, 0), Vector3(PI_D / 2, 0, 0)), K_PAINT);
			b.put(cyl(0.1, 0.11, 0.3, 12), T3(Vector3(front + 0.4, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			b.put(box(Vector3(0.05, 0.05, 0.05)), T3(Vector3(front + 0.33, gy, 0.22)), K_SLIT, true);
			b.put(box(Vector3(0.05, 0.05, 0.05)), T3(Vector3(front + 0.33, gy + 0.05, -0.24)), K_SLIT, true);
		}
		else if (S.mant == MANT_BELL) {
			// литая скруглённая маска «Пантеры» и прорези бинокулярного прицела
			b.put(cyl(0.38, 0.38, 0.96, 18), T3(Vector3(front - 0.02, gy, 0), Vector3(PI_D / 2, 0, 0)), K_PAINT);
			b.put(cyl(0.13, 0.15, 0.42, 12), T3(Vector3(front + 0.5, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			for (double z : { -0.3, -0.38 }) {
				b.put(box(Vector3(0.05, 0.05, 0.04)), T3(Vector3(front + 0.35, gy + 0.12, z)), K_SLIT, true);
			}
			b.put(box(Vector3(0.05, 0.05, 0.05)), T3(Vector3(front + 0.35, gy + 0.05, 0.3)), K_SLIT, true);
		}
		else if (S.mant == MANT_SAUKOPF_BIG) {
			// литая маска «свиное рыло» башни «Хеншель»
			b.put(sph(16, 10), T3(Vector3(front + 0.04, gy, 0), Vector3(0, 0, 0), Vector3(0.6, 0.56, 0.66)), K_PAINT);
			b.put(cyl(0.15, 0.3, 0.5, 14), T3(Vector3(front + 0.4, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
			b.put(box(Vector3(0.05, 0.05, 0.05)), T3(Vector3(front + 0.3, gy + 0.1, 0.3)), K_SLIT, true);
		}
		else if (S.mant == MANT_SAUKOPF) {
			// литая маска «свиное рыло» на штурмовом орудии
			b.put(sph(16, 10), T3(Vector3(front + 0.06, gy, 0), Vector3(0, 0, 0), Vector3(0.56, 0.44, 0.52)), K_PAINT);
			b.put(cyl(0.12, 0.24, 0.42, 14), T3(Vector3(front + 0.36, gy, 0), Vector3(0, 0, -PI_D / 2)), K_PAINT);
		}
	}
}

void turret_details(TB &b, const Spec &S, double front, double h, bool skirts, int year) {
	int key = S.key;
	double hw = S.tp_hw, back = S.tp_b, top = S.tur_top;
	// командирская башенка со смотровыми щелями и открытым люком
	double cx = 0.0, cz = 0.0, ch = 0.0;
	if (S.cupola.size() >= 4) {
		cx = S.cupola[0];
		cz = S.cupola[1];
		double cr = S.cupola[2];
		ch = S.cupola[3];
		b.put(cyl(cr, cr * 1.05, ch, 16), T3(Vector3(cx, h * top + ch / 2 - 0.02, cz)), K_PAINT);
		b.put(cyl(cr * 1.01, cr * 1.01, 0.05, 16), T3(Vector3(cx, h * top + ch * 0.55, cz)), K_SLIT);
		b.put(cyl(cr * 0.88, cr * 0.92, 0.07, 16), T3(Vector3(cx, h * top + ch + 0.01, cz)), K_PAINT);
		b.put(box(Vector3(0.1, 0.05, 0.04)), T3(Vector3(cx + cr * 0.4, h * top + ch + 0.06, cz)), K_STEEL, true);
	}
	// люк заряжающего
	if (S.hatch) {
		b.put(box(Vector3(0.5, 0.05, 0.45)), T3(Vector3(-0.1, h * top + 0.02, cz != 0.0 ? -cz * 0.9 : 0.4)), K_PAINT, true);
	}
	// match key
	{
		if (key == KEY_T34) {
			for (double s : { 1.0, -1.0 }) {
				// поручни и перископы
				auto rail = cyl_x(0.02, 0.02, 1.1, 6);
				b.put(rail.p0, T3(Vector3(-0.35, h * 0.7, s * (hw * 0.93 + 0.04)), rail.p1), K_STEEL);
				b.put(box(Vector3(0.12, 0.1, 0.1)), T3(Vector3(0.25, h * top + 0.05, s * 0.45)), K_PAINT, true);
			}
			// грибки вентиляторов
			for (double z : { -0.25, 0.25 }) {
				b.put(sph(12, 6), T3(Vector3(-1.05, h * top, z), Vector3(0, 0, 0), Vector3(0.32, 0.18, 0.32)), K_PAINT);
			}
		}
		else if (key == KEY_TIGER) {
			for (double s : { 1.0, -1.0 }) {
				// дымовые мортирки по три на борт
				for (int k = 0; k < 3; k++) {
					b.put(cyl(0.05, 0.05, 0.22, 8), T3(Vector3(front * 0.55 - k * 0.12, h * 0.78, s * (hw + 0.05)), Vector3(s * 0.7, 0, 0)), K_PAINT);
				}
				// запасные траки на бортах башни
				for (int k = 0; k < 3; k++) {
					b.put(box(Vector3(0.16, 0.36, 0.035)), T3(Vector3(-0.25 - k * 0.2, h * 0.42, s * (hw + 0.02))), K_STEEL, true);
				}
			}
			// ящик «Роммеля» на корме башни
			b.put(box(Vector3(0.5, 0.45, 1.2)), T3(Vector3(-back - 0.18, h * 0.5, 0)), K_PAINT, true);
		}
		else if (key == KEY_IS2) {
			// ДШК на командирской башенке, кормовой пулемёт, поручни
			auto dshk = cyl_x(0.03, 0.03, 1.4, 6);
			b.put(dshk.p0, T3(Vector3(cx + 0.6, h * top + ch + 0.35, cz), dshk.p1 + Vector3(0, 0, 0.1)), K_STEEL);
			b.put(box(Vector3(0.2, 0.18, 0.12)), T3(Vector3(cx, h * top + ch + 0.25, cz)), K_STEEL, true);
			b.put(sph(12, 8), T3(Vector3(-back * 0.98, h * 0.48, 0), Vector3(0, 0, 0), Vector3(0.28, 0.28, 0.28)), K_PAINT);
			for (double s : { 1.0, -1.0 }) {
				auto rail = cyl_x(0.02, 0.02, 1.3, 6);
				b.put(rail.p0, T3(Vector3(-0.3, h * 0.72, s * (hw * 0.86 + 0.05)), rail.p1), K_STEEL);
			}
		}
		else if (key == KEY_PZ4) {
			// экраны вокруг башни (с весны 1943 г.)
			for (double s : { 1.0, -1.0 }) {
				if (skirts) {
					b.put(box(Vector3(1.55, 0.66, 0.03)), T3(Vector3(-0.35, h * 0.5, s * (hw + 0.24)), Vector3(0, 0, 0)), K_PAINT, true);
					b.put(box(Vector3(0.12, 0.04, 0.24)), T3(Vector3(-0.35, h * 0.75, s * (hw + 0.12))), K_STEEL, true);
				}
				// бортовые люки башни
				b.put(box(Vector3(0.45, 0.4, 0.05)), T3(Vector3(-0.1, h * 0.45, s * 0.84)), K_PAINT, true);
			}
			if (skirts) {
				b.put(box(Vector3(0.03, 0.66, 1.9)), T3(Vector3(-1.52, h * 0.5, 0)), K_PAINT, true);
			}
		}
		else if (key == KEY_T34_76) {
			// два круглых люка, перископы, поручни, лючки для стрельбы из личного оружия
			for (double s : { 1.0, -1.0 }) {
				b.put(cyl(0.26, 0.27, 0.06, 16), T3(Vector3(-0.42, h * top + 0.03, s * 0.36)), K_PAINT);
				b.put(box(Vector3(0.06, 0.04, 0.12)), T3(Vector3(-0.2, h * top + 0.07, s * 0.36)), K_STEEL, true);
				b.put(box(Vector3(0.12, 0.1, 0.1)), T3(Vector3(0.22, h * top + 0.05, s * 0.36)), K_PAINT, true);
				auto rail = cyl_x(0.02, 0.02, 0.9, 6);
				b.put(rail.p0, T3(Vector3(-0.3, h * 0.62, s * (side_at(hw, top, 0.62) + 0.05)), rail.p1), K_STEEL);
				b.put(cyl(0.05, 0.05, 0.05, 8), T3(Vector3(-0.7, h * 0.45, s * side_at(hw, top, 0.45)), Vector3(PI_D / 2, 0, 0)), K_STEEL);
			}
			b.put(sph(12, 6), T3(Vector3(0.42, h * top, 0), Vector3(0, 0, 0), Vector3(0.28, 0.14, 0.28)), K_PAINT);
		}
		else if (key == KEY_KV1) {
			// пулемёт ДТ в корме башни, большой люк, перископы, смотровые щели, антенна
			b.put(sph(12, 8), T3(Vector3(-back * side_at(1.0, top, 0.45), h * 0.45, 0), Vector3(0, 0, 0), Vector3(0.26, 0.26, 0.26)), K_PAINT);
			auto dt = cyl_x(0.02, 0.02, 0.3, 6);
			b.put(dt.p0, T3(Vector3(-back * side_at(1.0, top, 0.45) - 0.14, h * 0.45, 0), dt.p1), K_STEEL);
			b.put(cyl(0.36, 0.38, 0.06, 18), T3(Vector3(-0.25, h * top + 0.03, 0)), K_PAINT);
			b.put(box(Vector3(0.06, 0.05, 0.4)), T3(Vector3(-0.25, h * top + 0.08, 0)), K_STEEL, true);
			b.put(box(Vector3(0.14, 0.14, 0.1)), T3(Vector3(0.3, h * top + 0.07, -0.42)), K_PAINT, true);
			b.put(box(Vector3(0.1, 0.1, 0.08)), T3(Vector3(0.15, h * top + 0.05, 0.48)), K_PAINT, true);
			for (double s : { 1.0, -1.0 }) {
				auto rail = cyl_x(0.02, 0.02, 1.1, 6);
				b.put(rail.p0, T3(Vector3(-0.3, h * 0.66, s * (side_at(hw, top, 0.66) + 0.04)), rail.p1), K_STEEL);
				b.put(box(Vector3(0.18, 0.04, 0.04)), T3(Vector3(0.25, h * 0.68, s * side_at(hw * 0.97, top, 0.68))), K_SLIT, true);
			}
			b.put(cyl(0.012, 0.012, 1.8, 4), T3(Vector3(-0.75, h * top + 0.9, 0.55)), K_STEEL);
		}
		else if (key == KEY_SHERMAN || key == KEY_FIREFLY) {
			if (key == KEY_FIREFLY) {
				// короб радиостанции на корме башни: место внутри заняла казённая часть 17-фунтовки
				b.put(box(Vector3(0.5, 0.42, 0.9)), T3(Vector3(-back * side_at(1.0, top, 0.45) - 0.18, h * 0.45, 0)), K_PAINT, true);
			}
			// раздвижной люк командира, «Браунинг» калибра .50 на турели, перископы, антенна
			b.put(cyl(0.3, 0.32, 0.07, 16), T3(Vector3(-0.35, h * top + 0.03, 0.36)), K_PAINT);
			b.put(box(Vector3(0.04, 0.05, 0.56)), T3(Vector3(-0.35, h * top + 0.08, 0.36)), K_STEEL, true);
			auto m2 = cyl_x(0.03, 0.03, 1.5, 6);
			b.put(m2.p0, T3(Vector3(-0.15, h * top + 0.45, 0.36), m2.p1 + Vector3(0, 0, 0.06)), K_STEEL);
			b.put(box(Vector3(0.3, 0.15, 0.12)), T3(Vector3(-0.55, h * top + 0.42, 0.36)), K_STEEL, true);
			b.put(cyl(0.03, 0.03, 0.38, 6), T3(Vector3(-0.55, h * top + 0.2, 0.36)), K_STEEL);
			for (double z : { -0.4, 0.12 }) {
				b.put(box(Vector3(0.12, 0.1, 0.1)), T3(Vector3(0.35, h * top + 0.05, z)), K_PAINT, true);
			}
			auto px = -0.5;
			auto pz = hw * sqrt(1.0 - pow(px / back, 2.0)) * side_at(1.0, top, 0.5);
			b.put(cyl(0.08, 0.08, 0.05, 10), T3(Vector3(px, h * 0.5, -pz), Vector3(PI_D / 2, 0, 0)), K_STEEL);
			b.put(cyl(0.012, 0.012, 2.2, 4), T3(Vector3(-0.95, h * top + 1.1, -0.3)), K_STEEL);
		}
		else if (key == KEY_PANTHER) {
			// дымовые мортирки по три на борт (только Ausf. D), лючки, люк в корме башни, вентилятор
			for (double s : { 1.0, -1.0 }) {
				for (int k = 0; k < (year < 1944 ? 3 : 0); k++) {
					auto x = front * 0.15 - k * 0.15;
					auto sw = lerpd(hw * 0.66, hw, clampd((front - x) / (front + back * 0.86), 0.0, 1.0));
					b.put(cyl(0.045, 0.045, 0.2, 8), T3(Vector3(x, h * 0.8, s * (side_at(sw, top, 0.8) + 0.05)), Vector3(s * 0.7, 0, 0)), K_PAINT);
				}
				auto sw2 = lerpd(hw * 0.66, hw, clampd((front + 0.7) / (front + back * 0.86), 0.0, 1.0));
				b.put(cyl(0.06, 0.06, 0.05, 8), T3(Vector3(-0.7, h * 0.45, s * side_at(sw2, top, 0.45)), Vector3(PI_D / 2, 0, 0)), K_STEEL);
			}
			b.put(cyl(0.3, 0.3, 0.06, 16), T3(Vector3(-back * side_at(1.0, top, 0.48) - 0.02, h * 0.48, 0), Vector3(0, 0, PI_D / 2)), K_PAINT);
			b.put(cyl(0.12, 0.12, 0.05, 10), T3(Vector3(0.3, h * top + 0.02, 0.1)), K_PAINT);
		}
		else if (key == KEY_STUG) {
			// смотровой прибор механика в лобовом листе рубки, ниша прицела, щит пулемёта
			b.put(box(Vector3(0.08, 0.12, 0.38)), T3(Vector3(front * side_at(1.0, top, 0.62) + 0.02, h * 0.62, -0.62)), K_PAINT, true);
			b.put(box(Vector3(0.03, 0.03, 0.28)), T3(Vector3(front * side_at(1.0, top, 0.62) + 0.06, h * 0.62, -0.62)), K_SLIT, true);
			b.put(box(Vector3(0.3, 0.12, 0.22)), T3(Vector3(front * 0.55, h * top + 0.05, -0.3)), K_PAINT, true);
			b.put(box(Vector3(0.04, 0.32, 0.5)), T3(Vector3(0.05, h * top + 0.17, 0.5)), K_PAINT, true);
			auto mg = cyl_x(0.02, 0.02, 0.8, 6);
			b.put(mg.p0, T3(Vector3(0.35, h * top + 0.25, 0.5), mg.p1), K_STEEL);
			b.put(box(Vector3(0.55, 0.05, 0.45)), T3(Vector3(-0.5, h * top + 0.02, 0.5)), K_PAINT, true);
			// стереотруба командира и антенна
			for (double s : { 1.0, -1.0 }) {
				b.put(cyl(0.02, 0.02, 0.4, 6), T3(Vector3(cx + 0.1, h * top + ch + 0.2, cz + s * 0.07)), K_STEEL);
			}
			b.put(cyl(0.012, 0.012, 2.0, 4), T3(Vector3(-back * 0.8, h * top + 1.0, 0.85)), K_STEEL);
			// ящик ЗИП на корме рубки
			b.put(box(Vector3(0.22, 0.3, 0.9)), T3(Vector3(-back * side_at(1.0, top, 0.45) - 0.1, h * 0.45, 0)), K_PAINT, true);
		}
		else if (key == KEY_PZ3) {
			for (double s : { 1.0, -1.0 }) {
				// бортовые люки и смотровые щели
				b.put(box(Vector3(0.42, 0.4, 0.05)), T3(Vector3(-0.15, h * 0.45, s * side_at(hw * 0.97, top, 0.45))), K_PAINT, true);
				b.put(box(Vector3(0.16, 0.03, 0.04)), T3(Vector3(0.25, h * 0.62, s * side_at(hw * 0.99, top, 0.62))), K_SLIT, true);
				if (skirts) {
					b.put(box(Vector3(1.4, 0.6, 0.03)), T3(Vector3(-0.35, h * 0.5, s * (hw + 0.22))), K_PAINT, true);
					b.put(box(Vector3(0.12, 0.04, 0.22)), T3(Vector3(-0.35, h * 0.75, s * (hw + 0.11))), K_STEEL, true);
				}
			}
			// ящик «Роммеля» на корме башни
			b.put(box(Vector3(0.42, 0.4, 1.1)), T3(Vector3(-back * 0.92 - 0.12, h * 0.5, 0)), K_PAINT, true);
		}
		else if (key == KEY_CRUSADER) {
			// два люка, перископы, бомбомёт, ящик на корме, антенна
			for (double s : { 1.0, -1.0 }) {
				b.put(box(Vector3(0.45, 0.04, 0.36)), T3(Vector3(-0.35, h * top + 0.02, s * 0.25)), K_PAINT, true);
				b.put(box(Vector3(0.1, 0.1, 0.1)), T3(Vector3(0.12, h * top + 0.05, s * 0.3)), K_PAINT, true);
			}
			b.put(cyl(0.05, 0.05, 0.35, 8), T3(Vector3(0.05, h * 0.75, side_at(hw, top, 0.75) + 0.08), Vector3(0.6, 0, 0)), K_STEEL);
			b.put(box(Vector3(0.3, 0.32, 1.0)), T3(Vector3(-back * side_at(1.0, top, 0.45) - 0.12, h * 0.45, 0)), K_PAINT, true);
			b.put(cyl(0.012, 0.012, 2.4, 4), T3(Vector3(-0.7, h * top + 1.2, -0.4)), K_STEEL);
		}
		else if (key == KEY_CROMWELL) {
			// навесные бортовые листы на болтах, бомбомёт, ящик на корме, антенны
			for (double s : { 1.0, -1.0 }) {
				b.put(box(Vector3(1.3, h * 0.8, 0.03)), T3(Vector3(-0.1, h * 0.45, s * (hw + 0.02))), K_PAINT, true);
				for (int k = 0; k < 4; k++) {
					for (int j = 0; j < 2; j++) {
						b.put(cyl(0.025, 0.025, 0.02, 6), T3(Vector3(-0.65 + k * 0.36, h * (0.2 + j * 0.5), s * (hw + 0.04)), Vector3(PI_D / 2, 0, 0)), K_STEEL);
					}
				}
			}
			b.put(cyl(0.05, 0.05, 0.3, 8), T3(Vector3(0.3, h * 0.85, hw + 0.08), Vector3(0.6, 0, 0)), K_STEEL);
			b.put(box(Vector3(0.3, 0.42, 1.5)), T3(Vector3(-back - 0.15, h * 0.5, 0)), K_PAINT, true);
			b.put(box(Vector3(0.5, 0.04, 0.42)), T3(Vector3(-0.3, h * top + 0.02, 0.42)), K_PAINT, true);
			for (double z : { -0.75, 0.75 }) {
				b.put(cyl(0.012, 0.012, 2.2, 4), T3(Vector3(-back + 0.15, h * top + 1.1, z)), K_STEEL);
			}
		}
		else if (key == KEY_TIGER2) {
			// запасные траки на бортах башни, люк в корме, пистолетные лючки, крышка вентилятора
			for (double s : { 1.0, -1.0 }) {
				for (int k = 0; k < 4; k++) {
					auto x = -0.35 - k * 0.24;
					auto sw = lerpd(hw * 0.66, hw, clampd((front - x) / (front + back * 0.86), 0.0, 1.0));
					b.put(box(Vector3(0.18, 0.4, 0.04)), T3(Vector3(x, h * 0.5, s * (side_at(sw, top, 0.5) + 0.03)), Vector3(s * 0.36, 0, 0)), K_STEEL, true);
				}
			}
			b.put(cyl(0.32, 0.32, 0.06, 16), T3(Vector3(-back * side_at(1.0, top, 0.5) - 0.02, h * 0.5, 0), Vector3(0, 0, PI_D / 2)), K_PAINT);
			b.put(cyl(0.14, 0.14, 0.05, 10), T3(Vector3(0.2, h * top + 0.02, 0.15)), K_PAINT);
			b.put(box(Vector3(0.5, 0.05, 0.45)), T3(Vector3(-0.3, h * top + 0.02, 0.5)), K_PAINT, true);
		}
		else if (key == KEY_CHAFFEE) {
			// крупнокалиберный пулемёт на турели в корме крыши
			auto m2 = cyl_x(0.03, 0.03, 1.5, 6);
			b.put(m2.p0, T3(Vector3(-0.55, h * top + 0.55, 0.35), m2.p1 + Vector3(0, 0, 0.08)), K_STEEL);
			b.put(box(Vector3(0.28, 0.15, 0.12)), T3(Vector3(-0.85, h * top + 0.48, 0.35)), K_STEEL, true);
			b.put(cyl(0.03, 0.03, 0.45, 6), T3(Vector3(-0.85, h * top + 0.22, 0.35)), K_STEEL);
			b.put(box(Vector3(0.12, 0.1, 0.12)), T3(Vector3(0.3, h * top + 0.05, 0.4)), K_PAINT, true);
		}
	}

}

// Треугольники группы без индексов (как Mesh.get_faces): форма для лучей попаданий
std::vector<V3> faces_of(const Group &g) {
	std::vector<V3> out;
	for (const Group::Part &p : g.parts) {
		for (int32_t i : p.idx) out.push_back(p.v[i]);
	}
	return out;
}

struct Built {
	TB hull, top, mant, gun;
	Group tracks;
	double roof = 0.0;
};

// TankModels.build: геометрия всех частей
void build(const Spec &S, Built &out) {
	SP = &S;
	TB &hb = out.hull;
	double L = S.L, W = S.W, tw = S.tw, th = S.th;
	// --- корпус: низ между гусеницами, верх над гусеницами с наклоном бортов
	const std::vector<V2> &prof = S.hull;
	double roof = 0.0;
	for (V2 p : prof) roof = std::max(roof, (double)p.y);
	out.roof = roof;
	auto band = [](double y0, double y1) {
		return std::vector<V2>{ { -99, (float)y0 }, { 99, (float)y0 }, { 99, (float)y1 }, { -99, (float)y1 } };
	};
	std::vector<V2> lower = intersect_polygons(prof, band(-1.0, th + 0.02));
	std::vector<V2> upper = intersect_polygons(prof, band(th - 0.04, 9.0));
	double side_k = std::tan(S.side_slope * (PI_D / 180.0));
	double up_w = S.up_w;
	if (!lower.empty()) hb.put(geo_loft(lower, 0.0, W - tw * 2.0 + 0.04, 9.0, W - tw * 2.0 + 0.04), T3(Vector3(0, 0, 0)), K_PAINT, true);
	if (!upper.empty()) hb.put(geo_loft(upper, th, up_w, roof, up_w - 2.0 * (roof - th) * side_k), T3(Vector3(0, 0, 0)), K_PAINT, true);

	// --- ходовая
	double wr = S.wr;
	double tz = W / 2 - tw / 2;
	std::vector<V2> belt_pts;
	for (double s : { 1.0, -1.0 }) {
		double z = s * tz;
		// катки
		for (size_t i = 0; i < S.wheels.size(); i++) {
			double x = S.wheels[i];
			double cy = wr + 0.04;
			switch (S.wheel) {
				case W_INTERLEAVED: {
					double zo = s * (i % 2 == 0 ? tw * 0.22 : -tw * 0.22);
					wheel_disc(hb, x, cy, z + zo, wr, tw * 0.3, s, false);
					break;
				}
				case W_SPOKED: wheel_spoked(hb, x, cy, z, wr, tw * 0.8, s); break;
				case W_SINGLE: wheel_disc(hb, x, cy, z, wr, tw * 0.72, s, false); break;
				case W_VVSS: wheel_disc(hb, x, cy, z, wr, tw * 0.5, s, true); break;
				default:
					wheel_disc(hb, x, cy, z + s * tw * 0.22, wr, tw * 0.3, s, true);
					wheel_disc(hb, x, cy, z - s * tw * 0.22, wr, tw * 0.3, s, true);
					break;
			}
			if (s > 0) {
				for (int k = 0; k < 10; k++) {
					double a = TAU_D * k / 10.0;
					belt_pts.push_back({ (float)(x + std::cos(a) * (wr + 0.02)), (float)(cy + std::sin(a) * (wr + 0.02)) });
				}
			}
		}
		// тележки блокированной подвески: корпус с пружиной, рычаги, ролик сверху
		for (double bx : S.bogies) {
			double by = wr + 0.04;
			hb.put(box(Vector3(0.5, 0.42, tw * 0.3)), T3(Vector3(bx, by + 0.2, z)), K_PAINT, true);
			hb.put(box(Vector3(0.34, 0.2, tw * 0.36)), T3(Vector3(bx, by + 0.42, z)), K_PAINT, true);
			hb.put(cyl(0.07, 0.07, 0.3, 8), T3(Vector3(bx, by + 0.15, z)), K_STEEL);
			for (double d : { -1.0, 1.0 }) {
				hb.put(box(Vector3(0.36, 0.09, tw * 0.62)), T3(Vector3(bx + d * 0.17, by + 0.04, z), Vector3(0, 0, d * 0.35)), K_STEEL, true);
			}
		}
		// звёздочка (с зубьями) и ленивец
		sprocket(hb, S.spr[0], S.spr[1], z, S.spr[2], tw * 0.7, s);
		wheel_disc(hb, S.idl[0], S.idl[1], z, S.idl[2], tw * 0.6, s, false);
		for (double x : S.rollers) {
			double ry = th - 0.12;
			hb.wheel(cyl(0.11, 0.11, tw * 0.5, 10), T3(Vector3(x, ry, z), Vector3(PI_D / 2, 0, 0)), K_RUBBER, x, ry, 0.11, s);
			if (s > 0) belt_pts.push_back({ (float)x, (float)(ry + 0.12) });
		}
		// надгусеничная полка
		if (S.shelf) hb.put(box(Vector3(L * 0.97, 0.03, tw + 0.08)), T3(Vector3(0, th + 0.05, s * (tz + 0.02))), K_PAINT, true);
	}
	for (const std::vector<double> *a : { &S.spr, &S.idl }) {
		for (int k = 0; k < 12; k++) {
			double ang = TAU_D * k / 12.0;
			belt_pts.push_back({ (float)((*a)[0] + std::cos(ang) * ((*a)[2] + 0.03)), (float)((*a)[1] + std::sin(ang) * ((*a)[2] + 0.03)) });
		}
	}
	std::vector<V2> outline = convex_hull(belt_pts);
	if (outline.size() > 1 && outline[0].x == outline.back().x && outline[0].y == outline.back().y) outline.pop_back();
	float u = (float)U;
	for (V2 &p : outline) p = { p.x * u, p.y * u };
	// обе ленты — одна сетка и один материал: сдвиг текстуры у каждой свой в шейдере (по знаку z)
	out.tracks = tracks(outline, tw * U, tz * U);

	// --- детали корпуса
	hull_details(hb, S, roof, S.skirts, S.year);

	// --- башня или рубка
	TB &tb = out.top;
	std::vector<V2> tpoly = turret_poly(S.tpk, S.tp_f, S.tp_b, S.tp_hw);
	double tur_h = S.tur_h, front = S.tp_f, hw = S.tp_hw;
	double gun_y = tur_h * (S.casemate ? 0.42 : 0.46);
	tb.put(geo_frustum(tpoly, tur_h, S.tur_top, 0.0, S.smooth), T3(Vector3(0, 0, 0)), K_PAINT, !S.smooth);
	turret_details(tb, S, front, tur_h, S.skirts, S.year);
	if (S.band && !S.casemate) {
		// Берлин, 1945: белая полоса вокруг башни и белый крест на крыше — опознавание с воздуха
		double yb = tur_h * 0.5;
		double k0 = 1.0 + (S.tur_top - 1.0) * yb / tur_h;
		double k1 = 1.0 + (S.tur_top - 1.0) * (yb + 0.13) / tur_h;
		std::vector<V2> bp;
		float fk0 = (float)k0, fk = 1.012f;
		for (V2 p : tpoly) bp.push_back({ p.x * fk0 * fk, p.y * fk0 * fk });
		tb.put(geo_frustum(bp, 0.13, k1 / k0, 0.0, S.smooth), T3(Vector3(0, yb, 0)), K_WHITE, !S.smooth);
		double rw = hw * S.tur_top * 0.75;
		tb.put(box(Vector3(rw * 2.0, 0.02, 0.16)), T3(Vector3(-0.15, tur_h + 0.012, 0)), K_WHITE, true);
		tb.put(box(Vector3(0.16, 0.02, rw * 2.0)), T3(Vector3(-0.15, tur_h + 0.012, 0)), K_WHITE, true);
	}
	if (S.casemate) {
		// рубка на корпусе, а маска с орудием качается в амбразуре лобового листа
		mantlet(out.mant, S, 0.0, 0.0);
	} else {
		mantlet(tb, S, front, gun_y);
	}

	// --- орудие на оси возвышения
	TB &gb = out.gun;
	double glen = S.gun_len, gr0 = S.gun_r0, gr1 = S.gun_r1;
	CX c = cyl_x(gr1, gr0, glen, 14);
	gb.put(c.p0, T3(Vector3(glen / 2, 0, 0), c.p1), K_PAINT);
	if (S.brake == BR_DOUBLE || S.brake == BR_DOUBLE_BIG) {
		double big = S.brake == BR_DOUBLE_BIG ? 1.25 : 1.0;
		double r = gr1 * 1.9 * big;
		double bl = 0.5 * big;
		CX cb = cyl_x(r, r, bl, 14);
		gb.put(cb.p0, T3(Vector3(glen + bl / 2 - 0.05, 0, 0), cb.p1), K_PAINT);
		gb.put(box(Vector3(0.1, r * 1.6, r * 2.9)), T3(Vector3(glen + 0.06, 0, 0)), K_PAINT, true);
		gb.put(box(Vector3(0.1, r * 1.6, r * 2.9)), T3(Vector3(glen + bl - 0.1, 0, 0)), K_PAINT, true);
		gb.put(box(Vector3(bl * 0.7, r * 1.0, r * 2.95)), T3(Vector3(glen + bl / 2, 0, 0)), K_SLIT, true);
	} else if (S.brake == BR_BALL) {
		gb.put(sph(14, 8), T3(Vector3(glen + 0.12, 0, 0), Vector3(0, 0, 0), Vector3(0.42, gr1 * 3.2, gr1 * 3.2)), K_PAINT);
		gb.put(box(Vector3(0.16, gr1 * 2.2, gr1 * 3.4)), T3(Vector3(glen + 0.12, 0, 0)), K_SLIT, true);
	} else {
		CX cm = cyl_x(gr1 * 1.25, gr1 * 1.25, 0.18, 14);
		gb.put(cm.p0, T3(Vector3(glen - 0.09, 0, 0), cm.p1), K_PAINT);
	}
	// дульный срез
	CX hole = cyl_x(gr1 * 0.55, gr1 * 0.55, 0.02, 10);
	double tip = glen + ((S.brake == BR_DOUBLE || S.brake == BR_DOUBLE_BIG) ? 0.5 : 0.0);
	gb.put(hole.p0, T3(Vector3(tip + 0.005, 0, 0), hole.p1), K_SLIT);
	SP = nullptr;
}

} // namespace

// Процедурная модель: (спецификация PackedFloat64Array) → [корпус, гусеницы, башня/рубка, маска (у рубки), орудие
//  (группы), треугольники корпуса, башни, орудия (для форм попаданий), высота крыши корпуса]
METHOD(tank_build) {
	SELF;
	if (!need(a, 1, e)) return;
	Spec S;
	Built B;
	bool ok = read_spec(f64(a, 0), S);
	if (ok) build(S, B);
	ArrayOut out(9);
	ret_group(out.at(0), B.hull.g);
	ret_group(out.at(1), B.tracks);
	ret_group(out.at(2), B.top.g);
	ret_group(out.at(3), B.mant.g);
	ret_group(out.at(4), B.gun.g);
	std::vector<V3> fh = faces_of(B.hull.g), ft = faces_of(B.top.g), fg = faces_of(B.gun.g);
	ret_v3s(out.at(5), fh.data(), (int64_t)fh.size());
	ret_v3s(out.at(6), ft.data(), (int64_t)ft.size());
	ret_v3s(out.at(7), fg.data(), (int64_t)fg.size());
	ret_float(out.at(8), ok ? B.roof : -1.0);
	out.to_variant(r);
}

// Гусеницы готовой модели: (контур в единицах карты, ширина, смещение по z, единиц в метре) → группа
METHOD(tank_tracks) {
	SELF;
	if (!need(a, 4, e)) return;
	U = a.num(3);
	Group g = tracks(v2s(a, 0), a.num(1), a.num(2));
	ret_group(r, g);
}

// Белая полоса и крест на башне готовой модели (Берлин): (контур полосы, высота полосы, мин и макс башни xyz,
//  единиц в метре) → группа
METHOD(tank_band) {
	SELF;
	if (!need(a, 5, e)) return;
	U = a.num(4);
	std::vector<V2> poly = v2s(a, 0);
	if (polygon_clockwise(poly)) std::reverse(poly.begin(), poly.end());
	double yb = a.num(1);
	V3 tmin = a.v3(2), tmax = a.v3(3);
	Group g;
	g.add(geo_frustum(poly, 0.13, 1.0, 0.0, false), T3(Vector3(0, yb - 0.065, 0)), 0);
	double rw = std::min((double)tmax.z, -(double)tmin.z) * 0.75;
	double cx = ((double)tmax.x + tmin.x) * 0.5 - 0.1;
	g.add(box(Vector3(rw * 2.0, 0.02, 0.16)), T3(Vector3(cx, (double)tmax.y + 0.01, 0)), 0);
	g.add(box(Vector3(0.16, 0.02, rw * 2.0)), T3(Vector3(cx, (double)tmax.y + 0.01, 0)), 0);
	ret_group(r, g);
}

// Опознавательные знаки на обоих бортах: (место xyz в метрах, размер, наклон, единиц в метре) → группа
METHOD(tank_emblem) {
	SELF;
	if (!need(a, 4, e)) return;
	U = a.num(3);
	V3 pos = a.v3(0);
	double size = a.num(1), tilt = a.num(2);
	float su = (float)size * (float)U;
	Prim q = prim_quad(su, su);
	Group g;
	for (double s : { 1.0, -1.0 }) {
		M3 bs = s > 0 ? basis_axis({ 1, 0, 0 }, (float)-tilt) : basis_axis({ 0, 1, 0 }, (float)PI_D) * basis_axis({ 1, 0, 0 }, (float)-tilt);
		g.add(q, { bs, mulf(Vector3(pos.x, pos.y, s * pos.z), U) }, 0);
	}
	ret_group(r, g);
}

// Сетки по профилям для GDScript (Geo.prism, frustum, loft, belt): (вид 0..3, многоугольник, числа) → [v, n, uv]
METHOD(geo_profile) {
	SELF;
	if (!need(a, 3, e)) return;
	int kind = (int)a.integer(0);
	std::vector<V2> poly = v2s(a, 1);
	std::vector<double> p = f64(a, 2);
	p.resize(5, 0.0);
	Prim pm;
	switch (kind) {
		case 0: pm = geo_prism(poly, p[0]); break;
		case 1: pm = geo_frustum(poly, p[0], p[1], p[2], p[3] != 0.0); break;
		case 2: pm = geo_loft(poly, p[0], p[1], p[2], p[3]); break;
		default: pm = geo_belt(poly, p[0], p[1], p[2]); break;
	}
	ArrayOut out(3);
	ret_v3s(out.at(0), pm.v.data(), (int64_t)pm.v.size());
	ret_v3s(out.at(1), pm.n.data(), (int64_t)pm.n.size());
	ret_v2s(out.at(2), pm.uv.data(), (int64_t)pm.uv.size());
	out.to_variant(r);
}

void register_tankbuild(GDExtensionClassLibraryPtr lib, const char *cls) {
	static const MethodDef defs[] = {
		{ "tank_build", tank_build },
		{ "tank_tracks", tank_tracks },
		{ "tank_band", tank_band },
		{ "tank_emblem", tank_emblem },
		{ "geo_profile", geo_profile },
	};
	register_list(lib, cls, defs, sizeof(defs) / sizeof(defs[0]));
}
