# ImageMagick Integration for wasm-vips

This shows how to add ImageMagick support to wasm-vips. **This requires modifying wasm-vips itself** - there's no way around it since wasm-vips build.sh needs to build ImageMagick before libvips.

## The Actual Solution

Modify `/path/to/wasm-vips/build.sh`:

**1. Add ImageMagick build section** after libraw (~line 473):

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

**2. Change libvips section** (~line 535) to use static linking:

```bash
# Change this line:
-Dintrospection=disabled ${DISABLE_MODULES:+-Dmodules=disabled} -Darchive=disabled \

# To this:
-Dintrospection=disabled -Dmodules=disabled -Darchive=disabled \
```

**3. Run the modified build:**

```bash
cd /path/to/wasm-vips
./build.sh --disable-bindings
```

Done! Everything builds in one pass.

## Why This Is The Only Way

wasm-vips build.sh:
1. Builds 20+ image libraries in dependency order
2. Builds libvips last (which needs to know about ImageMagick)

You can't "add on" ImageMagick after because:
- libvips needs to be built with `-Dmodules=disabled` to include ImageMagick
- ImageMagick must be built before libvips

## The Reference Script (For Testing Only)

`build-imagemagick-wasm.sh` is provided for testing the ImageMagick build in isolation, but it's inefficient because it:
1. Assumes you already ran wasm-vips build.sh (which built libvips)
2. Builds ImageMagick
3. **Rebuilds libvips** (wasting the first build)

Use it only if you want to test ImageMagick integration without modifying wasm-vips.

## Verification

After building:

```bash
# Check detection
grep "magickcore found" build/deps/vips/_build/meson-logs/meson-log.txt

# Check symbols
strings build/target/lib/libvips.a | grep magickload
```

## Summary

✅ **For production:** Modify wasm-vips build.sh as shown above
⚠️ **For testing only:** Use build-imagemagick-wasm.sh (requires wasm-vips already built)

The real solution is integrating into wasm-vips build.sh. This repo shows exactly what to add.
