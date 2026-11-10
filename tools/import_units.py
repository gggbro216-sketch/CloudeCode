#!/usr/bin/env python3
"""Пехота: модели солдат и оружия (CC-BY, Sketchfab) -> godot/assets/units/*.bin + *.png.

Что делает с каждой моделью:
  1. читает glb, собирает текстуры материалов в один атлас (солдат 512x512 + полоса оружия 128x512);
  2. ставит в общий вид: рост 1,75 м, ноги на земле, лицом к +Z; упрощает сетку (meshoptimizer);
  3. сама расставляет скелет по пропорциям тела и считает веса вершин по расстоянию до костей;
  4. строит позы (стойка, прицеливание стоя / с колена / лёжа, бег, переползание, бросок, гибель)
     обратной кинематикой, оружие — жёсткая часть в руках;
  5. пишет позы в «текстуру вершинной анимации» (VAT): строка = поза, столбец = вершина.
В игре солдаты рисуются одним MultiMesh на вид бойца, позу выбирает шейдер (scripts/infantry.gd).

Запуск: python3 -I tools/import_units.py <папка со скачанными моделями> [--preview папка] [только_эти ...]
В папке моделей: <имя>/model.glb (имена — в таблицах SOLDIERS и WEAPONS ниже).
"""
import sys, os, json, math, struct
import numpy as np, trimesh
from PIL import Image
import meshoptimizer as mo

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "units")
HT = 1.75          # рост бойца, м
BODY = 512         # атлас тела
WSTRIP = 128       # полоса оружия справа от атласа тела

# ---------------------------------------------------------------- исходные модели
SOLDIERS = {
    "ger": {"src": "s_ger3", "tris": 1500, "credit": "WW2 German Wehrmacht Soldier — Tactical_Beard (CC BY 4.0)"},
    "sov": {"src": "s_sov1", "tris": 1500, "credit": "WW2 Soviet Soldier — Michael Jones (CC BY 4.0)"},
    "usa": {"src": "s_us1", "tris": 1500, "credit": "WW2 US Army Ranger — Tactical_Beard (CC BY 4.0)"},
    "ally": {"src": "s_x2", "tris": 1500, "credit": "WW2 Allied Soldier Low Poly — Zack (CC BY 4.0)"},
}
# оружие: длина, м; fwd/up — куда в исходной модели смотрит ствол и где у неё верх; kind — как его держат
WEAPONS = {
    "kar98": {"src": "w_kar98", "len": 1.11, "fwd": (1, 0, 0), "up": (0, 1, 0), "kind": "rifle", "tris": 130, "credit": "Kar98k — TastyTony (CC BY 4.0)"},
    "mosin": {"src": "w_mosin", "len": 1.23, "fwd": (1, 0, 0), "up": (0, 1, 0), "kind": "rifle", "tris": 130, "credit": "Mosin Nagant — TastyTony (CC BY 4.0)"},
    "garand": {"src": "w_garand", "len": 1.10, "fwd": (0, -1, 0), "up": (0, 0, -1), "kind": "rifle", "tris": 130, "credit": "M1 Garand — TastyTony (CC BY 4.0)"},
    "smle": {"src": "w_smle", "len": 1.13, "fwd": (0, -1, 0), "up": (0, 0, -1), "kind": "rifle", "tris": 130, "credit": "SMLE Mk III — TastyTony (CC BY 4.0)"},
    "mp40": {"src": "w_mp40", "len": 0.83, "fwd": (0, 0, 1), "up": (0, 1, 0), "kind": "smg", "tris": 150, "credit": "MP40 — Tactical_Beard (CC BY 4.0)"},
    "ppsh": {"src": "w_ppsh", "len": 0.84, "fwd": (1, 0, 0), "up": (0, 1, 0), "kind": "smg", "tris": 150, "credit": "PPSh-41 — TastyTony (CC BY 4.0)"},
    "ptrd": {"src": "w_ptrd", "len": 2.02, "fwd": (1, 0, -0.6), "up": (0, 1, 0), "kind": "atr", "tris": 170, "credit": "PTRD-41 — milhause.cz (CC BY 4.0)"},
    "schreck": {"src": "w_schreck", "len": 1.64, "fwd": (-1, 0, 0), "up": (0, 1, 0), "kind": "tube", "tris": 200, "credit": "Panzerschreck — Tactical_Beard (CC BY 4.0)"},
    "bazooka": {"src": "w_bazooka", "len": 1.37, "fwd": (1, 0, 0), "up": (0, 1, 0), "kind": "tube", "tris": 180, "credit": "Bazooka — Félix Poirier (CC BY 4.0)"},
    "faust": {"src": "w_faust", "len": 1.04, "fwd": (1, 0, 0), "up": (0, 1, 0), "kind": "faust", "tris": 130, "credit": "Panzerfaust — Tactical_Beard (CC BY 4.0)"},
}
# виды бойцов: имя файла -> (солдат, оружие или None)
UNITS = {
    "ger_rifle": ("ger", "kar98"), "ger_smg": ("ger", "mp40"), "ger_atr": ("ger", "ptrd"), "ger_tube": ("ger", "schreck"),
    "ger_faust": ("ger", "faust"), "ger_crew": ("ger", None),
    "sov_rifle": ("sov", "mosin"), "sov_smg": ("sov", "ppsh"), "sov_atr": ("sov", "ptrd"), "sov_crew": ("sov", None),
    "usa_rifle": ("usa", "garand"), "usa_tube": ("usa", "bazooka"), "usa_crew": ("usa", None),
    "ally_rifle": ("ally", "smle"), "ally_atr": ("ally", "ptrd"), "ally_tube": ("ally", "bazooka"), "ally_crew": ("ally", None),
}


