#!/usr/bin/env python3
"""Крики экипажа: настоящие записи мужских воплей + выкрики на немецком (Ось) и английском (Союзники).

Основа — реальные записи с OpenGameArt (лицензии CC0 / CC-BY 3.0 / OGA-BY 3.0, авторы в CREDITS.txt):
  Aargh! (male screams) — CC-BY 3.0 (creativeheroes, thanvannispen, JohnsonBrandEditing; собрал Bonsaiheldin);
  Male Grunt/Yelling sounds (megaboots) — CC0 / OGA-BY 3.0;
  Pain sounds (EmoPreben, залил Marscaleb) — CC0; Man hurt sounds — CC0.
Слова («Nein!», «Hilfe!», «Mein Bein!», «Help!», «My leg!» …) синтезированы голосами Piper, у которых
свободные лицензии: немецкий Thorsten (CC0) и английский Joe (CC0); речь доведена до выкрика (тон выше,
дрожь, перегруз, сорванное дыхание) и положена под настоящий крик. Всё это играет внутри «стальной коробки» —
короткая металлическая реверберация. Скрипт пишет godot/assets/sfx/crew/*.ogg.

Запуск: python3 tools/import_screams.py <папка для скачанного> <папка с моделями piper>
Нужны numpy, scipy, ffmpeg (libvorbis), piper-tts и модели de_DE-thorsten-high, en_US-joe-medium.
"""
import os, sys, subprocess, urllib.request, zipfile, glob, wave
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "godot", "assets", "sfx", "crew")
SR = 44100
OGA = "https://opengameart.org/sites/default/files/"
PACKS = {
    "aargh": OGA + "aargh.zip",
    "yelling": OGA + "yelling%20sounds.zip",
    "pain": OGA + "painsounds.zip",
    "manhurt": OGA + "ManHurt.ogg",
}

# слова: (текст, как произносить). Для каждого вида — по несколько вариантов.
WORDS = {
    "de": {
        "wound": ["Mein Bein!", "Ich bin getroffen!", "Mein Arm!", "Verdammt, ich blute!", "Ah! Es brennt!", "Getroffen!"],
        "die": ["Neeein!", "Hilfe!", "Mutter!", "Mein Gott!", "Ich will nicht sterben!", "Neiiin, bitte nicht!"],
        "fire": ["Wir brennen! Raus hier!", "Feuer! Raus, raus!", "Ich brenne! Hilfe!", "Es brennt! Alle raus!"],
        "boom": ["Die Munition!", "Raus!", "Alle raus!"],
    },
    "en": {
        "wound": ["My leg!", "I'm hit!", "My arm!", "God, I'm bleeding!", "Ah! It burns!", "We're hit!"],
        "die": ["Noooo!", "Help me!", "Mom!", "Oh God!", "I don't wanna die!", "No, please, no!"],
        "fire": ["We're on fire! Get out!", "Fire! Bail out!", "I'm burning! Help!", "It's burning! Everybody out!"],
        "boom": ["The ammo!", "Get out!", "Everybody out!"],
    },
}
VOICES = {"de": "de_DE-thorsten-high.onnx", "en": "en_US-joe-medium.onnx"}

# какие реальные клипы под какой вид (имя файла без папки)
DIE_CLIPS = ["aargh0", "aargh1", "aargh2", "aargh3", "aargh4", "aargh5", "aargh6", "aargh7", "yell2", "3yell13", "3yell14", "3yell10", "1yell5", "3yell9", "yell11"]
WOUND_CLIPS = ["Painsounds v2 - Track 1 - Arrrch ", "Painsounds v2 - Track 2 - Hurgh", "Painsounds v2 - Track 3 - Huuurh", "Painsounds v2 - Track 4 - Arrggh ",
               "Painsounds v2 - Track 5 - Urggh", "Painsounds v2 - Track 6 - hyyrdhh", "3grunt1", "3grunt4", "3grunt5", "1yell4", "yell5", "2yell7", "3yell12", "3yell15"]
