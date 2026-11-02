// Расстановка объектов карт (как MapGen.generate и всё, что она зовёт): дома, деревни, леса, лесополосы,
// изгороди бокажа, кварталы, заводы, окопы, остовы, воронки, дороги, высоты и овраги.
// Случайные числа — тот же генератор, что RandomNumberGenerator Godot (PCG32), а числа хранятся так
// же (скаляры GDScript — double, Vector2 и Rect2 — float): с одним зерном карта совпадает с GDScript.
#include "common.h"

#include <string>

namespace {

// ---------- RandomNumberGenerator Godot (RandomPCG) ----------
struct GRng {
	uint64_t state = 0, inc = 0;
	void seed(uint64_t s) {
		inc = (1442695040888963407ULL << 1u) | 1u;
		state = 0;
		next();
		state += s;
		next();
	}
	uint32_t next() {
		uint64_t old = state;
		state = old * 6364136223846793005ULL + inc;
		uint32_t xs = (uint32_t)(((old >> 18u) ^ old) >> 27u);
		uint32_t rot = (uint32_t)(old >> 59u);
		return (xs >> rot) | (xs << ((-rot) & 31));
	}
	double randf() {
		uint32_t proto = next();
		if (proto == 0) return 0.0;
		return (double)std::ldexp((float)(next() | 0x80000001u), -32 - __builtin_clz(proto));
	}
	double range(float a, float b) {
		float f = (float)randf();
		return (double)(f * (b - a) + a);
	}
	int64_t randi() { return (int64_t)next(); }
};

const double TAU_D = 6.283185307179586;
const double WS = 2860.0;

// Vector2 и Rect2 Godot (float), операции — как в движке
struct V { float x = 0, y = 0; };
inline V v(double x, double y) { return { (float)x, (float)y }; }
inline V operator+(V a, V b) { return { a.x + b.x, a.y + b.y }; }
inline V operator-(V a, V b) { return { a.x - b.x, a.y - b.y }; }
inline V operator*(V a, double k) { float f = (float)k; return { a.x * f, a.y * f }; }
inline V operator/(V a, double k) { float f = (float)k; return { a.x / f, a.y / f }; }
inline double dist(V a, V b) { return (double)std::sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)); }
inline V lerp(V a, V b, double t) { float f = (float)t; return { a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f }; }
inline V from_angle(double a) { float f = (float)a; return { std::cos(f), std::sin(f) }; }
inline double len(V a) { return (double)std::sqrt(a.x * a.x + a.y * a.y); }
inline V normalized(V a) {
	float l = a.x * a.x + a.y * a.y;
	if (l != 0.0f) {
		l = std::sqrt(l);
		a.x /= l;
		a.y /= l;
	}
	return a;
}
inline V vmin(V a, V b) { return { std::min(a.x, b.x), std::min(a.y, b.y) }; }
inline V vmax(V a, V b) { return { std::max(a.x, b.x), std::max(a.y, b.y) }; }
inline V closest_seg(V p, V a, V b) {  // Geometry2D.get_closest_point_to_segment
	V q = p - a, n = b - a;
	float l2 = n.x * n.x + n.y * n.y;
	if (l2 < 1e-20f) return a;
	float d = (n.x * q.x + n.y * q.y) / l2;
	if (d <= 0.0f) return a;
	if (d >= 1.0f) return b;
	return { a.x + n.x * d, a.y + n.y * d };
}
float bez(float s, float c1, float c2, float e, float t) {  // Math::bezier_interpolate
	float omt = 1.0f - t, omt2 = omt * omt, omt3 = omt2 * omt, t2 = t * t, t3 = t2 * t;
	return s * omt3 + c1 * omt2 * t * 3.0f + c2 * omt * t2 * 3.0f + e * t3;
}

struct R {
	float x = 0, y = 0, w = 0, h = 0;
	V pos() const { return { x, y }; }
	V size() const { return { w, h }; }
	V end() const { return { x + w, y + h }; }
	V center() const { return { x + w * 0.5f, y + h * 0.5f }; }
};
inline R rect(double x, double y, double w, double h) { return { (float)x, (float)y, (float)w, (float)h }; }
inline R rect(V p, V s) { return { p.x, p.y, s.x, s.y }; }
inline R grow(R r, double m) {
	float f = (float)m;
	return { r.x - f, r.y - f, r.w + f * 2, r.h + f * 2 };
}
inline R grow4(R r, double l, double t, double rr, double b) {
	return { r.x - (float)l, r.y - (float)t, r.w + (float)l + (float)rr, r.h + (float)t + (float)b };
}
inline bool intersects(R a, R b) {
	if (a.x >= b.x + b.w) return false;
	if (a.x + a.w <= b.x) return false;
	if (a.y >= b.y + b.h) return false;
	if (a.y + a.h <= b.y) return false;
	return true;
}
inline bool has_point(R r, V p) {
	if (p.x < r.x || p.y < r.y) return false;
	if (p.x >= r.x + r.w || p.y >= r.y + r.h) return false;
	return true;
}
inline R expand(R r, V p) {
	V b = r.pos(), e = r.end();
	if (p.x < b.x) b.x = p.x;
	if (p.y < b.y) b.y = p.y;
	if (p.x > e.x) e.x = p.x;
	if (p.y > e.y) e.y = p.y;
	return { b.x, b.y, e.x - b.x, e.y - b.y };
}

// виды (номера — как в MapGen.OBST_KINDS и т. д.)
enum Obk { O_HOUSE, O_RUIN, O_BUNKER, O_SANDBAGS, O_HEDGEHOGS, O_WRECK_TANK, O_WRECK_TRUCK, O_TENT, O_ROCK, O_HEDGEROW, O_CHURCH,
	O_BARN, O_GLIDER, O_REICHSTAG, O_FLAK_TOWER, O_TRAM, O_BARRICADE, O_FACTORY, O_CHIMNEY, O_WATER_TANK, O_FOUNTAIN, O_ADOBE,
	O_TEETH, O_RUBBLE, O_RUIN_TOWER, O_TOWER, O_RUIN_BLOCK, O_BLOCK };
enum Prk { P_TREE, P_FENCE, P_PALM, P_BARE, P_APPLE, P_SPRUCE };
enum Bsk { B_BUSH, B_FIR, B_SHRUB };
enum Dck { D_HAY, D_CRATES, D_BARRELS, D_POLE, D_LAMP };

struct Obst {
	R r;
	int kind;
	double ht;
	bool solid;
};
struct Bush {
	V pos;
	double r;
	int kind;
	std::vector<float> subs;  // dx, dy, радиус
};
struct Prop {
	V pos;
	double r;
	int kind;
	double rot = 0, scale = 1;
};
struct Decor {
	int kind;
	V pos;
	double rot;
};
struct Road {
	std::vector<V> pts;
	double w;
};
struct Hill {
	V a, b;
	double r, h, core;
};
struct Zn {
	V pos;
	double r;
};

