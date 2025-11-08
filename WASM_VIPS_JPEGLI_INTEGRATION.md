# wasm-vips + jpegli Integration

Integrated Google's standalone jpegli (not libjxl embedded) into wasm-vips with Immich's malformed JPEG handling patches.

## What Was Done

**Replaced mozjpeg with jpegli:**
- Repository: `google/jpegli` commit `bc19ca23`
- Built as libjpeg.a for API/ABI compatibility
- WASM SIMD support (`-msimd128`)
- 309KB static library

**Applied Immich patches:**
1. `jpegli-empty-dht.patch` - Handle JPEGs with empty DHT markers
2. `jpegli-icc-warning.patch` - Downgrade ICC profile errors to warnings

## Build Integration

Modified `/home/user/wasm-vips/build.sh`:
- Clone google/jpegli with submodules (for libjpeg-turbo headers)
- Apply patches before build
- Install as libjpeg.a with pkg-config

**Key Build Flags:**
```bash
emcmake cmake -DBUILD_SHARED_LIBS=FALSE \
  -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_VIEWERS=OFF \
  -DCMAKE_CXX_FLAGS="$CXXFLAGS -msimd128"
cmake --build _build --target jpegli-static
```

## Verification

✅ jpegli library built (309KB)
✅ Headers installed (jpeglib.h, jerror.h from libjpeg-turbo)
✅ libvips compiled JPEG modules successfully
✅ Both Immich patches applied and functional

## References

- google/jpegli: https://github.com/google/jpegli
- Immich patches: server/sources/libjxl-patches/
- Adapted for standalone jpegli at: wasm-vips/patches/jpegli/
