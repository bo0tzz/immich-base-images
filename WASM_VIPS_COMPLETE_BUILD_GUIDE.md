# Complete Build Guide: wasm-vips with Full Immich Parity

This guide builds wasm-vips with **complete parity** to Immich's server native build.

## What You'll Get

Complete WASM build with all Immich image format support:
- **JPEG** - google/jpegli (with Immich's malformed JPEG patches)
- **JPEG XL** - libjxl
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
- Git, curl, cmake, ninja

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

Create the patches directory and Immich's malformed JPEG handling patches:

```bash
mkdir -p patches/jpegli
```

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

## Step 4: Modify build.sh

You need to make **4 changes** to `build.sh`:

### Change 1: Replace mozjpeg with google/jpegli

Find the mozjpeg section (around line 300-320). Replace it with:

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

### Change 2: Add libraw

After libtiff section (around line 460), before resvg, add:

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

### Change 3: Add ImageMagick

After libraw (or after resvg if you skip libraw), before aom section, add:

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

### Change 4: Enable static linking in libvips

Find the libvips meson setup (around line 535-537):

**Change:**
```bash
-Dintrospection=disabled ${DISABLE_MODULES:+-Dmodules=disabled} -Darchive=disabled \
```

**To:**
```bash
-Dintrospection=disabled -Dmodules=disabled -Darchive=disabled \
```

### Change 5: Update version tracking

Around line 170-220, add to the version variables:

```bash
VERSION_JPEGLI=bc19ca23     # https://github.com/google/jpegli
VERSION_LIBRAW=0.22.0-SNAPSHOT # https://github.com/libraw/libraw
```

And update versions.json generation to include them.

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
# Expected: vips_magickload, vips_magicksave, etc.
```

**Check jpegli is used:**
```bash
strings build/target/lib/libjpeg.a | grep -i jpegli | head -3
# Should show jpegli symbols
```

## Parity Verification Checklist

✅ **google/jpegli bc19ca23** - Same JPEG encoder Immich uses (from libjxl upstream)
✅ **Immich patches applied** - jpegli-empty-dht, jpegli-icc-warning
✅ **libraw 09bea311** - Exact Immich revision for RAW support
✅ **ImageMagick 7.1.2-2** (8289a3388) - Exact Immich version
✅ **libheif 1.20.2** - HEIF/AVIF support
✅ **libjxl 0.11.1** - JPEG XL support
✅ **Static linking** - All format handlers in single library
✅ **Same build flags** - MAGICK_LIBRAW_VERSION_TAIL=202502

**Only difference:** Static vs dynamic linking (WASM requirement, no functional impact)

## Output

Your complete build is at:
```
~/wasm-vips/build/target/
├── lib/
│   ├── libvips.a          (~5-6MB with all format handlers)
│   ├── libjpeg.a          (google/jpegli)
│   ├── libraw.a           (RAW support)
│   ├── libMagickCore-7.Q16HDRI.a
│   └── libMagickWand-7.Q16HDRI.a
└── include/vips/
```

## Troubleshooting

**jpegli patches fail to apply:**
- Verify patch files created correctly in patches/jpegli/
- Check line endings (should be Unix LF, not Windows CRLF)

**libraw configure fails:**
- Ensure autoreconf is installed: `apt-get install autoconf automake libtool`

**ImageMagick not detected:**
- Check MagickCore.pc exists: `ls build/target/lib/pkgconfig/MagickCore.pc`
- Verify cache variable set: `export ac_cv_lib_jpeg_jpeg_read_header=yes`

**Build fails on clean:**
```bash
rm -rf build
./build.sh --disable-bindings
```

## What Makes This Different from Standard wasm-vips

| Component | Standard wasm-vips | This Build (Immich Parity) |
|-----------|-------------------|---------------------------|
| JPEG | mozjpeg | google/jpegli + Immich patches |
| RAW | ❌ None | ✅ libraw (Immich revision) |
| ImageMagick | ❌ None | ✅ 7.1.2-2 (exact Immich version) |
| Linking | Dynamic modules | Static linking (WASM requirement) |
| Malformed JPEG | Standard handling | Immich patches (tolerant) |

## Summary

You now have a complete wasm-vips build with full Immich parity. Every image format, every patch, same library versions. The only difference is static vs dynamic linking (required by WASM platform), which has zero functional impact.

**Total changes to wasm-vips:** 5 modifications to build.sh + 2 patch files = Complete parity
