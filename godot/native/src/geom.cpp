// Примитивы движка (scene/resources/3d/primitive_meshes.cpp Godot) и сборка сеток по материалу.
#include "geom.h"

static const double TAU_PRIM = 6.283185307179586;
static const double PI_PRIM = 3.141592653589793;

Prim prim_box(V3 size) {
	Prim p;
	const float onethird = 1.0f / 3.0f, twothirds = 2.0f / 3.0f;
	V3 sp = { size.x * -0.5f, size.y * -0.5f, size.z * -0.5f };
	int point = 0, thisrow, prevrow;
	float x, y, z;
	auto quads = [&](int i, int j) {
		if (i > 0 && j > 0) {
			int i2 = i * 2;
			int a[12] = { prevrow + i2 - 2, prevrow + i2, thisrow + i2 - 2, prevrow + i2, thisrow + i2, thisrow + i2 - 2,
				prevrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 + 1, thisrow + i2 - 1 };
			p.idx.insert(p.idx.end(), a, a + 12);
		}
	};
	// front + back
	y = sp.y;
	thisrow = point;
	prevrow = 0;
	for (int j = 0; j <= 1; j++) {
		float v = (float)j;
		v /= 2.0f;
		x = sp.x;
		for (int i = 0; i <= 1; i++) {
			float u = (float)i;
			u /= 3.0f;
			p.v.push_back({ x, -y, -sp.z });
			p.n.push_back({ 0, 0, 1 });
			p.uv.push_back({ u, v });
			point++;
			p.v.push_back({ -x, -y, sp.z });
			p.n.push_back({ 0, 0, -1 });
			p.uv.push_back({ twothirds + u, v });
			point++;
			quads(i, j);
			x += size.x;
		}
		y += size.y;
		prevrow = thisrow;
		thisrow = point;
	}
	// left + right
	y = sp.y;
	thisrow = point;
	prevrow = 0;
	for (int j = 0; j <= 1; j++) {
		float v = (float)j;
		v /= 2.0f;
		z = sp.z;
		for (int i = 0; i <= 1; i++) {
			float u = (float)i;
			u /= 3.0f;
			p.v.push_back({ -sp.x, -y, -z });
			p.n.push_back({ 1, 0, 0 });
			p.uv.push_back({ onethird + u, v });
			point++;
			p.v.push_back({ sp.x, -y, z });
			p.n.push_back({ -1, 0, 0 });
			p.uv.push_back({ u, 0.5f + v });
			point++;
			quads(i, j);
			z += size.z;
		}
		y += size.y;
		prevrow = thisrow;
		thisrow = point;
	}
	// top + bottom
	z = sp.z;
	thisrow = point;
	prevrow = 0;
	for (int j = 0; j <= 1; j++) {
		float v = (float)j;
		v /= 2.0f;
		x = sp.x;
		for (int i = 0; i <= 1; i++) {
			float u = (float)i;
			u /= 3.0f;
			p.v.push_back({ -x, -sp.y, -z });
			p.n.push_back({ 0, 1, 0 });
			p.uv.push_back({ onethird + u, 0.5f + v });
			point++;
			p.v.push_back({ x, sp.y, -z });
			p.n.push_back({ 0, -1, 0 });
			p.uv.push_back({ twothirds + u, 0.5f + v });
			point++;
			quads(i, j);
			x += size.x;
		}
		z += size.z;
		prevrow = thisrow;
		thisrow = point;
	}
	return p;
}

static inline V3 nrm(V3 v) {
	float l = v.x * v.x + v.y * v.y + v.z * v.z;
	if (l == 0.0f) return v;
	l = std::sqrt(l);
	return { v.x / l, v.y / l, v.z / l };
}

