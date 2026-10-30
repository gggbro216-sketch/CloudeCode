#!/usr/bin/env python3
"""Импорт моделей танков с Sketchfab (CC-BY) в игру.

Для каждой модели: скачать glTF (нужен токен Sketchfab в переменной SKETCHFAB_TOKEN),
повернуть носом вдоль +X, привести к историческим размерам из SPECS, разделить на корпус,
башню, орудие и катки, убрать гусеницы (в игре — своя анимированная лента по их контуру),
упростить сетки для телефона, собрать все текстуры в один атлас и записать:

  godot/assets/models/<танк>.glb   — узлы hull (корпус и катки), turret, gun; в метрах,
                                      башня — от центра погона, орудие — от оси цапф;
  godot/assets/models/<танк>.png   — атлас: RGB — исходный цвет, A — мелкая светотень
                                      (для перекраски в камуфляж карты);
  godot/assets/models/<танк>.json  — шарниры, контур гусениц, места для знаков, авторство.

Дополнительные каналы вершин (Godot читает TEXCOORD_2/3 как CUSTOM0):
  TEXCOORD_1 = (доля окраски, 0) — 1 для окрашенной брони, 0 для резины и голого металла;
  TEXCOORD_2 = центр катка (x, y), TEXCOORD_3 = (1 / радиус, борт ±1) — каток крутится в шейдере.

Запуск: SKETCHFAB_TOKEN=... python3 tools/import_models.py /tmp/sketchfab [танки] [--debug=папка]
Нужны numpy, scipy, pillow, trimesh, meshoptimizer (pip install).
"""
import json, os, re, sys, urllib.request
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "godot", "assets", "models")
ATLAS = 1024

# Из SPECS (tank_models.gd): длина и ширина корпуса, ширина гусеницы, высота верхней ветви.
SIZES = {
    "t34_76": (5.92, 3.0, 0.5, 0.92), "t34": (6.1, 3.0, 0.5, 0.92), "kv1": (6.75, 3.32, 0.7, 0.9),
    "is2": (6.77, 3.07, 0.65, 0.86), "sherman": (5.84, 2.62, 0.42, 0.98), "firefly": (6.05, 2.62, 0.42, 0.98),
    "cromwell": (6.35, 2.91, 0.36, 1.0), "chaffee": (5.03, 2.95, 0.41, 0.88), "pz3": (5.52, 2.95, 0.4, 0.85),
    "pz4": (5.89, 2.88, 0.4, 0.82), "stug": (5.4, 2.95, 0.4, 0.85), "panther": (6.87, 3.27, 0.66, 1.02),
    "tiger": (6.32, 3.56, 0.725, 0.98), "tiger2": (7.38, 3.75, 0.8, 1.08), "m13_40": (4.92, 2.2, 0.26, 1.1),
    "jagdpanther": (6.87, 3.27, 0.66, 1.02), "su100": (6.1, 3.0, 0.5, 0.92),
    "pz38t": (4.61, 2.14, 0.29, 0.95), "l6_40": (3.82, 1.86, 0.26, 0.85), "m15_42": (5.06, 2.23, 0.26, 1.1),
    "hetzer": (4.87, 2.63, 0.35, 0.9), "nashorn": (6.0, 2.95, 0.4, 0.85), "ferdinand": (7.05, 3.38, 0.64, 1.0),
    "jagdtiger": (7.8, 3.63, 0.8, 1.08), "stuart": (4.53, 2.24, 0.29, 0.95), "lee": (5.64, 2.72, 0.42, 1.0),
    "churchill": (7.44, 3.25, 0.56, 1.2), "comet": (6.55, 3.05, 0.46, 1.0), "kv2": (6.79, 3.32, 0.7, 0.9),
    "su85": (6.15, 3.0, 0.5, 0.92),
}

# Модели и правила разметки. Правило — (класс, поле, регулярное выражение) по пути узлов («path»)
# или имени материала («mat»); первое совпадение задаёт класс детали: drop — выбросить,
# track — гусеница, wheel — каток, turret — башня, gun — орудие; без совпадения — корпус.
#   bare — детали без окраски (резина, голый металл);  flip — нос модели смотрит в обратную сторону;
#   wheels_from — в каких классах ещё искать катки (круглые детали внизу у бортов);
#   gun_from — из какого класса вырезать ствол, если он не отдельный (turret или hull у САУ);
#   gun_ymin — ниже этой высоты ствол не ищется (у САУ, чтобы не задеть нос корпуса);
#   clip_y — всё выше этой высоты (м) — мусор вроде антенн и случайных вершин;
#   rot — поворот модели до разметки (строки матрицы 3×3), если у неё вверх не +Y;
#   gun_xmin — части орудия позади этой точки (казённик внутри рубки) выбрасываются: цапфы — у маски;
#   trunnion_x — где цапфы орудия (м), если по сетке их не найти (длинные треугольники низкополигонального ствола);
#   turret_box — [[x0, x1, y0, z0, z1], …] (м): если башня не отделена в модели, всё в этих коробках — башня.
STAFFORD = [("drop", "path", r"Area|Camera|Light"), ("track", "path", r"[LR]\.Truck"),
            ("wheel", "path", r"[LR]\.[Ww]heel|Wheel")]
