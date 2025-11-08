#!/bin/bash
set -e

# Full build script for ImageMagick + libvips WASM integration
# Assumes wasm-vips dependencies are already built (jpegli, libraw, libheif, libjxl, etc.)

echo "======================================"
echo "ImageMagick + libvips WASM Build"
echo "======================================"

# Check prerequisites
if [ ! -f "$HOME/emsdk/emsdk_env.sh" ]; then
  echo "ERROR: Emscripten SDK not found at $HOME/emsdk"
  exit 1
fi

if [ ! -d "$HOME/wasm-vips" ]; then
  echo "ERROR: wasm-vips repository not found at $HOME/wasm-vips"
  exit 1
fi

# Source Emscripten environment
source "$HOME/emsdk/emsdk_env.sh"

TARGET="$HOME/wasm-vips/build/target"
DEPS="$HOME/wasm-vips/build/deps"

# Check that dependencies are built
if [ ! -f "$TARGET/lib/pkgconfig/libjpeg.pc" ]; then
  echo "ERROR: wasm-vips dependencies not built. Run wasm-vips build.sh first."
  exit 1
fi

# ============================================
# Step 1: Build ImageMagick
# ============================================

if [ -f "$TARGET/lib/pkgconfig/MagickCore.pc" ]; then
  echo ""
  echo "ImageMagick already built, skipping..."
else
  echo ""
  echo "======================================"
  echo "Step 1/2: Building ImageMagick 7.1.2-2"
  echo "======================================"

  cd "$HOME"
  if [ ! -d "$HOME/ImageMagick" ]; then
    git clone https://github.com/ImageMagick/ImageMagick.git
    cd ImageMagick
    git reset --hard 8289a3388a085ad5ae81aa6812f21554bdfd54f2
  else
    cd ImageMagick
    make clean || true
    rm -rf config.cache
  fi

  # Configure flags matching wasm-vips style
  COMMON_FLAGS="-O3 -pthread"
  export CFLAGS="$COMMON_FLAGS -fvisibility=hidden"
  export CXXFLAGS="$CFLAGS"
  export CPPFLAGS="-DMAGICK_LIBRAW_VERSION_TAIL=202502 -I$TARGET/include"
  export LDFLAGS="$COMMON_FLAGS -L$TARGET/lib -sAUTO_JS_LIBRARIES=0 -sAUTO_NATIVE_LIBRARIES=0"

  # Force JPEG support via cache variable (cross-compilation workaround)
  export ac_cv_lib_jpeg_jpeg_read_header=yes

  emconfigure ./configure \
    --prefix="$TARGET" \
    --host=wasm32-unknown-linux \
    --enable-static \
    --disable-shared \
    --disable-openmp \
    --without-threads \
    --without-x \
    --with-magick-plus-plus=no \
    --with-modules=no

  emmake make -j$(nproc)

  # Install libraries only (skip utilities to avoid jpegli linking issues)
  emmake make install-libLTLIBRARIES install-MagickCoreincHEADERS \
    install-MagickCoreincarchHEADERS install-MagickWandincHEADERS \
    install-pkgconfigDATA install-configlibDATA

  echo "✅ ImageMagick built successfully"
  ls -lh "$TARGET/lib/libMagickCore-7.Q16HDRI.a"
  ls -lh "$TARGET/lib/libMagickWand-7.Q16HDRI.a"
fi

# ============================================
# Step 2: Build libvips with static linking
# ============================================

echo ""
echo "======================================"
echo "Step 2/2: Building libvips with static linking"
echo "======================================"

cd "$DEPS/vips" || {
  echo "ERROR: libvips source not found at $DEPS/vips"
  echo "Run wasm-vips build.sh to download libvips first"
  exit 1
}

rm -rf _build

export PKG_CONFIG_PATH="$TARGET/lib/pkgconfig"
export EM_PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
MESON_ARGS="--cross-file=$HOME/wasm-vips/build/emscripten-cross.ini"

meson setup _build \
  --prefix="$TARGET" \
  $MESON_ARGS \
  --default-library=static \
  --buildtype=release \
  -Ddeprecated=false \
  -Dexamples=false \
  -Dcplusplus=true \
  -Dauto_features=enabled \
  -Dintrospection=disabled \
  -Dmodules=disabled \
  -Darchive=disabled \
  -Dcfitsio=disabled \
  -Dfftw=disabled \
  -Dfontconfig=disabled \
  -Dmatio=disabled \
  -Dnifti=disabled \
  -Dopenexr=disabled \
  -Dopenjpeg=disabled \
  -Dopenslide=disabled \
  -Dpangocairo=disabled \
  -Dpdfium=disabled \
  -Dpoppler=disabled \
  -Dresvg=disabled \
  -Drsvg=disabled

ninja -C _build
meson install -C _build --tag runtime,devel

echo ""
echo "======================================"
echo "✅ Build Complete!"
echo "======================================"
echo ""
ls -lh "$TARGET/lib/libvips.a"

# Verify ImageMagick integration
echo ""
echo "Verification:"
if grep -q "magickcore found: YES" _build/meson-logs/meson-log.txt; then
  echo "✅ ImageMagick detected by meson"
  grep "magickcore found" _build/meson-logs/meson-log.txt | head -1
else
  echo "⚠️  ImageMagick not detected by meson"
fi

if strings "$TARGET/lib/libvips.a" | grep -q "vips_magickload"; then
  echo "✅ ImageMagick symbols present in libvips.a"
else
  echo "⚠️  ImageMagick symbols not found in libvips.a"
fi

echo ""
echo "Output: $TARGET/lib/libvips.a"