struct Gen {
	GRng rng;
	std::vector<Zn> zones;
	std::vector<Obst> obst;
	std::vector<Bush> bushes;
	std::vector<Prop> props;
	std::vector<Decor> decor;
	std::vector<Road> roads;
	std::vector<Hill> hills;
	std::vector<float> craters;
	double lane_hill = 0, lane_town = 0, lane_mid = 0;

	bool excl_ok(R r, double m) {
		if (!(r.y > 420 && r.end().y < WS - 420 && r.x > 90 && r.end().x < WS - 90)) return false;
		for (const Zn &z : zones) {
			V c = v(clampd(z.pos.x, r.x, r.end().x), clampd(z.pos.y, r.y, r.end().y));
			if (dist(c, z.pos) < z.r + m) return false;
		}
		return true;
	}
	static double clampd(double x, double a, double b) { return x < a ? a : (x > b ? b : x); }
	bool hits(R r, const std::vector<Obst> &ob, double m) {
		R g = grow(r, m);
		for (const Obst &o : ob) {
			if (intersects(g, o.r)) return true;
		}
		return false;
	}
	bool free_point(V p, double m, bool use_props = true) {
		if (p.x < 100 || p.x > WS - 100 || p.y < 380 || p.y > WS - 380) return false;
		for (const Obst &o : obst) {
			if (has_point(grow(o.r, m), p)) return false;
		}
		for (const Zn &z : zones) {
			if (dist(p, z.pos) < z.r + m * 0.5) return false;
		}
		if (use_props) {
			for (const Prop &pr : props) {
				if (dist(p, pr.pos) < m * 0.6) return false;
			}
		}
		return true;
	}
	int place(double w, double h, int kind, double ht, R area, double margin = 60.0, bool solid = true) {
		for (int t = 0; t < 60; t++) {
			double rx = rng.randf();
			double x = area.x + rx * std::max(1.0, (double)area.w - w);
			double ry = rng.randf();
			double y = area.y + ry * std::max(1.0, (double)area.h - h);
			R r = rect(x, y, w, h);
			if (excl_ok(r, 30.0) && !hits(r, obst, margin)) {
				obst.push_back({ r, kind, ht, solid });
				return (int)obst.size() - 1;
			}
		}
		return -1;
	}
	void add_bushes(int n, int kind, R area, bool use_props) {
		int tries = 0, left = n;
		size_t first = bushes.size();
		(void)first;
		while (left > 0 && tries < n * 30) {
			tries++;
			double rx = rng.randf();
			double x = area.x + rx * area.w;
			double ry = rng.randf();
			double y = area.y + ry * area.h;
			V c = v(x, y);
			if (!free_point(c, 55.0, use_props)) continue;
			bool near = false;
			for (const Bush &b : bushes) {
				if (dist(c, b.pos) < b.r + 40.0) {
					near = true;
					break;
				}
			}
			if (near) continue;
			Bush b;
			b.pos = c;
			b.kind = kind;
			b.r = kind == B_FIR ? 34.0 + rng.randf() * 10.0 : 40.0 + rng.randf() * 16.0;
			int k = kind == B_FIR ? 2 + (int)(rng.randi() % 3) : 7 + (int)(rng.randi() % 4);
			for (int i = 0; i < k; i++) {
				double a = rng.randf() * TAU_D;
				double d = rng.randf() * b.r * (kind == B_FIR ? 0.55 : 0.75);
				double sr = kind == B_FIR ? b.r * (0.5 + rng.randf() * 0.3) : b.r * (0.28 + rng.randf() * 0.22);
				b.subs.push_back((float)(std::cos(a) * d));
				b.subs.push_back((float)(std::sin(a) * d));
				b.subs.push_back((float)sr);
			}
			bushes.push_back(b);
			left--;
		}
	}
	int prop(int kind, V p, double r = 4.0) {
		Prop pr;
		pr.kind = kind;
		pr.pos = p;
		pr.r = r;
		pr.rot = rng.randf() * TAU_D;
		pr.scale = rng.range(0.8f, 1.25f);
		props.push_back(pr);
		return (int)props.size() - 1;
	}
	void tree_line(int kind, V a, V b, double step) {
		int n = (int)(dist(a, b) / step);
		for (int i = 0; i < n; i++) {
			V base = lerp(a, b, (double)i / std::max(1.0, (double)n));
			double ox = rng.range(-6, 6);
			double oy = rng.range(-6, 6);
			V p = base + v(ox, oy);
			if (free_point(p, 22.0)) prop(kind, p);
		}
	}
	void add_craters(int n, R area) {
		int got = 0;
		for (int i = 0; i < n * 4; i++) {
			if (got >= n) break;
			double rx = rng.randf();
			double x = area.x + rx * area.w;
			double ry = rng.randf();
			double y = area.y + ry * area.h;
			V p = v(x, y);
			if (free_point(p, 30.0, false)) {
				craters.push_back(p.x);
				craters.push_back(p.y);
				craters.push_back((float)rng.range(9.0f, 20.0f));
				got++;
			}
		}
	}
	void sandbag_nest(R area) {
		int oi = place(46, 9, O_SANDBAGS, 5.0, area, 50.0);
		if (oi < 0) return;
		R r = obst[oi].r;
		R s1 = rect(r.x - 9, r.end().y, 9, 30);
		R s2 = rect(r.end().x, r.end().y, 9, 30);
		if (rng.randf() < 0.5) {
			s1 = rect(r.x - 9, r.y - 30, 9, 30);
			s2 = rect(r.end().x, r.y - 30, 9, 30);
		}
		for (R s : { s1, s2 }) {
			if (excl_ok(s, 20.0)) obst.push_back({ s, O_SANDBAGS, 5.0, true });
		}
	}
	void lanes() {
		bool left = rng.randf() < 0.5;
		lane_hill = WS * (left ? 0.2 : 0.8);
		lane_town = WS * (left ? 0.8 : 0.2);
		lane_mid = WS * 0.5;
	}
	void hill(V a, V b, double r, double h, double core = 0.3) { hills.push_back({ a, b, r, h, core }); }
	std::vector<V> bezier(V p0, V p1, V p2, V p3, int n = 32) {
		std::vector<V> out;
		for (int i = 0; i <= n; i++) {
			float t = (float)((double)i / n);
			out.push_back({ bez(p0.x, p1.x, p2.x, p3.x, t), bez(p0.y, p1.y, p2.y, p3.y, t) });
		}
		return out;
	}
	double road_dist(V p) {
		double best = 1e9;
		for (const Road &rd : roads) {
			for (size_t i = 0; i + 1 < rd.pts.size(); i++) {
				V c = closest_seg(p, rd.pts[i], rd.pts[i + 1]);
				best = std::min(best, dist(p, c) - rd.w * 0.5);
			}
		}
		return best;
	}
	int place_off_road(double w, double h, int kind, double ht, R area, double margin = 40.0) {
		for (int t = 0; t < 40; t++) {
			int oi = place(w, h, kind, ht, area, margin);
			if (oi < 0) return -1;
			R r = obst[oi].r;
			bool ok = true;
			V pts[5] = { r.pos(), r.end(), { r.x, r.end().y }, { r.end().x, r.y }, r.center() };
			for (V c : pts) {
				if (road_dist(c) < 12.0) {
					ok = false;
					break;
				}
			}
			if (ok) return oi;
			obst.erase(obst.begin() + oi);
		}
		return -1;
	}
	void village(V c, int n, double rad, const std::vector<int> &kinds, V ht, int fences, int tree) {
		int placed = 0;
		for (int t = 0; t < n * 4; t++) {
			if (placed >= n) break;
			double a = rng.randf() * TAU_D;
			double d = rng.range(40, (float)rad);
			double w = rng.range(48, 72);
			double h = rng.range(36, 52);
			V p = c + v(std::cos(a), std::sin(a)) * d;
			int kind = kinds[(size_t)(rng.randi() % (int64_t)kinds.size())];
			double hh = rng.range(ht.x, ht.y);
			if (place_off_road(w, h, kind, hh, rect(p - v(30, 30), v(60 + w, 60 + h)), 30.0) >= 0) placed++;
		}
		for (int i = 0; i < fences; i++) {
			double fx = rng.range((float)-rad, (float)rad);
			double fy = rng.range((float)-rad, (float)rad);
			V fp = c + v(fx, fy);
			V dir = from_angle(rng.randf() * TAU_D);
			for (int k = 0; k < 5; k++) {
				V p = fp + dir * (k * 22.0);
				if (free_point(p, 16.0) && road_dist(p) > 10.0) {
					int fi = prop(P_FENCE, p, 9.0);
					props[fi].rot = (double)std::atan2(dir.y, dir.x);
					props[fi].scale = 1.0;
				}
			}
		}
		if (tree >= 0) {
			for (int i = 0; i < n; i++) {
				V dir = from_angle(rng.randf() * TAU_D);
				double d = rng.range(30, (float)(rad * 1.1));
				V p = c + dir * d;
				if (free_point(p, 22.0) && road_dist(p) > 12.0) prop(tree, p);
			}
		}
	}
	void forest(V c, V rad, int n, int tree, int n_bush, int bush) {
		int placed = 0;
		for (int t = 0; t < n * 3; t++) {
			if (placed >= n) break;
			double a = rng.randf() * TAU_D;
			double d = std::pow(rng.randf(), 0.7);
			V p = c + v(std::cos(a) * rad.x, std::sin(a) * rad.y) * d;
			if (free_point(p, 15.0) && road_dist(p) > 16.0) {
				prop(tree, p);
				placed++;
			}
		}
		add_bushes(n_bush, bush, rect(c - rad * 0.85, rad * 1.7), false);
	}
	void bush_line(int kind, V a, V b, int n, double off) {
		V dir = normalized(b - a);
		V nrm = { -dir.y, dir.x };
		for (int i = 0; i < n; i++) {
			V base = lerp(a, b, rng.randf());
			double sg = rng.randf() < 0.5 ? 1.0 : -1.0;
			V p = base + nrm * (off * sg);
			add_bushes(1, kind, rect(p - v(12, 12), v(24, 24)), false);
		}
	}
	void wrecks(int n, double truck_k, R area, double margin = 50.0) {
		for (int i = 0; i < n; i++) {
			bool truck = rng.randf() < truck_k;
			place_off_road(truck ? 34 : 36, truck ? 16 : 22, truck ? O_WRECK_TRUCK : O_WRECK_TANK, 10.0, area, margin);
		}
	}
	void hedgehogs(int n, double ln, R area) {
		for (int i = 0; i < n; i++) {
			bool hz = rng.randf() < 0.5;
			place(hz ? ln : 12.0, hz ? 12.0 : ln, O_HEDGEHOGS, 8.0, area, 45.0, false);
		}
	}
	void scatter(int kind, int n, R area, double m = 28.0) {
		for (int i = 0; i < n; i++) {
			double rx = rng.randf();
			double x = area.x + rx * area.w;
			double ry = rng.randf();
			double y = area.y + ry * area.h;
			V p = v(x, y);
			if (free_point(p, m) && road_dist(p) > 12.0) prop(kind, p);
		}
	}
	void add_decor(int kind, int n, R area) {
		for (int i = 0; i < n; i++) {
			double rx = rng.randf();
			double x = area.x + rx * area.w;
			double ry = rng.randf();
			double y = area.y + ry * area.h;
			V p = v(x, y);
			if (free_point(p, 26.0) && road_dist(p) > 12.0) {
				decor.push_back({ kind, p, rng.randf() * TAU_D });
			}
		}
	}
	void poles(const std::vector<V> &road, double off) {
		for (size_t i = 0; i < road.size(); i += 2) {
			V p = road[i] + v(off, 0);
			if (free_point(p, 12.0)) decor.push_back({ D_POLE, p, 0.0 });
		}
	}

