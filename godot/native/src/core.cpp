// Ускоренные части «Стального Штурма»: рельеф, препятствия, прямая видимость, засвет, сетка путей
// и A*, слияние геометрии, процедурные текстуры. Каждая функция повторяет GDScript-версию
// (она остаётся запасной, если библиотеки нет) — так результаты можно сверить.
#include "core.h"
#include "noise.h"

#include <algorithm>
#include <cfloat>
#include <queue>

using namespace gd;

static inline float clampf(float v, float a, float b) { return v < a ? a : (v > b ? b : v); }
static inline double lerpd(double a, double b, double t) { return a + (b - a) * t; }
static inline float smoothstep(float from, float to, float s) {
	if (std::fabs(from - to) < 1e-6f) {
		return s <= from ? 0.0f : 1.0f;
	}
	float t = clampf((s - from) / (to - from), 0.0f, 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

// ---------- Пространственная сетка ----------

void Hash::build(float lo, float hi, float p_cell) {
	cell = p_cell;
	x0 = y0 = (int)std::floor(lo / cell);
	nx = ny = (int)std::floor(hi / cell) - x0 + 1;
	cells.assign((size_t)nx * ny, {});
}

void Hash::put(float ax, float ay, float bx, float by, int item) {
	int ia = std::max(0, key(ax, false)), ib = std::min(nx - 1, key(bx, false));
	int ja = std::max(0, key(ay, true)), jb = std::min(ny - 1, key(by, true));
	for (int i = ia; i <= ib; i++) {
		for (int j = ja; j <= jb; j++) {
			cells[(size_t)j * nx + i].push_back(item);
		}
	}
}

const std::vector<int> *Hash::at(int cx, int cy) const {
	if (cx < 0 || cy < 0 || cx >= nx || cy >= ny) {
		return nullptr;
	}
	return &cells[(size_t)cy * nx + cx];
}

// ---------- Рельеф ----------

float Core::height(float x, float z) const {
	if (h.empty()) {
		return 0.0f;
	}
	double fx = std::min(std::max(((double)x - origin) / cell, 0.0), tn - 0.001);
	double fz = std::min(std::max(((double)z - origin) / cell, 0.0), tn - 0.001);
	int ix = (int)fx, iz = (int)fz;
	double tx = fx - ix, tz = fz - iz;
	size_t i = (size_t)iz * (tn + 1) + ix;
	return (float)lerpd(lerpd(h[i], h[i + 1], tx), lerpd(h[i + tn + 1], h[i + tn + 2], tx), tz);
}

void Core::build_cmax() {
	int N = tn;
	cmax.assign((size_t)N * N, 0.0f);
	for (int iz = 0; iz < N; iz++) {
		for (int ix = 0; ix < N; ix++) {
			size_t i = (size_t)iz * (N + 1) + ix;
			cmax[(size_t)iz * N + ix] = std::max(std::max(h[i], h[i + 1]), std::max(h[i + N + 1], h[i + N + 2]));
		}
	}
}

// Луч над рельефом: идём по клеткам сетки (DDA); где луч выше наивысшей точки клетки — клетку
// пропускаем, иначе проверяем точки внутри неё с шагом в четверть клетки.
bool Core::terrain_clear(V3 a, V3 b) const {
	if (h.empty()) {
		return true;
	}
	float dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z;
	float len = std::sqrt(dx * dx + dz * dz);
	if (len < 1e-4f) {
		return true;
	}
	float step = cell * 0.25f;
	// за краем сетки или без сетки максимумов — просто по точкам
	auto inside = [&](float x, float z) {
		return x > origin && z > origin && x < origin + tn * cell && z < origin + tn * cell;
	};
	if (cmax.empty() || !inside(a.x, a.z) || !inside(b.x, b.z)) {
		int steps = std::max(2, (int)(len / step));
		for (int i = 1; i < steps; i++) {
			float t = (float)i / steps;
			if (a.y + dy * t < height(a.x + dx * t, a.z + dz * t)) {
				return false;
			}
		}
		return true;
	}
	float fx = (a.x - origin) / cell, fz = (a.z - origin) / cell;
	int cx = std::min((int)fx, tn - 1), cz = std::min((int)fz, tn - 1);
	int ex = std::min((int)((b.x - origin) / cell), tn - 1), ez = std::min((int)((b.z - origin) / cell), tn - 1);
	int sx = dx > 0 ? 1 : -1, sz = dz > 0 ? 1 : -1;
	float inv_x = std::fabs(dx) > 1e-9f ? cell / std::fabs(dx) : FLT_MAX;
	float inv_z = std::fabs(dz) > 1e-9f ? cell / std::fabs(dz) : FLT_MAX;
	float tx = std::fabs(dx) > 1e-9f ? ((dx > 0 ? (cx + 1) - fx : fx - cx) * cell / std::fabs(dx)) : FLT_MAX;
	float tz = std::fabs(dz) > 1e-9f ? ((dz > 0 ? (cz + 1) - fz : fz - cz) * cell / std::fabs(dz)) : FLT_MAX;
	float t0 = 0.0f;
	float dt = step / len;
	for (int guard = 0; guard < 4 * tn; guard++) {
		float t1 = std::min(1.0f, std::min(tx, tz));
		float ymin = a.y + dy * (dy > 0 ? t0 : t1);
		if (ymin < cmax[(size_t)cz * tn + cx]) {
			// внутри клетки — по точкам (концы отрезка не проверяем: там наблюдатель и цель)
			for (float t = std::max(t0, dt * 0.5f); t <= t1 && t < 1.0f - dt * 0.5f; t += dt) {
				if (a.y + dy * t < height(a.x + dx * t, a.z + dz * t)) {
					return false;
				}
			}
		}
		if (t1 >= 1.0f || (cx == ex && cz == ez)) {
			break;
		}
		t0 = t1;
		if (tx < tz) {
			tx += inv_x;
			cx += sx;
		} else {
			tz += inv_z;
			cz += sz;
		}
		if (cx < 0 || cz < 0 || cx >= tn || cz >= tn) {
			break;
		}
	}
	return true;
}

V3 Core::normal(float x, float z, float e) const {
	float nx = height(x - e, z) - height(x + e, z);
	float ny = 2.0f * e;
	float nz = height(x, z - e) - height(x, z + e);
	float l = std::sqrt(nx * nx + ny * ny + nz * nz);
	return { nx / l, ny / l, nz / l };
}

// ---------- Препятствия ----------

bool Core::blocked_at(float px, float py, float r) const {
	if (px < r || py < r || px > ws - r || py > ws - r) {
		return true;
	}
	int ia = ohash.key(px - r, false), ib = ohash.key(px + r, false);
	int ja = ohash.key(py - r, true), jb = ohash.key(py + r, true);
	for (int i = ia; i <= ib; i++) {
		for (int j = ja; j <= jb; j++) {
			const std::vector<int> *c = ohash.at(i, j);
			if (!c) {
				continue;
			}
			for (int k : *c) {
				const Rect &o = obst[k];
				if (px >= o.x - r && py >= o.y - r && px < o.x + o.w + r && py < o.y + o.h + r) {
					return true;
				}
			}
		}
	}
	return false;
}

bool Core::straight(V2 a, V2 b, float r) const {
	float dx = b.x - a.x, dy = b.y - a.y;
	int n = (int)(std::sqrt(dx * dx + dy * dy) / 12.0f) + 1;
	for (int s = 1; s <= n; s++) {
		float t = (float)s / n;
		if (blocked_at(a.x + dx * t, a.y + dy * t, r)) {
			return false;
		}
	}
	return true;
}

// ---------- Прямая видимость: рельеф + коробки построек (то же, что луч физики по слоям 1–2) ----------

static bool hits_box(const Box &b, V3 a, V3 d) {
	float ox = a.x - b.cx, oz = a.z - b.cz;
	float lo[3] = { b.c * ox - b.s * oz, a.y - b.cy, b.s * ox + b.c * oz };
	float ld[3] = { b.c * d.x - b.s * d.z, d.y, b.s * d.x + b.c * d.z };
	float hs[3] = { b.hx, b.hy, b.hz };
	float tmin = -FLT_MAX, tmax = FLT_MAX;
	for (int k = 0; k < 3; k++) {
		if (std::fabs(ld[k]) < 1e-9f) {
			if (lo[k] < -hs[k] || lo[k] > hs[k]) {
				return false;
			}
			continue;
		}
		float t1 = (-hs[k] - lo[k]) / ld[k];
		float t2 = (hs[k] - lo[k]) / ld[k];
		if (t1 > t2) {
			std::swap(t1, t2);
		}
		tmin = std::max(tmin, t1);
		tmax = std::min(tmax, t2);
		if (tmin > tmax) {
			return false;
		}
	}
	// начало внутри коробки физика не считает попаданием
	return tmin >= 0.0f && tmin <= 1.0f;
}

bool Core::los(V3 a, V3 b) const {
	V3 d = { b.x - a.x, b.y - a.y, b.z - a.z };
	if (!terrain_clear(a, b)) {
		return false;
	}
	if (boxes.empty()) {
		return true;
	}
	float minx = std::min(a.x, b.x), maxx = std::max(a.x, b.x);
	float minz = std::min(a.z, b.z), maxz = std::max(a.z, b.z);
	int ia = bhash.key(minx, false), ib = bhash.key(maxx, false);
	int ja = bhash.key(minz, true), jb = bhash.key(maxz, true);
	int tested[64];
	int nt = 0;
	for (int i = ia; i <= ib; i++) {
		for (int j = ja; j <= jb; j++) {
			const std::vector<int> *c = bhash.at(i, j);
			if (!c || c->empty()) {
				continue;
			}
			// клетка в стороне от отрезка — мимо
			float cx0 = (i + bhash.x0) * bhash.cell, cz0 = (j + bhash.y0) * bhash.cell;
			float t0 = 0.0f, t1 = 1.0f;
			bool miss = false;
			float o2[2] = { a.x, a.z }, d2[2] = { d.x, d.z }, lo2[2] = { cx0, cz0 };
			for (int k = 0; k < 2 && !miss; k++) {
				if (std::fabs(d2[k]) < 1e-9f) {
					miss = o2[k] < lo2[k] || o2[k] > lo2[k] + bhash.cell;
					continue;
				}
				float u1 = (lo2[k] - o2[k]) / d2[k], u2 = (lo2[k] + bhash.cell - o2[k]) / d2[k];
				if (u1 > u2) {
					std::swap(u1, u2);
				}
				t0 = std::max(t0, u1);
				t1 = std::min(t1, u2);
				miss = t0 > t1;
			}
			if (miss) {
				continue;
			}
			for (int k : *c) {
				bool seen = false;
				for (int q = 0; q < nt; q++) {
					if (tested[q] == k) {
						seen = true;
						break;
					}
				}
				if (seen) {
					continue;
				}
				if (nt < 64) {
					tested[nt++] = k;
				}
				if (hits_box(boxes[k], a, d)) {
					return false;
				}
			}
		}
	}
	return true;
}

// ---------- Сетка путей и A* (как AStarGrid2D: октильная эвристика, диагональ — если не срезает угол) ----------

static inline float octile(int dx, int dy) {
	dx = std::abs(dx);
	dy = std::abs(dy);
	const float F = 1.41421356f - 1.0f;
	return dx < dy ? F * dx + dy : F * dy + dx;
}

std::vector<V2> Core::nav_path(V2 from, V2 to, bool safe, float r) const {
	std::vector<V2> out;
	auto cell_of = [&](V2 p, int &cx, int &cy) {
		cx = std::min(std::max((int)(p.x / nav_cell), 0), nn - 1);
		cy = std::min(std::max((int)(p.y / nav_cell), 0), nn - 1);
	};
	auto free_cell = [&](int &cx, int &cy) {
		if (!solid[(size_t)cy * nn + cx]) {
			return;
		}
		for (int rr = 1; rr < 8; rr++) {
			for (int k = -rr; k <= rr; k++) {
				int cand[4][2] = { { cx + k, cy - rr }, { cx + k, cy + rr }, { cx - rr, cy + k }, { cx + rr, cy + k } };
				for (auto &a : cand) {
					if (a[0] >= 0 && a[1] >= 0 && a[0] < nn && a[1] < nn && !solid[(size_t)a[1] * nn + a[0]]) {
						cx = a[0];
						cy = a[1];
						return;
					}
				}
			}
		}
	};
	int sx, sy, ex, ey;
	cell_of(from, sx, sy);
	cell_of(to, ex, ey);
	free_cell(sx, sy);
	free_cell(ex, ey);
	const std::vector<float> &w = safe ? w_safe : w_norm;
	std::vector<int> ids;
	int start = sy * nn + sx, end = ey * nn + ex;
	if (!solid[start] && !solid[end]) {
		size_t total = (size_t)nn * nn;
		std::vector<float> g(total, FLT_MAX);
		std::vector<int> parent(total, -1);
		std::vector<uint8_t> closed(total, 0);
		struct Node {
			float f, g;
			int id;
		};
		// как у AStarGrid2D: меньший f; при равенстве — больший g (ближе к цели)
		auto cmp = [](const Node &a, const Node &b) { return a.f > b.f || (a.f == b.f && a.g < b.g); };
		std::priority_queue<Node, std::vector<Node>, decltype(cmp)> open(cmp);
		g[start] = 0.0f;
		open.push({ octile(ex - sx, ey - sy), 0.0f, start });
		int best = start;
		float best_h = octile(ex - sx, ey - sy), best_g = 0.0f;
		bool found = false;
		while (!open.empty()) {
			Node cur = open.top();
			open.pop();
			if (closed[cur.id]) {
				continue;
			}
			closed[cur.id] = 1;
			int cx = cur.id % nn, cy = cur.id / nn;
			float hh = octile(ex - cx, ey - cy);
			if (hh < best_h || (hh <= best_h && cur.g < best_g)) {
				best = cur.id;
				best_h = hh;
				best_g = cur.g;
			}
			if (cur.id == end) {
				found = true;
				break;
			}
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					if (!dx && !dy) {
						continue;
					}
					int nx = cx + dx, ny = cy + dy;
					if (nx < 0 || ny < 0 || nx >= nn || ny >= nn) {
						continue;
					}
					int nid = ny * nn + nx;
					if (solid[nid] || closed[nid]) {
						continue;
					}
					if (dx && dy && (solid[cy * nn + nx] || solid[ny * nn + cx])) {
						continue;
					}
					float ng = cur.g + octile(dx, dy) * w[nid];
					if (ng < g[nid]) {
						g[nid] = ng;
						parent[nid] = cur.id;
						open.push({ ng + octile(ex - nx, ey - ny), ng, nid });
					}
				}
			}
		}
		int tail = found ? end : best;
		for (int c = tail; c != -1; c = parent[c]) {
			ids.push_back(c);
			if (c == start) {
				break;
			}
		}
		std::reverse(ids.begin(), ids.end());
	}
	if (ids.size() < 2) {
		out.push_back(to);
		return out;
	}
	std::vector<V2> pts;
	pts.reserve(ids.size());
	for (int id : ids) {
		pts.push_back({ (id % nn + 0.5f) * nav_cell, (id / nn + 0.5f) * nav_cell });
	}
	if (!blocked_at(to.x, to.y, r)) {
		pts.back() = to;
	}
	// спрямление: из цепочки клеток остаются точки, между которыми едут по прямой
	V2 cur = from;
	size_t k = 1;
	while (k < pts.size()) {
		size_t far = k;
		size_t hi = std::min(pts.size() - 1, k + 14);
		for (size_t j = hi; j > k; j--) {
			if (straight(cur, pts[j], r * 0.8f)) {
				far = j;
				break;
			}
		}
		out.push_back(pts[far]);
		cur = pts[far];
		k = far + 1;
	}
	return out;
}

