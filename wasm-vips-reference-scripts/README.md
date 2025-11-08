# Reference Scripts (Supplementary)

**Note:** For complete build instructions, see [../WASM_VIPS_COMPLETE_BUILD_GUIDE.md](../WASM_VIPS_COMPLETE_BUILD_GUIDE.md)

This directory contains reference implementations and code snippets for integrating ImageMagick into wasm-vips.

## What's Here

### build-imagemagick-wasm.sh

Test script that builds ImageMagick + libvips in isolation.

**Use case:** Testing ImageMagick build without modifying wasm-vips

**Limitation:** Inefficient - requires wasm-vips already built, then rebuilds libvips

**For production:** Follow the complete guide instead, which modifies wasm-vips build.sh directly

## Integration Code (Copy-Paste Reference)

The code snippets below are what you add to wasm-vips/build.sh. See complete guide for context.

### ImageMagick Build Section

Add after libraw (~line 473):

```bash
[ -f "$TARGET/lib/pkgconfig/MagickCore.pc" ] || (
  stage "Compiling ImageMagick"
  mkdir $DEPS/imagemagick
  git clone https://github.com/ImageMagick/ImageMagick.git $DEPS/imagemagick
  cd $DEPS/imagemagick
  git reset --hard 8289a3388a085ad5ae81aa6812f21554bdfd54f2
  export ac_cv_lib_jpeg_jpeg_read_header=yes
  emconfigure ./configure --host=$CHOST --prefix=$TARGET \
    --enable-static --disable-shared --disable-openmp \
    --without-threads --without-x --with-magick-plus-plus=no \
    --with-modules=no CPPFLAGS="$CPPFLAGS -DMAGICK_LIBRAW_VERSION_TAIL=202502"
  emmake make -j$(nproc)
  emmake make install-libLTLIBRARIES install-MagickCoreincHEADERS \
    install-MagickCoreincarchHEADERS install-MagickWandincHEADERS \
    install-pkgconfigDATA install-configlibDATA
)
```

### libvips Static Linking Change

Around line 537, change:

```bash
-Dintrospection=disabled ${DISABLE_MODULES:+-Dmodules=disabled} -Darchive=disabled \
```

To:

```bash
-Dintrospection=disabled -Dmodules=disabled -Darchive=disabled \
```

## Why Static Linking?

WASM dynamic modules (SIDE_MODULE) require:
- Minimal libc (many functions unavailable)
- All code compiled with `-sSIDE_MODULE=2`
- ImageMagick uses functions not available in SIDE_MODULE environment

Static linking bypasses all these issues - libvips and ImageMagick compile normally and link into a single library.

## Verification Commands

After building, verify ImageMagick integration:

```bash
# Check meson detected ImageMagick
grep "magickcore found" ~/wasm-vips/build/deps/vips/_build/meson-logs/meson-log.txt

# Check symbols present
strings ~/wasm-vips/build/target/lib/libvips.a | grep magickload
```

Expected: `vips_magickload`, `vips_magicksave`, etc.
