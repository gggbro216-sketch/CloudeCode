#!/bin/sh
# Сборка C++-библиотеки SteelCore (GDExtension на C-интерфейсе, без godot-cpp).
#   linux:   системный g++
#   android: Android NDK r28 (переменная ANDROID_NDK_ROOT)
#   web:     Emscripten 4.0.11 — той же версии, что шаблоны Godot 4.7.2 (переменная EMSDK; модуль без
#            потоков: страницы Яндекс Игр без SharedArrayBuffer)
# Результат — godot/native/bin/. Заголовок native/include/gdextension_interface.h выгружен
# из Godot 4.7 командой: godot --headless --dump-gdextension-interface
set -e
cd "$(dirname "$0")/../godot/native"
SRC="src/glue.cpp src/core.cpp src/textures.cpp src/battle.cpp src/mapgen.cpp src/geom.cpp src/mapbuild.cpp src/tankbuild.cpp"
FLAGS="-std=c++17 -O2 -fPIC -shared -fvisibility=hidden -Iinclude -Wall"
mkdir -p bin
g++ $FLAGS $SRC -o bin/libsteelcore.linux.x86_64.so -static-libstdc++ -static-libgcc
echo "linux.x86_64: ok"
if [ -n "$ANDROID_NDK_ROOT" ]; then
	CXX="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
	"$CXX" --target=aarch64-linux-android24 $FLAGS $SRC -o bin/libsteelcore.android.arm64.so -static-libstdc++ -Wl,-z,max-page-size=16384
	"$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" bin/libsteelcore.android.arm64.so
	echo "android.arm64: ok"
fi
if [ -n "$EMSDK" ]; then
	"$EMSDK/upstream/emscripten/em++" -std=c++17 -O2 -fvisibility=hidden -Iinclude -Wall -sSIDE_MODULE=1 -sSUPPORT_LONGJMP=wasm \
		-sWASM_BIGINT $SRC -o bin/libsteelcore.web.wasm32.wasm
	echo "web.wasm32: ok"
fi