// ---------- Методы для GDScript ----------

#define METHOD(fn) static void fn(void *self_, const Args &a, GDExtensionVariantPtr r, GDExtensionCallError *e)
#define SELF Core *self = (Core *)self_; (void)self; (void)e

// Рельеф готовыми высотами: (heights, n, origin, cell, ws)
METHOD(terrain_set) {
	SELF;
	if (!need(a, 5, e)) return;
	self->h = f32(a, 0);
	self->tn = (int)a.integer(1);
	self->origin = (float)a.num(2);
	self->cell = (float)a.num(3);
	self->ws = (float)a.num(4);
	self->build_cmax();
}

METHOD(height) {
	SELF;
	if (!need(a, 2, e)) return;
	ret_float(r, self->height((float)a.num(0), (float)a.num(1)));
}

// Рельеф: шум, высоты и овраги, горы за краем, ровные зоны старта, площадки баз, фундаменты, воронки.
// (seeds: PackedInt32Array[3], relief, desert, edge, hills [ax,ay,bx,by,r,core,h]*, zones [x,y,r]*,
//  obst [x,y,w,h]*, craters [x,y,rad]*, n, origin, cell, ws) → основания построек
METHOD(terrain_generate) {
	SELF;
	if (!need(a, 12, e)) return;
	std::vector<int32_t> seeds = i32(a, 0);
	float relief = (float)a.num(1);
	bool desert = a.boolean(2);
	float edge = (float)a.num(3);
	std::vector<float> hills = f32(a, 4), zones = f32(a, 5), ob = f32(a, 6), craters = f32(a, 7);
	self->tn = (int)a.integer(8);
	self->origin = (float)a.num(9);
	self->cell = (float)a.num(10);
	self->ws = (float)a.num(11);
	if (seeds.size() < 3) seeds.resize(3, 0);
	int N = self->tn;
	float ws = self->ws;
	// частоты на 10 % ниже, чем у FastNoiseLite в GDScript-версии: у этого симплекс-шума
	// больше мелких перепадов, так уклоны выходят те же (проверено по картам)
	const float K = 0.9f;
	Fractal big(seeds[0], 0.0028f * K, 3, false), small(seeds[1], 0.02f * K, 5, false), ridge(seeds[2], 0.0016f * K, 5, true);
	auto hills_at = [&](float px, float py) {
		double v = 0.0;
		for (size_t k = 0; k + 6 < hills.size() + 0; k += 7) {
			float ax = hills[k], ay = hills[k + 1], bx = hills[k + 2], by = hills[k + 3], hr = hills[k + 4], core = hills[k + 5], hh = hills[k + 6];
			float sx = bx - ax, sy = by - ay;
			float l2 = sx * sx + sy * sy;
			float t = l2 > 0.0f ? clampf(((px - ax) * sx + (py - ay) * sy) / l2, 0.0f, 1.0f) : 0.0f;
			float cx = ax + sx * t, cy = ay + sy * t;
			float d = std::sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
			if (d < hr) {
				float u = clampf((d / hr - core) / (1.0f - core), 0.0f, 1.0f);
				v += hh * (1.0f - u * u * (3.0f - 2.0f * u));
			}
		}
		return v;
	};
	std::vector<float> &h = self->h;
	h.assign((size_t)(N + 1) * (N + 1), 0.0f);
	for (size_t i = 0; i < h.size(); i++) {
		float x = self->origin + (i % (N + 1)) * self->cell;
		float z = self->origin + (i / (N + 1)) * self->cell;
		double bn = big.get(x, z);
		double v = bn * relief + small.get(x, z) * relief * 0.08;
		if (desert) {
			v = std::fabs(bn) * relief * 1.3 - relief * 0.3 + small.get(x, z) * 1.5;
		}
		if (!hills.empty() && x > -300.0f && z > -300.0f && x < ws + 300.0f && z < ws + 300.0f) {
			v += hills_at(x, z);
		}
		// горы за краем игровой зоны
		float out = std::max(std::max(-x, x - ws), std::max(-z, z - ws));
		if (out > -150.0f) {
			float k = smoothstep(-150.0f, 450.0f, out);
			v += k * (90.0 + (ridge.get(x, z) * 0.5 + 0.5) * 140.0) * edge;
		}
		// зоны старта сглажены, переход к холмам длинный
		if (z < 660.0f || z > ws - 660.0f) {
			float dz = std::min(std::fabs(z - 260.0f), std::fabs(z - (ws - 260.0f)));
			v = lerpd(v, v * 0.25, 1.0 - smoothstep(60.0f, 400.0f, dz));
		}
		h[i] = (float)v;
	}
	auto window = [&](float x0, float y0, float x1, float y1, int w[4]) {
		w[0] = std::min(std::max((int)((x0 - self->origin) / self->cell), 0), N);
		w[1] = std::min(std::max((int)((x1 - self->origin) / self->cell) + 1, 0), N);
		w[2] = std::min(std::max((int)((y0 - self->origin) / self->cell), 0), N);
		w[3] = std::min(std::max((int)((y1 - self->origin) / self->cell) + 1, 0), N);
	};
	auto vx = [&](int ix) { return self->origin + ix * self->cell; };
	// ровные площадки под зонами захвата
	for (size_t k = 0; k + 2 < zones.size(); k += 3) {
		float zx = zones[k], zy = zones[k + 1], zr0 = zones[k + 2];
		float zr = zr0 + 110.0f;
		double on_hill = hills_at(zx, zy);
		double target = (self->height(zx, zy) - on_hill) * 0.4 + on_hill;
		int w[4];
		window(zx - zr, zy - zr, zx + zr, zy + zr, w);
		for (int iz = w[2]; iz <= w[3]; iz++) {
			for (int ix = w[0]; ix <= w[1]; ix++) {
				size_t i = (size_t)iz * (N + 1) + ix;
				float d = std::sqrt((vx(ix) - zx) * (vx(ix) - zx) + (vx(iz) - zy) * (vx(iz) - zy));
				h[i] = (float)lerpd(h[i], target, 1.0 - smoothstep(zr0 * 0.9f, zr, d));
			}
		}
	}
	// фундаменты построек
	std::vector<float> bases;
	for (size_t k = 0; k + 3 < ob.size(); k += 4) {
		float x0 = ob[k], y0 = ob[k + 1], x1 = ob[k] + ob[k + 2], y1 = ob[k + 1] + ob[k + 3];
		double target = (self->height(x0, y0) + self->height(x1, y1) + self->height(x0, y1) + self->height(x1, y0)) / 4.0;
		int w[4];
		window(x0 - 40.0f, y0 - 40.0f, x1 + 40.0f, y1 + 40.0f, w);
		for (int iz = w[2]; iz <= w[3]; iz++) {
			for (int ix = w[0]; ix <= w[1]; ix++) {
				size_t i = (size_t)iz * (N + 1) + ix;
				float px = vx(ix), pz = vx(iz);
				float dx = std::max(0.0f, std::max(x0 - px, px - x1));
				float dz = std::max(0.0f, std::max(y0 - pz, pz - y1));
				float kk = 1.0f - smoothstep(8.0f, 40.0f, std::sqrt(dx * dx + dz * dz));
				h[i] = (float)lerpd(h[i], target, kk);
			}
		}
		bases.push_back((float)target);
	}
	// воронки
	for (size_t k = 0; k + 2 < craters.size(); k += 3) {
		float cx = craters[k], cy = craters[k + 1], rad = craters[k + 2];
		int w[4];
		window(cx - rad * 1.4f, cy - rad * 1.4f, cx + rad * 1.4f, cy + rad * 1.4f, w);
		for (int iz = w[2]; iz <= w[3]; iz++) {
			for (int ix = w[0]; ix <= w[1]; ix++) {
				size_t i = (size_t)iz * (N + 1) + ix;
				float d = std::sqrt((vx(ix) - cx) * (vx(ix) - cx) + (vx(iz) - cy) * (vx(iz) - cy)) / rad;
				if (d < 1.0f) {
					h[i] -= rad * 0.22f * (1.0f - d * d);
				} else if (d < 1.35f) {
					h[i] += rad * 0.06f * std::sin((d - 1.0f) / 0.35f * 3.14159265f);
				}
			}
		}
	}
	self->build_cmax();
	ret_f32(r, bases.data(), bases.size());
}