# ---------------------------------------------------------------- чтение glb
def load_parts(path):
    sc = trimesh.load(path, force="scene", process=False)
    parts = []
    for _name, g in sc.graph.to_flattened().items():
        gn = g.get("geometry")
        if gn is None:
            continue
        m = sc.geometry[gn].copy()
        m.apply_transform(g["transform"])
        v = np.asarray(m.vertices, np.float64)
        f = np.asarray(m.faces, np.int64)
        if len(f) == 0:
            continue
        uv = getattr(m.visual, "uv", None)
        mat = getattr(m.visual, "material", None)
        img = None
        col = (150, 150, 150)
        if mat is not None:
            img = getattr(mat, "baseColorTexture", None) or getattr(mat, "image", None)
            bc = getattr(mat, "baseColorFactor", None)
            if bc is None:
                bc = getattr(mat, "main_color", None)
            if bc is not None:
                bc = np.asarray(bc, np.float64)[:3]
                col = tuple(int(x) for x in (bc * 255.0 if bc.max() <= 1.0 else bc))
        if uv is None or img is None:
            img = None
            uv = np.zeros((len(v), 2))
        else:
            img = img.convert("RGB")
        parts.append({"v": v, "f": f, "uv": np.asarray(uv, np.float64), "img": img, "col": col})
    return parts


