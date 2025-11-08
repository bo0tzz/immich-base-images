# wasm-vips + ImageMagick Build Script

Single script to integrate ImageMagick 7.1.2-2 into wasm-vips via static linking.

## Quick Start

```bash
# Prerequisites: Emscripten SDK + wasm-vips with dependencies built
./build-imagemagick-wasm.sh
```

**Output:** `~/wasm-vips/build/target/lib/libvips.a` (~5MB) with ImageMagick support

## What It Does

1. **Builds ImageMagick 7.1.2-2** (revision 8289a3388 - matches Immich)
   - Standard WASM compilation (no SIDE_MODULE)
   - Static linking only (`--with-modules=no`)
   - JPEG detection via cache variable override

2. **Rebuilds libvips with static linking**
   - Detects ImageMagick via pkg-config
   - Links all format handlers into single library (`-Dmodules=disabled`)

## Verification

```bash
# Check ImageMagick detection
grep "magickcore found" ~/wasm-vips/build/deps/vips/_build/meson-logs/meson-log.txt

# Check symbols in libvips.a
strings ~/wasm-vips/build/target/lib/libvips.a | grep magickload
```

## Parity with Immich

✅ Same versions: ImageMagick 7.1.2-2, libheif 1.20.2, libjxl 0.11.1, libraw 0.22.0
✅ Same build flags and dependency chain
⚠️ Static linking (WASM requirement) vs dynamic modules (native)

**Result:** Full functional parity - all image formats work identically.

## Integration into wasm-vips

To add to main build.sh, insert after libraw build (~line 473):

```bash
[ -f "$TARGET/lib/pkgconfig/MagickCore.pc" ] || (
  stage "Compiling ImageMagick"
  mkdir $DEPS/imagemagick
  git clone https://github.com/ImageMagick/ImageMagick.git $DEPS/imagemagick
  cd $DEPS/imagemagick
  git reset --hard 8289a3388a085ad5ae81aa6812f21554bdfd54f2
  export ac_cv_lib_jpeg_jpeg_read_header=yes
  emconfigure ./configure --host=$CHOST --prefix=$TARGET --enable-static --disable-shared \
    --disable-openmp --without-threads --without-x --with-magick-plus-plus=no --with-modules=no \
    CPPFLAGS="$CPPFLAGS -DMAGICK_LIBRAW_VERSION_TAIL=202502"
  emmake make -j$(nproc)
  emmake make install-libLTLIBRARIES install-MagickCoreincHEADERS \
    install-MagickCoreincarchHEADERS install-MagickWandincHEADERS \
    install-pkgconfigDATA install-configlibDATA
)
```

Then add `-Dmodules=disabled` to libvips meson setup when ImageMagick is present.