METHOD(terrain_heights) {
	SELF;
	ret_f32(r, self->h.data(), self->h.size());
}

// Сетка рельефа для отрисовки: [вершины, нормали, индексы]
METHOD(terrain_mesh) {
	SELF;
	int N = self->tn;
	size_t nv = (size_t)(N + 1) * (N + 1);
	std::vector<V3> verts(nv), norms(nv);
	for (size_t i = 0; i < nv; i++) {
		float x = self->origin + (i % (N + 1)) * self->cell;
		float z = self->origin + (i / (N + 1)) * self->cell;
		verts[i] = { x, self->h[i], z };
		norms[i] = self->normal(x, z, self->cell);
	}
	std::vector<int32_t> idx;
	idx.reserve((size_t)N * N * 6);
	for (int iz = 0; iz < N; iz++) {
		for (int ix = 0; ix < N; ix++) {
			int32_t p = iz * (N + 1) + ix, q = p + 1, c = p + N + 1, d = c + 1;
			int32_t tri[6] = { p, q, c, q, d, c };
			idx.insert(idx.end(), tri, tri + 6);
		}
	}
	ArrayOut out(3);
	ret_v3s(out.at(0), verts.data(), verts.size());
	ret_v3s(out.at(1), norms.data(), norms.size());
	ret_i32(out.at(2), idx.data(), idx.size());
	out.to_variant(r);
}