MODELS = {
    "t34_76": {"uid": "876f6900000744358c0a7c8f7230741a", "bare": r"Truck",
               "rules": STAFFORD + [("gun", "path", r"T34 Gun"), ("turret", "path", r"T34 Head")]},
    "t34": {"uid": "f7dfafa6de044810b9d7dd3880c8490f", "bare": r"Truck",
            "rules": STAFFORD + [("gun", "path", r"T34 Gun"), ("turret", "path", r"T34 Head")]},
    "kv1": {"uid": "37cc8ff316144cf0a80fc02fea85782a", "bare": r"Truck",
            "rules": STAFFORD + [("gun", "path", r"kv-1 gun"), ("turret", "path", r"head")]},
    "is2": {"uid": "7efb256211eb423cb3f479e96bcb08fc", "bare": r"tracks", "wheels_from": ["hull"],
            "rules": [("track", "path", r"IS2_tracks"), ("gun", "path", r"IS2_barrel"), ("turret", "path", r"IS2_turret")]},
    "sherman": {"uid": "8766b7d04637437e884c511f89126a98", "bare": r"Tracks|MG_|Suspension", "gun_from": "turret",
                "rules": [("drop", "mat", r"Bullet|material_0"), ("track", "mat", r"Tracks"), ("wheel", "mat", r"Suspension"),
                          ("turret", "mat", r"Tower")]},
    "firefly": {"uid": "c903938af7f347dc9c64cda035e9f7ab", "bare": r"Tracks|MG_|Suspension", "gun_from": "turret",
                "rules": [("drop", "mat", r"Bullet|material_0"), ("track", "mat", r"Tracks"), ("wheel", "mat", r"Suspension"),
                          ("turret", "mat", r"Tower")]},
    "cromwell": {"uid": "373a8bb8189b42a690a51d41170280d1", "bare": r"Tracks", "gun_from": "turret",
                 "rules": [("track", "mat", r"Tracks"), ("wheel", "mat", r"Wheels"), ("turret", "mat", r"Turret")]},
    "chaffee": {"uid": "4f5e64590a514da2a6736fcac5c954e9", "bare": r"^Tracks", "wheels_from": ["track"],
                "rules": [("track", "mat", r"^Tracks"), ("gun", "mat", r"^material$"), ("turret", "mat", r"^Turret")]},
    "pz3": {"uid": "154de167f29b4387b92c83a7b54cb2bc", "bare": r"^\.010$",
            "rules": [("drop", "mat", r"^\.005$"), ("track", "mat", r"^\.010$"), ("wheel", "mat", r"^\.009$"),
                      ("gun", "mat", r"^1001\.006$"), ("turret", "mat", r"^material$")]},
    "pz4": {"uid": "098195c920b645e3af7ae7a744caeda2", "bare": r"^track$", "gun_from": "turret",
            "rules": [("track", "mat", r"^track$"), ("wheel", "mat", r"^drivetrain$"), ("turret", "mat", r"^turret$")]},
    "stug": {"uid": "14e16abe7e8d4fb3888c92f4a72a487a", "flip": True, "bare": r"Material\.001", "wheels_from": ["track"],
             "gun_from": "hull", "gun_ymin": 1.25, "clip_y": 3.2, "casemate": True,
             "rules": [("drop", "mat", r"Material\.003"), ("track", "mat", r"Material\.001")]},
    "panther": {"uid": "f76129fb212e4f70b76dbb34d770d823", "bare": r"Material_26", "gun_from": "turret",
                "rules": [("track", "mat", r"Material_26"), ("wheel", "mat", r"Material_2[57]"), ("turret", "mat", r"Material_28")]},
    "tiger": {"uid": "5dde7ae017584613a823784f744935fc", "bare": r"^chassis$", "wheels_from": ["track"], "gun_from": "turret",
              "rules": [("track", "mat", r"^chassis$"), ("turret", "mat", r"^turret$")]},
    "tiger2": {"uid": "f3fe1d22f3bb4528af3b152917daa65b", "bare": r"Truck",
               "rules": STAFFORD + [("gun", "path", r"Gun Tiger"), ("turret", "path", r"Head Tiger")]},
    "m13_40": {"uid": "6f458ef189744e80be4f430fcffa959b", "bare": r"Track|TireBlack", "gun_from": "turret", "clip_y": 2.45,
               "rules": [("track", "path", r"Track_GP"), ("wheel", "path", r"Wheel_GP"), ("turret", "path", r"Model_GP/polySurface9/")]},
    "jagdpanther": {"uid": "69fdbb9fe1e44870996f0dad90f0983e", "rot": [[1, 0, 0], [0, 0, -1], [0, 1, 0]], "bare": r"^tracks",
                    "wheels_from": ["hull"], "casemate": True, "clip_y": 3.0, "gun_xmin": 1.55,
                    "rules": [("drop", "mat", r"Decal|GLOW"), ("track", "mat", r"^tracks$"), ("gun", "mat", r"^material_2$")]},
    "pz38t": {"uid": "2cf97fbe68c74aa5985e1702748ae073", "bare": r"^blinn14$", "gun_from": "turret", "clip_y": 2.5,
              "rules": [("track", "mat", r"^blinn14$"), ("wheel", "mat", r"^blinn18$"), ("turret", "path", r"pCylinder1117")]},
    "l6_40": {"uid": "a84d6f985c1d42038a8b84cc1ebb0f84", "bare": r"Track_blinn8", "gun_from": "turret", "clip_y": 2.3,
              "rules": [("track", "path", r"Track_GP"), ("wheel", "path", r"Wheel_GP"), ("turret", "path", r"Turret_GP")]},
    "m15_42": {"uid": "fd4196a368d949e58abfc44251f39654", "bare": r"rubber|^track$", "clip_y": 2.6,
               "rules": [("track", "path", r"/track/"), ("wheel", "path", r"wheels_and_bogies"), ("gun", "path", r"/gun/"),
                         ("turret", "path", r"/turret/")]},
    "hetzer": {"uid": "2fdb125a6c1d460284ea04f0310da812", "rot": [[0.9336, 0, 0.3584], [0, 1, 0], [-0.3584, 0, 0.9336]], "bare": r"^Tracks$", "gun_from": "hull", "gun_ymin": 1.2,
               "casemate": True, "clip_y": 2.4, "rules": [("track", "mat", r"^Tracks$"), ("wheel", "mat", r"^Wheels$")]},
    "nashorn": {"uid": "2cb24f763c284b49949e3ec4bdb10f57", "bare": r"_track$", "casemate": True, "clip_y": 3.2, "trunnion_x": 0.3,
                "rules": [("drop", "path", r"_nc_"), ("track", "mat", r"_track$"), ("wheel", "path", r"chassis_wheels"),
                          ("gun", "path", r"SM_gun_03")]},
    "ferdinand": {"uid": "bf632385735f40138651fc22128c550e", "bare": r"^Material\.002$", "gun_from": "hull", "gun_ymin": 1.6,
                  "casemate": True, "clip_y": 3.2,
                  "rules": [("track", "mat", r"^Material\.002$"), ("wheel", "mat", r"^Material$")]},
    "jagdtiger": {"uid": "ffc00d5e92854b6d903b1801dba38367", "flip": True, "bare": r"^Track$", "gun_from": "hull",
                  "gun_ymin": 1.7, "casemate": True, "clip_y": 3.2,
                  "rules": [("track", "mat", r"^Track$"), ("wheel", "mat", r"^Wheels$")]},
    "stuart": {"uid": "812605c25a424162a54549faf7a39587", "bare": r"^Track$|Rubber", "gun_from": "turret", "clip_y": 2.7,
               "turret_box": [[-0.9, 0.9, 1.55, -0.85, 0.85], [0.4, 1.7, 2.3, -0.25, 0.25]], "rules": [("track", "mat", r"^Track$")], "wheels_from": ["hull"]},
    "lee": {"uid": "268c6a0ef3e3492f93f9c2a3213a0a6f", "bare": r"track_mat", "casemate": True, "clip_y": 3.3,
            "rules": [("track", "mat", r"track_mat"), ("wheel", "mat", r"chassis"), ("gun", "path", r"gun_02Shape")]},
    "churchill": {"uid": "ac032b8154f941a99914ba8679109064", "bare": r"Object_(91|39)$", "gun_from": "turret", "clip_y": 3.0,
                  "rules": [("track", "path", r"Object_(91|39)$"), ("wheel", "path", r"/4(\.014_64|_38)/"),
                            ("turret", "path", r"/1_5/")]},
    "comet": {"uid": "f30f1655bba04489b33c079f50e62716", "bare": r"Lower_Body", "gun_from": "turret", "wheels_from": ["track"],
              "clip_y": 3.0, "rules": [("track", "mat", r"Lower_Body"), ("turret", "mat", r"^Tower$")]},
    "kv2": {"uid": "ed4ce3da390e4aa6bddb0c7507fa93cd", "bare": r"KV-2_track", "clip_y": 3.4,
            "rules": [("wheel", "path", r"KV-2_wheel"), ("track", "mat", r"KV-2_track"), ("gun", "path", r"KV-2_gun|KV-2_mask"),
                      ("turret", "mat", r"KV-2_turret")]},
    "su85": {"uid": "2fb9d8a5caa247bbb5a5eb2518f3e0b2", "bare": r"Track_GP|Track_Color", "gun_from": "hull", "gun_ymin": 1.3,
             "clip_y": 2.6, "casemate": True, "rules": [("track", "path", r"Track_GP"), ("wheel", "path", r"Tire_Gp")]},
    "su100": {"uid": "b31f0902aa554702bb265700ce655b25", "bare": r"Track_GP|Track_Color", "gun_from": "hull", "gun_ymin": 1.3,
              "clip_y": 2.6, "casemate": True,
              "rules": [("track", "path", r"Track_GP"), ("wheel", "path", r"Tire_Gp")]},
}

CLASSES = ["hull", "turret", "gun", "wheel", "track", "drop"]
HULL, TURRET, GUN, WHEEL, TRACK, DROP = range(6)
# Бюджет треугольников на телефон (каждая часть отдельно; катки — на один каток).
BUDGET = {HULL: 6500, TURRET: 2600, GUN: 700, WHEEL: 260}


# ---------- загрузка ----------

def token():
    t = os.environ.get("SKETCHFAB_TOKEN", "")
    if not t:
        sys.exit("нужен SKETCHFAB_TOKEN (Sketchfab → Settings → Password & API)")
    return t


def api(url):
    req = urllib.request.Request(url, headers={"Authorization": "Token " + token(), "User-Agent": "Mozilla/5.0"})
    return json.loads(urllib.request.urlopen(req, timeout=60).read())


