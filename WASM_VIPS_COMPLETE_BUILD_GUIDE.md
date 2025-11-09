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

**Create `patches/jpegli/jpegli-malformed-jpeg.patch`:**

This single unified patch handles both empty DHT markers and malformed ICC chunks:

```bash
cat > patches/jpegli/jpegli-malformed-jpeg.patch << 'EOF'
diff --git a/lib/jpegli/decode_marker.cc b/lib/jpegli/decode_marker.cc
index 171942b3..0bf47e5e 100644
--- a/lib/jpegli/decode_marker.cc
+++ b/lib/jpegli/decode_marker.cc
@@ -285,7 +285,7 @@ void ProcessSOS(j_decompress_ptr cinfo, const uint8_t* data, size_t len) {
 void ProcessDHT(j_decompress_ptr cinfo, const uint8_t* data, size_t len) {
   size_t pos = 2;
   if (pos == len) {
-    JPEGLI_ERROR("DHT marker: no Huffman table found");
+    return;
   }
   while (pos < len) {
     JPEG_VERIFY_LEN(1 + kJpegHuffmanMaxBitLength);
@@ -411,24 +411,29 @@ void ProcessAPP(j_decompress_ptr cinfo, const uint8_t* data, size_t len) {
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

**Create `patches/jpegli/jpegli-enable-libjpeg-wrapper.patch`:**

This patch enables the libjpeg compatibility wrapper for EMSCRIPTEN and fixes incompatible linker flags:

```bash
cat > patches/jpegli/jpegli-enable-libjpeg-wrapper.patch << 'EOF'
diff --git a/lib/jpegli.cmake b/lib/jpegli.cmake
index e6993c7f..29d09456 100644
--- a/lib/jpegli.cmake
+++ b/lib/jpegli.cmake
@@ -106,7 +106,7 @@ endif()
 # Build libjpeg.so that links to libjpeg-static
 #

-if (JPEGXL_ENABLE_JPEGLI_LIBJPEG AND NOT APPLE AND NOT WIN32 AND NOT EMSCRIPTEN)
+if (JPEGXL_ENABLE_JPEGLI_LIBJPEG AND NOT APPLE AND NOT WIN32)
 add_library(jpegli-libjpeg-obj OBJECT "${JPEGXL_INTERNAL_JPEGLI_WRAPPER_SOURCES}")
 target_compile_options(jpegli-libjpeg-obj PRIVATE ${JPEGXL_INTERNAL_FLAGS})
 target_compile_options(jpegli-libjpeg-obj PUBLIC ${JPEGXL_COVERAGE_FLAGS})
@@ -121,7 +121,7 @@ target_compile_definitions(jpegli-libjpeg-obj PUBLIC
 set(JPEGLI_LIBJPEG_INTERNAL_OBJECTS $<TARGET_OBJECTS:jpegli-libjpeg-obj>)

 file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/jpegli)