def atlas_place(parts, atlas, rect, cols, rows):
    """Текстуры частей -> клетки области rect атласа; возвращает V, UV по углам треугольников (без индексов)."""
    x0, y0, w, h = rect
    keys = {}
    for p in parts:
        k = ("img", p["img"].size, hash(p["img"].tobytes()[:65536])) if p["img"] is not None else ("col",) + p["col"]
        p["key"] = k
        keys.setdefault(k, p)
    order = list(keys.keys())
    n = len(order)
    while cols * rows < n:
        if cols <= rows:
            cols += 1
        else:
            rows += 1
    cw, ch = w // cols, h // rows
    cell = {}
    for i, k in enumerate(order):
        cx, cy = x0 + (i % cols) * cw, y0 + (i // cols) * ch
        p = keys[k]
        if p["img"] is not None:
            atlas.paste(p["img"].resize((cw, ch), Image.LANCZOS), (cx, cy))
            atlas.paste(p["img"].resize((cw - 4, ch - 4), Image.LANCZOS), (cx + 2, cy + 2))
        else:
            atlas.paste(Image.new("RGB", (cw, ch), p["col"]), (cx, cy))
        cell[k] = (cx, cy, cw, ch)
    AW, AH = atlas.size
    Vs, UVs = [], []
    for p in parts:
        cx, cy, cw, ch = cell[p["key"]]
        vc = p["v"][p["f"]].reshape(-1, 3)
        uc = p["uv"][p["f"]]                       # (F, 3, 2), v снизу вверх (как отдаёт trimesh)
        if p["img"] is None:
            uc = np.full_like(uc, 0.5)
        uc = uc - np.floor(uc.min(axis=1, keepdims=True))   # плитка: сдвиг целого треугольника в 0..1
        uc = np.clip(uc, 0.0, 1.0).reshape(-1, 2)
        u = (cx + 2 + uc[:, 0] * (cw - 4)) / AW
        t = (cy + 2 + (1.0 - uc[:, 1]) * (ch - 4)) / AH
        Vs.append(vc)
        UVs.append(np.stack([u, t], axis=1))
    return np.vstack(Vs), np.vstack(UVs)


def weld(V, UV, tol=1e-4):
    key = np.round(np.hstack([V / tol, UV * 4096.0])).astype(np.int64)
    _, idx, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    F = inv.reshape(-1, 3)
    ok = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
    return V[idx], UV[idx], F[ok]


def compact(V, UV, F):
    used = np.unique(F)
    remap = np.full(len(V), -1, np.int64)
    remap[used] = np.arange(len(used))
    return V[used], UV[used], remap[F]


def simplify(V, UV, F, tris):
    if len(F) <= tris:
        return compact(V, UV, F)
    idx = F.astype(np.uint32).reshape(-1)
    pos = np.ascontiguousarray(V, np.float32)
    dst = np.zeros_like(idx)
    n = mo.simplify(dst, idx, pos, target_index_count=tris * 3, target_error=0.08, options=8)   # 8 = PRUNE: мелочь прочь
    F2 = dst[:n].reshape(-1, 3).astype(np.int64)
    if len(F2) > tris * 1.35:          # швы и мелкие детали не дали упростить — грубое упрощение остатка
        idx2 = F2.astype(np.uint32).reshape(-1)
        dst2 = np.zeros_like(idx2)
        n2 = mo.simplify_sloppy(dst2, idx2, pos, target_index_count=tris * 3, target_error=0.2)
        if n2 >= 3 * 200:
            F2 = dst2[:n2].reshape(-1, 3).astype(np.int64)
    return compact(V, UV, F2)


# ---------------------------------------------------------------- общий вид солдата и оружия
def norm_soldier(V):
    V = V.copy()
    V *= (HT + 0.03) / (V[:, 1].max() - V[:, 1].min())        # рост с каской
    V[:, 1] -= V[:, 1].min()
    hd = V[:, 1] > 0.9 * HT
    V[:, 0] -= (V[hd, 0].min() + V[hd, 0].max()) / 2
    pv = (V[:, 1] > 0.45 * HT) & (V[:, 1] < 0.62 * HT) & (np.abs(V[:, 0]) < 0.1 * HT)
    V[:, 2] -= (V[pv, 2].min() + V[pv, 2].max()) / 2
    return V


def unit(v):
    v = np.asarray(v, np.float64)
    return v / (np.linalg.norm(v) + 1e-12)


def norm_weapon(V, cfg):
    """Оружие в свои оси: +Z — к дульному срезу, +Y — вверх, начало — затыльник приклада на оси ствола."""
    U = np.unique(np.round(V, 5), axis=0)
    c = U.mean(axis=0)
    _, _, vt = np.linalg.svd(U - c, full_matrices=False)
    f = vt[0] * (1.0 if np.dot(vt[0], cfg["fwd"]) > 0 else -1.0)
    u = unit(np.asarray(cfg["up"], np.float64) - f * np.dot(cfg["up"], f))
    r = np.cross(u, f)
    L = np.stack([(V - c) @ r, (V - c) @ u, (V - c) @ f], axis=1)
    L *= cfg["len"] / (L[:, 2].max() - L[:, 2].min())
    L[:, 2] -= L[:, 2].min()
    tip = L[:, 2] > 0.88 * cfg["len"]
    L[:, 1] -= (L[tip, 1].min() + L[tip, 1].max()) / 2
    L[:, 0] -= (L[tip, 0].min() + L[tip, 0].max()) / 2
    return L


# точки хвата по видам оружия (в осях оружия, доли длины по Z): r — правая рука, l — левая,
# butt — что упирается в плечо, bal — центр тяжести (перенос в одной руке)
def grips(kind, L):
    if kind == "rifle":
        return {"r": (0, -0.055, 0.30 * L), "l": (0, -0.035, 0.58 * L), "butt": (0, -0.05, 0.0), "bal": (0, -0.02, 0.45 * L)}
    if kind == "smg":
        return {"r": (0, -0.075, 0.36 * L), "l": (0, -0.10, 0.62 * L), "butt": (0, -0.04, 0.0), "bal": (0, -0.02, 0.5 * L)}
    if kind == "atr":
        return {"r": (0, -0.08, 0.16 * L), "l": (0, -0.05, 0.30 * L), "butt": (0, -0.03, 0.0), "bal": (0, 0.0, 0.42 * L)}
    if kind == "tube":
        return {"r": (0, -0.13, 0.55 * L), "l": (0, -0.11, 0.68 * L), "butt": (0, -0.05, 0.43 * L), "bal": (0, 0.05, 0.5 * L)}
    return {"r": (0, 0.03, 0.42 * L), "l": (0, -0.03, 0.60 * L), "butt": (0, 0.02, 0.26 * L), "bal": (0, 0.02, 0.55 * L)}   # faust


# ---------------------------------------------------------------- скелет и веса
def Rx(a):
    a = math.radians(a); c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Ry(a):
    a = math.radians(a); c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def Rz(a):
    a = math.radians(a); c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


I3 = np.eye(3)


def find_joints(V):
    """Суставы по пропорциям тела, уточнённые по срезам сетки. Лицо к +Z, левая сторона тела — +X."""
    H = HT
    J = {}

    def box_c(m, fallback):
        return (V[m].min(axis=0) + V[m].max(axis=0)) / 2 if m.sum() >= 3 else np.asarray(fallback, np.float64)

    def torso_z(y):
        m = (np.abs(V[:, 1] - y) < 0.03 * H) & (np.abs(V[:, 0]) < 0.07 * H)
        return box_c(m, (0, y, 0))[2]

    for name, y in (("pelvis", 0.525), ("spine", 0.60), ("chest", 0.71), ("neck", 0.835), ("head", 0.895), ("top", 0.965)):
        J[name] = np.array([0.0, y * H, torso_z(min(y, 0.84) * H)])
    J["chest_end"] = np.array([0.0, 0.79 * H, J["chest"][2]])
    J["head"][2] = J["top"][2] = J["neck"][2]
    for side, s in (("L", 1.0), ("R", -1.0)):
        J["hip" + side] = np.array([s * 0.052 * H, 0.51 * H, J["pelvis"][2]])
        leg = (V[:, 0] * s > 0.006 * H) & (V[:, 1] < 0.40 * H)
        k = box_c(leg & (np.abs(V[:, 1] - 0.285 * H) < 0.02 * H), (s * 0.06 * H, 0.285 * H, 0))
        J["knee" + side] = np.array([k[0], 0.285 * H, k[2]])
        a = box_c(leg & (np.abs(V[:, 1] - 0.10 * H) < 0.02 * H), (s * 0.06 * H, 0.1 * H, 0))
        J["ankle" + side] = np.array([a[0], 0.05 * H, a[2]])
        foot = leg & (V[:, 1] < 0.05 * H)
        J["toe" + side] = np.array([a[0], 0.012 * H, V[foot, 2].max() if foot.sum() else a[2] + 0.1 * H])
        sh = np.array([s * 0.105 * H, 0.815 * H, torso_z(0.80 * H)])
        J["shoulder" + side] = sh
        arm = (V[:, 0] * s > 0.125 * H) & (V[:, 1] > 0.30 * H) & (V[:, 1] < 0.88 * H)
        if arm.sum() < 8:
            arm = (V[:, 0] * s > 0.10 * H) & (V[:, 1] > 0.30 * H) & (V[:, 1] < 0.88 * H)
        A = V[arm]
        tip = A[np.argmax(np.linalg.norm(A - sh, axis=1))]
        d = tip - sh
        ln = np.linalg.norm(d); d /= ln
        t = (A - sh) @ d / ln
        rad = np.linalg.norm((A - sh) - np.outer(t * ln, d), axis=1)
        e0, w0 = sh + d * ln * 0.43, sh + d * ln * 0.76
        J["elbow" + side] = box_c_pts(A[(np.abs(t - 0.43) < 0.05) & (rad < 0.07 * H)], e0)
        J["wrist" + side] = box_c_pts(A[(np.abs(t - 0.76) < 0.04) & (rad < 0.07 * H)], w0)
        J["tip" + side] = tip
    J["pelvisA"] = np.array([-0.05 * H, 0.53 * H, J["pelvis"][2]])
    J["pelvisB"] = np.array([0.05 * H, 0.53 * H, J["pelvis"][2]])
    return J


def box_c_pts(P, fallback):
    return (P.min(axis=0) + P.max(axis=0)) / 2 if len(P) >= 3 else np.asarray(fallback, np.float64)


# кость: имя, родитель, сустав-опора, отрезок (начало, конец), радиус в долях роста, сжатие по X, сторона
BONES = [
    ("pelvis", -1, "pelvis", ("pelvisA", "pelvisB"), 0.100, 1.0, 0),
    ("spine", 0, "spine", ("spine", "chest"), 0.110, 0.75, 0),
    ("chest", 1, "chest", ("chest", "chest_end"), 0.115, 0.65, 0),
    ("neck", 2, "neck", ("neck", "head"), 0.050, 1.0, 0),
    ("head", 3, "head", ("head", "top"), 0.100, 1.0, 0),
    ("armL1", 2, "shoulderL", ("shoulderL", "elbowL"), 0.044, 1.0, 1), ("armL2", 5, "elbowL", ("elbowL", "wristL"), 0.037, 1.0, 1),
    ("handL", 6, "wristL", ("wristL", "tipL"), 0.034, 1.0, 1),
    ("armR1", 2, "shoulderR", ("shoulderR", "elbowR"), 0.044, 1.0, -1), ("armR2", 8, "elbowR", ("elbowR", "wristR"), 0.037, 1.0, -1),
    ("handR", 9, "wristR", ("wristR", "tipR"), 0.034, 1.0, -1),
    ("legL1", 0, "hipL", ("hipL", "kneeL"), 0.062, 1.0, 1), ("legL2", 11, "kneeL", ("kneeL", "ankleL"), 0.046, 1.0, 1),
    ("footL", 12, "ankleL", ("ankleL", "toeL"), 0.040, 1.0, 1),
    ("legR1", 0, "hipR", ("hipR", "kneeR"), 0.062, 1.0, -1), ("legR2", 14, "kneeR", ("kneeR", "ankleR"), 0.046, 1.0, -1),
    ("footR", 15, "ankleR", ("ankleR", "toeR"), 0.040, 1.0, -1),
]
BI = {b[0]: i for i, b in enumerate(BONES)}


def skin_weights(V, J):
    W = np.zeros((len(V), len(BONES)))
    for i, (_n, _p, _piv, (ja, jb), rad, xs, side) in enumerate(BONES):
        sc = np.array([xs, 1.0, 1.0])
        a, b = J[ja] * sc, J[jb] * sc
        P = V * sc
        ab = b - a
        t = np.clip((P - a) @ ab / (ab @ ab + 1e-12), 0.0, 1.0)
        d = np.linalg.norm(P - (a + np.outer(t, ab)), axis=1) / (rad * HT)
        w = np.exp(-6.0 * d * d)
        if side != 0:
            x = np.clip((V[:, 0] * side + 0.012 * HT) / (0.024 * HT), 0.0, 1.0)
            w *= x * x * (3 - 2 * x)
        W[:, i] = w
    W += 1e-9
    W[W < W.max(axis=1, keepdims=True) * 0.03] = 0.0
    return W / W.sum(axis=1, keepdims=True)


def align(u, v):
    """Кратчайший поворот единичного u в единичный v."""
    u, v = unit(u), unit(v)
    c = float(np.dot(u, v))
    if c > 0.99999:
        return I3
    if c < -0.99999:
        p = unit(np.cross(u, (1, 0, 0) if abs(u[0]) < 0.9 else (0, 1, 0)))
        return 2 * np.outer(p, p) - I3
    k = np.cross(u, v)
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return I3 + K + K @ K / (1 + c)


def ik2(a, t, l1, l2, pole):
    d = t - a
    L = np.linalg.norm(d)
    dn = d / max(L, 1e-9)
    L2 = float(np.clip(L, abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3))
    x = (l1 * l1 - l2 * l2 + L2 * L2) / (2 * L2)
    h = math.sqrt(max(l1 * l1 - x * x, 0.0))
    p = np.asarray(pole, np.float64)
    p = unit(p - dn * np.dot(p, dn))
    return a + dn * x + p * h, a + dn * L2


def basis(d, up):
    z = unit(d)
    x = unit(np.cross(up, z))
    return np.stack([x, np.cross(z, x), z], axis=1)


def solve(J, P, G):
    """Поза P -> повороты и новые опоры костей, положение оружия. G — точки хвата оружия (или None)."""
    v3 = lambda q: np.asarray(q, np.float64)
    R = [None] * len(BONES)
    T = [None] * len(BONES)

    def child(name, parent, local):
        i, p = BI[name], BI[parent]
        R[i] = R[p] @ local
        T[i] = T[p] + R[p] @ (J[BONES[i][2]] - J[BONES[p][2]])

    R[0] = P.get("pelR", I3)
    T[0] = v3(P.get("pel", J["pelvis"]))
    child("spine", "pelvis", P.get("sp", I3))
    child("chest", "spine", P.get("ch", I3))
    child("neck", "chest", P.get("nk", I3))
    child("head", "neck", P.get("hd", I3))
    ch = BI["chest"]
    sh = {s: T[ch] + R[ch] @ (J["shoulder" + s] - J["chest"]) for s in "LR"}
    # цели кистей, заданные без оружия
    hand = {}
    for s, sg in (("L", 1.0), ("R", -1.0)):
        a = P.get("arm" + s, {"off": (sg * 0.07, -0.55, 0.06), "pole": (sg * 0.3, 0, -1)})
        if "abs" in a:
            hand[s] = v3(a["abs"])
        elif "off" in a:
            hand[s] = sh[s] + v3(a["off"])
    # оружие
    Rw, pw = None, None
    w = P.get("wpn")
    if G is not None and w is not None:
        at = w.get("at", "abs")
        base = {"shR": sh["R"], "chest": T[ch], "abs": np.zeros(3)}.get(at)
        if base is None:
            base = hand[at[-1]]
        Rw = basis(w.get("dir", (0, 0, 1)), w.get("up", (0, 1, 0)))
        pw = base + v3(w.get("off", (0, 0, 0))) - Rw @ v3(G[w.get("anchor", "butt")])
    for s, sg in (("L", 1.0), ("R", -1.0)):
        a = P.get("arm" + s, {"pole": (sg * 0.3, 0, -1)})
        if "grip" in a and Rw is not None:
            hand[s] = pw + Rw @ v3(G[a["grip"]])
        elif s not in hand:
            hand[s] = sh[s] + v3((sg * 0.07, -0.55, 0.06))
        i1, i2, i3 = BI["arm" + s + "1"], BI["arm" + s + "2"], BI["hand" + s]
        l1 = np.linalg.norm(J["elbow" + s] - J["shoulder" + s])
        l2 = np.linalg.norm(J["wrist" + s] - J["elbow" + s])
        el, wr = ik2(sh[s], hand[s], l1, l2, a.get("pole", (sg * 0.4, -0.8, -0.4)))
        R[i1] = align(R[ch] @ unit(J["elbow" + s] - J["shoulder" + s]), el - sh[s]) @ R[ch]
        T[i1] = sh[s]
        R[i2] = align(R[i1] @ unit(J["wrist" + s] - J["elbow" + s]), wr - el) @ R[i1]
        T[i2] = el
        R[i3] = R[i2]
        T[i3] = wr
    for s, sg in (("L", 1.0), ("R", -1.0)):
        g = P.get("leg" + s, {})
        hip = T[0] + R[0] @ (J["hip" + s] - J["pelvis"])
        tgt = v3(g["ankle"]) if "ankle" in g else J["ankle" + s]
        i1, i2, i3 = BI["leg" + s + "1"], BI["leg" + s + "2"], BI["foot" + s]
        l1 = np.linalg.norm(J["knee" + s] - J["hip" + s])
        l2 = np.linalg.norm(J["ankle" + s] - J["knee" + s])
        kn, an = ik2(hip, tgt, l1, l2, g.get("pole", (0, 0, 1)))
        R[i1] = align(R[0] @ unit(J["knee" + s] - J["hip" + s]), kn - hip) @ R[0]
        T[i1] = hip
        R[i2] = align(R[i1] @ unit(J["ankle" + s] - J["knee" + s]), an - kn) @ R[i1]
        T[i2] = kn
        R[i3] = g.get("foot", I3)
        T[i3] = an
    return R, T, Rw, pw


def skin(V, N, W, J, R, T):
    out = np.zeros_like(V)
    on = np.zeros_like(N)
    for i, b in enumerate(BONES):
        w = W[:, i:i + 1]
        if not w.any():
            continue
        out += w * ((V - J[b[2]]) @ R[i].T + T[i])
        on += w * (N @ R[i].T)
    return out, on / (np.linalg.norm(on, axis=1, keepdims=True) + 1e-12)


# ---------------------------------------------------------------- позы
POSES = ["stand", "aim_stand", "aim_kneel", "aim_prone"] + ["run%d" % i for i in range(8)] + ["crawl%d" % i for i in range(4)] + \
        ["fall_back", "dead_back", "fall_fwd", "dead_fwd", "throw_a", "throw_b", "crouch"]
AH = 0.05 * HT       # высота голеностопа над землёй


def weapon_pose(kind, stance):
    """Как держат оружие вида kind в стойке stance: (оружие, правая рука, левая рука)."""
    gr = {"grip": "r", "pole": (-0.5, -0.8, -0.3)}
    gl = {"grip": "l", "pole": (0.35, -0.9, -0.1)}
    lying = stance in ("aimP", "crawl")
    if lying:
        gr = {"grip": "r", "pole": (-0.8, -0.7, -0.2)}
        gl = {"grip": "l", "pole": (0.8, -0.7, -0.2)}
    if stance == "drop":
        return {"at": "abs", "off": (-0.55, 0.045, -0.2), "dir": (-0.25, 0, 1), "up": (1, 0.25, 0)}, None, None
    if stance == "fall":
        return {"at": "abs", "off": (-0.38, 0.55, 0.3), "dir": (0.3, -0.7, 0.6), "up": (0.5, 0.6, 0)}, None, None
    if stance == "throw":
        return {"at": "handL", "anchor": "bal", "dir": (0.1, -0.12, 1)}, None, {"off": (0.10, -0.52, 0.12), "pole": (0.3, 0, -1)}
    if kind in ("tube", "faust"):
        under = kind == "faust"
        if stance in ("aimS", "aimK", "aimP"):
            off = (-0.04, -0.14, 0.0) if under else (0.01, 0.085, 0.0)
            return {"at": "shR", "off": off, "dir": (0, 0.02, 1)}, gr, gl
        if stance in ("ready", "crouch"):
            off = (-0.04, -0.16, 0.0) if under else (0.01, 0.085, 0.0)
            return {"at": "shR", "off": off, "dir": (0.05, 0.22, 1)}, gr, gl
    if kind in ("tube", "faust", "atr") and stance in ("run", "crawl"):
        if stance == "run":
            return {"at": "handR", "anchor": "bal", "dir": (0, 0.06, 1)}, {"off": (-0.07, -0.53, 0.06), "pole": (-0.3, 0, -1)}, None
        return {"at": "handR", "anchor": "bal", "dir": (0.05, 0.02, 1), "up": (0.3, 1, 0)}, None, None
    if stance in ("aimS", "aimK", "aimP"):
        return {"at": "shR", "off": (0.045, -0.015 if not lying else 0.01, 0.05), "dir": (0, 0, 1)}, gr, gl
    if stance in ("ready", "crouch"):
        return {"at": "shR", "off": (0.07, -0.20, 0.03), "dir": (0.30, -0.42, 0.85)}, gr, gl
    if stance == "run":
        return {"at": "chest", "off": (-0.24, -0.20, 0.20), "dir": (0.62, 0.52, 0.22), "up": (-0.3, 0.6, 0.6)}, gr, gl
    return {"at": "handR", "anchor": "r", "dir": (0.08, 0.03, 1), "up": (0.4, 1, 0)}, None, None       # crawl


def body_pose(J, name, kind):
    """Поза тела по имени; kind — вид оружия или None (расчёт орудия)."""
    P = {}
    py = J["pelvis"][1]
    stance = "ready"
    if name == "stand":
        P["legL"] = {"ankle": (0.10, AH, 0.03), "foot": Ry(8)}
        P["legR"] = {"ankle": (-0.10, AH, -0.03), "foot": Ry(-12)}
    elif name == "aim_stand":
        stance = "aimS"
        P.update(pel=(0, py - 0.035, 0.02), pelR=Ry(-28) @ Rx(4), sp=Ry(-7) @ Rx(3), ch=Ry(-7), nk=Ry(16), hd=Ry(24) @ Rx(5) @ Rz(-6))
        P["legL"] = {"ankle": (0.11, AH, 0.24), "foot": Ry(-5)}
        P["legR"] = {"ankle": (-0.15, AH, -0.20), "foot": Ry(-50)}
    elif name in ("aim_kneel", "crouch"):
        stance = "aimK" if name == "aim_kneel" else "crouch"
        P.update(pel=(0, 0.47, -0.02), pelR=Ry(-26) @ Rx(6), sp=Ry(-7) @ Rx(6), ch=Ry(-7) @ Rx(3), nk=Ry(16), hd=Ry(22) @ Rz(-5))
        if name == "crouch":
            P.update(sp=Ry(-7) @ Rx(12), ch=Ry(-7) @ Rx(8), nk=Ry(16) @ Rx(-8), hd=Ry(20) @ Rx(-8))
        P["legL"] = {"ankle": (0.15, AH, 0.33), "pole": (0.2, 0.4, 1), "foot": Ry(-8)}
        P["legR"] = {"ankle": (-0.20, 0.11, -0.36), "pole": (-0.25, -1, 0.5), "foot": Ry(-25) @ Rx(68)}
    elif name == "aim_prone" or name.startswith("crawl"):
        stance = "aimP"
        yaw, sw = -14.0, 0.0
        if name.startswith("crawl"):
            stance = "crawl"
            ph = 2 * math.pi * int(name[5:]) / 4.0
            sw = math.sin(ph)
            yaw = 7.0 * sw
        B = Ry(yaw) @ Rx(88)
        P.update(pel=(0.06 if stance == "aimP" else 0.0, 0.135, -0.30), pelR=B, sp=Rx(-15), ch=Rx(-15), nk=Rx(-24), hd=Rx(-28))
        back = B @ np.array([0, -1.0, 0])                      # куда вытянуты ноги
        side = B @ np.array([1.0, 0, 0])
        hipc = np.array(P["pel"])
        for s, sg in (("L", 1.0), ("R", -1.0)):
            pull = max(0.0, sg * sw) if stance == "crawl" else (0.0 if s == "L" else 0.12)
            an = hipc + back * (0.84 - 0.34 * pull) + side * sg * (0.17 + 0.20 * pull)
            P["leg" + s] = {"ankle": (an[0], 0.075, an[2]), "pole": tuple(side * sg * 1.0 + np.array([0, -0.25 + 0.2 * pull, 0])),
                            "foot": B @ Rx(72) @ Ry(sg * 20)}
        if stance == "crawl":
            P.update(sp=Rx(-9), ch=Rx(-9), nk=Rx(-26), hd=Rx(-30))
            P["armL"] = {"abs": (0.24, 0.05, 0.40 + 0.15 * sw), "pole": (0.9, -0.5, -0.2)}
            P["armR"] = {"abs": (-0.24, 0.06, 0.40 - 0.15 * sw), "pole": (-0.9, -0.5, -0.2)}
    elif name.startswith("run"):
        stance = "run"
        ph = 2 * math.pi * int(name[3:]) / 8.0
        P.update(pel=(0, py - 0.055 + 0.028 * math.cos(2 * ph), 0.0), pelR=Rx(10) @ Ry(7 * math.sin(ph)),
                 sp=Rx(5) @ Ry(-9 * math.sin(ph)), ch=Rx(3), nk=Rx(-6), hd=Rx(-8))
        for s, sg, th in (("L", 1.0, ph), ("R", -1.0, ph + math.pi)):
            lift = max(0.0, -math.sin(th))
            P["leg" + s] = {"ankle": (sg * 0.085, AH + lift * (0.17 + 0.14 * (1 - math.cos(th)) / 2), 0.36 * math.cos(th) - 0.04),
                            "pole": (sg * 0.08, 0.1, 1), "foot": Rx(-18 * math.cos(th) * (1 - lift) + 32 * lift)}
        if kind is None or kind in ("tube", "faust", "atr"):
            P["armL"] = {"off": (0.10, -0.40 + 0.05 * math.sin(ph), 0.10 - 0.26 * math.sin(ph)), "pole": (0.4, 0, -1)}
        if kind is None:
            P["armR"] = {"off": (-0.10, -0.40 - 0.05 * math.sin(ph), 0.10 + 0.26 * math.sin(ph)), "pole": (-0.4, 0, -1)}
    elif name == "fall_back":
        stance = "fall"
        P.update(pel=(0, 0.66, -0.20), pelR=Rx(-42), sp=Rx(-10), ch=Rx(-6), nk=Rx(-10), hd=Rx(-14))
        P["legL"] = {"ankle": (0.11, AH, 0.10), "pole": (0.2, 0, 1)}
        P["legR"] = {"ankle": (-0.12, AH, -0.02), "pole": (-0.2, 0, 1)}
        P["armL"] = {"off": (0.36, 0.20, 0.16), "pole": (0.5, -0.6, -0.4)}
        P["armR"] = {"off": (-0.38, 0.06, 0.22), "pole": (-0.5, -0.6, -0.4)}
    elif name == "dead_back":
        stance = "drop"
        B = Ry(10) @ Rx(-88)
        P.update(pel=(0, 0.125, -0.25), pelR=B, sp=Rx(2), hd=Ry(25) @ Rx(-6))
        P["legL"] = {"ankle": (0.24, 0.075, 0.55), "pole": (0.4, 1, 0), "foot": B @ Ry(25)}
        P["legR"] = {"ankle": (-0.18, 0.075, 0.30), "pole": (-0.25, 1, 0.1), "foot": B @ Rx(30)}
        P["armL"] = {"abs": (0.56, 0.05, -0.72), "pole": (0.2, 0.3, 1)}
        P["armR"] = {"abs": (-0.36, 0.06, -0.38), "pole": (-1, 0.3, 0)}
    elif name == "fall_fwd":
        stance = "fall"
        P.update(pel=(0, 0.50, 0.06), pelR=Rx(34), sp=Rx(14), ch=Rx(10), nk=Rx(12), hd=Rx(16))
        P["legL"] = {"ankle": (0.13, 0.10, -0.36), "pole": (0.1, -0.5, 1), "foot": Rx(62)}
        P["legR"] = {"ankle": (-0.13, 0.10, -0.42), "pole": (-0.1, -0.5, 1), "foot": Rx(62)}
        P["armL"] = {"off": (0.14, -0.40, 0.30), "pole": (0.6, 0, -0.6)}
        P["armR"] = {"off": (-0.16, -0.44, 0.22), "pole": (-0.6, 0, -0.6)}
    elif name == "dead_fwd":
        stance = "drop"
        B = Ry(-8) @ Rx(89)
        P.update(pel=(0, 0.13, -0.25), pelR=B, sp=Rx(-2), nk=Ry(30), hd=Ry(40))
        P["legL"] = {"ankle": (0.28, 0.075, -1.06), "pole": (1, -0.2, 0), "foot": B @ Rx(75) @ Ry(25)}
        P["legR"] = {"ankle": (-0.08, 0.075, -1.10), "pole": (-1, -0.2, 0), "foot": B @ Rx(75) @ Ry(-25)}
        P["armL"] = {"abs": (0.30, 0.05, 0.78), "pole": (1, 0.2, 0)}
        P["armR"] = {"abs": (-0.44, 0.05, 0.10), "pole": (-1, 0.3, -0.3)}
    elif name in ("throw_a", "throw_b"):
        stance = "throw"
        a = name == "throw_a"
        P.update(pel=(0, py - 0.04, 0.0), pelR=Ry(-34 if a else 16) @ Rx(-4 if a else 8), sp=Ry(-10 if a else 10) @ Rx(-8 if a else 12),
                 ch=Ry(-8 if a else 8), nk=Ry(20 if a else -10), hd=Ry(22 if a else -12))
        P["legL"] = {"ankle": (0.11, AH, 0.27), "foot": Ry(-5)}
        P["legR"] = {"ankle": (-0.15, AH + (0.0 if a else 0.05), -0.26), "foot": Ry(-40) @ Rx(0 if a else 30)}
        P["armR"] = {"off": (-0.22, 0.24, -0.40), "pole": (-0.6, -0.6, -0.3)} if a else {"off": (0.04, 0.34, 0.50), "pole": (-0.6, -0.7, 0)}
        P["armL"] = {"off": (0.12, -0.50, 0.14), "pole": (0.3, 0, -1)}
    if kind is not None:
        w, ar, al = weapon_pose(kind, stance)
        P["wpn"] = w
        if ar is not None:
            P["armR"] = ar
        if al is not None:
            P["armL"] = al
    elif stance in ("aimS", "aimK", "aimP"):                   # расчёт орудия: руки вперёд, к казённику
        y = {"aimS": 1.15, "aimK": 0.78, "aimP": 0.2}[stance]
        P["armL"] = {"abs": (0.16, y, 0.46), "pole": (0.5, -0.8, 0)}
        P["armR"] = {"abs": (-0.16, y - 0.04, 0.42), "pole": (-0.5, -0.8, 0)}
    elif stance == "crouch":
        P["armL"] = {"abs": (0.20, 0.56, 0.24), "pole": (0.7, 0, -0.5)}
        P["armR"] = {"abs": (-0.26, 0.34, 0.10), "pole": (-0.7, 0, -0.5)}
    return P


# ---------------------------------------------------------------- нормали, запись, превью
def vertex_normals(V, F):
    key = np.round(V / 1e-4).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    acc = np.zeros((inv.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, inv[F[:, k]], fn)
    n = acc[inv]
    return n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-12)


def raster(V, F, C, ax, w, h, lo, scale):
    P = V[:, list(ax)]
    X = (P[:, 0] - lo[0]) * scale
    Y = h - (P[:, 1] - lo[1]) * scale
    Z = P[:, 2] * (1.0 if ax != (2, 1, 0) else -1.0)
    img = np.full((h, w, 3), 228, np.uint8)
    zb = np.full((h, w), -1e18)
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    fn /= (np.linalg.norm(fn, axis=1, keepdims=True) + 1e-12)
    sh = 0.5 + 0.5 * np.abs(fn @ unit((0.4, 0.7, 0.6)))
    for k, (a, b, c) in enumerate(F):
        x0, x1 = int(max(0, math.floor(min(X[a], X[b], X[c])))), int(min(w - 1, math.ceil(max(X[a], X[b], X[c]))))
        y0, y1 = int(max(0, math.floor(min(Y[a], Y[b], Y[c])))), int(min(h - 1, math.ceil(max(Y[a], Y[b], Y[c]))))
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (Y[b] - Y[c]) * (X[a] - X[c]) + (X[c] - X[b]) * (Y[a] - Y[c])
        if abs(d) < 1e-12:
            continue
        w0 = ((Y[b] - Y[c]) * (xs - X[c]) + (X[c] - X[b]) * (ys - Y[c])) / d
        w1 = ((Y[c] - Y[a]) * (xs - X[c]) + (X[a] - X[c]) * (ys - Y[c])) / d
        w2 = 1 - w0 - w1
        m = (w0 >= -0.01) & (w1 >= -0.01) & (w2 >= -0.01)
        z = w0 * Z[a] + w1 * Z[b] + w2 * Z[c]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        m &= z > sub
        if not m.any():
            continue
        col = (w0[..., None] * C[a] + w1[..., None] * C[b] + w2[..., None] * C[c]) * sh[k]
        sub[m] = z[m]
        img[y0:y1 + 1, x0:x1 + 1][m] = np.clip(col[m], 0, 255).astype(np.uint8)
    return img


def bake_unit(name, sol, wpn, preview):
    V, UV, F, W, J = sol["V"], sol["UV"], sol["F"], sol["W"], sol["J"]
    N = sol["N"]
    G = None
    if wpn is not None:
        G = grips(wpn["kind"], wpn["len"])
        F = np.vstack([F, wpn["F"] + len(V)])
        UV = np.vstack([UV, wpn["UV"]])
    nv = len(V) + (len(wpn["V"]) if wpn is not None else 0)
    rows_p, rows_n = [], []
    for pn in POSES:
        R, T, Rw, pw = solve(J, body_pose(J, pn, wpn["kind"] if wpn is not None else None), G)
        p, n = skin(V, N, W, J, R, T)
        if wpn is not None:
            p = np.vstack([p, wpn["V"] @ Rw.T + pw])
            n = np.vstack([n, wpn["N"] @ Rw.T])
        rows_p.append(p)
        rows_n.append(n)
    vat = np.concatenate([np.stack(rows_p), np.stack(rows_n)]).astype(np.float16)       # (2P, nv, 3)
    head = json.dumps({"nv": nv, "ni": int(F.size), "poses": POSES, "height": HT}).encode()
    with open(os.path.join(OUT, name + ".bin"), "wb") as f:
        f.write(b"SUV1" + struct.pack("<I", len(head)) + head)
        f.write(rows_p[0].astype("<f4").tobytes())
        f.write(UV.astype("<f4").tobytes())
        f.write(F.astype("<u2").tobytes())
        f.write(vat.astype("<f2").tobytes())
    print("  %-11s вершин %4d, треугольников %4d, поз %d, %d КБ" % (name, nv, len(F), len(POSES), (nv * len(POSES) * 12 + nv * 20 + F.size * 2) // 1024))
    if preview:
        at = np.asarray(sol["atlas"], np.float64)
        C = at[np.clip((UV[:, 1] * at.shape[0]).astype(int), 0, at.shape[0] - 1), np.clip((UV[:, 0] * at.shape[1]).astype(int), 0, at.shape[1] - 1)]
        tiles = []
        for p in rows_p:
            a = raster(p, F, C, (2, 1, 0), 300, 180, (-1.5, -0.05), 100.0)
            b = raster(p, F, C, (0, 1, 2), 180, 180, (-0.9, -0.05), 100.0)
            c = raster(p, F, C, (0, 2, 1), 180, 300, (-0.9, -1.5), 100.0)[60:240]
            tiles.append(np.hstack([a, b, c]))
        while len(tiles) % 3:
            tiles.append(np.full_like(tiles[0], 228))
        Image.fromarray(np.vstack([np.hstack(tiles[i:i + 3]) for i in range(0, len(tiles), 3)])).save(os.path.join(preview, name + ".png"))


def main():
    src = sys.argv[1]
    args = sys.argv[2:]
    preview = None
    if "--preview" in args:
        i = args.index("--preview")
        preview = args[i + 1]
        args = args[:i] + args[i + 2:]
        os.makedirs(preview, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    credits = []
    for sname, scfg in SOLDIERS.items():
        units = [(u, w) for u, (s, w) in UNITS.items() if s == sname and (not args or u in args or sname in args)]
        if not units:
            continue
        print(sname, "<-", scfg["src"])
        atlas = Image.new("RGB", (BODY + WSTRIP, BODY), (70, 70, 62))
        V, UV = atlas_place(load_parts(os.path.join(src, scfg["src"], "model.glb")), atlas, (0, 0, BODY, BODY), 1, 1)
        V = norm_soldier(V)
        V, UV, F = weld(V, UV)
        V, UV, F = simplify(V, UV, F, scfg["tris"])
        J = find_joints(V)
        sol = {"V": V, "UV": UV, "F": F, "J": J, "W": skin_weights(V, J), "N": vertex_normals(V, F), "atlas": atlas}
        credits.append(scfg["credit"])
        wnames = [w for _u, w in units if w is not None]
        wp = {}
        for i, wn in enumerate(dict.fromkeys(wnames)):
            cfg = WEAPONS[wn]
            ch = BODY // max(4, len(set(wnames)))
            WV, WUV = atlas_place(load_parts(os.path.join(src, cfg["src"], "model.glb")), atlas, (BODY, i * ch, WSTRIP, ch), 1, 1)
            WV = norm_weapon(WV, cfg)
            WV, WUV, WF = weld(WV, WUV, tol=2e-4)
            WV, WUV, WF = simplify(WV, WUV, WF, cfg["tris"])
            wp[wn] = {"V": WV, "UV": WUV, "F": WF, "N": vertex_normals(WV, WF), "kind": cfg["kind"], "len": cfg["len"]}
            if cfg["credit"] not in credits:
                credits.append(cfg["credit"])
        for u, wn in units:
            bake_unit(u, sol, wp.get(wn), preview)
        atlas.save(os.path.join(OUT, sname + ".png"), optimize=True)
    if not args:
        with open(os.path.join(OUT, "CREDITS.txt"), "w", encoding="utf-8") as f:
            f.write("Модели пехоты и стрелкового оружия (Sketchfab, лицензия CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/).\n"
                    "Модели упрощены, собраны в атласы и анимированы заново (tools/import_units.py).\n\n" + "\n".join(credits) + "\n")


if __name__ == "__main__":
    main()