Prim prim_cyl(float top_radius, float bottom_radius, float height, int radial_segments, int rings) {
	Prim p;
	int point = 0, thisrow = 0, prevrow = 0;
	float x, y, z, u, v, radius;
	const float side_normal_y = (bottom_radius - top_radius) / height;
	for (int j = 0; j <= rings + 1; j++) {
		v = (float)j;
		v /= (rings + 1);
		radius = top_radius + ((bottom_radius - top_radius) * v);
		y = height * v;
		y = (height * 0.5f) - y;
		for (int i = 0; i <= radial_segments; i++) {
			u = (float)i;
			u /= radial_segments;
			if (i == radial_segments) {
				x = 0.0f;
				z = 1.0f;
			} else {
				x = (float)std::sin(u * TAU_PRIM);
				z = (float)std::cos(u * TAU_PRIM);
			}
			p.v.push_back({ x * radius, y, z * radius });
			p.n.push_back(nrm({ x, side_normal_y, z }));
			p.uv.push_back({ u, v * 0.5f });
			point++;
			if (i > 0 && j > 0) {
				int a[6] = { prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1 };
				p.idx.insert(p.idx.end(), a, a + 6);
			}
		}
		prevrow = thisrow;
		thisrow = point;
	}
	if (top_radius > 0.0f) {
		y = height * 0.5f;
		thisrow = point;
		p.v.push_back({ 0, y, 0 });
		p.n.push_back({ 0, 1, 0 });
		p.uv.push_back({ 0.25f, 0.75f });
		point++;
		for (int i = 0; i <= radial_segments; i++) {
			float r = (float)i;
			r /= radial_segments;
			if (i == radial_segments) {
				x = 0.0f;
				z = 1.0f;
			} else {
				x = (float)std::sin(r * TAU_PRIM);
				z = (float)std::cos(r * TAU_PRIM);
			}
			u = (float)((x + 1.0) * 0.25);
			v = (float)(0.5 + ((z + 1.0) * 0.25));
			p.v.push_back({ x * top_radius, y, z * top_radius });
			p.n.push_back({ 0, 1, 0 });
			p.uv.push_back({ u, v });
			point++;
			if (i > 0) {
				int a[3] = { thisrow, point - 1, point - 2 };
				p.idx.insert(p.idx.end(), a, a + 3);
			}
		}
	}
	if (bottom_radius > 0.0f) {
		y = height * -0.5f;
		thisrow = point;
		p.v.push_back({ 0, y, 0 });
		p.n.push_back({ 0, -1, 0 });
		p.uv.push_back({ 0.75f, 0.75f });
		point++;
		for (int i = 0; i <= radial_segments; i++) {
			float r = (float)i;
			r /= radial_segments;
			if (i == radial_segments) {
				x = 0.0f;
				z = 1.0f;
			} else {
				x = (float)std::sin(r * TAU_PRIM);
				z = (float)std::cos(r * TAU_PRIM);
			}
			u = (float)(0.5 + ((x + 1.0) * 0.25));
			v = (float)(1.0 - ((z + 1.0) * 0.25));
			p.v.push_back({ x * bottom_radius, y, z * bottom_radius });
			p.n.push_back({ 0, -1, 0 });
			p.uv.push_back({ u, v });
			point++;
			if (i > 0) {
				int a[3] = { thisrow, point - 2, point - 1 };
				p.idx.insert(p.idx.end(), a, a + 3);
			}
		}
	}
	return p;
}

Prim prim_sphere(float radius, float height, int radial_segments, int rings) {
	Prim p;
	int point = 0, thisrow = 0, prevrow = 0;
	float x, y, z;
	float scale = height / radius * 0.5f;
	for (int j = 0; j <= rings + 1; j++) {
		float v = (float)j;
		float w;
		v /= (rings + 1);
		if (j == rings + 1) {
			w = 0.0f;
			y = -1.0f;
		} else {
			w = (float)std::sin(PI_PRIM * v);
			y = (float)std::cos(PI_PRIM * v);
		}
		for (int i = 0; i <= radial_segments; i++) {
			float u = (float)i;
			u /= radial_segments;
			if (i == radial_segments) {
				x = 0.0f;
				z = 1.0f;
			} else {
				x = (float)std::sin(u * TAU_PRIM);
				z = (float)std::cos(u * TAU_PRIM);
			}
			V3 q = { x * w, y * scale, z * w };
			p.v.push_back({ q.x * radius, q.y * radius, q.z * radius });
			p.n.push_back(nrm({ x * w * scale, y, z * w * scale }));
			p.uv.push_back({ u, v });
			point++;
			if (i > 0 && j > 0) {
				int a[6] = { prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1 };
				p.idx.insert(p.idx.end(), a, a + 6);
			}
		}
		prevrow = thisrow;
		thisrow = point;
	}
	return p;
}