	// ---------- карты ----------

	void prokhorovka() {
		lanes();
		double hx = lane_hill, tx = lane_town;
		R mid = rect(140, 440, WS - 280, WS - 880);
		hill(v(hx, WS * 0.42), v(hx, WS * 0.58), 440.0, 44.0, 0.3);
		{
			double oy = rng.range(-160, 160);
			hill(v(hx, WS * 0.5), v(hx + (WS * 0.5 - hx) * 0.62, WS * 0.5 + oy), 170.0, 20.0, 0.2);
		}
		double bx = WS * 0.5 + rng.range(-140, 140);
		double tilt = rng.range(-110, 110);
		hill(v(bx - tilt, WS * 0.3), v(bx + tilt, WS * 0.7), 80.0, -15.0, 0.25);
		double r1 = rng.range(-220, 220);
		double r2 = rng.range(-220, 220);
		double r3 = rng.range(-150, 150);
		std::vector<V> road = bezier(v(tx, WS + 100), v(tx + r1, WS * 0.68), v(tx + r2, WS * 0.32), v(tx + r3, -100));
		roads.push_back({ road, 46.0 });
		roads.push_back({ bezier(v(-100, WS * 0.56), v(WS * 0.3, WS * 0.42), v(WS * 0.62, WS * 0.64), v(WS + 100, WS * 0.46)), 34.0 });
		V vc = v(tx, WS * 0.5 + rng.range(-160, 160));
		village(vc, 15, 420.0, { O_HOUSE, O_RUIN }, v(19, 25), 9, P_TREE);
		double fx = rng.range(-260, 260);
		double fy = rng.range(-320, 320);
		V farm = v(WS * 0.5 + fx, WS * 0.5 + fy);
		for (int i = 0; i < 2; i++) {
			double w = rng.range(60, 76);
			double h = rng.range(36, 44);
			place_off_road(w, h, O_BARN, 22.0, rect(farm - v(160, 160), v(320, 320)), 24.0);
		}
		add_decor(D_HAY, 5, rect(farm - v(260, 260), v(520, 520)));
		R top = rect(v(hx - 280, WS * 0.37), v(560, WS * 0.26));
		for (int i = 0; i < 5; i++) sandbag_nest(top);
		for (int i = 0; i < 2; i++) place(44, 36, O_BUNKER, 11.0, top, 70.0);
		scatter(P_TREE, 10, top, 34.0);
		wrecks(10, 0.2, mid, 60.0);
		for (int i = 0; i < 4; i++) sandbag_nest(mid);
		hedgehogs(6, 90.0, mid);
		for (int i = 0; i < 2; i++) {
			double y = WS * (0.4 + 0.2 * i) + rng.range(-40, 40);
			double x0 = WS * 0.33 + rng.range(-60, 60);
			double x1 = WS * 0.67 + rng.range(-60, 60);
			double gap = rng.range((float)(x0 + 140), (float)(x1 - 140));
			double d1 = rng.range(-20, 20);
			tree_line(P_TREE, v(x0, y), v(gap - 55, y + d1), 28.0);
			double d2 = rng.range(-20, 20);
			tree_line(P_TREE, v(gap + 55, y), v(x1, y + d2), 28.0);
			bush_line(B_BUSH, v(x0, y), v(x1, y), 4, 44.0);
		}
		for (int i = 0; i < 4; i++) {
			double ax = rng.range((float)(WS * 0.3), (float)(WS * 0.7));
			double ay = rng.range((float)(WS * 0.25), (float)(WS * 0.65));
			V a = v(ax, ay);
			double bxo = rng.range(-160, 160);
			double byo = rng.range(260, 420);
			V b = a + v(bxo, byo);
			tree_line(P_TREE, a, b, 30.0);
			bush_line(B_BUSH, a, b, 3, 44.0);
		}
		scatter(P_TREE, 30, rect(150, 420, WS - 300, WS - 840), 30.0);
		add_bushes(44, B_BUSH, rect(120, 330, WS - 240, WS - 660), true);
		add_decor(D_HAY, 8, mid);
		add_decor(D_CRATES, 6, top);
		add_decor(D_CRATES, 4, mid);
		poles(road, 34.0);
		add_craters(70, mid);
	}

