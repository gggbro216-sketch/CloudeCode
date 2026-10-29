#!/usr/bin/env bash
# Сборка APK: ./build_apk.sh <godot> [keystore alias пароль]
# Без ключа подписывает ключом проекта из signing/ (см. signing/README.md).
# Нужны шаблоны экспорта той же версии Godot, JDK 17+ и Android SDK с build-tools
# (путь к SDK — в настройках редактора export/android/android_sdk_path).
set -euo pipefail
GODOT=$(realpath "$1")
cd "$(dirname "$0")"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$(realpath "${2:-signing/fireline.keystore}")
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=${3:-fireline}
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=${4:-fireline123}
mkdir -p ../build
"$GODOT" --headless --import
"$GODOT" --headless --export-release "Android" ../build/Fireline.apk
