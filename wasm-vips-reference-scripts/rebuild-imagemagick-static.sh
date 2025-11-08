#!/bin/bash
set -e

source /home/user/emsdk/emsdk_env.sh

cd /home/user/ImageMagick

# Clean previous build
make clean || true
rm -rf config.cache

# Use wasm-vips flags WITHOUT SIDE_MODULE
COMMON_FLAGS="-O3 -pthread"
export CFLAGS="$COMMON_FLAGS -fvisibility=hidden"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="-DMAGICK_LIBRAW_VERSION_TAIL=202502 -I/home/user/wasm-vips/build/target/include"
export LDFLAGS="$COMMON_FLAGS -L/home/user/wasm-vips/build/target/lib -sAUTO_JS_LIBRARIES=0 -sAUTO_NATIVE_LIBRARIES=0"

# Force JPEG support via cache variable
export ac_cv_lib_jpeg_jpeg_read_header=yes

echo "=========================================="
echo "Configuring ImageMagick for static linking (no SIDE_MODULE)..."
echo "CFLAGS: $CFLAGS"
echo "LDFLAGS: $LDFLAGS"
echo "=========================================="

emconfigure ./configure \
  --prefix=/home/user/wasm-vips/build/target \
  --host=wasm32-unknown-linux \
  --enable-static \
  --disable-shared \
  --disable-openmp \
  --without-threads \
  --without-x \
  --with-magick-plus-plus=no \
  --with-modules=no

echo "=========================================="
echo "Building ImageMagick libraries..."
echo "=========================================="

emmake make -j$(nproc)

echo "=========================================="
echo "Installing ImageMagick libraries..."
echo "=========================================="

emmake make install-libLTLIBRARIES install-MagickCoreincHEADERS \
  install-MagickCoreincarchHEADERS install-MagickWandincHEADERS \
  install-pkgconfigDATA install-configlibDATA

echo "=========================================="
echo "ImageMagick static build complete!"
echo "=========================================="

ls -lh /home/user/wasm-vips/build/target/lib/libMagickCore-7.Q16HDRI.a
ls -lh /home/user/wasm-vips/build/target/lib/libMagickWand-7.Q16HDRI.a
