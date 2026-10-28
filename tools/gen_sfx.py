#!/usr/bin/env python3
"""Генератор звуков «Стального Штурма».

Синтезирует звуки боя (выстрелы трёх калибров, разрывы, попадания, двигатели, траки,
привод башни, перезарядку, окружение) и сохраняет их в godot/assets/sfx/*.ogg.
Петли (двигатели, траки, башня, ветер, огонь) склеены бесшовно: фильтры считаются по
кругу, число циклов в петле целое.

Запуск: python3 tools/gen_sfx.py   (нужны numpy, scipy и ffmpeg с libvorbis)
Любой файл можно заменить настоящей записью с тем же именем.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "sfx")
rng = np.random.default_rng(1943)


# ---------- основы ----------

def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec):
    return rng.standard_normal(int(SR * sec))


def filt(x, kind, f, order=4):
    if kind == "bp":
        sos = signal.butter(order, [f[0] / (SR / 2), f[1] / (SR / 2)], btype="band", output="sos")
    else:
        sos = signal.butter(order, f / (SR / 2), btype="low" if kind == "lp" else "high", output="sos")
    return signal.sosfilt(sos, x)


def filt_loop(x, kind, f, order=4):
    """Фильтр без шва на стыке петли: считаем по трём копиям и берём среднюю."""
    n = len(x)
    y = filt(np.concatenate([x, x, x]), kind, f, order)
    return y[n:2 * n]


def env_exp(sec, tau, attack=0.002):
    t = t_axis(sec)
    a = np.clip(t / attack, 0, 1) if attack > 0 else 1.0
    return a * np.exp(-t / tau)


def pad(x, sec):
    n = int(SR * sec)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def at(x, delay, total):
    """Сдвинуть звук на delay секунд внутри дорожки длиной total."""
    out = np.zeros(int(SR * total))
    s = int(SR * delay)
    e = min(len(out), s + len(x))
    out[s:e] += x[: e - s]
    return out


def modal(freqs, decays, amps, sec, jitter=0.0):
    """Модальный синтез металла: сумма затухающих синусоид."""
    t = t_axis(sec)
    y = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        f2 = f * (1 + rng.uniform(-jitter, jitter))
        y += a * np.sin(2 * np.pi * f2 * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    return y


def sweep(f0, f1, sec, tau):
    t = t_axis(sec)
    f = f1 + (f0 - f1) * np.exp(-t / (sec * 0.25))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / tau)


def reverb(x, sec=2.5, tau=0.55, cutoff=1800.0, echoes=((0.32, 0.35), (0.85, 0.18)), wet=0.45):
    """Реверберация открытого поля: затухающий шум + отражения от холмов и строений."""
    ir = noise(sec) * np.exp(-t_axis(sec) / tau)
    ir = filt(ir, "lp", cutoff, 2)
    for d, g in echoes:
        i = int(SR * d)
        if i < len(ir):
            ir[i:i + 400] += g * np.max(np.abs(ir)) * np.hanning(400) * rng.standard_normal(400)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    y = signal.fftconvolve(x, ir)[: len(x) + len(ir) - 1]
    dry = np.concatenate([x, np.zeros(len(y) - len(x))])
    # хвост не громче прямого звука: пик реверберации — доля wet от пика удара
    y *= wet * (np.max(np.abs(x)) + 1e-9) / (np.max(np.abs(y)) + 1e-9)
    return dry + y


def soft(x, drive=1.6):
    return np.tanh(x * drive) / np.tanh(drive)


def norm(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def fade(x, fin=0.002, fout=0.05):
    n_in = max(1, int(SR * fin))
    n_out = max(1, int(SR * fout))
    x = x.copy()
    x[:n_in] *= np.linspace(0, 1, n_in)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    return x


def save_wav(name, x, rate=22050):
    """Петли храним в WAV: так стык остаётся бесшовным (Vorbis добавляет щелчок на границе)."""
    os.makedirs(OUT, exist_ok=True)
    if rate != SR:
        x = signal.resample_poly(np.concatenate([x, x, x]), rate, SR)
        n = len(x) // 3
        x = x[n:2 * n]
    # склейка петли: последние k сэмплов плавно переходят в начало
    k = int(rate * 0.04)
    body = x[k:].copy()
    ramp = np.linspace(0, 1, k)
    body[-k:] = body[-k:] * (1 - ramp) + x[:k] * ramp
    x = np.clip(body, -1, 1)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(f"{name}.wav  {len(x) / rate:.2f} c  {os.path.getsize(path) // 1024} КБ")


def save(name, x, quality=4):
    os.makedirs(OUT, exist_ok=True)
    x = np.clip(x, -1, 1)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = tmp.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", str(quality), out], check=True)
    os.remove(path)
    print(f"{name}.ogg  {len(x) / SR:.2f} c  {os.path.getsize(out) // 1024} КБ")


# ---------- выстрелы ----------

def gun(caliber):
    """Выстрел: ударная волна, дульный выхлоп, низкий удар, лязг затвора, эхо."""
    k = caliber / 85.0
    total = 0.9
    crack = filt(noise(0.006), "hp", 2500) * np.hanning(int(SR * 0.006))
    blast = filt(noise(total), "lp", 900 / k ** 0.5) * env_exp(total, 0.09 * k, 0.001)
    body = filt(noise(total), "bp", (120, 1600)) * env_exp(total, 0.22 * k, 0.003)
    boom = sweep(85 / k ** 0.6, 32 / k ** 0.3, total, 0.35 * k)
    clank = modal([410, 1130, 2240, 3480], [0.06, 0.12, 0.09, 0.05], [0.5, 0.35, 0.22, 0.15], 0.4, 0.05)
    x = pad(crack * 1.2, total) + blast * 1.1 + body * 0.55 + boom * 1.3 + at(clank * 0.12, 0.11, total)
    x = soft(norm(x), 2.2)
    x = reverb(x, 2.8, 0.6 * k ** 0.5, 1500, ((0.3, 0.4), (0.78, 0.22), (1.4, 0.1)), 0.42)
    return fade(norm(x), 0.0005, 0.4)


def explosion():
    total = 2.2
    boom = sweep(60, 22, total, 0.9)
    blast = filt(noise(total), "lp", 1200) * env_exp(total, 0.35, 0.004)
    roar = filt(noise(total), "lp", 300) * env_exp(total, 0.8, 0.02)
    crackle = np.zeros(int(SR * total))
    for _ in range(260):
        i = int(rng.uniform(0.05, 2.0) * SR)
        ln = int(SR * rng.uniform(0.002, 0.008))
        if i + ln < len(crackle):
            crackle[i:i + ln] += rng.uniform(0.2, 1.0) * np.hanning(ln) * np.exp(-i / SR / 0.8)
    crackle = filt(crackle * rng.standard_normal(len(crackle)), "bp", (900, 5000))
    debris = modal([230, 610, 1270, 2150], [0.2, 0.15, 0.1, 0.08], [0.5, 0.4, 0.3, 0.2], total, 0.1)
    x = boom * 1.5 + blast * 1.2 + roar * 0.8 + crackle * 0.5 + at(debris * 0.15, 0.25, total)
    x = soft(norm(x), 2.6)
    x = reverb(x, 3.0, 0.8, 1200, ((0.35, 0.4), (0.9, 0.25)), 0.5)
    return fade(norm(x), 0.001, 0.6)


# ---------- попадания ----------

def hit_pen():
    """Пробитие: тяжёлый удар по броне, хруст и короткое затухание корпуса."""
    total = 1.2
    thud = filt(noise(total), "lp", 350) * env_exp(total, 0.05, 0.001)
    crunch = filt(noise(total), "bp", (900, 3500)) * env_exp(total, 0.035, 0.0005)
    metal = modal([176, 463, 837, 1290, 1960, 2710], [0.35, 0.3, 0.25, 0.18, 0.12, 0.08], [0.6, 0.5, 0.4, 0.3, 0.2, 0.15], total, 0.04)
    x = thud * 1.4 + crunch * 0.8 + metal * 0.4
    x = reverb(soft(norm(x), 2.0), 1.4, 0.3, 2500, ((0.2, 0.2),), 0.25)
    return fade(norm(x), 0.0005, 0.3)


def hit_nopen():
    """Непробитие: звонкий удар, броня гудит."""
    total = 1.6
    tick = filt(noise(total), "hp", 2000) * env_exp(total, 0.012, 0.0003)
    ring = modal([620, 1490, 2580, 3870, 5230, 6900], [0.7, 0.55, 0.4, 0.3, 0.2, 0.12], [0.5, 0.45, 0.35, 0.25, 0.18, 0.1], total, 0.03)
    thud = filt(noise(total), "lp", 400) * env_exp(total, 0.04, 0.001)
    x = tick * 0.9 + ring * 0.6 + thud * 0.7
    x = reverb(norm(x), 1.2, 0.3, 4000, ((0.25, 0.15),), 0.2)
    return fade(norm(x), 0.0003, 0.4)


def ricochet():
    total = 1.1
    t = t_axis(total)
    f = 3200 * np.exp(-t / 0.35) + 700
    whine = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.45) * np.clip(t / 0.03, 0, 1)
    air = filt(noise(total), "bp", (1500, 6000)) * np.exp(-t / 0.3) * 0.3
    clang = modal([780, 1930, 3410], [0.15, 0.1, 0.07], [0.6, 0.4, 0.3], total)
    x = clang * 0.7 + whine * 0.55 + air
    return fade(norm(reverb(x, 1.0, 0.25, 5000, ((0.3, 0.1),), 0.2)), 0.0003, 0.3)


def impact_ground():
    total = 1.4
    thud = filt(noise(total), "lp", 220) * env_exp(total, 0.12, 0.002)
    boom = sweep(70, 35, total, 0.2)
    spray = np.zeros(int(SR * total))
    for _ in range(140):
        i = int(rng.uniform(0.03, 0.9) * SR)
        ln = int(SR * rng.uniform(0.001, 0.004))
        if i + ln < len(spray):
            spray[i:i + ln] += rng.uniform(0.1, 0.6) * np.hanning(ln) * np.exp(-i / SR / 0.35)
    spray = filt(spray * rng.standard_normal(len(spray)), "bp", (600, 3500))
    x = soft(norm(thud * 1.2 + boom * 0.9 + spray * 0.6), 2.0)
    return fade(norm(reverb(x, 2.0, 0.5, 1200, ((0.3, 0.3),), 0.35)), 0.001, 0.3)


def impact_stone():
    total = 1.3
    crack = filt(noise(total), "bp", (800, 5000)) * env_exp(total, 0.03, 0.0005)
    thud = filt(noise(total), "lp", 300) * env_exp(total, 0.08, 0.001)
    crumble = np.zeros(int(SR * total))
    for _ in range(90):
        i = int(rng.uniform(0.05, 1.1) * SR)
        ln = int(SR * rng.uniform(0.002, 0.01))
        if i + ln < len(crumble):
            crumble[i:i + ln] += rng.uniform(0.1, 0.7) * np.hanning(ln) * np.exp(-i / SR / 0.45)
    crumble = filt(crumble * rng.standard_normal(len(crumble)), "bp", (300, 2500))
    x = crack * 1.0 + thud * 1.2 + crumble * 0.6
    return fade(norm(reverb(soft(norm(x), 1.8), 1.6, 0.4, 2000, ((0.25, 0.25),), 0.3)), 0.0005, 0.3)


# ---------- двигатели и ходовая (петли) ----------

def engine(kind):
    """Двигатель на холостых: дизель В-2 (стук, жёсткие вспышки) или карбюраторный V12/V8."""
    loop = 2.0
    n = int(SR * loop)
    diesel = kind == "diesel"
    fire_hz = 60.0 if diesel else 80.0  # частота вспышек на холостых
    cycles = int(fire_hz * loop)
    period = n / cycles
    x = np.zeros(n)
    knock = np.zeros(n)
    pulse_len = int(period * 0.9)
    tp = np.arange(pulse_len) / SR
    for c in range(cycles):
        start = int(c * period + rng.uniform(-0.04, 0.04) * period) % n
        amp = rng.uniform(0.75, 1.15)
        p = np.exp(-tp / (0.004 if diesel else 0.006)) * np.sin(2 * np.pi * (95 if diesel else 120) * tp) * amp
        idx = (start + np.arange(pulse_len)) % n
        x[idx] += p
        if diesel:
            kl = int(SR * 0.0015)
            kidx = (start + np.arange(kl)) % n
            knock[kidx] += rng.uniform(0.4, 1.0) * np.hanning(kl)
    t = np.arange(n) / SR
    sub = np.sin(2 * np.pi * (fire_hz / 2) * t) * 0.35 + np.sin(2 * np.pi * fire_hz * t + 0.6) * 0.25
    rumble = filt_loop(rng.standard_normal(n), "lp", 180) * 0.6
    exhaust = filt_loop(rng.standard_normal(n), "bp", (200, 900)) * (0.25 if diesel else 0.12)
    y = filt_loop(x, "lp", 1400 if diesel else 1100) * 1.0 + sub + rumble + exhaust
    if diesel:
        y += filt_loop(knock * rng.standard_normal(n), "bp", (1800, 4500)) * 0.35
    else:
        # мягкий гул и подвывание нагнетателя
        y += np.sin(2 * np.pi * 240 * t) * 0.05 + np.sin(2 * np.pi * 480 * t) * 0.03
    y = filt_loop(y, "hp", 25, 2)
    return norm(soft(norm(y), 1.4), 0.8)


def tracks():
    """Лязг траков: удары звеньев о звёздочку, скрип пальцев, гул по грунту."""
    loop = 2.0
    n = int(SR * loop)
    rate = 24  # ударов звеньев в секунду при базовой скорости
    x = np.zeros(n)
    for c in range(int(rate * loop)):
        s = int(c * n / (rate * loop) + rng.uniform(-0.15, 0.15) * SR / rate) % n
        ln = int(SR * rng.uniform(0.003, 0.008))
        idx = (s + np.arange(ln)) % n
        x[idx] += rng.uniform(0.5, 1.0) * np.hanning(ln)
    clicks = filt_loop(x * rng.standard_normal(n), "bp", (700, 4000))
    ring = np.zeros(n)
    for c in range(int(rate * loop)):
        if rng.uniform() < 0.35:
            s = int(c * n / (rate * loop)) % n
            m = modal([1300, 2900], [0.03, 0.02], [0.5, 0.3], 0.08, 0.1)
            idx = (s + np.arange(len(m))) % n
            ring[idx] += m
    t = np.arange(n) / SR
    squeal = filt_loop(rng.standard_normal(n), "bp", (2000, 2400)) * (0.5 + 0.5 * np.sin(2 * np.pi * 1.5 * t)) * 0.25
    rumble = filt_loop(rng.standard_normal(n), "lp", 150) * 0.8
    y = clicks * 1.0 + ring * 0.25 + squeal + rumble
    return norm(soft(norm(y), 1.3), 0.8)


def turret():
    loop = 1.0
    n = int(SR * loop)
    t = np.arange(n) / SR
    whine = np.sin(2 * np.pi * 380 * t) * 0.4 + np.sin(2 * np.pi * 760 * t) * 0.2 + np.sin(2 * np.pi * 1140 * t) * 0.1
    gear = filt_loop(rng.standard_normal(n), "bp", (1500, 3000)) * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t)) * 0.25
    hum = filt_loop(rng.standard_normal(n), "lp", 200) * 0.3
    return norm(whine + gear + hum, 0.7)


def wind():
    """Ветер над полем боя с порывами."""
    loop = 8.0
    n = int(SR * loop)
    t = np.arange(n) / SR
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * t / loop) * np.sin(2 * np.pi * 3 * t / loop + 1.0)
    w = filt_loop(rng.standard_normal(n), "bp", (120, 900), 2) * gust
    hiss = filt_loop(rng.standard_normal(n), "bp", (1500, 5000), 2) * gust * 0.15
    return norm(w + hiss, 0.6)


def fire_loop():
    """Треск горящего танка."""
    loop = 3.0
    n = int(SR * loop)
    x = np.zeros(n)
    for _ in range(500):
        i = int(rng.uniform(0, loop) * SR)
        ln = int(SR * rng.uniform(0.001, 0.006))
        idx = (i + np.arange(ln)) % n
        x[idx] += rng.uniform(0.1, 1.0) * np.hanning(ln)
    crackle = filt_loop(x * rng.standard_normal(n), "bp", (800, 6000))
    roar = filt_loop(rng.standard_normal(n), "lp", 250) * 0.7
    return norm(crackle + roar, 0.7)


# ---------- прочее ----------

def reload_snd():
    """Перезарядка: звон стреляной гильзы и досылание снаряда, лязг затвора."""
    total = 1.4
    case = modal([930, 2410, 4130, 5600], [0.25, 0.18, 0.12, 0.08], [0.5, 0.4, 0.25, 0.15], 0.6, 0.03)
    bounce = at(case * 0.4, 0.18, 0.8)
    ram = filt(noise(0.2), "bp", (200, 1500)) * env_exp(0.2, 0.04)
    breech = modal([300, 760, 1450, 2800], [0.08, 0.06, 0.05, 0.03], [0.7, 0.5, 0.35, 0.2], 0.4, 0.05)
    x = at(case, 0.0, total) + at(bounce, 0.0, total) + at(ram, 0.75, total) + at(breech * 0.9, 0.85, total)
    return fade(norm(reverb(x, 0.6, 0.12, 4000, ((0.05, 0.3),), 0.25)), 0.0005, 0.2)


def tree_crack():
    total = 1.6
    snap = filt(noise(total), "bp", (500, 4000)) * env_exp(total, 0.03, 0.0005)
    creak = np.zeros(int(SR * total))
    t = t_axis(total)
    creak += filt(np.sin(2 * np.pi * (180 + 60 * np.sin(2 * np.pi * 3 * t)) * t) * (rng.standard_normal(len(t)) * 0.3 + 1), "bp", (150, 900)) * np.exp(-t / 0.5) * 0.4
    fall = filt(noise(total), "lp", 400) * np.clip((t - 0.9) / 0.05, 0, 1) * np.exp(-np.clip(t - 0.9, 0, None) / 0.15)
    leaves = filt(noise(total), "bp", (2000, 7000)) * np.exp(-t / 0.7) * 0.25
    return fade(norm(snap + creak + fall * 0.8 + leaves), 0.0005, 0.2)


def track_break():
    total = 1.4
    clank = modal([340, 870, 1610, 2560], [0.15, 0.12, 0.08, 0.05], [0.6, 0.5, 0.35, 0.2], total, 0.1)
    rattle = np.zeros(int(SR * total))
    for k in range(14):
        i = int((0.08 + k * 0.05 + rng.uniform(0, 0.02)) * SR)
        m = modal([1200, 2700], [0.02, 0.015], [0.6, 0.3], 0.06, 0.2)
        rattle[i:i + len(m)] += m * (1 - k / 16)
    thud = filt(noise(total), "lp", 300) * env_exp(total, 0.06)
    return fade(norm(clank * 0.6 + rattle * 0.5 + thud), 0.0005, 0.2)


def capture():
    """Сигнал рации о захвате: два тона через полосу 300–3000 Гц с треском эфира."""
    total = 0.7
    t = t_axis(total)
    tone = np.where(t < 0.3, np.sin(2 * np.pi * 880 * t), np.sin(2 * np.pi * 1175 * t)) * (t < 0.62)
    static = filt(noise(total), "bp", (300, 3000)) * 0.15
    return fade(norm(filt(tone * 0.8 + static, "bp", (300, 3000))), 0.005, 0.05)


def whiz():
    """Свист пролетающего рядом снаряда (с допплеровским сдвигом)."""
    total = 0.6
    t = t_axis(total)
    f = 1800 - 1100 * np.tanh((t - 0.25) / 0.08)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.3
    air = filt(noise(total), "bp", (800, 4500)) * 0.8
    envl = np.exp(-((t - 0.25) / 0.09) ** 2)
    return fade(norm((tone + air) * envl), 0.002, 0.05)


def distant_battle():
    """Далёкая канонада: глухие раскаты для фона."""
    total = 5.0
    x = np.zeros(int(SR * total))
    for d in [0.1, 1.3, 1.9, 3.4]:
        b = filt(noise(1.6), "lp", 180) * env_exp(1.6, 0.4, 0.02) + sweep(45, 25, 1.6, 0.6) * 0.6
        x += at(b * rng.uniform(0.4, 1.0), d, total)
    return fade(norm(reverb(x, 3.0, 1.0, 400, ((0.5, 0.4), (1.2, 0.3)), 0.6), 0.6), 0.05, 1.0)


if __name__ == "__main__":
    save("gun_75", gun(75))
    save("gun_88", gun(88))
    save("gun_122", gun(122))
    save("explosion", explosion())
    save("hit_pen", hit_pen())
    save("hit_nopen", hit_nopen())
    save("ricochet", ricochet())
    save("impact_ground", impact_ground())
    save("impact_stone", impact_stone())
    save_wav("engine_diesel", engine("diesel"))
    save_wav("engine_petrol", engine("petrol"))
    save_wav("tracks", tracks())
    save_wav("turret", turret())
    save_wav("wind", wind(), 16000)
    save_wav("fire", fire_loop())
    save("reload", reload_snd())
    save("tree", tree_crack())
    save("track_break", track_break())
    save("capture", capture())
    save("whiz", whiz())
    save("distant", distant_battle(), 3)
