#!/usr/bin/env bash
# Сборка APK: ./build_apk.sh <godot> <keystore> <alias> <пароль>
# Нужны шаблоны экспорта той же версии Godot, JDK 17+ и Android SDK с build-tools
# (путь к SDK — в настройках редактора export/android/android_sdk_path).
set -euo pipefail
GODOT=$1
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$(realpath "$2")
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=$3
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$4
cd "$(dirname "$0")"
mkdir -p ../build
"$GODOT" --headless --import
"$GODOT" --headless --export-release "Android" ../build/Fireline.apk
