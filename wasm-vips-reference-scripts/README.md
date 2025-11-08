# wasm-vips + ImageMagick Reference Build Scripts

These scripts demonstrate the successful integration of ImageMagick into wasm-vips via static linking, achieving full parity with Immich's server build.

## Overview

Two-step build process:
1. **rebuild-imagemagick-static.sh** - Builds ImageMagick 7.1.2-2 for WASM
2. **rebuild-vips-static.sh** - Builds libvips 8.17.3 with static linking

## Prerequisites

- Emscripten SDK 4.0.19+ installed and activated
- wasm-vips repository cloned to `/home/user/wasm-vips`
- wasm-vips dependencies built (jpegli, libraw, libheif, libjxl, etc.)

## Usage

### Step 1: Build ImageMagick

```bash
cd /home/user/wasm-vips-reference-scripts
./rebuild-imagemagick-static.sh
```

**What it does:**
- Clones ImageMagick 7.1.2-2 (revision 8289a3388a085ad5ae81aa6812f21554bdfd54f2)
- Configures with WASM-compatible flags (NO SIDE_MODULE)
- Uses cache variable override for JPEG detection: `ac_cv_lib_jpeg_jpeg_read_header=yes`
- Builds with `-O3 -pthread -fvisibility=hidden`
- Installs libraries and headers to `/home/user/wasm-vips/build/target/`

**Output:**
- `libMagickCore-7.Q16HDRI.a` (~4.6MB)
- `libMagickWand-7.Q16HDRI.a` (~1.5MB)
- Headers and pkg-config files

### Step 2: Build libvips with Static Linking

```bash
cd /home/user/wasm-vips-reference-scripts
./rebuild-vips-static.sh
```

**What it does:**
- Configures libvips with `-Dmodules=disabled` (static linking)
- Meson detects ImageMagick via pkg-config
- Builds libvips with all format handlers statically linked
- Installs to `/home/user/wasm-vips/build/target/`

**Output:**
- `libvips.a` (~5.0MB) - includes ImageMagick, jpegli, libraw, libheif, libjxl, etc.
- `libvips-cpp.a` (~333KB)

## Verification

Check that ImageMagick is integrated:

```bash
# Check meson detected ImageMagick
grep "magickcore found" /home/user/wasm-vips/build/deps/vips/_build/meson-logs/meson-log.txt
# Should show: Run-time dependency magickcore found: YES 7.1.2

# Check ImageMagick symbols in libvips.a
strings /home/user/wasm-vips/build/target/lib/libvips.a | grep -i "magickload"
# Should show: vips_magickload, vips_magickload_buffer, vips_magicksave, etc.
```

## Key Differences from Dynamic Module Build

| Aspect | Dynamic Modules | Static Linking (This Approach) |
|--------|----------------|--------------------------------|
| libvips meson flag | `-Dmodules=enabled` | `-Dmodules=disabled` |
| ImageMagick CFLAGS | `-sSIDE_MODULE=2` | Standard WASM flags |
| Output | Multiple .wasm files | Single libvips.a |
| Bundle size | Smaller initial, lazy-load | Larger initial (~5MB) |
| Compatibility | SIDE_MODULE issues | No issues |

## Parity with Immich Server Build

✅ **Matching Components:**
- ImageMagick: 7.1.2-2 (exact revision match)
- libheif: 1.20.2
- libjxl: 0.11.1
- libraw: 0.22.0-SNAPSHOT
- libvips: 8.17.3

✅ **Functional Capabilities:**
- All image formats supported (JPEG, JXL, HEIF, WebP, PNG, TIFF, RAW, GIF)
- ImageMagick fallback loader available
- Same dependency chain

⚠️ **Architectural Difference (WASM Constraint):**
- Immich uses dynamic modules (`--with-modules`)
- WASM uses static linking (`--with-modules=no`)
- This does NOT affect functionality

## Integration into wasm-vips build.sh

To integrate into the main wasm-vips build process, add the ImageMagick build section between `libraw` and `resvg` in `build.sh`:

```bash
[ -f "$TARGET/lib/pkgconfig/MagickCore.pc" ] || (
  stage "Compiling ImageMagick"
  mkdir $DEPS/imagemagick
  git clone https://github.com/ImageMagick/ImageMagick.git $DEPS/imagemagick
  cd $DEPS/imagemagick
  git reset --hard 8289a3388a085ad5ae81aa6812f21554bdfd54f2

  export ac_cv_lib_jpeg_jpeg_read_header=yes
  export MAGICK_CPPFLAGS="-DMAGICK_LIBRAW_VERSION_TAIL=202502 -I$TARGET/include"

  emconfigure ./configure --host=$CHOST --prefix=$TARGET \
    --enable-static --disable-shared --disable-openmp \
    --without-threads --without-x --with-magick-plus-plus=no \
    --with-modules=no CPPFLAGS="$CPPFLAGS $MAGICK_CPPFLAGS"

  emmake make -j$(nproc)
  emmake make install-libLTLIBRARIES install-MagickCoreincHEADERS \
    install-MagickCoreincarchHEADERS install-MagickWandincHEADERS \
    install-pkgconfigDATA install-configlibDATA
)
```

Then ensure libvips is built with `--disable-modules` flag when ImageMagick is present.

## References

- Full investigation: `/home/user/immich-base-images/LIBVIPS_IMAGEMAGICK_WASM_INVESTIGATION.md`
- Immich server build: `/home/user/immich-base-images/server/sources/imagemagick.sh`
- wasm-vips: https://github.com/kleisauke/wasm-vips

## Build Time

- ImageMagick: ~2-3 minutes
- libvips: ~1-2 minutes
- Total: ~3-5 minutes (on modern hardware with `nproc` parallel jobs)
