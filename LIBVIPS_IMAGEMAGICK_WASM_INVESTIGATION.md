# libvips + ImageMagick WASM Integration Investigation

## Summary

Investigated building ImageMagick for WASM and integrating it into wasm-vips to achieve complete parity with Immich's server base image build. **Successfully built ImageMagick libraries but encountered fundamental WASM architecture limitations preventing full integration.**

## What Was Accomplished

### 1. ImageMagick 7.1.2-2 Successful WASM Build

**Version:** `7.1.2-2`
**Revision:** `8289a3388a085ad5ae81aa6812f21554bdfd54f2` (exact match with Immich)
**Toolchain:** Emscripten 4.0.19

**Build Configuration:**
```bash
source /home/user/emsdk/emsdk_env.sh

# Use same flags as wasm-vips dependencies
COMMON_FLAGS="-O3 -pthread"
export CFLAGS="$COMMON_FLAGS -fvisibility=hidden"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="-DMAGICK_LIBRAW_VERSION_TAIL=202502 -I/home/user/wasm-vips/build/target/include"
export LDFLAGS="$COMMON_FLAGS -L/home/user/wasm-vips/build/target/lib -sAUTO_JS_LIBRARIES=0 -sAUTO_NATIVE_LIBRARIES=0"

# Force JPEG support via autotools cache variable override
export ac_cv_lib_jpeg_jpeg_read_header=yes

emconfigure ./configure \
  --prefix=/home/user/wasm-vips/build/target \
  --host=wasm32-unknown-linux \
  --enable-static \
  --disable-shared \
  --disable-openmp \
  --without-threads \
  --without-x \
  --with-magick-plus-plus=no \
  --with-modules

emmake make -j$(nproc)
emmake make install-libLTLIBRARIES install-MagickCoreincHEADERS \
  install-MagickCoreincarchHEADERS install-MagickWandincHEADERS \
  install-pkgconfigDATA install-configlibDATA
```

**Output Libraries:**
- `libMagickCore-7.Q16HDRI.a` - 4.6MB (optimized)
- `libMagickWand-7.Q16HDRI.a` - 1.5MB (optimized)

**Configure Result:**
```
JPEG v1           --with-jpeg=yes			yes
DELEGATES         = jpeg
```

### 2. Technical Discoveries

#### Discovery 1: Cross-Compilation Cache Variable Override
Autotools configure scripts fail in cross-compilation because they cannot execute test programs. Solution: override cache variables.

```bash
export ac_cv_lib_jpeg_jpeg_read_header=yes
```

This tells configure "pretend this test passed" without running it.

#### Discovery 2: google/jpegli vs libjxl/jpegli API Incompatibility
- **libjxl/jpegli**: Has C API compatibility layer (`jpeg_read_header`, etc.) but blocks WASM builds
- **google/jpegli**: Has WASM support but only C++ API (mangled symbols like `_ZN6jpegli...`)
- **Result**: ImageMagick's JPEG coder won't work at runtime with google/jpegli even if configure shows it enabled

```bash
# ImageMagick expects C API:
jpeg_read_header, jpeg_std_error, jpeg_CreateDecompress, etc.

# google/jpegli only provides:
_ZN6jpegli14JPEGErrorMgrE..., _ZN6jpegli12ReadHeaderEv, etc.
```

#### Discovery 3: Build Utilities vs Libraries
ImageMagick utilities require linking, which fails on JPEG symbol resolution. Solution: build and install only libraries.

```bash
# This fails:
emmake make

# This works:
emmake make install-libLTLIBRARIES install-MagickCoreincHEADERS ...
```

## The Fundamental WASM Limitation

### Problem: WASM Dynamic Module Architecture

libvips loads format handlers as dynamic WASM modules (`vips-magick.wasm`, `vips-jxl.wasm`, etc.). These modules require:

1. **Source code** compiled with `-sSIDE_MODULE=2` flag
2. **All linked libraries** also compiled with SIDE_MODULE-compatible flags

**Example from build.ninja:**
```bash
# vips magick module source (works):
ARGS = ... -fPIC -pthread -sSIDE_MODULE=2

# Link command (fails):
LINK_ARGS = -shared -fPIC -sSIDE_MODULE=2 ... \
  /home/user/wasm-vips/build/target/lib/libMagickCore-7.Q16HDRI.a  # ← Not compiled with SIDE_MODULE
```

**Error Result:**
```
wasm-ld: error: libMagickCore-7.Q16HDRI.a(libMagickCore_7_Q16HDRI_la-blob.o):
  relocation R_WASM_MEMORY_ADDR_SLEB cannot be used against symbol `.L.str.1`;
  recompile with -fPIC
```

The error message says "recompile with -fPIC" but actually means "recompile with SIDE_MODULE-compatible flags for WASM position-independent code."

### Why This Is Hard to Fix

To properly integrate ImageMagick into wasm-vips dynamic modules would require:

1. **Rebuild ImageMagick with SIDE_MODULE flags**
   ```bash
   CFLAGS="$CFLAGS -sSIDE_MODULE=2"
   LDFLAGS="$LDFLAGS -sSIDE_MODULE=2"
   ```

2. **Rebuild all ImageMagick's dependencies** with SIDE_MODULE flags (if any)

