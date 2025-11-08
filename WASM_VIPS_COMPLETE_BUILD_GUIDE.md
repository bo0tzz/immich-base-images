# Complete Guide: Building wasm-vips with Immich Parity

This guide builds a complete wasm-vips with **full parity** to Immich's server native build, including ImageMagick.

## What You'll Get

A complete WASM build with all image format support:
- **JPEG** (jpegli with Immich's malformed JPEG patches)
- **JPEG XL** (libjxl)
- **HEIF/AVIF** (libheif + aom)
- **WebP** (libwebp)
- **PNG** (libspng)
- **TIFF** (libtiff)
- **RAW** (libraw - Immich's specific revision)
- **GIF** (cgif)
- **SVG** (resvg)
- **ImageMagick** (7.1.2-2 - exact Immich version for fallback formats)

## Prerequisites

- Linux or macOS
- ~2GB disk space
- 10-20 minutes build time

## Step 1: Install Emscripten SDK

```bash
cd ~
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install 4.0.19
./emsdk activate 4.0.19
source ./emsdk_env.sh
```

Verify:
```bash
emcc --version  # Should show 4.0.19
```

## Step 2: Clone wasm-vips

```bash
cd ~
git clone https://github.com/kleisauke/wasm-vips.git
cd wasm-vips
```

## Step 3: Modify build.sh to Add ImageMagick

You need to make **2 changes** to `build.sh`:

### Change 1: Add ImageMagick Build (after libraw, before resvg)

Open `build.sh` and find the libraw section (ends around line 473) and the resvg section (starts around line 475). Between them, add:

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

### Change 2: Enable Static Linking in libvips (~line 537)

Find the libvips meson setup section (around line 535-537). Look for this line:

```bash
-Dintrospection=disabled ${DISABLE_MODULES:+-Dmodules=disabled} -Darchive=disabled \
```

Change it to:

```bash
-Dintrospection=disabled -Dmodules=disabled -Darchive=disabled \
```

(Remove the `${DISABLE_MODULES:+` conditional - we always want modules disabled)

## Step 4: Run the Build

```bash
source ~/emsdk/emsdk_env.sh  # Ensure Emscripten is active
./build.sh --disable-bindings
```

**Build time:** 10-20 minutes (first build downloads and compiles everything)

The build will:
1. Download and build 20+ image libraries (zlib, glib, lcms2, highway, brotli, jpegli, libjxl, etc.)
2. Download and build libheif, libraw, ImageMagick
3. Build libvips with all format handlers statically linked

## Step 5: Verify the Build

Check that ImageMagick was detected:

```bash
grep "magickcore found" build/deps/vips/_build/meson-logs/meson-log.txt
```

Expected output:
```
Run-time dependency magickcore found: YES 7.1.2
```

Check that ImageMagick symbols are in libvips:

```bash
strings build/target/lib/libvips.a | grep -i magickload
```

Expected output:
```
vips_magickload
vips_magickload_buffer
vips_magicksave
vips_magicksave_buffer
```

Check final library size:

```bash
ls -lh build/target/lib/libvips.a
```

Expected: ~5-6MB

## Step 6: Verify Parity with Immich

The build now has:

✅ **ImageMagick 7.1.2-2** (revision 8289a3388) - exact match
✅ **libheif 1.20.2** - HEIF/AVIF support
✅ **libjxl 0.11.1** - JPEG XL support
✅ **libraw 0.22.0-SNAPSHOT** - RAW format support
✅ **jpegli** with Immich's malformed JPEG patches
✅ **libvips 8.17.3** - image processing library
✅ All dependencies built with same flags as Immich

The only difference:
- **Immich native:** Dynamic module loading
- **WASM:** Static linking (required by WASM platform)
- **Impact:** None - functionality is identical

## Output Files

Your complete build is in:

```
~/wasm-vips/build/target/
├── lib/
│   ├── libvips.a          (~5MB - includes all format handlers)
│   ├── libvips-cpp.a      (~300KB - C++ bindings)
│   └── pkgconfig/         (all .pc files for dependencies)
├── include/
│   └── vips/              (libvips headers)
└── versions.json          (dependency versions)
```

## What If Something Goes Wrong?

**Build fails on ImageMagick:**
- Check Emscripten is activated: `emcc --version`
- Clean and retry: `rm -rf build && ./build.sh --disable-bindings`

**ImageMagick not detected by libvips:**
- Verify MagickCore.pc exists: `ls build/target/lib/pkgconfig/MagickCore.pc`
- Check meson logs: `cat build/deps/vips/_build/meson-logs/meson-log.txt | grep -i magick`

**Build succeeds but no ImageMagick symbols:**
- Verify you changed the meson line to `-Dmodules=disabled` (not conditional)
- Rebuild libvips: `rm -rf build/deps/vips/_build && ./build.sh --disable-bindings`

## Using This Build

The `libvips.a` library can be:
- Linked into Emscripten projects
- Used with wasm-vips JS bindings (if you remove `--disable-bindings`)
- Integrated into other WASM applications

For Immich specifically, this provides the same image processing capabilities as the native server build.

## Summary

You now have a complete wasm-vips build with:
- All image format loaders Immich uses
- ImageMagick for fallback/exotic formats
- Same versions as Immich's native build
- Full functional parity

Build time: ~15 minutes first run, ~3 minutes incremental (only rebuilds changed components)