// Высоты для HeightMapShape3D (квадрат клеток lo..hi, в долях шага)
METHOD(terrain_collision) {
	SELF;
	if (!need(a, 2, e)) return;
	int lo = (int)a.integer(0), hi = (int)a.integer(1);
	int n = hi - lo + 1, N = self->tn;
	std::vector<float> data((size_t)n * n);
	for (int iz = 0; iz < n; iz++) {
		for (int ix = 0; ix < n; ix++) {
			data[(size_t)iz * n + ix] = self->h[(size_t)(lo + iz) * (N + 1) + lo + ix] / self->cell;
		}
	}
	ret_f32(r, data.data(), data.size());
}

// Препятствия: [x, y, w, h, solid]*, ячейка сетки
METHOD(obst_set) {
	SELF;
	if (!need(a, 2, e)) return;
	std::vector<float> f = f32(a, 0);
	float hc = (float)a.num(1);
	self->obst.clear();
	float lo = -1000.0f, hi = self->ws + 1000.0f;
	for (size_t k = 0; k + 4 < f.size(); k += 5) {
		self->obst.push_back({ f[k], f[k + 1], f[k + 2], f[k + 3], f[k + 4] != 0.0f });
		lo = std::min(lo, std::min(f[k], f[k + 1]));
		hi = std::max(hi, std::max(f[k] + f[k + 2], f[k + 1] + f[k + 3]));
	}
	self->ohash.build(lo, hi, hc);
	for (size_t i = 0; i < self->obst.size(); i++) {
		const Rect &o = self->obst[i];
		self->ohash.put(o.x, o.y, o.x + o.w, o.y + o.h, (int)i);
	}
}