def fetch(key, folder):
    """Скачивает GLB и сведения об авторе (кэш в folder)."""
    uid = MODELS[key]["uid"]
    glb = os.path.join(folder, key + ".glb")
    info = os.path.join(folder, key + ".info.json")
    if not os.path.exists(info):
        m = api("https://api.sketchfab.com/v3/models/" + uid)
        json.dump({"name": m["name"], "author": m["user"]["displayName"], "user": m["user"]["username"],
                   "license": m["license"]["label"], "url": m["viewerUrl"]}, open(info, "w"), ensure_ascii=False)
    if not os.path.exists(glb):
        d = api("https://api.sketchfab.com/v3/models/%s/download" % uid)
        urllib.request.urlretrieve(d["glb"]["url"], glb + ".part")
        os.rename(glb + ".part", glb)
    return glb, json.load(open(info))


def load(path):
    """Все сетки сцены в мировых координатах: путь узлов, материал, вершины, нормали, грани, UV, текстура."""
    import trimesh
    sc = trimesh.load(path, force="scene", process=False, maintain_order=True)
    parents = sc.graph.transforms.parents
    parts = []
    for node in sc.graph.nodes_geometry:
        T, gname = sc.graph[node]
        g = sc.geometry[gname]
        if not isinstance(g, trimesh.Trimesh) or len(g.faces) == 0:
            continue
        chain = []
        n = node
        while n is not None and n != sc.graph.base_frame:
            chain.append(str(n))
            n = parents.get(n)
        chain.reverse()
        V = trimesh.transform_points(np.asarray(g.vertices, np.float64), T)
        N = np.asarray(g.vertex_normals, np.float64) @ np.linalg.inv(T[:3, :3])
        N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
        F = np.asarray(g.faces, np.int64)
        if np.linalg.det(T[:3, :3]) < 0:
            F = F[:, ::-1]
        uv, img, col, mname = None, None, np.array([0.8, 0.8, 0.8, 1.0]), ""
        vis = g.visual
        if isinstance(vis, trimesh.visual.TextureVisuals):
            m = vis.material
            mname = getattr(m, "name", "") or ""
            if getattr(vis, "uv", None) is not None and len(vis.uv) == len(V):
                uv = np.asarray(vis.uv, np.float64)
            if isinstance(m, trimesh.visual.material.PBRMaterial):
                if m.baseColorFactor is not None:
                    c = np.asarray(m.baseColorFactor, np.float64)
                    col = c / 255.0 if c.max() > 1.0 else c
                img = m.baseColorTexture
            elif isinstance(m, trimesh.visual.material.SimpleMaterial):
                img = m.image
                if m.diffuse is not None:
                    col = np.asarray(m.diffuse, np.float64) / 255.0
        elif isinstance(vis, trimesh.visual.ColorVisuals):
            col = np.asarray(vis.main_color, np.float64) / 255.0
        if img is None or uv is None:
            img, uv = None, None
        parts.append({"path": "/".join(chain), "mat": mname, "V": V, "N": N, "F": F, "uv": uv, "img": img, "col": col})
    return parts


# ---------- разметка, ориентация, масштаб ----------

def classify(parts, cfg):
    for p in parts:
        p["cls"] = HULL
        for cls, field, rx in cfg["rules"]:
            if re.search(rx, p[field]):
                p["cls"] = CLASSES.index(cls)
                break
        p["bare"] = bool(cfg.get("bare")) and bool(re.search(cfg["bare"], p["mat"] + " " + p["path"]))


def orient(parts, cfg, size):
    """Нос к +X, верх +Y, правый борт +Z; длина корпуса по SPECS; начало — центр днища."""
    keep = [p for p in parts if p["cls"] != DROP]
    allv = np.concatenate([p["V"] for p in keep])
    lo, hi = allv.min(0), allv.max(0)
    ext = hi - lo
    up = np.array([0.0, 1.0, 0.0])
    ax = 0 if ext[0] >= ext[2] else 2
    f = np.zeros(3)
    f[ax] = 1.0
    cen = (lo + hi) / 2
    guns = [p["V"] for p in keep if p["cls"] == GUN]
    turs = [p["V"] for p in keep if p["cls"] == TURRET]
    if guns:
        # ствол — спереди от середины
        f[ax] = np.sign(np.concatenate(guns)[:, ax].mean() - cen[ax]) or 1.0
    elif turs:
        # башня со стволом длиннее вперёд, чем назад
        t = np.concatenate(turs)[:, ax]
        tc = np.median(t)
        f[ax] = 1.0 if t.max() - tc > tc - t.min() else -1.0
    if cfg.get("flip"):
        f = -f
    R = np.stack([f, up, np.cross(f, up)])
    for p in parts:
        p["V"] = p["V"] @ R.T
        p["N"] = p["N"] @ R.T
    low = np.concatenate([p["V"] for p in keep if p["cls"] in (HULL, WHEEL, TRACK)])
    y0 = np.percentile(low[:, 1], 0.05)
    h = np.percentile(low[:, 1], 99.5) - y0
    body = low[low[:, 1] < y0 + h * 0.5]
    xl, xh = np.percentile(body[:, 0], [0.05, 99.95])
    zl, zh = np.percentile(body[:, 2], [0.05, 99.95])
    s = size[0] / (xh - xl)
    off = np.array([(xl + xh) / 2, y0, (zl + zh) / 2])
    for p in parts:
        p["V"] = (p["V"] - off) * s
    return s, (zh - zl) * s


def explode(parts):
    """Переход к «супу» граней: всё по треугольникам, чтобы делить детали по геометрии."""
    P, N, UV, pid, cls = [], [], [], [], []
    for i, p in enumerate(parts):
        F = p["F"]
        P.append(p["V"][F])
        N.append(p["N"][F])
        UV.append(p["uv"][F] if p["uv"] is not None else np.full((len(F), 3, 2), np.nan))
        pid.append(np.full(len(F), i))
        cls.append(np.full(len(F), p["cls"]))
    return {"P": np.concatenate(P), "N": np.concatenate(N), "UV": np.concatenate(UV), "pid": np.concatenate(pid),
            "cls": np.concatenate(cls), "wheel": np.full(sum(len(c) for c in cls), -1)}