	void alamein() {
		lanes();
		double hx = lane_hill, tx = lane_town;
		R mid = rect(140, 440, WS - 280, WS - 880);
		double a1 = rng.range(-120, 120);
		double a2 = rng.range(-260, 260);
		double a3 = rng.range(-260, 260);
		double a4 = rng.range(-120, 120);
		roads.push_back({ bezier(v(tx + a1, WS + 100), v(tx + a2, WS * 0.66), v(tx + a3, WS * 0.34), v(tx + a4, -100)), 30.0 });
		roads.push_back({ bezier(v(-100, WS * 0.35), v(WS * 0.35, WS * 0.2), v(WS * 0.55, WS * 0.8), v(WS + 100, WS * 0.66)), 26.0 });
		V ra = v(hx + rng.range(-70, 70), WS * 0.27);
		V rb = v(hx + rng.range(-70, 70), WS * 0.73);
		hill(ra, rb, 290.0, 40.0, 0.22);
		for (int i = 0; i < 10; i++) {
			double rr = rng.randf();
			V base = lerp(ra, rb, (i + rr) / 10.0);
			double ox = rng.range(-110, 110);
			V p = base + v(ox, 0);
			double s = rng.range(40, 90);
			double k1 = rng.range(0.8f, 1.3f);
			double k2 = rng.range(0.8f, 1.3f);
			double ht = rng.range(18, 32);
			place(s * k1, s * k2, O_ROCK, ht, rect(p - v(60, 60), v(120, 120)), 45.0);
		}
		for (int i = 0; i < 4; i++) sandbag_nest(rect(v(hx - 300, WS * 0.3), v(600, WS * 0.4)));
		double s = rng.randf() < 0.5 ? 1.0 : -1.0;
		hill(v(WS * 0.5 - s * 170, WS * 0.33), v(WS * 0.5 + s * 170, WS * 0.67), 105.0, -17.0, 0.25);
		V oc = v(tx, WS * 0.5 + rng.range(-220, 220));
		village(oc, 9, 260.0, { O_ADOBE, O_ADOBE, O_RUIN }, v(13, 18), 0, P_PALM);
		for (int i = 0; i < 12; i++) {
			V dir = from_angle(rng.randf() * TAU_D);
			double d = rng.range(20, 200);
			V p = oc + dir * d;
			if (free_point(p, 24.0)) prop(P_PALM, p);
		}
		R camp = rect(v(tx + (WS * 0.5 - tx) * 0.45 - 220, oc.y - 300), v(440, 600));
		for (int i = 0; i < 5; i++) place(30, 24, O_TENT, 12.0, camp, 50.0);
		wrecks(4, 0.8, camp, 40.0);
		add_decor(D_BARRELS, 10, camp);
		add_decor(D_CRATES, 8, camp);
		for (int i = 0; i < 18; i++) {
			double sz = rng.range(50, 130);
			double k1 = rng.range(0.8f, 1.2f);
			double k2 = rng.range(0.8f, 1.2f);
			double ht = rng.range(16, 40);
			place(sz * k1, sz * k2, O_ROCK, ht, mid, 75.0);
		}
		for (int i = 0; i < 6; i++) sandbag_nest(mid);
		wrecks(8, 0.4, mid, 60.0);
		hedgehogs(5, 90.0, mid);
		scatter(P_PALM, 8, rect(150, 420, WS - 300, WS - 840), 40.0);
		add_decor(D_BARRELS, 8, mid);
		add_bushes(30, B_SHRUB, rect(120, 330, WS - 240, WS - 660), true);
		add_craters(55, mid);
	}

