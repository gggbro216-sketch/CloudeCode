#!/usr/bin/env python3
"""Импорт настоящих записей с freesound.org в звуки игры.

Источники (превью высокого качества, лицензии CC0 и CC-BY 3.0/4.0) перечислены в SOURCES вместе с
авторами — их же выводит экран «Авторы» в ангаре (godot/assets/sfx/CREDITS.txt). Скрипт качает
превью, вырезает нужный участок, чистит низ и верх, нормализует, а петли сшивает бесшовно.
Звуки, которых нет в списке (треск дерева, срыв гусеницы, сигнал захвата, рация), остаются
синтезированными tools/gen_sfx.py.

Запуск: python3 tools/import_sfx.py <папка для скачанного>
"""
import os, sys, json, re, subprocess, urllib.request
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt

OUT = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "sfx")
SR = 44100

# id: (автор, название, лицензия)
SOURCES = {
    "368670": ("nicStage", "Sherman E8 (\"Easy 8\") tank starting up and running", "CC-BY 4.0"),
    "161897": ("JoniHeinonen", "WAR-TANK, LEOPARD-ENGINE STAND BY", "CC-BY 3.0"),
    "386661": ("YleArkisto", "Panssarivaunut maastossa / Tanks on terrain, tracks creaking", "CC-BY 4.0"),
    "171657": ("qubodup", "Tank or Tower Turret Moving and Turning", "CC0"),
    "127845": ("GaryQ", "Tank fire Mixed.wav", "CC0"),
    "187767": ("qubodup", "Cannon Shot", "CC0"),
    "186951": ("ReadeOnly", "cannon_boom7.wav", "CC0"),
    "539968": ("Za-Games", "Deep Boom", "CC0"),
    "108641": ("juskiddink", "Nearby explosion with debris.wav", "CC-BY 4.0"),
    "423113": ("OGsoundFX", "Guns & Explosions Album - Heavy Object Impact 10", "CC-BY 4.0"),
    "264889": ("EpicWizard", "SFX Metal Shed Door - Hits, Clangs, Rattle", "CC0"),
    "148840": ("cedarstudios", "ricochet.mp3", "CC0"),
    "446625": ("IdkMrGarcia", "explosion.wav", "CC0"),
    "318964": ("GryffDavid", "Bouncing Shell Casings (Various Sizes)", "CC0"),
    "170991": ("bendodge", "Incoming Artillery.wav", "CC-BY 3.0"),
    "345844": ("Aegersum", "Cannon artillery - distant gunshots.wav", "CC-BY 3.0"),
    "18766": ("reinsamba", "chimney fire.wav", "CC-BY 4.0"),
    "673807": ("klankbeeld", "wind cornfield 1613PM 220529_0375.wav", "CC-BY 4.0"),
}
USERS = {k: v[0] for k, v in SOURCES.items()}


def fetch(sid, folder):
    path = os.path.join(folder, sid + ".mp3")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    page = "https://freesound.org/people/%s/sounds/%s/" % (USERS[sid], sid)
    req = urllib.request.Request(page, headers={"User-Agent": "Mozilla/5.0"})
    html = urllib.request.urlopen(req).read().decode("utf-8", "ignore")
    m = re.search(r"previews/\d+/%s_\d+-lq\.mp3" % sid, html)
    url = "https://cdn.freesound.org/" + m.group(0).replace("-lq", "-hq")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    open(path, "wb").write(urllib.request.urlopen(req).read())
    return path


def load(sid, folder):
    mp3 = fetch(sid, folder)
    wav = mp3[:-4] + ".wav"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", mp3, "-ac", "1", "-ar", str(SR), wav], check=True)
    sr, x = wavfile.read(wav)
    return x.astype(np.float32) / 32768.0


def cut(x, a, b):
    return x[int(a * SR):int(b * SR)]


def band(x, lo=None, hi=None, order=4):
    if lo:
        x = sosfiltfilt(butter(order, lo, "hp", fs=SR, output="sos"), x)
    if hi:
        x = sosfiltfilt(butter(order, hi, "lp", fs=SR, output="sos"), x)
    return x


def norm(x, peak=0.89):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def level(x, rms_db, peak=0.89):
    """Громкость по среднему (RMS): тихие записи с редкими пиками поднимаются мягким ограничителем."""
    x = norm(x, 1.0)
    lo, hi = 0.0, 40.0
    for _ in range(24):
        g = (lo + hi) / 2
        y = norm(np.tanh(x * 10 ** (g / 20)), peak)
        rms = 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-9)
        lo, hi = (g, hi) if rms < rms_db else (lo, g)
    return y


def fade(x, fin=0.003, fout=0.05):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def steady(x, length, step=0.25):
    """Самый ровный по громкости участок заданной длины (для петель)."""
    hop = int(0.05 * SR)
    env = np.array([np.sqrt(np.mean(x[i:i + hop] ** 2)) for i in range(0, len(x) - hop, hop)])
    n = int(length / 0.05)
    best, bi = 1e9, 0
    for i in range(0, len(env) - n, int(step / 0.05)):
        seg = 20 * np.log10(env[i:i + n] + 1e-6)
        if seg.mean() < 20 * np.log10(env.max() + 1e-6) - 18:
            continue  # пропускаем тихие места
        if seg.std() < best:
            best, bi = seg.std(), i
    return x[bi * hop:bi * hop + int(length * SR)]


