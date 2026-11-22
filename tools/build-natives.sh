#!/usr/bin/env bash
# Builds the helper programs the Grabby phone app needs, for 64-bit Android (phones: arm64-v8a, emulators: x86_64):
#   qjs    - QuickJS-NG JavaScript engine (YouTube needs one to unlock its videos)
#   ffmpeg - joins HD video + audio, makes MP3/GIF/ringtones, Messenger-size videos
# Output: <out>/<abi>/libqjs.so and libffmpeg.so  (named lib*.so so Android installs them as runnable files)
set -euo pipefail
OUT=$(realpath -m "${1:-natives}")
API=24
QJS_VER=v0.18.0
FF_VER=7.1.1
LAME_VER=3.100
NDK=${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-}}
[ -d "$NDK" ] || { echo "Android NDK not found"; exit 1; }
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64
JOBS=$(nproc)
SRC=$(mktemp -d)

cd "$SRC"
git clone -q --depth 1 --branch "$QJS_VER" https://github.com/quickjs-ng/quickjs.git qjs
curl -fsSL "https://downloads.sourceforge.net/project/lame/lame/$LAME_VER/lame-$LAME_VER.tar.gz" -o lame.tgz
git clone -q --depth 1 https://code.videolan.org/videolan/x264.git x264
curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$FF_VER.tar.xz" -o ff.txz

build_abi() {   # build_abi <android abi> <clang target> <ffmpeg arch>
  local ABI=$1 HOST=$2 ARCH=$3
  local W; W=$(mktemp -d)
  local PREFIX=$W/prefix
  export CC=$TC/bin/${HOST}${API}-clang CXX=$TC/bin/${HOST}${API}-clang++
  export AR=$TC/bin/llvm-ar RANLIB=$TC/bin/llvm-ranlib STRIP=$TC/bin/llvm-strip NM=$TC/bin/llvm-nm
  export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
  local NOASM=""
  [ "$ARCH" = "x86_64" ] && NOASM=1        # emulator only: skip hand-written assembly (simpler, still works)
  mkdir -p "$OUT/$ABI" "$PREFIX"

  echo "::group::[$ABI] QuickJS-NG $QJS_VER"
  cmake -S "$SRC/qjs" -B "$W/qjs" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=$ABI -DANDROID_PLATFORM=android-$API -DBUILD_SHARED_LIBS=OFF >/dev/null
  cmake --build "$W/qjs" --target qjs_exe -j"$JOBS" >/dev/null || cmake --build "$W/qjs" --target qjs -j"$JOBS" >/dev/null
  "$STRIP" "$(find "$W/qjs" -maxdepth 2 -type f -name qjs | head -1)" -o "$OUT/$ABI/libqjs.so"
  echo "::endgroup::"

  echo "::group::[$ABI] LAME $LAME_VER (MP3)"
  tar xzf "$SRC/lame.tgz" -C "$W" && cd "$W/lame-$LAME_VER"
  ./configure --host=$HOST --prefix="$PREFIX" --enable-static --disable-shared --disable-frontend --disable-decoder --with-pic >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
  echo "::endgroup::"

  echo "::group::[$ABI] x264 (H.264 video)"
  cp -r "$SRC/x264" "$W/x264" && cd "$W/x264"
  ./configure --host=$HOST --cross-prefix="$TC/bin/llvm-" --prefix="$PREFIX" \
    --enable-static --enable-pic --disable-cli ${NOASM:+--disable-asm} >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
  echo "::endgroup::"

  echo "::group::[$ABI] FFmpeg $FF_VER"
  tar xJf "$SRC/ff.txz" -C "$W" && cd "$W/ffmpeg-$FF_VER"
  ./configure --prefix="$PREFIX" --enable-cross-compile --target-os=android --arch=$ARCH \
    --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --strip="$STRIP" --nm="$NM" \
    --pkg-config-flags="--static" --extra-cflags="-I$PREFIX/include -fPIC" --extra-ldflags="-L$PREFIX/lib" \
    --enable-gpl --enable-libx264 --enable-libmp3lame --enable-static --disable-shared \
    --disable-ffplay --disable-ffprobe --disable-doc --disable-debug --disable-vulkan \
    --disable-sdl2 --disable-xlib --disable-libxcb --disable-indevs --disable-outdevs --enable-pic \
    ${NOASM:+--disable-asm} | tail -n 30
  make -j"$JOBS" ffmpeg >/dev/null
  "$STRIP" ffmpeg -o "$OUT/$ABI/libffmpeg.so"
  echo "::endgroup::"
  cd "$SRC"; rm -rf "$W"
}

build_abi arm64-v8a aarch64-linux-android aarch64
build_abi x86_64 x86_64-linux-android x86_64

file "$OUT"/*/* 2>/dev/null || true
ls -laR "$OUT"