BOOM_CLIPS = ["aargh2", "aargh1", "yell2", "3yell13", "3yell10"]


def fetch(folder):
    os.makedirs(folder, exist_ok=True)
    for name, url in PACKS.items():
        path = os.path.join(folder, name + (".zip" if url.endswith(".zip") else ".ogg"))
        if not os.path.exists(path):
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            open(path, "wb").write(urllib.request.urlopen(req).read())
        if path.endswith(".zip"):
            with zipfile.ZipFile(path) as z:
                z.extractall(os.path.join(folder, name))


def to_wav(src, dst):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-ac", "1", "-ar", str(SR), dst], check=True)


def load_any(path):
    wav = path + ".tmp.wav"
    to_wav(path, wav)
    sr, x = wavfile.read(wav)
    os.remove(wav)
    return x.astype(np.float32) / 32768.0


def find_clip(folder, stem):
    for p in glob.glob(os.path.join(folder, "**", "*"), recursive=True):
        b = os.path.splitext(os.path.basename(p))[0]
        if b.strip() == stem.strip() and p.lower().endswith((".ogg", ".wav", ".mp3")):
            return p
    raise FileNotFoundError(stem)


def trim(x, thr_db=-38.0, keep=0.02):
    a = np.abs(x)
    m = a.max()
    idx = np.where(a > m * 10 ** (thr_db / 20))[0]
    if not len(idx):
        return x
    i0, i1 = max(0, idx[0] - int(keep * SR)), min(len(x), idx[-1] + int(0.06 * SR))
    return x[i0:i1]


def fade(x, fin=0.004, fout=0.06):
    x = x.copy()
    a, b = int(fin * SR), min(int(fout * SR), len(x))
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def hp(x, f=110):
    return sosfiltfilt(butter(2, f, "hp", fs=SR, output="sos"), x)


def band(x, lo, hi):
    return sosfiltfilt(butter(2, [lo, hi], "bp", fs=SR, output="sos"), x)


def sat(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def norm(x, peak=0.93):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)


def tank_room(x, rng, wet=0.22):
    """Стальная коробка: короткая металлическая реверберация и пара резонансов корпуса."""
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t / 0.07)
    ir = band(ir, 380, 4200)
    for f, g in ((210, 0.35), (415, 0.25), (880, 0.18)):
        ir += g * np.sin(2 * np.pi * f * t) * np.exp(-t / 0.05)
    ir[0] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    from scipy.signal import fftconvolve
    w = fftconvolve(x, ir)[:len(x) + n]
    out = np.zeros(len(w), np.float32)
    out[:len(x)] += x * (1 - wet)
    out += w * wet * 2.2
    return out


def pitch_shift(x, ratio):
    """Тон и тембр выше без сохранения длительности (как у сорвавшегося от страха голоса)."""
    n = int(len(x) / ratio)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)


def vibrato(x, rate, depth, rng):
    t = np.arange(len(x)) / SR
    ph = np.cumsum(1 + depth * np.sin(2 * np.pi * rate * t + rng.uniform(0, 6.28)) + 0.4 * depth * rng.standard_normal(len(x)) * 0.1)
    ph = np.clip(ph, 0, len(x) - 1)
    return np.interp(ph, np.arange(len(x)), x).astype(np.float32)


def synth(lang, text, models, work):
    wav = os.path.join(work, "tts_%s_%d.wav" % (lang, abs(hash(text)) % 10 ** 8))
    p = subprocess.run([sys.executable, "-m", "piper", "-m", os.path.join(models, VOICES[lang]), "-f", wav, "--length-scale", "0.82",
                        "--noise-scale", "0.9", "--noise-w-scale", "0.9"], input=text.encode("utf-8"), capture_output=True)
    if not os.path.exists(wav):
        raise RuntimeError(p.stderr.decode()[-300:])
    out = os.path.join(work, os.path.basename(wav)[:-4] + "_44.wav")
    to_wav(wav, out)
    sr, x = wavfile.read(out)
    return x.astype(np.float32) / 32768.0


