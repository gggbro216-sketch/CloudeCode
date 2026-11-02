// Текстуры рельефа (как Terrain._paint_mask/_paint_ao) и запекание миникарты (как Hud._bake_minimap):
// картинки рисуются кистями по пикселю — в GDScript это самые медленные места загрузки боя.
#include "common.h"

#include <cstring>

namespace {

struct RGBA {
	float r, g, b, a;
};

static inline uint8_t q8(float v) { return (uint8_t)(clampf(v, 0.0f, 1.0f) * 255.0f + 0.5f); }

// Картинка RGBA8, как Image: кисти смешиваются как Image.blend_rect (Color.blend поверх).
struct Img {
	int w = 0, h = 0;
	std::vector<uint8_t> px;
	Img(int p_w, int p_h, RGBA fill) : w(p_w), h(p_h), px((size_t)p_w * p_h * 4) {
		uint8_t c[4] = { q8(fill.r), q8(fill.g), q8(fill.b), q8(fill.a) };
		for (size_t i = 0; i < px.size(); i += 4) {
			memcpy(&px[i], c, 4);
		}
	}
	RGBA get(int x, int y) const {
		const uint8_t *p = &px[((size_t)y * w + x) * 4];
		return { p[0] / 255.0f, p[1] / 255.0f, p[2] / 255.0f, p[3] / 255.0f };
	}
	void set(int x, int y, RGBA c) {
		uint8_t *p = &px[((size_t)y * w + x) * 4];
		p[0] = q8(c.r);
		p[1] = q8(c.g);
		p[2] = q8(c.b);
		p[3] = q8(c.a);
	}
	void fill_rect(int x0, int y0, int rw, int rh, RGBA c) {
		int x1 = std::min(w, x0 + rw), y1 = std::min(h, y0 + rh);
		for (int y = std::max(0, y0); y < y1; y++) {
			for (int x = std::max(0, x0); x < x1; x++) {
				set(x, y, c);
			}
		}
	}
	// Color.blend: src поверх dst с учётом прозрачности обоих
	static RGBA blend(RGBA d, RGBA s) {
		float sa = 1.0f - s.a;
		RGBA o;
		o.a = d.a * sa + s.a;
		if (o.a == 0.0f) {
			return { 0, 0, 0, 0 };
		}
		o.r = (d.r * d.a * sa + s.r * s.a) / o.a;
		o.g = (d.g * d.a * sa + s.g * s.a) / o.a;
		o.b = (d.b * d.a * sa + s.b * s.a) / o.a;
		return o;
	}
	void blend_rect(const Img &src, int x0, int y0) {
		for (int y = 0; y < src.h; y++) {
			int ty = y0 + y;
			if (ty < 0 || ty >= h) continue;
			for (int x = 0; x < src.w; x++) {
				int tx = x0 + x;
				if (tx < 0 || tx >= w) continue;
				if (src.px[((size_t)y * src.w + x) * 4 + 3] == 0) continue;
				set(tx, ty, blend(get(tx, ty), src.get(x, y)));
			}
		}
	}
	const std::vector<uint8_t> &bytes() const { return px; }
};

// Круглая кисть (как Terrain._brush): цвет, прозрачность спадает к краю; хранится 8-битной, как Image.
Img brush(int r, RGBA c) {
	int s = r * 2 + 1;
	Img img(s, s, { 0, 0, 0, 0 });
	for (int y = 0; y < s; y++) {
		for (int x = 0; x < s; x++) {
			float d = std::sqrt((float)((x - r) * (x - r) + (y - r) * (y - r))) / (float)r;
			RGBA col = c;
			col.a = c.a * (1.0f - smoothstep(0.55f, 1.0f, d));
			img.set(x, y, col);
		}
	}
	return img;
}

struct BrushCache {
	std::vector<std::pair<long long, Img>> items;
	const Img &get(int r, RGBA c, int tag) {
		long long key = (long long)r * 1000 + tag;
		for (auto &it : items) {
			if (it.first == key) return it.second;
		}
		items.push_back({ key, brush(r, c) });
		return items.back().second;
	}
};

RGBA lightened(RGBA c, float k) { return { c.r + (1.0f - c.r) * k, c.g + (1.0f - c.g) * k, c.b + (1.0f - c.b) * k, c.a }; }
RGBA darkened(RGBA c, float k) { return { c.r * (1.0f - k), c.g * (1.0f - k), c.b * (1.0f - k), c.a }; }

RGBA col_at(const std::vector<float> &f, size_t i) {
	if (i * 4 + 3 >= f.size()) return { 0, 0, 0, 1 };
	return { f[i * 4], f[i * 4 + 1], f[i * 4 + 2], f[i * 4 + 3] };
}

} // namespace