	void stalingrad() {
		lanes();
		double hx = lane_hill, tx = lane_town;
		double cell = 300.0, street = 110.0, bs = cell - street;
		int n = (int)std::ceil((WS + 80.0) / cell);
		V kurgan = v(hx, WS * 0.5 + rng.range(-120, 120));
		hill(kurgan - v(0, 130), kurgan + v(0, 130), 480.0, 50.0, 0.16);
		R plant = rect(v(tx - WS * 0.165, WS * 0.29), v(WS * 0.33, WS * 0.42));
		R square = rect(v(WS * 0.5 - 180, WS * 0.5 - 180 + rng.range(-160, 160)), v(360, 360));
		std::vector<R> parks;
		for (int i = 0; i < n; i++) {
			for (int j = 0; j < n; j++) {
				double bx = -40.0 + i * cell + street / 2;
				double by = -40.0 + j * cell + street / 2;
				R block = rect(bx, by, bs, bs);
				if (dist(block.center(), kurgan) < 470.0 || intersects(block, grow(plant, 30)) || intersects(block, square)) continue;
				if (rng.randf() < 0.16) {
					parks.push_back(block);
					continue;
				}
				std::vector<R> parts;
				double q = rng.randf();
				if (q < 0.45) {
					double ox = rng.randf() * 15;
					double oy = rng.randf() * 15;
					parts.push_back(rect(bx + ox, by + oy, bs - 30, bs - 30));
				} else if (q < 0.72) {
					double sp = bs * rng.range(0.4f, 0.6f);
					parts.push_back(rect(bx, by, sp - 20, bs));
					parts.push_back(rect(bx + sp + 20, by, bs - sp - 20, bs));
				} else {
					double sp = bs * rng.range(0.4f, 0.6f);
					parts.push_back(rect(bx, by, bs, sp - 20));
					parts.push_back(rect(bx, by + sp + 20, bs, bs - sp - 20));
				}
				for (R pr : parts) {
					if (excl_ok(pr, 25.0)) {
						int kind = rng.randf() < 0.75 ? O_RUIN_TOWER : O_TOWER;
						double ht = rng.range(45, 105);
						obst.push_back({ pr, kind, ht, true });
					}
				}
			}
		}
		double hall_w = plant.w * 0.4, hall_d = plant.h * 0.24;
		for (int ci = 0; ci < 2; ci++) {
			for (int ri = 0; ri < 3; ri++) {
				R r = rect(plant.pos() + v(plant.w * (0.05 + ci * 0.52), plant.h * (0.04 + ri * 0.33)), v(hall_w, hall_d));
				double gr = rng.range(-30, 0);
				double gb = rng.range(-20, 0);
				r = grow4(r, 0, 0, gr, gb);
				if (excl_ok(r, 25.0)) {
					double ht = rng.range(30, 40);
					obst.push_back({ r, O_FACTORY, ht, true });
				}
			}
		}
		for (int i = 0; i < 3; i++) {
			double ht = rng.range(110, 140);
			place(18, 18, O_CHIMNEY, ht, plant, 26.0);
		}
		std::vector<Road> no_roads;
		roads.swap(no_roads);
		wrecks(4, 0.6, plant, 30.0);
		add_decor(D_CRATES, 5, plant);
		for (int i = 0; i < 4; i++) {
			double w = rng.range(30, 50);
			double h = rng.range(24, 40);
			place(w, h, O_RUBBLE, 6.0, plant, 30.0);
		}
		R kz = rect(kurgan - v(400, 400), v(800, 800));
		for (int i = 0; i < 2; i++) place(40, 40, O_WATER_TANK, 22.0, rect(kurgan - v(140, 140), v(280, 280)), 60.0);
		for (int i = 0; i < 7; i++) sandbag_nest(kz);
		wrecks(3, 0.3, kz, 50.0);
		scatter(P_BARE, 26, kz, 26.0);
		add_bushes(6, B_FIR, kz, true);
		double fx = rng.range(-40, 40);
		double fy = rng.range(-40, 40);
		V fc = square.center() + v(fx, fy);
		obst.push_back({ rect(fc - v(17, 17), v(34, 34)), O_FOUNTAIN, 5.0, true });
		R street_area = rect(120, 450, WS - 240, WS - 900);
		for (int i = 0; i < 14; i++) {
			double w = rng.range(30, 50);
			double h = rng.range(24, 40);
			place(w, h, O_RUBBLE, 6.0, street_area, 30.0);
		}
		hedgehogs(9, 60.0, street_area);
		for (int i = 0; i < 6; i++) sandbag_nest(street_area);
		wrecks(8, 0.4, street_area, 40.0);
		add_decor(D_CRATES, 6, street_area);
		add_decor(D_CRATES, 4, kz);
		for (R p : parks) {
			add_bushes(2, B_FIR, p, true);
			for (int k = 0; k < 3; k++) {
				double rx = rng.randf();
				double x = p.x + rx * p.w;
				double ry = rng.randf();
				double y = p.y + ry * p.h;
				V tp = v(x, y);
				if (free_point(tp, 24.0)) prop(P_BARE, tp);
			}
		}
		add_bushes(12, B_FIR, rect(120, 330, WS - 240, WS - 660), true);
		for (int i = 0; i < n + 1; i++) {
			double c = -40.0 + i * cell;
			roads.push_back({ { v(c, -100), v(c, WS + 100) }, street - 20.0 });
			roads.push_back({ { v(-100, c), v(WS + 100, c) }, street - 20.0 });
		}
		add_craters(36, kz);
		add_craters(40, street_area);
	}