Prim prim_prism(V3 size, float left_to_right) {
	Prim p;
	const float onethird = 1.0f / 3.0f, twothirds = 2.0f / 3.0f;
	V3 sp = { size.x * -0.5f, size.y * -0.5f, size.z * -0.5f };
	int point = 0, thisrow, prevrow;
	float x, y, z;
	// front + back
	y = sp.y;
	thisrow = point;
	prevrow = 0;
	for (int j = 0; j <= 1; j++) {
		float scale = (float)(j / 1.0);
		float scaled_size_x = size.x * scale;
		float start_x = (float)(sp.x + (1.0 - scale) * size.x * left_to_right);
		float offset_front = (float)((1.0 - scale) * onethird * left_to_right);
		float offset_back = (float)((1.0 - scale) * onethird * (1.0 - left_to_right));
		float v = (float)j;
		v /= 2.0f;
		x = 0.0f;
		for (int i = 0; i <= 1; i++) {
			float u = (float)i;
			u /= 3.0f;
			u *= scale;
			p.v.push_back({ start_x + x, -y, -sp.z });
			p.n.push_back({ 0, 0, 1 });
			p.uv.push_back({ offset_front + u, v });
			point++;
			p.v.push_back({ start_x + scaled_size_x - x, -y, sp.z });
			p.n.push_back({ 0, 0, -1 });
			p.uv.push_back({ twothirds + offset_back + u, v });
			point++;
			if (i > 0 && j == 1) {
				int i2 = i * 2;
				int a[6] = { prevrow + i2, thisrow + i2, thisrow + i2 - 2, prevrow + i2 + 1, thisrow + i2 + 1, thisrow + i2 - 1 };
				p.idx.insert(p.idx.end(), a, a + 6);
			} else if (i > 0 && j > 0) {
				int i2 = i * 2;
				int a[12] = { prevrow + i2 - 2, prevrow + i2, thisrow + i2 - 2, prevrow + i2, thisrow + i2, thisrow + i2 - 2,
					prevrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 + 1, thisrow + i2 - 1 };
				p.idx.insert(p.idx.end(), a, a + 12);
			}
			x += scale * size.x;
		}
		y += size.y;
		prevrow = thisrow;
		thisrow = point;
	}
	// left + right
	V3 normal_left = nrm({ -size.y, size.x * left_to_right, 0.0f });
	V3 normal_right = nrm({ size.y, size.x * (1.0f - left_to_right), 0.0f });
	y = sp.y;
	thisrow = point;
	prevrow = 0;
	for (int j = 0; j <= 1; j++) {
		float scale = (float)(j / 1.0);
		float left = (float)(sp.x + (size.x * (1.0 - scale) * left_to_right));
		float right = left + (size.x * scale);
		float v = (float)j;
		v /= 2.0f;
		z = sp.z;
		for (int i = 0; i <= 1; i++) {
			float u = (float)i;
			u /= 3.0f;
			p.v.push_back({ right, -y, -z });
			p.n.push_back(normal_right);
			p.uv.push_back({ onethird + u, v });
			point++;
			p.v.push_back({ left, -y, z });
			p.n.push_back(normal_left);
			p.uv.push_back({ u, 0.5f + v });
			point++;
			if (i > 0 && j > 0) {
				int i2 = i * 2;
				int a[12] = { prevrow + i2 - 2, prevrow + i2, thisrow + i2 - 2, prevrow + i2, thisrow + i2, thisrow + i2 - 2,
					prevrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 + 1, thisrow + i2 - 1 };
				p.idx.insert(p.idx.end(), a, a + 12);
			}
			z += size.z;
		}
		y += size.y;
		prevrow = thisrow;
		thisrow = point;
	}
	// bottom
	z = sp.z;
	thisrow = point;
	prevrow = 0;
	for (int j = 0; j <= 1; j++) {
		float v = (float)j;
		v /= 2.0f;
		x = sp.x;
		for (int i = 0; i <= 1; i++) {
			float u = (float)i;
			u /= 3.0f;
			p.v.push_back({ x, sp.y, -z });
			p.n.push_back({ 0, -1, 0 });
			p.uv.push_back({ twothirds + u, 0.5f + v });
			point++;
			if (i > 0 && j > 0) {
				int a[6] = { prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1 };
				p.idx.insert(p.idx.end(), a, a + 6);
			}
			x += size.x;
		}
		z += size.z;
		prevrow = thisrow;
		thisrow = point;
	}
	return p;
}

Prim prim_quad(float w, float h) {
	Prim p;
	float sx = w * -0.5f, sy = h * -0.5f;
	int point = 0, thisrow = 0, prevrow = 0;
	float z = sy;
	for (int j = 0; j <= 1; j++) {
		float x = sx;
		for (int i = 0; i <= 1; i++) {
			float u = (float)i, v = (float)j;
			p.v.push_back({ -x, z, 0.0f });
			p.n.push_back({ 0, 0, 1 });
			p.uv.push_back({ 1.0f - u, 1.0f - v });
			point++;
			if (i > 0 && j > 0) {
				int a[6] = { prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1 };
				p.idx.insert(p.idx.end(), a, a + 6);
			}
			x += w;
		}
		z += h;
		prevrow = thisrow;
		thisrow = point;
	}
	return p;
}