// Маска шейдера земли (S×S, RGBA8): R — дороги, G — гарь воронок, B — пахота и битый кирпич.
// (S, поля с бороздами, пыль кварталов, дороги [точек, ширина, x0, z0, …]*, воронки [x, z, r]*).
// Маска запоминается и для грунта под гусеницами (как mask_set).
METHOD(paint_mask) {
	SELF;
	if (!need(a, 5, e)) return;
	int S = (int)clampf((float)a.integer(0), 16.0f, 4096.0f);
	bool fields = a.boolean(1), dust = a.boolean(2);
	std::vector<float> roads = f32(a, 3), craters = f32(a, 4);
	float size = self->tn * self->cell, origin = self->origin, ws = self->ws;
	float k = S / std::max(size, 1.0f);
	Img m(S, S, { 0, 0, 0, 1 });
	if (fields) {
		// поля с бороздами
		for (int f = 0; f < 24; f++) {
			int fx = (int)((self->randf() * ws - origin) * k);
			int fz = (int)((self->randf() * ws - origin) * k);
			int fw = (int)((150.0f + self->randf() * 260.0f) * k);
			int fh = (int)((150.0f + self->randf() * 260.0f) * k);
			for (int s = 0; s < fw; s += 3) {
				m.fill_rect(fx + s, fz, 1, fh, { 0, 0, 0.55f, 1 });
			}
		}
	}
	BrushCache bc;
	if (dust) {
		// пыль и битый кирпич в кварталах и на пустырях
		const Img &br = bc.get((int)(60.0f * k), { 0, 0, 0.8f, 0.7f }, 1);
		for (int f = 0; f < 100; f++) {
			int px = (int)((self->randf() * ws - origin) * k);
			int pz = (int)((self->randf() * ws - origin) * k);
			m.blend_rect(br, px, pz);
		}
	}
	for (size_t q = 0; q + 1 < roads.size();) {
		int n = (int)roads[q];
		float w = roads[q + 1];
		size_t p0 = q + 2;
		q = p0 + (size_t)std::max(0, n) * 2;
		if (n < 2 || q > roads.size()) break;
		int br = std::max(2, (int)(w * 0.5f * k));
		const Img &b = bc.get(br, { 1, 0, 0, 0.9f }, 2);
		for (int i = 0; i + 1 < n; i++) {
			float ax = roads[p0 + i * 2], ay = roads[p0 + i * 2 + 1], bx = roads[p0 + i * 2 + 2], by = roads[p0 + i * 2 + 3];
			float len = std::sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
			int steps = std::max(1, (int)(len * k / (br * 0.5f)));
			steps = std::min(steps, 20000);
			for (int s = 0; s <= steps; s++) {
				float t = (float)s / steps;
				float px = ax + (bx - ax) * t, py = ay + (by - ay) * t;
				m.blend_rect(b, (int)((px - origin) * k) - br, (int)((py - origin) * k) - br);
			}
		}
	}
	for (size_t q = 0; q + 2 < craters.size(); q += 3) {
		int br = std::max(2, (int)(craters[q + 2] * 1.5f * k));
		const Img &b = bc.get(br, { 0, 1, 0, 0.85f }, 3);
		m.blend_rect(b, (int)((craters[q] - origin) * k) - br, (int)((craters[q + 1] - origin) * k) - br);
	}
	const std::vector<uint8_t> &out = m.bytes();
	self->mask = out;
	self->mask_w = S;
	self->tsize = size;
	ret_bytes(r, out.data(), (int64_t)out.size());
}

