// Постройки карты в 3D (как MapGen.build): дома, руины, доты, мешки, ежи, остовы, палатки, скалы,
// изгороди бокажа, церкви, амбары, планёры, Рейхстаг, зенитные башни, трамваи, баррикады, кварталы,
// цеха, трубы, баки, фонтаны, глинобитные дома, надолбы, завалы; мелочь (столбы, фонари, ящики,
// сено, бочки), кусты и ели, сетки деревьев и заборов с расстановкой, камешки пустыни, флагштоки.
// Случайные числа — генератор Godot с тем же зерном, порядок вызовов — как в GDScript, скаляры — double,
// векторы — float: с одним зерном сетки совпадают с GDScript-сборкой.
#include "geom.h"
#include "grng.h"

namespace {

const double PI_D = 3.141592653589793;
const double TAU_D = 6.283185307179586;
double WS_D = 2860.0;  // D.WS — сторона карты, у большой карты больше (ставит map_size)

inline V3 v(double x, double y, double z) { return { (float)x, (float)y, (float)z }; }
inline V3 operator+(V3 a, V3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 operator-(V3 a, V3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V3 operator*(V3 a, double k) {
	float f = (float)k;
	return { a.x * f, a.y * f, a.z * f };
}
inline V3 operator*(V3 a, V3 b) { return { a.x * b.x, a.y * b.y, a.z * b.z }; }
inline V3 operator/(V3 a, double k) {
	float f = (float)k;
	return { a.x / f, a.y / f, a.z / f };
}
inline V3 operator*(const M3 &b, V3 p) { return b.mul(p); }
inline float vlen(V3 a) { return std::sqrt(a.x * a.x + a.y * a.y + a.z * a.z); }
inline V3 vnorm(V3 a) {
	float l = a.x * a.x + a.y * a.y + a.z * a.z;
	if (l == 0.0f) return { 0, 0, 0 };
	l = std::sqrt(l);
	return { a.x / l, a.y / l, a.z / l };
}

const V3 UP = { 0, 1, 0 }, BACK = { 0, 0, 1 }, RIGHT = { 1, 0, 0 };

inline M3 axis(V3 a, double ang) { return basis_axis(a, (float)ang); }
inline M3 scl(V3 s) { return basis_scale(s); }
inline Xf X(V3 o) { return { M3::ident(), o }; }
inline Xf XR(V3 o, V3 rot) { return xf_pos(o, rot); }
inline Xf T(const M3 &b, V3 o) { return { b, o }; }

inline Prim box(double x, double y, double z) { return prim_box(v(x, y, z)); }
inline Prim box(V3 s) { return prim_box(s); }
inline Prim cyl(double top, double bottom, double h, int seg = 10) { return prim_cyl((float)top, (float)bottom, (float)h, seg, 1); }
inline Prim prism(V3 s, float ltr = 0.5f) { return prim_prism(s, ltr); }
inline Prim sphere(int radial = 7, int rings = 4) { return prim_sphere(0.5f, 1.0f, radial, rings); }

// Материалы — в порядке словаря M в GDScript (номер — ответ GDScript, какой материал ставить)
enum Mat {
	M_PLASTER, M_BRICK, M_ROOF, M_CONCRETE, M_CONCRETE_D, M_WOOD, M_STEEL, M_RUST, M_CHARRED, M_SAND, M_RUBBLE,
	M_ROCK, M_SNOW, M_CANVAS, M_OLIVE, M_POLE, M_EARTH, M_LEAVES, M_HAY, M_ADOBE, M_CRATE, M_WIN, M_FACADE
};

enum Kind {
	K_HOUSE, K_RUIN, K_BUNKER, K_SANDBAGS, K_HEDGEHOGS, K_WRECK_TANK, K_WRECK_TRUCK, K_TENT, K_ROCK, K_HEDGEROW,
	K_CHURCH, K_BARN, K_GLIDER, K_REICHSTAG, K_FLAK_TOWER, K_TRAM, K_BARRICADE, K_FACTORY, K_CHIMNEY, K_WATER_TANK,
	K_FOUNTAIN, K_ADOBE, K_TEETH, K_RUBBLE, K_RUIN_TOWER, K_TOWER, K_RUIN_BLOCK, K_BLOCK
};
enum { D_HAY, D_CRATES, D_BARRELS, D_POLE, D_LAMP };
enum { B_BUSH, B_FIR, B_SHRUB };
enum { P_TREE_K, P_FENCE_K, P_PALM_K, P_BARE_K, P_APPLE_K, P_SPRUCE_K, PROP_N };

// Поворот остова, планёра или скалы вдоль прямоугольника препятствия (танки упираются в него): 0 или 180°
// и немного вбок — так видимое совпадает с тем, обо что танк упирается. Одно случайное число, как раньше.
inline double rect_yaw(double u, double w, double d, double jitter) {
	double flip = u >= 0.5 ? PI_D : 0.0;
	double f = u * 2.0 - std::floor(u * 2.0);
	return (w >= d ? 0.0 : PI_D / 2) + flip + (f - 0.5) * 2.0 * jitter;
}

struct ObstIn {
	int kind;
	float x, y, w, h, ht, base;
};

// Color("rrggbb") Godot: компонента / 255 (float)
inline void html(uint32_t hex, float out[4]) {
	out[0] = (float)((hex >> 16) & 0xff) / 255.0f;
	out[1] = (float)((hex >> 8) & 0xff) / 255.0f;
	out[2] = (float)(hex & 0xff) / 255.0f;
	out[3] = 1.0f;
}

// Color.from_hsv (Color::set_hsv)
inline void from_hsv(float h, float s, float val, float out[4]) {
	out[3] = 1.0f;
	if (s == 0.0f) {
		out[0] = out[1] = out[2] = val;
		return;
	}
	h *= 6.0f;
	h = std::fmod(h, 6.0f);
	int i = (int)std::floor(h);
	float f = h - i;
	float p = val * (1.0f - s), q = val * (1.0f - s * f), t = val * (1.0f - s * (1.0f - f));
	switch (i) {
		case 0: out[0] = val; out[1] = t; out[2] = p; break;
		case 1: out[0] = q; out[1] = val; out[2] = p; break;
		case 2: out[0] = p; out[1] = val; out[2] = t; break;
		case 3: out[0] = p; out[1] = q; out[2] = val; break;
		case 4: out[0] = t; out[1] = p; out[2] = val; break;
		default: out[0] = val; out[1] = p; out[2] = q; break;
	}
}

// строки базиса и начало — как буфер MultiMesh (3×4 на экземпляр)
inline void put_xf(float *B, const M3 &b, V3 o) {
	B[0] = b.m[0][0]; B[1] = b.m[0][1]; B[2] = b.m[0][2]; B[3] = o.x;
	B[4] = b.m[1][0]; B[5] = b.m[1][1]; B[6] = b.m[1][2]; B[7] = o.y;
	B[8] = b.m[2][0]; B[9] = b.m[2][1]; B[10] = b.m[2][2]; B[11] = o.z;
}

// Участки карты для отсечения: 3×3 на квадрат [-400, WS + 400]
const int TILES = 3;
inline int tile_of(double x, double z) {
	double span = (WS_D + 800.0) / TILES;
	int ix = (int)std::floor((x + 400.0) / span), iz = (int)std::floor((z + 400.0) / span);
	ix = std::min(TILES - 1, std::max(0, ix));
	iz = std::min(TILES - 1, std::max(0, iz));
	return iz * TILES + ix;
}

struct Build {
	Core *core;
	GRng rng;
	bool winter = false, desert = false, stone = false, hq = false;
	// сетки по участкам 3×3: видеокарта рисует (и бросает в тени) только участки в поле зрения,
	// а не всю карту целиком
	std::vector<Group> gt = std::vector<Group>(TILES * TILES);
	int tile = 0;
	int obj_i = 0;  // номер постройки (как в obst): в uv2 вершин и в коллизии
	std::vector<float> phys;
	std::vector<V3> smokes;

	double randf() { return rng.randf(); }
	double range(double a, double b) { return rng.range((float)a, (float)b); }
	float height(float x, float z) const { return core->height(x, z); }
	// в Нормандии и Арденнах кирпич и штукатурка — один материал (одна сетка)
	int mat(int m) const { return (stone && m == M_BRICK) ? M_PLASTER : m; }
	void add(const Prim &p, const Xf &x, int m, bool flat = false) {
		gt[tile].add(p, x, mat(m), flat);
		if (coll) coll_add(p, x);
	}
	// точная коллизия (Core::mesh_build): те же треугольники, что идут на экран, наружной стороной наружу;
	// coll = false — мелочь, сквозь которую снаряды летят (столбы, фонари, ящики, сено, бочки, ежи, флагштоки)
	bool coll = true;
	std::vector<float> ctri;
	std::vector<int> cobj;  // [начало, конец) треугольников каждого объекта и номер постройки (−1 — не постройка)
	void coll_add(const Prim &p, const Xf &x);
	int tri_count() const { return (int)(ctri.size() / 9); }
	void add_phys(V3 c, V3 s, double yaw = 0.0) {
		float f[7] = { c.x, c.y, c.z, s.x, s.y, s.z, (float)yaw };
		phys.insert(phys.end(), f, f + 7);
	}

	void obst(const ObstIn &o);
	void obst_body(const ObstIn &o);
	void decor(int kind, float px, float py, float rot);
	void decor_body(int kind, float px, float py, float rot);
};

void Build::coll_add(const Prim &pm, const Xf &x) {
	const M3 &B = x.b;
	auto xf = [&](V3 p) { return V3{ B.m[0][0] * p.x + B.m[0][1] * p.y + B.m[0][2] * p.z + x.o.x, B.m[1][0] * p.x + B.m[1][1] * p.y + B.m[1][2] * p.z + x.o.y,
							  B.m[2][0] * p.x + B.m[2][1] * p.y + B.m[2][2] * p.z + x.o.z }; };
	// нормали — обратной транспонированной (как Group::add): по ним видно, какая сторона треугольника наружная
	float m00 = B.m[0][0], m01 = B.m[0][1], m02 = B.m[0][2], m10 = B.m[1][0], m11 = B.m[1][1], m12 = B.m[1][2], m20 = B.m[2][0], m21 = B.m[2][1], m22 = B.m[2][2];
	float c00 = m11 * m22 - m12 * m21, c01 = m12 * m20 - m10 * m22, c02 = m10 * m21 - m11 * m20;
	float c10 = m02 * m21 - m01 * m22, c11 = m00 * m22 - m02 * m20, c12 = m01 * m20 - m00 * m21;
	float c20 = m01 * m12 - m02 * m11, c21 = m02 * m10 - m00 * m12, c22 = m00 * m11 - m01 * m10;
	float det = m00 * c00 + m01 * c01 + m02 * c02;
	float id = std::fabs(det) > 1e-12f ? 1.0f / det : 0.0f;
	size_t n = pm.idx.empty() ? pm.v.size() : pm.idx.size();
	n -= n % 3;
	for (size_t t = 0; t < n; t += 3) {
		int ids[3];
		for (int k = 0; k < 3; k++) ids[k] = pm.idx.empty() ? (int)(t + k) : pm.idx[t + k];
		V3 A = xf(pm.v[ids[0]]), Bv = xf(pm.v[ids[1]]), C = xf(pm.v[ids[2]]);
		V3 e1 = Bv - A, e2 = C - A;
		V3 face = { e1.y * e2.z - e1.z * e2.y, e1.z * e2.x - e1.x * e2.z, e1.x * e2.y - e1.y * e2.x };
		if (face.x * face.x + face.y * face.y + face.z * face.z < 1e-8f) continue;  // вырожденный (вершина конуса, полюс шара)
		V3 nn;
		if (!pm.n.empty()) {
			V3 sn = { pm.n[ids[0]].x + pm.n[ids[1]].x + pm.n[ids[2]].x, pm.n[ids[0]].y + pm.n[ids[1]].y + pm.n[ids[2]].y,
				pm.n[ids[0]].z + pm.n[ids[1]].z + pm.n[ids[2]].z };
			nn = { (c00 * sn.x + c01 * sn.y + c02 * sn.z) * id, (c10 * sn.x + c11 * sn.y + c12 * sn.z) * id, (c20 * sn.x + c21 * sn.y + c22 * sn.z) * id };
		} else {
			nn = (A + Bv + C) / 3.0 - x.o;
		}
		if (face.x * nn.x + face.y * nn.y + face.z * nn.z < 0.0f) std::swap(e1, e2);
		float f[9] = { A.x, A.y, A.z, e1.x, e1.y, e1.z, e2.x, e2.y, e2.z };
		ctri.insert(ctri.end(), f, f + 9);
	}
}

void Build::obst(const ObstIn &o) {
	tile = tile_of(o.x + o.w * 0.5, o.y + o.h * 0.5);
	int t_start = tri_count();
	coll = o.kind != K_HEDGEHOGS;  // ежи — тонкие рельсы, снаряд пролетает
	// номер постройки + 1 в uv2 каждой её вершины: шейдер схлопывает разрушенные по маске
	for (Group &g : gt) g.cur_uv2 = { (float)(obj_i + 1), 0.0f };
	obst_body(o);
	for (Group &g : gt) g.cur_uv2 = { 0.0f, 0.0f };
	coll = true;
	if (tri_count() > t_start) {
		cobj.push_back(t_start);
		cobj.push_back(tri_count());
		cobj.push_back(obj_i);
	}
	obj_i++;
}

// Прочность построек по виду (−1 — неразрушима) и сносит ли их таран тяжёлого танка.
static void obj_strength(int kind, float &hp, bool &soft) {
	soft = false;
	switch (kind) {
		case K_HOUSE: hp = 700.0f; break;
		case K_RUIN: hp = 450.0f; break;
		case K_ADOBE: hp = 350.0f; break;
		case K_WATER_TANK: hp = 300.0f; break;
		case K_TRAM: hp = 200.0f; break;
		case K_SANDBAGS: hp = 120.0f; soft = true; break;
		case K_TENT: hp = 40.0f; soft = true; break;
		case K_HEDGEROW: hp = 260.0f; soft = true; break;
		case K_BARN: hp = 300.0f; soft = true; break;
		case K_GLIDER: hp = 80.0f; soft = true; break;
		case K_WRECK_TRUCK: hp = 150.0f; soft = true; break;
		case K_BARRICADE: hp = 250.0f; soft = true; break;
		default: hp = -1.0f; break;  // доты, церкви, цеха, башни, скалы, остовы танков, кварталы, Рейхстаг
	}
}

void Build::obst_body(const ObstIn &o) {
	// Rect2.get_center(): position + size * 0.5
	float c2x = o.x + o.w * 0.5f, c2y = o.y + o.h * 0.5f;
	double b = o.base, ht = o.ht;
	V3 c = v(c2x, b, c2y);
	double w = o.w, d = o.h;
	switch (o.kind) {
		case K_HOUSE: {
			add(box(w, ht + 4, d), X(c + v(0, ht / 2 - 2, 0)), M_PLASTER);
			bool along_x = w >= d;
			Prim roof = prism(v((along_x ? d : w) + 5, 15, (along_x ? w : d) + 5));
			add(roof, XR(c + v(0, ht + 7.5, 0), v(0, along_x ? PI_D / 2 : 0.0, 0)), M_ROOF, true);
			add(box(4, 10, 4), X(c + v(w * 0.25, ht + 10, d * 0.15)), M_BRICK);
			for (double s : { 1.0, -1.0 }) {
				add(box(6, 7, 0.6), X(c + v(w * 0.2 * s, ht * 0.55, d / 2 + 0.2)), M_CHARRED);
				add(box(0.6, 7, 6), X(c + v(w / 2 + 0.2, ht * 0.55, d * 0.2 * s)), M_CHARRED);
			}
			add_phys(c + v(0, ht / 2, 0), v(w, ht + 15, d));
			break;
		}
		case K_RUIN: {
			double thick = 3.0;
			struct Wall {
				V3 off;
				double ln;
				bool x;
			};
			Wall walls[4] = { { v(0, 0, -d / 2 + thick / 2), w, true }, { v(0, 0, d / 2 - thick / 2), w, true },
				{ v(-w / 2 + thick / 2, 0, 0), d, false }, { v(w / 2 - thick / 2, 0, 0), d, false } };
			for (const Wall &wl : walls) {
				int segs = 3;
				double ln = wl.ln;
				for (int s = 0; s < segs; s++) {
					if (randf() < 0.22) continue;
					double sh = ht * range(0.3, 1.0);
					double off = (s - (segs - 1) / 2.0) * ln / segs;
					V3 size = wl.x ? v(ln / segs, sh, thick) : v(thick, sh, ln / segs);
					V3 pos = c + wl.off + (wl.x ? v(off, sh / 2, 0) : v(0, sh / 2, off));
					int m = randf() < 0.6 ? M_PLASTER : M_BRICK;
					add(box(size), X(pos), m);
					add(box(size * v(1.02, 0.08, 1.02)), X(pos + v(0, sh / 2, 0)), M_CHARRED);
					add_phys(pos, size);
				}
			}
			for (int k = 0; k < 6; k++) {
				double sx = range(4, 10), sy = range(2, 5), sz = range(4, 9);
				double px = range(-w / 3, w / 3), pz = range(-d / 3, d / 3);
				double rx = randf() * 0.4, ry = randf() * TAU_D, rz = randf() * 0.4;
				add(box(sx, sy, sz), XR(c + v(px, 1.5, pz), v(rx, ry, rz)), M_RUBBLE);
			}
			if (randf() < 0.4) smokes.push_back(c + v(0, 4, 0));
			break;
		}
		case K_BUNKER: {
			add(box(w, ht, d), X(c + v(0, ht / 2, 0)), M_CONCRETE);
			add(box(w + 4, 2.5, d + 4), X(c + v(0, ht + 1.0, 0)), M_CONCRETE_D);
			add(box(w * 0.5, 2.0, 1.0), X(c + v(0, ht * 0.62, -d / 2 - 0.2)), M_CHARRED);
			add(box(w * 0.5, 2.0, 1.0), X(c + v(0, ht * 0.62, d / 2 + 0.2)), M_CHARRED);
			add_phys(c + v(0, ht / 2, 0), v(w, ht + 2, d));
			break;
		}
		case K_SANDBAGS: {
			static const Prim bag = prim_box({ 4.6f, 2.2f, 3.2f });
			bool horiz = w >= d;
			double ln = horiz ? w : d;
			int n = (int)(ln / 4.6);
			for (int layer = 0; layer < 2; layer++) {
				for (int i = 0; i < n; i++) {
					double t = (i + 0.5 * layer) * ln / n - ln / 2 + 2.3;
					if (t > ln / 2 - 1.0) continue;
					V3 p = horiz ? v(t, 1.1 + layer * 2.1, 0) : v(0, 1.1 + layer * 2.1, t);
					double ry = (horiz ? 0.0 : PI_D / 2) + range(-0.12, 0.12);
					double rz = range(-0.05, 0.05);
					add(bag, XR(c + p, v(0, ry, rz)), M_SAND, true);
				}
			}
			add_phys(c + v(0, 2.5, 0), v(w, 5, d));
			break;
		}
		case K_HEDGEHOGS: {
			bool horiz = w >= d;
			double ln = horiz ? w : d;
			int n = std::max(1, (int)(ln / 16.0));
			for (int i = 0; i < n; i++) {
				double t = (i + 0.5) * ln / n - ln / 2;
				V3 p = c + (horiz ? v(t, 4.2, 0) : v(0, 4.2, t));
				double spin = randf() * TAU_D;
				for (int k = 0; k < 3; k++) {
					M3 bs = axis(UP, spin + k * TAU_D / 3.0) * axis(BACK, 0.62);
					add(box(15, 1.3, 1.3), T(bs, p), M_RUST);
				}
			}
			break;
		}
		case K_WRECK_TANK: {
			double yaw = rect_yaw(randf(), w, d, 0.12);
			double r0 = range(-0.05, 0.05);
			M3 bs = axis(UP, yaw) * axis(BACK, r0);
			add(box(30, 8, 18), T(bs, c + v(0, 4, 0)), M_CHARRED);
			add(box(34, 5, 6), T(bs, c + bs * v(0, 2.5, 8)), M_RUST);
			add(box(34, 5, 6), T(bs, c + bs * v(0, 2.5, -8)), M_RUST);
			double r1 = range(-1.2, 1.2);
			double r2 = range(-0.3, 0.3);
			M3 tb = (bs * axis(UP, r1)) * axis(RIGHT, r2);
			double tx = range(-3, 3), tz = range(-2, 2);
			V3 tp = c + bs * v(tx, 10.5, tz);
			add(cyl(6.0, 7.0, 6.0, 10), T(tb, tp), M_CHARRED);
			add(cyl(0.9, 1.1, 18, 8), T(tb * axis(BACK, -PI_D / 2 - 0.2), tp + tb * v(12, -1.5, 0)), M_RUST);
			add_phys(c + v(0, 6, 0), v(w, 12, d), yaw);
			if (randf() < 0.5) smokes.push_back(c + v(0, 10, 0));
			break;
		}
		case K_WRECK_TRUCK: {
			double yaw = rect_yaw(randf(), w, d, 0.12);
			double r0 = range(-0.12, 0.12);
			M3 bs = axis(UP, yaw) * axis(RIGHT, r0);
			add(box(9, 8, 12), T(bs, c + bs * v(11, 5, 0)), M_RUST);
			add(box(20, 5, 13), T(bs, c + bs * v(-4, 4, 0)), M_CHARRED);
			for (double wx : { 11.0, -1.0, -9.0 }) {
				for (double s : { 6.5, -6.5 }) {
					add(cyl(2.6, 2.6, 2.0, 10), T(bs * axis(RIGHT, PI_D / 2), c + bs * v(wx, 2.4, s)), M_CHARRED);
				}
			}
			add_phys(c + v(0, 5, 0), v(w, 10, d), yaw);
			break;
		}
		case K_TENT: {
			add(prism(v(d, ht, w)), XR(c + v(0, ht / 2, 0), v(0, PI_D / 2, 0)), M_CANVAS, true);
			add_phys(c + v(0, ht / 2, 0), v(w, ht, d));
			break;
		}
		case K_ROCK: {
			static const Prim rock_base = sphere(7, 4);
			double a = rect_yaw(randf(), 1.0, 0.0, 0.35);  // эллипсоид уже растянут по w и d
			Xf xfm = T(axis(UP, a) * scl(v(w * 1.12, ht * 1.7, d * 1.12)), c + v(0, ht * 0.3, 0));
			add(rock_base, xfm, M_ROCK, true);
			for (int k = 0; k < 2; k++) {
				double sz = range(8, 16);
				double px = range(-w, w) * 0.6;
				double pz = range(-d, d) * 0.6;
				add(rock_base, T(scl(v(sz, sz * 0.7, sz)), c + v(px, sz * 0.15, pz)), M_ROCK, true);
			}
			add_phys(c + v(0, ht * 0.55, 0), v(w * 0.95, ht * 1.1, d * 0.95));
			break;
		}
		case K_HEDGEROW: {
			static const Prim hedge_blob = sphere(7, 3);  // 56 треугольников (было 80): изгородей в Нормандии тысячи
			bool horiz = w >= d;
			double ln = horiz ? w : d;
			double th = horiz ? d : w;
			add(box(w, 6.0, d), X(c + v(0, 2.5, 0)), M_EARTH);
			int n = std::max(2, (int)(ln / 7.0));
			V3 along = horiz ? v(1, 0, 0) : v(0, 0, 1);
			V3 across = horiz ? v(0, 0, 1) : v(1, 0, 0);
			for (int i = 0; i < n; i++) {
				double t = (i + 0.5) * ln / n - ln / 2 + range(-2.5, 2.5);
				double hgt = range(10, 21);
				double ra = range(10, 17);
				V3 sz = along * ra + v(0, hgt, 0);
				double rb = range(1.1, 1.6);
				sz = sz + across * th * rb;
				double rc = range(-2.0, 2.0);
				V3 p = c + along * t + across * rc + v(0, 4.0 + hgt * 0.42, 0);
				double ang = range(-0.4, 0.4);
				add(hedge_blob, T(basis_scaled(axis(UP, ang), sz), p), M_LEAVES);
				if (randf() < 0.45) {
					V3 s2 = v(1, 1, 1) * range(6, 10);
					double r4 = range(-1, 1);
					V3 q = p + across * r4 * th * 0.6;
					double r5 = range(-3, 3);
					add(hedge_blob, T(scl(s2), q + v(r5, hgt * 0.35, 0)), M_LEAVES);
				}
				if (randf() < 0.06) {
					add(cyl(0.7, 1.1, 18, 6), X(p + v(0, 6, 0)), M_WOOD);
					for (int k = 0; k < 4; k++) {
						double cs = range(10, 15);
						double ox = range(-5, 5), oy = range(0, 7), oz = range(-5, 5);
						add(hedge_blob, T(scl(v(cs, cs * 0.8, cs)), p + v(ox, 18 + oy, oz)), M_LEAVES);
					}
				}
			}
			add_phys(c + v(0, ht / 2, 0), v(w, ht, d));
			break;
		}
		case K_CHURCH: {
			bool along_y = d >= w;
			double nave_l = (along_y ? d : w) * 0.72;
			double nave_w = (along_y ? w : d) * 0.85;
			V3 nave_c = c + (along_y ? v(0, 0, -(d - nave_l) / 2) : v(-(w - nave_l) / 2, 0, 0));
			V3 nsize = along_y ? v(nave_w, 26, nave_l) : v(nave_l, 26, nave_w);
			add(box(nsize), X(nave_c + v(0, 13, 0)), M_PLASTER);
			add(prism(v(nave_w + 4, 16, nave_l + 2)), XR(nave_c + v(0, 34, 0), v(0, along_y ? 0.0 : PI_D / 2, 0)), M_ROOF, true);
			double tw = std::min(w, d) * 0.62;
			V3 tower_c = c + (along_y ? v(0, 0, d / 2 - tw / 2) : v(w / 2 - tw / 2, 0, 0));
			bool broken = randf() < 0.5;
			double th2 = broken ? 44.0 : 52.0;
			add(box(tw, th2, tw), X(tower_c + v(0, th2 / 2, 0)), M_PLASTER);
			add(box(tw * 0.3, 7, 1.0), X(tower_c + v(0, th2 - 10, tw / 2 + 0.2)), M_CHARRED);
			if (broken) {
				for (int k = 0; k < 4; k++) {
					double sy = range(3, 9);
					double px = range(-1, 1) * tw * 0.35;
					double pz = range(-1, 1) * tw * 0.35;
					add(box(tw * 0.3, sy, tw * 0.3), X(tower_c + v(px, th2 + 2, pz)), M_PLASTER);
				}
				smokes.push_back(tower_c + v(0, th2, 0));
			} else {
				add(cyl(0.0, tw * 0.62, 30, 4), T(axis(UP, PI_D / 4), tower_c + v(0, th2 + 15, 0)), M_ROOF, true);
			}
			add_phys(nave_c + v(0, 17, 0), nsize + v(0, 8, 0));
			add_phys(tower_c + v(0, th2 / 2, 0), v(tw, th2, tw));
			break;
		}
		case K_BARN: {
			add(box(w, 9, d), X(c + v(0, 4.5, 0)), M_PLASTER);
			add(box(w - 1, ht - 9, d - 1), X(c + v(0, 9 + (ht - 9) / 2, 0)), M_WOOD);
			bool along_x = w >= d;
			add(prism(v((along_x ? d : w) + 4, 14, (along_x ? w : d) + 4)), XR(c + v(0, ht + 7, 0), v(0, along_x ? PI_D / 2 : 0.0, 0)), M_ROOF, true);
			add(box(14, 14, 0.8), X(c + v(0, 7, d / 2 + 0.3)), M_CHARRED);
			add_phys(c + v(0, ht / 2, 0), v(w, ht + 12, d));
			break;
		}
		case K_GLIDER: {
			double yaw = rect_yaw(randf(), w, d, 0.1);
			M3 bs = axis(UP, yaw);
			add(cyl(4.0, 4.0, 34, 10), T(bs * axis(BACK, PI_D / 2 - 0.06), c + bs * v(-10, 4, 0)), M_OLIVE);
			add(cyl(2.2, 4.0, 22, 10), T((bs * axis(UP, 0.5)) * axis(BACK, PI_D / 2 + 0.12), c + bs * v(18, 3, 4)), M_OLIVE);
			add(box(12, 1.2, 64), T(bs * axis(RIGHT, 0.08), c + bs * v(-6, 1.5, -6)), M_WOOD);
			add(box(5, 8, 1), T(bs, c + bs * v(30, 7, 6)), M_OLIVE);
			for (int k = 0; k < 4; k++) {
				double sy = range(4, 9);
				double ang = range(-0.6, 0.6);
				add(box(1.2, sy, 0.6), T(bs * axis(BACK, ang), c + bs * v(-24 + k * 6, 4, 2)), M_CHARRED);
			}
			add_phys(c + v(0, 4, 0), v(w * 0.8, 8, d * 0.8), yaw);
			break;
		}
		case K_REICHSTAG: {
			int stone_m = M_CONCRETE_D;
			add(box(w, ht, d), X(c + v(0, ht / 2, 0)), stone_m);
			add(box(w + 3, 3, d + 3), X(c + v(0, ht + 1.5, 0)), M_CONCRETE);
			for (double sx : { -1.0, 1.0 }) {
				for (double sz : { -1.0, 1.0 }) {
					V3 tp = c + v(sx * (w / 2 - 20), 0, sz * (d / 2 - 20));
					add(box(44, ht + 22, 44), X(tp + v(0, (ht + 22) / 2, 0)), stone_m);
					add(box(48, 3, 48), X(tp + v(0, ht + 23, 0)), M_CONCRETE);
				}
			}
			double pz = d / 2 + 10.0;
			for (int k = 0; k < 6; k++) {
				add(cyl(3.0, 3.4, ht - 4, 10), X(c + v(-40 + k * 16, (ht - 4) / 2, pz)), M_CONCRETE);
			}
			add(box(96, 5, 20), X(c + v(0, ht - 1.5, pz - 2)), stone_m);
			add(prism(v(96, 14, 20)), X(c + v(0, ht + 8, pz - 2)), stone_m, true);
			for (int k = 0; k < 5; k++) {
				add(box(10, 2, 10), X(c + v(-40 + k * 20, 1, pz + 14)), M_CONCRETE);
			}
			for (int k = 0; k < 14; k++) {
				double side = k % 2 == 0 ? 1.0 : -1.0;
				double px = range(-w / 2 + 50, w / 2 - 50);
				double py = range(10, ht - 8);
				add(box(7, 10, 1.0), X(c + v(px, py, side * (d / 2 + 0.3))), M_CHARRED);
			}
			V3 dome_c = c + v(0, ht + 3, 0);
			for (int k = 0; k < 12; k++) {
				double a = TAU_D * k / 12.0;
				for (int sgm = 0; sgm < 4; sgm++) {
					double a0 = PI_D / 2 * sgm / 4.0;
					double a1 = PI_D / 2 * (sgm + 1) / 4.0;
					double dr = 34.0;
					V3 p0 = v(std::cos(a) * dr * std::cos(a0), dr * 0.8 * std::sin(a0), std::sin(a) * dr * std::cos(a0));
					V3 p1 = v(std::cos(a) * dr * std::cos(a1), dr * 0.8 * std::sin(a1), std::sin(a) * dr * std::cos(a1));
					V3 mid = (p0 + p1) / 2;
					V3 dir = p1 - p0;
					V3 dn = vnorm(dir);
					M3 bas = basis_looking_at(dn, (double)std::fabs(dn.y) < 0.95 ? UP : RIGHT);
					add(box(1.0, 1.0, (double)vlen(dir) + 0.5), T(bas, dome_c + mid), M_STEEL);
				}
			}
			for (double ring_h : { 0.0, 0.45, 0.75 }) {
				double rr = 34.0 * std::cos(std::asin(ring_h));
				for (int k = 0; k < 24; k++) {
					double a = TAU_D * k / 24.0;
					double a2 = TAU_D * (k + 1) / 24.0;
					V3 q0 = v(std::cos(a) * rr, 34.0 * 0.8 * ring_h, std::sin(a) * rr);
					V3 q1 = v(std::cos(a2) * rr, 34.0 * 0.8 * ring_h, std::sin(a2) * rr);
					add(box(0.8, 0.8, (double)vlen(q1 - q0) + 0.4), T(basis_looking_at(vnorm(q1 - q0), UP), dome_c + (q0 + q1) / 2), M_STEEL);
				}
			}
			double sx = range(-60, 60);
			smokes.push_back(c + v(sx, ht, 0));
			add_phys(c + v(0, (ht + 22) / 2, 0), v(w, ht + 22, d));
			break;
		}
		case K_FLAK_TOWER: {
			add(box(w, ht, d), X(c + v(0, ht / 2, 0)), M_CONCRETE);
			for (int k = 0; k < 4; k++) {
				add(box(w + 2, 2.5, d + 2), X(c + v(0, ht * (0.25 + k * 0.2), 0)), M_CONCRETE_D);
			}
			for (double sx : { -1.0, 1.0 }) {
				for (double sz : { -1.0, 1.0 }) {
					V3 tp = c + v(sx * (w / 2 - 12), ht, sz * (d / 2 - 12));
					add(cyl(16, 16, 12, 16), X(tp + v(0, 6, 0)), M_CONCRETE);
					add(box(6, 4, 6), X(tp + v(0, 14, 0)), M_STEEL);
					for (double gz : { -1.4, 1.4 }) {
						add(cyl(0.6, 0.6, 16, 6), T(axis(UP, sx * 0.7) * axis(BACK, -PI_D / 2 + 0.5), tp + v(6, 18, gz)), M_STEEL);
					}
				}
			}
			for (int k = 0; k < 16; k++) {
				double sx = range(-w / 2 + 10, w / 2 - 10);
				double sy = range(15, ht - 10);
				V3 side = v(sx, sy, (d / 2 + 0.3) * (k % 2 == 0 ? 1.0 : -1.0));
				add(box(4, 4, 1), X(c + side), M_CHARRED);
			}
			add_phys(c + v(0, ht / 2, 0), v(w, ht, d));
			break;
		}
		case K_TRAM: {
			bool horiz = w >= d;
			double ln = horiz ? w : d;
			double r0 = range(-0.05, 0.05);
			M3 bs = axis(UP, horiz ? 0.0 : PI_D / 2) * axis(RIGHT, r0);
			add(box(ln, 10, 9), T(bs, c + v(0, 6.5, 0)), M_RUST);
			add(box(ln - 4, 4, 9.3), T(bs, c + v(0, 8.5, 0)), M_CHARRED);
			add(box(ln + 1, 1.2, 9.5), T(bs, c + v(0, 11.8, 0)), M_STEEL);
			for (int k = 0; k < 4; k++) {
				add(cyl(1.4, 1.4, 9.6, 8), T(bs * axis(RIGHT, PI_D / 2), c + bs * v(-ln / 2 + 6 + k * (ln - 12) / 3.0, 1.4, 0)), M_STEEL);
			}
			add_phys(c + v(0, 6.5, 0), v(w, 13, d));
			break;
		}
		case K_BARRICADE: {
			bool horiz = w >= d;
			double ln = horiz ? w : d;
			for (int k = 0; k < 10; k++) {
				double t = range(-ln / 2, ln / 2);
				double sx = range(4, 10), sy = range(2, 6), sz = range(4, 9);
				V3 szv = v(sx, sy, sz);
				double q = range(-3, 3);
				V3 p = c + (horiz ? v(t, szv.y * 0.4, q) : v(q, szv.y * 0.4, t));
				double rx = randf() * 0.5, ry = randf() * TAU_D, rz = randf() * 0.5;
				add(box(szv), XR(p, v(rx, ry, rz)), (k % 3) ? M_RUBBLE : M_BRICK);
			}
			for (int k = 0; k < 4; k++) {
				double t = range(-ln / 2, ln / 2) * 0.8;
				V3 p = c + (horiz ? v(t, 5, 0) : v(0, 5, t));
				double a = randf() * TAU_D;
				double bb = range(-0.6, 0.6);
				add(box(1.4, 1.4, 16), T(axis(UP, a) * axis(RIGHT, bb), p), M_WOOD);
			}
			add_phys(c + v(0, 4, 0), v(w, 8, d));
			break;
		}
		case K_TOWER:
		case K_RUIN_TOWER:
		case K_BLOCK:
		case K_RUIN_BLOCK: {
			bool ruin = o.kind == K_RUIN_TOWER || o.kind == K_RUIN_BLOCK;
			int wall = (o.kind == K_BLOCK || o.kind == K_RUIN_BLOCK) ? M_FACADE : M_WIN;
			int cols = w > 110 ? 3 : 2;
			int rows = d > 110 ? 3 : 2;
			for (int ix = 0; ix < cols; ix++) {
				for (int iz = 0; iz < rows; iz++) {
					double cw = w / cols;
					double cd = d / rows;
					double hgt = !ruin ? ht : ht * range(0.3, 1.0);
					V3 p = c + v(-w / 2 + cw * (ix + 0.5), hgt / 2 - 3, -d / 2 + cd * (iz + 0.5));
					add(box(cw, hgt + 6, cd), X(p), wall);
					add(box(cw + 1, 1.6, cd + 1), X(p + v(0, hgt / 2 + 3.6, 0)), winter ? M_SNOW : M_CONCRETE_D);
					add_phys(p + v(0, 3, 0), v(cw, hgt, cd));
					if (ruin) {
						for (int k = 0; k < 2; k++) {
							double jh = range(3, 12);
							double bx = range(4, cw * 0.4), bz = range(4, cd * 0.4);
							double px = range(-cw, cw) * 0.3, pz = range(-cd, cd) * 0.3;
							add(box(bx, jh, bz), X(p + v(px, hgt / 2 + 3 + jh / 2, pz)), wall);
						}
					}
				}
			}
			if (ruin) {
				for (int k = 0; k < 5; k++) {
					double sx = range(-w, w) * 0.55;
					double sg = randf() < 0.5 ? 1.0 : -1.0;
					V3 side = v(sx, 0, (d / 2 + 6) * sg);
					double bx = range(5, 12), by = range(2, 5), bz = range(5, 10);
					double rx = randf() * 0.4, ry = randf() * TAU_D;
					add(box(bx, by, bz), XR(c + side + v(0, 1.5, 0), v(rx, ry, 0)), M_RUBBLE);
				}
				if (randf() < 0.35) smokes.push_back(c + v(0, ht * 0.5, 0));
			}
			break;
		}
		case K_FACTORY: {
			bool along_x = w >= d;
			double ln = along_x ? w : d;
			double wd = along_x ? d : w;
			bool ruined = randf() < 0.65;
			double yaw = along_x ? 0.0 : PI_D / 2;
			M3 bs = axis(UP, yaw);
			add(box(w, ht, d), X(c + v(0, ht / 2, 0)), M_BRICK);
			int bays = std::max(3, (int)(ln / 34.0));
			double bl = ln / bays;
			for (double sd : { -1.0, 1.0 }) {
				add(box(ln - 12, ht * 0.32, 0.8), T(bs, c + bs * v(0, ht * 0.6, sd * (wd / 2 + 0.3))), M_CHARRED);
				for (int k = 0; k < bays + 1; k++) {
					add(box(3.5, ht, 1.6), T(bs, c + bs * v(-ln / 2 + k * bl, ht / 2, sd * (wd / 2 + 0.6))), M_BRICK);
				}
			}
			for (int k = 0; k < bays; k++) {
				double t = -ln / 2 + (k + 0.5) * bl;
				if (ruined && randf() < 0.45) {
					for (int q = 0; q < 3; q++) {
						double r1 = range(-0.3, 0.3);
						double r2 = range(-0.35, 0.35);
						V3 bp = c + bs * v(t + r1 * bl, ht + 1.0, r2 * wd);
						double e1 = range(-0.3, 0.3), e2 = range(-0.5, 0.5);
						add(box(1.2, 1.2, wd * 0.45), T(bs * basis_euler(v(e1, e2, 0)), bp), M_STEEL);
					}
					continue;
				}
				add(prism(v(bl, 11, wd), 0.0f), T(bs, c + bs * v(t, ht + 5.5, 0)), M_ROOF, true);
				add(box(0.6, 9, wd - 4), T(bs, c + bs * v(t - bl / 2 + 0.4, ht + 5, 0)), M_CHARRED);
			}
			if (ruined) {
				double s1 = range(-0.3, 0.3) * w;
				double s2 = range(-0.3, 0.3) * d;
				smokes.push_back(c + v(s1, ht, s2));
				for (int k = 0; k < 6; k++) {
					double sd = randf() < 0.5 ? 1.0 : -1.0;
					double bx = range(6, 14), by = range(2, 6), bz = range(5, 10);
					double rx = randf() * 0.4, ry = randf() * TAU_D;
					double px = range(-0.45, 0.45) * ln;
					add(box(bx, by, bz), T(bs * basis_euler(v(rx, ry, 0)), c + bs * v(px, 1.5, sd * (wd / 2 + 6))), (k % 2) ? M_RUBBLE : M_BRICK);
				}
			}
			add_phys(c + v(0, ht / 2 + 3, 0), v(w, ht + 6, d));
			break;
		}
		case K_CHIMNEY: {
			double top_h = ht;
			if (!(randf() < 0.6)) top_h = ht * range(0.55, 0.8);
			add(box(w + 6, 8, d + 6), X(c + v(0, 4, 0)), M_BRICK);
			add(cyl(w * 0.32, w * 0.5, top_h, 12), X(c + v(0, top_h / 2, 0)), M_BRICK);
			for (int k = 0; k < 3; k++) {
				double bh = top_h * (0.3 + k * 0.25);
				double from = w * 0.5, to = w * 0.32;
				double br = from + (to - from) * (bh / top_h) + 0.6;
				add(cyl(br, br, 1.6, 12), X(c + v(0, bh, 0)), M_CHARRED);
			}
			add_phys(c + v(0, top_h / 2, 0), v(w, top_h, d));
			break;
		}
		case K_WATER_TANK: {
			add(cyl(w / 2, w / 2, ht, 18), X(c + v(0, ht / 2, 0)), M_CONCRETE_D);
			add(cyl(w / 2 + 1.2, w / 2 + 1.2, 2.0, 18), X(c + v(0, ht, 0)), M_CONCRETE);
			for (int k = 0; k < 5; k++) {
				double a = randf() * TAU_D;
				double py = range(4, ht - 3);
				add(box(3.5, 3.5, 1.0), T(axis(UP, -a + PI_D / 2), c + v(std::cos(a) * (w / 2 + 0.2), py, std::sin(a) * (w / 2 + 0.2))), M_CHARRED);
			}
			add_phys(c + v(0, ht / 2, 0), v(w * 0.9, ht, d * 0.9));
			break;
		}
		case K_FOUNTAIN: {
			add(cyl(w / 2, w / 2 + 1.0, ht, 24), X(c + v(0, ht / 2, 0)), M_CONCRETE);
			add(cyl(w / 2 - 2.0, w / 2 - 2.0, 0.6, 24), X(c + v(0, ht + 0.1, 0)), winter ? M_SNOW : M_CHARRED);
			double ry = randf() * TAU_D;
			add(box(9, 2.2, 2.6), XR(c + v(0, ht + 1.4, 0), v(0, ry, 0)), M_STEEL);
			static const Prim head = sphere(6, 4);
			for (int k = 0; k < 6; k++) {
				double a = TAU_D * k / 6.0;
				V3 fp = c + v(std::cos(a) * 6.5, ht, std::sin(a) * 6.5);
				add(cyl(0.6, 0.9, 4.2, 6), X(fp + v(0, 2.1, 0)), M_STEEL);
				add(head, T(scl(v(1.4, 1.4, 1.4)), fp + v(0, 4.8, 0)), M_STEEL);
			}
			add_phys(c + v(0, ht / 2, 0), v(w, ht, d));
			break;
		}
		case K_ADOBE: {
			add(box(w, ht, d), X(c + v(0, ht / 2, 0)), M_ADOBE);
			for (double sd : { -1.0, 1.0 }) {
				add(box(w, 2.4, 1.6), X(c + v(0, ht + 1.2, sd * (d / 2 - 0.8))), M_ADOBE);
				add(box(1.6, 2.4, d), X(c + v(sd * (w / 2 - 0.8), ht + 1.2, 0)), M_ADOBE);
			}
			double px = range(-0.25, 0.25) * w;
			add(box(6, 9, 0.6), X(c + v(px, 4.5, d / 2 + 0.2)), M_CHARRED);
			for (double sd : { -1.0, 1.0 }) {
				add(box(3.2, 3.2, 0.6), X(c + v(w * 0.3 * sd, ht * 0.62, -d / 2 - 0.2)), M_CHARRED);
			}
			for (int k = 0; k < 3; k++) {
				add(cyl(0.25, 0.25, 6, 4), T(axis(RIGHT, PI_D / 2), c + v(-w / 2 + (k + 1) * w / 4, ht - 1.5, d / 2 + 2.0)), M_WOOD);
			}
			add_phys(c + v(0, ht / 2 + 1, 0), v(w, ht + 2, d));
			break;
		}
		case K_TEETH: {
			bool horiz = w >= d;
			double ln = horiz ? w : d;
			double th = horiz ? d : w;
			int n = std::max(2, (int)(ln / 7.5));
			int rows = std::max(2, (int)(th / 8.5));
			for (int rw = 0; rw < rows; rw++) {
				for (int i = 0; i < n; i++) {
					double t = (i + 0.5 * (rw % 2)) * ln / n - ln / 2 + 3.0;
					double q = -th / 2 + (rw + 0.5) * th / rows;
					V3 p = c + (horiz ? v(t, 0, q) : v(q, 0, t));
					double hgt = ht * (0.75 + 0.15 * rw);
					add(cyl(0.9, 3.0, hgt, 4), XR(p + v(0, hgt / 2 - 0.4, 0), v(0, PI_D / 4, 0)), M_CONCRETE_D);
					if (winter) {
						add(cyl(0.0, 1.2, 1.4, 4), XR(p + v(0, hgt - 0.1, 0), v(0, PI_D / 4, 0)), M_SNOW);
					}
				}
			}
			break;
		}
		case K_RUBBLE: {
			for (int k = 0; k < 8; k++) {
				double sx = range(4, 12), sy = range(2, 6), sz = range(4, 10);
				V3 szv = v(sx, sy, sz);
				double px = range(-w, w) * 0.35;
				double pz = range(-d, d) * 0.35;
				double rx = randf() * 0.5, ry = randf() * TAU_D, rz = randf() * 0.5;
				add(box(szv), XR(c + v(px, szv.y * 0.4, pz), v(rx, ry, rz)), (k % 3) ? M_RUBBLE : M_BRICK);
			}
			add_phys(c + v(0, 3, 0), v(w, 6, d));
			break;
		}
		default: {
			add(box(w, ht, d), X(c + v(0, ht / 2, 0)), M_CONCRETE);
			add_phys(c + v(0, ht / 2, 0), v(w, ht, d));
			break;
		}
	}
}

// мелочь без коллизии: столбы, фонари, ящики, сено, бочки
void Build::decor(int kind, float px, float py, float rot) {
	tile = tile_of(px, py);
	coll = false;
	decor_body(kind, px, py, rot);
	coll = true;
}

void Build::decor_body(int kind, float px, float py, float rot) {
	double y = height(px, py);
	if (kind == D_POLE) {
		add(cyl(0.6, 0.8, 26, 6), X(v(px, y + 13, py)), M_POLE);
		add(box(0.6, 0.6, 9), X(v(px, y + 24, py)), M_POLE);
	} else if (kind == D_LAMP) {
		add(cyl(0.35, 0.6, 22, 6), X(v(px, y + 11, py)), M_STEEL);
		add(box(5, 0.5, 0.5), X(v(px, y + 21.5, py)), M_STEEL);
		for (double s : { -2.2, 2.2 }) {
			add(cyl(0.9, 0.5, 2.0, 6), X(v(px + s, y + 20.2, py)), M_CHARRED);
		}
	} else if (kind == D_CRATES) {
		M3 bs = axis(UP, rot);
		int lower = 2 + (int)(rng.randi() % 2);
		int cnt = lower + (int)(rng.randi() % 3);
		for (int k = 0; k < cnt; k++) {
			bool top = k >= lower;
			V3 lp;
			if (!top) {
				double rx = range(-0.6, 0.6);
				lp = v(rx, 1.6, (k - (lower - 1) * 0.5) * 4.1);
			} else {
				double rx = range(-0.8, 0.8);
				lp = v(rx, 4.7, ((k - lower) - 0.5) * 4.1);
			}
			V3 cp = v(px, y, py) + bs * lp;
			double ry = range(-0.12, 0.12);
			add(box(6.2, 3.1, 3.9), T(bs * axis(UP, ry), cp), M_CRATE);
		}
	} else if (kind == D_HAY) {
		static const Prim bale = cyl(2.6, 2.6, 3.6, 12);
		for (int k = 0; k < 3; k++) {
			double hx = range(-8, 8), hz = range(-8, 8);
			float qx = px + (float)hx, qz = py + (float)hz;
			double ry = randf() * TAU_D;
			add(bale, XR(v(qx, (double)height(qx, qz) + 2.6, qz), v(PI_D / 2, ry, 0)), M_HAY);
		}
	} else {
		static const Prim barrel = cyl(1.6, 1.6, 4.2, 10);
		for (int k = 0; k < 5; k++) {
			double bx = range(-7, 7), bz = range(-7, 7);
			float qx = px + (float)bx, qz = py + (float)bz;
			bool lying = randf() < 0.3;
			double ry = randf() * TAU_D;
			add(barrel, XR(v(qx, (double)height(qx, qz) + (lying ? 1.6 : 2.1), qz), v(lying ? PI_D / 2 : 0.0, ry, 0)), (k % 2) ? M_OLIVE : M_RUST);
		}
	}
}

// Сетки разрушаемых объектов (как MapGen._prop_meshes): для каждого вида — части по материалу
// (номер части = номер материала в списке вида у GDScript).
std::vector<std::vector<Group>> prop_meshes(bool winter) {
	std::vector<std::vector<Group>> out(PROP_N);
	// дерево: ствол с ветками и крона из шаров
	{
		Group t, crown;
		t.add(cyl(0.8, 1.4, 20, 7), X(v(0, 10, 0)), 0);
		for (int k = 0; k < 3; k++) {
			double a = k * 2.1 + 0.4;
			t.add(cyl(0.25, 0.55, 8, 5), T(axis(UP, a) * axis(BACK, -0.7), v(std::cos(a) * 2.0, 18.5, std::sin(a) * 2.0)), 0);
		}
		static const double blobs[7][4] = { { 0.0, 0.0, 27.0, 14.0 }, { 5.5, 1.0, 23.0, 11.0 }, { -5.0, 2.5, 23.5, 11.0 }, { 1.5, -5.5, 22.5, 10.5 },
			{ -2.0, 5.5, 24.0, 10.5 }, { 4.0, -2.5, 29.5, 9.0 }, { -3.5, -2.0, 30.0, 8.5 } };
		Prim s85 = sphere(7, 4);  // 70 треугольников на шар кроны (было 96)
		for (const auto &bl : blobs) {
			crown.add(s85, T(scl(v(bl[3], bl[3] * 0.82, bl[3])), v(bl[0], bl[2], bl[1])), 0, true);
		}
		out[P_TREE_K] = { t, crown };
	}
	// яблоня
	{
		Group at, acrown;
		at.add(cyl(0.6, 1.0, 9, 6), XR(v(0, 4.5, 0), v(0, 0, 0.12)), 0);
		for (int k = 0; k < 3; k++) {
			double a = k * 2.1;
			at.add(cyl(0.25, 0.5, 6, 5), T(axis(UP, a) * axis(BACK, -0.9), v(std::cos(a) * 1.8, 9.5, std::sin(a) * 1.8)), 0);
		}
		static const double blobs[5][4] = { { 0.0, 0.0, 14.0, 9.0 }, { 4.5, 1.5, 12.5, 7.0 }, { -4.0, 2.0, 13.0, 7.0 }, { 1.0, -4.5, 12.0, 6.5 }, { -1.5, -3.0, 16.5, 6.0 } };
		Prim s85 = sphere(7, 4);  // 70 треугольников на шар кроны (было 96)
		for (const auto &bl : blobs) {
			acrown.add(s85, T(scl(v(bl[3], bl[3] * 0.7, bl[3])), v(bl[0], bl[2], bl[1])), 0, true);
		}
		out[P_APPLE_K] = { at, acrown };
	}
	// пальма
	{
		Group palm_t, fronds;
		for (int k = 0; k < 4; k++) {
			palm_t.add(cyl(0.7, 0.9, 8.5, 6), XR(v(k * 0.6, 4 + k * 8, 0), v(0, 0, -0.06 * k)), 0);
		}
		for (int k = 0; k < 7; k++) {
			double a = k * TAU_D / 7.0;
			fronds.add(box(12, 0.4, 3), T(axis(UP, a) * axis(BACK, -0.45), v(2.4 + std::cos(a) * 5, 34, std::sin(a) * 5)), 0);
		}
		out[P_PALM_K] = { palm_t, fronds };
	}
	// голое дерево
	{
		Group bare;
		bare.add(cyl(0.6, 1.2, 22, 6), X(v(0, 11, 0)), 0);
		for (int k = 0; k < 5; k++) {
			double a = k * 1.3;
			bare.add(cyl(0.2, 0.45, 9, 5), T(axis(UP, a) * axis(BACK, -0.9), v(std::cos(a) * 2.5, 14 + k * 1.6, std::sin(a) * 2.5)), 0);
		}
		out[P_BARE_K] = { bare };
	}
	// ель: ярусы-конусы, зимой — снег на лапах
	{
		Group sp_t, sp_c, sp_s;
		sp_t.add(cyl(0.6, 1.3, 14, 6), X(v(0, 7, 0)), 0);
		static const double tiers[5][3] = { { 7.0, 13.5, 22.0 }, { 19.0, 11.0, 19.0 }, { 30.0, 8.5, 16.0 }, { 40.0, 6.0, 13.0 }, { 49.0, 3.6, 11.0 } };
		for (int k = 0; k < 5; k++) {
			const double *tr = tiers[k];
			sp_c.add(cyl(0.0, tr[1], tr[2], 9), XR(v(0, tr[0] + tr[2] / 2, 0), v(0, k * 0.7, 0)), 0);
			if (winter) {
				double y1 = k + 1 < 5 ? tiers[k + 1][0] : tr[0] + tr[2];
				double y0 = tr[0] + (y1 - tr[0]) * 0.35;
				double r0 = tr[1] * (1.0 - (y0 - tr[0]) / tr[2]) + 0.5;
				double r1 = tr[1] * (1.0 - (y1 - tr[0]) / tr[2]) + 0.5;
				sp_s.add(cyl(r1, r0, y1 - y0, 9), XR(v(0, (y0 + y1) / 2 + 0.3, 0), v(0, k * 0.7, 0)), 0);
			}
		}
		out[P_SPRUCE_K] = { sp_t, sp_c };
		if (winter) out[P_SPRUCE_K].push_back(sp_s);
	}
	// пролёт забора
	{
		Group fence;
		for (double x : { -10.0, 10.0 }) fence.add(box(1.2, 9, 1.2), X(v(x, 4.5, 0)), 0);
		for (double y : { 3.0, 6.5 }) fence.add(box(22, 1.2, 0.5), X(v(0, y, 0)), 0);
		out[P_FENCE_K] = { fence };
	}
	return out;
}

// Rect2.grow(m).has_point(p)
bool blocked(const std::vector<ObstIn> &obst, float px, float py, float m) {
	for (const ObstIn &o : obst) {
		float x0 = o.x - m, y0 = o.y - m, w = o.w + m * 2.0f, h = o.h + m * 2.0f;
		if (px < x0 || py < y0 || px >= x0 + w || py >= y0 + h) continue;
		return true;
	}
	return false;
}

} // namespace

// Сборка карты в 3D. (карта, [зима, hq], obst [вид, x, y, w, h, высота, основание]*, decor [вид, x, y, поворот]*,
//  кусты [вид, x, y, r, n, (dx, dy, радиус)×n]*, props [вид, x, y, поворот, масштаб]*, зоны [x, y, r]*, зерно)
// → [постройки (группа), кусты (группа с цветом и UV2), коробки физики [центр, размер, поворот]*, дымы,
//    сетки деревьев и заборов [вид][часть] (группы), буферы MultiMesh по видам, высоты деревьев,
//    камешки [буфер, сколько]×16 (пустыня), сетка камешка, состояние генератора после сборки]
void mapbuild_ws(double w) { WS_D = w; }

METHOD(map_build) {
	SELF;
	if (!need(a, 8, e)) return;
	Build B;
	B.core = self;
	int map = (int)a.integer(0);
	std::vector<float> flags = f32(a, 1);
	B.winter = flags.size() > 0 && flags[0] != 0.0f;
	B.hq = flags.size() > 1 && flags[1] != 0.0f;
	B.desert = map == 1;
	B.stone = map == 3 || map == 5 || map == 6;
	std::vector<float> of = f32(a, 2), df = f32(a, 3), bf = f32(a, 4), pf = f32(a, 5), zf = f32(a, 6);
	B.rng.seed((uint64_t)a.integer(7));

	std::vector<ObstIn> obst;
	for (size_t k = 0; k + 6 < of.size(); k += 7) {
		obst.push_back({ (int)of[k], of[k + 1], of[k + 2], of[k + 3], of[k + 4], of[k + 5], of[k + 6] });
	}
	for (Group &g : B.gt) g.uv2_only = true;
	// разрушаемость: прочность каждой постройки (номера — как obst, и в GDScript, и в Core::obst)
	self->obj_hp.assign(obst.size(), -1.0f);
	self->obj_soft.assign(obst.size(), 0);
	self->obj_dead.assign(obst.size(), 0);
	for (size_t k = 0; k < obst.size(); k++) {
		bool soft;
		obj_strength(obst[k].kind, self->obj_hp[k], soft);
		self->obj_soft[k] = soft ? 1 : 0;
	}
	for (const ObstIn &o : obst) B.obst(o);
	for (size_t k = 0; k + 3 < df.size(); k += 4) B.decor((int)df[k], df[k + 1], df[k + 2], df[k + 3]);

	// кусты и ели: одна сетка (материал кустов), цвет — тон и радиус, UV2 — центр куста
	std::vector<Group> bgt(TILES * TILES);
	for (Group &q : bgt) q.extra = true;
	{
		const Prim ico = sphere(9, 5);
		const Prim cone = cyl(0.0, 0.5, 1.0, 7);
		float tones[3][2][4];
		html(0x424e33, tones[B_BUSH][0]);
		html(0x5a6442, tones[B_BUSH][1]);
		html(0x2a4630, tones[B_FIR][0]);
		html(0xe9eff2, tones[B_FIR][1]);
		html(0x6f6a38, tones[B_SHRUB][0]);
		html(0x8a8448, tones[B_SHRUB][1]);
		size_t q = 0;
		while (q + 4 < bf.size()) {
			int kind = std::min(2, std::max(0, (int)bf[q + 3]));
			float bpx = bf[q], bpy = bf[q + 1], br = bf[q + 2];
			int ns = (int)bf[q + 4];
			q += 5;
			double by = B.height(bpx, bpy);
			float ac[4], lc[4];
			std::copy(tones[kind][0], tones[kind][0] + 4, ac);
			std::copy(tones[kind][1], tones[kind][1] + 4, lc);
			ac[3] = (float)((double)br / 100.0);
			lc[3] = ac[3];
			V2 bp = { bpx, bpy };
			Group &bg = bgt[tile_of(bpx, bpy)];
			for (int i = 0; i < ns && q + 2 < bf.size(); i++) {
				float sx = bf[q], sy = bf[q + 1], sz = bf[q + 2];
				q += 3;
				V3 base = v((double)bpx + sx, by, (double)bpy + sy);
				double tint = B.range(0.85, 1.12);
				float ca[4] = { (float)(ac[0] * tint), (float)(ac[1] * tint), (float)(ac[2] * tint), ac[3] };
				if (kind == B_FIR) {
					double h = sz * 1.6 + 20.0;
					bg.add(cone, T(scl(v(sz * 1.5, h, sz * 1.5)), base + v(0, h / 2, 0)), 0, true, ca, bp);
					bg.add(cone, T(scl(v(sz * 0.64, h * 0.32, sz * 0.64)), base + v(0, h * 0.86, 0)), 0, true, lc, bp);
				} else {
					double k = kind == B_SHRUB ? 0.75 : 1.0;
					double sq = B.range(0.75, 1.1);
					double ry = B.randf() * TAU_D;
					bg.add(ico, T(axis(UP, ry) * scl(v(sz * 2.0, sz * 1.5 * sq, sz * 1.7) * k), base + v(0, sz * 0.55 * k * sq, 0)), 0, false, ca, bp);
					double rx = B.range(-3, 3), rz = B.range(-3, 3);
					bg.add(ico, T(scl(v(sz * 1.1, sz * 0.9, sz * 1.1) * k), base + v(rx, sz * 1.05 * k * sq, rz)), 0, false, lc, bp);
				}
			}
		}
	}

	// деревья и заборы: сетки частей и буферы MultiMesh (3×4 и цвет на экземпляр)
	std::vector<std::vector<Group>> parts = prop_meshes(B.winter);
	std::vector<std::vector<float>> bufs((size_t)PROP_N * TILES * TILES);
	std::vector<float> ys;
	std::vector<int32_t> prop_tile;  // на каждое дерево: участок × 65536 + номер в буфере участка
	for (size_t k = 0; k + 4 < pf.size(); k += 5) {
		int kind = std::min(PROP_N - 1, std::max(0, (int)pf[k]));
		float px = pf[k + 1], py = pf[k + 2], rot = pf[k + 3], sc = pf[k + 4];
		float y = B.height(px, py);
		ys.push_back(y);
		double hh = B.range(0.12, 0.2);
		double ss = B.range(0.0, 0.12);
		double vv = B.range(0.82, 1.12);
		float tint[4];
		from_hsv((float)hh, (float)ss, (float)vv, tint);
		M3 b = axis(UP, -(double)rot) * scl(v(sc, sc, sc));
		int pt = tile_of(px, py);
		std::vector<float> &bu = bufs[(size_t)kind * TILES * TILES + pt];
		prop_tile.push_back(pt * 65536 + (int32_t)(bu.size() / 16));
		size_t o = bu.size();
		bu.resize(o + 16);
		put_xf(&bu[o], b, v(px, y, py));
		std::copy(tint, tint + 4, &bu[o + 12]);
	}

	// камешки в пустыне: участками 4×4
	Group tuft;
	std::vector<std::vector<float>> peb;
	std::vector<int> peb_n;
	if (B.desert) {
		tuft.add(sphere(5, 3), T(scl(v(3, 1.6, 2.6)), v(0, 0, 0)), M_ROCK, true);
		int n = B.hq ? 1500 : 680;
		double cs = (WS_D + 400.0) / 4.0;
		int per = n / 16;
		for (int cx = 0; cx < 4; cx++) {
			for (int cz = 0; cz < 4; cz++) {
				std::vector<float> buf((size_t)per * 12, 0.0f);
				int placed = 0;
				for (int t = 0; t < per * 3; t++) {
					if (placed >= per) break;
					double rx = B.randf();
					double rz = B.randf();
					float px = (float)(-200.0 + (cx + rx) * cs), pz = (float)(-200.0 + (cz + rz) * cs);
					if (blocked(obst, px, pz, 4.0f)) continue;
					double s = B.range(0.6, 1.5);
					double ang = B.randf() * TAU_D;
					put_xf(&buf[(size_t)placed * 12], basis_scaled(axis(UP, ang), v(s, s, s)), v(px, B.height(px, pz), pz));
					placed++;
				}
				peb.push_back(std::move(buf));
				peb_n.push_back(placed);
			}
		}
	}

	// флагштоки зон (снаряды пролетают)
	B.coll = false;
	{
		const Prim pole = cyl(0.8, 0.8, 56, 10);
		for (size_t k = 0; k + 2 < zf.size(); k += 3) {
			double zy = B.height(zf[k], zf[k + 1]);
			B.tile = tile_of(zf[k], zf[k + 1]);
			B.add(pole, X(v(zf[k], zy + 28, zf[k + 1])), M_STEEL);
		}
	}

	B.coll = true;
	self->mesh_build(B.ctri, B.cobj);

	ArrayOut out(11);
	{
		ArrayOut tg(TILES * TILES);
		for (int k = 0; k < TILES * TILES; k++) ret_group(tg.at(k), B.gt[k]);
		tg.to_variant(out.at(0));
	}
	{
		ArrayOut tb(TILES * TILES);
		for (int k = 0; k < TILES * TILES; k++) ret_group(tb.at(k), bgt[k]);
		tb.to_variant(out.at(1));
	}
	ret_f32(out.at(2), B.phys.data(), (int64_t)B.phys.size());
	ret_v3s(out.at(3), B.smokes.data(), (int64_t)B.smokes.size());
	{
		ArrayOut pm(PROP_N);
		for (int k = 0; k < PROP_N; k++) {
			ArrayOut kk((int64_t)parts[k].size());
			for (size_t i = 0; i < parts[k].size(); i++) ret_group(kk.at((int64_t)i), parts[k][i]);
			kk.to_variant(pm.at(k));
		}
		pm.to_variant(out.at(4));
	}
	{
		// [вид][участок] → буфер MultiMesh
		ArrayOut bb(PROP_N);
		for (int k = 0; k < PROP_N; k++) {
			ArrayOut kt(TILES * TILES);
			for (int q = 0; q < TILES * TILES; q++) {
				const std::vector<float> &bu = bufs[(size_t)k * TILES * TILES + q];
				ret_f32(kt.at(q), bu.data(), (int64_t)bu.size());
			}
			kt.to_variant(bb.at(k));
		}
		bb.to_variant(out.at(5));
	}
	ret_i32(out.at(10), prop_tile.data(), (int64_t)prop_tile.size());
	ret_f32(out.at(6), ys.data(), (int64_t)ys.size());
	{
		ArrayOut pp((int64_t)peb.size() * 2);
		for (size_t i = 0; i < peb.size(); i++) {
			ret_f32(pp.at((int64_t)i * 2), peb[i].data(), (int64_t)peb[i].size());
			ret_int(pp.at((int64_t)i * 2 + 1), peb_n[i]);
		}
		pp.to_variant(out.at(7));
	}
	ret_group(out.at(8), tuft);
	ret_int(out.at(9), (int64_t)B.rng.state);
	out.to_variant(r);
}

// Примитив движка для сверки: (вид 0 куб, 1 цилиндр, 2 сфера, 3 призма, 4 квадрат; параметры) → [v, n, uv, индексы]
METHOD(prim_test) {
	SELF;
	if (!need(a, 2, e)) return;
	int kind = (int)a.integer(0);
	std::vector<float> p = f32(a, 1);
	p.resize(6, 0.0f);
	Prim pm;
	switch (kind) {
		case 0: pm = prim_box({ p[0], p[1], p[2] }); break;
		case 1: pm = prim_cyl(p[0], p[1], p[2], (int)p[3], (int)p[4]); break;
		case 2: pm = prim_sphere(p[0], p[1], (int)p[2], (int)p[3]); break;
		case 3: pm = prim_prism({ p[0], p[1], p[2] }, p[3]); break;
		default: pm = prim_quad(p[0], p[1]); break;
	}
	ArrayOut out(4);
	ret_v3s(out.at(0), pm.v.data(), (int64_t)pm.v.size());
	ret_v3s(out.at(1), pm.n.data(), (int64_t)pm.n.size());
	ret_v2s(out.at(2), pm.uv.data(), (int64_t)pm.uv.size());
	ret_i32(out.at(3), pm.idx.data(), (int64_t)pm.idx.size());
	out.to_variant(r);
}

void register_mapbuild(GDExtensionClassLibraryPtr lib, const char *cls) {
	static const MethodDef defs[] = {
		{ "map_build", map_build },
		{ "prim_test", prim_test },
	};
	register_list(lib, cls, defs, sizeof(defs) / sizeof(defs[0]));
}
