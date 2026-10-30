// Состояние ускоренных расчётов одного боя: рельеф, препятствия, сетка путей, коробки построек.
// Заполняется при загрузке боя, дальше только читается (поэтому маршруты можно искать из потока).
#pragma once

#include "glue.h"

#include <cmath>
#include <cstdint>
#include <vector>

using gd::V2;
using gd::V3;

struct Rect {
	float x, y, w, h;
	bool solid;
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
	int key(float v, bool y) const { return (int)std::floor(v / cell) - (y ? y0 : x0); }
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

	// маска грунта (RGBA8, сторона mask_w): R — дорога, G — гарь воронок
	std::vector<uint8_t> mask;
	int mask_w = 0;
	float tsize = 1.0f;  // сторона рельефа в единицах (маска натянута на него)

	// сетка путей
	float nav_cell = 25.0f;
	int nn = 0;
	std::vector<uint8_t> solid, cover;
	std::vector<float> w_norm, w_safe;

	void build_cmax();
	float height(float x, float z) const;
	bool terrain_clear(V3 a, V3 b) const;
	V3 normal(float x, float z, float e) const;
	bool blocked_at(float px, float py, float r) const;
	bool straight(V2 a, V2 b, float r) const;
	bool los(V3 a, V3 b) const;
	std::vector<V2> nav_path(V2 from, V2 to, bool safe, float r) const;
};

void register_core(GDExtensionClassLibraryPtr lib);