	void normandy() {
		lanes();
		double hx = lane_hill, tx = lane_town;
		R mid = rect(140, 440, WS - 280, WS - 880);
		V hill_top = v(hx, WS * 0.5 + rng.range(-120, 120));
		hill(hill_top - v(0, 90), hill_top + v(0, 90), 440.0, 40.0, 0.25);
		V cross = v(tx, WS * 0.5 + rng.range(-150, 150));
		double a1 = rng.range(-150, 150);
		double a2 = rng.range(-120, 120);
		double a3 = rng.range(-120, 120);
		double a4 = rng.range(-150, 150);
		std::vector<V> road1 = bezier(v(tx + a1, WS + 100), cross + v(a2, WS * 0.2), cross + v(a3, -WS * 0.2), v(tx + a4, -100));
		double b1 = rng.range(-200, 200);
		double b2 = rng.range(-250, 250);
		double b3 = rng.range(-250, 250);
		double b4 = rng.range(-200, 200);
		std::vector<V> road2 = bezier(v(-100, cross.y + b1), v(WS * 0.33, cross.y + b2), v(WS * 0.66, cross.y + b3), v(WS + 100, cross.y + b4));
		roads.push_back({ road1, 34.0 });
		roads.push_back({ road2, 30.0 });
		place_off_road(40, 84, O_CHURCH, 34.0, rect(cross - v(170, 170), v(340, 340)), 30.0);
		R village_r = rect(cross - v(340, 330), v(680, 660));
		for (int i = 0; i < 13; i++) {
			double w = rng.range(44, 66);
			double h = rng.range(34, 48);
			int kind = rng.randf() < 0.6 ? O_HOUSE : O_RUIN;
			double ht = rng.range(18, 24);
			place_off_road(w, h, kind, ht, village_r, 26.0);
		}
		std::vector<R> orchards;
		for (int f = 0; f < 5; f++) {
			double cx = rng.range(300, (float)(WS - 300));
			double cy = rng.range(650, (float)(WS - 650));
			V c = v(cx, cy);
			if (dist(c, cross) < 520.0 || dist(c, hill_top) < 380.0) continue;
			R area = rect(c - v(140, 140), v(280, 280));
			double w1 = rng.range(46, 60);
			double h1 = rng.range(34, 42);
			place_off_road(w1, h1, O_HOUSE, 20.0, area, 24.0);
			double w2 = rng.range(60, 76);
			double h2 = rng.range(36, 44);
			place_off_road(w2, h2, O_BARN, 22.0, area, 24.0);
			double ox = rng.range(-260, 60);
			double oy = rng.range(-260, 60);
			orchards.push_back(rect(c + v(ox, oy), v(200, 200)));
		}
		// бокаж
		std::vector<double> xs;
		double x = 90.0;
		while (x < WS - 200.0) {
			x += rng.range(300, 420);
			if (x < WS - 200.0) xs.push_back(x);
		}
		std::vector<double> ys = { 440.0 };
		double y = 440.0;
		while (y < WS - 640.0) {
			y += rng.range(300, 400);
			ys.push_back(std::min(y, WS - 440.0));
		}
		if (ys.back() < WS - 440.0) ys.push_back(WS - 440.0);
		struct Edge {
			V a, b;
			bool outer;
		};
		std::vector<Edge> edges;
		std::vector<double> gx = { 90.0 };
		gx.insert(gx.end(), xs.begin(), xs.end());
		gx.push_back(WS - 90.0);
		for (size_t j = 0; j < ys.size(); j++) {
			for (size_t i = 0; i + 1 < gx.size(); i++) {
				double yy = ys[j] + rng.range(-20, 20);
				edges.push_back({ v(gx[i], yy), v(gx[i + 1], yy), j == 0 || j == ys.size() - 1 });
			}
		}
		for (size_t i = 0; i < xs.size(); i++) {
			for (size_t j = 0; j + 1 < ys.size(); j++) {
				double xx = xs[i] + rng.range(-20, 20);
				edges.push_back({ v(xx, ys[j]), v(xx, ys[j + 1]), false });
			}
		}
		std::vector<Obst> buildings = obst;
		for (const Edge &e : edges) {
			V a = e.a, b = e.b;
			bool on_hill = dist(closest_seg(hill_top, a, b), hill_top) < 300.0;
			if (!e.outer) {
				double rr = rng.randf();
				bool skip = rr < 0.16;
				if (!skip && on_hill) skip = rng.randf() < 0.75;
				if (skip) continue;
			}
			double ln = dist(a, b);
			V dir = (b - a) / ln;
			std::vector<std::pair<double, double>> gaps;
			int ng = e.outer ? 3 : 1 + (int)(rng.randi() % 2);
			for (int g = 0; g < ng; g++) {
				double gc = rng.range(50, (float)(ln - 50));
				double g0 = rng.range(32, 42);
				double g1 = rng.range(32, 42);
				gaps.push_back({ gc - g0, gc + g1 });
			}
			double t = 0.0, piece_start = 0.0, step = 8.0;
			bool open = false;
			while (t <= ln) {
				V p = a + dir * t;
				bool cut = road_dist(p) < 14.0 || dist(p, hill_top) < 190.0;
				for (auto &g : gaps) {
					if (t > g.first && t < g.second) cut = true;
				}
				if (cut || t + step > ln) {
					double end_t = cut ? t : ln;
					if (!open && end_t - piece_start > 24.0) {
						V p0 = a + dir * piece_start;
						V p1 = a + dir * end_t;
						R r = expand(rect(vmin(p0, p1), v(0, 0)), vmax(p1, p0));
						bool vy = std::fabs(dir.y) > 0.5f, vx = std::fabs(dir.x) > 0.5f;
						r = grow4(r, vy ? 7 : 0, vx ? 7 : 0, vy ? 7 : 0, vx ? 7 : 0);
						if (excl_ok(r, 20.0) && !hits(r, buildings, 12.0)) obst.push_back({ r, O_HEDGEROW, 19.0, true });
					}
					open = cut;
					piece_start = t;
				} else if (open) {
					open = false;
					piece_start = t;
				}
				t += step;
			}
		}
		forest(hill_top, v(170, 150), 48, P_TREE, 7, B_BUSH);
		for (R r : orchards) {
			double px = r.x;
			while (px < r.end().x) {
				double py = r.y;
				while (py < r.end().y) {
					double ox = rng.range(-4, 4);
					double oy = rng.range(-4, 4);
					V p = v(px + ox, py + oy);
					if (free_point(p, 18.0) && road_dist(p) > 10.0) prop(P_APPLE, p);
					py += 34.0;
				}
				px += 34.0;
			}
		}
		scatter(P_TREE, 44, rect(150, 420, WS - 300, WS - 840), 26.0);
		wrecks(8, 0.4, mid, 50.0);
		for (int i = 0; i < 3; i++) place_off_road(70, 26, O_GLIDER, 9.0, mid, 60.0);
		for (int i = 0; i < 4; i++) sandbag_nest(mid);
		add_decor(D_HAY, 20, rect(150, 420, WS - 300, WS - 840));
		add_decor(D_CRATES, 8, mid);
		poles(road1, 30.0);
		add_bushes(24, B_BUSH, rect(120, 330, WS - 240, WS - 660), true);
		add_craters(42, mid);
	}

