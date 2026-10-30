#include "glue.h"

namespace gd {

GDExtensionInterfaceVariantGetType variant_get_type;
GDExtensionInterfacePrintError print_error;

static GDExtensionInterfaceGetVariantFromTypeConstructor get_from_type;
static GDExtensionInterfaceGetVariantToTypeConstructor get_to_type;
static GDExtensionInterfaceVariantGetPtrConstructor get_ctor;
static GDExtensionInterfaceVariantGetPtrDestructor get_dtor;
static GDExtensionInterfaceVariantGetPtrBuiltinMethod get_method;
static GDExtensionInterfaceStringNameNewWithLatin1Chars string_name_new;
static GDExtensionInterfaceStringNewWithLatin1Chars string_new;
static GDExtensionInterfaceClassdbConstructObject2 construct_object;
static GDExtensionInterfaceObjectSetInstance object_set_instance;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class6;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method_fn;
static GDExtensionInterfaceArrayOperatorIndex array_index;

// Доступ к элементам упакованных массивов по типу.
typedef void *(*IndexFn)(GDExtensionTypePtr, GDExtensionInt);
typedef const void *(*IndexConstFn)(GDExtensionConstTypePtr, GDExtensionInt);

static const int TYPES = GDEXTENSION_VARIANT_TYPE_VARIANT_MAX;
static GDExtensionVariantFromTypeConstructorFunc from_type[TYPES];
static GDExtensionTypeFromVariantConstructorFunc to_type[TYPES];
static GDExtensionPtrConstructor ctor0[TYPES];
static GDExtensionPtrDestructor dtor[TYPES];
static GDExtensionPtrBuiltInMethod m_size[TYPES];
static GDExtensionPtrBuiltInMethod m_resize[TYPES];
static IndexFn index_fn[TYPES];
static IndexConstFn index_const_fn[TYPES];

// Хэши методов size() и resize() из extension_api.json (одинаковы у всех упакованных массивов и Array).
static const GDExtensionInt HASH_SIZE = 3173160232;
static const GDExtensionInt HASH_RESIZE = 848867239;

struct SN {
	void *p = nullptr;
};

static SN name(const char *s) {
	SN n;
	string_name_new(&n, s, true);
	return n;
}

#define PROC(var, type, str) var = (type)p_get_proc(str)

void load(GDExtensionInterfaceGetProcAddress p_get_proc) {
	PROC(variant_get_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
	PROC(print_error, GDExtensionInterfacePrintError, "print_error");
	PROC(get_from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
	PROC(get_to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
	PROC(get_ctor, GDExtensionInterfaceVariantGetPtrConstructor, "variant_get_ptr_constructor");
	PROC(get_dtor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
	PROC(get_method, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");
	PROC(string_name_new, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
	PROC(string_new, GDExtensionInterfaceStringNewWithLatin1Chars, "string_new_with_latin1_chars");
	PROC(construct_object, GDExtensionInterfaceClassdbConstructObject2, "classdb_construct_object2");
	PROC(object_set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
	PROC(register_class6, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
	PROC(register_method_fn, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
	PROC(array_index, GDExtensionInterfaceArrayOperatorIndex, "array_operator_index");

	const GDExtensionVariantType scalars[] = { GDEXTENSION_VARIANT_TYPE_BOOL, GDEXTENSION_VARIANT_TYPE_INT,
		GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_VECTOR2, GDEXTENSION_VARIANT_TYPE_VECTOR3 };
	for (GDExtensionVariantType t : scalars) {
		from_type[t] = get_from_type(t);
		to_type[t] = get_to_type(t);
	}
	SN sn_size = name("size");
	SN sn_resize = name("resize");
	const GDExtensionVariantType arrays[] = { GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
		GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,
		GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY,
		GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY };
	for (GDExtensionVariantType t : arrays) {
		from_type[t] = get_from_type(t);
		to_type[t] = get_to_type(t);
		ctor0[t] = get_ctor(t, 0);
		dtor[t] = get_dtor(t);
		m_size[t] = get_method(t, &sn_size, HASH_SIZE);
		m_resize[t] = get_method(t, &sn_resize, HASH_RESIZE);
	}
	index_fn[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY] = (IndexFn)p_get_proc("packed_byte_array_operator_index");
	index_fn[GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY] = (IndexFn)p_get_proc("packed_int32_array_operator_index");
	index_fn[GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY] = (IndexFn)p_get_proc("packed_float32_array_operator_index");
	index_fn[GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY] = (IndexFn)p_get_proc("packed_vector2_array_operator_index");
	index_fn[GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY] = (IndexFn)p_get_proc("packed_vector3_array_operator_index");
	index_fn[GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY] = (IndexFn)p_get_proc("packed_color_array_operator_index");
	index_const_fn[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY] = (IndexConstFn)p_get_proc("packed_byte_array_operator_index_const");
	index_const_fn[GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY] = (IndexConstFn)p_get_proc("packed_int32_array_operator_index_const");
	index_const_fn[GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY] = (IndexConstFn)p_get_proc("packed_float32_array_operator_index_const");
	index_const_fn[GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY] = (IndexConstFn)p_get_proc("packed_vector2_array_operator_index_const");
	index_const_fn[GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY] = (IndexConstFn)p_get_proc("packed_vector3_array_operator_index_const");
	index_const_fn[GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY] = (IndexConstFn)p_get_proc("packed_color_array_operator_index_const");
}

// ---------- Аргументы ----------

double Args::num(int i) const {
	GDExtensionVariantPtr v = (GDExtensionVariantPtr)a[i];
	switch (variant_get_type(v)) {
		case GDEXTENSION_VARIANT_TYPE_FLOAT: {
			double d;
			to_type[GDEXTENSION_VARIANT_TYPE_FLOAT](&d, v);
			return d;
		}
		case GDEXTENSION_VARIANT_TYPE_INT: {
			int64_t d;
			to_type[GDEXTENSION_VARIANT_TYPE_INT](&d, v);
			return (double)d;
		}
		case GDEXTENSION_VARIANT_TYPE_BOOL: {
			GDExtensionBool d;
			to_type[GDEXTENSION_VARIANT_TYPE_BOOL](&d, v);
			return d ? 1.0 : 0.0;
		}
		default:
			return 0.0;
	}
}

V2 Args::v2(int i) const {
	V2 r = { 0, 0 };
	if (type(i) == GDEXTENSION_VARIANT_TYPE_VECTOR2) {
		to_type[GDEXTENSION_VARIANT_TYPE_VECTOR2](&r, (GDExtensionVariantPtr)a[i]);
	}
	return r;
}

V3 Args::v3(int i) const {
	V3 r = { 0, 0, 0 };
	if (type(i) == GDEXTENSION_VARIANT_TYPE_VECTOR3) {
		to_type[GDEXTENSION_VARIANT_TYPE_VECTOR3](&r, (GDExtensionVariantPtr)a[i]);
	}
	return r;
}

// ---------- Упакованные массивы ----------

Packed::Packed(GDExtensionVariantType p_type) :
		t(p_type) {
	ctor0[t](d, nullptr);
}

Packed::Packed(GDExtensionVariantType p_type, GDExtensionConstVariantPtr p_from) :
		t(p_type) {
	to_type[t](d, (GDExtensionVariantPtr)p_from);
}

Packed::~Packed() {
	dtor[t](d);
}

int64_t Packed::size() const {
	int64_t r = 0;
	m_size[t]((GDExtensionTypePtr)d, nullptr, &r, 0);
	return r;
}

void Packed::resize(int64_t n) {
	int64_t arg = n;
	GDExtensionConstTypePtr args[1] = { &arg };
	int64_t ret = 0;
	m_resize[t](d, args, &ret, 1);
}

const void *Packed::cdata() const {
	return size() > 0 ? index_const_fn[t](d, 0) : nullptr;
}

void *Packed::data() {
	return size() > 0 ? index_fn[t](d, 0) : nullptr;
}

void Packed::to_variant(GDExtensionVariantPtr r) const {
	from_type[t](r, (GDExtensionTypePtr)d);
}

template <typename T>
static std::vector<T> read(const Args &a, int i, GDExtensionVariantType t) {
	std::vector<T> out;
	if (i >= a.n || a.type(i) != t) {
		return out;
	}
	Packed p(t, a.a[i]);
	int64_t n = p.size();
	if (n > 0) {
		out.resize(n);
		std::memcpy(out.data(), p.cdata(), n * sizeof(T));
	}
	return out;
}

std::vector<float> f32(const Args &a, int i) { return read<float>(a, i, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY); }
std::vector<int32_t> i32(const Args &a, int i) { return read<int32_t>(a, i, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY); }
std::vector<uint8_t> bytes(const Args &a, int i) { return read<uint8_t>(a, i, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY); }
std::vector<V2> v2s(const Args &a, int i) { return read<V2>(a, i, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY); }
std::vector<V3> v3s(const Args &a, int i) { return read<V3>(a, i, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY); }

// ---------- Ответы ----------

void ret_float(GDExtensionVariantPtr r, double v) { from_type[GDEXTENSION_VARIANT_TYPE_FLOAT](r, &v); }
void ret_int(GDExtensionVariantPtr r, int64_t v) { from_type[GDEXTENSION_VARIANT_TYPE_INT](r, &v); }
void ret_bool(GDExtensionVariantPtr r, bool v) {
	GDExtensionBool b = v ? 1 : 0;
	from_type[GDEXTENSION_VARIANT_TYPE_BOOL](r, &b);
}
void ret_v2(GDExtensionVariantPtr r, V2 v) { from_type[GDEXTENSION_VARIANT_TYPE_VECTOR2](r, &v); }

static void write(GDExtensionVariantPtr r, GDExtensionVariantType t, const void *p, int64_t n, size_t elem) {
	Packed out(t);
	out.resize(n);
	if (n > 0) {
		std::memcpy(out.data(), p, n * elem);
	}
	out.to_variant(r);
}

void ret_f32(GDExtensionVariantPtr r, const float *p, int64_t n) { write(r, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, p, n, 4); }
void ret_i32(GDExtensionVariantPtr r, const int32_t *p, int64_t n) { write(r, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, p, n, 4); }
void ret_bytes(GDExtensionVariantPtr r, const uint8_t *p, int64_t n) { write(r, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, p, n, 1); }
void ret_v2s(GDExtensionVariantPtr r, const V2 *p, int64_t n) { write(r, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, p, n, 8); }
void ret_v3s(GDExtensionVariantPtr r, const V3 *p, int64_t n) { write(r, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, p, n, 12); }
void ret_colors(GDExtensionVariantPtr r, const float *rgba, int64_t n) { write(r, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, rgba, n, 16); }

ArrayOut::ArrayOut(int64_t n) {
	ctor0[GDEXTENSION_VARIANT_TYPE_ARRAY](d, nullptr);
	int64_t arg = n;
	GDExtensionConstTypePtr args[1] = { &arg };
	int64_t ret = 0;
	m_resize[GDEXTENSION_VARIANT_TYPE_ARRAY](d, args, &ret, 1);
}

ArrayOut::~ArrayOut() {
	dtor[GDEXTENSION_VARIANT_TYPE_ARRAY](d);
}

GDExtensionVariantPtr ArrayOut::at(int64_t i) {
	return array_index(d, i);
}

void ArrayOut::to_variant(GDExtensionVariantPtr r) {
	from_type[GDEXTENSION_VARIANT_TYPE_ARRAY](r, d);
}

// ---------- Регистрация ----------

struct ClassReg {
	SN name;
	SN parent;
	void *(*create)();
	void (*destroy)(void *);
};

static GDExtensionObjectPtr create_instance(void *p_userdata, GDExtensionBool) {
	ClassReg *c = (ClassReg *)p_userdata;
	GDExtensionObjectPtr obj = construct_object(&c->parent);
	object_set_instance(obj, &c->name, c->create());
	return obj;
}

static void free_instance(void *p_userdata, GDExtensionClassInstancePtr p_instance) {
	((ClassReg *)p_userdata)->destroy(p_instance);
}

static GDExtensionClassCallVirtual get_virtual(void *, GDExtensionConstStringNamePtr, uint32_t) {
	return nullptr;
}

void register_class(GDExtensionClassLibraryPtr lib, const char *cls, const char *parent, void *(*create)(), void (*destroy)(void *)) {
	ClassReg *c = new ClassReg;  // живёт до выгрузки библиотеки
	c->name = name(cls);
	c->parent = name(parent);
	c->create = create;
	c->destroy = destroy;
	GDExtensionClassCreationInfo6 info = {};
	info.is_exposed = 1;
	info.create_instance_func = create_instance;
	info.free_instance_func = free_instance;
	info.get_virtual_func = get_virtual;
	info.class_userdata = c;
	register_class6(lib, &c->name, &c->parent, &info);
}

static void call_method(void *p_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args,
		GDExtensionInt p_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	r_error->error = GDEXTENSION_CALL_OK;
	Args a = { p_args, p_count };
	((Method)p_userdata)(p_instance, a, r_return, r_error);
}

static void ptrcall_method(void *, GDExtensionClassInstancePtr, const GDExtensionConstTypePtr *, GDExtensionTypePtr) {
	// vararg-методы Godot зовёт только через call_method
	print_error("SteelCore: ptrcall is not supported", __func__, __FILE__, __LINE__, 0);
}

void register_method(GDExtensionClassLibraryPtr lib, const char *cls, const char *method, Method m) {
	SN cn = name(cls);
	SN mn = name(method);
	SN empty = name("");
	SN *keep = new SN[3]{ cn, mn, empty };
	(void)keep;
	void *hint = nullptr;
	string_new(&hint, "");
	GDExtensionPropertyInfo ret = {};
	ret.type = GDEXTENSION_VARIANT_TYPE_NIL;
	ret.name = &empty;
	ret.class_name = &empty;
	ret.hint = 0;
	ret.hint_string = &hint;
	ret.usage = 6 | 131072;  // PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT: возвращает любой Variant
	GDExtensionClassMethodInfo info = {};
	info.name = &mn;
	info.method_userdata = (void *)m;
	info.call_func = call_method;
	info.ptrcall_func = ptrcall_method;
	info.method_flags = GDEXTENSION_METHOD_FLAGS_DEFAULT | GDEXTENSION_METHOD_FLAG_VARARG;
	info.has_return_value = 1;
	info.return_value_info = &ret;
	info.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	register_method_fn(lib, &cn, &info);
}

bool need(const Args &a, int n, GDExtensionCallError *e) {
	if (a.n >= n) {
		return true;
	}
	e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
	e->argument = n;
	e->expected = n;
	return false;
}

} // namespace gd
