#!/usr/bin/env python3
"""Неподвижные модели (ПТ-пушки, самолёты, укрепления) из glb -> godot/assets/units/<имя>.bin + <имя>.png.

Формат тот же, что у пехоты (tools/import_units.py), но с одной позой: модель упрощается, текстуры собираются
в один атлас. Оси результата: +Z — вперёд (ствол, нос), +Y — вверх, низ модели на y = 0, метры.

    python3 -I tools/import_props.py <папка с моделями> [--preview <папка>] [имена…]
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_units as U  # noqa: E402

# src — папка модели; len — длина вдоль оси «вперёд», м; fwd/up — оси исходной модели; pick — какую часть сцены брать
PROPS = {
    "gun_pak40": {"src": "g_pakzis", "len": 5.7, "fwd": (0, 0, 1), "up": (0, 1, 0), "pick": lambda c, e: c[0] > 0.0 and max(e) > 0.12, "tris": 9000, "atlas": 512, "color": (58, 60, 56),
                  "credit": "Pak 40 / ZiS-3 Anti-Tank Gun — Pavluha (CC BY 4.0)"},
    "gun_m3": {"src": "g_m3", "len": 3.9, "fwd": (0, 0, 1), "up": (0, 1, 0), "pick": lambda c, e: not (e[1] < 0.05 and e[0] > 3.0), "tris": 1100,
               "atlas": 64, "color": (84, 90, 58), "credit": "37mm AT Gun M3 — Ronald_Reagan (CC BY 4.0)"},
    "gun_flak88": {"src": "g_flak", "len": 6.7, "fwd": (1, 0, 0), "up": (0, 1, 0), "tris": 2600, "atlas": 256,
                   "credit": "8.8 cm Flak 18 — Liminal Bifrost (CC BY 4.0)"},
    "plane_ju87": {"src": "p_ju87", "len": 11.1, "fwd": (0, 0, 1), "up": (0, 1, 0), "tris": 2200, "atlas": 64, "center": True, "paint": (74, 84, 66),
                   "credit": "Junkers Ju 87 Stuka — Arthur C. Galuppo (CC BY 4.0)"},
    "plane_p47": {"src": "p_p47", "len": 11.0, "fwd": (0, 0, -1), "up": (0, 1, 0), "tris": 2200, "atlas": 256, "center": True,
                  "pick": lambda c, e: not (e[1] < 2.0 and e[0] > 1000.0),
                  "credit": "P-47 Thunderbolt — Yo Boy (CC BY 4.0)"},
    "plane_il2": {"src": "p_il2h", "len": 11.6, "fwd": (-1, 0, 0), "up": (0, 1, 0), "tris": 2200, "atlas": 256, "center": True,
                  "credit": "Ilyushin Il-2 — helijah (CC BY 4.0)"},
}


# наборы мелочей (камни, растения, мешки): сцена делится на отдельные предметы по расстоянию между частями,
# каждый запекается как decor_<набор>_<номер>; size — высота самого крупного предмета набора, м
PACKS = {
    "rock": {"src": "d_rocks", "size": 1.3, "tris": 260, "atlas": 128, "credit": "Free Pack — Rocks Stylized — PolyOne Studio (CC BY 4.0)"},
    "plant": {"src": "d_plants", "size": 0.9, "tris": 200, "atlas": 128, "credit": "Low Poly Stylized Plants Pack — Red_Ilya (CC BY 4.0)"},
    "foliage": {"src": "d_foliage", "size": 0.9, "tris": 240, "atlas": 128, "credit": "Stylized Foliage — Aki (CC BY 4.0)"},
    "sandbag": {"src": "d_sandbag", "size": 0.35, "tris": 300, "atlas": 128, "credit": "Sandbag — Islide (CC BY 4.0)"},
    "nature": {"src": "d_nature", "size": 3.0, "tris": 260, "atlas": 128, "credit": "Low Poly Trees Grass and Rocks — olehlila (CC BY 4.0)"},
}


def clusters(parts, gap):
    """Части сцены -> предметы: части ближе gap (по коробкам в плане) — один предмет."""
    n = len(parts)
    lo = np.array([p["v"].min(0) for p in parts])
    hi = np.array([p["v"].max(0) for p in parts])
    par = list(range(n))

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for i in range(n):
        for j in range(i + 1, n):
            if all(lo[i][k] - gap <= hi[j][k] and lo[j][k] - gap <= hi[i][k] for k in (0, 2)):
                par[find(i)] = find(j)
    out = {}
    for i in range(n):
        out.setdefault(find(i), []).append(parts[i])
    return sorted(out.values(), key=lambda ps: (round(min(p["v"][:, 0].min() for p in ps), 2), round(min(p["v"][:, 2].min() for p in ps), 2)))


def bake_pack(pname, cfg, src, preview):
    path = os.path.join(src, cfg["src"], "model.glb")
    if not os.path.exists(path):
        print("  нет набора:", path)
        return 0
    parts = U.load_parts(path)
    allv = np.vstack([p["v"] for p in parts])
    ext = allv.max(0) - allv.min(0)
    groups = clusters(parts, 0.01 * float(max(ext[0], ext[2])))
    hmax = max(max(p["v"][:, 1].max() for p in g) - min(p["v"][:, 1].min() for p in g) for g in groups)
    k = cfg["size"] / max(hmax, 1e-6)
    tiles = []
    for gi, g in enumerate(groups[:16]):
        S = cfg["atlas"]
        atlas = Image.new("RGB", (S, S), (70, 70, 62))
        V, UV = U.atlas_place(g, atlas, (0, 0, S, S), 1, 1)
        V = V * k
        V[:, 0] -= (V[:, 0].min() + V[:, 0].max()) / 2
        V[:, 2] -= (V[:, 2].min() + V[:, 2].max()) / 2
        V[:, 1] -= V[:, 1].min()
        V, UV, F = U.weld(V, UV, tol=1e-4)
        if len(F) > cfg["tris"] * 1.2:
            V, UV, F = U.simplify(V, UV, F, cfg["tris"])
        N = U.vertex_normals(V, F)
        name = "decor_%s_%d" % (pname, gi)
        head = json.dumps({"nv": len(V), "ni": int(F.size), "poses": ["rest"], "height": float(V[:, 1].max()),
                           "size": [float(x) for x in (V.max(0) - V.min(0))]}).encode()
        with open(os.path.join(U.OUT, name + ".bin"), "wb") as fh:
            fh.write(b"SUV1" + struct.pack("<I", len(head)) + head)
            fh.write(V.astype("<f4").tobytes())
            fh.write(UV.astype("<f4").tobytes())
            fh.write(F.astype("<u2").tobytes())
            fh.write(np.concatenate([V[None], N[None]]).astype("<f2").tobytes())
        atlas.save(os.path.join(U.OUT, name + ".png"), optimize=True)
        print("  %-18s вершин %4d, треугольников %4d, размер %s м" % (name, len(V), len(F), np.round(V.max(0) - V.min(0), 2).tolist()))
        if preview:
            at = np.asarray(atlas, np.float64)
            C = at[np.clip((UV[:, 1] * S).astype(int), 0, S - 1), np.clip((UV[:, 0] * S).astype(int), 0, S - 1)]
            sc = 110.0 / max(float((V.max(0) - V.min(0)).max()), 1e-6)
            tiles.append(U.raster(V, F, C, (0, 1, 2), 120, 120, (-60.0 / sc, -5.0 / sc), sc))
    if preview and tiles:
        Image.fromarray(np.hstack(tiles)).save(os.path.join(preview, "pack_" + pname + ".png"))
    return len(groups[:16])


def bake(name, cfg, src, preview):
    path = os.path.join(src, cfg["src"], "model.glb")
    if not os.path.exists(path):
        print("  нет модели:", path)
        return False
    parts = U.load_parts(path)
    if "pick" in cfg:
        parts = [p for p in parts if cfg["pick"]((p["v"].min(0) + p["v"].max(0)) / 2, p["v"].max(0) - p["v"].min(0))]
    if "paint" in cfg:
        for p in parts:
            p["img"] = None
            p["col"] = cfg["paint"]
    if "color" in cfg:
        for p in parts:
            if p["img"] is None:
                p["col"] = cfg["color"]
    S = cfg.get("atlas", 256)
    atlas = Image.new("RGB", (S, S), (70, 70, 62))
    V, UV = U.atlas_place(parts, atlas, (0, 0, S, S), 1, 1)
    f = U.unit(np.asarray(cfg["fwd"], np.float64))
    u = U.unit(np.asarray(cfg["up"], np.float64))
    r = np.cross(u, f)
    L = np.stack([V @ r, V @ u, V @ f], axis=1)
    L *= cfg["len"] / (L[:, 2].max() - L[:, 2].min())
    L[:, 0] -= (L[:, 0].min() + L[:, 0].max()) / 2
    L[:, 2] -= (L[:, 2].min() + L[:, 2].max()) / 2
    L[:, 1] -= (L[:, 1].min() + L[:, 1].max()) / 2 if cfg.get("center") else L[:, 1].min()
    V, UV, F = U.weld(L, UV, tol=2e-4)
    V, UV, F = U.simplify(V, UV, F, cfg["tris"])
    N = U.vertex_normals(V, F)
    nv = len(V)
    vat = np.concatenate([V[None], N[None]]).astype(np.float16)
    head = json.dumps({"nv": nv, "ni": int(F.size), "poses": ["rest"], "height": float(V[:, 1].max()),
                       "size": [float(x) for x in (V.max(0) - V.min(0))]}).encode()
    with open(os.path.join(U.OUT, name + ".bin"), "wb") as fh:
        fh.write(b"SUV1" + struct.pack("<I", len(head)) + head)
        fh.write(V.astype("<f4").tobytes())
        fh.write(UV.astype("<f4").tobytes())
        fh.write(F.astype("<u2").tobytes())
        fh.write(vat.astype("<f2").tobytes())
    atlas.save(os.path.join(U.OUT, name + ".png"), optimize=True)
    print("  %-12s вершин %4d, треугольников %4d, размер %s м" % (name, nv, len(F), np.round(V.max(0) - V.min(0), 2).tolist()))
    if preview:
        at = np.asarray(atlas, np.float64)
        C = at[np.clip((UV[:, 1] * S).astype(int), 0, S - 1), np.clip((UV[:, 0] * S).astype(int), 0, S - 1)]
        k = 280.0 / max(cfg["len"], float((V[:, 0].max() - V[:, 0].min())))
        lo = -140.0 / k
        a = U.raster(V, F, C, (2, 1, 0), 300, 200, (lo, -0.3 if not cfg.get("center") else -100.0 / k), k)
        b = U.raster(V, F, C, (0, 1, 2), 300, 200, (lo, -0.3 if not cfg.get("center") else -100.0 / k), k)
        c = U.raster(V, F, C, (0, 2, 1), 300, 300, (lo, lo), k)[50:250]
        Image.fromarray(np.hstack([a, b, c])).save(os.path.join(preview, name + ".png"))
    return True


def main():
    src = sys.argv[1]
    args = sys.argv[2:]
    preview = None
    if "--preview" in args:
        i = args.index("--preview")
        preview = args[i + 1]
        args = args[:i] + args[i + 2:]
        os.makedirs(preview, exist_ok=True)
    done = []
    for name, cfg in PROPS.items():
        if args and name not in args:
            continue
        if bake(name, cfg, src, preview):
            done.append(cfg["credit"])
    for pname, cfg in PACKS.items():
        if args and pname not in args:
            continue
        if bake_pack(pname, cfg, src, preview):
            done.append(cfg["credit"])
    if not args:
        with open(os.path.join(U.OUT, "CREDITS_props.txt"), "w", encoding="utf-8") as f:
            f.write("Модели пушек, самолётов и мелочей окружения (Sketchfab, CC BY 4.0), упрощены и собраны в атласы (tools/import_props.py).\n\n"
                    + "\n".join(dict.fromkeys(done)) + "\n")


if __name__ == "__main__":
    main()