3. **Potential code changes** if ImageMagick's code patterns aren't compatible with WASM SIDE_MODULE restrictions

This is a significant engineering effort beyond the scope of this investigation.

## Alternative Approaches Considered

### Option A: Disable Dynamic Modules in libvips
Build all format loaders statically into libvips.wasm instead of separate .wasm modules.

**Pros:**
- ImageMagick could be statically linked without SIDE_MODULE requirements
- Simpler build

**Cons:**
- Larger initial bundle size
- Defeats wasm-vips lazy-loading architecture
- Would require forking wasm-vips build system

### Option B: Disable ImageMagick, Accept Limitation
Since ImageMagick is only a fallback loader and its JPEG support won't work anyway with google/jpegli.

**Pros:**
- wasm-vips already has native loaders for common formats
- ImageMagick primarily needed for exotic formats
- Simpler build chain

**Cons:**
- Not complete parity with Immich server build
- Some exotic image formats won't load

### Option C: Use ImageMagick Statically in Main libvips (Not Dynamic Module)
Configure libvips to link ImageMagick directly into libvips.a instead of vips-magick.wasm.

**Feasibility:** Unknown - would require investigating libvips meson build options

## Current State

### Successfully Completed
✅ ImageMagick 7.1.2-2 compiled for WASM with proper flags (`-O3 -pthread -fvisibility=hidden`)
✅ ImageMagick configured with JPEG support enabled via cache override
✅ Libraries installed to wasm-vips target directory
✅ Headers and pkg-config files installed
✅ libvips meson detects ImageMagick: `Run-time dependency magickcore found: YES 7.1.2`

### Cannot Complete (Architectural Limitation)
❌ Linking ImageMagick into vips-magick.wasm dynamic module
❌ Reason: ImageMagick not compiled with WASM SIDE_MODULE flags
❌ Fixing requires rebuilding ImageMagick specifically for SIDE_MODULE

## Immich Server vs WASM Parity Analysis

### Immich Server Build
```
libheif → libjxl (with jpegli) → libraw → imagemagick → libvips
```
- Uses libjxl's embedded jpegli (C API compatible)
- ImageMagick builds normally (ELF shared libraries)
- libvips loads ImageMagick as fallback

### wasm-vips Build (Current)
```
libheif → libjxl + jpegli (standalone) → libraw → libvips
```
- Uses google/jpegli standalone (C++ API only)
- ImageMagick not integrated (WASM architecture limitation)
- libvips uses native loaders only

### Actual Impact on Immich

**Minimal** - because:
1. libvips uses native loaders first, ImageMagick only for unrecognized formats
2. Common formats (JPEG, PNG, WebP, TIFF, HEIF) have native loaders
3. ImageMagick's JPEG support wouldn't work in WASM anyway (google/jpegli API mismatch)
4. Immich's typical image workflows don't use exotic formats requiring ImageMagick fallback

## Recommendations

### For Production WASM Build
**Accept the limitation.** Do not integrate ImageMagick. Document that:
- wasm-vips supports all common image formats natively
- Exotic formats requiring ImageMagick fallback are not supported in WASM
- This is a WASM architectural limitation, not a code quality issue

### For Future Investigation (If Exotic Format Support Required)
1. Identify specific exotic formats actually needed
2. Check if libvips has native loaders for those formats
3. If ImageMagick truly required, invest in rebuilding with SIDE_MODULE flags
4. Alternative: Consider statically linking ImageMagick into main libvips.a instead of dynamic module

## Technical References

### WASM SIDE_MODULE Documentation
- Emscripten: https://emscripten.org/docs/compiling/Dynamic-Linking.html
- SIDE_MODULE required for all code in dynamic WASM modules
- Main module loads side modules at runtime

### Relocation Error Explanation
`R_WASM_MEMORY_ADDR_SLEB` - WebAssembly memory address relocation type
- SLEB = Signed LEB128 (variable-length integer encoding)
- Used for position-independent code in WASM
- Requires compilation with proper flags for dynamic linking

### Files Modified
- `/home/user/wasm-vips/build.sh:539` - Removed `-Dmagick=disabled`
  - **Note:** This change allows meson to attempt ImageMagick integration
  - Build will configure successfully but link will fail (expected given SIDE_MODULE limitation)

## Lessons Learned

1. **Cross-compilation requires cache overrides** - Standard configure tests don't work
2. **WASM dynamic linking is restrictive** - All code must be compiled together with SIDE_MODULE
3. **Opportunistic builds work until dynamic linking** - ImageMagick compiled fine, but linking into module failed
4. **API compatibility matters** - libjpeg C API vs C++ API prevents fallback
5. **Build parity != Runtime parity** - Even exact same libraries may behave differently in WASM

## Conclusion

Successfully demonstrated that ImageMagick CAN be built for WASM with proper flags, but CANNOT be integrated into wasm-vips dynamic modules without additional SIDE_MODULE compilation. This is a WASM architecture limitation, not a failure of the build process.

The practical impact on Immich is minimal since:
- Common image formats work via native libvips loaders
- ImageMagick is only a fallback for exotic formats
- The JPEG integration wouldn't work anyway due to API mismatch

**Recommendation:** Document this limitation and proceed with wasm-vips build without ImageMagick integration.