def loop(x, xf=0.4):
    """Бесшовная петля: конец плавно перетекает в начало (равная мощность)."""
    n = int(xf * SR)
    body, tail = x[:-n], x[-n:]
    t = np.linspace(0, np.pi / 2, n)
    body[:n] = body[:n] * np.sin(t) + tail * np.cos(t)
    return body


def layer(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n, np.float32)
    for p in parts:
        out[:len(p)] += p
    return out


def onset(x, thr_db=-12):
    """Индекс атаки: первое превышение порога относительно пика."""
    a = np.abs(x)
    return int(np.argmax(a > a.max() * 10 ** (thr_db / 20)))


def from_onset(x, pre=0.01, length=None):
    i = max(0, onset(x) - int(pre * SR))
    return x[i:i + int(length * SR)] if length else x[i:]


def save_ogg(name, x, q=5):
    wav = os.path.join(OUT, name + ".tmp.wav")
    wavfile.write(wav, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", str(q),
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)
    print(name, "%.2f s" % (len(x) / SR))


def save_wav(name, x, rate=SR):
    if rate != SR:
        n = int(len(x) * rate / SR)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    wavfile.write(os.path.join(OUT, name + ".wav"), rate, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    print(name, "%.2f s (петля)" % (len(x) / rate))


def main(folder):
    os.makedirs(folder, exist_ok=True)
    L = lambda sid: load(sid, folder)

    # --- петли
    sherman = L("368670")
    run = steady(cut(sherman, 12, 42), 4.4)
    save_wav("engine_petrol", norm(loop(band(run, 28, 9000))))
    leo = L("161897")
    save_wav("engine_diesel", norm(loop(band(steady(leo, 4.4), 28, 8000))))
    trk = L("386661")
    save_wav("tracks", norm(loop(band(steady(trk, 5.4), 60, 10000))))
    tur = L("171657")
    save_wav("turret", norm(loop(band(cut(tur, 0.2, 3.8), 80, 9000), 0.3)))
    fire = L("18766")
    save_wav("fire", level(loop(band(steady(fire, 6.4), 120, 12000)), -26))
    wind = L("673807")
    save_wav("wind", norm(loop(band(steady(wind, 8.6), 40, 7000), 0.8)) * 0.4, 22050)

    # --- выстрелы: короткий хлёсткий 75 мм, гулкий 88 мм, тяжёлый 122 мм с низким ударом
    g75 = from_onset(L("127845"), length=4.2)
    save_ogg("gun_75", norm(fade(band(g75, 30, 14000), 0.002, 0.8)))
    g88 = from_onset(cut(L("187767"), 0.0, 6.0), length=5.5)
    save_ogg("gun_88", norm(fade(band(g88, 25, 14000), 0.002, 1.0)))
    big = from_onset(L("186951"), length=1.8)
    low = band(from_onset(L("539968"), length=3.2), None, 220) * 0.9
    save_ogg("gun_122", norm(fade(band(layer(big, low), 22, 14000), 0.002, 0.9)))

    # --- разрывы и попадания
    save_ogg("explosion", norm(fade(band(from_onset(L("108641"), length=3.6), 25, 15000), 0.002, 0.6)))
    save_ogg("hit_pen", norm(fade(band(from_onset(L("423113"), length=2.8), 40, 15000), 0.002, 0.5)))
    shed = L("264889")
    clang = steady_hit(shed)
    save_ogg("hit_nopen", level(fade(band(clang, 120, 15000), 0.001, 0.4), -25))
    ric = L("148840")
    save_ogg("ricochet", norm(fade(band(from_onset(cut(ric, 0.0, 0.42), length=0.42), 300, 16000), 0.001, 0.12)))
    boom = L("446625")
    save_ogg("impact_ground", norm(fade(band(from_onset(boom, length=1.6), 30, 9000), 0.002, 0.5)))

    # --- перезарядка: звон гильзы о дно боевого отделения
    cas = L("318964")
    save_ogg("reload", level(fade(band(from_onset(cut(cas, 6.8, 9.6), length=1.6), 200, 16000), 0.001, 0.3), -24))
    # --- свист снаряда до разрыва
    inc = L("170991")
    save_ogg("whiz", norm(fade(band(cut(inc, 0.4, 2.85), 400, 14000), 0.15, 0.25)) * 0.55)
    # --- далёкая канонада
    save_ogg("distant", norm(fade(band(L("345844"), 20, 6000), 0.05, 1.0)) * 0.9, 3)

    with open(os.path.join(OUT, "CREDITS.txt"), "w") as f:
        f.write("Записи с freesound.org. CC0 — общественное достояние; CC-BY — Creative Commons Attribution,\n")
        f.write("использованы фрагменты, обработаны (обрезка, фильтры, нормализация, петли).\n\n")
        for sid, (user, title, lic) in SOURCES.items():
            f.write("%s — «%s», %s, https://freesound.org/s/%s/\n" % (user, title, lic, sid))


def steady_hit(x):
    """Самый звонкий одиночный удар в записи стальной двери: резкая атака, тишина перед ним."""
    hop = int(0.01 * SR)
    env = np.array([np.max(np.abs(x[i:i + hop])) for i in range(0, len(x) - hop, hop)])
    best, bi = 0.0, 0
    for i in range(30, len(env) - 150):
        pre = env[i - 30:i].max()
        if env[i] > 0.25 and env[i] > pre * 6 and env[i] > best:
            best, bi = env[i], i
    return x[bi * hop - int(0.005 * SR): bi * hop + int(1.2 * SR)]


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/freesound")
