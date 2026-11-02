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

// ---------- Двумерная геометрия (core/math/triangulate.cpp, geometry_2d.h Godot) ----------

static inline float cross2(V2 a, V2 b) { return a.x * b.y - a.y * b.x; }
static inline V2 nrm2(V2 v) {
	float l = v.x * v.x + v.y * v.y;
	if (l != 0.0f) {
		l = std::sqrt(l);
		v.x /= l;
		v.y /= l;
	}
	return v;
}

static const float CMP_EPS = 0.00001f;

static bool inside_tri(float Ax, float Ay, float Bx, float By, float Cx, float Cy, float Px, float Py, bool include_edges) {
	float ax = Cx - Bx, ay = Cy - By, bx = Ax - Cx, by = Ay - Cy, cx = Bx - Ax, cy = By - Ay;
	float apx = Px - Ax, apy = Py - Ay, bpx = Px - Bx, bpy = Py - By, cpx = Px - Cx, cpy = Py - Cy;
	float aCROSSbp = ax * bpy - ay * bpx;
	float cCROSSap = cx * apy - cy * apx;
	float bCROSScp = bx * cpy - by * cpx;
	if (include_edges) return aCROSSbp > 0.0f && bCROSScp > 0.0f && cCROSSap > 0.0f;
	return aCROSSbp >= 0.0f && bCROSScp >= 0.0f && cCROSSap >= 0.0f;
}

static bool snip(const std::vector<V2> &c, int u, int v, int w, int n, const std::vector<int> &V, bool relaxed) {
	float Ax = c[V[u]].x, Ay = c[V[u]].y, Bx = c[V[v]].x, By = c[V[v]].y, Cx = c[V[w]].x, Cy = c[V[w]].y;
	float threshold = relaxed ? -CMP_EPS : CMP_EPS;
	if (threshold > (((Bx - Ax) * (Cy - Ay)) - ((By - Ay) * (Cx - Ax)))) return false;
	for (int p = 0; p < n; p++) {
		if (p == u || p == v || p == w) continue;
		if (inside_tri(Ax, Ay, Bx, By, Cx, Cy, c[V[p]].x, c[V[p]].y, relaxed)) return false;
	}
	return true;
}

std::vector<int> triangulate(const std::vector<V2> &contour) {
	std::vector<int> result;
	int n = (int)contour.size();
	if (n < 3) return result;
	std::vector<int> V(n);
	float A = 0.0f;
	for (int p = n - 1, q = 0; q < n; p = q++) A += cross2(contour[p], contour[q]);
	A *= 0.5f;
	for (int v = 0; v < n; v++) V[v] = 0.0f < A ? v : (n - 1) - v;
	bool relaxed = false;
	int nv = n;
	int count = 2 * nv;
	for (int v = nv - 1; nv > 2;) {
		if (0 >= (count--)) {
			if (relaxed) return std::vector<int>();  // плохой многоугольник: как движок — пусто
			count = 2 * nv;
			relaxed = true;
		}
		int u = v;
		if (nv <= u) u = 0;
		v = u + 1;
		if (nv <= v) v = 0;
		int w = v + 1;
		if (nv <= w) w = 0;
		if (snip(contour, u, v, w, nv, V, relaxed)) {
			result.push_back(V[u]);
			result.push_back(V[v]);
			result.push_back(V[w]);
			for (int s = v, t = v + 1; t < nv; s++, t++) V[s] = V[t];
			nv--;
			count = 2 * nv;
		}
	}
	return result;
}

std::vector<V2> convex_hull(std::vector<V2> P) {
	int n = (int)P.size(), k = 0;
	std::vector<V2> H((size_t)2 * n);
	std::sort(P.begin(), P.end(), [](V2 a, V2 b) { return a.x == b.x ? a.y < b.y : a.x < b.x; });
	auto vc = [](V2 o, V2 a, V2 b) { return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x); };
	for (int i = 0; i < n; ++i) {
		while (k >= 2 && vc(H[k - 2], H[k - 1], P[i]) <= 0) k--;
		H[k++] = P[i];
	}
	for (int i = n - 2, t = k + 1; i >= 0; i--) {
		while (k >= t && vc(H[k - 2], H[k - 1], P[i]) <= 0) k--;
		H[k++] = P[i];
	}
	H.resize(k);
	return H;
}

bool polygon_clockwise(const std::vector<V2> &p) {
	int c = (int)p.size();
	if (c < 3) return false;
	float sum = 0.0f;
	for (int i = 0; i < c; i++) {
		const V2 &v1 = p[i];
		const V2 &v2 = p[(i + 1) % c];
		sum += (v2.x - v1.x) * (v2.y + v1.y);
	}
	return sum > 0.0f;
}

// ---------- Сетки по профилям (Geo.prism, frustum, loft, belt; SurfaceTool без индексов) ----------

