#!/usr/bin/env bash
# Builds the helper programs the Grabby phone app needs, for 64-bit Android phones (arm64-v8a):
#   qjs    - QuickJS-NG JavaScript engine (YouTube needs one to unlock its videos)
#   ffmpeg - joins HD video + audio, makes MP3/GIF/ringtones, Messenger-size videos
# Output: <out>/arm64-v8a/libqjs.so and libffmpeg.so  (named lib*.so so Android installs them as runnable files)
set -euo pipefail
OUT=$(realpath -m "${1:-natives}")
ABI=arm64-v8a; HOST=aarch64-linux-android; API=24
QJS_VER=v0.18.0
FF_VER=7.1.1
LAME_VER=3.100
NDK=${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-}}
[ -d "$NDK" ] || { echo "Android NDK not found"; exit 1; }
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64
export CC=$TC/bin/${HOST}${API}-clang CXX=$TC/bin/${HOST}${API}-clang++
export AR=$TC/bin/llvm-ar RANLIB=$TC/bin/llvm-ranlib STRIP=$TC/bin/llvm-strip NM=$TC/bin/llvm-nm
JOBS=$(nproc)
WORK=$(mktemp -d); PREFIX=$WORK/prefix
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
mkdir -p "$OUT/$ABI" "$PREFIX"
cd "$WORK"

echo "::group::QuickJS-NG $QJS_VER"
git clone -q --depth 1 --branch "$QJS_VER" https://github.com/quickjs-ng/quickjs.git qjs
cmake -S qjs -B qjs/build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=$ABI -DANDROID_PLATFORM=android-$API -DBUILD_SHARED_LIBS=OFF >/dev/null
cmake --build qjs/build --target qjs_exe -j"$JOBS" || cmake --build qjs/build --target qjs -j"$JOBS"
QJS_BIN=$(find qjs/build -maxdepth 2 -type f -name qjs | head -1)
"$STRIP" "$QJS_BIN" -o "$OUT/$ABI/libqjs.so"
echo "::endgroup::"

echo "::group::LAME $LAME_VER (MP3)"
curl -fsSL "https://downloads.sourceforge.net/project/lame/lame/$LAME_VER/lame-$LAME_VER.tar.gz" -o lame.tgz
tar xzf lame.tgz && cd "lame-$LAME_VER"
./configure --host=$HOST --prefix="$PREFIX" --enable-static --disable-shared --disable-frontend --disable-decoder --with-pic >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
cd "$WORK"
echo "::endgroup::"

echo "::group::x264 (H.264 video)"
git clone -q --depth 1 https://code.videolan.org/videolan/x264.git x264
cd x264
./configure --host=$HOST --cross-prefix="$TC/bin/llvm-" --prefix="$PREFIX" \
  --enable-static --enable-pic --disable-cli >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null
cd "$WORK"
echo "::endgroup::"

echo "::group::FFmpeg $FF_VER"
curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$FF_VER.tar.xz" -o ff.txz
tar xJf ff.txz && cd "ffmpeg-$FF_VER"
./configure --prefix="$PREFIX" --enable-cross-compile --target-os=android --arch=aarch64 \
  --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --strip="$STRIP" --nm="$NM" \
  --pkg-config-flags="--static" --extra-cflags="-I$PREFIX/include -fPIC" --extra-ldflags="-L$PREFIX/lib" \
  --enable-gpl --enable-libx264 --enable-libmp3lame --enable-static --disable-shared \
  --disable-ffplay --disable-ffprobe --disable-doc --disable-debug --disable-vulkan \
  --disable-sdl2 --disable-xlib --disable-libxcb --disable-indevs --disable-outdevs --enable-pic
make -j"$JOBS" ffmpeg >/dev/null
"$STRIP" ffmpeg -o "$OUT/$ABI/libffmpeg.so"
echo "::endgroup::"

file "$OUT/$ABI/"* 2>/dev/null || true
ls -la "$OUT/$ABI"
