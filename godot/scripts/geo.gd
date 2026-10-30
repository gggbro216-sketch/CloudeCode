extends RefCounted
## Процедурная геометрия: примитивы, экструзия профилей, гусеничные ленты
## и слияние частей в одну сетку на материал (меньше вызовов отрисовки на телефоне).


const Native = preload("res://scripts/native.gd")


## Набор сеток, сгруппированных по материалу. С C++ (SteelCore) вершины переносит и разворачивает
## библиотека, а сетка собирается из готовых массивов; без неё — SurfaceTool по вершине.
class Group:
	var sts := {}
	var extra := false  # писать цвет вершины и UV2 (центр куста для шейдера)
	var core: Object = Native.shared()
	var parts := {}  # материал → [[вершины, нормали, uv, цвет, uv2], …] (путь через C++)
	var arrs := {}  # сетка → её массивы (одну сетку часто ставят много раз)

	func _st(m: Material) -> SurfaceTool:
		if not sts.has(m):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[m] = st
		return sts[m]

	## Добавить сетку с преобразованием. flat — плоские нормали (low-poly).
	func add(mesh: Mesh, xf: Transform3D, m: Material, flat := false, col := Color.WHITE, uv2 := Vector2.ZERO, uv_over = null) -> void:
		if core:
			_add_native(mesh, xf, m, flat, col, uv2, uv_over)
			return
		var st := _st(m)
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nv = arr[Mesh.ARRAY_NORMAL]
		var uv = arr[Mesh.ARRAY_TEX_UV]
		var iv = arr[Mesh.ARRAY_INDEX]
		var norms := PackedVector3Array() if nv == null else PackedVector3Array(nv)
		var uvs := PackedVector2Array() if uv == null else PackedVector2Array(uv)
		var idx := PackedInt32Array() if iv == null else PackedInt32Array(iv)
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var nb := xf.basis.inverse().transposed()
		for t in range(0, idx.size(), 3):
			var ids := [idx[t], idx[t + 1], idx[t + 2]]
			var face := Vector3.ZERO
			if flat:
				var a := xf * verts[ids[0]]
				var b := xf * verts[ids[1]]
				var c := xf * verts[ids[2]]
				face = (b - a).cross(c - a)
				var avg := Vector3.ZERO
				if not norms.is_empty():
					avg = nb * (norms[ids[0]] + norms[ids[1]] + norms[ids[2]])
				else:
					avg = (a + b + c) / 3.0 - xf.origin
				if face.dot(avg) < 0:
					face = -face
				face = face.normalized()
			for k in 3:
				var i: int = ids[k]
				if flat:
					st.set_normal(face)
				elif not norms.is_empty():
					st.set_normal((nb * norms[i]).normalized())
				else:
					st.set_normal(Vector3.UP)
				if uv_over != null:
					st.set_uv(uv_over)
				else:
					st.set_uv(uvs[i] if not uvs.is_empty() else Vector2.ZERO)
				if extra:
					st.set_color(col)
					st.set_uv2(uv2)
				st.add_vertex(xf * verts[i])

	func _add_native(mesh: Mesh, xf: Transform3D, m: Material, flat: bool, col: Color, uv2: Vector2, uv_over) -> void:
		if not arrs.has(mesh):
			arrs[mesh] = mesh.surface_get_arrays(0)
		var arr: Array = arrs[mesh]
		var b := xf.basis
		var o := xf.origin
		var uo: Vector2 = uv_over if uv_over != null else Vector2.ZERO
		var p := PackedFloat32Array([b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z,
			1.0 if flat else 0.0, 1.0 if uv_over != null else 0.0, uo.x, uo.y])
		var nv = arr[Mesh.ARRAY_NORMAL]
		var uv = arr[Mesh.ARRAY_TEX_UV]
		var iv = arr[Mesh.ARRAY_INDEX]
		var res: Array = core.geo_add(arr[Mesh.ARRAY_VERTEX], nv if nv != null else PackedVector3Array(),
			uv if uv != null else PackedVector2Array(), iv if iv != null else PackedInt32Array(), p)
		if not parts.has(m):
			parts[m] = []
		parts[m].append([res[0], res[1], res[2], col, uv2])

	func commit(parent: Node3D, shadows: bool) -> Array:
		var out: Array = []
		for m in parts:
			var v := PackedVector3Array()
			var n := PackedVector3Array()
			var uv := PackedVector2Array()
			var cols := PackedColorArray()
			var uv2s := PackedVector2Array()
			for ch in parts[m]:
				v.append_array(ch[0])
				n.append_array(ch[1])
				uv.append_array(ch[2])
				if extra:
					var k: int = (ch[0] as PackedVector3Array).size()
					var cc := PackedColorArray()
					cc.resize(k)
					cc.fill(ch[3])
					cols.append_array(cc)
					var u2 := PackedVector2Array()
					u2.resize(k)
					u2.fill(ch[4])
					uv2s.append_array(u2)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = n
			arrays[Mesh.ARRAY_TEX_UV] = uv
			if extra:
				arrays[Mesh.ARRAY_COLOR] = cols
				arrays[Mesh.ARRAY_TEX_UV2] = uv2s
			var mesh := ArrayMesh.new()
			if not v.is_empty():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			out.append(mi)
		for m in sts:
			var mi := MeshInstance3D.new()
			mi.mesh = sts[m].commit()
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			out.append(mi)
		return out


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cyl(top: float, bottom: float, h: float, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func sphere(radial := 7, rings := 4) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = radial
	s.rings = rings
	return s


static func xf(pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scale), pos)