// ---------- повороты ----------

M3 basis_axis(V3 a, float angle) {
	M3 r;
	V3 sq = { a.x * a.x, a.y * a.y, a.z * a.z };
	float c = std::cos(angle), s = std::sin(angle), t = 1.0f - c;
	r.m[0][0] = sq.x + c * (1.0f - sq.x);
	r.m[1][1] = sq.y + c * (1.0f - sq.y);
	r.m[2][2] = sq.z + c * (1.0f - sq.z);
	float xyzt = a.x * a.y * t, zyxs = a.z * s;
	r.m[0][1] = xyzt - zyxs;
	r.m[1][0] = xyzt + zyxs;
	xyzt = a.x * a.z * t;
	zyxs = a.y * s;
	r.m[0][2] = xyzt + zyxs;
	r.m[2][0] = xyzt - zyxs;
	xyzt = a.y * a.z * t;
	zyxs = a.x * s;
	r.m[1][2] = xyzt - zyxs;
	r.m[2][1] = xyzt + zyxs;
	return r;
}

M3 basis_scale(V3 s) {
	M3 r = M3::ident();
	r.m[0][0] = s.x;
	r.m[1][1] = s.y;
	r.m[2][2] = s.z;
	return r;
}

M3 basis_euler(V3 e) {
	float c = std::cos(e.x), s = std::sin(e.x);
	M3 xm = { { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } } };
	c = std::cos(e.y);
	s = std::sin(e.y);
	M3 ym = { { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } } };
	c = std::cos(e.z);
	s = std::sin(e.z);
	M3 zm = { { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } } };
	return ym * xm * zm;
}

M3 basis_looking_at(V3 target, V3 up) {
	V3 vz = nrm(target);
	vz = { -vz.x, -vz.y, -vz.z };
	V3 vx = nrm({ up.y * vz.z - up.z * vz.y, up.z * vz.x - up.x * vz.z, up.x * vz.y - up.y * vz.x });
	V3 vy = { vz.y * vx.z - vz.z * vx.y, vz.z * vx.x - vz.x * vx.z, vz.x * vx.y - vz.y * vx.x };
	M3 r;
	r.m[0][0] = vx.x;
	r.m[1][0] = vx.y;
	r.m[2][0] = vx.z;
	r.m[0][1] = vy.x;
	r.m[1][1] = vy.y;
	r.m[2][1] = vy.z;
	r.m[0][2] = vz.x;
	r.m[1][2] = vz.y;
	r.m[2][2] = vz.z;
	return r;
}

M3 basis_scaled(const M3 &b, V3 s) {
	M3 r = b;
	for (int j = 0; j < 3; j++) {
		r.m[0][j] *= s.x;
		r.m[1][j] *= s.y;
		r.m[2][j] *= s.z;
	}
	return r;
}

V3 m3_mul(const M3 &b, V3 v) { return b.mul(v); }

Xf xf_pos(V3 pos, V3 rot, V3 scale) { return { basis_euler(rot) * basis_scale(scale), pos }; }

// ---------- сборка ----------

Group::Part &Group::part(int mat) {
	for (Part &p : parts) {
		if (p.mat == mat) return p;
	}
	parts.push_back(Part());
	parts.back().mat = mat;
	return parts.back();
}