def components(P):
    """Связные куски (по совпадающим вершинам) для набора треугольников: метка на каждую грань."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    key = np.round(P.reshape(-1, 3) / 2e-4).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    Fi = inv.reshape(-1, 3)
    n = int(inv.max()) + 1
    r = np.concatenate([Fi[:, 0], Fi[:, 1]])
    c = np.concatenate([Fi[:, 1], Fi[:, 2]])
    _, lab = connected_components(coo_matrix((np.ones(len(r)), (r, c)), shape=(n, n)), directed=False)
    return lab[Fi[:, 0]]


def find_wheels(S, cfg, size):
    """Катки, звёздочки и ленивцы — круглые куски внизу у бортов. Остальное из «катков» — в корпус."""
    L, W, tw, th = size
    src = [WHEEL] + [CLASSES.index(c) for c in cfg.get("wheels_from", ["hull", "track"])]
    idx = np.where(np.isin(S["cls"], src))[0]
    wheels = []
    if len(idx) == 0:
        return wheels
    lab = components(S["P"][idx])
    order = np.argsort(lab)
    lab_s = lab[order]
    cuts = np.flatnonzero(np.diff(lab_s)) + 1
    groups = np.split(idx[order], cuts)
    comps = []
    for g in groups:
        v = S["P"][g].reshape(-1, 3)
        lo, hi = v.min(0), v.max(0)
        d = hi - lo
        c = (lo + hi) / 2
        comps.append((g, lo, hi, d, c))
    # колёса стоят в плоскости гусеницы: центр по ширине — в её пределах
    trk = S["P"][S["cls"] == TRACK].reshape(-1, 3)
    zr = None
    if len(trk) > 100:
        az = np.abs(trk[:, 2])
        zr = (np.percentile(az, 1) - 0.03, np.percentile(az, 99) + 0.03)
    # круглые куски у бортов, ниже верхней ветви гусеницы
    rounds = []
    for k, (g, lo, hi, d, c) in enumerate(comps):
        r = max(d[0], d[1]) / 2
        if (0.1 < r < 0.62 and abs(d[0] - d[1]) < 0.18 * max(d[0], d[1]) and d[2] < max(d[0], d[1]) * 1.1
                and c[1] < th + 0.15 and abs(c[2]) > W / 2 - tw - 0.45
                and (zr is None or zr[0] <= abs(c[2]) <= zr[1])):
            rounds.append(k)
    # концентрические куски одного катка (шина, диск, ступица) — один каток
    for k in sorted(rounds, key=lambda k: -max(comps[k][3][0], comps[k][3][1])):
        g, lo, hi, d, c = comps[k]
        r = max(d[0], d[1]) / 2
        side = 1.0 if c[2] > 0 else -1.0
        for w in wheels:
            if w["side"] == side and abs(w["x"] - c[0]) < 0.06 and abs(w["y"] - c[1]) < 0.06 and abs(w["z"] - c[2]) < 0.6:
                w["comps"].append(k)
                w["z0"] = min(w["z0"], lo[2])
                w["z1"] = max(w["z1"], hi[2])
                break
        else:
            wheels.append({"x": c[0], "y": c[1], "z": c[2], "r": r, "side": side, "comps": [k], "z0": lo[2], "z1": hi[2]})
    # мелочь внутри круга катка (болты, колпаки) крутится вместе с ним
    taken = set(k for w in wheels for k in w["comps"])
    for k, (g, lo, hi, d, c) in enumerate(comps):
        if k in taken:
            continue
        for w in wheels:
            if (np.hypot(c[0] - w["x"], c[1] - w["y"]) + max(d[0], d[1]) / 2 < w["r"] * 1.02
                    and w["z0"] - 0.03 <= lo[2] and hi[2] <= w["z1"] + 0.03):
                w["comps"].append(k)
                break
    for i, w in enumerate(wheels):
        for k in w["comps"]:
            g = comps[k][0]
            S["wheel"][g] = i
            S["cls"][g] = WHEEL
    # не круглое из класса «каток» (рычаги, балансиры) — в корпус
    S["cls"][(S["cls"] == WHEEL) & (S["wheel"] < 0)] = HULL
    return wheels


def gun_split(S, cfg, ring_x):
    """Вырезает ствол из башни (или корпуса САУ): идём от дульного среза назад по сечению,
    пока оно узкое; где сечение резко расширяется — маска и лоб башни."""
    src = CLASSES.index(cfg["gun_from"])
    cen = S["P"].mean(1)
    sel = S["cls"] == src
    if "gun_ymin" in cfg:
        sel &= cen[:, 1] > cfg["gun_ymin"]
    idx = np.where(sel)[0]
    x1 = cen[idx, 0].max()
    tip = idx[cen[idx, 0] > x1 - 0.5]
    ya, za = np.median(cen[tip, 1]), np.median(cen[tip, 2])
    near = idx[(np.abs(cen[idx, 1] - ya) < 0.5) & (np.abs(cen[idx, 2] - za) < 0.5) & (cen[idx, 0] > ring_x)]
    step = 0.04
    x = x1
    cut = None
    wide = 0
    while x > ring_x:
        b = near[(cen[near, 0] <= x) & (cen[near, 0] > x - step)]
        if len(b):
            v = S["P"][b].reshape(-1, 3)
            e = max(v[:, 1].max() - v[:, 1].min(), v[:, 2].max() - v[:, 2].min())
            wide = wide + 1 if e > 0.62 else 0
            if wide >= 2:
                cut = x + step
                break
        x -= step
    if cut is None:
        raise RuntimeError("не найден срез ствола")
    g = near[cen[near, 0] > cut]
    S["cls"][g] = GUN
    return cut


def barrel_axis(S):
    """Ось ствола — горизонталь через центр дульного среза (там нет спаренного пулемёта и маски).
    Возвращает x начала узкой части ствола и высоту и смещение оси."""
    g = np.where(S["cls"] == GUN)[0]
    v = S["P"][g].reshape(-1, 3)
    x1 = v[:, 0].max()
    muzzle = v[v[:, 0] > x1 - 0.12]
    y = (muzzle[:, 1].max() + muzzle[:, 1].min()) / 2
    z = (muzzle[:, 2].max() + muzzle[:, 2].min()) / 2
    start = x1
    near = v[(np.abs(v[:, 1] - y) < 0.4) & (np.abs(v[:, 2] - z) < 0.4)]
    for x in np.arange(x1, near[:, 0].min(), -0.04):
        b = near[(near[:, 0] <= x) & (near[:, 0] > x - 0.04)]
        if len(b) < 3:
            continue
        if max(np.ptp(b[:, 1]), np.ptp(b[:, 2])) > 0.62:
            break
        start = x - 0.04
    return start, float(y), float(z)


def surface_z(T, x, y):
    """Наибольшая z поверхности (правый борт) на прямой, параллельной Z, через (x, y)."""
    a, b, c = T[:, 0], T[:, 1], T[:, 2]
    d = (b[:, 1] - c[:, 1]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 1] - c[:, 1])
    ok = np.abs(d) > 1e-9
    d = np.where(ok, d, 1.0)
    l1 = ((b[:, 1] - c[:, 1]) * (x - c[:, 0]) + (c[:, 0] - b[:, 0]) * (y - c[:, 1])) / d
    l2 = ((c[:, 1] - a[:, 1]) * (x - c[:, 0]) + (a[:, 0] - c[:, 0]) * (y - c[:, 1])) / d
    l3 = 1 - l1 - l2
    hit = ok & (l1 >= 0) & (l2 >= 0) & (l3 >= 0)
    if not hit.any():
        return None
    return float((l1 * a[:, 2] + l2 * b[:, 2] + l3 * c[:, 2])[hit].max())


def surface_y(T, x, z):
    """Наибольшая высота поверхности на вертикали через (x, z)."""
    Q = T[:, :, [0, 2, 1]]
    return surface_z(Q, x, z)


def side_mark(T, x, y):
    """Место для знака на борту: [x, y, z, наклон борта]."""
    z = surface_z(T, x, y)
    if z is None:
        return None
    z1, z0 = surface_z(T, x, y + 0.12), surface_z(T, x, y - 0.12)
    tilt = float(np.arctan2(z0 - z1, 0.24)) if z1 is not None and z0 is not None else 0.0
    return [float(x), float(y), z, tilt]


def section(T, y):
    """Точки сечения треугольников плоскостью высоты y (в плоскости XZ)."""
    pts = []
    for i, j in ((0, 1), (1, 2), (2, 0)):
        a, b = T[:, i], T[:, j]
        m = (a[:, 1] - y) * (b[:, 1] - y) < 0
        t = (y - a[m, 1]) / (b[m, 1] - a[m, 1])
        pts.append(a[m] + (b[m] - a[m]) * t[:, None])
    p = np.concatenate(pts)
    return p[:, [0, 2]]


def area_samples(T, n=40000, seed=0):
    """Точки, равномерно разбросанные по площади поверхности (для оценки габаритов без мелочей)."""
    rng = np.random.default_rng(seed)
    a = np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1)
    idx = rng.choice(len(T), n, p=a / a.sum())
    r1 = np.sqrt(rng.random(n))
    r2 = rng.random(n)
    t = T[idx]
    return t[:, 0] * (1 - r1)[:, None] + t[:, 1] * (r1 * (1 - r2))[:, None] + t[:, 2] * (r1 * r2)[:, None]


def poly_centroid(P):
    x, y = P[:, 0], P[:, 1]
    x1, y1 = np.roll(x, -1), np.roll(y, -1)
    cr = x * y1 - x1 * y
    a = cr.sum() / 2
    return np.array([((x + x1) * cr).sum() / (6 * a), ((y + y1) * cr).sum() / (6 * a)])


def in_poly(pts, poly):
    from matplotlib.path import Path
    return Path(poly).contains_points(pts)


def hull2d(pts):
    from scipy.spatial import ConvexHull
    h = ConvexHull(pts)
    return pts[h.vertices]


def rot_z(P, c, a):
    """Поворот точек (…,3) вокруг оси Z через точку c на угол a."""
    ca, sa = np.cos(a), np.sin(a)
    q = P - c
    out = q.copy()
    out[..., 0] = q[..., 0] * ca - q[..., 1] * sa
    out[..., 1] = q[..., 0] * sa + q[..., 1] * ca
    return out + c


# ---------- упрощение, развёртка, запекание ----------

def weld_pos(P, A):
    """Общие вершины по позиции (и данным катка/окраски) — без оглядки на швы UV исходника."""
    n = len(P)
    flat = np.concatenate([P.reshape(-1, 3), A.reshape(-1, A.shape[-1])], 1)
    key = np.round(flat * np.array([1e4] * 3 + [1e3] * A.shape[-1])).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return flat[first].astype(np.float32), inv.reshape(n, 3).astype(np.uint32)


def unwrap(groups):
    """Новая развёртка всех частей танка в один атлас (xatlas). На входе — сварные сетки и
    нормали в углах граней; на выходе — вершины (позиция, нормаль, данные), грани, UV."""
    import xatlas
    atlas = xatlas.Atlas()
    for v, f, cn in groups:
        atlas.add_mesh(np.ascontiguousarray(v[:, :3]), np.ascontiguousarray(f.astype(np.uint32)))
    co = xatlas.ChartOptions()
    co.max_iterations = 2
    po = xatlas.PackOptions()
    po.resolution = ATLAS
    po.padding = 4
    po.bilinear = True
    po.rotate_charts = True
    atlas.generate(co, po)
    out = []
    for i, (v, f, cn) in enumerate(groups):
        vmap, idx, uv = atlas[i]
        # вершина итоговой сетки — пара (вершина развёртки, нормаль угла)
        cv = idx.reshape(-1)
        key = np.concatenate([cv[:, None].astype(np.float64), np.round(cn.reshape(-1, 3) * 1e3)], 1)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        src = cv[first]
        verts = np.concatenate([v[vmap[src], :3], cn.reshape(-1, 3)[first], v[vmap[src], 3:]], 1)
        out.append((verts.astype(np.float32), inv.reshape(-1, 3).astype(np.uint32), uv[src].astype(np.float32)))
    return out


def raster(uv, f, size):
    """Тексели внутри треугольников развёртки: (номер грани, барицентрические, x, y)."""
    pix = uv * size - 0.5
    T = pix[f]
    out_f, out_b, out_x, out_y = [], [], [], []
    for i, t in enumerate(T):
        x0, y0 = np.floor(t.min(0)).astype(int)
        x1, y1 = np.ceil(t.max(0)).astype(int)
        xs, ys = np.meshgrid(np.arange(max(0, x0), min(size, x1 + 1)), np.arange(max(0, y0), min(size, y1 + 1)))
        xs = xs.ravel()
        ys = ys.ravel()
        if not len(xs):
            continue
        a, b, c = t
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l1 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / d
        l2 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / d
        l3 = 1 - l1 - l2
        m = (l1 > -0.08) & (l2 > -0.08) & (l3 > -0.08)
        if not m.any():
            continue
        bc = np.clip(np.stack([l1[m], l2[m], l3[m]], 1), 0, None)
        bc /= bc.sum(1, keepdims=True)
        out_f.append(np.full(m.sum(), i))
        out_b.append(bc)
        out_x.append(xs[m])
        out_y.append(ys[m])
    return np.concatenate(out_f), np.concatenate(out_b), np.concatenate(out_x), np.concatenate(out_y)


def closest_on_tri(p, a, b, c):
    """Ближайшая точка треугольника (векторно): барицентрические координаты и расстояние."""
    ab, ac = b - a, c - a
    n = np.cross(ab, ac)
    nn = (n * n).sum(-1) + 1e-18
    q = p - ((p - a) * n).sum(-1, keepdims=True) * n / nn[..., None]
    # барицентрические проекции, затем обрезка в пределы треугольника
    v0, v1, v2 = ab, ac, q - a
    d00 = (v0 * v0).sum(-1)
    d01 = (v0 * v1).sum(-1)
    d11 = (v1 * v1).sum(-1)
    d20 = (v2 * v0).sum(-1)
    d21 = (v2 * v1).sum(-1)
    den = d00 * d11 - d01 * d01 + 1e-18
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    u = 1 - v - w
    bc = np.clip(np.stack([u, v, w], -1), 0, None)
    bc /= bc.sum(-1, keepdims=True) + 1e-12
    cp = bc[..., :1] * a + bc[..., 1:2] * b + bc[..., 2:] * c
    return bc, np.linalg.norm(p - cp, axis=-1)


def ambient_occlusion(P, N, occ, rays=14, radius=0.9, seed=1):
    """Затенение окружением: для каждой точки — доля лучей полусферы (по косинусу), упёршихся
    в соседние детали ближе radius (м). Попадание в изнанку грани у самой поверхности не в счёт:
    упрощённая сетка местами проходит чуть внутри исходной."""
    from embreex import rtcore_scene as rtcs
    from embreex.mesh_construction import TriangleMesh
    sc = rtcs.EmbreeScene()
    TriangleMesh(sc, np.ascontiguousarray(occ, np.float32))
    rng = np.random.default_rng(seed)
    k = int(np.ceil(np.sqrt(rays)))
    cells = [((i + 0.5) / k, (j + 0.5) / k) for i in range(k) for j in range(k)][:rays]
    ao = np.ones(len(P))
    for c0 in range(0, len(P), 40000):
        p = P[c0:c0 + 40000].astype(np.float64)
        n = N[c0:c0 + 40000].astype(np.float64)
        t = np.cross(n, np.array([0.0, 1.0, 0.0]))
        bad = np.linalg.norm(t, axis=1) < 0.2
        t[bad] = np.cross(n[bad], np.array([1.0, 0.0, 0.0]))
        t /= np.linalg.norm(t, axis=1, keepdims=True) + 1e-12
        b = np.cross(n, t)
        rot = rng.random(len(p)) * 2 * np.pi
        o = (p + n * 0.03).astype(np.float32)
        far = np.full(len(p), radius, np.float32)
        occl = np.zeros(len(p))
        for u1, u2 in cells:
            r = np.sqrt(u1)
            phi = 2 * np.pi * u2 + rot
            d = t * (r * np.cos(phi))[:, None] + b * (r * np.sin(phi))[:, None] + n * np.sqrt(1 - u1)
            res = sc.run(o, d.astype(np.float32), dists=far.copy(), query="INTERSECT", output=1)
            hit = res["primID"] >= 0
            front = (res["Ng"] * d).sum(1) < 0
            ok = hit & (front | (res["tfar"] > 0.08))
            occl += ok * (1.0 - (np.minimum(res["tfar"], radius) / radius) ** 2)
        ao[c0:c0 + 40000] = 1.0 - occl / len(cells)
    return ao


def bake(meshes, S, parts, size=ATLAS):
    """Цвет исходной модели на новую развёртку: для каждого текселя — ближайшая исходная грань
    той же части танка (с учётом направления нормали), из её текстуры берётся цвет.
    Плюс затенение окружением от соседних деталей (occ — их треугольники в той же системе)."""
    from scipy.spatial import cKDTree
    from PIL import Image
    img = np.zeros((size, size, 3))
    aoi = np.ones((size, size))
    mask = np.zeros((size, size), bool)
    texcache = {}
    for v, f, uv, src, occ in meshes:
        fi, bc, xs, ys = raster(uv, f, size)
        P = (v[f[fi]][:, :, :3] * bc[:, :, None]).sum(1)
        N = (v[f[fi]][:, :, 3:6] * bc[:, :, None]).sum(1)
        N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9
        aoi[ys, xs] = ambient_occlusion(P, N, occ)
        ST = S["P"][src]
        SN = np.cross(ST[:, 1] - ST[:, 0], ST[:, 2] - ST[:, 0])
        SN /= np.linalg.norm(SN, axis=1, keepdims=True) + 1e-12
        tree = cKDTree(ST.mean(1))
        K = min(10, len(src))
        col = np.zeros((len(P), 3))
        for c0 in range(0, len(P), 60000):
            p = P[c0:c0 + 60000]
            n = N[c0:c0 + 60000]
            _, nb = tree.query(p, k=K)
            nb = nb.reshape(len(p), K)
            T = ST[nb]
            b2, d = closest_on_tri(p[:, None, :], T[:, :, 0], T[:, :, 1], T[:, :, 2])
            facing = (SN[nb] * n[:, None, :]).sum(-1)
            score = d + 0.03 * (facing < 0.2) + 0.01 * (1 - np.abs(facing))
            best = np.argmin(score, 1)
            r = np.arange(len(p))
            g = src[nb[r, best]]
            bb = b2[r, best]
            for pid in np.unique(S["pid"][g]):
                m = S["pid"][g] == pid
                part = parts[pid]
                c = np.clip(part["col"][:3], 0, 1)
                if part["img"] is None:
                    col[c0 + np.where(m)[0]] = c
                    continue
                key = id(part["img"])
                if key not in texcache:
                    texcache[key] = np.asarray(part["img"].convert("RGB"), np.float32) / 255.0
                tex = texcache[key]
                uvs = (S["UV"][g[m]] * bb[m][:, :, None]).sum(1)
                uvs = np.nan_to_num(uvs) % 1.0
                tx = np.clip((uvs[:, 0] * tex.shape[1]).astype(int), 0, tex.shape[1] - 1)
                ty = np.clip(((1 - uvs[:, 1]) * tex.shape[0]).astype(int), 0, tex.shape[0] - 1)
                col[c0 + np.where(m)[0]] = tex[ty, tx] * c
        img[ys, xs] = col
        mask[ys, xs] = True
    # растекание за края островов, чтобы мип-уровни не тянули чёрное
    filled = mask.copy()
    for _ in range(12):
        acc = np.zeros_like(img)
        cnt = np.zeros(mask.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            sh = np.roll(np.roll(filled, dy, 0), dx, 1)
            acc += np.roll(np.roll(img, dy, 0), dx, 1) * sh[..., None]
            cnt += sh
        grow = (~filled) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        filled |= grow
    img[~filled] = img[filled].mean(0)
    # мелкая светотень: яркость к местному среднему (крупные пятна камуфляжа не мешают перекраске);
    # светлые надписи и номера исходника срезаются сверху, тени и стыки листов остаются
    lum = img @ np.array([0.299, 0.587, 0.114])
    from scipy.ndimage import gaussian_filter

    def blur(a, s=7.0):
        return gaussian_filter(a, s, mode="nearest")
    mloc = blur(mask.astype(np.float64))
    lb = blur(lum * mask) / (mloc + 1e-4)
    lb = np.where(mloc > 0.01, lb, lum)
    detail = 1.0 + (np.clip(lum / (lb + 0.04), 0.45, 1.1) - 1.0) * 0.85
    # затенение: шум лучей сглаживается в пределах островов развёртки
    m1 = blur(mask.astype(np.float64), 1.2)
    ao = np.where(m1 > 0.05, blur(aoi * mask, 1.2) / (m1 + 1e-6), 1.0)
    ao = np.clip(ao, 0.0, 1.0) ** 1.1
    img = img * (1.0 - 0.75 * (1.0 - ao))[..., None]
    alpha = detail * (1.0 - 0.85 * (1.0 - ao)) * 0.5
    rgba = np.concatenate([img, alpha[..., None]], -1)
    return Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def corner_normals(v, f, angle=50.0):
    """Нормали в углах граней со сглаживанием: соседние грани под углом больше angle — острое ребро."""
    P = v[:, :3].astype(np.float64)
    fn = np.cross(P[f[:, 1]] - P[f[:, 0]], P[f[:, 2]] - P[f[:, 0]])
    fa = np.linalg.norm(fn, axis=1)
    fn = fn / (fa[:, None] + 1e-12)
    cos_t = np.cos(np.radians(angle))
    corner_v = f.reshape(-1)
    corner_f = np.repeat(np.arange(len(f)), 3)
    out = np.zeros((len(corner_v), 3))
    order = np.argsort(corner_v, kind="stable")
    cuts = np.flatnonzero(np.diff(corner_v[order])) + 1
    for grp in np.split(order, cuts):
        fs = corner_f[grp]
        n = fn[fs]
        w = fa[fs][:, None] * n
        # для каждого угла — сумма нормалей соседних граней, близких по направлению
        close = (n @ n.T) > cos_t
        acc = close.astype(np.float64) @ w
        out[grp] = acc / (np.linalg.norm(acc, axis=1, keepdims=True) + 1e-12)
    return out.reshape(-1, 3, 3).astype(np.float32)


def simplify(verts, idx, target):
    """Упрощение до бюджета с наименьшей возможной ошибкой (в метрах): мелочь меньше ошибки
    (болты, заклёпки) удаляется целиком."""
    import meshoptimizer as mo
    if len(idx) <= target:
        return idx
    pos = np.ascontiguousarray(verts[:, :3])
    flat = idx.reshape(-1).astype(np.uint32)
    best = flat
    for err in (0.002, 0.004, 0.007, 0.01, 0.015, 0.02, 0.03, 0.045, 0.06, 0.08, 0.11):
        dst = np.zeros(len(flat), np.uint32)
        k = mo.simplify(dst, flat, pos, target_index_count=target * 3, target_error=err,
                        options=mo.SIMPLIFY_PRUNE | mo.SIMPLIFY_ERROR_ABSOLUTE)
        if k == 0:
            break
        best = dst[:k]
        if k <= target * 3 * 1.1:
            break
    out = np.zeros(len(best), np.uint32)
    mo.optimize_vertex_cache(out, best, vertex_count=len(verts))
    return out.reshape(-1, 3)


def write_glb(path, meshes):
    """meshes: [(имя, вершины float32 (n,14), индексы (m,3))] → GLB с узлами по именам."""
    from pygltflib import (GLTF2, Scene, Node, Mesh, Primitive, Attributes, Buffer, BufferView, Accessor,
                           FLOAT, UNSIGNED_INT, UNSIGNED_SHORT, ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER)
    data = bytearray()
    views, accs, gmeshes, nodes = [], [], [], []

    def add(arr, target, ctype, typ, minmax=False):
        raw = arr.tobytes()
        while len(data) % 4:
            data.append(0)
        views.append(BufferView(buffer=0, byteOffset=len(data), byteLength=len(raw), target=target))
        data.extend(raw)
        kw = {"min": arr.min(0).tolist(), "max": arr.max(0).tolist()} if minmax else {}
        accs.append(Accessor(bufferView=len(views) - 1, componentType=ctype, count=len(arr), type=typ, **kw))
        return len(accs) - 1

    for name, v, f in meshes:
        used = np.unique(f)
        remap = np.zeros(len(v), np.int64)
        remap[used] = np.arange(len(used))
        v = v[used]
        f = remap[f]
        a = {"POSITION": add(np.ascontiguousarray(v[:, 0:3]), ARRAY_BUFFER, FLOAT, "VEC3", True),
             "NORMAL": add(np.ascontiguousarray(v[:, 3:6]), ARRAY_BUFFER, FLOAT, "VEC3"),
             "TEXCOORD_0": add(np.ascontiguousarray(v[:, 6:8]), ARRAY_BUFFER, FLOAT, "VEC2"),
             "TEXCOORD_1": add(np.ascontiguousarray(v[:, 8:10]), ARRAY_BUFFER, FLOAT, "VEC2"),
             "TEXCOORD_2": add(np.ascontiguousarray(v[:, 10:12]), ARRAY_BUFFER, FLOAT, "VEC2"),
             "TEXCOORD_3": add(np.ascontiguousarray(v[:, 12:14]), ARRAY_BUFFER, FLOAT, "VEC2")}
        if len(v) < 65536:
            ind = add(np.ascontiguousarray(f.reshape(-1).astype(np.uint16)), ELEMENT_ARRAY_BUFFER, UNSIGNED_SHORT, "SCALAR")
        else:
            ind = add(np.ascontiguousarray(f.reshape(-1).astype(np.uint32)), ELEMENT_ARRAY_BUFFER, UNSIGNED_INT, "SCALAR")
        gmeshes.append(Mesh(name=name, primitives=[Primitive(attributes=Attributes(**a), indices=ind)]))
        nodes.append(Node(name=name, mesh=len(gmeshes) - 1))
    g = GLTF2(scene=0, scenes=[Scene(nodes=list(range(len(nodes))))], nodes=nodes, meshes=gmeshes,
              buffers=[Buffer(byteLength=len(data))], bufferViews=views, accessors=accs)
    g.set_binary_blob(bytes(data))
    g.save_binary(path)


# ---------- отладочные картинки ----------

COLORS = {HULL: (0.55, 0.6, 0.45), TURRET: (0.85, 0.65, 0.2), GUN: (0.9, 0.2, 0.15), WHEEL: (0.25, 0.45, 0.85),
          TRACK: (0.3, 0.3, 0.3), DROP: (1, 0, 1)}


def debug_png(S, path, title, marks=()):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection
    fig, axs = plt.subplots(1, 3, figsize=(21, 6))
    views = [("сбоку (X вперёд, Y вверх)", 0, 1, 2), ("сверху (X вперёд, Z вправо)", 0, 2, 1), ("спереди (Z, Y)", 2, 1, 0)]
    keep = np.where(S["cls"] != DROP)[0]
    if len(keep) > 150000:
        keep = np.random.default_rng(0).choice(keep, 150000, replace=False)
    T = S["P"][keep]
    C = np.array([COLORS[c] for c in range(6)])[S["cls"][keep]]
    wh = S["wheel"][keep]
    C[wh >= 0] *= (0.7 + 0.3 * (wh[wh >= 0] % 3) / 2)[:, None]
    nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
    shade = 0.55 + 0.45 * np.abs(nrm @ (np.array([0.3, 0.8, 0.5]) / np.linalg.norm([0.3, 0.8, 0.5])))
    for ax, (name, a, b, d) in zip(axs, views):
        order = np.argsort(T[:, :, d].mean(1))
        ax.add_collection(PolyCollection(T[order][:, :, [a, b]], facecolors=np.clip(C[order] * shade[order, None], 0, 1),
                                         edgecolors="none"))
        ax.set_xlim(T[:, :, a].min() - 0.2, T[:, :, a].max() + 0.2)
        ax.set_ylim(T[:, :, b].min() - 0.2, T[:, :, b].max() + 0.2)
        if b == 2:
            ax.invert_yaxis()
        ax.set_aspect("equal")
        ax.set_title(name)
        ax.grid(alpha=0.3)
        for m in marks:
            ax.plot([m[a]], [m[b]], "k+", ms=18, mew=2)
    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(path, dpi=60)
    plt.close(fig)


# ---------- сборка одной модели ----------

def process(key, folder, dbg=None):
    cfg = MODELS[key]
    size = SIZES[key]
    L, W, tw, th = size
    glb, info = fetch(key, folder)
    parts = load(glb)
    if "rot" in cfg:
        R = np.array(cfg["rot"], np.float64)
        for p in parts:
            p["V"] = p["V"] @ R.T
            p["N"] = p["N"] @ R.T
    classify(parts, cfg)
    scale, width = orient(parts, cfg, size)
    S = explode(parts)
    cen = S["P"].mean(1)
    S["cls"][S["cls"] == DROP] = DROP
    if "clip_y" in cfg:
        S["cls"][S["P"][:, :, 1].max(1) > cfg["clip_y"]] = DROP
    for box in cfg.get("turret_box", []):
        x0, x1, y0, z0, z1 = box
        S["cls"][(S["cls"] == HULL) & (cen[:, 0] > x0) & (cen[:, 0] < x1) & (cen[:, 1] > y0) & (cen[:, 2] > z0) & (cen[:, 2] < z1)] = TURRET
    if "gun_xmin" in cfg:
        S["cls"][(S["cls"] == GUN) & (cen[:, 0] < cfg["gun_xmin"])] = DROP
    # детали в материале гусениц, но не на ней (запасные траки, буксирные крюки) — к корпусу
    tr = S["cls"] == TRACK
    S["cls"][tr & ((np.abs(cen[:, 2]) < W / 2 - tw * 1.15) | (cen[:, 1] > th + 0.3))] = HULL
    wheels = find_wheels(S, cfg, size)
    casemate = cfg.get("casemate", False)
    # башня: погон — центр нижнего пояса башни
    if not casemate:
        # то, что из материалов башни лежит ниже крыши корпуса (корзина, полик), — внутрь корпуса
        tsel = np.where(S["cls"] == TURRET)[0]
        tv = S["P"][tsel].reshape(-1, 3)
        x0, x1 = np.percentile(tv[:, 0], [10, 90])
        z0, z1 = np.percentile(tv[:, 2], [10, 90])
        hullT = S["P"][S["cls"] == HULL]
        decks = [surface_y(hullT, x, z) for x in (x0 - 0.25, (x0 + x1) / 2, x1 + 0.25) for z in (z0 - 0.25, z1 + 0.25)]
        decks = [d for d in decks if d is not None]
        if decks:
            deck = float(np.median(decks))
            S["cls"][tsel[cen[tsel, 1] < deck - 0.08]] = HULL
        tv = S["P"][S["cls"] == TURRET].reshape(-1, 3)
        if (S["cls"] == GUN).sum() == 0:
            gun_split(S, cfg, float(np.median(tv[:, 0])))
        tv = S["P"][S["cls"] == TURRET].reshape(-1, 3)
        ty0 = np.percentile(tv[:, 1], 2)
        ty1 = np.percentile(tv[:, 1], 98)
        low = hull2d(tv[tv[:, 1] < ty0 + 0.45 * (ty1 - ty0)][:, [0, 2]])
        ring = np.array([*poly_centroid(low), ty0])[[0, 2, 1]]
        ring[0] = cfg.get("ring_x", ring[0])
        ring[2] = 0.0 if abs(ring[2]) < 0.15 else ring[2]
    else:
        ring = np.array([0.0, 0.0, 0.0])
        if (S["cls"] == GUN).sum() == 0:
            gun_split(S, cfg, 0.0)
    if not casemate:
        # пулемёты, люки и траки на башне, оказавшиеся в материалах корпуса, — к башне
        tv = S["P"][S["cls"] == TURRET].reshape(-1, 3)
        foot = hull2d(tv[:, [0, 2]])
        fc = foot.mean(0)
        foot = fc + (foot - fc) * 1.06
        cand = np.where(np.isin(S["cls"], [HULL]) & (cen[:, 1] > ring[1] + 0.06))[0]
        inside = cand[in_poly(cen[cand][:, [0, 2]], foot)]
        S["cls"][inside] = TURRET
    start, ay, az = barrel_axis(S)
    gsel = S["cls"] == GUN
    gv = S["P"][gsel].reshape(-1, 3)
    tx = min(start - 0.3, gv[:, 0].min() + 0.25) if not casemate else gv[:, 0].min() + 0.2
    tx = cfg.get("trunnion_x", tx)
    trunnion = np.array([tx, ay, 0.0 if abs(az) < 0.12 else az])
    pitch = 0.0
    barrel = gv[:, 0].max() - trunnion[0]
    # гусеницы: контур сбоку и ширина
    trk = S["P"][S["cls"] == TRACK].reshape(-1, 3)
    if len(trk) > 100:
        outline = hull2d(trk[:, :2])
        wl = np.percentile(trk[trk[:, 2] > 0][:, 2], [1, 99]) if (trk[:, 2] > 0).any() else [W / 2 - tw, W / 2]
        wr = np.percentile(trk[trk[:, 2] < 0][:, 2], [1, 99]) if (trk[:, 2] < 0).any() else [-W / 2, -W / 2 + tw]
        t_w = float(((wl[1] - wl[0]) + (wr[1] - wr[0])) / 2)
        t_z = float((wl[1] + wl[0] - wr[1] - wr[0]) / 4)
    else:
        pts = []
        for w in wheels:
            a = np.linspace(0, 2 * np.pi, 16, endpoint=False)
            pts += list(zip(w["x"] + np.cos(a) * (w["r"] + 0.03), w["y"] + np.sin(a) * (w["r"] + 0.03)))
        outline = hull2d(np.array(pts))
        t_w, t_z = tw, W / 2 - tw / 2
    # прореживание контура: не больше ~40 точек
    while len(outline) > 40:
        d = np.linalg.norm(np.roll(outline, -1, 0) - np.roll(outline, 1, 0), axis=1)
        outline = np.delete(outline, int(np.argmin(d)), 0)
    keep = S["cls"] != DROP
    keep &= S["cls"] != TRACK
    # места для знаков: борт корпуса и борт башни
    hullT = S["P"][S["cls"] == HULL]
    ex, ey = -L * 0.08, th + 0.45 * (ring[1] - th if not casemate else 0.9)
    em_hull = side_mark(hullT, ex, ey)
    meta = {"key": key, "source": info, "scale": scale, "track": {"outline": outline.tolist(), "w": t_w, "z": t_z},
            "wheels": [{"x": w["x"], "y": w["y"], "z": w["z"], "r": w["r"]} for w in wheels],
            "barrel": float(barrel), "em_hull": em_hull, "casemate": casemate}
    tris = {}
    # перенос в местные системы шарниров
    S["P"][S["cls"] == GUN] -= trunnion
    if not casemate:
        tsel = S["cls"] == TURRET
        S["P"][tsel] -= ring
        S["P"][S["cls"] == GUN] -= 0  # орудие — от цапф, а цапфы — относительно погона
        tT = S["P"][tsel]
        tv = tT.reshape(-1, 3)
        ttop = float(np.percentile(tv[:, 1], 99.5))
        tfoot = hull2d(tv[:, [0, 2]])
        yb = ttop * 0.5
        band = section(tT, yb)
        # коробка попаданий башни: основной объём без командирской башенки, пулемётов и укладки
        sm = area_samples(tT)
        box0 = [float(np.percentile(sm[:, 0], 1.5)), 0.0, float(np.percentile(sm[:, 2], 1.5))]
        box1 = [float(np.percentile(sm[:, 0], 98.5)), float(np.percentile(sm[:, 1], 93)), float(np.percentile(sm[:, 2], 98.5))]
        meta.update({"box_min": box0, "box_max": box1})
        meta.update({"ring": ring.tolist(), "trunnion": (trunnion - ring).tolist(),
                     "tur_min": [float(tv[:, 0].min()), 0.0, float(tv[:, 2].min())],
                     "tur_max": [float(tv[:, 0].max()), ttop, float(tv[:, 2].max())],
                     "band_y": yb, "band": hull2d(band).tolist() if len(band) > 8 else tfoot.tolist(),
                     "em_tur": side_mark(tT, -0.2, ttop * 0.5)})
    else:
        meta.update({"trunnion": trunnion.tolist()})
    # окраска и данные катков на каждую вершину
    paint = np.array([0.0 if p["bare"] else 1.0 for p in parts])[S["pid"]]
    A = np.zeros((len(S["P"]), 3, 6))
    A[..., 0] = paint[:, None]
    for i, w in enumerate(wheels):
        sel = S["wheel"] == i
        A[sel, :, 2] = w["x"]
        A[sel, :, 3] = w["y"]
        A[sel, :, 4] = 1.0 / w["r"]
        A[sel, :, 5] = w["side"]
    # упрощение по геометрии, нормали, общая развёртка, запекание цвета
    plan = [("hull", HULL, BUDGET[HULL]), ("wheel", WHEEL, min(5200, BUDGET[WHEEL] * max(1, len(wheels)))),
            ("turret", TURRET, BUDGET[TURRET]), ("gun", GUN, BUDGET[GUN])]
    groups, srcs, names = [], [], []
    for name, cl, tgt in plan:
        src = np.where(keep & (S["cls"] == cl))[0]
        if not len(src):
            continue
        v, f = weld_pos(S["P"][src], A[src])
        f = simplify(v, f, tgt)
        groups.append((v, f, corner_normals(v, f)))
        srcs.append(src)
        names.append(name)
        tris[name] = len(f)
    unwrapped = unwrap(groups)
    # заслоняющие детали для затенения — в системе каждой части (башня и орудие — со своим смещением)
    cls_tris = lambda c: S["P"][keep & (S["cls"] == c)] if c != TRACK else S["P"][S["cls"] == TRACK]
    hull_occ = np.concatenate([cls_tris(HULL), cls_tris(WHEEL), cls_tris(TRACK)])
    if casemate:
        gun_occ = np.concatenate([cls_tris(GUN), hull_occ - trunnion])
        tur_occ = None
    else:
        gun_occ = np.concatenate([cls_tris(GUN), cls_tris(TURRET) + (ring - trunnion)])
        tur_occ = np.concatenate([cls_tris(TURRET), cls_tris(GUN) + (trunnion - ring)])
    occ_of = {"hull": hull_occ, "wheel": hull_occ, "turret": tur_occ, "gun": gun_occ}
    atlas = bake([(v, f, uv, src, occ_of[nm]) for (v, f, uv), src, nm in zip(unwrapped, srcs, names)], S, parts)
    built = {}
    for name, (v, f, uv) in zip(names, unwrapped):
        # столбцы: позиция, нормаль, UV, (окраска, 0), центр катка, (1/радиус, борт)
        built[name] = (np.concatenate([v[:, :6], uv, v[:, 6:]], 1).astype(np.float32), f)
    meshes = []
    for name, comb in (("hull", ["hull", "wheel"]), ("turret", ["turret"]), ("gun", ["gun"])):
        vs, fs, base = [], [], 0
        for c in comb:
            if c in built:
                vs.append(built[c][0])
                fs.append(built[c][1] + base)
                base += len(built[c][0])
        if vs:
            meshes.append((name, np.concatenate(vs), np.concatenate(fs)))
    os.makedirs(OUT, exist_ok=True)
    write_glb(os.path.join(OUT, key + ".glb"), meshes)
    atlas.save(os.path.join(OUT, key + ".png"), optimize=True)
    # атлас — со сжатием для видеопамяти (ETC2/ASTC на телефоне) и мип-уровнями
    imp = os.path.join(OUT, key + ".png.import")
    if not os.path.exists(imp):
        with open(imp, "w") as fi:
            fi.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                     'compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\n'
                     'compress/normal_map=2\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\n'
                     'process/fix_alpha_border=false\nprocess/premult_alpha=false\nprocess/size_limit=0\n'
                     'detect_3d/compress_to=0\n')
    meta["tris"] = tris
    json.dump(meta, open(os.path.join(OUT, key + ".json"), "w"), ensure_ascii=False, indent=1)
    print("%-8s масштаб %.4f ширина %.2f/%.2f  погон x=%.2f y=%.2f  цапфы %s  наклон ствола %.1f°  ствол %.2f м  катков %d  треугольников %s" % (
        key, scale, width, W, ring[0], ring[1], np.round(trunnion, 2), np.degrees(pitch), barrel, len(wheels), tris), flush=True)
    if dbg:
        os.makedirs(dbg, exist_ok=True)
        S["P"][S["cls"] == GUN] += trunnion
        if not casemate:
            S["P"][S["cls"] == TURRET] += ring
        debug_png(S, os.path.join(dbg, key + "_cls.png"), key, [ring, trunnion])
    return meta


def credits(folder):
    """Строки для экрана «Авторы» и CREDITS.txt."""
    lines = []
    for key in MODELS:
        p = os.path.join(folder, key + ".info.json")
        if os.path.exists(p):
            i = json.load(open(p))
            lines.append("%s — «%s», %s, %s" % (i["author"], i["name"], i["license"].replace("CC Attribution", "CC-BY 4.0"), i["url"]))
    with open(os.path.join(OUT, "CREDITS.txt"), "w") as f:
        f.write("Модели танков с sketchfab.com (CC-BY 4.0: Creative Commons Attribution). Изменены: упрощены,\n")
        f.write("разделены на части, текстуры собраны в атлас и перекрашиваются под карту, гусеницы заменены.\n\n")
        f.write("\n".join(lines) + "\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    folder = args[0] if args else "/tmp/sketchfab"
    keys = args[1:] or list(MODELS)
    dbg = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--debug=")), None)
    os.makedirs(folder, exist_ok=True)
    for key in keys:
        process(key, folder, dbg)
    credits(folder)


if __name__ == "__main__":
    main()