METHOD(blocked_at) {
	SELF;
	if (!need(a, 3, e)) return;
	ret_bool(r, self->blocked_at((float)a.num(0), (float)a.num(1), (float)a.num(2)));
}

METHOD(straight) {
	SELF;
	if (!need(a, 3, e)) return;
	ret_bool(r, self->straight(a.v2(0), a.v2(1), (float)a.num(2)));
}

// Коробки построек: [cx, cy, cz, sx, sy, sz, yaw]*
METHOD(boxes_set) {
	SELF;
	if (!need(a, 1, e)) return;
	std::vector<float> f = f32(a, 0);
	self->boxes.clear();
	float lo = -1000.0f, hi = self->ws + 1000.0f;
	for (size_t k = 0; k + 6 < f.size(); k += 7) {
		Box b = { f[k], f[k + 1], f[k + 2], f[k + 3] * 0.5f, f[k + 4] * 0.5f, f[k + 5] * 0.5f, std::cos(f[k + 6]), std::sin(f[k + 6]) };
		self->boxes.push_back(b);
		lo = std::min(lo, std::min(b.cx, b.cz) - 200.0f);
		hi = std::max(hi, std::max(b.cx, b.cz) + 200.0f);
	}
	self->bhash.build(lo, hi, 100.0f);
	for (size_t i = 0; i < self->boxes.size(); i++) {
		const Box &b = self->boxes[i];
		// описанный квадрат повёрнутой коробки
		float ex = std::fabs(b.c) * b.hx + std::fabs(b.s) * b.hz;
		float ez = std::fabs(b.s) * b.hx + std::fabs(b.c) * b.hz;
		self->bhash.put(b.cx - ex, b.cz - ez, b.cx + ex, b.cz + ez, (int)i);
	}
}

METHOD(los) {
	SELF;
	if (!need(a, 2, e)) return;
	ret_bool(r, self->los(a.v3(0), a.v3(1)));
}

// Засвет всех танков разом. На танк 16 чисел: команда, жив, подсвечен, x, z, глаз xyz, верх xyz,
// центр xyz, дальность обзора, в кусте/лесу. Ответ на пару (цель, команда): -1 — не виден,
// -2 — виден без наблюдателя (своя команда или подсвечен), иначе номер заметившего.
METHOD(spot) {
	SELF;
	if (!need(a, 2, e)) return;
	std::vector<float> f = f32(a, 0);
	float bush_range = (float)a.num(1);
	const int K = 16;
	int n = (int)(f.size() / K);
	std::vector<int32_t> res((size_t)n * 2, -1);
	for (int ei = 0; ei < n; ei++) {
		const float *E = &f[(size_t)ei * K];
		if (E[1] == 0.0f) {
			continue;
		}
		for (int team = 0; team < 2; team++) {
			int32_t &out = res[(size_t)ei * 2 + team];
			if ((int)E[0] == team || E[2] > 0.0f) {
				out = -2;
				continue;
			}
			for (int oi = 0; oi < n; oi++) {
				const float *O = &f[(size_t)oi * K];
				if (O[1] == 0.0f || (int)O[0] != team) {
					continue;
				}
				float dx = O[3] - E[3], dz = O[4] - E[4];
				float range = E[15] != 0.0f ? bush_range : O[14];
				if (dx * dx + dz * dz > range * range) {
					continue;
				}
				V3 eye = { O[5], O[6], O[7] };
				if (self->los(eye, { E[8], E[9], E[10] }) || self->los(eye, { E[11], E[12], E[13] })) {
					out = oi;
					break;
				}
			}
		}
	}
	ret_i32(r, res.data(), res.size());
}

// Сетка путей: (клетка, деревья PackedVector2Array, кусты [x,y,r]*) → [непроходимые, укрытия]
METHOD(nav_build) {
	SELF;
	if (!need(a, 3, e)) return;
	self->nav_cell = (float)a.num(0);
	std::vector<V2> trees = v2s(a, 1);
	std::vector<float> bushes = f32(a, 2);
	float NAV = self->nav_cell;
	int nn = (int)std::ceil(self->ws / NAV);
	self->nn = nn;
	size_t total = (size_t)nn * nn;
	self->solid.assign(total, 0);
	self->cover.assign(total, 0);
	self->w_norm.assign(total, 1.0f);
	self->w_safe.assign(total, 1.0f);
	Hash th, bh;
	th.build(-1000.0f, self->ws + 1000.0f, 100.0f);
	bh.build(-1000.0f, self->ws + 1000.0f, 100.0f);
	for (size_t i = 0; i < trees.size(); i++) {
		th.put(trees[i].x, trees[i].y, trees[i].x, trees[i].y, (int)i);
	}
	for (size_t k = 0; k + 2 < bushes.size(); k += 3) {
		float br = bushes[k + 2];
		bh.put(bushes[k] - br, bushes[k + 1] - br, bushes[k] + br, bushes[k + 1] + br, (int)(k / 3));
	}
	for (int y = 0; y < nn; y++) {
		for (int x = 0; x < nn; x++) {
			size_t c = (size_t)y * nn + x;
			float px = (x + 0.5f) * NAV, py = (y + 0.5f) * NAV;
			if (self->blocked_at(px, py, 13.0f)) {
				self->solid[c] = 1;
				continue;
			}
			float slope = 1.0f - self->normal(px, py, 14.0f).y;
			float w = 1.0f + clampf((slope - 0.06f) * 14.0f, 0.0f, 3.0f);
			int nt = 0;
			for (int i = th.key(px - 30.0f, false); i <= th.key(px + 30.0f, false); i++) {
				for (int j = th.key(py - 30.0f, true); j <= th.key(py + 30.0f, true); j++) {
					const std::vector<int> *cl = th.at(i, j);
					if (!cl) continue;
					for (int t : *cl) {
						float dx = trees[t].x - px, dy = trees[t].y - py;
						if (dx * dx + dy * dy < 900.0f) nt++;
					}
				}
			}
			bool cov = nt >= 2;
			if (!cov) {
				const std::vector<int> *cl = bh.at(bh.key(px, false), bh.key(py, true));
				if (cl) {
					for (int b : *cl) {
						float dx = bushes[b * 3] - px, dy = bushes[b * 3 + 1] - py, br = bushes[b * 3 + 2];
						if (dx * dx + dy * dy < br * br) {
							cov = true;
							break;
						}
					}
				}
			}
			if (!cov) {
				for (int i = self->ohash.key(px - 45.0f, false); i <= self->ohash.key(px + 45.0f, false) && !cov; i++) {
					for (int j = self->ohash.key(py - 45.0f, true); j <= self->ohash.key(py + 45.0f, true) && !cov; j++) {
						const std::vector<int> *cl = self->ohash.at(i, j);
						if (!cl) continue;
						for (int k : *cl) {
							const Rect &o = self->obst[k];
							if (o.solid && px >= o.x - 45.0f && py >= o.y - 45.0f && px < o.x + o.w + 45.0f && py < o.y + o.h + 45.0f) {
								cov = true;
								break;
							}
						}
					}
				}
			}
			self->cover[c] = cov ? 1 : 0;
			w += 0.3f * std::min(nt, 3);
			self->w_norm[c] = w;
			self->w_safe[c] = w * (cov ? 1.0f : 3.0f);
		}
	}
	ArrayOut out(2);
	ret_bytes(out.at(0), self->solid.data(), total);
	ret_bytes(out.at(1), self->cover.data(), total);
	out.to_variant(r);
}