	void berlin() {
		lanes();
		double hx = lane_hill, tx = lane_town;
		double cell = 330.0, street = 130.0, bs = cell - street;
		int n = (int)std::ceil((WS + 120.0) / cell);
		double axis_y = WS * 0.5;
		roads.push_back({ { v(-100, axis_y), v(WS + 100, axis_y) }, 150.0 });
		std::vector<R> landmarks;
		R park = rect(v(hx - WS * 0.15, WS * 0.28), v(WS * 0.3, WS * 0.44));
		landmarks.push_back(park);
		double rx = rng.range(-120, 120);
		double ry = rng.range(560, 700);
		R reich = rect(v(WS * 0.5 - 160 + rx, ry), v(320, 170));
		if (excl_ok(reich, 30.0)) {
			obst.push_back({ reich, O_REICHSTAG, 40.0, true });
			landmarks.push_back(grow4(reich, 60, 60, 60, 220));
		}
		double fx = rng.range(60, park.w - 190);
		double fy = rng.range(80, park.h - 210);
		R flak = rect(park.pos() + v(fx, fy), v(130, 130));
		if (std::fabs(flak.center().y - axis_y) < 150.0) {
			double sg = rng.randf() < 0.5 ? 1.0 : -1.0;
			flak.y += (float)(260.0 * sg);
		}
		if (excl_ok(flak, 30.0) && !hits(flak, obst, 80.0)) obst.push_back({ flak, O_FLAK_TOWER, 100.0, true });
		std::vector<R> parks;
		for (int i = 0; i < n; i++) {
			for (int j = 0; j < n; j++) {
				double bx = -60.0 + i * cell + street / 2;
				double by = -60.0 + j * cell + street / 2;
				R block = rect(bx, by, bs, bs);
				if (std::fabs(block.center().y - axis_y) < cell * 0.5) continue;
				bool skip = false;
				for (R lm : landmarks) {
					if (intersects(block, lm)) skip = true;
				}
				if (skip) continue;
				bool dense = std::fabs(block.center().x - tx) < WS * 0.18;
				if (!dense && rng.randf() < 0.14) {
					parks.push_back(block);
					continue;
				}
				std::vector<R> parts;
				double depth = bs * 0.32;
				parts.push_back(rect(bx, by, bs, depth));
				parts.push_back(rect(bx, by + bs - depth, bs, depth));
				if (dense || rng.randf() < 0.6) parts.push_back(rect(bx, by + depth + 12, depth, bs - 2 * depth - 24));
				if (dense || rng.randf() < 0.6) parts.push_back(rect(bx + bs - depth, by + depth + 12, depth, bs - 2 * depth - 24));
				for (R pr : parts) {
					if (rng.randf() < (dense ? 0.06 : 0.12)) continue;
					if (excl_ok(pr, 25.0)) {
						int kind = rng.randf() < 0.55 ? O_RUIN_BLOCK : O_BLOCK;
						double ht = rng.range(55, 85);
						obst.push_back({ pr, kind, ht, true });
					}
				}
			}
		}
		R street_area = rect(120, 450, WS - 240, WS - 900);
		R dense_area = rect(v(tx - WS * 0.18, 450), v(WS * 0.36, WS - 900));
		for (int i = 0; i < 14; i++) {
			double w = rng.range(30, 50);
			double h = rng.range(24, 40);
			place(w, h, O_RUBBLE, 6.0, street_area, 30.0);
		}
		for (int i = 0; i < 8; i++) {
			bool hz = rng.randf() < 0.5;
			place(hz ? 64.0 : 14.0, hz ? 14.0 : 64.0, O_BARRICADE, 8.0, i < 5 ? dense_area : street_area, 40.0);
		}
		for (int i = 0; i < 5; i++) {
			bool hz = rng.randf() < 0.5;
			place(hz ? 48.0 : 12.0, hz ? 12.0 : 48.0, O_TRAM, 13.0, street_area, 40.0);
		}
		hedgehogs(8, 60.0, street_area);
		for (int i = 0; i < 6; i++) sandbag_nest(street_area);
		{
			std::vector<Road> keep;
			keep.swap(roads);
			wrecks(9, 0.5, street_area, 40.0);
			add_decor(D_CRATES, 8, street_area);
			keep.swap(roads);
		}
		scatter(P_BARE, 70, park, 22.0);
		add_bushes(12, B_BUSH, park, true);
		for (int i = 0; i < 5; i++) sandbag_nest(park);
		wrecks(3, 0.5, park, 40.0);
		for (R p : parks) {
			for (int k = 0; k < 6; k++) {
				double qx = rng.randf();
				double x = p.x + qx * p.w;
				double qy = rng.randf();
				double y = p.y + qy * p.h;
				V tp = v(x, y);
				if (free_point(tp, 22.0)) prop(P_BARE, tp);
			}
			add_bushes(1, B_BUSH, p, true);
		}
		double xx = 120.0;
		while (xx < WS - 120.0) {
			for (double sd : { -1.0, 1.0 }) {
				double ox = rng.range(-6, 6);
				V p = v(xx + ox, axis_y + sd * 62.0);
				if (free_point(p, 16.0)) {
					if ((int)(xx / 70.0) % 2 == 0) {
						prop(P_BARE, p);
					} else {
						decor.push_back({ D_LAMP, p, 0.0 });
					}
				}
			}
			xx += 70.0;
		}
		for (int i = 0; i < n + 1; i++) {
			double c = -60.0 + i * cell;
			if (c < park.x || c > park.end().x) {
				roads.push_back({ { v(c, -100), v(c, WS + 100) }, street - 20.0 });
			} else {
				roads.push_back({ { v(c, -100), v(c, park.y) }, street - 20.0 });
				roads.push_back({ { v(c, park.end().y), v(c, WS + 100) }, street - 20.0 });
			}
			if (c < park.y || c > park.end().y) {
				roads.push_back({ { v(-100, c), v(WS + 100, c) }, street - 20.0 });
			} else {
				roads.push_back({ { v(-100, c), v(park.x, c) }, street - 20.0 });
				roads.push_back({ { v(park.end().x, c), v(WS + 100, c) }, street - 20.0 });
			}
		}
		add_craters(40, park);
		add_craters(36, street_area);
	}