## Треугольник с нормалью n, развёрнутый лицом наружу (в Godot лицевая сторона — по часовой).
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO) -> void:
	if (b - a).cross(c - a).dot(n) > 0:
		var t := b
		b = c
		c = t
		var tu := uvb
		uvb = uvc
		uvc = tu
	st.set_normal(n)
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(uvb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(uvc)
	st.add_vertex(c)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	tri(st, a, b, c, n)
	tri(st, a, c, d, n)


## Призма: боковой профиль (x вперёд, y вверх) вытянут по ширине (ось z).
static func prism(profile: PackedVector2Array, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width / 2.0
	var cen := Vector2.ZERO
	for p in profile:
		cen += p
	cen /= profile.size()
	var tris := Geometry2D.triangulate_polygon(profile)
	for i in range(0, tris.size(), 3):
		var a := profile[tris[i]]
		var b := profile[tris[i + 1]]
		var c := profile[tris[i + 2]]
		tri(st, Vector3(a.x, a.y, hw), Vector3(b.x, b.y, hw), Vector3(c.x, c.y, hw), Vector3.BACK)
		tri(st, Vector3(a.x, a.y, -hw), Vector3(b.x, b.y, -hw), Vector3(c.x, c.y, -hw), Vector3.FORWARD)
	for i in profile.size():
		var a := profile[i]
		var b := profile[(i + 1) % profile.size()]
		var e := b - a
		var n2 := Vector2(e.y, -e.x).normalized()
		if n2.dot((a + b) / 2.0 - cen) < 0:
			n2 = -n2
		quad(st, Vector3(a.x, a.y, hw), Vector3(b.x, b.y, hw), Vector3(b.x, b.y, -hw), Vector3(a.x, a.y, -hw), Vector3(n2.x, n2.y, 0))
	return st.commit()


## Усечённая призма: многоугольник вида сверху (x, z), высота h, верх сужен в top раз.
## smooth — сглаженные боковые нормали (литые башни).
static func frustum(poly: PackedVector2Array, h: float, top: float, shift := 0.0, smooth := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	var low: Array = []
	var high: Array = []
	for p in poly:
		low.append(Vector3(p.x, 0, p.y))
		high.append(Vector3(p.x * top + shift, h, p.y * top))
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tris.size(), 3):
		tri(st, high[tris[i]], high[tris[i + 1]], high[tris[i + 2]], Vector3.UP)
		tri(st, low[tris[i]], low[tris[i + 1]], low[tris[i + 2]], Vector3.DOWN)
	var fn: Array = []
	for i in n:
		var a: Vector3 = low[i]
		var b: Vector3 = low[(i + 1) % n]
		var d: Vector3 = high[i]
		var nrm := (b - a).cross(d - a).normalized()
		var c4: Vector3 = high[(i + 1) % n]
		var mid := (a + b + d + c4) / 4.0
		if nrm.dot(Vector3(mid.x, 0, mid.z)) < 0:
			nrm = -nrm
		fn.append(nrm)
	for i in n:
		var j := (i + 1) % n
		var a: Vector3 = low[i]
		var b: Vector3 = low[j]
		var c: Vector3 = high[j]
		var d: Vector3 = high[i]
		var nf: Vector3 = fn[i]
		if not smooth:
			quad(st, a, b, c, d, nf)
			continue
		var na: Vector3 = (fn[(i - 1 + n) % n] + nf).normalized()
		var nb: Vector3 = (nf + fn[j]).normalized()
		_tri_n(st, a, b, c, na, nb, nb, nf)
		_tri_n(st, a, c, d, na, nb, na, nf)
	return st.commit()


## Треугольник с нормалями в вершинах (для сглаживания); face задаёт сторону.
static func _tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, face: Vector3) -> void:
	if (b - a).cross(c - a).dot(face) > 0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	st.set_uv(Vector2.ZERO)
	st.set_normal(na)
	st.add_vertex(a)
	st.set_uv(Vector2.ZERO)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_uv(Vector2.ZERO)
	st.set_normal(nc)
	st.add_vertex(c)


## Корпус с наклонными бортами: боковой профиль (x, y) вытянут по z, ширина меняется
## линейно от w0 на высоте y0 до w1 на высоте y1.
static func loft(profile: PackedVector2Array, y0: float, w0: float, y1: float, w1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := func(y: float) -> float: return lerpf(w0, w1, clampf((y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)) / 2.0
	var cen := Vector2.ZERO
	for p in profile:
		cen += p
	cen /= profile.size()
	var tris := Geometry2D.triangulate_polygon(profile)
	for s: float in [1.0, -1.0]:
		for i in range(0, tris.size(), 3):
			var v: Array = []
			for k in 3:
				var p := profile[tris[i + k]]
				v.append(Vector3(p.x, p.y, s * hw.call(p.y)))
			var v0: Vector3 = v[0]
			var v1: Vector3 = v[1]
			var v2: Vector3 = v[2]
			var nrm := (v1 - v0).cross(v2 - v0).normalized()
			if nrm.z * s < 0:
				nrm = -nrm
			tri(st, v0, v1, v2, nrm)
	for i in profile.size():
		var a := profile[i]
		var b := profile[(i + 1) % profile.size()]
		var e := b - a
		var n2 := Vector2(e.y, -e.x).normalized()
		if n2.dot((a + b) / 2.0 - cen) < 0:
			n2 = -n2
		var za: float = hw.call(a.y)
		var zb: float = hw.call(b.y)
		quad(st, Vector3(a.x, a.y, za), Vector3(b.x, b.y, zb), Vector3(b.x, b.y, -zb), Vector3(a.x, a.y, -za), Vector3(n2.x, n2.y, 0))
	return st.commit()


## Гусеничная лента по замкнутому профилю (x, y): наружная поверхность с UV для прокрутки
## траков и боковины толщиной thick.
static func belt(profile: PackedVector2Array, width: float, thick: float, link: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width / 2.0
	var cen := Vector2.ZERO
	for p in profile:
		cen += p
	cen /= profile.size()
	var u := 0.0
	var n := profile.size()
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var e := b - a
		var nrm := Vector2(e.y, -e.x).normalized()
		if nrm.dot((a + b) / 2.0 - cen) < 0:
			nrm = -nrm
		var u2 := u + e.length() / link
		var n3 := Vector3(nrm.x, nrm.y, 0)
		tri(st, Vector3(a.x, a.y, hw), Vector3(b.x, b.y, hw), Vector3(b.x, b.y, -hw), n3, Vector2(u, 0), Vector2(u2, 0), Vector2(u2, 1))
		tri(st, Vector3(a.x, a.y, hw), Vector3(b.x, b.y, -hw), Vector3(a.x, a.y, -hw), n3, Vector2(u, 0), Vector2(u2, 1), Vector2(u, 1))
		var ai := a - nrm * thick
		var bi := b - nrm * thick
		for s: float in [1.0, -1.0]:
			var z := hw * s
			var sn := Vector3(0, 0, s)
			tri(st, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(bi.x, bi.y, z), sn, Vector2(u, 0.02), Vector2(u2, 0.02), Vector2(u2, 0.02))
			tri(st, Vector3(a.x, a.y, z), Vector3(bi.x, bi.y, z), Vector3(ai.x, ai.y, z), sn, Vector2(u, 0.02), Vector2(u2, 0.02), Vector2(u, 0.02))
		u = u2
	return st.commit()


## Многоугольник-эллипс (вид сверху) с разными полуосями спереди и сзади.
static func oval(front: float, back: float, half_w: float, seg := 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in seg:
		var a := TAU * i / seg
		var rx := front if cos(a) > 0 else back
		out.append(Vector2(cos(a) * rx, sin(a) * half_w))
	return out
