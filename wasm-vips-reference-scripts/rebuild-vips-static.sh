#!/bin/bash
set -e

source /home/user/emsdk/emsdk_env.sh

cd /home/user/wasm-vips/build/deps/vips
rm -rf _build

TARGET=/home/user/wasm-vips/build/target
export PKG_CONFIG_PATH="$TARGET/lib/pkgconfig"
export EM_PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
MESON_ARGS="--cross-file=/home/user/wasm-vips/build/emscripten-cross.ini"

echo "=========================================="
echo "Configuring libvips with static linking (modules disabled)..."
echo "=========================================="

meson setup _build \
  --prefix=$TARGET \
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

echo "=========================================="
echo "Building libvips..."
echo "=========================================="

ninja -C _build

echo "=========================================="
echo "Installing libvips..."
echo "=========================================="

meson install -C _build --tag runtime,devel

echo "=========================================="
echo "Libvips static build complete!"
echo "=========================================="

ls -lh $TARGET/lib/libvips.a