def shout(x, rng, strength=1.0):
    """Речь → выкрик: выше, с дрожью, с перегрузом и срывом дыхания."""
    x = trim(x, -42)
    x = pitch_shift(x, 1.0 + 0.10 * strength)
    x = vibrato(x, rng.uniform(5.0, 7.5), 0.008 * strength, rng)
    x = hp(x, 160)
    env = np.abs(x)
    env = np.convolve(env, np.ones(int(0.02 * SR)) / int(0.02 * SR), "same")
    breath = band(rng.standard_normal(len(x)).astype(np.float32), 1200, 6500) * env * 0.18
    x = sat(norm(x, 1.0) * 1.2 + breath, 1.8 + 0.8 * strength)
    # ударение: громче в начале, спад к концу
    x *= np.linspace(1.0, 0.7, len(x))
    return fade(norm(x, 0.95), 0.003, 0.05)


def place(parts, length):
    out = np.zeros(length, np.float32)
    for x, at, g in parts:
        i = int(at * SR)
        j = min(len(out), i + len(x))
        if j > i:
            out[i:j] += x[:j - i] * g
    return out


def render(path, x):
    x = np.clip(x, -1, 1)
    tmp = path + ".wav"
    wavfile.write(tmp, SR, (x * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", path], check=True)
    os.remove(tmp)


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else "/tmp/screams"
    models = sys.argv[2] if len(sys.argv) > 2 else "/tmp/piper"
    os.makedirs(OUT, exist_ok=True)
    fetch(folder)
    work = os.path.join(folder, "work")
    os.makedirs(work, exist_ok=True)
    rng = np.random.default_rng(1944)
    cache = {}

    def clip(stem):
        if stem not in cache:
            p = None
            for pack in ("aargh", "yelling", "pain", "manhurt"):
                try:
                    p = find_clip(os.path.join(folder, pack), stem)
                    break
                except FileNotFoundError:
                    pass
            if p is None:
                raise FileNotFoundError(stem)
            x = trim(load_any(p))
            if len(x) > int(2.8 * SR):
                x = x[:int(2.8 * SR)]
            cache[stem] = fade(norm(hp(x), 0.95), 0.003, 0.12)
        return cache[stem]

    made = []
    for lang in ("de", "en"):
        for kind, texts in WORDS[lang].items():
            pool = {"die": DIE_CLIPS, "wound": WOUND_CLIPS, "fire": DIE_CLIPS, "boom": BOOM_CLIPS}[kind]
            for i, text in enumerate(texts):
                stem = pool[(i * 3 + (0 if lang == "de" else 1) + len(kind)) % len(pool)]
                sc = clip(stem)
                w = shout(synth(lang, text, models, work), rng, 1.0 if kind != "wound" else 0.7)
                if kind == "wound":
                    # короткий вскрик, следом слова
                    sc = fade(sc[:int(0.8 * SR)], 0.003, 0.1)
                    parts = [(sc, 0.0, 0.85), (w, 0.55, 1.0)]
                elif kind == "boom":
                    parts = [(w, 0.0, 1.0), (sc, 0.05 + 0.8 * len(w) / SR, 0.75)]
                else:
                    # слово, и крик поверх его конца, затем затухающий вопль
                    parts = [(w, 0.0, 1.0), (sc, 0.85 * len(w) / SR, 0.8)]
                length = int((max(at * SR + len(x) for x, at, g in parts)) + 0.35 * SR)
                x = place(parts, length)
                x = tank_room(x, rng, 0.22 if kind != "boom" else 0.3)
                x = sat(x * 1.1, 1.5)
                x = fade(norm(hp(x, 90), 0.93), 0.002, 0.15)
                name = "crew_%s_%s_%d.ogg" % (lang, kind, i + 1)
                render(os.path.join(OUT, name), x)
                made.append((name, len(x) / SR, text, stem))
    for m in made:
        print("%-24s %.1f с  «%s»  ← %s" % m)


if __name__ == "__main__":
    main()