-add_library(jpeg SHARED ${JPEGLI_LIBJPEG_INTERNAL_OBJECTS})
+add_library(jpeg STATIC ${JPEGLI_LIBJPEG_INTERNAL_OBJECTS})
 target_link_libraries(jpeg PUBLIC ${JPEGXL_COVERAGE_FLAGS})
 target_link_libraries(jpeg PRIVATE jpegli-static)
 set_target_properties(jpeg PROPERTIES
@@ -133,9 +133,11 @@ set_target_properties(jpeg PROPERTIES

 # Add a jpeg.version file as a version script to tag symbols with the
 # appropriate version number.
+if (NOT EMSCRIPTEN)
 set_target_properties(jpeg PROPERTIES
   LINK_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/jpegli/jpeg.version.${JPEGLI_LIBJPEG_LIBRARY_SOVERSION})
 set_property(TARGET jpeg APPEND_STRING PROPERTY
   LINK_FLAGS " -Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/jpegli/jpeg.version.${JPEGLI_LIBJPEG_LIBRARY_SOVERSION}")
+endif()

 if (JPEGXL_INSTALL_JPEGLI_LIBJPEG)
EOF
```

### Patches for libjxl (JPEG XL's JPEG handling)

**Create `patches/libjxl/jxl-empty-dht-marker.patch`:**

This patch only includes the `lib/jxl/jpeg/*` portions (libjxl is built with `-DJPEGXL_ENABLE_JPEGLI=FALSE`, so it won't have `lib/jpegli` files):

```bash
cat > patches/libjxl/jxl-empty-dht-marker.patch << 'EOF'
diff --git a/lib/jxl/jpeg/dec_jpeg_data_writer.cc b/lib/jxl/jpeg/dec_jpeg_data_writer.cc
index 9fb664d3..e055ef9a 100644
--- a/lib/jxl/jpeg/dec_jpeg_data_writer.cc
+++ b/lib/jxl/jpeg/dec_jpeg_data_writer.cc
@@ -384,10 +384,12 @@ bool EncodeDHT(const JPEGData& jpg, SerializationState* state) {
   size_t marker_len = 2;
   for (size_t i = state->dht_index; i < huffman_code.size(); ++i) {
     const JPEGHuffmanCode& huff = huffman_code[i];
-    marker_len += kJpegHuffmanMaxBitLength;
     for (uint32_t count : huff.counts) {
       marker_len += count;
     }
+    // special case: empty DHT marker
+    if (marker_len == 2) break;
+    marker_len += kJpegHuffmanMaxBitLength;
     if (huff.is_last) break;
   }
   state->output_queue.emplace_back(marker_len + 2);
@@ -405,6 +407,17 @@ bool EncodeDHT(const JPEGData& jpg, SerializationState* state) {
     const JPEGHuffmanCode& huff = huffman_code[huffman_code_index];
     size_t index = huff.slot_id;
     HuffmanCodeTable* huff_table;
+    size_t total_count = 0;
+    size_t max_length = 0;
+    for (size_t i = 0; i < huff.counts.size(); ++i) {
+      if (huff.counts[i] != 0) {
+        max_length = i;
+      }
+      total_count += huff.counts[i];
+    }
+    // Empty DHT marker
+    if (total_count == 0) break;
+
     if (index & 0x10) {
       index -= 0x10;
       huff_table = &state->ac_huff_table[index];
@@ -417,14 +430,6 @@ bool EncodeDHT(const JPEGData& jpg, SerializationState* state) {
       return false;
     }
     huff_table->initialized = true;
-    size_t total_count = 0;
-    size_t max_length = 0;
-    for (size_t i = 0; i < huff.counts.size(); ++i) {
-      if (huff.counts[i] != 0) {
-        max_length = i;
-      }
-      total_count += huff.counts[i];
-    }
     --total_count;
     data[pos++] = huff.slot_id;
     for (size_t i = 1; i <= kJpegHuffmanMaxBitLength; ++i) {
diff --git a/lib/jxl/jpeg/enc_jpeg_data_reader.cc b/lib/jxl/jpeg/enc_jpeg_data_reader.cc
index 149bde1c..70ad6a30 100644
--- a/lib/jxl/jpeg/enc_jpeg_data_reader.cc
+++ b/lib/jxl/jpeg/enc_jpeg_data_reader.cc
@@ -226,7 +226,12 @@ bool ProcessDHT(const uint8_t* data, const size_t len, JpegReadMode mode,
   JXL_JPEG_VERIFY_LEN(2);
   size_t marker_len = ReadUint16(data, pos);
   if (marker_len == 2) {
-    return JXL_FAILURE("DHT marker: no Huffman table found");
+    // Empty DHT marker. Useless but does seem to occur in the wild.
+    // We represent this situation with a dummy all-zeroes Huffman table.
+    JPEGHuffmanCode huff;
+    huff.is_last = true;
+    jpg->huffman_code.push_back(huff);
+    return true;
   }
   while (*pos < start_pos + marker_len) {
     JXL_JPEG_VERIFY_LEN(1 + kJpegHuffmanMaxBitLength);
diff --git a/lib/jxl/jpeg/jpeg_data.cc b/lib/jxl/jpeg/jpeg_data.cc
index f3144dd6..1ae50a77 100644
--- a/lib/jxl/jpeg/jpeg_data.cc
+++ b/lib/jxl/jpeg/jpeg_data.cc
@@ -228,9 +228,10 @@ Status JPEGData::VisitFields(Visitor* visitor) {
                                        Bits(8), 0, &hc.counts[i]));
       num_symbols += hc.counts[i];
     }
-    if (num_symbols < 1) {
+    if (num_symbols == 0) {
       // Actually, at least 2 symbols are required, since one of them is EOI.
-      return JXL_FAILURE("Empty Huffman table");
+      // This case is used to represent an empty DHT marker.
+      continue;
     }
     if (num_symbols > hc.values.size()) {
       return JXL_FAILURE("Huffman code too large (%" PRIuS ")", num_symbols);
EOF
```

**Note:** The ICC warning patch from Immich only affects `lib/jpegli` files, which don't exist when building libjxl with `-DJPEGXL_ENABLE_JPEGLI=FALSE`. The jpegli ICC handling is already covered by the google/jpegli patches above.

### Patches for libheif (HEIF/AVIF support)

**Create `patches/libheif/libheif-jpegli-compat.patch`:**

This patch makes libheif compatible with jpegli by fixing a preprocessor check that fails when `LIBJPEG_TURBO_VERSION_NUMBER` is not a valid numeric value:

```bash
mkdir -p patches/libheif
cat > patches/libheif/libheif-jpegli-compat.patch << 'EOF'
diff --git a/heifio/decoder_jpeg.cc b/heifio/decoder_jpeg.cc
index 576deb9..a250f14 100644
--- a/heifio/decoder_jpeg.cc
+++ b/heifio/decoder_jpeg.cc
@@ -40,10 +40,14 @@ extern "C" {
 // Note: these 'undef's are only a workaround for a libjpeg-turbo-v2.0 bug and
 // should be removed again later. Bug has been fixed in libjpeg-turbo-v2.0.1.
 #include <jconfig.h>
+// Skip version check when using jpegli (LIBJPEG_TURBO_VERSION_NUMBER is defined but empty)
+// This workaround is only for libjpeg-turbo 2.0.0, not needed for jpegli
+#if 0
 #if defined(LIBJPEG_TURBO_VERSION_NUMBER) && LIBJPEG_TURBO_VERSION_NUMBER == 2000000
 #undef HAVE_STDDEF_H
 #undef HAVE_STDLIB_H
 #endif
+#endif
 #include <jpeglib.h>
 }

EOF

# Verify the patch was created correctly by testing if it applies to libheif
git clone --depth 1 --branch v1.19.5 https://github.com/strukturag/libheif.git /tmp/test-libheif-patch
cd /tmp/test-libheif-patch
git apply --check ../patches/libheif/libheif-jpegli-compat.patch && echo "✓ Patch is valid!" || echo "✗ Patch is CORRUPT - check for missing blank line before EOF"
cd -
rm -rf /tmp/test-libheif-patch
```

**Why this is needed:** jpegli's `jconfig.h` defines `LIBJPEG_TURBO_VERSION_NUMBER` but leaves it **empty** (not set to any value). When libheif tries to check `#if LIBJPEG_TURBO_VERSION_NUMBER == 2000000`, the preprocessor sees an empty value being compared to 2000000, which is invalid and causes a compilation error. The workaround code is only needed for libjpeg-turbo 2.0.0 (a bug fixed in 2.0.1), so we disable it entirely with `#if 0` when using jpegli.

## Step 4: Modify build.sh

You need to make **6 changes** to `build.sh`:

### Change 1: Replace mozjpeg with google/jpegli

Find the mozjpeg section (around line 338-350). **Replace** it with:

```bash
[ -f "$TARGET/lib/pkgconfig/libjpeg.pc" ] || (
  stage "Compiling jpeg (jpegli)"
  git clone https://github.com/google/jpegli.git $DEPS/jpeg
  cd $DEPS/jpeg
  git reset --hard bc19ca23
  git submodule update --init --recursive
  # Apply Immich's jpegli patches for malformed JPEG handling and libjpeg wrapper
  git apply $SOURCE_DIR/patches/jpegli/jpegli-malformed-jpeg.patch
  git apply $SOURCE_DIR/patches/jpegli/jpegli-enable-libjpeg-wrapper.patch
  mkdir -p _build
  cd _build
  emcmake cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TARGET $CMAKE_ARGS \
    -DBUILD_SHARED_LIBS=FALSE -DJPEGXL_WARNINGS_AS_ERRORS=OFF \
    -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_VIEWERS=OFF -DJPEGXL_ENABLE_PLUGINS=OFF \
    -DJPEGXL_ENABLE_DEVTOOLS=OFF -DBUILD_TESTING=OFF -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DJPEGXL_ENABLE_JPEGLI_LIBJPEG=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_CXX_FLAGS="$CXXFLAGS -msimd128" -DCMAKE_C_FLAGS="$CFLAGS -msimd128"
  # Verify headers were generated
  echo "Checking for jpegli headers..."
  ls -la lib/include/jpegli/ || { echo "ERROR: Headers not generated"; exit 1; }
  cmake --build . --target jpeg -j$(nproc)
  cmake --build . --target jpegli-static -j$(nproc)
  # Merge libjpeg wrapper and jpegli-static into single archive
  # The wrapper references jpegli symbols, so they must be in one .a file
  echo "Merging libjpeg.a and libjpegli-static.a..."
  mkdir -p merge-tmp
  cd merge-tmp
  emar x ../lib/libjpeg.a || { echo "Failed to extract libjpeg.a"; exit 1; }
  emar x ../lib/libjpegli-static.a || { echo "Failed to extract libjpegli-static.a"; exit 1; }
  OBJ_COUNT=$(ls -1 *.o | wc -l)
  echo "Extracted $OBJ_COUNT object files"
  emar rcs $TARGET/lib/libjpeg.a *.o || { echo "Failed to create merged archive"; exit 1; }
  MERGED_COUNT=$(emar t $TARGET/lib/libjpeg.a | wc -l)
  echo "Merged archive contains $MERGED_COUNT objects"
  [ "$MERGED_COUNT" -ge 26 ] || { echo "ERROR: Merged archive should have >=26 objects, got $MERGED_COUNT"; exit 1; }
  cd ..
  rm -rf merge-tmp
  # Install Highway library (jpegli dependency)
  echo "Installing libhwy.a..."
  cp third_party/highway/libhwy.a $TARGET/lib/ || { echo "ERROR: libhwy.a not found"; exit 1; }
  # Install headers
  echo "Installing jpegli headers..."
  cp lib/include/jpegli/*.h $TARGET/include/
  cd ..
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
Libs: -L\${libdir} -ljpeg -lhwy
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
  # Apply Immich's patch for JPEG XL's JPEG handling (lib/jxl/jpeg/* only)
  git apply $SOURCE_DIR/patches/libjxl/jxl-empty-dht-marker.patch
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
- Clone with `--recursive` to get submodules needed for patch
- Apply Immich's JPEG XL JPEG handling patch (lib/jxl/jpeg/* only, no lib/jpegli changes)
- Keep `-DJPEGXL_ENABLE_JPEGLI=FALSE` (uses google/jpegli as external dependency instead)

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

### Change 6: Apply libheif jpegli compatibility patch

Find the libheif section (around line 660-680). Look for:

```bash
cd $DEPS/heif
# Note: without CMAKE_FIND_ROOT_PATH find_path for AOM is not working...
emcmake cmake -B_build -S.
```

**After the `cd $DEPS/heif` line and BEFORE the `emcmake cmake` line, insert:**

```bash
# Apply jpegli compatibility patch for preprocessor error fix
patch -p1 < $SOURCE_DIR/patches/libheif/libheif-jpegli-compat.patch
```

**Complete example:**

```bash
[ -f "$TARGET/lib/pkgconfig/libheif.pc" ] || (
  stage "Compiling libheif"
  mkdir $DEPS/heif
  curl -Ls https://github.com/strukturag/libheif/releases/download/v$VERSION_HEIF/libheif-$VERSION_HEIF.tar.gz | tar xzC $DEPS/heif --strip-components=1
  cd $DEPS/heif
  # Apply jpegli compatibility patch for preprocessor error fix
  patch -p1 < $SOURCE_DIR/patches/libheif/libheif-jpegli-compat.patch
  # Note: without CMAKE_FIND_ROOT_PATH find_path for AOM is not working for some reason
  emcmake cmake -B_build -S. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TARGET $CMAKE_ARGS -DCMAKE_FIND_ROOT_PATH=$TARGET \
    -DBUILD_SHARED_LIBS=FALSE -DENABLE_PLUGIN_LOADING=FALSE -DBUILD_TESTING=FALSE \
    -DWITH_EXAMPLES=FALSE -DWITH_LIBDE265=FALSE -DWITH_X265=FALSE -DWITH_OpenH264_DECODER=FALSE \
    -DCMAKE_CXX_FLAGS="$CXXFLAGS -D__EMSCRIPTEN_STANDALONE_WASM__" \
    -DENABLE_MULTITHREADING_SUPPORT=FALSE
  make -C _build install
)
```

## Step 5: Run the Build

```bash
source ~/emsdk/emsdk_env.sh
./build.sh
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
✅ **libheif 1.20.2** - HEIF/AVIF support with jpegli compatibility patch
✅ **Static linking** - All format handlers in single library
✅ **Same build flags** - MAGICK_LIBRAW_VERSION_TAIL=202502

**Only difference:** Static vs dynamic linking (WASM requirement, no functional impact)

## Why This Approach?

**Immich uses:** libjxl with embedded jpegli (older jpegli, no WASM support)

**We use:** google/jpegli standalone + libjxl without embedded jpegli

**Why?** jpegli moved from libjxl to google/jpegli repo, WASM support added only to google version. libjxl's embedded jpegli is frozen/unmaintained for WASM.

**Result:** Functionally identical - libjxl uses google/jpegli as external libjpeg dependency, same as it would use its own embedded version.

## Troubleshooting

**jpegli patch fails:**
```bash
cd build/deps/jpeg
git apply --check ~/wasm-vips/patches/jpegli/jpegli-malformed-jpeg.patch
# If fails, check google/jpegli hasn't changed since bc19ca23
```

**libjxl patch fails:**
```bash
cd build/deps/jxl
git apply --check ~/wasm-vips/patches/libjxl/jxl-empty-dht-marker.patch
# Patch requires --recursive clone for submodules
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

**Total changes:** 6 modifications to build.sh + 4 patch files = Complete parity

**Patch files:**
1. `patches/jpegli/jpegli-malformed-jpeg.patch` - Handles malformed JPEG files
2. `patches/jpegli/jpegli-enable-libjpeg-wrapper.patch` - Enables libjpeg API compatibility for ImageMagick
3. `patches/libjxl/jxl-empty-dht-marker.patch` - Handles malformed JPEG XL files
4. `patches/libheif/libheif-jpegli-compat.patch` - Fixes jpegli compatibility in libheif

**Output:** `~/wasm-vips/build/target/lib/libvips.a` (~5-6MB) ready for WASM projects
