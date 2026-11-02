// Геометрия для построек и моделей: примитивы движка (BoxMesh, CylinderMesh, SphereMesh, PrismMesh,
// QuadMesh — вершины в том же порядке, что у Godot), повороты как у Basis и сборка сеток по материалу
// (как Geo.Group: перенос вершин, плоские нормали, цвет и UV2 для кустов).
#pragma once

#include "common.h"

struct Prim {
	std::vector<V3> v, n;
	std::vector<V2> uv;
	std::vector<int> idx;
};

Prim prim_box(V3 size);
Prim prim_cyl(float top, float bottom, float height, int segments, int rings = 1);
Prim prim_sphere(float radius, float height, int radial, int rings);
Prim prim_prism(V3 size, float left_to_right = 0.5f);
Prim prim_quad(float w, float h);

// Повороты и масштаб (строки, как Basis)
M3 basis_axis(V3 axis, float angle);  // Basis(axis, angle)
M3 basis_scale(V3 s);  // Basis.from_scale
M3 basis_euler(V3 rot);  // Basis.from_euler (YXZ)
M3 basis_looking_at(V3 target, V3 up);  // Basis.looking_at
M3 basis_scaled(const M3 &b, V3 s);  // Basis.scaled: строки × s
V3 m3_mul(const M3 &b, V3 v);

struct Xf {
	M3 b = M3::ident();
	V3 o = { 0, 0, 0 };
};
Xf xf_pos(V3 pos, V3 rot = { 0, 0, 0 }, V3 scale = { 1, 1, 1 });  // Geo.xf
inline Xf xf(const M3 &b, V3 o) { return { b, o }; }

// Сетки по материалу (материал — номер; порядок — как первое появление, как у словаря Geo.Group)
struct Group {
	struct Part {
		int mat;
		std::vector<V3> v, n;
		std::vector<V2> uv;
		std::vector<float> col;  // rgba на вершину (extra)
		std::vector<V2> uv2;
		std::vector<int32_t> idx;  // треугольники; гладкие части делят вершины, плоские — по три на грань
	};
	std::vector<Part> parts;
	bool extra = false;
	Part &part(int mat);
	void add(const Prim &p, const Xf &x, int mat, bool flat = false, const float *col = nullptr, V2 uv2 = { 0, 0 }, const V2 *uv_over = nullptr);
};

// Ответ GDScript: [номера материалов, (вершины, нормали, uv, индексы[, цвета, uv2])×материалов]
void ret_group(GDExtensionVariantPtr r, const Group &g);

// ---------- Двумерная геометрия движка и сетки по профилям (как Geometry2D и Geo в GDScript) ----------
std::vector<int> triangulate(const std::vector<V2> &poly);  // Geometry2D.triangulate_polygon (ear clipping)
std::vector<V2> convex_hull(std::vector<V2> pts);  // Geometry2D.convex_hull
bool polygon_clockwise(const std::vector<V2> &poly);  // Geometry2D.is_polygon_clockwise
Prim geo_loft(const std::vector<V2> &profile, double y0, double w0, double y1, double w1);
Prim geo_frustum(const std::vector<V2> &poly, double h, double top, double shift, bool smooth);
Prim geo_belt(const std::vector<V2> &profile, double width, double thick, double link);
Prim geo_prism(const std::vector<V2> &profile, double width);
std::vector<V2> geo_oval(double front, double back, double half_w, int seg = 16);
