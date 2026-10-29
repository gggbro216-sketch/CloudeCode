#!/usr/bin/env bash
# Сборка APK без Gradle: ./tools/build_apk.sh <godot> <keystore> <alias> <password>
# Нужны: шаблоны экспорта 4.7.2, JDK, Android SDK с platform-tools/adb и build-tools/*/apksigner
# (путь к SDK задаётся в настройках редактора export/android/android_sdk_path).
set -euo pipefail
GODOT=$1
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$(realpath "$2")
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=$3
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$4
cd "$(dirname "$0")/../godot"
mkdir -p ../build
"$GODOT" --headless --import
"$GODOT" --headless --export-release "Android" ../build/SteelAssault.apk
