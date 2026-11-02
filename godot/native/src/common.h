// Общее для частей SteelCore: математика, поля пакета танка, объявление методов для GDScript.
#pragma once

#include "core.h"

#include <algorithm>
#include <cfloat>
#include <cmath>

using namespace gd;

static inline float clampf(float v, float a, float b) { return v < a ? a : (v > b ? b : v); }
static inline bool finite2(float a, float b) { return std::isfinite(a) && std::isfinite(b); }
static inline bool finite3(V3 v) { return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z); }
// индекс клетки: нечисловое значение — к нижней границе
static inline int cell_index(double v, int lo, int hi) {
	if (!(v >= lo)) return lo;
	if (v > hi) return hi;
	return (int)v;
}
static inline double lerpd(double a, double b, double t) { return a + (b - a) * t; }
static inline float smoothstep(float from, float to, float s) {
	if (std::fabs(from - to) < 1e-6f) {
		return s <= from ? 0.0f : 1.0f;
	}
	float t = clampf((s - from) / (to - from), 0.0f, 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

static const float GRAVITY = 9.81f * 7.5f;
static const float PI_F = 3.14159265358979f;
static inline float signf(float v) { return v > 0.0f ? 1.0f : (v < 0.0f ? -1.0f : 0.0f); }
static inline float move_toward(float from, float to, float delta) {
	return std::fabs(to - from) <= delta ? to : from + signf(to - from) * delta;
}
static inline float wrapf(float v, float lo, float hi) {
	double range = (double)hi - lo;
	return (float)(v - range * std::floor((v - (double)lo) / range));
}
static inline float fposmod(float x, float y) {
	float v = std::fmod(x, y);
	if ((v < 0.0f && y > 0.0f) || (v > 0.0f && y < 0.0f)) v += y;
	return v;
}

static inline float ang_diff(float a, float b) { return wrapf(a - b, -PI_F, PI_F); }
static inline float turn_toward(float cur, float target, float step) {
	float d = ang_diff(target, cur);
	return std::fabs(d) <= step ? target : cur + signf(d) * step;
}

static const float RANGE = 1100.0f;  // D.RANGE

static inline V2 from_angle(float a) { return { std::cos(a), std::sin(a) }; }
static inline float dist2(V2 a, V2 b) { return std::sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)); }

static inline V3 v3add(V3 a, V3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
static inline V3 v3sub(V3 a, V3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
static inline V3 v3mul(V3 a, float k) { return { a.x * k, a.y * k, a.z * k }; }
static inline float v3dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline float v3len(V3 a) { return std::sqrt(v3dot(a, a)); }
static inline V3 v3norm(V3 a) {
	float l = v3len(a);
	return l > 1e-12f ? v3mul(a, 1.0f / l) : V3{ 0.0f, 0.0f, 0.0f };
}
// ближайшая к c точка отрезка [a, a + d] (как Geometry3D.get_closest_point_to_segment)
static inline V3 closest_on(V3 c, V3 a, V3 d) {
	float l2 = v3dot(d, d);
	float u = l2 > 1e-12f ? clampf(v3dot(v3sub(c, a), d) / l2, 0.0f, 1.0f) : 0.0f;
	return v3add(a, v3mul(d, u));
}

// Состояние танка в пакете phys_step (PHYS чисел на танк).
enum PhysField {
	P_CMD, P_THR, P_STEER, P_SPEED_K, P_TURN_K, P_ACCEL_K, P_TRACK_BROKEN, P_IMMOBILE, P_ALIVE, P_TEAM,
	P_X, P_Y, P_VX, P_VY, P_HULL, P_TUR, P_YAW, P_TRAVEL_L, P_TRAVEL_R, P_DIST,
	P_PITCH, P_ROLL, P_PITCH_V, P_ROLL_V, P_BODY_P, P_BODY_R, P_BODY_PV, P_BODY_RV,
	P_SLIP, P_SOFT, P_THROTTLE, P_ACCEL, P_SP, P_GROUND, P_VMAX,
	P_AIM, P_AX, P_AY, P_AZ, P_TSPD_K, P_GUN_PITCH, P_GUN_TARGET, P_TUR_RATE,
	P_DISP_CMD, P_DISP, P_DISP_K, P_AIM_K, P_SHOWN, P_HP, P_VIS0, P_VIS1, P_TG,
	// бот: управление в C++ (решения — GDScript, 5 раз в секунду)
	P_BOT, P_ACT, P_SPOT_HAS, P_SPOT_X, P_SPOT_Y, P_ADV, P_LOS, P_HOLD, P_SIDE, P_GUESS_HAS, P_GUESS_X, P_GUESS_Y,
	P_RL, P_CAN_FIRE, P_FIRE, P_STUCK, P_HIT_T, PHYS
};

// Методы класса SteelCore: (self, аргументы, ответ, ошибка).
#define METHOD(fn) static void fn(void *self_, const Args &a, GDExtensionVariantPtr r, GDExtensionCallError *e)
#define SELF Core *self = (Core *)self_; (void)self; (void)e

struct MethodDef {
	const char *name;
	Method m;
};
void register_list(GDExtensionClassLibraryPtr lib, const char *cls, const MethodDef *defs, size_t n);
// части, разнесённые по файлам: регистрируют свои методы
void register_textures(GDExtensionClassLibraryPtr lib, const char *cls);