// Маршрут: (откуда, куда, под огнём, радиус) → точки
METHOD(nav_path) {
	SELF;
	if (!need(a, 4, e)) return;
	if (self->nn == 0) {
		V2 to = a.v2(1);
		ret_v2s(r, &to, 1);
		return;
	}
	std::vector<V2> p = self->nav_path(a.v2(0), a.v2(1), a.boolean(2), (float)a.num(3));
	ret_v2s(r, p.data(), p.size());
}

// Маска грунта: (байты RGBA8 — можно с мипмапами, берётся нулевой уровень; сторона; сторона рельефа)
METHOD(mask_set) {
	SELF;
	if (!need(a, 3, e)) return;
	self->mask = bytes(a, 0);
	self->mask_w = (int)a.integer(1);
	self->tsize = (float)a.num(2);
}

// Трава одного участка карты (как MapGen._grass): (x0, z0, сторона, сколько, зерно) →
// [буфер MultiMesh (3D-преобразование + цвет, 16 чисел на пучок), сколько поставлено]
METHOD(grass_chunk) {
	SELF;
	if (!need(a, 5, e)) return;
	float x0 = (float)a.num(0), z0 = (float)a.num(1), cs = (float)a.num(2);
	int per = (int)a.integer(3);
	uint32_t st = (uint32_t)a.integer(4) * 747796405u + 2891336453u;
	auto rnd = [&]() {  // PCG-подобный: 0…1
		st = st * 747796405u + 2891336453u;
		uint32_t w = ((st >> ((st >> 28u) + 4u)) ^ st) * 277803737u;
		return ((w >> 22u) ^ w) / 4294967296.0f;
	};
	auto range = [&](float lo, float hi) { return lo + (hi - lo) * rnd(); };
	std::vector<float> buf((size_t)per * 16, 0.0f);
	int placed = 0;
	for (int t = 0; t < per * 3 && placed < per; t++) {
		float px = x0 + rnd() * cs, pz = z0 + rnd() * cs;
		// не в постройке (как _blocked: прямоугольник с запасом 3, без границ поля)
		bool blocked = false;
		for (int i = self->ohash.key(px - 3.0f, false); i <= self->ohash.key(px + 3.0f, false) && !blocked; i++) {
			for (int j = self->ohash.key(pz - 3.0f, true); j <= self->ohash.key(pz + 3.0f, true) && !blocked; j++) {
				const std::vector<int> *cl = self->ohash.at(i, j);
				if (!cl) continue;
				for (int k : *cl) {
					const Rect &o = self->obst[k];
					if (px >= o.x - 3.0f && pz >= o.y - 3.0f && px < o.x + o.w + 3.0f && pz < o.y + o.h + 3.0f) {
						blocked = true;
						break;
					}
				}
			}
		}
		if (blocked) continue;
		// не на дороге и не в гари
		if (self->mask_w > 0) {
			int W = self->mask_w;
			int mx = std::min(std::max((int)((px - self->origin) / self->tsize * W), 0), W - 1);
			int mz = std::min(std::max((int)((pz - self->origin) / self->tsize * W), 0), W - 1);
			size_t mi = ((size_t)mz * W + mx) * 4;
			if (mi + 1 < self->mask.size() && (self->mask[mi] / 255.0f > 0.35f || self->mask[mi + 1] / 255.0f > 0.4f)) continue;
		}
		float s = range(0.7f, 1.4f);
		float sy = s * range(0.8f, 1.3f);
		float ang = rnd() * 6.2831853f;
		float c = std::cos(ang), sn = std::sin(ang);
		float *B = &buf[(size_t)placed * 16];
		// строки базиса Basis(UP, ang).scaled(s, sy, s) и начало
		B[0] = s * c; B[1] = 0.0f; B[2] = s * sn; B[3] = px;
		B[4] = 0.0f; B[5] = sy; B[6] = 0.0f; B[7] = self->height(px, pz) - 0.2f;
		B[8] = -s * sn; B[9] = 0.0f; B[10] = s * c; B[11] = pz;
		// цвет Color.from_hsv(-0.04…0.04, 0…0.2, 0.8…1.15)
		float hh = range(-0.04f, 0.04f) * 6.0f, sat = range(0.0f, 0.2f), v = range(0.8f, 1.15f);
		if (hh < 0.0f) hh += 6.0f;
		int hi = (int)std::floor(hh);
		float f = hh - hi, p = v * (1.0f - sat), q = v * (1.0f - sat * f), tt = v * (1.0f - sat * (1.0f - f));
		float rr, gg, bb;
		switch (hi) {
			case 0: rr = v; gg = tt; bb = p; break;
			case 1: rr = q; gg = v; bb = p; break;
			case 2: rr = p; gg = v; bb = tt; break;
			case 3: rr = p; gg = q; bb = v; break;
			case 4: rr = tt; gg = p; bb = v; break;
			default: rr = v; gg = p; bb = q; break;
		}
		B[12] = rr; B[13] = gg; B[14] = bb; B[15] = 1.0f;
		placed++;
	}
	ArrayOut out(2);
	ret_f32(out.at(0), buf.data(), buf.size());
	ret_int(out.at(1), placed);
	out.to_variant(r);
}

