#!/usr/bin/env python3
"""Детальные текстуры окружения для «Стального штурма».

Рисует бесшовные текстуры 512 × 512 (кирпич, штукатурка, черепица, бетон, доски, камень,
сланец, ржавый металл, гарь, мешковина, битый кирпич, листва, грунт, фасады, ящики)
и карты нормалей к ним, а также детальные текстуры грунта для шейдера земли.
Всё процедурное: шум строится через БПФ, поэтому любая текстура повторяется без шва.

    python3 tools/make_textures.py [папка]   # по умолчанию godot/assets/textures
"""
import os
import sys

import numpy as np
from PIL import Image

S = 512
NS = 256  # карты нормалей
KY = np.fft.fftfreq(S)[:, None]
KX = np.fft.fftfreq(S)[None, :]
YY, XX = np.mgrid[0:S, 0:S]


# ---------- шум и помощники ----------

def blur(sx, sy, seed):
    """Белый шум, размытый гауссом (sx, sy — радиус пятен в пикселях); бесшовный, σ = 1."""
    w = np.random.default_rng(seed).standard_normal((S, S))
    g = np.exp(-2 * np.pi ** 2 * (sx ** 2 * KX ** 2 + sy ** 2 * KY ** 2))
    n = np.real(np.fft.ifft2(np.fft.fft2(w) * g))
    return n / (n.std() + 1e-9)


def fbm(sigma, seed, octaves=4, pers=0.5, stretch=(1.0, 1.0)):
    """Фрактальный шум 0..1 (среднее 0.5) из октав размытого шума."""
    t = np.zeros((S, S))
    a = 1.0
    for o in range(octaves):
        s = sigma / 2 ** o
        t += a * blur(s * stretch[0], s * stretch[1], seed + o * 101)
        a *= pers
    t = (t - t.mean()) / (t.std() + 1e-9)
    return np.clip(0.5 + t / 6.0, 0.0, 1.0)


def ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def col(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def mix(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return a * (1 - t) + b * t


def shade(c, k):
    """Осветлить (k > 0) или затемнить (k < 0) цвет по маске."""
    k = k[..., None] if np.ndim(k) == 2 else k
    return np.where(k > 0, c + (1 - c) * k, c * (1 + k))


def fill(c):
    return np.broadcast_to(col(c), (S, S, 3)).copy()


def walk_lines(n, steps, seed, width=1.0, turn=0.5):
    """Маска трещин: случайные блуждания (бесшовно, по модулю размера)."""
    rng = np.random.default_rng(seed)
    m = np.zeros((S, S))
    for _ in range(n):
        p = rng.random(2) * S
        a = rng.random() * 2 * np.pi
        for i in range(steps):
            a += rng.uniform(-turn, turn)
            p += np.array([np.cos(a), np.sin(a)])
            x, y = int(p[0]) % S, int(p[1]) % S
            m[y, x] = 1.0
            if width > 1.0 and rng.random() < width - 1.0:
                m[(y + 1) % S, x] = 1.0
    return m


def soften(m, s):
    return np.clip(np.real(np.fft.ifft2(np.fft.fft2(m) * np.exp(-2 * np.pi ** 2 * s ** 2 * (KX ** 2 + KY ** 2)))), 0, None)


def cells(n, seed, jitter=1.0, grid=None):
    """Ячейки Вороного (бесшовные): номер ближайшей точки, расстояние до неё и до границы ячейки."""
    rng = np.random.default_rng(seed)
    if grid:
        gx, gy = grid
        pts = []
        for j in range(gy):
            for i in range(gx):
                pts.append(((i + 0.5 + (rng.random() - 0.5) * jitter) * S / gx, (j + 0.5 + (rng.random() - 0.5) * jitter) * S / gy))
        pts = np.array(pts)
    else:
        pts = rng.random((n, 2)) * S
    d1 = np.full((S, S), 1e9)
    d2 = np.full((S, S), 1e9)
    idx = np.zeros((S, S), dtype=np.int32)
    for k, (px, py) in enumerate(pts):
        dx = np.abs(XX - px)
        dx = np.minimum(dx, S - dx)
        dy = np.abs(YY - py)
        dy = np.minimum(dy, S - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        idx = np.where(closer, k, idx)
        d1 = np.where(closer, d, d1)
    return idx, d1, d2 - d1


def normal_map(h, strength):
    """Нормали из высоты: x — вдоль строки, y — вниз по строкам (так их ждёт шейдер)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.dstack([-dx * strength, -dy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def save(out, name, c, h=None, strength=4.0, gray=False, flip=False):
    """flip — у текстур с верхом и низом: строки картинки идут снизу вверх по миру."""
    c = np.clip(c, 0, 1)
    if flip:
        c = c[::-1]
        h = h[::-1] if h is not None else None
    if gray:
        Image.fromarray((c * 255).astype(np.uint8), "L").save(os.path.join(out, name + ".png"), optimize=True)
    else:
        Image.fromarray((c * 255).astype(np.uint8), "RGB").save(os.path.join(out, name + ".png"), optimize=True)
    if h is not None:
        n = normal_map(h, strength)
        img = Image.fromarray((np.clip(n, 0, 1) * 255).astype(np.uint8), "RGB").resize((NS, NS), Image.BOX)
        img.save(os.path.join(out, name + "_n.png"), optimize=True)
    print("  ", name)


def per_cell(ids, seed, lo=0.0, hi=1.0):
    vals = np.random.default_rng(seed).uniform(lo, hi, ids.max() + 1)
    return vals[ids]


def grid_ids(bw, bh, offset=0.5):
    """Кладка рядами: номер блока, координаты внутри него и расстояние до края."""
    row = YY // bh
    off = ((row % 2) * int(bw * offset))
    xs = (XX + off) % S
    colm = xs // bw
    lx = xs % bw
    ly = YY % bh
    e = np.minimum(np.minimum(lx, bw - 1 - lx), np.minimum(ly, bh - 1 - ly)).astype(float)
    return row * (S // bw + 1) + colm, lx, ly, e


# ---------- материалы построек ----------

def brick():
    ids, lx, ly, e = grid_ids(64, 32)
    n_big = fbm(90, 1)
    n_fine = fbm(3, 2, 3)
    chip = fbm(6, 3, 3)
    tone = per_cell(ids, 4, -0.16, 0.12)
    burnt = per_cell(ids, 5) > 0.88
    mortar = (e + (chip - 0.5) * 3.0) < 2.6
    c = fill("8c5238")
    c = mix(c, col("6e3a2a"), burnt * 0.8)
    c = shade(c, tone + (n_fine - 0.5) * 0.35)
    # выщербленные края и скол углов
    edge = ss(3.5, 0.5, e) * ss(0.55, 0.75, chip)
    c = shade(c, -edge * 0.35)
    m = mix(col("a59d8c"), col("8a8274"), n_fine)
    c = np.where(mortar[..., None], m, c)
    # высолы и копоть
    c = mix(c, col("cfc8b8"), ss(0.72, 0.86, n_big) * 0.2)
    c = shade(c, -ss(0.5, 0.85, fbm(40, 6)) * 0.18)
    h = np.where(mortar, 0.0, 3.0 * ss(0.0, 3.0, e) + (n_fine - 0.5) * 0.8 - edge * 1.5)
    return c, h


def plaster(brick_c, brick_h):
    n = fbm(70, 11)
    n2 = fbm(18, 12, 3)
    fine = fbm(2.5, 13, 2)
    c = fill("d4cab0")
    c = shade(c, (fine - 0.5) * 0.12 + (n2 - 0.5) * 0.12)
    # сырость: желтоватые разводы снизу вверх
    damp = ss(0.55, 0.8, fbm(60, 14, stretch=(1.0, 2.5)))
    c = mix(c, col("a99a72"), damp * 0.4)
    # отвалившаяся штукатурка — под ней кирпич
    hole = n > 0.74
    lip = (n > 0.715) & ~hole
    c = np.where(hole[..., None], brick_c, c)
    c = np.where(lip[..., None], shade(c, np.full((S, S), -0.25)), c)
    cracks = soften(walk_lines(10, 170, 15, 1.2, 0.22), 0.5)
    c = shade(c, -np.clip(cracks * 1.2, 0, 0.45))
    h = np.where(hole, brick_h - 3.0, 2.0 + (fine - 0.5) * 0.6 + (n2 - 0.5) * 0.8) - cracks * 2.0
    return c, h


def roof():
    bw, bh = 32, 32
    row = YY // bh
    off = (row % 2) * (bw // 2)
    xs = (XX + off) % S
    ids = row * (S // bw) + xs // bw
    tx = (xs % bw) / bw
    ty = (YY % bh) / bh
    n = fbm(80, 21)
    fine = fbm(3, 22, 3)
    tone = per_cell(ids, 23, -0.15, 0.12)
    # желобчатая черепица: дуга поперёк, наклон вниз по ряду, тень под нахлёстом
    arc = np.sin(tx * np.pi)
    h = arc * 3.0 + ty * 4.0 + (fine - 0.5) * 0.6
    c = fill("8a4a32")
    c = shade(c, tone + (arc - 0.6) * 0.25 + (fine - 0.5) * 0.18)
    c = shade(c, -ss(0.75, 1.0, ty) * 0.45)
    # мох и грязь пятнами, местами битая черепица
    c = mix(c, col("5d5a3a"), ss(0.62, 0.8, n) * 0.5)
    broken = per_cell(ids, 24) > 0.95
    c = np.where(broken[..., None], c * 0.45, c)
    h = np.where(broken, h - 3.0, h)
    return c, h


def concrete():
    n = fbm(80, 31)
    n2 = fbm(12, 32, 3)
    fine = fbm(2, 33, 2)
    c = fill("8e8b82")
    c = shade(c, (n - 0.5) * 0.3 + (n2 - 0.5) * 0.15 + (fine - 0.5) * 0.15)
    # следы опалубки: доски по 64 px и отверстия от стяжек
    board = (YY % 64)
    seam = board < 2
    c = shade(c, np.where(seam, -0.25, (per_cell(YY // 64, 34, -0.06, 0.06))))
    holes = ((np.abs((XX % 128) - 64) < 3) & (np.abs((YY % 64) - 32) < 3))
    c = np.where(holes[..., None], c * 0.4, c)
    # потёки сверху вниз, раковины, трещины
    streak = ss(0.55, 0.85, fbm(30, 35, stretch=(0.15, 3.0)))
    c = shade(c, -streak * 0.25)
    pits = fine > 0.86
    c = np.where(pits[..., None], c * 0.7, c)
    cracks = soften(walk_lines(7, 200, 36, 1.3, 0.2), 0.5)
    c = shade(c, -np.clip(cracks * 1.3, 0, 0.55))
    h = (n2 - 0.5) * 1.2 + (fine - 0.5) * 0.5 - seam * 1.0 - holes * 2.0 - pits * 0.8 - cracks * 2.5
    return c, h


def wood():
    pw = 64
    plank = XX // pw
    lx = XX % pw
    tone = per_cell(plank, 41, -0.12, 0.1)
    grain_n = fbm(40, 42, 3, stretch=(0.08, 1.0))
    rings = np.sin((XX * 0.35 + grain_n * 30.0 + plank * 5.0)) * 0.5 + 0.5
    fine = fbm(2, 43, 2, stretch=(0.3, 1.0))
    c = fill("6e5238")
    c = shade(c, tone - rings * 0.18 + (fine - 0.5) * 0.15)
    # сучки
    rng = np.random.default_rng(44)
    knot = np.zeros((S, S))
    for _ in range(9):
        kx, ky = rng.random(2) * S
        dx = np.minimum(np.abs(XX - kx), S - np.abs(XX - kx))
        dy = np.minimum(np.abs(YY - ky), S - np.abs(YY - ky))
        knot = np.maximum(knot, ss(1.0, 0.0, np.sqrt((dx / 5.0) ** 2 + (dy / 9.0) ** 2)))
    c = shade(c, -knot * 0.45)
    gap = (lx < 3) | (lx > pw - 2)
    c = np.where(gap[..., None], col("1f1810"), c)
    # гвозди у торцов досок и выцветание
    nails = (np.abs(lx - pw / 2) < 2) & (np.abs((YY % 256) - 20) < 2)
    c = np.where(nails[..., None], col("3c3a36"), c)
    c = mix(c, col("8a8174"), ss(0.6, 0.85, fbm(70, 45)) * 0.35)
    h = np.where(gap, -3.0, (fine - 0.5) * 1.0 - rings * 0.6 - knot * 1.0)
    return c, h


def sandstone():
    n = fbm(60, 51)
    warp = fbm(50, 52)
    strata = np.sin(YY * 2 * np.pi * 7 / S + warp * 9.0) * 0.5 + 0.5
    fine = fbm(1.5, 53, 2)
    c = fill("b38f64")
    c = shade(c, -strata * 0.18 + (n - 0.5) * 0.2 + (fine - 0.5) * 0.22)
    holes = fbm(5, 54, 3) > 0.8
    c = np.where(holes[..., None], c * 0.7, c)
    h = strata * 1.5 + (fine - 0.5) * 0.8 - holes * 2.0 + (n - 0.5) * 2.0
    return c, h


def granite():
    n = fbm(70, 61)
    fine = fbm(1.2, 62, 2)
    spk = fbm(1.6, 63, 1)
    c = fill("878780")
    c = shade(c, (n - 0.5) * 0.3 + (fine - 0.5) * 0.3)
    c = np.where((spk > 0.78)[..., None], col("2b2a28"), c)
    c = np.where((spk < 0.2)[..., None], col("c9c2b8"), c)
    c = mix(c, col("a08070"), ss(0.65, 0.8, fbm(4, 64, 2)) * 0.4)
    lichen = ss(0.7, 0.82, fbm(20, 65, 3))
    c = mix(c, col("8f9566"), lichen * 0.45)
    h = (n - 0.5) * 3.0 + (fine - 0.5) * 0.8
    return c, h


def rust():
    n = fbm(40, 71)
    n2 = fbm(8, 72, 3)
    fine = fbm(1.5, 73, 2)
    c = fill("4e4038")
    r = ss(0.4, 0.7, n * 0.7 + n2 * 0.3)
    c = mix(c, col("7c4626"), r)
    c = mix(c, col("a0602e"), ss(0.72, 0.85, n2) * 0.6)
    # облезлая краска пятнами и потёки
    paint = (n < 0.3) & (n2 < 0.55)
    c = np.where(paint[..., None], shade(fill("4a4d3c"), (fine - 0.5) * 0.2), c)
    streak = ss(0.55, 0.85, fbm(20, 74, stretch=(0.15, 3.0)))
    c = shade(c, -streak * 0.3 + (fine - 0.5) * 0.3)
    pits = fine > 0.84
    h = np.where(paint, 1.0, (n2 - 0.5) * 1.2) + (fine - 0.5) * 0.6 - pits * 1.0
    return c, h


def charred():
    ids, d1, edge = cells(140, 81)
    fine = fbm(1.5, 82, 2)
    n = fbm(40, 83)
    c = fill("1d1b19")
    c = shade(c, per_cell(ids, 84, 0.0, 0.25) + (fine - 0.5) * 0.3)
    crack = edge < 1.6
    c = np.where(crack[..., None], col("0a0908"), c)
    c = mix(c, col("4d4740"), ss(0.65, 0.85, n) * 0.4)  # зола
    h = np.where(crack, -2.0, ss(0.0, 8.0, edge) * 2.0 + (fine - 0.5) * 0.5)
    return c, h


def sandbag():
    fine = fbm(1.2, 91, 2)
    n = fbm(50, 92)
    weave = (np.sin(XX * np.pi / 2.0) * np.sin(YY * np.pi / 2.0)) * 0.5 + 0.5
    crease = fbm(14, 93, 3, stretch=(2.5, 0.4))
    c = fill("a28c64")
    c = shade(c, (weave - 0.5) * 0.18 + (n - 0.5) * 0.3 + (crease - 0.5) * 0.25 + (fine - 0.5) * 0.12)
    dirt = ss(0.6, 0.85, fbm(25, 94))
    c = mix(c, col("6a5a42"), dirt * 0.45)
    h = weave * 0.6 + (crease - 0.5) * 3.0 + (fine - 0.5) * 0.3
    return c, h


def rubble():
    ids, d1, edge = cells(90, 101)
    kind = per_cell(ids, 102)
    fine = fbm(1.5, 103, 2)
    c = np.where((kind < 0.45)[..., None], fill("8a5240"), np.where((kind < 0.8)[..., None], fill("8a857a"), fill("6a645c")))
    c = shade(c, per_cell(ids, 104, -0.15, 0.12) + (fine - 0.5) * 0.3)
    gap = edge < 2.5
    c = np.where(gap[..., None], col("3d3832"), c)
    dust = ss(0.55, 0.8, fbm(30, 105))
    c = mix(c, col("a49c8c"), dust * 0.35)
    h = np.where(gap, 0.0, ss(0.0, 10.0, edge) * 4.0 * per_cell(ids, 106, 0.5, 1.0)) + (fine - 0.5) * 0.5
    return c, h


def stone():
    """Известняковая кладка неровными рядами (Нормандия, Арденны)."""
    rng = np.random.default_rng(111)
    ids = np.zeros((S, S), dtype=np.int32)
    e = np.zeros((S, S))
    y0 = 0
    k = 0
    while y0 < S:
        rh = int(rng.integers(40, 62))
        if y0 + rh > S - 24:
            rh = S - y0
        # ширины камней ряда в сумме дают ровно S — ряд замыкается без шва
        widths = []
        while sum(widths) < S:
            widths.append(int(rng.integers(52, 118)))
        widths[-1] -= sum(widths) - S
        if widths[-1] < 30:
            widths[-2] += widths.pop()
        x0 = -int(rng.integers(0, 60))
        for bw in widths:
            ys = slice(y0, y0 + rh)
            for xx in range(x0, x0 + bw):
                xi = xx % S
                lx = xx - x0
                ids[ys, xi] = k
                ly = np.arange(rh)
                e[ys, xi] = np.minimum(np.minimum(lx, bw - 1 - lx), np.minimum(ly, rh - 1 - ly))
            x0 += bw
            k += 1
        y0 += rh
    chip = fbm(7, 112, 3)
    fine = fbm(2, 113, 2)
    n = fbm(60, 114)
    mortar = (e + (chip - 0.5) * 5.0) < 3.5
    c = mix(fill("cdc2a6"), fill("b4a483"), per_cell(ids, 115))
    c = shade(c, per_cell(ids, 116, -0.12, 0.06) + (fine - 0.5) * 0.22 + (chip - 0.5) * 0.12)
    c = np.where(mortar[..., None], shade(fill("8d8576"), (fine - 0.5) * 0.3), c)
    c = mix(c, col("7d8160"), ss(0.68, 0.8, fbm(16, 117, 3)) * 0.4)  # лишайник
    c = shade(c, -ss(0.5, 0.85, n) * 0.25)
    h = np.where(mortar, 0.0, 4.0 * ss(0.0, 6.0, e) + (chip - 0.5) * 1.5 + (fine - 0.5) * 0.6)
    return c, h


def slate():
    bw, bh = 32, 32
    ids, lx, ly, e = grid_ids(bw, bh)
    fine = fbm(1.5, 121, 2)
    n = fbm(70, 122)
    ty = ly / bh
    c = fill("525a62")
    c = shade(c, per_cell(ids, 123, -0.12, 0.1) + 0.1 - ty * 0.2 + (fine - 0.5) * 0.15)
    c = shade(c, -ss(0.85, 1.0, ty) * 0.45)
    gap = lx < 1
    c = np.where(gap[..., None], col("23272a"), c)
    c = mix(c, col("6b6f55"), ss(0.65, 0.8, n) * 0.35)
    h = ty * 2.5 + (fine - 0.5) * 0.4 - gap * 1.0
    return c, h


def leaves():
    ids, d1, edge = cells(900, 131)
    fine = fbm(1.5, 132, 2)
    n = fbm(40, 133)
    lit = per_cell(ids, 134, 0.0, 1.0)
    c = mix(fill("34402a"), fill("6a7448"), lit * 0.8)
    c = shade(c, -(1.0 - ss(0.0, 6.0, edge)) * 0.45 + (fine - 0.5) * 0.15 + (n - 0.5) * 0.35)
    c = mix(c, col("7c7040"), ss(0.7, 0.85, fbm(30, 135)) * 0.3)
    h = ss(0.0, 6.0, edge) * 3.0 * (0.5 + lit) + (n - 0.5) * 4.0
    return c, h


def earth():
    n = fbm(50, 141)
    fine = fbm(1.5, 142, 2)
    ids, d1, edge = cells(260, 143)
    peb = (per_cell(ids, 144) > 0.75) & (d1 < 5.0 + per_cell(ids, 145) * 4.0)
    c = fill("6a5840")
    c = shade(c, (n - 0.5) * 0.35 + (fine - 0.5) * 0.3)
    c = np.where(peb[..., None], shade(fill("8d8572"), per_cell(ids, 146, -0.15, 0.15) - d1 * 0.02), c)
    roots = soften(walk_lines(10, 120, 147, 1.3, 0.35), 0.5)
    c = mix(c, col("3e3022"), np.clip(roots * 1.4, 0, 0.8))
    h = (n - 0.5) * 3.0 + (fine - 0.5) * 0.8 + np.where(peb, 2.5 - d1 * 0.3, 0.0) + roots * 1.0
    return c, h


def facade(brick_c):
    """Берлинский доходный дом: два этажа на текстуру, по четыре окна с наличниками."""
    n = fbm(60, 151)
    fine = fbm(2.0, 152, 2)
    c = fill("9a968a")
    c = shade(c, (n - 0.5) * 0.28 + (fine - 0.5) * 0.12)
    h = (fine - 0.5) * 0.5
    for fy in (0, 256):
        # карниз: свет сверху, тень снизу
        c[fy + 232:fy + 244] = shade(c[fy + 232:fy + 244], np.full((12, S), -0.1))
        c[fy + 228:fy + 232] = shade(c[fy + 228:fy + 232], np.full((4, S), 0.25))
        c[fy + 244:fy + 248] = shade(c[fy + 244:fy + 248], np.full((4, S), -0.35))
        h[fy + 228:fy + 248] += 3.0
        for wx in (40, 168, 296, 424):
            x0, x1 = wx - 10, wx + 58
            c[fy + 20:fy + 32, x0:x1] = col("c1b7a2")  # сандрик над окном
            h[fy + 20:fy + 32, x0:x1] += 2.5
            c[fy + 32:fy + 196, wx - 6:wx + 54] = col("837968")  # наличник
            h[fy + 32:fy + 196, wx - 6:wx + 54] += 1.5
            c[fy + 36:fy + 192, wx:wx + 48] = col("141310")  # проём
            h[fy + 36:fy + 192, wx:wx + 48] = -4.0
            c[fy + 36:fy + 192, wx + 22:wx + 26] = col("3d352b")  # импост
            c[fy + 100:fy + 103, wx:wx + 48] = col("3d352b")
            # уцелевшее стекло отсвечивает
            c[fy + 40:fy + 98, wx + 2:wx + 21] = mix(c[fy + 40:fy + 98, wx + 2:wx + 21], col("4f5a63"), 0.5)
            c[fy + 192:fy + 200, wx - 10:wx + 58] = col("beb49f")  # подоконник
            h[fy + 192:fy + 200, wx - 10:wx + 58] += 3.0
    # отбитая штукатурка с кирпичом, выбоины от пуль, копоть над окнами
    hole = (fbm(40, 153) > 0.76) & (h < 1.0) & (h > -1.0)
    c = np.where(hole[..., None], brick_c, c)
    h = np.where(hole, -1.5, h)
    rng = np.random.default_rng(154)
    for _ in range(260):
        px, py = rng.integers(0, S, 2)
        r = rng.uniform(1.5, 4.0)
        dx = np.minimum(np.abs(XX - px), S - np.abs(XX - px))
        dy = np.minimum(np.abs(YY - py), S - np.abs(YY - py))
        d = np.sqrt(dx * dx + dy * dy)
        sel = d < r * 1.8
        if not sel.any():
            continue
        rim = (d < r * 1.8) & (d >= r)
        core = d < r
        c[core] = c[core] * 0.45
        c[rim] = c[rim] * 0.8 + 0.2 * col("c8c0ae")
        h[core] -= 1.5
    for wx, fy in ((168, 256), (424, 256), (40, 0)):
        for i in range(90):
            k = (1.0 - i / 90.0) * 0.6
            ys = (fy + 35 - i) % S
            c[ys, wx - 10:wx + 58] *= 1.0 - k * (0.6 + 0.4 * fine[ys, wx - 10:wx + 58, None])
    return c, h


def windows(plaster_c, plaster_h):
    """Штукатурка с окнами (дома Сталинграда): 2 × 2 окна на текстуру."""
    c = plaster_c.copy()
    h = plaster_h.copy()
    fine = fbm(2.0, 161, 2)
    rng = np.random.default_rng(162)
    for (px, py) in ((72, 96), (296, 96), (72, 352), (296, 352)):
        c[py - 8:py + 136, px - 8:px + 144] = shade(c[py - 8:py + 136, px - 8:px + 144], np.full((144, 152), -0.2))
        h[py - 8:py + 136, px - 8:px + 144] += 1.0
        c[py:py + 128, px:px + 136] = col("15140f")
        h[py:py + 128, px:px + 136] = -4.0
        c[py:py + 128, px + 64:px + 72] = col("3a3329")
        c[py + 60:py + 66, px:px + 136] = col("3a3329")
        if rng.random() < 0.5:
            # заколочено досками
            for k in range(3):
                y = py + 20 + k * 38
                c[y:y + 16, px - 4:px + 140] = shade(fill("6e5238")[y:y + 16, px - 4:px + 140], (fine[y:y + 16, px - 4:px + 140] - 0.5) * 0.4)
                h[y:y + 16, px - 4:px + 140] = 1.5
        c[py + 128:py + 140, px - 12:px + 148] = col("a49c8c")
        h[py + 128:py + 140, px - 12:px + 148] += 2.5
    for (px, py) in ((72, 96), (296, 352)):
        for i in range(80):
            k = (1.0 - i / 80.0) * 0.6
            y = (py - 1 - i) % S
            c[y, px:px + 136] *= 1.0 - k * (0.6 + 0.4 * fine[y, px:px + 136, None])
    return c, h


def crate():
    """Снарядный ящик: доски поперёк, обвязка по краю, верёвочная ручка, трафаретная маркировка."""
    c = fill("6a5a3c")
    fine = fbm(2, 171, 2, stretch=(1.0, 0.1))
    grain = fbm(40, 172, 3, stretch=(1.0, 0.08))
    board = YY // 128
    tone = per_cell(board, 173, -0.1, 0.08)
    c = shade(c, tone - grain * 0.2 + (fine - 0.5) * 0.2)
    gap = (YY % 128) < 3
    frame = (XX < 40) | (XX > S - 41) | (YY < 40) | (YY > S - 41)
    c = np.where(frame[..., None], shade(fill("5d4e34"), (fine - 0.5) * 0.25 - grain * 0.1), c)
    c = np.where(gap[..., None] & ~frame[..., None], col("1d170f"), c)
    edge = ((np.abs(XX - 40) < 2) | (np.abs(XX - (S - 41)) < 2) | (np.abs(YY - 40) < 2) | (np.abs(YY - (S - 41)) < 2))
    c = np.where(edge[..., None], col("2a2216"), c)
    # гвозди в обвязке
    nails = (((XX % 128) - 20) ** 2 + ((YY - 20) % S) ** 2 < 9) | (((XX % 128) - 20) ** 2 + ((YY - (S - 21)) % S) ** 2 < 9)
    c = np.where(nails[..., None], col("2f2e2c"), c)
    # маркировка: полосы и стрелка «верх»
    paint = np.zeros((S, S), bool)
    paint |= (np.abs(YY - 200) < 12) & (np.abs(XX - 256) < 150)
    paint |= (np.abs(YY - 312) < 12) & (np.abs(XX - 256) < 150)
    ax, ay = XX - 256, YY - 256
    paint |= (np.abs(ax) < 10) & (ay > -30) & (ay < 40)
    paint |= (ay < -20) & (ay > -60) & (np.abs(ax) < (ay + 62) * 0.8)
    wear = fbm(4, 174, 2) > 0.62
    c = np.where((paint & ~wear)[..., None], shade(fill("d8cfa8"), (fine - 0.5) * 0.15), c)
    h = np.where(frame, 2.0, 0.0) + (fine - 0.5) * 0.6 - grain * 0.5 - gap * 2.0 - edge * 1.0
    return c, h


# ---------- грунт для шейдера земли (серый) ----------

def ground_grass():
    n = fbm(30, 201)
    fine = fbm(1.2, 202, 2)
    blades = fbm(0.8, 203, 1, stretch=(0.4, 2.5))
    clump = fbm(8, 204, 3)
    v = 0.35 + (n - 0.5) * 0.4 + (clump - 0.5) * 0.35 + np.clip(blades - 0.55, 0, 1) * 1.6 + (fine - 0.5) * 0.15
    h = clump * 3.0 + np.clip(blades - 0.5, 0, 1) * 4.0 + (fine - 0.5) * 0.5
    return v, h


def ground_sand():
    warp = fbm(60, 211)
    fine = fbm(0.8, 212, 1)
    ripple = np.sin((YY + warp * 70.0) * 2 * np.pi * 24 / S) * 0.5 + 0.5
    ripple = ripple ** 1.6
    peb = fbm(2.0, 213, 2) > 0.8
    v = 0.5 + (ripple - 0.5) * 0.35 + (fine - 0.5) * 0.25 + (warp - 0.5) * 0.2 - peb * 0.25
    h = ripple * 3.0 + (fine - 0.5) * 0.4 + peb * 1.0
    return v, h


def ground_snow():
    n = fbm(40, 221)
    drift = fbm(12, 222, 3, stretch=(2.0, 0.6))
    fine = fbm(0.8, 223, 1)
    sparkle = fine > 0.9
    v = 0.55 + (n - 0.5) * 0.3 + (drift - 0.5) * 0.25 + (fine - 0.5) * 0.08 + sparkle * 0.15
    h = n * 4.0 + drift * 3.0 + (fine - 0.5) * 0.3
    return v, h


def ground_urban():
    """Брусчатка: скруглённые камни рядами со сдвигом, песок и пыль в швах."""
    bw, bh = 32, 32
    ids, lx, ly, e = grid_ids(bw, bh)
    fine = fbm(1.2, 231, 2)
    n = fbm(40, 232)
    cx = (lx - bw / 2) / (bw / 2)
    cy = (ly - bh / 2) / (bh / 2)
    r = np.sqrt(cx ** 4 + cy ** 4) ** 0.5
    dome = np.clip(1.0 - r, 0, 1)
    stone = r < 0.88
    v = np.where(stone, 0.6 + per_cell(ids, 233, -0.12, 0.12) + dome * 0.15, 0.32) + (fine - 0.5) * 0.15 + (n - 0.5) * 0.25
    h = np.where(stone, dome * 4.0 + 1.0, 0.0) + (fine - 0.5) * 0.4
    return v, h


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "textures")
    os.makedirs(out, exist_ok=True)
    print("текстуры ->", out)
    bc, bh = brick()
    save(out, "brick", bc, bh, 1.5)
    pc, ph = plaster(bc, bh)
    save(out, "plaster", pc, ph, 1.5, flip=True)
    for name, fn, k in (("roof", roof, 1.5), ("concrete", concrete, 1.2), ("wood", wood, 1.2), ("sandstone", sandstone, 1.2),
                        ("granite", granite, 1.0), ("rust", rust, 1.2), ("charred", charred, 1.2), ("sandbag", sandbag, 1.0),
                        ("rubble", rubble, 1.0), ("stone", stone, 1.4), ("slate", slate, 1.5), ("leaves", leaves, 1.0),
                        ("earth", earth, 1.0), ("crate", crate, 1.2)):
        c, h = fn()
        save(out, name, c, h, k, flip=name in ("concrete", "rust"))
    c, h = facade(bc)
    save(out, "facade", c, h, 1.3, flip=True)
    c, h = windows(pc, ph)
    save(out, "windows", c, h, 1.3, flip=True)
    for name, fn, k in (("ground_grass", ground_grass, 1.0), ("ground_sand", ground_sand, 1.0),
                        ("ground_snow", ground_snow, 0.8), ("ground_urban", ground_urban, 1.0)):
        v, h = fn()
        save(out, name, v, None, gray=True)
        n = normal_map(h, k)
        Image.fromarray((np.clip(n, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(out, name + "_n.png"), optimize=True)


if __name__ == "__main__":
    main()