namespace {
inline V3 v3d(double x, double y, double z) { return { (float)x, (float)y, (float)z }; }
inline V3 sub3(V3 a, V3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline V3 add3(V3 a, V3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline V3 crs(V3 a, V3 b) { return { a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x }; }
inline float dt3(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

struct ST {
	Prim p;
	void vert(V3 v, V3 n, V2 uv) {
		p.v.push_back(v);
		p.n.push_back(n);
		p.uv.push_back(uv);
	}
	// Geo.tri: треугольник лицом по нормали (лицевая сторона Godot — по часовой)
	void tri(V3 a, V3 b, V3 c, V3 n, V2 uva = { 0, 0 }, V2 uvb = { 0, 0 }, V2 uvc = { 0, 0 }) {
		if (dt3(crs(sub3(b, a), sub3(c, a)), n) > 0.0f) {
			std::swap(b, c);
			std::swap(uvb, uvc);
		}
		vert(a, n, uva);
		vert(b, n, uvb);
		vert(c, n, uvc);
	}
	void quad(V3 a, V3 b, V3 c, V3 d, V3 n) {
		tri(a, b, c, n);
		tri(a, c, d, n);
	}
	void tri_n(V3 a, V3 b, V3 c, V3 na, V3 nb, V3 nc, V3 face) {
		if (dt3(crs(sub3(b, a), sub3(c, a)), face) > 0.0f) {
			std::swap(b, c);
			std::swap(nb, nc);
		}
		vert(a, na, { 0, 0 });
		vert(b, nb, { 0, 0 });
		vert(c, nc, { 0, 0 });
	}
};

V2 centroid(const std::vector<V2> &pr) {
	V2 c = { 0, 0 };
	for (V2 q : pr) {
		c.x += q.x;
		c.y += q.y;
	}
	float k = (float)pr.size();
	return { c.x / k, c.y / k };
}

// нормаль ребра a→b наружу (от центра)
V2 edge_out(V2 a, V2 b, V2 cen) {
	V2 e = { b.x - a.x, b.y - a.y };
	V2 n2 = nrm2({ e.y, -e.x });
	V2 mid = { (a.x + b.x) / 2.0f - cen.x, (a.y + b.y) / 2.0f - cen.y };
	if (n2.x * mid.x + n2.y * mid.y < 0.0f) n2 = { -n2.x, -n2.y };
	return n2;
}
} // namespace

Prim geo_prism(const std::vector<V2> &profile, double width) {
	ST st;
	if (profile.size() < 3) return st.p;
	double hw = width / 2.0;
	V2 cen = centroid(profile);
	std::vector<int> tris = triangulate(profile);
	for (size_t i = 0; i + 2 < tris.size(); i += 3) {
		V2 a = profile[tris[i]], b = profile[tris[i + 1]], c = profile[tris[i + 2]];
		st.tri(v3d(a.x, a.y, hw), v3d(b.x, b.y, hw), v3d(c.x, c.y, hw), { 0, 0, 1 });
		st.tri(v3d(a.x, a.y, -hw), v3d(b.x, b.y, -hw), v3d(c.x, c.y, -hw), { 0, 0, -1 });
	}
	size_t n = profile.size();
	for (size_t i = 0; i < n; i++) {
		V2 a = profile[i], b = profile[(i + 1) % n];
		V2 n2 = edge_out(a, b, cen);
		st.quad(v3d(a.x, a.y, hw), v3d(b.x, b.y, hw), v3d(b.x, b.y, -hw), v3d(a.x, a.y, -hw), { n2.x, n2.y, 0 });
	}
	return st.p;
}

Prim geo_frustum(const std::vector<V2> &poly, double h, double top, double shift, bool smooth) {
	ST st;
	int n = (int)poly.size();
	if (n < 3) return st.p;
	std::vector<V3> low, high;
	for (V2 q : poly) {
		low.push_back(v3d(q.x, 0, q.y));
		high.push_back(v3d(q.x * top + shift, h, q.y * top));
	}
	std::vector<int> tris = triangulate(poly);
	for (size_t i = 0; i + 2 < tris.size(); i += 3) {
		st.tri(high[tris[i]], high[tris[i + 1]], high[tris[i + 2]], { 0, 1, 0 });
		st.tri(low[tris[i]], low[tris[i + 1]], low[tris[i + 2]], { 0, -1, 0 });
	}
	auto nz = [](V3 v) {
		float l = v.x * v.x + v.y * v.y + v.z * v.z;
		if (l == 0.0f) return V3{ 0, 0, 0 };
		l = std::sqrt(l);
		return V3{ v.x / l, v.y / l, v.z / l };
	};
	std::vector<V3> fn;
	for (int i = 0; i < n; i++) {
		V3 a = low[i], b = low[(i + 1) % n], d = high[i];
		V3 nr = nz(crs(sub3(b, a), sub3(d, a)));
		V3 c4 = high[(i + 1) % n];
		V3 s4 = add3(add3(add3(a, b), d), c4);
		V3 mid = { s4.x / 4.0f, s4.y / 4.0f, s4.z / 4.0f };
		if (dt3(nr, { mid.x, 0, mid.z }) < 0.0f) nr = { -nr.x, -nr.y, -nr.z };
		fn.push_back(nr);
	}
	for (int i = 0; i < n; i++) {
		int j = (i + 1) % n;
		V3 a = low[i], b = low[j], c = high[j], d = high[i];
		V3 nf = fn[i];
		if (!smooth) {
			st.quad(a, b, c, d, nf);
			continue;
		}
		V3 na = nz(add3(fn[(i - 1 + n) % n], nf));
		V3 nb = nz(add3(nf, fn[j]));
		st.tri_n(a, b, c, na, nb, nb, nf);
		st.tri_n(a, c, d, na, nb, na, nf);
	}
	return st.p;
}

Prim geo_loft(const std::vector<V2> &profile, double y0, double w0, double y1, double w1) {
	ST st;
	if (profile.size() < 3) return st.p;
	auto hw = [&](double y) {
		double t = (y - y0) / std::max(y1 - y0, 0.001);
		t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
		return (w0 + (w1 - w0) * t) / 2.0;
	};
	V2 cen = centroid(profile);
	std::vector<int> tris = triangulate(profile);
	for (double s : { 1.0, -1.0 }) {
		for (size_t i = 0; i + 2 < tris.size(); i += 3) {
			V3 v[3];
			for (int k = 0; k < 3; k++) {
				V2 q = profile[tris[i + k]];
				v[k] = v3d(q.x, q.y, s * hw(q.y));
			}
			V3 raw = crs(sub3(v[1], v[0]), sub3(v[2], v[0]));
			float l = raw.x * raw.x + raw.y * raw.y + raw.z * raw.z;
			V3 nr = { 0, 0, 0 };
			if (l != 0.0f) {
				l = std::sqrt(l);
				nr = { raw.x / l, raw.y / l, raw.z / l };
			}
			if (nr.z * s < 0.0) nr = { -nr.x, -nr.y, -nr.z };
			st.tri(v[0], v[1], v[2], nr);
		}
	}
	size_t n = profile.size();
	for (size_t i = 0; i < n; i++) {
		V2 a = profile[i], b = profile[(i + 1) % n];
		V2 n2 = edge_out(a, b, cen);
		double za = hw(a.y), zb = hw(b.y);
		st.quad(v3d(a.x, a.y, za), v3d(b.x, b.y, zb), v3d(b.x, b.y, -zb), v3d(a.x, a.y, -za), { n2.x, n2.y, 0 });
	}
	return st.p;
}

Prim geo_belt(const std::vector<V2> &profile, double width, double thick, double link) {
	ST st;
	size_t n = profile.size();
	if (n < 2) return st.p;
	double hw = width / 2.0;
	V2 cen = centroid(profile);
	double u = 0.0;
	for (size_t i = 0; i < n; i++) {
		V2 a = profile[i], b = profile[(i + 1) % n];
		V2 e = { b.x - a.x, b.y - a.y };
		V2 nr = edge_out(a, b, cen);
		double u2 = u + (double)std::sqrt(e.x * e.x + e.y * e.y) / link;
		V3 n3 = { nr.x, nr.y, 0 };
		V2 p0 = { (float)u, 0 }, p1 = { (float)u2, 0 }, p2 = { (float)u2, 1 }, p3 = { (float)u, 1 };
		st.tri(v3d(a.x, a.y, hw), v3d(b.x, b.y, hw), v3d(b.x, b.y, -hw), n3, p0, p1, p2);
		st.tri(v3d(a.x, a.y, hw), v3d(b.x, b.y, -hw), v3d(a.x, a.y, -hw), n3, p0, p2, p3);
		float tk = (float)thick;
		V2 ai = { a.x - nr.x * tk, a.y - nr.y * tk }, bi = { b.x - nr.x * tk, b.y - nr.y * tk };
		for (double s : { 1.0, -1.0 }) {
			double z = hw * s;
			V3 sn = v3d(0, 0, s);
			V2 q0 = { (float)u, 0.02f }, q1 = { (float)u2, 0.02f };
			st.tri(v3d(a.x, a.y, z), v3d(b.x, b.y, z), v3d(bi.x, bi.y, z), sn, q0, q1, q1);
			st.tri(v3d(a.x, a.y, z), v3d(bi.x, bi.y, z), v3d(ai.x, ai.y, z), sn, q0, q1, q0);
		}
		u = u2;
	}
	return st.p;
}

std::vector<V2> geo_oval(double front, double back, double half_w, int seg) {
	std::vector<V2> out;
	for (int i = 0; i < seg; i++) {
		double a = 6.283185307179586 * i / seg;
		double rx = std::cos(a) > 0 ? front : back;
		out.push_back({ (float)(std::cos(a) * rx), (float)(std::sin(a) * half_w) });
	}
	return out;
}