// ---------- Слияние геометрии (Geo.Group.add) ----------
// (вершины, нормали, uv, индексы, параметры [базис x,y,z, начало (12), плоские, есть uv_over, uv_over xy])
// → [вершины, нормали, uv] без индексов
METHOD(geo_add) {
	(void)self_;
	if (!need(a, 5, e)) return;
	std::vector<V3> verts = v3s(a, 0), norms = v3s(a, 1);
	std::vector<V2> uvs = v2s(a, 2);
	std::vector<int32_t> idx = i32(a, 3);
	std::vector<float> p = f32(a, 4);
	if (p.size() < 16) p.resize(16, 0.0f);
	const float *B = p.data();  // столбцы: B[0..2] — x, B[3..5] — y, B[6..8] — z, B[9..11] — начало
	bool flat = p[12] != 0.0f;
	bool over = p[13] != 0.0f;
	V2 uv_over = { p[14], p[15] };
	auto xf = [&](V3 v) {
		return V3{ B[0] * v.x + B[3] * v.y + B[6] * v.z + B[9], B[1] * v.x + B[4] * v.y + B[7] * v.z + B[10],
			B[2] * v.x + B[5] * v.y + B[8] * v.z + B[11] };
	};
	// нормали — обратной транспонированной матрицей
	float m00 = B[0], m01 = B[3], m02 = B[6], m10 = B[1], m11 = B[4], m12 = B[7], m20 = B[2], m21 = B[5], m22 = B[8];
	float c00 = m11 * m22 - m12 * m21, c01 = m12 * m20 - m10 * m22, c02 = m10 * m21 - m11 * m20;
	float c10 = m02 * m21 - m01 * m22, c11 = m00 * m22 - m02 * m20, c12 = m01 * m20 - m00 * m21;
	float c20 = m01 * m12 - m02 * m11, c21 = m02 * m10 - m00 * m12, c22 = m00 * m11 - m01 * m10;
	float det = m00 * c00 + m01 * c01 + m02 * c02;
	float id = std::fabs(det) > 1e-12f ? 1.0f / det : 0.0f;
	// (M⁻¹)ᵀ = cof(M) / det
	auto nb = [&](V3 n) {
		return V3{ (c00 * n.x + c01 * n.y + c02 * n.z) * id, (c10 * n.x + c11 * n.y + c12 * n.z) * id,
			(c20 * n.x + c21 * n.y + c22 * n.z) * id };
	};
	auto norm = [](V3 v) {
		float l = std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
		return l > 0.0f ? V3{ v.x / l, v.y / l, v.z / l } : v;
	};
	size_t n = idx.empty() ? verts.size() : idx.size();
	n -= n % 3;
	std::vector<V3> ov(n), on(n);
	std::vector<V2> ou(n);
	for (size_t t = 0; t < n; t += 3) {
		int ids[3];
		for (int k = 0; k < 3; k++) {
			ids[k] = idx.empty() ? (int)(t + k) : idx[t + k];
		}
		V3 face = { 0, 0, 0 };
		if (flat) {
			V3 A = xf(verts[ids[0]]), Bv = xf(verts[ids[1]]), C = xf(verts[ids[2]]);
			V3 u = { Bv.x - A.x, Bv.y - A.y, Bv.z - A.z }, w = { C.x - A.x, C.y - A.y, C.z - A.z };
			face = { u.y * w.z - u.z * w.y, u.z * w.x - u.x * w.z, u.x * w.y - u.y * w.x };
			V3 avg;
			if (!norms.empty()) {
				V3 s = { norms[ids[0]].x + norms[ids[1]].x + norms[ids[2]].x, norms[ids[0]].y + norms[ids[1]].y + norms[ids[2]].y,
					norms[ids[0]].z + norms[ids[1]].z + norms[ids[2]].z };
				avg = nb(s);
			} else {
				avg = { (A.x + Bv.x + C.x) / 3.0f - B[9], (A.y + Bv.y + C.y) / 3.0f - B[10], (A.z + Bv.z + C.z) / 3.0f - B[11] };
			}
			if (face.x * avg.x + face.y * avg.y + face.z * avg.z < 0.0f) {
				face = { -face.x, -face.y, -face.z };
			}
			face = norm(face);
		}
		for (int k = 0; k < 3; k++) {
			int i = ids[k];
			ov[t + k] = xf(verts[i]);
			if (flat) {
				on[t + k] = face;
			} else if (!norms.empty()) {
				on[t + k] = norm(nb(norms[i]));
			} else {
				on[t + k] = { 0.0f, 1.0f, 0.0f };
			}
			ou[t + k] = over ? uv_over : (uvs.empty() ? V2{ 0.0f, 0.0f } : uvs[i]);
		}
	}
	ArrayOut out(3);
	ret_v3s(out.at(0), ov.data(), ov.size());
	ret_v3s(out.at(1), on.data(), on.size());
	ret_v2s(out.at(2), ou.data(), ou.size());
	out.to_variant(r);
}

// Масштаб всех точек (грани формы попаданий)
METHOD(scale_v3) {
	(void)self_;
	if (!need(a, 2, e)) return;
	std::vector<V3> v = v3s(a, 0);
	float s = (float)a.num(1);
	for (V3 &p : v) {
		p = { p.x * s, p.y * s, p.z * s };
	}
	ret_v3s(r, v.data(), v.size());
}

// ---------- Процедурные текстуры ----------

struct Col {
	float r, g, b;
	Col lerp(Col o, float t) const { return { r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t }; }
	Col darkened(float k) const { return { r * (1.0f - k), g * (1.0f - k), b * (1.0f - k) }; }
	Col lightened(float k) const { return { r + (1.0f - r) * k, g + (1.0f - g) * k, b + (1.0f - b) * k }; }
};

static Col hex(uint32_t v) {
	return { ((v >> 16) & 255) / 255.0f, ((v >> 8) & 255) / 255.0f, (v & 255) / 255.0f };
}

static inline uint8_t to8(float v) {
	return (uint8_t)clampf(v * 255.0f, 0.0f, 255.0f);
}

// Камуфляж: (вид, шум a, шум b, шум g — L8 одного размера) → RGB8.
// Виды — в порядке tank_models.gd CAMO_KINDS.
enum Camo { OLIVE, GERMAN, DESERT, GERMAN44, DAK, BRITISH, GREY_WINTER, WHITEWASH, ITALY, WASH44, OLIVE_WASH, HUNGARY };

