# wasm-vips + ImageMagick - Complete Build Guide

This is a **reference implementation** showing how to add ImageMagick to wasm-vips. It requires wasm-vips base dependencies to be built first.

## Complete Build Process

### Step 1: Build wasm-vips base dependencies

```bash
cd ~/wasm-vips
./build.sh --disable-bindings
```

This builds all the image libraries:
- zlib-ng, libffi, glib, expat, exif, lcms2
- highway, brotli, jpegli, libjxl (JPEG XL)
- spng (PNG), imagequant, cgif, webp, tiff
- libraw, resvg (SVG), aom, libheif (HEIF/AVIF)
- **libvips** (with dynamic modules)

**Time:** ~10-15 minutes

### Step 2: Add ImageMagick integration

```bash
cd ~/immich-base-images/wasm-vips-reference-scripts
./build-imagemagick-wasm.sh
```

This:
1. Builds ImageMagick 7.1.2-2 (4.6MB + 1.5MB libraries)
2. Rebuilds libvips with static linking to include ImageMagick

**Time:** ~3-5 minutes

**Final output:** `~/wasm-vips/build/target/lib/libvips.a` (~5MB) with ImageMagick support

## What build-imagemagick-wasm.sh Does

**Assumes already built:**
- jpegli (JPEG), libjxl (JPEG XL), libheif (HEIF/AVIF)
- libraw (RAW), libwebp (WebP), libspng (PNG), libtiff (TIFF)
- All other wasm-vips dependencies from Step 1

**Builds:**
- ImageMagick 7.1.2-2 libraries (libMagickCore, libMagickWand)
- libvips with static linking (`-Dmodules=disabled`)

## Verification

```bash
# Check ImageMagick detection
grep "magickcore found" ~/wasm-vips/build/deps/vips/_build/meson-logs/meson-log.txt

# Check symbols
strings ~/wasm-vips/build/target/lib/libvips.a | grep magickload
```

## One-Line Alternative

If you want the absolute simplest approach:

```bash
cd ~/wasm-vips && ./build.sh --disable-bindings && \
cd ~/immich-base-images/wasm-vips-reference-scripts && ./build-imagemagick-wasm.sh
```

## Why Two Steps?

- **Step 1 (wasm-vips build.sh):** Builds 20+ image libraries with complex interdependencies
- **Step 2 (this script):** Adds ImageMagick, which wasm-vips doesn't include by default

This is a reference showing how to extend wasm-vips builds. For production, you'd integrate the ImageMagick section directly into wasm-vips build.sh (see LIBVIPS_IMAGEMAGICK_WASM_INVESTIGATION.md for integration code).

## Parity with Immich

✅ ImageMagick 7.1.2-2 (revision 8289a3388)
✅ All image formats: JPEG, JXL, HEIF, WebP, PNG, TIFF, RAW, GIF
✅ Same dependency chain as Immich server build
⚠️ Static linking (WASM requirement) vs dynamic (native) - no functional difference