// Карта затенения (S×S, RGBA8): тёмные ореолы у оснований построек и под кустами.
// (S, постройки [x, z, ширина, глубина, сплошная]*, точки [x, z, радиус]*).
METHOD(paint_ao) {
	SELF;
	if (!need(a, 3, e)) return;
	int S = (int)clampf((float)a.integer(0), 16.0f, 4096.0f);
	std::vector<float> ob = f32(a, 1), pts = f32(a, 2);
	float size = self->tn * self->cell, origin = self->origin;
	float k = S / std::max(size, 1.0f);
	Img m(S, S, { 1, 1, 1, 1 });
	BrushCache bc;
	auto stamp = [&](float x, float z, float rad, float strength) {
		int br = std::max(2, (int)(rad * k));
		const Img &b = bc.get(br, { 0, 0, 0, strength }, (int)(strength * 100.0f));
		m.blend_rect(b, (int)((x - origin) * k) - br, (int)((z - origin) * k) - br);
	};
	for (size_t q = 0; q + 4 < ob.size(); q += 5) {
		float x0 = ob[q], z0 = ob[q + 1], x1 = ob[q] + ob[q + 2], z1 = ob[q + 1] + ob[q + 3];
		float strength = ob[q + 4] != 0.0f ? 0.45f : 0.25f;
		const float step = 9.0f;
		if (!(x1 - x0 < 1e5f) || !(z1 - z0 < 1e5f)) continue;
		for (float x = x0; x <= x1; x += step) {
			stamp(x, z0, 12.0f, strength);
			stamp(x, z1, 12.0f, strength);
		}
		for (float z = z0; z <= z1; z += step) {
			stamp(x0, z, 12.0f, strength);
			stamp(x1, z, 12.0f, strength);
		}
	}
	for (size_t q = 0; q + 2 < pts.size(); q += 3) {
		stamp(pts[q], pts[q + 1], pts[q + 2], 0.35f);
	}
	const std::vector<uint8_t> &out = m.bytes();
	ret_bytes(r, out.data(), (int64_t)out.size());
}

