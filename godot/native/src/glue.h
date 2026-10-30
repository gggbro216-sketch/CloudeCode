// Связка с Godot через чистый C-интерфейс GDExtension (без godot-cpp): чтение аргументов-Variant,
// упакованные массивы и запись ответа. Методы класса SteelCore регистрируются как vararg —
// Godot зовёт их одним путём (через Variant), и обёрток на каждый тип не нужно.
#pragma once

#include "gdextension_interface.h"

#include <cstdint>
#include <cstring>
#include <vector>

namespace gd {

extern GDExtensionInterfaceVariantGetType variant_get_type;
extern GDExtensionInterfacePrintError print_error;

void load(GDExtensionInterfaceGetProcAddress p_get_proc);

struct V2 {
	float x, y;
};
struct V3 {
	float x, y, z;
};

// Аргументы вызова.
struct Args {
	const GDExtensionConstVariantPtr *a;
	int64_t n;
	GDExtensionVariantType type(int i) const { return variant_get_type(a[i]); }
	double num(int i) const;
	int64_t integer(int i) const { return (int64_t)num(i); }
	bool boolean(int i) const { return num(i) != 0.0; }
	V2 v2(int i) const;
	V3 v3(int i) const;
};

// Упакованный массив Godot (PackedFloat32Array и т. п.) во владении на время вызова.
class Packed {
	alignas(8) uint8_t d[16];
	GDExtensionVariantType t;

public:
	explicit Packed(GDExtensionVariantType p_type);  // пустой
	Packed(GDExtensionVariantType p_type, GDExtensionConstVariantPtr p_from);  // из аргумента (тип проверяет вызывающий)
	~Packed();
	Packed(const Packed &) = delete;
	Packed &operator=(const Packed &) = delete;
	int64_t size() const;
	void resize(int64_t n);
	const void *cdata() const;  // nullptr для пустого
	void *data();
	void to_variant(GDExtensionVariantPtr r) const;
	void *self() { return d; }
};

// Чтение массивов-аргументов в векторы (копия: массивы маленькие или читаются один раз).
std::vector<float> f32(const Args &a, int i);
std::vector<int32_t> i32(const Args &a, int i);
std::vector<uint8_t> bytes(const Args &a, int i);
std::vector<V2> v2s(const Args &a, int i);
std::vector<V3> v3s(const Args &a, int i);

// Ответы.
void ret_float(GDExtensionVariantPtr r, double v);
void ret_int(GDExtensionVariantPtr r, int64_t v);
void ret_bool(GDExtensionVariantPtr r, bool v);
void ret_v2(GDExtensionVariantPtr r, V2 v);
void ret_f32(GDExtensionVariantPtr r, const float *p, int64_t n);
void ret_i32(GDExtensionVariantPtr r, const int32_t *p, int64_t n);
void ret_bytes(GDExtensionVariantPtr r, const uint8_t *p, int64_t n);
void ret_v2s(GDExtensionVariantPtr r, const V2 *p, int64_t n);
void ret_v3s(GDExtensionVariantPtr r, const V3 *p, int64_t n);
void ret_colors(GDExtensionVariantPtr r, const float *rgba, int64_t n);

// Массив Godot (Array) из нескольких ответов: заполнить по местам, потом отдать.
class ArrayOut {
	alignas(8) uint8_t d[8];

public:
	explicit ArrayOut(int64_t n);
	~ArrayOut();
	GDExtensionVariantPtr at(int64_t i);  // сюда пишут ret_*
	void to_variant(GDExtensionVariantPtr r);
};

// Регистрация класса и методов.
typedef void (*Method)(void *self, const Args &a, GDExtensionVariantPtr r, GDExtensionCallError *e);
void register_class(GDExtensionClassLibraryPtr lib, const char *name, const char *parent, void *(*create)(), void (*destroy)(void *));
void register_method(GDExtensionClassLibraryPtr lib, const char *cls, const char *name, Method m);

// Проверка числа аргументов: false — ошибка уже записана в e.
bool need(const Args &a, int n, GDExtensionCallError *e);

} // namespace gd