void Group::add(const Prim &pm, const Xf &x, int mat, bool flat, const float *col, V2 uv2, const V2 *uv_over) {
	Part &pt = part(mat);
	const M3 &B = x.b;
	auto xf = [&](V3 v) { return V3{ B.m[0][0] * v.x + B.m[0][1] * v.y + B.m[0][2] * v.z + x.o.x, B.m[1][0] * v.x + B.m[1][1] * v.y + B.m[1][2] * v.z + x.o.y,
							  B.m[2][0] * v.x + B.m[2][1] * v.y + B.m[2][2] * v.z + x.o.z }; };
	// нормали — обратной транспонированной матрицей (как geo_add)
	float m00 = B.m[0][0], m01 = B.m[0][1], m02 = B.m[0][2], m10 = B.m[1][0], m11 = B.m[1][1], m12 = B.m[1][2], m20 = B.m[2][0], m21 = B.m[2][1], m22 = B.m[2][2];
	float c00 = m11 * m22 - m12 * m21, c01 = m12 * m20 - m10 * m22, c02 = m10 * m21 - m11 * m20;
	float c10 = m02 * m21 - m01 * m22, c11 = m00 * m22 - m02 * m20, c12 = m01 * m20 - m00 * m21;
	float c20 = m01 * m12 - m02 * m11, c21 = m02 * m10 - m00 * m12, c22 = m00 * m11 - m01 * m10;
	float det = m00 * c00 + m01 * c01 + m02 * c02;
	float id = std::fabs(det) > 1e-12f ? 1.0f / det : 0.0f;
	auto nb = [&](V3 n) { return V3{ (c00 * n.x + c01 * n.y + c02 * n.z) * id, (c10 * n.x + c11 * n.y + c12 * n.z) * id, (c20 * n.x + c21 * n.y + c22 * n.z) * id }; };
	size_t n = pm.idx.empty() ? pm.v.size() : pm.idx.size();
	n -= n % 3;
	auto put = [&](int i, V3 nrm_v) {
		pt.v.push_back(xf(pm.v[i]));
		pt.n.push_back(nrm_v);
		pt.uv.push_back(uv_over ? *uv_over : (pm.uv.empty() ? V2{ 0, 0 } : pm.uv[i]));
		if (extra) {
			const float white[4] = { 1, 1, 1, 1 };
			const float *c = col ? col : white;
			pt.col.insert(pt.col.end(), c, c + 4);
			pt.uv2.push_back(uv2);
		}
	};
	if (!flat) {
		// гладкая: вершины сетки один раз, треугольники — индексами (вершина та же, что у каждого угла)
		int32_t base = (int32_t)pt.v.size();
		for (size_t i = 0; i < pm.v.size(); i++) {
			put((int)i, pm.n.empty() ? V3{ 0, 1, 0 } : nrm(nb(pm.n[i])));
		}
		for (size_t t = 0; t < n; t++) pt.idx.push_back(base + (pm.idx.empty() ? (int32_t)t : pm.idx[t]));
		return;
	}
	for (size_t t = 0; t < n; t += 3) {
		int ids[3];
		for (int k = 0; k < 3; k++) ids[k] = pm.idx.empty() ? (int)(t + k) : pm.idx[t + k];
		V3 A = xf(pm.v[ids[0]]), Bv = xf(pm.v[ids[1]]), C = xf(pm.v[ids[2]]);
		V3 u = { Bv.x - A.x, Bv.y - A.y, Bv.z - A.z }, w = { C.x - A.x, C.y - A.y, C.z - A.z };
		V3 face = { u.y * w.z - u.z * w.y, u.z * w.x - u.x * w.z, u.x * w.y - u.y * w.x };
		V3 avg;
		if (!pm.n.empty()) {
			avg = nb({ pm.n[ids[0]].x + pm.n[ids[1]].x + pm.n[ids[2]].x, pm.n[ids[0]].y + pm.n[ids[1]].y + pm.n[ids[2]].y,
				pm.n[ids[0]].z + pm.n[ids[1]].z + pm.n[ids[2]].z });
		} else {
			avg = { (A.x + Bv.x + C.x) / 3.0f - x.o.x, (A.y + Bv.y + C.y) / 3.0f - x.o.y, (A.z + Bv.z + C.z) / 3.0f - x.o.z };
		}
		if (face.x * avg.x + face.y * avg.y + face.z * avg.z < 0.0f) face = { -face.x, -face.y, -face.z };
		face = nrm(face);
		for (int k = 0; k < 3; k++) {
			pt.idx.push_back((int32_t)pt.v.size());
			put(ids[k], face);
		}
	}
}

void ret_group(GDExtensionVariantPtr r, const Group &g) {
	int per = g.extra ? 6 : 4;
	ArrayOut out(1 + (int64_t)g.parts.size() * per);
	std::vector<int32_t> mats;
	for (const Group::Part &p : g.parts) mats.push_back(p.mat);
	ret_i32(out.at(0), mats.data(), (int64_t)mats.size());
	int64_t k = 1;
	for (const Group::Part &p : g.parts) {
		ret_v3s(out.at(k++), p.v.data(), (int64_t)p.v.size());
		ret_v3s(out.at(k++), p.n.data(), (int64_t)p.n.size());
		ret_v2s(out.at(k++), p.uv.data(), (int64_t)p.uv.size());
		ret_i32(out.at(k++), p.idx.data(), (int64_t)p.idx.size());
		if (g.extra) {
			ret_colors(out.at(k++), p.col.data(), (int64_t)(p.col.size() / 4));
			ret_v2s(out.at(k++), p.uv2.data(), (int64_t)p.uv2.size());
		}
	}
	out.to_variant(r);
}
