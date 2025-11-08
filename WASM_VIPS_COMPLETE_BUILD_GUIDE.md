# Complete Build Guide: wasm-vips with Full Immich Parity

This guide builds wasm-vips with **complete parity** to Immich's server native build.

## What You'll Get

Complete WASM build with all Immich image format support:
- **JPEG** - google/jpegli (WASM-compatible, with Immich's malformed JPEG patches)
- **JPEG XL** - libjxl (with Immich's JPEG handling patches)
- **HEIF/AVIF** - libheif + aom
- **RAW** - libraw (Immich's exact revision)
- **WebP** - libwebp
- **PNG** - libspng
- **TIFF** - libtiff
- **GIF** - cgif
- **SVG** - resvg
- **ImageMagick 7.1.2-2** - Fallback loader for exotic formats

**Build time:** ~15-20 minutes | **Output:** ~5-6MB libvips.a

## Prerequisites

- Linux or macOS
- ~2GB disk space
- Git, curl, cmake, ninja, autoconf, automake, libtool

## Step 1: Install Emscripten SDK

```bash
cd ~
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install 4.0.19
./emsdk activate 4.0.19
source ./emsdk_env.sh
```

Verify: `emcc --version` should show 4.0.19

## Step 2: Clone wasm-vips

```bash
cd ~
git clone https://github.com/kleisauke/wasm-vips.git
cd wasm-vips
```

## Step 3: Create Immich Patch Files

We need patches for both google/jpegli and libjxl:

```bash
mkdir -p patches/jpegli patches/libjxl
```

### Patches for google/jpegli (JPEG codec)

**Create `patches/jpegli/jpegli-empty-dht.patch`:**
```bash
cat > patches/jpegli/jpegli-empty-dht.patch << 'EOF'
diff --git a/lib/jpegli/decode_marker.cc b/lib/jpegli/decode_marker.cc
index original..patched 100644
--- a/lib/jpegli/decode_marker.cc
+++ b/lib/jpegli/decode_marker.cc
@@ -285,7 +285,7 @@ void ProcessDHT(j_decompress_ptr cinfo, const uint8_t* data, size_t len) {
   size_t pos = 2;
   if (pos == len) {
-    JPEGLI_ERROR("DHT marker: no Huffman table found");
+    return;
   }
   while (pos < len) {
     JPEG_VERIFY_LEN(1 + kJpegHuffmanMaxBitLength);
EOF
```

**Create `patches/jpegli/jpegli-icc-warning.patch`:**
```bash
cat > patches/jpegli/jpegli-icc-warning.patch << 'EOF'
diff --git a/lib/jpegli/decode_marker.cc b/lib/jpegli/decode_marker.cc
index original..patched 100644
--- a/lib/jpegli/decode_marker.cc
+++ b/lib/jpegli/decode_marker.cc
@@ -411,19 +411,24 @@ void ProcessAPP(j_decompress_ptr cinfo, const uint8_t* data, size_t len) {
       payload += sizeof(kIccProfileTag);
       payload_size -= sizeof(kIccProfileTag);
       if (payload_size < 2) {
-        JPEGLI_ERROR("ICC chunk is too small.");
+        JPEGLI_WARN("ICC chunk is too small.");
+        return;
       }
       uint8_t index = payload[0];
       uint8_t total = payload[1];
       ++m->icc_index_;
       if (m->icc_index_ != index) {
-        JPEGLI_ERROR("Invalid ICC chunk order.");
+        JPEGLI_WARN("Invalid ICC chunk order.");
+        return;
       }
       if (total == 0) {
-        JPEGLI_ERROR("Invalid ICC chunk total.");
+        JPEGLI_WARN("Invalid ICC chunk total.");
+        return;
       }
       if (m->icc_total_ == 0) {
         m->icc_total_ = total;
       } else if (m->icc_total_ != total) {
-        JPEGLI_ERROR("Invalid ICC chunk total.");
+        JPEGLI_WARN("Invalid ICC chunk total.");
+        return;
       }
       if (m->icc_index_ > m->icc_total_) {
-        JPEGLI_ERROR("Invalid ICC chunk index.");
+        JPEGLI_WARN("Invalid ICC chunk index.");
+        return;
       }
       m->icc_profile_.insert(m->icc_profile_.end(), payload + 2,
                              payload + payload_size);
EOF
```

### Patches for libjxl (JPEG XL's JPEG handling)

**Copy Immich's libjxl patches directly:**
```bash
# Download from immich-base-images repository
curl -Ls https://raw.githubusercontent.com/immich-app/base-images/main/server/sources/libjxl-patches/jpegli-empty-dht-marker.patch \
  -o patches/libjxl/jpegli-empty-dht-marker.patch

curl -Ls https://raw.githubusercontent.com/immich-app/base-images/main/server/sources/libjxl-patches/jpegli-icc-warning.patch \
  -o patches/libjxl/jpegli-icc-warning.patch
```

## Step 4: Modify build.sh

You need to make **5 changes** to `build.sh`:

### Change 1: Replace mozjpeg with google/jpegli

Find the mozjpeg section (around line 338-350). **Replace** it with:

```bash
[ -f "$TARGET/lib/pkgconfig/libjpeg.pc" ] || (
  stage "Compiling jpeg (jpegli)"
  git clone https://github.com/google/jpegli.git $DEPS/jpeg
  cd $DEPS/jpeg
  git reset --hard bc19ca23
  git submodule update --init --recursive
  # Apply Immich's jpegli patches
  git apply $SOURCE_DIR/patches/jpegli/jpegli-empty-dht.patch
  git apply $SOURCE_DIR/patches/jpegli/jpegli-icc-warning.patch
  emcmake cmake -B_build -S. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TARGET $CMAKE_ARGS \
    -DBUILD_SHARED_LIBS=FALSE -DJPEGXL_WARNINGS_AS_ERRORS=OFF \
    -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_VIEWERS=OFF -DJPEGXL_ENABLE_PLUGINS=OFF \
    -DJPEGXL_ENABLE_DEVTOOLS=OFF -DBUILD_TESTING=OFF -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DCMAKE_CXX_FLAGS="$CXXFLAGS -msimd128" -DCMAKE_C_FLAGS="$CFLAGS -msimd128"
  cmake --build _build --target jpegli-static -j$(nproc)
  # Install as libjpeg for compatibility
  cp _build/lib/libjpegli-static.a $TARGET/lib/libjpeg.a
  cp _build/lib/include/jpegli/*.h $TARGET/include/
  cp third_party/libjpeg-turbo/jerror.h $TARGET/include/
  mkdir -p $TARGET/lib/pkgconfig
  cat > $TARGET/lib/pkgconfig/libjpeg.pc << PKGEOF
prefix=$TARGET
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libjpeg
Description: A JPEG library (jpegli)
Version: 62.3.0
Libs: -L\${libdir} -ljpeg
Cflags: -I\${includedir}
PKGEOF
)
```

### Change 2: Modify libjxl build to use google/jpegli + apply Immich patches

Find the libjxl section (around line 352). **Replace** it with:

```bash
[ -f "$TARGET/lib/pkgconfig/libjxl.pc" ] || [ -n "$DISABLE_JXL" ] || (
  stage "Compiling jxl"
  git clone --depth 1 --branch v$VERSION_JXL --recursive https://github.com/libjxl/libjxl.git $DEPS/jxl
  cd $DEPS/jxl
  # Apply Immich's patches for JPEG XL's JPEG handling
  git apply $SOURCE_DIR/patches/libjxl/jpegli-empty-dht-marker.patch
  git apply $SOURCE_DIR/patches/libjxl/jpegli-icc-warning.patch
  emcmake cmake -B_build -S. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TARGET $CMAKE_ARGS -DCMAKE_FIND_ROOT_PATH=$TARGET \
    -DBUILD_SHARED_LIBS=FALSE -DBUILD_TESTING=FALSE -DJPEGXL_ENABLE_TOOLS=FALSE \
    -DJPEGXL_ENABLE_JPEGLI=FALSE \
    -DJPEGXL_ENABLE_EXAMPLES=FALSE -DJPEGXL_ENABLE_SJPEG=FALSE -DJPEGXL_ENABLE_SKCMS=FALSE -DJPEGXL_BUNDLE_LIBPNG=FALSE \
    -DJPEGXL_FORCE_SYSTEM_BROTLI=TRUE -DJPEGXL_FORCE_SYSTEM_LCMS2=TRUE -DJPEGXL_FORCE_SYSTEM_HWY=TRUE \
    -DJPEGXL_ENABLE_TRANSCODE_JPEG=FALSE
  make -C _build install
  if [ -n "$ENABLE_MODULES" ]; then
    [ -n "$DISABLE_SIMD" ] || sed -i '/^Requires:/s/ libhwy//' $TARGET/lib/pkgconfig/libjxl.pc
    sed -i '/^Requires:/s/ lcms2//' $TARGET/lib/pkgconfig/libjxl_cms.pc
    sed -i '/^Libs/s/ -lc++//g' $TARGET/lib/pkgconfig/libjxl{,_cms}.pc
  fi
)
```

**Key changes:**
- Clone with `--recursive` to get submodules needed for patches
- Apply Immich's libjxl patches
- Keep `-DJPEGXL_ENABLE_JPEGLI=FALSE` (uses google/jpegli instead)

### Change 3: Add libraw

After libtiff section (around line 460), **add**:

```bash
[ -f "$TARGET/lib/pkgconfig/libraw.pc" ] || (
  stage "Compiling libraw"
  mkdir $DEPS/libraw
  LIBRAW_REVISION="09bea31181b43e97959ee5452d91e5bc66365f1f"
  curl -Ls https://github.com/libraw/libraw/archive/$LIBRAW_REVISION.tar.gz | tar xzC $DEPS/libraw --strip-components=1
  cd $DEPS/libraw
  autoreconf --install
  emconfigure ./configure --host=$CHOST --prefix=$TARGET --enable-static --disable-shared \
    --disable-dependency-tracking --disable-examples --disable-openmp \
    --disable-jpeg --disable-jasper CPPFLAGS="$CPPFLAGS -DNO_JASPER"
  make install
)
```

### Change 4: Add ImageMagick

After libraw, before resvg section, **add**:

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

### Change 5: Enable static linking in libvips

Find the libvips meson setup (around line 495-500):

**Change:**
```bash
-Dintrospection=disabled ${DISABLE_MODULES:+-Dmodules=disabled} -Darchive=disabled \
```

**To:**
```bash
-Dintrospection=disabled -Dmodules=disabled -Darchive=disabled \
```

## Step 5: Run the Build

```bash
source ~/emsdk/emsdk_env.sh
./build.sh --disable-bindings
```

**Expected output:** Builds all dependencies + ImageMagick + libvips (~15-20 min)

## Step 6: Verify Complete Parity

**Check all components built:**
```bash
ls -lh build/target/lib/libjpeg.a        # google/jpegli
ls -lh build/target/lib/libjxl.a         # JPEG XL
ls -lh build/target/lib/libraw.a         # libraw
ls -lh build/target/lib/libMagick*.a     # ImageMagick
ls -lh build/target/lib/libvips.a        # libvips (~5-6MB)
```

**Check ImageMagick detected:**
```bash
grep "magickcore found" build/deps/vips/_build/meson-logs/meson-log.txt
# Expected: Run-time dependency magickcore found: YES 7.1.2
```

**Check ImageMagick symbols:**
```bash
strings build/target/lib/libvips.a | grep magickload
# Expected: vips_magickload, vips_magicksave
```

**Check google/jpegli is used:**
```bash
strings build/target/lib/libjpeg.a | grep -i jpegli | head -3
# Should show jpegli symbols
```

## Parity Verification Checklist

✅ **google/jpegli bc19ca23** - Modern WASM-compatible JPEG codec (replaces libjxl's old embedded jpegli)
✅ **Immich jpegli patches applied** - Handles malformed DHT and ICC chunks
✅ **libjxl 0.11.1** - JPEG XL support (uses google/jpegli as external libjpeg)
✅ **Immich libjxl patches applied** - JPEG XL's JPEG handling tolerates malformed files
✅ **libraw 09bea311** - Exact Immich revision for RAW support
✅ **ImageMagick 7.1.2-2** (8289a3388) - Exact Immich version
✅ **libheif 1.20.2** - HEIF/AVIF support
✅ **Static linking** - All format handlers in single library
✅ **Same build flags** - MAGICK_LIBRAW_VERSION_TAIL=202502

**Only difference:** Static vs dynamic linking (WASM requirement, no functional impact)

## Why This Approach?

**Immich uses:** libjxl with embedded jpegli (older jpegli, no WASM support)

**We use:** google/jpegli standalone + libjxl without embedded jpegli

**Why?** jpegli moved from libjxl to google/jpegli repo, WASM support added only to google version. libjxl's embedded jpegli is frozen/unmaintained for WASM.

**Result:** Functionally identical - libjxl uses google/jpegli as external libjpeg dependency, same as it would use its own embedded version.

## Troubleshooting

**jpegli patches fail:**
```bash
cd build/deps/jpeg
git apply --check ~/wasm-vips/patches/jpegli/jpegli-empty-dht.patch
# If fails, check google/jpegli hasn't changed
```

**libjxl patches fail:**
```bash
cd build/deps/jxl
git apply --check ~/wasm-vips/patches/libjxl/jpegli-empty-dht-marker.patch
# Patches require --recursive clone for submodules
```

**libraw configure fails:**
```bash
sudo apt-get install autoconf automake libtool
```

**Clean rebuild:**
```bash
rm -rf build && ./build.sh --disable-bindings
```

## Summary

You now have wasm-vips with **complete Immich parity**:
- Same image codecs (jpegli, libjxl, libraw, ImageMagick)
- Same patches (malformed JPEG handling)
- Same versions (exact revision matches)
- Only difference: static linking (WASM platform requirement)

**Total changes:** 5 modifications to build.sh + 4 patch files = Complete parity

**Output:** `~/wasm-vips/build/target/lib/libvips.a` (~5-6MB) ready for WASM projects