// Неподвижный слой миникарты (S×S, RGBA8): отмывка склонов по сетке рельефа, дороги из маски,
// постройки и изгороди, кусты и лес. (S, цвета [фон, дорога, постройка, изгородь, куст, дерево] по
// 4 числа, постройки [x, z, ширина, глубина, изгородь]*, пятна [x, z, радиус, дерево]*).
METHOD(minimap) {
	SELF;
	if (!need(a, 4, e)) return;
	int S = (int)clampf((float)a.integer(0), 16.0f, 2048.0f);
	std::vector<float> cols = f32(a, 1), ob = f32(a, 2), dots = f32(a, 3);
	RGBA bg = col_at(cols, 0), road = col_at(cols, 1), oc = col_at(cols, 2), hedge = col_at(cols, 3), leaf = col_at(cols, 4), tree = col_at(cols, 5);
	float ws = self->ws, k = S / ws;
	int row = self->tn + 1;
	int n0 = (int)(-self->origin / self->cell);
	int cells = (int)(ws / self->cell);
	std::vector<RGBA> shade((size_t)std::max(cells, 0) * std::max(cells, 0), bg);
	if (!self->h.empty() && cells > 2 && n0 >= 1 && n0 + cells + 1 < row) {
		// свет с северо-запада: склоны к нему светлее, от него темнее
		for (int y = 0; y < cells; y++) {
			for (int x = 0; x < cells; x++) {
				size_t i = (size_t)(n0 + y) * row + n0 + x;
				const std::vector<float> &h = self->h;
				float g = (h[i + 1] - h[i - 1]) + (h[i + row] - h[i - row]);
				RGBA c = darkened(lightened(bg, clampf(-g * 0.03f, 0.0f, 0.25f)), clampf(g * 0.03f, 0.0f, 0.3f));
				c.a = 0.88f;
				shade[(size_t)y * cells + x] = c;
			}
		}
	}
	// растяжка до размера миникарты (билинейная, по центрам пикселей — как Image.resize)
	Img img(S, S, bg);
	if (cells > 0) {
		for (int y = 0; y < S; y++) {
			float sy = clampf((y + 0.5f) * cells / S - 0.5f, 0.0f, cells - 1.0f);
			int y0 = (int)sy, y1 = std::min(y0 + 1, cells - 1);
			float ty = sy - y0;
			for (int x = 0; x < S; x++) {
				float sx = clampf((x + 0.5f) * cells / S - 0.5f, 0.0f, cells - 1.0f);
				int x0 = (int)sx, x1 = std::min(x0 + 1, cells - 1);
				float tx = sx - x0;
				const RGBA &a00 = shade[(size_t)y0 * cells + x0], &a10 = shade[(size_t)y0 * cells + x1];
				const RGBA &a01 = shade[(size_t)y1 * cells + x0], &a11 = shade[(size_t)y1 * cells + x1];
				RGBA c;
				c.r = (a00.r * (1 - tx) + a10.r * tx) * (1 - ty) + (a01.r * (1 - tx) + a11.r * tx) * ty;
				c.g = (a00.g * (1 - tx) + a10.g * tx) * (1 - ty) + (a01.g * (1 - tx) + a11.g * tx) * ty;
				c.b = (a00.b * (1 - tx) + a10.b * tx) * (1 - ty) + (a01.b * (1 - tx) + a11.b * tx) * ty;
				c.a = (a00.a * (1 - tx) + a10.a * tx) * (1 - ty) + (a01.a * (1 - tx) + a11.a * tx) * ty;
				img.set(x, y, c);
			}
		}
	}
	// дороги — по маске рельефа
	int mw = self->mask_w;
	if (mw > 0 && self->mask.size() >= (size_t)mw * mw * 4) {
		float mk = mw / std::max(self->tsize, 1.0f);
		for (int y = 0; y < S; y++) {
			int mz = std::min(std::max((int)(((y + 0.5f) / k - self->origin) * mk), 0), mw - 1);
			for (int x = 0; x < S; x++) {
				int mx = std::min(std::max((int)(((x + 0.5f) / k - self->origin) * mk), 0), mw - 1);
				if (self->mask[((size_t)mz * mw + mx) * 4] / 255.0f > 0.4f) {
					img.set(x, y, road);
				}
			}
		}
	}
	for (size_t q = 0; q + 4 < ob.size(); q += 5) {
		int x0 = (int)(ob[q] * k), y0 = (int)(ob[q + 1] * k);
		int w = (int)std::max(ob[q + 2] * k, 2.0f), hh = (int)std::max(ob[q + 3] * k, 2.0f);
		img.fill_rect(x0, y0, w, hh, ob[q + 4] != 0.0f ? hedge : oc);
	}
	for (size_t q = 0; q + 3 < dots.size(); q += 4) {
		float cx = dots[q] * k, cy = dots[q + 1] * k;
		float rr = std::max(1.0f, dots[q + 2] * k);
		RGBA col = dots[q + 3] != 0.0f ? tree : leaf;
		for (int y = (int)(cy - rr); y <= (int)(cy + rr); y++) {
			for (int x = (int)(cx - rr); x <= (int)(cx + rr); x++) {
				if (x >= 0 && y >= 0 && x < S && y < S) {
					float dx = x + 0.5f - cx, dy = y + 0.5f - cy;
					if (std::sqrt(dx * dx + dy * dy) <= rr) img.set(x, y, col);
				}
			}
		}
	}
	const std::vector<uint8_t> &out = img.bytes();
	ret_bytes(r, out.data(), (int64_t)out.size());
}

void register_textures(GDExtensionClassLibraryPtr lib, const char *cls) {
	static const MethodDef defs[] = {
		{ "paint_mask", paint_mask },
		{ "paint_ao", paint_ao },
		{ "minimap", minimap },
	};
	register_list(lib, cls, defs, sizeof(defs) / sizeof(defs[0]));
}