METHOD(camo) {
	(void)self_;
	if (!need(a, 4, e)) return;
	int kind = (int)a.integer(0);
	std::vector<uint8_t> A = bytes(a, 1), Bn = bytes(a, 2), G = bytes(a, 3);
	size_t n = std::min(A.size(), std::min(Bn.size(), G.size()));
	static const uint32_t bases[] = { 0x464a2f, 0xa8956a, 0xc4b38a, 0xad9a68, 0x9c8358, 0x4f4b34, 0x4b5155, 0x3f4c2b, 0xb9a170,
		0xad9a68, 0x464a2f, 0x6b6a42 };
	Col base = kind >= 0 && kind < 12 ? hex(bases[kind]) : hex(0x3f4c2b);
	std::vector<uint8_t> out(n * 3);
	for (size_t i = 0; i < n; i++) {
		float va = A[i] / 255.0f, vb = Bn[i] / 255.0f, vg = G[i] / 255.0f;
		Col c = base;
		if (kind == GERMAN) {
			float s1 = smoothstep(0.075f, 0.035f, std::fabs(va - 0.5f));
			float s2 = smoothstep(0.06f, 0.025f, std::fabs(vb - 0.44f));
			c = c.lerp(hex(0x4f5935), s1 * 0.9f);
			c = c.lerp(hex(0x5e3b26), s2 * 0.85f);
		} else if (kind == DESERT) {
			c = c.lerp(hex(0x5c5a40), smoothstep(0.6f, 0.63f, va) * 0.9f);
			c = c.darkened((vb - 0.5f) * 0.12f);
		} else if (kind == GERMAN44 || kind == WASH44) {
			float s1 = smoothstep(0.56f, 0.6f, va);
			float s2 = smoothstep(0.58f, 0.62f, vb) * (1.0f - s1);
			c = c.lerp(hex(0x47522f), s1 * 0.95f);
			c = c.lerp(hex(0x6a3a24), s2 * 0.9f);
			float dots = smoothstep(0.78f, 0.82f, vg) * std::max(s1, s2);
			c = c.lerp(hex(0xb8a470), dots * 0.9f);
		} else if (kind == HUNGARY) {
			float s1 = smoothstep(0.57f, 0.61f, va);
			float s2 = smoothstep(0.6f, 0.64f, vb) * (1.0f - s1);
			c = c.lerp(hex(0xa08a52), s1 * 0.9f);
			c = c.lerp(hex(0x5a3f2a), s2 * 0.85f);
			c = c.darkened((vg - 0.5f) * 0.08f);
		} else if (kind == ITALY) {
			c = c.lightened(clampf((va - 0.55f) * 0.35f, 0.0f, 0.1f));
			c = c.darkened(clampf((0.45f - vb) * 0.3f, 0.0f, 0.08f));
		} else if (kind == DAK) {
			c = c.lerp(hex(0x6b6a52), smoothstep(0.62f, 0.66f, vb) * 0.85f);
			c = c.darkened((va - 0.5f) * 0.15f);
		} else if (kind != GREY_WINTER && kind != WHITEWASH) {
			c = c.darkened((va - 0.5f) * 0.22f);
			c = c.lightened(clampf((vb - 0.7f) * 0.6f, 0.0f, 0.12f));
		}
		if (kind == GREY_WINTER || kind == WHITEWASH || kind == WASH44 || kind == OLIVE_WASH) {
			float wash = smoothstep(0.36f, 0.52f, va * 0.75f + vg * 0.25f);
			if (kind == WASH44 || kind == OLIVE_WASH) {
				wash = smoothstep(0.44f, 0.58f, va * 0.7f + vb * 0.15f + vg * 0.15f);
			}
			c = c.darkened((vb - 0.5f) * 0.15f);
			c = c.lerp(hex(0xdcdfdc).darkened((vg - 0.5f) * 0.12f), wash * 0.92f);
		}
		c = c.lightened((vg - 0.5f) * 0.08f);
		out[i * 3] = to8(c.r);
		out[i * 3 + 1] = to8(c.g);
		out[i * 3 + 2] = to8(c.b);
	}
	ret_bytes(r, out.data(), out.size());
}

// Потёки грязи: (шум L8, сторона) → L8
METHOD(grime) {
	(void)self_;
	if (!need(a, 2, e)) return;
	std::vector<uint8_t> src = bytes(a, 0);
	int S = (int)a.integer(1);
	std::vector<uint8_t> out((size_t)S * S, 0);
	if (src.size() < out.size()) {
		ret_bytes(r, out.data(), out.size());
		return;
	}
	for (int x = 0; x < S; x++) {
		float streak = 0.0f;
		for (int y = 0; y < S; y++) {
			float v = src[(size_t)y * S + x] / 255.0f;
			streak = std::max(streak * 0.97f, v - 0.55f);
			out[(size_t)y * S + x] = to8(clampf(v - streak * 0.8f, 0.0f, 1.0f));
		}
	}
	ret_bytes(r, out.data(), out.size());
}

// ---------- Регистрация ----------

static void *create_core() { return new Core(); }
static void destroy_core(void *p) { delete (Core *)p; }

void register_core(GDExtensionClassLibraryPtr lib) {
	const char *C = "SteelCore";
	register_class(lib, C, "RefCounted", create_core, destroy_core);
	struct {
		const char *name;
		Method m;
	} methods[] = {
		{ "terrain_set", terrain_set }, { "height", height }, { "terrain_generate", terrain_generate },
		{ "terrain_heights", terrain_heights }, { "terrain_mesh", terrain_mesh }, { "terrain_collision", terrain_collision },
		{ "obst_set", obst_set }, { "blocked_at", blocked_at }, { "straight", straight }, { "boxes_set", boxes_set },
		{ "los", los }, { "spot", spot }, { "nav_build", nav_build }, { "nav_path", nav_path }, { "geo_add", geo_add },
		{ "scale_v3", scale_v3 }, { "camo", camo }, { "grime", grime }, { "mask_set", mask_set }, { "grass_chunk", grass_chunk },
	};
	for (auto &m : methods) {
		register_method(lib, C, m.name, m.m);
	}
}

// ---------- Точка входа ----------

static GDExtensionClassLibraryPtr library = nullptr;

static void initialize(void *, GDExtensionInitializationLevel level) {
	if (level == GDEXTENSION_INITIALIZATION_SCENE) {
		register_core(library);
	}
}

static void deinitialize(void *, GDExtensionInitializationLevel) {}

extern "C" __attribute__((visibility("default"))) GDExtensionBool steel_core_init(GDExtensionInterfaceGetProcAddress p_get_proc,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_init) {
	gd::load(p_get_proc);
	library = p_library;
	r_init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_init->userdata = nullptr;
	r_init->initialize = initialize;
	r_init->deinitialize = deinitialize;
	return 1;
}