	void ardennes() {
		lanes();
		double hx = lane_hill, tx = lane_town;
		R mid = rect(140, 440, WS - 280, WS - 880);
		V ra = v(hx + rng.range(-60, 60), WS * 0.29);
		V rb = v(hx + rng.range(-60, 60), WS * 0.71);
		hill(ra, rb, 340.0, 42.0, 0.3);
		V cross = v(tx, WS * 0.5 + rng.range(-150, 150));
		double a1 = rng.range(-150, 150);
		double a2 = rng.range(-140, 140);
		double a3 = rng.range(-140, 140);
		double a4 = rng.range(-150, 150);
		std::vector<V> road1 = bezier(v(tx + a1, WS + 100), cross + v(a2, WS * 0.22), cross + v(a3, -WS * 0.22), v(tx + a4, -100));
		double ry = WS * 0.5 + rng.range(-240, 240);
		double b1 = rng.range(-200, 200);
		double b2 = rng.range(-150, 150);
		std::vector<V> road2 = bezier(cross, v(WS * 0.5, cross.y + b1), v(hx, ry + b2), v(hx < WS * 0.5 ? -100.0 : WS + 100.0, ry));
		roads.push_back({ road1, 38.0 });
		roads.push_back({ road2, 28.0 });
		place_off_road(40, 84, O_CHURCH, 34.0, rect(cross - v(170, 170), v(340, 340)), 30.0);
		village(cross, 12, 360.0, { O_HOUSE, O_HOUSE, O_RUIN }, v(18, 24), 8, P_BARE);
		for (int i = 0; i < 3; i++) {
			double w = rng.range(60, 76);
			double h = rng.range(36, 44);
			place_off_road(w, h, O_BARN, 22.0, rect(cross - v(420, 420), v(840, 840)), 26.0);
		}
		forest((ra + rb) * 0.5, v(300, WS * 0.27), 240, P_SPRUCE, 26, B_FIR);
		double face = hx < WS * 0.5 ? 1.0 : -1.0;
		for (int i = 0; i < 2; i++) place(44, 36, O_BUNKER, 11.0, rect(v(hx + face * 200 - 80, WS * 0.35), v(160, WS * 0.3)), 80.0);
		double tz = hx + face * 340.0;
		double ty = WS * 0.5 + rng.range(-200, 200);
		for (int k = 0; k < 3; k++) {
			V a = v(tz, ty + (k - 1) * 230.0 - 80.0);
			R r = rect(a, v(26, 150));
			if (excl_ok(r, 20.0) && !hits(r, obst, 20.0) && road_dist(r.center()) > 60.0) obst.push_back({ r, O_TEETH, 7.0, false });
		}
		for (int i = 0; i < 5; i++) {
			double cx = rng.range((float)(WS * 0.3), (float)(WS * 0.7));
			double cy = rng.range((float)(WS * 0.22), (float)(WS * 0.78));
			V c = v(cx, cy);
			if (dist(c, cross) < 420.0) continue;
			double rx = rng.range(80, 140);
			double rz = rng.range(80, 140);
			forest(c, v(rx, rz), 26, P_SPRUCE, 3, B_FIR);
		}
		for (size_t i = 1; i + 1 < road1.size(); i += 2) {
			for (double sd : { -1.0, 1.0 }) {
				V p = road1[i] + v(sd * 36.0, 0);
				if (free_point(p, 18.0)) prop(P_BARE, p);
			}
		}
		for (int i = 0; i < 6; i++) sandbag_nest(mid);
		wrecks(8, 0.5, mid, 50.0);
		add_decor(D_HAY, 8, mid);
		add_decor(D_CRATES, 4, rect(cross - v(380, 380), v(760, 760)));
		add_decor(D_CRATES, 6, mid);
		poles(road1, 30.0);
		scatter(P_SPRUCE, 30, rect(150, 420, WS - 300, WS - 840), 30.0);
		add_bushes(28, B_FIR, rect(120, 330, WS - 240, WS - 660), true);
		add_craters(40, mid);
	}
};

} // namespace

// Расстановка карты: (вид карты 0–5: Прохоровка, Эль-Аламейн, Сталинград, Нормандия, Берлин, Арденны,
// зерно, зоны [x, z, r]*) → [постройки [x, z, ш, г, вид, высота, сплошная]*, кусты [x, z, r, вид,
// кронок, (dx, dz, r)*]*, деревья и заборы [x, z, r, вид, поворот, размер]*, мелочи [вид, x, z, поворот]*,
// воронки [x, z, r]*, дороги [ширина, точек, (x, z)*]*, высоты [ax, az, bx, bz, r, h, ядро]*,
// направления [высота, застройка, центр]]
METHOD(map_generate) {
	SELF;
	if (!need(a, 3, e)) return;
	int map = (int)a.integer(0);
	Gen g;
	g.rng.seed((uint64_t)a.integer(1));
	std::vector<float> zf = f32(a, 2);
	for (size_t k = 0; k + 2 < zf.size(); k += 3) g.zones.push_back({ { zf[k], zf[k + 1] }, (double)zf[k + 2] });
	switch (map) {
		case 1: g.alamein(); break;
		case 2: g.stalingrad(); break;
		case 3: g.normandy(); break;
		case 4: g.berlin(); break;
		case 5: g.ardennes(); break;
		default: g.prokhorovka(); break;
	}
	std::vector<float> ob, bu, pr, de, ro, hi;
	for (const Obst &o : g.obst) {
		float q[7] = { o.r.x, o.r.y, o.r.w, o.r.h, (float)o.kind, (float)o.ht, o.solid ? 1.0f : 0.0f };
		ob.insert(ob.end(), q, q + 7);
	}
	for (const Bush &b : g.bushes) {
		float q[5] = { b.pos.x, b.pos.y, (float)b.r, (float)b.kind, (float)(b.subs.size() / 3) };
		bu.insert(bu.end(), q, q + 5);
		bu.insert(bu.end(), b.subs.begin(), b.subs.end());
	}
	for (const Prop &p : g.props) {
		float q[6] = { p.pos.x, p.pos.y, (float)p.r, (float)p.kind, (float)p.rot, (float)p.scale };
		pr.insert(pr.end(), q, q + 6);
	}
	for (const Decor &d : g.decor) {
		float q[4] = { (float)d.kind, d.pos.x, d.pos.y, (float)d.rot };
		de.insert(de.end(), q, q + 4);
	}
	for (const Road &r : g.roads) {
		ro.push_back((float)r.w);
		ro.push_back((float)r.pts.size());
		for (V p : r.pts) {
			ro.push_back(p.x);
			ro.push_back(p.y);
		}
	}
	for (const Hill &h : g.hills) {
		float q[7] = { h.a.x, h.a.y, h.b.x, h.b.y, (float)h.r, (float)h.h, (float)h.core };
		hi.insert(hi.end(), q, q + 7);
	}
	float ln[3] = { (float)g.lane_hill, (float)g.lane_town, (float)g.lane_mid };
	ArrayOut out(8);
	ret_f32(out.at(0), ob.data(), (int64_t)ob.size());
	ret_f32(out.at(1), bu.data(), (int64_t)bu.size());
	ret_f32(out.at(2), pr.data(), (int64_t)pr.size());
	ret_f32(out.at(3), de.data(), (int64_t)de.size());
	ret_f32(out.at(4), g.craters.data(), (int64_t)g.craters.size());
	ret_f32(out.at(5), ro.data(), (int64_t)ro.size());
	ret_f32(out.at(6), hi.data(), (int64_t)hi.size());
	ret_f32(out.at(7), ln, 3);
	out.to_variant(r);
}

// Первые n чисел генератора с зерном (для сверки с RandomNumberGenerator): randf, randf_range(-6, 6), randi % 1000
METHOD(rng_test) {
	SELF;
	if (!need(a, 2, e)) return;
	GRng g;
	g.seed((uint64_t)a.integer(0));
	int n = (int)a.integer(1);
	std::vector<float> out;
	for (int i = 0; i < n; i++) {
		out.push_back((float)g.randf());
		out.push_back((float)g.range(-6, 6));
		out.push_back((float)(g.randi() % 1000));
	}
	ret_f32(r, out.data(), (int64_t)out.size());
}

void register_mapgen(GDExtensionClassLibraryPtr lib, const char *cls) {
	static const MethodDef defs[] = {
		{ "map_generate", map_generate },
		{ "rng_test", rng_test },
	};
	register_list(lib, cls, defs, sizeof(defs) / sizeof(defs[0]));
}
